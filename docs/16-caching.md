# 16 — Caching dependencies

> **Verification.** The workflow in this chapter is
> `.github/workflows/16-caching.yml`. The manual-cache job was executed with
> `./scripts/verify.sh .github/workflows/16-caching.yml "manual" push ch16-manual`,
> and the full log is at `docs/_logs/ch16-manual.log`. The warm-cache evidence
> comes from `docs/_logs/ch12-lint.log` (a run of `12-lint-step.yml`, which uses
> `actions/setup-node` with `cache: 'npm'`). The cold-cache comparison comes from
> `docs/_logs/ch09-actions.log`. Every log excerpt in section 4 is quoted from
> those files. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/16-caching.yml (2 job(s))`.
>
> **What this local execution cannot prove.** `act` does reproduce a working cache
> (you can see `Cache restored successfully` and `Cache saved successfully` in
> the logs), so the mechanism, the keys, and the hit/miss output are real and
> measured here. What it cannot prove is GitHub's hosted cache service behaviour
> that matters in production: the 10 GB per-repository cache limit, the 7-day
> eviction of unused caches, the cache scoping rules (a pull request from a fork
> cannot write to the default branch's cache), and the exact cache hit rate you
> will see on a busy repository. Those are documented in the GitHub Actions cache
> reference and cannot be exercised from a laptop. The *keys and the output* are
> real; the *quota and eviction* are not.

---

## 1. Simple explanation (like I'm 7)

Imagine you are baking a cake every single day. The recipe is the same, and the
ingredients are the same, but every morning you drive to the shop, buy flour,
sugar, eggs, butter and vanilla, drive home, and only then start mixing.

That is a CI run without a cache. The shop is the internet, the ingredients are
your npm packages, and the drive is `npm ci` downloading 127 packages from the
registry every single time. It works. It is also silly, because nothing changed
since yesterday.

A **cache** is the pantry. The first time you bake, you buy everything and put
the spare bags in the pantry. The next morning you check the pantry before going
to the shop: if everything you need is already there, you bake immediately. If
the recipe changed (a new ingredient), you go to the shop for just that one
thing and refill the pantry.

Two things matter about this pantry, and they are the whole chapter:

- The pantry is **labelled**. You do not rummage; you look for a label like
  `node-cache-Linux-x64-npm-<hash of the lock file>`. If the label matches, you
  use it. If it does not, you go shopping.
- The pantry is **per recipe**. A cake recipe and a bread recipe do not share
  flour, even though the flour is the same brand. A Node 20 cache and a Node 22
  cache are different labels, and so are a Linux cache and a Windows cache.

The point is not "make it faster". The point is "stop paying for work you
already did, and make the payment visible in the log so you can prove it".

## 2. Real name

### Cache

Named, reusable storage that survives between workflow runs. A cache is written
by one run and read by a later run, possibly on a different machine. It is
keyed by a string you choose, and the key is what decides whether a later run
reuses it or starts fresh.

### Cache key

The string that names a cache entry. It is computed from things that, if they
change, mean the cached contents would be wrong: the operating system, the
architecture, the package manager, and a hash of the lock file. The canonical
shape in this course is:

```
node-cache-Linux-x64-npm-6aabe04fd4b2161267891150af82ba292cb51d2ee06dbd26ffcafaa2da9cc66c
```

Read it left to right: `node-cache` (what it is), `Linux` (runner OS),
`x64` (architecture), `npm` (package manager), then a 64-character hash of
`package-lock.json`. Change the lock file and the hash changes and the key
changes, so a dependency change can never accidentally reuse a cache built for
different dependencies. That is the design, and it is the reason a cache is
safe where a hand-rolled `node_modules` tarball is not.

### Cache hit / cache miss

- **Hit**: a previous run stored something under this key, and it was restored.
  The step that restores reports `cache-hit=true`.
- **Miss**: nothing matched. The step reports `cache-hit` as an **empty string**,
  not the word `false`. This distinction is the single most common bug in
  cache-aware scripts and is covered in section 6.

There is also a **partial hit** (a `restore-keys` prefix matched but the exact
key did not). This course does not use `restore-keys`, so you will not see one
here; it is mentioned so the log line `Cache restored from key:` does not
surprise you.

### `actions/setup-node` with `cache: 'npm'`

The easy path. This action does three things at once:

1. Installs Node at the requested version.
2. Computes the cache key from the lock file.
3. Restores and saves the **npm download cache** (`~/.npm`), not `node_modules`.

Paired with `npm ci`, which installs from the lock file into a clean
`node_modules`, this is the recommended combination. The download cache makes
`npm ci` fast; `npm ci` makes the install reproducible. Caching `node_modules`
directly would be faster still and is a bad idea: it breaks across Node
versions, OS images, and native modules, and it silently ships stale build
artifacts. Cache downloads, not installed trees.

### `cache-dependency-path`

Required when the lock file is not at the repository root. `actions/setup-node`
looks for `package-lock.json` at the repo root by default; if your app lives in
a subdirectory (as `cicd-learn` does here), you must tell it where:

```yaml
cache-dependency-path: cicd-learn/package-lock.json
```

Without it the step fails with
`::error::Dependencies lock file is not found in <repo>` and the job is red
before it installs anything. This is the trap in section 6.

### `actions/cache`

The general-purpose version, for ecosystems that `setup-node` does not know
about, or for caching things other than dependencies (build outputs, tool
chains, downloaded binaries). You supply two things:

- `path`: what to store.
- `key`: the name to store it under, which must change when the contents would
  differ.

It also exposes `cache-hit` and `cache-key` as step outputs, so you can branch
on a hit or miss in later steps.

### Cache versus artifact

Both are "save something for later", and they are deliberately different
(chapter 02 and chapter 20):

| | Cache | Artifact |
| - | - | - |
| Purpose | Skip re-downloading or re-computing | Pass a build output between jobs or to a human |
| Identity | Keyed by content hash | Named per run |
| Mutability | Overwritten on the same key | Immutable in v4+ (one name, one write per run) |
| Lifetime | 7 days unused, then evicted | Retention days you set (default 90) |
| Read by | Any run with the same key | The run that produced it, or a downstream job |

If you are passing `dist/app.js` to a deploy job, that is an artifact. If you
are avoiding re-downloading 21 MB of npm tarballs, that is a cache.

## 3. Workflow example

This is the complete `.github/workflows/16-caching.yml` from this repository.

```yaml
name: Caching

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── The simple path: setup-node's built-in npm cache ──────────────────────
  # `cache: 'npm'` caches the npm *download* cache (~/.npm), NOT node_modules.
  # Paired with `npm ci`, the lock file is hashed into the cache key, so a
  # dependency change means a new key and therefore a fresh install.
  with-cache:
    name: Install with cache
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          # Required when the lock file is not at the repo root. Without it:
          #   ::error::Dependencies lock file is not found in <repo>
          cache-dependency-path: cicd-learn/package-lock.json

      - name: Show what the cache key is made of
        run: |
          echo "npm cache dir: $(npm config get cache)"
          echo "lock file    : $(wc -c < package-lock.json) bytes"
          # The key is OS + arch + package manager + hash of the lock file.
          # Change the lock file, change the key, lose the cache. That is the
          # design: it is impossible to restore a cache built for other
          # dependencies.

      - name: Install (first run populates the cache, later runs restore it)
        run: npm ci

      - name: Time it
        run: |
          echo "install finished; see the step timing in the Actions tab"

  # ── What the cache does NOT do ────────────────────────────────────────────
  # Caching node_modules directly is a common and unwise idea: it breaks when the
  # OS, Node version or libc differs, and it silently ships stale build artifacts
  # and native modules. npm's own download cache is content-addressed, so it is
  # safe. Cache downloads, not installed trees.

  # ── The manual version, for other ecosystems ──────────────────────────────
  manual:
    name: Manual cache with actions/cache
    runs-on: ubuntu-24.04
    timeout-minutes: 10
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

      # actions/cache is the general-purpose version. You supply two things:
      #   path    what to store
      #   key     the name it is stored under, which must change when the
      #           contents would differ
      #
      # Here we cache the build output, keyed on the lock file, so a rebuild
      # triggered only by a source change can skip work that did not change.
      - name: Restore the esbuild cache
        id: esbuild-cache
        uses: actions/cache@v6
        with:
          path: |
            cicd-learn/node_modules/.cache/esbuild
            cicd-learn/.build-cache
          # `${{ runner.os }}` and `${{ hashFiles(...) }}` are both expressions.
          # hashFiles is the important one: it is what makes the key content-based
          # instead of time-based.
          key: esbuild-${{ runner.os }}-${{ hashFiles('cicd-learn/package-lock.json') }}

      # A cache-hit is a boolean output, so you can branch on it.
      - name: Report the hit or miss
        run: |
          echo "cache hit: ${{ steps.esbuild-cache.outputs.cache-hit }}"
          echo "cache key: ${{ steps.esbuild-cache.outputs.cache-key }}"
          if [ "${{ steps.esbuild-cache.outputs.cache-hit }}" = "true" ]; then
            echo "restored from a previous run"
          else
            echo "cold cache; this run will populate it"
          fi

      - run: npm ci
      - name: Build, warming the cache
        run: |
          mkdir -p .build-cache
          npm run build
          # Stand-in for a real expensive build step's intermediate output.
          cp dist/app.js .build-cache/
          du -sh .build-cache
```

Two structural things to notice:

- **`cache-dependency-path` is set on both jobs**, even though only one of them
  needs it for `npm ci` to find the lock file. `setup-node` runs before any
  `defaults.run.working-directory` matters, so the path is always repo-relative.
- **The manual cache uses `hashFiles(...)` in the key.** That is the same
  content-based idea as `setup-node`'s built-in key, applied to whatever you are
  caching. A key without `hashFiles` is a time bomb: it never changes, so it
  keeps restoring stale content forever.

## 4. What I should see

### The hit, from a real run

`docs/_logs/ch12-lint.log` is a run of `12-lint-step.yml`, which uses
`actions/setup-node` with `cache: 'npm'`. The cache was already warm from an
earlier run, so this is what a **hit** looks like:

```
[Lint step/Lint]   ⚙  ::set-output:: cache-hit=true
[Lint step/Lint]   ⚙  ::set-output:: cache-matched-key=node-cache-linux-x64-npm-6aabe04fd4b2161267891150af82ba292cb51d2ee06dbd26ffcafaa2da9cc66c
```

And the install that follows it, on a warm cache:

```
[Lint step/Lint]   | added 127 packages, and audited 128 packages in 1s
```

One second. The download cache restored all 127 packages' tarballs locally, so
`npm ci` only had to extract them.

### The miss, from a real run

`docs/_logs/ch16-manual.log` is a run of the `manual` job in this chapter's
workflow. The esbuild cache had never been saved before, so it is a **miss**:

```
[Caching/Manual cache with actions/cache]   | Cache not found for input keys: esbuild-Linux-6aabe04fd4b2161267891150af82ba292cb51d2ee06dbd26ffcafaa2da9cc66c
[Caching/Manual cache with actions/cache]   ✅  Success - Main Restore the esbuild cache [738.38635ms]
```

Note two things. First, a miss is **not an error**: the step is green. The cache
action treats "nothing found" as a normal outcome, because its job is to
*attempt* a restore, not to guarantee one. Second, the report step prints what
the miss looks like in your own code:

```
[Caching/Manual cache with actions/cache]   | cache hit: 
[Caching/Manual cache with actions/cache]   | cache key: 
[Caching/Manual cache with actions/cache]   | cold cache; this run will populate it
```

**`cache hit:` is followed by nothing.** Not `false`. Not `0`. An empty
string. If your script does `if [ "$CACHE_HIT" = "false" ]`, it will take the
wrong branch on every miss. Section 6.

Then the same run saves the cache at the end, so the *next* run hits:

```
[Caching/Manual cache with actions/cache]   | Cache saved with key: esbuild-Linux-6aabe04fd4b2161267891150af82ba292cb51d2ee06dbd26ffcafaa2da9cc66c
```

### The cold versus warm comparison

Same project, same `npm ci`, measured here:

| Run | `npm ci` line in the log | Time |
| --- | --- | --- |
| Cold (no cache) — `docs/_logs/ch09-actions.log` | `added 127 packages, and audited 128 packages in 3s` | 3s |
| Warm (cache hit) — `docs/_logs/ch12-lint.log` | `added 127 packages, and audited 128 packages in 1s` | 1s |

Three seconds down to one. On a larger project the ratio is usually worse, not
better, because the download dominates. On this project the cache is worth
about two seconds per job, and with four jobs in parallel that is eight seconds
of runner time you stop paying for.

Also visible in the manual run: `setup-node` itself found the Node binary in
its own cache:

```
[Caching/Manual cache with actions/cache]   | Found in cache @ /opt/hostedtoolcache/node/22.23.3/x64
```

That is a separate cache from the npm one — `setup-node` caches the Node
installation too, so the first run after a version change is the slow one.

### Reading the hit in the `with-cache` job

That job does not print a hit line, because it never asks for one. Its evidence
is indirect and shows up in the setup-node step:

```
::set-output:: cache-hit=true
```

when warm, and the absence of that line (or `cache-hit=` empty) when cold. If
you want the hit to be visible in your own logs, copy the pattern from the
`manual` job: read `steps.<id>.outputs.cache-hit` and `echo` it.

## 5. When to use it and when NOT to

**Use caching when:**

- **You run `npm ci` more than once a day.** Which is every project with CI.
  The return is immediate and the risk is low, because the key is content-based.
- **Your install is slow.** A two-second install is not worth a cache entry you
  have to reason about; a two-minute install is. Measure first.
- **You have a genuinely expensive build step** (TypeScript compile, codegen,
  native module build) whose inputs are a hash of the source. `actions/cache`
  with a key built from `hashFiles('src/**/*.ts')` is the right tool there,
  not a dependency cache.
- **You want CI to be cheaper.** Cache hits cost fewer runner minutes, and
  public repositories get the cache for free.

**Do NOT reach for caching when:**

- **You cache `node_modules` directly.** It is the most common caching mistake
  and it fails in three distinct ways: a Node version change leaves stale
  native modules that crash at runtime; a lock file change leaves packages that
  `npm ci` would have removed; and a cache built on one OS is restored on
  another and breaks. Cache the download cache, not the tree.
- **You cache without a content-based key.** A key like `npm-cache` that never
  changes restores yesterday's dependencies forever, including the ones you
  removed. Always include `hashFiles(...)` of the lock file.
- **You cache secrets or build outputs that must be fresh.** A cache is
  "probably the same"; an artifact is "exactly this run". Do not cache a
  signed bundle or a coverage report you intend to publish.
- **You add `restore-keys` to paper over misses.** A partial hit restores an
  older cache and `npm ci` then has to reconcile it, which is slower than a
  clean miss. Fix the key instead.

## 6. Common mistakes

- **Testing `cache-hit` against the string `"false"`.** On a miss the output is
  an empty string, not `false`. Symptom: a script that prints "restored from a
  previous run" on every cold run, or one that skips warming the cache because
  it thinks a restore happened. Fix: test against `"true"` for a hit, or test
  `-n` (non-empty) for "anything was restored". The manual job in this chapter
  does it the safe way:
  `if [ "${{ steps.esbuild-cache.outputs.cache-hit }}" = "true" ]`.
- **Forgetting `cache-dependency-path` with a subdirectory app.** Symptom:
  `::error::Dependencies lock file is not found in <repo>`, red job, no
  install. Fix: add `cache-dependency-path: cicd-learn/package-lock.json`.
  This is the reason the path is quoted in the workflow with a comment.
- **Mixing up `cache: 'npm'` and caching `node_modules`.** `cache: 'npm'`
  caches `~/.npm`, the download cache. If you also add an `actions/cache` step
  pointing at `node_modules`, you are caching the same data twice under
  different keys, and one of them will be stale. Pick one.
- **A key with no OS or architecture.** `key: npm-${{ hashFiles('...') }}`
  collides across runner images and restores a Linux cache onto a Windows
  runner (or vice versa), which breaks native modules. Always start the key with
  `${{ runner.os }}-${{ runner.arch }}` or use `setup-node`'s built-in key.
- **Expecting a cache to be shared across branches.** GitHub scopes caches by
  branch: a cache written on a feature branch is readable by that branch and by
  the default branch, but not by other feature branches. Symptom: "it's cached
  on main but my PR re-downloads everything". That is by design, to prevent a
  PR from poisoning main's cache. It is not a bug.
- **Expecting a cache to be shared across forks.** A pull request from a fork
  cannot write to the base repository's cache. It can read the base's cache if
  the key matches, but it cannot populate a new one. Symptom: every PR from a
  fork is cold. There is no fix; it is a security boundary.
- **Caching on every job.** Each job that calls `setup-node` with `cache: 'npm'`
  restores and saves its own cache. With four parallel jobs you get four
  identical 21 MB saves. That is wasteful but not wrong; if it matters, cache
  in one job and pass the restored directory as an artifact, which is a
  different and more complex pattern.
- **Assuming a saved cache is permanent.** Unused caches are evicted after
  7 days, and the repository total is capped at 10 GB (least-recently-used
  first). Symptom: a cache that worked last month is cold this month. Not a
  bug; the design. Re-running the workflow repopulates it.

## 7. Try it yourself

**Exercise: prove the hit and the miss, and break a cache key on purpose.**

1. Run the real workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/16-caching.yml manual push ch16-manual
   ```

   Read the log. Find `Cache not found for input keys:` — that is your miss —
   and `Cache saved with key:` at the end — that is the pantry being filled.

2. Run it again:

   ```bash
   ./scripts/verify.sh .github/workflows/16-caching.yml manual push ch16-manual-2
   ```

   This time find `Cache restored successfully` and
   `Cache restored from key:`. The miss became a hit because the key matched
   and the cache had been saved. Compare the `npm ci` timing if you want to
   see the payoff, though on this project it is small.

3. **Prove the empty-string behaviour.** Open the `Report the hit or miss` step
   and change the test to the wrong one:

   ```bash
   if [ "${{ steps.esbuild-cache.outputs.cache-hit }}" = "false" ]; then
     echo "this branch is taken on every miss, which is the bug"
   fi
   ```

   Run it cold. The "this branch" line does not print, because the value was
   empty, not `false`. Now you have seen the bug rather than read about it.

4. **Break the key.** Remove `hashFiles(...)` from the manual cache key so it
   becomes `esbuild-${{ runner.os }}`. Run twice. The second run hits, but now
   change a dependency in `package-lock.json` (add a space, anything) and run
   again. It still hits, because the key no longer tracks the lock file. That
   is the failure mode: a stale cache restored for dependencies it was not
   built for. Revert the lock file and the key.

5. **Break `cache-dependency-path`.** Delete that line from the `with-cache`
   job and run it. The step fails with
   `::error::Dependencies lock file is not found in <repo>` before `npm ci`
   runs. Put it back.

**Hint:** the cache that `act` uses lives on your machine (under
`~/.cache/act`), so "cold" and "warm" here are real states you can inspect
and delete. On GitHub the same states exist but are scoped per branch and per
repository, and you cannot `rm` them from a terminal.

**What this exercise proves:** the miss/hit cycle, that a miss is green, that
`cache-hit` is empty on a miss, that a content-based key is what makes the
cache safe, and that `cache-dependency-path` is mandatory for subdirectory
apps. **What it cannot prove:** GitHub's 10 GB limit, 7-day eviction, branch
and fork scoping, or the cache hit rate on a repository with many concurrent
pushes. Those need a hosted run.

## 8. Next

You can make one job fast by reusing yesterday's downloads. The next question
is how to run the same job against several versions of Node at once, instead
of picking one.

→ [17 — Matrix builds](17-matrix-builds.md)