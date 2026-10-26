# 48 — Re-running jobs

> **Verification.** This is a concept chapter. There is no workflow executed for
> it: re-running, re-running on a different runner, and SSH debugging are
> GitHub-hosted features that `act` cannot reproduce (no Actions tab, no "Re-run"
> button, no live runner to SSH into). The GitHub-only parts are marked
> `[read-only example]` and sourced from the GitHub documentation. The local,
> runnable counterparts are `./scripts/verify.sh` (re-run a workflow locally) and
> `act --reuse` (keep a container alive between runs). `python3 scripts/validate-workflows.py`
> is the check applied to the YAML shown in section 3.

---

## 1. Simple explanation (like I'm 7)

Sometimes the smoke alarm goes off because of burnt toast, not a fire. You do not
rebuild the kitchen. You open a window, fan the smoke away, and check whether it
was really a fire. If it was just toast, you carry on. If it was a fire, you
call the fire brigade and start over from a clean kitchen.

CI works the same way. A red build is sometimes a real bug in your code, and
sometimes a flaky test, a dead runner, or a network blip. Re-running is the
"open a window" move: try the same work again without changing anything. If it
goes green, it was toast. If it stays red, it was a fire, and you need a real
fix or a clean re-run from scratch.

The three buttons in the Actions tab map to three different levels of "start
over", and picking the wrong one either wastes minutes or hides the real
problem.

## 2. Real name

### Re-run failed jobs

Re-runs **only the jobs that failed** in the previous run. Successful jobs keep
their logs and their outputs; their steps are not executed again. This is the
cheapest re-run and the right first move for a flaky failure.

Two consequences that surprise people:

- **It does not re-checkout the code.** The failed job's workspace is gone (the
  runner was deleted), so the job starts fresh and checks out again — but any
  job that *succeeded* is not re-executed, so its artifacts and outputs are
  reused. If the failure was caused by a stale artifact from an earlier job, a
  "re-run failed jobs" will not fix it; you need a full re-run.
- **It does not re-run jobs that were skipped.** A job with `if: failure()` that
  did not fire stays skipped.

### Re-run all jobs

Re-runs the entire workflow from scratch, every job, every step. Use this when
the failure might be in a job that succeeded but produced a bad artifact, or
when you want a clean slate. It costs the full minute allowance of the workflow.

### Re-run on a different runner

A variant of "re-run failed jobs" that requests a **new runner instance** for
each failed job. Use it when you suspect the runner itself: a poisoned cache,
a stale toolchain image, a disk-full machine, or a hardware flake. GitHub picks
a fresh VM; nothing from the previous attempt is reused except the source commit.

### Re-run a single job

The Actions tab also lets you re-run one job by name, which is narrower than
"re-run failed jobs". Useful when a matrix leg failed and the others passed.

### Debugging with SSH (tmate)

When a failure only reproduces on the hosted runner and `act` cannot reproduce
it, the last resort is to pause the job mid-flight and SSH into the live
runner. The standard tool is `mxschmitt/action-tmate`, which opens a tmate
session and prints an SSH command in the log. You connect, poke around the
filesystem and environment, then let the job finish.

This is `[read-only example]`: it needs a real GitHub runner, a real network
path back to it, and the workflow to be triggered on GitHub. It cannot be
verified locally. The free alternative is to reproduce with `act`, which drops
you into the same container, or to add `echo` debugging steps and re-run
locally.

### Re-run attempt and job identity

Every re-run increments `github.run_attempt` (1 for the first run, 2 for the
first re-run, …). Workflows that upload artifacts or create releases often
gate on this to avoid publishing twice. A re-run keeps the same `github.run_id`
and the same commit; only the attempt number changes. Artifacts from a re-run
overwrite the previous attempt's artifacts with the same name.

### Concurrency and re-runs

A re-run does not cancel other in-flight runs. If a newer push started a new
run while you were re-running an old one, both finish. Chapter 21's
`concurrency:` groups are what prevent that.

## 3. Workflow example

This workflow shows a normal CI pipeline plus an optional SSH-debug step that is
disabled by default. The SSH step is `[read-only example]` and is guarded by
`if: false` so it never runs unless you deliberately turn it on.

```yaml
name: Re-running jobs demo

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
  ci:
    name: CI
    runs-on: ubuntu-24.04
    timeout-minutes: 10
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

      # ── Optional: drop into a live shell on failure ────────────────────────
      # [read-only example] Needs a real GitHub runner. Disabled by default.
      # When enabled, the job pauses and prints an SSH command in the log.
      - name: Debug with SSH (disabled)
        if: false
        uses: mxschmitt/action-tmate@v3
        with:
          limit-access-to-actor: true

  # ── A job that only runs when CI fails, for diagnostics ───────────────────
  diagnose:
    name: Diagnose
    runs-on: ubuntu-24.04
    needs: [ci]
    if: failure()
    steps:
      - uses: actions/checkout@v7
      - name: Print what we know
        run: |
          echo "run id      : ${{ github.run_id }}"
          echo "run attempt : ${{ github.run_attempt }}"
          echo "CI failed; this job only exists to capture extra context."
```

Two things to notice. First, the tmate step is the **last** step of the job, so
the workspace is fully populated when you connect. Second, `limit-access-to-actor: true`
restricts the SSH session to the user who triggered the run, which is the only
safe setting on a public repository.

## 4. What I should see

### The Actions tab (GitHub-only, `[read-only example]`)

```
[read-only example] GitHub-rendered, from docs.github.com/en/actions

Run page, top right:
  Re-run all jobs          <- re-runs every job, every step
  Re-run failed jobs       <- re-runs only red jobs; green jobs keep their logs
  Re-run failed jobs on a different runner
                           <- fresh VM for each failed job

Job page, top right:
  Re-run job               <- re-runs one job by name

After a re-run:
  The run keeps the same run id; run_attempt becomes 2.
  Successful jobs show "Re-run" as their status and keep their original logs.
  Failed jobs show the new attempt's logs under "Attempt 2".
```

### The tmate session (GitHub-only, `[read-only example]`)

```
[read-only example] What the log prints when the tmate step runs

Run Debug with SSH
  ...
  Web shell: https://tmate.io/t/abc123
  SSH:       ssh abc123@nyc1.tmate.io
  ...
  Waiting for connection...          <- job pauses here until you disconnect
```

You SSH in, inspect the filesystem (`ls`, `cat`, `env`), reproduce the failure
by hand, then `exit` or disconnect. The job resumes and finishes. The session URL
is also a secret: anyone with it can run commands as the runner user, so treat
the log line as sensitive and delete the run when done.

### Locally, what you can actually do today

```bash
# Re-run a workflow locally, the free equivalent of "re-run failed jobs"
./scripts/verify.sh .github/workflows/49-cost.yml report push ch49

# Keep the container alive between runs while debugging
act -j ci --reuse

# Inspect a failed step's environment by adding echo statements and re-running
grep -n 'Failure\|exit code' docs/_logs/ch49.log
```

`act --reuse` keeps the container between invocations, which is the closest
local equivalent to "re-run on the same runner". It is not identical: `act`
bind-mounts your working directory, so files you create locally persist, which
a real runner would not. Trust the hosted run for anything about isolation.

### What a re-run does and does not change

| Thing | Re-run failed jobs | Re-run all jobs |
| ----- | ------------------ | --------------- |
| Failed jobs re-execute | yes | yes |
| Successful jobs re-execute | no (logs kept) | yes |
| Checkout happens again | for failed jobs only | yes, every job |
| `github.run_id` | unchanged | unchanged |
| `github.run_attempt` | increments | increments |
| Artifacts | overwritten with same name | overwritten with same name |
| Secrets / env | re-resolved from the store | re-resolved from the store |

## 5. When to use it and when NOT to

**Use "re-run failed jobs" when:**

- **A flaky test or a transient failure** (network, registry, runner). This is
  the cheapest re-run and the right first move.
- **You fixed nothing but suspect the runner.** Re-run on a different runner
  instead, so you do not reuse a poisoned machine.
- **A single matrix leg failed.** Re-run that job by name rather than the
  whole matrix.

**Use "re-run all jobs" when:**

- **A successful job produced a bad artifact** that a downstream job consumed.
  "Re-run failed jobs" will not rebuild it.
- **You changed a secret or variable** and want every job to pick up the new
  value.
- **You want a clean slate** for a release or a deploy.

**Use SSH debugging when:**

- **The failure only reproduces on the hosted runner** and `act` cannot
  reproduce it (toolchain, environment, or a secret-dependent step).
- **You need to inspect state that the log does not print** (a file, an env
  var, a process).

**Do NOT:**

- **Do not re-run a real bug until green.** If the code is wrong, re-running
  just delays the fix and burns minutes. Fix first, then re-run to confirm.
- **Do not re-run to "clear" a flaky test.** Quarantine it and fix it;
  re-running teaches you nothing.
- **Do not SSH into a runner that handles secrets** unless you must, and never
  leave a session open. The session has the runner's environment, including
  secrets passed via `env:`.
- **Do not publish from a re-run without checking `run_attempt`.** A re-run of a
  release workflow can publish twice. Gate publishes on `github.run_attempt == 1`
  or on a tag.
- **Do not re-run on the same runner when you suspect the runner.** Use "on a
  different runner" or you are testing the same broken machine twice.

## 6. Common mistakes

- **"Re-run failed jobs" does not re-checkout.** It re-checks out the *failed*
  job, but successful jobs' outputs are reused. A stale artifact survives.
  Symptom: the re-run is green but the deployed artifact is still old. Fix: re-run
  all jobs.
- **Confusing job status with step conclusion.** A green job can contain a red
  step (chapter 47). Re-running "failed jobs" skips it because the job is green.
  Fix: read the step conclusions, not only the job colour.
- **Publishing twice on re-run.** A release workflow that runs on every push and
  does not check `run_attempt` publishes on attempt 1 and again on attempt 2.
  Symptom: a duplicate release. Fix: gate on `github.run_attempt == 1` or on a tag.
- **Leaving a tmate session open.** The job hangs until the session ends, burning
  minutes and exposing the runner. Symptom: a run stuck at "Waiting for
  connection". Fix: disconnect when done; set a timeout on the job.
- **SSH on a public repo without `limit-access-to-actor`.** Anyone who reads the
  log can connect. Fix: always set it, and delete the run afterwards.
- **Re-running a workflow with a newer commit.** A re-run always uses the
  original commit. If you pushed a fix, push again or trigger a new run; do not
  re-run the old one.
- **Expecting "on a different runner" to change the OS.** It changes the VM, not
  the `runs-on` label. A `macos-15` re-run is still macOS.
- **Using SSH as the first debugging tool.** It is the last resort. Most failures
  are readable from the log; SSH is for when the log is not enough.

## 7. Try it yourself

**Exercise: practise the three re-run levels locally.**

1. Run the cost workflow once:
   ```bash
   ./scripts/verify.sh .github/workflows/49-cost.yml report push ch49
   ```
   Confirm green and note the step names.

2. **Simulate "re-run failed jobs".** Break one step (for example, change
   `npm run lint` to `npm run lintt`), re-run, and watch the first failing step
   stop the job. Then fix it and re-run. That is the real cycle, just done by
   editing and re-running `verify.sh` instead of clicking a button.

3. **Simulate "re-run all jobs".** Delete the local log and re-run the whole
   workflow from scratch. Compare the new log with the old one: same steps, fresh
   run, identical result. That is what "re-run all jobs" gives you on GitHub.

4. **Practise reading `run_attempt`.** Add `echo "attempt: ${{ github.run_attempt }}"`
   to a step and run it twice locally. Locally `github.run_attempt` is always 1,
   so this is a `[read-only example]` for the incrementing behaviour; on GitHub
   the second run prints 2.

5. **Inspect a live container (free alternative to tmate).** Run:
   ```bash
   act -j report --reuse
   ```
   The container stays up. `docker ps` shows it; you can `docker exec` into it and
   inspect the workspace exactly as tmate would let you. Tear it down when done:
   `docker rm -f` the container.

6. **Break it on purpose.** Publish a fake release step gated only on
   `github.event_name == 'push'` and re-run the workflow twice. Observe that a
   re-run would publish twice. Add `&& github.run_attempt == 1` to the `if:` and
   re-run: the second attempt skips the step. Revert the fake step.

**Hint:** when in doubt about whether a re-run reused stale state, "re-run all
jobs" is the safe, expensive answer. "Re-run failed jobs" is the cheap one, and
it is only safe when you are sure the successful jobs' outputs are still valid.

**Break it on purpose, the worst version:** re-run a workflow after changing a
secret in the store, using "re-run failed jobs" only. Jobs that succeeded before
never re-run, so they keep the old secret value. The re-run is green and wrong.
Fix: "re-run all jobs" whenever a secret or variable changes.

## 8. Next

You now know when to re-run, when to start over, and when to drop into a live
shell. The next chapter is about the bill that all of this generates: free
minutes, per-minute rates, OS multipliers, and how to keep the cost sane.

→ [49 — Cost and usage limits](49-cost-and-limits.md)
