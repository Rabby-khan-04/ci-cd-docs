# 38 — Secret scanning and push protection

> **Verification.** This chapter has no workflow file and no local run. Secret
> scanning and push protection are repository settings enforced by GitHub's
> backend; they cannot be exercised by `act`, and there is no YAML to
> validate. `python3 scripts/validate-workflows.py` does not apply. Everything
> about what the scanner finds and how push protection behaves is described
> from GitHub's documentation and from the related local scan in chapter 26.
> **[GitHub-only feature].**
>
> **What this cannot prove locally.** You cannot trigger a secret-scanning
> alert or a push rejection from your laptop. The free alternative is to use
> a public repository (secret scanning is free for public repos) and push a
> known test pattern, or to use GitHub's documented test tokens, which are
> designed to trigger alerts without being real credentials.

---

## 1. Simple explanation (like I'm 7)

Imagine a post office that X-rays every parcel before it leaves. If it sees
something that looks like a key — a house key, a car key, a safe key — it
stops the parcel and calls you. The parcel never reaches the recipient, and
you get a chance to take the key out before anyone else sees it.

Secret scanning is that X-ray for your repository. Every time you push, GitHub
looks at the new code for things that look like credentials: API keys, tokens,
passwords, private keys. If it finds one, it either alerts you (after the
fact) or, with push protection, stops the push before it lands. The goal is
simple: a secret that never reaches the repository never needs to be
rotated.

## 2. Real name

### Secret scanning

GitHub's feature that scans repository contents (and, on push, the incoming
commits) for patterns matching known credential formats. It covers GitHub's
own tokens, partner patterns (AWS, Azure, Google Cloud, Stripe, Slack, and
many more), and generic high-entropy strings. Alerts appear in the
repository's Security tab.

### Push protection

A mode of secret scanning that blocks the push itself. When a push contains
a detected secret, the push is rejected with an error message naming the
secret type and the file. The developer must remove the secret or bypass with
a documented reason.

### Secret scanning alert

A record created when a secret is detected in the repository's history or in
an incoming push. It includes the secret type, the location, and (for some
partners) an automatic revocation or notification to the issuer.

### Partner pattern

A credential format registered by a third party (e.g. AWS, Stripe) with
GitHub. When GitHub detects one, it can notify the partner, who may revoke
the credential automatically. This is why a leaked AWS key is often dead
within minutes.

### Bypass

Push protection can be bypassed by the pusher, with a required reason. The
bypass is logged and (depending on settings) notifies repository admins.
Bypasses are the escape hatch for false positives and for secrets that are
not real (test fixtures, documentation examples).

### `GITHUB_TOKEN` scoping (revisited)

The built-in token is scoped to the repository and to the run. Secret
scanning treats a leaked `GITHUB_TOKEN` value like any other credential, but
because the token expires with the run, the practical risk is lower. The
real risk is a long-lived PAT or a cloud key.

### Custom patterns

Organisation-level secret scanning can be extended with custom regular
expressions, so internal token formats (your company's API keys) are
detected even though GitHub does not ship a pattern for them.

## 3. Workflow example

There is no workflow file for this chapter. Secret scanning is configured
in the repository settings, not in YAML. But it interacts with your CI in
two ways worth showing, so here is a small workflow that demonstrates the
interaction. Save it as `.github/workflows/secret-scan-check.yml` if you
want a CI-side backstop (this is illustrative; the real scanning is
GitHub's):

```yaml
# A CI-side backstop that fails if a credential-shaped string is committed.
# This complements, but does not replace, GitHub's secret scanning.
name: Secret scan (CI backstop)

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  scan:
    name: Scan tracked files
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    defaults:
      run:
        working-directory: cicd-learn
    steps:
      # Note: this checks out the repo, which is fine here because we are
      # scanning our own code on push and pull_request, not on fork PRs with
      # secrets. See chapter 25 for the pull_request_target trap.
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Scan for credential shapes
        run: |
          set +e
          hits=0

          git grep -nE 'BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY' -- . \
            && hits=1 || true
          git grep -nE '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' -- . \
            && hits=1 || true
          git grep -nE '\b(AKIA|ASIA)[0-9A-Z]{16}\b' -- . \
            && hits=1 || true

          if [ "$hits" = "1" ]; then
            echo "::error::Possible secret in tracked files."
            exit 1
          fi
          echo "clean"
```

Three things to notice:

1. This is a backstop, not the real thing. It catches the same obvious
   shapes chapter 26's workflow catches, and it misses everything GitHub's
   scanner catches that you have not thought of.
2. `fetch-depth: 0` checks the full history. A secret committed three
   commits ago and removed in the latest commit is still in git history,
   and a shallow checkout would miss it.
3. The real scanning happens on GitHub's side, on every push, regardless of
   whether this workflow exists.

## 4. What I should see

### Turning it on (GitHub UI)

1. Open the repository on github.com.
2. Settings → Security → Code security and analysis.
3. Enable "Secret scanning".
4. Enable "Push protection" (this is the part that blocks pushes).
5. Optionally enable "Validity checks" and "Partner notifications" if
   offered.
6. For organisations, enable it at the org level so every new repository
   inherits it.

For public repositories, secret scanning and push protection are free and
on by default. For private repositories, they require GitHub Advanced
Security (paid), except for a limited set of patterns.

### What a push rejection looks like

With push protection on, pushing a commit containing a detected secret
fails:

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote:
remote: - GITHUB PUSH PROTECTION
remote:   Resolve the following violations before pushing again
remote:
remote:     - Push cannot contain secrets
remote:
remote:      (?) Learn how to resolve a blocked push
remote:      https://docs.github.com/...
remote:
remote:      (?) This secret can be bypassed
remote:
remote:       (?) See: https://docs.github.com/...
remote:
remote:       secret: github_personal_access_token
remote:       file:  src/config.js:12
remote:
remote:       (?) To push, remove secret from commit(s) or follow this URL to
remote:       allow the secret.
remote:
To github.com:owner/repo.git
 ! [remote rejected] main -> main (push declined due to repository rule violations)
error: failed to push some refs to 'git@github.com:owner/repo.git'
```

The push never lands. The secret never enters the repository's history.

### What an alert looks like (when scanning finds one)

If a secret slips through (push protection off, or a bypass), an alert
appears under Security → Secret scanning:

```
Secret scanning alert #42
  Type: AWS Access Key ID
  Location: src/deploy.js, line 8
  Commit: a1b2c3d
  State: Open
  [Revoke] [Close as false positive] [Close as used in tests]
```

For partner patterns, the issuer is notified and may revoke the credential
automatically, often within minutes.

### What a real GitHub run adds (not verified locally)

- The actual push rejection and the bypass flow.
- Partner revocation, which happens outside GitHub.
- Custom patterns, which are configured at organisation level.
- The validity checks that tell you whether a detected secret is still live.
- The audit log entries for bypasses.

## 5. When to use it and when NOT to

**Use secret scanning and push protection when:**

- **Always, on every repository.** There is no downside to detecting
  leaked credentials, and push protection stops the leak before it starts.
- **You have multiple contributors.** The person who leaks a secret is
  usually not the person who owns it. Scanning protects against other
  people's mistakes.
- **You use long-lived credentials.** Cloud keys, database passwords, and
  PATs are the high-value targets. Push protection is the cheapest way to
  keep them out of git.
- **You have a public repository.** Public repos are scanned by GitHub and
  by third parties. Assume anything pushed is public forever.

**Do NOT:**

- **Do not treat push protection as a licence to be careless.** It catches
  known patterns, not your internal tokens or passwords that do not match
  a pattern. Keep the CI scan from chapter 26 as a backstop.
- **Do not bypass without a reason.** Every bypass is logged and reviewed.
  Bypassing because "it is just a test key" trains the team to bypass
  everything. Use a clearly fake value instead.
- **Do not store real secrets in test fixtures.** Even with push protection,
  a test that uses a real credential is a leak waiting to happen. Use fake,
  obviously-fake values (`AKIAIOSFODNN7EXAMPLE`).
- **Do not assume scanning covers git history.** It does, but only after the
  fact. A secret pushed years ago is still an alert. Rotate it; do not just
  delete the file.
- **Do not disable push protection to "unblock" a push.** Remove the
  secret instead. Disabling protection to push a leak is how incidents
  happen.

## 6. Common mistakes

- **Assuming scanning is on by default for private repos.** Symptom: a
  leaked secret in a private repo creates no alert. Fix: enable secret
  scanning and push protection in settings, or at org level.
- **Bypassing push protection for a "test" secret.** Symptom: a real-looking
  credential enters history and gets scanned later. Fix: use obviously fake
  values that do not match a pattern, or mark the commit with the bypass
  reason "test credential".
- **Deleting the file but not rotating.** Symptom: the secret is still in git
  history and still live. Fix: rotate the credential immediately, then
  rewrite history if it was pushed.
- **Confusing secret scanning with the CI scan.** Symptom: relying on one
  and disabling the other. Fix: both. GitHub's scanner is broader; the CI
  scan is yours and runs on every PR.
- **Not enabling custom patterns for internal tokens.** Symptom: your
  company's API keys leak without an alert, because GitHub does not know
  their format. Fix: add a custom pattern at org level.
- **Ignoring validity checks.** Symptom: an alert for a secret that was
  already revoked, creating noise. Fix: use validity checks to filter dead
  secrets, and close stale alerts.
- **Treating `GITHUB_TOKEN` leaks as harmless.** Symptom: a leaked
  `GITHUB_TOKEN` value is dismissed because "it expires anyway." Fix: it
  still grants repository access for the duration of the run and can be used
  to exfiltrate data. Rotate by re-running or revoking the run.
- **Pushing to a branch that bypasses protection.** Symptom: a direct push
  to `main` with a secret, because branch protection was not configured.
  Fix: protect `main` (chapter 34) so pushes go through pull requests and
  push protection.

### Custom patterns

GitHub's built-in patterns cover popular services. Your own token format
needs a custom pattern. At organisation level (Settings → Code security and
analysis → Secret scanning → Custom patterns):

```text
Name:    Internal API token
Secret format:  myapp_[A-Za-z0-9]{32}
Push protection: enabled
```

Once enabled, any push containing a string matching that regex is blocked
or alerted, exactly like a built-in pattern. Custom patterns are the only
way to catch internal credentials, and they are the reason many leaks of
company-specific tokens go undetected: nobody defined the pattern.

### Validity checks

For some partners, GitHub can check whether a detected secret is still
live. An alert then shows "active" or "inactive", which helps triage: an
inactive secret is still a leak worth fixing (it was live at some point),
but it is not an ongoing incident. Validity checks are enabled per
organisation and are not available for all pattern types.

### GITHUB_TOKEN scoping, revisited

Secret scanning finds `GITHUB_TOKEN` values too, but the risk is different:

- A `GITHUB_TOKEN` expires when the run ends, so a leaked value has a
  short shelf life.
- It is scoped to the repository and to the permissions granted, so even a
  live value cannot exceed what the workflow declared (chapter 25).
- The bigger risk is a leaked PAT or cloud key, which is long-lived and
  broadly scoped. Push protection's highest value is there.

This is why `permissions: contents: read` (chapter 25) and secret scanning
(chapter 38) are two halves of the same defence: one limits what a leaked
token can do, the other keeps the token out of the repository in the first
place.

### What scanning does NOT catch

- Secrets that do not match any pattern, including most passwords and
  internal tokens without a custom pattern.
- Secrets in binary files, images, or archived formats.
- Secrets split across multiple lines or encoded in a way the scanner does
  not decode.
- Secrets in commit messages, issue bodies, or pull request comments (these
  are scanned separately, with different coverage).

This is why the CI scan from chapter 26 and the habit of never committing
credentials remain necessary. Scanning is a safety net, not a policy.

## 7. Try it yourself

**Exercise: trigger push protection with a known test pattern.**

1. Create a public repository (so scanning is free) and enable secret
   scanning and push protection.
2. Clone it locally.
3. Create a file `leak.txt` containing a documented test token, for example
   GitHub's own example PAT format from the documentation, or the AWS
   example key `AKIAIOSFODNN7EXAMPLE`.
4. Commit and push. Observe the push rejection with the secret type and
   file named.
5. Remove the file, amend the commit, and push again. The push succeeds.
6. **Trigger an alert instead.** Disable push protection temporarily, push
   the same file, and watch the alert appear under Security → Secret
   scanning. Re-enable push protection immediately.
7. **Try a bypass.** With push protection on, push the secret and choose
   "bypass" with reason "test". The push lands and an alert is created.
   Read the audit log entry. Revert the commit and rotate nothing (it was a
   test value), but note how the bypass is recorded.
8. **Break it on purpose.** Add a custom internal token format to your org's
   custom patterns, then push a file containing it. Confirm it is now
   caught. Remove the pattern and confirm it is missed. That is the gap
   custom patterns close.

**Hint:** GitHub publishes "test credentials" specifically for this
purpose. Search the documentation for "supported secret scanning patterns"
and use the example values listed there. Never use a real credential, even
in a throwaway repository.

## 8. Next

You now have two detectives: one reading your code for vulnerabilities, one
reading your commits for secrets. The last piece of the safety story is
making sure the tools you trust — the actions in your workflows — cannot be
silently replaced underneath you.

→ [39 — Pinning actions](39-pinning-actions.md)