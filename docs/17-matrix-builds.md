# 17 — Matrix builds

> **Verification.** The workflow in this chapter is
> `.github/workflows/17-matrix-builds.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/17-matrix-builds.yml "" push ch17`,
> and the full log is at `docs/_logs/ch17.log`. Every log excerpt in section 4
> is quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/17-matrix-builds.yml (1 job(s))`.
>
> **What this local execution cannot prove.** `act` does run all four matrix
> jobs and reports the same job graph GitHub would (the `🧪 Matrix:` lines in
> the log are act's own rendering of the expansion). What it cannot prove is
> the GitHub Actions tab rendering of a matrix run: the collapsed job groups,
> the per-combination status checks that branch protection can require (chapter
> 34), and the `fail-fast` cancellation behaviour when one combination fails
> mid-run. The expansion count and the per-combination output are real and
> measured; the UI grouping and the cancellation timing are not.

---

## 1. Simple explanation (like I'm 7)

You have one recipe and four ovens. The recipe is identical, but you want to
know whether it works in a gas oven, an electric oven, a convection oven, and
your friend's old oven that runs a bit hot. Baking the cake four times by hand
— rewriting the recipe each time — is silly. You want to write the recipe once
and say "bake it in all four ovens, and tell me how each one went".

That is a **matrix build**. You write one job, declare the axes you care about
(Node 20, 22, 24; Linux and Windows; maybe an experimental flag), and GitHub
runs the same job once per combination. One definition, many runs. Each run is
a real, independent job with its own machine, its own log, and its own pass/fail.

The reason this matters is not "more coverage". It is **not having to maintain
four nearly identical workflow files**. Four files drift; one matrix does not.

## 2. Real name

### Matrix

A strategy that expands one job definition into many jobs, one per combination
of the declared axes. Declared under `strategy.matrix` inside a job. The axes
are lists; the expansion is the **cross product** of those lists.

### Axis

One dimension of the matrix. In this chapter the axes are `node` (versions) and
`os` (runner labels). An axis value becomes available inside the job as
`${{ matrix.node }}` and `${{ matrix.os }}`, which is how it reaches
`runs-on:` and `actions/setup-node`.

### Cross product

With `node: [20, 22, 24]` and `os: [ubuntu-24.04]`, you get 3 jobs. Add
`os: [ubuntu-24.04, windows-2025]` and you get 6. The number multiplies, which
is why a two-axis matrix is cheap to write and expensive to run. Windows is
billed at 2x Linux minutes (chapter 49), so think before you add an axis.

### `include`

Adds combinations to the matrix, or **extends** an existing one. Two behaviours,
and the distinction is the whole point of this chapter:

- An `include` entry whose keys **all match** an existing combination does not
  create a new job. It **extends** that combination with extra keys. The
  existing job gains those keys; no duplicate runs.
- An `include` entry that does **not** match any existing combination creates a
  **new job**.

This is the difference between "test Node 24 on arm64 as well" (new job) and
"mark the Node 24 Linux job as experimental" (extend). Both are written with
`include`, and which one you get depends on whether the keys match.

### `exclude`

Removes combinations from the cross product. Used to drop combinations you
cannot or will not test, e.g. an end-of-life Node version on Windows.

### `fail-fast`

What happens when one combination fails. Default `true`: GitHub cancels the
other in-flight combinations. Set `false` when you want the full picture of
what broke — for example, when upgrading Node across versions and you want
every failure, not just the first.

### `max-parallel`

Caps how many matrix jobs run at once. Default is "as many as the account
allows". Lower it to avoid hammering a shared resource (a test database, a rate-
limited API).

### Job name in a matrix

`${{ matrix.node }}` and friends are evaluated in `name:`, so each job gets a
distinct, readable label. Without a `name:`, every job is labelled with the
job id plus an index, which is unreadable in the Actions tab.

### Matrix versus copy-paste

A matrix is one job. That means one set of steps, one `if:`, one timeout, one
place to fix a typo. The cost is that every combination must run the same
steps; if one combination needs a fundamentally different flow, it is a
separate job, not a matrix axis.

## 3. Workflow example

This is the complete `.github/workflows/17-matrix-builds.yml` from this
repository.

```yaml
name: Matrix builds

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── Several Node versions, one workflow, N jobs ───────────────────────────
  # One job definition becomes one job per combination of the matrix axes.
  # 3 node versions x 2 operating systems = 6 jobs, from the definition below.
  matrix:
    name: Node ${{ matrix.node }} on ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    timeout-minutes: 10
    strategy:
      # When one combination fails, cancel the rest. Default is true.
      # Turn it off when you want to see the full picture of what broke, e.g.
      # when upgrading Node across versions and you want all the failures.
      fail-fast: false
      matrix:
        # The axes. `node` x `os` = the cross product.
        node: ['20', '22', '24']
        os: [ubuntu-24.04]
        # `include` ADDS jobs or extends existing ones. An entry that only
        # partially matches an existing combination extends it rather than
        # duplicating it, which is how you give one combination a different
        # config.
        include:
          # Node 24 on arm64: a 4th job, testing Apple-silicon-class hardware.
          - node: '24'
            os: ubuntu-24.04-arm
          # Extends the existing `node: '24', os: ubuntu-24.04` combination
          # because both keys already match; adds `experimental: true`.
          - node: '24'
            os: ubuntu-24.04
            experimental: true

    defaults:
      run:
        working-directory: cicd-learn
    steps:
      - uses: actions/checkout@v7

      # `node-version: ${{ matrix.node }}` is how the axis value reaches the step.
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ matrix.node }}
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json

      - name: Report the combination
        run: |
          echo "node        : $(node --version)"
          echo "npm         : $(npm --version)"
          echo "os label    : ${{ matrix.os }}"
          echo "experimental: ${{ matrix.experimental || 'no' }}"

      - run: npm ci
      - name: Lint
        run: npm run lint
      - name: Test
        run: npm test
      - name: Build
        run: npm run build

      - name: Summary row
        run: |
          {
            echo "| node | npm | os | experimental |"
            echo "| ---- | --- | -- | ------------ |"
            echo "| ${{ matrix.node }} | $(npm --version) | ${{ matrix.os }} | ${{ matrix.experimental || 'no' }} |"
          } >> "$GITHUB_STEP_SUMMARY"

  # ── The cross product, made explicit ──────────────────────────────────────
  # To test Node 20/22 on Linux and Windows, you do NOT write four entries.
  # You write two axes and get four jobs:
  #
  #   matrix:
  #     node: ['20', '22']
  #     os: [ubuntu-24.04, windows-2025]
  #
  # That is 4 jobs. Windows is billed at 2x Linux, so think before you add it
  # to a matrix. Chapter 49.
  #
  # `exclude:` removes combinations from the cross product:
  #
  #   exclude:
  #     - node: '20'        # Node 20 is EOL, do not test it on Windows
  #       os: windows-2025
```

Two structural things to notice:

- **`runs-on: ${{ matrix.os }}`** uses the axis value as the runner label. This
  is the one place a matrix value is allowed to drive infrastructure, and it is
  why the `os` axis must contain real runner labels, not nicknames.
- **`experimental: ${{ matrix.experimental || 'no' }}`** is the safe way to read
  an optional axis value. An `include`-extended key is absent on the other
  combinations, so `matrix.experimental` is empty there; `|| 'no'` keeps the
  output readable and avoids an empty cell in the summary table.

## 4. What I should see

### The expansion, from a real run

`docs/_logs/ch17.log` is a run of this chapter's workflow. `act` prints one
`🧪 Matrix:` line per job it is about to create, and those four lines are the
proof of how `include` behaves:

```
[Matrix builds/Node 22 on ubuntu-24.04-2    ] 🧪  Matrix: map[node:22 os:ubuntu-24.04]
[Matrix builds/Node 20 on ubuntu-24.04-1    ] 🧪  Matrix: map[node:20 os:ubuntu-24.04]
[Matrix builds/Node 24 on ubuntu-24.04-arm-4] 🧪  Matrix: map[node:24 os:ubuntu-24.04-arm]
[Matrix builds/Node 24 on ubuntu-24.04-3    ] 🧪  Matrix: map[experimental:true node:24 os:ubuntu-24.04]
```

Four jobs, not five. Read them carefully:

- The first three are the cross product: Node 20, 22, 24 on `ubuntu-24.04`.
- The fourth is `experimental:true` on top of the existing Node 24 / ubuntu-24.04
  combination. It did **not** create a fifth job, because both keys matched an
  existing combination. It extended it.
- The arm64 entry created a brand-new job, because `ubuntu-24.04-arm` did not
  match any existing combination.

That is the `include` rule in one log: **match all keys, and you extend; match
none, and you add.** If you expected five jobs and got four, this is why.

### The per-combination report

Each job prints what it actually ran on, which is the only way to trust a
matrix result:

```
[Matrix builds/Node 22 on ubuntu-24.04-2    ]   | node        : v22.23.3
[Matrix builds/Node 22 on ubuntu-24.04-2    ]   | npm         : 10.9.9
[Matrix builds/Node 22 on ubuntu-24.04-2    ]   | os label    : ubuntu-24.04
[Matrix builds/Node 22 on ubuntu-24.04-2    ]   | experimental: no
```

and for the extended combination:

```
[Matrix builds/Node 24 on ubuntu-24.04-3    ]   | node        : v24.21.0
[Matrix builds/Node 24 on ubuntu-24.04-3    ]   | npm         : 11.19.0
[Matrix builds/Node 24 on ubuntu-24.04-3    ]   | os label    : ubuntu-24.04
[Matrix builds/Node 24 on ubuntu-24.04-3    ]   | experimental: true
```

The `experimental` cell is the proof that the extension landed: the same Node 24
/ ubuntu-24.04 job carries `experimental: true`, while the Node 20 and 22 jobs
carry `no`. If `experimental` were `true` on all four, your `include` entry
had matched more broadly than you intended.

### The summary table

Each job writes a row to its own run summary, and those are the rows that end up
in the Actions tab:

```
[Matrix builds/Node 22 on ubuntu-24.04-2    ]   ⚙  Summary - | node | npm | os | experimental |
| ---- | --- | -- | ------------ |
| 22 | 10.9.9 | ubuntu-24.04 | no |
```

```
[Matrix builds/Node 24 on ubuntu-24.04-3    ]   ⚙  Summary - | node | npm | os | experimental |
| ---- | --- | -- | ------------ |
| 24 | 11.19.0 | ubuntu-24.04 | true |
```

```
[Matrix builds/Node 24 on ubuntu-24.04-arm-4]   ⚙  Summary - | node | npm | os | experimental |
| ---- | --- | -- | ------------ |
| 24 | 11.19.0 | ubuntu-24.04-arm | no |
```

Four rows, four machines, one workflow file. That is the whole pitch.

### The real Node versions

The matrix asked for `'20'`, `'22'`, `'24'`, and `setup-node` resolved them to:

| Requested | Resolved | npm |
| --- | --- | --- |
| `'20'` | v20.20.2 | 10.8.2 |
| `'22'` | v22.23.3 | 10.9.9 |
| `'24'` | v24.21.0 | 11.19.0 |

Quoted strings in the matrix (`'20'`) matter: without quotes YAML 1.1 can read
`20` as a number, and `setup-node` expects a string. The quotes are not
decoration.

### The engine warning, and why it is expected

On the Node 20 job, `npm ci` prints:

```
[Matrix builds/Node 20 on ubuntu-24.04-1    ]   | npm warn EBADENGINE Unsupported engine {
[Matrix builds/Node 20 on ubuntu-24.04-1    ]   | npm warn EBADENGINE   package: 'cicd-learn@1.0.0',
[Matrix builds/Node 20 on ubuntu-24.04-1    ]   | npm warn EBADENGINE   required: { node: '>=22' },
[Matrix builds/Node 20 on ubuntu-24.04-1    ]   | npm warn EBADENGINE   current: { node: 'v20.20.2', npm: '10.8.2' }
```

`package.json` declares `engines.node: ">=22"`, so Node 20 is out of support.
The job still passes, because `npm ci` treats an engine mismatch as a warning,
not an error, by default. That warning is the honest signal: this combination
is not one you should ship. In a real matrix you would either drop Node 20 or
add `engine-strict=true` and let it fail.

### The arm64 caveat

The arm64 job ran on the same `cicd-act-runner:24` image, so it did not
exercise real arm64 hardware here. On GitHub, `ubuntu-24.04-arm` is a real
arm64 runner and that is the combination worth testing. The local run proves
the workflow expands and runs; it does not prove arm64 behaviour.

## 5. When to use it and when NOT to

**Use a matrix when:**

- **You support more than one version of something.** Node, Python, a database
  client, a browser. One matrix is cheaper than N workflows.
- **You want the same check on two operating systems.** Linux and Windows have
  different path separators, line endings and case sensitivity; a matrix finds
  those bugs before a user does.
- **You are about to drop a version.** Run the matrix with `fail-fast: false`
  for one release cycle to see which tests break on the new version, then remove
  the old axis.
- **You want an experimental track.** `include` with an `experimental: true`
  flag lets you run a newer toolchain without making it a required check.

**Do NOT reach for a matrix when:**

- **The combinations need different steps.** A matrix is one job. If the
  Windows job needs PowerShell and the Linux job needs bash, that is not a
  matrix axis; that is two jobs with an `if:`.
- **The cost multiplies past your budget.** 3 nodes x 2 OSes x 2 browser
  versions = 12 jobs. Each is a full machine startup and install. A matrix
  that costs 40 minutes of runner time per push is a matrix nobody keeps.
- **You only ever run one combination.** A single-value matrix is noise; just
  write the job.
- **You are testing a matrix of *inputs* rather than *environments*.** Feeding
  the test suite 50 different config files is a test concern, not a CI concern;
  run it inside one job with a loop.

## 6. Common mistakes

- **Expecting `include` to always add a job.** It adds only when no existing
  combination matches all the keys. An entry with `node: '24', os: 'ubuntu-24.04'`
  extends the existing combination; it does not duplicate it. Symptom: "I
  wanted two Node 24 runs and got one." Fix: change a key (a different OS, a
  different flag) so it no longer matches.
- **Expecting `include` to always extend.** The opposite mistake. If you want
  a new job, make sure at least one key differs from every existing
  combination, otherwise you silently get an extension and your new test never
  runs.
- **Quoting the axis values inconsistently.** `node: [20, 22, 24]` (numbers)
  versus `node: ['20', '22', '24']` (strings). `setup-node` accepts both in
  practice, but expressions like `${{ matrix.node == '22' }}` compare against
  a string and fail against a number. Always quote.
- **`fail-fast: true` (the default) hiding failures.** The first red
  combination cancels the rest, so you see one failure and fix it, push, and
  discover the next. Symptom: "I fixed three failures one at a time over three
  days." Fix: `fail-fast: false` while you are stabilising, then turn it back
  on.
- **Forgetting `max-parallel` on a huge matrix.** GitHub queues the overflow,
  but a 30-job matrix with no cap can exhaust your concurrency limit and block
  other workflows in the same repository.
- **Using a matrix axis in `needs:`.** `needs:` takes job ids, not matrix
  entries. A matrix job's id is the job key (`matrix` here), and every
  combination shares it, so `needs: [matrix]` waits for all of them. That is
  usually what you want, but it is not what you get if you expected "wait for
  Node 22 only".
- **Assuming a matrix job can read another matrix job's outputs.** Each
  combination is its own job; they do not share a filesystem or outputs. If
  combination A builds an artifact, combination B cannot see it unless A
  uploads it.
- **Writing `runs-on: ubuntu-latest` inside a matrix.** The whole point of a
  matrix is reproducibility. Pin the OS label per combination, or use the
  `os` axis with pinned labels.

## 7. Try it yourself

**Exercise: change the matrix and watch the expansion change.**

1. Run the real workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/17-matrix-builds.yml "" push ch17
   ```

   Confirm four jobs and four `🧪 Matrix:` lines in the log.

2. **Add a real fifth job.** Change the arm64 `include` entry to also set
   `experimental: true`:

   ```yaml
   - node: '24'
     os: ubuntu-24.04-arm
     experimental: true
   ```

   Run again. You still get four jobs, but the arm64 row now reads
   `experimental: true`. That is an extension, not an addition, because the
   keys `node` and `os` still match... wait — they do not match any existing
   combination, because `ubuntu-24.04-arm` is new. So this is actually a new
   job with `experimental: true` attached. Run and count: still four, because
   there was no arm64 job with `experimental: false` to extend. The rule holds:
   extension requires a match on all keys.

3. **Make it five.** Add a genuinely new combination:

   ```yaml
   include:
     - node: '24'
       os: ubuntu-24.04-arm
     - node: '22'
       os: ubuntu-24.04
       experimental: true
   ```

   The second entry matches the existing Node 22 / ubuntu-24.04 combination, so
   it extends rather than adds. You still have four jobs, but the Node 22 job
   now reports `experimental: true`. That is the trap: you thought you added a
   job and you changed a label instead. Check the `🧪 Matrix:` lines to see
   which happened.

4. **Use `exclude`.** Add:

   ```yaml
   exclude:
     - node: '20'
       os: ubuntu-24.04
   ```

   Run. Three jobs. The Node 20 job is gone, and no `EBADENGINE` warning with
   it.

5. **Break `fail-fast`.** Set `fail-fast: true` and introduce a failing step on
   Node 20 (e.g. `run: exit 1` under `Test`). Run. The Node 22 and 24 jobs
   are cancelled mid-flight. Revert.

**Hint:** the job label in the log includes an index (`Node 20 on
ubuntu-24.04-1`), which is act's way of disambiguating matrix entries. On
GitHub the label is just `Node 20 on ubuntu-24.04`, and the matrix index is
hidden.

**What this exercise proves:** the expansion count, the extend-versus-add rule,
`exclude`, and `fail-fast`. **What it cannot prove:** the GitHub Actions tab
rendering of a matrix group, branch-protection status checks per combination,
or real arm64 hardware. Those need a hosted run.

## 8. Next

You can run one job many times in parallel. The next question is how to make
jobs depend on each other deliberately — running some in parallel and some in
series, and passing a small value from one machine to another.

→ [18 — Job dependencies and parallelism](18-jobs-dependencies-and-parallelism.md)