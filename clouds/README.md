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

`storageclass.yaml` — a StorageClass named exactly what the real cloud calls
its default block storage (`premium-rwo` on GKE, `managed-csi` on AKS, `gp3`
on EKS). In this *simulated* demo the provisioner is kind's built-in
`rancher.io/local-path` so it runs GPU- and cloud-free; on a real cluster you'd
swap the provisioner for the cloud's CSI driver and the rest of the demo is
unchanged. (`clouds/kind/` has none — kind already ships `standard`.)

`platform-config.yaml` — the `genaiops-platform-config` ConfigMap KRO reads via
`externalRef`. Its `storageClass` value is what every GenAIService on that
cluster uses. This is the object that actually drives KRO's per-cluster
resolution; `storageclass.yaml` just makes sure the class it names exists.

## Adding a cloud

Drop in `clouds/<newcloud>/{storageclass,platform-config}.yaml` and point
`setup-multicloud.sh` at it. No change to the RGD, no change to any instance.
That's the whole point. `clouds/eks/` is included as a worked example even
though the demo only spins up the GKE and AKS clusters.
