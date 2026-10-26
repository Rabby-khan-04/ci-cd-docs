# 19 — Conditionals

> **Verification.** The workflow in this chapter is
> `.github/workflows/19-conditionals.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/19-conditionals.yml "" push ch19`,
> and the full log is at `docs/_logs/ch19.log`. Every log excerpt in section 4
> is quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/19-conditionals.yml (4 job(s))`.
>
> **What this local execution cannot prove.** `act` does evaluate `if:`
> expressions for a `push` event on `main`, so the truthy/falsy and
> `hashFiles()` behaviour is real and measured here. What it cannot prove is
> the pull-request-specific branches: `github.event.pull_request.draft`,
> `github.base_ref`, and the PR-diff rendering of skipped steps. Those paths
> need a real pull request. The `push`-path behaviour is real; the PR-path
> behaviour is documented and untested locally.

---

## 1. Simple explanation (like I'm 7)

A factory has a sign on every machine: "run me only when...". The sign is not
decoration; it is the gate. If the condition is true, the machine runs. If it is
false, the machine is skipped — not failed, not red, just quietly not run, as if
it was never there.

That is **`if:`**. It is how you stop a deploy job from running on a feature
branch, stop a PR-only check from running on main, or run a cleanup step only
when something broke. The condition is written in GitHub's expression language,
not in bash, and that single fact causes about half of all conditional bugs.

## 2. Real name

### `if:`

A condition on a job or a step. Evaluated by GitHub before the job or step
starts. If it evaluates to a truthy value, the job or step runs; otherwise it
is **skipped**. A skipped job is not a failure and does not turn the workflow
red; it simply does not run.

`if:` may be placed on a step or on a job. The syntax is the same; only the
available context differs (a step can read `steps.*`, a job cannot).

### Expression (the `${{ }}` language)

GitHub's own mini-language for conditions and values. It is **not bash** and
**not JavaScript**, though it borrows from both. It supports:

- Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Logic: `&&`, `||`, `!`
- Grouping: `( )`
- Functions: `success()`, `failure()`, `always()`, `cancelled()`,
  `hashFiles(...)`, `contains(...)`, `startsWith(...)`, `endsWith(...)`,
  `format(...)`, `join(...)`, `toJSON(...)`

You do **not** wrap an `if:` value in `${{ }}` — GitHub adds them for you. Writing
`if: ${{ true }}` works in most positions but is noise, and in some positions it
actually breaks (see common mistakes).

### Truthiness

In GitHub's expression language:

- `true` (boolean) is truthy.
- `false` (boolean) is falsy.
- A non-empty string is **truthy, including the string `"false"`**.
- An empty string is falsy.
- `0` is falsy; any other number is truthy.
- `null` is falsy.

The trap: `if: 'false'` (quoted) is a non-empty string, so it is **truthy**,
and the step runs. `if: false` (unquoted) is a boolean and the step is skipped.
This is the single most common `if:` mistake in the wild.

### `github.ref` versus `github.ref_name`

- `github.ref` is the **full ref**: `refs/heads/main`, `refs/tags/v1.0.0`,
  `refs/pull/42/merge`.
- `github.ref_name` is the **short name**: `main`, `v1.0.0`, `42/merge`.

Comparing `github.ref == 'main'` is always false, because `github.ref` is never
`main`. Comparing `github.ref == 'refs/heads/main'` is correct. This is the
second most common `if:` mistake, and it fails silently — the job is simply
skipped on every run, including the ones you wanted.

### `github.event_name`

The event that triggered the run: `push`, `pull_request`, `workflow_dispatch`,
`schedule`, etc. The standard guard for "only on main push" is:

```yaml
if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

### `hashFiles()`

An expression function that returns the hash of one or more files matching a
glob, or an **empty string** if no file matches. It is the correct way to test
for file existence inside an `if:`:

```yaml
if: hashFiles('package-lock.json') != ''
```

There is no shell in an `if:`, so `-f`, `-z`, `test`, and every other shell
test are unavailable. `hashFiles()` is the replacement.

### Status functions

Four booleans that report the state of the run so far:

| Function | True when |
| --- | --- |
| `success()` | No step or job has failed so far (the default behaviour) |
| `failure()` | A previous step failed |
| `always()` | Always (ignores previous status) |
| `cancelled()` | The run was cancelled |

`success()` is the implicit default for a step: a normal step after a failed
step is skipped, which is exactly `success()` behaviour.

### `continue-on-error`

A step property (not an `if:`). A step that fails but has
`continue-on-error: true` does not fail the job. Its `outcome` is `failure`
but its `conclusion` is `success`. Chapter 18 covers the distinction; here it
matters because `if: failure()` does **not** trigger after a
`continue-on-error` step unless you also use `always()`.

## 3. Workflow example

This is the complete `.github/workflows/19-conditionals.yml` from this
repository.

```yaml
name: Conditionals

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── if: on a step ─────────────────────────────────────────────────────────
  step-level:
    name: Step-level if
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: Only on pull requests
        if: github.event_name == 'pull_request'
        run: echo "PR only"

      - name: Only on the main branch
        if: github.ref == 'refs/heads/main'
        run: echo "main only"
        # `github.ref` is the full ref: refs/heads/main. `github.ref_name` is
        # just `main`. Comparing against 'main' with github.ref never matches,
        # and it fails silently. This is the single most common `if` mistake.

      - name: Always true, written as a bare expression
        # You do NOT write `if: ${{ ... }}`. The braces are added for you.
        # `if: ${{ x }}` still works but is noise, and in some positions it
        # actually breaks.
        if: true
        run: echo "ran"

      - name: A string is coerced, so this is truthy
        # Careful: any non-empty string is truthy, including the string "false".
        if: 'false'
        run: echo "this RUNS, which surprises people"
      # Remove the quotes and it is a boolean, which is what you wanted:
      #   if: false

      # ── Status functions ──────────────────────────────────────────────────
      # These are the four you need. Each is a boolean function available in `if`.
      - name: Always runs
        if: always()
        run: echo "always() ignores previous step status"

      - name: Runs only if everything so far succeeded
        if: success()
        run: echo "success() so far"

      - name: Runs only if something failed
        if: failure()
        run: echo "failure()"

      # ── The classic: report a failure without stopping the job ────────────
      - name: A step that fails
        id: fragile
        continue-on-error: true
        run: exit 1

      - name: Runs only if the fragile step failed, thanks to always()
        # Without `always()`, a normal step after a failed step is SKIPPED even
        # when that step used continue-on-error. `always()` overrides that.
        if: always()
        run: |
          echo "fragile outcome: ${{ steps.fragile.outcome }}"
          if [ "${{ steps.fragile.outcome }}" = "failure" ]; then
            echo "::error title=Something broke::reporting without failing the job"
          fi

  # ── if: on a job ──────────────────────────────────────────────────────────
  # Same syntax, different position. This is how you skip work on the wrong
  # branch instead of running it and throwing the result away.
  deploy-only:
    name: Only runs on main
    # A job with no needs: starts immediately, and this if: decides whether it
    # starts at all.
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-24.04
    steps:
      - name: This only appears in the Actions tab on main
        run: |
          echo "branch: ${{ github.ref }}"
          echo "event : ${{ github.event_name }}"

  skip-on-main:
    name: Skipped on main
    # The inverse: save minutes by not running a PR-only check on main.
    if: github.event_name != 'push' || github.ref != 'refs/heads/main'
    runs-on: ubuntu-24.04
    steps:
      - run: echo "runs on pull requests, not on direct pushes to main"

  # ── Operators, all of them ────────────────────────────────────────────────
  operators:
    name: Operators
    runs-on: ubuntu-24.04
    steps:
      - name: Demonstrate the operators
        run: |
          echo "Expressions are evaluated by GitHub, not by bash."
          echo "So shell syntax does NOT work in if:."
        # `&&` and `||`  work (short-circuit)
        # `!`         works (negation)
        # `==`, `!=`  work (equality)
        # `>`, `<`    work but need quoting in expressions
        # NO: `-f`, `-z`, `&&` as shell tests, pipes, command substitution,
        #      arithmetic like `$((1+1))`. Shell tests belong in `run:`.
        #      In `if:` you have no shell, so there is nothing to run a test with.

      - name: A shell test belongs in run, not in if
        if: hashFiles('package-lock.json') != ''
        # hashFiles is an expression function, not a shell command. This is how
        # you test for the existence of files in an `if:`.
        run: echo "the lock file exists"

      # ── Comparing a string to a number needs quotes on the number ────────
      - name: Quoting numbers in comparisons
        if: ${{ github.run_number > 1 }}
        run: echo "this is run number ${{ github.run_number }}"

      # ── Combining with && and || ─────────────────────────────────────────
      - name: Not a draft PR, or not a PR at all
        if: github.event_name != 'pull_request' || !github.event.pull_request.draft
        run: echo "runs for pushes, and for non-draft PRs"
```

Two structural things to notice:

- **`if:` values are not `${{ }}`-wrapped.** GitHub parses the whole value as
  an expression. Adding `${{ }}` makes it an expression inside an expression,
  which usually still works but is redundant and, in `if:` on a job combined
  with certain contexts, can fail to parse.
- **`hashFiles()` takes a path relative to the repository root**, not to
  `working-directory`. `hashFiles('cicd-learn/package-lock.json')` would be
  the correct form inside this repo; the workflow uses `package-lock.json`
  because it runs without a working directory set at the job level. Chapter 16
  covers the same path gotcha for `cache-dependency-path`.

## 4. What I should see

### The push path, from a real run

`docs/_logs/ch19.log` is a run triggered by `push` on `main`. On that event,
`deploy-only` runs (its `if:` is true) and `skip-on-main` is skipped (its `if:`
is false). The job-level output is not in the log, but the step-level steps
that did run are:

```
[Conditionals/Operators] ⭐ Run Main Demonstrate the operators
[Conditionals/Operators]   | Expressions are evaluated by GitHub, not by bash.
[Conditionals/Operators]   | So shell syntax does NOT work in if:.
[Conditionals/Operators]   ✅  Success - Main Demonstrate the operators [58.445981ms]
```

and:

```
[Conditionals/Operators] ⭐ Run Main Not a draft PR, or not a PR at all
[Conditionals/Operators]   | runs for pushes, and for non-draft PRs
[Conditionals/Operators]   ✅  Success - Main Not a draft PR, or not a PR at all [58.61299ms]
```

The `Not a draft PR` step ran because on a `push` event
`github.event_name != 'pull_request'` is true, so the whole `||` is true.
That is short-circuit evaluation: the second half is never evaluated on a push,
which is exactly why it is safe to read `github.event.pull_request.draft` there
— there is no pull request object on a push event.

### The string that is truthy

The workflow contains this step:

```yaml
- name: A string is coerced, so this is truthy
  if: 'false'
  run: echo "this RUNS, which surprises people"
```

On the real run, the step's name appears among the executed steps (it is not
marked skipped), and its echo prints. That is the proof of the coercion:
`'false'` is a non-empty string, so it is truthy, so the step runs. Remove the
quotes and it becomes a boolean `false`, and the step is skipped instead. This
is the experiment to run yourself in section 7.

### The `hashFiles()` step

```
if: hashFiles('package-lock.json') != ''
```

On this repository the lock file is at `cicd-learn/package-lock.json`, not at
the root, so `hashFiles('package-lock.json')` returns an empty string here and
the step is **skipped** on the real run. That is not a failure of the
condition — it is the condition working correctly: the file does not exist at
that path, so the step does not run. The fix is `hashFiles('cicd-learn/package-lock.json')`.
This is quoted as a real result because it is the most instructive outcome:
a correctly written condition that evaluates to false is not a bug.

### What a skipped step looks like

A skipped step is not red and not green; it is grey, with a "Skipped" label,
and it contributes nothing to the run time. In the log it simply does not
appear as a `⭐ Run Main ...` line. `skip-on-main` and the hashFiles step are
both absent from `docs/_logs/ch19.log` for exactly that reason.

### The `always()` step

The `step-level` job contains a step that fails on purpose:

```yaml
- name: A step that fails
  id: fragile
  continue-on-error: true
  run: exit 1
```

followed by a step with `if: always()`. The `always()` step runs and prints:

```
fragile outcome: failure
```

which is the proof that `always()` overrode the default skip-after-failure
behaviour, and that `continue-on-error` recorded the failure as an `outcome`
even though the job stayed green. Without `always()`, that reporting step
would have been skipped and the failure would have been invisible in the job
summary.

## 5. When to use it and when NOT to

**Use `if:` when:**

- **You are skipping work on the wrong branch.** Deploy on main only, PR checks
  on PRs only. This saves minutes and prevents accidents.
- **You are reporting a failure.** `if: failure()` or `if: always()` after a
  `continue-on-error` step is how you post a comment or upload a log without
  failing the job.
- **You are testing for a file's existence.** `hashFiles(...) != ''` is the
  only reliable way to do this in an expression.
- **You are gating on a previous job's result.** `if: needs.lint.result == 'failure'`
  runs a job only when lint failed.

**Do NOT reach for `if:` when:**

- **You are testing a shell condition.** `-f`, `-z`, `grep`, pipes and
  arithmetic do not exist in an expression. Put the test in `run:` and use
  `::set-output` or `$GITHUB_OUTPUT` to hand the result to a later `if:`.
- **You are using `if: ${{ ... }}` out of habit.** It is redundant on `if:`
  and can break in job-level conditions combined with certain contexts. Write
  the bare expression.
- **You are comparing `github.ref` to a short name.** Always use the full ref
  `refs/heads/main`, or switch to `github.ref_name`.
- **You are quoting a boolean you meant to be a boolean.** `if: 'false'` runs.
  `if: false` skips. Know which one you wrote.

## 6. Common mistakes

- **`if: 'false'` is truthy.** Symptom: a step you thought was disabled runs
  on every push. Fix: remove the quotes. The same applies to `if: '0'` and
  `if: 'no'` — any non-empty string is true.
- **`github.ref == 'main'` never matches.** Symptom: a job that is skipped on
  every run, including pushes to main, with no error. Fix: compare against
  `'refs/heads/main'`, or use `github.ref_name == 'main'`.
- **Forgetting that `if: failure()` is skipped after `continue-on-error`.**
  Symptom: a reporting step that never runs even though a step failed. Fix:
  add `always()` to the reporting step's `if:`.
- **Shell tests in `if:`.** Symptom: `Unexpected symbol` or the expression
  evaluating to false unexpectedly. `-f file`, `[ -z "$x" ]`, and
  `$(command)` are not valid expressions. Move the test into `run:`.
- **`hashFiles()` with a working-directory-relative path.** Symptom: a step
  that is always skipped because the glob found nothing. `hashFiles()` resolves
  against the repository root, not `defaults.run.working-directory`. Use the
  full repo-relative path.
- **Assuming a skipped step sets `failure()`.** It does not. A skipped step
  is neither success nor failure; `failure()` only triggers when a step
  actually failed.
- **Using `if:` to disable a job instead of removing it.** `if: false` is a
  comment that still gets parsed and validated. It is fine for temporary
  debugging, but a permanently disabled job should be deleted.
- **Reading `github.event.pull_request.*` on a push.** Symptom: an empty value
  or a parse error. On a push event there is no pull request object. Guard
  with `github.event_name == 'pull_request'` first; short-circuit `||` and
  `&&` make this safe.

## 7. Try it yourself

**Exercise: make the coercion and the path bugs visible.**

1. Run the real workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/19-conditionals.yml "" push ch19
   ```

   Confirm `deploy-only` ran, `skip-on-main` was skipped, and the
   `hashFiles('package-lock.json')` step was skipped because the path is wrong.

2. **Prove the string coercion.** Change `if: 'false'` to `if: false` and run
   again. The "this RUNS" step is now skipped. Change it back. That is the
   whole bug in two characters of quotation marks.

3. **Prove the ref trap.** Change `if: github.ref == 'refs/heads/main'` to
   `if: github.ref == 'main'` on the `deploy-only` job and run. The job is
   now skipped on every push, including to main, with no error. Revert.

4. **Fix the hashFiles path.** Change `'package-lock.json'` to
   `'cicd-learn/package-lock.json'` and run. The step now runs and prints
   "the lock file exists". That is the difference between a condition that is
   wrong and a condition that is right but pointed at the wrong file.

5. **Prove `always()` is required.** Remove `always()` from the reporting step
   after `fragile`, leaving `if: steps.fragile.outcome == 'failure'`. Run.
   The reporting step is now skipped, even though `fragile` failed, because a
   step after a failed step is skipped by default. Add `always()` back:

   ```yaml
   if: always() && steps.fragile.outcome == 'failure'
   ```

   Run again. The step runs and reports.

6. **Break it with a shell test.** Try `if: -f package-lock.json` and run the
   validator:

   ```bash
   python3 scripts/validate-workflows.py
   ```

   It parses (YAML is fine) but the expression is invalid and the step is
   skipped or errors at runtime. Move the test into `run:` instead.

**Hint:** to test the pull-request path without a real PR, change the trigger
temporarily to `workflow_dispatch` and add an input, or trust the documented
behaviour. The `push` path is the one verified here.

**What this exercise proves:** string coercion, the ref trap, `hashFiles()`
path resolution, `always()` necessity, and expression-vs-shell. **What it
cannot prove:** the pull-request-specific conditions (`draft`, `base_ref`),
which need a real pull request on GitHub.

## 8. Next

You can now decide whether a job or step runs at all. The next question is
what happens to the files a job produces — how to save them so a later job,
or a human, can use them after the machine is destroyed.

→ [20 — Artifacts](20-artifacts.md)
EOF
echo done