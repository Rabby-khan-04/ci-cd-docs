# 23 — Variables

> **Verification.** The variable behaviour in this chapter comes from the
> variables part of `.github/workflows/22-secrets.yml`, executed with
> `./scripts/verify.sh .github/workflows/22-secrets.yml secrets push ch22`.
> The full log is at `docs/_logs/ch22.log`, and the relevant excerpt is quoted
> in section 4. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/22-secrets.yml (1 job(s))`.
>
> **What this local execution cannot prove.** Variables are a GitHub feature
> with a UI store, just like secrets. `act` does not read the GitHub variables
> store, so `vars.APP_ENV` is empty in the local run and prints as
> `<not set>`. That is exactly the behaviour you see when a variable has not
> been configured, so the local run is a faithful demonstration of the unset
> case. The set case, where `vars.APP_ENV` resolves to a configured value, is
> described from the GitHub documentation and verified by configuring a variable
> in the UI.

---

## 1. Simple explanation (like I'm 7)

A secret is a diary in a locked locker. A **variable** is a sticky note on the
fridge.

The sticky note is not sensitive. Anyone in the house can read it. It says
things like "we are cooking for 4 people tonight" or "the oven runs hot, set
it 10 degrees lower." It changes often, it is not a password, and nobody
would get in trouble if a guest saw it.

In a pipeline, variables hold the same kind of information: the name of the
environment you are deploying to, the URL of an API you call, a feature flag
that turns a step on or off, a region name. They are **configuration**, not
credentials. They are stored in plain text, they are visible in the log without
any masking, and they are meant to be read by humans.

The reason both exist is that you do not want to mix the two. A password
disguised as configuration is a leak waiting to happen; configuration disguised
as a secret cannot be read back when you need to debug.

## 2. Real name

### Variable (GitHub Actions variable)

A named, plain-text value stored in GitHub and exposed to workflows through the
`vars` context. Set in the UI under Settings → Secrets and variables →
Actions → **Variables** tab. Read with `${{ vars.NAME }}`.

### `vars` context

The object that holds variables for the current run. Available in the same
places as `secrets`: step-level `env:`, action `with:`, and expressions. Like
`secrets`, it is **not** available in workflow-level `env:`.

### Repository variable

A variable scoped to one repository. Available to every workflow in it. The
default and the one this chapter uses.

### Organization variable

A variable scoped to an organization, optionally restricted to selected
repositories. Same scoping rules as organization secrets, one tier up.

### Environment variable (GitHub Actions environment)

A variable scoped to a named environment (`staging`, `production`), handed only
to jobs that declare that environment. Chapter 24. Do not confuse this with a
shell environment variable (`$FOO` inside a `run:` block) — GitHub calls both
"environment variables" and the name collision is genuinely confusing.

### Shell environment variable

A variable that exists inside a `run:` step's bash process, set with `env:`
on the step or with `export`. This is an ordinary OS variable. It has nothing
to do with the GitHub `vars` context, except that you often bridge one into the
other:

```yaml
env:
  APP_ENV: ${{ vars.APP_ENV }}   # GitHub variable -> shell variable
run: echo "$APP_ENV"             # now it is a shell variable
```

### Configuration vs secret

The decision rule: if the value would be a security incident if it appeared
in a public log, it is a secret. If it would merely be embarrassing or
confusing, it is a variable. URLs, region names, environment names, flags,
timeouts and thresholds are variables. Tokens, passwords, keys and webhook
secrets are secrets.

## 3. Workflow example

The variables portion of `.github/workflows/22-secrets.yml`, shown here as a
complete, runnable workflow so you can read it on its own. The secret parts
are omitted; chapter 22 covers those.

```yaml
name: Variables

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
  variables:
    name: Variables
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
      # Read with `vars.NAME`. If it is unset, `vars.APP_ENV` is empty.
      - name: Variables are visible in logs
        env:
          APP_ENV: ${{ vars.APP_ENV }}
        run: |
          # Safe to print. A variable is not a credential.
          echo "APP_ENV    : ${APP_ENV:-<not set>}"
          echo "vars are for config: environment names, URLs, feature flags"

      # ── Using a variable to drive behaviour ───────────────────────────────
      # A feature flag stored as a variable, toggled in the UI without a
      # commit. This is the most common reason to reach for vars.
      - name: Feature flag from a variable
        env:
          FEATURE_NEW_REPORT: ${{ vars.FEATURE_NEW_REPORT }}
        run: |
          if [ "${FEATURE_NEW_REPORT}" = "true" ]; then
            echo "new report enabled"
          else
            echo "new report disabled (default)"
          fi

      # ── Variable with a default ──────────────────────────────────────────
      # `vars` resolves to empty when unset, so a default belongs in the shell,
      # not in the variable store. Keep the default in the workflow so a missing
      # variable degrades gracefully instead of silently doing nothing.
      - name: Variable with a fallback
        env:
          API_BASE_URL: ${{ vars.API_BASE_URL }}
        run: |
          : "${API_BASE_URL:=https://api.example.com}"
          echo "calling $API_BASE_URL"
```

Three structural things to notice:

1. `vars.APP_ENV` is resolved in the step's `env:` line, the same slot where
   `secrets` go. The two contexts are siblings and behave identically in
   terms of where they may appear.
2. An unset variable is an empty string. There is no error, no "not found"
   message from GitHub. That is why the `${APP_ENV:-<not set>}` fallback and
   the `:=` default exist: they make the unset case visible and safe.
3. A variable can hold the literal string `true`. It is not a boolean in YAML;
   it is whatever you typed in the UI. Compare with `true` in a workflow
   file, which is a YAML boolean. This trips people up when a variable drives
   an `if:`.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch22.log`, the "Variables are visible in logs" step:

```
[Secrets and variables/Secrets and variables] ⭐ Run Main Variables are visible in logs
[Secrets and variables/Secrets and variables]   | APP_ENV    : <not set>
[Secrets and variables/Secrets and variables]   | vars are for config: environment names, URLs, feature flags
[Secrets and variables/Secrets and variables]   ✅  Success - Main Variables are visible in logs [71.914022ms]
```

`APP_ENV` prints as `<not set>` because this repository has no `APP_ENV`
variable configured, and `act` does not read the GitHub variables store. That
is the same output you get on GitHub when the variable has not been created:
an empty value, rendered by the shell's `${VAR:-<not set>}` fallback.

### What a real GitHub run adds (not verified locally)

With `APP_ENV` set to `production` in the UI, the same step prints:

```
APP_ENV    : production
vars are for config: environment names, URLs, feature flags
```

No masking, no `***`, no redaction. The value is in the log in clear text,
because it is not a secret. That is the intended behaviour and the reason you
must not put a credential in a variable: it would be logged verbatim.

### Adding a variable in the UI

1. Repository on github.com → Settings → Secrets and variables → Actions.
2. **Variables** tab (next to Secrets) → "New repository variable".
3. Name: `APP_ENV`. Value: `production`. Add variable.
4. Re-run the workflow. The step now prints `APP_ENV    : production`.

Unlike a secret, you can read the value back in the UI and edit it in place.
That readability is the feature, and it is why variables are the right place
for configuration.

### Variables in expressions

Variables work in `${{ }}` everywhere a secret does:

```yaml
- name: Deploy to the configured environment
  run: |
    echo "deploying to ${{ vars.APP_ENV }}"
```

And they can drive job-level decisions:

```yaml
jobs:
  deploy:
    if: vars.APP_ENV == 'production'
```

Note the comparison: `vars.APP_ENV` is a string. Write `'production'` with
quotes so YAML does not misread it, and write the comparison against a
quoted string so the types line up.

## 5. When to use it and when NOT to

**Use variables when:**

- **The value is configuration.** Environment name, API base URL, region, a
  timeout, a threshold, a retry count.
- **The value changes between environments but is not sensitive.** `vars` can
  be scoped per environment (chapter 24), so `staging` and `production` get
  different values from the same name.
- **You want a value editable without a commit.** Toggling a feature flag in
  the UI takes effect on the next run, with no pull request.
- **You want the value visible in logs.** Variables are meant to be read;
  printing them is fine and often useful for debugging.
- **The value is needed in a fork PR.** Variables are available to fork PRs
  (unlike secrets), so PR checks can use configuration safely.

**Do NOT use variables when:**

- **The value is a credential.** A token in a variable is printed in clear
  text in every log. That is a leak. Use a secret (chapter 22).
- **The value is different per matrix cell.** Put it in the matrix `include`
  block (chapter 17); variables are global to a scope.
- **The value is computed during the run.** Use a job output or
  `$GITHUB_OUTPUT` (chapter 18). Variables are static configuration, not
  runtime state.
- **You need the value to be hidden.** Variables are readable by anyone with
  read access to the repository. If that is too broad, it is a secret.

### Variables vs secrets at a glance

| Question | Variable | Secret |
| -------- | -------- | ------ |
| Sensitive? | No | Yes |
| Stored as | Plain text | Encrypted |
| Readable in UI? | Yes | No (only name shown) |
| Masked in logs? | No | Yes (exact string only) |
| Available to fork PRs? | Yes | No |
| Typical contents | URLs, flags, env names | Tokens, passwords, keys |
| Context | `vars.NAME` | `secrets.NAME` |

## 6. Common mistakes

- **Treating a variable as a secret.** `echo "$API_KEY"` of a variable that
  holds a key prints it in clear text. Symptom: a credential in a public log.
  Fix: if it is a credential, make it a secret, period.
- **Treating a secret as a variable.** Moving a token to `vars` so it can be
  "read back" destroys the masking. Symptom: the token in every run's log.
  Fix: keep it in `secrets`; you do not need to read a secret back to use it.
- **Assuming an unset variable errors.** It does not; it is empty. Symptom: a
  step that silently does nothing or calls an empty URL. Fix: provide a
  default with `${VAR:-default}` or `${VAR:=default}` and fail loudly if the
  default is unsafe.
- **Comparing a variable to a boolean.** `if: vars.FLAG == true` is almost
  always wrong, because `vars.FLAG` is the string `"true"` and `true` in YAML
  is a boolean. Symptom: a condition that never matches. Fix: compare to the
  string `'true'`.
- **Workflow-level `env:` referencing `vars`.** Same trap as secrets: the
  `vars` context is not available at workflow level. Symptom: empty value.
  Fix: step-level `env:`.
- **Hardcoding a value that should be a variable.** A URL buried in a `run:`
  block cannot be changed without a commit and a review. Symptom: editing
  workflows to change configuration. Fix: move it to `vars` and reference it.
- **Hardcoding a value that should be a secret.** The reverse mistake, and
  the worse one. Symptom: a credential in git history. Fix: rotate, then
  rewrite history (chapter 38).
- **Expecting variables to be masked.** They are not. Anything you print stays.
  Symptom: surprise that a "private" value is visible. Fix: if it must be
  hidden, it is a secret, not a variable.

## 7. Try it yourself

**Exercise: configure a variable and watch it flow through a run.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/22-secrets.yml secrets push ch22
   ```

   Confirm `APP_ENV : <not set>`. That is the unset case.

2. **Create a variable on GitHub.** Settings → Secrets and variables → Actions
   → Variables → New repository variable. Name `APP_ENV`, value `staging`.
   Re-run the workflow on GitHub. The step now prints `APP_ENV : staging`.

3. **Use it to drive a step.** Add a step:

   ```yaml
   - name: Branch on the variable
     env:
       APP_ENV: ${{ vars.APP_ENV }}
     run: |
       case "$APP_ENV" in
         production) echo "deploying to prod" ;;
         staging)    echo "deploying to staging" ;;
         *)          echo "unknown environment: $APP_ENV"; exit 1 ;;
       esac
   ```

   Re-run. Change the variable to `production` in the UI and re-run. No commit,
   no pull request, different behaviour. Revert the edit afterwards.

4. **Prove variables reach fork PRs.** Open a pull request from a fork (or
   ask a collaborator to). The variable is available; a secret would not be.
   That is the design, and it is why configuration belongs in `vars`.

5. **Break it on purpose.** Set `APP_ENV` to a value containing a space, e.g.
   `staging eu`, without quoting in the `env:` line. Re-run and read the
   error. The fix is to quote: `APP_ENV: ${{ vars.APP_ENV }}` is already
   quoted by the `${{ }}` expression, but the shell still word-splits on the
   value, so the `run:` block must quote `"$APP_ENV"`. Fix and re-run.

6. **Clean up.** Delete the `APP_ENV` variable you created, so the repository
   is back to its original state.

**Hint:** to inject a variable locally with `act`, pass it as an environment
variable prefixed for act's variable store:

```bash
./scripts/run-workflow.sh .github/workflows/22-secrets.yml secrets push \
  --var APP_ENV=staging
```

Whether your version of `act` supports `--var` depends on the release; if it
does not, export `APP_ENV` and edit the workflow to read it directly for the
experiment, then revert. The masking behaviour (none, for variables) is the
same locally and on GitHub, unlike secrets.

## 8. Next

Variables cover configuration that is the same shape everywhere. The next
problem is configuration and secrets that differ by *target*: staging and
production should not share a database password, and a deploy to production
should need a human's approval.

→ [24 — Environments and their secrets](24-environment-secrets.md)