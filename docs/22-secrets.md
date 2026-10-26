# 22 — Secrets

> **Verification.** The workflow in this chapter is
> `.github/workflows/22-secrets.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/22-secrets.yml secrets push ch22`,
> and the full log is at `docs/_logs/ch22.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/22-secrets.yml (1 job(s))`.
>
> **What this local execution cannot prove.** `act` has no secrets store. It
> passes a secret only if you export it on the command line, so the run in
> `docs/_logs/ch22.log` ran with `DEMO_TOKEN` and `NPM_TOKEN` *unset*, and the
> "masked demo" branch was skipped. What the log does prove is the mechanics:
> a variable that is unset prints as `<not set>`, a secret that is unset makes
> the step exit cleanly, and `vars`/`secrets` are resolved at step time, not
> workflow time. The masking of a real secret, the value `***` in the log, and
> the fact that GitHub replaces the literal string everywhere it appears are
> properties of GitHub's runner and are described here from the documentation,
> not from a local run. No real secret was used at any point in producing this
> chapter.

---

## 1. Simple explanation (like I'm 7)

Imagine a school locker. You have a diary you do not want anyone to read. You
put it in a locker with a combination lock. The locker is not on your desk; it
is in the school office, behind a counter. Only the teacher can open it, and
only when you ask.

A **secret** in GitHub Actions is that diary. It is a value you do not want in
your code, in your logs, or in your repository. You store it once, in the
GitHub UI, behind your account. When a workflow runs, GitHub hands the value to
the runner for the duration of that run, and only to jobs that are allowed to
ask for it. The runner is told to **scrub the value out of the log** if it ever
appears, so even if a step accidentally prints it, the log shows `***`
instead.

The catch, and the whole reason this chapter exists: the scrubbing is a
**text search-and-replace on the log**, not encryption. It replaces the exact
string. Anything you do to the secret — reversing it, base64-encoding it,
putting it inside JSON, measuring its length — no longer matches, so it is
printed in clear text. That is how secrets actually leak, and it is the mistake
this chapter is built to prevent.

## 2. Real name

### Secret

A named, encrypted value stored in GitHub and made available to workflows
through the `secrets` context. It is set in the UI, never in code, and never
committed. Examples: API tokens, passwords, private keys, deploy credentials.

### `secrets` context

The object that holds secrets for the current run. You read one with
`${{ secrets.NAME }}`. It is available in `env:` on a step and in `with:` on an
action, but **not in workflow-level `env:`** — a common trap, see common
mistakes. `secrets.GITHUB_TOKEN` is always present; every other secret is one
you added.

### Repository secret

A secret scoped to one repository. Every workflow in that repository can read
it. This is the default scope and the one this chapter uses. Set at
Settings → Secrets and variables → Actions → Secrets tab.

### Organization secret

A secret scoped to an organization, optionally restricted to selected
repositories. Useful when many repos share one credential. Chapter 34's
branch-protection and organization settings touch this; the mechanics are the
same.

### Environment secret

A secret scoped to a named environment (`staging`, `production`) and only
handed to jobs that declare that environment. Chapter 24.

### Masking

GitHub's log scrubber. When a step runs, the runner records the values of all
secrets it was given and replaces every occurrence of each value in the log
stream with `***`. Masking is automatic, per-value, and literal. It is not
encryption, not hashing, and not a filter on what may be printed — it is a
string replacement applied after the fact.

### The `secrets` context is not an environment variable

This distinction matters. A secret is not an environment variable you set
yourself with `env:` at the top of the workflow. It is injected by GitHub at
run time, it is encrypted at rest, it is redacted in logs, and it is never
visible in the workflow file. Treating `secrets.X` and `env.X` as the same
thing is the first mistake most people make.

## 3. Workflow example

This is the complete `.github/workflows/22-secrets.yml` from this repository.

```yaml
name: Secrets and variables

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
  secrets:
    name: Secrets and variables
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci

      # ── A variable: not secret, plain text, for config ────────────────────
      # Set with: Settings -> Secrets and variables -> Actions -> Variables tab.
      # Read with `vars.NAME`. Chapter 23.
      - name: Variables are visible in logs
        env:
          APP_ENV: ${{ vars.APP_ENV }}
        run: |
          # Safe to print. A variable is not a credential.
          echo "APP_ENV    : ${APP_ENV:-<not set>}"
          echo "vars are for config: environment names, URLs, feature flags"

      # ── A secret: encrypted, masked ───────────────────────────────────────
      # Set with: Settings -> Secrets and variables -> Actions -> Secrets tab.
      # NEVER write a real secret into a workflow file. This repository has no
      # real secrets and this job does not require any: the point is to show the
      # mechanics with a placeholder.
      #
      # In the GitHub UI, add a repository secret named DEMO_TOKEN. Locally, run:
      #   ./scripts/run-workflow.sh .github/workflows/22-secrets.yml secrets push
      # with DEMO_TOKEN exported, or pass it with act's -s flag.
      - name: Secrets are masked in the log
        env:
          # Referenced through `secrets`, never through `env` at workflow level:
          # the `secrets` context is not available in workflow-level `env`.
          DEMO_TOKEN: ${{ secrets.DEMO_TOKEN }}
        run: |
          if [ -z "${DEMO_TOKEN:-}" ]; then
            echo "DEMO_TOKEN is not set; skipping the masked demo."
            echo "Add it in Settings -> Secrets and variables -> Actions -> Secrets."
            exit 0
          fi

          # Printing it directly is masked by GitHub:
          echo "direct print : $DEMO_TOKEN"
          # GitHub replaces the value with *** in the log.
          #
          # But masking is a TEXT substitution on the log, not encryption. These
          # derived forms are NOT masked, and this is the most common way people
          # leak a secret:
          echo "length        : ${#DEMO_TOKEN}"                     # length leaks
          echo "reversed      : $(printf %s "$DEMO_TOKEN" | rev)"    # leaks
          echo "base64        : $(printf %s "$DEMO_TOKEN" | base64)" # leaks
          echo "json          : $(printf '{"t":"%s"}' "$DEMO_TOKEN")" # leaks
          #
          # Chapter 26 covers this in full. The rule: never transform a secret in
          # a log. Pass it to the tool, let the tool use it.

      # ── Using a secret where it belongs: as an action input ───────────────
      - name: The right way to pass a secret to a tool
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
        run: |
          # A real workflow does this, and the token never reaches the log:
          #   echo "//registry.npmjs.org/:_authToken=${NPM_TOKEN}" > .npmrc
          #   npm publish
          #   rm .npmrc
          #
          # The credential is written to a file, used, then deleted. Never
          # echoed. Also: never `set -x` in a step that touches a secret.
          echo "if NPM_TOKEN were set, this step would authenticate without printing it."
          echo "set: ${NPM_TOKEN:+yes}${NPM_TOKEN:-no}"

      # ── Not available at all, and that is the point ───────────────────────
      - name: What a secret is NOT
        run: |
          echo "secrets are not environment variables you set yourself"
          echo "secrets are not in the repository"
          echo "secrets are not readable by a forked pull request"
          echo "secrets are not printed in plaintext by the Actions UI"
          echo "secrets ARE available to any job in any workflow in this repo"
          echo "  -> which is why you scope jobs, not secrets (chapter 25)"
```

Four things to notice in the shape:

1. `DEMO_TOKEN` is declared in a **step-level** `env:`, not a workflow-level
   one. The `secrets` context is not available at workflow level, so
   `env: { DEMO_TOKEN: ${{ secrets.DEMO_TOKEN } }` at the top of the file
   would fail to resolve.
2. The step checks for an empty value and exits 0. That is what makes the
   workflow runnable on a repository that has not configured the secret yet.
3. `NPM_TOKEN` is read but never printed; the step only reports whether it is
   set. That is the correct shape for a credential you do not own in this repo.
4. The final step states the scoping problem up front: a repository secret is
   available to *every* job in *every* workflow. Scoping is done with
   `permissions:` and job structure, not with the secret store. Chapter 25.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch22.log` is a run of the `secrets` job with both secrets unset.
The variable step:

```
[Secrets and variables/Secrets and variables] ⭐ Run Main Variables are visible in logs
[Secrets and variables/Secrets and variables]   | APP_ENV    : <not set>
[Secrets and variables/Secrets and variables]   | vars are for config: environment names, URLs, feature flags
[Secrets and variables/Secrets and variables]   ✅  Success - Main Variables are visible in logs [71.914022ms]
```

The secret step, with `DEMO_TOKEN` unset, takes the documented skip path:

```
[Secrets and variables/Secrets and variables] ⭐ Run Main Secrets are masked in the log
[Secrets and variables/Secrets and variables]   | DEMO_TOKEN is not set; skipping the masked demo.
[Secrets and variables/Secrets and variables]   | Add it in Settings -> Secrets and variables -> Actions -> Secrets.
[Secrets and variables/Secrets and variables]   ✅  Success - Main Secrets are masked in the log [76.42135ms]
```

The "right way" step shows `NPM_TOKEN` is not configured in this repository:

```
[Secrets and variables/Secrets and variables] ⭐ Run Main The right way to pass a secret to a tool
[Secrets and variables/Secrets and variables]   | if NPM_TOKEN were set, this step would authenticate without printing it.
[Secrets and variables/Secrets and variables]   | set: no
[Secrets and variables/Secrets and variables]   ✅  Success - Main The right way to pass a secret to a tool [73.293284ms]
```

And the summary step:

```
[Secrets and variables/Secrets and variables] ⭐ Run Main What a secret is NOT
[Secrets and variables/Secrets and variables]   | secrets are not environment variables you set yourself
[Secrets and variables/Secrets and variables]   | secrets are not in the repository
[Secrets and variables/Secrets and variables]   | secrets are not readable by a forked pull request
[Secrets and variables/Secrets and variables]   | secrets are not printed in plaintext by the Actions UI
[Secrets and variables/Secrets and variables]   | secrets ARE available to any job in any workflow in this repo
[Secrets and variables/Secrets and variables]   |   -> which is why you scope jobs, not secrets (chapter 25)
[Secrets and variables/Secrets and variables]   ✅  Success - Main What a secret is NOT [75.617685ms]
```

### What a real GitHub run adds (not verified locally)

With `DEMO_TOKEN` set to a real value in the UI, the secret step would instead
print:

```
direct print : ***
length        : 23 chars
reversed      : ...the reversed value, in clear text...
base64        : ...the base64 value, in clear text...
json          : {"t":"...the value, in clear text..."}
```

The direct print is replaced by `***` because the runner recorded the value and
scrubbed the exact string. The derived forms are **not** scrubbed, because none
of them equals the recorded value. That asymmetry — one line masked, the next
four leaking — is the single most important thing to take away from this
chapter, and it is the reason chapter 26 exists.

### Adding a secret in the UI

1. Open the repository on github.com.
2. Settings → Secrets and variables → Actions.
3. Secrets tab → "New repository secret".
4. Name: `DEMO_TOKEN`. Value: any placeholder you control (never a real one for
   this exercise). Add secret.
5. Re-run the workflow. The skip branch is no longer taken, and you see the
   masking behaviour above.

The name is case-sensitive and is referenced exactly as `secrets.DEMO_TOKEN`.
A typo does not error; it resolves to an empty string, which is why the
`[ -z ]` guard exists.

### Reading a secret in a workflow

```yaml
- name: Use a secret
  env:
    TOKEN: ${{ secrets.DEMO_TOKEN }}
  run: |
    # TOKEN is in the environment of this step only.
    # Pass it to a tool, never echo it.
    some-tool --token "$TOKEN"
```

Rules:

- Reference through `secrets.NAME`, never hardcode.
- Put the reference in a **step-level** `env:` (or an action's `with:`), not
  workflow-level `env:`.
- Never `echo` it, never put it in a URL you log, never transform it.
- A missing secret is an empty string, not an error. Guard with `[ -z ]`.

## 5. When to use it and when NOT to

**Use secrets when:**

- **The value is a credential.** Tokens, passwords, private keys, webhook URLs
  with embedded tokens, anything that grants access.
- **The value must not be in the repository.** If committing it would be a
  security incident, it is a secret.
- **The value is shared across workflows.** One store, many consumers, rotated
  in one place.
- **You need masking in logs.** Secrets are the only values GitHub scrubs
  automatically.

**Do NOT use secrets when:**

- **The value is configuration.** An environment name, a URL, a feature flag, a
  timeout. That is a *variable* (chapter 23), not a secret. Secrets are
  encrypted and cannot be read back in the UI; variables are plain text and
  editable. Using a secret for a URL means you cannot see what URL you are
  deploying to.
- **The value is different per branch but not sensitive.** Use `vars` or a
  matrix; secrets do not vary by branch.
- **You need the value in a fork PR.** Fork PRs do not receive secrets by
  design (chapter 26). If your PR checks need a value, it is either a variable
  or your design is wrong.
- **You are tempted to "hide" a non-secret by making it a secret.** That only
  makes debugging harder. Secrets cannot be printed even when you want to.

## 6. Common mistakes

- **Workflow-level `env:` referencing `secrets`.** `env: { X: ${{ secrets.X } }`
  at the top of the file does not resolve; the `secrets` context is only
  available inside a job or step. Symptom: the variable is empty and nothing
  complains. Fix: move it to step-level `env:`.
- **Echoing a secret "just to check it is set."** `echo "token=$TOKEN"` prints
  `token=***`, which looks fine, but any transformation (length, substring,
  base64) leaks. Symptom: a partial value in the log. Fix: print only
  `set: yes/no` with `${TOKEN:+yes}${TOKEN:-no}`.
- **Assuming masking is encryption.** It is a string replace. Derived forms
  leak. Symptom: a reversed or base64 value visible in the log. Fix: never
  transform a secret in a step that logs.
- **A typo in the secret name.** `secrets.DEMO_TOKN` resolves to empty, no
  error. Symptom: a step that silently does nothing. Fix: guard with
  `[ -z ]` and fail loudly, or name secrets consistently.
- **Storing a secret in the repository.** Even in a private repo, even
  "temporarily", even base64-encoded. Symptom: a commit that has to be
  rewritten. Fix: rotate the credential, then rewrite history. Chapter 38.
- **Using `set -x` in a secret-handling step.** It echoes every expanded
  command, credentials included. Symptom: the secret in clear text. Fix:
  never enable tracing in such a step.
- **Believing a secret is scoped to a job.** Repository secrets are available to
  every job. Symptom: a low-privilege job can read a production credential.
  Fix: use environment secrets (chapter 24) and `permissions:` (chapter 25).
- **Forgetting that secrets are not passed to fork PRs.** Symptom: a PR check
  that works on a branch and fails on a fork. Fix: design PR checks to run
  without secrets, or use `pull_request_target` very carefully (chapter 26).

## 7. Try it yourself

**Exercise: prove that masking is a text replacement, not encryption.**

1. Run the workflow locally without a secret:

   ```bash
   ./scripts/verify.sh .github/workflows/22-secrets.yml secrets push ch22
   ```

   Confirm `APP_ENV : <not set>` and the skip message. That is all `act` can
   show without a secret.

2. **Add a secret on GitHub.** Settings → Secrets and variables → Actions →
   Secrets → New repository secret. Name `DEMO_TOKEN`, value
   `demo-token-abcdef123456` (a throwaway). Re-run the workflow on GitHub.

3. **Read the log.** The secret step now runs the transformation block. The
   direct print shows `***`; the length, reversed, base64 and JSON lines show
   the value in clear text. That is the lesson, and it is the reason chapter 26
   exists.

4. **Fix it.** Edit the step so it only prints
   `echo "set: ${DEMO_TOKEN:+yes}${DEMO_TOKEN:-no}"` and re-run. The log
   now contains no transformation of the value at all. Revert the edit.

5. **Break it on purpose.** Add `set -x` to the secret step and re-run. The log
   now contains the expanded `echo "direct print : demo-token-abcdef123456"`
   line in clear text, masking or no masking. Remove `set -x`.

6. **Rotate.** Delete the `DEMO_TOKEN` secret you created. A secret you
   created for an exercise is a secret you must delete afterwards.

**Hint:** to run locally *with* a secret, export it and pass it to `act`:

```bash
DEMO_TOKEN='demo-token-abcdef123456' \
  ./scripts/run-workflow.sh .github/workflows/22-secrets.yml secrets push
```

`act` will inject it as `secrets.DEMO_TOKEN`. The masking behaviour itself
will not reproduce, because `act` does not scrub logs — only GitHub does. So
the local run shows you the transformations; the GitHub run shows you the
masking. Both are needed to see the full picture.

## 8. Next

You can store a secret and you know how it leaks. The next question is what to
do with values that are *not* secrets — configuration that changes between
environments but is not sensitive.

→ [23 — Variables](23-variables.md)