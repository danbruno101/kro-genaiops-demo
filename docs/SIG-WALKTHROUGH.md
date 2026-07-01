# SIG Cloud Provider — live topology walkthrough

Four commands to walk the audience through the deployed topology on **real GKE +
AKS + EKS**. Assumes everything is already deployed (platform via
`deploy-multicloud-real.sh`, and `instances/sentiment-api.yaml` applied to each
context). Contexts are named `gke` / `aks` / `eks`.

**The arc:** real, different clouds → KRO owns each cluster's storage config → the
same developer workload runs on all three → each PVC bound to its cloud's
KRO-resolved class.

---

## Prep (optional) — populate the CLOUD node label

Real clusters aren't labeled with `demo.genaiops/cloud` (only the kind sims are), so
that column shows blank. Label them once if you want it populated on stage:

```bash
for c in gke aks eks; do kubectl --context $c label nodes --all demo.genaiops/cloud=$c --overwrite; done
```

---

## 1. Three real clusters, three clouds

```bash
for c in gke aks eks; do
  kubectl --context $c get nodes -L topology.kubernetes.io/region,demo.genaiops/cloud
done
```

Real nodes on each cloud, with their region (`us-central1` / `eastus` /
`us-east-1`) and Kubernetes versions.

> "Three real clusters, three providers, three regions — not a simulation. This is
> the environment KRO has to be portable across."

---

## 2. KRO owns each cluster's storage config

```bash
for c in gke aks eks; do
  echo -n "$c -> "
  kubectl --context $c get configmap genaiops-platform-config -o jsonpath='{.data.storageClass}'
  echo -n "  | sc managed-by: "
  kubectl --context $c get sc \
    -o jsonpath='{.items[?(@.metadata.labels.app\.kubernetes\.io/managed-by=="kro")].metadata.name}{"\n"}'
done
```

Each cluster's platform ConfigMap value **and** which StorageClass carries the
`managed-by: kro` label.

> "Each cloud names its own class — premium-rwo, managed-csi, gp3 — in a ConfigMap
> KRO owns. And KRO created that StorageClass itself: `managed-by: kro`. On EKS, gp3
> didn't exist until KRO made it. Nothing here was hand-applied."

---

## 3. The same developer workload runs on all three

```bash
for c in gke aks eks; do
  kubectl --context $c get genaiservice sentiment-api
done
```

The identical `GenAIService` object, reconciled on each cluster.

> "The exact same 9-line spec is live on all three — one API, and each cluster owns
> its own graph."

---

## 4. Each workload bound to its cloud's KRO-resolved class ← the payoff

```bash
for c in gke aks eks; do
  echo -n "$c -> "
  kubectl --context $c get pvc sentiment-api-cache -o jsonpath='{.spec.storageClassName}{"\n"}'
done
# gke -> premium-rwo   aks -> managed-csi   eks -> gp3
```

The workload's PVC bound to each cloud's class — with zero changes to the
developer's YAML.

> "And the workload's PVC bound to each cloud's class — premium-rwo, managed-csi,
> gp3 — with no change to the developer's spec. Same YAML, resolved per cluster.
> That's the whole thesis."

---

## Optional follow-ups

- **End-user calling the service** (same OpenAI-compatible API, every cloud):
  ```bash
  ./scripts/call-service.sh --count 10 --metrics
  ```
- **One object owns the whole graph** (per cluster):
  ```bash
  kubectl --context gke get genaiservice,deploy,svc,pvc,pod -l app=sentiment-api
  ```

> Note on scope: KRO owns the graph **within** each cluster; the *same spec* is
> portable **across** clusters. A single cross-cluster owned graph would sit a layer
> up (OCM / Karmada / Argo CD), with KRO doing the per-cluster expansion underneath.
