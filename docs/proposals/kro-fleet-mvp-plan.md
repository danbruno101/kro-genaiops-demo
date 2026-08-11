# kro-fleet MVP — the north star, demonstrable

This is the **single build plan** for the `kro-fleet` MVP: the smallest thing that
demonstrates the [KEP](./KEP-kro-multicluster.md)'s north star **live** — author one
object on a hub, watch it run across a fleet of clusters, and see the object graph and
logs in a UI. It supersedes and merges the two earlier prompts
([`kro-fleet-poc-prompt.md`](./kro-fleet-poc-prompt.md) — controller; and the Headlamp
plugin prompt) into one scoped MVP.

It is built in the separate **`kro-fleet`** repo (which already has its `CLAUDE.md`,
`KEP-kro-multicluster.md`, and `KEP-GAP.md`). This document is the spec a fresh session
there builds from.

> **Origin:** SIG Cloud Provider (elmiko) and a KRO maintainer (Jesse Butler) validated
> the fleet idea and asked for a **visual** demo (a Headlamp dashboard) plus a
> **recording** as a glitch-proof fallback. This MVP delivers exactly that.

---

## The one idea that makes this an MVP, not a rewrite

The north star's **experience** is: *author once on the hub → running across the fleet
→ visualized.* The **thin PoC** (a hub placement controller + **stock kro on members**)
delivers that whole experience **without forking kro**. The only difference from the
"native" end-state is *where the graph expands* (on each member vs. inside kro on the
hub) — and **that difference is invisible in the demo.**

So the MVP = **thin controller + Headlamp plugin.** No kro fork. (Forking kro is still
premature — no maintainer buy-in on internals — and buys nothing the audience can see.)

### Two-narrative honesty rule (keep both in their lanes)
- **To the audience / on stage:** "One object on the hub, placed and running across
  three clusters, visualized live." ✅
- **To the KRO maintainers:** "Hub placement controller + stock kro on members; native
  in-kro expansion is the *proposal*." ✅
- `docs/KEP-GAP.md` holds every technical caveat. Never tell maintainers kro itself is
  doing hub-side expansion in the MVP.

---

## Components (one `kro-fleet` repo, two directories)

### `controller/` — the hub placement control plane
- `FleetGenAIService` CRD: the sister repo's `GenAIService` spec/ref +
  `placement.clusterSelector` (label selector over `ClusterProfile`s).
- Hub controller (Go, `multicluster-runtime` + `ClusterProfile`/cluster-inventory
  provider): resolve placement → server-side-apply the `GenAIService` onto each matching
  member → track applied manifests per `(object, member)` → finalizer GC on
  unplace/delete → aggregate per-member readiness into `status.clusters[]` + a rolled-up
  condition.
- Members run **unmodified kro** + the sister repo's RGDs/`ClusterPlatform`; kro expands
  the placed `GenAIService` locally, resolving each member's StorageClass per cloud.

### `headlamp-plugin/` — the visual
- TS/React plugin (current Headlamp plugin lib). Pointed at the **hub** context:
  1. "KRO Fleet" sidebar entry.
  2. Fleet page: registered members (`ClusterProfile`s) + `FleetGenAIService`s with
     per-member health from `status.clusters[]`.
  3. Detail: the one object placed across the 3 members, each with its expanded graph.
  4. **Object graph** via a Headlamp **map source** (`registerMapSource`):
     `FleetGenAIService` (hub) →(placed on)→ `GenAIService` (member) →(owns)→
     Deployment / PVC / Service / Metrics / Pods.
  5. **Pod logs** streamed in the UI (click a Pod → logs), read from that member.
- Prior art to reuse: the **Kubeflow** Headlamp plugin (map source for CRDs + reads
  pods/logs directly), the **Cluster API** plugin (multi-cluster viz), and
  `pnz1990/kro-ui` (kro graph viz).
- Member mapping: `ClusterProfile` name ⇄ Headlamp/kubeconfig context (convention or an
  annotation) — **document it**.

---

## MVP scope — cut hard to the money shot

**IN**
- Place **one** `FleetGenAIService` onto **three** members; stock kro expands on each.
- Basic `status.clusters[]` + rolled-up condition; finalizer GC.
- Plugin: fleet view, the one object across 3 clusters, the graph, and pod logs.
- A **screen recording** of the walkthrough (elmiko's fallback) — first-class deliverable.

**OUT / deferred (record in `KEP-GAP.md`)**
- Native expand-on-hub (the kro fork), placement strategies, pull mode, GC edge cases,
  scale, hardened credentials/RBAC.

**Fleet target:** reuse the existing **real gke/aks/eks** clusters *or* kind — pick
whichever is more **demo-stable** on the day.

---

## Build sequence (so it converges)
1. **Controller, minimal:** CRD + place-on-3 + `status.clusters[]`. Enough for the
   plugin to render real objects.
2. **Plugin Phase 0 (parallel):** in a dev Headlamp, prove the only real unknowns —
   cross-cluster read (hub + members in one view), a custom **map source**, and pod-log
   fetch from a member. Render one trivial cross-cluster node + one log stream first.
3. **Plugin build:** fleet → `FleetGenAIService` → graph across 3 → logs.
4. **Record it.**

Early UI dev can start against a hand-created `FleetGenAIService` + manually-applied
`GenAIService`s on members, before the controller is complete.

## Phase-0 risks to validate before committing
- **Controller:** `multicluster-runtime` + `ClusterProfile` provider actually reconcile
  a trivial object hub→member on current API versions.
- **Plugin:** Headlamp can render **one graph spanning hub + members** from a single
  plugin view (cross-context reads), plus map source + logs.

## Success criteria (the demo proves)
- [ ] One `FleetGenAIService` on the hub → workload Ready on all three members.
- [ ] Mutate the hub object → all three converge.
- [ ] Remove/unmatch a member → workload evacuates it, no orphans.
- [ ] Delete the hub object → all placed objects GC'd everywhere.
- [ ] Plugin shows the fleet, the object graph across 3 clusters, and live pod logs.
- [ ] A recording of the above exists.

## Where this runs
A fresh session opened **in the `kro-fleet` repo**, using its `CLAUDE.md`,
`docs/proposals/KEP-kro-multicluster.md`, and `docs/KEP-GAP.md`. (This session — scoped
to `kro-genaiops-demo` — cannot build or push the `kro-fleet` code; it authors this plan.)
