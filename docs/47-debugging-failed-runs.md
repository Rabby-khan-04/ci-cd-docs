# 47 — Debugging failed runs

> **Verification.** The workflow used as this chapter's running example is
> `.github/workflows/26-secret-safety.yml`, executed with
> `./scripts/verify.sh .github/workflows/26-secret-safety.yml safety push ch26`
> → `docs/_logs/ch26.log` (exit 0). Two other saved logs are quoted and labelled
> where they come from: `docs/_logs/ch12-lint.log` (the lint step) and
> `docs/_logs/ch08-steps.log` (continue-on-error). `python3 scripts/validate-workflows.py`
> reports `ok .github/workflows/26-secret-safety.yml (1 job(s))`.
>
> **What local execution proves:** that the workflow's YAML is valid; that the
> commands run and exit as intended; and the exact byte stream each step wrote to
> stdout. **What it cannot prove, and none of it is claimed below:** the Actions
> tab's job/step tree, the red/green icons, the `Error: Process completed with exit
> code N` runner wording (act prints `exitcode 'N': failure` instead), the
> Annotations pane, `gh run view --log-failed`, the hosted-runner toolchain,
> minutes billing, and secret masking. Those are GitHub-only and are marked
> `[read-only example]` where they appear. The hosted confirmation is pending,
> because there is no remote repository yet.

---

## 1. Simple explanation (like I'm 7)

Imagine a smoke alarm in a kitchen. It goes off. You do not start by reading every
recipe book in the house. You walk into the kitchen, look at the stove, and ask
three questions in order: which burner, what is on it, and what just changed.
Ninety-nine times out of a hundred the answer is "the left front burner, and
somebody left a towel on it."

A red CI build is the same alarm. The instinct is to read the whole log from the
top. That is the recipe-book move, and it wastes an hour. The job has already
told you which burner: the red step. The log has already told you what is on it:
the last twenty lines before the error. And the diff has already told you what
changed: the commit that started the run.

So the ritual is short. Three questions, in order, every time. Do not skip the
order, because the first question is the cheapest and the third is the one that
actually fixes it.

## 2. Real name

### Triage, in order

1. **Which step failed.** The step name, not the job name. A job with five steps
   has one red step; the other four are green and irrelevant. Click the red step.
2. **What exit code it returned.** `0` is success; anything else is failure, and
   the number is a category, not a sentence. `1` = the command decided to fail;
   `2` = shell misuse; `126` = found but not executable; `127` = command not
   found or never started; `137` = killed (OOM or timeout). Exit codes are
   defined in chapter 10.
3. **The last twenty lines before the error.** The verdict is at the bottom of
   the step. The top is setup noise. Read upward from
   `Error: Process completed with exit code N`, not downward from the first line.

Do these three before you read anything else. If the answer is not obvious after
them, then widen the search: the diff, the job graph, the matrix leg, the cache
key.

### The six real causes, in the order they actually happen

These are the causes that produce most red builds in this repository and in most
others. They are listed in the order you should suspect them.

1. **Missing `actions/checkout`.** The workspace is empty. Symptom: `npm ci`
   fails with "no such file or directory", or a glob matches nothing. Fix: add
   the checkout step as the first step of the job.
2. **`defaults.run.working-directory` on a job with no checkout.** The runner
   tries to `chdir` into `cicd-learn` before any file exists, bash never starts,
   and the step exits `127`. This is the single most confusing failure in this
   course; it is called out in the brief and in chapter 08. Fix: either check
   out first, or remove the default from that job.
3. **Unpinned or moving action references.** `actions/checkout@main` or
   `actions/checkout` with no version picks up whatever the maintainer pushed
   last. Symptom: a workflow that was green last week is red this week with no
   code change of yours. Fix: pin to a major version (`@v7`) at minimum, and to
   a SHA in chapter 39.
4. **Cache key mismatch.** The cache key changed (lock file changed, OS
   changed, or a typo in the key), so `npm ci` runs cold and takes three times
   as long, or a stale cache restores the wrong `node_modules`. Symptom: "npm
   cache is not found" in the log, or `cache-hit=false`, followed by a slow
   install. Fix: check the key inputs and the lock file diff (chapter 16).
5. **Node version drift.** The workflow pins `node-version: '22'`, the runner
   image ships something else, and a step that relies on a Node feature breaks.
   Symptom: a syntax error or "not supported" message that only appears in CI.
   Fix: always install Node with `actions/setup-node` before using it, and print
   the version in the summary so you can see what actually ran.
6. **Flaky tests.** A test that passes locally and fails in CI one run in ten,
   usually because of time, ordering, or a shared resource. Symptom: re-running
   the same commit goes green. Fix: do not just re-run; find the test, make it
   deterministic, or quarantine it with a tracked issue.

### `act` as a reproduction tool

`act` runs the real workflow file in a real container on your laptop. It is how
this course produces every log. It is the right first move for a failure you can
reproduce locally: run the workflow, read the log in `docs/_logs/`, fix,
re-run. It is not a replacement for GitHub: it cannot reproduce secrets,
environments, concurrency, the hosted runner toolchain, or minutes billing.
Anything in that list is a `[read-only example]` and needs a real run.

### `continue-on-error` and why it confuses people

A step with `continue-on-error: true` that fails is printed red in its own
block, but the job stays green. That is the single most misread signal in a
log: a red step inside a green job. Chapter 08's log shows it exactly. The
step's **conclusion** is `failure`; the job's **status** is `success`. They are
different fields, and both are real. Do not assume a green job means every step
passed.

## 3. Workflow example

This chapter's running example is the secret-safety workflow,
`.github/workflows/26-secret-safety.yml`. It is a workflow whose scan step is
designed to fail when a credential shape is present, which makes it a good
vehicle for practising triage. The full file:

```yaml
name: Secret safety

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  safety:
    name: Secret safety checks
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

      # ── 1. No secrets committed to the repository ──────────────────────────
      - name: Scan tracked files for credential shapes
        run: |
          set +e
          hits=0

          git grep -nE 'BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY' -- . \
            && hits=1 || echo "no private keys in tracked files"

          git grep -nE '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' -- . \
            && hits=1 || echo "no GitHub tokens in tracked files"

          git grep -nE '_authToken\s*=' -- . \
            && hits=1 || echo "no npm auth tokens in tracked files"

          git grep -nE '\b(AKIA|ASIA)[0-9A-Z]{16}\b' -- . \
            && hits=1 || echo "no AWS access key ids in tracked files"

          git grep -nEi '(password|passwd|secret|api[_-]?key|token)\s*[:=]\s*["'"'"'][^"'"'"']{8,}' -- . \
            && hits=1 || echo "no hardcoded credential assignments"

          if [ "$hits" = "1" ]; then
            echo "::error title=Possible secret in the repository::See the matches above."
            exit 1
          fi
          echo "clean"

      # ── 2. .gitignore covers the files that would contain secrets ─────────
      - name: Check .gitignore
        run: |
          for pattern in '.env' 'node_modules' 'dist'; do
            if grep -qxF -e "$pattern" -e "$pattern/" .gitignore; then
              echo "ok: .gitignore contains $pattern"
            else
              echo "::error::.gitignore is missing $pattern"
              exit 1
            fi
          done

      # ── 3. The log-injection problem, demonstrated safely ─────────────────
      - name: Show why transformations leak
        env:
          FAKE_TOKEN: 'demo-token-abcdef123456'
        run: |
          echo "Direct print        : $FAKE_TOKEN        <- GitHub would mask this"
          echo "Length              : ${#FAKE_TOKEN} chars <- NOT masked"
          echo "Reversed            : $(printf %s "$FAKE_TOKEN" | rev) <- NOT masked"
          echo "Base64              : $(printf %s "$FAKE_TOKEN" | base64) <- NOT masked"

      # ── 4. set -x is a secret leak with extra steps ───────────────────────
      - name: Why set -x is dangerous in a secret-handling step
        run: |
          echo "set -x echoes every expanded command, credentials included."
          echo "Never enable it in a step that reads a secret."

      # ── 5. Fork safety ────────────────────────────────────────────────────
      - name: Fork safety is a feature
        run: |
          echo "PRs from forks run with no secrets and a read-only token."
          echo "That is why you never deploy from an untrusted pull request."
```

## 4. What I should see

### The triage ritual on a passing run (baseline)

From `docs/_logs/ch26.log`, the scan step that is the gate:

```
[Secret safety/Secret safety checks] ⭐ Run Main Scan tracked files for credential shapes
[Secret safety/Secret safety checks]   | no private keys in tracked files
[Secret safety/Secret safety checks]   | no GitHub tokens in tracked files
[Secret safety/Secret safety checks]   | no npm auth tokens in tracked files
[Secret safety/Secret safety checks]   | no AWS access key ids in tracked files
[Secret safety/Secret safety checks]   | no hardcoded credential assignments
[Secret safety/Secret safety checks]   | clean
[Secret safety/Secret safety checks]   ✅  Success - Main Scan tracked files for credential shapes [87.530311ms]
```

Question 1 (which step): `Scan tracked files for credential shapes`. Question 2 (exit
code): `Success`, which means `0`. Question 3 (last lines): `clean`. Verdict:
green, nothing to do. The whole ritual took three lines.

The `.gitignore` check from the same log:

```
[Secret safety/Secret safety checks] ⭐ Run Main Check .gitignore
[Secret safety/Secret safety checks]   | ok: .gitignore contains .env
[Secret safety/Secret safety checks]   | ok: .gitignore contains node_modules
[Secret safety/Secret safety checks]   | ok: .gitignore contains dist
[Secret safety/Secret safety checks]   ✅  Success - Main Check .gitignore [73.001612ms]
```

And the transformation step, which is what a leak looks like when it happens:

```
[Secret safety/Secret safety checks] ⭐ Run Main Show why transformations leak
[Secret safety/Secret safety checks]   | This token is NOT a secret. It is a hardcoded string.
[Secret safety/Secret safety checks]   |
[Secret safety/Secret safety checks]   | Direct print        : demo-token-abcdef123456        <- GitHub would mask this
[Secret safety/Secret safety checks]   | Length              : 23 chars <- NOT masked
[Secret safety/Secret safety checks]   | Reversed            : 654321fedcba-nekot-omed <- NOT masked
[Secret safety/Secret safety checks]   | Base64              : ZGVtby10b2tlbi1hYmNkZWYxMjM0NTY= <- NOT masked
[Secret safety/Secret safety checks]   | As JSON             : {"t":"demo-token-abcdef123456"} <- NOT masked
[Secret safety/Secret safety checks]   | URL-encoded         : demo%2Dtoken%2Dabcdef123456 <- NOT masked
[Secret safety/Secret safety checks]   |
[Secret safety/Secret safety checks]   | GitHub's masking is a literal string replacement in the log stream.
[Secret safety/Secret safety checks]   | Anything derived from the secret does not match, so it is printed.
[Secret safety/Secret safety checks]   ✅  Success - Main Show why transformations leak [77.745595ms]
```

On GitHub the "Direct print" line would show `***` instead of the value, and every
other line would look exactly as above. That is the whole lesson in one block:
the mask catches one form and misses all the others.

The `set -x` and fork-safety steps print their rules:

```
[Secret safety/Secret safety checks] ⭐ Run Main Why set -x is dangerous in a secret-handling step
[Secret safety/Secret safety checks]   | set -x echoes every expanded command, credentials included.
[Secret safety/Secret safety checks]   | Never enable it in a step that reads a secret.
[Secret safety/Secret safety checks]   ✅  Success - Main Why set -x is dangerous in a secret-handling step [77.189584ms]

[Secret safety/Secret safety checks] ⭐ Run Main Fork safety is a feature
[Secret safety/Secret safety checks]   | PRs from forks run with no secrets and a read-only token.
[Secret safety/Secret safety checks]   | That is why you never deploy from an untrusted pull request.
[Secret safety/Secret safety checks]   ✅  Success - Main Fork safety is a feature [72.628972ms]
```

### A broken lint run (what red looks like)

From `docs/_logs/ch12-lint.log`, the same ritual on a lint step. This run is
green, so it shows the shape of a *passing* lint step; a broken one prints the
ESLint complaints and `Error: Process completed with exit code 1` where the
`✅ Success` line is:

```
[Lint step/Lint] ⭐ Run Main Lint
[Lint step/Lint]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/lint] user= workdir=cicd-learn
[Lint step/Lint]   | 
[Lint step/Lint]   | > cicd-learn@1.0.0 lint
[Lint step/Lint]   | > eslint .
[Lint step/Lint]   | 
[Lint step/Lint]   ✅  Success - Main Lint [560.048517ms]
```

And the table that the lint report step prints, which is the evidence you read
when the lint step is red:

```
[Lint step/Lint] ⭐ Run Main Lint report as a table
[Lint step/Lint]   | | file                         | errors | warnings |
[Lint step/Lint]   | | ---------------------------- | -----: | -------: |
[Lint step/Lint]   | | build.mjs                    |      0 |        0 |
[Lint step/Lint]   | | src/greet.js                 |      0 |        0 |
[Lint step/Lint]   | | src/sum.js                   |      0 |        0 |
[Lint step/Lint]   | | test/greet.test.js           |      0 |        0 |
[Lint step/Lint]   | **Total: 0 error(s), 0 warning(s)**
```

When a file has errors, the `errors` column is non-zero and the lint step exits
`1`. The table tells you *which* file; the lint step's output tells you *which
line*.

### `continue-on-error` and the red-step-in-a-green-job trap

From `docs/_logs/ch08-steps.log`, a step that fails but is allowed to:

```
[Jobs and steps/run versus uses] ⭐ Run Main Fails, but the job survives
[Jobs and steps/run versus uses]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/soft-fail] user= workdir=cicd-learn
[Jobs and steps/run versus uses]   | about to exit 1
[Jobs and steps/run versus uses] Failed but continue next step
[Jobs and steps/run versus uses]   ❌  Failure - Main Fails, but the job survives [57.114737ms]

[Jobs and steps/run versus uses] ⭐ Run Main Proof the job continued, and how to read the step's conclusion
[Jobs and steps/run versus uses]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/12] user= workdir=cicd-learn
[Jobs and steps/run versus uses]   | previous step conclusion: failure
[Jobs and steps/run versus uses]   | job status              : success
[Jobs and steps/run versus uses]   ✅  Success - Main Proof the job continued, and how to read the step's conclusion [63.627411ms]
```

Read both blocks. The first says `❌ Failure`; the second says `job status: success`.
Both are true. The step's conclusion is `failure`, the job's status is `success`,
and the log shows them side by side. If you only look at the job-level green
tick, you miss the red step entirely. This is why triage question 1 is "which
step failed", not "which job failed".

### The six causes, matched to their symptoms

| Cause | What the log shows | Where to look |
| ----- | ------------------ | ------------- |
| Missing checkout | `npm ci` → `ENOENT: no such file or directory` | First step of the job |
| `working-directory` without checkout | `Error: Process completed with exit code 127` with no bash output | `defaults.run.working-directory` vs checkout order |
| Unpinned / moving action | Green last week, red this week, no code change | The `uses:` lines; chapter 39 |
| Cache key mismatch | `npm cache is not found` / `cache-hit=false` then slow install | `actions/setup-node` cache lines; chapter 16 |
| Node version drift | Syntax error or "not supported" only in CI | `node --version` in the summary; setup-node step |
| Flaky test | Fails on run 1, passes on run 2, same commit | Test output; re-run once to confirm |

### What a real GitHub failure adds (not verified locally)

- The Actions tab renders the job/step tree with red/green icons and the
  `Error: Process completed with exit code N` line (the runner's own wording;
  `act` prints `exitcode 'N': failure` instead, which is why the exact GitHub
  wording is not in any file in `docs/_logs/`).
- The Annotations pane filters `::error` lines; a secret-safety scan failure
  produces one red annotation titled `Possible secret in the repository`.
- `gh run view <id> --log-failed` prints only the failing steps (needs a remote
  and auth; `[read-only example]` here).
- Masking turns a direct secret print into `***`; derived forms still leak
  (chapter 26).

## 5. When to use it and when NOT to

**Use this ritual when:**

- **Any red build, always.** Three questions, in order, before reading anything
  else. It is faster than scrolling.
- **A failure you cannot reproduce locally.** Run it on GitHub, then
  `gh run view --log-failed` or download the log, and apply the same three
  questions.
- **A flaky failure.** Re-run once to confirm flakiness, then stop re-running
  and fix the test. Re-running a flaky test ten times teaches you nothing.
- **A failure in a job you did not touch.** The six-cause list is the starting
  point; usually it is checkout, working-directory, or an unpinned action.

**Do NOT:**

- **Do not read the log from the top.** The error is at the bottom of the red
  step. Reading from the top wastes time and hides the cause in setup noise.
- **Do not re-run blindly.** Re-running a real bug just wastes minutes and
  leaves the bug for next time. Re-run only to confirm flakiness, then fix.
- **Do not trust a green job.** Check the step conclusions; `continue-on-error`
  can hide a red step inside a green job.
- **Do not change two things at once.** One change per re-run, or you cannot
  tell which fixed it.
- **Do not skip the exit code.** `127` and `1` look similar in a summary but
  mean completely different things.

## 6. Common mistakes

- **Reading the log from the top.** The error is at the bottom of the red step.
  Start at `Error: Process completed with exit code N` and read up.
- **Blaming the tool.** `npm ci` exiting 1 says nothing; the lines above it say
  everything. And `127` is categorically different from `1`.
- **Missing checkout, then debugging npm.** `npm ci` cannot find `package.json`
  because the repo was never checked out. The fix is not an npm flag; it is
  `actions/checkout@v7` as step one.
- **`working-directory` before checkout.** Exit `127`, no bash output, hours of
  confusion. Reorder, or drop the default.
- **Re-running until green.** A flaky test re-run green is still a flaky test.
  Fix the cause or quarantine it with a tracked issue.
- **Trusting `continue-on-error`.** A red step inside a green job is still a
  failure of that step. Read the conclusion, not just the job status.
- **Changing the workflow and the code in the same commit.** You cannot tell
  which one fixed it. Separate the changes.
- **Not printing the version.** A summary without `node --version` hides drift.
  Print it.
- **Grepping for `error` and trusting hits.** `::error` can come from a green
  step (an annotation is a report, not a verdict). Match the runner's wording
  instead.
- **Treating a cache miss as a failure.** `cache-hit=false` is normal on the
  first run or after a lock change. It is slow, not broken.

## 7. Try it yourself

**Exercise: take a red build through the three questions.**

1. Run the baseline and confirm green:
   ```bash
   ./scripts/verify.sh .github/workflows/26-secret-safety.yml safety push ch26
   ```
   Confirm `clean` and the three `.gitignore` lines. That is a green run; note
   which step names appear.

2. **Make the scan fail.** Create `.github/workflows/leak-demo.txt` containing:
   ```
   api_key = "supersecretvalue1234"
   ```
   Commit it (do not push). Re-run:
   ```bash
   ./scripts/verify.sh .github/workflows/26-secret-safety.yml safety push ch26-fail
   ```
   Now apply the ritual:
   - Question 1: which step is red? (`Scan tracked files for credential shapes`)
   - Question 2: exit code? (`1`, because the script ran `exit 1`)
   - Question 3: last twenty lines? The match line plus
     `::error title=Possible secret in the repository::`.
   Delete the file and unstage it. The scan returns to `clean`.

3. **Make the `.gitignore` check fail.** Remove `dist` (or `dist/`) from
   `.gitignore` temporarily and re-run. The check prints
   `::error::.gitignore is missing dist` and exits 1. Restore `.gitignore`.

4. **Prove `continue-on-error` hides a failure.** Take a small workflow (or the
   step from chapter 05) with a step that exits 1 and `continue-on-error: true`.
   Run it. Observe: the step block is red (`❌ Failure`), the job is green
   (`🏁 Job succeeded`), and the next step runs. That is the trap from section 4.

5. **Reproduce a missing-checkout failure.** Create a temporary workflow with
   `defaults.run.working-directory: cicd-learn` and no checkout step. Run it with
   `act`. The first step exits `127` with no bash output. That is the signature
   from the six-cause table. Delete the file.

6. **Break the triage order on purpose.** Re-run the failing scan from step 2,
   but this time start reading from the top of the log. Count how many lines you
   read before reaching the error. Then re-run reading from the bottom up. The
   difference is the cost of skipping the ritual.

**Hint:** the scan is a backstop, not a guarantee. GitHub's own secret scanning
is broader and runs on every push regardless of CI. Turn it on under Settings →
Security → Code security and analysis → Secret scanning, and enable push
protection. Chapter 38 covers the full setup.

**Break it on purpose, the worst version:** change the scan's `hits=1` logic to
`hits=0` so a found secret does not fail the job. Re-run with the leak file
present: the scan prints the match but the job stays green. That is a broken
gate. Revert.

## 8. Next

You can now take a red build apart in three questions and name the six causes
that produce most of them. The next chapter is what to do once you know the
cause and the fix is a re-run rather than a code change: re-running jobs,
re-running on a different runner, and dropping into a live shell over SSH.

→ [48 — Re-running jobs](48-re-running-jobs.md)
