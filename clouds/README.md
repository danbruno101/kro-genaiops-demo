# `clouds/` — platform-team, per-cluster environment config

This directory is where **environment details live**: one folder per cloud, each
holding the Kubernetes objects the *platform team* applies to a cluster to make
it behave like that cloud.

It exists to keep the demo's central rule honest:

> Environment specifics never leak into the `ResourceGraphDefinition`
> (`rgd/`) or into a product team's instance (`instances/`). They live here,
> owned by the platform team, applied per cluster.

## The division of labor

| Who | Owns | Artifact |
|-----|------|----------|
| Platform team | The *environment* (which cloud, which StorageClass, which region) | `clouds/<cloud>/*` + the RGD |
| Product team | The *workload* (a model service, ~9 lines) | `instances/*` |

A product team writes `instances/sentiment-api.yaml` once and leaves
`storageClass` empty. **KRO** resolves the real value per cluster: the RGD
reads `genaiops-platform-config` (this folder's ConfigMap) as a read-only
`externalRef` and folds its `storageClass` into the PVC. The platform team sets
that value per cluster by applying the manifests in the matching folder here.
The same product YAML therefore lands on a "GKE" cluster and binds to
`premium-rwo`, or on an "AKS" cluster and binds to `managed-csi` — and the
product team never named a storage class, edited a manifest, or knew which
cloud they were on.

> **Why a ConfigMap and not just the cluster's default StorageClass?** Both
> work, but the ConfigMap makes KRO — not an implicit Kubernetes default — the
> thing that resolves the environment, keeps the platform's intent explicit and
> auditable (`kubectl get configmap genaiops-platform-config`), and decouples
> "the class GenAI workloads use" from "the cluster-wide default class." The
> resolution precedence is: developer override (`spec.storageClass`) → this
> ConfigMap's value → cluster default (when both are empty).

## What's in each folder

`platform.yaml` — a single **`ClusterPlatform`** instance (the API defined by
`rgd/platform-rgd.yaml`). KRO expands it into the per-cluster environment config,
so the StorageClass and the ConfigMap are **KRO-owned**, not hand-applied. It
carries:

- `storageClass` — the class name GenAI workloads use here (`premium-rwo` on GKE,
  `managed-csi` on AKS, `gp3` on EKS). Written into the `genaiops-platform-config`
  ConfigMap that the GenAIService RGD reads via `externalRef`.
- `manageStorageClass` — **the cross-cloud toggle.** `false` where the cloud
  already ships the class (real GKE/AKS) so KRO just *references* it (creating it
  would collide); `true` where it doesn't (EKS — even Auto Mode ships no class, only
  the built-in CSI driver) so KRO *creates* it. A StorageClass is a plain K8s
  object, so KRO can own it.
- `provisioner` / `volumeType` / `encrypted` — used only when KRO creates the
  class. The committed files use kind's `rancher.io/local-path` so the *simulated*
  demo runs cloud-free; real provisioners (`pd.csi.storage.gke.io`,
  `disk.csi.azure.com`, `ebs.csi.eks.amazonaws.com`) are applied by
  `scripts/deploy-to-cluster.sh` / documented in `docs/PROVISION-REAL-CLUSTERS.md`.

Net: the **only** thing applied to a cluster is KRO — kro itself, the RGDs, this
one `ClusterPlatform` instance, and the developer instances. 100% KRO.

## Adding a cloud

Drop in `clouds/<newcloud>/platform.yaml` (one `ClusterPlatform` instance) and
point `setup-multicloud.sh` at it. No change to the RGD, no change to any instance.
That's the whole point. `clouds/eks/` is included as a worked example even though
the local demo only spins up the GKE and AKS sims.
