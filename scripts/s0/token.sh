# Shared BUILD-TOKEN helpers. Source this file; do not execute it.
TOKEN=${TOKEN:-/tmp/ms-keri-11/BUILD-TOKEN}
LANE=${S0_BUILD_LANE:-S0/commit-owner-1}
MIN_START_BYTES=$((5310 * 1073741824 / 100))
STOP_AT_BYTES=$((50 * 1073741824))
s0_acquired=0

s0_release_token() {
  if ((s0_acquired)); then
    rm -rf "$TOKEN"
    s0_acquired=0
  fi
}

s0_acquire_token() {
  trap s0_release_token EXIT INT TERM
  while ! mkdir "$TOKEN" 2>/dev/null; do
    local holder
    holder=$(cat "$TOKEN/lane" 2>/dev/null || true)
    if [[ -z "$holder" && -f "$TOKEN/meta" ]]; then
      holder=$(sed -n 's/^lane=//p' "$TOKEN/meta" | head -n 1)
    fi
    printf 'S0-TOKEN-WAIT lane=%s holder=%s\n' \
      "$LANE" "${holder:-unknown}" >&2
    sleep 5
  done
  s0_acquired=1
  date -u +%Y-%m-%dT%H:%M:%SZ >"$TOKEN/start"
  printf '%s\n' "$LANE" >"$TOKEN/lane"
}

s0_record_avail() {
  local dest=$1
  local avail
  avail=$(df -B1 --output=avail /nix/store | tail -n 1 | tr -d ' ')
  printf '%s\n' "$avail" >"$TOKEN/avail"
  if [[ -n "$dest" ]]; then
    printf '%s\n' "$avail" >"$dest"
  fi
  if ((avail < MIN_START_BYTES)); then
    printf 'S0-TOKEN-REFUSE avail=%s min_start=%s\n' \
      "$avail" "$MIN_START_BYTES" >&2
    exit 51
  fi
  if ((avail <= STOP_AT_BYTES)); then
    printf 'S0-TOKEN-STOP avail=%s stop_at=%s\n' "$avail" "$STOP_AT_BYTES" >&2
    exit 52
  fi
}

s0_run_aiken() {
  local desc=$1
  local log=$2
  local avail_file=$3
  shift 3
  local cmd
  cmd=$(printf '%q ' "$@")
  s0_record_avail "$avail_file"
  set +e
  script -qec "$cmd" /dev/null >"$log" 2>&1
  local status=$?
  set +e
  printf '%s\n' "$status" >"${log}.exit"
  if ((status != 0)); then
    printf 'S0-AIKEN-FAIL step=%s exit=%s log=%s\n' "$desc" "$status" "$log" >&2
  fi
  return "$status"
}
