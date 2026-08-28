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
- **Never name an RGD status field `conditions`** — reserved by kro ≥0.9.3, and
  on older versions it silently shadows the instance's own conditions. Use a
  distinct name (`deploymentConditions`).
- **Replicas share a ReadWriteOnce PVC.** More than 1 replica works on
  single-node kind and deadlocks with a Multi-Attach error on any multi-node
  cluster. Keep instance `replicas: 1` (and `strategy: Recreate`) unless the
  storage is RWX. This applies to both the serving and fine-tuning flows.
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
  `Daniel Bruno <daniel.c.bruno@gmail.com>` and pushed as `danbruno101`. The
  machine's *global* git identity is the work account
  (`danielbruno@boroughtech.com` → `dbruno-bt`) and `gh` may have `dbruno-bt`
  active — both are wrong here. Check and fix BEFORE committing:
  ```bash
  git config user.email          # must be daniel.c.bruno@gmail.com (set locally if not)
  gh auth status                 # active account must be danbruno101
  gh auth switch --user danbruno101   # if it is not
  ```
  This has gone wrong before: dbruno-bt and Claude both ended up in this repo's
  contributors list, and recent history had to be rewritten to remove them.
