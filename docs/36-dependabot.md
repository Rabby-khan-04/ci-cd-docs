# 36 — Dependency updates with Dependabot

> **Verification.** This chapter has no workflow file and no local run.
> Dependabot is a GitHub-hosted service: it reads a configuration file from
> your repository, opens pull requests on your behalf, and runs on GitHub's
> infrastructure. None of that can be exercised by `act`. The configuration
> example below is valid YAML (it parses with the same parser as the workflow
> files), but it is not executed here. `python3 scripts/validate-workflows.py`
> does not process it, because it is not a workflow. **[GitHub-only feature].**
>
> **What this cannot prove locally.** You cannot trigger a Dependabot run
> locally, and you cannot see the pull requests it would open. The free
> alternative is to enable it on a public repository and wait for the first
> scheduled run, or use the "Dependency graph" → "Dependabot" tab to request
> an immediate check.

---

## 1. Simple explanation (like I'm 7)

Imagine your house has a gardener who comes by once a week, looks at every
plant, and says: "This one has a new variety that resists bugs. Shall I
plant it?" The gardener does not plant anything without asking. He leaves a
note on your fridge (a pull request), and you decide whether to say yes.

Dependabot is that gardener for your dependencies. It watches the packages
your project uses, notices when a newer version exists, and opens a pull
request with the update. It also watches for security advisories and opens a
pull request with the fix, sometimes within hours of the advisory being
published. You still review and merge; it just does the boring part of
checking what is out of date.

## 2. Real name

### Dependabot

GitHub's automated dependency-update service. It has two parts: **version
updates** (regular bumps to the latest version) and **security updates**
(bumps that fix a known vulnerability). Both are configured by a file in the
repository.

### Version updates

Scheduled pull requests that bump a dependency to its latest release,
according to the rules in `.github/dependabot.yml`. These are routine
maintenance: keeping current, reducing drift, and catching breakage early in
a small, reviewable change instead of a giant upgrade later.

### Security updates

Pull requests opened automatically when GitHub's advisory database records a
vulnerability in a dependency you use, and a fixed version exists.
Security updates are enabled per repository (or organisation) and do not
require a `dependabot.yml` entry, though the same configuration influences
how they are grouped and labelled.

### `.github/dependabot.yml`

The configuration file. It lists which ecosystems (npm, pip, docker,
github-actions, …) to check, where their manifests live, how often to check,
and how to group or label the resulting pull requests.

### Ecosystem

The package manager or manifest type Dependabot understands: `npm`, `pip`,
`docker`, `github-actions`, `terraform`, `bundler`, `cargo`, `composer`,
`gomod`, `maven`, `nuget`, and others.

### Grouping

A configuration option that combines multiple dependency updates into a
single pull request instead of one PR per dependency. Essential for keeping
the PR queue manageable.

### Cooldown / ignore

Rules that tell Dependabot to skip certain dependencies, certain version
ranges, or updates for a period of time. Used to avoid churn on noisy
packages or to hold a dependency at a known-good version.

## 3. Workflow example

There is no workflow file for this chapter. Dependabot is configured by a
file, not a workflow. Save this as `.github/dependabot.yml`:

```yaml
# Dependabot configuration. This file is read by GitHub's service; it is not
# a workflow and has no `on:` trigger of its own.
version: 2

updates:
  # ── npm dependencies ──────────────────────────────────────────────────────
  - package-ecosystem: npm
    # Where the manifest lives, relative to the repository root.
    directory: "/cicd-learn"
    # How often to check. Daily is noisy; weekly is the usual default.
    schedule:
      interval: weekly
      day: monday
      time: "09:00"
      timezone: "Europe/Berlin"
    # Keep the number of open PRs bounded.
    open-pull-requests-limit: 5
    # Group minor and patch updates into one PR per week.
    groups:
      production-dependencies:
        patterns:
          - "*"
        update-types:
          - "minor"
          - "patch"
    # Labels applied to the PRs Dependabot opens.
    labels:
      - "dependencies"
      - "npm"
    # Reviewers / assignees (optional).
    reviewers:
      - "your-github-username"
    # Commit message prefix, so the history stays tidy.
    commit-message:
      prefix: "chore(deps):"
      include: "scope"

  # ── GitHub Actions versions ───────────────────────────────────────────────
  # This is what keeps the actions in your workflows current. It also covers
  # the SHA-pinning story in chapter 39: Dependabot can open PRs that update
  # a pinned SHA to a newer release.
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    groups:
      actions:
        patterns:
          - "*"
    labels:
      - "dependencies"
      - "github-actions"

  # ── Docker base images ─────────────────────────────────────────────────────
  - package-ecosystem: docker
    directory: "/cicd-learn"
    schedule:
      interval: monthly
    labels:
      - "dependencies"
      - "docker"
```

Four structural things to notice:

1. `version: 2` is required at the top. It is the config schema version, not
   a dependency version.
2. Each entry under `updates:` is one ecosystem + directory pair. A monorepo
   with two `package.json` files needs two entries.
3. `directory` is where the manifest lives, not where the code lives. For a
   root-level `package.json` it is `/`; for this course's app it is
   `/cicd-learn`.
4. `groups` is what keeps Dependabot from opening 40 pull requests a week.
   Grouping minor and patch updates is the setting almost everyone wants.

## 4. What I should see

### Enabling it (GitHub UI)

1. Commit `.github/dependabot.yml` to the default branch.
2. Go to Settings → Code security and analysis → Dependabot.
3. Enable "Dependabot version updates" (if not already on) and "Dependabot
   security updates".
4. The first version-update run happens on the next scheduled interval, or
   immediately if you click "Check for updates" on the Dependency graph page.

### What a Dependabot pull request looks like

```
Bump vitest from 5.0.3 to 5.1.0
dependabot[bot] wants to merge 1 commit into main from dependabot/npm_and_yarn/...

Files changed:
  cicd-learn/package.json
  cicd-learn/package-lock.json

Checks:
  ✅ CI / Test with coverage
```

The PR body includes the release notes, the changelog, and a compatibility
score (when available). The PR runs your CI automatically, because it is a
pull request like any other.

### Security update PRs

These look the same but are triggered by an advisory. The title includes the
CVE or GHSA identifier, and the PR is marked as a security update. They are
opened even if version updates are disabled, as long as security updates are
enabled for the repository.

### What a real GitHub run adds (not verified locally)

- The actual PRs, their timing, and the compatibility scores.
- The "Dependency graph" page, which shows what Dependabot found and when it
  last ran.
- Security-update behaviour, which requires a real advisory to trigger.
- The interaction with branch protection: a Dependabot PR must pass your
  required checks before it can be auto-merged (if you enable auto-merge).

## 5. When to use it and when NOT to

**Use Dependabot when:**

- **You want security fixes fast.** A vulnerable dependency with a published
  fix is the most common avoidable incident. Dependabot closes that window
  from weeks to hours.
- **You want to avoid big-bang upgrades.** Small, weekly bumps are reviewable;
  a yearly "upgrade everything" is not.
- **You use GitHub Actions.** Action versions drift too, and a vulnerable or
  compromised action is worse than a vulnerable library. Chapter 39.
- **You have a lock file.** Dependabot updates both the manifest and the lock
  file, which is the part humans get wrong.

**Do NOT:**

- **Do not enable version updates with no grouping.** You will get one PR per
  dependency per week, and the team will start ignoring them. Group
  minor/patch updates.
- **Do not auto-merge without CI.** Auto-merge on a Dependabot PR is safe
  only when required checks genuinely test the change. A PR that bumps a
  transitive dependency with no test coverage is a liability.
- **Do not ignore major versions forever.** A held-back major version
  accumulates debt until the upgrade is a project. Schedule a quarterly
  review of ignored majors.
- **Do not run Dependabot on a repo with no tests.** It will open PRs that
  nobody can evaluate, and they will pile up. Fix the test story first.
- **Do not duplicate it with Renovate without a reason.** Both do the same
  job. Pick one and disable the other to avoid conflicting PRs.

## 6. Common mistakes

- **Wrong `directory`.** Symptom: Dependabot says "no manifest found" and
  opens no PRs. Fix: the directory must contain the manifest, relative to
  the repo root, with a leading slash.
- **Forgetting the lock file.** Symptom: Dependabot updates `package.json`
  but not `package-lock.json`, and CI fails on `npm ci`. Fix: Dependabot
  updates both when they are committed; make sure the lock file is tracked.
- **No grouping.** Symptom: 30 PRs a week, most ignored. Fix: add a
  `groups` block with `update-types: [minor, patch]`.
- **Grouping majors with minors.** Symptom: one PR that bumps everything,
  including a breaking major, and CI fails. Fix: group only minor and patch;
  let majors arrive as separate, reviewable PRs.
- **Ignoring a dependency and forgetting.** Symptom: a held-back package
  stays vulnerable. Fix: review the `ignore` list quarterly, and prefer
  `allow` over `ignore` where possible.
- **Enabling security updates but not version updates, then wondering why
  versions drift.** Symptom: security PRs arrive, but routine updates do
  not. Fix: enable both, or accept that you are doing manual maintenance.
- **Running Dependabot on a fork.** Symptom: it does not run, because
  Dependabot requires the repository to be the original, not a fork. Fix:
  enable it on the upstream repository.
- **Trusting the compatibility score blindly.** Symptom: a PR with a high
  score still breaks your build. Fix: the score is a heuristic; CI is the
  truth.

### Ignore, allow, and cooldown

Dependabot's defaults are noisy for some packages. The `ignore` and
`allow` blocks control which updates are proposed:

```yaml
  - package-ecosystem: npm
    directory: "/cicd-learn"
    schedule:
      interval: weekly
    # Only propose updates for these dependencies.
    allow:
      - dependency-name: "vitest"
      - dependency-type: "production"
    # Never propose updates for these.
    ignore:
      - dependency-name: "eslint"
        versions: [">=10"]
      - dependency-name: "some-noisy-package"
        update-types: ["version-update:semver-patch"]
    # Wait at least N days after a release before proposing it, to let
    # broken releases be yanked.
    cooldown:
      default-days: 7
```

- `allow` restricts the universe. Use it when you only want Dependabot to
  watch a subset (e.g. production deps, not dev deps).
- `ignore` excludes specific packages or version ranges. Use it to hold a
  dependency at a known-good version, but review the list quarterly.
- `cooldown` reduces churn by waiting for a release to settle. Seven days
  is a reasonable default for libraries; shorter for security-critical ones.

### Monorepo and multiple manifests

A repository with multiple `package.json` files needs one entry per
directory:

```yaml
updates:
  - package-ecosystem: npm
    directory: "/frontend"
    schedule:
      interval: weekly
  - package-ecosystem: npm
    directory: "/backend"
    schedule:
      interval: weekly
```

Dependabot opens separate PRs per directory. Grouping is per-entry, so
group rules do not span directories. If you want cross-directory grouping,
that is a reason to consider Renovate instead.

### Auto-merge

GitHub can auto-merge a Dependabot PR once required checks pass. Configure
it in the repository settings (Settings → General → Pull Requests → Allow
auto-merge) and add a workflow or use the UI to enable auto-merge on each
PR. A sensible policy:

- Auto-merge patch and minor updates that pass CI.
- Require human review for major updates.
- Never auto-merge updates to actions that have `permissions:` or deploy
  steps without reading the diff.

## 7. Try it yourself

**Exercise: add Dependabot and watch it open its first PR.**

1. Create `.github/dependabot.yml` using the example above, adjusted to your
   repository (directory, reviewers).
2. Commit and push to the default branch.
3. In the repository settings, enable Dependabot version and security
   updates.
4. Trigger an immediate check: Insights → Dependency graph → Dependabot →
   "Check for updates". (The button appears once the config is on the
   default branch.)
5. Wait for the first PR. Review it: does CI pass? Does the lock file
   update match the manifest?
6. **Break it on purpose.** Change `directory` to `/nonexistent` and push.
   Dependabot reports "no manifest found" and opens nothing. Fix the path
   and re-trigger.
7. **Break it the other way.** Remove the `groups` block and re-trigger.
   Dependabot now opens one PR per dependency. Observe the queue, then
   restore grouping.

**Hint:** Dependabot is free for public repositories and for private
repositories on paid plans. On a free private repository, security updates
are still available; version updates may be limited.

## 8. Next

You now have a gardener for your dependencies. The next chapter adds a
security guard that reads your own code for vulnerabilities, not just the
packages you import.

→ [37 — Security scanning: CodeQL](37-codeql.md)