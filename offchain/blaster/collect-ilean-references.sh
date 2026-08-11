#!/usr/bin/env bash
set -euo pipefail

if (( $# < 3 )); then
  echo 'usage: collect-ilean-references.sh BUILD_ROOT SOURCE_ROOT FILE...' >&2
  exit 64
fi

build_root="$1"
source_root="$2"
shift 2

required_env=(
  AUDIT_LEAN_BLASTER_ROOT AUDIT_PLUTUS_CORE_ROOT AUDIT_LEDGER_API_ROOT
)
for name in "${required_env[@]}"; do
  if [[ -z ${!name:-} || ! -d ${!name} ]]; then
    printf 'AUDIT-DISCOVERY construct=ilean-module-ownership outcome=COULD-NOT-EVALUATE layer=module-ownership\n' >&2
    printf 'collect-ilean-references: package source root unavailable: %s\n' "$name" >&2
    exit 1
  fi
done

fail_discovery() {
  local source="$1" construct="$2" layer="$3" message="$4"
  printf 'AUDIT-DISCOVERY source_path=%s construct=%s outcome=COULD-NOT-EVALUATE layer=%s\n' \
    "$source" "$construct" "$layer" >&2
  printf 'collect-ilean-references: %s\n' "$message" >&2
  exit 1
}

module_path() {
  printf '%s.lean' "${1//./\/}"
}

package_for_module() {
  local module="$1" path
  path="$(module_path "$module")"
  if [[ -f $AUDIT_LEAN_BLASTER_ROOT/$path ]]; then
    printf '%s' leanBlaster
  elif [[ -f $AUDIT_PLUTUS_CORE_ROOT/$path ]]; then
    printf '%s' plutusCoreBlaster
  elif [[ -f $AUDIT_LEDGER_API_ROOT/$path ]]; then
    printf '%s' cardanoLedgerApiBlaster
  fi
}

is_declared_name() {
  [[ $1 == Blaster || $1 == Blaster.* \
    || $1 == PlutusCore || $1 == PlutusCore.* || $1 == Cryptograph || $1 == Cryptograph.* \
    || $1 == CardanoLedgerApi || $1 == CardanoLedgerApi.* ]]
}

is_internal_module() {
  [[ $1 == KeriBlaster || $1 == KeriBlaster.* \
    || $1 == Init || $1 == Init.* || $1 == Lean || $1 == Lean.* \
    || $1 == Std || $1 == Std.* || $1 == Lake || $1 == Lake.* ]]
}

declare -A seen_source=()
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
: >"$work/rows"

for source in "$@"; do
  relative="${source#"$source_root"/}"
  source_path="offchain/blaster/$relative"
  [[ $source != "$relative" && -f $source ]] \
    || fail_discovery "$source_path" tracked-source source-mapping "source is outside the tracked root or absent: $source"
  [[ $relative == KeriBlaster.lean || $relative == KeriBlaster/*.lean ]] \
    || fail_discovery "$source_path" tracked-source source-mapping "source is outside the tracked bridge set: $relative"
  [[ -z ${seen_source[$relative]:-} ]] \
    || fail_discovery "$source_path" duplicate-ilean source-mapping "duplicate tracked source mapping: $relative"
  seen_source[$relative]=1

  module="${relative%.lean}"
  module="${module//\//.}"
  ilean="$build_root/${module//./\/}.ilean"
  [[ -r $ilean ]] \
    || fail_discovery "$source_path" missing-ilean source-mapping "missing .ilean for tracked module: $module"

  version="$(jq -er '.version' "$ilean")" \
    || fail_discovery "$source_path" unreadable-ilean source-mapping "cannot read .ilean version: $ilean"
  [[ $version == 4 ]] \
    || fail_discovery "$source_path" unsupported-ilean source-mapping "unsupported .ilean version $version: $ilean"
  recorded_module="$(jq -er '.module' "$ilean")" \
    || fail_discovery "$source_path" unreadable-ilean source-mapping "cannot read .ilean module: $ilean"
  [[ $recorded_module == "$module" ]] \
    || fail_discovery "$source_path" foreign-ilean source-mapping "expected module $module, found $recorded_module"

  jq -r '
    (.directImports[]? | ["module", .[0], .[0]] | @tsv),
    (.references | to_entries[] | (.key | fromjson).c? as $constant |
      select($constant != null) | select((.value.usages // []) | length > 0) |
      ["name", $constant.m, $constant.n] | @tsv)
  ' "$ilean" >"$work/module-rows"

  while IFS=$'\t' read -r kind owner reference; do
    [[ -n $kind && -n $owner && -n $reference ]] || continue
    package="$(package_for_module "$owner")"
    if [[ -n $package ]]; then
      printf '%s\t%s\t%s\t%s\telaborated\n' \
        "$source_path" "$package" "$reference" "$kind" >>"$work/rows"
    elif is_internal_module "$owner"; then
      continue
    elif [[ $kind == name ]] && ! is_declared_name "$reference"; then
      # Constants from Lean's own standard library are outside this audit.
      continue
    else
      fail_discovery "$source_path" foreign-module module-ownership \
        "compiler attributed declared reference $reference to undeclared module $owner"
    fi
  done <"$work/module-rows"
done

sort -u "$work/rows"
