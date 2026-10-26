# 52 — A containerized service [runnable]

> **Verification.** The workflow in this chapter is
> `.github/workflows/52-containerized-service.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/52-containerized-service.yml "" push ch52`,
> and the full log is at `docs/_logs/ch52.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/52-containerized-service.yml (2 job(s))`.
>
> **What this local execution cannot prove.** `act` runs the build on the
> local Docker daemon, so the build, the smoke test, the image size and the
> layer list are real and are quoted below. What it cannot reproduce is
> GitHub's hosted runner toolchain, the `GITHUB_TOKEN` scoping, the
> `type=gha` cache's behaviour across separate runs on the hosted cache, and
> the `push` job, which needs a tag and a real registry. The image itself is
> identical to what a hosted runner would produce, because the Dockerfile
> pins its base image. The push half is described from the documentation and
> from chapter 31, not from a local run.

---

## 1. Simple explanation (like I'm 7)

You baked a cake and sealed it in a box (chapter 30). Now you want a
machine that bakes the box, checks the cake inside is good, and only ships
the box to the warehouse when the head baker stamps it "approved for
release". Most days the box is built and tasted but stays in the kitchen.
On release day, the stamped box goes to the warehouse.

A **containerized service** is a program shipped as a Docker image. The
pipeline builds the image on every push, runs it to prove it works, and
pushes it to a registry only when a tag is pushed. Building on every push
catches Dockerfile bugs early; pushing only on tags means you never ship an
untested or unreviewed image.

## 2. Real name

### Containerized service

An application packaged as a container image and run as a container, rather
than installed onto a host. The image is the artifact; the container is
the running instance. Chapter 30.

### Build on every push

Running the Docker build for every commit, even when you will not push the
result. Catches Dockerfile regressions (missing files, bad permissions,
broken base image) at the moment they are introduced, not at release time.

### Push on tag only

Restricting the registry push to runs triggered by a version tag. Keeps
untested images out of the registry and keeps the registry clean. The
`if: startsWith(github.ref, 'refs/tags/v')` condition is the gate.

### `ghcr.io`

GitHub Container Registry. Free for public images; private images count
against storage. Uses the automatic `GITHUB_TOKEN` with `packages: write`.
Chapter 31.

### `docker/build-push-action@v7`

The action that builds (and optionally pushes) an image. Supports
`load: true` (local daemon) and `push: true` (registry). Chapter 30 and 31.

### `docker/metadata-action@v6`

Generates tags and labels from git context (SHA, branch, semver, PR
number). Used to stop hand-writing tag lists. Chapter 31.

### Image tag strategy

Which tags an image gets: the commit SHA (immutable, traceable), the
branch name (convenient, mutable), and a semver tag on release (human
readable). Never `latest` alone.

### Non-root container

A container whose process runs as an unprivileged user. Costs one `USER`
line in the Dockerfile and removes a whole class of container-escape risk.
Chapter 30.

### Distinctions people get wrong

- **Build vs push.** Building proves the image works; pushing publishes it.
  They are separate jobs here, and the push job has stricter permissions.
- **`load` vs `push`.** `load` puts the image in the local daemon so you
  can run it. `push` sends it to a registry. You cannot do both in one
  invocation by default. Chapter 30.
- **Tag vs digest for deployment.** A tag can be moved; a digest cannot.
  Deploy by digest in production. Chapter 31.
- **`latest` vs SHA.** `latest` tells you nothing about what is running.
  Always push the SHA; add `latest` only as a convenience.
- **Registry vs repository.** The registry is the service (`ghcr.io`); the
  repository is the named collection inside it. One registry, many repos.

## 3. Workflow example

This is the complete `.github/workflows/52-containerized-service.yml` from
this repository.

```yaml
name: Containerized service

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    name: Build and verify the image
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4
      - name: Build
        id: build
        uses: docker/build-push-action@v7
        with:
          context: cicd-learn
          file: cicd-learn/Dockerfile
          tags: cicd-learn:${{ github.sha }}
          load: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
      - name: Smoke test the running container
        run: |
          docker run --rm cicd-learn:${{ github.sha }} Ada | grep -q 'HELLO, ADA!'
          echo "the container serves the expected output"
      - name: Report the image
        run: |
          echo "image: cicd-learn:${{ github.sha }}"
          echo "size:  $(docker images cicd-learn:${{ github.sha }} --format '{{.Size}}')"
          {
            echo "### Containerized service"
            echo ""
            echo "- image: \`cicd-learn:${{ github.sha }}\`"
            echo "- size: $(docker images cicd-learn:${{ github.sha }} --format '{{.Size}}')"
            echo ""
            echo "The image is built and verified, but NOT pushed. Push happens"
            echo "only on a tag, in the tag-driven release pipeline."
          } >> "$GITHUB_STEP_SUMMARY"

  # ── Push on tag only ──────────────────────────────────────────────────────
  push:
    name: Push the image to the registry
    runs-on: ubuntu-24.04
    needs: [build]
    if: startsWith(github.ref, 'refs/tags/v')
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Push
        uses: docker/build-push-action@v7
        with:
          context: cicd-learn
          file: cicd-learn/Dockerfile
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/cicd-learn:${{ github.ref_name }}
            ghcr.io/${{ github.repository }}/cicd-learn:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Structural things to notice:

1. **Two jobs, opposite permissions.** `build` is `contents: read` only.
   `push` adds `packages: write`, and only runs on a tag. Least privilege
   in practice: the job that does not push cannot push.
2. **`build` runs on every push and PR.** It catches Dockerfile bugs before
   they reach a release, and it does not need any secret.
3. **`push` is gated by `if: startsWith(github.ref, 'refs/tags/v')`.** A
   normal push to `main` runs `build` and skips `push`. A tag push runs
   both.
4. **`push` rebuilds rather than reusing.** It does not download the image
   from `build`; it rebuilds from the Dockerfile with the same cache. That
   is simpler and avoids passing images between jobs, at the cost of a
   second build. Chapter 31 discusses the trade-off.
5. **The smoke test asserts, it does not just print.** `grep -q 'HELLO, ADA!'`
   turns a missing line into a non-zero exit, which fails the step.
6. **`timeout-minutes: 20`.** A Docker build that hangs should not burn the
   default six hours.
7. **The report step writes a summary.** The image name and size land in the
   run summary, so a regression (a 1GB image) is visible without opening a
   shell.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch52.log` builds the image and smoke-tests it. The build step
completes and reports the image digest:

```
[Containerized service/Build and verify the image]   ✅  Success - Main Build [27.040419592s]
```

Then the smoke test runs the container and checks its output:

```
[Containerized service/Build and verify the image] ⭐ Run Main Smoke test the running container
[Containerized service/Build and verify the image]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/3] user= workdir=
[Containerized service/Build and verify the image]   | the container serves the expected output
[Containerized service/Build and verify the image]   ✅  Success - Main Smoke test the running container [801.109187ms]
```

The report step prints the image name and size:

```
[Containerized service/Build and verify the image] ⭐ Run Main Report the image
[Containerized service/Build and verify the image]   🐳  docker exec cmd=[bash -e /var/run/act/workflow/4] user= workdir=
[Containerized service/Build and verify the image]   | image: cicd-learn:f910ba9c5cf17c6f7fc61410349e5de80e6f69c1
[Containerized service/Build and verify the image]   | size:  336MB
[Containerized service/Build and verify the image]   ✅  Success - Main Report the image [132.761197ms]
```

And the summary block:

```
[Containerized service/Build and verify the image]   ⚙  Summary - ### Containerized service

- image: `cicd-learn:f910ba9c5cf17c6f7fc61410349e5de80e6f69c1`
- size: 336MB

The image is built and verified, but NOT pushed. Push happens
only on a tag, in the tag-driven release pipeline.
```

The job ends with `🏁 Job succeeded`.

### The push half (documented, not verified locally)

The `push` job does not run in `docs/_logs/ch52.log`, because the run used
the `push` event, not a tag. On github.com, after pushing a tag `v1.0.0`:

1. `build` runs as shown above and passes.
2. `push` starts (the `if:` condition is true). It logs in to `ghcr.io`
   with `GITHUB_TOKEN` and reports `Login Succeeded`.
3. `docker/build-push-action` rebuilds and pushes two tags:
   `ghcr.io/<owner>/<repo>/cicd-learn:v1.0.0` and `...:sha-...`.
4. The action outputs `digest=sha256:...`, the registry's content hash.
5. The package appears under the repository's Packages page.

### Two findings worth understanding

**1. The image is 336MB, and most of it is the base image.** The
Dockerfile is a two-stage build on `node:22-alpine`, so the size is
dominated by the Node runtime, not by the app. The app layer is ~20kB.
Shrinking it further means a smaller base image or a distroless image, which
is a separate decision from the pipeline.

**2. The non-root check is structural, not a test.** The Dockerfile ends
with `USER node`, so `whoami` prints `node` and the container's UID is not
0. The smoke test runs as that user, which proves the app works without root
privileges. If you ever add a step that needs root, it will fail here, which
is the point.

### What `act` cannot show

- **The push.** No tag, no registry. The `push` job's condition is false on a
  `push` event, so it is skipped. Verify on GitHub with a real tag.
- **`GITHUB_TOKEN` scoping.** `act` does not mint the token. The
  `packages: write` permission is granted by GitHub based on the workflow's
  `permissions:` block. Chapter 25.
- **The registry.** `ghcr.io` stores the image; `act` has no registry. The
  local daemon is not a registry. Chapter 31.
- **Cache across runs.** `type=gha` cache is present locally but is not the
  hosted cache. The second build may be faster or not depending on local
  state.

## 5. When to use it and when NOT to

**Use a containerized service pipeline when:**

- **You ship a container to production.** If production runs your image, CI
  must build and test that image, or you are shipping something nobody
  tested.
- **You want reproducible environments.** The image contains the runtime and
  dependencies; "works on my machine" stops being an excuse.
- **You want to separate build from deploy.** Build once, push to a
  registry, deploy pulls the same digest. No rebuild in production.
- **You want to catch Dockerfile bugs early.** Building on every push turns
  a broken Dockerfile into a red build, not a 3am incident.

**Do NOT build and push containers when:**

- **You ship static files.** A static site on Pages or a CDN does not need a
  container; the container just adds size and complexity.
- **Your host runs Node directly.** A platform that runs `npm start` (Heroku,
  Render, Railway) needs a Dockerfile only if you want control over the
  runtime.
- **You build without a smoke test.** A build that produces an image nobody
  runs proves the Dockerfile parses, not that the image works. Always run it.
- **You push on every commit.** Untested images in a registry are a
  liability. Push on tags, or on a protected branch after CI is green, and
  never on a feature branch.
- **You have no retention policy.** Registries accumulate images forever.
  Set retention or your storage bill grows silently.

## 6. Common mistakes

- **Forgetting `load: true`.** The build succeeds, the image exists inside
  buildx, and `docker run` fails with "unable to find image." Symptom: a
  green build followed by a red run step. Fix: add `load: true`.
- **Pushing `latest` only.** `latest` moves; you cannot tell which commit is
  running. Symptom: "which version is deployed?" has no answer. Fix: always
  push the SHA tag; add `latest` optionally.
- **Pushing on every commit.** Symptom: a registry full of untested images
  and a storage bill. Fix: gate the push on a tag or a protected branch.
- **Missing `packages: write`.** The push fails with 403. Symptom: a
  successful build followed by a permission error. Fix: add
  `packages: write` to the push job.
- **Wrong image name case.** `ghcr.io` requires lowercase owner and image
  name. `github.repository` is not always lowercase. Symptom: "name
  invalid". Fix: lowercase it, or use `docker/metadata-action` which does.
- **Running as root.** The default user in most base images is root.
  Symptom: `whoami` prints `root`. Fix: add `USER node` and `--chown` on
  `COPY`.
- **Assuming `rm` shrinks the image.** It does not, because the file was
  already committed in an earlier layer. Symptom: a 336MB image that contains
  no `node_modules` at runtime. Fix: do not copy `node_modules` into the
  final stage.
- **No smoke test.** Symptom: a green build that ships a broken image. Fix:
  always `docker run` the image and check its output.
- **No timeout.** A hung build burns the default 360 minutes. Symptom: a
  run that sits for hours. Fix: `timeout-minutes:` on the job.
- **Building the same image twice for no reason.** The push job rebuilds
  instead of reusing the built image. That is a deliberate trade-off here
  (simpler, no cross-job image transfer), but it costs a second build. If
  build time matters, push from the build job instead.

## 7. Try it yourself

**Exercise: build, smoke-test, and (optionally) push locally.**

Part A — the verified build (no push):

1. Run the workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/52-containerized-service.yml "" push ch52
   ```

   Confirm the image builds, prints `HELLO, ADA!`, is 336MB, and runs as
   `node`. That is the baseline.

2. **Prove the smoke test catches a regression.** Change the `grep` pattern
   to `HELLO, BOB!` and run. The build passes; the smoke test fails. Revert.

3. **Prove `load` matters.** Remove `load: true` and run. The build step
   succeeds; the smoke test fails with "unable to find image." Restore
   `load: true`.

4. **Prove the tag gate.** The `push` job should not run on a `push` event.
   Check the log: there is no `Push the image to the registry` job. That is
   the `if:` condition working.

Part B — push to a real registry on your own machine (optional, free):

5. Start a local registry:

   ```bash
   docker run -d -p 5000:5000 --name local-registry registry:2
   ```

6. Re-tag and push the image you built in part A:

   ```bash
   docker tag cicd-learn:main localhost:5000/cicd-learn:main
   docker push localhost:5000/cicd-learn:main
   ```

7. Pull it back to prove it round-trips:

   ```bash
   docker rmi localhost:5000/cicd-learn:main
   docker pull localhost:5000/cicd-learn:main
   docker run --rm localhost:5000/cicd-learn:main Ada
   ```

   The output is `HELLO, ADA!` again. The image survived the round trip
   through a registry.

8. **Clean up:**

   ```bash
   docker stop local-registry && docker rm local-registry
   ```

Part C — on GitHub, for real:

9. Push a tag `v0.0.1` to a repository that has this workflow. Watch the
   `push` job run and the package appear under Packages.

10. **Break it on purpose.** Remove `packages: write` from the `push` job and
    push a tag. The login succeeds but the push fails with 403. Restore the
    permission.

**Hint:** the local registry speaks plain HTTP on port 5000. A production
registry speaks HTTPS and needs authentication. The protocol is the same;
only the URL and the login differ.

## 8. Next

You can now build and (on a tag) publish a container image. The next
pattern is the one that keeps you up at night: changing a database schema
without losing data.

→ [53 — Database migrations, safely](53-pattern-database-migrations.md)
EOF
echo written