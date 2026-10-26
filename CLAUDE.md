# CLAUDE.md — kro-genaiops-demo

Durable project context for Claude Code working in this repo.

## What this repo is

Demo companion for the KubeCon NA talk: proof that **KRO can be a portability
layer for GenAI infrastructure** — one RGD, a ~10-line developer instance,
identical behavior across kind / EKS / GKE / AKS. The GenAI payload is a mock
vLLM-compatible server on purpose; the star is KRO, not the ML.

Read `README.md` first; runbooks live in `docs/` (`RUNBOOK.md`, `MULTICLOUD.md`,
`PROVISION-REAL-CLUSTERS.md`, `HEADLAMP-MULTICLOUD-WALKTHROUGH.md`).

Sister project: https://github.com/danbruno101/kro-fleet — the fleet-scoped
placement PoC that reuses this repo's RGDs and mock images as its workload.

## Hard-won constraints — DO NOT regress these

- **Pin kro versions deliberately.** `scripts/setup.sh` resolves the *latest*
  kro release; CI pins `KRO_VERSION` in `demo-smoke-test.yaml`. **The CI pin
  must be at or above what setup.sh installs**, or CI stays green while every
  README follower is broken. This happened: kro v0.9.3 made `status.conditions`
  reserved and rejected the RGD while CI (pinned 0.9.1) stayed green.
- **RGD `status.conditions` is kro's custom-conditions list.** Declaring it
  replaces kro's built-in instance conditions, so always define `Ready` in it.
- **GenAIService replicas each get their own cache disk.** The serving pod
  template uses a generic ephemeral volume (`ephemeral.volumeClaimTemplate`),
  so Kubernetes stamps one ReadWriteOnce PVC per pod (`<pod>-cache`, labelled
  `app=<name>`) and replicas spread across nodes under RollingUpdate. kro
  resolves the StorageClass into that template and reads the claims back via
  the `modelCaches` externalRef collection (keep its `namespace`; without it kro
  lists cluster-wide). Consequences to keep: the platform `storageClass` must
  never be empty (`""` = no class = PVC Pending forever; kind writes
  `standard`), and the cache does not survive its pod. Do not reintroduce a
  shared named PVC or `strategy: Recreate` here.
- **The fine-tuning flow still shares one RWO PVC.** `rgd/finetune-rgd.yaml`'s
  artifacts PVC is the hand-off between the train Job and the serving
  Deployment, so it must stay shared. Keep `servingReplicas: 1` (and
  `strategy: Recreate`) there unless the storage is RWX.
- Renaming a generated-CRD status field is a **breaking CRD change**: kro
  refuses the update and the CRD outlives the RGD. Migration steps are inline in
  `rgd/genaiops-rgd.yaml`.

## Verification gate

A change is not done until `demo-smoke-test` CI is green **and** the flow it
touches has been exercised on a fresh kind cluster via `scripts/setup.sh`
(which tests against *latest* kro, unlike a stale local cluster).

## Git / PR workflow

- Work on a feature branch; open a PR. Keep commits focused; keep CI green.
- All commits require DCO sign-off (`git commit -s`).

### Commit attribution — NON-NEGOTIABLE
- Claude is only ever **"Assisted-by"**, never a co-author. Use the trailer
  `Assisted-by: Claude <noreply@anthropic.com>`. NEVER use `Co-Authored-By:` for
  Claude — GitHub treats that as real co-authorship and adds Claude to the
  repo's contributors list, which violates the contribution guidelines Daniel
  works under. Claude must also never be the commit *author* or *committer*.
- **Verify the identity before the first commit and push of a session.** This
  repo is owned by `danbruno101`; commits must be authored as
  `Daniel Bruno <daniel.c.bruno@gmail.com>` and pushed as `danbruno101`. Since
  the 2026-08-31 account consolidation the machine's global git identity is the
  personal address and the old work account (`dbruno-bt`) is retired — but the
  check stays cheap and the failure stays expensive, so run it anyway:
  ```bash
  git config user.email          # must be daniel.c.bruno@gmail.com
  gh auth status                 # active account must be danbruno101
  ```
  This has gone wrong before: dbruno-bt and Claude both ended up in this repo's
  contributors list, and recent history had to be rewritten to remove them.
