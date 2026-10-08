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

# Platform image. Official images only, since the usual act community images for
# 24.04 are no longer published. node:* gives us a working Node for free.
PLATFORM_IMAGE="${PLATFORM_IMAGE:-node:24-bookworm}"

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

args=(push --workflows "$WORKFLOW" -P "ubuntu-24.04=$PLATFORM_IMAGE" --pull=false)
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