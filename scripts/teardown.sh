#!/usr/bin/env bash
# teardown.sh — delete the demo cluster cleanly.
set -euo pipefail
CLUSTER="${CLUSTER:-genaiops-demo}"
kind delete cluster --name "${CLUSTER}"
echo "Deleted cluster ${CLUSTER}."
