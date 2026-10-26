# 30 — Building a Docker image

> **Verification.** The workflow in this chapter is
> `.github/workflows/30-docker-build.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/30-docker-build.yml "" push ch30`,
> and the full log is at `docs/_logs/ch30.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/30-docker-build.yml (1 job(s))`.
>
> **A note on the log.** The saved log's header names `.tmp/sim-ch30.yml`,
> a formatting-equivalent copy used for the run; the workflow quoted in
> section 3 is `.github/workflows/30-docker-build.yml`. The job name, steps,
> commands and outputs are the same, which is what matters for the quotes
> below.
>
> **What this local execution cannot prove.** `act` runs the build on the
> local Docker daemon, so the build, the smoke test, the image size and the
> layer list are real and are quoted below. What it cannot reproduce is
> GitHub's hosted runner toolchain, the `GITHUB_TOKEN` scoping, and the
> `type=gha` cache's behaviour across separate runs (the cache is present
> locally but is not the hosted cache). The image itself is identical to what
> a hosted runner would produce, because the Dockerfile pins its base image.

---

## 1. Simple explanation (like I'm 7)

Baking a cake and putting it in a sealed box with a label. The box contains
everything needed to serve the cake: the cake, the plate, the fork, the
instructions. You do not need the bakery's oven, or the baker, or the flour.
Anyone who receives the box can open it and serve the cake, anywhere, any
time, and it will taste the same.

A **Docker image** is that sealed box for software. It contains your code,
the runtime that runs it (Node, Python, ...), and every dependency, in one
file. A **container** is the cake being served: a running instance of the
image. You build the image once, in CI, and then you can run it on a laptop,
a server, or a cloud, and it behaves the same. That is the whole reason
containers exist: **build once, run anywhere, with no "works on my machine."**

This chapter builds the box in CI and proves it opens and serves cake.

## 2. Real name

### Image

A read-only template containing everything needed to run an application:
code, runtime, libraries, environment variables, and a default command. An
image is identified by a name and a tag (`cicd-learn:sha-abc123`) or by a
digest (a content hash). Images are built in layers, which makes them
cacheable and shareable.

### Container

A running instance of an image. You can run many containers from one image;
they are isolated from each other and from the host. When a container stops,
its writable layer is discarded unless you explicitly keep it.

### Layer

One step in an image build, corresponding to one Dockerfile instruction
(`FROM`, `COPY`, `RUN`). Layers are cached and shared between images. A
layer that does not change is reused on the next build, which is why the
order of instructions in a Dockerfile matters so much.

### Dockerfile

A text file with instructions for building an image. Each instruction
creates a layer. Multi-stage builds use several `FROM` lines to separate
build-time tools from the final runtime image.

### Multi-stage build

A Dockerfile with more than one `FROM`. Earlier stages can contain build
tools and dev dependencies; the final stage copies only what is needed to
run. The result is a smaller image with a smaller attack surface.

### `docker/setup-buildx-action@v4`

An action that installs and configures `buildx`, Docker's modern builder.
buildx supports multi-stage builds, advanced caching, and building for
multiple architectures.

### `docker/build-push-action@v7`

An action that builds (and optionally pushes) an image. Despite the name,
it can build without pushing, which is what this chapter does.

### `load: true`

A `build-push-action` option that loads the built image into the local
Docker daemon, so subsequent steps can `docker run` it. Without it, the
image exists only inside the builder's cache and is invisible to
`docker images`. This is the single most common confusion with buildx.

### Tag

A human-readable label attached to an image, like `main` or
`sha-abc123`. Tags are mutable: `latest` can be reassigned. A digest is
immutable and is the safe way to reference an exact image.

### Digest

A content hash of an image, like `sha256:e125...`. Two images with the
same digest are byte-identical. Prefer digests over tags in production.

### Base image

The image a Dockerfile starts from (`FROM node:22-alpine`). It is the
foundation layer; everything else is added on top. Pinning the base image by
digest, not by tag, is what makes builds reproducible.

### Non-root user

A container that runs as a dedicated, unprivileged user instead of `root`.
If an attacker escapes the container, they arrive on the host as that
unprivileged user, not as root. Costs one `USER` line.

### ENTRYPOINT vs CMD

Two Dockerfile instructions that set the default command. `CMD` is the
default that gets *replaced* when you pass arguments to `docker run`.
`ENTRYPOINT` is the executable that *receives* those arguments. For an
application container whose behaviour depends on arguments, `ENTRYPOINT` is
correct. For a default you expect to be overridden wholesale, `CMD` is
correct. See the Dockerfile and the trap below.

### Distinctions people get wrong

- **Image vs container.** An image is a file on disk; a container is a
  process. You build an image, you run a container. "Docker image" and
  "Docker container" are not interchangeable.
- **`load` vs `push`.** `load` puts the image into the local daemon so you
  can run it. `push` sends it to a registry so others can pull it. This
  chapter uses `load`; chapter 31 uses `push`.
- **Tag vs digest.** A tag is a name that can move; a digest is a hash that
  cannot. Deploying by tag means you might get a different image tomorrow.
- **Layer size vs image size.** The image size is the sum of its layers.
  Deleting a file in a later layer does not shrink the image, because the
  earlier layer still contains it. See the 74.2MB node_modules layer below.
- **`ENTRYPOINT` vs `CMD`.** Covered in detail in section 6; the difference
  only shows up when you pass arguments.

## 3. Workflow example

This is the complete `.github/workflows/30-docker-build.yml` from this
repository.

```yaml
name: Build a Docker image

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    name: Build and smoke-test the image
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7

      # buildx is the modern builder. It supports multi-stage builds, better
      # cache control, and building for architectures other than the host's.
      - uses: docker/setup-buildx-action@v4

      # Build and load into the local daemon, so the NEXT step can run it.
      # `load:` is what makes `docker run` possible afterwards. Without it the
      # image exists only inside the builder's cache and never becomes a local
      # image. This is the single most common confusion with buildx.
      - name: Build the image
        id: build
        uses: docker/build-push-action@v7
        with:
          context: cicd-learn
          file: cicd-learn/Dockerfile
          # A tag that describes what was built. `sha` is immutable and
          # traceable; `latest` is a moving target with no history.
          tags: |
            cicd-learn:sha-${{ github.sha }}
            cicd-learn:main
          load: true
          # The cache source. `gha` uses GitHub's own Actions cache, which is
          # what makes the second build much faster than the first.
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # The point of the whole chapter: prove the image actually runs. A build
      # that produces an image nobody executes is not a test.
      - name: Run the image and check the output
        run: |
          echo "--- images present ---"
          docker images cicd-learn --format '{{.Repository}}:{{.Tag}} {{.Size}}'
          echo
          echo "--- running it ---"
          output=$(docker run --rm cicd-learn:sha-${{ github.sha }} Ada)
          echo "$output"
          echo
          # Assert, do not eyeball. Grep the expected line and fail if absent.
          echo "$output" | grep -q 'HELLO, ADA!' || {
            echo "::error::the image did not produce the expected output"
            exit 1
          }
          echo "the image works"

      # Inspect the image: layers, size, and what is inside it.
      - name: Inspect the image
        run: |
          echo "--- size ---"
          docker images cicd-learn:sha-${{ github.sha }} --format '{{.Size}}'
          echo
          echo "--- history (each line is a layer) ---"
          docker history cicd-learn:sha-${{ github.sha }} --format '{{.Size}}\t{{.CreatedBy}}' | head -8
          echo
          echo "--- what is actually in there ---"
          docker run --rm --entrypoint sh cicd-learn:sha-${{ github.sha }} -c \
            'ls -la /app; echo; echo "who am i:"; whoami; echo; echo "node:"; node --version'

      - name: Confirm it does not run as root
        run: |
          # Running as root inside a container is a real, if small, risk. A
          # dedicated unprivileged user costs one line.
          if docker run --rm --entrypoint sh cicd-learn:sha-${{ github.sha }} -c 'test "$(id -u)" = "0"'; then
            echo "::warning title=Container runs as root::Add a USER instruction to the Dockerfile"
          else
            echo "the container runs as a non-root user"
          fi
```

Structural things to notice:

1. **One job, four steps after setup.** Build, run, inspect, confirm non-root.
   They are steps, not jobs, because they share the built image via the
   local daemon.
2. **`load: true` is the bridge.** Without it, `docker run` in the next
   step finds no image and fails with "unable to find image."
3. **The smoke test asserts, it does not just print.** `grep -q` turns a
   missing line into a non-zero exit, which fails the step. Eyeballing a
   log is not a test.
4. **`timeout-minutes: 20`.** A Docker build that hangs should not burn the
   default six hours of allowance.
5. **Tags include both SHA and branch.** The SHA tag is immutable and
   traceable to a commit; the branch tag (`main`) is convenient but mutable.
   Chapter 31 shows how to generate these with `docker/metadata-action`.
6. **The image is inspected, not just built.** Size, layers and runtime
   user are printed so a regression (a 1GB image, a root user) is visible
   in the log without anyone opening a shell.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch30.log` builds the image and smoke-tests it. The build step
completes and reports the image id:

```
[Build a Docker image/Build and smoke-test the image] ⭐ Run Main Build the image
...
[Build a Docker image/Build and smoke-test the image]   | #15 [runtime 7/7] RUN node build.mjs && rm -rf node_modules
[Build a Docker image/Build and smoke-test the image]   | #15 0.136 built dist/app.js (2887 bytes)
[Build a Docker image/Build and smoke-test the image]   | #15 DONE 0.3s
...
[Build a Docker image/Build and smoke-test the image]   ✅  Success - Main Build the image [25.57157126s]
```

Then the smoke test runs the image and checks its output:

```
[Build a Docker image/Build and smoke-test the image] ⭐ Run Main Run the image and check the output
[Build a Docker image/Build and smoke-test the image]   | --- images present ---
[Build a Docker image/Build and smoke-test the image]   | cicd-learn:main 334MB
[Build a Docker image/Build and smoke-test the image]   | cicd-learn:sha-aa4fe9e164daa8cb6ac189d751ca2a0e15ab0b5a 334MB
[Build a Docker image/Build and smoke-test the image]   | 
[Build a Docker image/Build and smoke-test the image]   | --- running it ---
[Build a Docker image/Build and smoke-test the image]   | {
[Build a Docker image/Build and smoke-test the image]   |   "message": "HELLO, ADA!",
[Build a Docker image/Build and smoke-test the image]   |   "total": 10,
[Build a Docker image/Build and smoke-test the image]   |   "mean": 2.5
[Build a Docker image/Build and smoke-test the image]   | }
[Build a Docker image/Build and smoke-test the image]   | 
[Build a Docker image/Build and smoke-test the image]   | the image works
[Build a Docker image/Build and smoke-test the image]   ✅  Success - Main Run the image and check the output [641.959389ms]
```

The inspect step prints size, layers and contents:

```
[Build a Docker image/Build and smoke-test the image] ⭐ Run Main Inspect the image
[Build a Docker image/Build and smoke-test the image]   | --- size ---
[Build a Docker image/Build and smoke-test the image]   | 334MB
[Build a Docker image/Build and smoke-test the image]   | 
[Build a Docker image/Build and smoke-test the image]   | --- history (each line is a layer) ---
[Build a Docker image/Build and smoke-test the image]   | 0B	ENTRYPOINT ["node" "dist/app.js"]
[Build a Docker image/Build and smoke-test the image]   | 0B	USER node
[Build a Docker image/Build and smoke-test the image]   | 20.5kB	RUN /bin/sh -c node build.mjs && rm -rf node…
[Build a Docker image/Build and smoke-test the image]   | 24.6kB	COPY --chown=node:node src ./src # buildkit
[Build a Docker image/Build and smoke-test the image]   | 12.3kB	COPY --chown=node:node build.mjs ./ # buildk…
[Build a Docker image/Build and smoke-test the image]   | 12.3kB	COPY --chown=node:node package.json ./ # bui…
[Build a Docker image/Build and smoke-test the image]   | 74.2MB	COPY --chown=node:node /app/node_modules ./n…
[Build a Docker image/Build and smoke-test the image]   | 8.19kB	WORKDIR /app
[Build a Docker image/Build and smoke-test the image]   | 
[Build a Docker image/Build and smoke-test the image]   | --- what is actually in there ---
[Build a Docker image/Build and smoke-test the image]   | total 24
[Build a Docker image/Build and smoke-test the image]   | drwxr-xr-x    1 root     root          4096 Oct  8 09:49 .
[Build a Docker image/Build and smoke-test the image]   | -rw-rw-r--    1 node     node           764 Oct  8 08:48 build.mjs
[Build a Docker image/Build and smoke-test the image]   | drwxr-xr-x    2 root     root          4096 Oct  8 09:49 dist
[Build a Docker image/Build and smoke-test the image]   | -rw-rw-r--    1 node     node           627 Oct  8 09:23 package.json
[Build a Docker image/Build and smoke-test the image]   | drwxr-xr-x    2 node     node          4096 Oct  8 09:49 src
[Build a Docker image/Build and smoke-test the image]   | 
[Build a Docker image/Build and smoke-test the image]   | who am i:
[Build a Docker image/Build and smoke-test the image]   | node
[Build a Docker image/Build and smoke-test the image]   | 
[Build a Docker image/Build and smoke-test the image]   | node:
[Build a Docker image/Build and smoke-test the image]   | v22.23.3
[Build a Docker image/Build and smoke-test the image]   ✅  Success - Main Inspect the image [396.356369ms]
```

And the non-root check:

```
[Build a Docker image/Build and smoke-test the image] ⭐ Run Main Confirm it does not run as root
[Build a Docker image/Build and smoke-test the image]   | the container runs as a non-root user
[Build a Docker image/Build and smoke-test the image]   ✅  Success - Main Confirm it does not run as root [326.304014ms]
```

The job ends with `🏁 Job succeeded` and `### act exit status: 0`.

### Two findings worth understanding

**1. The image is 334MB, and 74.2MB of that is a layer that no longer exists.**
The layer `COPY --chown=node:node /app/node_modules ./node_modules` is 74.2MB,
even though the Dockerfile runs `rm -rf node_modules` afterwards in the same
`RUN`. The rm happens in a *later* layer, so the node_modules layer is still
in the image, still counted in the size, and still shipped. The image
contains no node_modules at runtime (the inspect step shows only `src`,
`dist`, `build.mjs`, `package.json`), but the bytes are in the layer history.
The fix is to not copy node_modules into the final stage at all, or to use a
multi-stage build where the runtime stage never receives them. This is the
classic "rm does not shrink the image" trap.

**2. ENTRYPOINT vs CMD is a real trap, and the workflow uses it.**
The Dockerfile ends with `ENTRYPOINT ["node", "dist/app.js"]`. So
`docker run img Ada` appends `Ada` and the app receives it as an argument,
printing `HELLO, ADA!`. If the Dockerfile instead used
`CMD ["node", "dist/app.js"]`, then `docker run img Ada` would *replace*
the whole command with `Ada`, and node would try to load a file called
`Ada` and fail. That is why the workflow passes `Ada` as an argument: it
proves the ENTRYPOINT behaviour. Change it to `CMD` and the smoke test fails
with a module-not-found error. Try it.

## 5. When to use it and when NOT to

**Use a Docker build in CI when:**

- **You ship a container.** If production runs your app in a container, CI
  must build that container, or you are shipping something nobody tested.
- **You want reproducible environments.** The image contains the runtime and
  dependencies; "works on my machine" stops being an excuse.
- **You want to test the artifact you ship.** Building and running in CI
  catches Dockerfile bugs (wrong base image, missing files, bad permissions)
  that a plain `npm run build` never sees.
- **You deploy to a registry or a host that takes images.** Chapter 31 and
  32 follow directly from this.

**Do NOT build a Docker image when:**

- **You ship static files.** A static site on GitHub Pages or a CDN does not
  need a container; the container just adds size and complexity.
- **Your build is trivial and your host runs Node.** A platform that runs
  `npm start` for you (Heroku, Render, Railway) needs a Dockerfile only if
  you want control over the runtime.
- **You are building on every commit without a cache.** An uncached Docker
  build that pulls base images and installs dependencies from scratch on
  every push is slow and expensive. Use `cache-from`/`cache-to` (this
  workflow does) or a registry cache.
- **You build but never run.** A build step with no smoke test proves the
  Dockerfile parses, not that the image works. Always run the image.

## 6. Common mistakes

- **Forgetting `load: true`.** The build succeeds, the image exists inside
  buildx, and `docker run` fails with "unable to find image." Symptom: a
  green build followed by a red run step. Fix: add `load: true`.
- **Assuming `rm` shrinks the image.** It does not, because the file was
  already committed in an earlier layer. Symptom: a 334MB image that
  contains no node_modules at runtime. Fix: do not copy node_modules into
  the final stage; or use `--squash` (experimental); or restructure the
  Dockerfile.
- **Running as root.** The default user in most base images is root.
  Symptom: `whoami` prints `root` in the inspect step. Fix: add `USER node`
  (or create a dedicated user) and `--chown` on `COPY`.
- **Using `latest` as the only tag.** `latest` moves; you cannot tell which
  commit is running in production. Symptom: "which version is deployed?"
  has no answer. Fix: always tag with the commit SHA; add `latest` or
  `main` as a convenience tag only.
- **Not pinning the base image.** `FROM node:22-alpine` resolves to
  whatever `22-alpine` points at today. Symptom: a build that worked
  yesterday fails today because the base image changed. Fix: pin by digest
  (`FROM node:22-alpine@sha256:...`).
- **Building without a smoke test.** Symptom: a green build that ships a
  broken image. Fix: always `docker run` the image and check its output.
- **Copying the whole repository into the image.** `COPY . .` pulls in
  `node_modules`, `.git`, tests, and secrets. Symptom: a huge image and a
  leaked secret. Fix: a `.dockerignore` file and explicit `COPY` of only
  what is needed.
- **Confusing ENTRYPOINT and CMD.** Symptom: `docker run img Ada` does
  nothing useful or fails with module-not-found. Fix: use ENTRYPOINT when
  arguments should be appended, CMD when they should replace. Test with an
  argument.
- **No timeout.** A hung build burns the default 360 minutes. Symptom: a
  run that sits for hours. Fix: `timeout-minutes:` on the job.

## 7. Try it yourself

**Exercise: break the image, then fix it.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/30-docker-build.yml "" push ch30
   ```

   Confirm the image builds, prints `HELLO, ADA!`, is 334MB, and runs as
   `node`. That is the baseline.

2. **Prove the ENTRYPOINT trap.** Edit `cicd-learn/Dockerfile`: change
   `ENTRYPOINT ["node", "dist/app.js"]` to
   `CMD ["node", "dist/app.js"]`. Rebuild locally:

   ```bash
   cd cicd-learn && docker build -t trap:test . && docker run --rm trap:test Ada
   ```

   The container fails: node tries to load `./Ada` and exits. Restore
   ENTRYPOINT.

3. **Prove `rm` does not shrink.** Remove the `&& rm -rf node_modules`
   from the `RUN` line and rebuild. The image grows (node_modules is now
   present at runtime too). Restore the line; the size does not come back
   down, because the layer history still contains it. The fix is structural,
   not a deletion.

4. **Prove `load` matters.** Remove `load: true` from the workflow and run
   it. The build step succeeds; the "Run the image" step fails with
   "unable to find image." Restore `load: true`.

5. **Prove the smoke test catches a regression.** Change the `grep` pattern
   to `HELLO, BOB!` and run. The build passes; the smoke test fails. Revert.

6. **Shrink the image (harder).** Restructure the Dockerfile so the runtime
   stage never receives node_modules (build the app in a builder stage,
   copy only `dist/` into the runtime stage). Rebuild and compare the size.
   The 74.2MB layer should disappear.

7. **Break it on purpose.** Add `USER root` before the `ENTRYPOINT` and run
   the "Confirm it does not run as root" step. It prints the warning.
   Revert.

8. **Clean up.** Remove any test images: `docker rmi trap:test` etc.

**Hint:** the smoke test uses `docker run --rm cicd-learn:sha-... Ada`.
The `Ada` is not decoration; it is the argument that exercises ENTRYPOINT.
If you ever change the Dockerfile's command, re-check that this invocation
still means what you think it means.

## 8. Next

You can now build a container image in CI and prove it runs. The next
chapter takes that image and pushes it to a registry so other machines can
pull it — a read-only example, because it needs a real registry login, with
a free alternative you can run today.

→ [31 — Pushing an image to a registry](31-container-registry-push.md)