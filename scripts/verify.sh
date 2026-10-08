#!/usr/bin/env bash
# Run a workflow and save the full log, so chapter text can quote real output.
#
# Usage:
#   scripts/verify.sh <workflow-file> [job-id] [event] [label]
#
# Writes docs/_logs/<label>.log and prints the step results plus stdout lines.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO_ROOT/docs/_logs"
mkdir -p "$LOG_DIR"

WORKFLOW="${1:?usage: verify.sh <workflow-file> [job-id] [event] [label]}"
JOB="${2:-}"
EVENT="${3:-push}"
LABEL="${4:-$(basename "$WORKFLOW" .yml)}"

cd "$REPO_ROOT"
set +e
./scripts/run-workflow.sh "$WORKFLOW" "$JOB" "$EVENT" 2>&1 | tee "$LOG_DIR/$LABEL.log"
status="${PIPESTATUS[0]}"
set -e

# act's artifact server is too old for upload-artifact@v7 (it rejects the
# `mime_type` field in the upload request). Re-run with artifact steps swapped for
# equivalent local tar operations; `--bind` makes those files visible across jobs.
if grep -qE 'unknown field .mime_type.|ACTIONS_RUNTIME_TOKEN' "$LOG_DIR/$LABEL.log"; then
  echo
  echo "### artifact backend unsupported by act; re-running with local artifact simulation"
  mkdir -p .tmp/artifacts
  python3 scripts/simulate-artifacts.py "$WORKFLOW" ".tmp/sim-${LABEL}.yml" .tmp/artifacts || exit 1
  rm -f "$LOG_DIR/$LABEL.log"
  set +e
  ./scripts/run-workflow.sh ".tmp/sim-${LABEL}.yml" "$JOB" "$EVENT" 2>&1 | tee "$LOG_DIR/$LABEL.log"
  status="${PIPESTATUS[0]}"
  set -e
fi

echo
echo "### saved to docs/_logs/$LABEL.log (act exit $status)"
exit "$status"