# Shared brief for writing this course

Read this before writing anything. It is the contract every chapter must meet.

## What this repository is

A CI/CD course built around one running example. Everything is verified locally
before it is written down. The repository root contains:

```
cicd-learn/          the sample Node.js app (the running example)
  src/greet.js       pure functions: greet, shout, slugify, add
  src/sum.js         pure functions: sum, average
  src/app.js         entry point, exports report()
  build.mjs          esbuild build -> dist/app.js
  test/greet.test.js 8 Vitest tests
  test/sum.test.js   5 Vitest tests
  scripts/lint-summary.mjs     eslint --format json -> markdown table
  scripts/lint-annotations.mjs eslint --format json -> workflow commands
  Dockerfile         2-stage build, non-root, ENTRYPOINT
  eslint.config.js   ESLint 10 flat config
  vitest.config.js   tests + coverage thresholds (90% lines)
docs/                the chapters
.github/workflows/   one workflow file per chapter, named NN-topic.yml
scripts/             the verification tooling
```

## Verified versions

Use these exact versions. Do not invent others. If you need a version that is not
listed, look it up and say where you got it.

| Thing | Version |
| ----- | ------- |
| Node.js (local, this machine) | v24.19.0 |
| Node.js in `cicd-learn` CI | `node-version: '22'` (resolves to 22.23.3) |
| npm | 11.17.0 local, 10.9.9 under Node 22 |
| Runner image | `ubuntu-24.04` (pinned, never `ubuntu-latest`) |
| `actions/checkout` | `v7` |
| `actions/setup-node` | `v7` |
| `actions/cache` | `v6` |
| `actions/upload-artifact` | `v7` |
| `actions/download-artifact` | `v8` |
| `actions/configure-pages` | `v6` |
| `actions/upload-pages-artifact` | `v5` |
| `actions/deploy-pages` | `v5` |
| `docker/setup-buildx-action` | `v4` |
| `docker/login-action` | `v4` |
| `docker/build-push-action` | `v7` |
| `docker/metadata-action` | `v6` |
| `github/codeql-action` | `v4` |
| `actions/dependency-review-action` | `v5.0.0` |
| `appleboy/ssh-action` | `v1` |
| `slackapi/slack-github-action` | `v4` |
| `softprops/action-gh-release` | `v3` |
| `vitest` | 5.0.3 |
| `eslint` | 10.12.0 |
| `esbuild` | 0.28.2 |

Sample app results, measured:

```
npm run lint      -> exit 0, no output
npm test          -> Test Files 2 passed (2), Tests 13 passed (13)
npm run coverage  -> All files 93.33% stmts, 92.3% lines, 100% funcs, 71.42% branch
npm run build     -> built dist/app.js (2887 bytes)
```

`2887` is the sum of ALL metafile outputs: `dist/app.js` is 525 bytes and
`dist/app.js.map` is 2362 bytes. Do not confuse the two numbers.

## The eight-part chapter template

Every chapter follows this order, with these exact headings. Use `##` for them.

1. `## 1. Simple explanation (like I'm 7)` — short sentences, no jargon, one
   concrete real-world analogy carried through the whole explanation. The reader
   has never set up a pipeline.
2. `## 2. Real name` — the proper CI/CD terms, defined precisely, with the
   distinctions that people get wrong.
3. `## 3. Workflow example` — a COMPLETE `.yml` file for the topic, with a
   comment on every line that is not obvious. Never a fragment. If the example
   uses a concept, it must have been explained in an earlier chapter.
4. `## 4. What I should see` — which jobs run, what green and red look like, and
   REAL log output taken from the run of that workflow file. Say where the log
   came from.
5. `## 5. When to use it and when NOT to` — real trade-offs: speed, cost,
   complexity, risk.
6. `## 6. Common mistakes` — what beginners actually get wrong. Be specific
   about the symptom and the fix.
7. `## 7. Try it yourself` — one small exercise, a hint, and a way to break the
   pipeline on purpose and then fix it.
8. `## 8. Next` — a link to the next chapter.

Every chapter also opens with a `> **Verification**` block stating exactly what
was executed to produce it.

## Rules that are not negotiable

- **Only quote log output that actually came from a real run.** The runs are in
  `docs/_logs/*.log`, written by `scripts/verify.sh`. If a line is not in a log
  file, do not present it as real output. Mark illustrative output as
  illustrative, in the same way chapters 01-05 do.
- **Never write a real secret.** Placeholders only, named things like
  `DEMO_TOKEN`, plus instructions for adding it in the GitHub UI.
- **Pin every action version.** Explain why, and note that chapter 39 covers SHA
  pinning.
- **No deprecated syntax.** `set-output`, `save-state` and `set-env` are removed;
  use `$GITHUB_OUTPUT`, `$GITHUB_ENV`. Never `actions/*@v2`.
- **Quote the `on:` key** as `"on":`. Bare `on:` parses as the boolean `true` in
  YAML 1.1, which breaks every tool that is not GitHub.
- **Mark anything not executed as `[read-only example]`** and give the reader a
  free alternative they can actually run today.
- **Build up gradually.** A chapter may only use a concept explained earlier.
  Chapters 01-09 exist and are the foundation. Do not re-explain them; link to them.
- **Be honest about limits.** Say when something is a GitHub-only feature that
  cannot be verified locally.

## What local execution can and cannot prove

The tooling:

```bash
python3 scripts/validate-workflows.py        # parse + lint every workflow
./scripts/run-workflow.sh <workflow> [job] [event]   # run a real workflow file
./scripts/verify.sh <workflow> [job] [event] [label]  # run it, save the log
./scripts/verify-artifact-chain.sh <wf> <producer> <consumer> [label]
```

It runs real workflow files in a real Linux container (`cicd-act-runner:24`,
Node 24 plus the Docker CLI) using `act`.

It CANNOT reproduce: the secrets store, environments and their approval rules,
`GITHUB_TOKEN` scoping, concurrency groups, the hosted runner's exact toolchain,
GitHub's artifact service, minutes billing, or the Actions tab itself. Be
explicit about this in the Verification block of any chapter that touches it.

## Repository layout for workflows

- One workflow file per chapter: `.github/workflows/NN-topic.yml`
- Prefix number matches the chapter number
- Use `permissions:` at the top of every workflow, least privilege
- Use `defaults.run.working-directory: cicd-learn` ONLY on jobs that run
  `actions/checkout` first. A job without a checkout fails immediately,
  because the subdirectory does not exist yet. This is a real trap.
- Job-level `outputs:` must sit beside `runs-on`, never between steps

## Chapter list

Read `docs/00-roadmap.md` for the full ordered list. Chapters 01-05 are done.
Chapter numbering is fixed by the roadmap; do not renumber.