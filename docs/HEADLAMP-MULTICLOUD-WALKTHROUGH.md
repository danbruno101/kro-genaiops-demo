# Multi-Cloud Demo — driven from the kro Headlamp plugin

The same beats as `docs/MULTICLOUD.md`, performed in the UI instead of a
terminal, against **real GKE / AKS / EKS**. Nothing is typed on stage except a
URL; the portability claim is read off the screen.

> **The mechanic that carries the whole demo:** every page URL is
> `http://localhost:3000/c/<CONTEXT>/kro/...`. Swapping one path segment —
> `gke` → `aks` → `eks` — moves the *same view* to another cloud. The URL is
> the thesis.

---

## T-minus (before you walk on)

Servers (leave both running):

```bash
cd ~/headlamp-dev/headlamp/backend && ./headlamp-server -dev -plugins-dir ~/headlamp-dev/plugins
cd ~/headlamp-dev/headlamp/frontend && npm start
```

Preflight — every row must be populated:

```bash
for c in gke aks eks; do
  printf "%-4s sc=%-12s ready=%-4s\n" "$c" \
    "$(kubectl --context $c get pvc sentiment-api-cache -o jsonpath='{.spec.storageClassName}' 2>/dev/null)" \
    "$(kubectl --context $c get deploy sentiment-api -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)"
done
# verified 2026-08-25 on real clusters:
#   gke premium-rwo 1/1 | aks managed-csi 1/1 | eks gp3 1/1
```

> `replicas: 1` is deliberate — the replicas share one ReadWriteOnce cache PVC,
> so a second replica on another node hangs with a Multi-Attach error. Single-node
> kind hides this; real multi-node clusters do not.

Open these four tabs in advance (demo insurance — no navigation on stage):

1. `http://localhost:3000/c/gke/kro/resourcegraphdefinitions/genaiservice.kro.run`
2. `http://localhost:3000/c/gke/kro/resourcegraphdefinitions/genaiservice.kro.run/instances/default/sentiment-api`
3. `.../c/aks/kro/resourcegraphdefinitions/genaiservice.kro.run/instances/default/sentiment-api`
4. `.../c/eks/kro/resourcegraphdefinitions/genaiservice.kro.run/instances/default/sentiment-api`

**Do not open the sidebar "Map" page** — upstream aggregation bug
(kubernetes-sigs/headlamp#6555) can leave it spinning.

---

## Beat 1 — The platform contract is identical on every cloud (45s)

Tab 1, then sidebar **kro → Resource Graph Definitions**. Two RGDs, both
`Active`. Switch the cluster (top-right selector) to **aks**, then **eks**.

> "Three clouds. Same two ResourceGraphDefinitions, byte-identical, all Active.
> The platform contract doesn't vary by cloud — that's the precondition for
> everything else."

---

## Beat 2 — What the abstraction *is* (60s) ← the composition point

Tab 1 → scroll to **Template Graph**.

> "This is the RGD as kro understands it: a PVC, a Deployment, two Services, and
> the platform config it reads. And notice — **nobody declared this order**. Each
> edge is a CEL reference from one resource to another; kro derived the graph
> from the expressions and publishes it in status. The plugin is just drawing
> what kro already computed."

Scroll to **Composed Resources** and point at the *Depends On* column.

> "kro's own static analysis. No custom controller, no Go."

Optionally scroll to **Schema** — the developer-facing API generated from
SimpleSchema.

---

## Beat 3 — The developer experience (30s)

Still on Tab 1, click **New Instance** (top right).

> "This is what a product team writes. The editor is pre-filled from the RGD's
> schema — name, model, replicas, mode. Notice what is *not* here: no cloud, no
> storage class, no CSI driver."

Close the dialog without applying (the instance already exists).

---

## Beat 4 — Same spec, three clouds ← THE PAYOFF (90s)

Tab 2 (**gke**) → scroll to **Sub-resources**.

Point at two things on the same screen:

- **Resolved Values** → `storageClass: premium-rwo, capacity: 8Gi`
- **Spec** (just below) → the `storageClass` row is **empty**

> "The developer left storage unspecified. kro resolved it *on this cluster* from
> the platform config, and it landed on `premium-rwo` — what Google calls its
> storage. The developer never knew the word."

Switch to Tab 3 (**aks**) — the same page on another cloud:

> "Same object. Same nine-line spec. I changed one segment of the URL. Storage
> resolved to `managed-csi`."

Switch to Tab 4 (**eks**):

> "Third cloud — and this is the interesting one. A real EKS cluster ships **no**
> default StorageClass. So kro didn't just resolve the class here, it **created**
> it: `gp3`, provisioner `ebs.csi.eks.amazonaws.com`. Still nothing applied to
> this cluster but kro."

*(EKS proof, if asked — Headlamp → Storage → StorageClasses → `gp3`, label
`app.kubernetes.io/managed-by: kro`.)*

**Proving these are real cloud clusters — without leaving Headlamp.** Fold this
into the beat rather than making it a separate segment: click through from the
resolved class to **Storage → Storage Classes → \<class\>** and read the
provisioner aloud.

| Context | Provisioner (unfakeable) | Node `providerID` | Version suffix |
|---|---|---|---|
| `gke` | `pd.csi.storage.gke.io` | `gce://<project>/us-central1-a/...` | `-gke.1710000` |
| `aks` | `disk.csi.azure.com` | `azure:///subscriptions/<sub>/...` | plain upstream |
| `eks` | `ebs.csi.eks.amazonaws.com` | `aws:///us-east-1c/i-0089...` | `-eks-a3a0722` |

> "That's Google's persistent-disk CSI driver — this is a real GKE cluster in
> us-central1." A kind cluster would say `rancher.io/local-path`.

Node identity lives in **Nodes → \<node\> → Labels**; the OS images differ per
cloud too (Container-Optimized OS, Ubuntu, and Bottlerocket on EKS Auto Mode).

---

## Beat 5 — It keeps reconciling (45s)

Stay on any instance tab, graph visible. In a terminal:

```bash
kubectl --context gke delete pod -l app=sentiment-api --wait=false
```

> "Watch the Deployment node." — it goes red/warning, the Sub-resources row drops
> to `0/2`, then both converge back to green. No refresh; these are watches.

> "Helm and Kustomize are apply-time. This is a controller — it keeps converging."

---

## Beat 6 — One object, not a pile (30s, no typing) ← the message to land

Back to the instance graph.

> "The skeptic says: *I can kubectl apply the same YAML to two clusters.* Here's
> the difference. Without kro this workload is five coupled resources you move in
> dependency order and delete without orphaning the PVC. With kro the workload
> **is** one GenAIService — this whole graph has one owner. One apply moves it;
> one delete reclaims all of it. And the environment is resolved **on the target
> cluster**, not rendered per-cloud before you ship."

That is the handoff into the fleet-scoped conversation: composition knows these
are one unit — and today that knowledge stops at the cluster boundary.

---

## Contingencies

| If… | Do this |
|---|---|
| A page looks stale | `Cmd+R`. Selection is restored from `?node=`. |
| Graph empty / cluster spinner | Check the context is reachable: `kubectl --context <c> get nodes`. |
| A node has no details panel | You clicked a synthetic node (the RGD root); only live objects open details. |
| EKS not ready in time | Substitute `kind-genaiops-eks` — same beats, `gp3` still kro-created. |
| Someone asks "is this in Headlamp?" | Plugin is `0.2.0-alpha`, PR headlamp-k8s/plugins#1182; embedded graphs use Headlamp's own GraphView, exposed by headlamp#6992 (newer than 0.44.0), with an automatic fallback renderer on older hosts. |

## Teardown (stop billing)

```bash
gcloud container clusters delete genaiops-gke --zone us-central1-a --quiet
az group delete --name genaiops-demo --yes --no-wait
eksctl delete cluster --name genaiops-eks --region us-east-1
```
