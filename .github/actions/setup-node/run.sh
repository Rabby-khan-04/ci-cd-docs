#!/usr/bin/env bash
# The script half of a composite action. This particular action delegates to
# other actions, so there is not much logic here; a real composite action with
# its own logic would put it here.
set -euo pipefail

echo "composite action invoked"
echo "  node-version: ${1:-22}"
echo "  run-checks  : ${2:-true}"
