# Multi-Cloud Demo — "It Just Works on Any Cloud"

**Thesis on stage:** *Product teams ship one spec and never think about where it
runs. The platform team moves the workload to any cluster on any cloud, and it
just works — same RGD, same instance, zero diff.*

This walkthrough simulates **three clouds with three local `kind` clusters**:

| Context | Plays the role of | StorageClass KRO resolves | Who creates the class |
|---------|-------------------|---------------------------|-----------------------|
| `kind-genaiops-gke` | GKE | `premium-rwo` | KRO (real GKE: ships it) |
| `kind-genaiops-aks` | AKS | `managed-csi` | KRO (real AKS: ships it) |
| `kind-genaiops-eks` | EKS | `gp3` | **KRO** (real EKS ships none; Auto Mode provides the CSI driver) |

The *only* thing that makes one cluster "GKE", another "AKS", another "EKS" is the
platform-team config in `clouds/<cloud>/platform.yaml`: a single `ClusterPlatform`
instance that **KRO** expands into that cluster's StorageClass *and* its
`genaiops-platform-config` ConfigMap. The GenAIService RGD reads that ConfigMap (a
read-only `externalRef`) and folds its `storageClass` into each workload's PVC — so
KRO does the per-cluster resolution, and KRO owns the config it resolves from. Both
`ResourceGraphDefinition`s are byte-identical on all three clusters. The product
instance is byte-identical on all three.

> **100% KRO.** The only thing applied to each cluster is KRO — kro itself, the
> RGDs, one `ClusterPlatform` instance, and the developer instances. Where the cloud
> ships the class (GKE/AKS) KRO references it; where it doesn't (**EKS** — even Auto
> Mode ships only the built-in EBS CSI *driver*) KRO **creates** it. Nothing is
> hand-applied.

> Everything runs GPU-free on a laptop. On real clusters the only change is the
> StorageClass provisioner (CSI driver); see `clouds/README.md`.

> **Live demo on real clusters?** The contexts below (`kind-genaiops-gke/aks/eks`)
> are the local/CI flow. For the real-cloud live demo, provision GKE + AKS + EKS
> (Auto Mode) per `docs/PROVISION-REAL-CLUSTERS.md` (which names the contexts
> **`gke`**, **`aks`**, **`eks`**) and run `./scripts/deploy-multicloud-real.sh`
> (it deploys to all three, skipping any context you didn't provision). Every beat
> after that is identical — just use the real contexts in place of the
> `kind-genaiops-*` ones.

---

## T-minus (before you walk on)

```bash
./scripts/setup-multicloud.sh        # ~6 min: three kind clusters, kro + RGDs on each
```

Confirm all three clouds are live:
```bash
kubectl config get-contexts -o name | grep kind-genaiops
```

---

## Beat 1 — Three clusters, three clouds (45s)

Show that the clusters are genuinely different *environments*, labeled like real
cloud nodes:
```bash
for c in gke aks eks; do
  kubectl --context kind-genaiops-$c get nodes -L topology.kubernetes.io/region,demo.genaiops/cloud
done
```

Now show the one platform-owned difference that matters — the storage choice
KRO will read for each cluster:
```bash
for c in gke aks eks; do
  echo -n "$c -> "
  kubectl --context kind-genaiops-$c get configmap genaiops-platform-config -o jsonpath='{.data.storageClass}{"\n"}'
done
# gke -> premium-rwo   aks -> managed-csi   eks -> gp3
```
> "Three clouds. Each names its own storage class — exactly what that cloud calls
> it — in a ConfigMap the platform team owns. It lives in `clouds/`, not in any
> template a developer touches. The RGD *reads* this; that's how KRO resolves the
> environment per cluster."

And — the 100%-KRO point — KRO *created* each of those classes, not a hand-applied
manifest:
```bash
for c in gke aks eks; do
  kubectl --context kind-genaiops-$c get sc -L app.kubernetes.io/managed-by | grep -E 'NAME|kro'
done
```
> "On EKS this is the one that matters: a real EKS cluster ships no default class.
> Auto Mode gives you the EBS CSI driver built in, and KRO creates the `gp3` class
> itself — `managed-by: kro`. Same on all three: nothing applied but KRO."

And the platform contract is the *same* on both:
```bash
kubectl --context kind-genaiops-gke get rgd
kubectl --context kind-genaiops-aks get rgd     # identical GenAIService API
```

---

## Beat 2 — Product team ships one spec (90s) ← the payoff

The product team's file names no cloud and no storage class. Show it:
```bash
cat instances/sentiment-api.yaml      # no storageClass field at all
```

Deploy it to the "GKE" cloud:
```bash
kubectl --context kind-genaiops-gke apply -f instances/sentiment-api.yaml
kubectl --context kind-genaiops-gke get genaiservice,deploy,svc,pvc -l app=sentiment-api
```

Prove the PVC bound to **GKE's** storage — which the product team never named:
```bash
kubectl --context kind-genaiops-gke get pvc sentiment-api-cache \
  -o jsonpath='{.spec.storageClassName}{"\n"}'      # -> premium-rwo
```
> "The instance left storage unspecified, so KRO resolved it from this cluster's
> platform ConfigMap. On this cloud that's `premium-rwo`. The developer never knew."

---

## Beat 3 — Platform moves the workload across clouds (90s) ← the thesis

Same file. Different cloud. No edit:
```bash
kubectl --context kind-genaiops-aks apply -f instances/sentiment-api.yaml
kubectl --context kind-genaiops-aks get pvc sentiment-api-cache \
  -o jsonpath='{.spec.storageClassName}{"\n"}'      # -> managed-csi
```
> "I changed the *context* — the destination cloud — and nothing else. The same
> nine-line spec landed on AKS and bound to `managed-csi`. The product team did
> nothing. The RGD didn't change. That's KRO as the portability layer."

And the third cloud — **EKS**, the one with no default class. Same file again:
```bash
kubectl --context kind-genaiops-eks apply -f instances/sentiment-api.yaml
kubectl --context kind-genaiops-eks get pvc sentiment-api-cache \
  -o jsonpath='{.spec.storageClassName}{"\n"}'      # -> gp3 (the class KRO created)
```
> "Same spec, third cloud. It bound to `gp3` — and here KRO didn't just *resolve*
> the class, it *created* it. On a real EKS Auto Mode cluster that's the only
> difference: provisioner `ebs.csi.eks.amazonaws.com`. Still nothing applied but KRO."

Prove it actually serves on another cloud:
```bash
kubectl --context kind-genaiops-aks port-forward svc/sentiment-api 8080:80 &
curl -s localhost:8080/v1/chat/completions -X POST -d '{}' | jq .
kill %1
```

Side-by-side — the same object, healthy on all three clouds at once:
```bash
for c in gke aks eks; do
  echo "== $c =="; kubectl --context kind-genaiops-$c get genaiservice sentiment-api
done
```

---

## Beat 3.5 — Why this needs KRO (45s, no typing) ← the message to land

The skeptic's objection is *"I can `kubectl apply` the same YAML to two clusters,
or ship a Helm chart."* Here's why that's not the same thing — say all three:

1. **One object moves, not a pile.** Without KRO the workload is 5+ coupled
   resources (PVC, Deployment, two Services, monitoring). Moving it means applying
   them to cluster B in dependency order and deleting them from cluster A without
   orphaning the PVC. With KRO the workload *is* one `GenAIService`: one apply
   moves it, one delete reclaims the whole owned graph.

2. **The environment is resolved ON the target cluster — not baked into what you
   ship.** This is the one that beats Helm/Kustomize. Their portability is
   *client-side templating*: you render `values-gke` vs `values-aks` (or
   `overlays/gke` vs `overlays/aks`) **before** apply, so a *different* manifest
   lands on each cloud and you maintain N drifting per-cloud variants. With KRO
   you submit the **same** instance everywhere; the RGD running in-cluster plus
   the cluster's own defaults expand it locally. The move re-renders *nothing* —
   there was never a per-cloud render.

3. **It keeps reconciling — operator behavior, zero Go.** Helm/Kustomize are
   apply-time only; after the move they don't self-heal. KRO continuously
   converges each cluster to the declared graph, and the generated API is
   provably identical on both (`kubectl --context … explain genaiservice`) — which
   is *why* the move target is guaranteed to accept the same spec.

> "Without KRO, 'portable' means per-cloud manifests plus a runbook of applies.
> With KRO the workload is a single API object — one owner, one place where
> environment branching lives — so moving it is just submitting the same intent
> to a cluster that speaks the same API, and the cluster fills in its own truth."

**How the value gets resolved:** KRO reads the per-cluster
`genaiops-platform-config` ConfigMap (a read-only `externalRef` in the RGD) and
folds its `storageClass` into the PVC. So the resolution is KRO's, not an
implicit Kubernetes default — the same RGD and instance on every cluster, the
value supplied by a platform-owned object KRO consumes. The precedence is
developer override → platform ConfigMap → cluster default (when both empty), so
the zero-config path still works on a plain laptop kind cluster.

---

## Beat 4 — Where the cloud actually lives (30s, no typing)

Open these three, in order:
1. `instances/sentiment-api.yaml` — the product team. No cloud anywhere.
2. `rgd/genaiops-rgd.yaml` — the platform contract. No cloud-specific *values*;
   it just *reads* the platform ConfigMap (`externalRef`) and resolves the class.
3. `clouds/gke/platform.yaml` vs `clouds/aks/platform.yaml` vs
   `clouds/eks/platform.yaml` — **the only files that know about a cloud**: one
   `ClusterPlatform` instance each (note EKS sets `manageStorageClass: true` — KRO
   creates the class there), which KRO expands into that cluster's ConfigMap +
   StorageClass. They belong to the
   platform team — and they're KRO objects too, so nothing is hand-applied.

> "Environment detail didn't get pushed up to developers or baked into the
> template. It's isolated to one folder the platform team owns, and KRO reads it.
> Adding EKS is dropping in `clouds/eks/` — the RGD and every instance stay
> untouched."

---

## Land it / clean up

```bash
./scripts/teardown-multicloud.sh      # deletes both kind clusters
```

## If something breaks on stage

- **PVC stuck `Pending`:** that's expected until a pod is scheduled —
  `volumeBindingMode: WaitForFirstConsumer`. Check the Deployment came up:
  `kubectl --context kind-genaiops-gke get deploy -l app=sentiment-api`.
- **Wrong StorageClass on the PVC / GenAIService not reconciling:** the RGD's
  `externalRef` needs the ConfigMap to exist, which KRO creates from the
  `ClusterPlatform` instance. Re-apply it —
  `kubectl --context kind-genaiops-gke apply -f clouds/gke/platform.yaml` — and
  check the value KRO will read:
  `kubectl --context kind-genaiops-gke get configmap genaiops-platform-config -o jsonpath='{.data.storageClass}{"\n"}'`
  (and `kubectl --context kind-genaiops-gke get clusterplatform` to confirm it reconciled).
- **`ImagePullBackOff`:** the mock image didn't load. Re-run
  `kind load docker-image ghcr.io/danbruno101/mock-vllm:demo --name genaiops-gke`.
- **Total fallback:** this runbook narrates the whole flow without a live
  cluster — the contrast is in the files, not the demo gods.
