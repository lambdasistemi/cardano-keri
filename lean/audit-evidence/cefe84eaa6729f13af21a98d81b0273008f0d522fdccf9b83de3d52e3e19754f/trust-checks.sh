#!/usr/bin/env bash
set -euo pipefail
cd /code/cardano-keri-368/lean
evidence=$(cat /tmp/epic-367/to-368/evidence-path)
for module in Lifecycle Goals Invariants; do
  printf 'import CardanoKeri.%s\n' "$module" > "$evidence/Retired-$module.lean"
  set +e
  nix shell --no-write-lock-file ../offchain#lean --command lake env lean "$evidence/Retired-$module.lean" > "$evidence/retired-$module.log" 2>&1
  rc=$?
  set -e
  printf '%s\n' "$rc" > "$evidence/retired-$module.exit"
  test "$rc" -ne 0
  rg "CardanoKeri/$module.olean.*does not exist" "$evidence/retired-$module.log"
done
nix shell --no-write-lock-file ../offchain#lean --command lean --version > "$evidence/toolchain.log" 2>&1
cd ..
set +e
nix shell nixpkgs#ripgrep nixpkgs#gawk nixpkgs#gnused nixpkgs#gnugrep nixpkgs#coreutils nixpkgs#diffutils --command bash scripts/check-lean-traceability.sh > "$evidence/traceability.log" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$evidence/traceability.exit"
exit "$rc"
