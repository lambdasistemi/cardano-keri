#!/usr/bin/env bash
# S0-F09 / S0-M10 — measure or verify the seven-member family.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=token.sh
source "$here/token.sh"

EXPECTED_TOOL_SHA=c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689
REF_CEILING=16133
TX_CEILING=16384
REDESIGN_AT=12907
CAVEAT='size-only; transaction-fit unproven'
TRACE_LEVEL=silent

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
  printf 'usage: %s verify|measure|self-test --repo DIR --aiken ABS --report FILE --evidence-dir DIR\n' \
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

else_title_for() {
  case "$1" in
    append) printf '%s' 's0_append.s0_append.else' ;;
    cursor) printf '%s' 's0_cursor.s0_cursor.else' ;;
    lineage) printf '%s' 's0_lineage.s0_lineage.else' ;;
    maintenance_escrow)
      printf '%s' 's0_maintenance_escrow.s0_maintenance_escrow.else'
      ;;
    staging_proof_token)
      printf '%s' 's0_staging_proof_token.s0_staging_proof_token.else'
      ;;
    consumer_predicates)
      printf '%s' 's0_consumer_predicates.s0_consumer_predicates.else'
      ;;
    reference_cursor_consumer)
      printf '%s' 's0_reference_cursor_consumer.s0_reference_cursor_consumer.else'
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

classify() {
  local bytes=$1
  if ((bytes >= REDESIGN_AT)); then
    printf '%s' REDESIGN
  else
    printf '%s' PASS
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
      onchain/validators/s0_skeleton_tests.ak \
      scripts/s0 -type f | sort | xargs sha256sum
  ) | sha256sum | awk '{print $1}'
}

hex_of() {
  local blueprint=$1
  local title=$2
  jq -r --arg t "$title" \
    '[.validators[] | select(.title == $t) | .compiledCode // empty] | .[]' \
    "$blueprint"
}

measure_blueprint() {
  local blueprint=$1
  local rows_out=$2
  local emit_verdict=$3

  mapfile -t all_s0 < <(jq -r '.validators[].title' "$blueprint" | command grep -E '^s0_' | sort)
  expected_all=()
  for member in "${MEMBERS[@]}"; do
    expected_all+=("$(title_for "$member")")
    expected_all+=("$(else_title_for "$member")")
  done
  mapfile -t expected_sorted < <(printf '%s\n' "${expected_all[@]}" | sort)
  if [[ "${all_s0[*]}" != "${expected_sorted[*]}" ]]; then
    printf 'S0-MEASURE-FAIL unexpected-or-missing-s0-titles\n' >&2
    printf ' expected=%s\n' "${expected_sorted[*]}" >&2
    printf ' actual=%s\n' "${all_s0[*]}" >&2
    return 35
  fi

  : >"$rows_out"
  declare -A seen_titles=()
  for member in "${MEMBERS[@]}"; do
    local title else_title
    title=$(title_for "$member")
    else_title=$(else_title_for "$member")
    if [[ -n "${seen_titles[$title]:-}" ]]; then
      printf 'S0-MEASURE-FAIL duplicate-title title=%s\n' "$title" >&2
      return 36
    fi
    seen_titles[$title]=1
    mapfile -t codes < <(hex_of "$blueprint" "$title")
    mapfile -t else_codes < <(hex_of "$blueprint" "$else_title")
    if ((${#codes[@]} == 0)); then
      printf 'S0-MEASURE-FAIL missing-title title=%s\n' "$title" >&2
      return 37
    fi
    if ((${#codes[@]} != 1 || ${#else_codes[@]} != 1)); then
      printf 'S0-MEASURE-FAIL duplicate-or-missing-else title=%s\n' "$title" >&2
      return 36
    fi
    local hex=${codes[0]}
    local else_hex=${else_codes[0]}
    if [[ -z "$hex" ]]; then
      printf 'S0-MEASURE-FAIL empty-compiledCode title=%s\n' "$title" >&2
      return 38
    fi
    if ((${#hex} % 2 != 0)); then
      printf 'S0-MEASURE-FAIL odd-length-compiledCode title=%s len=%s\n' \
        "$title" "${#hex}" >&2
      return 39
    fi
    if [[ "$hex" != "$else_hex" ]]; then
      printf 'S0-MEASURE-FAIL else-sibling-mismatch title=%s else=%s\n' \
        "$title" "$else_title" >&2
      return 42
    fi
    local bytes=$((${#hex} / 2))
    local ref_pct tx_pct ref_head tx_head threshold
    ref_pct=$(format_pct "$bytes" "$REF_CEILING")
    tx_pct=$(format_pct "$bytes" "$TX_CEILING")
    ref_head=$((REF_CEILING - bytes))
    tx_head=$((TX_CEILING - bytes))
    threshold=$(classify "$bytes")
    if [[ "$emit_verdict" == yes ]]; then
      printf 'BARE-VERDICT member=%s bytes=%s reference_pct=%s reference_headroom=%s tx_pct=%s tx_headroom=%s threshold=%s caveat="%s"\n' \
        "$member" "$bytes" "$ref_pct" "$ref_head" "$tx_pct" "$tx_head" \
        "$threshold" "$CAVEAT"
    fi
    printf 'S0-ROW member=%s title=%s bytes=%s reference_pct=%s reference_headroom=%s tx_pct=%s tx_headroom=%s threshold=%s caveat="%s"\n' \
      "$member" "$title" "$bytes" "$ref_pct" "$ref_head" "$tx_pct" "$tx_head" \
      "$threshold" "$CAVEAT" >>"$rows_out"
  done
  return 0
}

parse_table_rows() {
  local report=$1
  local dest=$2
  : >"$dest"
  local line member title bytes ref_pct ref_head tx_pct tx_head threshold
  local row_pat='^\| ([a-z_]+) \| `([^`]+)` \| ([0-9]+) \| ([0-9.]+) \| (-?[0-9]+) \| ([0-9.]+) \| (-?[0-9]+) \| ([A-Z]+) \|'
  while IFS= read -r line; do
    [[ "$line" =~ $row_pat ]] || continue
    member=${BASH_REMATCH[1]}
    title=${BASH_REMATCH[2]}
    bytes=${BASH_REMATCH[3]}
    ref_pct=${BASH_REMATCH[4]}
    ref_head=${BASH_REMATCH[5]}
    tx_pct=${BASH_REMATCH[6]}
    tx_head=${BASH_REMATCH[7]}
    threshold=${BASH_REMATCH[8]}
    printf 'S0-ROW member=%s title=%s bytes=%s reference_pct=%s reference_headroom=%s tx_pct=%s tx_headroom=%s threshold=%s caveat="%s"\n' \
      "$member" "$title" "$bytes" "$ref_pct" "$ref_head" "$tx_pct" "$tx_head" \
      "$threshold" "$CAVEAT" >>"$dest"
  done <"$report"
}

write_report() {
  local dest=$1
  local source_commit=$2
  cat >"$dest" <<EOF
# S0 family size report

Architectural measurement of seven separately compiled skeletons.
Every row and verdict is ${CAVEAT}.

## Toolchain

- path: \`${aiken}\`
- version: \`${aiken_version}\`
- sha256: \`${tool_sha}\`
Trace level: \`${TRACE_LEVEL}\`

## Source and blueprint identity

Measured source commit: \`${source_commit}\`
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
    local member title bytes ref_pct ref_head tx_pct tx_head threshold
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

## Residuals

- Tx-A inherits the released 1024-byte premint cap. A 1,049-byte 8-key
  inception is refused at premint and never reaches append.
- G1 coupling 15,155,350 mem / 7,631,646,035 CPU is a two-transaction sum
  of the heaviest measured role instances: not a per-transaction limit,
  not headroom, not one AID's coupling. Per-role budgets remain S2.
- \`g1_c4_input_393\` and \`g1_c4_input_966\` are excluded (known broken
  SAID/offset fixtures). The 1024-byte boundary fact may be cited.
- Two transactions make \`${CAVEAT}\` more load-bearing, not less.

## Machine rows

\`\`\`
EOF
  cat "$rows_file" >>"$dest"
  printf '\n```\n' >>"$dest"
}

synthetic_blueprint() {
  local dest=$1
  shift
  printf '{"validators":[' >"$dest"
  local first=1
  local title code
  for spec in "$@"; do
    title=${spec%%=*}
    code=${spec#*=}
    if ((first)); then first=0; else printf ',' >>"$dest"; fi
    printf '{"title":"%s","compiledCode":"%s"}' "$title" "$code" >>"$dest"
  done
  printf ']}\n' >>"$dest"
}

complete_titles() {
  local code=$1
  local specs=()
  local member
  for member in "${MEMBERS[@]}"; do
    specs+=("$(title_for "$member")=$code")
    specs+=("$(else_title_for "$member")=$code")
  done
  printf '%s\n' "${specs[@]}"
}

run_self_test() {
  local work=$evidence_dir/self-test
  mkdir -p "$work"
  local rows=$work/rows.txt
  local rc

  # 12906 PASS / 12907 REDESIGN
  [[ $(classify 12906) == PASS ]] || {
    printf 'S0-MEASURE-SELF-TEST-FAIL classify-12906\n' >&2
    exit 40
  }
  [[ $(classify 12907) == REDESIGN ]] || {
    printf 'S0-MEASURE-SELF-TEST-FAIL classify-12907\n' >&2
    exit 40
  }

  # missing title
  synthetic_blueprint "$work/missing.json" \
    s0_append.s0_append.spend=aa \
    s0_append.s0_append.else=aa
  set +e
  measure_blueprint "$work/missing.json" "$rows" no
  rc=$?
  set -e
  ((rc != 0)) || {
    printf 'S0-MEASURE-SELF-TEST-FAIL missing-not-rejected\n' >&2
    exit 40
  }

  # duplicate compiled entries of same title via two identical objects
  printf '{"validators":[{"title":"s0_append.s0_append.spend","compiledCode":"aa"},{"title":"s0_append.s0_append.spend","compiledCode":"aa"}]}\n' \
    >"$work/dup.json"
  # pad with expected others? measure fails first on unexpected set
  set +e
  measure_blueprint "$work/dup.json" "$rows" no
  rc=$?
  set -e
  ((rc != 0)) || {
    printf 'S0-MEASURE-SELF-TEST-FAIL duplicate-not-rejected\n' >&2
    exit 40
  }

  # empty compiledCode
  mapfile -t specs < <(complete_titles '')
  synthetic_blueprint "$work/empty.json" "${specs[@]}"
  set +e
  measure_blueprint "$work/empty.json" "$rows" no
  rc=$?
  set -e
  ((rc != 0)) || {
    printf 'S0-MEASURE-SELF-TEST-FAIL empty-not-rejected\n' >&2
    exit 40
  }

  # odd-length
  mapfile -t specs < <(complete_titles abc)
  synthetic_blueprint "$work/odd.json" "${specs[@]}"
  set +e
  measure_blueprint "$work/odd.json" "$rows" no
  rc=$?
  set -e
  ((rc != 0)) || {
    printf 'S0-MEASURE-SELF-TEST-FAIL odd-length-not-rejected\n' >&2
    exit 40
  }

  # unexpected handler suffix
  mapfile -t specs < <(complete_titles aa)
  specs+=("s0_append.s0_append.withdraw=aa")
  synthetic_blueprint "$work/unexpected.json" "${specs[@]}"
  set +e
  measure_blueprint "$work/unexpected.json" "$rows" no
  rc=$?
  set -e
  ((rc != 0)) || {
    printf 'S0-MEASURE-SELF-TEST-FAIL unexpected-handler-not-rejected\n' >&2
    exit 40
  }

  # display-table drift
  mapfile -t specs < <(complete_titles aabb)
  synthetic_blueprint "$work/ok.json" "${specs[@]}"
  measure_blueprint "$work/ok.json" "$rows" no
  cat >"$work/drift-report.md" <<EOF
| member | title | bytes | ref % | ref headroom | tx % | tx headroom | threshold | caveat |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| append | \`s0_append.s0_append.spend\` | 9999 | 0.00 | 0 | 0.00 | 0 | PASS | ${CAVEAT} |

\`\`\`
$(cat "$rows")
\`\`\`
EOF
  parse_table_rows "$work/drift-report.md" "$work/table-rows.txt"
  if cmp -s "$rows" "$work/table-rows.txt"; then
    printf 'S0-MEASURE-SELF-TEST-FAIL display-drift-not-detected\n' >&2
    exit 40
  fi

  printf 'S0-MEASURE-SELF-TEST-PASS\n'
}

[[ $# -ge 1 ]] || usage
mode=$1
shift
[[ "$mode" == verify || "$mode" == measure || "$mode" == self-test ]] || usage

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
mkdir -p "$evidence_dir"
evidence_dir=$(cd "$evidence_dir" && pwd)
[[ -x "$aiken" ]] || {
  printf 'S0-MEASURE-FAIL missing-aiken path=%s\n' "$aiken" >&2
  exit 32
}

if [[ "$mode" == self-test ]]; then
  run_self_test
  exit 0
fi

s0_acquire_token

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
printf '%s\n' "$TRACE_LEVEL" >"$evidence_dir/trace-level.txt"

blueprint=$repo/onchain/plutus.json
set +e
s0_run_aiken build \
  "$evidence_dir/aiken-build.log" \
  "$evidence_dir/pre-build-avail-bytes.txt" \
  env -C "$repo/onchain" "$aiken" build -t silent
build_rc=$?
set -e
if ((build_rc != 0)); then
  exit "$build_rc"
fi

if [[ ! -f "$blueprint" ]]; then
  printf 'S0-MEASURE-FAIL missing-blueprint path=%s\n' "$blueprint" >&2
  exit 34
fi
cp "$blueprint" "$evidence_dir/plutus.json"
blueprint_sha=$(sha256sum "$blueprint" | awk '{print $1}')
printf '%s\n' "$blueprint_sha" >"$evidence_dir/plutus.json.sha256"
source_sha=$(source_tree_hash "$repo")
printf '%s\n' "$source_sha" >"$evidence_dir/source-tree.sha256"
source_commit=$(git -C "$repo" rev-parse HEAD)

rows_file=$evidence_dir/rows.txt
measure_blueprint "$blueprint" "$rows_file" yes

if [[ "$mode" == measure ]]; then
  write_report "$report" "$source_commit"
  printf 'S0-MEASURE-PASS report=%s blueprint_sha=%s tool_sha=%s\n' \
    "$report" "$blueprint_sha" "$tool_sha"
  exit 0
fi

if [[ ! -f "$report" ]]; then
  printf 'S0-MEASURE-FAIL missing-report path=%s\n' "$report" >&2
  exit 34
fi

expected_rows=$evidence_dir/expected-rows.txt
command grep -E '^S0-ROW ' "$report" >"$expected_rows"
if ! cmp -s "$rows_file" "$expected_rows"; then
  printf 'S0-MEASURE-FAIL report-mismatch\n' >&2
  diff -u "$expected_rows" "$rows_file" >&2 || true
  exit 40
fi

table_rows=$evidence_dir/table-rows.txt
parse_table_rows "$report" "$table_rows"
if ! cmp -s "$rows_file" "$table_rows"; then
  printf 'S0-MEASURE-FAIL display-table-mismatch\n' >&2
  diff -u "$rows_file" "$table_rows" >&2 || true
  exit 40
fi

for member in "${MEMBERS[@]}"; do
  title=$(title_for "$member")
  if ! command grep -Fq "\`$title\`" "$report"; then
    printf 'S0-MEASURE-FAIL title-mapping-missing title=%s\n' "$title" >&2
    exit 41
  fi
done

if ! command grep -Fq "$CAVEAT" "$report"; then
  printf 'S0-MEASURE-FAIL missing-caveat\n' >&2
  exit 41
fi
if ! command grep -Fq "$tool_sha" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-toolchain-hash\n' >&2
  exit 41
fi
if ! command grep -Fq "$blueprint_sha" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-blueprint-hash\n' >&2
  exit 41
fi
if ! command grep -Fq "$source_sha" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-source-hash\n' >&2
  exit 41
fi
if ! command grep -Fq "Trace level: \`$TRACE_LEVEL\`" "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-trace-level\n' >&2
  exit 41
fi
if ! command grep -Eq '^Measured source commit: `[0-9a-f]{40}`$' "$report"; then
  printf 'S0-MEASURE-FAIL report-missing-source-commit\n' >&2
  exit 41
fi
reported_source=$(
  sed -nE 's/^Measured source commit: `([0-9a-f]{40})`$/\1/p' "$report"
)
if [[ -z "$reported_source" ]] || ! git -C "$repo" cat-file -e "$reported_source^{commit}"; then
  printf 'S0-MEASURE-FAIL report-source-commit-invalid\n' >&2
  exit 41
fi

printf 'S0-MEASURE-PASS report=%s blueprint_sha=%s tool_sha=%s\n' \
  "$report" "$blueprint_sha" "$tool_sha"
