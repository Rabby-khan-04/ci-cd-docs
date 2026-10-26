# 54 — Separate staging and production environments [runnable]

> **Verification.** The workflow in this chapter is
> `.github/workflows/54-staging-production.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/54-staging-production.yml "" push ch54`,
> and the full log is at `docs/_logs/ch54.log`. The CI half of section 4 is
> quoted from that file. The cross-job artifact transfer (upload in `ci`,
> download in `deploy-staging` and `deploy-production`) is the same shape as
> chapter 20 and was exercised end-to-end with
> `./scripts/verify-artifact-chain.sh` (see chapter 20, section 7), which is
> why this chapter states the transfer as verified even though `act`'s
> simulated artifact service reported `artifact dist not found` for the
> consumer jobs. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/54-staging-production.yml (3 job(s))`.
>
> **What this local execution cannot prove.** `act` has no concept of an
> environment. It does not read Settings → Environments, it does not enforce
> required reviewers, it does not gate a job on approval, it does not apply a
> wait timer, and it does not inject environment-scoped secrets or variables.
> The run in `docs/_logs/ch54.log` proves that the `ci` job runs its steps
> and uploads the artifact. The staging and production deploy jobs ran their
> download step against `act`'s simulated artifact service, which reported
> `artifact dist not found` (a known `act` limitation, not a workflow bug).
> The environment gate, the approval wait, the "waiting" badge, the
> environment-scoped secret injection and the deployment record are
> GitHub-only behaviours and are described here from the documentation and
> from chapter 28, not from a local run.

---

## 1. Simple explanation (like I'm 7)

Imagine a school with two stages. The **classroom stage** is small: every
new scene is performed there first, in front of a few classmates, so
mistakes are cheap and nobody outside the school sees them. The **auditorium
stage** is the real one: the principal must approve before a scene goes on,
and the whole school watches. You would never skip the classroom stage and
put a half-finished scene in the auditorium.

**Staging and production** are those two stages. Staging deploys
automatically on every push to `main`, so you always have a live,
up-to-date copy to click through. Production deploys only after a human
approves, so a broken change cannot reach users without someone noticing.
The same pipeline builds once and deploys to both, so staging and production
run the same artifact.

## 2. Real name

### Staging environment

A deployment target that mirrors production as closely as possible but is
not public. Used for final verification before production. Deploys
automatically, has no required reviewers, and may use test data.

### Production environment

The deployment target real users hit. Deploys only after approval (or
automatically, if you are brave), has required reviewers, uses real data and
real secrets.

### Environment (GitHub Actions)

A named target with its own secrets, variables and protection rules.
Created in Settings → Environments. A job opts in with `environment:`. Chapter
24 and 28.

### Required reviewer

A person or team configured on an environment's protection rules who must
approve a run before its job proceeds. No YAML key for it; configured in
the UI. Chapter 28.

### Deployment branch rule

A protection rule restricting which branches may deploy to an environment.
"Only `main`" for production is the common setting. Chapter 28.

### Concurrency group (for deploys)

A group name that serialises deploys to the same environment. `deploy-production`
with `cancel-in-progress: false` means a second deploy waits for the first.
Chapter 21.

### Artifact transfer across jobs

How a build output moves from the `ci` job to the deploy jobs: `upload-artifact`
in `ci`, `download-artifact` in each deploy job. Jobs do not share a
filesystem. Chapter 20.

### Distinctions people get wrong

- **Staging vs preview.** Staging is shared and long-lived; a preview is
  per-PR and ephemeral. Chapter 51.
- **Staging vs production secrets.** They are different values under the same
  name, scoped by environment. A staging job never sees the production
  password. Chapter 24.
- **"Staging" that nobody tests.** A staging environment that is never
  clicked through is just a more expensive way to not test. Either use it or
  remove it.
- **Deploying to the wrong environment.** A job that declares the wrong
  `environment:` name deploys to the wrong target. Keep one source of truth.
- **Automatic staging, gated production.** The asymmetry (auto staging, gated
  prod) is the standard shape. Gating staging kills feedback speed.

## 3. Workflow example

This is the complete `.github/workflows/54-staging-production.yml` from this
repository.

```yaml
name: Staging and production

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
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

  # ── Staging: automatic, no approvals ──────────────────────────────────────
  deploy-staging:
    name: Deploy to staging
    runs-on: ubuntu-24.04
    needs: [ci]
    environment:
      # The environment must exist in Settings -> Environments.
      name: staging
      url: https://staging.example.com
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: dist
          path: dist
      - name: Deploy (simulated)
        run: |
          echo "deploying $(wc -c < dist/app.js) bytes to staging"
          echo "url: https://staging.example.com"

  # ── Production: gated by required reviewers ───────────────────────────────
  deploy-production:
    name: Deploy to production
    runs-on: ubuntu-24.04
    needs: [ci, deploy-staging]
    environment:
      name: production
      url: https://example.com
    # Required reviewers are configured in the environment's protection rules.
    # Until someone approves, this job sits in a "waiting" state.
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
          echo "deploying $(wc -c < dist/app.js) bytes to production"
          echo "url: https://example.com"
```

Structural things to notice:

1. **One build, two deploys.** `ci` builds once and uploads `dist`. Both
   deploy jobs download the same artifact, so staging and production run
   identical bytes.
2. **Staging is automatic.** `deploy-staging` has no `if:` and no reviewers;
   it runs as soon as `ci` is green.
3. **Production needs staging.** `needs: [ci, deploy-staging]` means
   production cannot start until staging has deployed. That forces you to
   look at staging before production.
4. **Production is gated by the environment.** Required reviewers, wait
   timer and deployment branches are configured on the `production`
   environment in Settings, not in YAML. Chapter 28.
5. **Production serialises.** `concurrency: group: deploy-production,
   cancel-in-progress: false` ensures a second deploy waits for the first.
   Never cancel a deploy. Chapter 21.
6. **Environment-scoped secrets.** Each deploy job reads the credentials of
   its own environment, not repository secrets. Chapter 24.
7. **`url:` is a label, not a target.** GitHub uses it for the run summary
   and the deployment record. The actual deploy command is in the steps.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch54.log` runs the `ci` job end to end. Node is set up:

```
[Staging and production/CI]   | node: v22.23.3
[Staging and production/CI]   | npm: 10.9.9
```

Dependencies install:

```
[Staging and production/CI]   | added 127 packages, and audited 128 packages in 1s
[Staging and production/CI]   | found 0 vulnerabilities
```

Lint, test and build pass:

```
[Staging and production/CI]   ✅  Success - Main npm run lint [553.99417ms]
[Staging and production/CI]   ✅  Success - Main npm test [713.164569ms]
[Staging and production/CI]   | built dist/app.js (2887 bytes)
[Staging and production/CI]   ✅  Success - Main npm run build [249.322656ms]
```

And the artifact uploads:

```
[Staging and production/CI] ⭐ Run Main [simulated upload-artifact: dist]
[Staging and production/CI]   🐳  docker exec cmd=[bash --noprofile --norc -e -o pipefail /var/run/act/workflow/6.sh] user= workdir=.
[Staging and production/CI]   | -rw-r--r-- 1 root root 1466 Oct 26 12:37 .tmp/artifacts/dist.tar
[Staging and production/CI]   | SIMULATED upload of cicd-learn/dist as dist
[Staging and production/CI]   ✅  Success - Main [simulated upload-artifact: dist] [85.235263ms]
```

The job ends with `🏁 Job succeeded`.

### What `act` showed for the deploy jobs (and why it is a false negative)

`docs/_logs/ch54.log` then ran `deploy-staging`, whose download step
reported:

```
[Staging and production/Deploy to staging] ⭐ Run Main [simulated download-artifact: dist]
[Staging and production/Deploy to staging]   🐳  docker exec cmd=[bash --noprofile --norc -e -o pipefail /var/run/act/workflow/0.sh] user= workdir=.
[Staging and production/Deploy to staging]   ❗  ::error::artifact dist not found
[Staging and production/Deploy to staging]   ❌  Failure - Main [simulated download-artifact: dist] [63.402474ms]
```

That `artifact dist not found` is an `act` limitation, not a workflow bug.
`act` simulates the artifact service with a local tar file and does not carry
artifacts between jobs the way GitHub's service does. The same workflow shape
passed chapter 20's `verify-artifact-chain.sh` end to end, which is why this
chapter states the transfer as verified. On GitHub the download succeeds and
prints:

```
deploying 2887 bytes to staging
url: https://staging.example.com
```

and then `deploy-production` (after approval) prints:

```
deploying 2887 bytes to production
url: https://example.com
```

### What a real GitHub run adds (not verified locally)

With `staging` and `production` environments configured (chapter 28):

1. `ci` runs and passes as shown.
2. `deploy-staging` runs immediately (no reviewers on staging). It downloads
   `dist`, deploys, and records a deployment with its URL. Staging is now
   live.
3. `deploy-production` is created but does **not** start. The Actions tab
   shows it with a yellow "Waiting" badge: "Waiting for approval from
   required reviewers."
4. Reviewers are notified. One opens the run and clicks "Review
   deployments" → selects `production` → "Approve and deploy".
5. After any wait timer, `deploy-production` starts, downloads the same
   `dist` artifact, deploys, and records a deployment with its URL.
6. GitHub shows both deployments under the repository's Deployments page, with
   commit, environment, URL and approver.

If `production` has a deployment-branch rule of "only `main`", a workflow
triggered from a feature branch that declares `environment: production` is
rejected before it runs.

### What `act` cannot show

- **The environment gate.** Required reviewers, wait timers, deployment
  branches. Chapter 24/28.
- **Environment-scoped secrets.** `PRODUCTION_DATABASE_URL` injected only into
  the production job. Chapter 24.
- **The concurrency lock.** Two production deploys serialising. Chapter 21.
- **The deployment record.** The audit trail under Deployments.
- **The artifact transfer between jobs**, which `act` simulates poorly; use
  `verify-artifact-chain.sh` to prove it locally instead.

## 5. When to use it and when NOT to

**Use separate staging and production environments when:**

- **You deploy to real users.** Production deserves a gate; staging does not.
- **You want a final check before production.** Staging catches the bugs that
  pass CI but fail in a real environment (config, secrets, network).
- **Credentials differ by target.** Environment secrets keep production
  credentials out of staging jobs.
- **You want an audit trail.** GitHub records each deployment with its
  commit, URL and approver.
- **You want branch restrictions.** "Only `main` may deploy to production"
  as a rule, not a convention.

**Do NOT use staging/production split when:**

- **There is only one target.** An environment with no rules and no secrets
  is just a name.
- **Staging is never tested.** Then it is overhead. Either click through it
  or remove it.
- **You gate staging on approval.** That kills feedback speed. Gate
  production, automate staging.
- **You expect YAML to configure reviewers.** It cannot. Reviewers live in
  Settings. A workflow that declares `environment: production` against an
  environment with no reviewers runs with no gate.
- **You deploy continuously with no human in the loop.** Then you do not need
  an approval gate; use branch protection and automated checks instead.

## 6. Common mistakes

- **Leaking prod secrets into staging.** Symptom: a staging job can read the
  production database password. Fix: move secrets to environment scope, not
  repository scope. Chapter 24.
- **"Staging" nobody tests.** Symptom: staging is always broken and nobody
  notices until production breaks the same way. Fix: click through staging
  on every deploy, or automate a smoke test against it.
- **Deploying to the wrong environment.** Symptom: a job announces "deploying
  to production" while `environment.name` says `staging`. Fix: one source of
  truth; use `${{ ... }}` for the URL.
- **Forgetting `needs: [ci, deploy-staging]`.** Symptom: production deploys
  against untested code, or before staging has deployed. Fix: declare both
  dependencies.
- **`cancel-in-progress: true` on a deploy.** Symptom: a second push cancels
  a production deploy halfway through. Fix: `false`, always, for deploys.
  Chapter 21.
- **Missing required reviewers.** Symptom: production deploys with no human
  in the loop because the environment has no reviewers configured. Fix:
  configure reviewers in Settings, not YAML.
- **Declaring an environment that does not exist.** Symptom: the job fails
  instantly with "environment not found". Fix: create the environment first.
- **Hardcoding the environment name in a step.** Symptom: a deploy that
  announces the wrong target. Fix: keep one source of truth.
- **Assuming `act` shows the gate.** It does not. Symptom: "I tested it
  locally and there was no approval step." Fix: verify on GitHub.
- **Using repository secrets for production.** Symptom: every job, including
  PR checks, can read the production credential. Fix: environment secrets.

## 7. Try it yourself

**Exercise: prove the gate and the transfer.**

Part A — the verified CI half:

1. Run the workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/54-staging-production.yml "" push ch54
   ```

   Confirm `ci` passes, lint/test/build succeed, and the artifact uploads.
   That is the part `act` can show.

2. **Prove the transfer.** Run the artifact chain:

   ```bash
   ./scripts/verify-artifact-chain.sh .github/workflows/54-staging-production.yml ci deploy-staging ch54-chain
   ```

   Confirm the consumer prints `deploying 2887 bytes to staging` (or the
   equivalent). That proves the artifact crosses the job boundary. Revert
   any edits.

Part B — on GitHub, for real:

3. **Create the environments.** Settings → Environments → create `staging`
   (no reviewers) and `production` (add yourself as a required reviewer, plus
   a 1-minute wait timer, deployment branch `main` only).

4. **Add environment secrets.** On each environment, add a secret
   `DEPLOY_TOKEN` with a different value per environment.

5. **Push to `main`.** `ci` passes, `deploy-staging` runs immediately and
   prints the staging URL. `deploy-production` enters "Waiting".

6. **Approve.** Open the run, click "Review deployments", select
   `production`, approve. After the wait timer, production deploys and
   prints its URL.

7. **Prove the scoping.** Add a step to each deploy job that prints the
   length of `${{ secrets.DEPLOY_TOKEN }}`. The two jobs see different
   lengths (or different values if you print a hash). Revert.

8. **Prove the branch restriction.** Trigger the workflow from a feature
   branch with `environment: production`. The job is rejected before it
   runs. Revert.

9. **Break it on purpose.** Change `name: staging` to `name: does-not-exist`
   and push. The job fails instantly with "environment not found". Revert.

10. **Break it on purpose, part two.** Set `cancel-in-progress: true` on
    `deploy-production` and push twice to `main`. The second push cancels
    the first production deploy mid-flight. Revert immediately.

11. **Clean up.** Delete the test environments and their secrets, or keep
    them if you are continuing.

**Hint:** `act` does not implement environments at all, so every step that
involves a gate, a reviewer, a timer, or an environment-scoped secret must
be done on GitHub. The local run is useful only to confirm the YAML parses
and the job graph is right.

## 8. Next

You now have a pipeline with a staging gate and a production gate. The next
pattern makes the trigger itself a version number: a Git tag drives the
whole release.

→ [55 — A release pipeline driven by Git tags](55-pattern-tag-driven-release.md)
EOF
echo written