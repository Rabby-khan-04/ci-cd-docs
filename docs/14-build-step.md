# 14 — The build step

> **Verification.** The workflow in this chapter is
> `.github/workflows/14-build-step.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/14-build-step.yml build push ch14-build`,
> and the full log is at `docs/_logs/ch14-build.log`. Every log excerpt in
> section 4 is quoted from that file. `python3 scripts/validate-workflows.py`
> reports `ok .github/workflows/14-build-step.yml (1 job(s))`.
>
> The byte arithmetic in section 4 was checked directly: `dist/app.js` is 525
> bytes and `dist/app.js.map` is 2362, and `525 + 2362 = 2887`, which is the
> number the build script prints. The `metafile.outputs` structure was read out
> of a real esbuild 0.28.2 run in a throwaway copy of `cicd-learn` under
> `/tmp`, with `node build.mjs` and with a direct `build()` call.
>
> **What this local execution cannot prove.** It cannot prove anything about
> GitHub's artifact service. Chapter 14's workflow deliberately does **not**
> upload an artifact, so that is not claimed here — but it does mean the claim
> "the machine is destroyed when the job ends, so the output is gone" is
> asserted from the documented runner lifecycle and **pending a hosted run**.
> `act` also behaves differently in one important way for this chapter: it
> bind-mounts or copies the working tree, so a locally built `dist/` can
> survive into a later run and quietly make a broken build look fine. Treat any
> green build in this repository as suspect unless you deleted `dist/` first.

---

## 1. Simple explanation (like I'm 7)

You have a folder of paper scraps. Each scrap is one idea, and each scrap says
"see the scrap with the clouds on it". Perfect for reading. Useless as a
single object, and it cannot be handed to anyone.

A **build** takes the folder and produces one finished thing: all the scraps
lined up in the right order, everything joined together, nothing left to look up
outside.

```
  src/greet.js   ─┐
  src/sum.js     ─┼─►  build  ─►  dist/app.js      ← what people run
  src/app.js     ─┘                   dist/app.js.map  ← the notes
```

The finished thing is small and it runs on its own. That is the point of doing
it.

Here is the part that surprises everyone. When the machine finishes its work,
it is **thrown away**. Deleted. Wiped. The finished thing goes with it, because
it was never saved anywhere.

So a build that does not *save* its output has achieved nothing beyond the log
lines. This is not a theoretical worry; it is the most common way a build step
is quietly useless.

And there is one more trap waiting, which is the reason this chapter exists at
all: the number the build prints is not the size of the file. See section 4.

## 2. Real name

### Build, bundle, artifact — three different words

- **Build**: the process. Here, `npm run build` → `node build.mjs`.
- **Bundle**: what esbuild did. It walked the `import` statements starting at
  `src/app.js`, inlined `greet.js` and `sum.js`, and emitted a single ESM file
  with no imports left. You can see the result — the whole app is 525 bytes and
  contains five functions.
- **Artifact**: the *saved* copy of `dist/`. Uploading it is a separate step with
  a separate action (`actions/upload-artifact@v7`), and chapter 20 is about it.

Conflating "built" and "kept" is the mistake. The build produced output;
whether anyone can still reach it afterwards is a different question with a
different answer.

### Bundler versus compiler

esbuild does not type-check, does not downlevel syntax for old browsers unless
you ask, and does not polyfill. It concatenates, renames, minifies and rewrites
imports. In this project `build.mjs` is about 25 lines and readable end to end:

```js
const result = await build({
  entryPoints: ['src/app.js'],
  outfile: `${outdir}/app.js`,
  bundle: true,          // follow imports and inline them
  format: 'esm',         // keep ESM
  platform: 'node',      // node builtins are external, not polyfilled
  target: 'node22',      // syntax level
  minify: true,          // shorter output
  sourcemap: true,       // also emit dist/app.js.map
  metafile: true,        // report what it did
});
```

`platform: 'node'` matters more than it looks. With `platform: 'browser'`,
esbuild would try to fill in Node built-ins with shims. With `platform: 'node'`
it leaves `node:` imports alone and stops.

`minify: true` is why the output is unreadable, which is why `sourcemap: true`
matters.

### Source maps

`dist/app.js.map` is the map from the mangled bundle back to your source: for
every position in `app.js`, which original file and line it came from. It is
**2362 bytes, which is larger than the code it describes.** That is normal —
the map contains `sourcesContent`, i.e. the full original source text.

This matters for this chapter's headline confusion, and it also matters for
deployment: shipping the map is a trade (great stack traces, readable source in
the wild). Shipping it to production without thinking about it is a leak of
your source.

### The metafile, and where 2887 comes from

`metafile: true` makes esbuild return a JSON description of what it did. The
last line of `build.mjs` is:

```js
const bytes = Object.values(result.metafile.outputs)
  .reduce((t, f) => t + f.bytes, 0);
console.log(`built dist/app.js (${bytes} bytes)`);
```

`result.metafile.outputs` has **one entry per file esbuild wrote**. This build
writes two. So the printed number is the sum of both files, and the message
names only one of them. That is a genuinely misleading log line, and section 4
has the numbers that prove it.

### Determinism, and why size belongs in a log

The build deletes `dist/` first:

```js
await rm(outdir, { recursive: true, force: true });
```

so a renamed or deleted source file never leaves a stale copy behind. A build
whose output depends on what was in the directory before it is not a build, it
is a rumour.

Recording `wc -c` on the output is cheap and catches two real classes of
regression: an accidental dependency that pulls in a megabyte, and a
`"sideEffects": false` mistake that silently drops code.

## 3. Workflow example

This is the complete `.github/workflows/14-build-step.yml` from this repository.

```yaml
name: Build step

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
  build:
    name: Build
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci

      # A build that only runs when tests pass. `needs:` does not run the tests;
      # it waits for them, and skips this job if they failed.
      - name: Lint first, because it is fastest
        run: npm run lint

      - name: Test
        run: npm test

      - name: Build
        id: build          # <- what makes steps.build.outputs.* addressable
        run: |
          npm run build
          # Record the output size so the next job and the summary can use it.
          bytes=$(wc -c < dist/app.js)
          mapbytes=$(wc -c < dist/app.js.map)
          echo "dist/app.js is $bytes bytes, sourcemap is $mapbytes bytes"
          echo "bytes=$bytes" >> "$GITHUB_OUTPUT"
          echo "mapbytes=$mapbytes" >> "$GITHUB_OUTPUT"

      # Prove the artifact is not just present but runnable. A build step that
      # produces output nobody executes is how a broken build ships.
      - name: Run the built output
        run: |
          node dist/app.js Ada
          node dist/app.js Grace

      - name: List what was produced
        run: ls -l dist/

      - name: Summary
        run: |
          {
            echo "### Build"
            echo ""
            echo "| file | bytes |"
            echo "| ---- | ----: |"
            echo "| \`dist/app.js\` | ${{ steps.build.outputs.bytes }} |"
            echo "| \`dist/app.js.map\` | ${{ steps.build.outputs.mapbytes }} |"
          } >> "$GITHUB_STEP_SUMMARY"
```

Five things in that file are load-bearing and worth naming now, because chapters
after this one depend on them:

1. **`id: build` on the step.** This is what makes `steps.build.outputs.bytes`
   resolvable. Without it, `${{ steps.build.outputs.bytes }}` renders as an empty
   string and your summary table shows blank cells with no error at all.

2. **`>> "$GITHUB_OUTPUT"`.** The current mechanism. The old
   `echo ::set-output name=bytes::...` syntax was deprecated and is now
   disabled; `save-state` and `set-env` are likewise gone, replaced by
   `$GITHUB_STATE` and `$GITHUB_ENV`. If you copy a workflow written before
   2023, this is the line to change.

3. **Running the output.** `node dist/app.js Ada` is the highest-value check in
   the whole step. Lint and tests read `src/`. Only this reads `dist/`. A
   bundler misconfiguration — a `browser` field, a missing `files` entry, a
   dynamic import the bundler resolved wrongly — is invisible to both of them.

4. **`ls -l dist/`.** Not for decoration. It is how you see a build that wrote
   nothing, or wrote three files when you expected one, or wrote to the wrong
   directory.

5. **Lint and test in the same job, before the build.** Steps in a job share a
   filesystem, so this is three commands on one machine and one `npm ci`.
   Chapter 15 is about that choice and about when to undo it.

## 4. What I should see

### The build

From `docs/_logs/ch14-build.log`:

```
[Build step/Build] ⭐ Run Main Build
[Build step/Build]   | 
[Build step/Build]   | > cicd-learn@1.0.0 build
[Build step/Build]   | > node build.mjs
[Build step/Build]   | 
[Build step/Build]   | built dist/app.js (2887 bytes)
[Build step/Build]   | dist/app.js is 525 bytes, sourcemap is 2362 bytes
[Build step/Build]   ✅  Success - Main Build [263.945094ms]
[Build step/Build]   ⚙  ::set-output:: bytes=525
[Build step/Build]   ⚙  ::set-output:: mapbytes=2362
```

### The 2887 that is not 2887

Two lines, four lines apart, and they disagree:

```
built dist/app.js (2887 bytes)          <- from build.mjs, summing the metafile
dist/app.js is 525 bytes, ...          <- from wc -c, the actual file
```

**Both are correct. 525 + 2362 = 2887.** `build.mjs` sums
`Object.values(result.metafile.outputs)`, and esbuild wrote two files into that
object — `dist/app.js` (525 bytes) and `dist/app.js.map` (2362 bytes). The log
line says `dist/app.js` because that is the string in the `console.log` template;
it is not a claim about which file was measured.

Confirmed against the real `metafile`, produced by esbuild 0.28.2:

```json
{
  "dist/app.js.map": { "imports": [], "exports": [], "inputs": {}, "bytes": 2362 },
  "dist/app.js": {
    "imports": [],
    "exports": [ "report" ],
    "entryPoint": "src/app.js",
    "inputs": {
      "src/greet.js": { "bytesInOutput": 159 },
      "src/sum.js":   { "bytesInOutput": 111 },
      "src/app.js":   { "bytesInOutput": 202 }
    },
    "bytes": 525
  }
}
```

Two entries. Sum them: 2887. Note also `"exports": ["report"]` — the bundle has
one export, and it is the one `src/app.js` declared. And note the `inputs`: the
three source files, and how many bytes of each ended up in the output, which is
where a "why did my bundle double?" investigation starts.

### Why this confusion is worth a whole section

Because the number is the one people quote. "The build is 2.8 kB" is wrong by
4.5×, and it is wrong in the direction that makes you *feel better* than you
should: most of those bytes are the source map, which is not shipped code.

And the direction it goes wrong depends on the project. If a build minifies and
sourcemaps, the printed total is dominated by the map. If a build emits several
chunks, it is the sum of all of them. If a build writes a licence file or a
`manifest.json`, that is in there too. **A total is not a file size, and you
should never compare one to a file size.**

The habit to adopt: report the file, not the total.

```bash
du -h dist/app.js          # one file
find dist -type f -exec ls -l {} +   # every file
```

If you want a single number to track, sum it yourself, name what you summed, and
say whether source maps are included. Chapter 14's workflow does that with two
separate `wc -c` calls, which is why the summary table has two rows.

### The output runs

```
[Build step/Build] ⭐ Run Main Run the built output
[Build step/Build]   | {
[Build step/Build]   |   "message": "HELLO, ADA!",
[Build step/Build]   |   "total": 10,
[Build step/Build]   |   "mean": 2.5
[Build step/Build]   | }
[Build step/Build]   | {
[Build step/Build]   |   "message": "HELLO, GRACE!",
[Build step/Build]   |   "total": 10,
[Build step/Build]   |   "mean": 2.5
[Build step/Build]   | }
[Build step/Build]   ✅  Success - Main Run the built output [148.036607ms]
```

Twice, with two different names, because the argument is the one thing that
varies. This is the step that catches a bundler bug: if `greet.js` had been
excluded from the bundle, `node dist/app.js Ada` fails with
`ReferenceError: o is not defined` or `SyntaxError: The requested module
'./greet.js' does not provide an export named 'greet'`, while every test still
passes, because the tests import `src/` and never touch `dist/`.

And what actually got written:

```
[Build step/Build] ⭐ Run Main List what was produced
[Build step/Build]   | total 8
[Build step/Build]   | -rw-r--r-- 1 root root  525 Oct  8 09:24 app.js
[Build step/Build]   | -rw-r--r-- 1 root root 2362 Oct  8 09:24 app.js.map
```

Two files. `ls -l` is not decoration: it is how you notice that a build quietly
started emitting three chunks, or that `dist/` is empty and the build "passed".

And the run summary, written from the step outputs:

```
[Build step/Build]   ⚙  Summary - ### Build

| file | bytes |
| ---- | ----: |
| `dist/app.js` | 525 |
| `dist/app.js.map` | 2362 |
```

Two rows, honest labels, and the map called out as its own file. Compare with
the single misleading line above it. This is what a size report should look
like.

### The step that did not exist here

This workflow **does not upload an artifact**. It is deliberate, so the chapter
does not have to hedge about a service it cannot test locally: the runner is
destroyed, the output is gone, and nothing here depends on that being
recoverable.

The chapter that fixes that is [20 — Artifacts](20-artifacts.md), and chapter
15's workflow is where an artifact upload appears for the first time.

## 5. When to use it and when NOT to

**Use a build step when:**

- **There is a bundle, a compile, or a codegen.** TypeScript to JavaScript,
  JSX to JavaScript, bundling, minification, migrations. If nothing is
  transformed, there is nothing to build, and pretending otherwise is a step
  that only measures the toolchain's start-up time.
- **You ship the output somewhere.** A container image, a CDN, a Pages deploy, a
  release. Chapter 27 onward.
- **You want the artifact to be testable as an artifact.** Running
  `node dist/app.js Ada` catches a whole category of bug nothing else sees.

**Do NOT reach for a build step when:**

- **Nothing is compiled.** A pure shell script or a config-only repo: `npm run
  build` that echoes "ok" is ceremony. It costs minutes and catches nothing.

- **You are building on every push in a large project.** Cost and time. The
  usual split is fast checks on every push and the expensive build on the merge
  to `main` or on a tag. Chapter 55.

- **The build is not cached or incremental.** A full rebuild on every keystroke
  of your team is a tax on every push. See chapter 16 for dependencies, and
  chapter 30 for Docker layer caching.

- **You treat a passing build as a green pipeline without saving the output.**
  If nothing downstream consumes `dist/`, then the build step is a lint step for
  bundler configuration, which is fine — but then say so, rather than shipping
  a step that reads as if it produced something deployable.

- **`sourcemap: 'inline'` in production without deciding.** It embeds the whole
  original source in the shipped file and inflates it several times over. Here
  the map is 4.5× the code; inlined it would be inside every copy you deploy.

- **Trusting the printed total as a size budget.** See section 4. Budget the file
  you ship, and decide separately about the map.

## 6. Common mistakes

- **Reading `built dist/app.js (2887 bytes)` as the size of `dist/app.js`.** It
  is the sum of every metafile output. `dist/app.js` is 525 bytes. Symptom: a
  size budget that passes locally and fails a real size check, or a "2.8 kB"
  claim in a README that is off by 4.5×.

- **Not running the output.** Symptom: green pipeline, broken artifact. Lint and
  tests read `src/`; only `node dist/app.js` reads `dist/`. A bundler config bug
  is invisible to everything else in the pipeline.

- **Forgetting `id:` on the step that writes outputs.** Symptom: no error
  anywhere, and `$GITHUB_STEP_SUMMARY` containing a table with empty cells.
  Empty is not a failure, so nothing warns you.

- **Using `::set-output`.** Removed. Symptom: the run is fine but the value never
  appears, or the step fails on a runner that enforces the deprecation. Use
  `echo "key=value" >> "$GITHUB_OUTPUT"`.

- **Using `echo $BYTES >> $GITHUB_OUTPUT` without quotes.** Symptom: a value
  containing spaces silently becomes two values, and the second one is ignored.
  Always `"key=$value"`.

- **Job-level `outputs:` placed between steps.** Symptom: the job is invalid, or
  silently the outputs are not registered. Job `outputs:` sits beside `runs-on`,
  never inside `steps:`. Chapter 02.

- **Not deleting the output directory first.** Symptom: a renamed source file
  leaves its old bundle in `dist/`, and you deploy a build containing code that
  no longer exists. `build.mjs` does `rm -rf dist` first; your build should too.

- **Building in the repository root and linting the output.** Symptom: ESLint
  fails on `dist/app.js` because minified code has no unused variables and does
  have short names. `eslint.config.js` ignores `dist/**`.

- **Checking in `dist/`.** Symptom: merge conflicts on every build, and a diff
  full of generated noise that hides the one line that matters.

- **Assuming a green build means deployable.** It means it compiled and ran once
  with one argument. It does not mean it works in a container, on a different
  Node version, or with real input. That is what chapter 30 is for.

- **Caching `dist/` in the dependency cache.** A cache is keyed and reused; a
  build output is unique per commit. `dist/` belongs in an artifact.

## 7. Try it yourself

**Exercise: make the build lie to you, then learn to catch it.**

The `2887` confusion is the headline, so start there.

1. Build locally and read the numbers honestly:

   ```bash
   cd cicd-learn
   npm run build
   ls -l dist/
   wc -c dist/app.js dist/app.js.map
   ```

   `built dist/app.js (2887 bytes)` and `525` and `2362`. Add them up. Now you
   will never be confused by this again, and it takes thirty seconds.

2. **Break the message on purpose** and see exactly what the metafile is doing.
   In a throwaway copy, change the last line of `build.mjs` to print each output
   separately:

   ```js
   for (const [file, info] of Object.entries(result.metafile.outputs)) {
     console.log(`${file} ${info.bytes} bytes`);
   }
   ```

   Run it. Now the log tells the truth, and you can see that `outputs` had two
   keys all along. This is the fix if you ever write a build script: name every
   file, or clearly label the sum as a sum.

3. **Break the bundle in a way lint and tests cannot see.** In a copy, add to
   `eslint.config.js`:

   ```js
   { ignores: ['dist/**', 'node_modules/**', 'coverage/**', 'src/greet.js'] },
   ```

   No — that is the wrong experiment, it makes lint miss something too. Do it
   properly instead: make the **bundler** skip a file. In `build.mjs`, change
   `bundle: true` to `bundle: false`:

   ```bash
   sed -i 's/bundle: true/bundle: false/' build.mjs
   npm run lint && npm test && npm run build
   ```

   The build still *succeeds*. esbuild wrote a file, and reported a size. Then
   run the step the pipeline runs:

   ```bash
   node dist/app.js Ada
   ```

   That is where it dies, with an unresolved `import` in the output. This is the
   whole argument for the "Run the built output" step, demonstrated rather than
   asserted.

4. **Break the size report.** Change the step's measurement to the total and
   watch the summary become wrong in a way nobody would notice:

   ```bash
   sed -i 's|bytes=$(wc -c < dist/app.js)|bytes=$(( $(wc -c < dist/app.js) + $(wc -c < dist/app.js.map) ))|' \
     ../.github/workflows/14-build-step.yml
   ```

   The table now says `2887` under `dist/app.js`. Everything is green, nothing is
   red, and the number is wrong. Revert it.

5. **Break the pipeline for real.** Delete `id: build` from the step and look at
   the summary table in the run summary:

   ```
   | file | bytes |
   | ---- | ----: |
   | `dist/app.js` |  |
   | `dist/app.js.map` |  |
   ```

   Empty cells, no error, green run. Then restore `id: build` and confirm the
   numbers come back. This is the failure mode that costs an afternoon, and it
   never announces itself.

**Hint:** to see the whole step in a real run:

```bash
./scripts/verify.sh .github/workflows/14-build-step.yml build push ch14-build
```

**What this exercise proves:** the 2887/525/2362 relationship, the metafile
structure, that `bundle: false` passes lint and tests but fails when the output
is executed, and that a missing `id:` silently blanks the summary. **What it
cannot prove:** anything about artifact upload or download, or that a hosted
runner destroys the workspace the way `act` may not. `act` copies or bind-mounts
your working tree, so a `dist/` from a previous run can survive into the next
one — delete `cicd-learn/dist` before any experiment whose result depends on a
clean build.

## 8. Next

You now have four working steps: install, lint, test, build. Four workflow files,
four chances to be red.

Chapter 15 puts them in one file, argues for the order lint → test → build, and
documents a real trap discovered while writing it: `defaults.run.working-directory`
at **workflow** level breaks any job that does not check the code out first.

→ [15 — Putting it together: the order](15-ci-pipeline-order.md)