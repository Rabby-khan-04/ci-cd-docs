# CI/CD from zero to advanced — the roadmap

Read this page first. It is the map. Every chapter listed here exists as its own
file, and the checkbox in the checklist at the bottom gets ticked as each chapter
is finished.

Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

---

## Verified versions (the numbers every chapter is written against)

Everything in this course was run against these exact versions. If you see a
different version anywhere in these docs, trust the table below.

| Thing | Version | Note |
| ----- | ------- | ---- |
| Node.js (local) | `v24.19.0` | `cicd-learn/package.json` declares `engines.node: ">=22"` |
| npm | `11.17.0` | |
| Runner image | `ubuntu-24.04` | Pinned, never `ubuntu-latest`. See ch. 07. |
| `actions/checkout` | `v7` (SHA `3d3c42e5aac5ba805825da76410c181273ba90b1`) | |
| `actions/setup-node` | `v7` (SHA `949feb2413d6458794dcd2491c4babbbce0c15c1`) | |
| `actions/cache` | `v6` (SHA `55cc8345863c7cc4c66a329aec7e433d2d1c52a9`) | |
| `actions/upload-artifact` | `v7` (SHA `cf430e030ddbb5b0abf93d22962f4752f3646cd9`) | |
| `actions/download-artifact` | `v8` (SHA `9000827ccba6bdab643e8b6fd33ac0654aef8333`) | |
| `actions/configure-pages` | `v6` (SHA `45bfe0192ca1faeb007ade9deae92b16b8254a0d`) | |
| `actions/upload-pages-artifact` | `v5` (SHA `fc324d3547104276b827a68afc52ff2a11cc49c9`) | |
| `actions/deploy-pages` | `v5` (SHA `368f82528645a54fb793d4d04e342629a3f51346`) | |
| `docker/setup-buildx-action` | `v4` (SHA `f87e5991a6d7451dcb8d9637bfbc97413f497069`) | |
| `docker/login-action` | `v4` (SHA `dbcb813823bdd20940b903addbd779551569679f`) | |
| `docker/build-push-action` | `v7` (SHA `c3c9e263c25d99ce0380d002d59b67737d91b0dc`) | |
| `docker/metadata-action` | `v6` (SHA `dc802804100637a589fabce1cb79ff13a1411302`) | |
| `github/codeql-action` | `v4` (SHA `7999b86c43a865dc79d8923397f35af22de63401`) | |
| `actions/dependency-review-action` | `v5.0.0` (SHA `a1d282b36b6f3519aa1f3fc636f609c47dddb294`) | |
| `appleboy/ssh-action` | `v1` (SHA `0ff4204d59e8e51228ff73bce53f80d53301dee2`) | |
| `codecov/codecov-action` | `v7` | |
| `slackapi/slack-github-action` | `v4` (SHA `dcb1066f776dd043e64d0e8ba94ca15cc7e1875d`) | |
| `softprops/action-gh-release` | `v3` | |
| Sample app deps | `vitest 5.0.3`, `eslint 10.12.0`, `esbuild 0.28.2` | |

Sources of truth for this course, in priority order:

1. The real run logs of `cicd-learn` on your repository. If the docs and the run
   disagree, the run wins and the chapter gets corrected.
2. <https://docs.github.com/en/actions>
3. <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax>
4. <https://github.com/marketplace?type=actions>

Chapters marked **[read-only example]** were not executed, because they need
credentials or infrastructure you do not have (cloud accounts, a real server,
a real registry login). Each one tells you that up front and ends with a free
alternative you *can* run today.

---

## Part 1 — Concepts (no YAML yet)

1. **What is CI/CD?** — the three words, what each one means, and the difference
   between continuous integration, continuous delivery, and continuous
   deployment. Why teams bother.
   → `01-what-is-cicd.md`
2. **Anatomy of a pipeline** — trigger, workflow, job, step, runner, artifact,
   and how a commit flows through them. The vocabulary used by every later
   chapter.
   → `02-anatomy-of-a-pipeline.md`
3. **How GitHub Actions fits in** — where it sits compared to other CI tools, and
   what it costs.
   → `03-github-actions-in-the-landscape.md`

## Part 2 — GitHub Actions basics

4. **Your first workflow** — `.github/workflows/`, YAML in 10 minutes, a workflow
   that says hello, and reading the result in the Actions tab.
   → `04-first-workflow.md`
5. **YAML for workflows** — indentation, lists, keys, the traps that break a file
   silently (tabs, `on` vs `true`, unquoted `on`).
   → `05-yaml-for-workflows.md`
6. **Events and triggers** — `push`, `pull_request`, `schedule`, `workflow_dispatch`,
   plus branches, tags, and path filters.
   → `06-events-and-triggers.md`
7. **Runners** — what a runner is, `ubuntu-24.04` vs `ubuntu-latest`, what is
   preinstalled, and why you pin.
   → `07-runners.md`
8. **Jobs and steps** — `runs-on`, `steps`, `run` vs `uses`, `with`, order, and
   the fact that each step shares one workspace.
   → `08-jobs-and-steps.md`
9. **Using actions** — `actions/checkout` and `actions/setup-node`, what an action
   is, and what `with:` keys do.
   → `09-using-actions.md`
10. **Reading logs** — the Actions tab, expanding steps, exit codes, the
    "annotations" pane, and how to copy the exact failing command.
    → `10-reading-logs.md`

## Part 3 — Building a real CI pipeline

11. **Install** — `npm ci` vs `npm install`, why the lock file matters, and
    `package-lock.json` behaviour in CI.
    → `11-install-step.md`
12. **Lint** — running ESLint in CI, exit codes as pass/fail, and making the
    log readable.
    → `12-lint-step.md`
13. **Test** — running Vitest in CI, reading a failure, and what a red test does
    to the pipeline.
    → `13-test-step.md`
14. **Build** — running the esbuild step in CI and keeping the output as an
    artifact.
    → `14-build-step.md`
15. **Putting it together: the order** — lint → test → build, why that order, and
    one workflow that does all four.
    → `15-ci-pipeline-order.md`

## Part 4 — Speed and structure

16. **Caching dependencies** — `actions/setup-node` `cache: npm`, `actions/cache`,
    what a cache key is, and how to prove it worked from the log.
    → `16-caching.md`
17. **Matrix builds** — testing several Node versions at once, `fail-fast`,
    `include`, and reading a matrix run.
    → `17-matrix-builds.md`
18. **Job dependencies and parallel jobs** — `needs:`, what runs in parallel vs
    in series, and job outputs.
    → `18-jobs-dependencies-and-parallelism.md`
19. **Conditionals** — `if:`, `always()`, `success()`, `failure()`, and skipping
    jobs on the wrong branch.
    → `19-conditionals.md`
20. **Artifacts** — `upload-artifact` / `download-artifact`, retention,
    `if: always()`, and why jobs do not share a filesystem.
    → `20-artifacts.md`
21. **Concurrency** — cancelling superseded runs, `concurrency` groups, and not
    deploying twice at once.
    → `21-concurrency.md`

## Part 5 — Secrets and configuration

22. **Secrets** — repo secrets, `secrets` context, adding them in the UI, and
    why they are not environment variables.
    → `22-secrets.md`
23. **Variables** — non-secret config (`vars`), when to use a variable instead of
    a secret.
    → `23-variables.md`
24. **Environments and their secrets** — environment-scoped secrets, required
    reviewers, and environment protection rules.
    → `24-environment-secrets.md`
25. **`GITHUB_TOKEN` and permissions** — what the token can do, `permissions:`,
    least privilege per job, and `pull_request_target` danger.
    → `25-token-permissions.md`
26. **Not leaking secrets** — masking, forks, debug logs, `set -x`, log
    injection, and what to do when a secret leaks.
    → `26-secret-safety.md`

## Part 6 — Deployment

27. **Deployment fundamentals** — deploying means what, the staging/production
    split, and why deploys are separated from CI.
    → `27-deployment-fundamentals.md`
28. **Environments and manual approvals** — creating environments, required
    reviewers, and a human in the loop.
    → `28-environments-and-approvals.md`
29. **Deploying a static site to GitHub Pages** **[runnable]** — build, upload the
    artifact, deploy, and read the deployed URL.
    → `29-github-pages-deploy.md`
30. **Building a Docker image** **[runnable]** — `buildx`, layer caching,
    multi-stage, and tagging.
    → `30-docker-image-build.md`
31. **Pushing an image to a registry** **[read-only example]** — GitHub Packages
    (free, no extra account) with a free local alternative using a local daemon.
    → `31-container-registry-push.md`
32. **Deploying over SSH** **[read-only example]** — key-based auth, `appleboy/ssh-action`,
    and a free alternative that runs entirely in the workflow.
    → `32-ssh-deploy.md`
33. **Deployment strategies** — rolling, blue-green, canary, recreate, and when
    each is worth it.
    → `33-deployment-strategies.md`

## Part 7 — Quality and safety

34. **Branch protection and required checks** — turning CI into a gate, required
    status checks, and why a required check that never runs blocks you.
    → `34-branch-protection.md`
35. **Code coverage** — measuring it, thresholds that fail the build, and what
    coverage does *not* tell you.
    → `35-code-coverage.md`
36. **Dependency updates with Dependabot** — version bumps, security updates, and
    grouping.
    → `36-dependabot.md`
37. **Security scanning: CodeQL** **[runnable]** — a SAST workflow on your own
    code, plus `push security advisories`.
    → `37-codeql.md`
38. **Secret scanning and push protection** — turning it on, what it finds, and
    `GITHUB_TOKEN` scoping.
    → `38-secret-scanning.md`
39. **Pinning actions** — version tags vs commit SHAs, Dependabot for actions,
    and the actual attack this prevents.
    → `39-pinning-actions.md`

## Part 8 — Advanced

40. **Reusable workflows** — `workflow_call`, inputs, secrets, outputs, and
    `caller`/`callee` permissions.
    → `40-reusable-workflows.md`
41. **Composite actions** — bundling steps into `.github/actions/`, vs a
    workflow vs a container action.
    → `41-composite-actions.md`
42. **Self-hosted runners** **[read-only example]** — what they are for, security
    warnings, and a free alternative (larger runners / `act`).
    → `42-self-hosted-runners.md`
43. **OIDC and cloud authentication** **[read-only example]** — keyless auth to
    AWS/GCP/Azure, no long-lived keys, and a free alternative you can run.
    → `43-oidc-cloud-auth.md`
44. **Monorepo pipelines** — path filters, changed-package detection, affected
    projects, and caching per package.
    → `44-monorepo-pipelines.md`
45. **Release automation and semantic versioning** — Conventional Commits,
    automated version bumps, changelogs, and GitHub Releases from a tag.
    **[read-only example]** for the publish step.
    → `45-release-automation-semver.md`
46. **Rollbacks** — rolling back a release, reverting a deploy, database-shaped
    rollbacks, and the limits of automation.
    → `46-rollbacks.md`

## Part 9 — Operations

47. **Debugging failed runs** — a repeatable triage order, `act` for local
    reproduction, and the top real causes of red builds.
    → `47-debugging-failed-runs.md`
48. **Re-running jobs** — re-run failed jobs vs re-run all, re-running on a
    different runner, and debugging with SSH.
    → `48-re-running-jobs.md`
49. **Cost and usage limits** — free minutes for public vs private repos, per-minute
    rates, artifact retention, and keeping bills sane.
    → `49-cost-and-limits.md`
50. **Notifications** — GitHub's own notifications, email, and Slack via
    `slackapi/slack-github-action` **[read-only example]** with a free
    alternative (GitHub's built-in email).
    → `50-notifications.md`

## Part 10 — Real-world patterns

51. **A Next.js app with a preview URL on every pull request** **[read-only
    example]** — lint, test, build, preview deploy; and the pitfalls. Free
    alternative: build the app in CI and post the artifact size as a comment.
    → `51-pattern-nextjs-preview.md`
52. **A containerized service** **[runnable]** — build the image, prove it runs,
    push on tags only.
    → `52-pattern-containerized-service.md`
53. **Database migrations, safely** **[read-only example]** — expand/contract,
    running migrations once per deploy, and a free alternative with a SQLite
    file you can migrate locally.
    → `53-pattern-database-migrations.md`
54. **Separate staging and production environments** **[runnable]** — two
    environments, different URLs, different secrets, one workflow.
    → `54-pattern-staging-and-production.md`
55. **A release pipeline driven by Git tags** **[runnable]** — tag → build →
    release → deploy, and what breaks if you tag twice.
    → `55-pattern-tag-driven-release.md`

## Part 11 — Wrapping up

56. **Other platforms: same ideas, different syntax** — GitLab CI, Jenkins,
    CircleCI. Concepts map one-to-one; only the YAML differs.
    → `56-other-platforms.md`
57. **Where to go next** — your own checklist for a real repository, and how to
    keep learning.
    → `57-next-steps.md`

---

## Real-world patterns (summary)

Each pattern gets its own chapter. All five are listed above; this is the shape
of each at a glance.

| Pattern | Chapter | Status | Pitfalls covered |
| ------- | ------- | ------ | ---------------- |
| Next.js app with a preview URL per PR | `51-pattern-nextjs-preview.md` | read-only + free alternative | deploy credentials in PRs, `pull_request_target`, cache thrash, runaway preview environments |
| Containerized service | `52-pattern-containerized-service.md` | runnable | building on every push, no layer cache, pushing to `latest` only, untagged images |
| Database migrations | `53-pattern-database-migrations.md` | read-only + free alternative | running migrations twice, destructive migrations, migrations not in a transaction, running them in parallel jobs |
| Staging vs production | `54-pattern-staging-and-production.md` | runnable | leaking prod secrets into staging, "staging" nobody tests, deploying to the wrong environment |
| Tag-driven release | `55-pattern-tag-driven-release.md` | runnable | tagging a commit that never passed CI, re-running a tag, publishing twice, mutable tags |

## Chapters that are read-only, and why

| Chapter | Blocked by | Free alternative provided |
| ------- | ---------- | ------------------------- |
| 31 container registry push | Needs a registry login / cloud account | Build the image locally in the workflow, load it, run a smoke test, no push |
| 32 SSH deploy | Needs a real server | Run the deploy script inside the runner against a local target directory |
| 42 self-hosted runners | Needs a machine you control | Larger runners + `act` locally |
| 43 OIDC cloud auth | Needs an AWS/GCP/Azure account | Show the token request, verify its claims, never exchange it |
| 45 release automation (publish part) | Needs npm registry or a paid org | Tag → build → GitHub Release only, no publish to npm |
| 51 Next.js preview deploy | Needs a hosting account | Full CI pipeline + artifact + summary comment |
| 53 database migrations | Needs a real database | SQLite file in the workspace, migrated inside the runner |

---

## Checklist

One box per topic. Ticked as the chapter lands.

### Part 1 — Concepts
- [x] 01 What is CI/CD
- [x] 02 Anatomy of a pipeline
- [x] 03 GitHub Actions in the landscape

### Part 2 — GitHub Actions basics
- [x] 04 Your first workflow
- [x] 05 YAML for workflows
- [x] 06 Events and triggers
- [x] 07 Runners
- [x] 08 Jobs and steps
- [x] 09 Using actions
- [x] 10 Reading logs

### Part 3 — Building a CI pipeline
- [x] 11 Install
- [x] 12 Lint
- [x] 13 Test
- [x] 14 Build
- [x] 15 The order, end to end

### Part 4 — Speed and structure
- [x] 16 Caching dependencies
- [x] 17 Matrix builds
- [x] 18 Job dependencies and parallelism
- [x] 19 Conditionals
- [x] 20 Artifacts
- [x] 21 Concurrency

### Part 5 — Secrets and configuration
- [x] 22 Secrets
- [x] 23 Variables
- [x] 24 Environment secrets
- [x] 25 `GITHUB_TOKEN` and permissions
- [x] 26 Secret safety

### Part 6 — Deployment
- [x] 27 Deployment fundamentals
- [x] 28 Environments and manual approvals
- [x] 29 Deploy to GitHub Pages
- [x] 30 Build a Docker image
- [x] 31 Push to a registry
- [x] 32 Deploy over SSH
- [x] 33 Deployment strategies

### Part 7 — Quality and safety
- [x] 34 Branch protection and required checks
- [x] 35 Code coverage
- [x] 36 Dependabot
- [x] 37 CodeQL
- [x] 38 Secret scanning
- [x] 39 Pinning actions

### Part 8 — Advanced
- [x] 40 Reusable workflows
- [x] 41 Composite actions
- [x] 42 Self-hosted runners
- [x] 43 OIDC cloud auth
- [x] 44 Monorepo pipelines
- [x] 45 Release automation and semver
- [x] 46 Rollbacks

### Part 9 — Operations
- [x] 47 Debugging failed runs
- [x] 48 Re-running jobs
- [x] 49 Cost and limits
- [x] 50 Notifications

### Part 10 — Real-world patterns
- [x] 51 Next.js preview pipeline
- [x] 52 Containerized service pipeline
- [x] 53 Safe database migrations
- [x] 54 Staging and production
- [x] 55 Tag-driven release

### Part 11 — Wrap-up
- [x] 56 Other platforms
- [x] 57 Next steps

---

## How the writing works

- One file per topic. No combining. If a topic is too big, it becomes `05a`,
  `05b`, and so on.
- Every chapter follows the same eight-part template: simple explanation, real
  name, workflow example, what you should see, when to use it, common mistakes,
  try it yourself, next.
- Every workflow is executed on the real `cicd-learn` repository before its
  chapter is written. Chapter 04 onward quote actual run logs, not invented ones.
- No secrets in any file. Placeholders only, plus UI instructions.
- Actions are pinned by major version in early chapters, then by SHA in
  chapter 39 where the reasoning is explained.
- Nothing is deployed to production and no other repository is touched, ever,
  without asking first.