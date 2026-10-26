# 15 — Putting it together: the order

> **Verification.** The workflow in this chapter is
> `.github/workflows/15-ci-pipeline-order.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/15-ci-pipeline-order.yml '' push ci15`.
> `act` 0.2.89 cannot speak the protocol `actions/upload-artifact@v7` uses, so
> `verify.sh` detected that and re-ran an automatically generated copy in which
> the upload step was replaced by a local `tar`, which is why the log header says
> `### file .tmp/sim-ci15.yml`. The full log is at `docs/_logs/ci15.log`; every
> excerpt in section 4 is quoted from it. `python3 scripts/validate-workflows.py`
> reports `ok .github/workflows/15-ci-pipeline-order.yml (2 job(s))`.
>
> The failure in section 4 is **also real and also from this repository's
> tooling**: a temporary probe copy of this same workflow, with
> `defaults.run.working-directory` moved from the `quality` job to workflow
> level, was run with
> `./scripts/verify.sh .tmp/probe-defaults.yml '' push probe-defaults`. The
> `quality` job passed and `release-ready` failed on a step made only of
> `echo`. That log is **not checked in**, because it is generated from a
> temporary file; section 7 reproduces it with two commands and prints it.
>
> **What this local execution cannot prove.** It cannot prove that GitHub's
> artifact service accepts the upload, that `retention-days: 7` is honoured, or
> that the `release-ready` job is *skipped* when `quality` fails — `act`
> reproduced the success path, and the skip behaviour comes from the documented
> `needs:` semantics. It cannot prove branch protection, and it cannot show
> parallel jobs running in parallel. The **artifact upload itself is the one step
> in this chapter that was simulated rather than executed**; everything else in
> the file ran for real.

---

## 1. Simple explanation (like I'm 7)

You have four machines that check your work.

- Machine one: get the toys out of the box.
- Machine two: check the toys are not broken.
- Machine three: play with every toy to see if it works.
- Machine four: pack the toys into one sealed box for someone else.

Two questions, and both are about **order**.

**First: which machine should go first?** The fast, boring one. If the toys are
already broken, playing with them wastes your time and tells you less. So: check
first, play second, pack last. Always cheapest-boring-first.

**Second: one long line of machines, or four machines all at once?** One after
another means one machine unpacks once. All at once means four machines each
unpack separately and all finish at the same time — which sounds faster and
usually is *not*. Most people guess "parallel is faster". For four quick checks
on a small project it is slower, and section 4 has the numbers.

There is also a third machine in this chapter that does no work at all. It just
says "the other machines all said yes". That is not a joke — that is the piece
you attach everything important to.

## 2. Real name

### The four steps

| Step | Command | What it decides | Wall clock here |
| ---- | ------- | --------------- | --------------- |
| Install | `npm ci` | is there a valid dependency tree | ~1.9s |
| Lint | `npm run lint` | is the code written the way we agreed | ~0.56s |
| Test | `npm test` | does the code do the right thing | ~0.70s |
| Build | `npm run build` | can the code be packaged | ~0.26s |

Every step's *only* job is to exit 0 or not. That is the pattern chapters 11 to
14 built, and this chapter is what it is for.

### Order: cheapest and most-likely-to-catch-typos first

The order is **install → lint → test → build**, and each position has a reason:

- **Install first**, obviously: nothing else can run without libraries.
- **Lint before test.** Lint takes half a second and catches *parse* errors. If
  `src/greet.js` has a syntax error, every test that imports it crashes with a
  module-loading error in an unrelated-looking place. Lint says "line 27: this
  file cannot be parsed" in half a second instead.
- **Test before build.** Tests are the most valuable signal you have — they are
  the only thing here that says the code is *right*. Nothing downstream should
  spend time on code that is about to fail.
- **Build last.** The bundler only fails for bundler reasons: a bad config, an
  unresolvable dynamic import, a `files` entry missing from `package.json`. Those
  are real failures, and they are also the *least* urgent thing to find, because
  nothing is being shipped yet.

Reverse the order and you get strictly worse failure messages. Build before
test and you spend time bundling code that is about to fail its tests. Test
before lint and a typo presents as a mystery.

### One job versus four jobs

This is the decision beginners get wrong, and the intuition that it is four jobs
"because there are four checks" is the mistake.

- **Steps in one job** share one machine and one filesystem. One `npm ci`.
  Chapter 08.
- **Jobs** each get their own machine. Four jobs means four `npm ci` runs, four
  sets of logs to read, and — unless you add `needs:` — they run **at the same
  time**.

Time is not "one sum, one queue". It is `max()` when jobs run in parallel, and
jobs run in parallel *by default*. So four jobs finish in roughly the time of
the slowest one, but each pays its own install. Here, install is 1.9s and
everything else totals about 1.5s: four jobs would finish in roughly 3s versus
about 3.4s for one job. No meaningful gain, four times the machines, four times
the minutes, four places to look when one of them is red.

The rule that follows: **split by dependency, not by tidiness.** Chapter 18 is
the chapter for when you *do* want the split.

### The gate

The second job in this workflow does no work. It is called `release-ready`, it
depends on `quality`, and it prints three lines. That is not filler:

- `needs: [quality]` makes it **wait** for `quality`.
- If `quality` fails, `needs` makes it **skip**. Skipped is not passed. Nothing
  downstream of the gate can happen.

So "everything is green" becomes a thing you can hang things on: a deploy, a
release, a comment on the pull request, a Slack message. Chapter 21 for the
notification, chapter 27 onward for the deploy. Adding a deployment later does
not mean re-deriving "when is it safe to deploy"; it means adding
`needs: [release-ready]` to one more job.

The one thing to be certain about: a job whose dependency failed **or was
skipped** is skipped too, unless you write `if: always()` or `if: failure()`.
Those conditions are the direct way to turn a gate back off. Chapter 19.

## 3. Workflow example

This is the complete `.github/workflows/15-ci-pipeline-order.yml` from this
repository.

```yaml
name: CI

# Quoted so YAML 1.1 and YAML 1.2 agree (chapter 05).
"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

# One permission for the whole file: read the code, change nothing. Individual
# jobs can only ever narrow this, never widen it.
permissions:
  contents: read

jobs:
  # ── Stage 1: the fast checks, in one job, cheapest first ──────────────────
  # Lint fails in about a second, tests in two, build in one. Putting them in
  # ONE job means one machine and one `npm ci` instead of three. Chapter 18
  # explains when to split them instead.
  quality:
    name: Lint, test, build
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    # Scoped to this job, not the whole file. `defaults.run.working-directory`
    # that points into a subdirectory only exists after `checkout` has run, so a
    # job WITHOUT a checkout (like the gate below) fails immediately with:
    #   OCI runtime exec failed: chdir to cwd (".../cicd-learn") failed
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

      - name: Install dependencies
        run: npm ci

      # Order matters, and it is cheapest-first.
      #
      #   1. lint   ~1s   catches syntax errors, so later steps do not crash on
      #                     a file that cannot even parse
      #   2. test   ~2s   catches behaviour errors, the most valuable signal
      #   3. build  ~1s   catches bundling errors, which only show up here
      #
      # If test ran before lint, a syntax error would surface as a confusing
      # test failure in an unrelated file. If build ran before test, you would
      # spend time bundling code that is about to fail its tests.
      - name: 1. Lint
        run: npm run lint

      - name: 2. Test
        run: npm test

      - name: 3. Build
        run: npm run build

      # ── Keep the output ───────────────────────────────────────────────────
      # The machine is destroyed when this job ends. If anything later needs
      # dist/, it has to be saved now. Chapter 20.
      - name: Upload the build output
        uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 7
          if-no-files-found: error

  # ── Stage 2: the gate ──────────────────────────────────────────────────────
  # This job does no work. Its only job is to not exist unless stage 1 passed,
  # which makes it the natural place to hang anything that must only happen on
  # green: a deploy, a comment, a release.
  release-ready:
    name: Release ready
    # `needs:` makes this job wait, and skip if the needed job failed. That is
    # the gate, and it is one line.
    needs: [quality]
    runs-on: ubuntu-24.04
    steps:
      - name: Everything passed
        run: |
          echo "quality gate passed"
          echo "commit  : ${{ github.sha }}"
          echo "branch  : ${{ github.ref_name }}"
          echo "event   : ${{ github.event_name }}"
          {
            echo "### CI passed"
            echo ""
            echo "This job does no work. It exists so that 'everything is green'"
            echo "is a thing you can attach other things to."
          } >> "$GITHUB_STEP_SUMMARY"
```

Read the shape: **two jobs, one of which does nothing.** That is the entire
architecture. Four checks, one machine, an artifact, and a named point after
which things are allowed to happen.

### The `defaults` trap, which is why that block is inside the job

This is the real bug found while writing this chapter, and it deserves a section
because the error message points nowhere near the cause.

The natural first draft puts `defaults` at the top of the file, next to
`permissions:`, where chapters 04 to 14 of this course all put it:

```yaml
# WRONG - do not do this
defaults:
  run:
    working-directory: cicd-learn
```

It applies to **every `run:` step in every job**. The `release-ready` job has no
`actions/checkout`; on a fresh runner its workspace is empty, so `cicd-learn/`
does not exist, and the job dies before printing anything.

Measured, with the same shape and the same tooling, `defaults` at workflow level:

```
[CI/Release ready    ] ⭐ Run Main Everything passed
[CI/Release ready    ]   | OCI runtime exec failed: exec failed: unable to start container process: chdir to cwd ("/home/sunny/app/nimo/cicd-docs/cicd-learn") set in config.json failed: no such file or directory
[CI/Release ready    ]   ❌  Failure - Main Everything passed [61.274999ms]
[CI/Release ready    ]   exitcode '127': command not found, please refer to https://github.com/nektos/act/issues/107 for more information
[CI/Release ready    ]   🏁  Job failed
Error: Job 'Release ready' failed
```

Note that `quality` — the job with a checkout — passed completely. Only the job
without one died, and it died on a step that contains nothing but `echo`. That
misalignment between cause and symptom is what makes this one expensive.

> The wording above is the local container runtime's message. On a GitHub-hosted
> runner the same mistake surfaces as a shell error from the failed `cd`, of the
> shape `cd: cicd-learn: No such file or directory`, followed by
> `Error: Process completed with exit code 1`. The cause is identical; only the
> wording differs, and neither mentions `defaults`.

**The fix is to scope `defaults` per job**, which is what the real file does:

```yaml
jobs:
  quality:
    defaults:              # <- inside the job that has a checkout
      run:
        working-directory: cicd-learn
    steps:
      - uses: actions/checkout@v7
      - run: npm ci

  release-ready:
    # no `defaults`, because it has no checkout and does not need a
    # subdirectory: its only step runs from the workspace root.
```

A second detail this chapter makes concrete: `defaults.run.working-directory`
affects **`run:` steps only**. It does *not* affect the `with:` inputs of an
action. That is why the upload step says

```yaml
path: cicd-learn/dist
```

and not `path: dist`. Paths given to actions are resolved from the workspace
root, so they must include the subdirectory themselves. Getting this backwards is
why some workflows upload a file called `dist` containing the wrong thing, or
fail with `No files were found with the provided path`.

## 4. What I should see

**In the Actions tab**, one workflow run named `CI`, two jobs. The shape below is
what GitHub draws; the durations are illustrative, because a local `act` run
reports per-step times rather than per-job totals:

```
CI
├─ ✓ Lint, test, build   (completed in 34s)
└─ ✓ Release ready       (completed in 8s)
```

They never overlap. `release-ready` sits greyed out for the first job's duration
and only starts afterwards.

From `docs/_logs/ci15.log`. The header first, because the `### file` line is
worth understanding:

```
### act act version 0.2.89
### image  node:24-bookworm
### event  push
### file   .tmp/sim-ci15.yml
```

That last line is the honest part: this run used an automatically generated copy
of the workflow in which the artifact upload was replaced by a local `tar`,
because `act` 0.2.89 cannot talk to the protocol `actions/upload-artifact@v7`
uses.

Stage 1, with the times that justify the ordering:

```
[CI/Lint, test, build] ⭐ Run Main Install dependencies
[CI/Lint, test, build]   | added 127 packages, and audited 128 packages in 1s
[CI/Lint, test, build]   | found 0 vulnerabilities
[CI/Lint, test, build]   ✅  Success - Main Install dependencies [1.363436232s]

[CI/Lint, test, build] ⭐ Run Main 1. Lint
[CI/Lint, test, build]   | > cicd-learn@1.0.0 lint
[CI/Lint, test, build]   | > eslint .
[CI/Lint, test, build]   ✅  Success - Main 1. Lint [554.276731ms]

[CI/Lint, test, build] ⭐ Run Main 2. Test
[CI/Lint, test, build]   | > cicd-learn@1.0.0 test
[CI/Lint, test, build]   | > vitest run
[CI/Lint, test, build]   |  ✓ test/greet.test.js (8 tests) 7ms
[CI/Lint, test, build]   |  ✓ test/sum.test.js (5 tests) 5ms
[CI/Lint, test, build]   |  Test Files  2 passed (2)
[CI/Lint, test, build]   |       Tests  13 passed (13)
[CI/Lint, test, build]   ✅  Success - Main 2. Test [714.244802ms]

[CI/Lint, test, build] ⭐ Run Main 3. Build
[CI/Lint, test, build]   | > cicd-learn@1.0.0 build
[CI/Lint, test, build]   | > node build.mjs
[CI/Lint, test, build]   | built dist/app.js (2887 bytes)
[CI/Lint, test, build]   ✅  Success - Main 3. Build [246.093875ms]
```

Sum of the three checks: 1.51 seconds of work. Plus install: 2.88 seconds total,
plus about 1.3s for `setup-node` and the checkout. **One machine, one install.**
Split into four jobs, each one would pay its own 1.36s install: more minutes,
more logs, and — because jobs start in parallel — about the same wall clock.

Then the artifact step, which is the simulated one:

```
[CI/Lint, test, build] ⭐ Run Main [simulated upload-artifact: dist]
[CI/Lint, test, build]   | -rw-r--r-- 1 root root 1478 Oct  8 09:26 /home/sunny/app/nimo/cicd-docs/.tmp/artifacts/dist.tar
[CI/Lint, test, build]   | SIMULATED upload of cicd-learn/dist as dist
[CI/Lint, test, build]   ✅  Success - Main [simulated upload-artifact: dist] [81.974886ms]
```

`SIMULATED` is literal, and it is the only step in this chapter that was not
really executed. What *was* really executed is that `path: cicd-learn/dist`
resolved to a directory containing the two built files, which is the part most
likely to be wrong.

Stage 2:

```
[CI/Release ready    ] ⭐ Run Set up job
[CI/Release ready    ]   🐳  docker exec cmd=[node --no-warnings -e console.log(process.execPath)] user= workdir=
[CI/Release ready    ]   ✅  Success - Set up job
[CI/Release ready    ] ⭐ Run Main Everything passed
[CI/Release ready    ]   | quality gate passed
[CI/Release ready    ]   | commit  : aa4fe9e164daa8cb6ac189d751ca2a0e15ab0b5a
[CI/Release ready    ]   | branch  : main
[CI/Release ready    ]   | event   : push
[CI/Release ready    ]   ✅  Success - Main Everything passed [58.272322ms]
[CI/Release ready    ]   ⚙  Summary - ### CI passed
[CI/Release ready    ] 
[CI/Release ready    ] This job does no work. It exists so that 'everything is green'
[CI/Release ready    ] is a thing you can attach other things to.
[CI/Release ready    ] 🏁  Job succeeded
```

Now look at `workdir=` on the second line. Empty. That job never changed into
`cicd-learn`, because it has no `defaults` and no checkout. Compare with every
step in stage 1, which shows `workdir=cicd-learn`. That one word in the log is
the whole difference between the working workflow and the broken one — and in
the broken probe run the same line reads `workdir=cicd-learn` for a directory
that does not exist.

### What red looks like

**[illustrative]** — push a commit with a lint error and the shape is:

```
CI
├─ ✗ Lint, test, build   (completed in 26s)
└─ - Release ready       (skipped)
```

- `Lint` is red and **every later step is gone**: `2. Test`, `3. Build`, and
  `Upload the build output` are all skipped. Nothing is built, nothing is
  uploaded, nothing can be deployed from a build that was never attempted.
- `Release ready` is **skipped**, not passed. Skipped is grey. It is not a green
  tick, and a branch protection rule that requires `Release ready` will not be
  satisfied by a skipped job — a subtlety that bites when you first set up
  required checks, and is the reason chapter 34 says to require the *checking*
  job rather than the gate.

Both of those behaviours come from the documented semantics of step failure and
of `needs:`. The success path above was executed; **the skip path was not**, and
is marked as such.

## 5. When to use it and when NOT to

**This shape — one job, fastest first, then a gate — when:**

- **Your checks are all fast and share the same dependencies.** Lint, test and
  build here total 1.5s. One `npm ci`, one machine, no artifact between steps.
- **You are at the start, and the pipeline is red for reasons you have not
  diagnosed yet.** Fewer jobs means fewer places to look.
- **The install is expensive relative to the checks.** 1.36s to install 127
  packages versus 1.51s of checking. Every extra job repeats the bigger number.

**Split into jobs when:** a check is genuinely slow and should start while the
others run (chapter 18); you want each check to fail and be required
independently, because "Lint is red" is a better notification than "CI is red";
or a check needs a different environment, like a Node matrix (chapter 17) or a
database service container (chapter 44).

**Keep them in one job when:** they share a workspace — no artifact, no
download, and no risk of a version mismatch between the tested tree and the
built tree; or splitting would make the log harder to read, because four jobs
for four `echo`s is four notifications.

**Do NOT reach for this shape when:**

- **Nothing is being checked.** A workflow with one job that says `echo ok` is
  worse than no workflow: it looks like CI and proves nothing.

- **The gate is the *only* thing standing between a bug and production, with no
  branch protection behind it.** A `needs:` chain is an internal gate. The real
  gate on `main` is a required status check, chapter 34, and it lives in the
  repository settings, not in this file. Do not describe this workflow as
  "protection".

- **You are tempted to add `if: always()` to the gate "so it always reports".**
  That removes the gate. Chapter 19.

- **You have four slow checks on a big project.** One job means the slowest
  check plus the total of the rest, serialised. At that size, split.

## 6. Common mistakes

- **`defaults.run.working-directory` at workflow level in a file that has a job
  with no checkout.** Symptom: a job that contains nothing but `echo` fails with
  a `chdir` error, or on a hosted runner with
  `cd: cicd-learn: No such file or directory`. The other jobs are green, which
  makes it look unrelated. Fix: scope `defaults` to the jobs that check out,
  as this file does. **This is the single most valuable thing in this chapter.**

- **Splitting lint, test and build into three jobs because they are "different
  concerns".** Symptom: three times the install time, three times the minutes,
  three notifications, and no wall-clock gain because jobs were parallel anyway.
  Split by dependency, not by tidiness.

- **`needs: ['Lint, test, build']` — the job *name* instead of the job *id*.**
  Symptom: the workflow is invalid, or the dependency silently does nothing.
  Only ids work in `needs:`. Chapter 02.

- **`path: dist` on the upload step in a file with `working-directory:
  cicd-learn`.** Symptom: `No files were found with the provided path`, or an
  artifact containing the wrong thing. `defaults` does not apply to `with:`
  inputs; action paths resolve from the workspace root.

- **`if-no-files-found: warn` as a default.** Symptom: the build produced nothing
  and the artifact step is still green. `error` makes a missing artifact a
  failure, which is what you want. Same class of bug as `if: always()` on the
  gate: `release-ready` runs even when `quality` is red, prints "quality gate
  passed", and you believe it. Chapter 19.

- **Reordering to test → lint → build because "tests matter more".** Symptom: a
  syntax error surfaces as a module-load crash in an unrelated test file, and the
  person debugging it blames the test runner for an hour. Build before test is
  the same class of mistake: you burn bundling time on code that is about to
  fail, and the log ends with an error that is not the real problem.

- **Forgetting `timeout-minutes: 10`.** Chapter 13 is the reason. In a single
  job, one hang blocks the gate as well as the check.

- **Trusting the gate as security.** A `needs:` chain is only as strong as the
  branch protection rule behind it, and a workflow file in a pull request can be
  edited by the pull request. Chapter 34 and chapter 25.

- **Running the whole pipeline on every branch and every push.** Two of those
  four steps are usually not needed on a documentation-only change. Chapter 06
  for path filters.

## 7. Try it yourself

**Exercise: reproduce the `defaults` bug, see the failure, fix it, and then break
the gate on purpose.** Three experiments, all on the real file, all locally.

1. **Reproduce the trap.** Copy the workflow and move `defaults` out of the job
   to workflow level. Use `verify.sh`, not `run-workflow.sh`: `act` cannot run
   `actions/upload-artifact@v7`, so with `run-workflow.sh` the `quality` job dies
   on the upload step and the run never reaches the interesting failure.
   `verify.sh` detects that and re-runs with the upload simulated.

   ```bash
   mkdir -p .tmp
   python3 - <<'EOF'
   src = open('.github/workflows/15-ci-pipeline-order.yml').read()
   scoped = """    defaults:
      run:
        working-directory: cicd-learn
"""
   assert scoped in src
   broken = src.replace(scoped, '')
   broken = broken.replace(
       "jobs:\n",
       'defaults:\n  run:\n    working-directory: cicd-learn\n\njobs:\n',
       1,
   )
   open('.tmp/probe-defaults.yml', 'w').write(broken)
   EOF
   ./scripts/verify.sh .tmp/probe-defaults.yml '' push probe-defaults
   ```

   Watch: `Lint, test, build` succeeds, `Release ready` fails on a step made of
   `echo`. Read the failure text again:

   ```
   OCI runtime exec failed: exec failed: unable to start container process: chdir to cwd (".../cicd-learn") set in config.json failed: no such file or directory
   ```

   Ask yourself the question that will save you an hour later: *which line of
   this workflow makes that path exist?* The answer is `actions/checkout`, and
   the broken job does not have one.

2. **Fix it and prove the fix.** Keep `defaults` inside `quality` only, restore
   the original file, and run it:

   ```bash
   ./scripts/verify.sh .github/workflows/15-ci-pipeline-order.yml '' push ci15
   ```

   Both jobs green. Now prove you understand *why*, not just that it works: add a
   `run:` step to `release-ready` that prints `pwd`. It prints the workspace
   root, because that job has no `defaults`. Every `run:` step in `quality`
   prints `.../cicd-learn`. One word of `defaults` per job, doing exactly what
   it says.

3. **Break the gate deliberately.** Swap `1. Lint` and `3. Build` so the build
   runs first, and introduce a real lint error in `src/sum.js` (add
   `var x = 1;`). Run it and answer two questions: which step is red and which
   never ran, and did `release-ready` run, get skipped, or pass?

   Correct answers: lint is red; `npm test` and `npm run build` never ran; the
   gate is **skipped**. Skipped is not passed. Put the order back and remove the
   `var`.

```bash
rm -f .tmp/probe-defaults.yml
```

**Hint:** `./scripts/run-workflow.sh` prints `workdir=` for every step. `grep` for
it and you can see which steps had a `working-directory` at all:

```bash
./scripts/run-workflow.sh .github/workflows/15-ci-pipeline-order.yml 2>&1 | grep -o 'workdir=[^ ]*' | sort | uniq -c
```

**What this exercise proves:** the `defaults` failure and its cause; that the
fix is per-job scoping; that a failing step skips the rest of the job; that
`needs:` skips the gate. **What it cannot prove:** that the `upload-artifact`
step really uploads (it was simulated — `act` cannot speak the v7 artifact
protocol), that `retention-days: 7` is honoured, that a *pull request* run
behaves the same as this `push` run, or that a skipped job fails a required
check. All four need a hosted run against a real repository.

## 8. Next

You have a working CI pipeline. It is also slow in a way you have probably
already noticed: the same 127 packages are downloaded on every single push.

Chapter 16 fixes that, and — more usefully — teaches you how to prove the cache
hit from the log, because "I enabled a cache" and "the cache is being used" are
different claims.

→ [16 — Caching dependencies](16-caching.md)