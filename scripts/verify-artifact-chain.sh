#!/usr/bin/env bash
# Verify a produce -> upload -> download -> consume job chain, in two phases.
#
# Why this exists: `act` 0.2.89 cannot host a working artifact service for
# actions/upload-artifact@v7 (its bundled server rejects the `mime_type` field),
# and without --bind every job gets a fresh copy-in workspace, so a consumer job
# cannot see what a producer job produced. Neither is true on GitHub, where the
# artifact service is exactly the mechanism that carries files between jobs.
#
# So: run the producer alone with --bind, keep what it built, clean the workspace
# back to pristine, then run the consumer with the artifact staged where its
# download step expects it. Both halves are real runs over real files. The only
# thing substituted is GitHub's artifact storage.
#
# Usage:
#   scripts/verify-artifact-chain.sh <workflow> <producer-job> <consumer-job> [label]
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WORKFLOW="${1:?usage: verify-artifact-chain.sh <workflow> <producer> <consumer> [label]}"
PRODUCER="${2:?}"
CONSUMER="${3:?}"
LABEL="${4:-chain}"

LOG_DIR="$REPO_ROOT/docs/_logs"
STAGE="$REPO_ROOT/.tmp/chain-$LABEL"
mkdir -p "$LOG_DIR" "$STAGE"

# Remove paths, tolerating root-owned files left by --bind containers. Plain
# `rm` cannot delete those; this is.
scrub() {
  docker run --rm -v "$REPO_ROOT:/w" -w /w alpine:3.20 sh -c "rm -rf $*"
}

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# Clear stale build output first. A leftover empty dist/ from a previous failed
# chain would be picked up by the staging loop below and silently stage nothing.
scrub cicd-learn/dist cicd-learn/coverage dist build dist-out

echo "### phase 1: $PRODUCER  (--bind so its output stays on disk)"
# Phase 1 is expected to exit non-zero: the real upload-artifact step has no
# artifact service to talk to. What matters is that the build steps succeeded and
# their files are on disk.
set +e
ACT_BIND=1 ./scripts/run-workflow.sh "$WORKFLOW" "$PRODUCER" push 2>&1 | tee "$LOG_DIR/$LABEL-produce.log"
set -e

# Stage what the producer built. upload-artifact stores paths relative to the
# least common ancestor of `path`, so `cicd-learn/dist` is stored as `dist/`.
staged=""
for candidate in cicd-learn/dist dist build dist-out; do
  if [ -d "$candidate" ]; then staged="$candidate"; break; fi
done
if [ -z "$staged" ]; then
  echo "no build output found after $PRODUCER; nothing to chain" >&2
  exit 1
fi

mkdir -p "$STAGE/artifact"
cp -r "$staged/." "$STAGE/artifact/"
tar czf .tmp/artifacts/dist.tar -C "$STAGE/artifact" . 2>/dev/null || {
  mkdir -p .tmp/artifacts
  tar czf .tmp/artifacts/dist.tar -C "$STAGE/artifact" .
}
echo "### staged artifact contents:"
( cd "$STAGE/artifact" && find . -type f | sed 's|^\./||' )

# Restore a pristine workspace so the consumer cannot cheat by reading leftovers.
# GitHub gives it a brand new machine with nothing in it; we approximate that.
echo
echo "### cleaning the workspace before the consumer job"
scrub cicd-learn/dist cicd-learn/coverage dist build dist-out

python3 scripts/simulate-artifacts.py "$WORKFLOW" ".tmp/chain-$LABEL.yml" .tmp/artifacts --only-job "$CONSUMER"

echo
echo "### phase 2: $CONSUMER  (fresh workspace, artifact pre-staged)"
# --bind again, so the container can SEE the staged artifact and the cleaned
# workspace. Without it act copies the workspace in and the staged tar, which
# exists only on the host, is invisible to the consumer.
set +e
ACT_BIND=1 ./scripts/run-workflow.sh ".tmp/chain-$LABEL.yml" "$CONSUMER" push 2>&1 | tee "$LOG_DIR/$LABEL-consume.log"
status="${PIPESTATUS[0]}"
set -e

echo
echo "### chain exit status: $status"
exit "$status"