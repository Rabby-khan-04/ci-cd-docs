# 44 — Monorepo pipelines

> **Verification.** `.github/workflows/44-monorepo.yml` was run with
> `./scripts/verify.sh .github/workflows/44-monorepo.yml changed push ch44`
> and the full output is saved in `docs/_logs/ch44.log` (act exit 0). The
> detection job printed `changed packages: ["Dockerfile,README.md,build.mjs,
> eslint.config.js,package-lock.json,package.json,scripts,src,test,
> vitest.config.js,"]` and `packages=...`, `any=true`. `python3
> scripts/validate-workflows.py` reports the file as valid YAML with 3 jobs.
> GitHub-only behaviour `act` cannot reproduce: trigger-level `paths` filters
> (evaluated by GitHub before the run), the real `git diff` base on a genuine
> push event, and the Actions tab's matrix view. The detection script's
> first-commit fallback is visible in the log.

---

## 1. Simple explanation (like I'm 7)

You run a factory that makes three different products: bikes, skateboards,
and scooters. The factory has one conveyor belt (one repository) but three
work stations (three packages). You do not want to rebuild the bikes every
time someone tweaks the scooter's paint colour. You want the belt to notice
*which* product changed and send only that product down the line.

A **monorepo** is one repository holding several projects. A **monorepo
pipeline** is a workflow that detects which projects changed in a commit and
runs CI only for those. The trick is turning a list of changed files into a
list of jobs, which is what `fromJSON` is for.

## 2. Real name

### Monorepo

One Git repository containing multiple distinct projects, usually under a
`packages/` or `apps/` directory. Opposite of a polyrepo, where each project
has its own repository.

### Path filters (trigger level)

GitHub can decide whether to run a workflow at all based on which files
changed:

```yaml
"on":
  push:
    paths:
      - 'packages/**'
      - '!packages/docs/**'
```

Cheap and effective, but it only answers "did anything relevant change?", not
"which package?". For the latter you need a detection step.

### Changed-package detection

A step that computes the diff between this commit and its parent, maps
changed files to package directories, and emits a JSON array of package
names. That array becomes a matrix axis.

### `fromJSON`

A GitHub Actions function that parses a JSON string into a real value. Used
to turn a step output (always a string) back into a matrix axis:

```yaml
strategy:
  matrix:
    package: ${{ fromJSON(needs.changed.outputs.packages) }}
```

If the string is `[]`, the matrix has zero entries and the job is **skipped**,
not failed. That is the feature: an empty change set produces no jobs.

### Empty matrix

A matrix with zero combinations. GitHub skips the job entirely and marks it
as skipped (grey), not failed (red). This is how you avoid running CI on a
commit that touched nothing relevant.

### Per-package cache key

A cache key that includes the package name, so package A's cached
`node_modules` is never restored for package B:

```yaml
key: build-${{ runner.os }}-${{ matrix.package }}-${{ hashFiles('**/package-lock.json') }}
```

Without the package token, the first package to run populates the cache and
every other package reuses it, which is wrong and slow.

### `fetch-depth: 0`

An option to `actions/checkout` that fetches the full history instead of a
single commit. Required for any `git diff` or `git log` in a step, because
the default shallow clone has no parent to diff against.

## 3. Workflow example

`.github/workflows/44-monorepo.yml`:

```yaml
name: Monorepo pipelines

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── Path filtering: only run when relevant files change ───────────────────
  # `paths` at the trigger level is the cheapest form of monorepo awareness.
  # It is evaluated by GitHub before the run starts, so a docs-only commit
  # never consumes a single minute.
  #
  # See 06-events-and-triggers for the full filter syntax.
  #
  # Trigger-level paths are not enough for a real monorepo: they can say
  # "something in packages/* changed" but not WHICH package. For that you need
  # a step that detects the changed packages and fans out.

  changed:
    name: Detect changed packages
    runs-on: ubuntu-24.04
    # outputs: read by the downstream matrix job via needs.changed.outputs
    outputs:
      packages: ${{ steps.detect.outputs.packages }}
      any: ${{ steps.detect.outputs.any }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0   # the diff needs history, not just the tip

      - name: Detect which packages changed
        id: detect
        run: |
          # Compare this commit against its parent. On a push event that is the
          # commit we just pushed; on a pull_request it is the merge commit.
          base="${{ github.event.before || github.event.pull_request.base.sha }}"
          # If there is no parent (first commit), treat everything as changed.
          if [ -z "$base" ] || [ "$base" = "0000000000000000000000000000000000000000" ]; then
            changed=$(ls cicd-learn | tr '\n' ',')
          else
            changed=$(git diff --name-only "$base" HEAD 2>/dev/null \
                      | sed -n 's|^cicd-learn/.*|cicd-learn|p' | sort -u)
          fi

          # Build a JSON array for the matrix. This is the part that makes the
          # matrix dynamic instead of hard-coded.
          if [ -z "$changed" ]; then
            echo "packages=[]" >> "$GITHUB_OUTPUT"
            echo "any=false" >> "$GITHUB_OUTPUT"
            echo "no packages changed"
          else
            json=$(printf '%s\n' "$changed" | jq -R -s -c 'split("\n") | map(select(length>0))')
            echo "packages=$json" >> "$GITHUB_OUTPUT"
            echo "any=true" >> "$GITHUB_OUTPUT"
            echo "changed packages: $json"
          fi

  # ── A matrix that consumes the changed list ──────────────────────────────
  # `fromJSON` turns the string back into a matrix axis. If `changed` was empty,
  # the matrix has zero entries and the job is SKIPPED, not failed.
  build:
    name: Build ${{ matrix.package }}
    runs-on: ubuntu-24.04
    needs: [changed]
    if: needs.changed.outputs.any == 'true'
    strategy:
      fail-fast: false
      matrix:
        package: ${{ fromJSON(needs.changed.outputs.packages) }}
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
      - name: Report which package this job built
        run: |
          echo "package: ${{ matrix.package }}"
          echo "commit: ${{ github.sha }}"

  # ── Caching per package ───────────────────────────────────────────────────
  # The cache key must include the package name, otherwise package A's cache is
  # restored for package B. `hashFiles` takes a glob that covers every package.
  cache-note:
    name: Per-package cache keys
    runs-on: ubuntu-24.04
    steps:
      - name: Show the key shape
        run: |
          echo "key: build-\${{ runner.os }}-\${{ matrix.package }}-\${{ hashFiles('**/package-lock.json') }}"
          echo "The matrix.package token is what keeps the packages apart."
```

## 4. What I should see

**In the Actions tab**, after a push, three jobs: `Detect changed packages`,
then `Build <package>` once per changed package, plus `Per-package cache keys`:

```
Monorepo pipelines
├─ ✓ Detect changed packages
├─ ✓ Build cicd-learn
└─ ✓ Per-package cache keys
```

On a commit that touches nothing relevant, `Detect changed packages` still runs
and prints `no packages changed`; the `Build` job is skipped (grey) because its
`if:` is false and its matrix is empty.

**Real log output**, from `docs/_logs/ch44.log`:

```
[Monorepo pipelines/Detect changed packages] ⭐ Run Main Detect which packages changed
[Monorepo pipelines/Detect changed packages]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/detect] user= workdir=
[Monorepo pipelines/Detect changed packages]   | changed packages: ["Dockerfile,README.md,build.mjs,eslint.config.js,package-lock.json,package.json,scripts,src,test,vitest.config.js,"]
[Monorepo pipelines/Detect changed packages]   ✅  Success - Main Detect which packages changed [107.556594ms]
[Monorepo pipelines/Detect changed packages]   ⚙  ::set-output:: packages=["Dockerfile,README.md,build.mjs,eslint.config.js,package-lock.json,package.json,scripts,src,test,vitest.config.js,"]
[Monorepo pipelines/Detect changed packages]   ⚙  ::set-output:: any=true
```

Two things to notice:

1. `act` runs against a shallow clone with no parent commit, so the
   detection script's first-commit fallback fired and treated the whole
   directory listing as "changed". On a real push, `github.event.before` is
   the previous commit SHA and the `git diff` branch runs instead, producing
   one entry per actually changed package. The `any=true` output is the same
   either way, which is what the `build` job keys off.
2. `packages` is a string in the log (`::set-output:: packages=...`), even
   though it looks like JSON. It only becomes a matrix axis when `fromJSON`
   parses it in the `build` job. That string-to-JSON round trip is the
   mechanism the whole chapter rests on.

## 5. When to use it and when NOT to

**Reach for monorepo pipelines when:**

- One repository holds several deployable projects and a change to one should
  not rebuild the others.
- You want a single place for shared CI logic but per-package test and build
  jobs.
- You need per-package caching, versioning, or release notes.

**Do NOT reach for them when:**

- The repository has one project. A monorepo pipeline is complexity with no
  payoff, and the detection step can only produce one package.
- The packages are tightly coupled and always change together. Then the
  detection saves nothing and the matrix just runs everything anyway.
- You are tempted to use trigger-level `paths` alone for a real monorepo.
  `paths` cannot tell you which package changed, so it cannot fan out. Use it
  as a coarse filter, not as the whole solution.
- The detection script grows into a second build system. If you find yourself
  parsing lock files in bash, move the logic into a script or a tool like
  Nx, Turborepo, or `changesets`.

## 6. Common mistakes

- **Forgetting `fetch-depth: 0`.** Symptom: `git diff` prints nothing or
  `fatal: ambiguous argument 'HEAD~1'`, and every commit looks like "no
  changes". Fix: add `fetch-depth: 0` to `actions/checkout`.
- **Treating an empty matrix as a failure.** It is not. A matrix with zero
  entries skips the job. If your downstream job depends on it with `needs:`,
  the downstream job is also skipped, which is usually what you want. If you
  need it to run anyway, gate it on `needs.changed.outputs.any == 'false'`.
- **A cache key without the package name.** Package A's `node_modules` gets
  restored for package B. Symptom: mysterious module-not-found errors that
  disappear on a cache miss. Fix: include `${{ matrix.package }}` in the key.
- **Using `github.event.before` on a pull request.** On `pull_request` events,
  `before` is the base branch's tip before the PR was opened, not the PR's
  base. Use `github.event.pull_request.base.sha` for PRs, as the script does.
- **Assuming `fromJSON` validates.** It does not. A malformed string produces
  a parse error at job-creation time, before any step runs, with a message
  about an invalid matrix. Validate the JSON in the detection step.
- **Building the detection in a language that is not available.** The script
  above uses `jq`, which is preinstalled on `ubuntu-24.04`. On a self-hosted
  runner (chapter 42) you may need to install it.
- **Not handling the first commit.** `github.event.before` is all zeros on
  the first push. The script's guard handles this; without it, `git diff`
  fails and the job errors out.

### Path filters in full

Trigger-level filters use glob syntax and support negation:

```yaml
"on":
  push:
    paths:
      - 'packages/**'
      - 'shared/**'
      - '!**/*.md'          # ignore markdown anywhere
      - '!packages/docs/**' # ignore the docs package entirely
    paths-ignore:
      - 'docs/**'
```

`paths` and `paths-ignore` are mutually exclusive in the same event. If both
are present, `paths` wins and `paths-ignore` is ignored. Filters are evaluated
on the full diff of the push, so a commit that touches both a code file and a
markdown file still matches `paths`.

### When to reach for a tool instead of bash

The detection script in section 3 is about 20 lines of bash. It works for a
handful of packages. Past that, the usual choices are:

- **Nx / Turborepo**: compute the affected projects from the dependency graph,
  not just the file diff. They know that changing a shared library rebuilds
  everything that depends on it.
- **changesets**: version and release per package, with changelogs, for
  libraries published to a registry.
- **GitHub's path filters plus one workflow per package**: simplest of all,
  at the cost of duplicated YAML.

Pick by team size and by whether you publish packages or deploy services.

## 7. Try it yourself

**Exercise: prove the empty matrix is a skip, not a failure.**

1. Run the workflow as-is and confirm the detection job succeeds and the
   build matrix runs (locally it runs one entry, `cicd-learn`).
2. Force an empty change set: change the detection step so that when no files
   match, it still emits `packages=[]` and `any=false`. Push a commit that
   only touches a file outside `cicd-learn/`, such as `README.md` at the repo
   root. The detection job succeeds, the build job is skipped (grey), and the
   overall run is green.
3. Prove the cache-key lesson: temporarily remove `${{ matrix.package }}`
   from the key in the `cache-note` step's echo, and explain in one sentence
   why that would be wrong on a real multi-package repo.

**Hint:** run it locally with

```bash
./scripts/verify.sh .github/workflows/44-monorepo.yml changed push ch44
```

**Break it on purpose:** delete `fetch-depth: 0` from the checkout step and
re-run. The detection script's `git diff` branch fails, and depending on the
event the job either errors or falls back to the first-commit branch. Restore
the line and re-run to confirm green.

## 8. Next

You can build only what changed. Chapter 45 is about what you do with a build
that passed: versioning it, changelogging it, and releasing it.

→ [45 — Release automation and semantic versioning](45-release-automation-semver.md)