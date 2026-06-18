#!/usr/bin/env bash
# =============================================================================
# deploy-to-cluster.sh — install the GenAIOps platform onto an ALREADY-PROVISIONED
# cluster (real GKE / AKS, or anything reachable via a kubeconfig context).
#
# This is the REAL-CLOUD counterpart to setup-multicloud.sh (which creates local
# kind clusters). It assumes the cluster already exists and its context is in your
# kubeconfig. It does NOT create clusters, load images, or create StorageClasses —
# the per-cluster footprint is pure KRO:
#
#     helm install kro  +  the GenAIOps RGD  +  one ConfigMap KRO reads
#
# The mock workload image is pulled from GHCR (public), so nothing is `kind load`-ed.
# The named StorageClass (premium-rwo on GKE, managed-csi on AKS) already ships on
# the managed cluster; we only apply the ConfigMap that tells KRO to use it.
#
# Usage:
#   ./scripts/deploy-to-cluster.sh --context <kube-context> --cloud <gke|aks>
#
# Needs: kubectl, helm (and your cloud credentials already wired into the context).
# Idempotent. See docs/PROVISION-REAL-CLUSTERS.md for the morning-of runbook.
# =============================================================================
set -euo pipefail

KRO_VERSION="${KRO_VERSION:-}"   # empty = latest release
HERE="$(dirname "$0")"
REPO="${HERE}/.."

CTX=""
CLOUD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --context) CTX="$2"; shift 2 ;;
    --cloud)   CLOUD="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

say()  { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
note() { printf "  \033[2m%s\033[0m\n" "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

need kubectl; need helm

[ -n "${CTX}" ]   || { echo "Missing --context <kube-context>"; exit 1; }
[ -n "${CLOUD}" ] || { echo "Missing --cloud <gke|aks>"; exit 1; }

CFG="${REPO}/clouds/${CLOUD}/platform-config.yaml"
[ -f "${CFG}" ] || { echo "No platform config for cloud '${CLOUD}' at ${CFG}"; exit 1; }

say "[${CLOUD}] Deploying to context '${CTX}'"
note "Verifying the cluster is reachable"
kubectl --context "${CTX}" cluster-info >/dev/null \
  || { echo "Cannot reach context '${CTX}'. Is it in your kubeconfig and authenticated?"; exit 1; }

if [ -z "${KRO_VERSION}" ]; then
  KRO_VERSION="$(curl -sL https://api.github.com/repos/kubernetes-sigs/kro/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"
fi
note "Installing kro (official chart), version: ${KRO_VERSION:-<latest>}"
helm --kube-context "${CTX}" upgrade --install kro \
  oci://registry.k8s.io/kro/charts/kro \
  --namespace kro --create-namespace \
  ${KRO_VERSION:+--version "${KRO_VERSION}"} \
  --wait || note "kro may already be installed; continuing."
kubectl --context "${CTX}" wait --for=condition=Available deploy -n kro --all --timeout=180s || true

note "Applying platform config (the ConfigMap KRO reads to resolve StorageClass)"
kubectl --context "${CTX}" apply -f "${CFG}"
WANT_SC="$(kubectl --context "${CTX}" get configmap genaiops-platform-config \
  -o jsonpath='{.data.storageClass}' 2>/dev/null || true)"
if [ -n "${WANT_SC}" ]; then
  if kubectl --context "${CTX}" get storageclass "${WANT_SC}" >/dev/null 2>&1; then
    note "StorageClass '${WANT_SC}' is present on this cluster. ✓"
  else
    note "WARNING: StorageClass '${WANT_SC}' not found on '${CTX}'."
    note "         On managed GKE/AKS it ships by default; if missing, create it"
    note "         (or edit clouds/${CLOUD}/platform-config.yaml) before deploying a workload."
  fi
fi

note "Deploying Prometheus (shared monitoring infra)"
kubectl --context "${CTX}" apply -f "${REPO}/monitoring/prometheus.yaml"
kubectl --context "${CTX}" wait --for=condition=Available deploy/prometheus --timeout=180s || true

note "Applying the SAME GenAIOps RGD (identical on every cluster)"
kubectl --context "${CTX}" apply -f "${REPO}/rgd/genaiops-rgd.yaml"
for i in $(seq 1 30); do
  kubectl --context "${CTX}" get crd genaiservices.kro.run >/dev/null 2>&1 && break
  sleep 2
done

say "Ready on '${CTX}'. Deploy the unchanged developer spec with:"
cat <<EOF
  kubectl --context ${CTX} apply -f instances/sentiment-api.yaml
  kubectl --context ${CTX} get pvc sentiment-api-cache \\
    -o jsonpath='{.spec.storageClassName}{"\\n"}'   # -> ${WANT_SC:-<cluster default>}
EOF
