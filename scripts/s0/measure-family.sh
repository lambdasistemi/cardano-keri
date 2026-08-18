#!/usr/bin/env bash
# S0-F09 / S0-M10 — measure or verify the seven-member family.
set -euo pipefail

TOKEN=/tmp/ms-keri-11/BUILD-TOKEN
LANE=${S0_BUILD_LANE:-S0/commit-owner-1}
MIN_START_BYTES=$((5310 * 1073741824 / 100))
STOP_AT_BYTES=$((50 * 1073741824))
REF_CEILING=16133
TX_CEILING=16384
REDESIGN_AT=12907
CAVEAT='size-only; transaction-fit unproven'
EXPECTED_TOOL_SHA=c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689

MEMBERS=(
  append
  cursor
  lineage
  maintenance_escrow
  staging_proof_token
  consumer_predicates
  reference_cursor_consumer
)

usage() {
  printf 'usage: %s verify|measure --repo DIR --aiken ABS --report FILE --evidence-dir DIR\n' \
    "$0" >&2
  exit 2
}

title_for() {
  case "$1" in
    append) printf '%s' 's0_append.s0_append.spend' ;;
    cursor) printf '%s' 's0_cursor.s0_cursor.spend' ;;
    lineage) printf '%s' 's0_lineage.s0_lineage.spend' ;;
    maintenance_escrow)
      printf '%s' 's0_maintenance_escrow.s0_maintenance_escrow.spend'
      ;;
    staging_proof_token)
      printf '%s' 's0_staging_proof_token.s0_staging_proof_token.mint'
      ;;
    consumer_predicates)
      printf '%s' 's0_consumer_predicates.s0_consumer_predicates.spend'
      ;;
    reference_cursor_consumer)
      printf '%s' 's0_reference_cursor_consumer.s0_reference_cursor_consumer.spend'
      ;;
    *) return 1 ;;
  esac
}

format_pct() {
  local bytes=$1
  local ceiling=$2
  local scaled=$((bytes * 10000 / ceiling))
  printf '%d.%02d' $((scaled / 100)) $((scaled % 100))
}

release_token() {
  if [[ -d "$TOKEN" && "$(cat "$TOKEN/lane" 2>/dev/null || true)" == "$LANE" ]]; then
    rm -rf "$TOKEN"
  fi
}

acquire_token() {
  while ! mkdir "$TOKEN" 2>/dev/null; do
    printf 'S0-TOKEN-WAIT lane=%s holder=%s\n' \
      "$LANE" "$(cat "$TOKEN/lane" 2>/dev/null || echo unknown)" >&2
    sleep 5
  done
  trap release_token EXIT INT TERM
  date -u +%Y-%m-%dT%H:%M:%SZ >"$TOKEN/start"
  printf '%s\n' "$LANE" >"$TOKEN/lane"
}

check_disk_and_record() {
  local avail
  avail=$(df -B1 --output=avail /nix/store | tail -n 1 | tr -d ' ')
  printf '%s\n' "$avail" >"$TOKEN/avail"
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

run_aiken() {
  local desc=$1
  shift
  local log=$1
  shift
  local cmd
  cmd=$(printf '%q ' "$@")
  check_disk_and_record
  set +e
  script -qec "$cmd" /dev/null >"$log" 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status" >"${log}.exit"
  if ((status != 0)); then
    printf 'S0-MEASURE-FAIL step=%s exit=%s log=%s\n' "$desc" "$status" "$log" >&2
    exit "$status"
  fi
}

source_tree_hash() {
  local repo=$1
  (
    cd "$repo"
    find onchain/lib/cardano_keri/m12 \
      onchain/validators/s0_append.ak \
      onchain/validators/s0_cursor.ak \
      onchain/validators/s0_lineage.ak \
      onchain/validators/s0_maintenance_escrow.ak \
      onchain/validators/s0_staging_proof_token.ak \
      onchain/validators/s0_consumer_predicates.ak \
      onchain/validators/s0_reference_cursor_consumer.ak \
      scripts/s0 -type f | sort | xargs sha256sum
  ) | sha256sum | awk '{print $1}'
}

[[ $# -ge 1 ]] || usage
mode=$1
shift
[[ "$mode" == verify || "$mode" == measure ]] || usage

repo=
aiken=
report=
evidence_dir=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo=$2
      shift 2
      ;;
    --aiken)
      aiken=$2
      shift 2
      ;;
    --report)
      report=$2
      shift 2
      ;;
    --evidence-dir)
      evidence_dir=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

[[ -n "$repo" && -n "$aiken" && -n "$report" && -n "$evidence_dir" ]] || usage
repo=$(cd "$repo" && pwd)
[[ -x "$aiken" ]] || {
  printf 'S0-MEASURE-FAIL missing-aiken path=%s\n' "$aiken" >&2
  exit 32
}
mkdir -p "$evidence_dir"
evidence_dir=$(cd "$evidence_dir" && pwd)

acquire_token

tool_sha=$(sha256sum "$aiken" | awk '{print $1}')
if [[ "$tool_sha" != "$EXPECTED_TOOL_SHA" ]]; then
  printf 'S0-MEASURE-FAIL toolchain-hash expected=%s actual=%s\n' \
    "$EXPECTED_TOOL_SHA" "$tool_sha" >&2
  exit 32
fi
aiken_version=$("$aiken" --version | tr -d '\r')
printf '%s\n' "$tool_sha" >"$evidence_dir/aiken.sha256"
printf '%s\n' "$aiken_version" >"$evidence_dir/aiken.version"
printf '%s\n' "$aiken" >"$evidence_dir/aiken.path"

blueprint=$repo/onchain/plutus.json
run_aiken build "$evidence_dir/aiken-build.log" \
  env -C "$repo/onchain" "$aiken" build -t verbose

if [[ ! -f "$blueprint" ]]; then
  printf 'S0-MEASURE-FAIL missing-blueprint path=%s\n' "$blueprint" >&2
  exit 34
fi
cp "$blueprint" "$evidence_dir/plutus.json"
blueprint_sha=$(sha256sum "$blueprint" | awk '{print $1}')
printf '%s\n' "$blueprint_sha" >"$evidence_dir/plutus.json.sha256"
source_sha=$(source_tree_hash "$repo")
printf '%s\n' "$source_sha" >"$evidence_dir/source-tree.sha256"

mapfile -t s0_titles < <(
  jq -r '.validators[].title' "$blueprint" |
    grep -E '^s0_.*\.(spend|mint)$' | sort
)

expected_titles=()
for member in "${MEMBERS[@]}"; do
  expected_titles+=("$(title_for "$member")")
done
mapfile -t expected_sorted < <(printf '%s\n' "${expected_titles[@]}" | sort)

if [[ "${s0_titles[*]}" != "${expected_sorted[*]}" ]]; then
  printf 'S0-MEASURE-FAIL unexpected-or-missing-s0-titles\n' >&2
  printf ' expected=%s\n' "${expected_sorted[*]}" >&2
  printf ' actual=%s\n' "${s0_titles[*]}" >&2
  exit 35
fi

rows_file=$evidence_dir/rows.txt
: >"$rows_file"
declare -A seen_titles=()

for member in "${MEMBERS[@]}"; do
  title=$(title_for "$member")
  if [[ -n "${seen_titles[$title]:-}" ]]; then
    printf 'S0-MEASURE-FAIL duplicate-title title=%s\n' "$title" >&2
    exit 36
  fi
  seen_titles[$title]=1
  mapfile -t codes < <(
    jq -r --arg t "$title" \
      '.validators[] | select(.title == $t) | .compiledCode // empty' \
      "$blueprint"
  )
  if ((${#codes[@]} == 0)); then
    printf 'S0-MEASURE-FAIL missing-title title=%s\n' "$title" >&2
    exit 37
  fi
  if ((${#codes[@]} != 1)); then
    printf 'S0-MEASURE-FAIL duplicate-title title=%s count=%s\n' \
      "$title" "${#codes[@]}" >&2
    exit 36
  fi
  hex=${codes[0]}
  if [[ -z "$hex" ]]; then
    printf 'S0-MEASURE-FAIL empty-compiledCode title=%s\n' "$title" >&2
    exit 38
  fi
  if ((${#hex} % 2 != 0)); then
    printf 'S0-MEASURE-FAIL odd-length-compiledCode title=%s len=%s\n' \
      "$title" "${#hex}" >&2
    exit 39
  fi
  bytes=$((${#hex} / 2))
  ref_pct=$(format_pct "$bytes" "$REF_CEILING")
  tx_pct=$(format_pct "$bytes" "$TX_CEILING")
  ref_head=$((REF_CEILING - bytes))
  tx_head=$((TX_CEILING - bytes))
  if ((bytes >= REDESIGN_AT)); then
    threshold=REDESIGN
  else
    threshold=PASS
  fi
  printf 'BARE-VERDICT member=%s bytes=%s reference_pct=%s reference_headroom=%s tx_pct=%s tx_headroom=%s threshold=%s caveat="%s"\n' \
    "$member" "$bytes" "$ref_pct" "$ref_head" "$tx_pct" "$tx_head" \
    "$threshold" "$CAVEAT"
  printf 'S0-ROW member=%s title=%s bytes=%s reference_pct=%s reference_headroom=%s tx_pct=%s tx_headroom=%s threshold=%s caveat="%s"\n' \
    "$member" "$title" "$bytes" "$ref_pct" "$ref_head" "$tx_pct" "$tx_head" \
    "$threshold" "$CAVEAT" >>"$rows_file"
done

write_report() {
  local dest=$1
  cat >"$dest" <<EOF
# S0 family size report

Architectural measurement of seven separately compiled skeletons.
Every row and verdict is ${CAVEAT}.

## Toolchain

- path: \`${aiken}\`
- version: \`${aiken_version}\`
- sha256: \`${tool_sha}\`

## Source and blueprint identity

- owned-source sha256: \`${source_sha}\`
- blueprint sha256: \`${blueprint_sha}\`
- reproduction command:

\`\`\`
scripts/s0/measure-family.sh verify \\
  --repo <repo> \\
  --aiken ${aiken} \\
  --report specs/m11-s0-size-failfast/SIZE-REPORT.md \\
  --evidence-dir <fresh-directory>
\`\`\`

Runtime evidence directories are not the committed identity.

## Title mapping

| member | blueprint title |
| --- | --- |
| append | \`s0_append.s0_append.spend\` |
| cursor | \`s0_cursor.s0_cursor.spend\` |
| lineage | \`s0_lineage.s0_lineage.spend\` |
| maintenance_escrow | \`s0_maintenance_escrow.s0_maintenance_escrow.spend\` |
| staging_proof_token | \`s0_staging_proof_token.s0_staging_proof_token.mint\` |
| consumer_predicates | \`s0_consumer_predicates.s0_consumer_predicates.spend\` |
| reference_cursor_consumer | \`s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend\` |

## Rows

| member | title | bytes | ref % | ref headroom | tx % | tx headroom | threshold | caveat |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
EOF
  while read -r line; do
    member=$(sed -n 's/.*member=\([^ ]*\).*/\1/p' <<<"$line")
    title=$(sed -n 's/.*title=\([^ ]*\).*/\1/p' <<<"$line")
    bytes=$(sed -n 's/.*bytes=\([^ ]*\).*/\1/p' <<<"$line")
    ref_pct=$(sed -n 's/.*reference_pct=\([^ ]*\).*/\1/p' <<<"$line")
    ref_head=$(sed -n 's/.*reference_headroom=\([^ ]*\).*/\1/p' <<<"$line")
    tx_pct=$(sed -n 's/.*tx_pct=\([^ ]*\).*/\1/p' <<<"$line")
    tx_head=$(sed -n 's/.*tx_headroom=\([^ ]*\).*/\1/p' <<<"$line")
    threshold=$(sed -n 's/.*threshold=\([^ ]*\).*/\1/p' <<<"$line")
    printf '| %s | `%s` | %s | %s | %s | %s | %s | %s | %s |\n' \
      "$member" "$title" "$bytes" "$ref_pct" "$ref_head" "$tx_pct" \
      "$tx_head" "$threshold" "$CAVEAT" >>"$dest"
  done <"$rows_file"

  cat >>"$dest" <<EOF

Percentages are truncated display values from integer arithmetic
\`bytes * 10000 / ceiling\`. Threshold uses integer bytes:
\`>= ${REDESIGN_AT}\` is \`REDESIGN\`. Headroom is signed and not clamped.

## Machine rows

\`\`\`
EOF
  cat "$rows_file" >>"$dest"
  printf '\n```\n' >>"$dest"
}

if [[ "$mode" == measure ]]; then
  write_report "$report"
  printf 'S0-MEASURE-PASS report=%s blueprint_sha=%s tool_sha=%s\n' \
    "$report" "$blueprint_sha" "$tool_sha"
  exit 0
fi

if [[ ! -f "$report" ]]; then
  printf 'S0-MEASURE-FAIL missing-report path=%s\n' "$report" >&2
  exit 34
fi

expected_rows=$evidence_dir/expected-rows.txt
grep -E '^S0-ROW ' "$report" >"$expected_rows"
if ! cmp -s "$rows_file" "$expected_rows"; then
  printf 'S0-MEASURE-FAIL report-mismatch\n' >&2
  diff -u "$expected_rows" "$rows_file" >&2 || true
  exit 40
fi

if ! grep -Fq "$CAVEAT" "$report"; then
  printf 'S0-MEASURE-FAIL missing-caveat\n' >&2
  exit 41
fi
if ! grep -Fq "$tool_sha" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-toolchain-hash\n' >&2
  exit 41
fi
if ! grep -Fq "$blueprint_sha" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-blueprint-hash\n' >&2
  exit 41
fi
if ! grep -Fq "$source_sha" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-source-hash\n' >&2
  exit 41
fi

printf 'S0-MEASURE-PASS report=%s blueprint_sha=%s tool_sha=%s\n' \
  "$report" "$blueprint_sha" "$tool_sha"
