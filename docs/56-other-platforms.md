# 56 — Other platforms: same ideas, different syntax

> **Verification.** This is a **concept chapter**: there is **no workflow** and
> **no log**. The comparison table in section 2 is built from the official
> documentation of each platform (GitLab CI, Jenkins, CircleCI) and from
> chapter 03 of this course, which covers the same comparison at a higher
> level. No command was executed. `python3 scripts/validate-workflows.py` has
> nothing to check here.

---

## 1. Simple explanation (like I'm 7)

Imagine four schools that all teach the same subject. The classrooms look
different, the bells ring at different times, and the teachers use different
words for the same things ("homework" vs "assignment" vs "problem set"), but
the subject is the same: someone writes something, someone checks it,
someone ships it. A student who knows the subject can walk into any of the
four schools and be productive in a week.

**CI/CD platforms** are those schools. GitHub Actions, GitLab CI, Jenkins and
CircleCI all do the same job: trigger, build, test, deploy. The concepts
you learned in this course (trigger, workflow, job, step, runner, artifact,
cache, secret, environment, approval, concurrency) exist in all four. Only
the YAML syntax and the file location differ. If you know one, you know the
shape of all of them.

## 2. Real name

### The four platforms

- **GitHub Actions** — built into GitHub. Config in `.github/workflows/*.yml`.
  Covered by this whole course.
- **GitLab CI** — built into GitLab. Config in `.gitlab-ci.yml` at the repo
  root.
- **Jenkins** — self-hosted server. Config in a `Jenkinsfile` (usually
  Groovy) at the repo root, or in the UI.
- **CircleCI** — SaaS (or self-hosted). Config in `.circleci/config.yml`.

### The concept map (one-to-one)

| Concept (this course) | GitHub Actions | GitLab CI | Jenkins | CircleCI |
| --- | --- | --- | --- | --- |
| Trigger | `on:` (push, PR, schedule, dispatch) | `rules:` / `workflow` rules / `only`/`except` | `triggers {}` block or webhook | `workflows:` with triggers |
| Workflow / pipeline file | `.github/workflows/*.yml` | `.gitlab-ci.yml` | `Jenkinsfile` | `.circleci/config.yml` |
| Job | `jobs:` entry | job (top-level key) | `stage` + `agent` | `jobs:` entry |
| Step | `steps:` list | `script:` list | `steps {}` | `steps:` list |
| Runner / executor | `runs-on:` | `tags:` / shared runners | `agent { label }` / node | `resource_class` / executor |
| Parallel jobs | separate jobs, no `needs:` | separate jobs, no `needs:` | parallel stages | `workflows:` fan-out |
| Job dependency | `needs:` | `needs:` | `stage` order | `requires:` |
| Artifact | `actions/upload-artifact` | `artifacts:` keyword | `archiveArtifacts` | `store_artifacts` |
| Cache | `actions/cache` / `cache:` | `cache:` keyword | `stash`/plugins | `save_cache`/`restore_cache` |
| Secret | `secrets.X` | CI/CD variables (masked) | Credentials plugin | project env vars |
| Environment | `environment:` | `environment:` keyword | not native | not native (contexts) |
| Manual approval | required reviewers (UI) | manual job (`when: manual`) | input step | approval job |
| Concurrency / lock | `concurrency:` | not native (resource groups) | not native (lockable resources plugin) | not native |
| Matrix | `strategy.matrix` | `parallel: matrix:` | matrix (declarative) | matrix (parameters) |
| Reusable config | reusable workflows / composite actions | `include:` / components | shared libraries | orbs |
| Container build | `docker/build-push-action` | `image:` + `services:` / Kaniko | Docker plugin | `setup_remote_docker` |

### Job (more precisely)

A unit of work that gets its own execution environment (runner/container). In
all four platforms, jobs are the parallelism boundary and the place where you
choose the machine.

### Step / script

A single command or action inside a job. In all four, steps run sequentially
in the same environment and share a filesystem.

### Runner / executor / agent

The machine that runs a job. GitHub: `runs-on`. GitLab: shared or
group/project runners. Jenkins: `agent`. CircleCI: executor (Docker, machine,
macOS). Same idea, different word.

### Artifact (cross-platform)

A file saved by one job and downloaded by another, or by a human. All four
support it; the keyword differs.

### Cache (cross-platform)

Reusable storage keyed by a string, used to skip re-downloading
dependencies. All four support it; the key syntax differs.

### Secret (cross-platform)

A masked, encrypted value injected into a job at runtime. All four support
it; the storage location differs (repo settings, project variables, Jenkins
credentials, CircleCI contexts).

### Reusable configuration (cross-platform)

A way to share pipeline logic across repositories. GitHub: reusable
workflows + composite actions. GitLab: `include:` and CI/CD components.
Jenkins: shared libraries. CircleCI: orbs. Same need, different mechanism.

### Distinctions people get wrong

- **Config file location.** GitHub: `.github/workflows/*.yml` (many files).
  GitLab: `.gitlab-ci.yml` (one file, though it can include others). Jenkins:
  `Jenkinsfile`. CircleCI: `.circleci/config.yml`. Getting the path wrong
  means the platform never sees your pipeline.
- **One file vs many.** GitHub encourages many small workflow files. GitLab
  and CircleCI prefer one file with multiple jobs. Jenkins is one file by
  convention.
- **Runner ownership.** GitHub and CircleCI host runners for you. GitLab
  offers both. Jenkins is you-host-it by default. The trade-off is
  maintenance vs control.
- **Secrets storage.** GitHub: Settings → Secrets. GitLab: Settings → CI/CD
  → Variables. Jenkins: Credentials plugin. CircleCI: Project Settings →
  Environment Variables or contexts. Same concept, different UI.
- **Manual approval.** GitHub: environment protection rules (UI). GitLab:
  `when: manual` job. Jenkins: `input` step. CircleCI: approval job. Same
  gate, different shape.
- **Concurrency.** GitHub has it natively. The others approximate it with
  plugins or conventions. If you rely on it, check your platform.

## 3. Workflow example

A small pipeline doing the same thing (install, lint, test, build) on three
platforms, so you can see the syntax differences side by side. All three are
illustrative and were not executed.

### GitHub Actions (`.github/workflows/ci.yml`)

```yaml
name: CI
"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  ci:
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
      - run: npm ci
      - run: npm run lint
      - run: npm test
      - run: npm run build
```

### GitLab CI (`.gitlab-ci.yml`)

```yaml
stages:
  - test
  - build

default:
  image: node:22
  cache:
    key: ${CI_COMMIT_REF_SLUG}
    paths:
      - cicd-learn/node_modules/

lint:
  stage: test
  script:
    - cd cicd-learn && npm ci && npm run lint

test:
  stage: test
  script:
    - cd cicd-learn && npm ci && npm test

build:
  stage: build
  script:
    - cd cicd-learn && npm ci && npm run build
  artifacts:
    paths:
      - cicd-learn/dist/
    expire_in: 7 days
```

### Jenkins (`Jenkinsfile`)

```groovy
pipeline {
  agent { label 'linux' }
  stages {
    stage('Install') {
      steps {
        dir('cicd-learn') { sh 'npm ci' }
      }
    }
    stage('Lint') {
      steps {
        dir('cicd-learn') { sh 'npm run lint' }
      }
    }
    stage('Test') {
      steps {
        dir('cicd-learn') { sh 'npm test' }
      }
    }
    stage('Build') {
      steps {
        dir('cicd-learn') { sh 'npm run build' }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'cicd-learn/dist/**', allowEmptyArchive: true
    }
  }
}
```

### CircleCI (`.circleci/config.yml`)

```yaml
version: 2.1
orbs:
  node: circleci/node@5
jobs:
  ci:
    docker:
      - image: cimg/node:22.0
    steps:
      - checkout
      - node/install-packages:
          app-dir: cicd-learn
      - run:
          name: Lint
          command: cd cicd-learn && npm run lint
      - run:
          name: Test
          command: cd cicd-learn && npm test
      - run:
          name: Build
          command: cd cicd-learn && npm run build
      - persist_to_workspace:
          root: cicd-learn
          paths:
            - dist
workflows:
  ci:
    jobs:
      - ci
```

Structural things to notice:

1. **The concepts are identical; only the keywords differ.** `needs:` vs
   `requires:` vs stage ordering. `runs-on:` vs `agent` vs `docker:`.
   `actions/upload-artifact` vs `artifacts:` vs `archiveArtifacts` vs
   `persist_to_workspace`.
2. **GitHub's `uses:` for actions has no direct equivalent.** GitLab has
   `include:` and components; Jenkins has plugins; CircleCI has orbs. All
   solve "reuse someone else's code", but the packaging differs.
3. **GitLab's `services:` is first-class.** A Postgres sidecar is a keyword,
   not a separate action. GitHub needs `services:` too (it is native), but
   the ecosystem leans on actions for everything else.
4. **Jenkins is Groovy, not YAML.** That is its biggest difference and its
   biggest cost: you need a developer to write and review it.
5. **CircleCI's orbs are the closest to GitHub Actions.** An orb is a
   packaged, versioned set of jobs and commands, like an action but
   coarser-grained.

## 4. What I should see

There is no run to quote. What follows is what you would see on each
platform for the same green pipeline.

### On all four platforms

- A green checkmark next to the commit or PR.
- A log with install, lint, test and build steps, each with its output.
- An artifact (the `dist/` directory) available for download.
- A failure that turns red and stops the downstream steps.

### Where they differ in the UI

- **GitHub Actions**: a "Checks" tab on the PR, an "Actions" tab on the repo,
  a run summary with artifacts and environment URLs.
- **GitLab CI**: a "Pipelines" page per project, "Jobs" per stage, artifacts
  downloadable from the job page. Environments and deployments are
  first-class pages.
- **Jenkins**: a "Build History" per job, console output per build, archived
  artifacts on the build page. The UI is older and more plugin-driven.
- **CircleCI**: a "Pipelines" page, "Jobs" and "Steps" per pipeline, with
  a polished log viewer. Insights and analytics are a selling point.

### The migration question

If you move from one platform to another, the work is not "learn CI/CD" —
you already know it. The work is "translate the keywords and re-create the
secrets and runners". Expect a week of friction, not a month.

## 5. When to use it and when NOT to

**Stay on GitHub Actions when:**

- Your code is on GitHub. The event integration (PR checks, releases,
  deployments) is the killer feature and is hard to replicate.
- You want zero infrastructure. No server to patch, no runner to register.
- Your team is small and the learning curve matters.

**Consider GitLab CI when:**

- Your code is on GitLab. Same reasoning: use the native tool.
- You want built-in container registry, environments and security scanning
  in one place.
- You need free self-hosted runners with a generous allowance.

**Consider Jenkins when:**

- Your company mandates it or already runs it.
- You must build inside an internal network and cannot use hosted runners.
- You need a tool or hardware that hosted runners do not provide.
- You have an admin to maintain it (this is not optional).

**Consider CircleCI when:**

- You want the most polished SaaS UX and good analytics.
- You are on GitHub but want a different CI vendor (vendor diversity).
- You need macOS or Windows builds with good support.

**Do NOT switch platforms because:**

- A tutorial used a different one. The concepts transfer; the syntax does
  not matter that much.
- You want one feature. Every platform has equivalents for the features in
  this course.
- You are unhappy with your current one but have not fixed the actual
  problem (slow builds, flaky tests, missing tests). Switching platforms
  does not fix those.

## 6. Common mistakes

- **Translating syntax literally.** `needs:` in GitHub is not `needs:` in
  GitLab in every respect. Read the docs for your target platform; do not
  assume.
- **Forgetting to recreate secrets.** The new platform has no access to your
  old secrets. Symptom: a workflow that worked yesterday fails with
  "secret not found". Fix: migrate secrets deliberately, with a checklist.
- **Forgetting to register runners.** On Jenkins and GitLab self-hosted,
  the pipeline is green in theory but no runner picks it up. Symptom: jobs
  stuck in "pending". Fix: register and tag runners before you need them.
- **Using `latest` for base images on the new platform.** Same trap as
  GitHub. Pin the image or tag.
- **Assuming the new platform is faster.** Speed comes from caching and
  parallelism, which you configure, not from the vendor. A bad cache key is
  slow everywhere.
- **Losing the audit trail.** Moving platforms loses your deployment history
  and run logs. Symptom: "when did we deploy v1.2.3?" has no answer. Fix:
  export what you can before you migrate.
- **Treating the migration as a rewrite.** It is a translation. Keep the
  same stages, the same gates, the same artifacts. Change only the keywords.

## 7. Try it yourself

**Exercise: translate one workflow.**

1. Pick one workflow from this course that you understand well, for example
   `15-ci-pipeline-order.yml` or `20-artifacts.yml`.

2. Translate it to GitLab CI, Jenkins, or CircleCI using the table in
   section 2 and the examples in section 3. Keep the stages, the gates, the
   artifact, and the cache.

3. If you have an account on the target platform, run it. If not, at least
   validate the syntax:
   - GitLab: use the "CI/CD → Pipelines → Run pipeline" dry-run, or
     `gitlab-ci-lint`.
   - Jenkins: use the "Pipeline Syntax" snippet generator and the
     `Jenkinsfile` linter.
   - CircleCI: `circleci config validate`.

4. **Prove the concepts transfer.** Check that your translated pipeline has
   the same stages (install, lint, test, build), the same artifact, and the
   same failure behaviour. Only the keywords changed.

5. **Break it on purpose.** Remove the cache. Watch the build get slower.
   Add it back. The effect is the same on every platform.

6. **Clean up.** Delete the translated file if you do not intend to use it.

**Hint:** start with the concept, then find the keyword. "I need a job
dependency" → `needs:` (GitHub) / `needs:` (GitLab) / stage order
(Jenkins) / `requires:` (CircleCI). The concept is the same; only the
spelling changes.

## 8. Next

You now know that CI/CD is one subject with four dialects. The last chapter
is a checklist for taking everything in this course and applying it to a real
repository.

→ [57 — Where to go next](57-next-steps.md)
EOF
echo written