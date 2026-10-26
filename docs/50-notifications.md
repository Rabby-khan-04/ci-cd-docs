# 50 — Notifications

> **Verification.** This chapter's Slack workflow is a **`[read-only
> example]`**: it was **not** executed, because it needs a real Slack
> workspace and a webhook secret. There is no log for it. The free
> alternative — GitHub's built-in email notifications — needs no workflow at
> all and is described in section 7. `python3 scripts/validate-workflows.py`
> was run on the illustrative workflow in section 3 and reports it as valid
> YAML. The repository's own workflows (for example
> `.github/workflows/49-cost.yml`) are green and are the source of the log
> lines quoted where a run is referenced.
>
> **What local execution cannot prove.** Slack delivery, webhook secrets,
> notification routing and the Actions-tab "notify" settings are GitHub- and
> Slack-side features. They are described here from the GitHub and Slack
> documentation, not from a run in this repository.

---

## 1. Simple explanation (like I'm 7)

A pipeline that breaks in the dark is useless. If nobody is told, the red
build sits there until someone happens to open the Actions tab, which might be
days. Notifications are the alarm bell: when something goes red (or green, or
finishes a deploy), a message goes out to the people who need to know.

There are two kinds of alarm bell in this chapter:

- **The free one that is already installed.** GitHub emails you when a
  workflow you care about fails. You do not write any YAML for it; you turn it
  on in your account settings. This is the right starting point for everyone.
- **The custom one you build.** A workflow step that posts a message to
  Slack (or Teams, or Discord, or anywhere with a webhook). You write the
  YAML, you store a secret, you maintain it. This is for teams that already
  live in a chat tool and want the alert there instead of in email.

The rule of the chapter is simple: **notifications come last.** Get the
pipeline green and reliable first. An alert on a flaky pipeline is just noise,
and noise trains people to ignore the alarm.

## 2. Real name

### GitHub notifications

GitHub's own notification system: in-app (the bell icon), email, and (on
mobile) push. Configured per user, per repository, and per workflow. No
workflow YAML required.

### Email notifications

The default channel. GitHub sends an email when a workflow run you are
watching fails (and, optionally, when it succeeds). Addressed to the
account's primary email unless changed.

### Slack

A chat platform. GitHub can post to Slack via an incoming webhook or via the
`slackapi/slack-github-action` action, which gives you control over the
message format and the channel.

### Incoming webhook

A URL that accepts an HTTP POST and turns it into a chat message. Slack
generates one per channel. The URL is a secret: anyone who has it can post
to your channel.

### `slackapi/slack-github-action`

The official GitHub Action for posting to Slack. Pinned in this course to
`v4` (SHA `dcb1066f776dd043e64d0e8ba94ca15cc7e1875d`). It supports
incoming-webhook and bot-token modes.

### Watch / unwatch

GitHub's per-repository setting that decides whether you receive
notifications for activity in that repo. Separate from workflow notifications.

### Notification routing

Deciding *who* gets told about *which* events. Email goes to individuals;
Slack goes to channels. Routing is the difference between an alert that
reaches the on-call engineer and one that nobody reads.

### Alert fatigue

The state where people stop reading alerts because there are too many, or
because too many are false positives. The reason notifications are the last
thing you build.

## 3. Workflow example

This workflow is valid YAML but was not executed. It posts a Slack message
when the pipeline fails, and a different one when it succeeds. Save as
`.github/workflows/50-notify.yml`:

```yaml
name: Notify on failure (read-only)

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  ci:
    name: Build and test
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

  notify:
    name: Post to Slack
    runs-on: ubuntu-24.04
    # Only notify when CI failed. Chapter 19 covers `if: failure()`.
    if: failure()
    needs: [ci]
    steps:
      # slackapi/slack-github-action@v4 posts to a channel via a webhook.
      # The webhook URL is a secret; never put it in the YAML.
      - name: Post failure to Slack
        uses: slackapi/slack-github-action@v4
        with:
          # Incoming-webhook mode: one secret, one channel.
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-type: incoming-webhook
          # The message body. Supports Slack mrkdwn.
          payload: |
            {
              "text": ":x: CI failed on `${{ github.ref_name }}`",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*CI failed*\nRepo: `${{ github.repository }}`\nBranch: `${{ github.ref_name }}`\nCommit: `${{ github.sha }}`\nRun: <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|Open run>"
                  }
                }
              ]
            }
```

Three things to notice:

1. The `notify` job has `if: failure()` and `needs: [ci]`. It only runs when
   the CI job failed, and it waits for CI to finish. Chapter 19.
2. The webhook URL comes from `secrets.SLACK_WEBHOOK_URL`. It is never in the
   file. Chapter 22.
3. The message contains a link to the run. An alert that does not link to the
   run is half an alert; the first thing a responder does is open the run.

A success notification is the same shape with `if: success()` instead of
`if: failure()`. Most teams notify only on failure; success notifications
are useful for deploy jobs, where "it shipped" is worth announcing.

## 4. What I should see

There is no real log for this chapter. The free alternative (GitHub's built-in
email) produces no workflow log at all; it is handled by GitHub's notification
service. What you would see, described from the documentation:

### GitHub's built-in email `[read-only example]`

When a workflow run fails, GitHub sends an email to the accounts that are
watching the repository, subject to their notification settings:

```
Subject: [cicd-docs] Run failed: CI #42
From:    notifications@github.com
Body:    The "CI" workflow run has failed.
         View run: https://github.com/owner/repo/actions/runs/12345
```

The email links to the run. It does not include the log; you open the link to
read it. That is deliberate: email is for "something happened", not for
diagnosis.

Configuration is per user, under Settings → Notifications → Actions:

- **Notify me:** "Only failures" (recommended) or "All runs".
- **Email delivery:** to your primary email, or to a custom address.
- **Watching:** you must be watching the repository. Unwatching stops the
  emails.

### Slack via `slackapi/slack-github-action` `[read-only example]`

When the `notify` job runs, the action posts to the webhook URL:

```
Run Post failure to Slack
  ✅  Success - Main Post failure to Slack [1.2s]
```

And the Slack channel receives:

```
:x: CI failed on `main`

*CI failed*
Repo: `owner/cicd-docs`
Branch: `main`
Commit: `a1b2c3d...`
Run: Open run
```

The message arrives within seconds of the failure. The "Open run" link jumps
to the Actions tab.

### The GitHub UI for notifications `[read-only example]`

```
Repository → Settings → Notifications
  - Watch: "Releases only", "Participating and mentions", "All activity", "Ignore"
Repository → Settings → Webhooks (for custom integrations)
Account → Settings → Notifications → Actions
  - "Email" on/off, "Web" on/off, "Mobile" on/off
  - "Send notifications for failed workflows only" (recommended)
```

None of this is workflow YAML. It is account and repository configuration,
and it is where most teams should spend their first notification hour.

### What a Slack setup looks like, end to end `[read-only example]`

1. In Slack: Apps → Incoming Webhooks → Add to Slack → pick a channel → copy
   the webhook URL (`https://hooks.slack.com/services/...`).
2. In GitHub: repository Settings → Secrets and variables → Actions → New
   repository secret → name `SLACK_WEBHOOK_URL`, value = the webhook URL.
3. Add the workflow from section 3. Push. Break the build on purpose. The
   message appears in Slack within seconds.
4. Rotate the webhook if it leaks: Slack lets you revoke and regenerate a
   webhook URL; update the secret.

The webhook URL is a credential. Treat it like a password: store it as a
secret, never commit it, rotate it if it leaks. Chapter 22 and 26.

## 5. When to use it and when NOT to

**Use GitHub's built-in email when:**
- You are one person or a small team. It is free, instant, and requires zero
  YAML. Start here.
- You want failure alerts and nothing else. "Only failures" is the right
  default.
- You do not want to maintain a secret or a third-party integration.

**Use Slack (or Teams/Discord) when:**
- Your team already lives in a chat tool and checks it more often than email.
- You want rich messages: links, commit info, who broke it, a button to
  re-run.
- You want routing: failures to `#ci-alerts`, deploy successes to
  `#releases`, security alerts to `#security`.

**Do NOT notify when:**
- **The pipeline is not yet reliable.** A flaky pipeline that pages people
  three times a day trains them to ignore the page. Fix the pipeline first.
- **Every event.** Success, failure, cancellation, skipped — all of them. That
  is spam. Notify on failure; optionally on deploy success.
- **Every branch.** A failure on a throwaway feature branch does not need an
  alert. Notify on `main` and on pull requests that are ready for review.
- **Without a link to the run.** An alert that says "CI failed" and nothing
  else wastes the responder's first minute. Always link.

**Do NOT use Slack when:**
- You are the only person on the project. Email is simpler and has no secret
  to leak.
- You cannot keep the webhook secret. A leaked webhook is a spam channel into
  your workspace. Email has no equivalent leak.
- You want the alert to survive a Slack outage. Email is more reliable for
  the "something is on fire" case.

## 6. Common mistakes

- **Notifying before the pipeline is stable.** Alert fatigue in a week.
  Symptom: people mute the channel. Fix: stabilize, then notify.
- **Notifying on success as well as failure.** Doubles the noise. Symptom:
  a channel full of green checkmarks. Fix: failure only, plus deploy success.
- **Committing the webhook URL.** It is a credential. Symptom: a spam
  channel. Fix: `secrets.SLACK_WEBHOOK_URL`, always.
- **A notify job with no `if:`.** It runs on every outcome, including
  success, and the message says "failed" when it did not. Symptom: lying
  alerts. Fix: `if: failure()` or `if: success()`.
- **A notify job with no `needs:`.** It runs in parallel with CI and may
  post "failed" before CI has finished, or post about a job that has not run.
  Symptom: premature or contradictory alerts. Fix: `needs: [ci]`.
- **Using `pull_request` for deploy notifications.** Deploy jobs should run on
  `push` to `main` or on a tag, not on every PR. Symptom: "deployed" messages
  for code that was never merged. Fix: gate on the right event.
- **Ignoring the account-level setting.** GitHub's default for a new account
  is "Participating and mentions", which may not include workflow failures.
  Symptom: no emails arrive. Fix: Settings → Notifications → Actions → "Only
  failures".
- **Not testing the notification.** The first time you find out the webhook
  is wrong is during a real incident. Symptom: silence during an outage. Fix:
  break the build on purpose once and confirm the message arrives.
- **A message with no run link.** The responder has to find the run by hand.
  Symptom: wasted minutes. Fix: include `${{ github.server_url }}/${{
  github.repository }}/actions/runs/${{ github.run_id }}`.
- **Leaving a revoked webhook in the secret.** After rotating, the old
  secret still points at a dead URL. Symptom: silent notification failures.
  Fix: update the secret and re-test.

## 7. Try it yourself

**Exercise A — the free alternative (GitHub's built-in email).**

1. Make sure you are watching this repository: on the repo page, click
   **Watch** → **All activity** (or at least **Participating and mentions**).
2. Settings → Notifications → Actions: enable email, set "Only failures".
3. Break the build on purpose (a failing test or a lint error) and push.
4. Within a minute or two, an email arrives with a link to the run. Open it.
   That is the whole free alternative, and it costs zero YAML.
5. Fix the build and push again. No email arrives for success (with "Only
   failures"), which is the desired behaviour.
6. Unwatch the repository when you are done, to stop the emails.

**Exercise B — Slack, read-only, with a free stand-in.**

You can rehearse the Slack workflow without a Slack workspace by replacing
the Slack step with a step that writes the same payload to the job summary:

```yaml
- name: Preview the Slack message (free stand-in)
  if: failure()
  needs: [ci]
  run: |
    {
      echo "### :x: CI failed (Slack preview)"
      echo ""
      echo "- Repo: \`${{ github.repository }}\`"
      echo "- Branch: \`${{ github.ref_name }}\`"
      echo "- Commit: \`${{ github.sha }}\`"
      echo "- Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
    } >> "$GITHUB_STEP_SUMMARY"
```

This renders the exact message you would have sent, on the run page you
already have, with no secret and no third party. When you are ready for real
Slack, swap the step for `slackapi/slack-github-action@v4` and add the
`SLACK_WEBHOOK_URL` secret.

**Exercise: test the real thing (on GitHub only).**

1. Create a Slack incoming webhook for a test channel.
2. Add it as `SLACK_WEBHOOK_URL` in the repository secrets.
3. Add the workflow from section 3.
4. Break the build on purpose and push.
5. Confirm the message arrives in Slack with the run link.
6. Click the link, read the failure, fix it, push again.
7. Confirm no second message arrives (because the run succeeded).
8. Revoke the test webhook when finished.

**Hint:** if no message arrives, check three things in order: the job's
`if:` condition (did CI actually fail?), the `needs:` (did the notify job
wait for CI?), and the secret name (does it match `SLACK_WEBHOOK_URL`
exactly, including case?). Those three account for almost every "Slack is
broken" report.

**Break it on purpose:** put the webhook URL directly in the YAML instead of
using the secret, push, and watch it arrive in Slack. Then rotate the
webhook immediately and update the secret. That is the leak, demonstrated
once, so you never do it in production.

## 8. Next

You have now built, secured, deployed, debugged, re-run, costed and wired up
notifications for a pipeline. That is the whole of Part 9, and the end of
the operational arc.

→ [51 — A Next.js app with a preview URL on every pull request](51-pattern-nextjs-preview.md)