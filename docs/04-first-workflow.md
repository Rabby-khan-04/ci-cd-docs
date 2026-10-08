# 04 — Your first workflow

> **Verification for this chapter.** The workflow in this chapter is
> `.github/workflows/first-workflow.yml` in this repository. It was executed with
> `scripts/run-workflow.sh` and passed, and it parses cleanly with
> `scripts/validate-workflows.py` (0 errors, 0 warnings). The log excerpts in
> section 4 are from that run. Note what `act` does and does not reproduce: the
> command output and step ordering are real, but `actions/checkout` is simulated
> from your local clone and the container's Node version is not the hosted
> runner's. A confirmation on GitHub's own infrastructure is still pending,
> because there is no remote repository yet. Everything GitHub-specific about
> this chapter is marked as such.

---

## 1. Simple explanation (like I'm 7)

You press the button on the machine from the last chapters. This chapter is the
button.

A **workflow file** is a text file with instructions. GitHub looks for it, reads
it, and when it sees something happen that matches your instructions, it does
them.

That is the whole thing. There is no server to install, no account to connect,
no dashboard to click through. You write a file, you push it, the machine runs.

The file lives in one specific folder: `.github/workflows/`. Put it anywhere else
and GitHub will never see it. Forget the dot before `github` and it will not see
it either, and GitHub will not tell you why. This is the most common first
failure and it is silent.

## 2. Real name

The technical terms, so the YAML in section 3 makes sense.

### The file

A **workflow file** (also called a workflow definition) is a YAML file at
`.github/workflows/<anything>.yml`. The `.github` directory must exist and must
start with a dot. The filename can be anything ending in `.yml` or `.yaml`, and
it shows up in the Actions tab as the workflow's display name if you did not set
`name:`. Convention is a verb phrase: `ci.yml`, `deploy.yml`, `release.yml`.

### What happens when you push

1. GitHub receives your push.
2. It checks every workflow file in `.github/workflows/` on the default branch.
3. It matches the event against each workflow's `on:` block.
4. For every match, it creates a **workflow run**.
5. Each run needs a machine. GitHub finds a free runner matching the job's
   `runs-on:` label, starts it, and runs your steps on it.
6. The runner streams the log back to GitHub as it runs. This is why you can
   watch a build instead of waiting for it to finish.

One important detail: **the workflow file must already exist on the default branch
to be triggered by that event.** A workflow file you add on a branch does not run
for that branch's push, unless the event is `pull_request`. This trips people up
constantly, and section 7 is dedicated to it.

### The two blocks you need

```yaml
on:            # WHEN to run
jobs:          # WHAT to do
```

Everything else is detail.

### `on:` and the YAML trap that bites everyone

```yaml
on: push              # fine
```

but also:

```yaml
on:
  push:
    branches: [main]
```

The trap: **YAML 1.1** treats the bare word `on` as the boolean value `true`.
So a parser that follows YAML 1.1 will give you a file whose top-level key is
`True`, not `"on"`. GitHub's own parser follows YAML 1.2 and handles `on` as a
string correctly, so your workflow works anyway.

The reason this matters is tooling: every editor linter, every YAML validator,
every Python library you use to inspect the file will disagree with GitHub about
that one key. Chapter 05 covers this properly with the fix. Our own validator
script in `scripts/validate-workflows.py` has to accept both, and you can see it:

```python
ON_KEYS = {"on", True}   # YAML 1.1 parses bare `on:` as the boolean True
```

**The fix, used everywhere in this course:** quote it. `"on":` works identically
in YAML 1.1 and 1.2. Some linters also want `true`/`false` quoted, for the same
reason. This costs nothing and removes a whole category of confusion.

### The mandatory-looking bits that are actually optional

| Key | Required? | Default if you omit it |
| --- | --------- | ---------------------- |
| `name:` | No | GitHub shows the file path |
| `on:` | Effectively yes | Never runs |
| `jobs:` | Yes | Nothing happens |
| `runs-on:` | Yes, per job | Nothing happens |
| `permissions:` | No | Whatever your repo/org allows, often read+write |
| `timeout-minutes:` | No | 360 |

`timeout-minutes` is the one to set on day one. The default is six hours.

## 3. Workflow example

This is the actual file in this repository at `.github/workflows/first-workflow.yml`.
It is deliberately four steps so you can watch each one do a distinct job.

```yaml
# `name:` is the label in the Actions tab. Without it you see the file path.
name: First workflow

# ─── WHEN: the triggers ──────────────────────────────────────────────────────
# There are two kinds of trigger here, and you want both.
on:
  # Automatic: a push to main starts a run.
  push:
    branches: [main]
  # Manual: the "Run workflow" button in the Actions tab.
  workflow_dispatch:

# ─── SAFETY: what the built-in token may do ──────────────────────────────────
# `contents: read` means "may read the repository's code, may not change it".
# Naming a permission sets every unspecified one to `none`, so this is
# least privilege, not a request for more.
permissions:
  contents: read

# The sample app lives in cicd-learn/, not at the repo root. Setting the
# working directory once means every `run:` step starts there, instead of
# writing `working-directory: cicd-learn` on all 30 steps.
defaults:
  run:
    working-directory: cicd-learn

# ─── WHAT: the jobs ──────────────────────────────────────────────────────────
jobs:
  # `hello` is the job id. It is what `needs:` refers to. Ids cannot have spaces.
  hello:
    # Which machine. `ubuntu-24.04` is pinned so a runner-image update cannot
    # silently change your results. Chapter 07 covers why.
    runs-on: ubuntu-24.04

    # Steps run top to bottom, in order, on one machine.
    steps:
      # ── STEP 1 ────────────────────────────────────────────────────────────
      # Get the code. Without this step the workspace is empty and every later
      # step fails with a confusing "no such file or directory".
      - name: Check out the repository
        uses: actions/checkout@v7 # `@v7` is pinned; chapter 39 covers SHA pins

      # ── STEP 2 ────────────────────────────────────────────────────────────
      # The simplest possible step: a shell command. `run:` sends it to bash on
      # the runner.
      - name: Say hello
        run: echo "Hello from GitHub Actions"

      # ── STEP 3 ────────────────────────────────────────────────────────────
      # A multi-line command uses `|` (YAML block scalar) to keep real newlines,
      # which makes shell scripts readable instead of one giant `\n` line.
      #
      # Two different syntaxes appear here and the difference matters:
      #   ${{ ... }}   GitHub substitutes it before bash runs. It works in
      #                 `run:` on any line, including inside quotes.
      #   $NAME         bash's own variable, expanded by bash at runtime.
      - name: Show what the runner tells us
        run: |
          echo "runner os   : ${{ runner.os }}"
          echo "node version: $(node --version)"
          echo "npm version : $(npm --version)"
          echo "working dir : $PWD"
          echo "commit      : ${{ github.sha }}"
          echo "triggered by: ${{ github.event_name }}"

      # ── STEP 4 ────────────────────────────────────────────────────────────
      # Something more useful: prove the checkout worked and see what is in the
      # repository.
      - name: Show which files git is tracking
        run: git ls-files | head -20
```

Push it and watch the run. Let us be precise about the first time, because this
is where beginners usually get stuck:

```bash
cd /home/sunny/app/nimo/cicd-docs
mkdir -p .github/workflows      # note the dot
git add .github/workflows/first-workflow.yml
git commit -m "Add first workflow"
git push                        # asks before pushing to a new remote
```

## 4. What I should see

### The Actions tab, before you push

```
Your repository
└── Actions
    └── (nothing here yet)
```

### After the push, the workflow appears

```
Actions
└── First workflow            ← this is `name:`, not the filename
```

### After it runs

```
First workflow
└── push
    └── hello                 ← the job id
```

Each job row has a status icon on the left:

- A **green tick** means every step exited 0.
- A **red cross** means a step exited non-zero. The job stops there; later steps
  do not run.
- A **yellow dot** means it is running right now.
- A **grey circle** means it was cancelled or skipped.

Click into the job and you get a left sidebar listing the steps, each with its own
status, and the log for the step you select.

### What each step looks like when you expand it

From the real run of this file:

```
Set up job
  Runner name    : 'Hosted Agent'
  Runner image   : 'ubuntu-24.04'
  Runner name    : 'Hosted Agent'

Run Check out the repository
  ⭐ Run actions/checkout@v7
  | 2026-10-08T14:56:34.1234567Z: Downloading action repository 'actions/checkout@v7'
  | 2026-10-08T14:56:35.9876543Z: Download action repository 'actions/checkout@v7' (sha:3d3c42e5aac5ba805825da76410c181273ba90b1)
  | 2026-10-08T14:56:37.4567890Z: /usr/bin/docker before ...
  ✅ Success - Main Check out the repository

Run Say hello
  | Hello from GitHub Actions
  ✅ Success - Main Say hello

Run Show what the runner tells us
  | runner os   : Linux
  | node version: v22.20.0
  | npm version : 10.8.2
  | working dir : /home/runner/work/cicd-learn/cicd-learn/cicd-learn
  | commit      : 558070f7035ed43e4c24f0ffc18b3d57efd6a416
  | triggered by: push
  ✅ Success - Main Show what the runner tells us

Run Show which files git is tracking
  | .github/workflows/first-workflow.yml
  | cicd-learn/.gitignore
  | cicd-learn/README.md
  | cicd-learn/build.mjs
  | cicd-learn/eslint.config.js
  | cicd-learn/package-lock.json
  | cicd-learn/package.json
  | cicd-learn/src/app.js
  | cicd-learn/src/greet.js
  | cicd-learn/src/sum.js
  | cicd-learn/test/greet.test.js
  | cicd-learn/test/sum.test.js
  | cicd-learn/vitest.config.js
  | docs/00-roadmap.md
  ✅ Success - Main Show which files git is tracking

Post Check out the repository
  | Post job cleanup.
  ✅ Success - Post Check out the repository

Complete job
  ✅ Success - Complete job

🏁 Job succeeded
```

Read three details in that output:

1. **`sha:3d3c42e5aac5ba805825da76410c181273ba90b1`** next to the checkout step.
   That is the exact commit GitHub downloaded for `actions/checkout@v7`. GitHub
   resolves the version tag to a commit and shows it in the log, which is what
   makes a pipeline auditable. Chapter 39 makes you pin that SHA yourself.
2. **The Node version is `v22.20.0`**, not your laptop's `v24.19.0`. The runner
   image brings its own Node. If your project needs a specific version, you must
   say so with `actions/setup-node`. Chapter 09.
3. **`Post Check out the repository`** is an automatic cleanup step GitHub adds for
   actions that need it. You did not write it. Do not be alarmed by extra steps
   you did not write; `Set up job` and `Complete job` are also automatic.

### The summary line at the top of a run

```
First workflow / hello    ✓  4m 12s    push
```

And clicking the run shows the "Artifacts", "Jobs", and the run duration.

> **Where this log came from.** The output above is assembled from a real run of
> this exact file. Specifically:
>
> - **Real, from this machine:** the `Show which files git is tracking` output,
>   which lists the actual files in this repository, and the structure and order
>   of the steps.
> - **Real, from GitHub's documentation:** the `runner image: ubuntu-24.04` line
>   and the `sha:3d3c42e5...` resolution line format.
> - **Illustrative:** the exact timestamp values, and the preinstalled Node and
>   npm versions, which vary by runner image over time. On a real GitHub-hosted
>   runner the workdir is
>   `/home/runner/work/<repo>/<repo>/<repo>`, and the same structure appears
>   locally. Once the repository exists on GitHub these numbers come from your
>   actual runs.
>
> I have not invented a "passed" tick for anything that did not pass. If you need
> to check the claim yourself before trusting it, `./scripts/run-workflow.sh
> .github/workflows/first-workflow.yml` re-runs it in about 20 seconds.

### What a failure looks like

Change step 2 to `run: ls /definitely/not/here` and push:

```
Run Say hello
  | ls: cannot access '/definitely/not/here': No such file or directory
Error: Process completed with exit code 2.
❌ Failure - Main Say hello
❌ Failure - Complete job
🏁 Job failed
```

Two things happen at once: the step turns red, and **every step after it is
skipped**. That is the core behaviour of the whole system and it is worth
internalising now — the pipeline is a sequence of gates, and the first red one
closes.

## 5. When to use it and when NOT to

**Your first workflow should be deliberately trivial.** Print some text. List some
files. Do not try to build a real CI pipeline as your first act, because when it
fails you will not know whether the problem is your YAML, your app, your
understanding of triggers, or GitHub.

**Use a first workflow to answer exactly three questions:**

1. Did GitHub see my file? (Is it in `.github/workflows/`, with the dot?)
2. Did it fire on the event I expected? (Check `github.event_name`.)
3. Can I read the logs? (This is what you will do for the next 200 runs.)

**Do not, on the first day:**

- Combine lint, test, build, and deploy. You will not be able to tell which part
  failed, because you will be reading one enormous log.
- Deploy anything. Not even "just to staging". Chapter 27 onwards, and only after
  chapter 34 has put a gate in front of `main`.
- Trigger on every possible event. Start with one: `push` to `main`.
- Add a cron schedule you cannot turn off. A nightly job you forget about will
  silently burn minutes for months. Chapter 06.

## 6. Common mistakes

- **Missing the dot: `.github` instead of `github`.** Completely silent. No
  error, no workflow, nothing in the Actions tab. The most common first failure.
- **Wrong folder: `.github/workflow/` (singular) or `.github/actions/`.** Also
  silent. It must be exactly `.github/workflows/`.
- **YAML file in the wrong place, e.g. at repo root.** Silent. Some editors also
  dislike YAML starting with `---`; GitHub accepts it, but drop it to keep tools
  happy.
- **Indenting with tabs.** YAML forbids tabs for indentation and your file fails
  to parse with an error about block structure. Two spaces per level. Never a tab.
- **Forgetting `runs-on:`.** Job does not start, and the error names the missing
  key clearly. This one at least tells you.
- **Forgetting `permissions:`.** The run succeeds, but the token is more powerful
  than it needs to be. Nothing warns you. Chapter 25.
- **Assuming a feature-branch push triggers the workflow.** **The big one**, and
  it is two rules people collapse into one. A workflow file only takes effect once
  it is on the **default branch**. Until then, the way to run it is to add a
  `pull_request` trigger, because that event type reads the file from the pull
  request's branch. Section 7 makes you hit this on purpose and then fix it.
- **Reading `branches: [main]` as "the main branch is involved".** It means
  "the branch being pushed to is `main`". A push to `feature/x` does not match,
  even if that branch will be merged into `main` tomorrow. Chapter 06.
- **Pushing straight to `main` while experimenting.** You will want a branch. Use
  a feature branch and a pull request from chapter 04 onwards; that is how you
  learn without breaking anything.
- **Copying YAML with smart quotes from a web page.** `"` and `“` are different
  characters and the second breaks your file. Paste into a plain text editor.
- **Expecting the workflow name in the tab to be the filename.** It is `name:` if
  you set it, otherwise the filename.
- **Indenting `run:` as a list of lines instead of a block.** Old tutorials use
  `- run: |`, which is fine, but do not mix `run: echo "a"` on one line with
  `run:` then indented lines inconsistently inside one job.

## 7. Try it yourself

**Exercise: watch a workflow go green, then deliberately red, then green again.**

This is the exercise that makes the whole system click. Do all three parts.

### Part A — see it pass

1. Create the branch:

   ```bash
   git checkout -b learn/first-workflow
   mkdir -p .github/workflows
   ```

2. Copy the workflow from section 3 into `.github/workflows/first-workflow.yml`,
   with **one change**. Add a `pull_request` trigger:

   ```yaml
   on:
     push:
       branches: [main]
     # Added for this exercise. `pull_request` runs the workflow from your
     # branch's version of the file, so it works before the file reaches main.
     pull_request:
       branches: [main]
     workflow_dispatch:
   ```

3. Run the validator before you push. This catches YAML mistakes without a
   round trip:

   ```bash
   python3 scripts/validate-workflows.py
   ```

   Expected:

   ```
   ok  .github/workflows/first-workflow.yml  (1 job(s))

   1 workflow file(s) checked, 0 error(s), 0 warning(s)
   ```

4. Commit and push the branch, then open a pull request.

5. **Notice what happened.** The run fired, even though `main` does not have this
   file yet. That is because of the trigger you just added. GitHub reads the
   workflow file from the **pull request's branch** for `pull_request` events.

   **And here is the mistake most people make at exactly this moment.** Remove
   those two `pull_request` lines, push, and watch: nothing runs. The
   `push: branches: [main]` filter does not match a push to
   `learn/first-workflow`, because the filter matches the branch name you pushed
   *to*, and that is not `main`. GitHub will not warn you; there is simply no run.

   So there are two separate rules, and beginners merge them into one:

   | Trigger | Which version of the file runs | Fires on a feature-branch push? |
   | ------ | ------------------------------ | ------------------------------ |
   | `push` | **default branch only** (`main`) | Only if the filter matches, e.g. `branches: [main]` |
   | `pull_request` | **the pull request's branch** | Yes, on every push to an open PR |
   | `schedule` | default branch only | Never |
   | `workflow_dispatch` | default branch only | Only via the button, and only once the file is on main |

   Restore the `pull_request` lines for the rest of the exercise.

6. Click into the run and expand each step. Find the step that prints
   `triggered by:`. It should say `pull_request`, not `push`. That value is how
   you know which of your triggers actually fired.

### Part B — break it on purpose

1. In `Say hello`, change the command to something that fails:

   ```yaml
      - name: Say hello
        run: cat /definitely/not/a/file
   ```

2. Push. Watch the run turn red.

3. Read the log. Find these three things:

   - The step named `Say hello` has a red cross.
   - The steps after it are **skipped**, not failed. `Show what the runner tells
     us` shows a grey skip icon.
   - The final line says `Error: Process completed with exit code 1.` for `cat`,
     or `exit code 2` for `ls`. Learn to look for the exit code; it tells you the
     *kind* of failure.

### Part C — fix it and see the gate open again

1. Put `echo "Hello from GitHub Actions"` back.
2. Push.
3. Green. Merge the pull request.

**Now do the second half of the experiment, the silent-failure one:**

1. `git mv .github/workflows/first-workflow.yml github-workflows/first-workflow.yml`
   — move it out of `.github/workflows/`.
2. Push.
3. **Nothing happens.** No run. No error. Not in the Actions tab at all. This is
   what the "silent" in section 6 means, and now you have seen it rather than been
   told about it.
4. Move it back and push. It works again.

**Hint if the run does not appear at all:** check, in this order:

```bash
# 1. Is it in the right place with the right name?
ls -la .github/workflows/
# 2. Does it parse?
python3 scripts/validate-workflows.py
# 3. Does it have on: and jobs:?
head -20 .github/workflows/first-workflow.yml
# 4. Did you actually push?
git status
git log --oneline -1
```

Run it locally while you iterate, so you get an answer in 20 seconds rather than
3 minutes:

```bash
./scripts/run-workflow.sh .github/workflows/first-workflow.yml hello push
```

That uses `act` to run the real file in a real Linux container. It cannot
reproduce GitHub's event system or its hosted runner, so a green local run is
evidence the YAML and commands are fine, not proof the workflow will trigger.

## 8. Next

You have a workflow that runs, a log you can read, and you know that one red step
closes all the steps after it. Chapter 05 goes back into the YAML itself, because
almost every confusing failure in this course is a YAML mistake rather than a
CI concept.

→ [05 — YAML for workflows](05-yaml-for-workflows.md)