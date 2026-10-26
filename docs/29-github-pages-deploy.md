# 29 — Deploying a static site to GitHub Pages

> **Verification.** The workflow in this chapter is
> `.github/workflows/29-github-pages-deploy.yml`. It was executed with
> `./scripts/verify.sh .github/workflows/29-github-pages-deploy.yml "" push ch29`,
> and the full log is at `docs/_logs/ch29.log`. The log excerpts in section 4
> are quoted from that file. `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/29-github-pages-deploy.yml (2 job(s))`.
>
> **What this local execution cannot prove, and what it actually showed.** The
> build job's install and build steps pass locally and are quoted below. The
> `actions/configure-pages@v6` step fails in `act` with
> `Get Pages site failed ... Error: Not Found`, because `act` has no Pages
> API and no repository settings to read. `actions/upload-pages-artifact@v5`
> requires GitHub's artifact service, which `act` also does not provide, so
> the upload step is never reached in the local run. The `deploy` job is
> never reached either, because `needs: [build]` waits for a build job that
> failed. On github.com, with Pages enabled and configured to build with
> GitHub Actions, the same file runs end to end and prints a live URL. The
> configure-pages failure is an `act` limitation, not a workflow bug, and is
> shown honestly below.

---

## 1. Simple explanation (like I'm 7)

A school newspaper. The reporters write the articles and lay out the pages
(the build). The editor checks the layout (CI). Then the whole finished issue
goes to the school office, which pins it to the bulletin board in the hallway
where everyone can read it (the deploy). The office only accepts a finished,
checked issue, not loose pages, and it only pins one issue at a time so two
different versions never hang side by side.

**GitHub Pages** is the bulletin board. It is a free, static website host
built into GitHub: you give it a folder of HTML, CSS and JavaScript, and it
serves them at `https://<user>.github.io/<repo>/`. No server to rent, no
domain to buy, no deploy script to write. The "office" in this picture is
three actions that do the pinning for you, and a special environment called
`github-pages` that records that the site went live.

## 2. Real name

### GitHub Pages

A static site hosting service provided by GitHub. Serves the contents of a
branch or an uploaded artifact at a `github.io` URL (or a custom domain you
configure). It hosts only static files: HTML, CSS, JavaScript, images. No
server-side code, no database.

### Static site

A website made of files that do not change between requests: HTML, CSS, JS
and assets. The browser does all the work. Contrast with a dynamic site,
which runs code on a server per request. GitHub Pages can host the former
only.

### `actions/configure-pages@v6`

An action that talks to GitHub's Pages API to set up the Pages environment
for this run: it checks that Pages is enabled and configured to build with
GitHub Actions, and outputs the site's base URL and other metadata. It must
run before `actions/upload-pages-artifact`. On a repository where Pages is
not enabled, it fails with "Get Pages site failed."

### `actions/upload-pages-artifact@v5`

An action that uploads a directory as the Pages artifact. The artifact name
is fixed by the action: `github-pages`. You cannot rename it, and the deploy
step looks for exactly that name. It wraps `actions/upload-artifact` with
Pages-specific metadata.

### `actions/deploy-pages@v5`

An action that takes the `github-pages` artifact and publishes it to GitHub
Pages. It runs in a job bound to the `github-pages` environment and outputs
`page_url`, the live URL of the deployed site.

### `github-pages` environment

A special environment GitHub creates automatically for Pages deployments
when Pages is enabled. You do not create it by hand. It has its own
deployment history and URL, and `deploy-pages` records the deployment
against it.

### Pages build type

A repository setting: how Pages gets its content. "Deploy from a branch"
serves files straight from a branch. "GitHub Actions" lets a workflow upload
an artifact and deploy it. This course uses "GitHub Actions", because it
allows a build step (npm, bundlers) before publishing.

### `pages: write` permission

The permission a workflow needs to publish to Pages. Without it,
`deploy-pages` fails with a 403. It is granted at workflow level alongside
`id-token: write`.

### `id-token: write` permission

Allows the workflow to request an OIDC token, which `deploy-pages` uses to
authenticate to the Pages service without a long-lived secret. Chapter 43
covers OIDC in depth.

### Concurrency group `pages`

A concurrency group named `pages` with `cancel-in-progress: false` is the
standard setting for Pages: two deploys never run at once, and a second one
waits rather than cancelling the first. Cancelling a Pages deploy mid-flight
can leave the site in a half-published state.

### Base URL / path prefix

On a project Pages site (`https://user.github.io/repo/`), the site is served
under `/repo/`, not `/`. Assets and links in your HTML must account for that,
or the deployed page loads with broken styles and 404s. User/organization
sites (`https://user.github.io/`) are served from the root.

### Distinctions people get wrong

- **Pages vs a server.** Pages serves files only. There is no runtime, no
  environment variables at request time, no server-side rendering. If your
  app needs a backend, Pages is the wrong target (see chapter 52).
- **Branch deploy vs Actions deploy.** "Deploy from a branch" publishes raw
  files with no build step. "GitHub Actions" publishes whatever artifact the
  workflow uploads. You pick one in Settings; mixing them is a common source
  of "my deploy did nothing."
- **`upload-pages-artifact` vs `upload-artifact`.** The Pages variant fixes
  the artifact name to `github-pages` and adds Pages metadata. A normal
  `upload-artifact` with any other name will not be picked up by
  `deploy-pages`.
- **`configure-pages` vs enabling Pages.** `configure-pages` assumes Pages is
  already enabled in Settings. It does not enable it for you. Enabling is a
  one-time UI action.
- **`page_url` vs a hardcoded URL.** `page_url` comes from the deploy step's
  output and is the source of truth. Hardcoding `https://user.github.io/repo/`
  works but drifts if the repo is renamed.

## 3. Workflow example

This is the complete `.github/workflows/29-github-pages-deploy.yml` from
this repository.

```yaml
name: Deploy to GitHub Pages

"on":
  push:
    branches: [main]
  workflow_dispatch:

# Pages needs specific permissions. These are the minimum.
permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    name: Build
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
      - run: npm run build

      # configure-pages sets up the Pages environment and outputs the base URL.
      # It must run before upload-pages-artifact.
      - uses: actions/configure-pages@v6

      # Upload the build output as the Pages artifact. The name is fixed by the
      # action: "github-pages". You cannot rename it.
      - uses: actions/upload-pages-artifact@v5
        with:
          path: cicd-learn/dist

  deploy:
    name: Deploy
    runs-on: ubuntu-24.04
    needs: [build]
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v5
      - name: Report the URL
        run: |
          echo "deployed to: ${{ steps.deployment.outputs.page_url }}"
```

Structural things to notice:

1. **Two jobs, one pipeline.** `build` produces the artifact; `deploy`
   publishes it. The split lets `deploy` run under the `github-pages`
   environment with its own permissions and history, while `build` stays a
   plain CI job.
2. **Permissions are specific.** `contents: read` for checkout,
   `pages: write` and `id-token: write` for publishing. Nothing else.
3. **`configure-pages` before `upload-pages-artifact`.** The Pages
   environment must be initialised before the artifact is uploaded, or the
   upload has nowhere to go.
4. **`path: cicd-learn/dist`.** The directory to publish is the build
   output. If your build writes somewhere else, change this and only this.
5. **`environment: github-pages`.** Binds the deploy job to the Pages
   environment so the deployment is recorded and the URL is surfaced.
6. **`url: ${{ steps.deployment.outputs.page_url }}`.** The live URL comes
   from the deploy step's output, not from a hardcoded string.

## 4. What I should see

### The run we actually executed

`docs/_logs/ch29.log` runs the build job. Install and build pass:

```
[Deploy to GitHub Pages/Build] ⭐ Run Main npm ci
[Deploy to GitHub Pages/Build]   | added 127 packages, and audited 128 packages in 1s
[Deploy to GitHub Pages/Build]   | found 0 vulnerabilities
[Deploy to GitHub Pages/Build]   ✅  Success - Main npm ci [1.614635267s]
[Deploy to GitHub Pages/Build] ⭐ Run Main npm run build
[Deploy to GitHub Pages/Build]   | > cicd-learn@1.0.0 build
[Deploy to GitHub Pages/Build]   | > node build.mjs
[Deploy to GitHub Pages/Build]   |
[Deploy to GitHub Pages/Build]   | built dist/app.js (2887 bytes)
[Deploy to GitHub Pages/Build]   ✅  Success - Main npm run build [260.282171ms]
```

Then `configure-pages` fails, because `act` has no Pages API:

```
[Deploy to GitHub Pages/Build] ⭐ Run Main actions/configure-pages@v6
[Deploy to GitHub Pages/Build]   ❗  ::error title=HttpError,file=/run/act/actions/actions-configure-pages@v6/node_modules/@octokit/request/dist-node/index.js,line=124,col=1::Get Pages site failed. Please verify that the repository has Pages enabled and configured to build using GitHub Actions, or consider exploring the `enablement` parameter for this action. Error: Not Found - https://docs.github.com/rest/pages/pages#get-a-apiname-pages-site
[Deploy to GitHub Pages/Build]   ❗  ::error::HttpError: Not Found - https://docs.github.com/rest/pages/pages#get-a-apiname-pages-site
[Deploy to GitHub Pages/Build]   ❌  Failure - Main actions/configure-pages@v6 [1.003394965s]
[Deploy to GitHub Pages/Build] exitcode '1': failure
[Deploy to GitHub Pages/Build] 🏁  Job failed
```

Because the build job failed, the `deploy` job never starts, and
`upload-pages-artifact` is never reached. The log ends with
`Error: Job 'Build' failed` and `### act exit status: 1`.

That is the honest picture: the build is verified, the Pages-specific steps
are not, because they need GitHub's Pages service.

### What a real GitHub run adds (not verified locally)

On github.com, with Pages enabled and set to "GitHub Actions":

1. `build` runs: checkout, setup Node, `npm ci`, `npm run build` →
   `built dist/app.js (2887 bytes)`.
2. `configure-pages` succeeds and outputs the base URL.
3. `upload-pages-artifact` uploads `cicd-learn/dist` as the `github-pages`
   artifact.
4. `deploy` starts (it was waiting on `needs: [build]`). It runs
   `deploy-pages`, which publishes the artifact and outputs `page_url`.
5. The run summary shows the `github-pages` environment with a clickable
   URL, and a deployment record is created.
6. "Report the URL" prints `deployed to: https://<user>.github.io/<repo>/`.
7. If a second push lands while a deploy is in progress, the second run's
   `deploy` waits on the `pages` concurrency group.

### Enabling Pages (one-time, in the UI)

Before the workflow can succeed, Pages must be enabled:

1. Repository → Settings → Pages.
2. Under "Build and deployment", set Source to "GitHub Actions".
3. Save. No branch selection is needed for the Actions source.

The `configure-pages` step's error message names exactly this: "Please
verify that the repository has Pages enabled and configured to build using
GitHub Actions." That is the fix for the failure above, but it can only be
applied on github.com, not in `act`.

### The deployed URL

For a project site, the URL is
`https://<owner>.github.io/<repo>/`. For a user or organization site (repo
named `<owner>.github.io`), it is `https://<owner>.github.io/`. The
workflow does not need to know which: `page_url` carries it.

## 5. When to use it and when NOT to

**Use GitHub Pages when:**

- **You are publishing a static site.** Documentation, a marketing page, a
  generated report, a client-side app.
- **You want free hosting with no infrastructure.** Pages is free for public
  repos and included for private repos on paid plans.
- **You want deploys tied to git.** Every push to `main` republishes; the
  site's history is the commit history.
- **You want a custom domain.** Pages supports custom domains and HTTPS for
  free.

**Do NOT use GitHub Pages when:**

- **You need server-side code or a database.** Pages serves files only. A
  Node/Python/Go backend does not run there.
- **You need request-time logic.** Environment variables, authentication
  gates, per-user content. None of that exists on Pages.
- **You need large files or high bandwidth.** Pages has soft limits on site
  size and bandwidth; a media-heavy site will hit them.
- **You need preview URLs per pull request.** Pages has one URL per repo.
  Per-PR previews need a different host (chapter 51).
- **You need a monorepo of sites.** One Pages site per repository. Multiple
  sites means multiple repos or a different host.

## 6. Common mistakes

- **Pages not enabled, or set to "Deploy from a branch".** `configure-pages`
  fails with "Get Pages site failed." Symptom: the error quoted in section 4.
  Fix: Settings → Pages → Source → "GitHub Actions".
- **Missing permissions.** Without `pages: write` and `id-token: write`,
  `deploy-pages` fails with 403. Symptom: a permission error in the deploy
  job. Fix: add both to the workflow's `permissions:`.
- **Wrong publish path.** `path: cicd-learn/dist` must match where the build
  writes. Symptom: an empty site or a 404 on the root. Fix: check
  `npm run build`'s output directory.
- **Forgetting `configure-pages` before upload.** The upload has no Pages
  environment to attach to. Symptom: an upload error. Fix: keep the order.
- **Using `upload-artifact` instead of `upload-pages-artifact`.** The deploy
  step looks for the `github-pages` artifact name. Symptom: "artifact not
  found" in the deploy job. Fix: use the Pages variant.
- **Assets with absolute paths on a project site.** `/assets/style.css`
  resolves to `https://user.github.io/assets/style.css`, which 404s on a
  project site. Symptom: a page with no styling. Fix: relative paths or a
  base URL that includes the repo name.
- **`cancel-in-progress: true` on the Pages concurrency group.** A cancelled
  deploy can leave the site half-published. Symptom: a broken site after a
  fast push. Fix: `false`.
- **Expecting `act` to publish.** It cannot; Pages is GitHub-only. Symptom:
  "it worked locally" about a site that was never uploaded. Fix: verify on
  GitHub with Pages enabled.

## 7. Try it yourself

**Exercise: publish the site for real.**

1. Run the workflow locally:

   ```bash
   ./scripts/verify.sh .github/workflows/29-github-pages-deploy.yml "" push ch29
   ```

   Confirm `npm ci` and `npm run build` pass and `configure-pages` fails with
   the error quoted in section 4. That failure is expected and honest.

2. **Enable Pages.** Settings → Pages → Source → "GitHub Actions".

3. **Push the workflow to a repository on github.com.** Both jobs pass. The
   run summary shows a clickable URL.

4. **Open the URL.** The page renders. Check the browser's network tab for
   404s on assets; fix any absolute paths.

5. **Break it on purpose.** Change `path:` to `cicd-learn/dist-typo` and
   push. The upload fails with "no files found." Revert.

6. **Break it on purpose, part two.** Remove `pages: write` from
   `permissions:` and push. `deploy-pages` fails with 403. Revert.

7. **Break it on purpose, part three.** Swap `upload-pages-artifact` for
   `upload-artifact` with `name: dist`. The deploy job fails with "artifact
   not found." Revert.

8. **Clean up.** If you do not want a live site, disable Pages in Settings
   or delete the workflow.

**Hint:** `configure-pages` accepts an `enablement` parameter that can enable
Pages automatically for the repository. It requires the token to have
admin rights and is not used here, because enabling Pages is a deliberate
one-time decision, not something a workflow should do on every push.

## 8. Next

You now have a real, runnable deploy to a free host. The next chapter moves
from shipping files to shipping a container: building a Docker image in CI,
proving it runs, and reading its layers.

→ [30 — Building a Docker image](30-docker-image-build.md)