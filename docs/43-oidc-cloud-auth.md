# 43 — OIDC and cloud authentication [read-only example]

> **Verification.** This chapter is a **`[read-only example]`**: it was **not**
> executed, because OIDC cloud authentication needs a real cloud account
> (AWS, GCP or Azure) and a trust policy you control. There is no log for it.
> `python3 scripts/validate-workflows.py` was run on the illustrative workflow
> in section 3 and reports it as valid YAML with 2 jobs. The free alternative
> you can run today is at the end of section 7: request the token, decode it,
> and verify its claims, without ever exchanging it for cloud credentials.

---

## 1. Simple explanation (like I'm 7)

Normally, to let your CI robot into a cloud account, you give it a password
and store the password in GitHub's secrets. The problem is that the password
sits there forever, and if it leaks, an attacker has access until you notice
and rotate it. That is like giving a spare house key to a delivery driver and
hoping they never lose it.

**OIDC** is the no-key version. Instead of a password, your CI robot carries
a signed letter from GitHub saying "I am workflow X in repository Y, running
on commit Z". The cloud provider checks the signature, checks that it trusts
GitHub, and checks that the letter names the right repository and workflow.
If everything matches, the cloud provider hands over a short-lived key that
expires in an hour. No password is ever stored, and a leaked key is useless
within minutes.

This chapter is marked `[read-only example]` because it needs a real cloud
account. But the mechanism is just a signed JWT, and you can request one and
read it without any cloud account at all. That is the free alternative in
section 7.

## 2. Real name

### OIDC (OpenID Connect)

An identity protocol built on OAuth 2.0. It lets one system (here, GitHub
Actions) issue a signed identity token (a JWT) that another system (a cloud
provider) can verify without a shared secret. RFCs 6749 and 7519, plus the
Discovery and JWKS endpoints.

### ID token

The JWT GitHub mints for a run. It contains claims about who is running:
repository, workflow, job, ref, commit SHA, actor, and an audience. It is
signed by GitHub's private key and verifiable against GitHub's public JWKS at
`https://token.actions.githubusercontent.com/.well-known/jwks`.

### `id-token: write`

The permission a job needs in order to request an ID token. Without it, the
token endpoint returns 403. This is the only permission you add; everything
else stays least-privilege.

```yaml
permissions:
  id-token: write
  contents: read
```

### Audience

The `aud` claim in the JWT, stating which service the token is for. Cloud
providers require a specific audience (`sts.amazonaws.com` for AWS,
`https://iam.googleapis.com/...` for GCP, or a custom value for Azure). A
token minted for one audience cannot be used against another.

### Trust policy / federation

The configuration on the cloud side that says "I trust GitHub's OIDC issuer,
and only for tokens whose claims match these conditions." The conditions are
usually `repository == owner/repo` and sometimes `ref == refs/heads/main` or
`environment == production`. This is where the security lives: GitHub signs
the token, but the cloud provider decides which tokens it honours.

### Short-lived credentials

What the cloud provider hands back after verifying the token: an access key
and secret (or a session token) valid for a limited time, typically one hour.
There is no long-lived key to leak, rotate, or revoke.

### The three cloud providers

| Provider | Action | What it does |
| -------- | ------ | ------------ |
| AWS | `aws-actions/configure-aws-credentials` | Calls STS `AssumeRoleWithWebIdentity` |
| GCP | `google-github-actions/auth` | Exchanges the JWT for a short-lived access token |
| Azure | `azure/login` | Federated credential on an app registration |

The mechanism is identical; only the action and the trust policy differ.

## 3. Workflow example

This workflow is valid YAML but was not executed. It requests an OIDC token
and would exchange it for AWS credentials, then list an S3 bucket.

```yaml
name: OIDC cloud auth demo (read-only)

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── Request the token and exchange it ─────────────────────────────────────
  # `id-token: write` is the only new permission. Everything else stays
  # least-privilege.
  auth:
    name: Authenticate to AWS via OIDC
    runs-on: ubuntu-24.04
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: eu-west-1
          # The action requests the ID token from GitHub, verifies nothing
          # itself, and calls STS AssumeRoleWithWebIdentity under the hood.

      - name: Prove we are authenticated
        run: |
          aws sts get-caller-identity
          aws s3 ls s3://my-deploy-bucket

  # ── A second job that reuses the same trust policy ───────────────────────
  deploy:
    name: Deploy using the OIDC session
    runs-on: ubuntu-24.04
    needs: [auth]
    permissions:
      id-token: write
      contents: read
    environment: production
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: eu-west-1
      - name: Deploy
        run: echo "deploy step would run here"
```

Three lines carry all the weight:

- `permissions: id-token: write` on the job. Without it, GitHub refuses to
  mint the token.
- `role-to-assume: arn:...`. The ARN names the IAM role whose trust policy
  accepts GitHub's OIDC issuer for this repository.
- `aws-region`. The STS endpoint is regional.

Everything else is ordinary CI.

## 4. What I should see

There is no real log for this chapter. On a real run you would see:

- The `Configure AWS credentials` step printing `Assuming role with OIDC`.
- `aws sts get-caller-identity` printing an ARN like
  `arn:aws:sts::123456789012:assumed-role/github-actions-deploy/GitHubActions`,
  proving the session belongs to the role, not to a human.
- No secret anywhere in the workflow file or the logs. The only inputs are
  the role ARN and the region, both of which are not secrets.
- The session expiring after about an hour, after which any command using it
  fails with `ExpiredToken`. That is the feature, not a bug.

The free alternative in section 7 shows you the token itself and its claims,
which is the part of this flow you can actually observe without a cloud
account.

## 5. When to use it and when NOT to

**Reach for OIDC when:**

- Your workflow needs to touch a cloud provider at all. There is essentially
  no reason to store a long-lived cloud key in GitHub secrets anymore.
- You deploy to production and want the deploy to be tied to a specific
  branch, environment, or commit. The trust policy can require
  `ref == refs/heads/main` or `environment == production`, so a token minted
  from a feature branch cannot be used to deploy.
- You want auditability. Cloud audit logs record which repository and commit
  assumed the role, because the session name is derived from the JWT claims.
- Compliance forbids long-lived credentials. OIDC is the standard answer.

**Do NOT reach for it when:**

- You are only pushing to GitHub Packages or GitHub Pages. The built-in
  `GITHUB_TOKEN` already covers those; OIDC is for external clouds.
- You cannot control the trust policy on the cloud side. OIDC requires
  configuration in both places; GitHub alone is not enough.
- Your cloud provider does not support OIDC federation. Most major ones do,
  but check before committing.
- You need access from outside GitHub Actions. OIDC tokens are minted per run;
  there is no reusable credential. For local development, use a personal
  profile or a separate service account.

## 6. Common mistakes

- **Forgetting `id-token: write`.** Symptom: `Error: Could not get ID token.
  The action is not trusted by the OIDC provider` or a 403 from the token
  endpoint. Fix: add `id-token: write` to the job's `permissions:`.
- **A trust policy that is too loose.** `repository: owner/*` or no
  condition on `ref` means any branch in any fork-shaped repo can assume the
  role. Fix: pin the policy to the exact repository, and to `ref` or
  `environment` where possible.
- **A trust policy that is too tight.** Requiring `ref == refs/heads/main`
  means pull-request runs cannot authenticate, which breaks preview deploys.
  Fix: use a separate role for PRs with read-only permissions, or authenticate
  only in the deploy job that runs on `main`.
- **Requesting the token but never restricting the audience.** The default
  audience is the cloud provider's, but a custom audience must match the trust
  policy exactly. A mismatch gives `InvalidIdentityToken`.
- **Storing the role ARN as a secret.** It is not a secret; it is a
  resource name. Store it as a variable (`vars.AWS_ROLE_ARN`) or hardcode it.
  Storing it as a secret makes the workflow harder to audit and rotate.
- **Assuming the session is permanent.** It expires. A long-running job that
  starts at minute 0 and tries to use the credentials at minute 90 will fail.
  Re-authenticate inside the step that needs it, or extend the session
  duration in the trust policy.
- **Confusing `GITHUB_TOKEN` with OIDC.** `GITHUB_TOKEN` talks to GitHub.
  OIDC talks to external clouds. They are separate mechanisms and separate
  permissions.

### GCP and Azure, in one line each

- **GCP**: create a Workload Identity Pool and Provider trusting
  `https://token.actions.githubusercontent.com`, then grant a service account
  to the pool with an attribute condition on `repository`. Use
  `google-github-actions/auth` with `workload_identity_provider` and
  `service_account`.
- **Azure**: create an app registration, add a federated credential with
  issuer `https://token.actions.githubusercontent.com` and subject
  `repo:org/repo:ref:refs/heads/main`, then use `azure/login` with
  `client-id`, `tenant-id`, and `subscription-id`. No client secret.

The claims in the JWT are the same in all three cases; only the trust-policy
syntax and the action differ.

### What a trust policy looks like (AWS example)

For reference, not execution. An IAM role's trust policy that accepts GitHub's
OIDC provider only for this repository on `main`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:your-org/your-repo:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

The `sub` (subject) claim is the one that pins the policy to a repository and
branch. Change `ref:refs/heads/main` to `environment:production` to gate on an
environment instead, which is the stronger option for deploys.

## 7. Try it yourself

**Exercise: read a real OIDC token without a cloud account.**

This is the free alternative. It mints a real token from GitHub and prints
its claims, so you can see exactly what the cloud provider would verify. It
never exchanges the token for anything.

1. Create `.github/workflows/oidc-probe.yml`:

   ```yaml
   name: OIDC probe
   "on": [workflow_dispatch]
   permissions:
     id-token: write
     contents: read
   jobs:
     probe:
       runs-on: ubuntu-24.04
       steps:
         - name: Request the ID token
           id: token
           run: |
             # The token endpoint is provided to every run.
             curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
               "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" \
               -o token.json
             echo "token saved; decoding claims next"

         - name: Decode and print the claims
           run: |
             python3 - <<'PY'
             import json, base64
             t = json.load(open('token.json'))['value']
             header, payload, sig = t.split('.')
             def dec(s):
                 s += '=' * (-len(s) % 4)
                 return json.loads(base64.urlsafe_b64decode(s))
             print(json.dumps(dec(payload), indent=2))
             PY
   ```

2. Run it on GitHub (this one needs the real Actions environment; `act`
   cannot mint a real token). Read the output. You will see claims like:

   ```json
   {
     "iss": "https://token.actions.githubusercontent.com",
     "aud": "sts.amazonaws.com",
     "repository": "your-org/your-repo",
     "repository_owner": "your-org",
     "workflow": "OIDC probe",
     "ref": "refs/heads/main",
     "sha": "abc123...",
     "actor": "your-username"
   }
   ```

3. Verify the signature locally if you want: fetch GitHub's JWKS from
   `https://token.actions.githubusercontent.com/.well-known/jwks` and check
   the token's `kid` against it. That is exactly what the cloud provider does.

**Break it on purpose:** remove `id-token: write` and re-run. The curl returns
403 and `token.json` contains an error. That is the permission boundary in
one line.

## 8. Next

You can log in to a cloud with no password. Chapter 44 is about a different
scaling problem: one repository with many packages.

→ [44 — Monorepo pipelines](44-monorepo-pipelines.md)