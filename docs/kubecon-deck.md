---
marp: true
theme: default
size: 16:9
paginate: true
header: "GenAIOps on KRO"
footer: "KubeCon NA · main session"
---

<!--
KubeCon NA main-session deck (use-case 1: serving). Marp markdown source — the
single editable source of truth (this replaces the old binary genaiops-kro-deck.pptx).

Render locally:
  npx --yes @marp-team/marp-cli@latest docs/kubecon-deck.md -o deck.pdf
  npx --yes @marp-team/marp-cli@latest docs/kubecon-deck.md -o deck.pptx
  npx --yes @marp-team/marp-cli@latest docs/kubecon-deck.md -o deck.html

The Maintainers Summit deck (docs/maintainers-summit-deck.md) is the superset that
also covers use-case 2 (fine-tuning). Speaker notes live in HTML comments and track
docs/RUNBOOK.md. Diagrams from the original pptx are described as layouts here; add
images in Marp later if a rendered deck needs the visuals.
-->

# Building a Cloud-Agnostic AIOps
## Abstracting GenAI infrastructure with KRM and KRO

> One template. One ~10-line YAML. The same everywhere — kind · EKS · GKE · AKS.
> KRO is the portability layer; the LLM is just proof the layer holds.

---

# Why KRO matters

- **Hours, not weeks** — build-your-own platform API becomes a small task, with **no custom Go operator**.
- **Reduced cognitive load** — developers consume a **10-line API**; the platform team encodes the resource graph **once**, not per team.
- **Portability, not vendor lock-in** — any K8s resource, native or CRD. Environment differences become **fields, not rewrites**.
- **Safe & predictable** — CEL is non-Turing-complete and validated at creation time. Errors caught before runtime, **unlike Helm**.
- **A cross-vendor standard** — AWS, Google & Microsoft collaborate on one project — rare credibility for a true portability layer.

**Maturity note:** KRO is `v1alpha1` — early but credible. Frame it as **where platform engineering is heading**, not battle-tested in prod today.

<!--
Slide 1 of the original deck. Don't read the bullets — land "fields, not rewrites"
and "encode the graph once." The maturity note is the honest framing; say it out loud.
-->

---

# How it works — one object fans out into a managed graph

**The developer writes ~10 lines of YAML:**

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

**KRO** infers the DAG → generates the CRD → reconciles at runtime, **creating & managing:**
`PersistentVolumeClaim` (model cache) · `Deployment` (vLLM-compatible, 2 replicas) · `Service` (stable in-cluster endpoint) · `Metrics Service` (Prometheus scrape wiring)

> One object owns the whole graph — create and delete. No glue operator.

<!--
Slide 2. RUNBOOK Beats 1–3. The payoff line: "one apply created the PVC, the
Deployment, both Services, and wired Prometheus — in dependency order I never specified."
-->

---

# Same template, same instance — every cluster

The **only** things that change between clouds are field **values** (`mode`, `storageClass`) — **not the YAML shape, not the RGD**.

**One ResourceGraphDefinition + one 10-line GenAIService — authored once · applied unchanged everywhere.**

| Profile | mode | storageClass |
|---|---|---|
| **kind** — laptop · CPU | `mock` | *(cluster default)* |
| **Amazon EKS** — GPU nodes | `gpu` | `gp3` |
| **Google GKE** — GPU nodes | `gpu` | `premium-rwo` |
| **Azure AKS** — GPU nodes | `gpu` | `managed-csi` |

Move from laptop to any hyperscaler by changing values in the 10-line file — **no re-templating, no fork of the RGD**.

<!--
Slide 3 (the thesis). RUNBOOK Beat 4 + instances/catalog.yaml. In the live demo
this runs on real GKE + AKS clusters (docs/PROVISION-REAL-CLUSTERS.md); KRO resolves
each cluster's storageClass from a platform-owned ConfigMap it reads. Close here.
-->
