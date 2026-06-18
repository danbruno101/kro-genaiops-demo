#!/usr/bin/env bash
# teardown-multicloud.sh — delete both simulated-cloud clusters cleanly.
set -euo pipefail

CLUSTERS=("genaiops-gke" "genaiops-aks")

for c in "${CLUSTERS[@]}"; do
  if kind get clusters 2>/dev/null | grep -qx "${c}"; then
    kind delete cluster --name "${c}"
  else
    echo "Cluster ${c} not found; skipping."
  fi
done
echo "Multi-cloud demo torn down."
