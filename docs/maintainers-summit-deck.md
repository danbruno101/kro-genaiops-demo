---
marp: true
theme: default
size: 16:9
paginate: true
header: "GenAIOps on KRO"
footer: "KubeCon NA · Maintainers Summit"
---

<!--
Maintainers Summit deck (the "second deck"). Standalone superset of the
KubeCon main-session deck (docs/kubecon-deck.md): it keeps the serving story
(use-case 1) and adds the fine-tuning lifecycle (use-case 2).

Render locally:
  npx --yes @marp-team/marp-cli@latest docs/maintainers-summit-deck.md -o deck.pdf
  npx --yes @marp-team/marp-cli@latest docs/maintainers-summit-deck.md -o deck.pptx
  npx --yes @marp-team/marp-cli@latest docs/maintainers-summit-deck.md -o deck.html

Speaker notes live in HTML comments under each slide and track docs/RUNBOOK.md.
-->

# GenAIOps on KRO
## One template. Every cloud. Every use-case.

**Maintainers Summit** — the day before KubeCon NA

> One template. One ~10-line YAML. The same everywhere — kind · EKS · GKE · AKS.
> KRO is the portability layer; the LLM is just proof the layer holds.

<!--
This is the deeper, two-use-case session. The main-stage talk shows serving
(use-case 1). Today we keep that and add the full fine-tuning lifecycle
(use-case 2) — same KRO pattern, end to end.
-->

---

# Why KRO matters

- **Hours, not weeks** — build-your-own platform API with no custom Go operator.
- **Reduced cognitive load** — developers consume a 10-line API; the platform team encodes the resource graph **once**, not per team.
- **Portability, not vendor lock-in** — any K8s resource, native or CRD. Environment differences become **fields, not rewrites**.
- **Safe & predictable** — CEL is non-Turing-complete and validated at creation time. Errors caught before runtime, unlike Helm.
- **A cross-vendor standard** — AWS, Google & Microsoft on one project: rare credibility for a true portability layer.

<!--
Six value props from the KubeCon deck slide 1. Don't read them — land
"fields, not rewrites" and "encode the graph once." Maturity note lands at the
end, not here.
-->

---

# Use-case 1 — one object fans out into a managed graph

**The developer writes ~10 lines:**

```yaml
apiVersion: kro.run/v1alpha1
kind: GenAIService
metadata:
  name: sentiment-api
spec:
  name: sentiment-api
  model: Qwen2.5-0.5B
  replicas: 2
  mode: mock
  monitoring: true
```

**KRO infers the DAG → generates the CRD → reconciles at runtime, creating:**
`PersistentVolumeClaim` (model cache) · `Deployment` (vLLM-compatible, 2 replicas) · `Service` (stable endpoint) · `Metrics Service` (Prometheus scrape wiring)

> One object owns the whole graph — create and delete. No glue operator.

<!--
RUNBOOK Beats 1–3. The payoff is "one apply created the PVC, Deployment, both
Services, and wired Prometheus — in dependency order I never specified."
-->

---

# Use-case 1 — same template, every cluster

The **only** things that change between clouds are field **values** — not the YAML shape, not the RGD.

| Profile | mode | storageClass |
|---|---|---|
| **kind** — laptop · CPU | `mock` | *(default)* |
| **Amazon EKS** — GPU nodes | `gpu` | `gp3` |
| **Google GKE** — GPU nodes | `gpu` | `premium-rwo` |
| **Azure AKS** — GPU nodes | `gpu` | `managed-csi` |

**One ResourceGraphDefinition + one 10-line GenAIService — authored once, applied unchanged everywhere.**

**And it's 100% KRO on every cloud:** a one-per-cluster `ClusterPlatform` instance is KRO-owned, so KRO references the shipped class on GKE/AKS and *creates* it on EKS (Auto Mode bakes in the EBS CSI driver — the one piece KRO couldn't own). Nothing is hand-applied but KRO.

<!--
RUNBOOK Beat 4 (the thesis). Source: instances/catalog.yaml — five teams behind
one template. Move laptop -> hyperscaler by changing values in the 10-line file;
no re-templating, no fork of the RGD. The "only thing applied is KRO" line + EKS
Auto Mode is the SIG Cloud Provider hook.
-->

---

<!-- _class: lead -->

# Beyond serving

## The full GenAI lifecycle — the same KRO pattern

train → evaluate → register → **approval gate** → serve → drift

<!--
Transition. Use-case 2 is a *separate, independent* RGD (FineTuneModel). It is
not an extension of GenAIService — it's a second module that proves the pattern
generalizes from a single workload to a whole MLOps lifecycle.
-->

---

# Use-case 2 — `FineTuneModel`: one object, the whole MLOps lifecycle

**Still ~10 lines. The developer never sees KRM:**

```yaml
apiVersion: kro.run/v1alpha1
kind: FineTuneModel
metadata:
  name: sentiment-tuned
spec:
  name: sentiment-tuned
  baseModel: "Qwen/Qwen2.5-0.5B-Instruct"
  dataset: "support-tickets-v3"
  epochs: 3
  approvalPolicy: auto      # promote only if eval clears the threshold
  evalThreshold: "0.80"
  servingReplicas: 2
  driftDetection: true
```

**KRO expands this into:** shared-artifact `PVC` · least-privilege `RBAC` · train+eval `Job` · MLflow registration · **gated** serving `Deployment` · drift sidecar · Prometheus wiring

<!--
RUNBOOK Beat 6. Same kro pattern as serving — but one template provisions the
whole lifecycle: training, MLflow registration, an approval gate, serving, AND
drift detection.
-->

---

# The approval gate — promotion is a data change, not a side effect

```yaml
# inside the serving Deployment, in the RGD:
replicas: ${schema.spec.approved ? servingReplicas : 0}
```

Serving runs **0 replicas** until `approved: true`. Two policies, one template:

- **`approvalPolicy: manual`** *(default — the guardrail)* — train, evaluate, register to MLflow, then **stop**. A data scientist reviews `eval_accuracy` and promotes:
  ```bash
  kubectl patch finetunemodel fraud-tuned --type merge -p '{"spec":{"approved":true}}'
  ```
- **`approvalPolicy: auto`** — the Job promotes itself, but **only** if the eval score clears `evalThreshold`. Below it, serving stays dark.

> Promotion to production is an explicit, auditable change — not a side effect of training finishing.

<!--
RUNBOOK Beats 7–8. This is the compliance / human-in-the-loop story.
fraud-tuned = manual (high stakes), sentiment-tuned = auto (trusts the eval gate).
-->

---

# Drift + MLflow — observability for free

- **Drift detection** ships with the template. The detector emits `genaiops_drift_score`, scraped via the **same pod-annotation pattern** as serving — no Prometheus reconfig, no per-team wiring.
- **MLflow is the constant control plane** at `http://mlflow:5000` — every team registers to the same registry and is scraped by the same Prometheus, **regardless of which cloud the train/serve infra lands on.**

```text
genaiops_drift_score      # already a Prometheus target, no config written
```

> Constant control plane + field-driven data plane = the whole portability story.

<!--
RUNBOOK Beat 8. The drift detector the template added is already scraped — same
annotations as everything else. driftDetection:false is the includeWhen toggle.
-->

---

# Use-case 2 — same fine-tuning template, every cloud

`instances/finetune-catalog.yaml`: **five teams, four clouds, one template.** Only `trainMode` / `servingMode` and `storageClass` change.

| Team | profile | trainMode → cloud | storageClass |
|---|---|---|---|
| summarizer-tuned | kind | `mock` | *(default)* |
| code-assistant-tuned | EKS | `gpu` | `gp3` |
| doc-search-tuned | GKE | `gpu` | `premium-rwo` |
| ticket-router-tuned | AKS | `gpu` | `managed-csi` |

The portability thesis holds for the **whole lifecycle**, not just serving. No Helm overlays, no per-cloud CRD variants, no vendor SDK.

<!--
RUNBOOK Beat 9. batch-classifier-tuned (5th team) sets driftDetection:false to
demo the includeWhen toggle live.
-->

---

# Independence & extensibility

- Each use-case declares its **own CRD** — `genaiservices.kro.run`, `finetunemodels.kro.run` — and kro starts a **separate dynamic controller** per CRD. No shared reconciliation state, no collisions.
- Deleting one RGD removes **only** that use-case:
  ```bash
  kubectl delete -f rgd/finetune-rgd.yaml   # fine-tuning gone
  kubectl get genaiservice                   # serving still running
  ```
- Setup is **layered**: `setup.sh` (base + serving) → `setup-finetune.sh` (adds fine-tuning). Run only what you need.
- **Use-case 3** (rag · eval · guardrail) drops in the exact same way — one RGD, one catalog, its own CI job. *(see `docs/ADDING-A-USE-CASE.md`)*

> Each use-case is just another RGD. No vendor lock-in, no shared blast radius.

<!--
RUNBOOK Beat 9 + ADDING-A-USE-CASE.md. This is the maintainer-audience payoff:
how a real platform onboards teams without coupling them.
-->

---

# Takeaways

- **One template. One ~10-line YAML. The same everywhere** — kind · EKS · GKE · AKS.
- Two use-cases — **serving** and the full **fine-tuning lifecycle** — built on the **same KRO pattern**, with **no custom Go operator**.
- Environment differences are **fields, not rewrites**. Use-cases are **independent modules**, not a monolith.

**Maturity note:** KRO is `v1alpha1` — early but credible. This is **where platform engineering is heading**, not a battle-tested-in-prod claim today.

> Build the platform API in hours. Onboard teams as RGDs. Stay portable by design.

<!--
Close on the thesis + the honest maturity framing from the KubeCon deck. Invite
questions; the live runbook (docs/RUNBOOK.md) is the demo backing all of this.
-->
