#!/usr/bin/env bash
# Assemble the ckeri evidence bundle from a declared inventory. The
# inventory is the authority; a tree walk may supply candidates only.
set -euo pipefail

usage() { echo "usage: $0 INVENTORY SRC_ROOT DEST" >&2; exit 2; }
[ "$#" -eq 3 ] || usage
inventory=$1
src_root=$2
dest=$3

[ -r "$inventory" ] || {
  echo "MEASUREMENT-FAILED: inventory unreadable: $inventory" >&2
  exit 1
}
mkdir -p "$dest"

copied=0
while IFS=$'\t' read -r path origin mode required || [ -n "${path:-}" ]; do
  [ -n "${path:-}" ] || continue
  [[ $path == \#* ]] && continue
  src="$src_root/$path"
  if [ ! -e "$src" ]; then
    echo "declared artifact missing from source: $path origin=$origin" >&2
    exit 1
  fi
  mkdir -p "$dest/$(dirname "$path")"
  cp -a "$src" "$dest/$path"
  chmod "$mode" "$dest/$path"
  copied=$((copied + 1))
done < "$inventory"

[ "$copied" -gt 0 ] || {
  echo "MEASUREMENT-FAILED: inventory unexpectedly empty: $inventory" >&2
  exit 1
}
echo "ASSEMBLED copied=$copied dest=$dest inventory=$inventory"
exit 0
