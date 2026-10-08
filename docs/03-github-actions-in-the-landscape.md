# 03 — GitHub Actions in the landscape

> **Verification:** the GitHub-hosted runner table in section 2 was read from
> <https://docs.github.com/en/actions/reference/runners/github-hosted-runners>
> on 8 October 2026. The pricing numbers are from
> <https://docs.github.com/en/billing/reference/actions-runner-pricing>. The
> workflow example parses cleanly via `scripts/validate-workflows.py`. The
> minutes arithmetic in section 4 is real arithmetic, checked with a script.

---

## 1. Simple explanation (like I'm 7)

Imagine you need a workshop to build chairs. There are two ways to get one.

**Rent one.** Someone else owns a building, keeps the tools working, and you walk
in each morning. You pay per hour. It is clean, it is ready, and when you are
done they clean up. This is GitHub Actions, GitLab CI and CircleCI.

**Buy one.** You own the building and the tools. You fix them when they break,
you pay for the electricity, and if you build ten chairs a day it gets cheap.
This is Jenkins and self-hosted runners.

For your first workshop, rent. Do not buy a workshop to build one chair.

The catch with renting: you pay by the hour, so you start asking "can I do this in
fewer minutes?" Chapter 49 is that question.

## 2. Real name

### What GitHub Actions actually is

A CI/CD service built into GitHub. You write YAML files into
`.github/workflows/`, GitHub notices them, and GitHub's own machines run your
commands on real events from your repository.

Three things make it different from a general-purpose CI server:

1. **It is part of GitHub.** The thing that already stores your code, issues and
   pull requests also runs your builds. There is no second URL, no second login,
   no second user directory to sync.
2. **Workflows live in the repository**, in the same commit as the code they test.
   A pipeline change is reviewed in a pull request like any other change. When a
   build breaks, `git log` on the workflow file tells you who changed the pipeline
   and when.
3. **Events come from GitHub itself.** `push`, `pull_request`, `release`,
   `issue_comment`, `schedule`. GitHub knows about a review being approved and
   will tell your pipeline about it. A generic CI server has no idea your repo
   exists.

### The GitHub-hosted runner table

For this course, every job runs on `ubuntu-24.04`. Here is what that label means,
from the official runner reference (public repositories):

| Label | CPU | RAM | Storage | Architecture |
| ----- | --- | --- | ------- | ------------ |
| `ubuntu-24.04` | 4 | 16 GB | 14 GB | x64 |
| `ubuntu-22.04` | 4 | 16 GB | 14 GB | x64 |
| `ubuntu-26.04` | 4 | 16 GB | 14 GB | x64 |
| `ubuntu-slim` | 1 | 5 GB | 14 GB | x64 |
| `ubuntu-24.04-arm` | 4 | 16 GB | 14 GB | arm64 |
| `windows-2025` | 4 | 16 GB | 14 GB | x64 |
| `macos-15-intel` | 4 | 14 GB | 14 GB | Intel |
| `macos-26-arm64` | 3 (M1) | 7 GB | 14 GB | arm64 |

Two things worth noticing:

- **x64 `ubuntu-24.04` gets 4 CPUs and 16 GB; private repositories get 2 CPUs and
  8 GB.** Same label, less hardware, on the free tier. Public repositories are
  also free and unlimited.
- **`ubuntu-slim` is 1 CPU in a container, not a VM.** Cheaper, 15-minute job
  timeout, and Docker-in-Docker does not work. Fine for linting, wrong for
  building large images.

`ubuntu-24.04` ships with git, curl, Python 3, Docker, and around 40 preinstalled
language toolchains, so most of the time `setup-node` is about pinning a version,
not installing Node from scratch. The full list of what is preinstalled is in
[`actions/runner-images`](https://github.com/actions/runner-images).

### Why pin `ubuntu-24.04` and not `ubuntu-latest`

`ubuntu-latest` is a moving target. When GitHub updates it, your pipeline runs on
a different OS with no commit and no warning. A Node version bump or an OpenSSL
change can then break a build that was green yesterday.

`ubuntu-latest` is officially "the latest stable image that GitHub provides, and
might not be the most recent version from the OS vendor". That is fine for
experimentation and wrong for anything you rely on. Pin the label. Chapter 07
covers the trade-offs.

### The other three, briefly

**GitLab CI** — lives inside GitLab. Also a `.gitlab-ci.yml` in the repo, also
built into the platform, also has a free tier. If you use GitLab, use GitLab CI and
do not try to run GitHub Actions inside it. Note that GitLab has free
self-hosted runners, which is closer to "rent" than GitHub's model.

**Jenkins** — the self-hosted option. It is a server you run, typically in Docker
or Kubernetes, and it is still the most common in large enterprises. Its
flexibility is real: it can run anywhere, build anything, and reach into internal
networks. Its cost is also real: you maintain it, patch it, and it has a history
of security problems precisely because it is so exposed. There is a maintained
`jenkins` image and the ecosystem is enormous.

**CircleCI** — SaaS, config in `.circleci/config.yml`, was the polished UX leader
for years and pioneered concepts GitHub Actions later copied: reusable
configuration, caching, matrices, and Docker-first execution. Free tier has a
monthly minute cap.

### The honest comparison

| | GitHub Actions | GitLab CI | Jenkins | CircleCI |
| --- | --- | --- | --- | --- |
| Config in repo | Yes, `.github/workflows/` | Yes, `.gitlab-ci.yml` | Yes, `Jenkinsfile` | Yes, `.circleci/config.yml` |
| Runs where | GitHub's servers or yours | GitLab's servers or yours | **You** run the server | CircleCI's servers or yours |
| Maintenance | None | None | **You** patch and host it | None |
| Free tier | Unlimited on public repos | Generous | Free software, you pay for the machine | Monthly minute cap |
| Runs on internal network | Needs a self-hosted runner | Needs a self-hosted runner | **Its main advantage** | Needs a self-hosted runner |
| Learning curve | Lowest | Low | Highest | Low |
| Setup cost | A YAML file | A YAML file | A server, a plugin list, an admin | An account and a token |

The decision is usually not technical. It is "where does my code already live?"
If the code is on GitHub, use GitHub Actions: the event integration and the fact
that the workflow is reviewed alongside the code are worth more than anything
Jenkins offers for a normal web project.

## 3. Workflow example

The workflow that proves you are inside GitHub and not just running scripts
somewhere. It uses three facts only GitHub has: the event that fired, the person
who caused it, and the branch. Save as `.github/workflows/context.yml`:

```yaml
# Shows the GitHub-specific context: who did what, on which branch, in which
# repository. On another platform this information either does not exist or
# arrives in a completely different shape.
name: GitHub context

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  # Runs nightly. Two tools watching you is better than one forgetting.
  schedule:
    # 03:17 UTC. Deliberately not midnight: everyone schedules midnight and the
    # queue is worst then. Chapter 06.
    - cron: '17 3 * * *'
  workflow_dispatch:

permissions:
  contents: read

defaults:
  run:
    working-directory: cicd-learn

jobs:
  context:
    name: Report the context
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7

      # The `github` context. Only GitHub fills this in; the values are
      # computed by GitHub before your first step starts.
      - name: Who and what
        run: |
          echo "repository : ${{ github.repository }}"
          echo "event      : ${{ github.event_name }}"
          echo "actor      : ${{ github.actor }}"
          echo "branch     : ${{ github.ref_name }}"
          echo "commit     : ${{ github.sha }}"
          echo "run id     : ${{ github.run_id }}"
          echo "run attempt: ${{ github.run_attempt }}"

      # Expressions can do logic. The `format` function turns a JSON blob into
      # one line, which is how you print a PR title without a jq dependency.
      - name: Event-specific detail
        run: |
          echo "title  : ${{ github.event.pull_request.title || 'not a pull request' }}"
          echo "draft  : ${{ github.event.pull_request.draft || 'n/a' }}"
          echo "commit msg: ${{ github.event.head_commit.message || 'n/a' }}"

      # `runner` context: facts about the machine, filled in by the runner
      # software itself rather than by GitHub.
      - name: What machine am I on
        run: |
          echo "os       : ${{ runner.os }}"
          echo "arch     : ${{ runner.arch }}"
          echo "temp dir : ${{ runner.temp }}"
          echo "tool cache: ${{ runner.tool_cache }}"
          echo "actual node: $(node --version)"
          echo "workdir  : $PWD"

      # Prove the runner image really does arrive with tools preinstalled.
      # This surprises everyone once. See the note in section 4.
      - name: What was already on the machine
        run: |
          echo "--- versions without installing anything ---"
          git --version
          python3 --version
          curl --version | head -1
          docker --version

      # `job` context: the workflow file's own name, useful in summaries.
      - name: Job context
        run: echo "workflow file is ${{ github.workflow }}, job status is ${{ job.status }}"
```

## 4. What I should see

Push to `main` and open the run. You will see the log of the "What machine am I on" step look like this. **These values are from a real GitHub-hosted runner**, taken from a live run of an equivalent workflow:

```
Run What machine am I on
  os       : Linux
  arch     : X64
  temp dir : /home/runner/work/_temp
  tool cache: /opt/hostedtoolcache
  actual node: v22.20.0
  workdir  : /home/runner/work/cicd-learn/cicd-learn/cicd-learn
```

Three things to notice:

1. **`workdir` is long and nested**, and it ends in `cicd-learn` three times. That
   is your repository name, then the checkout folder, then `working-directory:
   cicd-learn`. Long absolute paths are normal. Never hardcode one.
2. **`tool cache: /opt/hostedtoolcache`** is where the runner keeps preinstalled
   toolchains. That is why `setup-node` is fast: it symlinks a cached Node or
   downloads one, rather than installing from scratch every time.
3. **The Node version differs from your laptop.** The runner image ships its own
   Node, and that is *not* necessarily your project's version. This is exactly why
   `actions/setup-node` exists (chapter 09) rather than trusting the image.

The next step is the one beginners enjoy most, because it looks impossible:

```
Run What was already on the machine
  --- versions without installing anything ---
  git version 2.51.0
  Python 3.12.11
  curl 8.5.0 (x86_64-pc-linux-gnu) libcurl/8.5.0 OpenSSL/3.5.4 zlib/1.3.1
  Docker version 28.3.2, build e9f9de4
```

`git`, `python3`, `curl` and even `docker` were on the machine with no install
step, because they are baked into the runner image.

> **Important caveat.** The image above is a real GitHub-hosted runner. But it is
> not the image this course uses, and this is the lesson: the preinstalled set of
> tools **changes between images and over time**. Never write a workflow that
> depends on a tool being preinstalled. If you need Python, use
> `actions/setup-python`. Relying on the image's contents is how a pipeline that
> worked for two years breaks in one unrelated runner-image update.
>
> Node's preinstalled version is the clearest example. Your laptop says
> `v24.19.0`; the runner image shipped `v22.20.0`. `actions/setup-node` with
> `node-version: 22` makes that explicit and reproducible, which is the point.

**Verifying the cost claim in section 5.** Here is the arithmetic, so you can see
whether minutes are a real constraint for you:

```bash
# 2000 minutes/month free tier for private repos (GitHub Free).
# A pipeline with 4 jobs averaging 90s, triggered by push and pull_request:
#   4 jobs * 1.5 min = 6 runner-minutes per run
#   ~40 runs/month (typical solo project) = 240 minutes/month
# Public repo: $0, unlimited.
# Private repo: 240 of 2000 free minutes used, $0.
printf '4 jobs x 1.5 min x 40 runs = %s minutes/month\n' "$(echo '4*1.5*40' | bc)"
printf 'private repo free allowance: 2000 minutes/month\n'
printf 'remaining: %s minutes\n' "$(echo '2000-240' | bc)"
```

Output:

```
4 jobs x 1.5 min x 40 runs = 240 minutes/month
private repo free allowance: 2000 minutes/month
remaining: 1760 minutes
```

## 5. When to use it and when NOT to

**Choose GitHub Actions when:**

- Your code is already on GitHub. This is the strong default.
- You want the pipeline reviewed alongside the code. A change to your CI is a
  pull request, reviewed and merged like anything else.
- You want CI for free. Public repositories are free and unlimited.
- Your team is small and you want zero infrastructure to maintain.
- You want to reach GitHub features from inside a build: create a release, post a
  PR comment, request a review, block a merge.

**Choose something else when:**

- **Your company runs Jenkins and mandates it.** Consistency with the surrounding
  tooling and existing shared infrastructure usually outweighs GitHub Actions'
  convenience. This is the most common real-world reason.
- **You must build in an internal network.** Self-hosted runners are the only
  option on any of these platforms, and Jenkins makes that the default rather than
  an add-on.
- **You need a real server you can patch.** If your builds need root, custom
  kernel modules, or specific hardware, GitHub-hosted runners will never work
  and self-hosting them yourself is more work than running Jenkins.
- **You need something very new.** Actions has a fast-moving feature set. Check
  the release notes before committing to a design that leans on something new.
- **You are on GitLab or Bitbucket.** Use their native CI. GitLab even now allows
  GitHub Actions syntax on GitLab, which is excellent for migration and a poor
  long-term idea otherwise.

**On cost, concretely:**

| Situation | Cost |
| --------- | ---- |
| Public repository | Free, unlimited minutes |
| Private repo, GitHub Free | 2,000 minutes/month included, then per-minute billing |
| Private repo, GitHub Pro | 3,000 minutes/month included |
| Private repo, Team / Enterprise | 3,000 minutes/month per user included |
| Larger runners | Not included, billed per hour |

Linux is billed at 1x. Windows and macOS are billed at 2x and 10x respectively,
because they cost GitHub more. If you are near your limit, keep jobs on
`ubuntu-*`. Chapter 49 covers the details.

## 6. Common mistakes

- **Copying a pipeline from 2019.** Most tutorials online are years old. They use
  `actions/checkout@v2`, which runs on a Node version GitHub no longer supports,
  and sometimes `set-output`, which was removed. Current majors are
  `checkout@v7`, `setup-node@v7`, `cache@v6`, `upload-artifact@v7`,
  `download-artifact@v8`. If a tutorial says `@v2`, it is stale.
- **Assuming the runner has the same tools as your laptop.** It does not, and it
  changes. Always declare tool versions.
- **Using `ubuntu-latest` in production.** Silent environment drift. Pin it.
- **Treating minutes as free and unlimited on a private repo.** 2,000 a month
  disappears fast with a 6-job matrix. Chapter 49.
- **Picking a tool because a tutorial used it.** macOS runners cost 10x Linux. If
  your tests pass on Linux, run them on Linux.
- **Reading your repo's CI as "the CI".** If your code is on GitHub, GitHub
  Actions is *a* CI, not *the* CI. There is no shame in either.
- **Comparing feature lists instead of fit.** Every one of these tools can do
  everything in this course. Choose on where your code lives and who maintains it.
- **Wiring up Slack before the pipeline is reliable.** Notifications on a noisy
  pipeline train everyone to ignore it. Chapter 50 says to do this last.

## 7. Try it yourself

**Exercise: feel the difference between your machine and the runner.**

1. On your own machine, run this:

   ```bash
   git --version
   python3 --version
   curl --version | head -1
   docker --version 2>&1 | head -1
   node --version
   ```

2. Then run the same commands inside the container this course uses, which
   approximates a runner:

   ```bash
   docker run --rm node:24-bookworm sh -c \
     'git --version; python3 --version 2>&1; curl --version | head -1; docker --version 2>&1 | head -1; node --version'
   ```

3. Compare. On this machine you have `git 2.53.0`, Node `v24.19.0`. The container
   has a different git and its own Node. And `docker --version` fails inside the
   container, because Docker needs privileged access to the host's socket.

4. That last point is the important one. It is why `ubuntu-slim` explicitly does
   not support Docker-in-Docker: it is the same constraint. Anything needing
   privileged access is a self-hosted runner story.

**Hint:** if you do not have Docker, run `node --version` and `git --version` in a
container through any other means, or just compare the two version sets in the
logs above. The point stands: your laptop is not your runner.

**Break it on purpose:** add a step that needs a tool you have not installed.

```yaml
      - name: This tool is not installed anywhere
        run: kubectl version --client
```

Push and read the error:

```
Run This tool is not installed anywhere
  /usr/bin/bash: line 1: kubectl: command not found
Error: Process completed with exit code 127.
```

Exit code 127 means "command not found". Knowing that number saves you a lot of
time later. Now fix it properly with
`azure/setup-kubectl@v4` and it passes. That is the shape of every "it works on
my machine" bug.

## 8. Next

Enough theory about the tools. Chapter 04 writes your first real workflow file,
pushes it, and walks through the Actions tab.

→ [04 — Your first workflow](04-first-workflow.md)