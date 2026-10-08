#!/usr/bin/env bash
# Run a workflow file from this repo locally with `act`, using a real Ubuntu
# container. This is the closest thing to a GitHub-hosted run available before
# the repository exists on github.com.
#
# Usage:
#   scripts/run-workflow.sh <workflow-file> [job-id] [event]
#
# Examples:
#   scripts/run-workflow.sh .github/workflows/first-workflow.yml hello push
#   scripts/run-workflow.sh .github/workflows/ci.yml push
#
# `act` is NOT GitHub. Known differences, so results are not over-trusted:
#   - `actions/checkout` is simulated by act: the workspace is bind-mounted from
#     your local clone, so `git remote -v` is empty and no network fetch happens.
#   - The container's toolchain is the Docker image's, not GitHub's runner image.
#     For example `node --version` here is the image's, not the runner's.
#   - GitHub-only services (secrets store, environments, OIDC, concurrency
#     groups) are stubbed or ignored.
# A green run here means "the YAML is valid and the commands work". It does not
# replace a real GitHub-hosted run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACT_BIN="${ACT_BIN:-/tmp/opencode/act}"

# Platform image: scripts/act-runner.Dockerfile, Node 24 plus the Docker CLI and
# git. The community images `act` used to default to are no longer published for
# 24.04, and plain `node:24-bookworm` has no `docker` command, which the Docker
# chapters need in order to smoke-test a built image.
#
# Build it with:
#   docker build -f scripts/act-runner.Dockerfile -t cicd-act-runner:24 scripts
PLATFORM_IMAGE="${PLATFORM_IMAGE:-cicd-act-runner:24}"

if [[ ! -x "$ACT_BIN" ]]; then
  echo "act not found at $ACT_BIN" >&2
  echo "Install it, or set ACT_BIN to its location:" >&2
  echo "  curl -sL https://github.com/nektos/act/releases/latest/download/act_Linux_x86_64.tar.gz | tar xz -C /tmp/opencode act" >&2
  exit 127
fi

WORKFLOW="${1:?usage: run-workflow.sh <workflow-file> [job-id] [event]}"
JOB="${2:-}"
EVENT="${3:-push}"

if [[ ! -f "$REPO_ROOT/$WORKFLOW" ]]; then
  echo "no such workflow: $WORKFLOW" >&2
  exit 1
fi

echo "### act $("$ACT_BIN" --version)"
echo "### image  $PLATFORM_IMAGE"
echo "### event  $EVENT"
echo "### file   $WORKFLOW"
echo

cd "$REPO_ROOT"

# --bind mounts the working directory into the container instead of copying it in.
# OFF by default, and it must stay off for accuracy: with --bind, a later job sees
# the previous job's files, which GitHub never does. It is switched on only by
# scripts/verify-artifact-chain.sh, which runs producer and consumer as two
# separate invocations and cleans up in between.
#
# NOTE ON ARTIFACTS: act 0.2.89 bundles an artifact server, but it cannot speak
# the protocol used by actions/upload-artifact@v7 (it rejects the `mime_type`
# field), so real artifact steps fail locally with:
#   Error decode request body: unknown field "mime_type"
# scripts/verify.sh detects that and re-runs with artifact steps replaced by
# equivalent local tar operations. `--bind` is what makes that work: it mounts the
# working directory into the container instead of copying it in, so files written
# by one job are visible to the next job, exactly as GitHub's artifact service
# would make them visible.
# --bind is opt-in: set ACT_BIND=1 (or any non-empty value) to mount the working
# directory into the container instead of copying it in.
ACT_BIND_FLAG=()
if [[ -n "${ACT_BIND:-}" ]]; then
  ACT_BIND_FLAG=(--bind)
fi

args=(
  push
  --workflows "$WORKFLOW"
  -P "ubuntu-24.04=$PLATFORM_IMAGE"
  --pull=false
  "${ACT_BIND_FLAG[@]+"${ACT_BIND_FLAG[@]}"}"
)
if [[ -n "$JOB" ]]; then
  args+=(-j "$JOB")
fi

set +e
"$ACT_BIN" "${args[@]}"
status=$?
set -e

echo
echo "### act exit status: $status"
exit "$status"