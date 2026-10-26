# 34 — Branch protection and required checks

> **Verification.** This chapter has no workflow file and no local run. Branch
> protection is configured entirely in the GitHub UI (Settings → Branches →
> Branch protection rules) and cannot be exercised by `act`. There is no
> workflow to validate, so `python3 scripts/validate-workflows.py` does not
> apply. Everything about how required status checks behave is described from
> GitHub's documentation and from the behaviour of the checks produced by the
> workflow files in earlier chapters. **[GitHub-only feature].**
>
> **What this cannot prove locally.** `act` cannot create branches, open pull
> requests, or enforce merge rules. The only way to observe a required check
> blocking a merge is on github.com, with a real pull request against a
> protected branch. The free alternative is to use a public repository (branch
> protection rules are free for public repos) and a throwaway branch.

---

## 1. Simple explanation (like I'm 7)

Imagine a bridge with a toll booth. Every car that wants to cross must stop,
hand over a ticket, and get a stamp. No stamp, no crossing. The bridge does
not care who you are or how fast you drove; it cares only that the stamp is
there.

Branch protection is the toll booth for your `main` branch. A pull request is
a car trying to cross. The required status checks are the stamps: CI must have
run, and it must have passed, before the merge button lights up. Without the
stamp, the button stays grey, and no amount of "but it works on my machine"
gets you across.

The clever part is that the toll booth is not in your code. It is a setting on
the branch itself, enforced by GitHub, not by your workflow. Your workflow
produces the stamp; the branch decides whether the stamp is required.

## 2. Real name

### Branch protection rule

A rule attached to a branch (or a pattern of branches) in a repository, set
under Settings → Branches. It restricts what can happen to that branch:
who can push, whether force-pushes are allowed, whether the branch can be
deleted, and which status checks must pass before a merge.

### Required status check

A named check that must be in the "success" state before a pull request
targeting the protected branch can be merged. The name is the name GitHub
shows for the check, which is the job's `name:` (or the workflow plus job
combination), not the job id.

### Status check

The pass/fail result GitHub records for a workflow run against a commit or a
pull request. Every job in every workflow that runs on a pull request becomes
a status check with a name. "Green" means success; "red" means failure;
"neutral" or "skipped" are usually treated as not-success.

### Merge button (squash / merge / rebase)

The UI control that turns a pull request into commits on the base branch. It
is disabled while any required check is pending or failing.

### Bypass / admin override

The ability of repository administrators (or specifically listed users/teams)
to merge even when required checks have not passed. It exists for emergencies
and is audit-logged.

### Ruleset (the newer form)

GitHub's newer "Rulesets" feature, which applies branch protection rules at
the organisation or repository level with targeting by branch name pattern,
tag, or path. The older "Branch protection rules" still work and are what
most tutorials describe. Both enforce the same idea.

### The settings you will actually toggle

A branch protection rule has many checkboxes. These are the ones that matter
for a CI gate, and what each one does:

| Setting | What it does | Typical value |
| ------- | ------------ | ------------- |
| Require a pull request before merging | No direct pushes to `main`; changes must come via a PR | On |
| Require approvals | A PR needs N approving reviews before merge | 1 (or 2 for production) |
| Dismiss stale pull request approvals when new commits are pushed | A new commit invalidates old approvals | On |
| Require review from Code Owners | Files matching `CODEOWNERS` need the owner's approval | On if you have owners |
| Require status checks to pass before merging | The core of this chapter: named checks must be green | On |
| Require branches to be up to date before merging | The PR head must include the latest `main` | On for correctness, off for throughput |
| Require conversation resolution before merging | Unresolved review comments block merge | On |
| Require signed commits | Every commit must be GPG/SSH signed | On in regulated environments |
| Require linear history | No merge commits; squash or rebase only | Optional |
| Include administrators | Admins are subject to the rules too | On (strongly recommended) |
| Allow force pushes | Lets someone overwrite history | Off |
| Allow deletions | Lets someone delete the branch | Off |

Two details that bite people:

- **"Include administrators" is off by default.** With it off, an admin can
  push directly to `main` and bypass every check. Turn it on unless you have
  a documented reason not to.
- **"Require branches to be up to date"** sounds like a good idea and is,
  but on a busy repository it serialises merges: every PR must rebase on the
  latest `main` before the button enables. That can create a queue where
  merging one PR invalidates the "up to date" state of five others. Enable
  it for correctness-critical repos, disable it when throughput matters.

### Rulesets vs. branch protection rules

GitHub now offers two ways to do this:

- **Branch protection rules** (the classic UI, Settings → Branches). One rule
  per branch pattern. Simple, well-documented, and what 90% of repositories
  use.
- **Rulesets** (Settings → Rules → Rulesets). Newer, can target multiple
  branches, tags, or repositories at once, and can be enforced at
  organisation level. Rulesets also support "bypass lists" per rule and a
  dry-run mode.

Both enforce the same underlying idea, and a repository can use either or
both. If you are starting fresh, prefer rulesets: they are the direction
GitHub is investing in, and the organisation-level enforcement is worth it
once you have more than a handful of repositories. If you already have
branch protection rules working, there is no urgent reason to migrate.

## 3. Workflow example

There is no workflow file for this chapter, because branch protection is not a
workflow. It is a setting. But it depends on workflows existing, so here is
the smallest workflow that can act as a required check. Save it as
`.github/workflows/ci-gate.yml` if you want a gate of your own:

```yaml
# A minimal gate workflow. Its job name becomes the status check name.
name: CI gate

"on":
  pull_request:
    branches: [main]
  push:
    branches: [main]

# Least privilege: this workflow only reads code.
permissions:
  contents: read

jobs:
  # The job `name:` is what you will select in the branch protection UI.
  # Pick a stable name and never rename it without updating the rule.
  test:
    name: tests must pass
    runs-on: ubuntu-24.04
    timeout-minutes: 10
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
      - run: npm test
```

Three things to notice:

1. The job is named `tests must pass`. That string, not the id `test`, is what
   appears in the branch protection dropdown.
2. The workflow runs on `pull_request` against `main`. A required check that
   only runs on `push` will never produce a result for a pull request, and
   will block merges forever (section 6).
3. The `name:` of the job is the contract. Renaming it breaks the rule
   silently: GitHub keeps waiting for a check name that no longer exists.

## 4. What I should see

### Configuring it (GitHub UI)

1. Open the repository on github.com.
2. Settings → Branches → "Add branch protection rule" (or "Add ruleset").
3. Branch name pattern: `main`.
4. Enable "Require a pull request before merging".
5. Enable "Require status checks to pass before merging".
6. In the search box, type part of the check name, e.g. `tests must pass`.
   The check must have run at least once before it appears in the list. Select
   it.
7. Optionally enable "Require branches to be up to date before merging".
8. Save.

### What a pull request looks like

Before CI finishes:

```
Some checks haven't completed yet
  ⏳ tests must pass — In progress
Merging is blocked.
```

After CI passes:

```
All checks have passed
  ✅ tests must pass
Merge pull request   (button enabled)
```

After CI fails:

```
Some checks were not successful
  ❌ tests must pass — Failed
Merging is blocked.
```

### The trap: a required check that never runs

This is the single most common branch-protection surprise, and it is worth
understanding before you turn anything on.

If you require a check named `tests must pass`, but no workflow ever produces
a check with that exact name on the pull request, then:

- The pull request shows "Expected — Waiting for status to be reported".
- The merge button stays disabled.
- Nothing fails, nothing passes, nothing times out. The PR is stuck.

The cause is almost always one of:

- The workflow runs only on `push`, not on `pull_request`, so it never fires
  for a PR.
- The job was renamed after the rule was created, so the old name is still
  required.
- The workflow has a path filter or branch filter that excludes this PR.
- The check name in the rule has a typo.

The fix is not to wait. Remove the stale required check from the rule, or
rename the job back, or add `pull_request` to the workflow's triggers.

### What a real GitHub run adds (not verified locally)

- The exact wording of the "Expected" state and the merge button's disabled
  styling.
- The list of selectable checks, which only populates after a check has run
  at least once on the repository.
- Admin bypass behaviour and the audit log entries it creates.
- Rulesets targeting multiple branches or repositories at once.

## 5. When to use it and when NOT to

**Use branch protection when:**

- **You have a CI pipeline that means something.** A required check is only
  worth requiring if it actually catches real problems. Turn it on once
  chapters 11-15's pipeline is green and trustworthy.
- **You work with other people.** The merge button is the last line of defence
  against a teammate pushing broken code to `main`. It is the cheapest
  coordination tool available.
- **You want to enforce review.** "Require a pull request before merging"
  plus "Require approvals" makes code review a hard gate, not a suggestion.
- **You publish from `main`.** If `main` is what ships, `main` must be
  protected. Anything else is a deploy of unreviewed code.

**Do NOT:**

- **Do not require a check before it has ever run.** It will block every PR
  until you remove it. Run the workflow once on a throwaway branch first, then
  add it to the required list.
- **Do not require checks that are slow or flaky.** A 20-minute or
  occasionally-red required check trains people to bypass the rule or to
  merge with admin override. Fix the check first.
- **Do not protect `main` with rules nobody can satisfy.** If your required
  checks need secrets that fork PRs do not have, every external contribution
  is blocked. Design PR checks to run without secrets (chapter 26).
- **Do not rely on branch protection as your only safety net.** It gates
  merges; it does not stop a direct push from an admin, a compromised
  credential, or a force-push by someone with bypass rights. Combine it with
  least-privilege tokens and secret scanning.
- **Do not enable "Require branches to be up to date" on a busy repo without
  thinking.** It forces every PR to rebase on the latest `main` before
  merging, which serialises merges and can create a queue. Worth it for
  correctness, costly for throughput.

## 6. Common mistakes

- **Requiring a check that never runs.** Symptom: every PR shows "Expected —
  Waiting for status to be reported" and the merge button is grey forever.
  Fix: check the trigger (`pull_request`, not just `push`), the branch
  filter, and the exact check name. Run the workflow once on a PR to
  populate the list.
- **Renaming a job after creating the rule.** Symptom: the old check name is
  still required and never reports. Fix: either rename the job back or update
  the branch protection rule to the new name.
- **Requiring a check from a workflow that needs secrets on fork PRs.**
  Symptom: external PRs are stuck on a check that cannot run. Fix: split
  fork-safe checks (lint, test, build) from secret-needing checks (deploy,
  publish) and require only the former.
- **Protecting the wrong branch.** Symptom: PRs to `main` are unguarded while
  `develop` is protected. Fix: name the branch you actually merge into, and
  consider a pattern like `main` plus `release/*`.
- **Forgetting that admins can bypass.** Symptom: a protected branch still
  receives a bad commit, and the audit log shows an admin override. Fix:
  restrict bypass to a small group, or disable it entirely with "Do not
  allow bypassing the above settings".
- **Assuming a skipped check counts as passing.** A job with `if: false` or
  a skipped matrix leg reports "skipped", which is not "success". Symptom:
  a required check that is skipped blocks the merge. Fix: either do not
  require skippable checks, or make the job report success when intentionally
  skipped.
- **Editing the rule and breaking everyone's open PRs.** Symptom: PRs that
  were mergeable suddenly are not. Fix: change required checks deliberately
  and tell the team; prefer adding new checks over renaming old ones.

### Required checks and matrix jobs

Matrix jobs (chapter 17) produce one status check per combination. If your
workflow tests Node 20 and 22, the checks are named `tests (20)` and
`tests (22)` (or whatever the matrix expands to). When you require them,
you must require **both**, or require a single aggregate job that depends on
the matrix. Requiring only one leaves the other unguarded.

The clean pattern is an aggregator job:

```yaml
jobs:
  test:
    strategy:
      matrix:
        node: [20, 22]
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - run: npm test

  # This is the check you require. It runs only after the matrix passes.
  all-tests:
    name: all tests pass
    runs-on: ubuntu-24.04
    needs: [test]
    steps:
      - run: echo "matrix passed"
```

Require `all tests pass`, not the individual matrix legs. That keeps the
branch protection rule stable even when you add or remove a Node version.

### Required checks and reusable workflows

A reusable workflow (chapter 40) produces checks named after the calling
job, not the callee. If workflow A calls reusable workflow B's job `test`,
the status check is named after A's job. Renaming the caller breaks the
rule, even though the reusable workflow is unchanged. Keep caller job names
stable, or add an aggregator.

## 7. Try it yourself

**Exercise: turn CI into a gate, and then watch it block you.**

1. Make sure you have a workflow that runs on `pull_request` against `main`
   (the minimal gate above, or any chapter's workflow with that trigger).
2. Push it to `main` once so the check name appears in GitHub's list.
3. Open Settings → Branches → add a rule for `main`, requiring that check.
4. Create a branch, make a small change, open a pull request.
5. Confirm the merge button is disabled while the check runs, and enabled
   once it passes.
6. **Break it on purpose.** Rename the job in the workflow (change its
   `name:`) and push. Open (or re-open) a pull request. The PR now shows
   "Expected — Waiting for status to be reported" for the old name, and
   merging is blocked forever. That is the rename trap. Fix it by updating
   the branch protection rule to the new name (or reverting the rename).
7. **Break it the other way.** Remove `pull_request` from the workflow's
   triggers, leaving only `push`. Open a new PR. The check never fires, and
   the PR is stuck on "Expected". Add `pull_request` back to fix it.

**Hint:** branch protection is the one chapter in this course you cannot
reproduce with `act`. Use a real public repository and a throwaway branch;
everything is free and nothing is deployed.

## 8. Next

You now know how to make CI a hard gate. The next chapter measures something
most teams *think* they are testing but are not: how much of the code the
tests actually touch.

→ [35 — Code coverage](35-code-coverage.md)