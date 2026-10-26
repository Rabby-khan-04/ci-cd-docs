# 32 — Deploying over SSH [read-only example]

> **Verification.** This chapter is a **`[read-only example]`**: the workflow
> it describes was **not** executed, because deploying over SSH needs a real
> server, a real key pair, and a reachable host. There is no log for it. The
> build and artifact outputs it relies on are the real outputs from chapters
> 27 and 30, quoted from `docs/_logs/ch27.log` and `docs/_logs/ch30.log`.
> `python3 scripts/validate-workflows.py` was run on the workflow file quoted
> in section 3 and reports it as valid YAML with 2 jobs.
>
> **What you can run today.** The free alternative is in section 7: a deploy
> script that runs entirely inside the runner against a local target
> directory, with no server, no key, and no network. It reproduces the exact
> commands a real SSH deploy would run, so you can see the shape and test
> the script.

---

## 1. Simple explanation (like I'm 7)

You have a finished box (the artifact) and a cafeteria (the server) that
needs to receive it. The cafeteria is in another building, and the door is
locked. You do not have a key to the door, but you have a special key that
only opens the cafeteria's delivery hatch, and only from the outside. You
slide the box through the hatch, the cafeteria staff unpack it and put the
new menu on the board, and the old menu comes down. Nobody from the
cafeteria ever comes to your building; you always go to theirs, through the
hatch, with your key.

**Deploying over SSH** is exactly that: your CI runner opens a connection
to a remote server using a private key, runs a short script on that server
to replace the old version with the new one, and disconnects. The server
never initiates anything; the runner always initiates. The private key is
the hatch key, and it lives in GitHub's secrets store, never in the
repository.

This chapter is marked `[read-only example]` because it needs a real server.
But the script that runs on the server is just shell commands, and you can
run those same commands locally against a directory to see exactly what
happens. That is the free alternative in section 7.

## 2. Real name

### SSH (Secure Shell)

A protocol for running commands on a remote machine over an encrypted
connection. Authentication is by password or, in CI, by a key pair. SSH is
the universal remote-control tool for Linux servers.

### Key pair

Two files: a private key (kept secret) and a public key (placed on the
server). Anything encrypted with the public key can only be decrypted by
the private key, and vice versa. In CI, the private key is a secret; the
public key goes in the server's `~/.ssh/authorized_keys`.

### `appleboy/ssh-action@v1`

A widely used GitHub Action that opens an SSH connection to a host and runs
a script on it. It takes the host, username, key and script as inputs. It
is the standard way to deploy over SSH from a workflow.

### Host key verification

SSH checks that the server's identity matches a known fingerprint, to
prevent man-in-the-middle attacks. In CI this is usually disabled or
pinned; either way it must be a conscious choice, not an accident.

### `known_hosts`

The file where SSH stores trusted server fingerprints. In CI you either
pre-populate it or use the action's option to skip verification (less
safe) or to add the host's key (safer).

### Remote deploy script

The shell commands that run on the server: stop the old process, move the
new artifact into place, start the new process, health-check it. This is
the part that actually changes the running system.

### Secrets for SSH

Three values, all stored as repository or environment secrets:
`SSH_HOST` (the server address), `SSH_USER` (the login name), and
`SSH_KEY` (the private key). A fourth, `SSH_PORT`, is optional (default
22).

### Distinctions people get wrong

- **Private key vs public key.** The private key is the secret and goes in
  GitHub. The public key is not secret and goes on the server. Reversing
  them is the most common SSH mistake in CI.
- **SSH vs SCP/rsync.** SSH runs commands. SCP and rsync move files. A
  deploy usually needs both: move the artifact, then run commands to
  restart. `appleboy/ssh-action` can do the file move with its `scp` option
  or you can run `rsync` inside the script.
- **Key-based auth vs password auth.** Passwords in CI are a bad idea
  (they are hard to rotate and easy to leak). Key-based auth is the
  standard. Password auth is for humans at a terminal.
- **Host verification vs convenience.** Disabling host verification
  (`strict_host_key_checking: no`) is common in tutorials and is a real
  security reduction. Pinning the host key is safer and costs one extra step.
- **Root vs deploy user.** Logging in as root over SSH from CI is dangerous:
  a leaked key gives full control of the server. Use a dedicated deploy
  user with only the permissions it needs.
- **One server vs many.** SSH deploy scales poorly: pushing to ten servers
  means ten SSH connections and ten chances to fail halfway. For many
  targets, use a registry pull (chapter 31) or a config-management tool.

## 3. Workflow example

This workflow was **not executed**. It needs a real server and a real key
pair, which `act` cannot provide. It is shown here so you can read the
shape. The build half is identical to chapter 27 (CI builds and uploads an
artifact); the deploy half is the SSH step.

```yaml
name: Deploy over SSH

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  ci:
    name: CI
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
      - run: npm run lint
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist
          retention-days: 7
          if-no-files-found: error

  deploy:
    name: Deploy to server
    runs-on: ubuntu-24.04
    needs: [ci]
    if: github.ref_name == 'main' && github.event_name == 'push'
    # Environment-bound, so the key and host are environment-scoped secrets.
    environment:
      name: production
      url: https://example.com
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: dist
          path: dist

      # The SSH step. The script runs ON THE SERVER, not in the runner.
      - name: Deploy over SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          port: ${{ secrets.SSH_PORT || 22 }}
          script: |
            set -e
            APP_DIR=/var/www/cicd-learn
            RELEASE_DIR=$APP_DIR/releases/$(date +%Y%m%d%H%M%S)
            mkdir -p "$RELEASE_DIR"
            # The artifact was uploaded to the runner; copy it to the server
            # first (scp), then unpack and switch. See the note below.
            echo "deploying to $RELEASE_DIR"
            # ... unpack, symlink, restart, health check ...
            echo "deployed"
```

Structural things to notice:

1. **CI and deploy are separate jobs.** CI builds and uploads the artifact;
   deploy downloads it and ships it. Same shape as chapter 27.
2. **The SSH step runs on the server.** The `script:` block is not executed
   in the runner; it is sent to the server over SSH and executed there. Files
   must be transferred separately (scp/rsync) before the script can use them.
3. **Secrets are environment-scoped.** `SSH_HOST`, `SSH_USER`, `SSH_KEY`
   live in the `production` environment's secrets, not repository secrets, so
   a staging job cannot read them.
4. **`set -e` in the script.** Without it, a failed command on the server
   does not fail the step, and the deploy reports success while half-done.
5. **The release directory pattern.** Each deploy goes into a timestamped
   directory; a symlink (`current`) points at the active one. Rollback is
   repointing the symlink. Chapter 46.
6. **`concurrency: deploy-production` with `cancel-in-progress: false`.** Two
   SSH deploys never run at once; the second waits.

### A note on file transfer

`appleboy/ssh-action` runs commands on the server but does not move files by
default. The common patterns are:

- **scp inside the script's setup**, using the action's `scp` option or a
  separate `appleboy/scp-action` step to copy `dist/` to the server first.
- **rsync over SSH** from the runner: `rsync -avz dist/ user@host:/path/`.
- **Pull from a registry** (chapter 31): the server runs
  `docker pull` and `docker compose up`. This is usually better than SCP
  for containerized apps, because the artifact travels through the registry
  rather than through the runner.

For this course's Node app (no container), the SCP/rsync pattern is the
natural one.

## 4. What I should see

There is no real log for this workflow. What follows is split into two
parts: the build half, which is real and quoted from chapter 27, and the
deploy half, which is described from the documentation and is not verified
locally.

### The build half (real, from `docs/_logs/ch27.log`)

CI builds and uploads the artifact, exactly as in chapter 27:

```
[Deployment fundamentals/CI] ⭐ Run Main npm run build
[Deployment fundamentals/CI]   | built dist/app.js (2887 bytes)
[Deployment fundamentals/CI]   ✅  Success - Main npm run build [258.640899ms]
[Deployment fundamentals/CI] ⭐ Run Main [simulated upload-artifact: dist]
[Deployment fundamentals/CI]   | -rw-r--r-- 1 root root 1466 Oct 26 12:42 .tmp/artifacts/dist.tar
[Deployment fundamentals/CI]   | SIMULATED upload of cicd-learn/dist as dist
[Deployment fundamentals/CI]   ✅  Success - Main [simulated upload-artifact: dist] [86.204479ms]
[Deployment fundamentals/CI] 🏁  Job succeeded
```

On github.com, the artifact travels between jobs and `deploy` downloads it.
In `act`, the cross-job download fails (the limitation noted in chapter
27), so even the free alternative below is useful for testing the script
without the artifact plumbing.

### The deploy half (documented, not verified locally)

On github.com, with a real server and key:

1. `ci` builds and uploads `dist/` as the `dist` artifact.
2. `deploy` downloads it and opens an SSH connection using `SSH_KEY`.
3. The host key is verified (or explicitly skipped, depending on config).
4. The `script:` block runs on the server: creates a release directory,
   copies the files in, repoints the `current` symlink, restarts the
   process.
5. The script exits 0; the action reports `======CMD======
   ...` and `✅ Successfully executed commands to all host.`
6. The deployment is recorded against the `production` environment with its
   URL.
7. If a second push lands mid-deploy, the second run waits on
   `deploy-production`.

### What a real run adds that `act` cannot show

- **The remote server.** `act` has no SSH target. The script never runs
  anywhere but the runner.
- **Key authentication.** `GITHUB_TOKEN`-style minting does not apply; the
  private key is a secret you create and rotate yourself.
- **Host key verification.** Whether the server's fingerprint is trusted is
  a property of the connection, not the YAML.
- **Network reachability.** The runner must be able to reach the server on
  port 22. Firewalls, security groups and VPNs are outside the workflow.
- **Process management on the server.** systemd, pm2, docker compose: how
  the app actually restarts is a property of the server, not the workflow.

## 5. When to use it and when NOT to

**Use SSH deploy when:**

- **You own a server.** A VPS, a dedicated box, or a VM you control, where
  you can install SSH and run a script.
- **Your app is not containerized.** A plain Node/Python/Ruby app on a
  server is deployed by copying files and restarting a process.
- **You need full control.** SSH gives you the shell; you can do anything
  the deploy user is allowed to do.
- **The target count is small.** One to a handful of servers is fine.

**Do NOT use SSH deploy when:**

- **You have many targets.** Ten SSH connections is ten chances to fail
  halfway and leave the fleet inconsistent. Use a registry pull or a
  config-management tool.
- **You can use a platform instead.** Heroku, Render, Fly.io, Cloud Run and
  friends handle deploy, scaling and rollback for you. SSH is the
  do-it-yourself option.
- **Your server has no SSH access from GitHub's runners.** Some corporate
  networks block outbound SSH from CI. Fix the network or pick a different
  deploy method.
- **You are deploying containers.** If the app is an image, push it
  (chapter 31) and have the server pull. SCP-ing image tarballs is slower
  and more fragile.
- **You have no rollback plan.** An SSH deploy that breaks production needs
  a way back: release directories and a symlink, or a previous image. Plan
  this before the first deploy (chapter 46).

## 6. Common mistakes

- **Committing the private key.** The single worst mistake. Symptom: a key
  in git history that anyone can read. Fix: revoke it immediately, generate
  a new pair, and store only the new private key as a secret. Rotate
  everything the old key touched.
- **Logging in as root.** Symptom: a leaked key gives full control of the
  server. Fix: create a `deploy` user with only the needed permissions.
- **Disabling host verification without thinking.** `strict_host_key_checking:
  no` removes a real protection. Symptom: a man-in-the-middle attack goes
  unnoticed. Fix: pin the host key in `known_hosts` or use the action's
  option to add it.
- **No `set -e`.** A failed command on the server does not fail the step.
  Symptom: a deploy reported as successful that left the app broken. Fix:
  `set -e` at the top of the script.
- **Copying files into the running directory directly.** If the copy fails
  halfway, production is half-updated. Symptom: a broken site. Fix:
  release directories plus a symlink swap.
- **No health check after restart.** Symptom: the deploy reports success but
  the app is crash-looping. Fix: curl the health endpoint at the end of
  the script and fail if it does not return 200.
- **Forgetting the artifact retention window.** If the deploy job runs hours
  later and the artifact expired, the deploy fails. Symptom: "artifact not
  found" on the deploy job. Fix: set `retention-days:` high enough.
- **Using repository secrets for production keys.** Any job can read them.
  Symptom: a PR check can read the production SSH key. Fix: environment
  secrets (chapter 24).
- **Assuming `act` tests the deploy.** It does not; the script never runs
  on a server. Symptom: "it worked locally" about a deploy that never
  happened. Fix: test the script against a local directory (section 7) and
  do a real dry run to a staging server.

## 7. Try it yourself

**Exercise: run the deploy script locally, with no server.**

Part A — the free alternative (no server, no key, no network):

1. Simulate CI producing the artifact, the way chapter 27 does:

   ```bash
   mkdir -p /tmp/deploy-target/releases /tmp/deploy-target/dist
   ./scripts/run-workflow.sh .github/workflows/27-deployment-fundamentals.yml ci 2>/dev/null || true
   ```

   If the artifact did not travel (the `act` limitation), just build it
   directly:

   ```bash
   cd cicd-learn && npm ci && npm run build && cd ..
   cp -r cicd-learn/dist/* /tmp/deploy-target/dist/
   ```

2. Run the exact script a real SSH deploy would run, but against the local
   directory:

   ```bash
   set -e
   APP_DIR=/tmp/deploy-target
   RELEASE_DIR=$APP_DIR/releases/$(date +%Y%m%d%H%M%S)
   mkdir -p "$RELEASE_DIR"
   cp -r /tmp/deploy-target/dist/* "$RELEASE_DIR"/
   ln -sfn "$RELEASE_DIR" "$APP_DIR/current"
   echo "deployed to $RELEASE_DIR"
   ls -l "$APP_DIR/current"
   cat "$APP_DIR/current/app.js" | head -3
   ```

3. Run it a second time. A second release directory is created, and
   `current` now points at it. The previous release is still on disk, so
   rollback is repointing `current`:

   ```bash
   ls "$APP_DIR"/releases/
   # rollback:
   PREVIOUS=$(ls -1 "$APP_DIR"/releases/ | sort | tail -2 | head -1)
   ln -sfn "$APP_DIR/releases/$PREVIOUS" "$APP_DIR/current"
   echo "rolled back to $PREVIOUS"
   ```

4. **Prove `set -e` matters.** Remove `set -e` and insert a failing
   command (`false`) in the middle. The script continues and prints
   "deployed" even though it failed. Restore `set -e`.

5. **Prove the symlink swap is atomic.** The `ln -sfn` replaces the
   symlink in one operation; readers either see the old target or the new
   one, never a half-copied directory. That is why you deploy to a release
   directory and swap a symlink, instead of copying into the live directory.

Part B — on GitHub, for real:

6. Provision a small server (a $5 VPS is enough) and create a `deploy`
   user with SSH key access.

7. Generate a key pair locally:

   ```bash
   ssh-keygen -t ed25519 -C "github-actions-deploy" -f deploy_key -N ""
   ```

   Put `deploy_key.pub` in the server's `~deploy/.ssh/authorized_keys`.
   Store `deploy_key` (the private key) as the `SSH_KEY` secret in the
   `production` environment.

8. Add the workflow from section 3. Push to `main`. Watch the deploy job
   open an SSH connection and run the script.

9. **Break it on purpose.** Store the public key as `SSH_KEY` instead of
   the private key. The connection fails with "Permission denied
   (publickey)." Fix by storing the private key.

10. **Break it on purpose, part two.** Point `SSH_HOST` at a host that does
    not exist. The connection times out. Fix the host.

11. **Clean up.** Revoke the deploy key on the server, delete the secrets,
    and remove the workflow if you are done.

**Hint:** the free alternative in part A tests the *script*, which is the
part that actually changes the server. The SSH plumbing (key, host, port)
is the part you cannot test locally, and it is the part that fails most
often on the first real run. Do a dry run to a staging server before you
need it in production.

## 8. Next

You now know how to ship code to a server you control. The next chapter
steps back from the mechanics and compares the strategies you can use once
you can deploy: rolling, blue-green, canary and recreate, and when each is
worth the complexity.

→ [33 — Deployment strategies](33-deployment-strategies.md)