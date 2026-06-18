# Adding a use-case to the AIOps platform

This repo is built so that **each GenAI use-case is an independent module**. The
serving use-case (`GenAIService`) and the fine-tuning use-case (`FineTuneModel`)
share only the cluster, the kro controller, and idempotently-applied platform
infra. Adding or deleting one has **zero effect** on the others — exactly how
product teams self-onboard onto a real, vendor-neutral platform.

This is the payoff of doing it on vanilla Kubernetes + kro rather than a managed
platform (SageMaker, Vertex AI, …): a use-case is just a
`ResourceGraphDefinition` you apply to a conformant cluster. No proprietary
control plane, no lock-in, and the same artifact runs on kind / EKS / GKE / AKS.

## Why use-cases are independent

- Each use-case declares its **own CRD / API kind** (`genaiservices.kro.run`,
  `finetunemodels.kro.run`). kro starts a **separate dynamic controller** per
  CRD, so they don't share reconciliation state and can't collide.
- `kubectl delete -f rgd/<other>-rgd.yaml` removes only that use-case's CRD and
  instances. The rest of the platform keeps running.
- Setup is **layered**: `scripts/setup.sh` is the base + use-case 1;
  `scripts/setup-finetune.sh` adds use-case 2 on top. You run only what you need.
- CI runs a **separate job per use-case**, each on its own kind cluster, so one
  use-case's tests never gate another's.

## Checklist: drop in use-case 3 without touching 1 or 2

Replace `<uc>` with your use-case's short name (e.g. `rag`, `eval`, `guardrail`).

1. **RGD** — `rgd/<uc>-rgd.yaml`: one `ResourceGraphDefinition` declaring a
   **distinct** `kind` and CRD name. Model it on `rgd/finetune-rgd.yaml`. Keep
   the developer-facing SimpleSchema to ~10 lines of knobs; fold environment
   differences into CEL field-swaps (`${schema.spec.mode == "gpu" ? ... : ...}`).
2. **Instances** — `instances/<uc>-*.yaml`: at least one happy-path instance and
   an `<uc>-catalog.yaml` showing the same template across cloud profiles (the
   portability proof).
3. **Mock workloads** — `monitoring/<uc>-*/` with a stdlib-only `*.py` + a
   `Dockerfile` (clone the `mock-vllm` / `mock-trainer` pattern: no `pip
   install`, talk to anything over HTTP via `urllib`).
4. **Setup** — `scripts/setup-<uc>.sh`: layered and idempotent. Assume the base
   cluster from `setup.sh` exists; (re-)apply any shared infra idempotently
   (`kubectl apply` is safe to repeat). Add an optional
   `scripts/teardown-<uc>.sh` for isolated removal.
5. **CI** — add a `<uc>-smoke` job to
   `.github/workflows/demo-smoke-test.yaml` on its **own** cluster
   (`CLUSTER: genaiops-ci-<uc>`). Leave the other jobs untouched.
6. **Contrast** — `docs/before-raw-<uc>-krm.yaml`: the hand-written KRM your
   template replaces, to quantify the line-count reduction.
7. **Docs** — add a section to `README.md` and beats to `docs/RUNBOOK.md`.

## Independence rules (don't break the isolation)

- **Distinct CRD group/kind** per use-case. Never reuse another's `kind`.
- **Per-use-case-prefixed names** for anything cluster-scoped or shared. Per-
  instance resources should be named off `${schema.spec.name}` (as the existing
  RGDs do) so multiple instances — and multiple use-cases — never collide.
- **Shared platform infra stays singular and idempotent.** Prometheus and MLflow
  are deployed once and reused. If your use-case needs new shared infra, add it
  as its own idempotent manifest and `kubectl apply` it from your setup script;
  don't bake it into another use-case's path. (Note: `setup.sh` / use-case 1 has
  **no** dependency on MLflow — keep cross-use-case dependencies at zero.)
- **Never edit another use-case's files.** A new use-case is purely additive.
