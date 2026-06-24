# Provisioning Real Clusters — runbook (GKE + AKS + EKS)

Stand up real managed clusters for the live demo, then deploy the unchanged
GenAIOps platform to each. Budget ~25–35 min (most of it is the clouds creating
the control planes).

> **Scope.** The demo's thesis is *workload portability across clusters*, not
> provisioning. So this runbook provisions plain clusters with the cloud CLIs;
> KRO's job starts once the clusters exist. Everything runs **CPU-only (mock
> mode)** — no GPU, no quota dance.

> **100% KRO in-cluster.** Once a cluster exists, the **only** thing applied to it
> is KRO: `helm install kro`, the two RGDs, one `ClusterPlatform` instance, and the
> developer instances. KRO owns the `genaiops-platform-config` ConfigMap and — where
> the cloud doesn't ship a class (EKS) — the StorageClass too. Nothing is
> `kubectl apply`-ed by hand. Cluster *creation* (gcloud/az/eksctl) is the only
> out-of-band step, and it's out-of-band on all three clouds equally.

The demo scripts assume the contexts are named **`gke`**, **`aks`**, **`eks`** —
the steps below rename them for you.

---

## 0. Prereqs (once)

Authenticated CLIs on your laptop:
- `gcloud` (logged in, a project set), `az` (logged in), `aws` + `eksctl`,
  `kubectl`, `helm`, `docker`.

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

GKE ships the `premium-rwo` StorageClass by default → the deploy uses
`manageStorageClass: false` and KRO just **references** it.

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

AKS ships the `managed-csi` StorageClass by default → `manageStorageClass: false`,
KRO **references** it.

---

## 3. EKS — via Auto Mode (this is the 100%-KRO unlock)

EKS ships **no** default StorageClass. **Auto Mode** bakes the EBS CSI **driver**
into the managed nodes (no addon to install, no IRSA) — removing the one piece KRO
couldn't own. The remaining StorageClass is a plain K8s object, so **KRO creates
it** (`manageStorageClass: true`, provisioner `ebs.csi.eks.amazonaws.com`). Result:
EKS reaches the same 100%-KRO bar as GKE/AKS.

```bash
# Auto Mode = built-in compute + storage (EBS CSI driver), AWS-managed.
eksctl create cluster --name genaiops-eks --region us-east-1 --enable-auto-mode
#   (no `eksctl create addon aws-ebs-csi-driver`, no IRSA — Auto Mode includes it.)

aws eks update-kubeconfig --region us-east-1 --name genaiops-eks
# get-credentials sets the context to the cluster ARN; normalize to `eks`:
kubectl config rename-context "$(kubectl config current-context)" eks
```

> Note: `deploy-to-cluster.sh --cloud eks` sets the **Auto Mode** provisioner
> `ebs.csi.eks.amazonaws.com` (not the self-managed `ebs.csi.aws.com`), with
> `type: gp3` and `encrypted: true` — and KRO creates the `gp3` class for you.

---

## 4. Deploy the platform to each (pure-KRO footprint)

GKE + AKS in one shot:
```bash
./scripts/deploy-multicloud-real.sh           # contexts gke, aks
```

EKS (Auto Mode → KRO creates the class):
```bash
./scripts/deploy-to-cluster.sh --context eks --cloud eks
```

Each call installs kro, applies the platform + workload RGDs, then applies a
`ClusterPlatform` instance: on GKE/AKS it owns the ConfigMap and references the
shipped class; on EKS it also **creates** the `gp3` class. No image loading (pods
pull from GHCR), nothing `kubectl`-applied but KRO objects.

---

## 5. Verify (do this before you present)

```bash
for c in gke aks eks; do
  echo "== $c =="
  kubectl --context $c get deploy -n kro                 # kro Ready
  kubectl --context $c get rgd                           # both RGDs ACTIVE
  kubectl --context $c get clusterplatform               # platform config reconciled
done

# Deploy the unchanged developer spec to each and confirm KRO resolves storage:
for c in gke aks eks; do
  kubectl --context $c apply -f instances/sentiment-api.yaml
  kubectl --context $c wait --for=condition=Available deploy/sentiment-api --timeout=180s
  kubectl --context $c get pvc sentiment-api-cache -o jsonpath="{.spec.storageClassName}{\"\n\"}"
done
# expect: gke -> premium-rwo,  aks -> managed-csi,  eks -> gp3 (KRO-created)
```

On EKS, confirm KRO created the class itself:
```bash
kubectl --context eks get storageclass gp3   # PROVISIONER ebs.csi.eks.amazonaws.com
```

If the PVCs show each cloud's class, you're ready. Run the live beats from
`docs/MULTICLOUD.md` — substitute the real contexts `gke` / `aks` / `eks` for the
`kind-genaiops-*` ones (the commands are otherwise identical).

> Reset between rehearsals: `kubectl --context <c> delete -f instances/sentiment-api.yaml`.

---

## 6. Teardown (stop billing!)

```bash
gcloud container clusters delete genaiops-gke --zone us-central1-a --quiet
az group delete --name genaiops-demo --yes --no-wait
eksctl delete cluster --name genaiops-eks --region us-east-1
```
