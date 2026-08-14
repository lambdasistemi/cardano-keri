#!/usr/bin/env bash
set -euo pipefail

if (( $# < 5 )); then
  echo 'usage: elaborate-ilean-root.sh DEPENDENCY_ROOT SOURCE_ROOT ARTIFACT_ROOT OUTPUT_ROOT FILE...' >&2
  exit 64
fi

dependency_root="$1"
source_root="$2"
artifact_root="$3"
output_root="$4"
shift 4

fail() {
  local layer=build-root-provenance
  if [[ ${1:-} == --layer ]]; then
    layer="$2"
    shift 2
  fi
  printf 'AUDIT-DISCOVERY construct=source-reelaboration outcome=COULD-NOT-EVALUATE layer=%s\n' \
    "$layer" >&2
  printf 'elaborate-ilean-root: %s\n' "$*" >&2
  exit 1
}

[[ -d $dependency_root ]] || fail "dependency root is unavailable: $dependency_root"
[[ -d $source_root ]] || fail "source root is unavailable: $source_root"
mkdir -p "$output_root"
[[ -z $(find "$output_root" -mindepth 1 -print -quit) ]] \
  || fail "output root is not empty: $output_root"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
declare -A seen=()
declare -a relative_sources=()
needs_artifacts=false

for source in "$@"; do
  relative="${source#"$source_root"/}"
  [[ $source != "$relative" && -f $source ]] \
    || fail "source is outside the declared root or absent: $source"
  [[ $relative == KeriBlaster.lean || $relative == KeriBlaster/*.lean ]] \
    || fail "source is outside the tracked bridge set: $relative"
  [[ -z ${seen[$relative]:-} ]] || fail "duplicate source: $relative"
  seen[$relative]=1
  relative_sources+=("$relative")
  mkdir -p "$stage/$(dirname "$relative")"
  cp "$source" "$stage/$relative"
  if grep -qF 'nix-generated/' "$stage/$relative"; then
    needs_artifacts=true
  fi
done

if [[ $needs_artifacts == true ]]; then
  [[ -d $artifact_root ]] || fail "S2 artifact root is unavailable: $artifact_root"
  mapfile -t artifacts < <(find "$artifact_root" -maxdepth 1 -type f -name '*.hex' -print | sort)
  (( ${#artifacts[@]} > 0 )) || fail "S2 artifact root contains no .hex files: $artifact_root"
  mkdir -p "$stage/nix-generated"
  cp "${artifacts[@]}" "$stage/nix-generated/"
fi

compile_source() {
  local relative="$1" module ilean olean
  module="${relative%.lean}"
  module="${module//\//.}"
  ilean="$output_root/${module//./\/}.ilean"
  olean="$output_root/${module//./\/}.olean"
  mkdir -p "$(dirname "$ilean")"
  if ! (cd "$stage" && LEAN_PATH="$output_root:$dependency_root" \
      lean -i "$ilean" -o "$olean" "$relative"); then
    fail "Lean could not re-elaborate tracked source: $relative"
  fi
  [[ $(jq -er '.version' "$ilean") == 4 ]] \
    || fail "re-elaborated map has an unsupported version: $relative"
  [[ $(jq -er '.module' "$ilean") == "$module" ]] \
    || fail "re-elaborated map has the wrong module identity: $relative"
}

declared_local_imports() {
  local staged_root="$1" relative="$2" module
  while IFS= read -r module; do
    [[ -n $module ]] || continue
    printf '%s.lean\n' "${module//./\/}"
  done < <(
    sed -nE \
      's/^[[:space:]]*import[[:space:]]+(KeriBlaster\.[A-Za-z0-9_.]+).*/\1/p' \
      "$staged_root/$relative"
  )
}

derive_compile_order() {
  local staged_root="$1"
  shift

  # Sorting the node set up front and the available set after each graph step
  # makes bytewise lexical order the deterministic tie-break between modules
  # that are independent in the import graph.
  local -a nodes=()
  if (( $# > 0 )); then
    mapfile -t nodes < <(printf '%s\n' "$@" | LC_ALL=C sort)
  fi

  local -A tracked=()
  local -A in_degree=()
  local -A dependents=()
  local -A edges=()
  local node dependency edge
  for node in "${nodes[@]}"; do
    tracked["$node"]=1
    in_degree["$node"]=0
    dependents["$node"]=''
  done

  # Validate the complete graph before invoking Lean. A dependency edge is
  # prerequisite -> importer, so Kahn's algorithm emits prerequisites first.
  for node in "${nodes[@]}"; do
    while IFS= read -r dependency; do
      [[ -n $dependency ]] || continue
      if [[ ${tracked["$dependency"]+present} != present ]]; then
        fail --layer unresolved-local-import \
          "declared local import '$dependency' imported by '$node' is absent from tracked sources"
      fi
      edge="$dependency->$node"
      [[ ${edges["$edge"]+present} != present ]] || continue
      edges["$edge"]=1
      in_degree["$node"]=$(( ${in_degree["$node"]} + 1 ))
      if [[ -n ${dependents["$dependency"]} ]]; then
        dependents["$dependency"]+=$'\n'
      fi
      dependents["$dependency"]+="$node"
    done < <(declared_local_imports "$staged_root" "$node")
  done

  local -a available=()
  local -a ordered=()
  local current dependent
  for node in "${nodes[@]}"; do
    (( ${in_degree["$node"]} == 0 )) && available+=("$node")
  done
  if (( ${#available[@]} > 1 )); then
    mapfile -t available < <(printf '%s\n' "${available[@]}" | LC_ALL=C sort)
  fi

  while (( ${#available[@]} > 0 )); do
    current="${available[0]}"
    if (( ${#available[@]} == 1 )); then
      available=()
    else
      available=("${available[@]:1}")
    fi
    ordered+=("$current")

    if [[ -n ${dependents["$current"]} ]]; then
      while IFS= read -r dependent; do
        [[ -n $dependent ]] || continue
        in_degree["$dependent"]=$(( ${in_degree["$dependent"]} - 1 ))
        if (( ${in_degree["$dependent"]} == 0 )); then
          available+=("$dependent")
        fi
      done <<<"${dependents["$current"]}"
    fi
    if (( ${#available[@]} > 1 )); then
      mapfile -t available < <(
        printf '%s\n' "${available[@]}" | LC_ALL=C sort
      )
    fi
  done

  if (( ${#ordered[@]} != ${#nodes[@]} )); then
    local -a cycle_participants=()
    local participants
    for node in "${nodes[@]}"; do
      if (( ${in_degree["$node"]} > 0 )); then
        cycle_participants+=("$node")
      fi
    done
    participants="$(IFS=,; printf '%s' "${cycle_participants[*]}")"
    fail --layer dependency-cycle \
      "dependency cycle detected among tracked modules: $participants"
  fi

  if (( ${#ordered[@]} > 0 )); then
    printf '%s\n' "${ordered[@]}"
  fi
}

declare -a non_root_sources=()
for relative in "${relative_sources[@]}"; do
  [[ $relative != KeriBlaster.lean ]] || continue
  non_root_sources+=("$relative")
done

# Do not place derive_compile_order in command or process substitution: either
# would isolate fail() in a subshell and let the driver fall through to Lean.
order_file="$stage/.elaboration-order"
derive_compile_order "$stage" "${non_root_sources[@]}" >"$order_file"
mapfile -t ordered_sources <"$order_file"
rm -f "$order_file"

declare -a order_modules=()
for relative in "${ordered_sources[@]}"; do
  module="${relative%.lean}"
  order_modules+=("${module//\//.}")
done
printf 'ELABORATION-ORDER count=%d derived=%s\n' \
  "${#ordered_sources[@]}" "$(IFS=,; printf '%s' "${order_modules[*]}")" >&2

# Derived leaf order first, then the aggregate root. This prevents an existing
# KeriBlaster module in DEPENDENCY_ROOT from satisfying an internal import.
for relative in "${ordered_sources[@]}"; do
  [[ -n $relative ]] || continue
  compile_source "$relative"
done

if [[ -n ${seen[KeriBlaster.lean]:-} ]]; then
  compile_source KeriBlaster.lean
fi
