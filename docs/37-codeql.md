# 37 — Security scanning: CodeQL

> **Verification.** The workflow in this chapter is
> `.github/workflows/37-codeql.yml`. `python3 scripts/validate-workflows.py`
> reports `ok .github/workflows/37-codeql.yml (1 job(s))`. A local run was
> attempted with
> `./scripts/verify.sh .github/workflows/37-codeql.yml analyze push ch37`;
> the full (partial) attempt is at `docs/_logs/ch37.log`. The attempt reached
> the container setup and began fetching `github/codeql-action@v4`; it did not
> complete, because the CodeQL action downloads the CodeQL CLI bundle (roughly
> a gigabyte) and the run was terminated. **[read-only example]**: CodeQL
> analysis requires GitHub Advanced Security, which is free for public
> repositories and paid for private ones. The shape of the workflow, its
> permissions, and its steps are taken from the official `github/codeql-action`
> documentation and from the file in this repository.
>
> **What this local execution cannot prove.** `act` can start the workflow but
> cannot complete a CodeQL analysis: the action downloads the CodeQL CLI and
> a language pack, builds a database of the repository, runs the queries, and
> uploads results to the Security tab via `security-events: write`. None of
> that is reproducible locally in a reasonable time, and the results land in a
> GitHub-only surface (the Security tab). The free alternative is to push the
> workflow to a public repository and watch the `analyze` job run to
> completion; public repositories get GitHub Advanced Security for free.

---

## 1. Simple explanation (like I'm 7)

Imagine a detective who reads your entire codebase, not to run it, but to
look for patterns that humans miss: "this function takes user input and
passes it straight to a database query," or "this password is compared with
`==` instead of a constant-time function." The detective does not need the
code to run; he reads it like a book and flags the suspicious sentences.

CodeQL is that detective. It turns your code into a database, then runs
queries over that database looking for vulnerability patterns. The results
appear in your repository's Security tab as alerts, each pointing at a file
and line, with a severity and a suggested fix. It is a static analysis tool:
it analyses the source without executing it.

## 2. Real name

### SAST (Static Application Security Testing)

Analysing source code for vulnerabilities without running it. CodeQL is a
SAST tool. It complements, rather than replaces, tests and dependency
scanning.

### CodeQL

GitHub's semantic code analysis engine. It supports JavaScript/TypeScript,
Python, Java, C/C++, C#, Go, Ruby, and Swift. It parses the code into a
relational database and runs queries (written in the CodeQL language) over
it.

### CodeQL database

The intermediate representation CodeQL builds from your source. Queries run
against the database, not the source. Building it is the slow step; querying
is fast.

### Query suite

A named set of queries. The default suite covers common vulnerabilities
(SQL injection, XSS, path traversal, etc.). `security-extended` adds more
rules at the cost of runtime. `security-and-quality` adds code-quality
queries on top.

### Security tab

The repository surface where CodeQL results (and Dependabot alerts, secret
scanning alerts) appear. Results are uploaded as SARIF and are not part of
the Actions log.

### SARIF (Static Analysis Results Interchange Format)

The JSON format CodeQL uses to report findings. GitHub ingests SARIF and
turns it into alerts. You can also upload SARIF from other tools with
`github/codeql-action/upload-sarif`.

### `security-events: write`

The permission CodeQL needs to upload results to the Security tab. Without
it, the `analyze` step fails with "Resource not accessible by integration."
This is the permission most people forget.

### GHAS (GitHub Advanced Security)

The paid feature set that includes CodeQL on private repositories. Free for
public repositories. Secret scanning and dependency review have their own
availability rules.

## 3. Workflow example

This is the complete `.github/workflows/37-codeql.yml` from this
repository.

```yaml
name: CodeQL

"on":
  push:
    branches: [main]
  pull_request:
    branches: [main]
  # A weekly scheduled scan catches vulnerabilities in code that has not
  # changed recently, and in newly published queries.
  schedule:
    - cron: '17 3 * * 1'

permissions:
  # contents: read is needed to check out the code.
  contents: read
  # security-events: write is what lets CodeQL upload results to the
  # Security tab. This is the permission the whole workflow exists to use.
  security-events: write

jobs:
  analyze:
    name: Analyse with CodeQL
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7

      # Initialize CodeQL. `languages` is the list of languages to analyse.
      # Auto-detect only works when there is one language; for a pure JS repo,
      # naming it explicitly removes a class of surprising failures.
      - uses: github/codeql-action/init@v4
        with:
          languages: javascript-typescript
          # queries: security-extended   # more rules, slower; good for a security review

      # CodeQL builds a database of your code; the database is what gets queried.
      - uses: github/codeql-action/autobuild@v4

      # Run the queries and upload the results. The results appear under the
      # repository's Security tab, not in the Actions log.
      - uses: github/codeql-action/analyze@v4
        with:
          category: "/language:javascript-typescript"
```

Four structural things to notice:

1. `security-events: write` is declared at workflow level, because the
   `analyze` step needs it. `contents: read` is also needed for checkout.
   There is no job that needs less, so workflow level is fine here; in a
   larger file you would narrow it to the `analyze` job.
2. `languages: javascript-typescript` is named explicitly. Auto-detection
   works for single-language repos, but naming it removes a failure mode
   where CodeQL guesses wrong and analyses nothing.
3. `autobuild` is the step most likely to need replacing. For a Node
   project with a standard `npm ci` + `npm run build`, autobuild works. For
   anything exotic (custom build scripts, monorepo task runners), replace it
   with explicit `run:` steps that build the code before `analyze`.
4. `category` groups results by language, so a multi-language matrix does
   not overwrite its own findings.

## 4. What I should see

### The run we actually attempted

`docs/_logs/ch37.log` shows the workflow reaching the container and
starting to fetch the action:

```
[CodeQL/Analyse with CodeQL] ⭐ Run Set up job
[CodeQL/Analyse with CodeQL] 🚀  Start image=cicd-act-runner:24
[CodeQL/Analyse with CodeQL]   🐳  docker pull image=cicd-act-runner:24 platform= username= forcePull=false
[CodeQL/Analyse with CodeQL]   🐳  docker create image=cicd-act-runner:24 platform= entrypoint=["tail" "-f" "/dev/null"] cmd=[] network="host"
[CodeQL/Analyse with CodeQL]   🐳  docker run image=cicd-act-runner:24 platform= entrypoint=["tail" "-f" "/dev/null"] cmd=[] network="host"
[CodeQL/Analyse with CodeQL]   🐳  docker exec cmd=[node --no-warnings -e console.log(process.execPath)] user= workdir=
[CodeQL/Analyse with CodeQL]   ✅  Success - Main actions/checkout@v7 [106.629978ms]
[CodeQL/Analyse with CodeQL]   ☁  git clone 'https://github.com/github/codeql-action' # ref=v4
```

That is as far as local execution goes. The next thing that would happen on
GitHub is the `init` step downloading the CodeQL CLI bundle.

### What a real GitHub run looks like

On a public repository, the `analyze` job runs to completion:

```
CodeQL / Analyse with CodeQL
  ✅ Analyse with CodeQL
    ✅ Check out the repository
    ✅ Initialize CodeQL
       Installing CodeQL CLI...
       Installed CodeQL CLI 2.x.x
    ✅ Autobuild
       Running autobuild for javascript-typescript...
    ✅ Perform CodeQL Analysis
       Found 0 alerts
```

The results do not appear in the Actions log beyond "Found N alerts". They
appear in the repository's Security tab → Code scanning, as a list of alerts
with file, line, severity, and a link to the query that flagged them.

If a real vulnerability exists, the alert looks like:

```
High severity
  js/sql-injection
  src/db.js:42
  This query may be vulnerable to SQL injection...
  [Show more] [Dismiss] [Create issue]
```

### What a real GitHub run adds (not verified locally)

- The CodeQL CLI download and the database build, which together take
  several minutes.
- The actual query results, which depend on the code and on the query suite.
- The Security tab surface, which is where alerts are triaged, dismissed,
  and turned into issues.
- The `schedule` trigger, which runs the scan weekly even when no code
  changed.
- Push protection for code scanning (blocking a push that introduces a new
  alert), which is a separate, newer feature.

## 5. When to use it and when NOT to

**Use CodeQL when:**

- **You ship code that handles untrusted input.** Web apps, APIs, CLIs that
  parse user data. The injection-class bugs CodeQL finds are exactly the
  ones that become incidents.
- **You want a security review that does not depend on a human.** CodeQL
  runs on every PR and on a schedule, so a new vulnerability is caught
  before merge, not after a breach.
- **You maintain an open-source project.** Public repos get GHAS for free,
  and code scanning is one of the strongest signals a project can send to
  downstream users.
- **You want to enforce "no new alerts" on PRs.** Code scanning can be
  configured to fail a check when a PR introduces an alert, turning it into
  a gate (chapter 34).

**Do NOT:**

- **Do not enable CodeQL on a private repo without budgeting.** GHAS is
  paid for private repositories. Check the cost before turning it on for a
  large org.
- **Do not expect it to find logic bugs.** CodeQL finds known vulnerability
  patterns, not "this business rule is wrong." It will not catch an
  off-by-one in a pricing calculation.
- **Do not ignore the alert triage.** An alert list nobody triages becomes
  noise, and the team disables the tool. Triage weekly; dismiss false
  positives with a documented reason.
- **Do not run it on every push to a feature branch if it is slow.** The
  database build is expensive. Run on PRs and on a weekly schedule, not on
  every commit.
- **Do not assume `autobuild` works for your project.** If the build step
  produces no database, the analysis is empty and reports zero alerts, which
  looks like success but is not. Verify the database was built.

## 6. Common mistakes

- **Missing `security-events: write`.** Symptom: the `analyze` step fails
  with "Resource not accessible by integration." Fix: add
  `security-events: write` to the job or workflow permissions.
- **`autobuild` silently producing an empty database.** Symptom: "Found 0
  alerts" on a codebase that definitely has issues. Fix: replace
  `autobuild` with explicit build steps, or check the build logs.
- **Wrong `languages` value.** Symptom: CodeQL analyses nothing or the
  wrong language. Fix: use the exact identifiers (`javascript-typescript`,
  `python`, `java-kotlin`, `cpp`, `csharp`, `go`, `ruby`, `swift`).
- **No `schedule` trigger.** Symptom: vulnerabilities discovered in
  unchanged code are not caught, because no run fires. Fix: add a weekly
  cron.
- **Dismissing alerts without a reason.** Symptom: the same false positive
  reappears and gets dismissed again, forever. Fix: use the documented
  dismissal reasons (false positive, used in tests, won't fix) so the
  decision is recorded.
- **Running CodeQL on a fork PR without thinking.** Symptom: analysis runs
  on untrusted code with your token's permissions. Fix: CodeQL on
  `pull_request` from forks runs without secrets by default, but check the
  trigger and permissions; use `pull_request` not `pull_request_target`.
- **Confusing code scanning with secret scanning.** Symptom: expecting
  CodeQL to find a leaked AWS key. Fix: CodeQL finds code vulnerabilities;
  secret scanning (chapter 38) finds credentials. Both are needed.
- **Expecting results in the Actions log.** Symptom: "where are my alerts?"
  Fix: they are in the Security tab, not the log. The log only says how
  many were found.

### Query suites and what they cost

| Suite | What it adds | Runtime |
| ----- | ------------ | ------- |
| `default` | High-confidence security queries | Baseline |
| `security-extended` | More security queries, including lower-confidence ones | ~2-3x |
| `security-and-quality` | Security plus code-quality queries | ~3-5x |

Start with the default. Move to `security-extended` for a security review or
before a release. `security-and-quality` is for teams that want CodeQL to
double as a linter, which is usually overkill given ESLint.

### Triage workflow

A CodeQL alert that nobody triages is worse than no alert at all, because
it trains the team to ignore the Security tab. A workable triage loop:

1. **Weekly**: review new alerts. For each, decide real / false positive /
   won't fix.
2. **Real**: create an issue, link the alert, fix in a PR. The alert
   closes automatically when the vulnerable code is removed.
3. **False positive**: dismiss with reason "false positive" and a comment
   explaining why. Future runs suppress the same query on that location.
4. **Won't fix**: dismiss with reason "won't fix" and a justification.
   These still appear in reports, which is the point: the decision is
   recorded.
5. **Quarterly**: review dismissed alerts. Code changes; a dismissed alert
   may become live again.

### Uploading SARIF from other tools

CodeQL is not the only tool that can populate the Security tab. Any tool
that emits SARIF can upload its results:

```yaml
- uses: github/codeql-action/upload-sarif@v4
  with:
    sarif_file: results.sarif
    category: "eslint-security"
```

This is how you unify findings from Semgrep, Trivy, or a custom scanner
into one place. The `category` keeps them distinct so one tool does not
overwrite another's results.

### CodeQL on pull requests

By default, CodeQL on a pull request analyses only the changed files and
reports new alerts introduced by the PR. This keeps PR checks fast and makes
the alert actionable: "this PR introduced a SQL injection." The full
repository scan still runs on `push` to `main` and on the weekly schedule.

## 7. Try it yourself

**Exercise: add CodeQL and read your first alert.**

1. Add `.github/workflows/37-codeql.yml` from section 3 to a **public**
   repository (so GHAS is free).
2. Push to `main`. Watch the `analyze` job run to completion (several
   minutes).
3. Open Security → Code scanning. Read any alerts. For each one, decide:
   real vulnerability, false positive, or "won't fix", and dismiss with
   the matching reason.
4. **Introduce a vulnerability on purpose.** Add a function that builds a
   SQL query by string concatenation with user input:

   ```js
   function findUser(name) {
     return db.query("SELECT * FROM users WHERE name = '" + name + "'");
   }
   ```

   Open a pull request. CodeQL flags it as SQL injection. Fix it with a
   parameterised query, push again, and watch the alert disappear from the
   PR's checks. Revert when done.
5. **Break the permissions.** Remove `security-events: write` and push.
   The `analyze` step fails with "Resource not accessible by integration."
   Restore the permission.
6. **Break the build.** Replace `autobuild` with a step that does nothing
   (`run: echo skip`). The analysis reports "Found 0 alerts" and looks
   green. That is a false negative. Restore `autobuild`.
7. **Enable the schedule.** Confirm the cron line is present and that a
   weekly run appears in the Actions tab after seven days (or trigger it
   manually with `workflow_dispatch` if you add that trigger).

**Hint:** CodeQL is the only chapter in this course that needs a public
repository to be free. If your repository is private, the workflow still
runs, but the upload step fails without a GHAS licence.

## 8. Next

You now have a detective reading your code. The next chapter adds a second
detective that reads your commits, looking for secrets that should never
have been written down.

→ [38 — Secret scanning and push protection](38-secret-scanning.md)