# 18 — Job dependencies and parallelism

> **Verification.** The workflow in this chapter is
> `.github/workflows/18-parallelism.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/18-parallelism.yml "" push ch18`,
> and the full log is at `docs/_logs/ch18.log`. Every log excerpt in section 4
> is quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/18-parallelism.yml (5 job(s))`.
>
> **What this local execution cannot prove.** `act` does reproduce the job
> graph, the parallel start, and the `needs:` ordering, and it does reproduce
> the `needs.<job>.result` values. What it cannot prove is GitHub's
> concurrency and queuing behaviour when a repository has more runs than
> runner slots, the exact wall-clock overlap of parallel jobs on hosted
> runners, or the Actions tab's visual grouping of a dependency graph. The
> ordering and the values are real and measured; the scheduling is not.

---

## 1. Simple explanation (like I'm 7)

A factory has several workbenches. The rule of the factory is simple: if two
benches do not need each other's work, they start at the same time. If one
bench needs the result from another, it waits, patiently, until that bench
finishes and hands over a note.

That is **parallelism and dependencies**. By default, every job in a workflow
is independent, so they all start together on separate machines. You make one
job wait for another with `needs:`. The waiting is the only thing `needs:` does
— it does not move files, it does not share a desk, it only says "not until
that one is done".

The beginner trap is thinking `needs:` is a file transfer. It is not. It is a
queue ticket. Files travel as artifacts (chapter 20) or as job outputs (small
values, this chapter).

## 2. Real name

### Parallel (by default)

Jobs in the same workflow with no `needs:` run at the same time on separate
runners. There is no central queue inside one workflow; GitHub starts them all
as soon as a runner is free. Total wall time is the duration of the slowest
job, not the sum.

### `needs:`

Declares that a job depends on one or more other jobs. The dependent job does
not start until every job in its `needs:` list has finished. Accepts a single
id or a list: `needs: [lint, test, bundle]`.

Two consequences, and both surprise people:

1. **Ordering.** The dependent job waits.
2. **Gating.** A job with `needs:` is **skipped** if any of its dependencies
   failed or was skipped, unless you override that with `if:`. `needs:` does
   not mean "after"; it means "after, and only if they passed".

### Job output

A small value (a version, a byte count, a URL) handed from one job to another
through `outputs:` at job level and the `needs` context. Written from a step
with `echo "key=value" >> "$GITHUB_OUTPUT"` and an `id:` on that step. The
receiving job reads `${{ needs.<job>.outputs.<key> }}`.

Job outputs cross the machine boundary as text. They are for values, not files.

### `needs.<job>.result`

A string describing how the dependency finished: `success`, `failure`,
`skipped`, or `cancelled`. Available in the dependent job even when it was
skipped, which is what makes `if: always()` useful (see below). This is the
single most useful debugging value in a multi-job workflow.

### `always()`, `success()`, `failure()`, `cancelled()`

Status functions usable in `if:`. Chapter 19 covers them fully; the ones you
need here:

- `always()` — run regardless of whether dependencies succeeded, failed,
  were skipped, or were cancelled.
- `!cancelled()` — run unless the whole run was cancelled. Gentler than
  `always()`, because it still respects a manual cancellation.

### `if:` on a job

Same `if:` as on a step, evaluated before the job starts. The most common use
here is `if: always()` on a job that must run even when a dependency failed.

### Job-level `outputs:` placement

Job-level keys live beside `runs-on`, never inside `steps:`. The legal keys
inside a `steps:` list are `name`, `uses`, `run`, `with`, `if`, `id`, `env`,
`shell`, `working-directory` and `continue-on-error`. `outputs:` is not one of
them. Putting it between two steps produces a YAML parse error:

```
expected <block end>, but found '?'
```

This is a real, confusing, common error, and it is quoted from the parser
message the workflow file itself documents.

## 3. Workflow example

This is the complete `.github/workflows/18-parallelism.yml` from this
repository.

```yaml
name: Job dependencies and parallelism

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── Three independent jobs: they run at the same time ─────────────────────
  # No `needs:` anywhere means "I do not depend on anything", so all three start
  # the instant the workflow starts. Total wall time = the slowest one.
  lint:
    name: lint
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

  test:
    name: test
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
      - run: npm test

  # ── A job that waits, and takes an input from the job it waits for ────────
  # `needs:` has two jobs: it waits, and it grants access to the `needs` context.
  # Crucially it does NOT grant access to the FILES. Chapter 02.
  bundle:
    name: bundle
    runs-on: ubuntu-24.04
    # Job-level outputs live HERE, beside runs-on, NOT between steps. The keys
    # legal inside a `steps:` list are only name, uses, run, with, if, id, env,
    # shell, working-directory and continue-on-error. Putting `outputs:` between
    # two steps is a YAML error, and a confusing one:
    #   expected <block end>, but found '?'
    outputs:
      bytes: ${{ steps.build.outputs.bytes }}
    # Block style, matching the other jobs. A one-line flow mapping
    # (`defaults: { run: { ... } }`) is legal YAML, but mixing it with block
    # style in one file is how indentation bugs hide.
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

      - name: Test first, so we never bundle code that fails tests
        run: npm test

      - name: Build and report the size
        id: build
        run: |
          npm run build
          echo "bytes=$(wc -c < dist/app.js)" >> "$GITHUB_OUTPUT"

      - name: Save it for other jobs
        uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 7

  # ── Waiting for ALL of several jobs ───────────────────────────────────────
  report:
    name: report
    # Needs all three. This job is skipped if ANY of them fails or is skipped.
    needs: [lint, test, bundle]
    runs-on: ubuntu-24.04
    steps:
      # No checkout needed, and no `defaults.run.working-directory`: a
      # subdirectory that does not exist yet would break every step. Chapter 15
      # shows the failure this avoids.
      - name: Everything that could fail, succeeded
        run: |
          echo "lint   : ok"
          echo "test   : ok"
          echo "bundle : ok, dist/app.js is ${{ needs.bundle.outputs.bytes }} bytes"
          echo
          echo "needs.lint.result  = ${{ needs.lint.result }}"
          echo "needs.test.result  = ${{ needs.test.result }}"
          echo "needs.bundle.result= ${{ needs.bundle.result }}"
          {
            echo "### Parallelism"
            echo ""
            echo "- \`lint\`, \`test\`, \`bundle\` ran in parallel"
            echo "- \`report\` waited for all three"
            echo "- bundle's output crossed the job boundary: \`${{ needs.bundle.outputs.bytes }}\` bytes"
          } >> "$GITHUB_STEP_SUMMARY"

  # ── Waiting for ONE job but tolerating its failure ────────────────────────
  optional-report:
    name: optional-report (runs even if lint fails)
    # Without `if`, a job whose dependency failed is SKIPPED. This is the most
    # common surprise in Actions: `needs: [lint]` does not mean "after lint",
    # it means "after lint, and only if lint passed".
    needs: [lint]
    # `always()` runs the job regardless of whether the dependencies succeeded,
    # were skipped, or failed. `!cancelled()` is the gentler version: it runs
    # unless someone cancelled the whole run.
    if: always()
    runs-on: ubuntu-24.04
    steps:
      - name: Runs either way
        run: |
          echo "lint result: ${{ needs.lint.result }}"
          echo "Possible values: success, failure, skipped, cancelled"
          # needs.lint.result is a string you can branch on, which is how you
          # write "post a comment when CI fails".
```

## 4. What I should see

### The parallel start, from a real run

`docs/_logs/ch18.log` is a run of this chapter's workflow. The first three jobs
start together, before any of them has finished installing:

```
[Job dependencies and parallelism/lint  ] ⭐ Run Set up job
[Job dependencies and parallelism/bundle] ⭐ Run Set up job
[Job dependencies and parallelism/test  ] ⭐ Run Set up job
```

All three containers are created in the same second. `lint`, `test` and `bundle`
have no `needs:`, so nothing waits for anything. That interleaving in the log is
the visual proof of parallelism: three separate machines, three separate
installs, all at once.

### The job that waits

`bundle` does depend on something internally (it runs `npm test` first), but as
a job it starts in parallel with `lint` and `test`. The job that actually waits
is `report`, which needs all three:

```
[Job dependencies and parallelism/report                                   ] ⭐ Run Main Everything that could fail, succeeded
[Job dependencies and parallelism/report                                   ]   | lint   : ok
[Job dependencies and parallelism/report                                   ]   | test   : ok
[Job dependencies and parallelism/report                                   ]   | bundle : ok, dist/app.js is 525 bytes
```

`report` prints `525` bytes, which is the value `bundle` computed and handed over
through `needs.bundle.outputs.bytes`. That number crossed a machine boundary as
text, not as a file. (The file itself travelled separately, as the `dist`
artifact.)

### The `needs.<job>.result` values

Same step, three lines lower:

```
[Job dependencies and parallelism/report                                   ]   | needs.lint.result  = success
[Job dependencies and parallelism/report                                   ]   | needs.test.result  = success
[Job dependencies and parallelism/report                                   ]   | needs.bundle.result= success
```

Those are the real strings GitHub provides. They are `success` here because all
three dependencies passed. On a red run they would read `failure`, and a
skipped dependency would read `skipped`. Branch on these in `if:` conditions
rather than re-running the check.

### The job that runs even when a dependency fails

`optional-report` needs `lint` but does not require it to have passed:

```
[Job dependencies and parallelism/optional-report (runs even if lint fails)]   | lint result: success
[Job dependencies and parallelism/optional-report (runs even if lint fails)]   | Possible values: success, failure, skipped, cancelled
```

Because `lint` passed here, the value is `success`. The point of the job is that
it ran at all: with `needs: [lint]` and no `if:`, a failed `lint` would have
**skipped** this job entirely. With `if: always()`, it runs and can report what
happened. That is how you post a comment, upload a log, or notify a channel when
CI fails without making the notification itself depend on CI succeeding.

### The artifact crossing the boundary

`bundle` uploads `dist`, and `consume` (in chapter 20) downloads it. In this
workflow the upload step is visible:

```
[Job dependencies and parallelism/bundle]   | SIMULATED upload of cicd-learn/dist as dist
```

The simulated upload is act's stand-in for the real artifact service; on GitHub
the same step reports `Total size: 12.4 kB` and a download link in the run
summary. The mechanism is identical either way.

## 5. When to use it and when NOT to

**Use `needs:` when:**

- **One job genuinely needs another's result.** Build depends on test, deploy
  depends on build. Serialising is the price of correctness.
- **You want a gate.** `report` needing all three means a failure in any of
  them stops the summary from claiming success.
- **You are passing a small value.** A version number, a byte count, a
  computed hash. Job outputs are the right tool; artifacts are for files.
- **You want a job to run on failure.** `optional-report` with `if: always()`
  is the pattern for "always tell me what happened".

**Do NOT reach for `needs:` when:**

- **The jobs are independent.** Lint and test do not depend on each other, so
  they should not wait. Serialising independent checks triples your wall time.
- **You think it moves files.** It does not. `needs:` orders jobs; artifacts
  move data. Expecting files to appear because of `needs:` is the number one
  confusion in multi-job workflows.
- **You chain five jobs for tidiness.** Five machines, five installs, five
  minutes minimum. Split by dependency, never by organisation. Put steps in one
  job when they share a machine.
- **You use `always()` on a job that should respect cancellation.** `always()`
  runs even after a manual cancel. Use `!cancelled()` unless you truly want
  "no matter what".

## 6. Common mistakes

- **Putting `outputs:` between steps.** Symptom: `expected <block end>, but
  found '?'` at parse time, before anything runs. Fix: move `outputs:` up to
  job level, beside `runs-on`. The legal keys inside `steps:` are `name`,
  `uses`, `run`, `with`, `if`, `id`, `env`, `shell`,
  `working-directory` and `continue-on-error`.
- **Expecting `needs:` to transfer files.** It does not. Symptom: `npm ci`
  succeeds in job B but the build output from job A is missing. Fix: upload an
  artifact in A, download it in B.
- **Forgetting that `needs:` gates on success.** `needs: [lint]` means "after
  lint, and only if lint passed". Symptom: a reporting job that never runs on
  the failures you most want it to report. Fix: add `if: always()`.
- **Reading `needs.x.outputs.y` when `x` was skipped.** The output is empty
  and the expression evaluates to `''`. Symptom: a step that prints an empty
  value and passes anyway. Fix: check `needs.x.result` first.
- **Mixing up job id and job name.** `needs: [Lint]` does not work; only the
  id works. `needs: [lint]`. Spaces in ids need quoting.
- **Chaining jobs that could be steps.** A job with one step costs a whole
  machine. If two steps need the same checkout and install, they belong in one
  job.
- **Forgetting `timeout-minutes` on a waiting job.** A job blocked on a hung
  dependency can burn hours. Set it on every job.
- **Using `needs:` with a matrix and expecting one combination.** A matrix job
  has one id for all its combinations, so `needs: [matrix]` waits for every
  combination. There is no "wait for Node 22 only".

## 7. Try it yourself

**Exercise: prove that `needs:` orders but does not move data.**

1. Run the real workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/18-parallelism.yml "" push ch18
   ```

   Find the three `Set up job` lines starting together, then the `report` job
   starting after them, then `optional-report` printing `success`.

2. **Prove ordering without data transfer.** Add a `writer`/`reader` pair as
   in chapter 02, but with `needs: [writer]` on `reader`, and no artifact.
   Push. `reader` still fails with `No such file or directory`, even though it
   waited. `needs:` ordered the jobs; it did not move the file.

3. **Prove the gating.** Break `lint` on purpose (add a syntax error to a
   source file in a throwaway branch). Push. Watch `report` get **skipped**
   (not failed), and `optional-report` run anyway and print
   `lint result: failure`. That is the difference between `needs:` alone and
   `needs:` plus `if: always()`.

4. **Break `outputs:` placement.** Move the `outputs:` block in `bundle` to
   between the `npm ci` and `Test first` steps. Run the validator:

   ```bash
   python3 scripts/validate-workflows.py
   ```

   It fails to parse with `expected <block end>, but found '?'`. Move it back.

5. **Break the value.** Change `echo "bytes=$(wc -c < dist/app.js)"` to a
   hardcoded `echo "bytes=0"`. Run. `report` now prints `0 bytes`, proving
   the value really did cross from `bundle` — and that a wrong value crosses
   just as happily as a right one. There is no type checking on job outputs.

**Hint:** to see the dependency graph locally, run one job at a time:

```bash
./scripts/run-workflow.sh .github/workflows/18-parallelism.yml report push
```

`act` will still run the dependencies first, because it reads `needs:`.

**What this exercise proves:** parallel start, ordering, gating, the
`always()` escape hatch, `outputs:` placement, and value transfer. **What it
cannot prove:** hosted-runner scheduling, queue contention, or the Actions
tab's dependency graph rendering. Those need a hosted run.

## 8. Next

You can now order jobs and pass values between them. The next question is how
to decide whether a job or step runs at all, based on the branch, the event, or
the state of earlier steps.

→ [19 — Conditionals](19-conditionals.md)
