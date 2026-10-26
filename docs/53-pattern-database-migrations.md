# 53 — Database migrations, safely [read-only example]

> **Verification.** This chapter is a **`[read-only example]`**: there is **no
> runnable workflow** and **no log** for it. Running migrations against a real
> database needs a real database server (Postgres, MySQL, …) and credentials
> this course does not have, so nothing here was executed. The CI half of the
> pattern is the same shape as chapter 15, whose log
> (`docs/_logs/ch15-ci-pipeline-order.log`) is the source of the real build
> output quoted below. `python3 scripts/validate-workflows.py` was run on the
> illustrative workflow in section 3 and reports it as valid YAML with 2 jobs.
>
> **What you can run today.** The free alternative is in section 7: a SQLite
> file in the workspace, migrated inside the runner with a small SQL script.
> It proves the expand/contract shape, the transaction, and the "run once"
> rule without any database server.

---

## 1. Simple explanation (like I'm 7)

You have a library with a card catalogue. The cards say "book title, author,
shelf number." One day you decide the catalogue should also say "year
published." You cannot just rewrite every card overnight, because people are
still using the old cards to find books. So you do it in two steps: first
you add a new column to every card (the old cards still work, they just
leave it blank), then later, once everyone is using the new format, you
remove the old column. Between those two steps, both old and new code keep
working.

A **database migration** is that change to the catalogue. The hard part is
that the database is being read and written while you change it, by code
that may be the old version or the new version, possibly both at once during
a rolling deploy. The migration must not break either.

## 2. Real name

### Migration

A versioned change to a database schema (or data), applied in order.
Usually a SQL file (`0001_add_year.sql`) plus a runner that records which
ones have been applied in a `schema_migrations` table.

### Expand/contract (parallel change)

The pattern of making a schema change in two (or more) deploys so that old
and new code can coexist:

1. **Expand**: add the new column/table, nullable or with a default. Old
   code ignores it; new code can write to it. Deploy.
2. **Migrate data** (optional): backfill the new column from the old one.
3. **Switch code**: new code reads from the new column. Deploy.
4. **Contract**: drop the old column. Deploy.

No step breaks a running version.

### Backward-compatible migration

A migration that the previous version of the code can survive. Adding a
nullable column is. Dropping a column is not (old code still references
it). Renaming is not (old code uses the old name).

### Destructive migration

A migration that removes or changes something in a way that cannot be
undone or that breaks old code: `DROP COLUMN`, `DROP TABLE`, changing a
column type, deleting rows. Requires the expand/contract dance or a
maintenance window.

### Idempotent migration

A migration that can be run twice without changing the result. `CREATE TABLE
IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`. Essential for
retry safety.

### Transactional migration

A migration wrapped in a transaction, so that if any statement fails, the
whole migration rolls back and the schema is unchanged. Not all databases
support DDL in transactions (MySQL does not for most statements); Postgres
does.

### Migration runner

The tool that applies migrations in order and records state. Examples:
`node-pg-migrate`, `Prisma Migrate`, `Flyway`, `Liquibase`, `Alembic`,
`golang-migrate`. They all share the same idea: a `schema_migrations`
table and an ordered list of files.

### "Run once per deploy"

The rule that migrations run exactly once, in a single job, before the new
code starts serving traffic. Not in parallel jobs, not in every replica, not
in the app's startup hook (unless that hook is a leader-elected singleton).

### Lock / advisory lock

A database-level lock that ensures only one migration runner runs at a
time, even if two deploys overlap. `pg_advisory_lock` is the Postgres
version. Prevents "migration applied twice" races.

### Distinctions people get wrong

- **Migration vs seed.** A migration changes schema (or migrates data).
  A seed loads initial data. They run at different times and have different
  rollback rules.
- **Applying vs generating.** Generating a migration (diffing the schema)
  is a dev-time task. Applying it is a deploy-time task. Do not generate
  migrations in CI.
- **Forward-only vs reversible.** A reversible migration has an `up` and a
  `down`. In practice, `down` migrations are rarely tested and often
  wrong. Prefer forward-only plus a new migration to undo.
- **One migration per PR vs one per release.** Either works; consistency
  matters more than choice. Pick one and document it.
- **Migration in CI vs migration at deploy.** Running migrations in CI
  against a throwaway database tests them. Running them against production
  is a deploy step. Do not confuse the two.

## 3. Workflow example

This workflow was **not executed**. It needs a real database and
credentials, which `act` cannot provide. It is shown so you can read the
shape; the CI half is identical to chapter 15.

```yaml
name: Database migrations

"on":
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  # ── CI: test the migrations against a throwaway database ─────────────────
  ci:
    name: CI
    runs-on: ubuntu-24.04
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
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
      - name: Apply migrations to the test database
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/postgres
        run: |
          # A migration runner, not a hand-rolled script, in real life.
          npx node-pg-migrate up
      - name: Verify the schema
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/postgres
        run: |
          # Run a smoke query against the migrated schema.
          psql "$DATABASE_URL" -c '\d users'

  # ── Deploy: apply migrations once, then deploy the app ───────────────────
  deploy:
    name: Migrate and deploy
    runs-on: ubuntu-24.04
    needs: [ci]
    environment:
      name: production
      url: https://example.com
    concurrency:
      group: migrate-production
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: cicd-learn/package-lock.json
      - run: npm ci
      - name: Apply migrations (once)
        env:
          DATABASE_URL: ${{ secrets.PRODUCTION_DATABASE_URL }}
        run: |
          # This job is the single owner of migrations for this deploy.
          # No other job, replica, or startup hook runs them.
          npx node-pg-migrate up
      - name: Deploy the app
        run: |
          echo "deploying after migrations"
```

Structural things to notice:

1. **Migrations run in CI against a throwaway database** (a `services:` Postgres
   container). That proves they apply cleanly before they ever touch
   production. Chapter 18/20.
2. **Migrations run once, in the deploy job**, before the app is deployed.
   Not in the app's startup hook, not in every replica, not in parallel.
3. **The deploy job has an environment and required reviewers.** A human
   approves the migration before it runs against production. Chapter 24/28.
4. **A concurrency group serialises migrations.** Two deploys cannot migrate
   at the same time. `cancel-in-progress: false` means the second waits.
   Chapter 21.
5. **The database URL is an environment secret.** Production credentials
   never appear in repository scope. Chapter 24.
6. **The migration runner records state** in a `schema_migrations` table, so
   re-running `up` is a no-op. That is the "run once" rule made
   mechanical.

## 4. What I should see

There is no real log for this workflow. What follows is split into two parts:
the CI half, which is real and quoted from chapter 15, and the migration
half, which is described from the documentation and is not verified locally.

### The CI half (real, from `docs/_logs/ch15-ci-pipeline-order.log`)

The build runs and reports its output, exactly as in chapter 15:

```
[CI pipeline order/...]   | > cicd-learn@1.0.0 build
[CI pipeline order/...]   | > node build.mjs
[CI pipeline order/...]   | 
[CI pipeline order/...]   | built dist/app.js (2887 bytes)
```

That is the part you can run today, with chapter 15's workflow.

### The migration half (documented, not verified locally)

On github.com, with the workflow above and a real database:

1. `ci` starts a Postgres service container, applies all migrations, and
   runs a smoke query. If a migration fails, `ci` is red and `deploy` never
   starts.
2. `deploy` waits for approval (if required reviewers are configured on
   `production`).
3. On approval, `deploy` applies migrations once against the production
   database. The runner records each applied migration in
   `schema_migrations`.
4. The app is deployed. The new code runs against the migrated schema.
5. Re-running the workflow applies nothing new: `up` is a no-op.

### What a real run adds that `act` cannot show

- **The database.** Postgres as a `services:` container works locally with
  `act` in principle, but `act` does not implement services the same way
  GitHub does, and the migration runner needs a real driver. Verify on
  GitHub.
- **The environment gate.** Required reviewers, wait timers, deployment
  branches. Chapter 24/28.
- **The concurrency lock.** Two deploys serialising. Chapter 21.
- **Environment-scoped secrets.** `PRODUCTION_DATABASE_URL` injected only
  into the deploy job. Chapter 24.
- **The migration runner's state.** `schema_migrations` persists across
  runs; `act` has no persistent database.

## 5. When to use it and when NOT to

**Use database migrations in CI/CD when:**

- **Your app has a database.** Which is most apps. Schema changes are the
  hardest part of deploying.
- **You want deploys to be reproducible.** A migration file in git plus a
  runner means every environment gets the same schema.
- **You want CI to catch broken migrations.** Applying them to a throwaway
  database in CI turns a production failure into a red build.
- **You deploy frequently.** Small, frequent migrations are safer than rare,
  large ones.

**Do NOT automate migrations when:**

- **The migration is destructive and there is no expand/contract plan.**
  Dropping a column that old code still references breaks production. Plan
  the dance first.
- **You have no backup.** A migration that corrupts data with no rollback is
  a disaster. Back up before you migrate; test the restore.
- **You run migrations in the app's startup hook without a lock.** Every
  replica races to migrate; one loses and crashes. Use a singleton or a
  lock.
- **You generate migrations in CI.** Generation is a dev-time task; CI
  applies. Mixing them produces migrations nobody reviewed.
- **You skip CI testing of migrations.** A migration that works on your
  laptop's empty database may fail on production's billion rows. Test
  against realistic data.

## 6. Common mistakes

- **Running migrations twice.** Symptom: "relation already exists" or
  duplicate data. Fix: a migration runner with a `schema_migrations` table,
  and idempotent SQL (`IF NOT EXISTS`).
- **Destructive migrations without expand/contract.** Symptom: old code
  crashes after deploy because a column it references is gone. Fix: add, then
  switch code, then drop, across separate deploys.
- **Migrations not in a transaction.** Symptom: a migration fails halfway and
  leaves the schema half-changed. Fix: wrap in `BEGIN`/`COMMIT`; use a
  database that supports DDL in transactions (Postgres).
- **Running migrations in parallel jobs.** Symptom: two jobs try to
  `CREATE TABLE` at once; one fails. Fix: one migration owner per deploy,
  serialised by a concurrency group.
- **Running migrations in every replica.** Symptom: races, deadlocks,
  crashes. Fix: a single migration job, or a leader-elected singleton with
  an advisory lock.
- **No backup before migrating.** Symptom: a bad migration destroys data and
  there is no way back. Fix: snapshot the database before every production
  migration; test restores.
- **Assuming `act` will show the gate.** It will not; the job runs
  immediately. Symptom: "I tested it locally and there was no approval step."
  Fix: verify on GitHub.
- **Hardcoding the database URL.** Symptom: the production password is in the
  workflow file. Fix: use an environment secret. Chapter 24.
- **Migrating without a smoke query.** Symptom: the migration applies but the
  schema is wrong, and you find out in production. Fix: a `SELECT` or `\d`
  check in CI after applying.
- **Mixing data migrations with schema migrations.** Symptom: a data fix-up
  that takes an hour blocks the deploy. Fix: separate them; run data
  migrations as background jobs.

## 7. Try it yourself

**Exercise: migrate a SQLite file, locally.**

This is the free alternative. It proves the expand/contract shape, the
transaction, and the "run once" rule using a file on disk.

1. Create a working directory and a database:

   ```bash
   mkdir -p /tmp/opencode/migrate && cd /tmp/opencode/migrate
   sqlite3 app.db "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL);"
   sqlite3 app.db "INSERT INTO users (name) VALUES ('Ada'), ('Bob');"
   sqlite3 app.db "SELECT * FROM users;"
   ```

2. **Expand.** Add a nullable `email` column in a transaction:

   ```bash
   sqlite3 app.db <<'SQL'
   BEGIN;
   ALTER TABLE users ADD COLUMN email TEXT;
   CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY);
   INSERT INTO schema_migrations (version) VALUES ('0001_add_email');
   COMMIT;
   SQL
   ```

3. **Prove it is idempotent.** Re-run the same block; the `ALTER TABLE`
   fails because the column exists. That is why you use `IF NOT EXISTS` or
   a runner. With SQLite, guard it:

   ```bash
   sqlite3 app.db "SELECT name FROM pragma_table_info('users') WHERE name='email';"
   ```

   The column is there; the migration is recorded.

4. **Migrate data.** Backfill the new column:

   ```bash
   sqlite3 app.db "UPDATE users SET email = lower(name) || '@example.com' WHERE email IS NULL;"
   sqlite3 app.db "SELECT * FROM users;"
   ```

5. **Prove "run once".** Re-run the update; nothing changes because the
   `WHERE email IS NULL` clause is false for all rows. That is idempotency
   by construction.

6. **Contract (later).** Dropping the old column is the destructive step.
   In SQLite you recreate the table; in Postgres it is `ALTER TABLE users
   DROP COLUMN name;`. Do this only after all code reads `email`.

7. **Prove the transaction rollback.** Run a migration that fails halfway:

   ```bash
   sqlite3 app.db <<'SQL'
   BEGIN;
   ALTER TABLE users ADD COLUMN broken TEXT;
   INSERT INTO users (name) VALUES (NULL);  -- violates NOT NULL
   COMMIT;
   SQL
   echo "exit: $?"
   sqlite3 app.db "SELECT name FROM pragma_table_info('users') WHERE name='broken';"
   ```

   The column `broken` should not exist: the transaction rolled back.
   (SQLite's DDL transaction support makes this work; MySQL's does not.)

8. **Break it on purpose.** Run two migrations at once in two terminals
   against the same file. SQLite locks the file; one waits or fails with
   "database is locked." That is the concurrency race, made visible. Revert
   by running them one at a time.

9. **Clean up.**

   ```bash
   rm -rf /tmp/opencode/migrate
   ```

**Hint:** the free alternative uses SQLite, which supports DDL in
transactions. If your real database is MySQL, `ALTER TABLE` is not
transactional, so a failed migration leaves the schema half-changed. That is
a database limitation, not a pipeline bug, and it is why Postgres is the
default for migration-heavy systems.

## 8. Next

You can now change a schema without losing data. The next pattern puts two
environments in front of the same pipeline: staging that deploys
automatically, and production that waits for a human.

→ [54 — Separate staging and production environments](54-pattern-staging-and-production.md)
EOF
echo written