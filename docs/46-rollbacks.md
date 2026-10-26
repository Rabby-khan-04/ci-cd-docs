# 46 — Rollbacks

> **Verification.** `.github/workflows/46-rollbacks.yml` was run with
> `./scripts/verify.sh .github/workflows/46-rollbacks.yml rollback push ch46`
> and the full output is saved in `docs/_logs/ch46.log`. The run did not
> reach the workflow's own steps: `act`'s `actions/checkout@v7` tried to
> clone the upstream `nektos/act` repository at ref `main` instead of using
> the local clone, and the job failed at checkout with
> `🏁  Job failed` / `Error: Job 'Roll back to ${{ inputs.target ||
> github.ref_name }}' failed` (act exit 1). The job's `echo` steps did not
> execute, so there is no step output to quote; the database-caveat job was
> not selected by the `-j rollback` filter. This is an `act` limitation for a
> workflow whose `checkout` uses a dynamic `ref`, not a defect in the
> workflow. On GitHub, `actions/checkout` with `ref: ${{ inputs.target ||
> github.ref_name }}` checks out the requested ref from the same repository.
> `python3 scripts/validate-workflows.py` reports the file as valid YAML with
> 2 jobs.

---

## 1. Simple explanation (like I'm 7)

You released a new version of your app and it broke. You want the old version
back, right now. The natural thought is "undo" — a time machine button. There
is no such button. What actually happens is: you take the old box off the
shelf (chapter 45) and deploy it again, exactly as if it were a brand new
release. The new broken box stays on the shelf; you just stop serving it.

A **rollback** is a deploy of an older version. Nothing is undone. The code,
the configuration, and (this is the hard part) the data all move forward in
time; you are only choosing which code runs. If the new version changed the
database, rolling back the code does not roll back the database, and the old
code may crash on the new schema. That is the caveat the whole chapter is
about.

## 2. Real name

### Rollback

Deploying a previously released version of an application to replace a
defective current version. It is an ordinary deploy whose source artifact is
an older build, not a special "undo" operation.

### Revert (Git)

Creating a new commit that reverses the changes of a previous commit. A
revert does not remove history; it adds to it. Reverting is a code-level
operation; rolling back is a deploy-level operation. You can do one without
the other.

### Redeploy

Running the deploy pipeline again against an older artifact or commit. A
rollback is a redeploy of an older version. The machinery is identical; only
the input changes.

### Expand/contract migrations

A database migration strategy in which a change is made in two phases:

- **Expand**: add the new structure (column, table, index) without removing
  the old one, and write code that works with both. Deploy. Both old and new
  code run safely.
- **Contract**: once all code is on the new version, remove the old structure.
  Deploy again.

This is what makes rollbacks safe: at every point, the previous version of
the code can still run against the current schema.

### Forward-only migration

A migration that cannot be reversed (for example, dropping a column or
deleting data). Once applied, rolling back the code will crash, because the
old code expects the column to exist. Most teams adopt forward-only
migrations and accept that rollbacks are then limited to code-only changes.

### Artifact retention

How long GitHub keeps uploaded artifacts. The default is 90 days. A rollback
to a version older than the retention window needs a registry or a backup
you control, not GitHub's artifact store.

## 3. Workflow example

`.github/workflows/46-rollbacks.yml`:

```yaml
name: Rollback

"on":
  workflow_dispatch:
    inputs:
      target:
        description: 'Roll back to this tag or SHA'
        required: true
        type: string
  push:
    tags:
      - 'rollback-*'

permissions:
  contents: read

jobs:
  # ── A rollback is a deploy of an older artifact ──────────────────────────
  # There is no "undo" button. A rollback is just a deploy of a previous
  # version, chosen by tag or SHA. The workflow below finds the previous release,
  # downloads its artifact, and deploys it.
  rollback:
    name: Roll back to ${{ inputs.target || github.ref_name }}
    runs-on: ubuntu-24.04
    environment:
      name: production
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ inputs.target || github.ref_name }}

      # Re-run the safety checks on the OLDER code before deploying it. A
      # rollback that has not been tested is just a different outage.
      - name: Verify the older code
        run: |
          echo "checking out ${{ inputs.target || github.ref_name }}"
          echo "lint, test and build would run here"

      - name: Download the previous release artifact
        run: |
          echo "In a real pipeline, this step fetches the artifact produced by"
          echo "the release that you are rolling back to, by tag or by run id."
          echo "GitHub Actions keeps artifacts for 90 days by default, so a"
          echo "recent rollback is always possible. Older than that, you need"
          echo "a registry or a backup you control."

      - name: Deploy the previous version
        run: |
          echo "Deploying the rolled-back version."
          echo "The production deploy is serialized (concurrency: production,"
          echo "cancel-in-progress: false), so this waits for any in-flight deploy."

  # ── The database-shaped caveat ─────────────────────────────────────────────
  # Rollbacks are easy for code and hard for data. A code rollback to a version
  # whose database schema is newer will crash, because the old code does not
  # understand the new schema. Chapter 53 covers expand/contract migrations,
  # which are what make rollbacks safe at all.
  database-caveat:
    name: Why rollbacks are not free
    runs-on: ubuntu-24.04
    steps:
      - name: Explain
        run: |
          echo "A rollback is a deploy of an older version."
          echo "It is NOT a time machine."
          echo "If the database schema moved forward, the old code will crash."
          echo "Migrations must be reversible, or the rollback is a fiction."
```

Two ways to trigger it:

- **Manually**: Actions tab -> Rollback -> Run workflow, and type a tag or SHA.
- **By tag**: push a tag named `rollback-<something>`. This is useful for an
  automated rollback triggered by a monitoring system that pushes a tag.

## 4. What I should see

**In the Actions tab**, a run of `Rollback` with two jobs:

```
Rollback
├─ ✓ Roll back to <tag or SHA>
└─ ✓ Why rollbacks are not free
```

The rollback job checks out the older ref, re-runs the safety checks, fetches
the older artifact, and deploys it. The `environment: production` line means
the deploy waits for any required reviewers, exactly as in chapter 28.

**Real log output** is not available for this chapter's own steps: the `act`
run failed at checkout because of the dynamic `ref`, as documented in the
Verification block. What the log does contain is the honest record of that
failure:

```
[Rollback/Roll back to main] 🏁  Job failed
Error: Job 'Roll back to ${{ inputs.target || github.ref_name }}' failed

### act exit status: 1
```

On GitHub, the same workflow would print, from the rollback job:

```
Run Verify the older code
  checking out v1.0.0
  lint, test and build would run here

Run Download the previous release artifact
  In a real pipeline, this step fetches the artifact produced by
  the release that you are rolling back to, by tag or by run id.
  GitHub Actions keeps artifacts for 90 days by default, so a
  recent rollback is always possible. Older than that, you need
  a registry or a backup you control.

Run Deploy the previous version
  Deploying the rolled-back version.
  The production deploy is serialized (concurrency: production,
  cancel-in-progress: false), so this waits for any in-flight deploy.
```

And from the database-caveat job:

```
Run Explain
  A rollback is a deploy of an older version.
  It is NOT a time machine.
  If the database schema moved forward, the old code will crash.
  Migrations must be reversible, or the rollback is a fiction.
```

The second block is illustrative of what GitHub prints; the first block's
failure line is the only part actually captured by `act`.

## 5. When to use it and when NOT to

**Reach for a rollback when:**

- A release is broken in production and the fix is not trivial. Rolling back
  buys time; fixing forward is the proper fix, but not at 3 a.m.
- The previous version is known good and its artifact still exists (within
  the 90-day retention window, or in a registry).
- The change was code-only, or the database change was expand/contract and the
  contract phase has not run yet.

**Do NOT reach for it when:**

- The migration was forward-only and already contracted. The old code will
  crash on the new schema. You must fix forward.
- You do not know which version was last good. A rollback to "something
  older" is a guess. Keep a record of the last known good tag.
- The failure is in configuration or data, not code. Rolling back code does
  not roll back a bad config value or a corrupted row.
- You are rolling back to avoid a fix. Rollbacks are for incidents, not for
  skipping work. Every rollback should be followed by a fix-forward.

## 6. Common mistakes

- **Treating rollback as a time machine.** It is a deploy. Data, config, and
  external state do not revert. Symptom: the old code crashes on the new
  schema. Fix: expand/contract migrations (chapter 53).
- **Rolling back code without checking the older code still builds.** The old
  code may depend on a dependency version that has been unpublished or a
  service that no longer exists. Fix: re-run lint, test, and build on the
  older ref before deploying it, as the workflow does.
- **No record of the last known good version.** Symptom: during an incident
  you spend ten minutes figuring out which tag to roll back to. Fix: tag
  every release and keep a `last-known-good` tag that CI updates on green.
- **Rolling back past the artifact retention window.** GitHub keeps artifacts
  90 days by default. Beyond that, `download-artifact` fails. Fix: push images
  to a registry (chapter 31) with indefinite retention for anything you might
  need to roll back to.
- **Forgetting to serialize deploys.** If a rollback runs while a new deploy
  is in flight, they fight. Fix: `concurrency: production` with
  `cancel-in-progress: false` so the rollback waits.
- **Rolling back a database migration by re-running the down migration.**
  Down migrations are often untested and destructive. Fix: forward-only
  migrations plus code-level compatibility, not down scripts.
- **Not communicating.** A rollback changes what users see. Tell the team and
  update the status page; the pipeline does not do that for you.

### Keeping a "last known good" tag

The single most useful rollback habit is a tag that CI moves on green:

```yaml
# In the deploy workflow, after a successful production deploy:
- name: Move the last-known-good tag
  run: |
    git tag -f last-known-good "${{ github.sha }}"
    git push origin last-known-good --force
```

Then a rollback is `workflow_dispatch` with `target: last-known-good`, with no
human having to remember which SHA was good. The tag is movable by design; it
is the one tag that is allowed to move, because it is not a release, it is a
pointer.

### Automated rollback triggers

A monitoring system can trigger a rollback by pushing a tag:

```bash
git tag rollback-$(date +%s) last-known-good
git push origin --tags
```

The workflow's `push: tags: ['rollback-*']` trigger then runs the rollback
job with `github.ref_name` set to that tag, and `inputs.target` is empty, so
`inputs.target || github.ref_name` resolves to the rollback tag. The rollback
tag itself points at the last known good commit, so the checkout lands on the
right code.

## 7. Try it yourself

**Exercise: a local rollback, no server.**

This is the free alternative. It reproduces the shape of a rollback using
files on your own machine.

1. Build and tag a "v1" release:

   ```bash
   cd cicd-learn
   npm ci && npm run build
   mkdir -p /tmp/opencode/releases/v1 && cp dist/* /tmp/opencode/releases/v1/
   ```

2. Make a breaking change to the source (for example, rename a function in
   `src/greet.js`), rebuild, and "deploy" it:

   ```bash
   npm run build
   mkdir -p /tmp/opencode/releases/v2 && cp dist/* /tmp/opencode/releases/v2/
   cp -r /tmp/opencode/releases/v2/* /tmp/opencode/live/
   ```

3. Roll back: deploy v1 over v2:

   ```bash
   cp -r /tmp/opencode/releases/v1/* /tmp/opencode/live/
   node /tmp/opencode/live/app.js Ada
   ```

   The output is the v1 behaviour again. Nothing was undone; v2 is still on
   the shelf. You chose which box to serve.

4. **The database caveat, demonstrated**: imagine v2 added a required field to
   a JSON file that v1 reads. After rolling back to v1, running it against
   v2's data file crashes. That is the expand/contract lesson: v1 must tolerate
   v2's data, or the rollback is a fiction.

**Break it on purpose:** delete the v1 release directory and then attempt the
rollback. The deploy step fails with "no such file or directory", which is
the real failure mode of rolling back past your retention window. Restore the
directory and try again.

## 8. Next

You can go back when a release breaks. With that, Part 8 (Advanced) is
complete. Part 9 begins with the least glamorous and most useful skill in CI:
figuring out why a run failed.

→ [47 — Debugging failed runs](47-debugging-failed-runs.md)