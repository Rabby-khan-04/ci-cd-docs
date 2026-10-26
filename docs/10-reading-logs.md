# 10 — Reading logs

> **Verification.** The workflow in this chapter is
> `.github/workflows/10-reading-logs.yml`, run with
> `scripts/verify.sh .github/workflows/10-reading-logs.yml reading push ch10`
> (`act` 0.2.89, exit 0) → `docs/_logs/ch10.log`. Two other saved logs from
> earlier runs are quoted as well, and are labelled where they come from:
> `docs/_logs/ch12-lint.log` and `docs/_logs/ch09-actions.log`.
>
> **What the local run proves:** that the workflow's YAML is valid; that the
> commands run and exit as intended; and — this is the important part — **the
> exact byte stream each step wrote to stdout**. `::group::`, `::endgroup::`,
> `::warning` and `::error` are just lines of text on stdout, so their emission is
> fully reproducible locally. `act` renders them with its own prefixes (`❓`,
> `🚧`, `❗`) and adds the `⚙ Summary -` banner for the job summary.
>
> **What the local run cannot prove, and none of it is claimed below:**
>
> - **The Actions tab.** `act` has no UI. Group collapsing, the Annotations
>   filter, the check-run list, the "Re-run failed jobs" button, the job summary
>   pane and the PR diff view are all GitHub-rendered. `act` prints
>   `::group::` as a visible line; GitHub collapses it to one clickable row.
> - **Annotations rendering.** An annotation with `file=` and `line=` becomes a
>   coloured marker in the pull request diff on GitHub. That transformation is
>   server-side. What you see locally is the *command line*, not the annotation.
> - **The hosted runner toolchain.** The summary in the chapter's own log reports
>   `Node | v24.21.0`, which is this repository's local container, **not** a
>   GitHub-hosted runner. A workflow with no `actions/setup-node` step reports
>   whatever the runner image happens to carry, and that is the single most
>   misread number in a CI log.
> - **Job isolation** (chapter 08) and **event filters** (chapter 06).
> - **Minutes billing, re-run behaviour, and any secret masking.**
>
> Where this chapter shows GitHub's own rendering, it is marked
> `[read-only example]` and sourced. The hosted confirmation is pending, because
> there is no remote repository yet.

---

## 1. Simple explanation (like I'm 7)

The machine does the work and writes down everything it saw, line by line. That
list is the **log**. Reading it is the job.

Three tricks make a huge log short enough to read.

**First: you do not read it from the top.** The Actions tab shows the whole run
as a list of steps, collapsed. One step is red. You click the red one. You never
read the other eleven.

**Second: you can fold away the boring part.** A step can print "here comes a lot
of noise", print the noise, then print "noise over". The tab turns all of it into
one line you can click open when you need it. So a 400-line `npm ci` log becomes
one row, and the three lines you actually care about stay where your eyes are.

**Third: you can shout, in a way the page understands.** A tool that finds a
problem can say "this is a problem, in *that* file, on *that* line", and the page
draws a coloured mark next to that line in your pull request. A person reading
the log sees a wall of text; a person looking at the pull request sees the exact
line that is wrong, before they even open anything.

And underneath all of it is one rule that decides everything: **did the command
succeed?** A command that ends with "0" succeeded. Anything else failed, and the
number it ended with is the reason. Every green tick and every red cross in
GitHub is a number from one command.

## 2. Real name

### The shape of a run

```
Run page        "CI"  ·  commit abc1234  ·  push by @octocat
 ├─ job  lint            ✓ completed in 21s
 ├─ job  test            ✗ completed in 48s        <- the interesting one
 │   ├─ step  Set up job            ✓
 │   ├─ step  actions/checkout@v7   ✓
 │   ├─ step  Set up Node.js        ✓
 │   ├─ step  npm ci                ✓
 │   └─ step  npm test              ✗             <- click this
 └─ job  summary          ✓ completed in 12s
Job summary (bottom of the run page, markdown you wrote)
```

Reading is a **filtering** problem: collapse everything, open only the failure,
then read the last ten lines before the error message. The error is always at
the bottom. The top of a step's output is setup; the bottom is the verdict.

### Exit codes

The single number that decides pass or fail. The runner runs the step's command,
takes its exit code, and:

- **`0` — success.** Green tick.
- **anything else — failure.** Red cross, and GitHub prints
  `Error: Process completed with exit code N.`

The numbers you will actually meet:

| Code | Means |
| ---- | ----- |
| `0` | Success |
| `1` | Generic failure: your command decided to fail. `npm test` with a failing test, or your own `exit 1` |
| `2` | Shell misuse. `ls nonexistent` exits 2. Bash uses it for a syntax error too |
| `126` | Found, but not executable — missing `chmod +x` on a script |
| `127` | Command not found. Also: the runner could not start the shell at all |
| `128 + N` | Killed by signal N. `137` = SIGKILL, which is what an OOM kill and a timeout kill both look like |

`127` deserves its own line because it is the one in this repository's logs. The
runner could not `chdir` into the working directory, so `bash` never started, so
there is no bash exit code — only the runner's own 127. The full text is in
chapter 08's section 4 and in `docs/_logs/ch08-reader.log`.

**The most common CI mistake here:** a command that fails but whose failure you
never look at. A pipeline step is a **gate**, not a reporter, and the moment you
capture output and carry on the gate is gone:

```bash
# WRONG: the step passes unless eslint happens to also fail
npx eslint . --format json > report.json
echo "lint done"

# RIGHT: let the exit code through
npx eslint .

# ALSO RIGHT: capture for a report, then re-raise the code
npx eslint . --format json > report.json || status=$?
node scripts/lint-annotations.mjs report.json
exit "${status:-0}"
```

### Workflow commands: writing to the log *and* to the UI

The runner watches stdout for lines beginning with `::`. A line like

```
::error file=src/sum.js,line=2,title=Unused function::sum is exported but never called
```

is one line on two levels. Before the second `::` are the **command** and its
**properties**; after it is the **message**. The runner turns that line into
something more than text.

The full set that matters:

| Command | What it does |
| ------- | ------------ |
| `::group::Title` … `::endgroup::` | Everything between them collapses into one clickable row |
| `::error …::msg` | Red annotation, in the PR diff and the Annotations filter |
| `::warning …::msg` | Yellow annotation |
| `::notice …::msg` | Blue annotation |
| `::debug …::msg` | Only with `ACTIONS_STEP_DEBUG=true` |
| `::add-matcher::file.json` | Register a problem-matcher so raw tool output gets annotated automatically |
| `::save-state name=…::v` | Runner-side state between a step's main and post phases. Distinct from `$GITHUB_ENV` |

Properties available on the annotation commands: `title`, `file`, `col`,
`endColumn`, `line`, `endLine`. `title` is the tooltip, so it is worth writing.

An **unclosed** group swallows everything after it until the step ends, so
`::endgroup::` must be unconditional — never inside an `if`. Group the
expected-noisy output and leave the verdict ungrouped: you want the interesting
line visible without a click.

**Escaping.** The message cannot contain a raw newline, `::` or `,`, or it breaks
the parser — and a message you did not sanitise is a **log-injection** hole,
because someone who can make your tool print text can inject a command. This
repository does it properly in
`cicd-learn/scripts/lint-annotations.mjs`:

```js
const escape = (s) => String(s)
  .replace(/\r/g, '%0D')
  .replace(/\n/g, '%0A')
  // `::` starts a new command; escaping the colons stops message injection.
  .replace(/::/g, '%3A%3A')
  // Commas separate the properties, so one inside a value would shift them.
  .replace(/,/g, '%2C');
```

and then:

```js
console.log(`::${level} ${props}::${escape(m.message)}`);
```

Do this in anything you write. It is thirty lines and it is the difference
between a tool and a vulnerability.

### `GITHUB_STEP_SUMMARY` — the one screen that matters

Every `run:` step can append markdown to a file. The runner collects it and
renders it as a block on the run page and on the job page.

```bash
{
  echo "## Log reading demo"
  echo ""
  echo "| Field | Value |"
  echo "| ----- | ----- |"
  echo "| Node | $(node --version) |"
} >> "$GITHUB_STEP_SUMMARY"
```

Three rules:

1. **It is a file, not a variable.** Quote it: `>> "$GITHUB_STEP_SUMMARY"`. It is
   a path, and unquoted paths with spaces break.
2. **It is per job, and every step appends to the same one.** Several steps can
   each add a section; they concatenate in step order.
3. **It is markdown, and it renders as markdown.** Headings, tables, code fences.
   It is the only place in the log area where formatting survives.

What belongs in it: the version you tested with, the counts that decided the
result, the one number a human would want. What does not: the entire test output.

### The Actions tab, and the CLI, for reading

```
[read-only example] GitHub-rendered, from docs.github.com/en/actions
Actions tab:  repository -> Actions -> click the run -> click the job
              -> click the step name to expand or collapse it
              -> top-right "Annotations" filter to see only annotated lines
              -> "Re-run failed jobs" button, which keeps successful steps' logs
gh CLI:       gh run list --workflow ci.yml --limit 5
              gh run view <run-id> --log-failed     # only failing steps
              gh run view <run-id> --log            # everything
              gh run download <run-id>              # artifacts
```

`--log-failed` is the flag that turns this chapter into a two-minute ritual.
It needs a GitHub remote and authentication, and **this repository has no remote
yet**, so it is `[read-only example]` here. The free alternative you can run
today is the one this course has been using all along:

```bash
./scripts/verify.sh .github/workflows/10-reading-logs.yml reading push ch10
# the log lands in docs/_logs/ch10.log and you can grep it
grep -n 'Failure' docs/_logs/ch10.log
```

## 3. Workflow example

This is the real file, `.github/workflows/10-reading-logs.yml`:

```yaml
name: Reading logs

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
  reading:
    name: Log reading features
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7

      # ── Writing to the log ────────────────────────────────────────────────
      - name: Ordinary output
        run: |
          echo "this goes to the log as normal output"

      # Grouping. The UI collapses a group into one clickable line. Use it for
      # verbose output you want available but not staring at you.
      - name: Grouped output
        run: |
          {
            echo "::group::Installing dependencies"
            echo "resolved 128 packages"
            echo "audited 128 packages"
            echo "::endgroup::"
            echo "and here is the important part, ungrouped"
          }

      # ── Annotations: how warnings and errors appear in the PR diff ─────────
      # The UI turns these into coloured annotations next to the file and line
      # that produced them. `::error file=...,line=...::message`
      - name: Emit annotations
        run: |
          echo "::warning file=src/greet.js,line=4,title=Empty name::Name is allowed to be empty here"
          echo "::error file=src/sum.js,line=2,title=Unused function::sum is exported but never called"

      # ── Writing a run summary ─────────────────────────────────────────────
      # Rendered as markdown under the run. This is the right place for the
      # "what happened, in one screen" version of your results.
      - name: Write a run summary
        run: |
          {
            echo "## Log reading demo"
            echo ""
            echo "| Field | Value |"
            echo "| ----- | ----- |"
            echo "| Node | $(node --version) |"
            echo "| Branch | \`${{ github.ref_name }}\` |"
            echo "| Commit | \`${GITHUB_SHA::8}\` |"
            echo ""
            echo "This block is markdown, so it renders in the run summary."
          } >> "$GITHUB_STEP_SUMMARY"

      # ── Exit codes, demonstrated ──────────────────────────────────────────
      - name: Exit code 1 is a plain failure
        if: false          # disabled by default; uncomment to see it fail
        run: exit 1

      - name: Exit code 0 is success
        run: exit 0
```

Note what this file does *not* have: no `actions/setup-node`. That is why the
Node version it prints is the image's, which is the trap the last section of this
chapter is about.

## 4. What I should see

All of this is from `docs/_logs/ch10.log`, exit status 0. `act`'s emoji and its
`🐳`/`⭐` scaffolding are removed; the stdout of each step is verbatim.

### Ordinary output, and grouped output

```
⭐ Run Main Ordinary output
  | this goes to the log as normal output
✅  Success - Main Ordinary output [83.430952ms]

⭐ Run Main Grouped output
  ❓  ::group::Installing dependencies
  | resolved 128 packages
  | audited 128 packages
  ❓  ::endgroup::
  | and here is the important part, ungrouped
✅  Success - Main Grouped output [64.207547ms]
```

`echo` writes to stdout, stdout is the log, and `Success` means exit code 0. In
the second block all four command lines are there byte for byte, because `echo`
printed them. What you cannot see here is the *collapsing*: on GitHub the three
lines between `::group::` and `::endgroup::` are hidden behind one clickable row
titled `Installing dependencies`. `act` prints `❓ ::group::…` because a terminal
cannot collapse anything. **The command is real; the folding is a UI feature.**

### Annotations

```
⭐ Run Main Emit annotations
  🚧  ::warning file=src/greet.js,line=4,title=Empty name::Name is allowed to be empty here
  ❗  ::error file=src/sum.js,line=2,title=Unused function::sum is exported but never called
✅  Success - Main Emit annotations [72.348111ms]
```

Two things to read here, one of them a trap.

**The step is green.** `Emit annotations` succeeded, and the job succeeded,
despite the step having printed the word `error`. An annotation is a **report, not
a verdict**. It changes nothing about exit codes. If you want a lint failure to
fail the build, `cicd-learn/scripts/lint-annotations.mjs` says so in a comment on
its last line:

```js
// Always exit 0. This step reports; the lint step's own exit code is the
// verdict. Deciding here as well would make a red lint look green.
```

That is the whole design, and it is the correct one: **report in one step, judge
in another.** Chapter 12 wires it to the real lint step.

**The trap: `file=src/sum.js` will not resolve here.** In this repository the
files are at `cicd-learn/src/sum.js`. The annotation names a path that does not
exist at the repository root, so on GitHub it would appear in the log's
Annotations filter but **not** as a marker in the pull request diff. Paths in
annotations must be relative to the **repository root**, which is exactly what
`lint-annotations.mjs` guarantees with:

```js
// Repo-relative paths. Absolute runner paths would be meaningless in the diff.
const root = `${process.cwd()}/`;
const rel = (p) => p.startsWith(root) ? p.slice(root.length) : p;
```

Note also that the step prints `::error file=…` but **not** a `::group::`, so
these two lines stay expanded in the tab. Annotations are worth leaving visible.

### The job summary

```
⭐ Run Main Write a run summary
  | ## Log reading demo
  |
  | Field | Value |
  | ----- | ----- |
  | Node | v24.21.0 |
  | Branch | `main` |
  | Commit | `f910ba9c` |
  |
  | This block is markdown, so it renders in the run summary.
⚙  Summary - ## Log reading demo

| Field | Value |
| ----- | ----- |
| Node | v24.21.0 |
| Branch | `main` |
| Commit | `f910ba9c` |

This block is markdown, so it renders in the run summary.
```

`act` echoes the file's contents under a `⚙ Summary -` banner. GitHub renders
the same bytes as a markdown table on the run page.

**`Node | v24.21.0` is the number to be suspicious of.** This workflow has no
`actions/setup-node` step, so it printed the runner image's default Node. On a
GitHub-hosted `ubuntu-24.04` runner it would print a different version, and if
someone later adds `setup-node` with `node-version: '22'` it becomes `22.23.3`
(measured, `docs/_logs/ch09-actions.log`). A version in a summary is a claim about
the toolchain, and an unpinned toolchain makes the claim meaningless. **If you
print a version in your summary, you should have installed it two steps earlier.**

### Exit codes, and one step that is not there

The file has two exit-code steps. The log has one:

```
⭐ Run Main Write a run summary
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/4] user= workdir=cicd-learn
⭐ Run Main Exit code 0 is success
  🐳  docker exec cmd=[bash -e /var/run/act/workflow/6] user= workdir=cicd-learn
✅  Success - Main Exit code 0 is success [71.484011ms]
⭐ Run Complete job
🏁  Job succeeded

### act exit status: 0
```

`Exit code 1 is a plain failure` has `if: false`, and a skipped step produces
**no log section at all**. The script numbers also show the gap: step 4 then
step **6**. Index 5 was consumed by the skipped step. Two lessons in two lines:

- A step you expected to see and cannot find was probably **skipped**, not
  silently deleted. Check its `if:` first (chapter 08).
- The step numbers prove the step existed.

What a real GitHub failure looks like, as quoted in chapter 05 from its own run:

```
Run Show that -e is why a failed command stops the step
  first
Error: Process completed with exit code 1.
❌  Failure - Main Show that -e is why a failed command stops the step
```

That `Error: Process completed with exit code` line is the **GitHub runner's**
wording; `act` prints its own instead (`exitcode '1': failure`, which does appear
in `docs/_logs/ch09-anatomy.log`). So that exact line is not in any file in
`docs/_logs/`, and it is cited here from chapter 05, not from this run.

Three lines matter: the output up to the failure, `Process completed with exit
code 1`, and the red `Failure` marker. The message names the **exit code**, never
the reason. The reason is the lines above it, which is why you read upward from
the error rather than down from the top.

### Groups and annotations from a real pipeline step

The two features are not theoretical. From `docs/_logs/ch12-lint.log`, the real
`Set up Node.js` step in the lint workflow:

```
[lint step/lint]   | Found in cache @ /opt/hostedtoolcache/node/22.23.3/x64
[lint step/lint]   ❓  ::group::Environment details
[lint step/lint]   | node: v22.23.3
[lint step/lint]   | npm: 10.9.9
[lint step/lint]   | yarn: 1.22.22
[lint step/lint]   ❓  ::endgroup::
```

and from the same log, this repository's own annotation step:

```
[lint step/lint] ⭐ Run Main Lint annotations on the PR diff
[lint step/lint]   ❓  ::notice title=Lint summary::0 error(s), 0 warning(s)
✅  Success - Main Lint annotations on the PR diff [692.314141ms]
```

You use groups and annotations because the actions you depend on use them. Two
conventions worth copying: the **environment details** group (tool versions,
folded away, available on demand) and a **notice with a count** as a one-line
verdict.

The same log also shows why two log lines can mean opposite things. `docs/_logs/ch12-lint.log` has a warm cache:

```
| Cache restored from key: node-cache-linux-x64-npm-6aabe04f…
⚙  ::set-output:: cache-hit=true
…
| added 127 packages, and audited 128 packages in 1s
```

against the cold run in `docs/_logs/ch09-actions.log`:

```
| npm cache is not found
⚙  ::set-output:: cache-hit=false
…
| added 127 packages, and audited 128 packages in 3s
```

Same lock file, same key (`6aabe04f…`), `cache-hit=true` versus `false`, and
`npm ci` in **1s versus 3s**. Nothing about the two runs differs except those two
lines, and those two lines are the entire explanation. Chapter 16 picks this up.

### `[read-only example]` — GitHub's rendering, which cannot be shown here

```
Actions tab, the Grouped output step, collapsed:
  ▸ ::group::Installing dependencies              <- one clickable row

Actions tab, Annotations filter applied:
  src/greet.js  4  warning  Name is allowed to be empty here
  src/sum.js    2  error    sum is exported but never called

Pull request "Files changed", with an annotation whose path resolves:
  cicd-learn/src/sum.js
    2 |   return numbers.reduce((a, b) => a + b, 0);   <- red marker here
```

All three are rendered by GitHub from the bytes quoted in section 4. The `src/…`
paths in the middle block are the workflow's own, and they do not resolve — which
is the trap above.

## 5. When to use it and when NOT to

**`::group::`** — when a tool emits more than about ten lines you only need
occasionally: install output, a changelog, a test listing, `docker build`'s
per-step detail. The detail stays in the log, one click away.

Not when the group *is* the failure (a folded error is a wasted click at the worst
moment), not when you end up folding everything, and not when the group spans an
`if:` — the `::endgroup::` may never run, and an unclosed group swallows the rest
of the step.

**Annotations** — when the problem belongs to a file and a line and a human is
going to open that file anyway: lint, type-checking, code scanning. The payoff is
that the reviewer sees the problem on the diff without opening a log. You need a
machine-readable result with line numbers (ESLint JSON, `tsc`, SARIF, shellcheck);
`cicd-learn/scripts/lint-annotations.mjs` is 60 lines of exactly this.

Not when the path is not repository-root-relative (section 4's silent
non-appearance), not when the message is unsanitised (`::` in a message is a
log-injection hole), not when you merely want a red word in the log, and **never
as a way to fail the build** — an annotation is not an exit code.

**`$GITHUB_STEP_SUMMARY`** — when a human will make a decision from it: approve a
deploy, read a coverage number, see which matrix legs failed. It is above the fold
on the run page, so it is the one block guaranteed to be read. Several steps can
append to it to assemble one table.

Not when you are pasting the log into it — if it grew past a screen, write less
rather than scroll more — and not when secrets might land in it (chapter 26).

## 6. Common mistakes

- **Reading a log from the top.** You will not reach the error. Click the red step;
  read upward from `Error: Process completed with exit code N`.
- **Swallowing a failure.** `cmd > log.txt` then `echo done` turns a gate into a
  reporter and the pipeline is green forever. Section 2's fix preserves the code.
- **Blaming the tool instead of reading the exit code.** `npm ci` exiting 1 says
  nothing; the lines above it say everything. And exit 127 is categorically
  different from exit 1: one means "your command failed", the other means "your
  command never started".
- **Trusting the version in a summary.** `Node | v24.21.0` in this chapter's log
  is the local container, and on the hosted runner it is something else. Without
  `actions/setup-node`, that number describes an image, not your project.
- **An unsanitised annotation message.** A newline truncates the command; `::`
  lets text in a lint message inject a workflow command. Escape both.
- **An annotation path relative to the working directory.** Silent
  non-appearance. Paths must be relative to the repository root.
- **`>> $GITHUB_OUTPUT` unquoted.** It is a path; a space in it gives you
  `ambiguous redirect` and a baffling failure.
- **`>> "$GITHUB_ENV"` then reading `$MY_VAR` in the same step.** It only affects
  later steps. Chapter 08's log shows this exact ordering.
- **An unclosed `::group::`.** Everything after it folds away, including the error.
- **Expecting an annotation to fail the build.** It is a report. Chapter 12's
  script says so in a comment on its last line.
- **Expecting a skipped step in the log.** It is not there. `if: false` produces
  no output; the step-number gap in section 4 is the only trace it existed.
- **Grepping a log for `error` and trusting the hits.** `::error` inside an
  annotation line can come from a green step. Match the runner's own wording —
  `Error: Process completed with exit code`, `Failure -` — instead.
- **Pasting a whole log into an issue or a chat message.** Use
  `gh run view <id> --log-failed` (needs a remote) or `./scripts/verify.sh`, then
  quote the ten lines around the error. Secrets are masked, but a full log still
  carries internal URLs and hostnames.

## 7. Try it yourself

**Exercise: build a log that is easy to read when it fails.**

1. Create `.github/workflows/logcraft.yml`:

   ```yaml
   name: Log craft
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
     craft:
       name: Log craft
       runs-on: ubuntu-24.04
       steps:
         - uses: actions/checkout@v7
         - uses: actions/setup-node@v7
           with:
             node-version: '22'
             cache: 'npm'
             cache-dependency-path: cicd-learn/package-lock.json

         # Noisy expected output, folded. The verdict stays outside the fold.
         - name: Install
           run: |
             {
               echo "::group::npm ci output"
               npm ci 2>&1
               echo "::endgroup::"
               echo "install finished"
             }

         # The real lint, with its exit code preserved.
         - name: Lint
           run: npx eslint . --format stylish

         # A report step that never decides anything.
         - name: Lint annotations
           run: |
             npx eslint . --format json > /tmp/lint.json || true
             node scripts/lint-annotations.mjs /tmp/lint.json

         # One screen, for a human.
         - name: Summary
           run: |
             {
               echo "## Result"
               echo ""
               echo "| Tool | Version |"
               echo "| ---- | ------- |"
               echo "| node | $(node --version) |"
               echo "| npm  | $(npm --version) |"
             } >> "$GITHUB_STEP_SUMMARY"
   ```

2. Push. Open the run. On GitHub the `Install` step is **one row** labelled
   `npm ci output`, with `install finished` below it ungrouped. Read the summary:
   `node` is `22.23.3`, because this time `setup-node` installed it — unlike this
   chapter's own workflow. That contrast is the point: **a version in a summary is
   only as good as the step that pinned it.**

3. **Break it four ways, and read each message.**

   - **Break the exit code.** Change the `Lint` step to
     `npx eslint . --format stylish || true`, write a deliberate unused variable
     into `cicd-learn/src/greet.js`, and push. The step is **green** and the log
     still prints the ESLint complaint: a pipeline that is lying to you. Delete
     the `|| true`.
   - **Break the annotation path.** Emit
     `::error file=src/greet.js,line=1::oops` by hand and push. The annotation
     appears in the log's Annotations filter and nowhere on the diff.
   - **Break the grouping.** Remove one `::endgroup::`, push, and watch the rest
     of the step — including any error — disappear into a fold. Add it back.
   - **Break the summary.** Change `>> "$GITHUB_STEP_SUMMARY"` to
     `>> $GITHUB_STEP_SUMMARY` and read the shell's complaint about an ambiguous
     redirect. A one-character-class bug, prevented only by the quotes.

4. Local equivalent:

   ```bash
   ./scripts/verify.sh .github/workflows/logcraft.yml craft push logcraft
   grep -nE 'Failure|Success|exit code' docs/_logs/logcraft.log
   ```

   Byte-exact stream locally in seconds. Not reproducible locally: the collapsed
   row, the Annotations filter, the diff markers, the hosted runner's version.
   Know which is which and you never trust the wrong one.

**Hint:** always read the same three things, in this order — the step's exit
code, the last ten lines above the error, and the version line. In that order,
almost every CI failure is diagnosed in under a minute.

**Break it on purpose, the worst version:** delete the `Lint` step and keep the
`Lint annotations` step. The annotations still appear, the summary still renders,
the run is green, and `scripts/lint-annotations.mjs`'s comment becomes a lie:
`::notice title=Lint summary::0 error(s), 0 warning(s)` — **zero errors, because
nothing ran.** Reports and verdicts are separate steps for exactly this reason.

## 8. Next

You can write a workflow, choose when it runs, choose its machine, write its jobs
and steps, pull in other people's actions, and read what came out. That is the
whole of Part 2.

Part 3 builds a real pipeline out of it, one step at a time, in the order that
fails fastest: install, then lint, then test, then build.

→ [11 — Install](11-install-step.md)
