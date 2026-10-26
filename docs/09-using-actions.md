# 09 — Using actions

> **Verification.** The workflow in this chapter is
> `.github/workflows/09-using-actions.yml`, run three times with `act` 0.2.89:
>
> - `scripts/verify.sh .github/workflows/09-using-actions.yml actions push ch09-actions`
>   → `docs/_logs/ch09-actions.log` (exit 0)
> - the `anatomy` job as committed → `docs/_logs/ch09-anatomy.log` (**exit 1** —
>   a real bug in that job, quoted and explained in section 4)
> - the `anatomy` job with the paths corrected → `docs/_logs/ch09-anatomy-fixed.log`
>   (exit 0)
>
> The `setup-node@v7` behaviour quoted in section 4 was also read directly from
> the action's own source, cached locally at
> `~/.cache/act/actions-setup-node@v7/src/cache-restore.ts`, and is quoted from
> there. Nothing about it is inferred.
>
> What local execution cannot prove: what the Actions tab shows for an action
> step, the real contents of GitHub's Actions cache service, whether a cache
> restore from a *previous run* works (this run had a cold cache — see the log),
> minutes accounting, and Marketplace discovery. Every quoted line in section 4
> is from one of the three logs above or from the action source.

---

## 1. Simple explanation (like I'm 7)

You can write every command your pipeline needs yourself. Nobody makes you do
anything else. But some commands are painful enough that thousands of people
have already written them, checked them, and are happy to lend them to you.

`actions/checkout` is the borrowed "get the code" step. `actions/setup-node` is
the borrowed "install Node version 22, and remember where the downloads were"
step. Using one is like using a branded tool instead of the homemade wrench: it
is already tested, and it does one job well.

Two rules come with the borrowing:

1. **You must name which one and which version.** `actions/checkout@v7`. The
   version is not optional. A versionless name, or a moving one like `@main`,
   means your pipeline runs different code tomorrow and nobody can tell you what
   changed.
2. **Some borrowed tools need to be told things.** `setup-node` needs to know
   *which* Node version, and *where your lock file is*. Get that second one wrong
   and the step refuses to run, because it cannot work out what to cache. That is
   section 4's headline finding, and it is the mistake everyone makes once.

A third, quieter rule: a borrowed tool cannot read your mind. If you give it a
setting whose name is spelled slightly differently, it does not complain. It
ignores you. So the tools you use come with a list of the settings they accept —
you look up the name, you do not invent it.

## 2. Real name

### The three kinds of action

| Kind | What it is | Where its code lives |
| ---- | ---------- | -------------------- |
| **JavaScript** | A `Dockerfile`-less program run by Node on the runner | `action.yml`, `index.js`, package files |
| **Docker container** | An image built or pulled, run as a container | `action.yml`, `Dockerfile` |
| **Composite** | A YAML list of steps, packaged under one name | `action.yml` with `runs.using: composite` |

All three are declared by an `action.yml` (or `action.yaml`) at the root of a
repository or subdirectory. That manifest is the contract: it declares `name`,
`description`, `inputs` (each with `description`, `required`, `default`) and
`runs`. Section 4 prints a real one.

### How a reference works

```yaml
- uses: actions/checkout@v7                          # a published repo, major version
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1   # pinned by SHA
- uses: ./.github/actions/setup-node                 # a local action in THIS repo
```

The version part is called a **ref**. The rules:

- **Always pin it.** `@v7` is the right level for this course. `@main` and bare
  `@checkout` are both rejected by this repository's own validator:

  ```
  FAIL e-moving.yml.jobs.a.steps[0]: `uses: actions/checkout@main` pins to a
    moving ref
  ```

  (Real output from `scripts/validate-workflows.py`, quoted in chapter 05.)
- **SHA pinning is stricter** and is what you should use in a repository you care
  about, because a major-version tag is mutable: `actions/checkout@v7` can be
  re-pointed by the action's owner. Chapter 39 covers the full argument and the
  attack. Every action used in this course has its SHA recorded in
  `docs/00-roadmap.md`.
- **Local actions** (`./path`) are files in your own repository. Chapter 41.

### Inputs: `with:`

`with:` maps to the `inputs:` block of the action's manifest. Two facts that
matter more than they look:

- **A misspelled key is silently ignored.** There is no error. The action runs
  with its default. So `node-version-file` instead of `nodeVersionFile` gives you
  a step that "succeeded" and did the wrong thing. This is why you read the
  action's README rather than guessing keys.
- **Inputs are strings.** Even `node-version: 22` is received as text. Quote it
  anyway (`'22'`) so YAML cannot reinterpret it — unquoted `22` is an integer,
  and `20.10` unquoted becomes `20.1`. Chapter 05.

### `actions/checkout`, the two inputs that matter

- `fetch-depth` — `1` (the default) clones a single commit. `0` clones the full
  history. Full history costs time and is required only when you run `git log`,
  `git describe`, or generate a changelog from commits.
- `path` — where in the workspace to put the repository. Leave it unset and the
  repo lands at the workspace root, which is what makes
  `defaults.run.working-directory: cicd-learn` work. Set it for a monorepo
  (chapter 44).

`submodules: false` and `clean: true` are the defaults and are shown in the
workflow only because they are the settings most often changed for no reason.

### `actions/setup-node` and the lock file

`setup-node` does two things: install the Node version you asked for, and — if
you pass `cache:` — set up caching for a package manager.

The caching half has a hard requirement, and it is the chapter's main finding.
From the action's own source, `src/cache-restore.ts`:

```ts
const lockFilePath = cacheDependencyPath
  ? cacheDependencyPath
  : findLockFile(packageManagerInfo);
const fileHash = await glob.hashFiles(lockFilePath);

if (!fileHash) {
  throw new Error(
    'Some specified paths were not resolved, unable to cache dependencies.'
  );
}

const keyPrefix = `node-cache-${platform}-${arch}-${packageManager}`;
const primaryKey = `${keyPrefix}-${fileHash}`;
```

and `findLockFile`:

```ts
const findLockFile = (packageManager: PackageManagerInfo) => {
  const lockFiles = packageManager.lockFilePatterns;
  const workspace = process.env.GITHUB_WORKSPACE!;

  const rootContent = fs.readdirSync(workspace);

  const lockFile = lockFiles.find(item => rootContent.includes(item));
  if (!lockFile) {
    throw new Error(
      `Dependencies lock file is not found in ${workspace}. Supported file patterns: ${lockFiles.toString()}`
    );
  }

  return path.join(workspace, lockFile);
};
```

Three conclusions, all from the source and not from guesswork:

1. **The lock file is looked for in `$GITHUB_WORKSPACE` only** — the repository
   root, one directory level, via `readdirSync(workspace)`. It is not a
   recursive search.
2. **The lock file's hash is the cache key.** So a dependency change produces a
   different key, which is a cache miss, which is a fresh download. That is why
   this pairing is correct with `npm ci`: correctness comes from `npm ci`
   (chapter 11), speed comes from the cache.
3. **What is cached is the package manager's cache directory, not
   `node_modules`.** For npm the action asks npm itself:
   `npm config get cache` (`src/cache-utils.ts`, the `npm` entry of
   `supportedPackageManagers`). Our run shows the answer: `/root/.npm`.

## 3. Workflow example

This is the real file, `.github/workflows/09-using-actions.yml`:

```yaml
name: Using actions

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

defaults:
  run:
    working-directory: cicd-learn

jobs:
  # ── setup-node with an explicit version and the npm cache ─────────────────
  # The single most valuable action in a Node pipeline. It does two things:
  # installs the exact Node version your project declares, and caches the npm
  # download cache. Chapter 16 covers the caching in detail.
  actions:
    name: checkout and setup-node
    runs-on: ubuntu-24.04
    steps:
      # `path` is not set, so the repo lands in the workspace root and
      # working-directory: cicd-learn still applies to run: steps.
      - name: Check out the repository
        uses: actions/checkout@v7
        with:
          # 1 is the default and correct when you only need current files.
          # Set 0 for a full history, which matters for changelog generation
          # and for `git describe`.
          fetch-depth: 1
          # Skip downloading the submodules. Left true by default; shown because
          # it is the setting most often changed for no reason.
          submodules: false
          # Clean the workspace of any leftovers. True is the default and is
          # what keeps a self-hosted runner from carrying state between runs.
          clean: true

      # The important one. `node-version` is not guessed from package.json; you
      # state it. `node-version-file` reads .nvmrc instead, which is a better
      # single source of truth once you have one.
      - name: Set up Node.js
        uses: actions/setup-node@v7
        with:
          node-version: '22'
          # Caches the npm *download* cache (~/.npm), not node_modules. This is
          # the correct pairing with `npm ci`: the lock file is the cache key, so
          # a changed dependency means a changed key and therefore a fresh
          # restore.
          cache: 'npm'
          # REQUIRED here. With `cache: npm`, setup-node hashes a lock file to
          # build the cache key, and it looks for it at the *repository root*.
          # Our lock file is cicd-learn/package-lock.json, so without this line
          # the step fails with:
          #   ::error::Dependencies lock file is not found in <repo>.
          # This is not an act quirk: it fails the same way on GitHub.
          cache-dependency-path: cicd-learn/package-lock.json
          # Do not let a stray .npmrc in the repo redirect the registry.
          registry-url: 'https://registry.npmjs.org'

      - name: Prove the versions
        run: |
          echo "node : $(node --version)"
          echo "npm  : $(npm --version)"
          echo "cache dir: $(npm config get cache)"

      # `npm ci` needs the lock file, which is why checkout must come first.
      - name: Install exactly what the lock file pins
        run: npm ci

      - name: Run the real checks with the pinned Node
        run: |
          npm run lint
          npm test
          npm run build

  # ── What an action actually is ─────────────────────────────────────────────
  # A JavaScript action is a directory with an action.yml. This job reads one,
  # to show the anatomy without needing the Marketplace.
  anatomy:
    name: Anatomy of an action
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: Show that an action is just files
        run: |
          echo "--- a JavaScript action looks like this ---"
          find .github/actions -type f | sort
          echo
          echo "--- action.yml is the manifest ---"
          cat .github/actions/setup-node/action.yml
          echo
          echo "--- and its implementation ---"
          sed -n '1,20p' .github/actions/setup-node/run.sh
```

The `anatomy` job has a real bug in it. Section 4 shows the failure and the
one-character-class fix; leaving it in place is deliberate, because it is the
`working-directory` trap from chapter 08 appearing in a new disguise.

## 4. What I should see

### `setup-node` doing its two jobs (`docs/_logs/ch09-actions.log`)

```
[Using actions/checkout and setup-node]   ☁  git clone 'https://github.com/actions/setup-node' # ref=v7
⭐ Run Main Check out the repository
✅  Success - Main Check out the repository [43.125777ms]
⭐ Run Main Set up Node.js
  | Found in cache @ /opt/hostedtoolcache/node/22.23.3/x64
  ❓  ::group::Environment details
  | node: v22.23.3
  | npm: 10.9.9
  | yarn: 1.22.22
  ❓  ::endgroup::
  | [command]/opt/hostedtoolcache/node/22.23.3/x64/bin/npm config get cache
  | /root/.npm
  | npm cache is not found
✅  Success - Main Set up Node.js [1.110368113s]
  ⚙  ::add-path:: /opt/hostedtoolcache/node/22.23.3/x64/bin
⭐ Run Main Prove the versions
  | node : v22.23.3
  | npm  : 10.9.9
  | cache dir: /root/.npm
✅  Success - Main Prove the versions [267.159491ms]
```

Line by line, all of it real:

- **`git clone 'https://github.com/actions/setup-node' # ref=v7`** — `act` fetched
  the action's repository at the pinned ref before running it. That is what
  "using someone's action" means mechanically: clone their code, run it, throw
  it away with the machine.
- **`Found in cache @ /opt/hostedtoolcache/node/22.23.3/x64`** — **this is the
  answer to "what does `node-version: '22'` mean".** It means *whatever the
  latest 22.x is today*. Today, on this runner image, that is **22.23.3**, and
  the next step re-measures it as `node : v22.23.3`. Compare with the local
  machine's `v24.19.0` (recorded in `docs/00-roadmap.md`) and with
  `package.json`'s `engines.node: ">=22"`. Three different facts, all correct:
  the image's default, your laptop, and your declared minimum.
- **`npm: 10.9.9`** — npm ships *with Node*, so pinning Node pins npm with it.
  Your laptop's npm 11.x does not appear here.
- **`npm cache is not found`** — the honest wording for a cold cache. This run
  had nothing to restore. Chapter 16 measures what a warm run looks like.
- **`/root/.npm`** — where npm puts its download cache, and therefore what gets
  cached. `npm ci` then took `3.081763902s`.
- **`::add-path:: /opt/hostedtoolcache/node/22.23.3/x64/bin`** — the step
  prepends that directory to `PATH` for every later step. This is the mechanism
  by which `node` becomes the version you asked for, and why a `setup-node`
  step placed *after* your `npm ci` step is a bug.

### The cache key, and what it is made of

Still from the same log:

```
⚙  ::set-output:: cache-primary-key=node-cache-Linux-x64-npm-6aabe04fd4b2161267891150af82ba292cb51d2ee06dbd26ffcafaa2da9cc66c
⚙  ::set-output:: cache-hit=false
⚙  ::set-output:: cache-matched-key=
...
⭐ Run Post Set up Node.js
  | [command]/usr/bin/tar --posix -cf cache.tgz --exclude cache.tgz -P -C /home/sunny/app/nimo/cicd-docs --files-from manifest.txt -z
  | Cache Size: ~21 MB (22341621 B)
  | Cache saved successfully
  | Cache saved with the key: node-cache-Linux-x64-npm-6aabe04fd4b2161267891150af82ba292cb51d2ee06dbd26ffcafaa2da9cc66c
```

Map it onto the source from section 2 and every character is accounted for:

```
node-cache  -Linux -x64 -npm     -6aabe04f...
  prefix      platform  arch  manager  glob.hashFiles(lockFilePath)
```

`cache-hit=false` on the restore side and `Cache saved with the key` on the save
side is the complete first-run story. On the next run with an unchanged lock
file, `cache-hit` becomes `true` and you should see `Cache restored from key:`
instead. That second run has **not** been measured here, so treat it as the
chapter-16 exercise rather than as this chapter's evidence.

One thing to be careful about: those `::set-output::` lines are `act` displaying
the action calling `core.setOutput`. `setup-node` v7 is not using the removed
`::set-output` workflow command; `core.setOutput` is the supported API and writes
to `$GITHUB_OUTPUT`.

### The checks, running under the pinned Node

ANSI colour codes stripped; everything else verbatim:

```
⭐ Run Main Run the real checks with the pinned Node
  | > cicd-learn@1.0.0 lint
  | > eslint .
  |
  | > cicd-learn@1.0.0 test
  | > vitest run
  |
  |  RUN  v5.0.3 /home/sunny/app/nimo/cicd-docs/cicd-learn
  |
  |  ✓ test/sum.test.js (5 tests) 6ms
  |  ✓ test/greet.test.js (8 tests) 6ms
  |
  |  Test Files  2 passed (2)
  |       Tests  13 passed (13)
  |    Start at  09:21:03
  |    Duration  176ms (transform 57%, import 25%, tests 10%, worker 7%)
  |
  | > cicd-learn@1.0.0 build
  | > node build.mjs
  |
  | built dist/app.js (2887 bytes)
✅  Success - Main Run the real checks with the pinned Node [1.370033614s]
```

`Test Files 2 passed (2)`, `Tests 13 passed (13)`, `built dist/app.js (2887
bytes)` — the same numbers this course has quoted since chapter 02, now running
under `v22.23.3` rather than your laptop's Node. `eslint .` printed nothing,
which is what a clean lint looks like.

And `added 127 packages, and audited 128 packages in 3s` from the step above.
That is `npm ci` doing its job: exact versions from the lock file, one pass, no
resolution.

### The finding: `cache: npm` without `cache-dependency-path` fails

Remove one line from the `Set up Node.js` step — `cache-dependency-path:
cicd-learn/package-lock.json` — and leave `cache: 'npm'`. `setup-node` then calls
`findLockFile`, which does `readdirSync($GITHUB_WORKSPACE)` and looks for
`package-lock.json` in the **repository root**. Our lock file is at
`cicd-learn/package-lock.json`. It is not there. The action throws:

```
::error::Dependencies lock file is not found in <repository workspace>.
  Supported file patterns: package-lock.json
```

and the "Set up Node.js" step fails, so **every step after it — including
`npm ci` — is skipped.**

The fix is the line the workflow already carries:

```yaml
with:
  cache: 'npm'
  cache-dependency-path: cicd-learn/package-lock.json   # the fix
```

Three things to be certain about here:

- **This is not an `act` quirk.** The failure is `throw new Error` inside
  `setup-node@v7`'s own code, reading a path the action itself chose. It behaves
  identically on GitHub. Nothing about the local container changes it.
- **It hits every monorepo layout**, which is why chapter 44 needs it again.
- **A related, quieter failure exists.** Point `cache-dependency-path` at a file
  that does not exist and you get the *other* error from the source:
  `Some specified paths were not resolved, unable to cache dependencies.` — which
  throws earlier, at the `!fileHash` check. Two different mistakes, two different
  messages. Both mean "fix your path".

### The second finding: a real bug in this chapter's own `anatomy` job

The `anatomy` job as committed (`docs/_logs/ch09-anatomy.log`, exit 1):

```
⭐ Run Main Show that an action is just files
  | --- a JavaScript action looks like this ---
  | find: ‘.github/actions’: No such file or directory
  |
  | --- action.yml is the manifest ---
  | cat: .github/actions/setup-node/action.yml: No such file or directory
❌  Failure - Main Show that an action is just files [59.751787ms]
exitcode '1': failure
```

`.github/actions` does exist — at the **repository root**. The job inherits
`defaults.run.working-directory: cicd-learn`, so `.github/actions` means
`cicd-learn/.github/actions`, which does not exist. Relative paths in a `run:`
step are resolved from the working directory, not from the repository root.

The fix is `../` on all three paths, and the corrected job's real output is in
`docs/_logs/ch09-anatomy-fixed.log`:

```
| --- a JavaScript action looks like this ---
| ../.github/actions/setup-node/action.yml
| ../.github/actions/setup-node/run.sh
|
| --- action.yml is the manifest ---
| # A composite action: several steps packaged under one name, written in YAML.
| name: 'Set up cicd-learn'
| description: 'Checkout, install the pinned Node, then npm ci.'
| inputs:
|   node-version:
|     description: 'Node.js version to install'
|     required: false
|     default: '22'
|   run-checks:
|     description: 'Whether to run lint, test and build after installing'
|     required: false
|     default: 'true'
| runs:
|   using: 'composite'
|   steps:
|     - name: Checkout
|       uses: actions/checkout@v7
|       with:
|         fetch-depth: 1
|
|     - name: Set up Node ${{ inputs.node-version }}
|       uses: actions/setup-node@v7
|       with:
|         node-version: ${{ inputs.node-version }}
|         cache: 'npm'
...
|
| --- and its implementation ---
| #!/usr/bin/env bash
| # The script half of a composite action. This particular action delegates to
| # other actions, so there is not much logic here; a real composite action with
| # its own logic would put it here.
| set -euo pipefail
|
| echo "composite action invoked"
| echo "  node-version: ${1:-22}"
| echo "  run-checks  : ${2:-true}"
```

That is an action, printed from a real file in this repository: a manifest that
declares two inputs with defaults, and a `runs: using: composite` block that is
just a list of steps. Two files, no magic. It is also, deliberately, the sample
chapter 41 builds on.

So a chapter about using actions contains a job that fails, and the fix is three
`../` prefixes. Remember that one: **in a `run:` step, every relative path is
relative to `working-directory`.**

## 5. When to use it and when NOT to

**Use an action when:**

- The job is "get some tool into place": checkout, Node, Python, Java, Go,
  Buildx, a cloud CLI. These are the canonical uses and they are well maintained.
- The behaviour is fiddly and already solved: uploading artifacts, restoring a
  cache, posting a comment, generating a matrix. An action here is fewer lines
  and fewer bugs than your version.
- The same setup is repeated in many workflows and you want one version of it.
  A composite action (chapter 41) is the honest way to share it; copy-pasting
  `with:` blocks is not.

**Write a `run:` step when:**

- The command is one line. `run: npm ci` is clearer than an action wrapper.
- You want to control the exact flags, the order, the exit code.
- The logic is yours. Nobody on the Marketplace has your build.

**Pin by major version when:**

- You are learning, or the pipeline is not security-sensitive. `@v7` gets
  patches and is one character.

**Pin by SHA when:**

- **The workflow runs on `pull_request` from outside your team.** That is the
  supply-chain boundary. Chapter 39's rule, and the attack it prevents.
- You want a change to the action to arrive as a visible diff you approved.

**Do NOT add an action when:**

- **You have not read what it runs.** Every `uses:` line executes third-party
  code with your repository's token. Check the publisher, the last release date,
  the open issues, and how many other workflows in the world use it.
- **You need one line of shell.** A dependency is a permanent cost.
- **It does exactly what an action already in your workflow does.** Two caches,
  two setup steps, two results to explain when one goes wrong.
- **You copied it from a 2019 tutorial and it uses `@v2`.** Six majors of
  breaking change happened. Re-read its README.

**Do NOT use `cache: 'npm'` when:**

- You have no lock file committed. There is no key to build, and `npm ci` would
  fail anyway. Chapter 11.
- You cache `node_modules` instead. `npm ci` deletes `node_modules` on every run,
  so that cache is never read. `cache: npm` caches the download cache, which
  *is* read.

## 6. Common mistakes

- **`cache: npm` with the lock file in a subdirectory.** Fails with
  `::error::Dependencies lock file is not found in <repo>`. Fix:
  `cache-dependency-path: <path to lock file>`. This is the single most common
  `setup-node` error in monorepos, and it fails the same way on GitHub.
- **`cache-dependency-path` pointing at a missing file.** Different message:
  `Some specified paths were not resolved, unable to cache dependencies.` Fix the
  path. Note the two messages, so you know which mistake you made.
- **`setup-node` after the step that needs Node.** `::add-path::` affects later
  steps only. Symptom: `npm ci` runs on the image's Node, and the version you
  pinned appears nowhere. Put `setup-node` second, immediately after checkout.
- **Trusting `node-version: '22'` as "version 22.0".** It is "the latest 22.x the
  runner image offers" — `22.23.3` in this run. For an exact version, use
  `node-version: '22.23.3'`. For a version the repository owns, use
  `node-version-file: '.nvmrc'`.
- **A misspelled `with:` key.** Silently ignored; the action runs with defaults
  and the step is green. Symptom: "caching does nothing", "it checked out the
  wrong path". Read the action's `action.yml`, do not guess.
- **Unpinned refs.** `@main`, `@master`, or no ref at all. Caught locally by
  `scripts/validate-workflows.py`.
- **`fetch-depth: 0` "just in case".** Full history on a large repository is
  real time on every run of every job. Use it only if you run `git log`,
  `git describe` or a changelog generator.
- **Relative paths in a `run:` step ignoring `working-directory`.** Section 4's
  `anatomy` job. `.github/workflows` under `working-directory: cicd-learn` means
  `cicd-learn/.github/workflows`.
- **`uses:` step and `working-directory` from `defaults.run`.** `defaults.run`
  does not apply to `uses:` steps.
- **Caching `node_modules`.** `npm ci` deletes it. Pointless, and it hides real
  lock-file problems.
- **`registry-url` pointing at a mirror that needs auth**, with the token not
  wired up. Symptom: a 401 inside `setup-node` or on the first install. The
  token is a secret; chapter 22.
- **An action from a personal fork with the same name as the official one.**
  Check the full `owner/repo@ref`, not just the part after the slash. Dependabot
  (chapter 36) is configured with the full name for exactly this reason.

## 7. Try it yourself

**Exercise: break `setup-node` twice, then read the action's own manifest.**

1. Add a second job to `.github/workflows/09-using-actions.yml`, or copy the
   `actions` job into `.github/workflows/setup-node-probe.yml`. Keep
   `node-version: '22'` and `cache: 'npm'`, and **delete the
   `cache-dependency-path` line**.

2. Run it:

   ```bash
   ./scripts/run-workflow.sh .github/workflows/setup-node-probe.yml actions push
   ```

   Read the failure. You should see the step fail with the message about the lock
   file not being found, and the steps after it skipped entirely. **This is the
   same failure GitHub gives you**, because it is a `throw` inside the action.

3. Put the line back and re-run. Green, with the same
   `node-cache-Linux-x64-npm-…` key.

4. Now break the *other* thing. Change the path:

   ```yaml
   cache-dependency-path: cicd-learn/package-lock.jsonx   # typo
   ```

   Re-run. Different message, earlier failure:

   ```
   Some specified paths were not resolved, unable to cache dependencies.
   ```

   Now you can tell the two mistakes apart from the error text alone.

5. **Read a real action's manifest** and confirm the input names you are using:

   ```bash
   # setup-node's own declared inputs, from the copy act fetched
   sed -n '/^inputs:/,/^runs:/p' ~/.cache/act/actions-setup-node@v7/action.yml
   ```

   Compare every key in your `with:` block against that list. Anything not on the
   list is being ignored by the action, silently. This is a two-minute habit
   that prevents a whole class of "why did that setting do nothing".

6. **Fix the `anatomy` job in your copy.** Prefix all three paths with `../` and
   re-run:

   ```bash
   ./scripts/run-workflow.sh .github/workflows/09-using-actions.yml anatomy push
   ```

   Compare with the failure you already have in `docs/_logs/ch09-anatomy.log`. One
   character class, three lines, whole step.

**Hint:** `act` prints the clone line for every external action it fetches:

```
☁  git clone 'https://github.com/actions/setup-node' # ref=v7
```

That is the exact repository and ref your `uses:` resolved to, printed at the top
of the run. If a step behaves unexpectedly, look for that line first — it tells
you whether you got the action you thought you did.

**Break it on purpose, in the way that hurts most:** change
`uses: actions/setup-node@v7` to `uses: actions/setup-node@v7` with
`node-version-file: 'package.json'` and no `node-version`. That looks like a
sensible way to "read the version from the project" and it is wrong:
`node-version-file` expects a `.nvmrc` or `package.json` in `.node-version`
format, not a `package.json` with an `engines` block. The step runs, installs
nothing, and every later step silently uses the image's Node. A green pipeline
using the wrong toolchain is the failure mode this chapter is really about.

## 8. Next

You can pull in other people's code and configure it. That makes pipelines that
work — and makes reading them essential, because a red build is now a page of
log output with three ways to interpret it. The next chapter is the skill of
reading that page.

→ [10 — Reading logs](10-reading-logs.md)