# 33 — Deployment strategies

> **Verification.** The workflow reused in this chapter is
> `.github/workflows/30-docker-build.yml`, the same file as chapter 30. It
> was executed with
> `./scripts/verify.sh .github/workflows/30-docker-build.yml "" push ch30`,
> and the full log is at `docs/_logs/ch30.log`. The build, smoke-test and
> image-inspection outputs quoted in section 4 are taken from that file.
> `python3 scripts/validate-workflows.py` reports
> `ok .github/workflows/30-docker-build.yml (1 job(s))`.
>
> **What this local execution cannot prove.** The strategies themselves
> (rolling, blue-green, canary, recreate) are operational patterns that
> happen on a host or a cluster, not in a workflow file. Nothing in this
> chapter was executed against a real host. The build that produces the
> artifact a strategy would deploy is real and is quoted below; the
> strategy-specific behaviour is described from the documentation and from
> standard practice, not from a run. There is no separate workflow for this
> chapter, because a strategy is a property of how you run the artifact, not
> of how you build it.

---

## 1. Simple explanation (like I'm 7)

A restaurant that is open for lunch and needs to change its menu. Four ways
to do it:

- **Recreate.** Close the restaurant, repaint the menu board, reopen. Nobody
  eats during the change. Simple, but there is downtime.
- **Rolling.** Change one table's menu at a time. Most tables still serve
  the old menu while a few serve the new one; gradually everything switches.
  No full closure, but for a while two menus are in use at once.
- **Blue-green.** Build a second identical restaurant next door with the new
  menu. When it is ready, move the sign from the old building to the new
  one. The switch is instant; the old building stays as a fallback.
- **Canary.** Serve the new menu to one table only. Watch whether those
  customers get sick. If they are fine, roll it out to the rest; if not,
  take the new menu away and nobody else is affected.

All four get you from "old version" to "new version." They differ in
downtime, risk, cost, and how fast you can go back. That is the whole
chapter.

## 2. Real name

### Deployment strategy

The way a new version of software replaces an old one in a running system.
The strategy determines downtime, risk, rollback speed and cost. It is a
property of the runtime platform (Kubernetes, ECS, a load balancer, a
process manager), not of the CI workflow that built the artifact.

### Recreate

Stop the old version completely, then start the new one. There is a window
where nothing is running. Simplest of all; only acceptable when downtime is
fine.

### Rolling update (rolling deployment)

Replace instances one (or a few) at a time. At any moment, old and new
versions run side by side. No downtime if there is more than one instance,
but the transition takes time and both versions must coexist.

### Blue-green deployment

Run two identical environments ("blue" and "green"). One serves traffic;
the other is idle or being updated. Switch traffic to the updated one
instantly. Rollback is switching back. Costs double the infrastructure
while both run.

### Canary release (canary deployment)

Route a small fraction of traffic to the new version while the rest stays
on the old one. Observe metrics. If healthy, increase the fraction until
the new version serves everything. If not, route everything back.

### Traffic shifting

The mechanism behind blue-green and canary: a load balancer or router
changes which instances receive requests, without restarting them. The
deploy is a routing change, not a process change.

### Health check / readiness probe

A test the platform runs against an instance to decide whether it is ready
to receive traffic. A rolling update waits for the new instance to pass its
health check before moving to the next. Without health checks, "deployed"
means "started," not "working."

### Rollback (in this context)

Reverting to the previous version. With blue-green, rollback is a routing
switch (seconds). With rolling, rollback is another rolling update (minutes).
With recreate, rollback is another recreate (downtime again). Canary rollback
is routing all traffic back to the old version.

### Feature flag

A runtime switch that turns a feature on or off without a deploy. Often
combined with canary: deploy the code to everyone but enable the feature
for 1% of users. Distinct from a deployment strategy, but they solve the
same problem (safe change) from different angles.

### Distinctions people get wrong

- **Deploy vs release.** A deploy puts code on a server. A release makes it
  visible to users. Blue-green and canary separate the two; recreate and
  rolling do not.
- **Rolling vs canary.** Rolling replaces instances gradually but sends all
  traffic to whatever is running. Canary keeps most traffic on the old
  version while a little goes to the new. Rolling is about instances;
  canary is about traffic.
- **Blue-green vs canary.** Blue-green is all-or-nothing with an instant
  switch and a full fallback. Canary is gradual traffic shifting with
  observation. Blue-green is simpler to reason about; canary gives finer
  control.
- **Strategy vs pipeline.** The CI/CD pipeline builds and ships the
  artifact. The strategy is how the runtime adopts it. A pipeline can
  trigger any strategy; the strategy lives in the platform config.
- **Zero downtime vs zero risk.** Rolling, blue-green and canary avoid
  downtime, not bugs. A bad deploy still breaks users; the strategy only
  limits how many and how fast.
- **Rollback vs fix forward.** Rollback goes back to a known-good version.
  Fix forward ships a corrected version. Both are valid; the strategy you
  chose determines how fast rollback is.

## 3. Workflow example

This chapter reuses `.github/workflows/30-docker-build.yml` from chapter 30.
There is no new workflow, because a deployment strategy is not a build step;
it is how the built artifact is run. The build below is the artifact that
any of the four strategies would deploy.

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

      - uses: docker/setup-buildx-action@v4

      - name: Build the image
        id: build
        uses: docker/build-push-action@v7
        with:
          context: cicd-learn
          file: cicd-learn/Dockerfile
          tags: |
            cicd-learn:sha-${{ github.sha }}
            cicd-learn:main
          load: true
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run the image and check the output
        run: |
          echo "--- images present ---"
          docker images cicd-learn --format '{{.Repository}}:{{.Tag}} {{.Size}}'
          echo
          echo "--- running it ---"
          output=$(docker run --rm cicd-learn:sha-${{ github.sha }} Ada)
          echo "$output"
          echo
          echo "$output" | grep -q 'HELLO, ADA!' || {
            echo "::error::the image did not produce the expected output"
            exit 1
          }
          echo "the image works"

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
          if docker run --rm --entrypoint sh cicd-learn:sha-${{ github.sha }} -c 'test "$(id -u)" = "0"'; then
            echo "::warning title=Container runs as root::Add a USER instruction to the Dockerfile"
          else
            echo "the container runs as a non-root user"
          fi
```

What a strategy consumes from this build is the image tag
`cicd-learn:sha-<commit>`. The strategy's job is to get that tag running on
the target and to switch traffic to it. The build does not change; only the
deploy step does. Chapter 31 pushes the image to a registry so the target can
pull it; chapter 32 copies files to a server. Either way, the artifact is
the same.

## 4. What I should see

### The build (real, from `docs/_logs/ch30.log`)

The image builds, smoke-tests, and is inspected, exactly as in chapter 30:

```
[Build a Docker image/Build and smoke-test the image]   | #15 [runtime 7/7] RUN node build.mjs && rm -rf node_modules
[Build a Docker image/Build and smoke-test the image]   | #15 0.136 built dist/app.js (2887 bytes)
[Build a Docker image/Build and smoke-test the image]   | #15 DONE 0.3s
...
[Build a Docker image/Build and smoke-test the image]   | cicd-learn:main 334MB
[Build a Docker image/Build and smoke-test the image]   | cicd-learn:sha-aa4fe9e164daa8cb6ac189d751ca2a0e15ab0b5a 334MB
...
[Build a Docker image/Build and smoke-test the image]   | {
[Build a Docker image/Build and smoke-test the image]   |   "message": "HELLO, ADA!",
[Build a Docker image/Build and smoke-test the image]   |   "total": 10,
[Build a Docker image/Build and smoke-test the image]   |   "mean": 2.5
[Build a Docker image/Build and smoke-test the image]   | }
[Build a Docker image/Build and smoke-test the image]   | the image works
...
[Build a Docker image/Build and smoke-test the image]   | 334MB
[Build a Docker image/Build and smoke-test the image]   | 74.2MB	COPY --chown=node:node /app/node_modules ./n…
...
[Build a Docker image/Build and smoke-test the image]   | the container runs as a non-root user
[Build a Docker image/Build and smoke-test the image]   ✅  Success - Main Confirm it does not run as root [326.304014ms]
[Build a Docker image/Build and smoke-test the image] 🏁  Job succeeded
```

That is the artifact a strategy deploys: an image tagged
`cicd-learn:sha-<commit>`, 334MB, non-root, proven to run.

### What each strategy looks like (described, not run)

**Recreate.** The platform stops all instances of the old version, then
starts instances of the new one. During the gap, requests fail or queue.
Typical implementation: a single-instance service where you kill the process
and start the new one; or Kubernetes with `strategy: Recreate`. Rollback is
another recreate, with the same downtime.

**Rolling.** The platform replaces instances gradually: take one down,
start the new one, wait for its health check, repeat. At any moment both
versions serve traffic. Typical implementation: Kubernetes default
`RollingUpdate`, AWS ECS rolling, or a load balancer draining one instance
at a time. Rollback is a new rolling update back to the old tag.

**Blue-green.** Two identical environments exist. The idle one is updated to
the new version and health-checked. Traffic switches at the load balancer in
one operation. The old environment stays running as the fallback. Typical
implementation: two target groups behind an ALB, or two Kubernetes
deployments with a service selector switch. Rollback is switching traffic
back (seconds).

**Canary.** A small fraction of traffic (1%, 5%, 10%) is routed to the new
version while the rest stays on the old one. Metrics are watched (error
rate, latency, business KPIs). If healthy, the fraction increases until the
new version serves everything. If not, traffic returns to 0% on the new
version. Typical implementation: a service mesh (Istio, Linkerd), a load
balancer with weighted routing, or a platform feature (AWS CodeDeploy,
Argo Rollouts).

## 5. When to use it and when NOT to

### Recreate

**Use when:**
- Downtime is acceptable (internal tools, batch jobs, low-traffic services).
- The old and new versions cannot coexist (database schema incompatible,
  singleton lock, shared state).
- You want the simplest possible deploy.

**Do NOT use when:**
- Users expect availability. Even a 30-second gap is visible.
- You need a fast rollback. Recreate rollback is another recreate.

### Rolling

**Use when:**
- You have multiple instances and want no downtime.
- Old and new versions are compatible (same API, same data format).
- You want a built-in, low-cost default. Most platforms default to rolling.

**Do NOT use when:**
- Old and new versions are incompatible. Mixed traffic during the transition
  breaks users.
- You need instant rollback. Rolling rollback takes as long as the original
  rollout.
- You have a single instance. Rolling on one instance is recreate with extra
  steps.

### Blue-green

**Use when:**
- You need instant, safe rollback (switch back in seconds).
- You want to test the new version with real traffic before committing
  (smoke-test the idle environment).
- You can afford double the infrastructure for the duration of the deploy.
- Deployments are infrequent enough that the cost is small.

**Do NOT use when:**
- Infrastructure cost matters. Two full environments running is expensive.
- Deployments are very frequent (the second environment is always busy).
- Your state is not portable. A database shared between blue and green
  couples them; a migration in one affects the other.

### Canary

**Use when:**
- You want to catch problems with real traffic before full rollout.
- You have good observability (metrics, logs, alerts) to judge health.
- The change is risky or user-facing and you want a gradual blast radius.
- You can route traffic by weight or by user segment.

**Do NOT use when:**
- You have no metrics. Canary without observation is just a slow rolling
  update with no decision point.
- The change is a database migration that affects all users. A canary
  cannot isolate a schema change.
- Your traffic is too low to get a meaningful sample at 1%.
- The platform does not support weighted routing. Implementing canary on a
  single server is not worth it.

### Summary table

| Strategy | Downtime | Rollback speed | Infra cost | Complexity | Needs metrics |
| -------- | -------- | -------------- | ---------- | ---------- | ------------- |
| Recreate | Yes | Slow (redeploy) | 1x | Low | No |
| Rolling | No (if >1 instance) | Medium | 1x | Low | Helpful |
| Blue-green | No | Instant | 2x during deploy | Medium | Helpful |
| Canary | No | Fast (route back) | 1x + routing | High | Yes |

### The usual progression

Teams typically move through these as they grow:

1. **Recreate** while the app is small and downtime is fine.
2. **Rolling** once there is more than one instance and downtime stops being
   acceptable.
3. **Blue-green** once rollback speed matters more than infrastructure cost.
4. **Canary** once observability is good enough to judge a partial rollout.

Most teams never reach canary, and that is fine. Rolling with a good
health check and a fast rollback is a solid, defensible choice for the
majority of services.

## 6. Common mistakes

- **Choosing a strategy the platform does not support.** Canary on a
  platform with no weighted routing is a fiction. Symptom: you implement
  canary in application code and it is buggy. Fix: check what your platform
  supports before designing the deploy.
- **No health checks.** A rolling update that does not wait for readiness
  just restarts instances as fast as possible. Symptom: a deploy that
  reports success while instances crash-loop. Fix: define a real health
  endpoint and configure the platform to use it.
- **Mixing incompatible versions.** Rolling and canary put old and new
  code in the same fleet. If the new code changes the API or the data
  format, mixed traffic breaks. Symptom: intermittent 500s during a
  deploy. Fix: backward-compatible changes only, or use feature flags to
  gate the new behaviour.
- **Database migrations coupled to the deploy.** A migration that runs on
  deploy affects all instances, including the old ones still serving
  traffic. Symptom: the old version breaks against the new schema. Fix:
  expand/contract migrations (chapter 53) so old and new code coexist.
- **Blue-green with shared state.** Two environments pointing at the same
  database means a migration in green affects blue. Symptom: rollback does
  not actually restore the old behaviour. Fix: either migrate after the
  switch or accept that rollback is not free.
- **Canary without a stop condition.** If nobody watches the metrics, the
  canary becomes a slow rolling update. Symptom: a bad change reaches 100%
  before anyone notices. Fix: automate the promotion decision on a metric
  threshold.
- **Treating rollback as free.** Blue-green rollback is fast but the old
  environment may have stale data or missed writes. Symptom: data loss after
  a rollback. Fix: design for rollback from the start; test it.
- **Over-engineering.** A single-instance internal tool does not need
  canary. Symptom: a deployment pipeline more complex than the app. Fix:
  match the strategy to the actual risk and traffic.
- **Confusing deploy strategy with release strategy.** Feature flags,
  phased rollouts and A/B tests are release concerns. Symptom: a deploy
  pipeline that also manages user-facing experiments. Fix: keep deploy
  (getting code running) separate from release (making it visible).

## 7. Try it yourself

**Exercise: observe the strategies with containers on your own machine.**

Part A — the baseline (the artifact any strategy deploys):

1. Run chapter 30's workflow to build the image:

   ```bash
   ./scripts/verify.sh .github/workflows/30-docker-build.yml "" push ch30
   ```

   Confirm `HELLO, ADA!` and 334MB. That image is what you are deploying.

Part B — simulate rolling with two containers:

2. Start two "instances" of the old version:

   ```bash
   docker run -d --name inst-a -p 8081:3000 cicd-learn:main
   docker run -d --name inst-b -p 8082:3000 cicd-learn:main
   ```

   (The app prints to stdout rather than serving HTTP, so this is a
   stand-in: imagine each container is an instance behind a load balancer.)

3. Replace one instance with the new version:

   ```bash
   docker stop inst-a && docker rm inst-a
   docker run -d --name inst-a -p 8081:3000 cicd-learn:sha-$(git -C cicd-learn rev-parse --short HEAD)
   ```

   That is one step of a rolling update: one instance changed, one
   unchanged.

4. Replace the second:

   ```bash
   docker stop inst-b && docker rm inst-b
   docker run -d --name inst-b -p 8082:3000 cicd-learn:sha-$(git -C cicd-learn rev-parse --short HEAD)
   ```

   Both instances now run the new version. Rollback would repeat the
   process in reverse.

Part C — simulate blue-green with a symlink:

5. Reuse the release-directory pattern from chapter 32. Build two
   "environments" and switch between them:

   ```bash
   mkdir -p /tmp/bg/blue /tmp/bg/green
   echo "version 1" > /tmp/bg/blue/version.txt
   echo "version 2" > /tmp/bg/green/version.txt
   ln -sfn /tmp/bg/blue /tmp/bg/current
   cat /tmp/bg/current/version.txt          # version 1
   ln -sfn /tmp/bg/green /tmp/bg/current
   cat /tmp/bg/current/version.txt          # version 2
   # rollback:
   ln -sfn /tmp/bg/blue /tmp/bg/current
   cat /tmp/bg/current/version.txt          # version 1 again
   ```

   The switch is one `ln -sfn`. That is the blue-green idea: two complete
   environments, instant swap, instant rollback.

Part D — simulate canary with a counter:

6. Route 9 of 10 requests to "old" and 1 to "new". A simple way to see it:

   ```bash
   for i in $(seq 1 10); do
     if [ $i -eq 1 ]; then echo "request $i -> NEW"; else echo "request $i -> old"; fi
   done
   ```

   Increase the `1` to `2`, then `5`, then `10` as confidence grows. That
   is the canary progression: 10%, 20%, 50%, 100%.

7. **Clean up:**

   ```bash
   docker rm -f inst-a inst-b 2>/dev/null
   rm -rf /tmp/bg
   ```

**Hint:** none of these simulations need a load balancer or a cluster. The
point is to feel the difference: rolling changes instances, blue-green
swaps environments, canary changes traffic weights. The commands are the
same idea at small scale.

## 8. Next

You now know what the strategies are and when each is worth it. The next
chapter turns CI into a gate: branch protection and required status checks,
so that a red build actually blocks a merge.

→ [34 — Branch protection and required checks](34-branch-protection.md)