# 45 — Release automation and semantic versioning [read-only example for the publish step]

> **Verification.** This chapter is a **concept chapter** with a runnable build
> half and a **`[read-only example]`** publish half. The build half is the
> real workflow `.github/workflows/55-tag-driven-release.yml`, which was run
> and logged in `docs/_logs/ch55.log`. The publish step (creating a GitHub
> Release and attaching assets) needs a real tag push and write permissions
> that `act` cannot reproduce, so it is marked `[read-only example]`. The
> free alternative is in section 7: tag, build, and create a local release
> directory without any network. `python3 scripts/validate-workflows.py`
> reports `55-tag-driven-release.yml` as valid YAML with 2 jobs.

---

## 1. Simple explanation (like I'm 7)

You bake a cake, taste it, and it is good. Now you need to put it in a box,
write the recipe version on the lid ("v1.2.3"), and put it on the shelf so
people can find it later. If you bake a better cake next week, that one gets
a new lid ("v1.3.0") and the old one stays on the shelf, because someone
might want the old recipe.

**Release automation** is the machine that writes the lid and puts the box
on the shelf for you, every time you push a tag. **Semantic versioning** is
the rule for what number goes on the lid, so that everyone knows whether the
new cake is a tiny fix, a new flavour, or a completely different cake.

This chapter's *build* half is runnable and verified. The *publish* half (the
actual GitHub Release) is marked `[read-only example]`, because it needs a
real tag push and write permissions. The free alternative is in section 7.

## 2. Real name

### Semantic versioning (SemVer)

A version number of the form `MAJOR.MINOR.PATCH`, with these meanings:

- **MAJOR**: a change that breaks existing users. They must change their code
  to use the new version.
- **MINOR**: a new feature that is backwards compatible. Users can upgrade
  without changing anything.
- **PATCH**: a bug fix. No new features, no breakage.

Pre-release and build metadata are appended with a hyphen or a plus:
`1.2.3-rc.1`, `1.2.3+build.42`. The comparison rules are in the SemVer
spec; the short version is that pre-releases sort before the release.

### Conventional Commits

A commit-message format that makes the version bump computable:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Types that drive versioning:

- `fix:` -> PATCH bump.
- `feat:` -> MINOR bump.
- `feat!:` or a `BREAKING CHANGE:` footer -> MAJOR bump.
- `docs:`, `chore:`, `refactor:`, `test:`, `ci:` -> no bump (but still
  recorded in the changelog).

A commit like `feat(api): add slugify endpoint` is both human-readable and
machine-parseable. That parseability is what makes the version bump
automatic.

### Changelog

A file (usually `CHANGELOG.md`) listing what changed in each version, grouped
by type. Generated from commit messages so it is never out of date. The
standard format is "Keep a Changelog".

### GitHub Release

A named, tagged snapshot of a repository at a commit, with attached assets
(the built files). Created from a Git tag. It is the "box on the shelf": a
stable, addressable thing people can download.

### Tag-driven release

A workflow triggered by a tag push (`on: push: tags: ['v*.*.*']`) that
builds, tests, and creates a GitHub Release from that tag. The tag is the
trigger and the version number at once.

### Automated version bump

A tool (such as `semantic-release`, `release-please`, or `standard-version`)
that reads commits since the last tag, computes the next version, creates the
tag, and generates the changelog, all without a human choosing the number.

## 3. Workflow example

The build half is `.github/workflows/55-tag-driven-release.yml` (the same
file referenced by chapter 55). It builds and creates the release:

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

The publish half (the `gh release create` call) is the `[read-only example]`
part: it needs a real tag push and a token with `contents: write`, neither of
which `act` can provide. The build half is runnable and is what produced
`docs/_logs/ch55.log`.

## 4. What I should see

**In the Actions tab**, after pushing a tag `v1.0.0`, one run of
`Tag-driven release` with two jobs:

```
Tag-driven release
├─ ✓ Build
└─ ✓ Create the GitHub Release
```

**Real log output**, from `docs/_logs/ch55.log` (the build half):

```
[Tag-driven release/Build]   | > cicd-learn@1.0.0 build
[Tag-driven release/Build]   | > node build.mjs
[Tag-driven release/Build]   | 
[Tag-driven release/Build]   | built dist/app.js (2887 bytes)
```

And from the publish half (read-only, shown as it would appear on GitHub):

```
[Tag-driven release/Create the GitHub Release]   | tag: v1.0.0
[Tag-driven release/Create the GitHub Release]   | creating a release for v1.0.0
[Tag-driven release/Create the GitHub Release]   | release created; the built files are attached to it
[Tag-driven release/Create the GitHub Release]   | -rw-r--r-- 1 runner runner 525 ... dist/app.js
```

Two things to notice:

1. The trigger is the tag, not a branch push. The workflow only runs when a
   tag matching `v*.*.*` is pushed. A normal commit to `main` does nothing.
2. The release job has `permissions: contents: write` at job level, overriding
   the workflow's `contents: read`. That is least privilege in practice: only
   the job that creates the release can write, and only for that job's
   duration.

## 5. When to use it and when NOT to

**Reach for release automation when:**

- You publish a library or a tool and consumers depend on version numbers.
- You want a changelog that is never stale, because it is generated from
  commits.
- You want releases to be reproducible: the same tag always produces the
  same artifact.
- You have more than one contributor and want to remove the "who cuts the
  release" bottleneck.

**Do NOT reach for it when:**

- You deploy continuously and never ship a versioned artifact. A deploy
  pipeline (chapter 27) is enough; a release is overhead.
- Your commit messages are not conventional. The automation will produce
  nonsense version bumps and an unreadable changelog. Fix the commit culture
  first (section 7).
- You need a human to approve what goes in a release. Automation removes
  that gate. Use a manual `workflow_dispatch` with an input for the version
  instead, or keep a release branch.
- The publish step needs credentials you cannot give to CI. Then keep the
  build automated and the publish manual.

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
  linter (`commitlint`). Without enforcement, `fix:` and `fixed:` both happen
  and the bump is wrong.

### The automated bump, in one picture

A tool such as `release-please` or `semantic-release` does this on every push
to `main`:

1. Read commits since the last tag.
2. Parse each commit's type (`feat`, `fix`, `BREAKING CHANGE`).
3. Compute the next version (PATCH / MINOR / MAJOR).
4. Open a pull request titled `chore(main): release 1.2.0` that updates
   `CHANGELOG.md` and `package.json`.
5. When that PR is merged, create the tag `v1.2.0` and the GitHub Release,
   attaching the built artifacts.

The human's job is to write good commit messages. The machine's job is
everything else. That is the deal, and it only works if the commit messages
are honest.

### Enforcing Conventional Commits

Without enforcement, `fix:` and `fixed:` and `bugfix:` all happen. Add a
commit-msg hook or a CI check:

```bash
# .github/workflows/commitlint.yml (illustrative)
npx --no -- commitlint --edit "$1"
```

with a `commitlint.config.js` extending `@commitlint/config-conventional`. This
is the same idea as linting code: catch the mistake at commit time, not at
release time.

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

**Break it on purpose:** tag a commit that has not passed CI (skip the
`npm test` step above) and assemble the release anyway. The artifact ships
with a failing test. That is exactly the failure mode "tagging a commit that
never passed CI" produces, and it is why the release workflow re-runs CI.

## 8. Next

You can ship a versioned release. Chapter 46 is about the day after: when the
release turns out to be broken and you need to go back.

→ [46 — Rollbacks](46-rollbacks.md)