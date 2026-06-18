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
docker build -t genaiops/mock-vllm:demo "${MOCK_DIR}"
kind load docker-image genaiops/mock-vllm:demo --name "${CLUSTER}"

say "Deploying Prometheus (lightweight, for the monitoring beat)"
kubectl apply -f "$(dirname "$0")/../monitoring/prometheus.yaml"
kubectl wait --for=condition=Available deploy/prometheus --timeout=120s || true

say "Applying the GenAIOps ResourceGraphDefinition (platform team artifact)"
kubectl apply -f "$(dirname "$0")/../rgd/genaiops-rgd.yaml"

say "Waiting for the generated GenAIService CRD to register"
for i in $(seq 1 30); do
  if kubectl get crd genaiservices.kro.run >/dev/null 2>&1; then
    echo "GenAIService API is live."; break
  fi
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
