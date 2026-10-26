# 39 — Pinning actions

> **Verification.** This chapter has no workflow file and no local run.
> Pinning is a property of how a workflow references an action, not something
> that executes. `python3 scripts/validate-workflows.py` already enforces
> that every `uses:` in this repository's workflows is pinned to a version
> or a SHA, and reports `0 error(s)` across the workflow files. The SHA table
> in section 3 is copied verbatim from `docs/00-roadmap.md`, which is the
> source of truth for the versions this course was written against. The attack
> described in section 6 is a documented, real-world incident (the
> `tj-actions/changed-files` compromise), not a hypothetical.
>
> **What this cannot prove locally.** You cannot observe a supply-chain
> attack locally, and you cannot prove that a SHA is immutable without
> network access. The free alternative is to inspect an action's releases on
> GitHub and confirm that the SHA you pin resolves to the tag you expect.

---

## 1. Simple explanation (like I'm 7)

Imagine you ask a friend to "bring the usual cake" every week. For a while,
the usual cake is the one you like. Then one week your friend brings a
different cake — same box, same ribbon, but the inside is wrong. You trusted
the word "usual," and the word stopped meaning what you thought.

A version tag like `@v4` is the word "usual." It points at a release today,
but the person who owns the action can move the tag to point at different
code tomorrow. A commit SHA is the cake itself: a specific, unchangeable
recipe. Once you pin to a SHA, the only way the code changes is if you
change the pin. The tag can move; the SHA cannot.

## 2. Real name

### Action reference

The string after `uses:` in a workflow: `owner/repo@ref`. The `ref` can be
a branch, a tag, or a commit SHA.

### Tag (moving ref)

A human-readable name like `v4` or `v4.1.2` that points at a commit. Tags
can be moved or deleted by anyone with write access to the repository. A
tag is a promise, not a guarantee.

### Commit SHA (immutable ref)

The 40-character (or short) hash of a specific commit. A commit's contents
cannot change without changing its hash. Pinning to a SHA means "this exact
code, no matter what happens to the tags."

### Supply-chain attack

An attack that compromises a dependency (here, an action) so that every
consumer runs the attacker's code. Because actions run with your
`GITHUB_TOKEN` and your secrets, a compromised action is a compromised
repository.

### Tag mutation

The act of moving an existing tag to point at a different commit. Legitimate
when fixing a broken release; malicious when done to inject code into
consumers who pin to the tag.

### Dependabot for GitHub Actions

Dependabot can monitor the actions in your workflows and open pull requests
when a new version is released, including updating a pinned SHA to the new
release's SHA. This is how you stay current without giving up immutability.

### SHA pinning policy

An organisation rule requiring all `uses:` references to be pinned to a
full commit SHA, often with the version recorded in a comment for
readability.

## 3. Workflow example

There is no workflow file for this chapter, because pinning is a property
of every other workflow file. The table below is the SHA reference for the
versions this course uses, copied from `docs/00-roadmap.md`. Use it when
converting a tag pin to a SHA pin.

| Action | Version | Commit SHA |
| ------ | ------- | ---------- |
| `actions/checkout` | `v7` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-node` | `v7` | `949feb2413d6458794dcd2491c4babbbce0c15c1` |
| `actions/cache` | `v6` | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/upload-artifact` | `v7` | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` |
| `actions/download-artifact` | `v8` | `9000827ccba6bdab643e8b6fd33ac0654aef8333` |
| `actions/configure-pages` | `v6` | `45bfe0192ca1faeb007ade9deae92b16b8254a0d` |
| `actions/upload-pages-artifact` | `v5` | `fc324d3547104276b827a68afc52ff2a11cc49c9` |
| `actions/deploy-pages` | `v5` | `368f82528645a54fb793d4d04e342629a3f51346` |
| `docker/setup-buildx-action` | `v4` | `f87e5991a6d7451dcb8d9637bfbc97413f497069` |
| `docker/login-action` | `v4` | `dbcb813823bdd20940b903addbd779551569679f` |
| `docker/build-push-action` | `v7` | `c3c9e263c25d99ce0380d002d59b67737d91b0dc` |
| `docker/metadata-action` | `v6` | `dc802804100637a589fabce1cb79ff13a1411302` |
| `github/codeql-action` | `v4` | `7999b86c43a865dc79d8923397f35af22de63401` |
| `actions/dependency-review-action` | `v5.0.0` | `a1d282b36b6f3519aa1f3fc636f609c47dddb294` |
| `appleboy/ssh-action` | `v1` | `0ff4204d59e8e51228ff73bce53f80d53301dee2` |
| `slackapi/slack-github-action` | `v4` | `dcb1066f776dd043e64d0e8ba94ca15cc7e1875d` |
| `codecov/codecov-action` | `v7` | (no SHA recorded in this course) |
| `softprops/action-gh-release` | `v3` | (no SHA recorded in this course) |

### How a pinned line looks

Before (tag pin):

```yaml
- uses: actions/checkout@v7
```

After (SHA pin, with the version in a comment for humans):

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
```

The comment is not decoration. It is how a human knows which version the SHA
corresponds to without looking it up. Dependabot preserves the comment when it
updates the SHA.

### Converting the whole file

A tag pin becomes a SHA pin by replacing the tag with the SHA and appending
the tag as a comment. Do it for every `uses:` line, including transitive
actions you call inside composite actions and reusable workflows. A single
unpinned action anywhere in the dependency graph is a hole.

## 4. What I should see

### Verifying a pin locally

`scripts/validate-workflows.py` already rejects unpinned actions:

```bash
$ python3 scripts/validate-workflows.py
ok  .github/workflows/35-code-coverage.yml  (1 job(s))
...
N workflow file(s) checked, 0 error(s), 0 warning(s)
```

If you change a line to `uses: actions/checkout` (no ref) or
`uses: actions/checkout@main` (a branch), the validator reports it:

```
FAIL .github/workflows/example.yml.jobs.x.steps[0]: `uses: actions/checkout` is not pinned
  (needs @version or @sha)
FAIL .github/workflows/example.yml.jobs.x.steps[0]: `uses: actions/checkout@main` pins to a
  moving ref
```

### Confirming a SHA resolves to a tag

On GitHub, every commit SHA is addressable:

```
https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1
```

That page shows the tag `v7.0.1` (or whatever release) attached to the
commit. If the tag has moved since, the SHA still points at the original
code. That immutability is the entire point.

### What a real GitHub run adds (not verified locally)

- The actual behaviour of a tag that has been moved: consumers pinning to
  the tag get the new code on their next run, with no change to their
  workflow file.
- Dependabot's PRs updating SHAs, including the comment preservation.
- The audit and notification behaviour when an action you use is archived
  or deleted.

## 5. When to use it and when NOT to

**Pin to a SHA when:**

- **Always, in production workflows.** There is no downside to immutability
  for code that runs with your token and secrets.
- **You use third-party actions.** First-party GitHub actions (`actions/*`)
  are lower risk but not zero risk; a compromised maintainer account can
  push a tag. Pin them too.
- **You are in a regulated or security-sensitive environment.** SHA pinning
  is a common compliance requirement because it makes the executed code
  auditable.
- **You want reproducible builds.** A SHA pin means a re-run of an old
  workflow uses the same code, even years later.

**Tag pins are acceptable when:**

- **You are learning or prototyping.** A tag pin is faster to write and
  easier to read. Convert to SHAs before the workflow touches production.
- **The action is one you own and control.** Even then, a SHA is safer,
  but the risk of tag mutation is lower.
- **You have Dependabot for actions enabled and review its PRs.** The tag
  pin plus Dependabot is a reasonable middle ground, but it still has a
  window between the tag moving and the PR being merged.

**Do NOT:**

- **Do not pin to a branch (`@main`, `@master`).** A branch is the most
  mutable ref of all. Symptom: your workflow's behaviour changes on every
  run. Fix: pin to a tag at minimum, a SHA ideally.
- **Do not pin to a short SHA.** Seven characters is not enough; collisions
  (deliberate or accidental) become plausible. Use the full 40 characters.
- **Do not skip the version comment.** A bare SHA is unreadable. Symptom:
  nobody knows whether `3d3c42e...` is v6 or v7. Fix: append `# v7`.
- **Do not assume first-party actions are safe.** The `actions/*`
  namespace is well-maintained, but it is still code you did not write,
  running with your token. Pin it.
- **Do not forget composite actions and reusable workflows.** A workflow
  that calls a composite action inherits its unpinned references. Audit
  the whole graph.

## 6. Common mistakes

- **Pinning the action but not its transitive dependencies.** Symptom: the
  action itself is pinned, but it calls an unpinned action internally.
  Fix: audit the action's source, or vendor it.
- **Updating the SHA without updating the comment.** Symptom: the comment
  says `# v7` but the SHA is from v8. Fix: update both, or let
  Dependabot do it.
- **Using Dependabot but never merging its PRs.** Symptom: you are pinned
  to an old SHA with known vulnerabilities. Fix: review and merge action
  update PRs promptly; they are usually safe.
- **Confusing "pinned" with "reviewed."** Symptom: a SHA pin that nobody
  has actually read. Pinning prevents silent change; it does not prove the
  code is safe. Fix: read the action's source before adopting it, and pin
  what you have read.
- **Leaving `@main` on a fork of an action.** Symptom: your fork's default
  branch moves and your workflow changes. Fix: pin your fork to a SHA too.
- **Trusting the tag after a maintainer account is compromised.** This is
  the attack pinning prevents (below).

### The attack pinning prevents

In March 2024, the popular action `tj-actions/changed-files` was
compromised. An attacker gained access to the maintainer's credentials and
moved the `v44` (and other) tags to point at a malicious commit. That
commit ran a payload that dumped the runner's memory to the workflow log,
exfiltrating secrets from thousands of repositories that used the action
pinned to a tag.

Repositories that pinned `tj-actions/changed-files` to a specific commit SHA
were not affected, because the SHA they referenced still pointed at the
original, clean code. The tag moved; the SHA did not.

This is the concrete, documented incident behind the rule "pin to a SHA."
It is not a theoretical risk, and it is not limited to that one action or
that one month. Any tag you reference can be moved by anyone with write
access to that repository. Pinning to a SHA removes that entire class of
attack.

### Finding the SHA for an action

Three ways, in order of convenience:

1. **GitHub's UI.** Open the action's repository, go to the release or tag
   you want, and click the commit SHA. The URL becomes
   `https://github.com/owner/repo/commit/<sha>`. Copy it.
2. **The GitHub CLI.** `gh api repos/owner/repo/git/ref/tags/v4 --jq
   '.object.sha'` returns the SHA the tag points at. If the tag is
   annotated, dereference with `^{commit}`.
3. **Dependabot.** Enable Dependabot for `github-actions` and let it open
   the PR. The PR's diff shows the SHA it chose, which you can copy into
   other workflows.

Always verify the SHA resolves to the tag you expect before adopting it.
A tag and its SHA are only as trustworthy as the maintainer's account.

### Enforcing SHA pins in review

The validator in this repository accepts any pin, tag or SHA. To enforce
SHA pins specifically, use one of:

- **`actionlint`**, which can be configured to require SHA pins.
- **`step-security/secure-workflows`**, a tool that rewrites workflows to
  SHA pins and opens a PR.
- **A CI check** that greps `uses:` lines for a 40-character hex string
  after the `@`. A simple, effective gate:

  ```bash
  if grep -nE 'uses: [^@]+@[^#]*$' .github/workflows/*.yml; then
    echo "unpinned or tag-pinned action found"; exit 1
  fi
  ```

### Pinning in reusable workflows and composite actions

A reusable workflow (chapter 40) and a composite action (chapter 41) can
themselves contain `uses:` lines. Pinning the caller is not enough; the
callee's references must be pinned too, because they run with the caller's
permissions. Audit the whole graph:

```bash
grep -rn 'uses:' .github/
```

Every line should have `@<40-hex>` (or a documented exception). Anything
else is a hole.

### The trade-off, honestly

SHA pinning costs readability and convenience. A workflow with 20 SHA pins
is harder to read than one with tags, and staying current requires
Dependabot or manual effort. The benefit is immunity to tag mutation, which
is a real, documented attack (below). Most teams settle on: SHA pins in
production, tag pins in prototypes and forks, Dependabot everywhere.

## 7. Try it yourself

**Exercise: convert one workflow from tag pins to SHA pins.**

1. Pick a workflow, e.g. `.github/workflows/35-code-coverage.yml`.
2. For each `uses:` line, replace the tag with the SHA from the table in
   section 3, keeping the version as a comment:

   ```yaml
   - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
   ```

3. Run the validator:

   ```bash
   python3 scripts/validate-workflows.py
   ```

   It should still report `0 error(s)`. The validator accepts both forms;
   pinning is a policy choice, not a syntax requirement.

4. Run the workflow to confirm nothing changed in behaviour:

   ```bash
   ./scripts/verify.sh .github/workflows/35-code-coverage.yml coverage push ch35
   ```

   The output should be identical to the tag-pinned run.

5. **Enable Dependabot for actions.** Add the `github-actions` ecosystem
   entry from chapter 36's example and push. Dependabot will now open PRs
   when an action releases a new version, updating both the SHA and the
   comment.

6. **Break it on purpose.** Change a pin to `actions/checkout@main` and run
   the validator. It reports "pins to a moving ref." Change it to
   `actions/checkout` with no ref. It reports "is not pinned." Restore the
   SHA pin.

7. **Verify a SHA.** Open
   `https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1`
   in a browser and confirm the `v7` tag is attached to that commit. Then
   imagine the tag moving: the URL still shows the same code.

**Hint:** the validator enforces *a* pin, not a *SHA* pin. Enforcing SHA
pins is a policy you apply in review or with a dedicated tool like
`actionlint` or `step-security/secure-workflows`.

## 8. Next

You now know how to keep your dependencies current (chapter 36), how to
scan your code (chapter 37) and your commits (chapter 38), and how to make
sure the tools you trust cannot be silently swapped. Part 7 is complete.

The next part moves to advanced patterns, starting with reusing workflow
logic instead of copying it.

→ [40 — Reusable workflows](40-reusable-workflows.md)