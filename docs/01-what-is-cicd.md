# 01 — What is CI/CD?

> **Verification for this chapter:** no workflow needed, it is a concepts chapter.
> `run: echo` style checks were run through `scripts/run-workflow.sh` while
> writing chapters 04+. See [00-roadmap.md](00-roadmap.md#verified-versions-the-numbers-every-chapter-is-written-against) for versions.

---

## 1. Simple explanation (like I'm 7)

You know how a factory makes chocolate bars? The chocolate moves along a
conveyor belt. At each stop on the belt, a robot checks it. If the chocolate is
wrong, the belt stops right there and nobody gets a bad bar.

Nobody stands at the end of the belt eating every single bar to check it. They
trust the checks at the stops.

Now imagine the belt moves only when you press a button, and it is dark at night.

- **Without a pipeline:** you press a button, wait 40 minutes, then find out the
  chocolate is broken. You fix it, press the button, wait 40 minutes again. You
  find out about the breakage the next day, or worse, your friend finds out
  because the bar reached them.
- **With a pipeline:** the belt is always on. Every time you change something,
  the belt starts by itself and runs the checks. Broken chocolate gets caught in
  2 minutes, not the next day.

That is the whole idea. Everything else in this course is detail.

## 2. Real name

The three words are three different things. People mix them up constantly,
including in job interviews.

### Continuous Integration (CI)

Merging everyone's work into one shared branch many times a day, and **automatically
verifying every merge with a build and tests** before it is allowed to stay.

The word that matters is *automatically*. If a human has to remember to run the
tests, they will forget. CI means the verification is not a thing someone
remembers to do, it is a thing that happens because a machine cannot forget.

CI is about **code quality**: does it compile, does it lint, do the tests pass,
is coverage still good enough.

CI is where most of this course lives, and where you should spend most of your
time. CI/CD is a spectrum with CI at the easy end and CD at the end where
mistakes cost real money.

### Continuous Delivery (CD, with an "e")

Everything CI does, **plus the ability to release at any moment with one command or
one click**, but a **human still decides when to actually do it**.

The build is always sitting there, tested, packaged, waiting. Like a meal that is
finished and plated in the kitchen, waiting for the chef to decide to serve it.

You could ship on a Tuesday. The question is only whether anyone wants to.

This is the setup most professional teams aim for, and it is what you should
build. Continuous delivery means *removing the decision*, not automating the
decision. Once releasing takes one click and takes five minutes, teams stop
batch-releasing and release constantly, because batching was only ever there to
amortize the pain of a scary deploy. Take away the pain and the batching becomes
pure harm.

### Continuous Deployment (CD, with no "e")

Same thing, but the human decision is gone too. Every commit that passes CI goes
straight to production, automatically.

No human says yes. The pipeline has permission to ship on its own.

This sounds reckless and sometimes it is. But the risk is manageable once you
have the safety nets from Part 7 of this course: branch protection, required
checks, feature flags, canary releases, and rollbacks. With those in place,
shipping 20 times a day is genuinely *less* risky per release than deploying once
a month, because you find out about breakage while it is small and you touch far
fewer lines of code each time.

Netflix, Amazon and Google all deploy continuously. It is not reckless, it is
just a different set of costs.

### How they differ, in one table

| | Automatic build + test | Can release any time | Ships without asking a human | Needs a scary deploy window |
| --- | --- | --- | --- | --- |
| **CI** only | Yes | No | No | Yes, all at once |
| **CI + Continuous Delivery** | Yes | Yes | No | No |
| **CI + Continuous Deployment** | Yes | Yes | Yes | No |

Read it as nested: each row includes everything above it.

### Why teams bother at all

Honestly, for a one-person weekend project: **you do not, for a long time.** Skip
this chapter in practice until you have collaborators, or until you have broken
production once and wished something had checked your work.

The reasons teams adopt CI/CD, roughly in order of how much they matter:

1. **Bugs get caught in minutes instead of weeks.** The interval between writing
   a bug and finding out about it is the single biggest predictor of how painful
   a bug is. CI minimizes it.
2. **Nobody has to be the person who runs the tests.** Human beings are bad at
   repetitive verification and good at design. CI takes the boring half.
3. **Merging stops being scary.** If `main` is always green and always tested,
   merging is a non-event. If you only test at release time, `main` rots, merges
   take longer, and releases get postponed. This death spiral is the real reason
   CI exists, not the testing itself.
4. **Deploying stops being an event and becomes a non-event.** Fewer releases,
   each smaller, each easier to blame and revert.
5. **Confidence scales with the team.** Two people can work without CI. Twenty
   people cannot.

### The cost, honestly

- **Time to set up.** A day or two for a small project. Real.
- **Maintenance.** The pipeline breaks when dependencies update. It is code, and
  it needs looking after.
- **Minutes and money.** GitHub-hosted runners are free for public repos, and
  private repos get a free monthly allowance. Covered in chapter 49.
- **Flaky tests.** The real danger. A test that fails at random destroys trust in
  the pipeline faster than anything else, and once people learn "just re-run it,
  it's probably fine", the pipeline is worse than useless. Chapter 13 comes back
  to this.

### The single most common beginner misunderstanding

"I can already run these commands on my laptop. What does this add?"

The answer is not *capability*, it is **certainty and frequency**. You *can* run
the tests locally, and you *did not*, and that one time you shipped a broken
build. CI is the part that runs when you are tired, in a hurry, on a Friday, at
6pm, having already forgotten that file. Automation has no bad days.

## 3. Workflow example

Concept chapters have nothing to run yet. But here is the entire pipeline we are
going to build up over this course, so you can see where chapter 01 sits in the
roadmap. This is the finished shape, not something to type now:

```yaml
# .github/workflows/ci.yml — the destination, chapters 11 to 15
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

defaults:
  run:
    working-directory: cicd-learn

jobs:
  # These three are independent, so they run at the same time. Chapter 18.
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - run: npm ci
      - run: npm run lint

  test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - run: npm ci
      - run: npm test

  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-artifact@v7
        with:
          name: dist
          path: cicd-learn/dist

  # This one waits for all three. Chapter 18 covers `needs:`.
  release-ready:
    needs: [lint, test, build]   # nothing below starts until all three are green
    runs-on: ubuntu-24.04
    steps:
      - run: echo "Everything passed. This is the green light to deploy."
```

Note the structure: three parallel quality checks, then one gate. That shape is
the whole course in miniature. Chapter 15 builds the first version of it for real,
chapter 18 makes the parallelism explicit, chapter 20 adds the artifact, and
chapters 27 to 33 attach a deploy to the gate.

## 4. What I should see

Nothing yet, and that is correct. This chapter has no workflow file, so pushing
produces no new run.

By the end of chapter 15 you will have this in the **Actions** tab:

```
CI
├─ ✓ lint              (completed in 14s)
├─ ✓ test              (completed in 21s)
├─ ✓ build             (completed in 18s)
└─ ✓ release-ready     (completed in 3s)
```

A green tick means every command in that job exited with code 0. A red cross means
at least one command exited non-zero, and the job stops at that step.

## 5. When to use it and when NOT to

**Use CI/CD when:**

- More than one person pushes to the repo, even occasionally. Merging untested
  code is how outages happen.
- You deploy to anywhere other than your own laptop.
- You have tests worth protecting. Coverage with no CI is a number you compute by
  hand and forget.
- Someone else will ever look at this code, including future you.

**Do NOT bother yet when:**

- It is a solo weekend project that never leaves your laptop. The setup cost is
  real and the payoff is not.
- There are no tests. A pipeline that runs `npm test` and passes because there are
  zero tests is a green light that means nothing. Write the tests first.
- The project changes shape every week. A pipeline that references files that
  keep moving will be rewritten every week.
- You cannot spare an afternoon. Setup is a half-day the first time.

The honest beginner path, which is also the fastest: build the CI pipeline for
this course's sample app because it is tiny and disposable, then apply the same
shape to a real project once you have one.

## 6. Common mistakes

- **Confusing delivery and deployment.** Continuous delivery stops at "a human
  clicks." Continuous deployment does not. They are different levels of
  automation and different levels of risk.
- **Setting up CI and no tests.** Green because it did nothing. A pipeline that
  cannot fail is not a safety net.
- **Running everything on every push.** Wasting minutes and training people to
  ignore the pipeline. Chapter 06 is about choosing triggers carefully.
- **Trying to reach continuous deployment before continuous integration works.**
  Automating a deploy on top of unreliable tests just ships unreliability faster.
- **Expecting CI to fix bugs.** It finds them earlier. It does not find the class
  of bug where the code does what you told it to, and you told it the wrong thing.
- **Believing "100% CI coverage" means the code is good.** It means the tests ran,
  nothing more. Chapter 35.
- **Treating a red pipeline as an inconvenience to route around.** The moment you
  merge with a red X because "the failure looks unrelated", you have taught your
  team that the pipeline is advisory. It took one excuse.

## 7. Try it yourself

**Exercise: experience the interval, once, by hand.**

The point is to feel the difference between finding a bug in 2 seconds and
finding it in a day.

1. In `cicd-learn/`, break a test on purpose. In `test/greet.test.js`, change the
   first expectation:

   ```js
   expect(greet('Ada')).toBe('Hello, Grace!');
   ```

2. Run `npm test` locally and read the failure:

   ```
   FAIL  test/greet.test.js > greet > greets by name
   AssertionError: expected 'Hello, Ada!' to be 'Hello, Grace!'
     Expected: "Hello, Grace!"
     Received: "Hello, Ada!"
   ```

3. Notice how fast you knew. About 200 milliseconds.

**Hint:** the bug above is in your *test*, not your code. That is a real category
of bug too, and it is why chapter 13 covers reading failures properly.

4. Now undo it: `git checkout test/greet.test.js` (or set the expectation back to
   `'Hello, Ada!'`) and confirm `npm test` is green again.

5. Consider the alternative. Instead of running that one command, imagine you had
  finished work at 6pm, went for dinner, and the failing command was three steps
  deep in a script you were not looking at. The interval just went from
  milliseconds to eight hours.

**Break the pipeline on purpose, later:** once chapter 04 lands, you will make the
GitHub Actions run go red on purpose by breaking a test and pushing. That is the
exercise that actually matters, and it is chapter 04's.

## 8. Next

You now know what the machine is for. Chapter 02 takes the pipeline apart into
its moving parts: trigger, workflow, job, step, runner, artifact. That vocabulary
is used, without redefinition, in every remaining chapter.

→ [02 — Anatomy of a pipeline](02-anatomy-of-a-pipeline.md)