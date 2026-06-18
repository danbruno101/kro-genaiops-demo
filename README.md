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
| `rgd/genaiops-rgd.yaml` | **Platform team artifact.** Defines the `GenAIService` API via one ResourceGraphDefinition. |
| `instances/sentiment-api.yaml` | **The developer experience.** 9 lines of real config. The payoff. |
| `instances/catalog.yaml` | **Self-service catalog.** Three teams, one template — the portability thesis. |
| `docs/before-raw-krm.yaml` | **The "before."** 92 lines of raw KRM the template replaces. |
| `monitoring/` | Lightweight Prometheus + the mock-vllm image source. |
| `scripts/setup.sh` / `teardown.sh` | One-command cluster up/down (kind). |
| `docs/RUNBOOK.md` | **Minute-by-minute stage script.** Read this before presenting. |
| `genaiops-kro-deck.pptx` | Talk deck: impact slide + two-panel architecture diagram (kind / EKS / GKE / AKS). |

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
