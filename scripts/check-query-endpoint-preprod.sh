#!/usr/bin/env bash
set -euo pipefail

# Records a live acceptance journey for the hosted ckeri-query preprod
# endpoint (#176 Slice 2/3): pre-outage readiness/data proof, an exact
# upstream cardano-preprod stop/restart, automatic reconnection proof
# without touching the query service, and an optional declarative
# nixos-rebuild switch --flake bring-up journey. It never brings the query
# service up imperatively -- that is a declarative-only deployment
# boundary (#176 FR-13) and this helper only observes it.
#
# Does nothing live unless --live is given. --help always exits 0 first.

BASE_URL="https://ckeri.dev.plutimus.com"
UPSTREAM_CONTAINER="cardano-preprod"
FLAKE_REF="${CKERI_ENDPOINT_FLAKE:-/code/infrastructure-cardano-keri-176/nixos/development#default}"
CHECKPOINT_AID=""
WITNESS_KEY=""
LIVE=0
SKIP_REBUILD=0
ROOT_FLOOR_GIB=30
REBUILD_START_FLOOR_GIB=37
COMMAND_BURN_LIMIT_GIB=8
CODE_BURN_FRACTION=20

usage() {
  cat <<'USAGE'
check-query-endpoint-preprod.sh -- live acceptance journey for the hosted
ckeri-query preprod endpoint. Nodeless: uses only public curl/jq.

Does nothing live by default; pass --live to run the real journey.

Options:
  --live                 perform the live journey (required for any action)
  --base-url URL         public endpoint base (default: https://ckeri.dev.plutimus.com)
  --checkpoint-aid AID   CESR E-code AID to query /checkpoint/{aid} and
                         /watchability/{aid} with (required with --live)
  --witness-key KEY      CESR B-code witness key to query /board/{witness_key}
                         with (required with --live)
  --flake PATH#ATTR      nixos-rebuild flake reference (default: env
                         CKERI_ENDPOINT_FLAKE, or the accepted development
                         infrastructure worktree)
  --skip-rebuild         run only the outage/recovery journey; skip the
                         declarative nixos-rebuild switch --flake step
  --selftest             run the non-live executable-sequencing self-test
                         (zero-match and positive-match branches) and exit
  --help                 show this help and exit
USAGE
}

# Count exact-executable-name matches without tripping `set -euo pipefail`
# on the zero-match case. `pgrep` exits 1 when nothing matches -- which is
# the expected, safe state before a rebuild -- and a `pgrep -x ... | wc -l`
# pipe fails closed on exactly that branch under `pipefail` (the pipeline's
# exit status is pgrep's 1, since `wc -l` itself still exits 0). `pgrep -c`
# prints the count directly, so the explicit `|| count=0` is the only thing
# needed to accept the safe zero-match result instead of aborting on it.
exact_process_count() {
  local exe="$1" count
  count=$(pgrep -xc "$exe" 2>/dev/null) || count=0
  printf '%s\n' "$count"
}

# Non-live proof that both branches of exact_process_count behave under
# set -euo pipefail: a name nothing runs as (the safe pre-rebuild state)
# must reach zero without aborting, and a name something does run as (this
# script's own interpreter, so it never depends on host state) must reach
# a positive count.
selftest_sequencing() {
  local zero_count positive_count
  zero_count=$(exact_process_count ckeri-selftest-no-such-exe-zzz)
  if [[ "$zero_count" -ne 0 ]]; then
    echo "selftest FAILED: expected 0 for a nonexistent executable name, got $zero_count" >&2
    return 1
  fi
  echo "selftest: zero-match branch OK (count=$zero_count), did not abort under pipefail"

  positive_count=$(exact_process_count bash)
  if [[ "$positive_count" -le 0 ]]; then
    echo "selftest FAILED: expected a positive match count for 'bash', got $positive_count" >&2
    return 1
  fi
  echo "selftest: positive-match branch OK (count=$positive_count)"

  echo "selftest: exact-executable-name sequencing counter OK"
}

# --help and --selftest must exit before anything else runs, including
# argument validation, so neither touches curl/docker/nix or requires
# --checkpoint-aid/--witness-key.
for arg in "$@"; do
  if [[ "$arg" == "--help" ]]; then
    usage
    exit 0
  fi
  if [[ "$arg" == "--selftest" ]]; then
    selftest_sequencing
    exit $?
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) LIVE=1; shift ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --checkpoint-aid) CHECKPOINT_AID="$2"; shift 2 ;;
    --witness-key) WITNESS_KEY="$2"; shift 2 ;;
    --flake) FLAKE_REF="$2"; shift 2 ;;
    --skip-rebuild) SKIP_REBUILD=1; shift ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$LIVE" -ne 1 ]]; then
  echo "no --live given; nothing to do. Pass --help for usage." >&2
  exit 0
fi

if [[ -z "$CHECKPOINT_AID" || -z "$WITNESS_KEY" ]]; then
  echo "--live requires --checkpoint-aid and --witness-key" >&2
  exit 2
fi

for tool in curl jq docker; do
  command -v "$tool" >/dev/null || {
    echo "required tool not found: $tool" >&2
    exit 2
  }
done

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# ---------------------------------------------------------------------------
# Upstream safety: only ever stop/start the exact cardano-preprod container,
# and always leave it running -- an EXIT trap restarts it if this script
# stopped it and did not confirm it running again before exiting.
upstream_stopped_by_us=0
restore_upstream() {
  if [[ "$upstream_stopped_by_us" -eq 1 ]]; then
    log "EXIT cleanup: restoring $UPSTREAM_CONTAINER"
    docker start "$UPSTREAM_CONTAINER" >/dev/null || true
    upstream_stopped_by_us=0
  fi
}
trap restore_upstream EXIT

# ---------------------------------------------------------------------------
# Disk/tmpfs accounting -- / and /code are real disks, /run is a 32GiB tmpfs
# that filled to 100% once already; all three are tracked the same way.
sample_space() {
  df -k / /code /run 2>/dev/null | awk 'NR>1{print $1, $4}'
}

free_kib_for() {
  local mount="$1"
  df -k "$mount" | awk 'NR==2{print $4}'
}

# ---------------------------------------------------------------------------
# Query-process identity: PID, start time, and restart counters, so the
# recovery proof can show the query service was never touched.
sample_query_identity() {
  local pid unit_restarts container_restarts started_at exe
  pid=$(docker inspect --format '{{.State.Pid}}' ckeri-query-preprod 2>/dev/null || echo "")
  exe=""
  if [[ -n "$pid" && "$pid" != "0" ]]; then
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "")
  fi
  started_at=$(docker inspect --format '{{.State.StartedAt}}' ckeri-query-preprod 2>/dev/null || echo "")
  container_restarts=$(docker inspect --format '{{.RestartCount}}' ckeri-query-preprod 2>/dev/null || echo "")
  unit_restarts=$(systemctl show ckeri-query-preprod.service -p NRestarts --value 2>/dev/null || echo "")
  printf 'pid=%s exe=%s started_at=%s container_restarts=%s unit_restarts=%s\n' \
    "$pid" "$exe" "$started_at" "$container_restarts" "$unit_restarts"
}

# ---------------------------------------------------------------------------
# Public HTTP helpers -- nodeless: only the public HTTPS surface is used.
get_json() {
  curl -fsS "$BASE_URL$1"
}

get_status() {
  curl -s -o /dev/null -w '%{http_code}' "$BASE_URL$1"
}

assert_ready_true() {
  local body
  body=$(get_json /ready)
  echo "$body" | jq -e '.ready == true' >/dev/null
  echo "$body" | jq -r '"ready=true as_of_slot=" + (.as_of_slot|tostring) + " tip_lag_slots=" + (.tip_lag_slots|tostring)'
}

assert_ready_false() {
  local body
  body=$(get_json /ready)
  echo "$body" | jq -e '.ready == false' >/dev/null
  echo "$body" | jq -r '"ready=false upstream=" + .upstream + " reason=" + (.reason // "null")'
}

prove_data_routes() {
  local phase="$1"
  log "$phase: GET /checkpoint/$CHECKPOINT_AID"
  get_json "/checkpoint/$CHECKPOINT_AID" | jq -e '.as_of_slot != null' >/dev/null
  log "$phase: GET /board/$WITNESS_KEY"
  get_json "/board/$WITNESS_KEY" | jq -e '.as_of_slot != null' >/dev/null
  log "$phase: GET /watchability/$CHECKPOINT_AID"
  get_json "/watchability/$CHECKPOINT_AID" | jq -e '.as_of_slot != null' >/dev/null
}

prove_data_routes_unavailable() {
  local code
  code=$(get_status "/checkpoint/$CHECKPOINT_AID")
  [[ "$code" == "503" ]] || {
    echo "expected 503 on /checkpoint during outage, got $code" >&2
    exit 1
  }
  # the 503 body must carry no checkpoint field at all, not even null
  local body
  body=$(curl -s "$BASE_URL/checkpoint/$CHECKPOINT_AID")
  echo "$body" | jq -e 'has("checkpoint") | not' >/dev/null
  echo "$body" | jq -e '.error == "service_unavailable"' >/dev/null
}

# ---------------------------------------------------------------------------
# Journey
log "before: space $(sample_space | tr '\n' ' ')"
log "before: query identity $(sample_query_identity)"
identity_before=$(sample_query_identity)

log "pre-outage readiness/data proof"
assert_ready_true
prove_data_routes "pre-outage"

log "stopping upstream $UPSTREAM_CONTAINER"
docker stop "$UPSTREAM_CONTAINER" >/dev/null
upstream_stopped_by_us=1

log "proving fail-closed: ready=false and 503/no-payload"
sleep 1
assert_ready_false
prove_data_routes_unavailable

log "restoring upstream $UPSTREAM_CONTAINER"
docker start "$UPSTREAM_CONTAINER" >/dev/null
for _ in $(seq 1 60); do
  health=$(docker inspect --format '{{.State.Health.Status}}' "$UPSTREAM_CONTAINER" 2>/dev/null || echo "")
  [[ "$health" == "healthy" ]] && break
  sleep 2
done
[[ "$health" == "healthy" ]] || {
  echo "upstream did not become healthy in time" >&2
  exit 1
}
upstream_stopped_by_us=0

log "proving automatic recovery without restarting the query service"
recovered=0
for attempt in $(seq 1 30); do
  if get_json /ready | jq -e '.ready == true' >/dev/null 2>&1; then
    recovered=1
    log "automatic recovery observed on attempt $attempt"
    break
  fi
  sleep 2
done
[[ "$recovered" -eq 1 ]] || {
  echo "query did not automatically recover after upstream restart" >&2
  exit 1
}

# Two as_of_slot samples a minute apart is the decisive test that the
# service is genuinely following the chain, not frozen on a stale socket.
# An equal pair is the exact frozen-socket signature NOTE-013 recorded on
# the broken generation-93 instance (129920097 twice, 69s apart, while the
# container reported healthy), so the comparison must be strict: holding
# steady is a failure, not a pass, on preprod's ~20s block cadence.
sample_one=$(get_json /ready | jq -r '.as_of_slot')
log "as_of_slot before wait: $sample_one"
sleep 60
sample_two=$(get_json /ready | jq -r '.as_of_slot')
log "as_of_slot after wait: $sample_two"
[[ "$sample_two" -gt "$sample_one" ]] || {
  echo "as_of_slot did not advance (before=$sample_one after=$sample_two) -- holding steady is the known frozen-socket failure signature, not a pass" >&2
  exit 1
}

prove_data_routes "post-recovery"

identity_after=$(sample_query_identity)
log "after-recovery: query identity $identity_after"
[[ "$identity_before" == "$identity_after" ]] || {
  echo "query identity changed across the outage -- it was restarted:" >&2
  echo "  before: $identity_before" >&2
  echo "  after:  $identity_after" >&2
  exit 1
}
log "query PID unchanged, restart count 0 (or unchanged) across the outage -- automatic recovery confirmed"

if [[ "$SKIP_REBUILD" -eq 1 ]]; then
  log "skip-rebuild requested; outage/recovery journey complete"
  exit 0
fi

# ---------------------------------------------------------------------------
# Declarative rebuild journey (#176 T176-S3-6): re-run the declarative
# bring-up and prove the endpoint returns without any manual
# compose/container command against the query service.
log "rebuild: exact executable-name sequencing checks"
for exe in Runner.Worker nix-build nix; do
  count=$(exact_process_count "$exe")
  log "rebuild: pgrep -x $exe -> $count"
  [[ "$count" -eq 0 ]] || {
    echo "$exe is running; refusing to contend with it for the shared store" >&2
    exit 1
  }
done

root_free_start=$(free_kib_for /)
code_free_start=$(free_kib_for /code)
run_free_start=$(free_kib_for /run)
log "rebuild: start space / $((root_free_start / 1024 / 1024))GiB /code $((code_free_start / 1024 / 1024))GiB /run $((run_free_start / 1024 / 1024))GiB"
[[ "$((root_free_start / 1024 / 1024))" -ge "$REBUILD_START_FLOOR_GIB" ]] || {
  echo "/ below the ${REBUILD_START_FLOOR_GIB}GiB rebuild start floor; aborting" >&2
  exit 1
}

# Re-measure immediately before running the rebuild command: this host's
# free space is shared with CI runners and can move by tens of GiB between
# checks. A sharp unexplained drop here means something else took it.
root_free_immediate=$(free_kib_for /)
drop_gib=$(( (root_free_start - root_free_immediate) / 1024 / 1024 ))
if [[ "$drop_gib" -ge "$COMMAND_BURN_LIMIT_GIB" ]]; then
  echo "/ dropped ${drop_gib}GiB between the start check and the rebuild -- aborting rather than pushing through" >&2
  exit 1
fi
[[ "$((root_free_immediate / 1024 / 1024))" -ge "$ROOT_FLOOR_GIB" ]] || {
  echo "/ below the ${ROOT_FLOOR_GIB}GiB absolute floor immediately before the rebuild; aborting" >&2
  exit 1
}

log "rebuild: sudo nixos-rebuild switch --flake $FLAKE_REF"
sudo nixos-rebuild switch --flake "$FLAKE_REF"

root_free_end=$(free_kib_for /)
code_free_end=$(free_kib_for /code)
run_free_end=$(free_kib_for /run)
root_burn_gib=$(( (root_free_start - root_free_end) / 1024 / 1024 ))
code_burn_fraction=$(( (code_free_start - code_free_end) * 100 / code_free_start ))
log "rebuild: end space / $((root_free_end / 1024 / 1024))GiB /code $((code_free_end / 1024 / 1024))GiB /run $((run_free_end / 1024 / 1024))GiB"
log "rebuild: burn / ${root_burn_gib}GiB /code ${code_burn_fraction}% of pre-rebuild free"
[[ "$root_burn_gib" -lt "$COMMAND_BURN_LIMIT_GIB" ]] || {
  echo "rebuild burned ${root_burn_gib}GiB on / (limit ${COMMAND_BURN_LIMIT_GIB}GiB)" >&2
  exit 1
}
[[ "$code_burn_fraction" -lt "$CODE_BURN_FRACTION" ]] || {
  echo "rebuild burned ${code_burn_fraction}% of /code free space (limit ${CODE_BURN_FRACTION}%)" >&2
  exit 1
}

sleep 5
root_free_settled=$(free_kib_for /)
[[ "$root_free_settled" -ge "$root_free_end" ]] || {
  echo "/ kept shrinking after the rebuild exited -- treat as unbounded/post-exit burn and escalate" >&2
  exit 1
}

log "post-rebuild readiness/data proof"
assert_ready_true
prove_data_routes "post-rebuild"

log "declarative rebuild journey complete; endpoint returned without any manual query-service command"
