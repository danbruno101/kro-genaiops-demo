# Building a Cloud-Agnostic AIOps: Abstracting GenAI Infrastructure with KRM and KRO

[![demo-smoke-test](https://github.com/danbruno101/kro-genaiops-demo/actions/workflows/demo-smoke-test.yaml/badge.svg)](https://github.com/danbruno101/kro-genaiops-demo/actions/workflows/demo-smoke-test.yaml)

Demo companion for the KubeCon NA talk. A self-contained, laptop-runnable proof
that **KRO can be a portability layer for GenAI infrastructure**: one template,
one 10-line developer YAML, identical behavior across kind / EKS / GKE / AKS.

The GenAI payload (a vLLM-compatible server) is deliberately boring so the star
of the demo is KRO and the single reusable workflow — not the ML.

> **Status:** demo / proof-of-concept for a KubeCon NA talk. Built on kro
> `v1alpha1`. **Not intended for production use.** Shared with SIG Cloud
> Provider in response to talk feedback requesting a working demo.

## For SIG Cloud Provider reviewers — start here

Thanks for the earlier feedback. You asked for a demo; this is it. If you have
five minutes, look at these three things in order:

1. **`rgd/genaiops-rgd.yaml`** — the whole abstraction. One
   `ResourceGraphDefinition` exposes a `GenAIService` API and expands it into a
   PVC, Deployment, Service, and monitoring wiring. The portability mechanism is
   the CEL conditionals on `mode` and `storageClass` (e.g. the GPU resource
   limit and the storageClassName are folded into the template, not the
   instance). No custom Go controller anywhere in this repo.
2. **`instances/sentiment-api.yaml` vs `docs/before-raw-krm.yaml`** — the
   developer experience (9 lines of real config) against the raw KRM it replaces
   (92 lines across 5 resources). This is the cognitive-load claim, made
   checkable.
3. **`instances/catalog.yaml`** — the same template instantiated for kind / EKS
   / GKE / AKS profiles. The only thing that differs between clouds is the
   *value* of `mode` and `storageClass`; the YAML shape and the RGD are
   unchanged. This is the portability claim, made checkable.

**Run it:** `./scripts/setup.sh` stands up a kind cluster, installs kro, applies
the RGD, and registers the `GenAIService` API in ~2 minutes (needs docker, kind,
kubectl, helm). Then follow `docs/RUNBOOK.md`. You don't have to take our word
that it works — the `demo-smoke-test` CI (badge above) runs exactly this flow on
every push: it installs kro from the official `registry.k8s.io/kro/charts/kro`
chart, applies the RGD, creates a `GenAIService`, and asserts kro reconciled the
PVC, Deployment, both Services, and the right replica count.

**Feedback most useful to us:** whether the CEL-based environment branching is
the idiomatic kro pattern for cross-cloud portability, or whether there's a
cleaner approach the SIG would recommend; and whether anything here would break
against the current kro release. CI is pinned to a known-good release
(`v0.9.1`); `setup.sh` resolves the latest release at run time, so if a newer
kro has landed and broken something, the local run will surface it — see the
note at the bottom.

## What's here

| Path | Role in the talk |
|------|------------------|
| `rgd/genaiops-rgd.yaml` | **Use-case 1 platform artifact.** Defines the `GenAIService` (serving) API via one ResourceGraphDefinition. |
| `instances/sentiment-api.yaml` | **The developer experience.** 9 lines of real config. The payoff. |
| `instances/catalog.yaml` | **Self-service catalog.** Three teams, one template — the portability thesis. |
| `docs/before-raw-krm.yaml` | **The "before."** 92 lines of raw KRM the template replaces. |
| `rgd/finetune-rgd.yaml` | **Use-case 2 platform artifact.** Defines the `FineTuneModel` (train → register → gate → serve → drift) API. |
| `instances/sentiment-finetune.yaml` / `fraud-finetune.yaml` | Fine-tuning developer experience — auto-approval and the manual gate. |
| `instances/finetune-catalog.yaml` | Fine-tuning self-service catalog — the portability thesis for use-case 2. |
| `docs/before-raw-finetune-krm.yaml` | The raw KRM the `FineTuneModel` template replaces. |
| `docs/ADDING-A-USE-CASE.md` | **The module convention.** How a use-case 3 drops in without touching 1 or 2. |
| `monitoring/` | Lightweight Prometheus, MLflow, and the mock-vllm / mock-trainer / mock-drift image sources. |
| `scripts/setup.sh` / `teardown.sh` | One-command cluster up/down for use-case 1 (kind). |
| `scripts/setup-finetune.sh` / `teardown-finetune.sh` | Layered up/down for use-case 2 (additive, independent). |
| `scripts/setup-multicloud.sh` / `teardown-multicloud.sh` | **The portability thesis, live.** Stands up two kind clusters that stand in for two clouds (GKE / AKS) and moves the same workload between them. |
| `clouds/` | **Platform-team environment config.** The only place cloud details live (per-cluster default StorageClass) — never the RGD, never an instance. See `clouds/README.md`. |
| `docs/MULTICLOUD.md` | **Minute-by-minute multi-cloud runbook.** Deploy one spec to "GKE", move it to "AKS", no diff. |
| `docs/RUNBOOK.md` | **Minute-by-minute stage script.** Read this before presenting. |
| `genaiops-kro-deck.pptx` | KubeCon talk deck (use-case 1): impact slide + two-panel architecture diagram (kind / EKS / GKE / AKS). |
| `docs/maintainers-summit-deck.md` | Maintainers Summit deck (both use-cases), Marp source. Render: `npx --yes @marp-team/marp-cli@latest docs/maintainers-summit-deck.md -o deck.pptx`. |

## The contrast, in numbers

- Raw KRM a developer would hand-write: **92 lines** across 5 resources (and that's
  before HPA/PDB/ServiceMonitor/per-cloud variants).
- With the template: **9 lines**, zero Kubernetes objects authored by the developer.

## Quick start

```bash
# Requires: docker, kind, kubectl, helm
./scripts/setup.sh
kubectl apply -f instances/sentiment-api.yaml
kubectl get genaiservice sentiment-api -w
```

Then follow `docs/RUNBOOK.md` for the full demo flow.

## Second use-case: fine-tuning (`FineTuneModel`)

The same pattern generalizes beyond serving. A second, **independent**
ResourceGraphDefinition (`rgd/finetune-rgd.yaml`) gives product teams the whole
fine-tuning lifecycle from ~10 lines of YAML:

1. a **training run** whose infrastructure they pick (`trainMode` mock↔gpu,
   `epochs`),
2. **Apache MLflow** registering the run, its metrics, and the produced model
   (deployed once as shared platform infra, `monitoring/mlflow.yaml`),
3. an **evaluation + approval gate** — `approvalPolicy: auto` promotes the model
   to serving only if `eval_accuracy >= evalThreshold`; `approvalPolicy: manual`
   (the default guardrail) keeps serving at **0 replicas** until a data scientist
   reviews the metrics in MLflow and sets `approved: true`,
4. **serving** of the fine-tuned model (only once approved),
5. **drift detection** once live (`genaiops_drift_score`), and
6. **Prometheus** observability — auto-scraped via the same annotations, no
   Prometheus config change.

The approval gate is the compliance story made concrete: promotion to production
is an explicit, auditable one-field change, not a side effect of training. In
auto mode the train+eval Job performs that change itself (PATCHing the instance
via a least-privilege ServiceAccount) only when the model clears the bar.

Portability carries over unchanged: `instances/finetune-catalog.yaml` runs the
*same* `FineTuneModel` template across kind / EKS / GKE / AKS profiles, with only
`trainMode` / `servingMode` and `storageClass` differing. The control plane
(MLflow at `http://mlflow:5000`, Prometheus) is identical on every cloud.

Compare `instances/sentiment-finetune.yaml` (~10 lines) against
`docs/before-raw-finetune-krm.yaml` (the raw KRM — a Job, RBAC, a PVC, two
Deployments, two Services, MLflow wiring, and hand-gated approval) for the
cognitive-load contrast.

### Independence (and no vendor lock-in)

Each use-case is its own CRD with its own kro controller; adding or deleting one
RGD has zero effect on the other. `setup.sh` (use-case 1) has **no** dependency
on MLflow or the fine-tuning RGD. This is how teams self-onboard on a vendor-
neutral platform — see `docs/ADDING-A-USE-CASE.md` for the template a future
use-case 3 follows without touching use-cases 1 or 2.

## Running the demos

Each use-case runs independently, so you can show one or both:

```bash
# Use-case 1 only (the KubeCon talk — simplest):
./scripts/setup.sh

# Both use-cases (the Maintainer Summit — adds MLflow + fine-tuning + drift):
./scripts/setup.sh && ./scripts/setup-finetune.sh
```

`scripts/setup-finetune.sh` is additive and idempotent; `scripts/teardown-finetune.sh`
removes just use-case 2 (instances, RGD, MLflow) without touching use-case 1 or
the cluster.

## Simulating multi-cloud locally (deploy to "GKE" and "AKS")

The headline takeaway — *deploy the same solution to multiple clouds* — is now
runnable on a laptop, no cloud account or GPU required:

```bash
./scripts/setup-multicloud.sh
# Product team ships one spec — names no cloud, no storage class:
kubectl --context kind-genaiops-gke apply -f instances/sentiment-api.yaml   # binds premium-rwo
# Platform team moves the SAME spec to the other cloud — no edit:
kubectl --context kind-genaiops-aks apply -f instances/sentiment-api.yaml   # binds managed-csi
```

It stands up **two kind clusters that stand in for two clouds**
(`kind-genaiops-gke`, `kind-genaiops-aks`). The clean separation is the whole
point:

- **Product teams** ship one ~9-line instance and never name a cloud or a
  StorageClass — so they never think about where it runs.
- **The platform team** owns the environment: each cluster's *default*
  StorageClass is set from `clouds/<cloud>/` (`premium-rwo` for GKE,
  `managed-csi` for AKS). Moving a workload to another cloud is switching the
  `kubectl --context`; the spec and the RGD don't change.

The cloud-specific detail is isolated to `clouds/` (platform-team owned) — it
never leaks into the RGD or any instance. Follow `docs/MULTICLOUD.md` for the
staged walkthrough, and `clouds/README.md` for how to add a third cloud (EKS is
included as a worked example). To run against *real* GKE/AKS clusters, swap the
StorageClass provisioner for the cloud's CSI driver and point the same RGD and
instance at that kubeconfig context.

## How portability actually works here

The RGD exposes `mode` (`mock`|`gpu`) and `storageClass` as **schema fields**.
Moving from a laptop to an EKS, GKE, or AKS GPU node means changing those
*values* in the
10-line instance — not editing manifests, not re-templating, not forking the RGD.
CEL conditionals in the RGD (`${schema.spec.mode == "gpu" ? ... : ...}`) fold the
environment differences into the template once, so developers never see them.

## Notes

- kro API: `kro.run/v1alpha1`, `kind: ResourceGraphDefinition` (alpha).
- **kro version:** CI is pinned to `v0.9.1` (chart `0.9.1`) via `KRO_VERSION` in
  `.github/workflows/demo-smoke-test.yaml` for deterministic runs. To bump,
  change that value after confirming the demo still reconciles on the new
  release. `scripts/setup.sh` resolves the latest release at run time unless you
  export `KRO_VERSION=<x.y.z>` before running it (pin it on stage if you want
  reproducibility).
- `mock-vllm` is stdlib-only Python; it serves `/health`, `/metrics`, and
  `/v1/chat/completions` so the demo runs GPU-free. In `gpu` mode the RGD swaps
  in `vllm/vllm-openai` with no other changes.
