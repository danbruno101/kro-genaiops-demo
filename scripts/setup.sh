#!/usr/bin/env bash
# =============================================================================
# setup.sh — stand up the entire demo on a laptop in ~2 minutes.
# Idempotent: safe to re-run. Run this the night before AND morning of the talk.
# =============================================================================
set -euo pipefail

CLUSTER="${CLUSTER:-genaiops-demo}"
KRO_VERSION="${KRO_VERSION:-}"   # empty = latest release

say() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

need kind; need kubectl; need helm

say "Creating kind cluster: ${CLUSTER}"
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  kind create cluster --name "${CLUSTER}" --wait 60s
else
  echo "Cluster already exists, reusing."
fi
kubectl config use-context "kind-${CLUSTER}"

say "Installing kro controller via Helm (official chart)"
# Canonical install per kro.run docs / kubernetes-sigs/kro.
# Resolve the latest release tag unless KRO_VERSION is pinned.
if [ -z "${KRO_VERSION}" ]; then
  KRO_VERSION="$(curl -sL https://api.github.com/repos/kubernetes-sigs/kro/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"
fi
echo "Using kro version: ${KRO_VERSION:-<latest-resolved-failed>}"
helm install kro oci://registry.k8s.io/kro/charts/kro \
  --namespace kro --create-namespace \
  ${KRO_VERSION:+--version "${KRO_VERSION}"} \
  --wait || echo "kro may already be installed; continuing."

say "Waiting for kro controller to be Ready"
kubectl wait --for=condition=Available deploy -n kro --all --timeout=120s || true

say "Building and loading the mock-vllm image into kind"
MOCK_DIR="$(dirname "$0")/../monitoring/mock-vllm"
docker build -t ghcr.io/danbruno101/mock-vllm:demo "${MOCK_DIR}"
kind load docker-image ghcr.io/danbruno101/mock-vllm:demo --name "${CLUSTER}"

say "Deploying Prometheus (lightweight, for the monitoring beat)"
kubectl apply -f "$(dirname "$0")/../monitoring/prometheus.yaml"
kubectl wait --for=condition=Available deploy/prometheus --timeout=120s || true

REPO="$(dirname "$0")/.."

say "Applying the platform RGDs (platform team artifacts)"
# ClusterPlatform: KRO owns the per-cluster env config (the genaiops-platform-config
# ConfigMap, and the StorageClass where the cloud doesn't ship one). GenAIService:
# the developer-facing serving API, which READS that ConfigMap via externalRef.
kubectl apply -f "${REPO}/rgd/platform-rgd.yaml"
kubectl apply -f "${REPO}/rgd/genaiops-rgd.yaml"

say "Waiting for the generated CRDs to register"
for i in $(seq 1 30); do
  if kubectl get crd clusterplatforms.kro.run genaiservices.kro.run >/dev/null 2>&1; then
    echo "ClusterPlatform + GenAIService APIs are live."; break
  fi
  sleep 2
done

say "Applying the ClusterPlatform instance (KRO creates the platform config)"
# On a laptop kind cluster this just creates genaiops-platform-config with an
# empty storageClass (inherit kind's default). KRO -- not a hand-applied manifest
# -- now owns it. Wait for it before any GenAIService reconciles (externalRef).
kubectl apply -f "${REPO}/clouds/kind/platform.yaml"
for i in $(seq 1 30); do
  kubectl get configmap genaiops-platform-config >/dev/null 2>&1 && break
  sleep 2
done

say "Setup complete. The new API is ready:"
kubectl get rgd
echo
echo "Next, demo the developer experience with:"
echo "  kubectl apply -f instances/sentiment-api.yaml"
echo "  kubectl get genaiservice sentiment-api -w"
echo
echo "Want the second use-case (fine-tuning + MLflow + drift)? Layer it on with:"
echo "  ./scripts/setup-finetune.sh"
