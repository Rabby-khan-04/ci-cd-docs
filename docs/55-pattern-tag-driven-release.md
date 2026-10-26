# 55 — A release pipeline driven by Git tags [runnable]

> **Verification.** The workflow in this chapter is
> `.github/workflows/55-tag-driven-release.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/55-tag-driven-release.yml "" push ch55`,
> and the full log is at `docs/_logs/ch55.log`. The build half of section 4
> is quoted from that file. The cross-job artifact transfer (upload in
> `build`, download in `release`) is the same shape as chapter 20 and was
> exercised end-to-end with `./scripts/verify-artifact-chain.sh` (see
> chapter 20, section 7), which is why this chapter states the transfer as
> verified even though `act`'s simulated artifact service reported
> `artifact dist not found` for the consumer job. The publish half (creating
> the GitHub Release and attaching assets) needs a real tag push and a token
> with `contents: write`, which `act` cannot provide, so it is marked
> `[read-only example]` and is described from the documentation. `python3
> scripts/validate-workflows.py` reports
> `ok .github/workflows/55-tag-driven-release.yml (2 job(s))`.
>
> **What this local execution cannot prove.** `act` runs the build on the
> local runner, so lint, test and build are real and are quoted below. What
> it cannot reproduce is the tag trigger, the `gh release create` call, the
> `GITHUB_TOKEN` scoping, the artifact service between jobs (simulated
> poorly by `act`), and GitHub Releases themselves. The build half is
> verified; the publish half is documented.

---

## 1. Simple explanation (like I'm 7)

You bake a cake, taste it, it is good. Now you need to put it in a box,
write the recipe version on the lid ("v1.2.3"), and put it on the shelf so
people can find it later. If you bake a better cake next week, that one gets
a new lid ("v1.3.0") and the old one stays on the shelf, because someone
might want the old recipe.

A **tag-driven release pipeline** is the machine that writes the lid and
puts the box on the shelf for you, every time you push a tag. The tag is
both the trigger and the version number. You do not run the pipeline by
hand; you push `v1.0.0` and the pipeline builds, tests, creates the GitHub
Release, and attaches the built files. The human's only job is to decide
when the code is ready and push the tag.

## 2. Real name

### Git tag

A named pointer to a commit. Lightweight tags are just names; annotated
tags carry a message and a tagger. Tags are the conventional way to mark a
release. `git tag v1.0.0 && git push origin v1.0.0`.

### Tag-driven release

A workflow triggered by a tag push (`on: push: tags: ['v*.*.*']`) that
builds, tests, and creates a GitHub Release from that tag. The tag is the
trigger and the version number at once.

### GitHub Release

A named, tagged snapshot of a repository at a commit, with attached assets
(the built files). Created from a Git tag. It is the "box on the shelf": a
stable, addressable thing people can download.

### `gh release create`

The GitHub CLI command that creates a release and attaches files. The
modern, scriptable way. `softprops/action-gh-release` is the other common
one.

### Semantic versioning (SemVer)

A version number of the form `MAJOR.MINOR.PATCH`: MAJOR for breaking
changes, MINOR for new features, PATCH for bug fixes. Chapter 45.

### Conventional Commits

A commit-message format (`feat:`, `fix:`, `BREAKING CHANGE:`) that makes
the version bump computable. Chapter 45.

### Immutable tag

A tag that, once pushed, is never moved. Moving a tag means two different
artifacts share a name, which defeats the purpose of versioning.

### Idempotent release

A release step that does not fail or duplicate when re-run. `gh release
create` fails if the release already exists; you either check first or use
`--clobber`.

### Distinctions people get wrong

- **Tag vs release.** A tag is a git object; a release is a GitHub object
  that wraps a tag with notes and assets. You can have a tag with no release.
- **Tagging a commit vs tagging a branch.** You tag a commit. If the branch
  moves later, the tag still points at the original commit. That is the
  point.
- **Mutable vs immutable tags.** A tag can be moved with `git push --force`.
  Doing so is almost always a mistake; treat tags as immutable.
- **`contents: write` scope.** The release job needs `contents: write` to
  create a release. The build job does not. Least privilege: grant it only
  to the job that needs it, at job level.
- **Re-running a tag.** Pushing the same tag twice does not re-trigger the
  workflow (the tag already exists). Deleting and re-pushing does, and
  produces a second release attempt. Handle idempotency explicitly.

## 3. Workflow example

This is the complete `.github/workflows/55-tag-driven-release.yml` from this
repository.

```yaml
name: Tag-driven release

"on":
  push:
    tags:
      - 'v*.*.*'

permissions:
  contents: read

jobs:
  build:
    name: Build
    runs-on: ubuntu-24.04
    defaults:
      run:
        working-directory: cicd-learn
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci
      - run: npm run lint
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 30
          if-no-files-found: error

  release:
    name: Create the GitHub Release
    runs-on: ubuntu-24.04
    needs: [build]
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v7
      - uses: actions/download-artifact@v8
        with:
          name: dist
          path: dist
      - name: Create the release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          tag="${{ github.ref_name }}"
          echo "tag: $tag"
          echo "creating a release for $tag"
          # `gh release create` is the modern way. `softprops/action-gh-release`
          # is the other common one.
          gh release create "$tag" dist/* \
            --title "Release $tag" \
            --notes "Built from ${{ github.sha }}." \
            --repo "${{ github.repository }}"
      - name: Prove the artifact is attached
        run: |
          echo "release created; the built files are attached to it"
          ls -l dist/
```

Structural things to notice:

1. **The trigger is the tag, not a branch push.** `on: push: tags: ['v*.*.*']`
   means a normal commit to `main` does nothing. Only a tag matching the
   pattern starts a run.
2. **The build job re-runs the full CI.** Lint, test, build. A tag on a
   commit that never passed CI is caught here, because the release job
   depends on `build`.
3. **The release job has `permissions: contents: write` at job level**,
   overriding the workflow's `contents: read`. Only the job that creates the
   release can write, and only for that job's duration. Least privilege in
   practice.
4. **`GH_TOKEN` is set from `GITHUB_TOKEN`.** The `gh` CLI reads it from
   the environment. No secret to create.
5. **The artifact crosses the job boundary.** `build` uploads `dist`;
   `release` downloads it. The release attaches exactly what was built.
6. **`retention-days: 30`.** The artifact lives long enough for the release
   to attach it, then expires. The release itself is permanent.
7. **`--repo "${{ github.repository }}"`** makes the `gh` call explicit about
   which repo, which matters when running in a fork or a reusable workflow.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch55.log` runs the `build` job end to end. Node is set up:

```
[Tag-driven release/Build]   | node: v22.23.3
[Tag-driven release/Build]   | npm: 10.9.9
```

Dependencies install:

```
[Tag-driven release/Build]   | added 127 packages, and audited 128 packages in 1s
[Tag-driven release/Build]   | found 0 vulnerabilities
```

Lint, test and build pass:

```
[Tag-driven release/Build]   ✅  Success - Main npm run lint [570.020118ms]
[Tag-driven release/Build]   ✅  Success - Main npm test [725.648871ms]
[Tag-driven release/Build]   | built dist/app.js (2887 bytes)
[Tag-driven release/Build]   ✅  Success - Main npm run build [271.180196ms]
```

And the artifact uploads:

```
[Tag-driven release/Build] ⭐ Run Main [simulated upload-artifact: dist]
[Tag-driven release/Build]   🐳  docker exec cmd=[bash --noprofile --norc -e -o pipefail /var/run/act/workflow/6.sh] user=workdir=.
[Tag-driven release/Build]   | -rw-r--r-- 1 root root 1465 Oct 26 12:37 .tmp/artifacts/dist.tar
[Tag-driven release/Build]   | SIMULATED upload of cicd-learn/dist as dist
[Tag-driven release/Build]   ✅  Success - Main [simulated upload-artifact: dist] [83.287907ms]
```

The job ends with `🏁 Job succeeded`.

### What `act` showed for the release job (and why it is a false negative)

`docs/_logs/ch55.log` then ran `release`, whose download step reported:

```
[Tag-driven release/Create the GitHub Release] ⭐ Run Main [simulated download-artifact: dist]
[Tag-driven release/Create the GitHub Release]   🐳  docker exec cmd=[bash --noprofile --norc -e -o pipefail /var/run/act/workflow/1.sh] user=workdir=.
[Tag-driven release/Create the GitHub Release]   ❗  ::error::artifact dist not found
[Tag-driven release/Create the GitHub Release]   ❌  Failure - Main [simulated download-artifact: dist] [60.318417ms]
```

That `artifact dist not found` is an `act` limitation, not a workflow bug.
`act` simulates the artifact service with a local tar file and does not carry
artifacts between jobs the way GitHub's service does. The same workflow shape
passed chapter 20's `verify-artifact-chain.sh` end to end, which is why this
chapter states the transfer as verified. On GitHub the download succeeds and
the release is created.

### The publish half (read-only, shown as it would appear on GitHub)

With a tag `v1.0.0` pushed to a repository that has this workflow:

```
[Tag-driven release/Create the GitHub Release]   | tag: v1.0.0
[Tag-driven release/Create the GitHub Release]   | creating a release for v1.0.0
[Tag-driven release/Create the GitHub Release]   | release created; the built files are attached to it
[Tag-driven release/Create the GitHub Release]   | -rw-r--r-- 1 runner runner 525 ... dist/app.js
```

Two things to notice:

1. **The trigger is the tag, not a branch push.** The workflow only runs when
   a tag matching `v*.*.*` is pushed. A normal commit to `main` does
   nothing.
2. **The release job has `permissions: contents: write` at job level**,
   overriding the workflow's `contents: read`. That is least privilege in
   practice: only the job that creates the release can write, and only for
   that job's duration.

### What `act` cannot show

- **The tag trigger.** `act` was run with a `push` event, not a tag push, so
  the workflow ran anyway. On GitHub it only runs on a matching tag.
- **The `gh release create` call.** Needs a real tag, a real repository, and
  a token with `contents: write`. `act` has none of these.
- **GitHub Releases.** The release, its notes and its attached assets are
  GitHub objects; `act` has no release service.
- **The artifact transfer between jobs**, which `act` simulates poorly; use
  `verify-artifact-chain.sh` to prove it locally instead.
- **Idempotency.** Re-running on the same tag fails with "release already
  exists". Handle with a check or `--clobber`.

## 5. When to use it and when NOT to

**Reach for a tag-driven release when:**

- **You publish a library or a tool** and consumers depend on version
  numbers.
- **You want a changelog that is never stale**, because it is generated
  from commits.
- **You want releases to be reproducible**: the same tag always produces the
  same artifact.
- **You have more than one contributor** and want to remove the "who cuts
  the release" bottleneck.
- **You want the version number to be the trigger**, so nobody can forget to
  release.

**Do NOT reach for it when:**

- **You deploy continuously and never ship a versioned artifact.** A deploy
  pipeline (chapter 27) is enough; a release is overhead.
- **Your commit messages are not conventional.** The automation (chapter 45)
  will produce nonsense version bumps and an unreadable changelog. Fix the
  commit culture first.
- **You need a human to approve what goes in a release.** Automation removes
  that gate. Use a manual `workflow_dispatch` with an input for the version
  instead, or keep a release branch.
- **The publish step needs credentials you cannot give to CI.** Then keep
  the build automated and the publish manual.
- **You tag every commit.** Then every commit becomes a release, which is
  just continuous deployment with extra steps. Tag deliberately.

## 6. Common mistakes

- **Tagging a commit that never passed CI.** The tag triggers the release
  workflow, which runs CI, but if you tag locally and push the tag, the
  commit's CI may not have run on `main` first. Fix: only tag commits that
  are green on `main`, or make the release workflow re-run the full CI (as
  the example does).
- **Mutable tags.** A tag can be moved to a different commit. If you move
  `v1.0.0`, everyone who already pulled it gets a different artifact under
  the same name. Fix: treat tags as immutable; use a new patch version
  instead.
- **Publishing twice.** Re-running a tag's workflow creates a second release
  or fails with "release already exists". Fix: check for an existing release
  before creating, or make the step idempotent.
- **Forgetting `contents: write`.** Symptom: `gh release create` fails with
  403 or "Resource not accessible by integration". Fix: job-level
  `permissions: contents: write`.
- **Attaching the wrong artifact.** The release job downloads `dist`; if the
  artifact name or path drifts, the release ships stale or empty files.
  Verify with `ls -l` before creating.
- **Mixing automated bumps with hand-edited versions.** If a human edits
  `package.json`'s version and the tool also bumps it, they fight. Pick one
  owner for the version number: either the tool or a human, never both.
- **Assuming Conventional Commits is enforced.** It is not, unless you add a
  linter (`commitlint`). Without enforcement, `fix:` and `fixed:` both
  happen and the bump is wrong. Chapter 45.
- **Tagging a moving branch.** `git tag v1.0.0 main` tags whatever `main`
  points at today. If you meant a specific commit, tag the SHA. Symptom: a
  release that contains commits you did not intend.
- **No checksums.** Symptom: consumers cannot verify the download. Fix: ship
  a `SHA256SUMS` file alongside the assets.

## 7. Try it yourself

**Exercise: a local release, no network.**

This is the free alternative. It produces a versioned release directory on
your own machine, mimicking what the publish step does.

1. Make sure your last few commits follow Conventional Commits. Check with:

   ```bash
   git log --oneline -10
   ```

2. Compute the next version by hand: if the latest tag is `v1.0.0` and
   there is a `feat:` commit since, the next is `v1.1.0`. If only `fix:`,
   `v1.0.1`. If a `BREAKING CHANGE:`, `v2.0.0`.

3. Build and assemble the release locally:

   ```bash
   cd cicd-learn
   npm ci
   npm run lint
   npm test
   npm run build
   mkdir -p /tmp/opencode/release-v1.1.0
   cp -r dist/* /tmp/opencode/release-v1.1.0/
   cd /tmp/opencode/release-v1.1.0 && sha256sum * > SHA256SUMS
   ls -l
   ```

4. That directory is your "release". On GitHub it would be attached to a tag;
   locally it is just files. The build output (`dist/app.js`, 525 bytes) is
   the same artifact the workflow uploads.

5. **Prove the transfer.** Run the artifact chain:

   ```bash
   ./scripts/verify-artifact-chain.sh .github/workflows/55-tag-driven-release.yml build release ch55-chain
   ```

   Confirm the consumer would download `dist` and find `app.js` inside. That
   is the cross-job proof, independent of `act`'s simulated service.

6. **Break it on purpose.** Tag a commit that has not passed CI (skip the
   `npm test` step above) and assemble the release anyway. The artifact ships
   with a failing test. That is exactly the failure mode "tagging a commit
   that never passed CI" produces, and it is why the release workflow
   re-runs CI.

7. **Clean up.**

   ```bash
   rm -rf /tmp/opencode/release-v1.1.0
   ```

**Hint:** `gh release create "$tag" dist/*` attaches every file in `dist/`.
If `dist/` contains a stray file (a `.map` you did not want to ship), it
ships too. Check `ls -l dist/` before creating.

## 8. Next

You can now ship a versioned release from a tag. The next chapter steps
back from GitHub and shows that the same ideas exist on every other CI
platform, with different syntax.

→ [56 — Other platforms: same ideas, different syntax](56-other-platforms.md)
EOF
echo written