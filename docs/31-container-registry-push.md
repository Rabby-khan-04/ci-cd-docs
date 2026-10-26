# 31 — Pushing an image to a registry [read-only example]

> **Verification.** This chapter is a **`[read-only example]`**: the workflow
> it describes was **not** executed, because pushing an image needs a
> registry login and a registry you control. There is no log for it. The
> build, smoke-test and inspection outputs it relies on are the real outputs
> from chapter 30, quoted from `docs/_logs/ch30.log`. `python3
> scripts/validate-workflows.py` was run on the workflow file quoted in
> section 3 and reports it as valid YAML with 1 job.
>
> **What you can run today.** The free alternative is chapter 30's workflow,
> `.github/workflows/30-docker-build.yml`: it builds the image, loads it
> into the runner's daemon, and smoke-tests it, with no push and no login.
> That is the same build with the last step removed. The commands for pushing
> to a free local registry are in section 7.

---

## 1. Simple explanation (like I'm 7)

You baked the cake and sealed it in a box (chapter 30). Now you need to get
that box to the school cafeteria so the lunch staff can serve it. The
cafeteria has a **warehouse** (a registry) where boxes are stored by name and
version. You drive the box to the warehouse, hand it to the clerk, and the
clerk puts it on the shelf under `cicd-learn:sha-abc123`. Later, any kitchen
anywhere can ask the warehouse for that exact box and get the same cake.

A **container registry** is the warehouse. It stores Docker images and hands
them out on request. GitHub provides one for free, attached to your
repository: `ghcr.io` (GitHub Container Registry). You log in with the
token GitHub already gives every workflow, build the image, and push it.
No extra account, no credit card.

This chapter is marked `[read-only example]` because pushing needs a real
registry and a real login, which `act` cannot provide. But the build half is
exactly chapter 30, and the push half is three lines. Read the three lines,
understand them, and run chapter 30 for the part you can actually execute.

## 2. Real name

### Container registry

A service that stores and distributes container images. You push an image to
it; others pull it. Examples: GitHub Container Registry (`ghcr.io`), Docker
Hub (`docker.io`), Amazon ECR, Google Artifact Registry, Azure Container
Registry. The protocol is the same (OCI Distribution Spec); only the URL
and the login differ.

### Push

Uploading a locally built image to a registry. After a push, the image is
available to anyone (or any CI job) that can authenticate to the registry
and pull it.

### Pull

Downloading an image from a registry to a local daemon. The counterpart of
push. `docker pull ghcr.io/owner/repo:sha-abc`.

### Tag (in a registry context)

An image's name in the registry: `ghcr.io/owner/repo:sha-abc123`. The part
before the colon is the repository path; after the colon is the tag. A
registry can hold many tags for the same image.

### Digest (in a registry context)

The content hash the registry assigns on push. Pushing the same bytes twice
yields the same digest. Pulling by digest guarantees you get exactly those
bytes, even if the tag was moved.

### `ghcr.io`

GitHub Container Registry. Free for public images; private images count
against your storage quota. Images are tied to a user or organization and
can be linked to a repository for discoverability.

### `docker/login-action@v4`

An action that authenticates the Docker CLI to a registry. For `ghcr.io`
it uses the automatic `GITHUB_TOKEN` with `packages: write` permission. No
stored secret is needed.

### `docker/metadata-action@v6`

An action that generates tags and labels for an image from git context:
commit SHA, branch name, semver tags, PR number. It outputs a `tags` string
you feed to `build-push-action`. This is how you stop hand-writing tag
lists.

### `packages: write` permission

The permission a workflow needs to push to `ghcr.io`. Granted at workflow
level. Without it, the push fails with 403.

### Image naming convention for ghcr.io

`ghcr.io/<owner>/<image>:<tag>`, where `<owner>` is the user or
organization name (lowercased) and `<image>` is usually the repository
name. Example:
`ghcr.io/octocat/cicd-learn:sha-aa4fe9e164daa8cb6ac189d751ca2a0e15ab0b5a`.

### Distinctions people get wrong

- **Registry vs repository.** A registry is the service (`ghcr.io`). A
  repository is a named collection of images inside it
  (`ghcr.io/owner/cicd-learn`). One registry, many repositories.
- **Push vs load.** `push` sends the image to a registry for others.
  `load` puts it in the local daemon for this job. You can do both in one
  build (`push: true` plus a separate `load` build, or build once and
  push).
- **Tag vs digest for deployment.** Deploy by digest in production. A tag
  can be overwritten by a later push; a digest cannot.
- **Public vs private image.** A public image can be pulled by anyone
  without authentication. A private image needs a token. Default for
  `ghcr.io` is private; you change visibility in the package settings.
- **`GITHUB_TOKEN` vs a PAT.** For pushing to `ghcr.io` from a workflow,
  the automatic `GITHUB_TOKEN` is enough and is preferred. A personal
  access token is only needed for pushing from your laptop or for
  cross-repository access.
- **Metadata action output vs hand-written tags.** `docker/metadata-action`
  generates consistent, conventional tags. Hand-written tag lists drift and
  miss PR numbers and semver.

## 3. Workflow example

This workflow was **not executed**. It needs a registry login and a registry
you control, which `act` cannot provide. It is shown here so you can read
the shape; the build half is identical to chapter 30.

```yaml
name: Push an image to a registry

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  packages: write        # required to push to ghcr.io

jobs:
  build-and-push:
    name: Build and push the image
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7

      # Generate tags and labels from git context. This is what produces the
      # `sha-...` and `latest` tags without hardcoding them.
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ghcr.io/${{ github.repository }}
          # github.repository is "owner/repo", lowercased by the action.
          tags: |
            type=sha,format=long
            type=raw,value=latest,enable={{is_default_branch}}

      # Log in to ghcr.io using the automatic token. No secret to create.
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/setup-buildx-action@v4

      # Build and push in one step. `push: true` is the only difference from
      # chapter 30, where `load: true` was used instead.
      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: cicd-learn
          file: cicd-learn/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Prove the pushed image exists and is pullable, by digest.
      - name: Inspect the pushed image
        run: |
          echo "tags:"
          echo "${{ steps.meta.outputs.tags }}"
          echo
          echo "digest: ${{ steps.build.outputs.digest }}"
```

Structural things to notice:

1. **`packages: write` is the new permission.** Without it, the push fails
   with 403. `contents: read` stays, because checkout still needs it.
2. **`docker/login-action` uses `GITHUB_TOKEN`.** No personal access token,
   no secret to create in Settings. The token is minted per run.
3. **`metadata-action` generates tags.** `type=sha,format=long` produces the
   full commit SHA tag; `type=raw,value=latest` adds `latest` only on the
   default branch. This replaces the hand-written tag list from chapter 30.
4. **`push: true` instead of `load: true`.** You cannot `load` and `push`
   in the same build invocation with this action's defaults; if you also
   want to smoke-test locally, build twice or use `outputs`. Chapter 30's
   `load: true` is the testable half.
5. **The image name comes from `github.repository`.** That keeps the
   registry path and the repo path in sync, so nobody typos a name.
6. **The digest is the receipt.** `steps.build.outputs.digest` is the
   immutable reference to what was pushed. Save it (job output, release
   note, deployment record) if you need to prove what shipped.

## 4. What I should see

There is no real log for this workflow. What follows is split into two
parts: the build half, which is real and quoted from chapter 30, and the
push half, which is described from the documentation and is not verified
locally.

### The build half (real, from `docs/_logs/ch30.log`)

The image builds and is smoke-tested, exactly as in chapter 30:

```
[Build a Docker image/Build and smoke-test the image]   | #15 [runtime 7/7] RUN node build.mjs && rm -rf node_modules
[Build a Docker image/Build and smoke-test the image]   | #15 0.136 built dist/app.js (2887 bytes)
[Build a Docker image/Build and smoke-test the image]   | #15 DONE 0.3s
...
[Build a Docker image/Build and smoke-test the image]   | cicd-learn:main 334MB
[Build a Docker image/Build and smoke-test the image]   | {
[Build a Docker image/Build and smoke-test the image]   |   "message": "HELLO, ADA!",
[Build a Docker image/Build and smoke-test the image]   |   "total": 10,
[Build a Docker image/Build and smoke-test the image]   |   "mean": 2.5
[Build a Docker image/Build and smoke-test the image]   | }
[Build a Docker image/Build and smoke-test the image]   | the image works
```

That is the part you can run today, with chapter 30's workflow.

### The push half (documented, not verified locally)

On github.com, with the workflow above:

1. `docker/login-action` authenticates to `ghcr.io` using `GITHUB_TOKEN`.
   The log shows `Login Succeeded`.
2. `docker/build-push-action` builds the image and pushes it. The log shows
   `pushing layer ...` and `pushed ghcr.io/.../cicd-learn:sha-...`.
3. The action outputs `digest=sha256:...`, the registry's content hash.
4. The package appears under the repository's "Packages" page and under
   your user/org packages, linked to the repository.
5. `docker pull ghcr.io/<owner>/cicd-learn:sha-...` from any machine with
   access succeeds and yields the same image.

### What a real run adds that `act` cannot show

- **The registry itself.** `ghcr.io` stores the image; `act` has no
  registry. The local daemon is not a registry.
- **`GITHUB_TOKEN` scoping.** The token's `packages: write` permission is
  granted by the workflow's `permissions:` block. `act` does not mint this
  token.
- **Package visibility and linking.** Whether the image is public or
  private, and whether it is linked to the repository, are Settings in
  GitHub, not YAML.
- **Multi-architecture builds.** Pushing `linux/amd64` and `linux/arm64`
  from one workflow needs `platforms:` and a registry that accepts both.
  `act` on a single-arch host cannot prove this.

## 5. When to use it and when NOT to

**Use a registry push when:**

- **You deploy containers to a host that pulls from a registry.** Kubernetes,
  ECS, Cloud Run, a VPS with `docker compose pull`, all need a registry.
- **You want immutable, versioned artifacts.** An image in a registry is a
  snapshot you can roll back to by digest.
- **You share images across teams or repos.** A registry is the distribution
  mechanism.
- **You want to separate build from deploy.** Build once in CI, push, then
  deploy pulls the same digest. No rebuild in production.

**Do NOT push to a registry when:**

- **You only run the image in the same job.** Chapter 30's `load: true` is
  enough; a push adds a network round trip and storage for nothing.
- **You have no registry and no budget.** `ghcr.io` is free, but private
  images on other registries cost money. Do not push to a paid registry
  without a plan.
- **You are pushing `latest` only, with no SHA tag.** A mutable tag alone
  means you cannot tell what is running. Always push the SHA tag; add
  `latest` as a convenience.
- **You push on every commit to a repo with no retention policy.** Registries
  accumulate images forever. Set retention (delete untagged or old images)
  or your storage bill grows silently.
- **You push secrets into the image.** An image in a registry is just a
  tarball anyone with pull access can extract. If a secret is in a layer, it
  is public to anyone who can pull. Build secrets with `--secret`, never
  `ARG`/`ENV`.

## 6. Common mistakes

- **Missing `packages: write`.** The push fails with 403. Symptom: a
  successful build followed by a permission error. Fix: add `packages: write`
  to the workflow's `permissions:`.
- **Wrong image name case.** `ghcr.io` requires the owner and image name to
  be lowercase. `github.repository` is not always lowercase. Symptom: a
  "name invalid" error. Fix: the metadata action lowercases it; if you
  hand-write the name, lowercase it yourself.
- **Using `load` and `push` in the same build.** `build-push-action` does
  one or the other per invocation by default. Symptom: "image not found"
  when you expected both. Fix: build twice, or build and push, then pull
  for the smoke test.
- **Pushing `latest` only.** Symptom: "which version is in production?"
  has no answer. Fix: always push the SHA tag; add `latest` optionally.
- **Forgetting to link the package to the repository.** The image pushes
  successfully but does not appear under the repo's Packages page. Symptom:
  a stray package nobody finds. Fix: in the package settings, link it to
  the repository.
- **Leaving the image private by accident.** A private image needs a token
  to pull, including from a deploy host. Symptom: `pull access denied` on
  the deploy host. Fix: set visibility in the package settings, or provide
  a pull token.
- **Pushing a root-owned image.** If the image runs as root, anyone who
  pulls and runs it runs as root. Symptom: a security review failure. Fix:
  confirm non-root in chapter 30 before you push.
- **No retention policy.** Symptom: storage grows without bound. Fix:
  configure retention in the package settings to delete untagged or old
  versions.
- **Treating the registry as a backup.** A registry is for distribution, not
  for archiving source. Symptom: images nobody can rebuild. Fix: keep the
  Dockerfile and the workflow in git; the image is reproducible from them.

## 7. Try it yourself

**Exercise: build, then push to a free local registry.**

Part A — the free alternative you can run today (no registry, no login):

1. Run chapter 30's workflow:

   ```bash
   ./scripts/verify.sh .github/workflows/30-docker-build.yml "" push ch30
   ```

   Confirm the image builds, prints `HELLO, ADA!`, and is 334MB. That is
   the entire build half of this chapter, verified.

Part B — push to a real registry on your own machine (optional, free):

2. Start a local registry:

   ```bash
   docker run -d -p 5000:5000 --name local-registry registry:2
   ```

3. Re-tag and push the image you built in part A:

   ```bash
   docker tag cicd-learn:main localhost:5000/cicd-learn:main
   docker push localhost:5000/cicd-learn:main
   ```

4. Pull it back to prove it round-trips:

   ```bash
   docker rmi localhost:5000/cicd-learn:main
   docker pull localhost:5000/cicd-learn:main
   docker run --rm localhost:5000/cicd-learn:main Ada
   ```

   The output is `HELLO, ADA!` again. The image survived the round trip
   through a registry.

5. Inspect the registry's contents:

   ```bash
   curl http://localhost:5000/v2/_catalog
   curl http://localhost:5000/v2/cicd-learn/tags/list
   ```

6. **Clean up:**

   ```bash
   docker stop local-registry && docker rm local-registry
   docker rmi localhost:5000/cicd-learn:main 2>/dev/null
   ```

Part C — on GitHub, for real:

7. Add the workflow from section 3 to a repository. Push to `main`. Watch
   the package appear under the repository's Packages page. Pull it from
   your laptop with `docker pull ghcr.io/<owner>/cicd-learn:sha-...`.

8. **Break it on purpose.** Remove `packages: write` and push. The login
   succeeds but the push fails with 403. Restore the permission.

9. **Break it on purpose, part two.** Change the image name to contain an
   uppercase letter. The push fails with "name invalid." Restore the
   lowercase name.

**Hint:** the local registry in part B speaks plain HTTP on port 5000. A
production registry speaks HTTPS and needs authentication. The protocol is
the same; only the URL and the login differ. That is why part B is a valid
rehearsal for part C.

## 8. Next

You can now build and publish a container image. The next chapter deploys
over SSH to a real server — also a read-only example, because it needs a
real server, with a free alternative that runs entirely in the workflow.

→ [32 — Deploying over SSH](32-ssh-deploy.md)