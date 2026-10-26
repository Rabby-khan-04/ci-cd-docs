# 06 — Events and triggers

> **Verification.** The workflow in this chapter is
> `.github/workflows/06-events-and-triggers.yml` in this repository, and it was
> executed four separate times with `act` 0.2.89 against the real file:
>
> - `scripts/verify.sh .github/workflows/06-events-and-triggers.yml which-event push ch06`
>   → `docs/_logs/ch06-triggers.log` (exit 0)
> - `act workflow_dispatch ...` → `docs/_logs/ch06-dispatch.log` and
>   `docs/_logs/ch06-dispatch-inputs.log` (exit 0), the second with
>   `--input greeting=bonjour --input shout=true --input target=staging`
> - `act pull_request ...` → `docs/_logs/ch06-pullrequest.log` (exit 0)
>
> One more run exists purely to test a claim: a `push` event payload with
> `ref: refs/heads/feature-x`, saved as `docs/_logs/ch06-filter-ignored.log`
> (exit 0). It proves that **local `act` ignores `branches:` filters** while it
> **does** honour step-level `if:` conditions. Every log line quoted in section 4
> comes from one of those five files.
>
> What local execution **cannot** prove, and what you must confirm on GitHub:
> the Actions tab's "no runs appeared" behaviour, `workflow_dispatch` inputs
> rendering as a form, scheduled runs firing at their cron time, and the fact
> that a workflow file must already be on the default branch for `push` and
> `workflow_dispatch` to see it at all. The hosted confirmation is pending,
> because there is no remote repository yet. Values documented from the
> workflow-syntax reference rather than measured here are marked as such.

---

## 1. Simple explanation (like I'm 7)

Your house has a doorbell. The doorbell is always there, doing nothing. What
starts it is a **button**, and there is more than one button on the wall.

- Someone pushes code → the "post" button.
- Someone opens a pull request → the "visitor" button.
- It is 03:17 in the morning → the "alarm clock" button, which presses itself.
- You, a human, press "Run workflow" in the GitHub interface → the "manual"
  button.

The doorbell does nothing different depending on which button was pressed. It
runs the same instructions. But it only runs if the button you pressed is one of
the buttons the instructions say to listen to, **and** the note next to that
button matches what happened.

Those two words are the whole chapter:

- **Which button** = the event: `push`, `pull_request`, `schedule`,
  `workflow_dispatch`.
- **The note next to it** = the filter: "only for the `main` branch", "only if
  `cicd-learn/**` changed", "only if a tag starts with `v`".

The trap people fall into: they press a button, the doorbell does nothing, and
they assume the doorbell is broken. In nine cases out of ten the note does not
match. Not the button.

## 2. Real name

### Event

Something that happened in the repository. GitHub has around a hundred of them:
`push`, `pull_request`, `schedule`, `workflow_dispatch`, `release`, `issues`,
`issue_comment`, `workflow_run`, `repository_dispatch`, `deployment`, `fork`,
`watch`, and so on. Each one is a named, documented event with a documented
payload.

You do not have to pick from all of them. Four cover most of a first pipeline,
and this chapter uses exactly those four.

### Trigger

The thing that **starts a run**. It is a fuzzy word and that is the first thing
people get wrong:

- People say "the trigger is `push`" — they mean the **event**.
- People say "I set a trigger on `main`" — they mean the **filter**.
- Pressing "Run workflow" in the Actions tab is also a trigger, but its event is
  `workflow_dispatch`, so the event name never changes even though a human
  started it.

In a workflow file, the `on:` block contains both the events you listen for and
the filters on those events.

### Activity types

Most events have sub-types. `pull_request` fires for many different activities:
`opened`, `synchronize`, `reopened`, `closed`, `labeled`, `edited`, `ready_for_review`,
and about a dozen more.

If you write `types:`, you get **only** what you list. If you omit `types:` you get
the default set for that event, which for `pull_request` is:

```
opened, synchronize, reopened
```

That default is why people are surprised when a PR is closed and nothing runs.
`closed` is not in it, and closing a PR is not something you want to re-test
anyway. If you need it, you must ask:

```yaml
pull_request:
  types: [opened, synchronize, reopened, closed, ready_for_review]
```

`synchronize` is the one that matters most: it fires on **every new commit pushed
to the PR branch**, which is why a PR re-runs its checks as you push.

### The four events in this chapter

| Event | Fires when | Reads the workflow file from |
| ----- | ---------- | --------------------------- |
| `push` | Someone pushes commits or tags | The ref that was pushed to |
| `pull_request` | PR activity on the base branch | The PR's merge ref, i.e. the PR's own version of the file |
| `schedule` | The cron expression comes due | The **default branch**, always |
| `workflow_dispatch` | A human clicks "Run workflow" | The **default branch**, always |

The last column is not a detail. It is the reason a brand-new workflow file does
nothing when you push it to a feature branch, and the reason a workflow file you
add in a PR cannot be tested by `workflow_dispatch` until it merges.

### Filters, and the four ways people get them wrong

```yaml
"on":
  push:
    branches: [main]          # 1. where the ref lands
    tags: ['v*']              # 2. tag names
    paths:                    # 3. which files changed
      - 'cicd-learn/**'
      - '!**/*.md'
    branches-ignore: [main]   # 4. everything except
```

**Wrong 1: thinking `branches` means "branches that contain this".** It is the
branch being pushed *to*. A push to `feature/login` does not match
`branches: [main]` even if it will be merged into `main` tomorrow.

**Wrong 2: expecting `branches` and `tags` to be an OR.** They are not. Per the
workflow-syntax reference, if you specify only `tags`, branch pushes do not run
this workflow. If you specify only `branches`, tag pushes do not. **Specify
neither and both fire.** This one surprises people who add `tags: ['v*']` to a
push trigger and then find that ordinary branch pushes stopped working.

**Wrong 3: expecting `paths` to apply to tag pushes.** It does not. Path filters
are not evaluated for pushes of tags.

**Wrong 4: using both sides of a pair.** `branches` together with
`branches-ignore` is an error, and so is `paths` with `paths-ignore`. Pick one
side. Within `paths`, negative patterns (`!`) must come **after** the positive
ones, or they are ignored.

### What the runner puts in your environment

When a run starts, the runner sets variables that tell the job what actually
happened. The ones used in this chapter:

| Expression | Meaning |
| ---------- | ------- |
| `github.event_name` | Which event fired: `push`, `pull_request`, ... |
| `github.ref` | The full ref: `refs/heads/main`, `refs/tags/v1.2.0` |
| `github.ref_name` | The short form: `main`, `v1.2.0` |
| `github.ref_type` | `branch` or `tag` |
| `github.actor` | The username that caused the event |
| `github.run_id`, `github.run_attempt` | Which run, and which attempt of it |
| `github.event.schedule` | The cron string, on a `schedule` event only |
| `github.event.number` | The PR number, on a `pull_request` event only |
| `$GITHUB_EVENT_PATH` | Path to a JSON file with the whole event payload |

The one that costs people a day: **on a `pull_request` event, `github.ref` is
`refs/pull/<number>/merge`, not `refs/heads/main`.** So
`if: github.ref == 'refs/heads/main'` is false on a PR even when the PR targets
`main`. Use `github.base_ref` for the target branch, or `github.head_ref` for
the source branch. (From the workflow-syntax reference; not reproduced in the
local logs, because `act` fabricates its own pull-request payload — section 4
shows exactly what that looked like.)

### `workflow_dispatch` inputs

The manual trigger can ask for input, and the Actions tab turns it into a form
under the "Run workflow" button:

```yaml
workflow_dispatch:
  inputs:
    greeting:
      description: 'What to print'
      required: false
      default: 'hello'
      type: string
    shout:
      default: false
      type: boolean
    target:
      type: choice
      options: [staging, production]
```

Five input types: `boolean`, `choice`, `number`, `environment`, `string`.
`choice` must list `options:` and **cannot have a `default`** — if the operator
does not pick one, the input is simply unset.

Two ways to read an input, and the trap between them:

- `inputs.greeting` — the real, typed value. `inputs.shout` is a boolean.
- `github.event.inputs.greeting` — the raw payload. **Every value here is a
  string**, so `github.event.inputs.shout` is the text `"true"`, not `true`.

Use `inputs.*`. It is the typed one.

## 3. Workflow example

This is the real file, `.github/workflows/06-events-and-triggers.yml`:

```yaml
name: Events and triggers demo

# The quote on `on:` matters: YAML 1.1 parses bare `on:` as the boolean True,
# which breaks every non-GitHub tool that reads this file. Chapter 05.
"on":
  # ── 1. push ────────────────────────────────────────────────────────────────
  # Fires on a push to a branch or a tag.
  push:
    # `branches` filters on the branch being pushed TO. A push to feature/x does
    # not match `branches: [main]`, even if it will merge into main tomorrow.
    branches: [main]
    # `tags` filters on tags. If you specify only tags, branch pushes do not run
    # this workflow; if you specify only branches, tag pushes do not. Specify
    # neither and both fire.
    # tags: ['v*']
    # Filter on which files changed. Cheapest way to stop docs-only commits from
    # burning a full CI run. Paths are NOT evaluated for tag pushes.
    # paths:
    #   - 'cicd-learn/**'
    #   - '.github/workflows/**'
    #   - '!**/*.md'          # negative patterns come after positive ones

  # ── 2. pull_request ────────────────────────────────────────────────────────
  # Fires on PR activity. This is the trigger that reads the workflow file from
  # the PR's own branch, which is why it works before the file reaches main.
  pull_request:
    # Which branches the PR is TARGETING. Default: all branches.
    branches: [main]
    # `types` limits which PR activities fire. Default when omitted:
    # [opened, synchronize, reopened]. Note that `closed` is NOT in the default.
    types: [opened, synchronize, reopened]

  # ── 3. schedule ────────────────────────────────────────────────────────────
  # POSIX cron, always UTC. Runs on the latest commit on the DEFAULT branch only.
  # Not 03:17 for the reason given in the comment.
  schedule:
    - cron: '17 3 * * *'

  # ── 4. workflow_dispatch ───────────────────────────────────────────────────
  # The "Run workflow" button. Works only once the file is on the default branch.
  # This is the escape hatch: re-run, or run on demand with different inputs.
  workflow_dispatch:
    inputs:
      greeting:
        description: 'What to print'
        required: false
        default: 'hello'
        type: string
      shout:
        description: 'Uppercase it'
        required: false
        default: false
        type: boolean
      target:
        description: 'Environment selector'
        required: false
        type: choice
        options: [staging, production]

permissions:
  contents: read

defaults:
  run:
    working-directory: cicd-learn

jobs:
  # Prints which trigger actually fired. This single job is the fastest way to
  # answer "why did / why didn't my workflow run?".
  which-event:
    name: Which event fired
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: Report the trigger
        run: |
          echo "event name : ${{ github.event_name }}"
          echo "ref name   : ${{ github.ref_name }}"
          echo "ref type   : ${{ github.ref_type }}"
          echo "actor      : ${{ github.actor }}"
          echo "run id     : ${{ github.run_id }}"
          echo "attempt    : ${{ github.run_attempt }}"
          echo "event path : $GITHUB_EVENT_PATH"
          echo "triggering schedule: ${{ github.event.schedule || 'not a schedule' }}"

      # Only true on pull_request events. Proves which branch is being targeted.
      - name: Pull request detail, if any
        run: |
          echo "PR number  : ${{ github.event.number || 'none' }}"
          echo "PR title   : ${{ github.event.pull_request.title || 'none' }}"
          echo "PR draft   : ${{ github.event.pull_request.draft }}"
          echo "base branch: ${{ github.event.pull_request.base.ref || 'none' }}"

      # Manual inputs. The `||` fallback covers "input was not supplied".
      - name: Manual inputs, if any
        run: |
          echo "greeting: ${{ inputs.greeting || 'not supplied' }}"
          echo "shout   : ${{ inputs.shout || false }}"
          echo "target  : ${{ inputs.target || 'not supplied' }}"

      # Gate one job on the event, so the Actions tab shows only relevant work.
      - name: PR-only step, skipped elsewhere
        if: github.event_name == 'pull_request'
        run: echo "this only runs for pull requests"

      - name: main-only step, skipped on PRs
        if: github.ref_name == 'main'
        run: echo "this only runs when the branch is main"

      # A job summary: rendered as a markdown table at the bottom of the run.
      - name: Write a run summary
        run: |
          {
            echo "### Trigger report"
            echo ""
            echo "| Field | Value |"
            echo "| ----- | ----- |"
            echo "| event | \`${{ github.event_name }}\` |"
            echo "| branch | \`${{ github.ref_name }}\` |"
            echo "| actor | @${{ github.actor }} |"
          } >> "$GITHUB_STEP_SUMMARY"
```

Only one job, deliberately. Its entire purpose is to answer "which button was
pressed?" — the question you will ask most often in your first month.

## 4. What I should see

### A `push` event (real run, `docs/_logs/ch06-triggers.log`)

`act` noise removed (the `🐳 docker exec` and `⭐ Run` scaffolding), real
command output kept:

```
Run Main Report the trigger
  | event name : push
  | ref name   : main
  | ref type   : branch
  | actor      : nektos/act
  | run id     : 1
  | attempt    : 1
  | event path : /var/run/act/workflow/event.json
  | triggering schedule: not a schedule
✅  Success - Main Report the trigger [58.868643ms]

Run Main Pull request detail, if any
  | PR number  : none
  | PR title   : none
  | PR draft   :
  | base branch: none
✅  Success - Main Pull request detail, if any [60.932517ms]

Run Main Manual inputs, if any
  | greeting: not supplied
  | shout   : false
  | target  : not supplied
✅  Success - Main Manual inputs, if any [57.763962ms]

Run Main main-only step, skipped on PRs
  | this only runs when the branch is main
✅  Success - Main main-only step, skipped on PRs [61.567868ms]

⚙  Summary - ### Trigger report

| Field | Value |
| ----- | ----- |
| event | `push` |
| branch | `main` |
| actor | @nektos/act |
```

Four things to notice:

1. **No `PR-only step` section at all.** The step had
   `if: github.event_name == 'pull_request'`, the event was `push`, so the step
   was skipped — and a skipped step produces no log section whatsoever, not even
   an empty one. On GitHub it appears greyed-out in the step list with nothing
   under it.
2. **`triggering schedule: not a schedule`** comes from
   `github.event.schedule || 'not a schedule'`. The `||` is what stops the log
   from showing an empty line, and it is the pattern to reuse everywhere.
3. **`actor : nektos/act`** is `act`'s default actor, not a person. On GitHub this
   is the GitHub username that pushed.
4. **`event path : /var/run/act/workflow/event.json`** is `act`'s path. On
   GitHub it is under `/runner/work/_temp/_github_workflow/`. The variable is the
   same; only the path differs.

### `workflow_dispatch` with no input (`docs/_logs/ch06-dispatch.log`)

```
| event name : workflow_dispatch
| ref name   : main
| triggering schedule: not a schedule
| greeting: hello
| shout   : false
| target  : not supplied
```

`greeting: hello` is the **`default:` from the `inputs:` block**, applied
because nobody supplied anything. `target  : not supplied` because a `choice`
input has no `default`, so it is genuinely unset. That is the whole difference
between a defaulted input and a choice input, shown in two adjacent lines.

### `workflow_dispatch` with inputs supplied (`docs/_logs/ch06-dispatch-inputs.log`)

Run locally with `--input greeting=bonjour --input shout=true --input target=staging`:

```
| event name : workflow_dispatch
| greeting: bonjour
| shout   : true
| target  : staging
```

On GitHub the same three values arrive from the form under the "Run workflow"
dropdown. That form is a GitHub-rendered UI element and cannot be reproduced
locally.

### `pull_request` (`docs/_logs/ch06-pullrequest.log`)

```
| event name : pull_request
| ref name   : %!f(<nil>)/merge
| ref type   :
| PR number  : none
| PR title   : none
| PR draft   :
| base branch: none
| greeting: not supplied

Run Main PR-only step, skipped elsewhere
  | this only runs for pull requests
✅  Success - Main PR-only step, skipped elsewhere [60.228181ms]
```

Read this carefully, because **half of it is a local-run artefact**:

- ✅ **Real and worth trusting:** `event name : pull_request` was correct, and the
  `if: github.event_name == 'pull_request'` step ran while the
  `if: github.ref_name == 'main'` step did not. Step-level conditions on the event
  name work locally.
- ❌ **`act`'s fabrication:** `%!f(<nil>)/merge` and every `none`. `act` has no
  real pull request, so it synthesises an event payload with no
  `pull_request` object in it. On GitHub you get `refs/pull/42/merge` and a
  populated `github.event.pull_request`.

If you copy the `none` values into your notes as expected output, you will be
wrong on GitHub. The rule: **trust the event name and the step conditions, never
trust the payload values from a local `act` run.**

### What local `act` does *not* check: filters (`docs/_logs/ch06-filter-ignored.log`)

This run used a `push` event payload with `ref: refs/heads/feature-x` — a branch
the workflow explicitly does not listen to (`branches: [main]`):

```
⭐ Run Main Report the trigger
  | event name : push
  | ref name   : feature-x
  | ref type   : branch
✅  Success - Main Report the trigger [66.708399ms]
...
⭐ Run Main Complete job
🏁  Job succeeded
```

**The run succeeded.** `act` did not reject a push to `feature-x` against
`branches: [main]`, and it does not evaluate `tags:` or `paths:` either. It
started the job anyway.

Meanwhile the step `if: github.ref_name == 'main'` **was** skipped — there is no
`Run Main main-only step` line anywhere in that log.

So, precisely:

| Thing | Enforced by local `act`? |
| ----- | ------------------------ |
| `github.event_name` value | Yes |
| Step-level `if:` conditions | Yes |
| Job-level `if:` conditions | Yes |
| `branches:` / `tags:` / `paths:` event filters | **No** |

A green local run therefore proves nothing about whether your filters match.
Filter behaviour has to be verified on GitHub, in the Actions tab, by pushing a
commit to a branch you expect to be ignored and confirming no run appears.

### `[read-only example]` — what GitHub shows, which cannot be run locally

The following is documented behaviour from the workflow-syntax reference, not
measured here:

```
Actions tab
└─ Events and triggers demo
   ├─ push            Run main by @octocat  (which-event ✓  18s)
   ├─ pull_request    PR #42: add the run report  (which-event ✓  22s)
   ├─ workflow_dispatch  Run by @octocat (which-event ✓  16s)
   └─ schedule        Cron by @github-actions  (which-event ✓  17s)
```

The "Run workflow" button and its input form, the "No workflow runs found" empty
state, and the cron-driven run at 03:17 UTC are all GitHub-rendered behaviours.
`act` has no Actions tab and no clock.

## 5. When to use it and when NOT to

**Reach for `push` when:**

- The check must be trustworthy on the branch people work on. `push: branches:
  [main]` is the last line of defence before bad code lands.
- You deploy from tags and want one trigger for both shapes. Specify **neither**
  `branches` nor `tags` and both fire.

**Reach for `pull_request` when:**

- You want the check *before* merge, on code nobody has merged yet. This is the
  reason branch protection exists (chapter 34).
- You use `paths:` to skip docs-only PRs. It saves real money and real minutes.

**Reach for `schedule` when:**

- You check for dependency drift overnight, so the failure is discovered in the
  morning rather than by a user.
- You do housekeeping: prune stale branches, rebuild a stale index, rotate logs.

**Reach for `workflow_dispatch` when:**

- You need a manual re-run. It is also what makes chapter 48's "re-run failed
  jobs" and chapter 45's manual release possible.
- You want a deploy that a human starts. This is the *simplest* approval
  mechanism that exists, and it beats inventing a CI service for the job.

**Do NOT reach for these when:**

- **One workflow trying to be everything.** A workflow with `push`, `pull_request`
  *and* `schedule` on the same jobs runs every check three times for most
  commits. Split them: `ci.yml` on PRs, `nightly.yml` on a cron, `deploy.yml` on
  a tag. Chapter 15 shows the shape.
- **A very wide `schedule`.** `schedule: - cron: '* * * * *'` does not run once a
  minute. Scheduled runs are queued and delayed during busy periods, and missed
  schedules are **not** backfilled. A workflow that must run on time belongs on a
  real scheduler, not on a cron in a CI file.
- **`pull_request_target` for "I need the workflow file and the secrets".** That
  event runs the workflow file from the **base** branch with a token scoped to a
  write-capable context, against code written by anyone who can open a PR. It is
  the mechanism behind real repository compromises. Chapter 25 covers it, and the
  rule is: never check out the PR's code in it.
- **Filtering by path when your path patterns are narrower than your repo.** A
  `paths:` filter that misses `.github/workflows/**` means a commit that changes
  only the CI will not run the CI. You will find this out during the incident,
  not before it.
- **`types:` on `push`.** `push` has no activity types. `types` is only valid for
  events that have them.

## 6. Common mistakes

- **Unquoted `on:`.** Works on GitHub, breaks every other YAML tool. Chapter 05.
  Every file in this course writes `"on":`.
- **`push: branches: [main]` plus `tags: ['v*']`, expecting both.** Adding a
  `tags` filter **removes** branch pushes. Symptom: you add a release trigger and
  the next normal push does nothing. Fix: omit both filters, or write two
  separate workflows.
- **`branches` and `branches-ignore` together.** Rejected by the workflow parser
  with a message naming both keys. Same for `paths` and `paths-ignore`.
- **Negative path patterns before positive ones.** `!`**`'**docs/**'` before
  `'cicd-learn/**'` is silently ignored — no error, just a filter that does not
  filter. Positive patterns first, always.
- **Expecting `paths:` to apply to a tag push.** It does not, and no warning is
  given.
- **Filtering `branches: [main]` on a PR workflow instead of using
  `github.base_ref` in a step condition.** On a PR, `github.ref` is
  `refs/pull/N/merge`, so `github.ref == 'refs/heads/main'` is false and your step
  silently never runs.
- **Adding a new workflow file on a feature branch and pushing to that branch.**
  Nothing runs. The file has to reach the default branch before `push` can see
  it. Symptom: "the workflow works once I merge it but not before". Fix: open a
  PR, and let `pull_request` run it — that event reads the file from your branch.
- **Clicking "Run workflow" and getting a 404 for the branch dropdown.** The file
  is not on the default branch. Same root cause as above.
- **A `schedule` that never fires.** Almost always one of: not on the default
  branch; the file was added after the last scheduled run, so you are waiting for
  the next cron tick; or the cron is not what you think (it is UTC, always).
- **Unquoted cron.** `- cron: 17 3 * * *` is fragile and can be misparsed. Use
  `- cron: '17 3 * * *'`. Chapter 05.
- **`type: choice` with a `default:`.** Not allowed, and the input is unset if
  nobody picks — which is why `target  : not supplied` above.
- **Reading `github.event.inputs.shout` as a boolean.** It is the string
  `"true"`. `if: github.event.inputs.shout == true` fails; `inputs.shout` is the
  boolean you want.
- **Believing a green local `act` run means your filter matches.** It does not
  check filters at all. Proven above with `ref: refs/heads/feature-x`.

## 7. Try it yourself

**Exercise: build a triage workflow, then make it lie to you.**

The fastest way to stop guessing about triggers is to have the workflow tell you
what fired. This chapter's workflow already does; make it yours.

1. Create `.github/workflows/what-triggered-me.yml` from the `which-event` job in
   section 3, with a deliberately narrow trigger so you have something to
   discover:

   ```yaml
   name: What triggered me
   "on":
     push:
       branches: [main]
       paths:
         - 'cicd-learn/**'
         - '!**/*.md'
   permissions:
     contents: read
   jobs:
     report:
       runs-on: ubuntu-24.04
       steps:
         - uses: actions/checkout@v7
         - name: Report
           run: |
             echo "event: ${{ github.event_name }}"
             echo "ref  : ${{ github.ref }}"
             echo "name : ${{ github.ref_name }}"
             echo "actor: ${{ github.actor }}"
   ```

2. Push a commit that only touches `README.md`. **Expected: nothing runs.** The
   only positive pattern that matched is negated away. Confirm in the Actions
   tab that there is no new run — that absence *is* the result.

3. Push a commit that touches `cicd-learn/src/greet.js`. **Expected: one run**,
   reporting `event: push`, `ref: refs/heads/main`, `name: main`.

4. Push a commit that touches **only** `.github/workflows/what-triggered-me.yml`.
   **Expected: nothing runs**, and that is a bug in your filter: you have not
   included `.github/workflows/**`. Fix it, and never write that omission again.

5. Now the local experiment, which is worth doing precisely because it shows the
   blind spot. `act` has no `--ref` flag, but it accepts an event payload, so
   point it at a branch your filter excludes:

   ```bash
   cat > /tmp/evt-feature.json <<'JSON'
   {"ref":"refs/heads/feature-x","repository":{"full_name":"local/cicd-docs",
   "name":"cicd-docs","owner":{"login":"local"}},"actor":"local","action":"opened",
   "head_commit":{"id":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","message":"probe",
   "timestamp":"2026-10-08T12:00:00Z","author":{"name":"local",
   "email":"local@example.invalid"}},"commits":[]}
   JSON
   ./scripts/run-workflow.sh .github/workflows/what-triggered-me.yml report push
   act push -W .github/workflows/what-triggered-me.yml -P ubuntu-24.04=<image> \
       --pull=false -j report -e /tmp/evt-feature.json
   ```

   Locally the job runs either way, and with the event payload it prints
   `ref: refs/heads/feature-x`. On GitHub: no run at all. Same file, same ref,
   opposite outcome. That is exactly which half of trigger behaviour your local
   tool cannot check.

**Hint:** you will never get a real `pull_request` payload from `act` — its
synthetic event has no `pull_request` object, so every field reads `none`. That
`none` is the tell that the payload was invented. Assert on the *shape* of what
your logic needs locally, and confirm the values on the hosted run.

**Break it on purpose, three ways, and read each error message:**

1. Add `branches-ignore: [main]` beside `branches: [main]`. GitHub rejects the
   file; `python3 scripts/validate-workflows.py` will not, because it is
   syntactically valid YAML. That gap is why `actionlint` exists (chapter 05).
2. Change `types: [opened, synchronize, reopened]` to `types: [opened, closed]`.
   Push a second commit to the PR. **Expected: nothing runs** — `synchronize`
   is gone, so new commits to the PR no longer trigger. Put it back.
3. Delete `workflow_dispatch:` entirely and try to re-run from the Actions tab.
   The button is gone, because the button's existence *is* the trigger.

## 8. Next

You now control *when* a workflow starts. The next question is unavoidable: it
started, and it needs a computer to run on. Which computer, with what already
installed, and why the label you pick is a promise to your future self.

→ [07 — Runners](07-runners.md)