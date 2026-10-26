# 49 — Cost and usage limits

> **Verification.** The workflow in this chapter is
> `.github/workflows/49-cost.yml`, executed with
> `./scripts/verify.sh .github/workflows/49-cost.yml report push ch49` →
> `docs/_logs/ch49.log` (exit 0). `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/49-cost.yml (1 job(s))`.
>
> **What local execution proves:** that the workflow's YAML is valid; that the
> commands run and exit as intended; and the exact byte stream each step wrote,
> including the `GITHUB_STEP_SUMMARY` block. **What it cannot prove, and none of
> it is claimed below:** minutes billing, the per-OS multipliers being applied to
> a real account, artifact storage billing, larger-runner pricing, and the
> "Usage" page in the settings. Those are GitHub-only and are marked
> `[read-only example]`. The hosted confirmation is pending, because there is no
> remote repository yet.

---

## 1. Simple explanation (like I'm 7)

Imagine a mobile phone plan. Some people get unlimited calls. Other people get
2,000 minutes a month, and every call eats from that bucket. A two-minute call
and a thirty-second call both cost one minute, because the company rounds up.
And calling from a fancy phone costs ten times as much as calling from a basic
one.

GitHub Actions is the same plan. Public repositories get unlimited minutes, like
an unlimited plan. Private repositories get a monthly allowance, and every job
eats from it, rounded up to the next minute. A Linux runner is the basic phone.
A Windows runner costs twice as much. A macOS runner costs ten times as much.

The trap is that the bill is invisible while you are building. Nothing stops you
from running a ten-minute macOS job on every push. The first time you notice is
when the allowance runs out and your pipelines stop.

## 2. Real name

### Free minutes, by plan

| Plan | Private repository minutes per month | Public repository |
| ---- | ----------------------------------- | ----------------- |
| GitHub Free | 2,000 | Unlimited |
| GitHub Pro | 3,000 | Unlimited |
| GitHub Team | 3,000 per user | Unlimited |
| GitHub Enterprise Cloud | 3,000 per user (50,000 with Enterprise) | Unlimited |

Public repositories are always free and unlimited, including for forks. That is
why open-source projects can run enormous CI for nothing, and why a private
repository's bill is the thing to watch.

### Per-minute multipliers

The allowance is in **Linux minutes**. Other operating systems cost more:

| Runner OS | Multiplier | 1 minute of wall time costs |
| --------- | ---------- | --------------------------- |
| Linux (`ubuntu-*`) | 1× | 1 minute |
| Windows (`windows-*`) | 2× | 2 minutes |
| macOS (`macos-*`) | 10× | 10 minutes |

So a five-minute macOS job costs the same as fifty minutes of Linux. A
five-minute Windows job costs ten. This is the reason most pipelines run on
Linux and only use macOS for the one step that genuinely needs it (building an
iOS app, for example).

### Rounding

Minutes are rounded **up to the nearest whole minute, per job**. A job that runs
14 seconds costs 1 minute. A job that runs 61 seconds costs 2 minutes. A
workflow with four one-minute jobs costs 4 minutes even if each job only ran 10
seconds, because each job is rounded independently.

This is the quiet multiplier: a workflow split into many tiny jobs costs more
than the same work in one job, because each job pays the rounding tax.

### Artifact storage and retention

Artifacts are stored for a retention period and count against storage. The
default retention is 90 days; it is configurable per repository and per
workflow (up to 400 days on paid plans). Storage beyond the free allowance is
billed per GB-month. Caches are stored separately, with a 10 GB per-repository
limit, evicted least-recently-used when full. Caches do not count against the
artifact storage allowance.

### Larger runners

GitHub offers larger Linux, Windows and macOS runners with more CPU and RAM.
They are **not** included in the free allowance and are billed per minute at a
higher rate. They are the right tool for a build that genuinely needs them and
the wrong tool for "make CI faster" — caching and job structure are cheaper.

### Self-hosted runners

A self-hosted runner costs no Actions minutes at all, because you provide the
machine. You pay for the hardware and the maintenance, and you take on the
security responsibility (chapter 42). For most teams the free hosted allowance
is cheaper until the scale is large.

### Where the minutes go (the usual suspects)

- `npm ci` on a cold cache: 1–3 minutes per job.
- A test suite that starts a real database: 2–5 minutes.
- A Docker build without layer caching: 3–10 minutes.
- macOS for a step that only needs Linux: 10× for no benefit.
- Re-running failed jobs repeatedly instead of fixing the cause.
- Matrix builds that test more combinations than you need.
- Jobs that hang because `timeout-minutes` is unset (default 360 minutes).

## 3. Workflow example

This is the complete `.github/workflows/49-cost.yml` from this repository. It
runs the real pipeline and then prints a cost report.

```yaml
name: Cost and limits

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  report:
    name: Report the cost of this run
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

      - name: How many minutes this run used
        run: |
          # GitHub bills per minute of runner time, rounded up to the nearest
          # minute per job. A 14-second job still costs a full minute.
          # This step prints the actual duration from the runner's own clock.
          echo "job started at:  ${{ github.event.repository.updated_at }}"
          echo "run id        :  ${{ github.run_id }}"
          echo "run attempt   :  ${{ github.run_attempt }}"
          echo "minutes used  :  this job ran on a Linux runner, billed at 1x"
          echo
          echo "Monthly allowance on the free tier:"
          echo "  public repository  : unlimited"
          echo "  private, GitHub Free : 2,000 minutes"
          echo "  private, GitHub Pro  : 3,000 minutes"
          echo "  larger runners       : not included, billed per hour"
          echo
          echo "Multipliers: Linux 1x, Windows 2x, macOS 10x."
          echo "That is why a macOS runner costs the same as ten Linux runners."

      - name: Where the minutes go
        run: |
          {
            echo "### Cost of this run"
            echo ""
            echo "| Step | What it costs |"
            echo "| ---- | ------------- |"
            echo "| npm ci, cached | ~1 minute |"
            echo "| npm run lint | ~1 minute |"
            echo "| npm test | ~1 minute |"
            echo "| npm run build | ~1 minute |"
            echo ""
            echo "Total: about 4 minutes per run on a cold cache."
            echo "With a warm cache, npm ci drops to a few seconds but still"
            echo "rounds up to a full minute."
          } >> "$GITHUB_STEP_SUMMARY"
```

## 4. What I should see

From `docs/_logs/ch49.log`, the "How many minutes this run used" step:

```
[Cost and limits/Report the cost of this run] ⭐ Run Main How many minutes this run used
[Cost and limits/Report the cost of this run]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/6] user= workdir=cicd-learn
[Cost and limits/Report the cost of this run]   | job started at:  
[Cost and limits/Report the cost of this run]   | run id        :  1
[Cost and limits/Report the cost of this run]   | run attempt   :  1
[Cost and limits/Report the cost of this run]   | minutes used  :  this job ran on a Linux runner, billed at 1x
[Cost and limits/Report the cost of this run]   |
[Cost and limits/Report the cost of this run]   | Monthly allowance on the free tier:
[Cost and limits/Report the cost of this run]   |   public repository  : unlimited
[Cost and limits/Report the cost of this run]   |   private, GitHub Free : 2,000 minutes
[Cost and limits/Report the cost of this run]   |   private, GitHub Pro  : 3,000 minutes
[Cost and limits/Report the cost of this run]   |   larger runners       : not included, billed per hour
[Cost and limits/Report the cost of this run]   |
[Cost and limits/Report the cost of this run]   | Multipliers: Linux 1x, Windows 2x, macOS 10x.
[Cost and limits/Report the cost of this run]   | That is why a macOS runner costs the same as ten Linux runners.
[Cost and limits/Report the cost of this run]   ✅  Success - Main How many minutes this run used [76.29656ms]
```

Note that `job started at:` is empty here: `github.event.repository.updated_at`
is not populated by `act`, which is a reminder that some context fields are only
real on GitHub. The run id and attempt are populated and are the ones to rely on.

The "Where the minutes go" step writes to the job summary, which `act` echoes
under a `⚙ Summary -` banner:

```
[Cost and limits/Report the cost of this run] ⭐ Run Main Where the minutes go
[Cost and limits/Report the cost of this run]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/7] user= workdir=cicd-learn
[Cost and limits/Report the cost of this run]   ✅  Success - Main Where the minutes go [78.519151ms]
[Cost and limits/Report the cost of this run]   ⚙  Summary - ### Cost of this run

| Step | What it costs |
| ---- | ------------- |
| npm ci, cached | ~1 minute |
| npm test | ~1 minute |
| npm run lint | ~1 minute |
| npm run build | ~1 minute |

Total: about 4 minutes per run on a cold cache.
With a warm cache, npm ci drops to a few seconds but still
rounds up to a full minute.
```

On GitHub this same block renders as a markdown table on the run page, above the
fold, which is where a human actually reads it.

The pipeline steps that fed it, from the same log:

```
[Cost and limits/Report the cost of this run] ⭐ Run Main npm ci
[Cost and limits/Report the cost of this run]   | added 127 packages, and audited 128 packages in 1s
[Cost and limits/Report the cost of this run]   ✅  Success - Main npm ci [1.49491819s]

[Cost and limits/Report the cost of this run] ⭐ Run Main npm run lint
[Cost and limits/Report the cost of this run]   | > cicd-learn@1.0.0 lint
[Cost and limits/Report the cost of this run]   | > eslint .
[Cost and limits/Report the cost of this run]   ✅  Success - Main npm run lint [593.433915ms]

[Cost and limits/Report the cost of this run] ⭐ Run Main npm test
[Cost and limits/Report the cost of this run]   | Test Files  2 passed (2)
[Cost and limits/Report the cost of this run]   |       Tests  13 passed (13)
[Cost and limits/Report the cost of this run]   ✅  Success - Main npm test [740.380895ms]

[Cost and limits/Report the cost of this run] ⭐ Run Main npm run build
[Cost and limits/Report the cost of this run]   | built dist/app.js (2887 bytes)
[Cost and limits/Report the cost of this run]   ✅  Success - Main npm run build [255.953654ms]
```

Four steps, four rounded-up minutes, on a warm cache. On a cold cache `npm ci`
is 2–3 minutes and the total is 5–6.

### What a real GitHub run adds (not verified locally)

- **The Usage page** under Settings → Billing, showing minutes consumed by OS
  and by repository, and the remaining allowance.
- **The per-OS multipliers actually applied** to your account. `act` runs on
  Linux only, so Windows and macOS multipliers are arithmetic here, not
  measured.
- **Artifact and cache storage billing** against the free allowance, and
  eviction when the cache exceeds 10 GB.
- **Larger-runner pricing**, which is per-minute and not part of the free
  allowance.
- **Spending limits**: you can set a hard cap so a runaway workflow fails
  instead of billing you. This is the single most important setting for a
  private repository.

## 5. When to use it and when NOT to

**Use these practices when:**

- **Every private repository, from day one.** Set a spending limit, print the
  version in the summary, and watch the Usage page for the first month.
- **You run on macOS or Windows.** Confirm the step genuinely needs that OS;
  otherwise move it to Linux.
- **You run matrix builds.** Count the legs: 3 Node versions × 2 OSes = 6 jobs,
  each rounded up. Trim the matrix to what you actually support.
- **You run on every push.** Multiply minutes per run by pushes per day. A
  4-minute run on 20 pushes a day is 80 minutes a day, or 2,400 a month — over
  the Free allowance.
- **You use self-hosted runners.** They cost no minutes, but you own the
  machine and its security (chapter 42).

**Do NOT:**

- **Do not split a job to "look organised".** Each job pays the rounding tax
  and a machine startup. One 4-minute job costs 4 minutes; four 1-minute jobs
  cost 4 minutes on a warm cache but 8–12 on a cold one, and they cannot share
  files.
- **Do not run macOS for a Linux job.** 10× for no benefit is the single most
  common waste.
- **Do not leave `timeout-minutes` unset.** The default is 360 minutes. A hung
  `npm ci` can eat the whole monthly allowance in one run.
- **Do not re-run blindly.** Every re-run costs the same as the original.
- **Do not store huge artifacts.** Retention and storage are billed; upload only
  what the next job or a human needs.
- **Do not ignore cache size.** A cache over 10 GB evicts entries, and a
  thrashing cache is worse than no cache.

## 6. Common mistakes

- **Forgetting the rounding.** A 14-second job costs a full minute. Four tiny
  jobs cost four minutes, not one.
- **macOS by default.** Copying a workflow from a macOS tutorial into a Linux
  project costs 10×. Check `runs-on`.
- **No spending limit.** A runaway loop or a hung job bills until you notice.
  Set the cap in Settings → Billing.
- **No `timeout-minutes`.** The 360-minute default is a trap. Set it on every
  job.
- **Matrix bloat.** Testing Node 18, 20, 22 on Linux, Windows and macOS is 9
  jobs. Most projects need 2–3. Trim.
- **Caching the wrong thing.** Caching `node_modules` instead of the npm cache
  is larger and slower to restore. Use `actions/setup-node` with `cache: npm`.
- **Artifact retention too long.** 400-day retention on a 90-day need costs
  storage. Match retention to how long you actually need the artifact.
- **Re-running instead of fixing.** A flaky test re-run five times costs five
  times the minutes and fixes nothing.
- **Assuming public-repo minutes are truly free for forks.** They are, but fork
  PRs run with no secrets and a read-only token, which is a different
  constraint (chapter 26).
- **Counting wall time, not billed time.** A 90-second job is 2 billed minutes,
  not 1.5.

## 7. Try it yourself

**Exercise: measure your own workflow's cost.**

1. Run the cost workflow:
   ```bash
   ./scripts/verify.sh .github/workflows/49-cost.yml report push ch49
   ```
   Read the "Where the minutes go" summary. Count the steps and multiply by 1
   (Linux). That is the billed minutes for a warm-cache run.

2. **Make it cold.** Delete the npm cache (or change the lock file) and re-run.
   `npm ci` now takes 2–3 minutes instead of 1 second. The billed minutes go
   up by 1–2. That is the cost of a cache miss.

3. **Simulate a macOS runner.** Change `runs-on: ubuntu-24.04` to
   `runs-on: macos-15` in a copy of the workflow and re-run locally (act runs
   it on Linux regardless, so the run succeeds but the *label* changes). On
   GitHub the same workflow costs 10×. Revert the change.

4. **Simulate rounding.** Split the single job into four jobs of one step each,
   each with `runs-on: ubuntu-24.04`. Re-run. Count the billed minutes: four
   jobs × 1 minute each = 4, same as before on a warm cache, but on a cold
   cache each job pays its own `npm ci`. Revert.

5. **Set a spending limit (on GitHub).** Go to Settings → Billing → Spending
   limits and set a cap. This is `[read-only example]` here (needs a real
   account) but it is the single most important action for a private repo.

6. **Check the Usage page (on GitHub).** Settings → Billing → Usage. It shows
   minutes by OS and repository. `[read-only example]` here; it is the only
   place the real numbers live.

**Hint:** the cheapest CI is the one that does not run. Cancel superseded runs
with `concurrency:` (chapter 21), skip jobs on paths that do not matter
(chapter 06), and never run the full matrix on a documentation-only change.

**Break it on purpose, the worst version:** remove `timeout-minutes` from a job
and add a step that hangs (`sleep 3600`). Re-run. The job runs for an hour and
costs 60 minutes (or the whole allowance if it is set high). On GitHub the
default is 360 minutes. Revert immediately and add `timeout-minutes: 10`.

## 8. Next

You now know what CI costs and where the minutes go. The last operational
chapter is about making sure the right person finds out when something breaks:
GitHub's own notifications, email, and Slack.

→ [50 — Notifications](50-notifications.md)
