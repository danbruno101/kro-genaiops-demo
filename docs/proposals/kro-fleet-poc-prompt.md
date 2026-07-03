# `kro-fleet` — thin PoC build prompt

This is the build prompt for **`kro-fleet`**, the thin reference PoC that backs
[`KEP-kro-multicluster.md`](./KEP-kro-multicluster.md). It is meant to be pasted
into a fresh coding session (in a **new** repo — not this one, and **not** a fork
of `kubernetes-sigs/kro`).

**Scope decision (settled):** the PoC does **not** fork or modify kro. It runs
**stock kro on member clusters** and adds only a **hub-side fleet placement
controller**, built on SIG-Multicluster standards (`ClusterProfile` inventory +
`multicluster-runtime`). "Native mode inside kro" (expand-on-hub, one control loop)
is explicitly future work, tracked in the PoC's `docs/KEP-GAP.md`.

Before running the prompt, drop
[`KEP-kro-multicluster.md`](./KEP-kro-multicluster.md) into the new repo at
`docs/proposals/KEP-kro-multicluster.md` (the prompt references it).

---

```
Project: kro-fleet — a THIN reference PoC for the KEP "Native Multi-Cluster Mode for KRO."
Prove, on a laptop with kind, that one placement-enabled object applied ONCE on a hub cluster is dispersed
to the appropriate member clusters (across simulated clouds), with per-member status aggregated back on the
hub — by ADOPTING existing SIG-Multicluster standards (ClusterProfile inventory + multicluster-runtime),
NOT by forking kro and NOT by reinventing propagation.

EXPLICIT SCOPE DECISION (do not deviate):
  - DO NOT fork or modify kubernetes-sigs/kro. Run STOCK kro (released Helm chart) on each MEMBER cluster;
    it does the local graph expansion, exactly as in the sister repo.
  - The ONLY new code is a HUB-side "fleet placement controller." It distributes a developer instance to
    members and manages the cross-cluster lifecycle. Members do the rest with unmodified kro.
  - The eventual "native mode inside kro" (expand-on-hub, one control loop) is OUT OF SCOPE here and is
    documented as future work in docs/KEP-GAP.md.

READ FIRST:
  - docs/proposals/KEP-kro-multicluster.md — the spec you are validating (paste it into this repo).
  - github.com/danbruno101/kro-genaiops-demo — REUSE its GenAIService + ClusterPlatform RGDs and the
    ghcr.io/danbruno101/mock-vllm:demo workload. Match its ethos: kind-based, GPU-free, hermetic CI with a
    badge, pinned versions, one-command setup, a "for reviewers" README, and an explicit HONESTY section.
  - github.com/kubernetes-sigs/multicluster-runtime — provider model for reconciling across a fleet.
  - github.com/kubernetes-sigs/cluster-inventory-api + KEP-4322 — ClusterProfile, status.accessProviders.
  - github.com/kubernetes-sigs/kro — for understanding the RGD/GenAIService you distribute (as a USER, not
    to modify).

ARCHITECTURE (thin PoC):
  HUB cluster:
    - Install the ClusterProfile CRDs (cluster-inventory-api). Each member is registered as a ClusterProfile.
    - A new fleet placement controller (Go, built on multicluster-runtime), discovering members through a
      ClusterProfile/cluster-inventory provider. Use an existing provider if one exists; if not, writing a
      minimal ClusterProfile provider is in-scope (and a useful upstream contribution).
    - It watches a placement-enabled hub object (e.g. FleetGenAIService: carries the GenAIService spec/ref +
      a `placement.clusterSelector` label selector over ClusterProfiles). Placement is PLATFORM-owned; the
      GenAIService it distributes stays cloud/cluster-agnostic.
    - Reconcile loop: resolve placement -> for each selected member, server-side-apply the GenAIService
      instance -> TRACK applied manifests per (object, member) -> finalizer-driven GC on delete/unplace with
      NO orphans -> collect member status -> aggregate into status.clusters[] + a rolled-up condition
      (honor a tolerance like minReadyClusters).
  MEMBER clusters (unmodified):
    - Stock kro + the sister repo's platform-rgd/genaiops-rgd + a ClusterPlatform instance (per "cloud"),
      installed by the setup script. Stock kro expands the distributed GenAIService locally into
      PVC/Deployment/Service, resolving each member's StorageClass per cloud — as already proven.
  Member credentials flow through ClusterProfile status.accessProviders (a minimal kubeconfig-based access
  provider is acceptable for the kind PoC, but ClusterProfile MUST be the inventory API — not ad-hoc config).

PHASE 0 — VALIDATE THE FOUNDATION BEFORE COMMITTING (present a PLAN before building the full thing):
  Stand up 2 kind clusters, install ClusterProfile CRDs, register one as a ClusterProfile on the other,
  wire multicluster-runtime with a ClusterProfile provider, and prove you can reconcile a TRIVIAL object
  (e.g. a ConfigMap) FROM the hub INTO the member. Confirm current API versions/provider interfaces. Only
  then commit to the design and present the plan.

DEMO SHAPE (the money demo, on kind):
  - 1 hub + 3 members (kind), members labeled cloud=gke/aks/eks, registered as ClusterProfiles, each with
    stock kro + the sister repo's RGDs/ClusterPlatform pre-installed.
  - Apply ONE FleetGenAIService on the hub -> the sentiment-api workload appears on all 3 members, each
    bound to its cloud's StorageClass. Change it once -> all converge. Remove a member from the selector or
    delete its ClusterProfile -> the workload EVACUATES that member (clean GC). status.clusters[] shows
    per-member readiness on the hub object.

DELIVERABLES:
  - The hub fleet placement controller + the FleetGenAIService CRD/type.
  - ClusterProfile registration for kind members + the (minimal) access-provider wiring.
  - scripts/setup-fleet.sh + teardown-fleet.sh (hub + N members; install ClusterProfile CRDs + the hub
    controller; install stock kro + the sister repo's RGDs/ClusterPlatform on each member).
  - Hermetic CI (kind hub+members, PINNED versions) proving the full loop.
  - docs/proposals/KEP-kro-multicluster.md (the KEP, so proposal + PoC live together).
  - docs/KEP-GAP.md — honest map of PoC vs KEP: PoC distributes the instance and expands on MEMBERS via
    stock kro; native mode would expand on the HUB inside kro; the access provider is simplified; etc.
  - A Marp deck + a runbook, sister-repo style.
  - README: frame it as the thin reference PoC for the KEP; explicit honesty on PoC-vs-native.

SUCCESS CRITERIA — CI MUST PROVE:
  [ ] One FleetGenAIService on the hub -> workload present & Ready on every matching member.
  [ ] Mutation on the hub object -> all members converge.
  [ ] Add a member (new matching ClusterProfile) -> workload lands automatically.
  [ ] Remove/unmatch a member -> workload removed from that member, no orphaned objects.
  [ ] Delete the hub object -> all placed objects on all members are garbage-collected.
  [ ] status.clusters[] on the hub reflects per-member readiness and a correct rolled-up condition.

CONSTRAINTS: no secrets/credentials committed; kind + pinned versions (kro, multicluster-runtime,
cluster-inventory-api CRDs) for reproducibility; hermetic CI; reuse the sister repo's mock images; be
explicit about scale/limits per lucy.sh/fleet-scale-kubernetes (cluster size bounds only your biggest
single workload; the fleet scales by adding clusters).

START BY: (1) create/confirm the repo `kro-fleet`; (2) read the KEP + the sister repo + multicluster-runtime
+ cluster-inventory-api; (3) do the Phase 0 validation and PRESENT A PLAN before building; (4) build
incrementally with green CI at each step, keeping docs/KEP-GAP.md honest as you go.
```
