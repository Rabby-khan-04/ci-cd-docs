# 13 — The test step

> **Verification.** The workflow in this chapter is
> `.github/workflows/13-test-step.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/13-test-step.yml test push ch13`, and
> the full log is at `docs/_logs/ch13.log`. Every log excerpt in section 4 is
> quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/13-test-step.yml (1 job(s))`.
>
> The failure output, the coverage table, and the coverage-threshold failure in
> section 4 were measured on this machine (Node v24.19.0, npm 11.17.0) by
> running `npm test` and `npm run coverage` in throwaway copies of `cicd-learn`
> under `/tmp`, with one deliberate change per run. The
> `github-actions` reporter behaviour was confirmed by reading
> `node_modules/vitest/dist/chunks/defaults.D2ip7f-X.js`, which sets
> `reporters: [..., ...process.env.GITHUB_ACTIONS === "true" ? ["github-actions"] : []]`.
>
> **What this local execution cannot prove.** It cannot prove the failure
> *annotations on the pull request diff* — that is GitHub's renderer acting on
> the `::error` lines Vitest emits, and there is no repository here to render
> them into. It cannot prove branch protection behaviour, so the "a red test
> blocks the merge" claim in section 2 is documented from the workflow-syntax
> reference and is **pending a hosted run**. Test *outcomes*, *exit codes* and
> *output text* are real and measured.

---

## 1. Simple explanation (like I'm 7)

Here is a difference between two kinds of mistake.

You write a function that adds numbers. You ask it to add two and three. It
gives you four. Nobody notices.

Later, someone changes it slightly. Now it gives you `null`. Nobody notices
either, because nobody asked it that question again.

A **test** is you asking the question again. Automatically. Every single time
the machine runs. The machine holds your old answer in a file and compares:

```
  what I asked for:   5
  what the code did:  null
  VERDICT:            FAIL
```

That is the entire idea. You are not testing "correctness" in some deep sense.
You are writing down what the answer *was*, so that the machine can tell you
when the answer changes.

Which is why tests are strange when you first meet them. You are writing code
whose entire job is to fail, and which you are slightly embarrassed about
because it never does anything useful at runtime. It does the most useful thing
in the world: it makes a change from "silent" into "loud".

## 2. Real name

### Test, assertion, runner

- **Test case** — one named question with one expected answer.
- **Assertion** — the comparison itself. `expect(greet('Ada')).toBe('Hello, Ada!')`
  is an assertion: expected `Hello, Ada!`, and whatever came back.
- **Test runner** — the program that finds the test cases, runs them, compares,
  and reports. Here: **Vitest 5.0.3**, invoked as `vitest run`.

The project has 13 tests in two files:

```
test/greet.test.js   8 tests   greet, shout, slugify, add
test/sum.test.js     5 tests   sum, average
```

### `vitest run` versus `vitest`

`vitest` alone starts **watch mode**: it runs the tests, then sits there
watching the filesystem, re-running on every save, forever. In CI that step
never finishes. The job sits there until `timeout-minutes` kills it, or until
the runner's default six-hour limit, and your minutes are gone.

`vitest run` means run once and exit. The package script encodes this already:

```json
"test": "vitest run",
"test:watch": "vitest",
```

**Never invoke the watch form in a workflow.** If you write `run: npx vitest`,
you have written a step that hangs.

### Exit codes, again

Same contract as lint, and it is worth being blunt about why it matters: a
green test step that says nothing useful is indistinguishable from a broken
test command. `npm test` exits 0 when all 13 pass, non-zero when any fail. The
step is `run: npm test` and there is no parsing anywhere in this job.

| Exit | Meaning |
| ---- | ------- |
| 0 | Everything passed |
| 1 | At least one test failed |
| other | The runner itself broke: bad config, no test files found, crashed |

That last row is the one people miss. "No test files found" is a **config
mistake, not a passing suite**, and it also exits 0 in some tools. This project
guards against it structurally: `vitest.config.js` sets
`include: ['test/**/*.test.js']`, so a renamed file disappears from the run
instead of silently passing.

### Expected versus received

The single most important habit in reading a test failure. The output says:

```
Expected: "Hello, Grace!"     <- what the test asserted
Received: "Hello, Ada!"       <- what the code actually returned
```

Read it as a claim about the world. The code returned `Hello, Ada!` — that is a
fact, observed. The test expected `Hello, Grace!` — that is a belief, written
days or weeks ago. When a test fails, **the received value is the truth and the
expected value is the thing to interrogate.**

Most of the time the belief is wrong: the test encodes an old intent, or the
input changed. Sometimes the code is wrong. The failure message gives you both
numbers and no opinion, which is correct, and you have to supply the opinion.

### Annotations, for free this time

In chapter 12 you had to write 30 lines to turn ESLint's output into workflow
commands. Vitest needs nothing from you. Its default reporter list, read from
the installed package, is:

```js
reporters: [
  isAgent ? 'minimal' : 'default',
  ...process.env.GITHUB_ACTIONS === 'true' ? ['github-actions'] : [],
]
```

So on a runner, Vitest adds a `github-actions` reporter **automatically**, and
you get two things for free:

- a `::error` workflow command per failing test, with the file and line, so it
  shows up on the pull request diff;
- a `## Vitest Test Report` block written into `$GITHUB_STEP_SUMMARY`, which
  also tracks which tests were **flaky** — passed on a retry after failing
  first.

The lesson is not "Vitest is nice". The lesson is: **before you hand-roll a
reporter, check whether your runner already ships one for CI.** ESLint does
not; Vitest does.

### Flaky tests

A test that fails sometimes and passes sometimes, with no change in the code.
This is the most corrosive thing a test suite can have, because it teaches
everyone that red means nothing, and then one day a real bug is red and nobody
looks.

Causes, in rough order of how often it is really one of them:

1. **Real time.** `Date.now()` in a test, a timestamp comparison, anything that
   crosses midnight, a leap second, a DST boundary.
2. **Shared state.** Two tests using the same temp file, the same port, the same
   database row, and one not cleaning up.
3. **Order dependence.** It passes alone and fails in the suite. Run it alone and
   it passes — that is the test.
4. **Genuine raciness.** Parallel workers and a shared resource.

Fix the cause; do not `retry(3)` it into submission. Vitest does track retries,
so a flaky test shows up in the summary as flaky rather than passing silently —
use that signal.

### What a red test does to the pipeline

Inside the workflow: the step goes red, the job goes red, and every step after
it is skipped. Nothing deploys, nothing publishes.

Outside the workflow: the job's **name** — here `Unit tests` — becomes a status
check that GitHub attaches to the commit. A branch protection rule on `main` can
require that check to be green before merging. That rule is where the gate
really lives; the workflow only produces the verdict. Chapter 34.

## 3. Workflow example

This is the complete `.github/workflows/13-test-step.yml` from this repository.

```yaml
name: Test step

# Quoted so YAML 1.1 and YAML 1.2 agree (chapter 05).
"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

# Safe only because this job checks out first, which is what creates
# `cicd-learn/`. Chapter 15 shows the job that does not.
defaults:
  run:
    working-directory: cicd-learn

jobs:
  test:
    name: Unit tests              # <- becomes the required status check name
    runs-on: ubuntu-24.04
    # A hung test suite should fail, not sit here for the default six hours.
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci

      # `vitest run` means run once and exit. Without `run` it would watch for
      # file changes forever and never finish the step.
      - name: Run tests
        id: tests
        run: npm test

      # ── Reading a failure ─────────────────────────────────────────────────
      # The reporter that matters in CI is one that prints the diff and the
      # actual value, not just "expected X to be Y". Vitest's default reporter
      # does this. The flag that helps most in CI is a verbose reporter, so each
      # test is listed by name.
      #
      # Real output from a deliberately broken assertion (see section 4):
      #
      #   FAIL  test/greet.test.js > greet > greets by name
      #   AssertionError: expected 'Hello, Ada!' to be 'Hello, Grace!'
      #     Expected: "Hello, Grace!"
      #     Received: "Hello, Ada!"
      #
      # Read it as: expected [what I asked for], received [what the code did].
      # In a real bug, the "received" value is the truth about the world and the
      # "expected" value is your belief about it. Usually your belief is wrong.

      # ── Non-zero exit is the whole contract ───────────────────────────────
      # Vitest exits 1 when any test fails. `bash -e` turns that into a red step,
      # and a red step skips everything after it. There is no parsing of output
      # anywhere in this job, and there should not be.

      # ── Do not deploy or publish from a failing run ───────────────────────
      # Chapter 34 explains required status checks: this job's name becomes a
      # check that a branch protection rule can require, so `main` cannot be
      # merged into while this is red. That is where the "gate" actually lives,
      # not in this workflow file.
```

## 4. What I should see

### A passing run

From `docs/_logs/ch13.log`. ANSI colour codes stripped; they are in the file:

```
[Test step/Unit tests] ⭐ Run Main Run tests
[Test step/Unit tests]   | 
[Test step/Unit tests]   | > cicd-learn@1.0.0 test
[Test step/Unit tests]   | > vitest run
[Test step/Unit tests]   | 
[Test step/Unit tests]   |  RUN  v5.0.3 /home/sunny/app/nimo/cicd-docs/cicd-learn
[Test step/Unit tests]   | 
[Test step/Unit tests]   |  ✓ test/greet.test.js (8 tests) 6ms
[Test step/Unit tests]   |  ✓ test/sum.test.js (5 tests) 6ms
[Test step/Unit tests]   | 
[Test step/Unit tests]   |  Test Files  2 passed (2)
[Test step/Unit tests]   |       Tests  13 passed (13)
[Test step/Unit tests]   |    Start at  09:51:14
[Test step/Unit tests]   |    Duration  162ms (transform 52%, import 27%, tests 12%, worker 8%)
[Test step/Unit tests]   ✅  Success - Main Run tests [695.303333ms]
```

`2 passed (2)` and `13 passed (13)`. Read those two counts as a claim about
*coverage of the suite*, not about the code: 13 tests over 4 exported functions
is not thorough. Chapter 35 is about that, honestly.

The step took 695ms wall clock while Vitest reports a 162ms duration. The
difference is process startup and npm's own overhead, and it is why pipeline
timing arithmetic should use wall clock from the log, not a tool's self-report.

Then, unprompted by this workflow, the step summary block:

```
[Test step/Unit tests]   ⚙  Summary - ## Vitest Test Report

### Summary

- **Test Files**: ✅ **2 passes** · 2 total
- **Test Results**: ✅ **13 passes** · 13 total
```

That is the `github-actions` reporter, enabled automatically because
`GITHUB_ACTIONS=true`. No step in the workflow writes to `$GITHUB_STEP_SUMMARY`.
That is the contrast with chapter 12 worth sitting with.

### A failing run

Measured. Change one assertion in a throwaway copy — in `test/greet.test.js`,
line 6, ask for a different name than the one the test passes in:

```bash
sed -i "6s/.*/    expect(greet('Ada')).toBe('Hello, Grace!');/" test/greet.test.js
npm test ; echo "exit=$?"
```

Real output, colour stripped:

```
 ❯ test/greet.test.js (8 tests | 1 failed) 16ms
   ❯ greet (3)
     × greets by name 11ms

 FAIL  test/greet.test.js > greet > greets by name
AssertionError: expected 'Hello, Ada!' to be 'Hello, Grace!' // Object.is equality

Expected: "Hello, Grace!"
Received: "Hello, Ada!"

 ❯ test/greet.test.js:6:26
      4| describe('greet', () => {
      5|   it('greets by name', () => {
      6|     expect(greet('Ada')).toBe('Hello, Grace!');
       |                          ^
      7|   });
      8|

⎯⎯⎯⎯⎯⎯ Failed Tests 1 ⎯⎯⎯⎯⎯⎯

 Test Files  1 failed | 1 passed (2)
      Tests  1 failed | 12 passed (13)
```

Exit code **1**.

Every part of that output earns its place:

- `FAIL test/greet.test.js > greet > greets by name` — the **full path** of the
  question. `greet.test.js` alone is not enough when you have hundreds of files;
  this is the string to paste into a search.
- `expected 'Hello, Ada!' to be 'Hello, Grace!'` — the one-line version, for
  scanning.
- `Expected` / `Received` — the same information, laid out so you cannot
  reverse it by accident.
- `test/greet.test.js:6:26` — file, line, column of the **assertion**, which is
  not always the line of the bug. `6:26` is the `.toBe(...)` call.
- The printed source with a caret. No need to open the file to see what it
  said.
- `1 failed | 1 passed (2)` at *file* level and `1 failed | 12 passed (13)` at
  *test* level. Two different denominators, and conflating them is a common
  source of confusion when only some tests in a file fail.

In the workflow this becomes a red step, `Run tests` goes red, and the job goes
red. On a pull request it additionally becomes an annotation on the diff, via
Vitest's own reporter.

### Coverage, and the threshold doing its job

`npm run coverage` is `vitest run --coverage`, and `vitest.config.js` configures
the v8 provider with a **90% line threshold**:

```js
coverage: {
  provider: 'v8',
  include: ['src/**/*.js'],
  reporter: ['text', 'json', 'html'],
  thresholds: { lines: 90 },
}
```

Real output on the current code:

```
 % Coverage report from v8
----------|---------|----------|---------|---------|-------------------
File      | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
----------|---------|----------|---------|---------|-------------------
All files |   93.33 |    71.42 |     100 |    92.3 |
 app.js   |   66.66 |     62.5 |     100 |   66.66 | 15
 greet.js |     100 |       75 |     100 |     100 | 4
----------|---------|----------|---------|---------|-------------------

=============================== Coverage summary ===============================
Statements   : 93.33% ( 14/15 )
Branches     : 71.42% ( 10/14 )
Functions    : 100% ( 8/8 )
Lines        : 92.3% ( 12/13 )
================================================================================
```

Exit code 0. Line coverage is 92.3%, above the 90 threshold, so the pipeline
passes. Note how narrow the margin is: **one more uncovered line and this goes
red.** That is a threshold doing its job, and also a threshold that will
eventually be annoying; chapter 35 covers where to set it.

Note also the honest reading of the table: `71.42%` branch coverage against
`100%` function coverage. The tests call every function and check the answer,
and only three-quarters of the *paths through* those functions. Nobody should
read "100% funcs" as "well tested".

Now the threshold firing. Append two untested functions to `src/sum.js` in a
throwaway copy and re-run:

```
----------|---------|----------|---------|---------|-------------------
File      | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
----------|---------|----------|---------|---------|-------------------
All files |   53.84 |    55.55 |   66.66 |      60 |
 app.js   |   66.66 |     62.5 |     100 |   66.66 | 15
 greet.js |     100 |       75 |     100 |     100 | 4
 sum.js   |   31.25 |    33.33 |   42.85 |      30 | 11-20
----------|---------|----------|---------|---------|-------------------

Lines        : 60% ( 12/20 )
================================================================================
ERROR: Coverage for lines (60%) does not meet global threshold (90%)
```

Exit code **1**. `Test Files 2 passed (2)` and `Tests 13 passed (13)` are
*still* printed above it, because all 13 tests did pass. That is a genuinely
useful design: the suite is green and the coverage gate is red, and the two
facts do not blur together. A project can add a well-written function with no
tests and be told so, without any test being "wrong".

## 5. When to use it and when NOT to

**Use a test step when:**

- **Always.** A build without tests is a build that reports only whether it
  compiled.
- **The failure output is good enough to act on.** If reading a red step takes
  more than a minute, the reporter is wrong, not you. This project prints
  expected, received, file, line, column, and source.
- **You want the exit code to be the only contract.** One command, one number.
  Then branch protection, deployment gates, and "why is main red" all reduce to
  one question.

**Do NOT reach for a test step when:**

- **The suite is the slowest thing in the pipeline and nobody reads it.** Fix the
  suite, not the gate. Skipping tests to go faster is how you get a fast,
  useless pipeline.

- **Tests assert on implementation details.** `expect(internal._cache).toBeNull()`
  fails on a refactor that changed nothing. Symptom: a commit that only renames
  something is red, and the team learns to `git push --no-verify`. Fix: assert
  on the public behaviour.

- **You add retries to hide flakiness.** `retries: 3` converts a 3% flake rate
  into a pipeline that lies. It also converts a real intermittent bug into an
  intermittent bug nobody investigates. Vitest's summary *does* report flaky
  tests, which means you can see them without hiding them — use that instead.

- **`npm test` in a repo with no tests yet.** It passes, and it will keep
  passing while you forget. A step that cannot fail teaches you nothing. Either
  write one test, or do not add the step yet. Testing the build output as your
  only safety net has the same problem from the other end: `node dist/app.js`
  catches a broken *bundle*, not broken logic. Both, as chapter 14 does.

## 6. Common mistakes

- **`npx vitest` instead of `npm test`.** Symptom: the step never finishes, the
  job hangs for `timeout-minutes`, the run is cancelled, minutes gone, no
  output. This is the single most common way to burn a month's minutes in an
  afternoon. Fix: use the package script, which already says `vitest run`, and
  keep `timeout-minutes` as the backstop for when someone forgets.

- **Reading a failure as "the code is broken".** Re-read: `Received` is a fact.
  The first question is whether the *test* is stale.

- **Retrying a flaky test until it passes.** Symptom: a pipeline that is
  sometimes red for no reason, and a team that stops reading it. Section 2 has
  the causes.

- **Tests that depend on each other's side effects.** Symptom: passes alone,
  fails in the suite, or fails only on CI where the file order differs. Fix:
  `beforeEach` cleanup, per-test temp directories.

- **Asserting on log output or on timing, or on the real current time.**
  Symptom, in all three cases: a failure that reproduces once a week and is
  never reproducible. `expect(now.getFullYear()).toBe(2026)` passes in 2026 and
  fails in 2027 in a way that looks exactly like a real bug. Fix: assert on
  return values, and inject the clock.

- **Coverage as a target people write tests to.** Symptom: 100% coverage and
  tests that call a function and assert `true`. Coverage measures execution, not
  verification, and the threshold is there to stop coverage *dropping*, not to
  be climbed. Chapter 35.

- **Copying a coverage report into Git as an artifact every commit.** It is a
  build output, not a source of truth. Read the number from the log.

- **Parsing the test output to decide anything.** If a step needs to know how
  many tests failed in order to behave differently, that is a bug in the design.
  The exit code already told you, and it is the only thing that cannot lie.

- **`continue-on-error: true` on the test step.** Chapter 05 showed what that
  looks like: a red step inside a green job. On a test step it means the gate
  does not exist.

## 7. Try it yourself

**Exercise: make a test fail, read it properly, then decide whether the code or
the test is wrong.**

The second half is the point. Most people do the first half and stop.

1. Work in a copy:

   ```bash
   rm -rf /tmp/test-lab
   cp -r cicd-learn /tmp/test-lab
   cd /tmp/test-lab
   ```

2. Read the assertion you are about to break, and note the two sides:
   the argument (`'Ada'`) and the expectation (`'Hello, Ada!'`).

   ```bash
   sed -n '4,8p' test/greet.test.js
   ```

3. Break the **expectation**, as in section 4:

   ```bash
   sed -i "6s/.*/    expect(greet('Ada')).toBe('Hello, Grace!');/" test/greet.test.js
   npm test ; echo "exit=$?"
   ```

   Read `Expected` and `Received` out loud, in that order, without looking at
   the source.

4. Now decide, and write the reason down. `Received: "Hello, Ada!"` is what
   `greet('Ada')` actually does. The test asks for Grace. Which one is the bug?
   In this case: **neither** — the test was edited wrongly on purpose. That
   answer is the goal. Real bugs look identical and the habit is what transfers.

5. Now break the **argument** instead, which is a more realistic mistake:

   ```bash
   sed -i "6s/.*/    expect(greet('Ada ')).toBe('Hello, Ada!');/" test/greet.test.js
   npm test 2>&1 | sed -n '/FAIL/,/⎯⎯/p'
   ```

   `greet` trims whitespace, so this actually still passes. Find an input that
   makes it fail, and note how different the two failure messages read. That
   difference is what you are learning to navigate by.

6. **Break the pipeline on purpose, the way that actually happens in the wild.**
   Replace the script:

   ```bash
   node -e "
     const p = require('fs');
     const j = JSON.parse(p.readFileSync('package.json'));
     j.scripts.test = 'vitest';
     p.writeFileSync('package.json', JSON.stringify(j, null, 2));
   "
   npm test
   ```

   It never exits. That is watch mode. `Ctrl-C`, then look at what a CI job
   would do: nothing, for `timeout-minutes`, at 360 by default. This is why the
   job has `timeout-minutes: 10`.

7. Finally, watch a threshold fail. Copy the working tree again, append two
   untested functions to `src/sum.js`, and run `npm run coverage`. Look for
   `Tests 13 passed (13)` **and** `ERROR: Coverage for lines (60%) does not meet
   global threshold (90%)` in the same output. Green suite, red gate, exit 1.

**Hint:** to see the whole thing as the pipeline sees it:

```bash
./scripts/verify.sh .github/workflows/13-test-step.yml test push ch13
```

**What this exercise proves:** the exit codes, the exact failure text, the
source of every field in it, and the coverage threshold behaviour. **What it
cannot prove:** that the failing test appears as an annotation on the pull
request diff, or that branch protection blocks the merge — both require a hosted
run with the repository configured, which is chapter 34.

## 8. Next

Your code is now shown to behave. It has not been shown to *package*.

Chapter 14 runs the esbuild bundler, which fails in ways lint and tests cannot
see, and then runs the output it produced — because a build nobody executes is
a build that ships broken.

→ [14 — The build step](14-build-step.md)