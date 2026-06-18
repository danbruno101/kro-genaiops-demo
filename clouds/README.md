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

A product team writes `instances/sentiment-api.yaml` once. It leaves
`storageClass` empty, so the PVC inherits **the cluster's default
StorageClass**. The platform team decides what that default *is* on each
cluster by applying the manifest in the matching folder here. The same
product YAML therefore lands on a "GKE" cluster and binds to `premium-rwo`,
or lands on an "AKS" cluster and binds to `managed-csi` — and the product
team never named a storage class, edited a manifest, or knew which cloud they
were on.

## What's in each folder

`storageclass.yaml` — a StorageClass named exactly what the real cloud calls
its default block storage (`premium-rwo` on GKE, `managed-csi` on AKS, `gp3`
on EKS), marked as the cluster's default class. In this *simulated* demo the
provisioner is kind's built-in `rancher.io/local-path` so it runs GPU- and
cloud-free; on a real cluster you'd swap the provisioner for the cloud's CSI
driver and the rest of the demo is unchanged. The name and the
"this is the default" decision are the parts the demo cares about.

## Adding a cloud

Drop in `clouds/<newcloud>/storageclass.yaml` and point `setup-multicloud.sh`
at it. No change to the RGD, no change to any instance. That's the whole point.
`clouds/eks/` is included as a worked example even though the demo only spins up
the GKE and AKS clusters.
