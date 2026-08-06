#!/usr/bin/env bash
set -euo pipefail

ckeri="$(realpath -- "${1:?usage: check-ckeri-closure-no-cli.sh CKERI}")"
package_root="$(dirname -- "$(dirname -- "$ckeri")")"

if [[ ! -x "$ckeri" ]]; then
  printf 'ckeri closure check: executable is missing: %s\n' "$ckeri" >&2
  exit 1
fi

mapfile -t closure < <(nix-store --query --requisites "$package_root")
for store_path in "${closure[@]}"; do
  if [[ -x "$store_path/bin/cardano-cli" ]]; then
    printf 'ckeri closure check: forbidden cardano-cli runtime dependency: %s\n' \
      "$store_path" >&2
    exit 1
  fi
done

printf 'ckeri closure check: cardano-cli absent from %s (%d closure paths inspected)\n' \
  "$package_root" "${#closure[@]}"
