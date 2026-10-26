# 35 — Code coverage

> **Verification.** The workflow in this chapter is
> `.github/workflows/35-code-coverage.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/35-code-coverage.yml coverage push ch35`,
> and the full log is at `docs/_logs/ch35.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/35-code-coverage.yml (1 job(s))`. The threshold and
> the numbers below come from `cicd-learn/vitest.config.js` and from the
> measured run of `npm run coverage` inside that log.
>
> **What this local execution cannot prove.** `act` runs Vitest in a container
> without a CI-agent environment variable, so the text table in the local log
> still lists `sum.js` (100% covered). On a real GitHub runner, Vitest
> detects the agent and sets `skipFull: true`, which hides fully-covered
> files from the printed table. The numbers, the threshold behaviour, and the
> exit code are real; only that display difference is environment-dependent.

---

## 1. Simple explanation (like I'm 7)

Imagine you are a teacher and you want to know whether your lessons reached
every student. One way is to ask: "Did anyone learn anything?" and check that
at least one student raised their hand. That is a test passing. It tells you
something worked, but not how much of the class was reached.

Code coverage asks a different question: "Of everything I taught, how much did
at least one student hear?" It is a map of the parts of your code that ran
during the tests, coloured in. Green where a test touched it, red where no
test ever reached.

The trap is thinking green means "correct." Green only means "executed." A
test can run a line, assert nothing useful, and still colour it green. So
coverage is a *floor*, not a *ceiling*: it tells you what you definitely did
not test, never what you definitely did.

## 2. Real name

### Code coverage

A measurement of how much of the source code is executed while the test suite
runs. Usually expressed as a percentage per metric: statements, branches,
functions, lines.

### Statement coverage

The percentage of executable statements that ran at least once. The finest
grained and the most commonly quoted number.

### Branch coverage

The percentage of decision branches (the two sides of an `if`, the cases of a
`switch`, the short-circuit of `&&`/`||`) that were taken at least once. The
hardest metric to get to 100%, and the most useful one, because a line can
run while only one of its branches is ever exercised.

### Function coverage

The percentage of declared functions that were called at least once.

### Line coverage

The percentage of source lines that executed. Coarser than statement coverage
but easier to read in a report.

### Coverage threshold

A minimum percentage configured in the test tool. If the measured coverage
falls below it, the command exits non-zero and the CI step fails. This is
how coverage becomes a gate instead of a report.

### `skipFull`

A reporter option (Vitest/V8) that omits fully-covered files from the printed
text table. On CI it is turned on automatically when a CI agent is detected,
so the table shows only the files that still need attention.

### Coverage report (HTML / JSON)

The detailed, file-by-file output. The text table is a summary; the HTML
report lets you click into a file and see which lines are red.

## 3. Workflow example

This is the complete `.github/workflows/35-code-coverage.yml` from this
repository.

```yaml
name: Code coverage

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  coverage:
    name: Test with coverage
    runs-on: ubuntu-24.04
    timeout-minutes: 10
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

      # Coverage is the same tests plus a coverage report. The threshold is
      # configured in vitest.config.js: lines: 90. If coverage drops below it,
      # `npm run coverage` exits non-zero and the step fails.
      - name: Run tests with coverage
        id: cov
        run: npm run coverage

      - name: Upload the HTML report as an artifact
        uses: actions/upload-artifact@v7
        with:
          name: coverage-report
          path: cicd-learn/coverage
          retention-days: 14
          if-no-files-found: error

      - name: What the text report actually shows
        run: |
          echo "On CI the text table hides 100%-covered files (skipFull is true"
          echo "when Vitest detects a CI agent). So `sum.js`, which is 100%"
          echo "covered on every metric, does not appear in the printed table even"
          echo "though it is in coverage-final.json. That is expected, not a bug."
```

Four structural things to notice:

1. Coverage runs as part of the test step, not as a separate job. There is
   no point running tests twice; `npm run coverage` runs the tests and
   measures them in one pass.
2. The threshold lives in `vitest.config.js` (`lines: 90`), not in the
   workflow. The workflow only calls `npm run coverage` and trusts the exit
   code. This keeps the policy in the code, where reviewers can see it.
3. The HTML report is uploaded as an artifact with a 14-day retention. A
   coverage percentage in a log is not actionable; the report, which shows
   the red lines, is.
4. The final step documents a display quirk (`skipFull`) so the next person
   who reads the log does not file a bug about a "missing" file.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch35.log` runs the `coverage` job end to end. Vitest runs all 13
tests and prints the coverage table:

```
[Code coverage/Test with coverage]   |  % Coverage report from v8
[Code coverage/Test with coverage]   | ----------|---------|----------|---------|---------|-------------------
[Code coverage/Test with coverage]   | File      | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
[Code coverage/Test with coverage]   | ----------|---------|----------|---------|---------|-------------------
[Code coverage/Test with coverage]   | All files |   93.33 |    71.42 |     100 |    92.3 |                   
[Code coverage/Test with coverage]   |  app.js   |   66.66 |     62.5 |     100 |   66.66 | 15                
[Code coverage/Test with coverage]   |  greet.js |     100 |       75 |     100 |     100 | 4                 
[Code coverage/Test with coverage]   |  sum.js   |     100 |      100 |     100 |     100 |                   
[Code coverage/Test with coverage]   | ----------|---------|----------|---------|---------|-------------------
```

The numbers to remember:

| Metric | Value |
| ------ | ----- |
| Statements | 93.33% |
| Branches | 71.42% |
| Functions | 100% |
| Lines | 92.3% |

The threshold is `lines: 90`. The measured 92.3% is above it, so the step
passes. Had it been 89.9%, `npm run coverage` would have exited non-zero and
the job would be red, even though every test passed.

The artifact upload is simulated locally (act's artifact server is too old
for `upload-artifact@v7`), but the step reports success:

```
[Code coverage/Test with coverage]   | SIMULATED upload of cicd-learn/coverage as coverage-report
[Code coverage/Test with coverage]   ✅  Success - Main [simulated upload-artifact: coverage-report] [90.892852ms]
```

The final step prints its explanation of the `skipFull` behaviour:

```
[Code coverage/Test with coverage]   | On CI the text table hides 100%-covered files (skipFull is true
[Code coverage/Test with coverage]   | /var/run/act/workflow/5: line 3: sum.js: command not found
[Code coverage/Test with coverage]   | when Vitest detects a CI agent). So , which is 100%
[Code coverage/Test with coverage]   | covered on every metric, does not appear in the printed table even
[Code coverage/Test with coverage]   | though it is in coverage-final.json. That is expected, not a bug.
```

The `sum.js: command not found` line is an artefact of the echo: the word
`sum.js` is unquoted in the shell and bash tries to execute it as a command.
The intent of the step is documentation, not computation, and the job stays
green.

### What a real GitHub run adds (not verified locally)

- **`skipFull` hides `sum.js`.** On a GitHub runner the text table shows only
  `All files`, `app.js`, and `greet.js`. `sum.js` is still in
  `coverage-final.json` and in the HTML report; it is only omitted from the
  console summary. This is why the log must never be the only place you check
  coverage.
- **The artifact is real.** `coverage-report` appears in the run's
  "Artifacts" section and can be downloaded, unzipped, and opened as
  `index.html` to see the red lines.
- **The threshold failure is a real exit code.** On GitHub the step fails
  with Vitest's threshold message, and the job turns red even though all
  tests passed. That distinction (tests green, coverage red) is the whole
  point of having a threshold.

### Reading the HTML report

The text table tells you *which* files are under-covered. The HTML report
tells you *which lines*. After a run, open `cicd-learn/coverage/index.html`
in a browser. Each file is colour-coded:

- **Green lines** executed during the tests.
- **Red lines** never executed.
- **Yellow lines** partially executed: the line ran, but only one branch of
  a condition was taken.

Clicking a file shows the line numbers. The "Uncovered Line #s" column in
the text table (line 15 in `app.js`, line 4 in `greet.js`) is the same
information in compact form. Use the column for a quick check, the HTML
report for a real investigation.

### Thresholds you can set

Vitest supports thresholds per metric and per file:

```js
coverage: {
  thresholds: {
    lines: 90,
    statements: 90,
    branches: 80,
    functions: 100,
    // Per-file thresholds are also possible:
    'src/app.js': { lines: 80 },
  },
  // Fail the run if a file has no tests at all:
  thresholdAutoUpdate: false,
}
```

Setting a per-file threshold is usually a mistake: it couples the policy to
the file layout and makes refactoring painful. Set one global threshold per
metric and let the report show where the gaps are.

### How V8 measures coverage

Vitest uses V8's built-in coverage, which instruments the code at the
engine level rather than transforming the source. That means:

- The numbers reflect the code *as executed*, including code paths triggered
  by dynamic imports and conditional requires.
- Source maps are used to map back to your original lines, so a bundled
  or transpiled file still reports against the source.
- Coverage is collected only for files that were imported during the test
  run. A source file that no test ever imports reports 0%, which is
  correct, but it also means an unused file drags the total down. Either
  test it or delete it.

## 5. When to use it and when NOT to

**Use coverage when:**

- **You want to know what is untested.** The red lines in the HTML report
  are the most actionable output of any CI run: "nobody has ever exercised
  this branch."
- **You want a ratchet.** A threshold that only goes up prevents coverage
  from silently eroding. Set it to today's number, and fail if it drops.
- **You review pull requests.** A coverage diff on a PR ("this change added
  40 lines, 30 of them untested") is a concrete, reviewable fact.
- **You have a legacy codebase.** Coverage tells you where the untested
  landmines are before you refactor.

**Do NOT:**

- **Do not chase 100%.** The last few percent are usually error paths and
  defensive branches that are hard to trigger and not worth testing. A
  threshold of 90% is a strong, honest number; 100% often produces tests
  that assert nothing.
- **Do not treat coverage as correctness.** 100% coverage with no
  assertions passes and proves nothing. Coverage measures execution, not
  verification. The tests still have to assert.
- **Do not set the threshold above your current number.** The first run
  fails immediately and the team disables the check. Set it to today's
  measured value and raise it deliberately.
- **Do not run coverage on every push if it is slow.** Coverage
  instrumentation can double test time. Run it on pull requests and on
  `main`, not on every commit to a feature branch.
- **Do not ignore branch coverage.** 93% statement coverage with 71% branch
  coverage means a quarter of the decisions are only ever taken one way. The
  untested branch is where the bug lives.

## 6. Common mistakes

- **Confusing "tests pass" with "code is covered."** Symptom: a green
  pipeline with 40% coverage. Fix: add the threshold so coverage is a
  separate, named failure.
- **Setting the threshold in the workflow instead of the config.** Symptom:
  the policy is invisible to anyone reading the code, and `npm run coverage`
  locally uses a different number. Fix: put `thresholds` in
  `vitest.config.js` (or the equivalent for your tool).
- **Forgetting that `skipFull` hides files on CI.** Symptom: a reviewer
  says "sum.js is not in the coverage report, did we delete it?" Fix:
  know the setting, and check `coverage-final.json` or the HTML report for
  the full list.
- **Measuring the wrong files.** Symptom: coverage is 100% because the
  config includes test files or generated code. Fix: restrict `include` to
  `src/**/*.js` (or equivalent) and exclude generated output.
- **Treating a coverage drop as a blocker without context.** Symptom: a PR
  that legitimately deletes dead code drops coverage and fails CI. Fix:
  allow the threshold to be a ratchet on the total, but review the diff
  rather than blindly rejecting.
- **Ignoring the HTML report.** Symptom: the team reads the percentage and
  never opens the report, so the red lines stay red for months. Fix: upload
  the report as an artifact and link to it in the PR.
- **Running coverage under a different Node version than tests.** Symptom:
  different numbers on CI and locally. Fix: pin the Node version in both
  (chapter 07).

## 7. Try it yourself

**Exercise: drop coverage below the threshold and watch the gate close.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/35-code-coverage.yml coverage push ch35
   ```

   Confirm the table shows 93.33% statements and 92.3% lines, and the step
   is green. That is the baseline.

2. **Drop below the threshold.** Open `cicd-learn/src/app.js` and add an
   untested branch:

   ```js
   export function report(name) {
     if (name === 'special') {   // new branch, never tested
       return 'special case';
     }
     // ... existing code
   }
   ```

   Re-run the coverage workflow. Lines drop below 90%, `npm run coverage`
   exits non-zero, and the job turns red even though all 13 tests still pass.
   That separation (tests green, coverage red) is the point of the
   threshold. Revert the edit.

3. **Raise the threshold to 100%.** Change `lines: 90` to `lines: 100` in
   `vitest.config.js` and re-run. It fails immediately, because `app.js` is
   at 66.66%. That is why 100% is not a good default. Revert.

4. **Look at the HTML report.** After a green run, open
   `cicd-learn/coverage/index.html` in a browser. Click `app.js` and find
   line 15 highlighted red. That is the uncovered line the table pointed at.

5. **Hide a file.** Set `skipFull: true` explicitly in `vitest.config.js`
   and re-run locally. `sum.js` disappears from the table. Confirm it is
   still in `cicd-learn/coverage/coverage-final.json`. Revert.

6. **Break it on purpose.** Delete the `thresholds` block entirely and
   re-run. Coverage is printed but nothing fails, no matter how low it goes.
   That is a report, not a gate. Restore the block.

**Hint:** the threshold is the only thing that makes coverage a CI concern
rather than a curiosity. Without it, nobody reads the report.

## 8. Next

You now know how much of the code the tests reach. The next chapter keeps the
dependencies themselves current, so the code you are measuring is not quietly
rotting underneath you.

→ [36 — Dependency updates with Dependabot](36-dependabot.md)