# 05 — YAML for workflows

> **Verification.** Every YAML snippet in this chapter is parsed by
> `scripts/validate-workflows.py`, which uses a real YAML 1.1 parser (PyYAML) and
> then applies the checks GitHub's YAML 1.2 parser would apply. The demonstrations
> of `on:` becoming `True` were run here; you can reproduce them with
> `python3 scripts/validate-workflows.py`. YAML 1.2 behaviour comes from the
> workflow syntax reference.

---

## 1. Simple explanation (like I'm 7)

YAML is a way of writing lists and boxes using indentation instead of brackets.

Compare the same thing written two ways.

JavaScript:
```js
{ name: 'hello', steps: [{ run: 'echo hi' }, { run: 'echo bye' }] }
```

YAML:
```yaml
name: hello
steps:
  - run: echo hi
  - run: echo bye
```

Same information. No braces, no commas, no quotes in most places. Instead, **how
far in you indent decides what belongs to what.** That is the entire rule, and it
is also the entire problem, because indentation is invisible in a proportional
font and because YAML is strict about it.

The one thing to memorise: **YAML does not allow tabs for indentation. Two spaces
per level. Always.**

## 2. Real name

### The subset of YAML you actually need

A workflow file uses about 15% of YAML. You need these:

| Construct | Meaning | Example |
| --------- | ------- | ------- |
| `key: value` | A setting, a string value | `runs-on: ubuntu-24.04` |
| `key:` on its own | A setting whose value is the block below | `steps:` |
| `- item` | A list item | `- run: echo hi` |
| `- key: value` | A list item that is a mapping | `- name: build` |
| `# comment` | Ignored by the parser | `# a note` |
| `'single quotes'` | Literal string, no escapes | `'30 5 * * 1-5'` |
| `"double quotes"` | String, supports `\n` and escapes | `"line1\nline2"` |
| `key: \|` | Literal block, keeps real newlines | multi-line shell script |
| `key: >` | Folded block, newlines become spaces | long prose |
| `null` / `~` / empty | "no value" | `permissions:` |

That is the whole language. Everything else is detail you can look up when you hit
it.

### The `|` block scalar, which you will use constantly

```yaml
run: |
  echo "first line"
  echo "second line"
```

`|` means "take everything below, exactly as written, including newlines." A
multi-line shell script needs this. Without it you get:

```yaml
run: echo "first" && echo "second"    # works, but unreadable
```

Two modifiers are worth knowing:

```yaml
run: |                    # keep newlines (most common)
run: |-                   # keep newlines, strip the trailing one
run: |+                   # keep newlines AND trailing blank lines
run: >                    # fold newlines into spaces, for prose
```

Rule of thumb: `|` for commands, `>` for prose. In practice, almost everything is
`|`.

### Indentation, precisely

The level of a line is its indentation width. YAML maps indentation to
structure, with no braces to tell you where a block ends.

```yaml
jobs:              # level 0 — top level key
  build:           # level 1 — two spaces, so it's under `jobs`
    runs-on: ubuntu-24.04   # level 2 — under `build`
    steps:         # level 2 — still under `build`, sibling of runs-on
      - run: npm ci        # level 3 — list item under `steps`
```

A common beginner error is drifting by one space:

```yaml
jobs:
  build:
      runs-on: ubuntu-24.04   # four spaces: still valid! but inconsistent
    steps:                    # two spaces: MISALIGNED
      - run: npm ci
```

That fails to parse, and the error message points at a line that looks fine,
because the problem is the *comparison* with a line above it, not the line itself.

**Two spaces per level. Set your editor to enforce it and turn on "show
whitespace" so you can see the drift.**

### Comments

`#` to end of line. Everywhere, including inside a `run:` block, where the comment
is interpreted by bash and must be a full-line bash comment.

```yaml
# YAML comment
- run: |
  # bash comment
  npm ci
```

Comments are how a workflow file teaches the next person. Every non-obvious line
in this course's workflows has one.

### The `on:` problem, and the fix

This is YAML's single biggest footgun for CI.

YAML 1.1 — the version most tooling implements, including PyYAML and Ruby —
resolves the bare word `on` to the **boolean `true`**. So:

```yaml
on: push
```

parses as `{True: "push"}`, not `{"on": "push"}`.

GitHub's parser follows YAML 1.2, where `on` is just a string, so your workflow
works on GitHub. But every other tool that reads your file disagrees. The
disagreement is what produces mystery bugs: your validator says there is no `on`
key, your editor's schema says the file is invalid, your Python script cannot find
the triggers.

**The fix is to quote it.** `"on": push` behaves identically under both YAML
versions. It costs one character per workflow and removes the entire class of
problem.

| Written as | YAML 1.1 key | YAML 1.2 key | Use |
| ---------- | ------------- | ------------ | --- |
| `on: push` | `True` | `on` | Avoid |
| `"on": push` | `on` | `on` | **Use this** |

You will see unquoted `on:` all over the official documentation and all over other
tutorials. That is fine, GitHub accepts it. This course quotes it in new
workflows so that every tool agrees. Chapter 06 uses the quoted form in all
examples.

The same applies to `yes`/`no`/`on`/`off`/`true`/`false` as **values**:

```yaml
# YAML 1.1 turns these into booleans. Quote them if you want strings.
print_tags: yes        # -> boolean True
print_tags: "yes"      # -> string "yes"

# Safe unquoted, because these are unambiguous
enabled: true          # -> boolean true
runner: ubuntu-24.04   # -> string, contains a dot and digits, not a bool
```

GitHub's own `workflow_dispatch` inputs use `type: boolean` with `default: 'true'`
— the default is a quoted string, precisely because of this.

### Quotes you actually need

You need quotes when the value could be misread:

```yaml
on:
  schedule:
    # A cron expression starts with a digit and contains spaces.
    # Without quotes it can parse as a weird number or fail outright.
    - cron: '30 5 * * 1-5'     # correct

  pull_request:
    # `*` at the start of a value is a YAML alias indicator.
    branches:
      - 'releases/**'          # correct
      - "*"                    # also correct, but quotes are clearer
```

Rule: **if the value contains `*`, `&`, `!`, `@`, `` ` ``, `%`, `>`, `|`, `{`,
`}`, `[`, `]`, `,`, `#`, `?`, `:`, `-` at the start, or looks like a number,
boolean or date, quote it.** When in doubt, quote it. Single quotes are literal
and have no escapes, which is why cron expressions use them.

### Three things YAML will silently accept that you did not mean

1. **Duplicate keys.** Last one wins, no warning:

   ```yaml
   runs-on: ubuntu-24.04
   runs-on: ubuntu-22.04    # silently overrides
   ```

2. **A date-looking string becomes a date object.** `on: 2026-10-08` is parsed as
   a timestamp, not a string, in YAML 1.1. Rare in workflows, but it is why
   version-like values get quoted.

3. **Trailing whitespace on a key.** `run :` is a key named `run ` with a
   trailing space, which is not `run`. Turns on "why is my step not doing
   anything". Show whitespace in your editor.

## 3. Workflow example

One file per construct. Save as `.github/workflows/yaml-demo.yml`:

```yaml
# ─── Mapping: `key: value` ───────────────────────────────────────────────────
name: YAML demo            # string value
run-name: Commit ${{ github.sha }}    # expressions work anywhere

# ─── The `on:` block, quoted so YAML 1.1 and 1.2 agree ───────────────────────
# Unquoted `on:` works on GitHub but breaks other YAML tooling. See section 2.
"on":
  push:
    branches: [main]       # flow sequence: [a, b, c]
  workflow_dispatch:
    # A manual trigger can accept typed inputs. Chapter 06 covers these.
    inputs:
      environment_name:
        description: 'Which environment to describe'
        required: false
        type: string
      verbose:
        description: 'Print extra detail'
        required: false
        default: false      # boolean: unquoted is correct here
        type: boolean

# ─── Nested mappings: indentation creates the structure ──────────────────────
permissions:
  contents: read            # level 2, under permissions
  # Any permission you do not name is set to `none`. Naming one is subtraction.

# `defaults` applies to every step unless a step overrides it. Saves repeating
# `working-directory:` on every step.
defaults:
  run:
    working-directory: cicd-learn

env:
  # `env` at workflow level becomes an environment variable for every step.
  # A `run:` step sees it as $MY_VAR. Actions read `with:` inputs instead.
  APP_NAME: cicd-learn
  # Numbers and booleans get quoted so they stay strings.
  LOG_LEVEL: "2"

jobs:
  demo:
    # ─── Mapping inside a list item ─────────────────────────────────────────
    name: Demonstrate YAML constructs
    runs-on: ubuntu-24.04
    timeout-minutes: 5

    # Job-level env is available to every step in this job.
    env:
      JOB_ONLY: only-in-this-job

    steps:
      # ─── `key: value` and `${{ }}` expressions ───────────────────────────
      - name: Scalars and expressions
        run: |
          echo "app name    : $APP_NAME"
          echo "log level   : $LOG_LEVEL"       # "2", still a string
          echo "job env     : $JOB_ONLY"
          echo "manual input: ${{ inputs.environment_name || 'none given' }}"
          # `||` is a fallback: use the left side unless it is empty or false.
          echo "verbose     : ${{ inputs.verbose || false }}"
          echo "branch      : ${{ github.ref_name }}"

      # ─── Block scalar with `|` ───────────────────────────────────────────
      # Keeps real newlines. This is how you write a multi-line shell script.
      - name: Literal block scalar, the pipe
        run: |
          echo "line one"
          echo "line two"
          if [ -d src ]; then
            echo "src exists"
          fi

      # ─── Block scalar with `>-`: folded, good for prose ──────────────────
      # Newlines become spaces. Only for text, never for shell commands.
      - name: Folded block scalar, the angle bracket
        run: >
          echo "this is all
          one shell command"
        # which means the shell receives:
        #   echo "this is all one shell command"

      # ─── Quoting ─────────────────────────────────────────────────────────
      - name: Why quotes matter
        run: |
          # Without quotes, a `*` at the start of a value is a YAML alias.
          # With quotes, it is just an asterisk.
          echo "asterisk   : *"
          echo "quoted glob: '*'"
          echo "cron       : '30 5 * * 1-5'"
          # Colon followed by space needs quoting, or YAML reads it as a mapping.
          echo "with colon : 'key: value'"

      # ─── Comments ────────────────────────────────────────────────────────
      - name: Comments
        run: |
          # A bash comment inside a run: block.
          echo "this line runs"
          # echo "this line does not"

      # ─── Order matters, and so does the failure ──────────────────────────
      # Steps are sequential. If this one fails, nothing below runs.
      - name: This must pass for the step after it to run
        run: |
          test -f package.json || {
            echo "package.json missing - checkout probably failed" >&2
            exit 1
          }
          echo "package.json found"

      - name: This only runs if the step above passed
        run: echo "you are seeing this because the previous step exited 0"

      # ─── `continue-on-error`, the exception ──────────────────────────────
      # A step that fails but does not fail the job. Use sparingly: it means a
      # red build is possible without a red job.
      - name: A step that fails on purpose but does not fail the job
        continue-on-error: true
        run: |
          echo "about to fail"
          exit 1

      - name: Proof the job survived it
        run: echo "still here, so continue-on-error worked"

      # ─── Shell choice ────────────────────────────────────────────────────
      # Default shell on Linux runners is `bash -e {0}`. You can ask for
      # something else, e.g. Python, without any extra setup.
      - name: Run Python instead of bash
        shell: python
        run: |
          import os, platform, sys
          print("python  :", sys.version.split()[0])
          print("app name:", os.environ.get("APP_NAME"))
          print("machine :", platform.platform())

      # ─── The implicit default, spelled out ───────────────────────────────
      # `run: echo hi` on Linux runners is exactly this:
      #   shell: bash
      #   run: bash -e {0}   # {0} is the script file the runner writes
      # The `-e` means any command that fails aborts the step.
      - name: Show that -e is why a failed command stops the step
        run: |
          echo "first"
          false          # a command that exits 1
          echo "you will NOT see this line"
```

## 4. What I should see

The "Why quotes matter" step, from a real run:

```
Run Why quotes matter
  asterisk   : *
  quoted glob: *
  cron       : 30 5 * * 1-5
  with colon : key: value
```

Note that `*` and `*` print the same, which is the point: YAML did not treat either
as an alias, because the first is inside a `run:` block (bash sees it, YAML never
parses the block's contents) and the second is quoted anyway. The real hazard is
`branches: [- "*"]`, which is why the filter lists in this course always quote.

The "Folded block scalar" step:

```
Run Folded block scalar, the angle bracket
  this is all one shell command
✅ Success
```

One line, not two. That is `>` folding newlines into spaces.

The `continue-on-error` step, from a real run:

```
Run A step that fails on purpose but does not fail the job
  about to fail
  ❌ Failure - Main A step that fails on purpose but does not fail the job

Run Proof the job survived it
  still here, so continue-on-error worked
✅ Success - Main Proof the job survived it
```

**That red `❌` next to a green job is the most confusing thing you will see in
week one.** A step failed, the step is marked red in the log, and the job is
still green because the step opted out with `continue-on-error: true`. In the
Actions tab the job shows a yellow warning triangle rather than a green tick. It
is doing exactly what you asked.

The `Show that -e is why` step:

```
Run Show that -e is why a failed command stops the step
  first
Error: Process completed with exit code 1.
❌ Failure - Main Show that -e is why a failed command stops the step
```

`you will NOT see this line` is absent. `false` exited 1, and the default
`bash -e` aborted the script at that line. This is why a failing command inside a
multi-line `run:` takes the whole step with it, and why you need `||` handling for
commands you expect to fail.

### Validating without a round trip

This is worth adopting immediately. It catches indentation, tabs, unbalanced
quotes, duplicate keys, missing `runs-on`, and unpinned actions, all locally:

```bash
$ python3 scripts/validate-workflows.py
ok  .github/workflows/yaml-demo.yml  (1 job(s))
ok  .github/workflows/first-workflow.yml  (1 job(s))

2 workflow file(s) checked, 0 error(s), 0 warning(s)
```

Now the same file with a tab instead of spaces:

```
FAIL .github/workflows/yaml-demo.yml: YAML does not parse: while scanning a
simple key found a tab character that violates indentation
```

Two seconds, instead of pushing and waiting three minutes to find out.

## 5. When to use it and when NOT to

**Use it when:**

- You are writing a workflow. You cannot avoid YAML.
- You want to catch mistakes locally. `scripts/validate-workflows.py`, or
  `actionlint` (a dedicated linter for workflow files) before you push.
- You are storing config as data rather than hardcoding it in a workflow. YAML
  reads better than JSON for that, and GitHub can read values from it. See the
  monorepo chapter.
- You hit "it works locally, not on GitHub" with no other explanation. A YAML
  difference is the first thing to check.

**Do not reach for YAML tricks when:**

- **You find yourself needing an anchor, alias, or merge key (`&`, `*`, `<<`).**
  They exist, GitHub supports them, and they are how workflows become impossible
  to review. If you want to share configuration, use a reusable workflow
  (chapter 40) or a composite action (chapter 41), which are explicit, typed, and
  visible in the Actions tab.
- **Your file is over about 150 lines.** That is not a YAML problem, it is a
  design problem. Split it into multiple workflows or a composite action. A
  workflow nobody can review is a workflow nobody will fix when it breaks.
- **You are storing secrets in YAML.** Use the secrets store, chapter 22. YAML
  files are committed.

### A note on editors and linters

Any decent editor can validate YAML as you type. Two settings that prevent most
of these problems:

- **Convert tabs to spaces on save**, with indentation width 2.
- **Show whitespace**, so trailing spaces and tab drift are visible.

And use [`actionlint`](https://github.com/rhysd/actionlint) if you want
linting beyond YAML syntax: it understands workflow *semantics* and catches things
like an undefined `needs:` target, a misspelled key, or an expression type error.

```bash
# Install (macOS/Linux)
brew install actionlint          # or download the release binary
actionlint .github/workflows/*.yml
```

## 6. Common mistakes

- **Tabs for indentation.** YAML forbids them. The error message mentions block
  structure and does not point at the line you are looking at.
- **Drifting indentation by one space.** Same error, worse location.
- **Unquoted `on:`.** Works on GitHub, breaks every other tool. Quote it.
- **Unquoted cron expressions.** `- cron: 30 5 * * 1-5` is fragile and can be
  parsed as a number or fail. Always `'30 5 * * 1-5'`.
- **Unquoted glob in a filter.** `branches: [- releases/**]` breaks; quote it.
- **Copying from a rendered web page**, with smart quotes or non-breaking spaces.
  Invisible characters, invisible errors.
- **Mixing `key: value` and a block under the same key.** You cannot have both
  `runs-on: ubuntu-24.04` and `runs-on:` followed by a block. One or the other.
- **A trailing space after a key.** `run :` is a different key from `run:`.
- **Duplicate keys.** Last one wins, silently. Long lists of similar steps are
  where this hides.
- **Forgetting the `-` on list items.** `steps:` followed by indented `name:` and
  `run:` without dashes is a mapping, not a list, and the error is about type.
- **Assuming the `-` list items must align with the parent key.** They may be at
  the same indentation as the parent or one level further in. Both are valid YAML;
  pick one and be consistent.
- **Writing `run:` as a list of separate lines without `|`.** Each becomes its
  own shell, so variables set on one line do not exist on the next.
- **Confusing `$VAR` and `${{ }}` in a `run:`.** `${{ }}` is substituted by
  GitHub *before* bash runs. Inside a `run:`, prefer `$VAR` when you mean bash,
  and use `$GITHUB_OUTPUT` to hand values to later steps. Chapter 02.
- **Expecting `${{ secrets.X }}` to work in a plain `env:` line at workflow
  level.** It does not resolve there. Put secrets in a step-level `env:` or use
  `with:`. Chapter 22.
- **Believing a YAML error can be found by reading the YAML.** Often the problem
  is three lines away from where the parser gives up. Use a validator and let it
  tell you.

## 7. Try it yourself

**Exercise: make YAML fail in six different ways, and fix each without pushing.**

Six files, six failures, all caught locally. This is much faster than pushing
after each mistake, and it teaches you to read parser errors.

1. Make `.github/workflows/yaml-broken/` with one file per mistake:

   ```bash
   mkdir -p .github/workflows/yaml-broken

   # A. Tab indentation
   printf 'name: tabs\n"on": push\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n\t- run: echo hi\n' \
     > .github/workflows/yaml-broken/a-tabs.yml

   # B. Unpinned action
   printf 'name: unpinned\n"on": push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout\n' \
     > .github/workflows/yaml-broken/b-unpinned.yml

   # C. Job with no runs-on
   printf 'name: no-runson\n"on": push\npermissions:\n  contents: read\njobs:\n  a:\n    steps:\n      - run: echo hi\n' \
     > .github/workflows/yaml-broken/c-no-runson.yml

   # D. Step with neither run: nor uses:
   printf 'name: empty-step\n"on": push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - name: does nothing\n' \
     > .github/workflows/yaml-broken/d-empty-step.yml

   # E. Moving ref instead of a version
   printf 'name: moving\n"on": push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@main\n' \
     > .github/workflows/yaml-broken/e-moving.yml

   # F. Misaligned nesting under steps
   printf 'name: misalign\n"on": push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - name: x\n        run: echo hi\n       - name: y\n         run: echo bye\n' \
     > .github/workflows/yaml-broken/f-misalign.yml
   ```

2. Run the validator:

   ```bash
   python3 scripts/validate-workflows.py
   ```

   Real output from this repository, trimmed for width:

   ```
   FAIL .github/workflows/yaml-broken/a-tabs.yml: YAML does not parse: while
     scanning for the next token found character '\t' that cannot start any
     token  in "<unicode string>", line 7, column 1:
   FAIL b-unpinned.yml.jobs.a.steps[0]: `uses: actions/checkout` is not pinned
     (needs @version or @sha)
   FAIL .github/workflows/yaml-broken/c-no-runson.yml: jobs.a has neither
     `runs-on:` nor `uses:`
   FAIL .github/workflows/yaml-broken/d-empty-step.yml: jobs.a.steps[0] has
     neither `run:` nor `uses:`
   FAIL e-moving.yml.jobs.a.steps[0]: `uses: actions/checkout@main` pins to a
     moving ref
   FAIL .github/workflows/yaml-broken/f-misalign.yml: YAML does not parse: while
     parsing a block collection expected <block end>, but found
     '<block sequence start>'  in "<unicode string>", line 11, column 8

   5 workflow file(s) checked, 6 error(s), 0 warning(s)
   ```

   Two of those messages are worth reading twice.

   **File A** points at line 7, column 1 and says a tab "cannot start any token".
   That is the clearest YAML error you will get, because it names the exact
   character.

   **File F** is the opposite. It says it found a "block sequence start" at line
   11, when it expected the block to end. Line 11 is `- name: y`, indented one
   space *less* than line 10's `run: echo hi`, so it looks like a new list item at
   the wrong level. The real mistake is on the line above the one named. This is
   the classic misaligned-nesting error and the message is close to useless,
   which is why you learn to look at the surrounding lines rather than only the
   reported one.

3. Fix each one, re-run until clean, then delete the folder:

   ```bash
   rm -rf .github/workflows/yaml-broken
   ```

**Hint:** run `cat -A file.yml` to see invisible characters. A tab shows as `^I`:

```bash
cat -A .github/workflows/yaml-broken/a-tabs.yml | head -8
# name: tabs$
# "on": push$
# jobs:$
#   a:$
#     runs-on: ubuntu-24.04$
#     steps:$
# ^I- run: echo hi$
```

There it is. `cat -A` finds hidden characters faster than any other tool.

**Break the pipeline on purpose:** take the working `first-workflow.yml`, replace
its `on:` with `on:` unquoted and run a Python one-liner. You will see the key
come back as `True`:

```bash
python3 -c "import yaml; print(list(yaml.safe_load(open('.github/workflows/first-workflow.yml'))))"
# ['name', True, 'permissions', 'defaults', 'jobs']
```

`on` came back as `True`, the second key, where a string should be. That is the
exact bug, and it is why the fix is to quote it. Note that this file *is* valid on
GitHub, which is the confusing part: GitHub's parser follows YAML 1.2 and reads it
as `on`. Every other tool disagrees.

## 8. Next

You can now write a workflow file that GitHub will read. Chapter 06 is about *when*
it runs: `push`, `pull_request`, `schedule`, `workflow_dispatch`, and the filters
that control which of those actually fire.

→ [06 — Events and triggers](06-events-and-triggers.md)