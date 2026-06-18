# Provisioning Real Clusters — morning-of runbook (GKE + AKS)

Run this the **morning of the talk** to stand up real managed clusters for the
live demo, then deploy the unchanged GenAIOps platform to both. Budget ~25–30 min
(most of it is the clouds creating the control planes).

> **Scope.** The demo's thesis is *workload portability across clusters*, not
> provisioning. So this runbook provisions plain clusters with the cloud CLIs;
> KRO's job starts once the clusters exist. Everything runs **CPU-only (mock
> mode)** — no GPU, no quota dance.

The demo scripts and `docs/MULTICLOUD.md` assume the two contexts are named
**`gke`** and **`aks`** — the steps below rename them for you.

---

## 0. Prereqs (once)

Authenticated CLIs on your laptop:
- `gcloud` (logged in, a project set), `az` (logged in), `kubectl`, `helm`, `docker`.

Confirm the mock image is public and pullable (it lives in GHCR; the
`publish-images` workflow pushes it). If this fails, make the GHCR packages public
— github.com/users/danbruno101/packages → each `mock-*` package → *Change
visibility → Public*:

```bash
docker pull ghcr.io/danbruno101/mock-vllm:demo
```

---

## 1. GKE

```bash
PROJECT="$(gcloud config get-value project)"
ZONE="us-central1-a"

gcloud container clusters create genaiops-gke \
  --zone "${ZONE}" --num-nodes 2 --machine-type e2-standard-4 \
  --release-channel regular

gcloud container clusters get-credentials genaiops-gke --zone "${ZONE}"
# Normalize the context name to `gke`:
kubectl config rename-context "gke_${PROJECT}_${ZONE}_genaiops-gke" gke
```

GKE ships the `premium-rwo` StorageClass by default — nothing to create.

---

## 2. AKS

```bash
az group create --name genaiops-demo --location eastus

az aks create --resource-group genaiops-demo --name genaiops-aks \
  --node-count 2 --node-vm-size Standard_DS3_v2 --generate-ssh-keys

az aks get-credentials --resource-group genaiops-demo --name genaiops-aks
# get-credentials creates a context named after the cluster; normalize to `aks`:
kubectl config rename-context genaiops-aks aks
```

AKS ships the `managed-csi` StorageClass by default — nothing to create.

---

## 3. Deploy the platform to both (pure-KRO footprint)

```bash
./scripts/deploy-multicloud-real.sh
```

This installs kro, applies the `genaiops-platform-config` ConfigMap (the only
per-cluster knob — names `premium-rwo` on GKE, `managed-csi` on AKS), Prometheus,
and the **same** RGD on each context. No image loading (pods pull from GHCR), no
StorageClass creation.

---

## 4. Verify (do this before you present)

```bash
for c in gke aks; do
  echo "== $c =="
  kubectl --context $c get deploy -n kro              # kro Ready
  kubectl --context $c get rgd                        # genaiservice.kro.run ACTIVE
done

# Deploy the unchanged developer spec to each and confirm KRO resolves storage:
for c in gke aks; do
  kubectl --context $c apply -f instances/sentiment-api.yaml
done
kubectl --context gke wait --for=condition=Available deploy/sentiment-api --timeout=180s
kubectl --context aks wait --for=condition=Available deploy/sentiment-api --timeout=180s

kubectl --context gke get pvc sentiment-api-cache -o jsonpath='{.spec.storageClassName}{"\n"}'  # premium-rwo
kubectl --context aks get pvc sentiment-api-cache -o jsonpath='{.spec.storageClassName}{"\n"}'  # managed-csi
```

If both PVCs show the cloud's class, you're ready. Run the live beats from
`docs/MULTICLOUD.md` — substitute the real contexts `gke` / `aks` for the
`kind-genaiops-*` ones (the commands are otherwise identical).

> Reset between rehearsals: `kubectl --context <c> delete -f instances/sentiment-api.yaml`.

---

## 5. Teardown (stop billing!)

```bash
gcloud container clusters delete genaiops-gke --zone us-central1-a --quiet
az group delete --name genaiops-demo --yes --no-wait
```

---

## Appendix — adding EKS (optional, extends the same way)

EKS is left out of the live run only because its `gp3` class isn't built in (it
needs the EBS CSI driver) — that's the one non-KRO setup step. The KRO side is
identical: `clouds/eks/platform-config.yaml` already names `gp3`.

```bash
eksctl create cluster --name genaiops-eks --region us-east-1 \
  --nodes 2 --node-type m5.xlarge --with-oidc

# Enable the EBS CSI driver, then create a gp3 StorageClass:
eksctl create addon --name aws-ebs-csi-driver --cluster genaiops-eks \
  --region us-east-1 --force

kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
YAML

kubectl config rename-context "$(kubectl config current-context)" eks
./scripts/deploy-to-cluster.sh --context eks --cloud eks
```

Teardown: `eksctl delete cluster --name genaiops-eks --region us-east-1`.
