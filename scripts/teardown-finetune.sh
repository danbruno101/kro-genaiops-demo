#!/usr/bin/env bash
# =============================================================================
# teardown-finetune.sh — remove ONLY the second use-case (fine-tuning) without
# touching the GenAIService use-case or the cluster. Demonstrates that each
# use-case is independent and can be added/removed in isolation.
# =============================================================================
set -euo pipefail

CLUSTER="${CLUSTER:-genaiops-demo}"
kubectl config use-context "kind-${CLUSTER}" 2>/dev/null || true

HERE="$(dirname "$0")"

echo "Removing fine-tuning instances..."
kubectl delete -f "${HERE}/../instances/finetune-catalog.yaml" --ignore-not-found
kubectl delete -f "${HERE}/../instances/sentiment-finetune.yaml" --ignore-not-found
kubectl delete -f "${HERE}/../instances/fraud-finetune.yaml" --ignore-not-found

echo "Removing the FineTuneModel RGD (and its generated CRD)..."
kubectl delete -f "${HERE}/../rgd/finetune-rgd.yaml" --ignore-not-found

echo "Removing MLflow..."
kubectl delete -f "${HERE}/../monitoring/mlflow.yaml" --ignore-not-found

echo "Done. The GenAIService use-case is untouched."
