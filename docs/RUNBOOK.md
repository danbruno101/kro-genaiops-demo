# GenAIOps + KRO — Live Demo Runbook

**Thesis on stage:** *One template. One 10-line YAML. Same everywhere — kind, EKS, GKE, AKS.
KRO is the portability layer; the LLM is just proof the layer holds.*

Total live time: ~8–10 min. Everything below is copy-paste. Keep two terminals
open (LEFT = you type, RIGHT = `watch`), plus a browser tab on Prometheus.

> **Two run modes.** Beats 0–5 are **use-case 1** (serving) — the KubeCon talk,
> run after `./scripts/setup.sh`. Beats 6–9 are **use-case 2** (fine-tuning) —
> the Maintainer Summit, run after also doing `./scripts/setup-finetune.sh`.
> Skip 6–9 for the simple KubeCon session.

---

## T-minus (before you walk on)
Run once, the morning of. Takes ~2 min.

```bash
./scripts/setup.sh
```

Confirm green:
```bash
kubectl get rgd                      # genaiservice.kro.run -> ACTIVE
kubectl get crd genaiservices.kro.run
```

Pre-warm the Prometheus port-forward in the RIGHT terminal:
```bash
kubectl port-forward svc/prometheus 9090:9090
```
Browser tab: http://localhost:9090/targets (leave open).

---

## Beat 0 — The problem (30s, no typing)
Open `docs/before-raw-krm.yaml` in your editor. Scroll it slowly.
> "This is what one model service looks like in raw KRM. PVC, Deployment,
> two Services, probes, Prometheus wiring. Now multiply by every model and
> every cloud. **This** is the friction."

---

## Beat 1 — The platform artifact (90s)
Show `rgd/genaiops-rgd.yaml`. Don't read it line by line — point at three things:
- the `schema` block → "this is the API developers get"
- the CEL `${...}` refs → "kro infers the dependency graph from these"
- the `mode` / `storageClass` fields → **"this is the entire portability story"**

It's already applied. Prove the new API exists:
```bash
kubectl get rgd genaiservice.kro.run
kubectl explain genaiservice.spec      # the API kro generated from the RGD
```

---

## Beat 2 — The developer experience (2 min) ← the payoff
LEFT terminal:
```bash
cat instances/sentiment-api.yaml        # 9 lines. Let it sit on screen.
kubectl apply -f instances/sentiment-api.yaml
```
RIGHT terminal (start the watch immediately):
```bash
watch -n1 'kubectl get genaiservice,deploy,svc,pvc -l app=sentiment-api'
```
> "One apply. kro just created the PVC, the Deployment, both Services, and
> wired Prometheus — in dependency order I never had to specify."

Show the status kro writes back onto the object:
```bash
kubectl get genaiservice sentiment-api -o jsonpath='{.status}{"\n"}'
```

Prove it serves:
```bash
kubectl port-forward svc/sentiment-api 8080:80 &
curl -s localhost:8080/v1/chat/completions -X POST -d '{}' | jq .
```

---

## Beat 3 — Monitoring lights up (1 min)
Flip to the Prometheus browser tab → **Targets**. `sentiment-api` pods appear
as UP (the RGD added the scrape annotations; you wrote none of that).
Run a quick query in the Graph tab:
```
genaiops_requests_total
```
Curl the endpoint a few more times; watch the counter climb on refresh.

---

## Beat 4 — Self-service catalog + portability (2 min) ← the thesis
> "Same template. Three teams. The only fields that differ between a laptop
> and a GPU node on EKS, GKE, or AKS are `mode` and `storageClass` — fields, not rewrites."

```bash
kubectl apply -f instances/catalog.yaml
kubectl get genaiservice
```
Open `instances/catalog.yaml`. Point at `code-assistant`:
> "To move this to a GPU node I set `mode: gpu` and `storageClass` to whatever
> that cloud calls it — `gp3` on EKS, `premium-rwo` on GKE, `managed-csi` on
> AKS. The shape of the YAML doesn't change. The RGD doesn't change. That's the
> whole point."

(Optional, if you have a GPU cluster wired as a second context — works the same
on EKS, GKE, or AKS; substitute your context name:)
```bash
kubectl --context <gpu-cluster> apply -f rgd/genaiops-rgd.yaml
kubectl --context <gpu-cluster> apply -f instances/sentiment-api.yaml
```
> "Same two files. Different cloud. No diff."

---

## Beat 5 — Land it (15s)
```bash
kubectl delete genaiservice sentiment-api
kubectl get deploy,svc,pvc -l app=sentiment-api   # all gone
```
> "One object owns the whole graph — create and delete. No Go operator. That's
> KRO as a portability layer for AI infra."

---

## ── Use-case 2: fine-tuning (Maintainer Summit only) ──

Prereq: `./scripts/setup-finetune.sh` has run (adds MLflow + the fine-tuning
API + the trainer/drift images). Pre-warm a second browser tab on MLflow:
```bash
kubectl port-forward svc/mlflow 5000:5000     # RIGHT terminal #2
```
Browser tab: http://localhost:5000 (Models + Experiments).

## Beat 6 — One YAML, the whole MLOps lifecycle (2 min)
Show `rgd/finetune-rgd.yaml` briefly — point at the schema, then at the serving
`replicas: '${schema.spec.approved ? servingReplicas : 0}'` line:
> "Same kro pattern as before — but this one template provisions a training job,
> MLflow registration, an approval gate, serving, AND drift detection."

LEFT terminal — start with the **manual** gate (the guardrail):
```bash
cat instances/fraud-finetune.yaml          # ~10 lines, approvalPolicy: manual
kubectl apply -f instances/fraud-finetune.yaml
```
RIGHT terminal:
```bash
watch -n1 'kubectl get finetunemodel,job,deploy,pvc -l app=fraud-tuned'
```
> "The Job trains and evaluates, the model lands in MLflow — but serving is at
> **0 replicas**. Nothing goes live without sign-off."

## Beat 7 — Human-in-the-loop approval (1.5 min) ← the compliance story
Flip to the MLflow tab → the `fraud-tuned` run → show `eval_accuracy`.
> "A data scientist reviews the metrics here. Promotion to production is an
> explicit, auditable change — not a side effect of training."

Approve it:
```bash
kubectl patch finetunemodel fraud-tuned --type merge -p '{"spec":{"approved":true}}'
```
Watch serving scale 0 → 1 in the RIGHT terminal.
> "One field. kro reconciled the gate and scaled serving up."

## Beat 8 — Auto-promotion on eval pass (1.5 min)
```bash
cat instances/sentiment-finetune.yaml      # approvalPolicy: auto
kubectl apply -f instances/sentiment-finetune.yaml
kubectl get finetunemodel sentiment-tuned -w
```
> "This team trusts the eval gate. The Job evaluates, clears the threshold, and
> promotes itself — serving comes up with no human in the loop. Below the
> threshold, it would stay dark."

Drift + observability — flip to the Prometheus tab → Graph:
```
genaiops_drift_score
```
> "The drift detector the template added is already being scraped. No Prometheus
> config — same annotations as everything else."

## Beat 9 — Portability + independence (1.5 min) ← the thesis
```bash
kubectl apply -f instances/finetune-catalog.yaml
kubectl get finetunemodel
```
> "Same template, five teams, four clouds — only `trainMode`/`servingMode` and
> `storageClass` differ. And this entire use-case is independent: it's a separate
> RGD. Deleting it leaves the serving use-case untouched —"
```bash
kubectl delete -f rgd/finetune-rgd.yaml    # finetune gone; GenAIService intact
kubectl get genaiservice                    # use-case 1 still running
```
> "That's how a real platform onboards teams: each use-case is just another RGD.
> No vendor lock-in, no shared blast radius."

---

## If something breaks on stage
- **CRD not registered yet:** `kubectl get rgd` — wait for `ACTIVE`. The setup
  script already waits, but if you re-applied, give it ~10s.
- **Pod ImagePullBackOff:** the mock image didn't load into kind. Re-run:
  `kind load docker-image ghcr.io/danbruno101/mock-vllm:demo --name genaiops-demo`
- **Prometheus target missing:** the pod needs `monitoring: true` (default) and
  ~10s to be scraped. Check `kubectl get svc -l genaiops.kro.run/scrape=true`.
- **Fine-tuning: serving stuck at 0:** that's the gate working. In manual mode
  patch `approved: true`; in auto mode check the Job logs
  (`kubectl logs job/<name>-train`) for the eval score vs threshold.
- **Fine-tuning: model not in MLflow:** the Job waits for MLflow to be ready.
  Confirm `kubectl get deploy mlflow` is Available, then re-check the Job logs.
- **Total fallback:** screenshots in `docs/` + this runbook are enough to narrate
  the whole flow without a live cluster.
