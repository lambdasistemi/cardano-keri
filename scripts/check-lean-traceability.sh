#!/usr/bin/env bash
set -euo pipefail

# Historical retirement ledger and complete compiled proof-trust inventory.
# Usage: check-lean-traceability.sh [repo_root] [base_sha]
# Defaults cover CI/just callers (no args). The compiler remains the authority
# for dependency closure; source-text scans locate references but never close
# compiled absence alone.
repo_root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
base_sha="${2:-9b2e6b88937707cc2c571ae1e9e5f112dc248a30}"
ruling_url=https://github.com/lambdasistemi/cardano-keri/issues/366#issuecomment-5543757547
lean_root="$repo_root/lean"

retired_modules=(Lifecycle Goals Invariants)
for module in "${retired_modules[@]}"; do
  test ! -e "$lean_root/CardanoKeri/$module.lean" || {
    echo "retirement: retired source still exists: CardanoKeri/$module.lean" >&2
    exit 1
  }
done

tmp_root=$(mktemp -d)
trap 'rm -rf -- "$tmp_root"' EXIT

# CI checks out one commit; the frozen base is older. Fetch exactly that
# commit when the clone does not carry it, so the denominator never depends
# on whatever history a runner happens to hold.
git -C "$repo_root" cat-file -e "$base_sha:lean/CardanoKeri/Goals.lean" 2>/dev/null ||
  git -C "$repo_root" fetch --quiet --depth=1 origin "$base_sha"

git -C "$repo_root" show "$base_sha:lean/CardanoKeri/Goals.lean" \
  | awk '/^theorem[[:space:]]+/ { print $2 }' >"$tmp_root/historical-theorems"
historical_count=$(wc -l <"$tmp_root/historical-theorems")
test "$historical_count" -gt 0 || {
  echo 'retirement: empty historical denominator (base source missing or unparsable)' >&2
  exit 1
}
test "$historical_count" -eq 21 || {
  echo "retirement: historical denominator is $historical_count, expected 21" >&2
  exit 1
}

csv="$lean_root/traceability.csv"
test "$(sed -n '1p' "$csv")" = 'lean_theorem,disposition,owner_decision' || {
  echo 'retirement: malformed CSV header (expected lean_theorem,disposition,owner_decision)' >&2
  exit 1
}
sed -n '2,$p' "$csv" >"$tmp_root/retirement-rows"
test "$(wc -l <"$tmp_root/retirement-rows")" -eq "$historical_count" || {
  echo "retirement: CSV row count $(wc -l <"$tmp_root/retirement-rows"), expected $historical_count" >&2
  exit 1
}
if rg -n 'PENDING|WITHDRAWN' "$csv"; then
  echo 'retirement: stale or non-retirement sentinel remains' >&2
  exit 1
fi
awk -F, -v ruling="$ruling_url" '
  NF != 3 || $1 == "" || $2 != "RETIRED" || $3 != ruling { exit 1 }
' "$tmp_root/retirement-rows" || {
  echo 'retirement: ledger row must be exactly {theorem,RETIRED,owner URL}' >&2
  exit 1
}
cut -d, -f1 "$tmp_root/retirement-rows" >"$tmp_root/retired-theorems"
test -z "$(sort "$tmp_root/retired-theorems" | uniq -d)" || {
  echo 'retirement: duplicate theorem identifier in ledger' >&2
  exit 1
}
diff -u "$tmp_root/historical-theorems" "$tmp_root/retired-theorems"

cd "$lean_root"
lake_run() {
  if [[ -n "${LAKE_BIN:-}" ]]; then "$LAKE_BIN" "$@"
  else nix shell --no-write-lock-file .#lean --command lake "$@"
  fi
}
lake_run clean
lake_run build CardanoKeri CardanoKeriStatements CardanoKeri.RegistryTraceWire \
  >"$tmp_root/build.log" 2>&1 || { cat "$tmp_root/build.log"; exit 1; }
cat "$tmp_root/build.log"
if rg -n "uses 'sorry'" "$tmp_root/build.log"; then
  echo 'retirement: clean build contains a sorry proof' >&2
  exit 1
fi

for module in "${retired_modules[@]}"; do
  printf 'import CardanoKeri.%s\n' "$module" >"$tmp_root/RetiredImport.lean"
  if lake_run env lean \
      "$tmp_root/RetiredImport.lean" >"$tmp_root/retired-import.log" 2>&1; then
    echo "retirement: retired module remains importable: CardanoKeri.$module" >&2
    exit 1
  fi
  rg -q "unknown module prefix|object file .*CardanoKeri/$module\\.olean.* does not exist" \
      "$tmp_root/retired-import.log" || {
    echo "retirement: retired import failed for the wrong reason: CardanoKeri.$module" >&2
    exit 1
  }
done

# The compiler enumerates every declaration owned by every current module,
# including generated/private names, and checks its transitive axiom closure.
# Standard Lean axioms are propext, Quot.sound and Classical.choice.
lake_run env lean AxiomInventory.lean >"$tmp_root/axioms.log" 2>&1 || { cat "$tmp_root/axioms.log"; exit 1; }
cat "$tmp_root/axioms.log"
sed -n 's/^MODULE //p' "$tmp_root/axioms.log" | sort >"$tmp_root/imported-modules"
{ printf 'CardanoKeri\n'; rg --files CardanoKeri -g '*.lean' | sed -e 's/\.lean$//' -e 's|/|.|g'; } \
  | sort >"$tmp_root/source-modules"
diff -u "$tmp_root/source-modules" "$tmp_root/imported-modules"
declaration_count=$(sed -n 's/^INVENTORY //p' "$tmp_root/axioms.log")
[[ "$declaration_count" =~ ^[1-9][0-9]*$ ]] || { echo 'inventory: missing positive denominator' >&2; exit 1; }
test "$(rg -c '^AXIOMS ' "$tmp_root/axioms.log")" -eq "$declaration_count" || {
  echo 'inventory: truncated declaration receipts' >&2; exit 1;
}
sed -n 's/^AXIOMS \([^:]*\):.*/\1/p' "$tmp_root/axioms.log" | sort | uniq -d >"$tmp_root/duplicates"
test ! -s "$tmp_root/duplicates" || { echo 'inventory: duplicate declaration' >&2; exit 1; }
for pair in ReviewedContracts:88 PreservedContracts:63; do
  source_name=${pair%:*}
  expected_count=${pair#*:}
  test "$(rg -c '^#check ' "retained-parking/$source_name.lean")" -eq "$expected_count"
  lake_run env lean "retained-parking/$source_name.lean" >"$tmp_root/$source_name.log" 2>&1 || { cat "$tmp_root/$source_name.log"; exit 1; }
  cat "$tmp_root/$source_name.log"
done

git -C "$repo_root" diff HEAD --check
node "$lean_root/retained-parking/story-bindings.mjs"
echo "retirement: retired=${#retired_modules[@]} ledger=$historical_count compiled-declarations=$declaration_count reviewed-types=88 preserved-types=63 build=pass axioms=pass"
