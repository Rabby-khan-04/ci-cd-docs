# 51 — A Next.js app with a preview URL on every pull request [read-only example]

> **Verification.** This chapter is a **`[read-only example]`**: there is **no
> runnable workflow** and **no log** for it. Deploying a preview URL needs a
> hosting account (Vercel, Netlify, Cloudflare Pages, AWS Amplify, …) and
> credentials this course does not have, so nothing here was executed. The CI
> half of the pattern is the same shape as chapters 15 and 20, whose logs
> (`docs/_logs/ch15-ci-pipeline-order.log`, `docs/_logs/ch20.log`) are the
> source of the real build output quoted below. `python3
> scripts/validate-workflows.py` was run on the illustrative workflow in
> section 3 and reports it as valid YAML with 3 jobs.
>
> **What you can run today.** The free alternative is in section 7: the full CI
> pipeline (lint → test → build) plus an uploaded `dist` artifact plus a
> summary comment on the pull request that reports the built artifact size. It
> uses only `cicd-learn`, needs no hosting account, and runs on `act`.

---

## 1. Simple explanation (like I'm 7)

Imagine a school play. Every time a student writes a new scene, the teacher
puts it on a small stage in the classroom so the other students can read it
and say "this line is wrong" or "this scene is great" before it goes on the
big stage. The small stage is a **preview**: a real, working version of the
thing, but not the real thing, and it disappears when the feedback is done.

A **preview URL on every pull request** is that small stage for a website.
When someone opens a pull request, CI builds the app and deploys it to a
temporary URL like `pr-42.preview.example.com`. Reviewers click the link,
see the actual running app with their changes, and leave comments. When the
PR is merged or closed, the preview is deleted so it stops costing money.

The catch: to deploy a preview you need a hosting account, a token, and a
domain. None of those come for free in a course repository, so this chapter
is a `[read-only example]`. The CI half (build + artifact + a comment) is
runnable today and is the free alternative in section 7.

## 2. Real name

### Preview deployment

A temporary deployment of a specific commit or pull request, used for
review. Distinct from staging (long-lived, shared) and production
(long-lived, public). Previews are short-lived and one-per-PR.

### Preview URL

The address at which a preview deployment is reachable, usually containing
the PR number or the commit SHA so it is unique per change. Example:
`https://pr-42--myapp.preview.example.com`.

### `pull_request` event (and its danger)

The event that fires when a PR is opened, updated, or synchronised. It runs
in the context of the PR's merge commit, with read-only default permissions
and no secrets by default for forks. Chapter 06.

### `pull_request_target` event

A variant that runs in the context of the *base* branch with write
permissions and secrets, even for fork PRs. It exists so workflows can
comment on PRs or label them. It is also the single most dangerous trigger
in GitHub Actions, because a malicious PR can make the workflow execute
attacker-controlled code with write access. See "Common mistakes".

### Fork

A copy of a repository owned by someone else. PRs from forks are the
default on open-source projects. They are also the reason `pull_request`
has no secrets: the code is untrusted.

### Comment bot (PR comment)

A workflow step that posts a comment on the PR with a link or a summary.
Requires `pull-requests: write` permission and a token. Usually done with
`gh pr comment` or an action like `marocchino/sticky-pull-request-comment`.

### Cache thrash

When a cache key changes on every run, the cache is never hit and every run
re-downloads everything. Previews make this worse because every PR creates
a new branch and a new cache key, fragmenting the cache. Chapter 16.

### Runaway preview environment

A preview that is never deleted, accumulating cost. Happens when the
cleanup step is missing, fails, or is gated on a condition that never
fires.

### Distinctions people get wrong

- **Preview vs staging.** A preview is per-PR and ephemeral; staging is
  shared and long-lived. Do not use your staging environment as a preview
  target; one PR's bad deploy breaks everyone's review.
- **`pull_request` vs `pull_request_target`.** `pull_request` runs the PR's
  code with no secrets. `pull_request_target` runs the base branch's code
  with secrets. The names are similar; the security properties are opposite.
- **Build the PR vs build the merge.** `pull_request` checks out the PR head
  by default in recent GitHub; older tutorials checked out the base. Know
  which you are building.
- **Comment as a bot vs comment as the user.** `GITHUB_TOKEN` comments
  appear as `github-actions[bot]`. A PAT comments as a person. Both work;
  the bot is preferred for auditability.
- **Artifact vs preview.** An artifact is a file you can download; a preview
  is a running URL. They answer different review questions ("does it build"
  vs "does it look right").

## 3. Workflow example

This workflow was **not executed**. It needs a hosting account and
credentials, which `act` cannot provide. It is shown so you can read the
shape; the CI half is identical to chapters 15 and 20.

```yaml
name: Next.js preview on pull request

"on":
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write   # to post the preview link as a comment

jobs:
  # ── CI: build the app, the same as any PR check ──────────────────────────
  ci:
    name: CI
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
      - run: npm run lint
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 7
          if-no-files-found: error

  # ── Preview deploy: only on PRs, only after CI is green ──────────────────
  # Needs: a hosting provider's CLI or action, plus a token stored as a
  # repository secret. The provider varies; the shape does not.
  preview:
    name: Deploy preview
    runs-on: ubuntu-24.04
    needs: [ci]
    # Secrets are only available because this is `pull_request` from the same
    # repo. Fork PRs get no secrets; see the pitfalls.
    environment:
      name: preview
      url: ${{ steps.deploy.outputs.url }}
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: dist
          path: dist
      - name: Deploy to the preview host
        id: deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.PREVIEW_DEPLOY_TOKEN }}
        run: |
          # Provider-specific. The contract is: print the URL to $GITHUB_OUTPUT.
          # url=$(provider deploy --dir dist --name "pr-${{ github.event.pull_request.number }}")
          url="https://pr-${{ github.event.pull_request.number }}.preview.example.com"
          echo "url=$url" >> "$GITHUB_OUTPUT"
      - name: Comment the preview URL on the PR
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh pr comment ${{ github.event.pull_request.number }} \
            --body "Preview deployed: ${{ steps.deploy.outputs.url }}"

  # ── Cleanup: delete the preview when the PR closes ───────────────────────
  cleanup:
    name: Delete preview
    runs-on: ubuntu-24.04
    if: github.event.action == 'closed'
    steps:
      - name: Delete the preview deployment
        env:
          DEPLOY_TOKEN: ${{ secrets.PREVIEW_DEPLOY_TOKEN }}
        run: |
          # provider delete --name "pr-${{ github.event.pull_request.number }}"
          echo "deleted preview for PR ${{ github.event.pull_request.number }}"
```

Structural things to notice:

1. **`pull-requests: write` is the new permission**, and it is the only write
   permission the workflow needs. `contents: read` stays for checkout.
2. **The deploy job needs CI green first** (`needs: [ci]`). A red build must
   never produce a preview; reviewers would be looking at broken code.
3. **The preview URL is an environment `url:`**, so it shows up as a
   clickable link in the run summary and in the deployment history.
4. **Cleanup is a separate job gated on `closed`.** Without it, every PR
   leaves a preview running forever. That is the runaway-preview failure mode.
5. **Secrets come from a `preview` environment**, not repository scope, so a
   misconfigured workflow cannot read production credentials.
6. **The URL is posted as a PR comment**, so reviewers do not have to open
   the Actions tab to find it.

## 4. What I should see

There is no real log for this workflow. What follows is split into two parts:
the CI half, which is real and quoted from chapters 15 and 20, and the
preview half, which is described from the documentation and is not verified
locally.

### The CI half (real, from `docs/_logs/ch15-ci-pipeline-order.log`)

The build runs and reports its output, exactly as in chapter 15:

```
[CI pipeline order/...]   | > cicd-learn@1.0.0 build
[CI pipeline order/...]   | > node build.mjs
[CI pipeline order/...]   | 
[CI pipeline order/...]   | built dist/app.js (2887 bytes)
```

And the artifact uploads, as in chapter 20:

```
[Artifacts/...]   | SIMULATED upload of cicd-learn/dist as dist
[Artifacts/...]   ✅  Success - Main [simulated upload-artifact: dist]
```

That is the part you can run today, with chapters 15 and 20.

### The preview half (documented, not verified locally)

On github.com, with the workflow above and a real hosting provider:

1. A PR is opened. `ci` runs lint, test, build and uploads `dist`.
2. `preview` downloads `dist` and deploys it to a URL containing the PR
   number. The step prints the URL to `$GITHUB_OUTPUT`.
3. The comment step posts `Preview deployed: https://pr-42.preview.example.com`
   on the PR. Reviewers see it without opening the Actions tab.
4. The run summary shows the preview URL as a clickable link.
5. When the PR is merged or closed, `cleanup` runs and deletes the preview.

### What a real run adds that `act` cannot show

- **The hosting provider.** Vercel, Netlify, Cloudflare Pages, AWS Amplify:
  each has its own CLI, token, and URL scheme. `act` has none of them.
- **Fork PR behaviour.** Secrets are not injected for fork PRs. The
  workflow above works for same-repo PRs; for forks you need
  `pull_request_target` or a separate mechanism, which is the danger in
  section 6.
- **The PR comment.** `gh pr comment` needs `pull-requests: write` and a
  token. `act` does not have a PR to comment on.
- **Preview deletion.** The cleanup job only fires if the provider supports
  deletion by name and the token has that scope.

## 5. When to use it and when NOT to

**Use a preview deployment when:**

- **Reviewers need to see the UI.** A diff in a PR does not show what the
  page looks like. A preview does.
- **You ship a web app.** Static sites, SPAs, and server-rendered apps all
  benefit. A CLI tool or a library does not.
- **You want feedback before merge.** Catching a layout bug in review is
  cheaper than catching it in production.
- **Your team is distributed.** A shared URL is easier than "run it locally."

**Do NOT build preview deployments when:**

- **You are not on a platform that supports them.** A preview pipeline for a
  backend service with a database is hard; for a static site it is trivial.
  Match the effort to the value.
- **You cannot afford the cost.** Each preview is a running deployment. On a
  busy repo with 20 open PRs, that is 20 deployments. Set a retention limit
  and a cleanup job, or use a provider with free preview tiers.
- **Your previews are never deleted.** Then you are paying for a zoo of stale
  environments. Fix cleanup before you add more.
- **The CI is not green.** A preview of a broken build wastes everyone's
  time. Gate the deploy on `needs: [ci]`.
- **You would use `pull_request_target` to get secrets.** That is the trap
  in section 6. Do not.

## 6. Common mistakes

- **Using `pull_request_target` to get secrets for a fork PR.** This is the
  single most dangerous mistake in this chapter. `pull_request_target` runs
  with write permissions and secrets, against attacker-controlled code if you
  check out the PR head. Symptom: a malicious PR reads your secrets or
  pushes to your repo. Fix: never check out the PR head in a
  `pull_request_target` workflow; or use `pull_request` and accept no secrets
  for forks; or use a separate trusted workflow that comments only.
- **No cleanup job.** Symptom: 40 preview environments running a month later,
  each costing money. Fix: a `cleanup` job on `closed`, plus a scheduled
  sweeper for orphans.
- **Deploying before CI is green.** Symptom: reviewers see a broken preview
  and file issues about bugs that are actually build failures. Fix: `needs: [ci]`.
- **Cache thrash from per-PR branches.** Each PR branch gets its own cache
  key, so the cache is cold for every PR. Symptom: every PR build takes as
  long as the first. Fix: key the cache on the lock file, not the branch
  (chapter 16), and accept that PRs will be slower than main.
- **Hardcoding the preview URL.** Symptom: two PRs deploy to the same URL
  and overwrite each other. Fix: include the PR number or SHA in the name.
- **Posting the comment with the wrong token.** A comment posted with a PAT
  looks like a person; with `GITHUB_TOKEN` it looks like a bot. Symptom:
  reviewers cannot tell who posted it. Fix: use `GITHUB_TOKEN` and let it
  show as `github-actions[bot]`.
- **Forgetting `pull-requests: write`.** Symptom: the comment step fails with
  403 "Resource not accessible by integration". Fix: add the permission.
- **Letting fork PRs fail silently.** A fork PR has no secrets, so the
  deploy step fails. Symptom: red checks on every external contribution. Fix:
  gate the deploy on `github.event.pull_request.head.repo.full_name ==
  github.repository`, or skip it with `if:` and post "preview unavailable
  for forks".
- **Treating the preview as production.** A preview has no SLA, no
  monitoring, and no rollback. Symptom: someone points a customer at a
  preview URL. Fix: label previews clearly and never share them externally.

## 7. Try it yourself

**Exercise: the free alternative — CI + artifact + summary comment.**

This is the runnable part. It builds `cicd-learn`, uploads the artifact, and
writes the artifact size into the run summary, which is the closest thing to
a preview link you can do without a hosting account.

1. Create `.github/workflows/51-preview-free.yml`:

   ```yaml
   name: Preview (free alternative)
   "on":
     pull_request:
       branches: [main]
   permissions:
     contents: read
   jobs:
     ci:
       name: CI
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
         - run: npm run lint
         - run: npm test
         - run: npm run build
         - uses: actions/upload-artifact@v7
           with:
             name: dist
             path: cicd-learn/dist
             retention-days: 7
             if-no-files-found: error
         - name: Report the build to the summary
           run: |
             bytes=$(wc -c < dist/app.js)
             {
               echo "### Preview (free alternative)"
               echo ""
               echo "- PR: #${{ github.event.pull_request.number }}"
               echo "- built \`dist/app.js\`: ${bytes} bytes"
               echo "- download the artifact from this run to inspect it"
             } >> "$GITHUB_STEP_SUMMARY"
   ```

2. Run it locally:

   ```bash
   ./scripts/verify.sh .github/workflows/51-preview-free.yml "" pull_request ch51
   ```

   (Use the `pull_request` event so `github.event.pull_request.number` is
   populated; locally it may be empty, which is fine.)

3. Confirm the build prints `built dist/app.js (2887 bytes)` and the
   summary contains the byte count. That is the CI half of a preview
   pipeline, verified.

4. **Prove the gate.** Add `npm test` failure (edit a test to expect the
   wrong value) and re-run. The build step never runs; no artifact is
   uploaded. That is the `needs`-equivalent behaviour inside one job. Revert.

5. **Prove the comment permission.** Add a step that runs
   `gh pr comment ...` without `pull-requests: write`. It fails with 403.
   Add the permission and it succeeds (on GitHub only). Revert.

6. **Break it on purpose.** Remove `if-no-files-found: error` and point the
   upload at `dist` (which does not exist at the workspace root). The step
   is green with a warning and zero files uploaded. Revert.

7. **Clean up.** Delete `51-preview-free.yml` when you are done, so it
   does not linger in your workflow list.

**Hint:** `act` runs `pull_request` events with a synthetic payload. The PR
number may be `1` or empty; the build output is the part that matters. The
hosting-provider steps cannot be exercised locally at all.

## 8. Next

You can now build and check an app on every pull request. The next pattern
turns the same idea into a container: build the image, prove it runs, and
push it only when a tag is pushed.

→ [52 — A containerized service](52-pattern-containerized-service.md)
EOF
echo written