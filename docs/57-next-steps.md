# 57 — Where to go next

> **Verification.** This is a **wrap-up chapter**: there is **no workflow** and
> **no log**. The checklist in section 3 is derived from the chapters of this
> course (01–56) and from the verified versions table in `docs/00-roadmap.md`.
> No command was executed. The only file touched is this chapter.

---

## 1. Simple explanation (like I'm 7)

You have spent a long time learning how the kitchen works: how to order
ingredients, how to cook, how to plate, how to serve, how to clean up, and
how to handle a rush. Now you are standing in your own kitchen for the first
time, with your own ingredients and your own customers, and the question is
no longer "how does a kitchen work?" but "what do I cook first, and in what
order?"

This chapter is the order. It is a checklist you can walk through, in
sequence, for a real repository, so that you build the pipeline in the right
order and do not, for example, set up Slack notifications before you have a
pipeline worth notifying about.

## 2. Real name

### Applying this course to a real repository

The process of taking the concepts, workflows and habits from this course
and installing them, one at a time, into a repository that ships real
software. The order matters: each layer assumes the previous one works.

### The layers (in order)

1. **Foundation**: the repo, the app, the tests.
2. **CI**: lint, test, build, on every push and PR.
3. **Speed**: caching, so CI stays fast as the repo grows.
4. **Structure**: jobs, artifacts, conditionals, concurrency.
5. **Safety**: secrets, permissions, environments, approvals.
6. **Delivery**: staging, production, containers, releases.
7. **Quality**: coverage, branch protection, dependency updates, scanning.
8. **Operations**: debugging, re-runs, cost, notifications.
9. **Advanced**: reusable workflows, monorepo, rollbacks.
10. **Habits**: commit messages, pinning, the checklist itself.

### The checklist

A concrete, ordered list of things to do. Each item links to the chapter
that explains it. Tick them off as you go.

## 3. Workflow example

There is no workflow in this chapter. Instead, here is the checklist as a
single block you can copy into a new repository's `TODO.md` and tick off.

```markdown
# CI/CD checklist for a real repository

## 0. Before you start
- [ ] The app builds locally with one command (`npm run build` or equivalent).
- [ ] Tests exist and pass locally (`npm test`).
- [ ] A lock file is committed (`package-lock.json`, `yarn.lock`, ...).
- [ ] The repo is on GitHub (or your chosen platform).

## 1. First pipeline (chapters 04–15)
- [ ] Create `.github/workflows/ci.yml`.
- [ ] Trigger on `push` and `pull_request` to `main`.
- [ ] Set `permissions: contents: read` at the top.
- [ ] Pin the runner to `ubuntu-24.04` (never `ubuntu-latest`).
- [ ] Checkout, setup Node with `node-version: '22'`, `npm ci`, lint, test, build.
- [ ] Quote the `on:` key.
- [ ] Set `timeout-minutes:` on every job.
- [ ] Confirm it is green on a push to `main`.

## 2. Speed (chapters 16–17)
- [ ] Enable `cache: 'npm'` in `setup-node`.
- [ ] Confirm the second run is faster than the first (read the log).
- [ ] If you test multiple Node versions, use a matrix with `fail-fast: false`.

## 3. Structure (chapters 18–21)
- [ ] Split lint and test into separate jobs only if they are independent.
- [ ] Use `needs:` where one job genuinely needs another.
- [ ] Upload build output as an artifact if a later job or a human needs it.
- [ ] Add `concurrency:` with `cancel-in-progress: true` on CI.
- [ ] Add `concurrency:` with `cancel-in-progress: false` on deploys.

## 4. Secrets and config (chapters 22–26)
- [ ] Move any secret out of the code and into GitHub Secrets.
- [ ] Set `permissions:` per job, least privilege.
- [ ] Create environments (`staging`, `production`) in Settings.
- [ ] Move deploy credentials to environment secrets.
- [ ] Add required reviewers to `production`.
- [ ] Turn on secret scanning and push protection.

## 5. Delivery (chapters 27–33)
- [ ] Deploy staging automatically on push to `main`.
- [ ] Gate production on approval.
- [ ] If you ship a container: build on every push, push on tags only.
- [ ] If you ship a static site: deploy to GitHub Pages.
- [ ] If you have a database: run migrations once, in a single job, before deploy.
- [ ] Use expand/contract for destructive migrations.

## 6. Quality (chapters 34–39)
- [ ] Turn on branch protection on `main`.
- [ ] Make CI a required status check.
- [ ] Add a coverage threshold and fail the build below it.
- [ ] Enable Dependabot for dependencies and for GitHub Actions.
- [ ] Add CodeQL (or another SAST) on push and PR.
- [ ] Pin actions by SHA where the risk justifies it (chapter 39).

## 7. Operations (chapters 47–50)
- [ ] Document how to read a failing run (chapter 10).
- [ ] Set up notifications only after the pipeline is reliable.
- [ ] Review cost and minutes monthly (chapter 49).
- [ ] Write down your rollback procedure (chapter 46).

## 8. Advanced (chapters 40–46, 51–55)
- [ ] Extract repeated steps into a composite action (chapter 41).
- [ ] Extract repeated jobs into a reusable workflow (chapter 40).
- [ ] If you have a monorepo: path filters and changed-package detection (ch. 44).
- [ ] If you ship versions: tag-driven releases with `gh release create` (ch. 55).
- [ ] If you deploy containers: push on tags only (ch. 52).

## 9. Habits
- [ ] Pin every action version (`@v7`, not `@main`).
- [ ] Quote `on:` in every workflow.
- [ ] Never commit a secret; use placeholders in docs.
- [ ] Write a comment on every non-obvious line.
- [ ] Run `python3 scripts/validate-workflows.py` before pushing.
- [ ] Run `./scripts/verify.sh` on any workflow you change.
```

## 4. What I should see

There is no run to quote. What you should see, when you follow the checklist
in order, is a pipeline that grows in layers:

1. **Week 1.** A green checkmark on every push. Lint, test, build. That is
   enough to start; everything else builds on it. The first green run is the
   milestone that makes everything else worth doing.
2. **Week 2.** Faster runs (cache), and a matrix if you support multiple
   Node versions. The pipeline is now fast enough that you stop dreading
   pushing. A run that takes 30 seconds instead of 4 minutes changes how
   often you push and how quickly you iterate.
3. **Week 3.** Artifacts, conditionals, concurrency. The pipeline is now
   structured: it does the right thing on the right branch and does not
   step on itself. A second push no longer cancels a deploy that is already
   running.
4. **Week 4.** Secrets in the secrets store, environments with reviewers,
   branch protection. The pipeline is now safe: a bad change cannot reach
   production without a human, and a credential cannot leak into a log.
5. **Month 2.** Staging and production deploys, containers or Pages, releases.
   The pipeline now ships software. The first time a tag produces a release
   automatically is the moment the pipeline pays for itself.
6. **Month 3.** Coverage, scanning, dependency updates. The pipeline now
   guards quality. Dependabot PRs arrive weekly and you merge them with one
   click because CI proves they are safe.
7. **Ongoing.** Debugging habits, cost awareness, notifications last. The
   pipeline is now operated, not just built. A monthly review of minutes and
   a quarterly review of the checklist keep it healthy.

### The signs that you are doing it right

- **A new contributor can push a PR and see CI go green without asking
  anyone.** That means the pipeline is documented by its own files.
- **A red build is rare and is fixed within an hour.** That means the tests
  are reliable and the pipeline is fast.
- **Production deploys are boring.** That means the gating and the staging
  environment are doing their job.
- **Nobody mentions the pipeline in standups.** That means it works.

### The signs that you are doing it wrong

- **CI is red more often than it is green.** The tests are flaky or the
  pipeline is too strict. Fix the tests first.
- **Deploys require a Slack message to a specific person.** The approval
  gate is a person, not a process. Configure required reviewers instead.
- **Secrets are stored in a shared password manager and pasted into the UI
  by hand.** Rotate them, move them to the secrets store, and document the
  rotation.
- **The pipeline takes 20 minutes.** Caching and parallelism are missing.
  Go back to sections 2 and 3 of the checklist.
- **Nobody knows what a failing build means.** The error messages are
  unclear. Add assertions with `::error::` and write a debugging runbook.

The order is the lesson. Teams that start with notifications and Slack bots
and end with tests have a noisy pipeline nobody trusts. Teams that start with
tests and end with notifications have a quiet pipeline everyone trusts.

## 5. When to use it and when NOT to

**Follow this checklist when:**

- **You are setting up CI/CD for a new or existing repository.** The order
  prevents the common mistakes (notifying before testing, gating before
  building).
- **You are reviewing a pipeline someone else built.** The checklist is a
  rubric: tick the boxes and see what is missing.
- **You are onboarding a new teammate.** Hand them this chapter and the
  roadmap; they will know where to start.
- **You are auditing a pipeline that has grown organically.** Most real
  pipelines have gaps; the checklist finds them.

**Do NOT follow it blindly when:**

- **Your project is a static site with no database.** Skip the database and
  container sections. Do not build infrastructure you do not need.
- **Your project is a library, not an app.** Skip the deploy sections; focus
  on test, build, and release.
- **You are on a different platform.** The concepts transfer; the file paths
  and keywords do not. Chapter 56.
- **You already have a working pipeline.** Use the checklist as an audit,
  not a rebuild. Change one thing at a time.
- **The checklist is longer than your patience.** Do the first three
  sections and ship. The rest can wait; a simple green pipeline beats a
  perfect one that never lands.

## 6. Common mistakes

- **Starting with notifications.** Symptom: Slack pings for a pipeline that
  is red 80% of the time, so everyone mutes the channel. Fix: notifications
  are the last step, after the pipeline is reliable.
- **Starting with production deploys.** Symptom: the first deploy breaks
  production because there was no staging or no tests. Fix: tests first,
  staging second, production last.
- **Skipping branch protection.** Symptom: a direct push to `main` breaks the
  build and nobody notices until a deploy fails. Fix: required checks before
  anything else can merge.
- **Over-engineering early.** Symptom: a reusable workflow and a matrix
  build for a repo with one contributor and no users. Fix: start simple; add
  structure when the pain is real.
- **Under-engineering late.** Symptom: a repo that grew to 50 contributors
  still has one giant job and no caching. Fix: revisit the checklist when
  the team or the codebase crosses a threshold.
- **Copying a pipeline from another repo without understanding it.** Symptom:
  a workflow that references secrets that do not exist and jobs that do
  nothing. Fix: build it yourself, line by line, once. Then borrow.
- **Treating the checklist as done.** A pipeline is never done; it evolves
  with the code. Re-run the audit when the team or the product changes.
- **Ignoring the "break it on purpose" exercises.** They are not optional;
  they are how you learn what a red build looks like before it matters.
- **One giant job instead of several small ones.** Symptom: a 15-minute job
  that re-runs everything on a one-line change. Fix: split by dependency,
  cache aggressively, and use `needs:` only where it is real.
- **Secrets in repository scope that belong in environment scope.** Symptom:
  a staging job can read the production database password. Fix: move them
  to environment secrets. Chapter 24.
- **No timeout on any job.** Symptom: a hung `npm ci` burns six hours of
  your minute allowance. Fix: `timeout-minutes:` on every job.
- **`ubuntu-latest` everywhere.** Symptom: a build that was green yesterday
  is red today because the runner image changed. Fix: pin `ubuntu-24.04`.
- **Notifications before reliability.** Already listed, but worth repeating:
  it is the most common order mistake and the most expensive one.

### A note on keeping the checklist alive

A checklist that is written once and never revisited becomes a museum piece.
Keep it useful:

- **Re-run it quarterly.** A pipeline that was right six months ago may have
  gaps today: a new service, a new contributor, a new secret.
- **Update it when you learn.** Every incident that the pipeline should have
  caught but did not is a new checklist item.
- **Delete items that no longer apply.** A section about Docker that you
  never use is noise. Remove it.
- **Keep it in the repo.** A `CHECKLIST.md` at the root, next to the
  workflows, is visible to everyone who opens the repository.

## 7. Try it yourself

**Exercise: apply this to a real repository.**

1. **Pick a repository.** Your own, or a small open-source project you
   contribute to. It should have tests and a build step.

2. **Walk the checklist.** Start at section 0 and tick boxes. Do not skip
   ahead; each section assumes the previous one is green.

3. **Stop at the first red.** If a step fails, fix it before moving on.
   The most common first failure is "the app does not build in CI even
   though it builds locally" — usually a missing environment variable or a
   case-sensitive path.

4. **Time-box each section.** Give yourself an hour per section. If it takes
   longer, the app is not ready for that layer; go back.

5. **Prove it works end to end.** Make a small change, open a PR, watch CI
   go green, merge, watch staging deploy, approve production, watch it go
   live. That is the whole course in one loop.

6. **Write down what you learned.** A short note: what was harder than
   expected, what was easier, what you would do differently. That note is
   worth more than the pipeline.

7. **Break it on purpose, one last time.** Remove a required check, push a
   bad commit, watch it land on `main`. Then restore the check. That is the
   exercise that proves the gate works.

8. **Clean up.** Remove any test workflows, test secrets, and test
   environments you created. Leave the repository tidy.

**Hint:** the first pipeline does not have to be perfect. A pipeline that
runs lint and test on every push, with no caching and no deploy, is already
better than no pipeline. Add the rest when the pain of not having it
exceeds the cost of building it.

### A first-week plan (concrete)

If you want a schedule, here is one that has worked for teams of all sizes:

- **Monday.** Section 0 and 1: the app builds and tests locally, and the
  first `ci.yml` runs green on a push. Do not touch anything else.
- **Tuesday.** Section 2: caching. Confirm the second run is faster. Add a
  matrix only if you support more than one Node version.
- **Wednesday.** Section 3: artifacts and concurrency. Upload the build
  output; add `cancel-in-progress: true` on CI.
- **Thursday.** Section 4: secrets and environments. Move one real secret
  into the store; create `staging` and `production` environments.
- **Friday.** Section 5: staging deploy. Automate it; gate production on
  approval; do not deploy to production yet.
- **Week 2 Monday.** Branch protection and required checks. Merge a bad
  PR on purpose and watch it get blocked.
- **Week 2 Tuesday.** Production deploy. Approve it yourself the first
  time, then hand the reviewer role to someone else.
- **Week 2 Wednesday.** Containers or Pages, depending on what you ship.
- **Week 2 Thursday.** Coverage, CodeQL, Dependabot.
- **Week 2 Friday.** Notifications, cost review, rollback drill.

That is two weeks from "no pipeline" to "shipping with a gate". It is not
fast, and it is not slow. It is the pace at which you can actually
understand each layer before adding the next.

### What to do when you are stuck

- **A step fails and the error is cryptic.** Copy the exact failing command
  from the log and run it locally. Chapter 10.
- **The pipeline is slow.** Measure first: which job, which step, how long.
  Then cache or parallelise. Chapter 16 and 18.
- **A secret is not resolving.** Check the scope: repository vs environment,
  and whether the job declares the environment. Chapter 24.
- **An environment gate is not firing.** Check that the environment exists in
  Settings and has reviewers configured. Chapter 28.
- **A deploy is stuck in "Waiting".** That is the gate working, not a bug.
  Approve it, or check who the required reviewers are.
- **You are not sure whether to add a feature.** Ask: "what pain does this
  remove?" If the answer is "none yet", skip it. The checklist is ordered
  by pain.

## 8. Next

There is no next chapter. You are at the end of the course. The next step
is your own repository, your own pipeline, and your own mistakes. Come back
to these chapters when you hit one; they were written for that moment.

If you want to keep learning:

- **GitHub's own docs.** `docs.github.com/en/actions` is the source of
  truth. This course points at it throughout.
- **`actionlint`.** A linter for workflow files. Catches semantic errors
  the YAML parser cannot.
- **The runner images repo.** `github.com/actions/runner-images` lists
  everything preinstalled. Read it once; you will stop guessing.
- **Other platforms.** Chapter 56. The concepts transfer.
- **Your own mistakes.** The best teacher. Break things on purpose, in a
  safe repo, and read the error.

You now know enough to be dangerous. Go build something.

→ End of course.
EOF
echo written