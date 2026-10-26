# 41 — Composite actions

> **Verification.** `.github/workflows/41-composite-actions.yml` and
> `.github/actions/setup-node-app/action.yml` were run together with
> `./scripts/verify.sh .github/workflows/41-composite-actions.yml push` and
> the full output is saved in `docs/_logs/ch41.log` (act exit 0). The
> composite action checked out the repo, installed Node 22.23.3, ran
> `npm ci`, lint, test and build, and the following step found
> `cicd-learn/dist/app.js` (525 bytes) in the same workspace. `python3
> scripts/validate-workflows.py` reports the workflow as valid YAML with 1
> job. The composite action is verified with `--bind` so the shared-workspace
> behaviour is visible across steps. GitHub-only behaviour `act` cannot
> reproduce: the Marketplace publishing flow and action versioning.

---

## 1. Simple explanation (like I'm 7)

You have a kitchen (your job, your runner). You cook a lot of the same things:
boil water, chop onions, brown meat. Instead of writing those three steps on
every recipe, you write them once on a **recipe card** and file it in a drawer
labelled "basic prep". When a recipe says "do basic prep", you pull out the
card and follow its steps **in your own kitchen**, with your own pots, on your
own stove. The food stays in your kitchen the whole time.

A **composite action** is that recipe card. It is a directory of steps, packaged
under one name, that run **in the job that calls them**, on the same runner,
sharing the same workspace and the same files. Nothing is sent anywhere. The
caller sees every file the composite action created, because they were created
on the caller's own machine.

Compare with chapter 40: a reusable workflow is a separate kitchen. A composite
action is steps you paste into your own kitchen.

## 2. Real name

### Composite action

An action whose `runs.using` is `composite`. Its steps are ordinary workflow
steps (`uses:` or `run:`) that execute in the caller's job context. Declared in
an `action.yml` (or `action.yaml`) file inside a directory.

```yaml
name: 'Set up cicd-learn'
description: 'Checkout, install Node, npm ci, and optionally run the checks.'
inputs:
  node-version:
    description: 'Node.js version to install'
    required: false
    default: '22'
  run-checks:
    description: 'Whether to run lint, test and build after installing'
    required: false
    default: 'true'
runs:
  using: 'composite'
  steps:
    - uses: actions/checkout@v7
      with:
        fetch-depth: 1

    - uses: actions/setup-node@v7
      with:
        node-version: ${{ inputs.node-version }}
        cache: 'npm'
        cache-dependency-path: cicd-learn/package-lock.json

    - name: Install
      shell: bash
      working-directory: cicd-learn
      run: npm ci

    - name: Run the checks
      if: inputs.run-checks == 'true'
      shell: bash
      working-directory: cicd-learn
      run: |
        npm run lint
        npm test
        npm run build
```

### `action.yml` and the directory layout

A composite action lives in a directory under `.github/actions/` (for
repository-local use) or in its own repository (for reuse across repos). The
file must be named `action.yml` or `action.yaml`. The directory name is what
you reference:

```yaml
- uses: ./.github/actions/setup-node-app
```

### Inputs and outputs

- `inputs:` declares parameters, exactly like `workflow_call` inputs. They are
  strings by default, so compare them as strings (`inputs.run-checks == 'true'`).
- `outputs:` declares values the action hands back, mapped from a step's
  `$GITHUB_OUTPUT`. The caller reads them as `steps.<id>.outputs.<name>`.

### The one rule everyone forgets

**Every `run:` step inside a composite action must declare `shell:`.** In a
normal workflow, `run:` defaults to `bash` on Linux. Inside a composite
action there is no default shell, so a `run:` without `shell:` fails to parse
or fails at run time with "shell is required". This is the single most common
composite-action error and is worth memorising now.

### Three kinds of action, for contrast

| Kind | Runs where | Shares workspace | Needs Docker | Best for |
| ---- | ---------- | ---------------- | ------------ | -------- |
| Composite (`composite`) | In the caller's job | Yes | No | Bundling steps, sharing code |
| Reusable workflow (`workflow_call`) | Its own job/runner | No | No | Whole pipelines, permission boundaries |
| Container (`docker`) | In a container on the caller's runner | Via volumes | Yes | A tool with a complex runtime |

## 3. Workflow example

The caller is `.github/workflows/41-composite-actions.yml`:

```yaml
name: Composite actions demo

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  use-composite:
    name: Use a composite action
    runs-on: ubuntu-24.04
    steps:
      # A composite action is a directory of steps, packaged under one name.
      # Unlike a reusable workflow, it runs IN THIS JOB, on THIS runner, and
      # shares the workspace. That is the whole difference.
      - name: Set up the whole app with one composite action
        uses: ./.github/actions/setup-node-app
        with:
          node-version: '22'
          run-checks: 'true'

      - name: The workspace is shared, so this works
        run: |
          echo "composite actions run on the caller's runner, so the built"
          echo "output is simply here:"
          ls -l cicd-learn/dist/app.js
```

The composite action is `.github/actions/setup-node-app/action.yml`:

```yaml
name: 'Set up cicd-learn'
description: 'Checkout, install Node, npm ci, and optionally run the checks.'
inputs:
  node-version:
    description: 'Node.js version to install'
    required: false
    default: '22'
  run-checks:
    description: 'Whether to run lint, test and build after installing'
    required: false
    default: 'true'
runs:
  using: 'composite'
  steps:
    - uses: actions/checkout@v7
      with:
        fetch-depth: 1

    - uses: actions/setup-node@v7
      with:
        node-version: ${{ inputs.node-version }}
        cache: 'npm'
        cache-dependency-path: cicd-learn/package-lock.json

    - name: Install
      shell: bash
      working-directory: cicd-learn
      run: npm ci

    - name: Run the checks
      if: inputs.run-checks == 'true'
      shell: bash
      working-directory: cicd-learn
      run: |
        npm run lint
        npm test
        npm run build
```

Notice that `shell: bash` appears on every `run:` step, and that
`working-directory:` is set per step rather than via `defaults:`, because
`defaults.run.working-directory` applies to the caller's job, not to steps
contributed by an action.

## 4. What I should see

**In the Actions tab**, one job, `Use a composite action`, whose step list is
the composite action's steps flattened in, followed by the caller's own step:

```
Composite actions demo
└─ ✓ Use a composite action
   ├─ ✓ Set up the whole app with one composite action
   │  ├─ ✓ Checkout
   │  ├─ ✓ Set up Node 22
   │  ├─ ✓ Install
   │  └─ ✓ Run the checks
   └─ ✓ The workspace is shared, so this works
```

**Real log output**, from `docs/_logs/ch41.log`:

```
[Composite actions demo/Use a composite action] ⭐ Run Main Run the checks
[Composite actions demo/Use a composite action]   🐳  docker exec cmd=[bash --noprofile --norc -e -o pipefail /var/run/act/workflow/0-composite-3.sh] user= workdir=cicd-learn
[Composite actions demo/Use a composite action]   | 
[Composite actions demo/Use a composite action]   | > cicd-learn@1.0.0 lint
[Composite actions demo/Use a composite action]   | > eslint .
[Composite actions demo/Use a composite action]   | 
[Composite actions demo/Use a composite action]   | > cicd-learn@1.0.0 test
[Composite actions demo/Use a composite action]   | > vitest run
...
[Composite actions demo/Use a composite action]   | > cicd-learn@1.0.0 build
[Composite actions demo/Use a composite action]   | > node build.mjs
[Composite actions demo/Use a composite action]   | 
[Composite actions demo/Use a composite action]   | built dist/app.js (2887 bytes)
```

Then the caller's own step, which did not rebuild anything:

```
[Composite actions demo/Use a composite action] ⭐ Run Main The workspace is shared, so this works
[Composite actions demo/Use a composite action]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/1] user= workdir=
[Composite actions demo/Use a composite action]   | composite actions run on the caller's runner, so the built
[Composite actions demo/Use a composite action]   | output is simply here:
[Composite actions demo/Use a composite action]   | -rw-r--r-- 1 root root 525 Oct 26 12:34 cicd-learn/dist/app.js
[Composite actions demo/Use a composite action]   ✅  Success - Main The workspace is shared, so this works
```

Two things to notice:

1. The composite action's steps are prefixed `0-composite-0.sh`,
   `0-composite-3.sh` and so on: act is flattening them into the caller's job,
   because that is what they are. On GitHub they appear as nested steps under
   one parent step.
2. The build output (`dist/app.js`, 525 bytes) is simply there for the next
   step, with no artifact upload or download. That is the entire reason to
   prefer a composite action when the steps need the same files.

## 5. When to use it and when NOT to

**Reach for a composite action when:**

- You repeat the same sequence of steps in several jobs or workflows in the
  same repository.
- The steps need the caller's checked-out code or build output without an
  artifact round-trip.
- You want to hide complexity behind a single `uses:` line while keeping
  everything on one runner.
- You are publishing a small, reusable bundle to the Marketplace.

**Do NOT reach for it when:**

- The shared work needs its own runner, permissions, or secrets boundary. Use a
  reusable workflow (chapter 40).
- The steps need to run on a different OS or in a matrix. A composite action
  inherits the caller's runner.
- You only share one or two commands. A script file is simpler and has no
  `shell:` rule to remember.
- The logic is complex enough to need real programming. Write a JavaScript or
  Docker action instead; composite actions are YAML all the way down and have
  no loops or error handling beyond `if:`.

## 6. Common mistakes

- **Missing `shell:` on a `run:` step.** The most common composite-action
  failure. Symptom: `A step's 'shell' is required when 'run' is defined` or a
  parse error. Fix: add `shell: bash` (or `shell: python`) to every `run:`.
- **Using `defaults.run.working-directory` and expecting the action's steps to
  honour it.** They do not; `defaults` belongs to the workflow job, not to an
  action. Set `working-directory:` on each `run:` step inside the action.
- **Treating inputs as non-strings.** `inputs.run-checks` is the string
  `"true"`, not the boolean `true`. Compare with `== 'true'`. The same rule
  applies to `workflow_call` inputs, but it bites harder here because there is
  no type coercion.
- **Forgetting that a composite action checks out nothing by itself.** If the
  caller did not check out the repo, the action's `actions/checkout` step does
  it. If you remove that step, the workspace is empty.
- **Referencing the action by directory without `action.yml`.** `uses:
  ./.github/actions/foo` requires `foo/action.yml` to exist. A missing file
  gives "action not found".
- **Expecting outputs to flow automatically.** They do not. You must declare
  `outputs:` in the action and map them from a step's `$GITHUB_OUTPUT`.
- **Publishing a composite action that uses other actions.** That is fine, but
  every nested action must be pinned (chapter 39), because your consumers
  inherit your supply chain.

### Composite action outputs (the full pattern)

Declaring an output requires two places: the action's `outputs:` block and a
step that writes to `$GITHUB_OUTPUT`.

```yaml
# action.yml
outputs:
  size:
    description: 'Size of dist/app.js in bytes'
    value: ${{ steps.measure.outputs.size }}

runs:
  using: 'composite'
  steps:
    ...
    - name: Measure
      id: measure
      shell: bash
      working-directory: cicd-learn
      run: echo "size=$(wc -c < dist/app.js)" >> "$GITHUB_OUTPUT"
```

The caller reads it as `steps.<step-id>.outputs.size`, where `<step-id>` is
the id of the step that called the action, not the action's internal step:

```yaml
- name: Set up the app
  id: setup
  uses: ./.github/actions/setup-node-app
  with:
    run-checks: 'true'

- name: Report
  run: echo "size: ${{ steps.setup.outputs.size }}"
```

Forgetting the outer `id:` is the usual reason an output comes back empty.

## 7. Try it yourself

**Exercise: add an output, then break the `shell:` rule.**

1. Add an output to the composite action: declare `outputs.size` mapped from a
   new step that runs `echo "size=$(wc -c < cicd-learn/dist/app.js)" >> "$GITHUB_OUTPUT"`,
   and read it in the caller as `steps.setup.outputs.size`. Push and confirm
   the value prints.
2. Prove the shared workspace is the point: remove the final `ls -l` step's
   dependency on the build by deleting the build step from the action and
   adding `npm run build` to the caller after the action. The caller now has
   to rebuild, which is the cost a composite action avoids. Revert.
3. Break `shell:`: delete `shell: bash` from the Install step and push. The run
   fails before doing anything useful, with a message about a required shell.
   Read the error, add the line back, push again.

**Hint:** run it locally with

```bash
./scripts/verify.sh .github/workflows/41-composite-actions.yml push
```

The local run uses `--bind`, which is what makes the shared-workspace
behaviour visible across steps in `act`.

**Break it on purpose:** set `run-checks: 'false'` (as a string, quoted) in the
caller's `with:`. The Run the checks step is skipped, and the final `ls` fails
because `dist/app.js` was never built. That is the cost of an optional step: a
later step that assumes it ran will break.

## 8. Next

You can paste steps into your own kitchen. Chapter 42 is about a kitchen you
own entirely: your own machine, registered as a runner.

→ [42 — Self-hosted runners](42-self-hosted-runners.md)