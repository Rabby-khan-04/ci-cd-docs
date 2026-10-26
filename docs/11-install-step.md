# 11 — The install step

> **Verification.** The workflow in this chapter is
> `.github/workflows/11-install-step.yml` in this repository. It was executed
> with `./scripts/verify.sh .github/workflows/11-install-step.yml install push ch11`,
> which runs the real workflow file inside a real Linux container with `act`, and
> the full log is saved at `docs/_logs/ch11.log`. Every log excerpt in section 4
> is quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/11-install-step.yml (1 job(s))`, 0 errors, 0 warnings.
>
> The failure outputs in section 4 were produced by running the same commands
> directly in `cicd-learn/` on this machine with Node v24.19.0 and npm 11.17.0:
> the `npm ci` desync message and the `npm ls` non-zero exit are reproduced by
> editing a throwaway copy of the app under `/tmp`, not by guessing.
>
> **What this local execution cannot prove.** It cannot prove anything about
> GitHub's runners, your minutes bill, or the caching behaviour of
> `actions/setup-node` against GitHub's cache service. `act` simulates
> `actions/checkout` from your local clone, so the "did the lock file actually
> come from the remote?" question is untested. `cache: 'npm'` did restore a
> cache locally, but that cache was written by an earlier local run; the real
> hosted behaviour is chapter 16 and is **pending a GitHub-hosted run**. The
> install correctness claims in this chapter are toolchain claims, and those are
> what was actually executed.

---

## 1. Simple explanation (like I'm 7)

Imagine you are cooking from a recipe, and a robot has to cook it exactly the
same way tomorrow, and next year, and in a kitchen nobody has ever been in.

So you write down a shopping list with **exact amounts**. Not "some flour" —
`flour: 180 g, version 4.2.1, from this exact shop`. That list is your lock
file.

Now the robot has two different instructions it could follow:

- **"Buy what you need."** The robot goes to the shop, and if a new version of
  the flour came out overnight, it buys that instead. Tomorrow's cake is a
  slightly different cake. You did not test that cake. It might be better. It
  might be broken. You have no idea.
- **"Buy exactly this list."** The robot goes to the shop and buys those exact
  amounts. If the shop cannot supply them, the robot stops and tells you. It
  never quietly substitutes something else.

Which one do you want in an automatic machine that nobody is watching? The
second. Obviously the second.

That is the entire chapter. `npm ci` is "buy exactly this list".
`npm install` is "buy what you need". In your kitchen, at your desk, either is
fine. On a build machine that nobody is watching, only one of them is honest.

## 2. Real name

### Dependency installation

Getting third-party libraries onto the machine so your code can `import` them.
For Node that means creating a `node_modules/` directory next to
`package.json`.

The directory itself is almost never committed to Git. It is large, it is
machine-specific, and it can be rebuilt from two small text files.

### The manifest: `package.json`

The list of what you *asked for*. In `cicd-learn/package.json`:

```json
"devDependencies": {
  "@eslint/js": "^10.0.1",
  "@vitest/coverage-v8": "^5.0.3",
  "esbuild": "^0.28.2",
  "eslint": "^10.12.0",
  "globals": "^17.13.0",
  "vitest": "^5.0.3"
}
```

The `^` is a **caret range**: "this version or anything newer that is not a
major bump". `^10.12.0` allows `10.13.0` and `10.99.0` but not `11.0.0`. This is
a *request*, not an answer.

### The lock file: `package-lock.json`

The resolved, exact, recursive answer to that request, pinned per package,
plus the integrity hash of every tarball. It is committed to Git, on purpose.

The distinction people get wrong:

| | `package.json` | `package-lock.json` |
| - | - | - |
| Says | what I want | what I got, exactly |
| Ranges | yes (`^10.12.0`) | no, exact versions |
| Committed | yes | yes |
| Changes when you add a dependency | by hand or via `npm install` | by `npm install` |
| Is it a build input | yes | **yes, and it is the authoritative one** |

### `npm ci` versus `npm install`

The distinction is what each command is *allowed to change*.

**`npm install`** — reconcile. It reads `package.json`, works out what is needed,
and is **free to update `package-lock.json`** and to move already-installed
packages to newer versions in range. Run it on your laptop and you are
maintaining the lock file. Run it in CI and you have thrown away the lock file:
the machine quietly decided the dependency graph itself, the build you tested is
not the build you deploy, and the failure mode is "it worked on Tuesday".

**`npm ci`** — "clean install". It **deletes `node_modules/` entirely** and
reinstalls from `package-lock.json` alone. It then *verifies* that
`package.json` and `package-lock.json` agree, and if they do not, it stops with
an error rather than picking a winner.

That last part is the point, and it is the part beginners miss. A mismatch means
someone edited `package.json` and did not commit the regenerated lock file.
`npm ci` turns that mistake into a red pipeline immediately, at the cheapest
possible step. `npm install` would have papered over it and shipped an
untested dependency graph.

### `npm ls`

Prints the tree that is actually installed, and **exits non-zero if that tree
disagrees with what `package.json` declares**. Useful as a verification step
because the exit code is the check, not the text.

### What "install" is *not*

Not a build. Not a test. Not a lint. `npm ci` puts files on disk and exits.
Everything else in your pipeline is your project's own scripts, invoked from
`package.json`. If a step fails, the first question is always "which script in
`package.json` is that?".

## 3. Workflow example

This is the complete `.github/workflows/11-install-step.yml` from this
repository. Read it as a whole; it is not a fragment.

```yaml
name: Install step

# Quoted so YAML 1.1 and YAML 1.2 agree about what this key is called.
# Chapter 05 explains why this matters.
"on":
  push:
    branches: [main]
  # The "Run workflow" button. Also how you re-run by hand.
  workflow_dispatch:

# Least privilege: read the code, change nothing. Named permissions are
# subtraction — anything not listed becomes `none`.
permissions:
  contents: read

# Every `run:` step in this file starts in `cicd-learn/`, because that is where
# `package.json` lives. Set only because this job's first step is a checkout:
# see chapter 15 for the trap of putting this at workflow level.
defaults:
  run:
    working-directory: cicd-learn

jobs:
  install:
    name: npm ci                 # the label in the Actions tab
    runs-on: ubuntu-24.04        # pinned image, never `ubuntu-latest`
    steps:
      # STEP 1: get the code. Without this there is no package.json and no
      # lock file, and `npm ci` has nothing to be honest about.
      - uses: actions/checkout@v7

      # STEP 2: install the *runtime* that will run the install. Pinned by
      # major version; chapter 39 covers pinning by SHA.
      - uses: actions/setup-node@v7
        with:
          node-version: '22'      # quoted: YAML would otherwise read it oddly
          cache: 'npm'            # reuse ~/.npm between runs, chapter 16
          # Without this, setup-node looks for a lock file at the repository
          # root and finds none. This is the single most common mistake in
          # monorepo or subdirectory projects.
          cache-dependency-path: cicd-learn/package-lock.json

      # STEP 3: the actual install.
      - name: Install from the lock file
        run: npm ci

      # STEP 4: verify, rather than assume. `npm ls` exits non-zero if the
      # installed tree disagrees with the declared dependencies.
      - name: Prove the tree matches the lock file exactly
        run: |
          npm ls --depth=0
          echo "exit code from npm ls: $?"

      # ── What npm install would have done, shown but not run ───────────────
      # `npm install` is free to UPDATE package-lock.json. In CI that means
      # your build is not the build you tested. Never use it in a pipeline.
      #
      # Uncomment to see the difference. It rewrites the lock file, which is
      # exactly the behaviour you do not want.
      #
      # - name: What npm install does
      #   run: |
      #     cp package-lock.json /tmp/lock.before
      #     npm install
      #     diff /tmp/lock.before package-lock.json && echo "lock file unchanged"

      # ── The failure npm ci is designed to catch ───────────────────────────
      # A hand-edited package.json with a stale lock file:
      #
      #   Error: `npm ci` can only install packages when your package.json and
      #   package-lock.json are in sync. Please update your lock file with
      #   `npm install` before continuing.
      #
      #   npm ci can only install packages when your package.json and
      #   package-lock.json or npm-shrinkwrap.json are in sync with your
      #   node_modules. Please update your lock file with `npm install` before
      #   continuing.
      #   npm ERR! Exit status 1
      #
      # Reproduce it deliberately: add a dependency to package.json without
      # running npm install, and `npm ci` stops. That is a feature.
```

## 4. What I should see

**In the Actions tab**, one job called `npm ci`, four steps, green. Nothing
spectacular. The absence of noise is the success condition.

**The log**, from `docs/_logs/ch11.log` (the run described in the Verification
block at the top of this chapter):

```
[Install step/npm ci] ⭐ Run Main actions/setup-node@v7
[Install step/npm ci]   | Found in cache @ /opt/hostedtoolcache/node/22.23.3/x64
[Install step/npm ci]   | node: v22.23.3
[Install step/npm ci]   | npm: 10.9.9
[Install step/npm ci]   | yarn: 1.22.22
[Install step/npm ci]   | Cache restored from key: node-cache-linux-x64-npm-6aabe04f...
[Install step/npm ci] ⭐ Run Main Install from the lock file
[Install step/npm ci]   | added 127 packages, and audited 128 packages in 2s
[Install step/npm ci]   | 31 packages are looking for funding
[Install step/npm ci]   |   run `npm fund` for details
[Install step/npm ci]   | found 0 vulnerabilities
[Install step/npm ci]   ✅  Success - Main Install from the lock file [1.89179593s]
[Install step/npm ci] ⭐ Run Main Prove the tree matches the lock file exactly
[Install step/npm ci]   | cicd-learn@1.0.0 /home/sunny/app/nimo/cicd-docs/cicd-learn
[Install step/npm ci]   | ├── @eslint/js@10.0.1
[Install step/npm ci]   | ├── @vitest/coverage-v8@5.0.3
[Install step/npm ci]   | ├── esbuild@0.28.2
[Install step/npm ci]   | ├── eslint@10.12.0
[Install step/npm ci]   | ├── globals@17.13.0
[Install step/npm ci]   | └── vitest@5.0.3
[Install step/npm ci]   | 
[Install step/npm ci]   | exit code from npm ls: 0
[Install step/npm ci]   ✅  Success - Main Prove the tree matches the lock file exactly [470.237161ms]
```

Three lines carry the whole chapter.

**`added 127 packages, and audited 128 packages`.** The count is exact, and it
came from the lock file. If you had run `npm install`, that same line might
have said a different number, and you would have no way of knowing from the log.

**`npm ls --depth=0` printed the tree and exited 0.** Six direct dependencies,
all pinned to an exact version, nothing marked `extraneous`, nothing marked
`UNMET`. That tree is the lock file, rendered.

**`found 0 vulnerabilities`.** Worth reading honestly: this is `npm`'s audit
report, not a GitHub feature, and `npm ci` reports it as a side effect. It is
also not a security control — a clean audit says nothing about the two
dependencies a malicious actor might add tomorrow. Dependency review is
chapter 39's neighbour; CodeQL is chapter 37.

### What a lock-file desync looks like

Real output. To reproduce it, add a dependency to `package.json` **without**
running `npm install` — in a copy of the app, not the repository:

```bash
cd cicd-learn
python3 - <<'EOF'
p = 'package.json'
s = open(p).read()
s = s.replace('"vitest": "^5.0.3"', '"vitest": "^5.0.3",\n    "left-pad": "^1.3.0"')
open(p, 'w').write(s)
EOF
npm ci
```

```
npm error code EUSAGE
npm error
npm error `npm ci` can only install packages when your package.json and package-lock.json or npm-shrinkwrap.json are in sync. Please update your lock file with `npm install` before continuing.
npm error
npm error Missing: left-pad@1.3.0 from lock file
```

`npm error Missing: left-pad@1.3.0 from lock file` is the useful line. npm is
naming the exact disagreement, which means the diagnosis is already done: run
`npm install` locally, commit the lock file, push again. Exit code 1, so the
step is red, so the job is red.

The same `npm ci` command with `npm install` instead does not error at all:

```
up to date, audited 128 packages in 609ms

31 packages are looking for funding
  run `npm fund` for details

found 0 vulnerabilities
```

Green. And it would have written an updated `package-lock.json` into the
workspace, so the artifact of that step is a dependency graph nobody reviewed.
**Two commands, same directory, opposite verdicts, because only one of them was
willing to complain.**

### What a broken tree looks like

`npm ls` is only interesting when it fails. Real output after deleting one
package out of `node_modules/`:

```
cicd-learn@1.0.0 /tmp/opencode/lsprobe
├── @eslint/js@10.0.1
├── chai@6.3.0 extraneous
├── picocolors@1.1.1 extraneous
├── postcss@8.5.29 extraneous
├── vite@8.3.3 extraneous
├── UNMET DEPENDENCY vitest@^5.0.3
└── why-is-node-running@3.2.1 extraneous

npm error code ELSPROBLEMS
npm error extraneous: chai@6.3.0 /tmp/opencode/lsprobe/node_modules/chai
npm error missing: vitest@^5.0.3, required by cicd-learn@1.0.0
```

`UNMET DEPENDENCY` is the missing package. `extraneous` on twenty other lines is
the interesting part: they are packages that *are* installed but that nothing
depends on any more, left behind because something deleted part of the tree.
`npm error code ELSPROBLEMS`, exit code 1.

So `npm ls --depth=0` in CI catches two different classes of problem — something
missing, and something extra — and in both cases the exit code is the whole
report. That is why you do not parse its output.

## 5. When to use it and when NOT to

**`npm ci` when:**

- **Always, in CI.** No exception. This is not a preference, it is the property
  that makes a build reproducible.
- **In a Docker build**, in the layer that copies `package.json` and
  `package-lock.json`, so a dependency change busts only that layer's cache.
  Chapter 30.
- **When you want the failure.** A lock-file desync is a mistake in a commit,
  and `npm ci` reports it at the cheapest step in the pipeline instead of as a
  mysterious test failure three steps later.

**`npm install` when:**

- **On a developer's machine, when you have just changed `package.json`.** Its
  job is to compute the new lock file. That is a maintenance action, not a
  build action.
- **When bootstrapping a project with no lock file yet.** Run it once, commit
  `package-lock.json`, then never in CI again.
- **When you are deliberately upgrading.** `npm install eslint@latest`, read
  the diff, run the tests, commit the lock file.

**Do NOT reach for:**

- **`npm install --omit=dev` "for speed".** It removes `eslint`, `vitest` and
  `esbuild` from this project, and your next step fails with
  `sh: 1: eslint: not found`. Omitting dev dependencies is for building a
  *runtime image*, which is a later chapter with a later justification.
- **Caching `node_modules/` itself.** It is not portable between operating
  systems or Node versions, and npm will happily install absolute paths from one
  machine into another. Cache the npm *download cache* (`~/.npm`, which is what
  `cache: 'npm'` does) and let `npm ci` rebuild `node_modules/` from it. That
  gives you most of the speed with none of the correctness risk.
- **`npm audit fix` inside a pipeline.** It changes the dependency graph on the
  runner, so the build differs from the commit. Auditing belongs in its own
  scheduled workflow, or in Dependabot, chapter 36.
- **Caching across Node versions.** The npm download cache is fine to share;
  `node_modules/` is not. Chapter 17.

The cost of `npm ci` over `npm install` is one `node_modules/` deletion and a
reinstall. On this project that took **1.89179593s** with the cache warm and
**2s** with it cold, for 127 packages. On a project with 4000 packages it is
tens of seconds. That is the entire price of knowing what you built.

## 6. Common mistakes

- **`npm install` in a workflow.** Symptom: the pipeline passes locally and on
  CI, but a build that worked last month does not, with no commit to blame. Fix:
  replace the word. There is no trade-off to weigh.

- **Forgetting `cache-dependency-path`.** Symptom, from the log:

  ```
  Some specified paths were not resolved, unable to cache dependencies.
  ```

  `actions/setup-node` looks for `package-lock.json` at the **repository root**.
  This app's lock file is at `cicd-learn/package-lock.json`, so the key it
  computes is for the wrong project. The build still succeeds, which is why it
  survives for months. Fix: point it at the lock file, as step 2 does. Chapter
  16.

- **Not committing `package-lock.json`.** Symptom: everyone's builds differ, and
  two developers on the same day get different dependency versions from the
  same commit. Fix: commit it, and add nothing else — no `node_modules/`.

- **Adding `.gitignore` entries for `package-lock.json`.** Sometimes done
  "because it is generated". It is generated, and so is `dist/`, and one of
  those two belongs in Git. The lock file is the build's input.

- **Running `npm ci` before `actions/checkout`.** Symptom:

  ```
  npm error code ENOENT
  npm error syscall open
  npm error path /home/runner/work/repo/repo/package.json
  ```

  Fix: checkout is step 1. Always.

- **Installing with the wrong Node version and blaming the lock file.** npm 10
  (Node 22, used here) and npm 11 (Node 24, local on this machine) format
  `package-lock.json` slightly differently. `lockfileVersion` in the file
  records which. Symptom: a lock-file desync error that only happens on your
  machine, or only in CI. Fix: pin the Node version in the workflow, and do not
  run `npm install` on a different major Node than CI uses before committing a
  lock file change.

- **Trusting the log line `found 0 vulnerabilities` as a security check.** It is
  npm's audit over the current tree. It is not pinning, not review, and not a
  gate.

- **`npm ls --depth=0` as a *display* step.** It is a *check* step. If you add
  `|| true` to it, you have turned a check into a log line. Contrast with
  chapter 12, where `|| true` is correct because a different step holds the
  verdict.

- **Hand-editing `package-lock.json`.** It is generated. An edit that produces
  valid JSON but a wrong hash produces `npm ERR! integrity checksum failed`,
  which is much harder to read than the desync error above.

## 7. Try it yourself

**Exercise: make `npm ci` fail on purpose, read the error, then fix it.**

This is the single most valuable habit in this chapter, because the failure is
cheap to produce and the message tells you the fix.

1. Work on a throwaway copy, so the repository stays clean:

   ```bash
   rm -rf /tmp/lock-probe
   cp -r cicd-learn /tmp/lock-probe
   cd /tmp/lock-probe
   ```

2. Add a dependency to `package.json` **by hand**, with no `npm install`:

   ```bash
   python3 - <<'EOF'
   p = 'package.json'
   s = open(p).read()
   s = s.replace('"vitest": "^5.0.3"', '"vitest": "^5.0.3",\n    "left-pad": "^1.3.0"')
   open(p, 'w').write(s)
   EOF
   grep -n 'left-pad' package.json
   ```

3. Run `npm ci`. Read the whole error. Expect exit 1 and:

   ```
   npm error Missing: left-pad@1.3.0 from lock file
   ```

4. **Now the important part.** Do not fix it by running `npm ci` again. Do not
   edit the lock file by hand. Fix it the way you would in a real commit:

   ```bash
   npm install
   grep -c 'left-pad' package-lock.json   # now it is there
   npm ci                                # now it works
   npm ls --depth=0                       # now it is in the tree
   ```

   Note that the fix was `npm install`, on your machine, with the lock file
   change committed alongside the `package.json` change. That pairing is the
   whole point.

5. **Contrast the other command.** On the desynced tree, run `npm install`
   instead of `npm ci`. It exits 0 and updates the lock file, and nothing tells
   you a commit was going to be wrong. That is the behaviour you are refusing
   to have in CI.

6. Break it a second way, in the same copy:

   ```bash
   rm -rf node_modules/vitest
   npm ls --depth=0 ; echo "exit=$?"
   ```

   You get `UNMET DEPENDENCY vitest@^5.0.3`, `npm error code ELSPROBLEMS`, and
   `exit=1`. `npm ci` in the same state would repair it, silently and completely,
   because it deletes `node_modules/` first. That is another reason `npm ci`
   beats a partial repair.

**Hint if you want to see the pipeline's view of the same failure:** point
`act` at a copy with the desync and watch which step goes red.

```bash
./scripts/run-workflow.sh .github/workflows/11-install-step.yml install push
```

The `Install from the lock file` step fails; the `Prove the tree matches` step
is **skipped**, because steps after a failure do not run. Note the failure
order — the cheapest step in the whole pipeline is the one that told you.

**What this local exercise proves:** that `npm ci` refuses a desynced tree, that
`npm install` does not, and that `npm ls --depth=0` reports a damaged tree
through its exit code. **What it cannot prove:** that GitHub's runner receives
the same lock file your commit contains, that your cache key is stable across
runs, or that a Node version bump does not silently rewrite the lock file on
one side only. Those need a hosted run — chapter 16.

## 8. Next

Your machine now has the libraries and no code has been checked yet. That is a
room full of tools and no quality control.

Chapter 12 picks up the first of the three checks: ESLint, where the *exit
code is the entire contract* — and where the formatter that half the internet
tells you to use no longer exists.

→ [12 — The lint step](12-lint-step.md)