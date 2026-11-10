#!/usr/bin/env bash
# The identities page states the revisions, hashes and sizes of this generation;
# every stated value is recomputed here and a difference fails the check.
#
#   bash scripts/check-identities.sh [PAGE]
#
# Default page: docs/architecture/registry-identities.md. The scripts' hashes and
# sizes come from scripts/registry-identities.sh (or from the file named by
# IDENTITIES_DERIVED, for a run that already holds the derivation). After the
# real page passes, the same check runs on a copy with one character of one
# stated hash changed and must fail: a check that cannot fail proves nothing.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
page=${1:-$root/docs/architecture/registry-identities.md}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

derived=${IDENTITIES_DERIVED:-}
if [[ -z $derived ]]; then
  derived=$work/derived.txt
  bash "$root/scripts/registry-identities.sh" > "$derived"
fi

# The expected value of every row of the page's table, by its label.
expected=$work/expected.txt
{
  printf 'Lean model revision|%s\n' "$(git -C "$root" log -1 --no-merges --format=%H -- lean)"
  printf 'Public Singular commit|%s\n' \
    "$(sed -nE 's/^revision=([0-9a-f]{40})$/\1/p' "$root/onchain/stage-dependencies.sh")"
  printf 'Aiken compiler|%s\n' \
    "$(nix eval --raw github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken.version)"
  awk '
    $1 == "application"         { print "Application script hash|" $2; print "Application program bytes|" $3 }
    $1 == "state-script"        { print "State script hash|" $2; print "State script program bytes|" $3 }
    $1 == "checkpoint-register" { print "Checkpoint validator script hash|" $2; print "Checkpoint validator program bytes|" $3 }
    $1 == "registry-name"       { print "Reference registry name|" $2 }
  ' "$derived"
} > "$expected"

# The compiler named by the project must be the one the check named above.
project_compiler=$(sed -nE 's/^compiler = "v([0-9.]+)"$/\1/p' "$root/onchain/aiken.toml")
[[ $project_compiler == "$(sed -n 's/^Aiken compiler|//p' "$expected")" ]] || {
  echo "onchain/aiken.toml names compiler $project_compiler, not the pinned one" >&2
  exit 1
}

# Compare one page with the expected values; print each difference.
compare() {
  local file=$1 status=0 label want got
  while IFS='|' read -r label want; do
    got=$(sed -nE "/<!-- identities:begin -->/,/<!-- identities:end -->/{
      s/^\\| ${label} \\| \`([^\`]*)\` \\|\$/\\1/p
    }" "$file")
    if [[ $got != "$want" ]]; then
      echo "stated '${label}': page has '${got}', derivation gives '${want}'" >&2
      status=1
    fi
  done < "$expected"
  return $status
}

compare "$page"
echo "identities page matches its derivation ($(wc -l < "$expected") values)"

# Control: one character of one stated hash changed must be refused.
control=$work/control.md
awk '
  !done && /^\| Application script hash \|/ {
    sub(/`[0-9a-f]/, "`" (substr($0, index($0, "`") + 1, 1) == "0" ? "1" : "0"))
    done = 1
  }
  { print }
' "$page" > "$control"
cmp -s "$page" "$control" && { echo "control did not change the page" >&2; exit 1; }
if compare "$control" 2> "$work/control.err"; then
  echo "control passed: the check cannot fail" >&2
  exit 1
fi
echo "control refused: $(head -1 "$work/control.err")"
