#!/usr/bin/env bash
# =============================================================================
# deploy-multicloud-real.sh — deploy the GenAIOps platform to the REAL GKE, AKS,
# and EKS clusters for the live demo, by calling deploy-to-cluster.sh for each.
#
# Assumes the clusters already exist and their kubeconfig contexts are named
# `gke`, `aks`, `eks` (see docs/PROVISION-REAL-CLUSTERS.md, which renames them for
# you). EKS should be an Auto Mode cluster so the EBS CSI driver is built in and
# KRO can create the gp3 StorageClass itself.
#
# Any cloud whose context isn't present in your kubeconfig is SKIPPED with a note,
# so this works whether you have all three or only a subset. Override context
# names via env:
#
#   GKE_CONTEXT=my-gke AKS_CONTEXT=my-aks EKS_CONTEXT=my-eks ./scripts/deploy-multicloud-real.sh
#
# Needs: kubectl, helm, cloud credentials wired into the contexts.
# =============================================================================
set -euo pipefail

HERE="$(dirname "$0")"
GKE_CONTEXT="${GKE_CONTEXT:-gke}"
AKS_CONTEXT="${AKS_CONTEXT:-aks}"
EKS_CONTEXT="${EKS_CONTEXT:-eks}"

# Each entry: "<context> <cloud>"
TARGETS=(
  "${GKE_CONTEXT} gke"
  "${AKS_CONTEXT} aks"
  "${EKS_CONTEXT} eks"
)

skip() { printf "  \033[2m%s\033[0m\n" "$*"; }
has_context() { kubectl config get-contexts -o name 2>/dev/null | grep -qx "$1"; }

deployed=()
for entry in "${TARGETS[@]}"; do
  # shellcheck disable=SC2086
  set -- ${entry}
  ctx="$1"; cloud="$2"
  if has_context "${ctx}"; then
    "${HERE}/deploy-to-cluster.sh" --context "${ctx}" --cloud "${cloud}"
    deployed+=("${ctx} ${cloud}")
  else
    skip "Skipping ${cloud}: kube-context '${ctx}' not found (set $(echo "${cloud}" | tr '[:lower:]' '[:upper:]')_CONTEXT or provision it)."
  fi
done

[ ${#deployed[@]} -gt 0 ] || { echo "No matching contexts found; nothing deployed."; exit 1; }

printf "\n\033[1;36m▶ Deployed to %d cloud(s). Show the thesis — same spec, every cloud:\033[0m\n\n" "${#deployed[@]}"
for entry in "${deployed[@]}"; do
  # shellcheck disable=SC2086
  set -- ${entry}
  ctx="$1"; cloud="$2"
  case "${cloud}" in
    gke) note="bound to premium-rwo" ;;
    aks) note="bound to managed-csi" ;;
    eks) note="bound to gp3 (the class KRO created)" ;;
    *)   note="" ;;
  esac
  printf "  kubectl --context %s apply -f instances/sentiment-api.yaml\n" "${ctx}"
  printf "  kubectl --context %s get pvc sentiment-api-cache   # %s\n\n" "${ctx}" "${note}"
done
echo "Full walkthrough: docs/MULTICLOUD.md"
