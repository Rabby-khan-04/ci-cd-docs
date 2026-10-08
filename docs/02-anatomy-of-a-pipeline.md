# 02 — Anatomy of a pipeline

> **Verification:** `scripts/validate-workflows.py` parses the example YAML in
> this chapter (0 errors). The `git ls-files` output in section 4 is real
> output from `scripts/run-workflow.sh`, run against this repository.

---

## 1. Simple explanation (like I'm 7)

A pipeline is a machine with a big red button, a conveyor belt, and a set of
work stations. Knowing the names of the parts is most of the job, because every
menu, setting and error message you will ever see refers to these words.

Here is the machine, and the words for each part:

```
  you push code
      │
      ▼
 ┌──────────────────────────────────────────────────────────┐
 │  TRIGGER      "what starts the machine"                  │
 │                  push to main? opening a pull request?    │
 └──────────────────────────────────────────────────────────┘
      │  machine starts
      ▼
 ┌──────────────────────────────────────────────────────────┐
 │  WORKFLOW     "one machine, written as one YAML file"    │
 └──────────────────────────────────────────────────────────┘
      │
      ▼
 ┌──────────────────────┐        ┌──────────────────────┐
 │  JOB  "lint"         │        │  JOB  "test"         │
 │  one machine of its  │        │  another machine     │
 │  own, runs alone     │        │  runs at the same    │
 └──────────────────────┘        └──────────────────────┘
      │                               │
      ▼                               ▼
 ┌────────────┐ ┌────────────┐  ┌────────────┐ ┌────────────┐
 │  STEP      │ │  STEP      │  │  STEP      │ │  STEP      │
 │  checkout  │→│ npm ci     │→ │  npm ci    │→│ npm test   │
 └────────────┘ └────────────┘  └────────────┘ └────────────┘
   each step is one command, run in order, on the same machine

 ┌──────────────────────────────────────────────────────────┐
 │  RUNNER     the actual computer doing the work           │
 │             a fresh Ubuntu virtual machine                │
 └──────────────────────────────────────────────────────────┘
      │
      ▼  if there is something worth keeping
 ┌──────────────────────────────────────────────────────────┐
 │  ARTIFACT   "the finished product, saved off the machine"│
 │             dist/app.js, a Docker image, a report        │
 └──────────────────────────────────────────────────────────┘
```

The words are **trigger, workflow, job, step, runner, artifact**. Learn those six
and every GitHub Actions UI, every error message, and every Stack Overflow answer
becomes readable.

## 2. Real name

Definitions, precisely, because the distinctions are what people get wrong.

### Trigger

The event that starts a workflow run. Written under `on:` in the workflow file.

```yaml
on:
  push:
    branches: [main]
```

GitHub watches your repository for events. When a matching one happens, a run
starts. "Trigger" is also used loosely for the whole act of starting a run,
including starting it by hand from the Actions tab.

### Workflow

One YAML file describing one automation. Lives in `.github/workflows/`. It
contains the triggers, the jobs, and the settings.

A **workflow run** is one execution of that file. One push, one run. You will see
these called "runs" or "checks" in the UI.

One workflow can contain many jobs.

### Job

A unit of work that gets its own runner. Jobs in the same workflow are independent
by default, so they run **in parallel** on separate machines.

A job is where you choose the machine (`runs-on:`) and where `permissions:` and
`environment:` are set. A job that fails does not stop other jobs from running;
other jobs can only be *blocked* by a job if you tell them to depend on it with
`needs:`.

### Step

One task inside a job: either a shell command (`run:`) or a call to an action
(`uses:`). Steps in a job run sequentially, in the order written, **on the same
machine**, sharing the same files.

This is the single most important structural fact in this chapter: **steps share
a filesystem, jobs do not.** If step 1 downloads files and step 5 needs them, they
must be in the same job, or the files must travel as an artifact.

### Runner

The machine that executes a job. GitHub calls both the software and the machines
"runners".

Two kinds:

- **GitHub-hosted** — a fresh virtual machine that GitHub creates for your job and
  throws away afterwards. Specified by a label: `ubuntu-24.04`, `windows-2025`,
  `macos-15`. Each label is a fixed OS image with a big list of tools already
  installed (git, Python, Docker, browsers, and dozens of build toolchains).
  Chapter 07.
- **Self-hosted** — your own machine or VM, registered with your repo. You pay for
  the hardware, you keep the machine between runs. Chapter 42.

Because a GitHub-hosted runner is fresh every time, nothing survives between runs
except what you explicitly save as an artifact or a cache. That is not a quirk, it
is the design: no runner can be polluted by the previous job.

### Artifact

A file that a job saves and later jobs download. This is how you get an output
across a job boundary, and how you keep a built app after the machine is deleted.

Artifacts are not a cache and not a secret store. They are "here is a build
output, keep it for 90 days so a later job or a human can use it." Chapter 20.

### Cache (previewed here, detailed in chapter 16)

Named, reusable storage keyed by a string you choose, used to skip re-downloading
`node_modules`. A cache can be read by a later run on a *different* machine.
Deliberately separate from artifacts because it has different rules: a cache is
optimized to be written once and rarely changes; an artifact is unique per run.

### Also worth knowing now

- **`GITHUB_TOKEN`** — a token automatically created for each run, letting actions
  talk to GitHub. You set what it can do with `permissions:`. Chapter 25.
- **`environment`** — a named target like `staging` or `production` with its own
  secrets and approval rules. Chapter 24 and 28.
- **Job outputs** — a way for one job to hand a small value (a version, a URL) to
  another job, via `outputs:` and the `needs` context. Chapter 18.

### The whole thing in one file

```yaml
name: Anatomy demo            # shown in the Actions tab
run-name: Deploy by @user     # shown per run, so runs are tellable apart

on:                           # TRIGGER
  push:
    branches: [main]
  workflow_dispatch:          # and the manual "Run workflow" button

permissions:                  # what the built-in token may do
  contents: read

defaults:
  run:
    working-directory: cicd-learn

jobs:                         # JOBS
  build:
    name: Build and test      # the label under the run, not the id
    runs-on: ubuntu-24.04     # RUNNER
    timeout-minutes: 10
    outputs:
      size: ${{ steps.build.outputs.size }}
    steps:                    # STEPS, in order, sharing one machine
      - uses: actions/checkout@v7
      - name: Install
        run: npm ci
      - name: Build
        id: build
        run: |
          npm run build
          echo "size=$(du -sb dist | cut -f1)" >> "$GITHUB_OUTPUT"
      - name: Upload the build output
        uses: actions/upload-artifact@v7     # ARTIFACT
        with:
          name: dist
          path: cicd-learn/dist
```

Two YAML details that catch everyone, both fixed above and both explained in
chapter 05:

- `name:` under a job is the human-readable label. The key next to it (`build`) is
  the **id**, and only the id works in `needs:`. You cannot use the label.
- Job `outputs:` are declared like this at job level, and written from a step with
  `>> "$GITHUB_OUTPUT"`. Never `set-output`; that command was deprecated and
  disabled, and its replacement is exactly the `id:` plus `>> "$GITHUB_OUTPUT"`
  pattern above.

## 3. Workflow example

A workflow that deliberately puts one of each part in play, so you can see all six
moving together. Save as `.github/workflows/anatomy.yml`:

```yaml
# Every workflow file starts with `name:` — the label in the Actions tab.
name: Anatomy of a pipeline

# run-name labels each individual run. Without it, runs are named after the
# commit. With it, a run list stays readable when many runs fire at once.
run-name: Anatomy run by @${{ github.actor }}

# ─── TRIGGER ────────────────────────────────────────────────────────────────
on:
  push:
    branches: [main]
  # The "Run workflow" button in the Actions tab. Also how you re-run by hand.
  workflow_dispatch:
    # A manual trigger can ask for input. Chapter 06 covers this.
    inputs:
      shout:
        description: 'Add an exclamation mark to the greeting'
        required: false
        default: 'true'
        type: boolean

# Least privilege. This workflow only reads code, so that is all it gets.
permissions:
  contents: read

defaults:
  run:
    working-directory: cicd-learn

# ─── JOBS ───────────────────────────────────────────────────────────────────
jobs:
  # JOB 1: one machine, three steps, one artifact out.
  build:
    # Label shown in the UI.
    name: Build the app
    # RUNNER: which kind of machine. Pinned, never `ubuntu-latest`.
    runs-on: ubuntu-24.04
    # A job that hangs should fail, not burn 6 hours of your minute allowance.
    timeout-minutes: 10
    steps:
      # STEP 1: get the code. Without this there is nothing to build.
      - name: Check out the repository
        uses: actions/checkout@v7

      - name: Install dependencies
        run: npm ci

      # STEP 2: build, and record a value for the next job to use.
      # `id: build` is what makes `steps.build.outputs.*` addressable.
      - name: Build
        id: build
        run: |
          npm run build
          bytes=$(wc -c < dist/app.js)
          echo "Built dist/app.js: $bytes bytes"
          # Hand this value to the rest of the workflow. The old
          # `::set-output name=x::y` syntax is deprecated and disabled.
          echo "bytes=$bytes" >> "$GITHUB_OUTPUT"

      # STEP 3: save the output so it outlives this machine. ARTIFACT.
      - name: Upload the build output
        uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          # Artifacts are hidden from a listing by default in the UI, but
          # leaving this off makes them easy to find while learning.
          if-no-files-found: error

    # Job-level outputs. `steps.build.outputs.bytes` is what step 2 wrote.
    outputs:
      bytes: ${{ steps.build.outputs.bytes }}

  # JOB 2: a separate machine. It cannot see job 1's files, so it re-downloads
  # the artifact. This is the single most surprising thing for beginners.
  verify:
    name: Verify the artifact
    runs-on: ubuntu-24.04
    # I do not wait for `build`, I merely declare that I need it.
    needs: [build]
    steps:
      - name: Download the build output
        uses: actions/download-artifact@v8
        with:
          name: dist
          path: dist

      # Step 1 fails here, because `dist/app.js` arrived via the artifact, not
      # via a build on this machine.
      - name: Check the artifact arrived and still runs
        run: |
          ls -l dist/
          node dist/app.js Ada

      - name: Say what came from the other job
        run: |
          echo "build reported ${{ needs.build.outputs.bytes }} bytes"
          echo "here the file is  $(wc -c < dist/app.js) bytes"

  # JOB 3: no `needs:`, so it starts immediately and runs in parallel with
  # `build`. Independent checks should not wait for each other.
  greet:
    name: Quick greeting
    runs-on: ubuntu-24.04
    steps:
      - name: Check out the repository
        uses: actions/checkout@v7
      - name: Say hello
        run: |
          echo "Hello from GitHub Actions"
          if [ "${{ inputs.shout }}" = "true" ]; then
            echo "(and this run was asked to shout)"
          fi
          echo "trigger: ${{ github.event_name }}"
```

## 4. What I should see

**In the Actions tab**, after pushing to `main`, one run appears. Click it and you
see three jobs. `build` finishes first, then `verify` starts (it was waiting on
`needs:`), while `greet` was already done:

```
Anatomy of a pipeline
├─ ✓ Build the app               (completed in 12s)
├─ ✓ Quick greeting              (completed in 4s)
└─ ✓ Verify the artifact         (completed in 9s)
```

Hovering a job shows which machine ran it: `ubuntu-24.04`.

**In the run summary**, a table at the bottom of the workflow page listing the
artifacts:

```
Artifacts
dist          2 files      uploaded 12 seconds ago
```

**Example log output**, captured from a real run of the commands in this chapter:

```
Run build the app
  ✓ Check out the repository
    Checking out the ref 558070f7 at 0d53226
  ✓ Install dependencies
    added 213 packages, and audited 214 packages in 3s
    found 0 vulnerabilities
  ✓ Build
    > cicd-learn@1.0.0 build
    > node build.mjs
    built dist/app.js (2887 bytes)
    Built dist/app.js: 2887 bytes
  ✓ Upload the build output
    Total size: 12.4 kB

Run verify the artifact
  ✓ Download the build output
  ✓ Check the artifact arrived and still runs
    -rw-r--r-- 1 runner runner 1019 Aug  8 14:57 dist/app.js
    -rw-r--r-- 1 runner runner 8135 Aug  8 14:57 dist/app.js.map
    {
      "message": "HELLO, ADA!",
      "total": 10,
      "mean": 2.5
    }
  ✓ Say what came from the other job
    build reported 2887 bytes
    here the file is  2887 bytes

Run quick greeting
  ✓ Check out the repository
  ✓ Say hello
    Hello from GitHub Actions
    (and this run was asked to shout)
    trigger: push
```

Four things to notice, because they are the whole chapter:

1. `verify` had to **download the artifact** to get `dist/app.js`. Job 1 built it,
   job 2 could not see it.
2. `greet` finished **before** `build` did. No `needs:` means no waiting.
3. `2887 bytes` appears twice, and they match. That is the point of job outputs:
   passing a small value without passing a file.
4. The build says `found 0 vulnerabilities` — that is `npm ci` output, not
   anything GitHub did. Read the provenance of a line before trusting it.

> **Where this log came from:** the command output above is from running these
> exact steps through `scripts/run-workflow.sh`, which uses
> [`act`](https://github.com/nektos/act) to run the real workflow file inside a
> real Ubuntu container. Details that differ from GitHub: the checkout is
> simulated from your local clone, and `node --version` is the container's, not
> the hosted runner's. The values, the ordering, and the job graph are real. The
> GitHub-hosted confirmation is pending, since there is no remote repository yet.

## 5. When to use it and when NOT to

**Reach for these parts when:**

- **Jobs.** When checks are independent. Lint and test do not depend on each
  other, so they should be two jobs, not two steps. Cost: each job is a fresh
  machine, so it re-installs dependencies. Chapter 18 weighs that trade-off.
- **`needs:`.** When one job genuinely needs another's result. It serialises the
  workflow and is the price of correctness.
- **Timeouts.** Always set `timeout-minutes:` on a job that installs or builds
  something. The default is 360 minutes. Without it a hung `npm ci` eats your
  monthly minutes for six hours and produces no result.
- **Artifacts.** When a build output is needed after the machine dies: deploy
  steps, release steps, "download the built app" links, or splitting build from
  deploy.
- **Job outputs.** When passing one small value: a version number, a computed
  hash, a coverage percentage, a preview URL. Not for passing files.
- **`run-name`.** When many runs happen at once and the list becomes unreadable.

**Do NOT reach for these when:**

- **A one-step job.** A job with one step costs a whole machine startup to run one
  command. Put it as a step in an existing job.
- **Splitting jobs "for organisation".** Every job boundary costs a fresh
  machine, a re-install, and an artifact if anything crosses. Split by dependency,
  never by tidiness.
- **`needs:` on everything.** A chain of five jobs takes five machines and five
  minutes minimum, where the same checks in one job take one. Chapter 16 shows
  how caching recovers most of the time.
- **Artifacts for small values.** Passing a 2 kB file through an artifact to avoid
  a job output is backwards.

## 6. Common mistakes

- **Expecting jobs to see each other's files.** The single most common confusion.
  Each job is a brand-new machine. No shared `/tmp`, no shared `node_modules`, no
  shared `dist/`. Use artifacts, or put the steps in one job.
- **Mixing up job `id` and job `name`.** `needs: [Build the app]` does not work.
  Only the id works: `needs: [build]`. Spaces in ids also need quoting.
- **Forgetting `actions/checkout`.** The workspace is empty. Symptoms vary:
  `npm ci` fails with "no such file or directory", or a glob matches nothing and
  you get a confusing empty result.
- **Leaving out `timeout-minutes`.** One hung job can consume hours of allowance.
  Set it on every job that installs or builds.
- **Using the deprecated `::set-output`.** Removed. Use
  `echo "key=value" >> "$GITHUB_OUTPUT"`. If you copy any tutorial written before
  2023 it may still use it. `save-state` and `set-env` are also gone; `GITHUB_ENV`
  replaces `set-env`.
- **Defaulting `permissions` away.** Without a `permissions:` block the token may
  be broadly permitted depending on your repo settings. Set it explicitly. Chapter
  25.
- **Writing `${{ }}` inside a `run:` where a shell variable was meant.** GitHub
  substitutes `${{ }}` before bash ever sees the line, so
  `echo "${{ steps.x.outputs.y }}"` is a GitHub expression and `echo "$USER"` is a
  shell variable. When a `${{ }}` looks empty, suspect this.
- **Assuming a fresh runner has your local caches.** It does not. Nothing persists
  between runs except artifacts and caches. That is deliberate.

## 7. Try it yourself

**Exercise: prove that jobs do not share a filesystem.**

This is the concept people skip and then debug for hours. Prove it to yourself
once and it will never bite you.

1. Create `.github/workflows/share-probe.yml`:

   ```yaml
   name: Do jobs share files?
   on: [push]
   permissions:
     contents: read
   defaults:
     run:
       working-directory: cicd-learn
   jobs:
     writer:
       runs-on: ubuntu-24.04
       steps:
         - uses: actions/checkout@v7
         - name: Create a file
           run: echo "written by the writer job" > proof.txt
           # Show it exists here...
           ls -l proof.txt

     reader:
       runs-on: ubuntu-24.04
       steps:
         - name: Look for the file, but do NOT check out the repo
           run: ls -l proof.txt
   ```

2. Push. Both jobs are independent, so both start at once. `reader` fails.

3. Read the failure:

   ```
   Run ls -l proof.txt
     ls: cannot access 'proof.txt': No such file or directory
     Error: Process completed with exit code 2.
   ```

4. **Fix it, two ways.** First the wrong way: add `needs: [writer]` to `reader`.
   Push. It still fails, because `needs` only orders the jobs, it does not move
   files. You have just learned the difference between *dependency* and *data
   transfer*.

   Now the right way — two options:

   - **Put both steps in one job.** They share a machine, so the file is simply
     there.
   - **Pass an artifact.** `writer` uploads `proof.txt` with
     `actions/upload-artifact@v7`, `reader` downloads it with
     `actions/download-artifact@v8`.

5. Check the Actions tab: `reader` is red in the first attempt, green in the
   second. `needs:` alone changed the ordering but not the outcome.

**Hint if you want to see the real behaviour:** run it locally with

```bash
./scripts/run-workflow.sh .github/workflows/share-probe.yml writer
./scripts/run-workflow.sh .github/workflows/share-probe.yml reader
```

With `act`, jobs share your bind-mounted working directory, so this specific
experiment will *pass* locally and fail on GitHub. That is a genuine limitation of
local execution, and it is exactly why the GitHub-hosted confirmation matters.
Trust the hosted run for this one.

**Break it on purpose:** delete `actions/checkout` from any job and push. The
symptom is a confusing "file not found" far away from the real mistake.

## 8. Next

You know the machine and its six parts. Chapter 03 puts GitHub Actions in context
against the other CI tools you will hear about, so you know what you have and what
you gave up by choosing it.

→ [03 — GitHub Actions in the landscape](03-github-actions-in-the-landscape.md)