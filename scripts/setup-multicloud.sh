#!/usr/bin/env bash
# =============================================================================
# setup-multicloud.sh — stand up THREE local clusters that stand in for three
# different clouds, and prove the portability thesis live:
#
#   "Product teams ship one spec and don't care where it runs. The platform
#    team moves the workload to any cluster on any cloud, and it just works."
#
# We simulate GKE / AKS / EKS with three kind clusters. The ONLY thing that makes
# one a "GKE", "AKS", or "EKS" cluster is platform-team config in
# clouds/<cloud>/platform.yaml — one ClusterPlatform instance KRO expands into the
# StorageClass (premium-rwo / managed-csi / gp3) and the platform ConfigMap. On the
# EKS sim KRO CREATES the class (real EKS ships none; Auto Mode provides the CSI
# driver). The RGDs are identical on all three. The product instance is identical
# on all three. Nothing about the cloud leaks into any of them.
#
# Idempotent: safe to re-run. Needs: docker, kind, kubectl, helm.
#
# Pair with docs/MULTICLOUD.md for the live runbook, and teardown-multicloud.sh
# to clean up.
# =============================================================================
set -euo pipefail

KRO_VERSION="${KRO_VERSION:-}"   # empty = latest release
HERE="$(dirname "$0")"
REPO="${HERE}/.."

# Each entry: "<kind-cluster-name> <cloud> <region>"
# <cloud> must match a folder name under clouds/.
CLUSTERS=(
  "genaiops-gke gke us-central1"
  "genaiops-aks aks eastus"
  "genaiops-eks eks us-east-1"
)

say()  { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
note() { printf "  \033[2m%s\033[0m\n" "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

need docker; need kind; need kubectl; need helm

# Resolve the kro release once, up front, so every cluster installs the same one.
if [ -z "${KRO_VERSION}" ]; then
  KRO_VERSION="$(curl -sL https://api.github.com/repos/kubernetes-sigs/kro/releases/latest \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"
fi
say "kro version for every cluster: ${KRO_VERSION:-<latest-resolve-failed>}"

# Build the mock-vllm image once; we load the same artifact into each cluster.
say "Building the mock-vllm image (built once, loaded into every cluster)"
docker build -t ghcr.io/danbruno101/mock-vllm:demo "${REPO}/monitoring/mock-vllm"

provision() {
  local cluster="$1" cloud="$2" region="$3"
  local ctx="kind-${cluster}"
  local platformfile="${REPO}/clouds/${cloud}/platform.yaml"

  [ -f "${platformfile}" ] || { echo "No platform config for cloud '${cloud}' at ${platformfile}"; exit 1; }

  say "[${cloud}] Cluster '${cluster}' (region ${region})"

  if ! kind get clusters 2>/dev/null | grep -qx "${cluster}"; then
    kind create cluster --name "${cluster}" --wait 60s
  else
    note "Cluster already exists, reusing."
  fi

  note "Tagging nodes with their (simulated) cloud and region"
  kubectl --context "${ctx}" label nodes --all \
    "demo.genaiops/cloud=${cloud}" "topology.kubernetes.io/region=${region}" \
    --overwrite >/dev/null

  note "Installing kro (official chart)"
  helm --kube-context "${ctx}" upgrade --install kro \
    oci://registry.k8s.io/kro/charts/kro \
    --namespace kro --create-namespace \
    ${KRO_VERSION:+--version "${KRO_VERSION}"} \
    --wait >/dev/null || note "kro may already be installed; continuing."
  kubectl --context "${ctx}" wait --for=condition=Available deploy -n kro --all --timeout=120s || true

  note "Loading the mock-vllm image into the cluster"
  kind load docker-image ghcr.io/danbruno101/mock-vllm:demo --name "${cluster}" >/dev/null

  note "Demoting kind's built-in 'standard' so the cloud-named class is the sole default"
  # Sim scaffolding only (real GKE/AKS have no kind 'standard'); PVCs name the
  # class explicitly via the ConfigMap, so this is cosmetic for `kubectl get sc`.
  if kubectl --context "${ctx}" get storageclass standard >/dev/null 2>&1; then
    kubectl --context "${ctx}" patch storageclass standard \
      -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' >/dev/null
  fi

  note "Applying the SAME platform + workload RGDs (identical on every cloud)"
  # ClusterPlatform: KRO owns this cluster's StorageClass + ConfigMap.
  # GenAIService: reads that ConfigMap via externalRef.
  kubectl --context "${ctx}" apply -f "${REPO}/rgd/platform-rgd.yaml" >/dev/null
  kubectl --context "${ctx}" apply -f "${REPO}/rgd/genaiops-rgd.yaml" >/dev/null
  for i in $(seq 1 30); do
    kubectl --context "${ctx}" get crd clusterplatforms.kro.run genaiservices.kro.run >/dev/null 2>&1 && break
    sleep 2
  done

  note "Applying PLATFORM-TEAM config: clouds/${cloud}/platform.yaml (KRO mints the class + ConfigMap)"
  kubectl --context "${ctx}" apply -f "${platformfile}" >/dev/null
  # Wait for KRO to create the ConfigMap (externalRef) and the named StorageClass
  # before any GenAIService reconciles.
  for i in $(seq 1 30); do
    kubectl --context "${ctx}" get configmap genaiops-platform-config >/dev/null 2>&1 && break
    sleep 2
  done

  note "Deploying Prometheus (monitoring beat)"
  kubectl --context "${ctx}" apply -f "${REPO}/monitoring/prometheus.yaml" >/dev/null
  kubectl --context "${ctx}" wait --for=condition=Available deploy/prometheus --timeout=120s || true

  note "Default StorageClass on ${ctx}:"
  kubectl --context "${ctx}" get storageclass \
    -o custom-columns='NAME:.metadata.name,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class' \
    2>/dev/null | sed 's/^/    /'
}

for entry in "${CLUSTERS[@]}"; do
  # shellcheck disable=SC2086
  provision ${entry}
done

say "Three clouds are live. Contexts:"
kubectl config get-contexts -o name | grep -E 'kind-genaiops-(gke|aks|eks)' | sed 's/^/  /'

cat <<'EOF'

The platform is ready on ALL THREE clusters. Now show the thesis:

  # Product team ships ONE spec — it never names a cloud or a StorageClass.
  kubectl --context kind-genaiops-gke apply -f instances/sentiment-api.yaml
  kubectl --context kind-genaiops-gke get pvc sentiment-api-cache   # bound to premium-rwo

  # Platform team MOVES the same workload to another cloud. Same file. No diff.
  kubectl --context kind-genaiops-aks apply -f instances/sentiment-api.yaml
  kubectl --context kind-genaiops-aks get pvc sentiment-api-cache   # bound to managed-csi

  # And EKS — where KRO CREATED the gp3 class itself (EKS ships none; Auto Mode
  # provides the CSI driver). Same file again, no diff.
  kubectl --context kind-genaiops-eks apply -f instances/sentiment-api.yaml
  kubectl --context kind-genaiops-eks get pvc sentiment-api-cache   # bound to gp3 (KRO-created)

Full walkthrough: docs/MULTICLOUD.md     Tear down: ./scripts/teardown-multicloud.sh
EOF
