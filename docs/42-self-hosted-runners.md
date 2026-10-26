# 42 — Self-hosted runners [read-only example]

> **Verification.** This chapter is a **`[read-only example]`**: it was **not**
> executed, because self-hosted runners need a machine you control and a
> registration token from GitHub. There is no log for it. `python3
> scripts/validate-workflows.py` was run on the illustrative workflow in
> section 3 and reports it as valid YAML. The free alternative you can run
> today is at the end of section 7: larger GitHub-hosted runners and `act`
> locally.

---

## 1. Simple explanation (like I'm 7)

So far every job has run on a computer that GitHub owns and throws away
afterwards. That is like borrowing a taxi: you get in, it drives you, you get
out, and the taxi is cleaned for the next passenger. Nothing of yours stays in
the taxi.

A **self-hosted runner** is your own car. You buy it, you park it in your
garage, and you register it with GitHub so that when a job needs a car, GitHub
hands the job to yours. Your car keeps its fuel, its radio presets, and its
muddy boots between trips. That persistence is the whole point and the whole
problem.

This chapter is marked `[read-only example]` because it needs a machine you
control. But the concepts and the warnings are the part that matters, and they
cost nothing to read.

## 2. Real name

### Self-hosted runner

A machine (physical, VM, or container) that you operate and register with a
repository, organisation, or enterprise. GitHub dispatches jobs to it instead
of to a hosted runner. You specify it with a label:

```yaml
runs-on: self-hosted
# or a custom label you assigned at registration time:
runs-on: [self-hosted, linux, x64, gpu]
```

### Runner labels

Labels are how a job asks for a machine. GitHub-hosted runners have fixed
labels (`ubuntu-24.04`, `ubuntu-24.04-arm`). Self-hosted runners get the
`self-hosted` label automatically plus whatever custom labels you add. A job's
`runs-on` is a list of labels that must all match.

### Registration

You download the runner binary from your repository's Settings -> Actions ->
Runners, run `config.sh` with a registration token, and start `run.sh`. The
runner then long-polls GitHub for work. Registration tokens expire after one
hour and are single-use.

### Runner groups

Organisation-level collections of runners with access rules. A repository can
be allowed to use only certain groups, which is how you keep production
runners away from pull-request jobs.

### Ephemeral runners

A runner configured with `--ephemeral` that takes one job and then unregisters
itself. This is the recommended mode for anything that handles untrusted code,
because it removes the persistence problem at the cost of re-installing tools
each time.

## 3. Workflow example

This workflow is valid YAML but was not executed. It shows the shape of a
self-hosted job.

```yaml
name: Self-hosted runner demo (read-only)

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build-on-own-machine:
    name: Build on a self-hosted runner
    # Ask for a Linux self-hosted runner with the `gpu` label.
    runs-on: [self-hosted, linux, x64, gpu]
    # Self-hosted jobs should always have a timeout; a hung job on your own
    # hardware still costs you electricity and blocks the runner.
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7

      - name: Show where we are
        run: |
          echo "hostname: $(hostname)"
          echo "user     : $(whoami)"
          echo "pwd      : $(pwd)"
          # On a self-hosted runner this prints YOUR machine, not a GitHub VM.
          echo "node     : $(node --version)"

      - name: Build
        working-directory: cicd-learn
        run: |
          npm ci
          npm run lint
          npm test
          npm run build
```

The only line that differs from a hosted workflow is `runs-on`. Everything
else is identical, which is the point: the workflow does not know or care
which kind of runner it is on.

## 4. What I should see

There is no real log for this chapter. On a real self-hosted run you would see:

- The job's runner name in the Actions tab, e.g. `my-build-box` instead of
  `ubuntu-24.04`.
- `hostname:` printing your machine's name rather than a GitHub VM name like
  `fv-az...`.
- Tools that are installed on your machine but not on GitHub's image working
  without a setup step, and tools that are missing failing the same way they
  would locally.
- State persisting between runs: a leftover `node_modules` from a previous
  run, a stale Docker image, a cached file in `/tmp`. This is the behaviour
  that makes self-hosted runners fast and dangerous at the same time.

The free alternative in section 7 reproduces the speed part (local tools, no
re-install) without any of the risk.

## 5. When to use it and when NOT to

**Reach for a self-hosted runner when:**

- You need hardware GitHub does not offer: a GPU, a specific CPU architecture,
  more RAM than the largest hosted runner, or a machine attached to special
  peripherals.
- Compliance requires that code never leaves your network. Self-hosted runners
  can run entirely on-premise.
- You run so many minutes that owned hardware is cheaper than billed minutes.
  Do the maths first; chapter 49 has the numbers.
- You need software that cannot be installed on a fresh VM each run, such as a
  licensed compiler or a proprietary SDK.

**Do NOT reach for it when:**

- You just want faster builds. Larger GitHub-hosted runners (section 7) or
  better caching (chapter 16) almost always win, and they carry none of the
  risk.
- The job runs on pull requests from forks. A fork PR runs on your machine
  with your secrets if you are not careful, which is a security incident
  waiting to happen.
- You are not prepared to patch and monitor the machine. An unpatched runner
  is a permanent foothold inside your network.
- You want reproducibility. A machine that accumulates state produces builds
  that cannot be reproduced on a fresh machine, which is the opposite of what
  CI is for.

## 6. Common mistakes

- **Running fork pull requests on a self-hosted runner with secrets.** The
  single most dangerous configuration in GitHub Actions. A malicious PR can
  read every secret the runner has access to. Fix: use `pull_request` (not
  `pull_request_target`) so secrets are not injected, or use ephemeral runners
  in an isolated network, or do not run untrusted code on self-hosted runners
  at all.
- **Assuming a self-hosted runner is clean.** It is not. Leftover
  `node_modules`, stale caches, and old Docker images cause "works on my
  runner" builds that fail everywhere else. Fix: ephemeral runners, or a
  cleanup step at the start of every job.
- **Sharing one runner across environments.** A runner that builds staging
  and production can be tricked into running production code with staging
  credentials, or vice versa. Fix: separate runners or runner groups per
  environment.
- **No timeout on self-hosted jobs.** A hung job pins your machine forever.
  Always set `timeout-minutes:`.
- **Leaving the runner service running as root.** The runner process and the
  jobs it runs share a user. Run the runner as a dedicated, unprivileged
  user, and never as root.
- **Forgetting that `actions/checkout` still works.** It does, but it checks
  out into the runner's working directory, which may contain leftovers. Use
  `clean: true` in the checkout step if you are not using ephemeral runners.
- **Treating runner registration tokens as long-lived.** They expire in one
  hour. Automate registration in your provisioning, do not paste a token into
  a wiki.

### The cost maths (roughly)

GitHub-hosted Linux minutes are billed per minute. A self-hosted runner costs
you the machine. The break-even depends on your usage, but as a rule of thumb:

- Under a few hundred minutes a month: hosted is cheaper and simpler.
- Thousands of minutes a month on identical, long jobs: a persistent
  self-hosted runner or a larger hosted runner may win.
- GPU or large-memory jobs: self-hosted is often the only affordable option,
  because hosted GPU runners are expensive and scarce.

Always include the cost of maintaining the machine (patching, monitoring, the
on-call rotation when it breaks) before declaring self-hosted cheaper.

### Ephemeral vs persistent runners

| Mode | State between jobs | Install cost per job | Security | When to use |
| ---- | ------------------ | -------------------- | -------- | ----------- |
| Persistent | Keeps everything | Low (tools stay installed) | Low (state accumulates) | Trusted, internal, cost-sensitive |
| Ephemeral | Clean slate every job | High (re-install tools) | High (no leftover state) | Anything touching untrusted code |

Ephemeral is the recommended default for any runner that handles pull requests.
The install cost is recovered by `actions/setup-node`'s cache and by pre-baking
a custom image with your tools already installed.

### A security checklist

Before you register a runner that will handle anything sensitive:

- [ ] Runner runs as a non-root, dedicated user.
- [ ] Runner is ephemeral if it ever sees pull-request code.
- [ ] `pull_request` (not `pull_request_target`) is used for PR jobs, so
      secrets are not injected.
- [ ] Runner groups restrict which repositories can use it.
- [ ] No production credentials are stored on the runner's disk.
- [ ] Runner is on a network segment that cannot reach production databases
      directly.
- [ ] Runner version is current and auto-updates are enabled.
- [ ] Work directory is cleaned between jobs, or the runner is ephemeral.

### Monitoring and upkeep

A self-hosted runner is a server you own, which means you own its uptime. The
minimum viable monitoring:

- Is `run.sh` / the service still running? (systemd status, or a process
  check.)
- Is the runner showing as "Idle" or "Offline" in Settings -> Actions ->
  Runners?
- Disk space on the runner's work directory; a few large builds can fill a
  small VM.
- Runner version: GitHub deprecates old runner versions. Update periodically
  with `./config.sh remove` then re-register, or use the built-in update.

### Scaling out

Multiple machines can register with the same labels. GitHub round-robins jobs
across them. For autoscaling, the common pattern is a small service (or a
Kubernetes controller) that watches the queue depth and spins up VMs, then
removes them when idle. GitHub does not autoscale your runners for you; you
provide the pool.

### What registration actually looks like (conceptual)

For reference, not execution. On your machine, in an empty directory:

```bash
# 1. Download the runner (Linux x64 example). The URL and token come from
#    your repository's Settings -> Actions -> Runners -> New self-hosted runner.
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz

# 2. Register. The token is single-use and expires in one hour.
./config.sh --url https://github.com/OWNER/REPO \
            --token REGISTRATION_TOKEN \
            --labels gpu,linux,x64 \
            --name my-build-box

# 3. Run it (foreground; Ctrl-C stops it).
./run.sh

# 4. Or install as a service so it survives reboots.
sudo ./svc.sh install
sudo ./svc.sh start
```

For an organisation runner, the URL is `https://github.com/ORG` and you add
`--runnergroup`. For ephemeral mode, add `--ephemeral` to `config.sh` and
the runner unregisters itself after one job.

The version number in the URL changes over time; always copy the exact
command from the GitHub UI rather than hardcoding a version.

## 7. Try it yourself

There is no exercise that needs a real runner. Instead, two free alternatives
that give you the useful parts.

**Alternative A — larger GitHub-hosted runners.** If the reason you wanted
self-hosted was speed or size, GitHub offers larger hosted runners with more
CPUs and RAM, billed per minute at a higher rate. They are still fresh VMs,
so you keep reproducibility and lose the security risk. Configure them in the
repository settings and reference by label:

```yaml
runs-on: ubuntu-24.04-8-cores  # example label for a larger runner
```

**Alternative B — `act` locally.** Everything this course runs is `act`
against a local container, which is a self-hosted runner in miniature: your
own machine, your own tools, no GitHub minutes. It is the best way to get the
"it runs on my machine" speed while you are developing a workflow, and it is
what produced every log in `docs/_logs/`.

```bash
./scripts/run-workflow.sh .github/workflows/15-ci-pipeline-order.yml push
```

**Break it on purpose (conceptually):** imagine a self-hosted runner that is
not ephemeral, running a job that does `rm -rf /` or reads
`~/.aws/credentials`. The blast radius is your machine and everything on it.
That is why the warnings above are not optional.

## 8. Next

You can own the machine. Chapter 43 is about owning nothing at all: logging in
to a cloud provider with no password stored anywhere.

→ [43 — OIDC and cloud authentication](43-oidc-cloud-auth.md)