# 08 — Jobs and steps

> **Verification.** The workflow in this chapter is
> `.github/workflows/08-jobs-and-steps.yml`, run twice with `act` 0.2.89:
>
> - `scripts/verify.sh .github/workflows/08-jobs-and-steps.yml both push ch08-steps`
>   → `docs/_logs/ch08-steps.log` (exit 0)
> - `scripts/verify.sh .github/workflows/08-jobs-and-steps.yml reader push ch08-reader`
>   → `docs/_logs/ch08-reader.log` (exit 1, and the reason is quoted in full)
>
> The `writer` job was not run, because its only purpose is to be the other half
> of the `reader` job's experiment, and that experiment needs a *fresh* machine
> — which local `act` cannot give you (see section 4). Every log line quoted in
> this chapter comes from those two files.
>
> What local execution cannot prove: that jobs really do get isolated machines
> (`act` copies your working directory in, so a later job can see an earlier
> job's files unless `--bind` is off, which it is by default), the exact wording
> of GitHub's `Error: Process completed with exit code N`, step-level
> `steps.<id>.conclusion` (as opposed to `outcome`, which *is* shown here), and
> how a partially-failed step is coloured in the Actions tab. Those are marked
> where they appear.

---

## 1. Simple explanation (like I'm 7)

Inside the rented room from the last chapter, you are given a **workbench**.

The workbench is one **job**. On it there is a list of things to do, one after
another, and that list is the job's **steps**.

Three rules, and they are the whole chapter:

1. **The list runs in order.** Step 1 finishes before step 2 starts. If step 3
   stops early with an error, steps 4, 5 and 6 never happen at all.
2. **The steps share the same table.** Anything step 1 writes to the table is
   still there when step 2 opens the bench. Same bench, same table. You do not
   pass files between steps; you just leave them there.
3. **But each job gets its own room.** If your workflow has two jobs, that is
   *two* workbenches in *two* rooms. A file on bench one is not on bench two.
   Not because the rules are unfair, but because bench two is in a different
   room and nobody carried anything.

Most beginner bugs are rule 2 understood and rule 3 forgotten.

And one more thing about the list: a step can be marked "keep going even if I
fail". Then the step itself is red in the notebook, but the list carries on and
the bench still closes successfully. That looks like a bug and is not one, and
section 4 shows it happening.

## 2. Real name

### Job

A unit of work that gets its own machine. The keys you will meet in this course:

| Key | What it does |
| --- | ------------ |
| `runs-on:` | Which machine. Chapter 07 |
| `steps:` | The ordered list. Required |
| `name:` | The human label shown in the Actions tab |
| the key beside `name:` | The **id** — the only name `needs:` and `steps.*` can use |
| `needs:` | Other jobs that must finish first. Chapter 18 |
| `if:` | Whether this job runs at all. Chapter 19 |
| `env:` | Environment variables for every step in the job |
| `permissions:` | What the job's `GITHUB_TOKEN` may do. Chapter 25 |
| `timeout-minutes:` | Kill the job after N minutes. Default 360 |
| `continue-on-error:` | Let the job fail without failing the run |
| `outputs:` | Values to hand to other jobs. Sits beside `runs-on:` |
| `strategy:` | Matrix. Chapter 17 |
| `container:` / `services:` | Run the job inside a container |
| `defaults.run:` | Default shell and working directory for `run:` steps |

Jobs with no `needs:` between them **run in parallel, each on its own machine.**

### Step

One entry in `steps:`. A step has **either** `run:` **or** `uses:`, never both:

| Key | What it does |
| --- | ------------ |
| `name:` | Label in the Actions tab |
| `id:` | Makes the step addressable as `steps.<id>.outputs.*` |
| `run:` | A shell command |
| `uses:` | Someone else's action, `owner/repo@version` |
| `with:` | Inputs to that action |
| `env:` | Environment variables for this step only |
| `if:` | Whether this step runs |
| `shell:` | Override the shell. Default on Linux: `bash` |
| `working-directory:` | Run from somewhere other than the workspace |
| `timeout-minutes:` | Kill just this step after N minutes |
| `continue-on-error:` | A failed step does not fail the job |

### `run:` and the shell that reads it

`run:` is a string, and the runner writes it to a temporary file and hands that
file to a shell. On a Linux runner with no `shell:` key, that shell is:

```
bash -e {0}
```

`-e` is the important half: **the script aborts at the first command that exits
non-zero.** So in a multi-line `run:`, a failure in line 2 means lines 3 to the
end never run, and the step fails.

What `-e` does *not* do, and this bites everyone:

- It does not set `pipefail`. In `cmd1 | cmd2`, the exit code is `cmd2`'s, so
  `false | true` exits 0 and the step passes.
- It does not care about a command whose output you meant to inspect.

If you want either, write `set -euo pipefail` as the first line of the script,
which is what this course's workflows do.

### `uses:` and `with:`

`uses:` is a reference to code someone else wrote, addressed
`owner/repository@version`:

```yaml
- uses: actions/checkout@v7
- uses: actions/setup-node@v7
  with:
    node-version: '22'
    cache: 'npm'
```

`with:` supplies that action's declared inputs, named exactly as in the action's
own `action.yml`. Typo a key and the action silently ignores it — there is no
"unknown input" error, only an output that stays at its default. Chapter 09.

The version must be pinned: `@v7`, not bare `@checkout` and never `@main`. A
moving ref means your pipeline runs different code tomorrow without a commit.
Chapter 39 covers full SHA pinning.

### Order and the filesystem

- Steps in a job: **sequential, one machine, one filesystem.** This is the only
  ordering guarantee in Actions, and it is a total one.
- Jobs in a workflow: **parallel, separate machines, separate filesystems.**

There is no implicit ordering between jobs beyond `needs:`, and `needs:` orders
them without moving any data. Ordering and data transfer are different problems
(Chapter 02's proof; Chapter 20's fix).

### Handing values between steps: `id:` and `$GITHUB_OUTPUT`

A step can publish a value. The current, supported way:

```yaml
- name: Produce a value for later steps
  id: produce
  run: |
    echo "computed=42" >> "$GITHUB_OUTPUT"
```

and later steps read it:

```yaml
- run: echo "the answer is ${{ steps.produce.outputs.computed }}"
```

Without the `id: produce`, there is no `steps.produce`. The `id` is the whole
mechanism.

Three more files a step can write to:

| File | Effect |
| ---- | ------ |
| `$GITHUB_OUTPUT` | Values for `steps.<id>.outputs.*` in **this** job |
| `$GITHUB_ENV` | Environment variables for **later** steps. Not this one |
| `$GITHUB_STEP_SUMMARY` | Markdown appended to the run's job summary |
| `$GITHUB_PATH` | Prepend to `PATH` for later steps. Cannot read the old value |

The old `::set-output` and `::set-env` commands were deprecated in 2022 and have
been **disabled**. Anything you find using them is broken. If a tutorial tells
you to use them, the tutorial is from before late 2022.

### `outcome` and `conclusion`

The two statuses of a step, and the difference is exactly one feature wide:

- `steps.<id>.outcome` — the result **before** `continue-on-error` is applied.
  Values: `success`, `failure`, `cancelled`, `skipped`.
- `steps.<id>.conclusion` — the result **after** it is applied. A step with
  `continue-on-error: true` that fails has `outcome: failure` and
  `conclusion: success`.

Section 4 shows the `outcome` value, measured. The `conclusion` value is
documented behaviour; local `act` did not print it in this run.

### `defaults.run` and what it does *not* reach

```yaml
defaults:
  run:
    shell: bash
    working-directory: cicd-learn
```

This sets defaults for **`run:` steps**. It is what makes this repository's
workflows able to say `run: npm ci` instead of repeating the directory eight
times.

Two consequences people trip over:

- **`defaults.run` does not apply to `uses:` steps.** An action sees the
  workspace, not `cicd-learn`. Give `actions/checkout` a `path:`, or run your
  own commands with `working-directory:`.
- **`working-directory` must exist when the step starts.** Nothing creates it
  for you. If the directory only appears after `actions/checkout`, then any
  `run:` step *before* the checkout is asking for a directory that is not there
  yet. Section 4 shows the exact error.

## 3. Workflow example

This is the real file, `.github/workflows/08-jobs-and-steps.yml`:

```yaml
name: Jobs and steps

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
  # ── run: versus uses: ─────────────────────────────────────────────────────
  both:
    name: run versus uses
    runs-on: ubuntu-24.04
    steps:
      # Always first. On a real runner the workspace exists before this, but the
      # habit matters: `act` only materialises the checkout directory when this
      # step runs, so a `run:` step before it cannot find its working directory.
      - uses: actions/checkout@v7
      - name: An action with inputs
        uses: actions/checkout@v7
        with:
          # fetch-depth 1 is the default: one commit. This workflow needs no
          # history, so the default is correct and cheapest.
          fetch-depth: 1

      # `run:` sends a string to the runner's default shell. On a Linux runner
      # that is `bash -e {0}`, so the step aborts on the first non-zero exit.
      - name: A run step, with a multi-line script
        run: |
          set -euo pipefail
          echo "this is a bash script"
          echo "line count: $(echo one two three | wc -w)"

      # Single-line `run:` needs no block scalar.
      - name: A one-line run step
        run: echo "no block scalar needed for one line"

      # ── Steps share a filesystem; order is the only ordering guarantee ─────
      - name: Write a file in one step
        run: echo "written by step one" > shared-proof.txt

      - name: Read it in the NEXT step, same job
        # This works. No artifact needed, because it is the same machine.
        run: |
          cat shared-proof.txt
          echo "steps in one job share a filesystem"

      # ── env: three scopes ──────────────────────────────────────────────────
      - name: env at step scope, plus override
        env:
          SCOPE: 'step'
          OVERRIDE: 'from the step'
        run: |
          echo "SCOPE   : $SCOPE"
          echo "OVERRIDE: $OVERRIDE"

      # ── id: makes a step's outputs addressable ─────────────────────────────
      - name: Produce a value for later steps
        id: produce
        run: |
          echo "computed=42" >> "$GITHUB_OUTPUT"
          echo "hello there" >> "$GITHUB_STEP_SUMMARY"
          # $GITHUB_ENV affects later steps, not this one.
          echo "FROM_ENV=set by an earlier step" >> "$GITHUB_ENV"

      - name: Use that value
        # Addressable because the producing step has `id: produce`.
        run: |
          echo "the answer is ${{ steps.produce.outputs.computed }}"
          # This variable was written by the previous step.
          echo "env value : $FROM_ENV"

      # ── if: skips a step ──────────────────────────────────────────────────
      # A colon-space inside an unquoted scalar breaks YAML. `proving if: works`
      # parses as a mapping, so it must be quoted: 'proving if: works'.
      - name: 'Skipped step, proving if: works'
        if: false
        run: echo "you will not see this"

      - name: Skipped because a variable is unset
        if: env.NEVER_SET == 'yes'
        run: echo "nor this"

      # ── continue-on-error ──────────────────────────────────────────────────
      - name: Fails, but the job survives
        id: soft-fail
        continue-on-error: true
        run: |
          echo "about to exit 1"
          exit 1

      - name: Proof the job continued, and how to read the step's conclusion
        # Without `if: always()`, a normal step after a failed step would be
        # skipped. `always()` means run regardless of previous status.
        if: always()
        run: |
          echo "previous step conclusion: ${{ steps.soft-fail.outcome }}"
          echo "job status              : ${{ job.status }}"

      # ── timeout-minutes ────────────────────────────────────────────────────
      - name: A quick step with a generous timeout
        timeout-minutes: 5
        run: echo "a step can have its own timeout too"

  # ── Jobs do not share a filesystem: proven, not asserted ──────────────────
  writer:
    name: Writer job
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: Create a file
        run: echo "written by the writer job" > job-proof.txt
      - name: Show it exists here
        run: ls -l job-proof.txt

  reader:
    name: Reader job (cannot see the file)
    runs-on: ubuntu-24.04
    steps:
      - name: Look for the file, with no checkout at all
        # Fails on GitHub with exit 2. `act` will not reproduce this, because it
        # bind-mounts your working directory. Chapter 02 explains why.
        run: ls -l job-proof.txt
```

The `both` job is a tour: `run:` against `uses:`, multi-line against one-line,
sharing, `env:` scoping, `id:` and outputs, `if:` skipping,
`continue-on-error`, and a per-step timeout. The `writer`/`reader` pair is the
one experiment that only GitHub can finish.

## 4. What I should see

### `run:` versus `uses:` (`docs/_logs/ch08-steps.log`)

```
⭐ Run Main actions/checkout@v7
  🐳  docker cp src=/home/sunny/app/nimo/cicd-docs/. dst=/home/sunny/app/nimo/cicd-docs
✅  Success - Main actions/checkout@v7 [42.215463ms]
⭐ Run Main An action with inputs
  🐳  docker cp src=/home/sunny/app/nimo/cicd-docs/. dst=/home/sunny/app/nimo/cicd-docs
✅  Success - Main An action with inputs [36.856811ms]
⭐ Run Main A run step, with a multi-line script
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/2] user= workdir=cicd-learn
  | this is a bash script
  | line count: 3
✅  Success - Main A run step, with a multi-line script [60.9328ms]
⭐ Run Main A one-line run step
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/3] user= workdir=cicd-learn
  | no block scalar needed for one line
✅  Success - Main A one-line run step [58.862633ms]
```

Three details, all real:

- `bash -e /var/run/act/workflow/2` — the temporary file the runner wrote the
  `run:` string into. `/var/run/act/` is `act`'s path; on GitHub it is under
  `/home/runner/work/_temp/`. **This is the default `bash -e {0}` in the open.**
- `workdir=cicd-learn` — `defaults.run.working-directory` applied. It applied to
  the `run:` step; it did **not** apply to the two `uses:` steps above, which
  ran with an empty workdir. Exactly the rule from section 2.
- `set -euo pipefail` did not break anything; `$(...)` still expanded.

### Steps share a filesystem

```
⭐ Run Main Write a file in one step
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/4] user= workdir=cicd-learn
✅  Success - Main Write a file in one step [66.368828ms]
⭐ Run Main Read it in the NEXT step, same job
  | written by step one
  | steps in one job share a filesystem
✅  Success - Main Read it in the NEXT step, same job [59.504387ms]
```

Two different steps, two different temporary script files (`/4` and `/5`), one
file surviving from the first to the second. No artifact, no output plumbing,
nothing. That is the whole reason to prefer steps over jobs when the data is
small.

### `id:`, `$GITHUB_OUTPUT`, `$GITHUB_ENV`

```
⭐ Run Main Produce a value for later steps
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/produce] user= workdir=cicd-learn
✅  Success - Main Produce a value for later steps [60.808583ms]
  ⚙  ::set-env:: FROM_ENV=set by an earlier step
  ⚙  ::set-output:: computed=42
  ⚙  Summary - hello there
⭐ Run Main Use that value
  | the answer is 42
  | env value : set by an earlier step
✅  Success - Main Use that value [56.954298ms]
```

Three things:

1. **The script file is named `produce`, not `8`.** `act` names it after the
   step's `id:`; unnamed steps get sequential numbers. That is direct evidence
   that `id: produce` registered, which is what makes `steps.produce.outputs`
   resolvable one step later.
2. `the answer is 42` — the value crossed the step boundary through
   `$GITHUB_OUTPUT`.
3. **About those `::set-env::` and `::set-output::` lines:** they are `act`'s
   display of writes to the modern `$GITHUB_ENV` and `$GITHUB_OUTPUT` files, not
   use of the removed commands. The workflow in section 3 never calls
   `::set-output` or `::set-env`. On GitHub you will not see these lines at all:
   the runner consumes them and shows only the values.

### Skipped steps leave no trace

The `both` job contains two skipped steps — `if: false` and
`if: env.NEVER_SET == 'yes'`. Neither appears anywhere in
`docs/_logs/ch08-steps.log`: no `⭐ Run` line, no output, no mention.

A skipped step is not a failed step and not a passing step. It is absent from
the log entirely, and greyed out in the Actions tab. **When you read a log and a
step you wrote is missing, check its `if:` before you check anything else.**

### `continue-on-error`: a red step in a green job

This is the finding to read three times:

```
⭐ Run Main Fails, but the job survives
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/soft-fail] user= workdir=cicd-learn
  | about to exit 1
Failed but continue next step
❌  Failure - Main Fails, but the job survives [57.114737ms]
⭐ Run Main Proof the job continued, and how to read the step's conclusion
  | previous step conclusion: failure
  | job status              : success
✅  Success - Main Proof the job continued, and how to read the step's conclusion [63.627413ms]
...
🏁  Job succeeded

### act exit status: 0
```

All five of these are true at once, and none of them is a bug:

| Fact | Where it comes from |
| ---- | ------------------- |
| The step ran and printed `about to exit 1` | the `run:` block |
| The step is marked `❌ Failure` | its exit code was 1 |
| `Failed but continue next step` | `continue-on-error: true` was honoured |
| `previous step conclusion: failure` | `steps.soft-fail.outcome`, before `continue-on-error` |
| `job status : success` and `🏁 Job succeeded` | the job's own verdict |
| The whole run exited 0 | the job succeeded |

The follow-up step also needed `if: always()`. Without it, Actions skips a step
whose predecessors failed — and even with `continue-on-error: true`, a step that
failed is enough to make the *default* condition false. `always()` is how you
say "run me regardless". (Chapter 19 covers the whole condition vocabulary.)

**Why this matters in practice:** a green check mark on a run does not mean
every step passed. It means every step either passed, was skipped, or failed and
explicitly opted out. If your pipeline must not tolerate that, do not use
`continue-on-error` on the steps that decide pass or fail — use it only for steps
you genuinely want to be able to fail, and check `outcome` explicitly.

### The `working-directory` trap, in full (`docs/_logs/ch08-reader.log`)

The `reader` job has one `run:` step, **no `actions/checkout`**, and inherits
`defaults.run.working-directory: cicd-learn` from the workflow. Full log:

```
### act act version 0.2.89
### image  cicd-act-runner:24
### event  push
### file   .github/workflows/08-jobs-and-steps.yml

[Jobs and steps/Reader job (cannot see the file)] ⭐ Run Set up job
[Jobs and steps/Reader job (cannot see the file)] 🚀  Start image=cicd-act-runner:24
[Jobs and steps/Reader job (cannot see the file)]   ✅  Success - Set up job
[Jobs and steps/Reader job (cannot see the file)] ⭐ Run Main Look for the file, with no checkout at all
[Jobs and steps/Reader job (cannot see the file)]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/0] user= workdir=cicd-learn
[Jobs and steps/Reader job (cannot see the file)]   | OCI runtime exec failed: exec failed: unable to start container process: chdir to cwd ("/home/sunny/app/nimo/cicd-docs/cicd-learn") set in config.json failed: no such file or directory
[Jobs and steps/Reader job (cannot see the file)]   ❌  Failure - Main Look for the file, with no checkout at all [67.473646ms]
[Jobs and steps/Reader job (cannot see the file)] exitcode '127': command not found, please refer to https://github.com/nektos/act/issues/107 for more information
[Jobs and steps/Reader job (cannot see the file)] ⭐ Run Complete job
[Jobs and steps/Reader job (cannot see the file)]   ✅  Success - Complete job
[Jobs and steps/Reader job (cannot see the file)] 🏁  Job failed
Error: Job 'Reader job (cannot see the file)' failed

### act exit status: 1
```

The whole failure happened **before your script ran.** `bash` was never started.
The runner tried to enter `cicd-learn`, the directory did not exist because no
checkout had ever happened, and the step died at `chdir`.

Read the sequence as a general rule:

1. `working-directory: cicd-learn` is applied to the step.
2. The directory `cicd-learn` does not exist yet, because `actions/checkout` has
   not run — in this job, it never runs.
3. The shell cannot start. Exit 127.
4. `Complete job` still reports `✅ Success`, and only then does the job report
   failure. The job teardown is not the verdict; the step was.

This is the single most common structural mistake in Actions, and chapter 07's
`ubuntu-latest` job failed with the identical message for the identical reason.

### What local `act` cannot show you

On GitHub, the `writer`/`reader` experiment gives you this, and it is the real
proof:

```
Run ls -l job-proof.txt
  ls: cannot access 'job-proof.txt': No such file or directory
Error: Process completed with exit code 2.
```

*Illustrative of GitHub's rendering; the local run above cannot produce it.* (The
`Error: Process completed with exit code 2.` line is the GitHub runner's wording,
also quoted in chapter 02; `act` prints `exitcode` lines instead.) `act` copies
your working directory into the container, so a `job-proof.txt` left over from a
previous local run would make the `reader` job pass — a false green. That
is why `--bind` is deliberately off in `scripts/run-workflow.sh`, and why the
job comment in section 3 says `act` will not reproduce this. Trust the hosted run
for job isolation.

## 5. When to use it and when NOT to

**A step, not a job, when:** the data is small and stays in the workspace (a file,
a variable, a build output the next step consumes) — steps are free and a job
costs a machine and a checkout; the work is sequential by nature, so install →
test → build belongs in one job rather than three serialised ones plus an
artifact hop; and you want the log to read as one narrative.

**A job, not a step, when:** the checks are independent (lint and test need
nothing from each other, so two jobs finish in the time of the slower one); you
need a different machine, which is `runs-on:`; you need different `permissions:`
or a different `environment:`, both job-level — a deploy job with
`environment: production` and a read-only PR job *must* be separate jobs; and
you are isolating something risky so a crash costs one job rather than the run.

**Never:** a one-step job, which pays a machine startup to run one command;
splitting "for organisation", which is slower, harder to read, and re-installs
dependencies three extra times; `needs:` to pass a file, because it orders and
does not transfer (chapter 20); or a job in the hope it shares `node_modules`
with another job (chapter 16).

**Never `continue-on-error`** on the step that decides pass or fail — that is the
one place a red build must stay red — and never on anything you cannot justify in
a code review. "We wanted the log to look clean" is not a justification; it is a
way to ship a broken pipeline quietly.

## 6. Common mistakes

- **`working-directory:` on a job with no checkout.** Fails before your first
  command, with `chdir to cwd (...) failed` or exit code 127. Section 4. The rule
  for this repository: `defaults.run.working-directory: cicd-learn` only on jobs
  that check out first. Same failure if a `run:` step is reordered above the
  checkout.
- **Expecting jobs to see each other's files.** Each job is a new machine.
  Symptoms range from `No such file or directory` to an empty glob to an artifact
  that turns out to be from the wrong run. And adding `needs:` does not help.
- **A job's `name:` in `needs:`.** Only the id works: `needs: [build]`, never
  `needs: [Build the app]`.
- **`run:` and `uses:` in the same step**, or neither. A step has exactly one.
  The validator says which mistake it is, by index: `jobs.a.steps[0] has neither
  'run:' nor 'uses:'`.
- **Expecting `bash -e` to catch a failed pipeline.** `false | true` exits 0.
  Write `set -euo pipefail` if you care.
- **`run:` lines without `|`.** Each line becomes its own step, so a variable set
  on line 1 does not exist on line 2. Symptom: `VAR: unbound variable`.
- **Reading `$GITHUB_ENV` in the step that wrote it.** It only affects *later*
  steps. Section 4's log shows this exact ordering.
- **`::set-output` / `::set-env` / `::save-state`.** Removed. Use
  `$GITHUB_OUTPUT`, `$GITHUB_ENV`, `$GITHUB_STATE`.
- **Using `steps.<id>.outputs.x` without an `id:`.** Silently empty, and the step
  still passes — the worst kind of CI bug. Section 7's last paragraph.
- **Reading `steps.<id>.outcome` where you wanted the post-`continue-on-error`
  verdict.** That is `conclusion`. Section 4 shows `outcome: failure` on a step the
  job considered fine.
- **An unquoted step name containing `: `.** `- name: Proving if: works` parses as
  a mapping and fails the file. Quote it. This is chapter 05's rule, in the one
  place nobody expects it.
- **Expecting a skipped step to log anything.** It logs nothing. Section 4.
- **Relying on `defaults.run` to reach a `uses:` step.** It does not.

## 7. Try it yourself

**Exercise: prove the three rules, then break rule 3 on purpose.**

1. Create `.github/workflows/bench.yml`:

   ```yaml
   name: Workbench rules
   "on":
     push:
       branches: [main]
   permissions:
     contents: read
   defaults:
     run:
       working-directory: cicd-learn
   jobs:
     bench:
       name: One bench, many steps
       runs-on: ubuntu-24.04
       steps:
         - uses: actions/checkout@v7
         - name: 1. write
           run: echo "from step one" > bench.txt
         - name: 2. read
           run: cat bench.txt
         - name: 3. hand a value forward
           id: calc
           run: |
             n=$(wc -c < bench.txt)
             echo "bytes=$n" >> "$GITHUB_OUTPUT"
         - name: 4. use it
           run: echo "step 3 said ${{ steps.calc.outputs.bytes }} bytes"
         - name: 5. skipped
           if: false
           run: echo "unreachable"
         - name: 6. soft failure
           id: soft
           continue-on-error: true
           run: exit 3
         - name: 7. report
           if: always()
           run: |
             echo "step 6 outcome    : ${{ steps.soft.outcome }}"
             echo "step 6 conclusion : ${{ steps.soft.conclusion }}"
             echo "job status        : ${{ job.status }}"
     other-bench:
       name: A different room
       runs-on: ubuntu-24.04
       steps:
         - uses: actions/checkout@v7
         - name: look for the other bench's file
           run: cat bench.txt
   ```

2. Push and read the log. Step 2 prints `from step one`, so steps share a
   filesystem. Step 4 prints a number, so `id:` plus `$GITHUB_OUTPUT` works. Step
   5 is **absent**, so skipped means invisible. Step 7 prints
   `outcome: failure` next to `conclusion: success` — the distinction this run
   makes visible and the chapter's log only showed half of. And `other-bench`
   fails with `cat: bench.txt: No such file or directory` — *unless* you have a
   stray `cicd-learn/bench.txt` lying around locally, in which case it passes and
   teaches you the local blind spot.

3. **Break rule 3, then break ordering:**

   - Add `needs: [bench]` to `other-bench`. It **still fails.** `needs:` ordered
     the jobs; it did not carry the file. You have just separated *ordering* from
     *data transfer*.
   - Move `run: cat bench.txt` to the top of `bench`, above the checkout. Push.
     Read the failure — it is the `chdir` error from section 4, verbatim.
   - Change `- name: 5. skipped` to `- name: 5. skipped: on purpose`. Push. The
     file fails to parse, because `: ` inside an unquoted scalar makes it a
     mapping. Chapter 05's rule, caught by the parser rather than by your tests.

4. Local equivalent:

   ```bash
   ./scripts/run-workflow.sh .github/workflows/bench.yml bench push
   ./scripts/run-workflow.sh .github/workflows/bench.yml other-bench push
   ```

   `bench` behaves identically to GitHub. `other-bench` is the one you cannot
   trust locally: `act` copies your working directory into the container, so a
   leftover `bench.txt` makes it pass. Delete that file first and you get the
   `chdir` failure instead of the `cat` failure — still not GitHub's result, and
   that gap is exactly why `--bind` is off by default in `scripts/run-workflow.sh`.

**Hint:** `act` names the temporary script file after the step `id` and numbers
the unnamed ones (`/var/run/act/workflow/soft-fail`, `/var/run/act/workflow/4`).
Reading those paths tells you exactly which step the runner is on, which is handy
when a log line looks like it belongs to the wrong step.

**Break it on purpose:** delete `id: produce` from the step that writes
`$GITHUB_OUTPUT`, keeping the reader. `steps.produce.outputs.computed` becomes
empty, the line prints `the answer is `, and the step still passes. That is the
worst class of CI bug: silently wrong, and green — which is why step outputs
deserve a test of their own.

## 8. Next

You can write the body of a job: ordered steps, shared files, hand-off values,
and deliberate failure handling. The last piece of the basic vocabulary is the
thing that fills almost every real pipeline — someone else's code, pulled in by
name, configured by `with:`.

→ [09 — Using actions](09-using-actions.md)
