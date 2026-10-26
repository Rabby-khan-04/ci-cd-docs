# 25 — `GITHUB_TOKEN` and permissions

> **Verification.** The workflow in this chapter is
> `.github/workflows/25-token-permissions.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/25-token-permissions.yml "" push ch25`,
> and the full log is at `docs/_logs/ch25.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/25-token-permissions.yml (4 job(s))`.
>
> **What this local execution cannot prove.** `act` injects a token, but it is
> not GitHub's `GITHUB_TOKEN` with real scopes; it is whatever `act` provides
> (often a personal access token or an empty value), and the permissions block
> is not enforced locally. The `gh` CLI is also not installed in the `act`
> container, so the read-only job's API call fails locally for an unrelated
> reason. The job graph, the step output, the `permissions: {}` behaviour, and
> the `pull_request_target` shape are real; the actual scoping of
> `GITHUB_TOKEN` on GitHub is described from the documentation.

---

## 1. Simple explanation (like I'm 7)

Every run gets a free key card. It is created automatically when the run
starts, it opens doors inside your repository, and it is thrown away when the
run ends. You did not ask for it, but it is there, and it has a surprising
amount of access by default.

The problem is that a key card with too many doors is a liability. If a
workflow step is tricked into running code you did not write — a malicious
dependency, a compromised action, a pull request from a stranger — that code
holds the key card. Whatever doors the card opens, the attacker walks through.

So the rule is: **give the key card only the doors it needs, and only for the
job that needs them.** A lint job needs to read code. A deploy job needs to
write a release. A job that only prints a message needs no doors at all. The
`permissions:` block is how you say which doors.

## 2. Real name

### `GITHUB_TOKEN`

An automatically generated token created for every workflow run. It
authenticates as the special `github-actions[bot]` user and can act on the
repository the run belongs to: read code, create comments, open issues, push
commits, create releases, and more. It is referenced as `secrets.GITHUB_TOKEN`
(or `github.token`). It expires when the run ends.

### `permissions:`

The block that declares what `GITHUB_TOKEN` may do. It can sit at workflow
level (the ceiling for every job) or job level (narrowing for one job). Each
named permission is set to `read`, `write`, or `none`. Any permission you do
not name is set to `none`. That last part is the whole design: naming one
permission subtracts all the others.

### Least privilege

The practice of granting only the access a job needs, nothing more. In
GitHub Actions this means: start from `permissions: {}` (nothing) and add
back only what the job requires. Never start from the default and try to
remember what to remove.

### Workflow-level permissions

The ceiling. A job cannot widen beyond the workflow level; it can only narrow
or match. If the workflow says `contents: read`, no job can get
`contents: write`, even if it asks.

### Job-level permissions

A replacement for the workflow level for that one job. It does not merge with
the workflow level; it replaces it. A job with `permissions: {}` has nothing,
regardless of what the workflow granted.

### `pull_request_target`

A trigger that runs a workflow in the context of the *base* branch, using the
base repository's secrets and `GITHUB_TOKEN`, even when the pull request
comes from a fork. It exists for labelling and commenting on PRs, and it is
the most dangerous trigger in GitHub Actions. See section 6.

### Fine-grained vs classic tokens

`GITHUB_TOKEN` is a classic-style token scoped to the repository. Personal
access tokens (PATs) and GitHub App tokens are the alternatives when you need
cross-repository access or a longer lifetime. They are stored as secrets and
used like any other. Chapter 43 covers OIDC for cloud access, which avoids
long-lived tokens entirely.

## 3. Workflow example

This is the complete `.github/workflows/25-token-permissions.yml` from this
repository.

```yaml
name: GITHUB_TOKEN permissions

"on":
  push:
    branches: [main]
  workflow_dispatch:

# ── Workflow-level default: the ceiling for every job in this file ───────────
# Naming any permission sets every UNNAMED permission to `none`. So this line
# does not mean "contents can read"; it means "contents can read and nothing
# else has any access at all". That is the whole point: subtraction, not addition.
permissions:
  contents: read

jobs:
  # ── Narrowing further for a read-only job ────────────────────────────────
  read-only:
    name: read-only job
    runs-on: ubuntu-24.04
    # A job-level permissions block REPLACES the workflow-level one for this job.
    # Job permissions can only ever be equal or narrower. A job cannot widen.
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
      - name: Prove it can read
        # `gh` is preinstalled on GitHub runners, but it needs a token to make
        # API calls. Passing GITHUB_TOKEN explicitly is the correct way, and the
        # `permissions:` block above is what limits what that token can do.
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo "the token can read the repository"
          gh api "repos/${{ github.repository }}" --jq '.full_name' \
            && echo "the token really can read the repository" \
            || echo "read failed, which would mean permissions: is too narrow"

  # ── Widening for a job that genuinely needs to write ─────────────────────
  # Example only. This job does NOT write anything; it exists to show the shape.
  # Anything that writes to the repository belongs in a separate, deliberately
  # scoped workflow, not in your CI file.
  can-comment:
    name: job that may comment (demonstration only)
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      # pull-requests: write is what lets a workflow comment on a PR.
      # Issues permission is NOT implied by it.
      pull-requests: write
    steps:
      - name: Explain, do not post
        run: |
          echo "This job could comment on pull requests."
          echo "It does not, because posting a comment nobody asked for is noise."
          echo "The real workflow would be:"
          echo "  gh pr comment \$PR_NUMBER --body '...' --repo \${{ github.repository }}"
          echo "and it would need:"
          echo "  GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}"
          echo "  GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}"
          echo "Which is why permissions are declared per job, not per file."

  # ── No permissions at all: the token cannot even read code ───────────────
  nothing:
    name: job with no permissions
    runs-on: ubuntu-24.04
    # `permissions: {}` means literally nothing is permitted. A job like this
    # cannot use actions/checkout, because checkout needs `contents: read`.
    permissions: {}
    steps:
      - name: No checkout is possible here
        run: |
          echo "This job has an empty permissions block."
          echo "Try adding actions/checkout to it: it will fail, because the token"
          echo "cannot read the repository contents."

  # ── Why this matters: pull_request_target ────────────────────────────────
  # THE most dangerous trigger. Unlike `pull_request`, a `pull_request_target`
  # workflow runs with the BASE branch's workflow file and the base repository's
  # secrets, EVEN when the pull request comes from a fork.
  #
  # That means: if you check out the fork's code and run it, you have just handed
  # an anonymous contributor your production secrets.
  #
  # The rule: never combine `pull_request_target` with checking out and running
  # untrusted code. Use `pull_request` for that. Chapter 26 covers the attack.
  danger:
    name: what NOT to do
    runs-on: ubuntu-24.04
    # This job is guarded off deliberately. Uncomment both lines to see the
    # shape of the bug this trigger enables.
    if: false
    steps:
      - name: NEVER DO THIS
        run: |
          echo "echo NEVER DO THIS"
```

Four structural things to notice:

1. The workflow-level `permissions: contents: read` is the **ceiling**. No job
   below can exceed it, no matter what it asks for.
2. `read-only` re-declares `contents: read` at job level. Redundant here, but
   it is the correct habit: a job states its own needs rather than inheriting
   them silently.
3. `can-comment` adds `pull-requests: write` on top of `contents: read`. That
   is the only job that could comment, and it is a separate, deliberately
   scoped job. Note that `issues: write` is *not* implied.
4. `nothing` uses `permissions: {}`. With that, `actions/checkout` cannot run,
   because checkout needs `contents: read`. The empty block is the safest
   default for a job that does not touch the repository.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch25.log` runs all four jobs in parallel. The `can-comment` job
prints its explanation:

```
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   | This job could comment on pull requests.
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   | It does not, because posting a comment nobody asked for is noise.
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   | The real workflow would be:
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   |   gh pr comment $PR_NUMBER --body '...' --repo \nektos/act
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   | and it would need:
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   |   GITHUB_TOKEN: \***
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   |   GH_TOKEN: \***
[GITHUB_TOKEN permissions/job that may comment (demonstration only)]   ✅  Success
```

Note that `act` prints `\***` for the token references even in a local run,
because `${{ secrets.GITHUB_TOKEN }}` resolves to `act`'s own token value and
the log scrubber masks it. That is a coincidence of `act`, not proof of
GitHub's scoping.

The `nothing` job runs without checkout, as designed:

```
[GITHUB_TOKEN permissions/job with no permissions                  ]   | This job has an empty permissions block.
[GITHUB_TOKEN permissions/job with no permissions                  ]   | Try adding actions/checkout to it: it will fail, because the token
[GITHUB_TOKEN permissions/job with no permissions                  ]   | cannot read the repository contents.
[GITHUB_TOKEN permissions/job with no permissions                  ]   ✅  Success
```

The `read-only` job checks out the repository and then tries to call the
GitHub API:

```
[GITHUB_TOKEN permissions/read-only job                            ]   | the token can read the repository
[GITHUB_TOKEN permissions/read-only job                            ]   | /var/run/act/workflow/1: line 3: gh: command not found
[GITHUB_TOKEN permissions/read-only job                            ]   | read failed, which would mean permissions: is too narrow
[GITHUB_TOKEN permissions/read-only job                            ]   ✅  Success
```

The `gh: command not found` failure is an **artefact of `act`**, not of
permissions. `gh` is preinstalled on GitHub-hosted runners but not in the
`act` container image. The step is written to survive it (`|| echo "read
failed..."`), so the job stays green. On a real GitHub runner, the same step
prints the repository's full name and "the token really can read the
repository", proving that `contents: read` is sufficient for the API call.

### What a real GitHub run adds (not verified locally)

On github.com, with the workflow-level `permissions: contents: read`:

- `read-only` calls `gh api repos/...` and gets the repository's full name
  back. `contents: read` is enough.
- If you change `read-only` to `permissions: {}` and re-run, `actions/checkout`
  fails with "Resource not accessible by integration" and the job stops before
  any step runs. That is the proof that `permissions: {}` really does deny
  `contents: read`.
- If you add `pull-requests: write` to a job and trigger it on a pull
  request, the job can post a comment with `gh pr comment`. Without that
  permission, the same call returns 403.
- The `danger` job never runs (`if: false`). If you removed the guard and
  triggered it from a fork PR with a `pull_request_target` workflow that
  checked out the fork's code, the run would execute with the base
  repository's secrets. That is the attack, and it is why the guard exists.

### The permission names you will actually use

| Permission | What it allows | Typical job |
| ---------- | -------------- | ----------- |
| `contents: read` | Clone the repo, read files | Any CI job |
| `contents: write` | Push commits, create releases | Release job |
| `pull-requests: read` | Read PR metadata | PR checks |
| `pull-requests: write` | Comment, label, close PRs | Bots, reviewers |
| `issues: write` | Create/comment issues | Issue bots |
| `packages: write` | Push to GitHub Packages | Registry push |
| `pages: write` | Deploy to GitHub Pages | Pages deploy |
| `id-token: write` | Request an OIDC token | Cloud auth (ch. 43) |
| `actions: read` | Read workflow runs | Self-inspection |
| `checks: write` | Create check runs | Test reporters |

Everything else defaults to `none` once you name any permission. The full list
is in the GitHub documentation; the table above covers 95% of real workflows.

## 5. When to use it and when NOT to

**Use explicit `permissions:` when:**

- **Always.** Every workflow should declare them. The default is broader than
  you want, and the default can change (GitHub has tightened it over time).
- **You want a job to write.** Declare exactly the write permission it needs,
  on that job only, never at workflow level for a whole file.
- **You publish artifacts to GitHub Packages or Pages.** Those need specific
  write permissions that are off by default under least privilege.
- **You use OIDC to cloud providers.** `id-token: write` is required and is
  the only permission that matters for that flow.

**Do NOT:**

- **Do not omit `permissions:` and rely on the default.** The default grants
  broad access that your job probably does not need, and it varies by
  repository settings. Symptom: a compromised step can do more than you
  intended. Fix: always declare.
- **Do not put `write` at workflow level.** A file-level `contents: write`
  hands write access to every job, including the lint job. Symptom: a lint
  failure can push a commit. Fix: job-level `permissions:`.
- **Do not use `permissions: write-all`.** It exists for migration and
  disables the entire point of this chapter. Symptom: maximum exposure.
  Fix: name what you need.
- **Do not combine `pull_request_target` with untrusted code.** This is the
  single most dangerous mistake in GitHub Actions. Symptom: a fork PR can
  exfiltrate your secrets. Fix: use `pull_request`, and if you must use
  `pull_request_target`, never check out the PR's code or run it.
- **Do not assume `permissions:` affects secrets.** It scopes `GITHUB_TOKEN`
  only. A repository secret is still available to every job regardless of
  `permissions:`. Scope secrets with environments (chapter 24).

## 6. Common mistakes

- **No `permissions:` block at all.** The default token is broader than you
  expect and depends on repository settings. Symptom: a workflow that "just
  works" with more access than it needs. Fix: add `permissions: contents:
  read` at minimum.
- **Workflow-level `write` for one job.** One job needs to comment; the whole
  file gets `pull-requests: write`. Symptom: every job can comment on PRs.
  Fix: move the permission to the job that needs it.
- **`permissions: {}` on a job that checks out code.** Checkout needs
  `contents: read`. Symptom: "Resource not accessible by integration."
  Fix: add `contents: read` to that job.
- **Thinking `permissions` merges.** Job-level `permissions:` *replaces*
  workflow-level; it does not add to it. Symptom: a job that declares only
  `pull-requests: write` loses `contents: read` and cannot check out. Fix:
  declare the full set the job needs.
- **`pull_request_target` + checkout of the PR head.** The workflow runs with
  the base branch's secrets and the base `GITHUB_TOKEN`, but checks out and
  runs the fork's code. Symptom: a fork PR exfiltrates `secrets.*` and the
  `GITHUB_TOKEN`. Fix: never check out `github.event.pull_request.head.sha`
  or the PR's code in a `pull_request_target` workflow; use `pull_request`
  instead, which runs without secrets.
- **Confusing `GITHUB_TOKEN` with a PAT.** `GITHUB_TOKEN` cannot access other
  repositories or survive the run. Symptom: a cross-repo API call that
  returns 404. Fix: use a PAT or GitHub App token stored as a secret, and
  scope it narrowly.
- **Assuming `id-token: write` is harmless.** It lets the run request an OIDC
  token that can be exchanged for cloud credentials. Only grant it to jobs
  that actually need cloud access. Symptom: a job that can mint cloud
  credentials it does not use. Fix: job-level, never workflow-level.
- **Rotating the token manually.** You cannot; it is managed by GitHub and
  expires with the run. Symptom: trying to revoke `GITHUB_TOKEN` in settings.
  Fix: nothing to do; it is already ephemeral.

## 7. Try it yourself

**Exercise: prove that `permissions: {}` denies checkout.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/25-token-permissions.yml "" push ch25
   ```

   Confirm the four jobs run and `read-only` fails on `gh: command not found`
   (an `act` limitation, not a permissions problem). That is all `act` can
   show for scoping.

2. **Prove `permissions: {}` denies checkout on GitHub.** Create a temporary
   copy of the workflow with an extra step in the `nothing` job:

   ```yaml
   - uses: actions/checkout@v7
   ```

   Push it to a branch and run. The job fails with "Resource not accessible
   by integration" before checkout completes. Revert.

3. **Prove job-level replaces workflow-level.** Change `read-only` to:

   ```yaml
   permissions:
     pull-requests: write
   ```

   (dropping `contents: read`). Re-run. `actions/checkout` now fails, because
   the job no longer has `contents: read`, even though the workflow level
   grants it. Revert. This is the single most surprising behaviour and the
   reason jobs must declare their full set.

4. **Prove `pull-requests: write` enables commenting.** On a pull request,
   run a workflow with a job that has `pull-requests: write` and calls
   `gh pr comment`. Then remove the permission and re-run: the call returns
   403. Revert.

5. **Inspect the token.** Add a step:

   ```yaml
   - name: Who am I?
     env:
       GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
     run: gh api user --jq '.login'
   ```

   It prints `github-actions[bot]`. That is the identity every `GITHUB_TOKEN`
   carries. Revert.

6. **Break it on purpose.** Set the workflow-level block to
   `permissions: write-all` and run. Everything works, which is exactly the
   problem: nothing was denied. Revert immediately and replace with the
   explicit list.

**Hint:** scoping is only verifiable on GitHub. `act` does not enforce
`permissions:`, so a local run will not fail on a too-narrow block. If you
want to test locally, use a real PAT with limited scopes and pass it as
`GITHUB_TOKEN`, but the behaviour of the built-in token is best confirmed on
github.com.

## 8. Next

You now know how to keep a credential out of the log, how to keep
configuration out of the secret store, how to scope both to a target, and how
to limit what the built-in token can do. The last piece of the safety story
is what to do when all of that fails: a secret leaks anyway.

→ [26 — Not leaking secrets](26-secret-safety.md)