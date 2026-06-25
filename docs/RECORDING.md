# Recording the Demo — end-to-end script (multi-cloud, 100% KRO)

A self-contained script for **recording** the GenAIOps + KRO demo for the SIG
Cloud Provider talk. It leads with the cross-vendor portability story and the
"100% KRO" message — including the **EKS Auto Mode** angle.

The recording runs on **three local kind clusters that simulate GKE, AKS, and EKS**
(no cloud account, no GPU). For the *live, real-cluster* version see
`docs/PROVISION-REAL-CLUSTERS.md`; for the deeper two-use-case stage script see
`docs/RUNBOOK.md`.

> **The hook:** with KRO now owning the StorageClass (the `ClusterPlatform` RGD),
> the kind sims *show KRO minting the class live* (`managed-by: kro`) — that's
> **Segment 2.5**. EKS is the cloud that proves it: it ships no default class, so
> KRO **creates** `gp3` (Auto Mode provides the CSI driver) — **Segment 5**.

---

## Before you hit record

Panes: **LEFT** (you type), **RIGHT** (`watch`), **EDITOR** (repo open).

```bash
cd kro-genaiops-demo
./scripts/setup-multicloud.sh          # ~6 min: three kind clusters (gke + aks + eks sims)
kubectl config get-contexts -o name | grep kind-genaiops   # expect kind-genaiops-gke / -aks / -eks
```

---

## Segment 1 — The problem (30s, no typing)

Open `docs/before-raw-krm.yaml`, scroll slowly.

> "One model service in raw Kubernetes — PVC, Deployment, two Services, probes,
> Prometheus wiring. 92 lines. Multiply by every model, team, and cloud. That's the
> friction KRO removes."

---

## Segment 2 — Three clouds, one platform contract (45s)

```bash
for c in gke aks eks; do
  kubectl --context kind-genaiops-$c get nodes -L topology.kubernetes.io/region,demo.genaiops/cloud
done
kubectl --context kind-genaiops-gke get rgd     # ClusterPlatform + GenAIService — identical on all three
```

> "Three different environments. The same two platform APIs on each — a
> `ClusterPlatform` and a `GenAIService`. Both are just KRO."

---

## Segment 2.5 — Even the StorageClass is KRO (60s) ← the SIG hook

The "100% KRO" beat: the per-cluster storage config isn't hand-applied — KRO owns it.

```bash
# The ONE platform object per cluster — KRO expands it:
kubectl --context kind-genaiops-gke get clusterplatform
cat clouds/eks/platform.yaml          # ~6 lines: storageClass + manageStorageClass: true

# KRO created BOTH the ConfigMap AND the StorageClass on each cloud (managed-by: kro):
for c in gke aks eks; do
  echo -n "$c -> "
  kubectl --context kind-genaiops-$c get configmap genaiops-platform-config -o jsonpath='{.data.storageClass}'
  echo -n "  | sc managed-by: "
  kubectl --context kind-genaiops-$c get sc \
    -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/managed-by=="kro")].metadata.name}{"\n"}'
done
# gke -> premium-rwo | sc managed-by: premium-rwo   ... eks -> gp3 | sc managed-by: gp3
```

> "The only thing applied to these clusters is KRO. One `ClusterPlatform` object
> each, and KRO created the StorageClass and the config it resolves from —
> `managed-by: kro`. On EKS that's the whole point: a real EKS cluster ships no
> default class, so KRO *creates* `gp3` — no hand-applied StorageClass, no glue.
> Nothing in any of these clusters that isn't KRO."

---

## Segment 3 — Developer experience (90s) ← the payoff

LEFT:
```bash
cat instances/sentiment-api.yaml
kubectl --context kind-genaiops-gke apply -f instances/sentiment-api.yaml
```
RIGHT (start immediately):
```bash
watch -n1 'kubectl --context kind-genaiops-gke get genaiservice,deploy,svc,pvc -l app=sentiment-api'
```

> "One apply. KRO infers the graph — PVC, Deployment, Service, Prometheus wiring —
> in dependency order. The developer wrote none of it."

Prove the PVC bound to the KRO-created class, and that it serves:
```bash
kubectl --context kind-genaiops-gke get pvc sentiment-api-cache \
  -o jsonpath='{.spec.storageClassName}{"\n"}'                # premium-rwo
kubectl --context kind-genaiops-gke port-forward svc/sentiment-api 8080:80 &
curl -s localhost:8080/v1/chat/completions -X POST -d '{}' | jq .
kill %1
```

---

## Segment 4 — Move the workload across clouds (90s) ← the thesis

Same file. Different contexts. No edit:
```bash
kubectl --context kind-genaiops-aks apply -f instances/sentiment-api.yaml
kubectl --context kind-genaiops-eks apply -f instances/sentiment-api.yaml
for c in gke aks eks; do
  echo -n "$c -> "
  kubectl --context kind-genaiops-$c get pvc sentiment-api-cache \
    -o jsonpath='{.spec.storageClassName}{"\n"}'
done
# gke -> premium-rwo   aks -> managed-csi   eks -> gp3 (KRO-created)
```

> "Same nine-line spec, three contexts. It bound to `managed-csi` on AKS and `gp3`
> on EKS — and on EKS, KRO *created* that class. The developer YAML didn't change,
> the RGD didn't change. KRO resolved each cloud."

---

## Segment 5 — Why EKS is the proof, and how it's 100% KRO (45s, no typing) ← EKS Auto Mode

Open `clouds/gke/platform.yaml`, `clouds/aks/platform.yaml`, `clouds/eks/platform.yaml`
side by side. Point at `manageStorageClass`.

> "You just watched the same spec land on all three. Here's the cross-vendor
> punchline. On GKE and AKS the cloud already ships the class, so KRO references it
> — `manageStorageClass: false`. **EKS** ships no default class at all. That used to
> mean an out-of-band step: install the EBS CSI driver, wire up IAM, then create the
> class. Not KRO.
>
> EKS **Auto Mode** changes that: AWS bakes the EBS CSI driver into the managed
> nodes — no addon, no IRSA. And a StorageClass is just a Kubernetes object, so KRO
> creates it — `manageStorageClass: true`, which is exactly what you saw mint `gp3`
> on the EKS cluster a minute ago. On a real EKS Auto Mode cluster the only
> difference is the provisioner: `ebs.csi.eks.amazonaws.com`.
>
> So the bar is the same on all three: the only thing applied to the cluster is
> KRO. One developer YAML, one RGD — GKE, AKS, and EKS."

> Proof-without-a-cloud: "Our CI runs this exact path on kind — KRO mints a `gp3`
> class via a `ClusterPlatform` and binds an unchanged workload to it. Green on
> every commit."

---

## Segment 6 — Self-service catalog (45s)

```bash
kubectl --context kind-genaiops-gke apply -f instances/catalog.yaml
kubectl --context kind-genaiops-gke get genaiservice
```
Open `instances/catalog.yaml`:

> "Five teams, one template. To move any of these to a GPU node it's two field
> changes — `mode: gpu` and the cloud's `storageClass`. The YAML shape doesn't
> change. The RGD doesn't fork."

---

## Segment 7 — Clean up (15s)

```bash
kubectl --context kind-genaiops-gke delete -f instances/sentiment-api.yaml
kubectl --context kind-genaiops-gke get deploy,svc,pvc -l app=sentiment-api   # all gone
```

> "One object owns the whole graph — create and delete. No Go, no vendor SDK. KRO
> as the portability layer, all the way down to storage."

After recording:
```bash
./scripts/teardown-multicloud.sh
```

---

## If something breaks mid-recording

| Symptom | Fix |
|---|---|
| `ClusterPlatform`/`GenAIService` CRD not registered | `kubectl --context kind-genaiops-gke get rgd` — wait for `ACTIVE` (~15s after setup) |
| StorageClass / ConfigMap missing | re-apply the platform instance: `kubectl --context kind-genaiops-gke apply -f clouds/gke/platform.yaml`; check `kubectl --context kind-genaiops-gke get clusterplatform` |
| PVC stuck `Pending` | expected until a pod schedules (`WaitForFirstConsumer`); check the Deployment came up |
| `ImagePullBackOff` | `kind load docker-image ghcr.io/danbruno101/mock-vllm:demo --name genaiops-gke` |
| Total fallback | narrate from the files — `docs/before-raw-krm.yaml` vs `instances/sentiment-api.yaml` + `clouds/gke/platform.yaml` is the whole story |
