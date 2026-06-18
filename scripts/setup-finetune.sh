#!/usr/bin/env bash
# =============================================================================
# setup-finetune.sh — layer the SECOND use-case (fine-tuning) on top of the base
# demo. Run scripts/setup.sh FIRST: this assumes the cluster, kro, Prometheus,
# and the mock-vllm image already exist.
#
# Use-cases are independent, so this is purely additive -- it never touches the
# GenAIService use-case. Idempotent: safe to re-run.
#
#   Maintainer Summit (both use-cases):  ./scripts/setup.sh && ./scripts/setup-finetune.sh
#   KubeCon talk (use-case 1 only):      ./scripts/setup.sh
# =============================================================================
set -euo pipefail

CLUSTER="${CLUSTER:-genaiops-demo}"

say() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

need kind; need kubectl; need docker

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  echo "Cluster '${CLUSTER}' not found. Run ./scripts/setup.sh first."; exit 1
fi
kubectl config use-context "kind-${CLUSTER}"

HERE="$(dirname "$0")"

say "Building and loading the mock-trainer and mock-drift images into kind"
docker build -t ghcr.io/danbruno101/mock-trainer:demo "${HERE}/../monitoring/mock-trainer"
docker build -t ghcr.io/danbruno101/mock-drift:demo "${HERE}/../monitoring/mock-drift"
kind load docker-image ghcr.io/danbruno101/mock-trainer:demo --name "${CLUSTER}"
kind load docker-image ghcr.io/danbruno101/mock-drift:demo --name "${CLUSTER}"

say "Deploying MLflow (shared platform infra: experiment tracking + model registry)"
kubectl apply -f "${HERE}/../monitoring/mlflow.yaml"
kubectl wait --for=condition=Available deploy/mlflow --timeout=180s || true

say "Applying the Fine-Tuning ResourceGraphDefinition (platform team artifact)"
kubectl apply -f "${HERE}/../rgd/finetune-rgd.yaml"

say "Waiting for the generated FineTuneModel CRD to register"
for i in $(seq 1 30); do
  if kubectl get crd finetunemodels.kro.run >/dev/null 2>&1; then
    echo "FineTuneModel API is live."; break
  fi
  sleep 2
done

say "Setup complete. The fine-tuning API is ready:"
kubectl get rgd
echo
echo "Next, demo the developer experience with:"
echo "  # auto-approval: trains, evaluates, and serves automatically on eval pass"
echo "  kubectl apply -f instances/sentiment-finetune.yaml"
echo "  kubectl get finetunemodel sentiment-tuned -w"
echo
echo "  # manual gate: serving stays at 0 until a data scientist approves"
echo "  kubectl apply -f instances/fraud-finetune.yaml"
echo "  kubectl patch finetunemodel fraud-tuned --type merge -p '{\"spec\":{\"approved\":true}}'"
