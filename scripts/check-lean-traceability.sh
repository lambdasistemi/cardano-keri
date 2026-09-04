#!/usr/bin/env bash
set -euo pipefail

# Retirement ledger + sole-spec + proof-trust enforcement for DISP-366-DELETE.
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
nix shell --no-write-lock-file ../offchain#lean --command lake clean
nix shell --no-write-lock-file ../offchain#lean --command lake build \
  >"$tmp_root/build.log" 2>&1
if rg -n "uses 'sorry'" "$tmp_root/build.log"; then
  echo 'retirement: clean build contains a sorry proof' >&2
  exit 1
fi

for module in "${retired_modules[@]}"; do
  printf 'import CardanoKeri.%s\n' "$module" >"$tmp_root/RetiredImport.lean"
  if nix shell --no-write-lock-file ../offchain#lean --command lake env lean \
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

cat >"$tmp_root/Axioms.lean" <<'EOF'
import CardanoKeri.CheckpointGoals
import CardanoKeri.RegistryGoals
import CardanoKeri.Cage
import CardanoKeri.Samaritan
EOF
theorem_count=0
while IFS=: read -r source prefix; do
  while read -r theorem_name; do
    printf '#print axioms %s.%s\n' "$prefix" "$theorem_name" >>"$tmp_root/Axioms.lean"
    theorem_count=$((theorem_count + 1))
  done < <(awk '/^theorem[[:space:]]+/ { print $2 }' "$lean_root/CardanoKeri/$source.lean")
done <<'EOF'
CheckpointGoals:CardanoKeri.Checkpoint
RegistryGoals:CardanoKeri.Registry
Cage:CardanoKeri.Cage
Samaritan:CardanoKeri.Samaritan
EOF
test "$theorem_count" -gt 0 || {
  echo 'retirement: empty live theorem inventory' >&2
  exit 1
}
nix shell --no-write-lock-file ../offchain#lean --command lake env lean \
  "$tmp_root/Axioms.lean" >"$tmp_root/axioms.log" 2>&1
test "$(rg -c "depends on axioms|does not depend on any axioms" "$tmp_root/axioms.log")" \
  -eq "$theorem_count" || {
  echo 'retirement: truncated axiom inventory (receipt count differs from theorem count)' >&2
  exit 1
}
if rg -n 'sorryAx|Classical.choice' "$tmp_root/axioms.log"; then
  echo 'retirement: live proof surface contains an unapproved axiom' >&2
  exit 1
fi
if rg 'depends on axioms:' "$tmp_root/axioms.log" \
    | rg -v 'depends on axioms: \[propext\]$|depends on axioms: \[Quot.sound\]$|depends on axioms: \[propext, Quot.sound\]$'; then
  echo 'retirement: live proof surface contains an unknown axiom set' >&2
  exit 1
fi

git -C "$repo_root" diff --check
echo "retirement: retired=3 ledger=$historical_count live-theorems=$theorem_count build=pass axioms=pass"
