# 20 — Artifacts

> **Verification.** The workflow in this chapter is
> `.github/workflows/20-artifacts.yml`. The producer was executed with
> `./scripts/verify.sh .github/workflows/20-artifacts.yml "produce" push ch20-produce`,
> and the full log is at `docs/_logs/ch20-produce.log`. The consumer side was
> executed as a two-phase chain (`.tmp/chain-ch20.yml`), because `act` has no
> GitHub artifact service, and its log is at `docs/_logs/ch20-consume.log`.
> Every log excerpt in section 4 is quoted from those two files.
> `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/20-artifacts.yml (2 job(s))`.
>
> **What this local execution cannot prove.** `act` cannot talk to GitHub's
> artifact service, so the real `actions/upload-artifact` and
> `actions/download-artifact` steps fail locally with
> `Unable to get the ACTIONS_RUNTIME_TOKEN env variable` (see section 4). The
> two-phase chain in `ch20-consume.log` is `act`'s stand-in: it tars the
> produced files and extracts them in the consumer, which proves the
> cross-machine data transfer but not the real service's size limits, retention
> enforcement, immutability rules, or download URLs. Those are documented in
> the artifact reference and need a hosted run. The *file layout and the
> "it really runs" proof* are real and measured.

---

## 1. Simple explanation (like I'm 7)

A factory has a conveyor belt that carries a finished cake from the baking
station to the decorating station. The two stations are in different rooms, with
different tools, and neither can see the other's table. If you do not put the
cake on the conveyor belt, the decorating station has no cake.

That is an **artifact**. A job finishes, saves a file, and a later job (or a
human, weeks later) downloads it. Jobs do not share a filesystem (chapter 02),
so anything that must outlive the machine that made it has to travel as an
artifact.

Two things matter, and they are the whole chapter:

- The conveyor belt is **named**. You upload under a name (`dist`) and download
  under the same name. The name is the only address.
- The conveyor belt is **one-way and one-write**. In v4 and later, a name can
  be written once per run. Two jobs uploading `dist` makes the second one fail.
  That is a feature, not a bug: it stops a later, slower job from overwriting
  a better build.

## 2. Real name

### Artifact

A file (or set of files) that a job saves so it outlives the runner, and that
later jobs or humans can download. Artifacts are "here is a build output, keep
it for N days". They are not a cache and not a secret store.

### `actions/upload-artifact`

Saves files from the runner into GitHub's artifact service. Key inputs:

- `name`: what the artifact is called. Downstream jobs match on this.
- `path`: which files, relative to the **workspace root**, not to
  `working-directory`. This is the number one artifact bug (section 6).
- `retention-days`: how long to keep it. Default 90. Lower it for anything
  large.
- `if-no-files-found`: `error` | `warn` | `ignore`. Default is **`warn`**,
  which means a missing path gives you a warning and a green job that produced
  nothing. Use `error`.
- `include-hidden-files`: whether dotfiles are included. Default false.

### `actions/download-artifact`

Retrieves an artifact into the current workspace. Key inputs:

- `name`: which artifact. Omit it to download **every** artifact at once.
- `path`: where to put it, relative to the workspace root.
- `pattern`: a glob to select a subset of artifacts when downloading all.
- `merge-multiple`: flatten several artifacts into one directory.

### Cross-job transfer

The reason artifacts exist. Job A runs on machine 1, builds `dist/app.js`,
uploads it. Job B runs on machine 2, downloads `dist`, and runs
`node dist/app.js`. Job B never checked out the repo and never ran `npm ci`;
the only way the file got there is the artifact.

### Immutability (v4+)

From `upload-artifact` v4 onward, an artifact name can be written **once per
run**. A second upload with the same name fails. This replaced the v3
behaviour of silently merging into the same archive, which caused corrupted
archives and confused consumers. If several jobs need to write similar things,
append a unique suffix (the job name, the matrix value, a timestamp).

### Retention

Artifacts expire. Default 90 days; you set `retention-days` per upload. After
expiry the download link returns 404. This is storage billing, not a bug.

### Artifact versus cache (again)

Chapter 16 and chapter 02. Cache = "probably the same, skip the work". Artifact
= "exactly this run's output, keep it". Build outputs are artifacts; download
caches are caches.

## 3. Workflow example

This is the complete `.github/workflows/20-artifacts.yml` from this
repository.

```yaml
name: Artifacts

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  produce:
    name: produce the build
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
      - name: Build, and produce a coverage report to upload as a second artifact
        run: |
          npm run build
          npm run coverage

      # ── Upload ────────────────────────────────────────────────────────────
      # name:  what this artifact is called. Downstream jobs match on it.
      # path:  relative to the WORKSPACE ROOT, not to working-directory. This is
      #        the number one artifact bug: `path: dist` silently uploads
      #        nothing when working-directory is cicd-learn, and with
      #        if-no-files-found: error you get a confusing failure.
      # retention-days: default is 90. Lower it for anything large.
      # if-no-files-found: error | warn | ignore. Default is warn, which means a
      #        missing path gives you a warning and a green job that produced
      #        nothing. Use `error`.
      - name: Upload dist
        uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 7
          if-no-files-found: error

      # A second artifact: the report, not the build. Keeping them separate
      # means a consumer can download just the report.
      - name: Upload the coverage summary as JSON
        uses: actions/upload-artifact@v7
        with:
          name: coverage
          path: cicd-learn/coverage/coverage-final.json
          retention-days: 7
          if-no-files-found: ignore

  # ── Download on another machine ───────────────────────────────────────────
  # This job has a brand new workspace. The only way dist/app.js can appear
  # here is if it is downloaded as an artifact.
  consume:
    name: consume the build
    runs-on: ubuntu-24.04
    needs: [produce]
    steps:
      # No checkout, and no working-directory: both would point at a directory
      # that does not exist until checkout runs.
      - name: Download dist
        uses: actions/download-artifact@v8
        with:
          # Which artifact. Omit `name` to get every artifact at once.
          name: dist
          # Where to put it. This path is relative to the workspace root.
          path: dist

      - name: It is really there, and it still runs
        run: |
          ls -l dist/
          node dist/app.js Ada

      - name: Proof it came from the other machine, not from a build here
        run: |
          # No checkout and no npm ci in this job, so these cannot have been
          # produced here.
          echo "dist/app.js is $(wc -c < dist/app.js) bytes"
          test -d node_modules && echo "node_modules exists (unexpected)" || echo "no node_modules, as expected"

      # ── The upload_everything: always() case ───────────────────────────────
      # A normal step is SKIPPED if an earlier step failed. So if you want to
      # upload a log or a failure report after something breaks, `always()` is
      # mandatory. Without it, the most useful artifact is the one you lose.
      - name: Always upload, even after a failure
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: always-present
          path: cicd-learn/package.json
          retention-days: 1
          if-no-files-found: warn

  # ── Why jobs cannot just read each other's files ──────────────────────────
  # The runner is a fresh machine per job. It is destroyed afterwards. Anything
  # that must outlive the job has to be saved explicitly: as an artifact (a
  # build output), as a cache (a download cache), or as a commit (source).
  #
  # v4+ of upload-artifact made artifacts IMMUTABLE: a name can only be written
  # once per run. Two jobs uploading the same name will fail the second one.
  # Append a unique suffix when several jobs write similar things.
```

Two structural things to notice:

- **`consume` has no checkout and no working directory.** It is a pure consumer.
  If you add `defaults.run.working-directory: cicd-learn` here, every step
  fails immediately because that directory does not exist until checkout runs.
  Chapter 15 is about exactly that trap.
- **Two uploads with different names** (`dist` and `coverage`) coexist in one
  run. That is the normal shape; the immutability rule only forbids two uploads
  with the *same* name.

## 4. What I should see

### The producer, and the honest local limitation

`docs/_logs/ch20-produce.log` is a run of the `produce` job. The build and
coverage steps run normally:

```
[Artifacts/produce the build]   | built dist/app.js (2887 bytes)
[Artifacts/produce the build]   | All files |   93.33 |    71.42 |     100 |    92.3 |
```

Then the upload step runs and hits `act`'s limitation:

```
[Artifacts/produce the build]   | With the provided path, there will be 2 files uploaded
[Artifacts/produce the build]   | Artifact name is valid!
[Artifacts/produce the build]   | Root directory input is valid!
[Artifacts/produce the build]   ❗  ::error::Unable to get the ACTIONS_RUNTIME_TOKEN env variable
[Artifacts/produce the build]   ❌  Failure - Main Upload dist [456.935926ms]
```

Three things to read in that block:

1. `With the provided path, there will be 2 files uploaded` — the action found
   `dist/app.js` and `dist/app.js.map`. The path was correct; the failure is
   not a path problem.
2. `Artifact name is valid!` and `Root directory input is valid!` — the
   inputs were accepted.
3. `Unable to get the ACTIONS_RUNTIME_TOKEN env variable` — the action needs
   GitHub's runtime token to talk to the artifact service, and `act` does not
   provide one. This is a local-execution limitation, not a workflow bug. On
   GitHub the same step reports `Total size: 12.4 kB` and a download link.

So locally the producer job is red at the upload step. That is expected and is
not a reason to change the workflow.

### The consumer, proving cross-machine transfer

Because `act` cannot move real artifacts, the verification used a two-phase
chain (`.tmp/chain-ch20.yml`) that tars the produced files and extracts them in
the consumer. Its log is `docs/_logs/ch20-consume.log`, and it proves the
thing that matters: the consumer is a different machine that never built
anything.

First, the simulated download lands the files:

```
[Artifacts/consume the build]   | SIMULATED download of dist into dist
```

Then the consumer lists them and runs the app:

```
[Artifacts/consume the build]   | total 8
[Artifacts/consume the build]   | -rw-r--r-- 1 node node  525 Oct  8 09:40 app.js
[Artifacts/consume the build]   | -rw-r--r-- 1 node node 2362 Oct  8 09:40 app.js.map
[Artifacts/consume the build]   | {
[Artifacts/consume the build]   |   "message": "HELLO, ADA!",
[Artifacts/consume the build]   |   "total": 10,
[Artifacts/consume the build]   |   "mean": 2.5
[Artifacts/consume the build]   | }
```

`525` bytes for `app.js` and `2362` for the map — the same numbers as the
build output (`2887` is the sum of both, and that is the number to quote when
you mean "the whole build"). The consumer ran `node dist/app.js Ada` and got
the correct output, with no checkout and no `npm ci` in that job.

Then the proof that it really was a transfer, not a local rebuild:

```
[Artifacts/consume the build]   | dist/app.js is 525 bytes
[Artifacts/consume the build]   | no node_modules, as expected
```

No `node_modules` directory exists in the consumer's workspace, which means
`dist/app.js` could not have been produced there. It arrived from the other
machine.

### The `always()` upload

The consumer also runs an upload with `if: always()`, and it succeeds even
though the earlier "real" upload failed:

```
[Artifacts/consume the build]   | SIMULATED upload of cicd-learn/package.json as always-present
```

On GitHub this is the pattern for uploading a failure log or a crash dump: the
step that produces the file failed, but the upload step with `if: always()`
still runs and saves what it can. Without `always()`, the most useful artifact
is the one you lose.

### What a real GitHub run adds

On github.com, the same workflow shows, in the run summary:

```
Artifacts
dist          2 files      uploaded 12 seconds ago
coverage      1 file       uploaded 12 seconds ago
```

with a download button per artifact and a per-artifact size. The consumer job
then shows `Downloaded artifact 'dist'` and the file listing. That rendering is
GitHub-only and cannot be reproduced by `act`.

## 5. When to use it and when NOT to

**Use artifacts when:**

- **A build output is needed by a later job.** Deploy, release, smoke test.
  This is the canonical use.
- **You want to inspect a build after the run.** Upload `dist/` and download
  it from the Actions tab to reproduce a reported bug against the exact binary
  CI produced.
- **A test produces a report you want to keep.** Coverage, JUnit XML, a
  screenshot on failure. Upload with `if: always()` so failures are captured.
- **You are splitting build from deploy.** Build once, upload, deploy job
  downloads. Never rebuild in the deploy job.

**Do NOT reach for artifacts when:**

- **You are passing a small value.** A version number or a byte count should
  be a job output (chapter 18), not a file. Artifacts have overhead.
- **You are caching dependencies.** That is a cache (chapter 16), with
  different lifetime and mutability rules.
- **You are uploading on every push without retention limits.** Default 90
  days of storage for every run adds up. Set `retention-days` deliberately.
- **You are uploading the same name from two jobs.** v4+ makes that fail. If
  two jobs produce similar things, give them distinct names.

## 6. Common mistakes

- **`path:` relative to `working-directory`.** The most common artifact bug.
  `path: dist` with `working-directory: cicd-learn` uploads nothing, because
  the action resolves `dist` against the workspace root. Symptom: a green
  upload step that saved zero files, or `if-no-files-found: error` failing
  with "no files found". Fix: use the repo-relative path, `cicd-learn/dist`.
- **`if-no-files-found` left at the default `warn`.** Symptom: a green job
  that produced nothing, discovered three weeks later. Fix: `error` on any
  upload whose absence would be a real problem.
- **Forgetting that artifacts are immutable in v4+.** Symptom: the second of
  two uploads with the same name fails with "an artifact with this name
  already exists". Fix: append a suffix, or restructure so one job uploads.
- **Downloading without `name` and being surprised by the layout.** Omitting
  `name` downloads every artifact, each into its own subdirectory. Symptom:
  `dist/dist/app.js` instead of `dist/app.js`. Fix: pass `name` when you want
  one artifact.
- **Assuming `download-artifact` creates the directory.** It does, but only
  the `path:` you give it. `path: dist` creates `dist/`; `path: .` dumps into
  the workspace root and can overwrite source files. Be explicit.
- **Uploading `node_modules`.** Huge, slow, and it breaks the immutability and
  retention budgets. Upload build outputs only.
- **Expecting an artifact to exist after retention.** 90 days (or whatever you
  set) later, the download returns 404. Symptom: "the link worked last
  month". Not a bug; set retention deliberately and re-run if you need it.
- **Using artifacts to pass secrets or credentials.** Artifacts are downloadable
  by anyone with read access to the repository. Never upload a `.env` or a
  private key.

## 7. Try it yourself

**Exercise: prove the cross-job transfer and the path bug.**

1. Run the producer:

   ```bash
   ./scripts/verify.sh .github/workflows/20-artifacts.yml produce push ch20-produce
   ```

   Read the log. The build succeeds; the upload fails with
   `Unable to get the ACTIONS_RUNTIME_TOKEN env variable`. That failure is
   `act`, not your workflow. On GitHub the same step is green.

2. Run the consumer chain:

   ```bash
   ./scripts/verify-artifact-chain.sh .github/workflows/20-artifacts.yml produce consume ch20
   ```

   Confirm `node dist/app.js Ada` prints the greeting, and that
   `no node_modules, as expected` appears. That is the cross-machine proof.

3. **Prove the path bug.** Change `path: cicd-learn/dist` to `path: dist` in
   the upload step and run the producer again. With `if-no-files-found: error`
   the step now fails with "no files found", because `dist` does not exist at
   the workspace root. That is the real bug the `error` setting exists to catch.
   Revert.

4. **Prove the default `warn`.** Change `if-no-files-found: error` to `warn`
   (or remove the line) and repeat the broken path from step 3. The step is
   now **green** with a warning, and zero files were uploaded. That is the
   silent failure the default creates. Revert to `error`.

5. **Prove immutability.** Add a second upload step with the same `name: dist`
   and run on GitHub (locally, `act` will not catch it because the service is
   absent). The second upload fails. Locally, simulate by uploading twice to
   the same `.tmp/artifacts/dist.tar` name and watching the second overwrite —
   which is exactly the behaviour v4 removed.

6. **Break `always()`.** Remove `if: always()` from the final upload step and
   make an earlier step fail (`exit 1`). The final upload is now skipped, and
   the artifact you wanted most is gone. Revert.

**Hint:** the consumer job has no checkout on purpose. If you add one "to be
safe", you have not broken anything, but you have hidden the proof that the
file came from the artifact.

**What this exercise proves:** the file layout, the cross-machine transfer,
the path relativity, the `warn` versus `error` default, and `always()`.
**What it cannot prove:** the real artifact service, its size and count limits,
retention enforcement, immutability, or download URLs. Those need a hosted run.

## 8. Next

You can now save a build and hand it to another machine. The last piece of
"structure" is making sure two runs of the same workflow cannot step on each
other — cancelling the obsolete one and serialising the dangerous one.

→ [21 — Concurrency](21-concurrency.md)
EOF
echo done