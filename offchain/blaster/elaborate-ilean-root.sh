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
  printf 'AUDIT-DISCOVERY construct=source-reelaboration outcome=COULD-NOT-EVALUATE layer=build-root-provenance\n' >&2
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
  [[ $relative != KeriBlaster/S2Evidence.lean ]] || needs_artifacts=true
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

# Leaf modules first, then the aggregate root.  This prevents an existing
# KeriBlaster module in DEPENDENCY_ROOT from satisfying an internal import.
while IFS= read -r relative; do
  [[ -n $relative ]] || continue
  compile_source "$relative"
done < <(printf '%s\n' "${relative_sources[@]}" | grep -v '^KeriBlaster\.lean$' | sort)

if [[ -n ${seen[KeriBlaster.lean]:-} ]]; then
  compile_source KeriBlaster.lean
fi
