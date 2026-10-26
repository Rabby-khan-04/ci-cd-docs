# 26 — Not leaking secrets

> **Verification.** The workflow in this chapter is
> `.github/workflows/26-secret-safety.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/26-secret-safety.yml safety push ch26`,
> and the full log is at `docs/_logs/ch26.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/26-secret-safety.yml (1 job(s))`.
>
> **What this local execution cannot prove.** `act` does not implement
> masking, so the "transformations leak" step prints the fake token in clear
> text locally — which is precisely the point of the demonstration. On GitHub,
> the direct print would be `***` and the derived forms would still leak, so
> the lesson holds in both environments. Fork behaviour, environment protection
> and secret scanning are GitHub-only and are described from the
> documentation.

---

## 1. Simple explanation (like I'm 7)

Imagine you write your diary password on a sticky note and leave it on the
fridge. Then you take a photo of the fridge for a recipe blog. The photo is
the log. The password is in the photo. That is a leak, and it happened
because the password was somewhere it could be photographed.

Now imagine a smarter version: you do not write the password down, but you
write "my password reversed." Reversing is easy, so anyone who reads the blog
can undo it. Still a leak. Base64-encoding it is the same trick with a bigger
disguise; it is still trivially reversible.

The point of this chapter is that **secrets leak in five boring, predictable
ways**, and every one of them is preventable with a habit. None of them
requires a clever attacker. They require only a developer who did not think
about what the log captures.

## 2. Real name

### Log injection

Writing untrusted input into a log in a way that lets it masquerade as a
workflow command. If a step echoes a PR title containing
`::set-output name=x::y`, older runners would execute it. The fix is to avoid
echoing untrusted values and to use the modern `$GITHUB_OUTPUT` mechanism.

### Masking (revisited)

GitHub's literal string replacement in the log stream. It scrubs the exact
secret value and nothing derived from it. Chapter 22.

### Fork PR secrets

Pull requests from forked repositories run with **no secrets** and a
read-only `GITHUB_TOKEN`. This is a protection, not a limitation. It means a
stranger's PR cannot read your credentials.

### `pull_request_target` (revisited)

The trigger that runs with the base branch's secrets and token even for fork
PRs. Combining it with checking out the PR's code is the canonical secret
exfiltration attack. Chapter 25.

### Secret scanning

GitHub's feature that scans repositories and pull requests for known
credential patterns (GitHub tokens, AWS keys, private keys, and partner
patterns). It runs on push and on PRs. Push protection blocks the push before
it lands. Chapter 38.

### `set -x` (xtrace)

A bash option that prints every command *after expansion*. If a command
contains a secret, the expanded form — secret included — is written to the
log. This defeats masking entirely.

### Debug logging

GitHub Actions can be switched to debug mode by setting the repository secret
`ACTIONS_STEP_DEBUG` to `true`. In debug mode, every step prints its inputs
and environment, which includes secrets passed via `env:`. This is the
single most common way a "careful" workflow leaks.

## 3. Workflow example

This is the complete `.github/workflows/26-secret-safety.yml` from this
repository.

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
          # git grep over tracked files only: what is in git is what is public.
          # These are patterns, not exact values, so they do not need a secret.
          set +e
          hits=0

          # Private keys
          git grep -nE 'BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY' -- . \
            && hits=1 || echo "no private keys in tracked files"

          # GitHub tokens: ghp_, gho_, ghu_, ghs_, ghr_, github_pat_
          git grep -nE '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' -- . \
            && hits=1 || echo "no GitHub tokens in tracked files"

          # npm tokens
          git grep -nE '_authToken\s*=' -- . \
            && hits=1 || echo "no npm auth tokens in tracked files"

          # AWS access key ids
          git grep -nE '\b(AKIA|ASIA)[0-9A-Z]{16}\b' -- . \
            && hits=1 || echo "no AWS access key ids in tracked files"

          # Anything that looks like an assignment to a secret-looking name
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
          # Accept an optional trailing slash: gitignore writes `node_modules/`
          # and `dist/`, and a naive exact match reports those as missing.
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
          # A FAKE secret. Never a real one. This value is public by design.
          FAKE_TOKEN: 'demo-token-abcdef123456'
        run: |
          echo "This token is NOT a secret. It is a hardcoded string."
          echo
          echo "Direct print        : $FAKE_TOKEN        <- GitHub would mask this"
          echo "Length              : ${#FAKE_TOKEN} chars <- NOT masked"
          echo "Reversed            : $(printf %s "$FAKE_TOKEN" | rev) <- NOT masked"
          echo "Base64              : $(printf %s "$FAKE_TOKEN" | base64) <- NOT masked"
          echo "As JSON             : {\"t\":\"$FAKE_TOKEN\"} <- NOT masked"
          echo "URL-encoded         : $(printf %s "$FAKE_TOKEN" | sed 's/-/%2D/g') <- NOT masked"
          echo
          echo "GitHub's masking is a literal string replacement in the log stream."
          echo "Anything derived from the secret does not match, so it is printed."

      # ── 4. set -x is a secret leak with extra steps ───────────────────────
      - name: Why set -x is dangerous in a secret-handling step
        run: |
          # Uncomment to see the problem. Never do this in a step that touches a
          # credential.
          #
          #   set -x
          #   curl -H "Authorization: Bearer $TOKEN" https://example.com
          #
          # `set -x` prints every expanded command, so the header, and therefore
          # the secret, is written to the log in cleartext.
          echo "set -x echoes every expanded command, credentials included."
          echo "Never enable it in a step that reads a secret."

      # ── 5. Fork safety ────────────────────────────────────────────────────
      # Secrets are NOT passed to workflows triggered by a pull request from a
      # forked repository. That is a protection, not a bug. It means:
      #   - your PR checks cannot use production secrets, by design
      #   - a fork PR cannot read your secrets, by design
      # Chapter 25 explains the pull_request_target trap that bypasses this.
      - name: Fork safety is a feature
        run: |
          echo "PRs from forks run with no secrets and a read-only token."
          echo "That is why you never deploy from an untrusted pull request."
```

Five structural things to notice:

1. The scan runs `git grep` over **tracked files only**. What is in git is
   what is public; untracked files are not the repository's problem yet, but
   once committed they are.
2. The patterns are **shapes, not values**. They detect a GitHub token prefix
   or an AWS key id, never a specific secret, so the scan needs no secret of
   its own.
3. The `.gitignore` check accepts a trailing slash. A naive exact match
   reports `node_modules/` and `dist/` as missing, which is the bug the
   workflow was written to avoid.
4. The leak demonstration uses a **fake** token that is public by design. A
   real secret must never be used to demonstrate a leak, even in a private
   repository, because the log is the point.
5. The `set -x` and fork-safety steps are **explanations, not executions**.
   They print the rule; they do not run the dangerous command.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch26.log` runs the `safety` job end to end. The scan finds
nothing:

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

The `.gitignore` check passes, including the trailing-slash case:

```
[Secret safety/Secret safety checks] ⭐ Run Main Check .gitignore
[Secret safety/Secret safety checks]   | ok: .gitignore contains .env
[Secret safety/Secret safety checks]   | ok: .gitignore contains node_modules
[Secret safety/Secret safety checks]   | ok: .gitignore contains dist
[Secret safety/Secret safety checks]   ✅  Success - Main Check .gitignore [73.001612ms]
```

The transformation step shows exactly what leaks:

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

On GitHub, the "Direct print" line would show `***` instead of the value,
and every other line would look exactly as above. That is the whole lesson in
one block: the mask catches one form and misses all the others.

The `set -x` step and the fork-safety step print their rules:

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

### What a real GitHub run adds (not verified locally)

- **Secret scanning.** If you push a file containing a real GitHub token or
  an AWS access key id, GitHub blocks the push (push protection) or opens a
  security alert within seconds. The scan in this workflow is a local, manual
  backstop; GitHub's scanner is broader and runs on every push.
- **Push protection.** With push protection enabled, a push containing a
  detected secret is rejected before it lands. The developer must either
  remove the secret or bypass with a documented reason. Bypasses are logged.
- **Debug logging.** With `ACTIONS_STEP_DEBUG: true`, every step prints its
  inputs, including `env:` values that hold secrets. The workflow's
  "transformations leak" step would print `FAKE_TOKEN`'s value in the debug
  block even though the step itself never echoes it. This is the reason the
  rule "never enable step debug on a run that handles secrets" exists.
- **Fork PR behaviour.** A workflow triggered by `pull_request` from a fork
  runs with `secrets.*` empty and `GITHUB_TOKEN` read-only. The "Fork safety
  is a feature" step is the only thing that can be verified locally; the
  actual fork behaviour needs a real fork.

## 5. When to use it and when NOT to

**Use these practices when:**

- **Every repository, from day one.** The scan and the `.gitignore` check cost
  one job and a few seconds. They are the cheapest insurance in CI.
- **You handle any secret in any workflow.** The transformation rule and the
  `set -x` rule apply everywhere, not just in "security" workflows.
- **You accept pull requests from forks.** The fork-safety rule is not
  optional if strangers can run your workflows.
- **You publish a repository.** A public repo is scanned by GitHub and by
  third parties. Assume anything committed is public forever.

**Do NOT:**

- **Do not print a secret to "verify it is set."** Print `set: yes/no` only.
  Symptom: a partial or transformed value in the log. Fix: `${TOKEN:+yes}${TOKEN:-no}`.
- **Do not use a real secret in a demonstration.** Even in a private repo,
  the log is the point of a leak demo. Symptom: a secret in a log you
  cannot delete. Fix: use a fake, public-by-design value.
- **Do not enable step debug on secret-handling runs.** `ACTIONS_STEP_DEBUG`
  dumps `env:` and inputs. Symptom: a secret in a debug block. Fix: keep
  debug off; reproduce locally instead.
- **Do not use `set -x` in a step that reads a secret.** It expands and
  prints the command. Symptom: the secret in clear text. Fix: trace only
  steps that do not touch credentials, or use `set +x` around the sensitive
  line.
- **Do not echo PR titles, commit messages or branch names unfiltered.** They
  are attacker-controlled and can inject workflow commands or exfiltrate data
  via log lines. Symptom: a PR titled `::set-output...` executing. Fix:
  never echo untrusted input; use `$GITHUB_OUTPUT` with values you control.
- **Do not assume masking covers derived forms.** It does not, ever.
  Symptom: a base64 value in the log. Fix: do not transform a secret in a
  logged step.

## 6. Common mistakes

- **Committing a secret "temporarily."** Git history is forever. Symptom: a
  credential in `git log` even after deletion. Fix: rotate the credential
  immediately, then rewrite history (chapter 38). Deletion alone is not
  enough.
- **A `.env` file committed by mistake.** Symptom: `git ls-files` shows
  `.env`. Fix: `git rm --cached .env`, add it to `.gitignore`, rotate the
  secret, rewrite history if it was pushed.
- **The `.gitignore` trailing-slash trap.** A check that does
  `grep -qx '.env' .gitignore` passes, but one that does
  `grep -qx 'node_modules' .gitignore` fails because the file contains
  `node_modules/`. Symptom: a false "missing pattern" failure. Fix: accept
  both forms, as the workflow does.
- **Using `echo` to "test" a secret.** `echo "token=$TOKEN"` prints
  `token=***`, which *looks* safe, so the developer moves on. But any
  transformation leaks. Symptom: a false sense of security. Fix: never echo
  a secret, even masked.
- **Logging a secret inside JSON or a URL.** `curl "https://api.example.com/?key=$TOKEN"`
  puts the token in the command line, which `set -x` and process listings
  expose. Symptom: the token in a process list. Fix: pass it as a header or
  environment variable, never in a URL you log.
- **Assuming fork PRs can use secrets if you "allow" them.** You cannot.
  GitHub does not pass secrets to fork PR workflows, period. Symptom: a PR
  check that works on a branch and fails on a fork. Fix: design PR checks
  without secrets, or gate the secret-using step behind a label or approval.
- **`pull_request_target` running the PR's code.** The single most dangerous
  mistake. Symptom: a fork PR exfiltrates your secrets. Fix: use
  `pull_request`; if you must use `pull_request_target`, never check out or
  run the PR's code.
- **Believing secret scanning is enough.** It catches known patterns, not
  your internal tokens or passwords. Symptom: a leaked internal token that
  scanning missed. Fix: keep the custom scan in CI and never commit
  credentials in the first place.

## 7. Try it yourself

**Exercise: make the scan fail, then fix it.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/26-secret-safety.yml safety push ch26
   ```

   Confirm `clean` and the three `.gitignore` lines. That is the baseline.

2. **Make the scan fail.** Create a temporary file
   `.github/workflows/leak-demo.txt` containing:

   ```
   api_key = "supersecretvalue1234"
   ```

   Commit it (do not push). Re-run the workflow. The scan now prints the
   match and exits 1 with `::error title=Possible secret in the repository::`.
   Delete the file and unstage it. The scan returns to `clean`.

3. **Make the `.gitignore` check fail.** Remove `dist` (or `dist/`) from
   `.gitignore` temporarily and re-run. The check prints
   `::error::.gitignore is missing dist` and exits 1. Restore `.gitignore`.

4. **Prove the transformation leak.** The step already does this. Read the
   output: direct print is `demo-token-abcdef123456` (masked to `***` on
   GitHub), and the reversed, base64, JSON and URL-encoded lines are all
   visible. Then change `FAKE_TOKEN` to a value you control and re-run to
   watch your own value leak in four forms. Revert.

5. **Prove `set -x` leaks.** Uncomment the `set -x` block in the workflow:

   ```yaml
   set -x
   TOKEN='demo-token-abcdef123456'
   curl -H "Authorization: Bearer $TOKEN" https://example.com || true
   set +x
   ```

   Re-run. The log now contains
   `+ curl -H 'Authorization: Bearer demo-token-abcdef123456' ...` in clear
   text, masking or no masking. Revert the edit immediately.

6. **Enable debug logging (on GitHub only).** Add the repository secret
   `ACTIONS_STEP_DEBUG` with value `true`. Re-run the workflow. The debug
   blocks now print step inputs and environment, including `FAKE_TOKEN`. Read
   them, then delete the secret. Never leave debug logging on.

7. **Break it on purpose.** Change the scan's `hits=1` logic to `hits=0`
   so a found secret does not fail the job. Re-run with the leak file from
   step 2 present: the scan prints the match but the job stays green. That
   is a broken gate. Revert.

**Hint:** the scan is a backstop, not a guarantee. GitHub's own secret
scanning is broader and runs on every push regardless of CI. Turn it on under
Settings → Security → Code security and analysis → Secret scanning, and enable
push protection. Chapter 38 covers the full setup.

## 8. Next

You now know how to store secrets, configure non-secret values, scope both to
a target, limit what the built-in token can do, and avoid the five ways
secrets leak. The safety story is complete. The next part is what all of this
was for: putting code somewhere users can reach.

→ [27 — Deployment fundamentals](27-deployment-fundamentals.md)