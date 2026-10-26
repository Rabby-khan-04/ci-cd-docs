# 12 — The lint step

> **Verification.** The workflow in this chapter is
> `.github/workflows/12-lint-step.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/12-lint-step.yml lint push ch12-lint`,
> and the full log is at `docs/_logs/ch12-lint.log`. Every log excerpt in
> section 4 is quoted from that file. `python3 scripts/validate-workflows.py`
> reports `ok .github/workflows/12-lint-step.yml (1 job(s))`.
>
> The ESLint findings in section 4 — the `github` formatter being gone, the exit
> codes, and the annotation output — were measured on this machine against the
> installed `eslint@10.12.0` (Node v24.19.0, npm 11.17.0) in a throwaway copy of
> `cicd-learn` under `/tmp`. The list of built-in formatters was read out of
> `node_modules/eslint/lib/cli-engine/formatters/formatters-meta.json`, and the
> behaviour of the `eslint-formatter-github` package was checked against its own
> published README on npm (version 1.1.4). Nothing in this chapter is quoted from
> a tutorial.
>
> **What this local execution cannot prove.** `act` does not reproduce GitHub's
> **annotations rendering**: the `::error` lines below appear in the local log as
> plain text with a `❓` marker, and the actual behaviour — a red squiggle next
> to line 27 in the pull request diff — is a GitHub-only feature that cannot be
> verified without a repository on github.com. It also cannot prove the PR-diff
> placement, the 10-annotation display cap, or that `GITHUB_STEP_SUMMARY` renders
> as a table. The *exit codes* and the *command text* are real and measured; the
> *rendering* is pending a hosted run.

---

## 1. Simple explanation (like I'm 7)

Your code can be wrong without being broken. It runs fine. It just has a habit
that will bite you later: you used the old way of doing something when there is
a new, safer way, and you left a note to yourself in the shape of a variable
named `x2`.

A **linter** is a machine that reads your code and points at those habits.

It is the same idea as spell-check in a word processor, with two differences
that matter. First, spell-check underlines the word and lets you carry on; a
linter in CI stops the whole machine. Second, and this is the important one:
the linter is not looking for *mistakes*. It is looking for *mistakes you said
you would not make*.

So the rule is not "the linter is clever". The rule is: **the team writes down
its rules once, the machine checks them on every single push, and nobody has to
remember.**

Which raises the obvious beginner question, and it deserves a straight answer:
why not just run it on my own machine? Because on your own machine it is a
suggestion you can decline. On the build machine it is the door.

## 2. Real name

### Linting versus formatting versus type checking

Three different jobs that beginners merge into one word. They are not the same
tool and they catch different things.

| | Lint | Format | Type check |
| - | - | - | - |
| Question | "Is this code written the way we agreed?" | "Is this laid out the way we agreed?" | "Are the types right?" |
| This project | ESLint 10.12.0 | (ESLint does not format) | (none) |
| Catches | `var`, `==`, unused variables | spacing, quotes, line width | passing a string where a number is needed |
| Fix tool | `eslint --fix`, sometimes | separate, e.g. Prettier | usually not automatic |

In this repository `eslint.config.js` turns on exactly four rules:

```js
rules: {
  eqeqeq: 'error',
  'no-unused-vars': 'error',
  'no-var': 'error',
  'prefer-const': 'error',
}
```

That is the "written down rules" part. `no-var` is not a matter of taste — `var`
is function-scoped and hoisted, which is how an accidental bug happens.

### Exit codes are the contract

This is the part that makes lint steps in CI simple, and the part people fight.
ESLint's exit code is the verdict. There is nothing to parse.

| Exit code | Meaning | Measured here |
| --------- | ------- | ------------- |
| `0` | No problems. Or nothing was linted at all. | see below |
| `1` | Lint problems were found. | `npm run lint` on a broken file |
| `2` | Fatal: bad config, bad flag, could not load | `eslint --format github .` on ESLint 10 |

Two consequences worth internalising:

1. **You never grep the output.** No `if grep -q error ...`. No `| tee` that
   swallows the code. The step is `run: npm run lint`, full stop.
2. **Exit 0 is ambiguous.** It means "no problems" *or* "nothing was checked".
   A silently empty lint is a real failure mode: a bad glob, a wrong
   `working-directory`, a config that excludes everything. The step that proves
   files were actually linted is the table in section 4 — it lists ten files.

### Formatters

A formatter decides how results are *presented*. ESLint 10.12.0 ships exactly
four, read out of `formatters-meta.json` in the installed package:

| Formatter | Shape | Use |
| --------- | ----- | --- |
| `stylish` | human text | the default |
| `json` | array of `{filePath, messages, errorCount, warningCount}` | machine reading |
| `json-with-metadata` | the same plus which rules were applied | auditing |
| `html` | a web page | sharing |

That is the whole list. Four. There is no `github` formatter, and there has not
been one since ESLint 10.

### The `github` formatter, and why every tutorial is wrong

Half the CI tutorials ever written contain this line:

```yaml
- run: npx eslint . --format github
```

On ESLint 10 it does not work. Measured, on a file with two lint errors:

```
There was a problem loading formatter: /tmp/opencode/lintprobe/node_modules/eslint/lib/cli-engine/formatters/github.js
Error: Cannot find module '/tmp/opencode/lintprobe/node_modules/eslint/lib/cli-engine/formatters/github.js' imported from /tmp/opencode/lintprobe/node_modules/eslint/lib/eslint/eslint.js
```

Exit code **2**, not 1. That distinction is diagnostic: 2 means ESLint never got
as far as linting anything. It did not find errors in your code; it could not
find its own formatter.

The formatter was removed from the built-in set in ESLint 10. It now lives in a
separate package, `eslint-formatter-github` (npm version 1.1.4), and reading its
own README is the fastest way to see why it is the wrong tool inside Actions: it
reports through the **GitHub Checks API**, which means it needs a **GitHub App**.
Its documented usage is: install *their* app on your repository, then run the
formatter. Or create your own app, give it `Checks: Read & Write`, and set
`ESLINT_APP_ID` and `ESLINT_APP_PRIVATE_KEY`.

So the fix for "I want lint errors on my PR diff" is: install a third-party
GitHub App on your repo, or mint a credential, in exchange for something GitHub
Actions already gives you for free and offline. That is the wrong trade inside
Actions.

### Workflow commands, which is the free mechanism

GitHub Actions reads your step's stdout for lines shaped like this:

```
::error file=src/greet.js,line=27,col=3,title=no-var::Unexpected var%2C use let or const instead.
```

The pieces:

| Part | Meaning |
| ---- | ------- |
| `::error` / `::warning` / `::notice` | the severity, and what colour it gets |
| `file=` | repo-relative path, so the diff can find it |
| `line=`, `col=` | where |
| `title=` | short label, here the rule name |
| `::` | end of properties, start of the message |
| message | the human text |

Any tool that prints these lines gets annotations, with no token, no network
call, and no extra account. **That is the mechanism you should use**, and
`cicd-learn/scripts/lint-annotations.mjs` is about 30 lines of it.

### Escaping, which is where a hand-rolled formatter breaks

The command is `::name key=value,key=value::message`. Two separators, two sets
of rules, and the reference implementation is the `Command` class in
[`@actions/core`](https://github.com/actions/toolkit/blob/main/packages/core/src/command.ts).
Read it rather than guessing:

```js
function escapeData(s) {          // the MESSAGE
  return String(s).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A')
}
function escapeProperty(s) {      // each key=value PROPERTY
  return String(s).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A')
    .replace(/:/g, '%3A').replace(/,/g, '%2C')
}
```

So: **commas and colons only need escaping inside the properties**, because the
properties are comma-separated and the second `::` ends the property list. The
message only needs `%`, `\r` and `\n`.

`cicd-learn/scripts/lint-annotations.mjs` applies one function's worth of rules
to *both* halves:

```js
const escape = (s) => String(s)
  .replace(/\r/g, '%0D')
  .replace(/\n/g, '%0A')
  .replace(/::/g, '%3A%3A')   // stops message injection of a new command
  .replace(/,/g, '%2C');
```

Real output from that script, on a file with one `no-var` violation:

```
::error file=src/greet.js,line=27,col=3,title=no-var::Unexpected var%2C use let or const instead.
```

The message ESLint produced is `Unexpected var, use let or const instead.` —
with a comma. The annotation shows `%2C`, because the script escapes commas
everywhere rather than only in the properties. That over-escaping is harmless:
GitHub decodes `%2C` back to a comma, so the annotation reads correctly. It is
also a useful teaching artefact, because you can *see* the escape in the log.

Two things do get this wrong in real code, and both are worth checking for:

- **A newline in the message.** ESLint messages are single-line, but a rule with
  a multi-line message would emit a second line that the runner reads as a
  *separate workflow command*.
- **`%` not escaped first.** This script does not escape `%` to `%25`;
  `@actions/core` does it first in both functions. Order matters for escapes in
  general, and this one is a genuine latent gap in the script as it stands.

## 3. Workflow example

This is the complete `.github/workflows/12-lint-step.yml` from this repository.

```yaml
name: Lint step

# Quoted so YAML 1.1 and YAML 1.2 agree (chapter 05).
"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

# Only safe because this job checks out the repo first, which is what creates
# `cicd-learn/`. Chapter 15 is about the job in this workflow that does not.
defaults:
  run:
    working-directory: cicd-learn

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci

      # Plain run. The whole contract is that the exit code is the verdict:
      # ESLint exits 0 when clean, 1 when it found problems. No parsing of the
      # output, no `grep`, no check of whether the words "error" appear.
      - name: Lint
        id: lint
        run: npm run lint

      # ── Annotations on the PR diff ───────────────────────────────────────
      # Older tutorials say to use `--format github`. That formatter was REMOVED
      # from ESLint's built-in formatters in ESLint 10. It now lives in the
      # separate `eslint-formatter-github` package, and that package uploads
      # results through a GitHub App instead of emitting workflow commands, so it
      # is the wrong tool inside Actions.
      #
      # The modern approach: read ESLint's JSON and print workflow commands
      # yourself. cicd-learn/scripts/lint-annotations.mjs does that in ~30 lines
      # with no dependencies, and problems then appear on the PR diff next to the
      # offending line instead of only in a log nobody scrolls to.
      - name: Lint annotations on the PR diff
        run: |
          npx eslint . --format json > /tmp/lint.json || true
          node scripts/lint-annotations.mjs /tmp/lint.json

      # ── Writing the report into the run summary ──────────────────────────
      # `--format json` gives structured output; a small script turns it into a
      # markdown table. The script lives in cicd-learn/scripts/lint-summary.mjs
      # rather than inline, because shell-quoting JavaScript inside a YAML run:
      # block is a trap that costs an afternoon.
      #
      # Note the `|| true`: without it, `bash -e` would abort the step the
      # moment eslint exits non-zero, and you would never see the table. The
      # step's verdict still comes from the earlier lint step.
      - name: Lint report as a table
        run: |
          npx eslint . --format json > /tmp/lint.json || true
          node scripts/lint-summary.mjs /tmp/lint.json | tee -a "$GITHUB_STEP_SUMMARY"
```

Two structural things to notice, because they are the reusable pattern:

- **The verdict step has no `|| true`.** `run: npm run lint` on its own. If it
  fails, the job is red and the two reporting steps never run.
- **Both reporting steps have `|| true`.** They exist to be *read*, so they must
  survive a failure. They deliberately do not decide anything; that is why both
  helper scripts end with a comment saying they always exit 0.

That is the shape of every "check, then report" pipeline: one step decides, the
rest are decoration that can never turn a red build green or a green build red.

## 4. What I should see

### A clean run

From `docs/_logs/ch12-lint.log`, the three steps that matter:

```
[Lint step/Lint] ⭐ Run Main Lint
[Lint step/Lint]   | 
[Lint step/Lint]   | > cicd-learn@1.0.0 lint
[Lint step/Lint]   | > eslint .
[Lint step/Lint]   | 
[Lint step/Lint]   ✅  Success - Main Lint [560.048517ms]
```

**The empty output is the success.** A green lint step prints the two lines npm
prints and nothing else. If you are looking for a reassuring "0 problems" line,
you will not find one — there is nothing to report when there is nothing wrong.

Then the annotation step, on a clean tree:

```
[Lint step/Lint] ⭐ Run Main Lint annotations on the PR diff
[Lint step/Lint]   ❓  ::notice title=Lint summary::0 error(s), 0 warning(s)
[Lint step/Lint]   ✅  Success - Main Lint annotations on the PR diff [692.314141ms]
```

One notice, zero annotations. That is what "no problems" looks like as a
workflow command.

And the summary step, which is also the **proof that files were actually
linted**:

```
[Lint step/Lint]   | | file                         | errors | warnings |
[Lint step/Lint]   | | ---------------------------- | -----: | -------: |
[Lint step/Lint]   | | build.mjs                    |      0 |        0 |
[Lint step/Lint]   | | eslint.config.js             |      0 |        0 |
[Lint step/Lint]   | | scripts/lint-annotations.mjs |      0 |        0 |
[Lint step/Lint]   | | scripts/lint-summary.mjs     |      0 |        0 |
[Lint step/Lint]   | | src/app.js                   |      0 |        0 |
[Lint step/Lint]   | | src/greet.js                 |      0 |        0 |
[Lint step/Lint]   | | src/sum.js                   |      0 |        0 |
[Lint step/Lint]   | | test/greet.test.js           |      0 |        0 |
[Lint step/Lint]   | | test/sum.test.js             |      0 |        0 |
[Lint step/Lint]   | | vitest.config.js             |      0 |        0 |
[Lint step/Lint]   | 
[Lint step/Lint]   | **Total: 0 error(s), 0 warning(s)**
```

Ten files, all zero. Read this table every time you first add a lint step. If a
file you care about is missing from it, your config is not covering it, and you
have a lint step that passes because it checks nothing.

### A dirty run

Add two violations to `src/greet.js` in a throwaway copy and run `npm run lint`.
Real output:

```
/tmp/opencode/lintprobe/src/greet.js
  25:2  error  Unexpected var, use let or const instead  no-var
  26:7  error  Expected '===' and instead saw '=='       eqeqeq

✖ 2 problems (2 errors, 0 warnings)
  1 error and 0 warnings potentially fixable with the `--fix` option.
```

Exit code **1**. The step is red, the job is red, and the two reporting steps
below it are skipped. Note the last line: ESLint is telling you it could have
fixed one of these for you. `npx eslint . --fix` on a throwaway copy is the
fastest way to read what a rule actually wants.

Now the same violations through the annotation script:

```
::error file=src/greet.js,line=27,col=3,title=no-var::Unexpected var%2C use let or const instead.
::error file=src/greet.js,line=27,col=12,title=eqeqeq::Expected '===' and instead saw '=='.
::notice title=Lint summary::2 error(s), 0 warning(s)
```

Read that first line closely, because it teaches four things at once:

- `file=src/greet.js` — **repo-relative**. The script strips `process.cwd()`. An
  absolute path like `/home/runner/work/repo/repo/cicd-learn/src/greet.js`
  would be meaningless in the diff, because GitHub matches against the path in
  the repository.
- `line=27,col=3` — where. Column 3 for `no-var` is where the keyword is, not
  where the line starts.
- `title=no-var` — the rule, not the prose. GitHub shows the title in the
  annotation list; the prose would be too long and too similar between rules.
- `%2C` — the escaped comma. ESLint said `Unexpected var, use let or const
  instead.` and the workflow command said `Unexpected var%2C use let or const
  instead.` Without the escape, GitHub would read `col=3` and then be off by one
  field, and the message would end at `Unexpected var`.

And the third line, the `::notice`, is the count. When there are 300 problems
GitHub shows a capped number in the diff; the notice is how you learn the real
number.

### The formatter that is not there

```
There was a problem loading formatter: .../eslint/lib/cli-engine/formatters/github.js
Error: Cannot find module '.../eslint/lib/cli-engine/formatters/github.js' imported from .../eslint/lib/eslint/eslint.js
```

Exit code **2**. If you see this, stop looking at your code: nothing was linted.

## 5. When to use it and when NOT to

**Use a lint step when:**

- **The rule set is small and agreed.** Four rules in this project. Four is a
  conversation. Forty is a negotiation and usually should be staged in.
- **You want to stop style arguments.** Once the rules are in the config and
  enforced, code review stops being about formatting and starts being about
  correctness. That is the actual return on the investment.
- **You can run the whole thing in seconds.** ESLint took 560ms here. A check
  that costs half a second gets run; a check that costs four minutes gets
  skipped by people, and a skipped check is a dead check.

**Do NOT reach for a lint step when:**

- **The rule set is inherited from a framework's example config.** Airbnb,
  `eslint:recommended` plus 200 rules: you will spend your first week turning
  things off, and the rules you never read are the ones that will surprise
  someone. Start with four, add four. You do not want formatting (that is a
  separate tool with a separate config) and you do not want type safety (that is
  a type checker, and nothing here can catch `sum("a", "b")`).

- **`--max-warnings=0` as a starting policy.** It is a good policy eventually
  and a terrible first day. Symptom: the pipeline is red from a commit that
  changed three lines, because the repository had 400 warnings. Fix: run
  `--fix`, or run once with `--max-warnings=-1` to see the number, fix or
  baseline, *then* turn it on. A gate nobody can pass gets bypassed.

- **Running the reporting scripts in the same step as the verdict.** You lose
  the annotations on failure, which is exactly when you want them.

- **Letting the annotation step set the verdict.** Both scripts here always exit
  0, on purpose. If someone "fixes" that to exit non-zero on findings, the
  `|| true` above it silently swallows the failure and you now have a lint step
  that reports errors and passes anyway. That is the worst outcome available:
  it looks like it works.

## 6. Common mistakes

- **`--format github` on ESLint 10.** Symptom: `Cannot find module
  '.../formatters/github.js'`, exit 2. Fix: delete the flag and read
  `--format json` with a script, as in section 3.

- **Installing `eslint-formatter-github` because the tutorial said so.** Symptom:
  green steps and no annotations, because the package only runs when it can
  reach the GitHub Checks API, and it silently does nothing without a GitHub App
  and its credentials. You have added a dependency and a network call and a
  third-party app, for annotations you can print yourself.

- **Grepping the output instead of using the exit code.** Every bad version:
  `run: npx eslint . | tee log.txt`, `run: npx eslint . || true`,
  `run: test -z "$(npx eslint .)"`. All of them can pass with lint errors. If a
  pipeline can be red in the log and green in the Actions tab, this is why.

- **`|| true` on the verdict step.** Symptom: the pipeline is green and someone
  has a lint error locally. This is the single most damaging mistake in the
  chapter, because nothing looks wrong.

- **Forgetting to escape commas in a hand-rolled formatter.** Symptom: an
  annotation whose title is truncated at the first comma, or whose `line=`/`col=`
  values are shifted by one field. Commas only matter in the *properties*;
  `@actions/core` escapes them there and not in the message.

- **Printing `::` unescaped in a message.** A lint message containing `::error`
  would let ESLint's output inject a workflow command into your run. `no-var`
  does not do this, a rule about log formatting very well might. The script
  escapes `::` to `%3A%3A` for exactly this reason — that is log-injection
  defence, and chapter 26 is about that class of bug. Escape `%` to `%25` first,
  before the other four replacements, or a message containing `%` produces
  garbage; Vitest's built-in reporter does this correctly and is worth reading
  for the full five-line `escapeProperty`.

- **Absolute paths in `file=`.** Symptom: annotations that appear in the log but
  not on the diff. Strip `process.cwd()`.

- **Assuming exit 0 means "linted and clean".** Exit 0 also means "linted
  nothing". Symptom: a green lint step three weeks after adding a rule. Fix:
  read the summary table, and assert on the file count if it matters.

- **Linting `dist/`, `coverage/` or `node_modules/`.** Not just slow: your
  generated output has its own opinions and will start failing the build on a
  rebuild that changed nothing you wrote. `eslint.config.js` here starts with
  `{ ignores: ['dist/**', 'node_modules/**', 'coverage/**'] }`.

- **Running ESLint against the whole monorepo root because the command was
  easier to type.** Symptom: minutes instead of seconds, and then someone
  removes the step. See chapter 44. Same trap as `--quiet` in a pipeline with no
  written warnings policy: decide explicitly whether warnings fail the build.

## 7. Try it yourself

**Exercise: produce the two outputs you actually need on purpose — annotations
and a failure — without pushing anything.**

1. Copy the app, so the repository stays clean:

   ```bash
   rm -rf /tmp/lint-lab
   cp -r cicd-learn /tmp/lint-lab
   cd /tmp/lint-lab
   ```

2. Add two violations to `src/greet.js`:

   ```bash
   printf 'var x = 1\nif (x == 1) { console.log(x) }\n' >> src/greet.js
   ```

3. The verdict. Confirm the exit code is the mechanism:

   ```bash
   npm run lint ; echo "exit=$?"
   ```

   `exit=1`, and the human output is the stylish format from section 4.

4. The annotations. This is the pair of commands from the workflow, run by
   hand:

   ```bash
   npx eslint . --format json > /tmp/lint.json || true
   node scripts/lint-annotations.mjs /tmp/lint.json
   ```

   You get the three `::` lines. Now **look at the `%2C`** and confirm it lines
   up with the comma in ESLint's own message.

5. Break the escape deliberately and watch the raw command change:

   ```bash
   sed -i "s/.replace(\/,\/g, '%2C')//" scripts/lint-annotations.mjs
   npx eslint . --format json > /tmp/lint.json || true
   node scripts/lint-annotations.mjs /tmp/lint.json
   ```

   The `no-var` line now reads
   `::error file=src/greet.js,line=25,col=2,title=no-var::Unexpected var, use let or const instead.`
   — the comma is no longer encoded. Nothing fails locally, and GitHub still
   renders it correctly, because commas in the *message* never needed escaping.
   That is the lesson: the escape matters in the properties, not the message, and
   the log is where you find out which half a given character belongs to. Now
   try it in the properties instead — change `title=${escape(m.ruleId)}` to
   `title=${m.ruleId}` and use a rule id containing a comma. Re-copy the app when
   you are done.

6. **Break the pipeline on purpose, the beginner way.** Delete the `--format`
   line and put back the one from the internet:

   ```bash
   npx eslint . --format github ; echo "exit=$?"
   ```

   `exit=2` and `Cannot find module '.../formatters/github.js'`. Now you
   recognise that message instantly instead of searching for it.

7. **Break it the dangerous way.** Add `|| true` to the verdict step in
   `.github/workflows/12-lint-step.yml`, push, and watch the job stay green
   while the log contains `✖ 2 problems (2 errors, 0 warnings)`. This is the
   single most instructive experiment in the chapter: *the log is red and the
   build is green*. Then remove the `|| true` and push again.

**Hint:** to see the whole thing without pushing, run the real workflow against
the real file:

```bash
./scripts/verify.sh .github/workflows/12-lint-step.yml lint push ch12-lint
```

**What this exercise proves:** the exit codes, the exact annotation text, that
commas are encoded as `%2C` by this script, and that the `github` formatter is
absent from ESLint 10.12.0. **What it cannot prove:** that GitHub renders those
`::error` lines as annotations on the pull request diff, that the file paths
resolve against the diff, or that a `%` in a message would actually be mangled
the way the escaping rules imply — that one needs a hosted run. Rendering is
the whole reason to run this chapter's workflow on GitHub before moving on.

## 8. Next

You have a machine that says yes or no about style. It does not say anything
about whether your code is *right*.

Chapter 13 runs the test suite, and the failure output there is the most
information-dense thing in this part of the course: expected versus received,
which is how a bug stops being a mystery.

→ [13 — The test step](13-test-step.md)