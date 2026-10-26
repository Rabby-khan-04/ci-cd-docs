# 24 — Environments and their secrets

> **Verification.** The workflow in this chapter is
> `.github/workflows/28-environments-and-approvals.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/28-environments-and-approvals.yml "" push ch28`,
> and the full log is at `docs/_logs/ch28.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/28-environments-and-approvals.yml (2 job(s))`.
>
> **What this local execution cannot prove.** `act` has no concept of an
> environment. It does not read Settings → Environments, it does not enforce
> required reviewers, it does not gate a job on approval, and it does not inject
> environment-scoped secrets or variables. The run in `docs/_logs/ch28.log`
> proves that the `ci` job runs its steps and that the `deploy` job, once `ci`
> succeeds, runs its steps immediately with no human in the loop. The
> protection rules, the approval wait, the "waiting" badge, and the
> environment-scoped secret injection are GitHub-only behaviours and are
> described here from the documentation, not from a local run. Chapter 28
> returns to environments from the approval angle.

---

## 1. Simple explanation (like I'm 7)

Imagine two doors in a school: the classroom door and the principal's office
door. The classroom is open to everyone with a student card. The principal's
office needs the principal to buzz you in, and only after you have explained
why you are there.

A **deployment environment** is the principal's office. `staging` and
`production` are not just names; they are doors with their own rules. A job
that says `environment: production` is asking to be let into the production
door. GitHub checks the rules on that door — who is allowed in, whether
someone has to approve, whether a timer must pass — and only then runs the
job. If the rules say "the principal must approve," the job sits in the
hallway, marked "waiting," until the principal clicks approve.

The secrets behind that door are different too. The staging door has the
staging database password; the production door has the production database
password. A job that walks through the staging door never sees the production
password, even though both are configured in the same repository. That is the
whole point of environments: **scope credentials to a target, and put a human
between code and that target.**

## 2. Real name

### Environment (GitHub Actions)

A named target for a deployment: `staging`, `production`, `qa`, whatever you
name it. Created in the repository's Settings → Environments. A job opts in
with `environment: name: production`. The environment is where protection
rules and environment-scoped secrets live.

### Protection rules

Rules attached to an environment that must be satisfied before a job bound to
it is allowed to run. Configured in the UI, not in YAML. The main ones:

- **Required reviewers** — one or more people who must approve the run before
  the job starts.
- **Wait timer** — a delay (in minutes) before the job is eligible to run,
  after approval if reviewers are also required.
- **Deployment branches** — which branches may deploy to this environment
  (e.g. only `main`).
- **Custom deployment protection rules** — webhooks to external systems
  (added later; not covered here).

### Environment secret

A secret scoped to an environment. Only jobs that declare that environment
receive it. Set under Settings → Environments → (environment) → Environment
secrets. Same mechanics as a repository secret, narrower scope.

### Environment variable

A variable scoped to an environment, same idea, plain text. Set under the same
page. Useful for per-environment URLs and flags.

### `environment:` (job key)

The block on a job that binds it to an environment:

```yaml
environment:
  name: production
  url: https://example.com
```

`name` selects the environment (must exist in Settings, or the job fails
immediately with "environment not found"). `url` is optional and shows up as
a clickable link in the run summary and in the deployment history.

### Required reviewer

A person (or team) configured on an environment's protection rules who must
approve a run before its job proceeds. Approval happens in the Actions tab
or via the GitHub API/CLI. There is no YAML key for it, and no way to
auto-approve from a workflow.

### Deployment

The record GitHub keeps of a job that ran against an environment: when, by
whom, which commit, which URL. Visible under the repository's "Deployments"
and in the environment's own page. Chapter 27.

### Environment vs repository scope

| Scope | Secret available to | Configured where |
| ----- | ------------------- | ---------------- |
| Repository | Every job in every workflow | Settings → Secrets and variables → Actions → Secrets |
| Environment | Only jobs declaring that environment | Settings → Environments → (env) → Environment secrets |

A repository secret is the wider, more dangerous scope. Prefer environment
secrets for anything that targets a specific deployment.

## 3. Workflow example

This is the complete `.github/workflows/28-environments-and-approvals.yml` from
this repository.

```yaml
name: Environments and approvals

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── A job with no environment: runs immediately ──────────────────────────
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

  # ── A job bound to an environment ────────────────────────────────────────
  # The environment must exist in Settings -> Environments. If it does not, the
  # job fails immediately with "environment not found".
  #
  # Required reviewers (configured in the environment's protection rules) turn
  # this job into a manual gate: it sits in "waiting" until someone approves.
  # There is no way to approve from YAML; the UI is the only mechanism.
  deploy:
    name: Deploy to staging
    runs-on: ubuntu-24.04
    needs: [ci]
    environment:
      name: staging
      url: https://staging.example.com
    steps:
      - name: Deploy (simulated)
        run: |
          echo "deploying to staging"
          echo "url: https://staging.example.com"
```

Three structural things to notice:

1. `ci` has no `environment:` and runs the moment it is scheduled. `deploy`
   has `environment:` and is subject to that environment's protection rules.
2. `deploy` declares `needs: [ci]`, so it cannot start until CI is green
   *and* the environment's rules are satisfied. Two independent gates, both
   must pass.
3. `url:` is not a deploy target; it is a label. The actual deploy command
   lives in the steps. GitHub uses `url:` to draw a link in the run summary
   and to record the deployment's URL.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch28.log` runs both jobs. `ci` completes normally:

```
[Environments and approvals/CI] ⭐ Run Main npm ci
[Environments and approvals/CI]   | added 127 packages, and audited 128 packages in 1s
[Environments and approvals/CI] ⭐ Run Main npm run lint
[Environments and approvals/CI]   ✅  Success - Main npm run lint
[Environments and approvals/CI] ⭐ Run Main npm test
[Environments and approvals/CI]   ✅  Success - Main npm test
[Environments and approvals/CI] 🏁  Job succeeded
```

Then `deploy` starts immediately, with no approval gate, because `act` does
not implement environments:

```
[Environments and approvals/Deploy to staging] ⭐ Run Main Deploy (simulated)
[Environments and approvals/Deploy to staging]   | deploying to staging
[Environments and approvals/Deploy to staging]   | url: https://staging.example.com
[Environments and approvals/Deploy to staging]   ✅  Success - Main Deploy (simulated) [65.515948ms]
[Environments and approvals/Deploy to staging] 🏁  Job succeeded
```

That immediate run is the honest limit of local execution: the job graph and
the steps are real, the gate is not.

### What a real GitHub run adds (not verified locally)

With a `staging` environment that has required reviewers configured:

1. `ci` runs and passes as shown.
2. `deploy` is created but does **not** start. The Actions tab shows it with a
   yellow "Waiting" badge and a note: "Waiting for approval from required
   reviewers."
3. The configured reviewers receive a notification. One of them opens the run
   and clicks "Review deployments" → selects `staging` → "Approve and deploy".
4. Only then does `deploy` start, run its steps, and record the deployment
   with its URL.

If the environment also has a wait timer of, say, 5 minutes, the job waits
that long *after* approval before starting. Both rules are configured in the
UI; neither appears in the YAML.

If the environment does not exist at all, the job fails instantly with
"environment not found" and never runs a step. That failure is the most
common first-time mistake, and it is the reason the workflow's comment says
the environment must be created first.

### Environment-scoped secrets and variables

Once an environment exists, you can add secrets and variables to it:

1. Settings → Environments → click the environment (e.g. `staging`).
2. "Environment secrets" → "Add secret": name `DATABASE_URL`, value
   `postgres://staging...`.
3. "Environment variables" → "Add variable": name `API_BASE_URL`, value
   `https://staging-api.example.com`.

A job bound to `staging` reads them exactly as before:

```yaml
deploy:
  environment:
    name: staging
  steps:
    - name: Use the environment secret
      env:
        DATABASE_URL: ${{ secrets.DATABASE_URL }}
      run: |
        # This is the STAGING database URL, because this job declared
        # environment: staging. A job bound to production gets a different
        # value under the same name.
        migrate --url "$DATABASE_URL"
```

The same expression, `secrets.DATABASE_URL`, resolves to different values
depending on which environment the job declared. That is the scoping, and it
is why environment secrets are safer than repository secrets: a job can only
read the secrets of the environment it was allowed to enter.

### Branch and reviewer rules

Two protection rules worth configuring on a real environment:

- **Deployment branches.** Restrict `production` to `main` only. Then a
  workflow triggered from a feature branch that declares
  `environment: production` is rejected before it runs, even if everything
  else passes. This is the backstop against "I deployed from a branch by
  mistake."
- **Required reviewers.** At least one human for `production`, zero for
  `staging` if you want staging to deploy automatically. The asymmetry
  (auto-deploy staging, gated production) is the standard shape.

## 5. When to use it and when NOT to

**Use environments when:**

- **You deploy to more than one target.** Staging and production are the
  obvious pair; a second region or a canary slot also qualifies.
- **A deploy should need a human.** Production deploys that gate on approval
  are the primary reason environments exist.
- **Credentials differ by target.** Environment secrets keep the production
  database password out of staging jobs.
- **You want a deployment history.** GitHub records each run against the
  environment, with its URL and commit, which is the audit trail.
- **You want branch restrictions.** "Only `main` may deploy to production"
  is a rule, not a convention, when it is an environment protection rule.

**Do NOT use environments when:**

- **There is only one target and no approval needed.** An environment with no
  protection rules and no secrets is just a name; it adds a Settings page
  and nothing else.
- **You want to gate CI, not deploys.** Environments gate jobs; if the job is
  a test job, you are using the wrong tool. Use `needs:` and branch
  protection (chapter 34) for CI gating.
- **You put required reviewers on staging.** A staging environment that needs
  approval stops being useful for fast feedback. Gate production, automate
  staging.
- **You expect YAML to configure the reviewers.** It cannot. The reviewers
  live in Settings. A workflow that declares `environment: production` against
  an environment with no reviewers runs with no gate, and that is a
  configuration error in the UI, not in the file.

## 6. Common mistakes

- **Declaring an environment that does not exist.** The job fails immediately
  with "environment not found" and runs no steps. Symptom: a red job with no
  log beyond the setup. Fix: create the environment in Settings first, then
  re-run.
- **Assuming `act` will show the approval gate.** It will not; the job runs
  immediately. Symptom: "I tested it locally and there was no approval step,
  so the environment is broken." It is not; `act` ignores environments. Verify
  on GitHub.
- **Putting secrets in repository scope that belong in environment scope.**
  A production password stored as a repository secret is readable by every
  job, including staging jobs and PR checks. Symptom: a staging job can read
  the production credential. Fix: move it to the environment's secrets.
- **Forgetting `needs: [ci]`.** An environment-gated deploy that does not
  depend on CI can run against untested code. Symptom: a deploy that skips
  the tests. Fix: always `needs:` the CI job.
- **Using `environment:` on a job that is not a deploy.** The word
  "environment" sounds generic. Symptom: a lint job bound to production,
  which then requires approval to lint. Fix: reserve `environment:` for jobs
  that actually deploy or touch the target.
- **Hardcoding the environment name in a step.** `echo "deploying to
  production"` while `environment.name` says `staging`. Symptom: a deploy
  that announces the wrong target. Fix: use `${{ ... }}` or keep one source
  of truth.
- **Expecting environment variables to be masked.** They are not; they are
  plain text. Symptom: a value you thought was hidden appears in the log.
  Fix: if it is sensitive, make it an environment *secret*, not a variable.
- **Configuring reviewers but not testing the flow.** The first real
  production deploy is a bad time to discover that the reviewers do not have
  the right permissions or that the notification went to the wrong people.
  Symptom: a stuck deploy at 2am. Fix: do a dry run to staging with reviewers
  enabled before you need it.

## 7. Try it yourself

**Exercise: create an environment and watch a job gate on it.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/28-environments-and-approvals.yml "" push ch28
   ```

   Confirm `ci` passes and `deploy` prints "deploying to staging". That is all
   `act` can show; there is no gate and no environment-scoped secret.

2. **Create the environment on GitHub.** Settings → Environments → "New
   environment" → name `staging`. Add a required reviewer (yourself) and a
   1-minute wait timer. Save.

3. **Add an environment secret.** On the `staging` environment page, add a
   secret `DEMO_DB_URL` with value `postgres://staging`. Add an environment
   variable `API_BASE_URL` with value `https://staging.example.com`.

4. **Re-run the workflow on GitHub.** `ci` passes, then `deploy` enters
   "Waiting" state. Approve it. After the wait timer, it runs and prints the
   simulated deploy. Check the run summary: the `url:` link is present.

5. **Prove the scoping.** Add a step to `deploy` that prints
   `${{ secrets.DEMO_DB_URL }}` indirectly (e.g. its length). It resolves to
   the staging value. Then create a `production` environment with a different
   `DEMO_DB_URL` and a second job bound to it; the two jobs see different
   values under the same name. Revert the edits.

6. **Prove the branch restriction.** Configure `production` to allow
   deployments only from `main`. Trigger the workflow from a feature branch
   with `environment: production`. The job is rejected before it runs. Revert
   the workflow edit.

7. **Break it on purpose.** Change `name: staging` to `name: does-not-exist`
   and push. The job fails instantly with "environment not found". Revert.

8. **Clean up.** Delete the `staging` environment and its secret/variable
   (or keep them if you are continuing to chapter 28), so you are not leaving
   test configuration around.

**Hint:** `act` does not implement environments at all, so every step of this
exercise that involves a gate, a reviewer, a timer, or an environment-scoped
secret must be done on GitHub. The local run is useful only to confirm that
the YAML parses and the job graph is right.

## 8. Next

You now know how to scope credentials to a target and put a human in front of
it. The next chapter is about the credential that exists in every run
automatically, whether you asked for it or not: `GITHUB_TOKEN`.

→ [25 — `GITHUB_TOKEN` and permissions](25-token-permissions.md)