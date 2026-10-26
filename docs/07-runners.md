# 07 — Runners

> **Verification.** The workflow in this chapter is
> `.github/workflows/07-runners.yml`. It was run three times with `act` 0.2.89:
>
> - `scripts/verify.sh .github/workflows/07-runners.yml pinned push ch07-pinned`
>   → `docs/_logs/ch07-pinned.log` (exit 0)
> - the `latest` job → `docs/_logs/ch07-latest.log` (exit 1)
> - the `slim` job → `docs/_logs/ch07-slim.log` (exit 0, job skipped)
>
> **Read section 4 before trusting any of those numbers.** The local run executes
> inside the repository's own container image (`cicd-act-runner:24`, described in
> `scripts/act-runner.Dockerfile`), not inside GitHub's `ubuntu-24.04` image. So
> the `cpus`, `memory`, `git --version`, `python3 --version` and `node --version`
> values in section 4 are **this course's container's** values. They prove the
> step ran. They prove **nothing** about what GitHub's hosted image contains.
>
> What local execution cannot prove: the actual contents of GitHub's runner
> images, the CPU/RAM/disk figures per plan, minute billing, job queueing, the
> Actions tab's runner labels, or that `ubuntu-slim` exists as a hosted label at
> all. Every such claim in this chapter is marked as coming from GitHub's
> documentation, with the URL given, and none of it is presented as measured
> output. The hosted confirmation is pending, because there is no remote
> repository yet.

---

## 1. Simple explanation (like I'm 7)

A workflow needs a computer to run on. GitHub gives you one.

Think of it as **renting a room in a hotel**. You check in, you have the room for
about ten minutes, you do your work, you check out, and the hotel cleans it
completely before the next guest arrives. Nothing you leave behind survives.
Nobody else has been in your room. There is no cupboard with yesterday's stuff in
it, and there is no way to hide a note on the wall for yourself.

That is a **GitHub-hosted runner**: a brand-new, completely clean computer, given
to your job for the length of that job and then destroyed.

The alternative is **your own computer that stays switched on**. You register it
with GitHub once. GitHub then posts work to it whenever a job is waiting. It
keeps everything between runs — your caches, your Docker images, your mistakes —
which sounds convenient and is exactly the source of the chapter's warnings in
section 5.

The other thing the room comes with is **furniture**: git, Python, curl, Java,
Go, Docker, and dozens of other tools, already installed and already the version
GitHub decided on. You do not install them, and you should not assume they match
what you have on your laptop. The one thing you *should* assume is that the
furniture changes without telling you, if you asked for "whatever is newest"
instead of "24.04".

## 2. Real name

### Runner: two meanings, one word

GitHub uses **runner** for both the machine and the agent program running on it.

- The **agent** is the piece of software that picks up a job, runs your steps,
  and streams the log back.
- The **machine** is what the agent runs on.

When GitHub says "the job ran on `ubuntu-24.04`", it is naming the machine's
image. The agent is the same software on all GitHub-hosted machines.

### GitHub-hosted vs self-hosted

| | GitHub-hosted | Self-hosted |
| - | ------------- | ------------ |
| Who owns the machine | GitHub | You |
| State between runs | None. Fresh VM every job | Whatever you left on it |
| Setup | Zero | Install and register an agent |
| Cost | Free for public repos; billed per minute for private | Your hardware, plus the minutes |
| Network | Inside GitHub's IP ranges | Your network, your firewalls |
| Risk | Low | High, if untrusted PRs can reach it |

GitHub-hosted is the default and the right answer for almost everything in this
course. Chapter 42 covers self-hosted, including the security warnings.

### The label

`runs-on: ubuntu-24.04` names a **label**. A label is a promise about what is
already on the machine and what shape it has. GitHub documents the standard
labels with the hardware each one gets. From the GitHub-hosted runners reference
(<https://docs.github.com/en/actions/reference/runners/github-hosted-runners>):

| Label | Architecture | CPU / RAM (public repo) | Notes |
| ----- | ------------ | ----------------------- | ----- |
| `ubuntu-24.04`, `ubuntu-latest`, `ubuntu-22.04`, `ubuntu-26.04` | x64 | 4 CPU, 16 GB, 14 GB SSD | The standard Linux image |
| `ubuntu-24.04-arm`, `ubuntu-22.04-arm`, `ubuntu-26.04-arm` | arm64 | 4 CPU, 16 GB | Not every community action is arm64-compatible |
| `ubuntu-slim` | x64 | 1 CPU, 5 GB | Single-CPU: a **container**, not a VM. See below |
| `windows-2025`, `windows-latest`, `windows-2022` | x64 | 4 CPU, 16 GB | Runs as administrator, UAC disabled |
| `macos-15`, `macos-latest`, `macos-26`, `macos-14` | arm64 (M1) | 3 CPU, 7 GB | The most expensive per minute |
| `macos-15-intel`, `macos-26-intel` | Intel | 4 CPU, 14 GB | Needed for the static UDID iOS signing requires |

Note that `ubuntu-latest` currently resolves to the **same image as
`ubuntu-24.04`** — the docs link it to the Ubuntu 24.04 readme. That is a
statement about today, not a guarantee about tomorrow, and the guarantee is the
entire point of the next section.

### What "pinned" actually buys you

The docs carry one sentence that is worth memorising:

> The `-latest` runner images are the latest stable images that GitHub provides,
> and might not be the most recent version of the operating system available from
> the operating system vendor.

And a warning that beta and deprecated images are provided "as-is" and excluded
from the service level agreement.

So `ubuntu-latest` is a **moving target that GitHub can re-point without notice,
and with no changelog aimed at you**. If your pipeline pins `ubuntu-latest` and
it silently moves from 24.04 to 26.04, a new OpenSSL or a new glibc can change
your build output, break a native module, or change a test result. Nothing in
your repository changed, and there is no commit to bisect.

`ubuntu-24.04` is a contract: this image, until GitHub announces a removal.

### `ubuntu-slim`, and why it is not just "cheap ubuntu"

From the same reference, and this is the part people miss:

- It is a **single-CPU runner** that executes jobs **inside a container rather
  than a full VM**.
- The container runs in **unprivileged mode**, so operations needing elevated
  privileges are unsupported: mounting filesystems, **Docker-in-Docker**, and
  low-level kernel features.
- The **job timeout is 15 minutes**, not 360.
- It carries a minimal set of tools.

That makes it right for "open an issue, tag something, post a comment, run a
quick script" and wrong for anything that builds an image or needs a real tool
chain. This course uses it to *demonstrate* the constraint, not to depend on it.

### Where things live on the machine

From the file-systems table in the same reference:

| Variable | What it is |
| -------- | ---------- |
| `GITHUB_WORKSPACE` | Where your steps run. `actions/checkout` puts the repository here |
| `HOME` | Per-user data for the current job |
| `GITHUB_EVENT_PATH` | The webhook payload as JSON. GitHub **rewrites it after every action executes**, so do not cache a path to it across steps |

Two more facts from the docs that change how you write steps:

- **Linux and macOS VMs have passwordless `sudo`.** That is why
  `sudo apt-get install` works in a step without any setup.
- Actions that themselves run in a container use static paths under `/github`
  (`/github/workspace`, `/github/home`, `/github/workflow`), and must run as the
  default Docker user (root). If your own Docker-based action sets `USER`, it
  cannot read `GITHUB_WORKSPACE`.

### Runner selection beyond a plain label

`runs-on:` accepts more than a string, and the extra forms are how organisations
share paid machines:

```yaml
# A self-hosted runner matching every label in the list
runs-on: [self-hosted, linux, x64, gpu]

# Any free runner in a named group (GitHub Team / Enterprise)
runs-on:
  group: build-runners

# A specific larger runner by label, optionally narrowed to a group
runs-on:
  group: ubuntu-runners
  labels: ubuntu-24.04-16core
```

Larger runners (more CPU, RAM and disk, static IPs, autoscaling, GPU) are a Team
and Enterprise feature, and the label scheme is `<image>-<size>`:
`ubuntu-24.04-16core`, `windows-2022-16core`, `macos-26-xlarge`. Chapter 49
covers what this costs.

### Two runner facts that are about *jobs*, not machines

- **Queueing.** A job can wait for a free runner before it starts. That wait is
  not work, and it is not billed as runner minutes; the minute counter is about
  the job's runtime (chapter 49 has the pricing detail).
- **Billing unit.** Private-repository minutes are counted per job and rounded up
  to the minute, so a job that runs 4 seconds still costs a minute. Splitting one
  slow job into six fast jobs is often *more* expensive, not less.

## 3. Workflow example

This is the real file, `.github/workflows/07-runners.yml`. Three jobs on three
different labels, each one printing the same facts, so the difference is visible
rather than argued:

```yaml
name: Runners

"on":
  push:
    branches: [main]
  workflow_dispatch:

# Least privilege: nothing here writes to the repository.
permissions:
  contents: read

defaults:
  run:
    working-directory: cicd-learn

jobs:
  # ── The same job on two different runner labels ────────────────────────────
  # Compare the "What is preinstalled" step. This is the whole chapter.
  pinned:
    name: ubuntu-24.04 (pinned)
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: What is preinstalled
        run: |
          echo "runner image : ubuntu-24.04"
          echo "runner os    : ${{ runner.os }}"
          echo "runner arch  : ${{ runner.arch }}"
          echo "cpus         : $(nproc)"
          echo "memory       : $(free -h | awk '/^Mem:/{print $2}')"
          echo "--- preinstalled ---"
          git --version
          python3 --version
          curl --version | head -1
          node --version
          # Not installed without setup-node matching a project version.
          echo "--- from the image, not from our project ---"

  latest:
    name: ubuntu-latest (moving)
    # This label can change at any time without warning. Chapter 07 is about why
    # you should not ship with it.
    runs-on: ubuntu-latest
    steps:
      - name: What is preinstalled
        run: |
          echo "runner image : ubuntu-latest"
          echo "cpus         : $(nproc)"
          git --version
          python3 --version
          node --version

  # ── ubuntu-slim: cheap, but limited ───────────────────────────────────────
  slim:
    name: ubuntu-slim (cheap, limited)
    runs-on: ubuntu-slim
    steps:
      - name: Show the constraint
        run: |
          echo "cpus: $(nproc)"
          # This is the trade-off of the slim image, demonstrated rather than
          # described. Docker-in-Docker is not available in an unprivileged
          # container.
          if docker info >/dev/null 2>&1; then
            echo "docker works here"
          else
            echo "docker NOT available on ubuntu-slim"
          fi
```

Two things to notice about the structure:

- The `latest` job has **no `actions/checkout` step**, only the `pinned` job has
  one. That is not an oversight — it is the whole chapter 08 lesson about
  `working-directory` and checkout order, and it is what makes the local `latest`
  run fail. Read section 4.
- No job here installs anything. The point is to look, not to build.

## 4. What I should see

### The pinned job (real run, `docs/_logs/ch07-pinned.log`)

`act` scaffolding removed, command output kept exactly:

```
Run Main What is preinstalled
  | runner image : ubuntu-24.04
  | runner os    : Linux
  | runner arch  : X64
  | cpus         : 8
  | memory       : 15Gi
  | --- preinstalled ---
  | git version 2.39.5
  | Python 3.11.2
  | curl 7.88.1 (x86_64-pc-linux-gnu) libcurl/7.88.1 OpenSSL/3.0.22 zlib/1.2.13 brotli/1.0.9 zstd/1.5.4 libidn2/2.3.3 libpsl/0.21.2 (+libidn2/2.3.3) libssh2/1.10.0 nghttp2/1.52.0 librtmp/2.3 OpenLDAP/2.5.13
  | v24.21.0
  | --- from the image, not from our project ---
✅  Success - Main What is preinstalled [81.012104ms]
```

**Do not read those versions as GitHub's.** `8` CPUs and `15Gi` of RAM are this
container; GitHub documents `ubuntu-24.04` as 4 CPU / 16 GB for a public
repository. `git version 2.39.5`, `Python 3.11.2` and `v24.21.0` are Debian
bookworm's packages inside this course's own image. GitHub's `ubuntu-24.04` has
its own curated set of versions, documented in the `actions/runner-images`
repository and updated weekly.

What this log *does* legitimately establish:

1. `runner.os` and `runner.arch` are real context values the runner fills in, and
   they are the ones you branch on when a step is platform-specific.
2. Four tools are present without any install step — which is the general point:
   the image ships a toolchain.
3. The `${{ }}` substitution happened before bash ran, and `$(...)` was evaluated
   by bash. Both work, in the same `run:` block, and they are not the same thing.

### The `ubuntu-latest` job (real run, `docs/_logs/ch07-latest.log`)

```
[Runners/ubuntu-latest (moving)] 🚀  Start image=node:16-buster-slim
[Runners/ubuntu-latest (moving)]   🐳  docker pull image=node:16-buster-slim
...
[Runners/ubuntu-latest (moving)] ⭐ Run Main What is preinstalled
  | OCI runtime exec failed: exec failed: unable to start container process: chdir to cwd ("/home/sunny/app/nimo/cicd-docs/cicd-learn") set in config.json failed: no such file or directory
❌  Failure - Main What is preinstalled [58.367237ms]
### act exit status: 1
```

This failure is worth reading twice, because it demonstrates the chapter's
argument with a bang:

- `act` did not have an image for the `ubuntu-latest` label, so it fell back to
  **its own default, `node:16-buster-slim`** — a Node 16 image from years ago.
- The job then failed for the second reason: this job has no
  `actions/checkout`, so `cicd-learn/` does not exist, and the workflow's
  `defaults.run.working-directory: cicd-learn` sent the runner's shell to a
  directory that was never created.

So `ubuntu-latest` resolved to *whatever the tool felt like using*. On GitHub it
resolves to the latest image GitHub publishes for that family, and tomorrow it
may not be what it is today. Neither tool gives you a guarantee, and only one of
them is telling you the truth on purpose.

### The `ubuntu-slim` job (real run, `docs/_logs/ch07-slim.log`)

```
[Runners/ubuntu-slim (cheap, limited)] 🚧  Skipping unsupported platform -- Try running with `-P ubuntu-slim=...`
```

The whole log. `act` has no image bound for that label, so it declined to run
the job. On GitHub `ubuntu-slim` is a real label; its constraints are the ones in
section 2 — one CPU, 5 GB, a container instead of a VM, unprivileged, no
Docker-in-Docker, and a **15-minute job timeout** instead of 360. The `docker
info` probe in that job is written to print exactly which side of that line you
land on.

### `[read-only example]` — hosted runner facts, from GitHub's documentation

Not executed here. Source:
<https://docs.github.com/en/actions/reference/runners/github-hosted-runners>

```
Runners / ubuntu-24.04 (pinned)
  Labels: ubuntu-24.04
  Image:  Ubuntu2404-Readme.md  (actions/runner-images, updated weekly)
  Specs:  4 CPU / 16 GB / 14 GB SSD, x64   (public repository)
  Notes:  passwordless sudo

Runners / ubuntu-slim (cheap, limited)
  Labels: ubuntu-slim
  Specs:  1 CPU / 5 GB / 14 GB SSD, x64
  Notes:  container, not a VM. Unprivileged: no Docker-in-Docker,
          no filesystem mounts, no low-level kernel features.
          Job timeout 15 minutes. Minimal tool set.
```

The specific per-image tool versions (which Node, which git, whether Docker is
present) are not in the runners reference; they live in the per-image readme in
`actions/runner-images`. Read the one for your label before you depend on a tool
being there.

## 5. When to use it and when NOT to

**Pin to a dated label — `ubuntu-24.04` — when:**

- **Always, by default.** A pipeline whose output depends on an image you did not
  choose is a pipeline you cannot debug.
- Especially for anything that produces an artifact you ship, anything with
  native modules, and anything whose test results you would act on.

**Use `ubuntu-latest` when:**

- You are deliberately testing "does this still work on the newest image", as a
  separate, non-blocking workflow. That is a real and useful pattern: a nightly
  canary on `ubuntu-latest` that alerts but does not gate.

**Use `ubuntu-slim` when:**

- The job is genuinely lightweight: commenting, labelling, issue triage,
  dispatching another workflow, a two-line script. One CPU and 5 GB is plenty.
- You are price-sensitive and the job is short.

**Do NOT use `ubuntu-slim` when:**

- **The job builds a container image.** No Docker-in-Docker, so it cannot. This
  course's chapter 30 is the counter-example.
- The job needs anything close to a full build toolchain. The image is
  deliberately minimal.

**Use larger runners when:**

- Your build genuinely needs 16 cores and you are on a plan that has them.
- You need a static egress IP or Azure private networking, because the hosted
  IP ranges are wide and change weekly — the docs explicitly advise against
  allowlisting them.

**Use self-hosted runners when — and read chapter 42 first:**

- Your hardware is specific (a GPU, an ARM board, a device farm) **or**
- You are deep enough in self-hosting that you have already handled persistent
  state, cleanup between jobs, network segmentation, and the fact that
  **untrusted pull-request code runs on that machine**.

The last clause is the one people skip. A public repository that accepts PRs
from strangers and points them at self-hosted runners is a remote code execution
service with your credentials on it.

**Never rely on:**

- Anything you installed on a previous run. The machine is destroyed.
- A file you left in `/tmp`. Same reason.
- The image's Node, Python or Java version matching what you develop against.
  `actions/setup-node` exists precisely because the image's version is not yours.

## 6. Common mistakes

- **`runs-on: ubuntu-latest` in a pipeline you depend on.** Symptom: a build
  starts failing on a day you changed nothing, or `node --version` prints
  something you have never seen. There is no commit to blame. Fix: pin, and
  Dependabot can then offer the bump deliberately (chapter 36).
- **Assuming the image's Node is your Node.** On the hosted runner it is *a*
  Node, not yours. `package.json` here declares `engines.node: ">=22"`, and
  chapter 09's run under `setup-node` reported `v22.23.3` — that is the version
  you asked for, not the one the image happened to have. Symptom of getting this
  wrong: it works for you on Node 24 locally and fails in CI on an older Node.
- **`sudo` being assumed on Windows.** Linux and macOS hosted VMs have
  passwordless `sudo`; Windows runners run as administrator with UAC disabled.
  A `run:` script written for bash does not transfer.
- **Expecting arm64 to just work.** All GitHub-provided actions support arm64;
  **community** actions may not. Symptom: a step that is green on
  `ubuntu-24.04` and fails on `ubuntu-24.04-arm`.
- **Building Docker images on `ubuntu-slim`.** No Docker-in-Docker. Symptom:
  `docker: command not found`, or a daemon error, or a permission error inside a
  container that cannot be privileged.
- **Assuming state survives.** Symptom: `node_modules` from yesterday's run
  "helped" on a self-hosted runner and then nothing reproduced. Chapter 16 is
  about caches, which are the supported mechanism.
- **A `working-directory:` on a job with no `actions/checkout`.** This is the
  failure in section 4: `OCI runtime exec failed: ... chdir to cwd
  ("/home/sunny/app/nimo/cicd-docs/cicd-learn") ... no such file or directory`.
  On GitHub the symptom is `The process '/usr/bin/bash' failed with exit code
  127`. Fix: `actions/checkout` first, always. Chapter 08.
- **Choosing macOS without knowing the price.** Apple silicon hosted runners are
  the most expensive per minute in the standard table. Run the Linux matrix and
  one macOS job, not the reverse.
- **Trusting a local `act` run to tell you what a hosted runner contains.** It
  cannot. Local runs prove your YAML and your commands work; they say nothing
  about the image. The `8 CPUs / 15Gi / Python 3.11.2` in section 4 are this
  repository's container, full stop.
- **`runs-on: [self-hosted, linux]` on a public repo with open PRs.** Chapter 42.
  The runner is not a sandbox.

## 7. Try it yourself

**Exercise: measure the toolchain, then watch it move.**

1. Create `.github/workflows/which-runner.yml`:

   ```yaml
   name: Which runner am I on
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
     facts:
       name: Runner facts
       runs-on: ubuntu-24.04
       steps:
         - uses: actions/checkout@v7
         - name: Everything the runner tells us
           run: |
             echo "os        : ${{ runner.os }}"
             echo "arch      : ${{ runner.arch }}"
             echo "name      : ${{ runner.name }}"
             echo "workspace : $GITHUB_WORKSPACE"
             echo "home      : $HOME"
             echo "cpus      : $(nproc)"
             echo "sudo      : $(sudo -n true && echo passwordless || echo not)"
             echo "--- tools, with versions ---"
             for t in git curl jq node python3 go java docker; do
               printf '%-8s %s\n' "$t" "$(command -v "$t" >/dev/null && "$t" --version 2>&1 | head -1 || echo 'NOT INSTALLED')"
             done
             echo "--- disk ---"
             df -h . | tail -1
   ```

2. Push it. Read the output. Two things to write down: which tools are present,
   and the exact versions. That list is now your baseline.

3. **Add a second job on `ubuntu-latest`** with the identical step list, and a
   third on `macos-15`. Push. In the Actions tab, look at the run summary for
   all three.

   - Every version on `ubuntu-latest` may differ from `ubuntu-24.04` today, and
     may differ again next quarter.
   - `macos-15` is arm64 (Apple silicon). `runner.arch` prints `ARM64`, and any
     community action you add later must survive that.

4. **Delete the pinned label.** Change `ubuntu-24.04` to `ubuntu-latest`, push,
   record the versions, then change it back and push again. Compare the three
   sets. Whatever differs, you now know exactly what your pipeline was exposed
   to.

5. **Break it on purpose, twice:**

   - Remove `actions/checkout` from the `facts` job and push. Read the failure:

     ```
     OCI runtime exec failed: exec failed: unable to start container process:
     chdir to cwd ("/home/sunny/app/nimo/cicd-docs/cicd-learn") set in
     config.json failed: no such file or directory
     ```

     This is the real, quoted error from `docs/_logs/ch07-latest.log` and
     `docs/_logs/ch08-reader.log`. On GitHub it appears as a failing step with
     exit code 127. The directory does not exist because nothing created it.
   - Add `container:` to the job and try to use a tool from the host image:

     ```yaml
     container:
       image: node:22-bookworm
     ```

     Then `git --version` fails, because your container has Node and not git. This
     is the price of `container:` — full control of the toolchain, and you own
     every dependency. Chapter 30 and 37 use it deliberately.

6. Local equivalent, which shows the blind spot explicitly:

   ```bash
   ./scripts/run-workflow.sh .github/workflows/which-runner.yml facts push
   ./scripts/run-workflow.sh .github/workflows/07-runners.yml latest push   # fails
   ./scripts/run-workflow.sh .github/workflows/07-runners.yml slim push     # skipped
   ```

   The second command tells you nothing about `ubuntu-latest` on GitHub; it tells
   you `act` picked `node:16-buster-slim` because it had nothing better. That is
   the point of pinning: on GitHub, the label decides, and the date in the label
   is part of the decision.

**Hint:** to see the images GitHub actually ships, do not guess. Read
`https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md`
— it is generated weekly from the live image, and it is the authoritative list of
what is preinstalled.

## 8. Next

You have a machine, chosen and pinned. The next question is what you do on it:
one job, many steps, one shared workspace, in order, with `run:` for your own
commands and `uses:` for other people's.

→ [08 — Jobs and steps](08-jobs-and-steps.md)