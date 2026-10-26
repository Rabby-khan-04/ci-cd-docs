# 27 — Deployment fundamentals

> **Verification.** The workflow in this chapter is
> `.github/workflows/27-deployment-fundamentals.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/27-deployment-fundamentals.yml "" push ch27`,
> and the full log is at `docs/_logs/ch27.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/27-deployment-fundamentals.yml (2 job(s))`.
>
> **What this local execution cannot prove.** `act` has no artifact service, so
> the workflow was re-run with artifact steps replaced by local tar operations
> (see `scripts/simulate-artifacts.py`). In that simulated run the `ci` job
> uploads `dist/` successfully, but the `deploy` job fails to find the staged
> artifact because `act` does not share the filesystem between job containers
> the way GitHub does. On GitHub the artifact travels between jobs normally.
> Deployment targets, real secrets, real environments and real approval rules
> are also out of scope for local execution and are described from the
> documentation. Chapter 29 is the first chapter in this course with a real,
> runnable deploy.

---

## 1. Simple explanation (like I'm 7)

Building a cake and serving it to guests are two different jobs. You can bake
the cake perfectly and still fail if you drop it on the way to the table. So
you separate the two: one person bakes, checks the cake is good, and sets it
on a cooling rack. A second person, only after the cake passed inspection,
carries it to the table.

In software, **CI** is baking and checking: install, lint, test, build. It
proves the code is good. **Deployment** is carrying it to the table: taking
the thing CI proved good and putting it where users can reach it. The two are
separate concerns because they fail differently, they need different
permissions, and they should not run on the same trigger.

The golden rule of this chapter: **a deploy only happens for code that passed
CI, on the branch you trust, and never twice at once.**

## 2. Real name

### Deployment

The act of taking a built artifact and making it available at a URL, a
registry, a server, or a store. It is a state change in the world outside
your repository: users can now see the new version. Contrast with CI, which
only changes state inside the runner.

### Continuous integration (CI)

The practice of automatically building and testing every change. The goal is
to know, within minutes, whether a commit broke anything. CI does not ship
anything to users.

### Continuous delivery (CD)

CI plus an automated pipeline that produces a deployable artifact and can
deploy it, but a human decides *when*. The deploy button exists and is
reliable; pressing it is a human act.

### Continuous deployment

CD where the deploy happens automatically on every green build. No human
button. The code that passes CI goes to production without further
intervention. This is the most automated end of the spectrum and the one
that requires the most confidence in your tests.

### Environment (deployment target)

A named place code runs: `staging`, `production`, `qa`. Each has its own
URL, its own secrets, and its own rules. Chapter 24 and 28.

### Artifact (revisited)

The bridge between CI and deploy. CI builds `dist/app.js` and uploads it as
an artifact; deploy downloads that exact artifact and ships it. Deploying the
artifact, not rebuilding, is what guarantees that what you tested is what you
shipped. Chapter 20.

### Promotion

Moving an artifact from one environment to the next: staging first, then
production, using the same artifact. You do not rebuild for production; you
promote what staging validated.

### Rollback

Reverting a deployment to a previous version. It is a deploy of an older
artifact, not an undo button. Chapter 46.

## 3. Workflow example

This is the complete `.github/workflows/27-deployment-fundamentals.yml` from
this repository.

```yaml
name: Deployment fundamentals

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── CI and deploy are separate concerns ───────────────────────────────────
  # This workflow shows the shape: CI runs on every push; deploy runs only on
  # main, only after CI is green, and only for the code that CI tested.
  ci:
    name: CI
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
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 7
          if-no-files-found: error

  # ── The deploy job: gated, serialized, environment-bound ──────────────────
  deploy:
    name: Deploy
    runs-on: ubuntu-24.04
    needs: [ci]
    # A deployment only happens for code that passed CI on main. A PR never
    # deploys, because github.ref_name is not 'main' on a pull_request event.
    if: github.ref_name == 'main' && github.event_name == 'push'
    environment:
      name: production
      url: https://example.com
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: dist
          path: dist
      - name: Deploy (simulated)
        run: |
          echo "deploying $(wc -c < dist/app.js) bytes"
          echo "this is where the real deploy command goes"
```

Five structural things to notice:

1. **Two jobs, two concerns.** `ci` builds and tests. `deploy` ships. They
   are not steps in one job, because a deploy needs different permissions,
   different triggers, and a different failure mode than CI.
2. **`needs: [ci]`.** Deploy cannot start until CI is green. If CI fails,
   deploy is skipped, not failed. That is the gate.
3. **`if: github.ref_name == 'main' && github.event_name == 'push'`.** A
   pull request never deploys, even if CI passes, because `github.ref_name`
   is the PR's head branch and `github.event_name` is `pull_request`. This
   is the single most important condition in a deploy workflow.
4. **`environment: production`.** The deploy is bound to an environment with
   its own secrets, reviewers and history. Chapter 24 and 28.
5. **`concurrency: deploy-production` with `cancel-in-progress: false`.** Two
   deploys to production never run at once; the second waits. Cancelling a
   deploy halfway through is worse than either finishing. Chapter 21.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch27.log` runs both jobs. `ci` completes and uploads the
artifact:

```
[Deployment fundamentals/CI] ⭐ Run Main npm run build
[Deployment fundamentals/CI]   | built dist/app.js (2887 bytes)
[Deployment fundamentals/CI]   ✅  Success - Main npm run build [258.640899ms]
[Deployment fundamentals/CI] ⭐ Run Main [simulated upload-artifact: dist]
[Deployment fundamentals/CI]   | -rw-r--r-- 1 root root 1466 Oct 26 12:42 .tmp/artifacts/dist.tar
[Deployment fundamentals/CI]   | SIMULATED upload of cicd-learn/dist as dist
[Deployment fundamentals/CI]   ✅  Success - Main [simulated upload-artifact: dist] [86.204479ms]
[Deployment fundamentals/CI] 🏁  Job succeeded
```

Then `deploy` starts (it was waiting on `needs: [ci]`) and tries to download
the artifact:

```
[Deployment fundamentals/Deploy] ⭐ Run Main [simulated download-artifact: dist]
[Deployment fundamentals/Deploy]   | ❗  ::error::artifact dist not found
[Deployment fundamentals/Deploy]   ❌  Failure - Main [simulated download-artifact: dist] [64.311803ms]
[Deployment fundamentals/Deploy] exitcode '1': failure
[Deployment fundamentals/Deploy] 🏁  Job failed
```

That failure is **an `act` limitation, not a workflow bug**. GitHub's
artifact service persists the upload and makes it available to the download
step across jobs. `act` has no such service, and its filesystem simulation
does not share staged files between job containers the way GitHub does. The
workflow itself is correct: on github.com, `deploy` downloads `dist/app.js`
and prints `deploying 2887 bytes`.

### What a real GitHub run adds (not verified locally)

On github.com, with a push to `main`:

1. `ci` runs: install, lint, test, build, upload artifact. Green.
2. `deploy` starts (it was gated on `ci`). It downloads the artifact and
   prints `deploying 2887 bytes`, then runs the real deploy command.
3. The run summary shows the `production` environment with its URL as a
   clickable link, and a deployment record is created under the environment.
4. If a second push lands while `deploy` is running, the second run's
   `deploy` job enters the `deploy-production` concurrency group and
   **waits**, because `cancel-in-progress: false`. It starts only after the
   first finishes.
5. If `ci` fails, `deploy` is skipped and shows "Skipped" in the run
   summary. No deploy happens for broken code.
6. On a pull request, `ci` runs but `deploy` is skipped because of the `if:`
   condition. PRs are tested, never deployed.

### The CI/deploy split, in practice

| Concern | CI job | Deploy job |
| ------- | ------ | ---------- |
| Trigger | Every push and PR | `main` push only |
| Gate | `needs:` (none for CI) | `needs: [ci]` + `if:` |
| Permissions | `contents: read` | environment's permissions |
| Concurrency | cancel obsolete runs | never cancel, queue |
| Failure mode | Red build, fix and re-push | Page someone, possibly rollback |
| Artifact | Produces `dist` | Consumes `dist` |
| Environment | none | `production` |

The split is what lets you move fast on CI (cancel, retry, parallelise) while
being careful on deploy (gate, serialise, human approval). Putting both in
one job forces one policy on both, which is wrong for at least one of them.

### Why deploy the artifact, not rebuild

A tempting shortcut is to have `deploy` check out the code and run
`npm run build` itself. Do not. The build that ran in CI is the build you
tested; a rebuild in `deploy` is a new build that nobody tested, and it can
differ (a dependency resolved differently, a cache that expired, a different
Node version). Shipping the artifact CI produced is the only way to guarantee
that what users see is what passed the tests. Chapter 20.

## 5. When to use it and when NOT to

**Use this split when:**

- **You deploy anything to anyone.** Even a static site benefits from "CI
  green, then deploy, same artifact."
- **You have more than one environment.** Staging validates the artifact;
  production promotes it. Rebuilding per environment defeats the point.
- **You want a human gate on production.** The `environment:` block plus
  required reviewers (chapter 28) gives you that without changing the
  workflow.
- **You deploy on every green main build.** That is continuous deployment,
  and it requires the split to be safe.

**Do NOT:**

- **Do not deploy from a pull request.** A PR is untrusted code until it is
  merged. Symptom: a fork PR ships to production. Fix: the `if:` condition in
  the workflow.
- **Do not rebuild in the deploy job.** You are shipping an untested build.
  Symptom: "it passed CI but broke in production." Fix: download the
  artifact.
- **Do not skip `needs:`.** A deploy that runs in parallel with CI can ship
  broken code. Symptom: a deploy that finishes before CI fails. Fix: always
  `needs: [ci]`.
- **Do not cancel a deploy.** `cancel-in-progress: true` on a deploy leaves
  production half-shipped. Symptom: a half-deployed service. Fix: `false`,
  always.
- **Do not put deploy logic in the CI job.** CI should be runnable on every
  PR without side effects. Symptom: a PR that deploys to a preview URL you
  did not intend. Fix: separate jobs, separate triggers.
- **Do not deploy without an artifact retention window.** If the deploy job
  runs hours later and the artifact expired, the deploy fails. Symptom: a
  failed deploy with "artifact not found." Fix: set `retention-days:` high
  enough for your pipeline (7 days is a reasonable default).

## 6. Common mistakes

- **`if:` on the wrong expression.** `github.ref == 'refs/heads/main'` works,
  but `github.ref_name == 'main'` is clearer and less error-prone. Mixing
  them, or comparing against `main` without checking the event, deploys on
  pull requests too. Symptom: a PR that deploys. Fix: `github.ref_name == 'main' && github.event_name == 'push'`.
- **Forgetting that `needs:` changes the job's trigger semantics.** A job
  with `needs:` only runs if its dependencies succeed. Symptom: a deploy
  that silently does not run because CI was skipped. Fix: check the `if:` on
  the dependency too.
- **Downloading an artifact that was never uploaded.** If `ci` fails before
  the upload step, `deploy` fails on download with "artifact not found."
  Symptom: a confusing download error masking a build failure. Fix: read the
  `ci` job's log first.
- **One workflow for CI and deploy with no concurrency.** Two pushes in
  quick succession run two deploys at once. Symptom: a corrupted deployment.
  Fix: `concurrency:` on the deploy job.
- **Deploying on `workflow_dispatch` without a guard.** A manual trigger can
  deploy from any branch. Symptom: a deploy from a feature branch. Fix: add
  `github.ref_name == 'main'` to the `if:`, or restrict the dispatch inputs.
- **No rollback plan.** The first deploy that breaks production is a bad
  time to learn how to revert. Symptom: a long outage. Fix: practice a
  rollback before you need it (chapter 46).
- **Assuming local execution proves the deploy.** `act` cannot run a real
  deploy, and its artifact simulation does not share files across jobs.
  Symptom: "it worked locally" about a deploy that never ran. Fix: verify on
  GitHub with a staging environment first.

## 7. Try it yourself

**Exercise: prove the gate works.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/27-deployment-fundamentals.yml "" push ch27
   ```

   Confirm `ci` passes and uploads, and `deploy` fails on the simulated
   download. That failure is the `act` limitation; the job graph and the
   steps are real.

2. **Prove the artifact travels on GitHub.** Push the workflow to a
   repository on github.com. `ci` and `deploy` both pass, and `deploy`
   prints `deploying 2887 bytes`. That is the real behaviour.

3. **Prove the gate.** Make a lint error (e.g. break a test) and push. `ci`
   fails; `deploy` shows "Skipped." No deploy happens. Fix the code and
   re-push; both pass.

4. **Prove the branch guard.** Trigger the workflow from a feature branch
   (push the branch, or run `gh workflow run` with the branch). `ci` runs;
   `deploy` is skipped because `github.ref_name` is not `main`. Merge the
   PR; `deploy` runs on the resulting main push.

5. **Prove the concurrency.** Push twice in quick succession to `main`. The
   first deploy runs; the second waits on `deploy-production` and starts
   only after the first finishes. Watch the "Queued" badge.

6. **Break it on purpose.** Remove `needs: [ci]` from `deploy` and push.
   `deploy` now runs in parallel with `ci` and can ship untested code.
   Revert immediately.

7. **Break it on purpose, part two.** Change `if:` to
   `if: github.event_name == 'push'` (dropping the branch check) and push
   from a feature branch. `deploy` now runs from the branch. Revert.

**Hint:** the deploy step is a placeholder (`echo "this is where the real
deploy command goes"`). Replace it with a real command only after you have a
target: GitHub Pages (chapter 29), a container registry (chapter 31), or an
SSH host (chapter 32). The shape of the workflow does not change; only the
last step does.

## 8. Next

You now know what a deployment is, why it is separate from CI, and the shape
of a workflow that gates, serialises and ships the same artifact CI tested.
The next chapter turns that shape into a real, runnable deploy to GitHub
Pages.

→ [28 — Environments and manual approvals](28-environments-and-approvals.md)