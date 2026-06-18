#!/usr/bin/env bash
# =============================================================================
# deploy-multicloud-real.sh — deploy the GenAIOps platform to the REAL GKE and
# AKS clusters for the live demo, by calling deploy-to-cluster.sh for each.
#
# Assumes both clusters already exist and their kubeconfig contexts are named
# `gke` and `aks` (see docs/PROVISION-REAL-CLUSTERS.md, which renames them for
# you). Override the context names via env if yours differ:
#
#   GKE_CONTEXT=my-gke AKS_CONTEXT=my-aks ./scripts/deploy-multicloud-real.sh
#
# Needs: kubectl, helm, cloud credentials wired into the contexts.
# =============================================================================
set -euo pipefail

HERE="$(dirname "$0")"
GKE_CONTEXT="${GKE_CONTEXT:-gke}"
AKS_CONTEXT="${AKS_CONTEXT:-aks}"

"${HERE}/deploy-to-cluster.sh" --context "${GKE_CONTEXT}" --cloud gke
"${HERE}/deploy-to-cluster.sh" --context "${AKS_CONTEXT}" --cloud aks

printf "\n\033[1;36m▶ Both clouds are ready. Show the thesis:\033[0m\n"
cat <<EOF

  # Product team ships ONE spec — it never names a cloud or a StorageClass.
  kubectl --context ${GKE_CONTEXT} apply -f instances/sentiment-api.yaml
  kubectl --context ${GKE_CONTEXT} get pvc sentiment-api-cache   # bound to premium-rwo

  # Platform team MOVES the same workload to the other cloud. Same file. No diff.
  kubectl --context ${AKS_CONTEXT} apply -f instances/sentiment-api.yaml
  kubectl --context ${AKS_CONTEXT} get pvc sentiment-api-cache   # bound to managed-csi

Full walkthrough: docs/MULTICLOUD.md
EOF
