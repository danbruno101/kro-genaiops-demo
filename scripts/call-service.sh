#!/usr/bin/env bash
# =============================================================================
# call-service.sh — simulate an END-USER hitting the sentiment-api service, and
# read its metrics, on one or all of the clouds (gke / aks / eks).
#
# sentiment-api is an OpenAI-compatible endpoint (POST /v1/chat/completions),
# so this is exactly how any app/client would call it. The service is ClusterIP,
# so we port-forward per cluster (a stand-in for the Ingress/LoadBalancer you'd
# have in prod), call it, then read /metrics to show the requests counter climb.
#
# Usage:
#   ./scripts/call-service.sh                     # one call to each cloud
#   ./scripts/call-service.sh --count 10          # 10 calls to each (drive metrics)
#   ./scripts/call-service.sh --metrics           # show metrics on each cloud
#   ./scripts/call-service.sh --count 10 --metrics  # call, then show metrics
#   ./scripts/call-service.sh --context gke       # just one cloud
#   ./scripts/call-service.sh --message "great product!"   # custom prompt
#
# Context names default to gke/aks/eks; override with GKE_CONTEXT / AKS_CONTEXT /
# EKS_CONTEXT (or pass --context). Works with whatever subset of clusters exist.
# Needs: kubectl, curl, python3 (for JSON parsing — stock on macOS/Linux).
# =============================================================================
set -euo pipefail

SVC="${SVC:-sentiment-api}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
MODEL="${MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
MESSAGE="This product is fantastic — fast and reliable!"
COUNT=1
DO_METRICS=0
ONLY_CONTEXT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --context)  ONLY_CONTEXT="$2"; shift 2 ;;
    --count)    COUNT="$2"; shift 2 ;;
    --message)  MESSAGE="$2"; shift 2 ;;
    --metrics)  DO_METRICS=1; shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need kubectl; need curl; need python3

# Build the (context, cloud-label) list.
if [ -n "${ONLY_CONTEXT}" ]; then
  TARGETS=("${ONLY_CONTEXT} ${ONLY_CONTEXT}")
else
  TARGETS=(
    "${GKE_CONTEXT:-gke} gke"
    "${AKS_CONTEXT:-aks} aks"
    "${EKS_CONTEXT:-eks} eks"
  )
fi

bold() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
dim()  { printf "  \033[2m%s\033[0m\n" "$*"; }
has_context() { kubectl config get-contexts -o name 2>/dev/null | grep -qx "$1"; }

PF_PID=""
pf_up() {   # $1=context ; background a port-forward and wait for /health
  kubectl --context "$1" port-forward "svc/${SVC}" "${LOCAL_PORT}:80" >/dev/null 2>&1 &
  PF_PID=$!
  local i
  for i in $(seq 1 20); do
    curl -fsS "http://localhost:${LOCAL_PORT}/health" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  return 1
}
pf_down() { [ -n "${PF_PID}" ] && kill "${PF_PID}" 2>/dev/null || true; wait "${PF_PID}" 2>/dev/null || true; PF_PID=""; }

extract_content='import sys,json; print(json.load(sys.stdin)["choices"][0]["message"]["content"])'

call_once() {
  curl -fsS "http://localhost:${LOCAL_PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"${MESSAGE}\"}]}" \
    | python3 -c "${extract_content}"
}

any=0
for entry in "${TARGETS[@]}"; do
  # shellcheck disable=SC2086
  set -- ${entry}
  ctx="$1"; cloud="$2"

  if ! has_context "${ctx}"; then
    dim "skip ${cloud}: kube-context '${ctx}' not found"
    continue
  fi
  any=1
  bold "[${cloud}] context '${ctx}'"

  if ! pf_up "${ctx}"; then
    dim "could not reach ${SVC} on '${ctx}' — is it deployed? (kubectl --context ${ctx} apply -f instances/sentiment-api.yaml)"
    pf_down; continue
  fi

  i=1
  while [ "${i}" -le "${COUNT}" ]; do
    reply="$(call_once || echo '<call failed>')"
    printf "  call %s/%s → %s\n" "${i}" "${COUNT}" "${reply}"
    i=$((i + 1))
  done

  if [ "${DO_METRICS}" = 1 ]; then
    dim "metrics:"
    curl -fsS "http://localhost:${LOCAL_PORT}/metrics" \
      | grep -E '^genaiops_(requests|tokens)_total' | sed 's/^/    /' || true
  fi

  pf_down
done

[ "${any}" = 1 ] || { echo "No matching contexts found (looked for: ${TARGETS[*]})."; exit 1; }
