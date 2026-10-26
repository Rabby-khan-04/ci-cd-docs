# 21 — Concurrency

> **Verification.** The workflow in this chapter is
> `.github/workflows/21-concurrency.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/21-concurrency.yml "ci" push ch21`,
> and the full log is at `docs/_logs/ch21.log`. The log excerpt in section 4
> is quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/21-concurrency.yml (3 job(s))`.
>
> **What this local execution cannot prove.** `act` does not implement
> concurrency groups at all. It runs whatever you ask it to run, immediately,
> with no cancellation and no queuing, so the `concurrency:` block in this
> workflow is parsed and ignored. `docs/_logs/ch21.log` proves only that the
> `ci` job runs its steps successfully; it cannot prove that a second run
> cancels the first, that two deploys serialise, or that a collision queues.
> Those behaviours are defined by GitHub's runner scheduler and are not
> reproducible locally. The syntax and the job are real; the concurrency is
> not, and this chapter says so plainly.

---

## 1. Simple explanation (like I'm 7)

Imagine a single-lane bridge. Two cars cannot cross at the same time, and if a
faster car arrives while a slower one is already on the bridge, one of them has
to decide what to do.

For a CI run, the answer is: **the new car cancels the old one**, because the
old car is checking a commit nobody cares about any more. A new push makes the
in-flight run obsolete.

For a deploy, the answer is the opposite: **the new car waits**. Cancelling a
deploy halfway through leaves production in a worse state than either finishing.

That is **concurrency**: grouping runs so they cannot step on each other, and
choosing, per group, whether a newcomer cancels or waits.

## 2. Real name

### Concurrency

A workflow- or job-level setting that makes runs sharing a group name mutually
exclusive. Two runs in the same group cannot execute their protected jobs at
the same time. What happens to the newcomer is controlled by
`cancel-in-progress`.

### `concurrency:`

The block, placed on a workflow or on a job:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

- `group`: a string. Runs with the same group string are in the same group.
- `cancel-in-progress`: `true` (cancel the in-flight run) or `false` (queue
  the newcomer).

### Concurrency group

The set of runs that share a group string. The string is built from
expressions, so it is usually per-workflow and per-branch. Without `github.ref`
in the group, every branch's run would queue behind one global group, and a
busy feature branch would block main.

### `cancel-in-progress: true`

Cancel the currently running job and start the newcomer. The right policy for
CI on a branch: a new push makes the previous run obsolete, so cancel it and
save the minutes.

### `cancel-in-progress: false`

Queue the newcomer behind the in-flight run. The right policy for deploys: never
cancel a deploy, never run two deploys to the same environment at once. There
is at most one in-flight production deploy, always.

### Workflow-level versus job-level

- **Workflow-level** `concurrency:` applies to the whole run. If a new run
  starts, the entire previous run is cancelled or queued.
- **Job-level** `concurrency:` applies to that job only. Two runs can proceed
  through their non-protected jobs in parallel and only serialise at the
  protected job. This is how you cancel CI but never cancel deploy in the same
  workflow.

### `github.run_id` and `github.run_attempt`

Identifiers for a run and its retry. Useful in deploy jobs to log which run won
the lock, and in re-run scenarios (chapter 48).

### Concurrency is not parallelism

Chapter 18's parallelism is about independent jobs starting together inside one
run. Concurrency is about independent *runs* not stepping on each other. They
are orthogonal: a single run can have parallel jobs, and many runs can be
concurrent, and both can be true at once.

## 3. Workflow example

This is the complete `.github/workflows/21-concurrency.yml` from this
repository.

```yaml
name: Concurrency

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      group:
        description: 'Concurrency group suffix, to show two runs colliding'
        required: false
        default: 'a'
        type: string

permissions:
  contents: read

jobs:
  # ── One workflow run at a time per branch ─────────────────────────────────
  # The core idea: a new push makes the in-flight run obsolete, so cancel it.
  # Without this, five pushes in a minute queue five full CI runs to check
  # commits nobody cares about any more.
  ci:
    name: CI
    runs-on: ubuntu-24.04
    defaults:
      run:
        working-directory: cicd-learn

    # ── The concurrency block ───────────────────────────────────────────────
    # group:   a name. Runs sharing a name are mutually exclusive.
    # cancel-in-progress: what to do when a new run wants the group.
    #
    # `github.workflow` and `github.ref` are expressions, so the group name is
    # built per branch. Without `github.ref`, every branch's CI would queue
    # behind a single group, and a busy PR branch would block main.
    concurrency:
      group: ${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress: true

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

  # ── The opposite policy for deploys ───────────────────────────────────────
  # NEVER cancel a deploy. Two concurrent deploys to the same environment is
  # precisely the failure you are trying to avoid, and cancelling the one that is
  # halfway through leaves you in a worse state than either finishing.
  deploy:
    name: Deploy (never cancelled)
    runs-on: ubuntu-24.04
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: [ci]
    concurrency:
      group: deploy-production
      # false: this run WAITS for the in-flight deploy to finish. Pending runs
      # queue. There is at most one in-flight production deploy, always.
      cancel-in-progress: false
    steps:
      - name: Report the environment lock
        run: |
          echo "This job is serialized behind any in-flight production deploy."
          echo "A second push waits here rather than cancelling the first."
          echo "run id: ${{ github.run_id }}"
          echo "attempt: ${{ github.run_attempt }}"

  # ── Two manual runs colliding, to make the group visible ──────────────────
  collides:
    name: Demonstrate a collision
    runs-on: ubuntu-24.04
    # The manual input makes the group name different per run, so you can watch
    # two runs with the SAME suffix queue against each other.
    concurrency:
      group: collision-demo-${{ inputs.group || 'a' }}
      cancel-in-progress: true
    steps:
      - name: Hold the group for a moment
        run: |
          echo "holding the group 'collision-demo-${{ inputs.group || 'a' }}'"
          sleep 10
          echo "released"
```

Two structural things to notice:

- **`ci` and `deploy` have opposite policies in the same workflow.** `ci`
  cancels; `deploy` queues. That is the realistic shape: fast checks are
  disposable, deploys are not.
- **`collides` uses a manual input in the group name.** That is the only way to
  make two runs collide on demand, because two normal pushes create different
  `github.ref` values only if they are on different branches. On the same
  branch they would collide automatically, which is the case you actually care
  about.

## 4. What I should see

### What `act` can show

`docs/_logs/ch21.log` is a run of the `ci` job. It runs normally:

```
[Concurrency/CI] ⭐ Run Main npm ci
[Concurrency/CI]   | added 127 packages, and audited 128 packages in 1s
[Concurrency/CI] ⭐ Run Main npm run lint
[Concurrency/CI]   ✅  Success - Main npm run lint [559.89034ms]
[Concurrency/CI] ⭐ Run Main npm test
[Concurrency/CI]   ✅  Success - Main npm test [724.172779ms]
[Concurrency/CI] ⭐ Run Main npm run build
[Concurrency/CI]   | built dist/app.js (2887 bytes)
[Concurrency/CI]   ✅  Success - Main npm run build [269.932246ms]
[Concurrency/CI] 🏁  Job succeeded
```

That is all `act` can tell you: the job's steps run and pass. The
`concurrency:` block is parsed and ignored, so no cancellation and no queuing
happen. If you run the workflow twice in a row locally, both complete. That is
not a bug in your workflow; it is a limit of local execution.

### What a real GitHub run adds

On github.com, with two pushes in quick succession to the same branch:

1. The first run starts. Its `ci` job shows a spinner.
2. The second run starts. GitHub evaluates the group string
   `Concurrency-refs/heads/main` for both, sees they match, and because
   `cancel-in-progress: true`, cancels the first run's `ci` job mid-flight.
   The first run's summary shows "Cancelled".
3. The second run proceeds normally and shows "Success".

For the `deploy` job (on main, after `ci` passes):

1. Run A's deploy starts.
2. Run B's deploy, triggered by a later push, enters the `deploy-production`
   group with `cancel-in-progress: false` and **waits**. The Actions tab shows
   it as "Queued" with a note that it is waiting for a concurrency group.
3. Run A's deploy finishes. Run B's deploy starts.

For the `collides` job, two manual runs with the same `group` input ('a'):

1. Run 1 holds the group for 10 seconds (`sleep 10`).
2. Run 2 starts and, with `cancel-in-progress: true`, cancels run 1 mid-sleep.
   Run 1's log shows the sleep was interrupted; run 2 completes.

To see the collision yourself, trigger two runs with the same group:

```bash
gh workflow run 21-concurrency.yml -f group=a
gh workflow run 21-concurrency.yml -f group=a
```

and watch the Actions tab. The second cancels the first.

### The Actions tab rendering

A cancelled run shows a grey "Cancelled" badge and a "This run was cancelled"
banner. A queued run shows a yellow "Queued" badge with the reason
"Waiting for a concurrency group to free up". Neither state exists in `act`'s
output, which is why this chapter marks them as unverified.

## 5. When to use it and when NOT to

**Use concurrency when:**

- **You push several times in a minute.** Without it, five pushes queue five
  full CI runs checking commits nobody will merge. Cancel the obsolete ones.
- **You deploy to a shared environment.** Two concurrent deploys to production
  is the failure you are trying to prevent. Serialise with `cancel-in-progress: false`.
- **You have a job that must not overlap with itself.** A database migration,
  a cache warm-up, a notification that must not fire twice. Group it.
- **You want to save minutes.** Cancelling obsolete runs is the cheapest
  optimisation available, and it costs one block.

**Do NOT reach for concurrency when:**

- **You put `cancel-in-progress: true` on a deploy.** This is the single most
  dangerous mistake in the chapter: a newer push cancels a deploy halfway
  through, leaving production mid-deployment. Deploys always use `false`.
- **You forget `github.ref` in the group.** Every branch queues behind one
  global group, and a busy PR branch blocks main. Always include the ref.
- **You group unrelated jobs.** A workflow-level group cancels everything,
  including a deploy that was already in flight. Put the group on the job that
  needs it, not on the whole workflow, when the policies differ.
- **You assume concurrency is a lock.** It is not a mutex with ownership; it is
  a scheduler hint. A job that takes 30 minutes holds the group for 30 minutes,
  and a queued run waits the full 30. Design for short groups.
- **You use it to replace `needs:`.** Concurrency prevents overlap between
  runs; `needs:` orders jobs within a run. They solve different problems.

## 6. Common mistakes

- **`cancel-in-progress: true` on a deploy.** Symptom: production is
  half-deployed after a rapid second push, with no error in the log. Fix:
  `false`, always, for deploys.
- **Group without `github.ref`.** Symptom: pushes to a feature branch cancel
  or queue main's run. Fix: `group: ${{ github.workflow }}-${{ github.ref }}`.
- **Workflow-level group with mixed policies.** Symptom: a new push cancels a
  deploy that was already running, because the whole workflow shares one group.
  Fix: move `concurrency:` to the job level, with different groups and policies.
- **Assuming `act` will show the behaviour.** It will not. Symptom: "I ran it
  twice locally and both succeeded, so concurrency is broken." It is not; `act`
  ignores the block. Verify on GitHub.
- **Queuing forever.** A queued run waits for the group to free. If the
  in-flight run is stuck, the queued run waits forever (or until the 6-hour
  job timeout). Symptom: a PR that never runs CI. Fix: set `timeout-minutes`
  on every job, including the one holding the group.
- **Colliding groups unintentionally.** Two workflows with the same group string
  share a group. Symptom: workflow B's run cancels workflow A's run. Fix: prefix
  the group with `${{ github.workflow }}`.
- **Using concurrency to serialise database migrations.** It works, but a
  migration that fails leaves the group held until timeout. Use an explicit
  lock (a GitHub environment with required reviewers, or a migration tool's own
  lock) for anything that must not be interrupted.

## 7. Try it yourself

**Exercise: trigger a collision on GitHub.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/21-concurrency.yml ci push ch21
   ```

   Confirm the `ci` job runs and passes. That is all `act` can show.

2. **Make two runs collide.** On GitHub, trigger two runs with the same group:

   ```bash
   gh workflow run 21-concurrency.yml -f group=a
   gh workflow run 21-concurrency.yml -f group=a
   ```

   Watch the Actions tab. The second run cancels the first mid-`sleep 10`,
   because `collides` has `cancel-in-progress: true`. The first run's log
   shows the sleep being interrupted.

3. **Make two runs queue.** Change `collides` to `cancel-in-progress: false`
   temporarily and repeat. The second run now waits for the first's 10 seconds
   to finish, then runs. Revert.

4. **Prove the ref is needed.** Remove `${{ github.ref }}` from the `ci`
   group so it becomes `${{ github.workflow }}` alone. Trigger two runs on
   different branches. The second cancels the first across branches. That is
   the bug. Revert.

5. **Prove the deploy policy.** On main, push twice in quick succession. The
   second push's `deploy` job queues behind the first's instead of cancelling
   it. Watch the "Queued" badge and the 30-second (or 10-second, here) wait.

6. **Break it on purpose.** Set `cancel-in-progress: true` on `deploy` and
   push twice. The second push cancels the first deploy mid-flight. This is
   the experiment that proves why the rule exists. Revert immediately.

**Hint:** `gh workflow run` requires the GitHub CLI and a repository on
github.com. There is no local equivalent; `act` does not implement
concurrency.

**What this exercise proves:** the syntax, the job, and the collision/queue
behaviour on a real GitHub repository. **What it cannot prove locally:** any of
it. This is the one chapter in this part of the course where `act` contributes
nothing, and the verification block says so.

## 8. Next

You now have a pipeline that is fast (cache), broad (matrix), ordered
(dependencies), selective (conditionals), portable (artifacts), and safe
(concurrency). Part 4 is complete.

The next part is about the thing most people get wrong first: secrets. A
pipeline that can deploy but cannot keep a credential safe is worse than no
pipeline at all.

→ [22 — Secrets](22-secrets.md)
EOF
echo done