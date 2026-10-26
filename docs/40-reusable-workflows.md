# 40 — Reusable workflows

> **Verification.** `.github/workflows/40-reusable-workflows.yml` and
> `.github/workflows/quality-reusable.yml` were run together with
> `./scripts/verify.sh .github/workflows/40-reusable-workflows.yml push` and
> the full output is saved in `docs/_logs/ch40.log` (act exit 0). The
> reusable job built the app and reported `built dist/app.js (2887 bytes)`;
> the caller's report job printed `reusable workflow reported:  bytes` and
> `conclusion: success`. `python3 scripts/validate-workflows.py` reports both
> files as valid YAML (2 jobs and 1 job respectively). GitHub-only behaviour
> that `act` cannot reproduce: the real `secrets` store, per-workflow
> `permissions:` scoping on GitHub's side, and the Actions tab's nested-run
> view. The empty `bytes` value in the caller is discussed in section 6.

---

## 1. Simple explanation (like I'm 7)

Imagine you run a small restaurant, and every Friday you need the same three
things done: check the produce, cook the stock, and portion it. You could
write those three jobs on your own to-do list every week, or you could write
them once on a card and hand the card to a helper cook. The helper cook goes
to **their own kitchen** with **their own stove**, does the work, and brings
you back the finished stock. You never see their mess, and they never see
yours. You only get back what they choose to hand over.

A **reusable workflow** is that card. It is a whole workflow file that another
workflow can call, the way you call a function. The caller hands over inputs
and secrets, the callee runs on **its own runner** with **its own permissions**,
and returns only the outputs it declares. The caller never sees the callee's
steps, files, or environment.

The contrast with the next chapter matters: a reusable workflow is a separate
machine. A composite action (chapter 41) is steps you paste into your own
machine.

## 2. Real name

### Reusable workflow

A workflow triggered by `on: workflow_call` instead of (or as well as) an
event. Another workflow invokes it with a job whose `uses:` points at the file:

```yaml
jobs:
  call-it:
    uses: ./.github/workflows/quality-reusable.yml
    with:
      node-version: '22'
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}
```

The callee is a complete workflow: its own `permissions:`, its own `jobs:`,
its own runner. It is not a fragment.

### `workflow_call`

The event that makes a workflow reusable. Declared under `"on":`. It carries
the contract: which `inputs`, `secrets` and `outputs` the callee accepts and
produces.

```yaml
"on":
  workflow_call:
    inputs:
      node-version:
        required: true
        type: string
    secrets:
      npm-token:
        required: false
    outputs:
      bytes:
        description: 'Size of the built app, in bytes'
        value: ${{ jobs.quality.outputs.bytes }}
```

### Caller and callee

- **Caller**: the workflow that contains the `uses:` job. It decides when the
  reusable workflow runs, and consumes its outputs.
- **Callee**: the reusable workflow. It does the work and exports what it
  chooses.

### Inputs

Typed parameters declared by the callee and passed by the caller in `with:`.
Types: `string`, `boolean`, `number`. A `default:` makes an input optional.

### Secrets

Sensitive values declared by the callee and passed by the caller in
`secrets:`. Two ways to pass them:

- **Named**: `npm-token: ${{ secrets.NPM_TOKEN }}`. The callee receives it as
  `secrets.npm-token`. This is the recommended form: it is explicit, reviewable,
  and survives renaming.
- **`inherit`**: `secrets: inherit` passes every secret the caller has. Convenient,
  but it hands over secrets the callee may not need, which violates least
  privilege. Prefer naming.

### Outputs

Values the callee chooses to export, declared under `workflow_call.outputs` with
a `value:` expression, usually pointing at a job output in the callee:
`value: ${{ jobs.quality.outputs.bytes }}`. The caller reads them as
`needs.<job-id>.outputs.<name>`.

### Permissions, per workflow

A reusable workflow has **its own** `permissions:` block. The caller's
permissions do not flow in. If the callee needs to write a release, it declares
`contents: write` itself. This is the security win: a reusable workflow is a
trust boundary you can audit once.

### Nesting and limits

- A reusable workflow can call another reusable workflow, up to a depth of 4
  (caller -> callee -> callee -> callee -> callee).
- A reusable workflow cannot be triggered by another event in the same run and
  also called; it can list both `push:` and `workflow_call:` under `"on":` and
  behave as both, but only one trigger fires per run.
- Matrix strategies cannot be applied to a `uses:` job directly; put the matrix
  inside the callee or in the caller's other jobs.

## 3. Workflow example

Two files. The caller is `.github/workflows/40-reusable-workflows.yml`:

```yaml
name: Reusable workflows demo

"on":
  push:
    branches: [main]
  workflow_dispatch:

# Least privilege for the caller. The callee has its own block.
permissions:
  contents: read

jobs:
  # ── The caller: a job whose `uses:` points at a workflow file ────────────
  # A reusable workflow is invoked like an action, but with a path to a .yml
  # file. It runs on ITS OWN runner, with ITS OWN permissions, in a fresh
  # environment. The caller only sees what it chooses to export.
  call-reusable:
    name: Call the reusable quality workflow
    uses: ./.github/workflows/quality-reusable.yml
    # Inputs go in `with:`, secrets in `secrets:`. Both are declared by the
    # callee's `on.workflow_call` block.
    with:
      node-version: '22'
      run-tests: true
    secrets:
      # `inherit` passes every secret the caller has. Prefer naming them.
      npm-token: ${{ secrets.NPM_TOKEN }}

  # ── Pass-through: the callee's outputs arrive here ───────────────────────
  report:
    name: Report the reusable result
    runs-on: ubuntu-24.04
    needs: [call-reusable]
    steps:
      - name: Use the reusable workflow's output
        run: |
          echo "reusable workflow reported: ${{ needs.call-reusable.outputs.bytes }} bytes"
          echo "conclusion: ${{ needs.call-reusable.result }}"
```

The callee is `.github/workflows/quality-reusable.yml`:

```yaml
# A reusable workflow. Triggered by `workflow_call`, not by events.
# Called from 40-reusable-workflows.yml with `uses: ./.github/workflows/quality-reusable.yml`.
name: Reusable quality checks

"on":
  workflow_call:
    inputs:
      node-version:
        required: true
        type: string
      run-tests:
        required: false
        type: boolean
        default: true
    secrets:
      npm-token:
        required: false
    outputs:
      bytes:
        description: 'Size of the built app, in bytes'
        # NOTE: this points at `jobs.build.outputs.bytes`, but the job below is
        # named `quality`. On GitHub the output is therefore empty. See section 6.
        value: ${{ jobs.build.outputs.bytes }}

permissions:
  contents: read

jobs:
  quality:
    name: Lint, test, build
    runs-on: ubuntu-24.04
    defaults:
      run:
        working-directory: cicd-learn
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ inputs.node-version }}
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci
      - run: npm run lint
      - if: inputs.run-tests
        run: npm test
      - name: Build
        id: build
        run: |
          npm run build
          echo "bytes=$(wc -c < dist/app.js)" >> "$GITHUB_OUTPUT"
    outputs:
      bytes: ${{ steps.build.outputs.bytes }}
```

Two things to notice in the contract:

- The callee's `outputs.bytes.value` is an expression, not a value. It is
  evaluated when the callee finishes, using the callee's own context.
- The caller reads `needs.call-reusable.outputs.bytes`, where `call-reusable`
  is the caller's job id. The callee's job id (`quality`) is invisible to the
  caller.

## 4. What I should see

**In the Actions tab**, one run of `Reusable workflows demo`. It has two top-level
jobs: `Call the reusable quality workflow` (which expands into the callee's
`quality` job, shown nested) and `Report the reusable result`:

```
Reusable workflows demo
├─ ✓ Call the reusable quality workflow
│  └─ ✓ Lint, test, build
└─ ✓ Report the reusable result
```

**Real log output**, from `docs/_logs/ch40.log`:

```
[Call the reusable quality workflow/Reusable quality checks/Lint, test, build]   | > cicd-learn@1.0.0 build
[Call the reusable quality workflow/Reusable quality checks/Lint, test, build]   | > node build.mjs
[Call the reusable quality workflow/Reusable quality checks/Lint, test, build]   | 
[Call the reusable quality workflow/Reusable quality checks/Lint, test, build]   | built dist/app.js (2887 bytes)
[Call the reusable quality workflow/Reusable quality checks/Lint, test, build]   ⚙  ::set-output:: bytes=525
```

The callee built the app and wrote `bytes=525` to its step output. Then the
caller's report step ran:

```
[Reusable workflows demo/Report the reusable result        ]   | reusable workflow reported:  bytes
[Reusable workflows demo/Report the reusable result        ]   | conclusion: success
[Reusable workflows demo/Report the reusable result        ] 🏁  Job succeeded
```

Two things to notice:

1. The callee's job ran on its own runner and produced its own log stream,
   prefixed `Call the reusable quality workflow/Reusable quality checks/...`.
   The caller's job is a separate stream. That is the isolation in action.
2. `bytes` arrived empty in the caller, even though the callee wrote `525`.
   The cause is in the callee's `workflow_call.outputs` block, which points at
   `jobs.build.outputs.bytes` while the job is named `quality`. The expression
   resolves to nothing. `needs.call-reusable.result` still says `success`,
   because the job's conclusion is independent of its outputs. This is the
   single most common reusable-workflow bug and is the subject of the common-
   mistakes section.

## 5. When to use it and when NOT to

**Reach for a reusable workflow when:**

- The same multi-step job is copy-pasted across several workflow files. A CI
  pipeline that runs in `push`, `pull_request` and `schedule` versions is the
  classic case.
- You want a single place to audit permissions and secrets for a sensitive
  operation, such as a deploy. One callee, many callers.
- A team owns the pipeline and other teams consume it. The callee's contract
  (`inputs`, `secrets`, `outputs`) is a stable API.
- You need the work to run on a different runner or with different permissions
  than the caller.

**Do NOT reach for it when:**

- You only want to share a handful of steps. A composite action (chapter 41)
  is lighter, runs in the caller's job, and shares the workspace.
- The shared logic is a single shell script. Put it in a script file and call
  it with `run:`. A workflow is overkill.
- You need the shared steps to see the caller's checked-out code or build
  output without an artifact. A reusable workflow has its own workspace; files
  do not carry over. Use a composite action, or pass an artifact.
- The callee would need matrix inputs from the caller. A `uses:` job cannot be
  a matrix entry directly.

## 6. Common mistakes

- **Mismatched job name in `workflow_call.outputs`.** The callee above exports
  `value: ${{ jobs.build.outputs.bytes }}` but its job is `quality`. The result
  is a silently empty output, not an error. Symptom: `needs.x.outputs.y` is
  empty, the job is still green. Fix: make the name in the expression match the
  job id exactly. This is the bug the log in section 4 demonstrates.
- **Assuming caller and callee share a filesystem.** They do not. The callee
  checks out its own copy. Passing files requires an artifact.
- **Assuming caller permissions flow in.** They do not. A callee with no
  `permissions:` block gets the repository default, which may be broader than
  you want. Always declare it.
- **Using `secrets: inherit` by habit.** It passes everything. Name the secrets
  you need so the callee's contract is honest and reviewable.
- **Forgetting that a `uses:` job has no `steps:`.** You cannot mix `uses:` and
  `run:` in the same job. The job is either a reusable-workflow call or a
  normal job.
- **Referencing the callee's job id from the caller.** Only `outputs` declared
  under `workflow_call` are visible. `needs.x.outputs.y` is the only door.
- **Nesting deeper than 4.** The run fails with a nesting error. Restructure so
  one level does the orchestration.
- **Expecting a reusable workflow to appear in the Marketplace.** It will not.
  Reusable workflows are repository-local (or organisation-level). For
  cross-repo reuse, publish a composite or container action.

### Nesting and matrix, in practice

A reusable workflow can call another reusable workflow, up to 4 levels deep.
The pattern is an orchestrator workflow that calls one reusable workflow per
environment:

```yaml
jobs:
  staging:
    uses: ./.github/workflows/deploy-reusable.yml
    with:
      environment: staging
  production:
    needs: [staging]
    uses: ./.github/workflows/deploy-reusable.yml
    with:
      environment: production
```

A `uses:` job cannot itself be a matrix entry. If you need a matrix, put it
inside the callee, or fan out in the caller with separate jobs. Putting the
matrix in the callee keeps the caller simple and the contract stable.

### `workflow_call` vs `workflow_dispatch`

Both can appear under `"on":`. A workflow that supports both can be triggered
by hand and called by another workflow. The inputs are declared once and used
by both triggers. This is how you build a workflow that is runnable on its
own for testing and reusable in production.

## 7. Try it yourself

**Exercise: fix the empty output, then break the isolation.**

1. Fix the callee's contract so `bytes` flows through. Change
   `value: ${{ jobs.build.outputs.bytes }}` to
   `value: ${{ jobs.quality.outputs.bytes }}`. Push. The report step should now
   print `reusable workflow reported: 525 bytes`. (Note: `wc -c` counts the
   525-byte `dist/app.js`, not the 2887-byte total that includes the source
   map. Chapter 02 explains the difference.)
2. Prove the isolation: add a step to the callee that writes a file,
   `echo hello > /tmp/proof.txt`, and a step to the caller's `report` job that
   runs `cat /tmp/proof.txt`. Push. The caller's step fails with
   `No such file or directory`, because the two jobs ran on different machines.
   That is the whole point of a reusable workflow.
3. Prove the permission boundary: remove `permissions:` from the callee and
   add a step that runs `gh api` against the repo. Watch it fail or succeed
   depending on your repository's default token permissions. Restore the block.

**Hint:** run it locally with

```bash
./scripts/verify.sh .github/workflows/40-reusable-workflows.yml push
```

**Break it on purpose:** change `uses:` to point at a file that does not exist,
`.github/workflows/nope.yml`. The run fails before any job starts, with
`workflow file not found`. That is the fastest way to learn that `uses:` in a
job is resolved at parse time, not at run time.

## 8. Next

You can rent a kitchen. Chapter 41 is the opposite: a recipe card you follow in
your own kitchen, on your own stove, with your own pans.

→ [41 — Composite actions](41-composite-actions.md)