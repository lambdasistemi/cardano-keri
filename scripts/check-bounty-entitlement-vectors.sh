#!/usr/bin/env bash
# #254 S254-E — Haskell/Aiken parity gate for the entitlement layer.
#
# One Haskell computation (offchain/app/GenBountyEntitlementVectors.hs) is the
# sole source of every value in the committed Aiken vectors module: the
# canonical digest over the COMPLETE actual enforcement payload, one digest per
# independently mutated evidence field, the golden wire bytes of the S254-E
# shapes, and the shared matcher's own verdict tag for each named row. This
# script regenerates them and rejects any drift.
#
# Two things distinguish it from a byte-equality check that could not fail:
#
#   * a NEGATIVE CONTROL corrupts one committed digest and requires the same
#     comparison to reject it, so a passing run is evidence rather than a
#     coincidence of two empty files;
#   * a VERDICT CONTROL requires the committed set to contain at least one
#     accepted row and at least one rejected row with a distinct reason. A
#     set that agreed everywhere would prove the two languages compute the
#     same constant, not the same matcher.
#
# It deliberately does not shell out to `aiken`: it compares the two modules
# with whitespace removed, so it is a content check that runs before any
# build-like step. `just format-check-onchain` independently guarantees the
# committed module's layout, and the Aiken tests in
# `onchain/lib/cardano_keri/checkpoint/entitlement_tests.ak` are what make the
# committed numbers load-bearing rather than merely present.
#
# Usage:
#   scripts/check-bounty-entitlement-vectors.sh              # check
#   scripts/check-bounty-entitlement-vectors.sh --self-test  # check, verbosely
set -euo pipefail

committed=onchain/lib/cardano_keri/checkpoint/entitlement_vectors.ak
generator=gen-bounty-entitlement-vectors
generator_source=offchain/app/GenBountyEntitlementVectors.hs

verbose=0
case "${1:-}" in
"") ;;
--self-test) verbose=1 ;;
*)
    echo "bounty-entitlement-vectors: unknown argument '$1'" >&2
    exit 2
    ;;
esac

root=$(git rev-parse --show-toplevel)
cd "$root"

test -f "$committed" || {
    echo "bounty-entitlement-vectors: missing committed module $committed" >&2
    exit 1
}
test -f "$generator_source" || {
    echo "bounty-entitlement-vectors: missing generator $generator_source" >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The generator is the oracle. If it cannot run, nothing below may pass.
(
    cd offchain
    nix develop --quiet --no-write-lock-file -c bash -c \
        "cabal update --project-file=cabal.project.devshell >/dev/null && cabal run -v0 -O0 --project-file=cabal.project.devshell $generator -- $work/regenerated.ak"
)
test -s "$work/regenerated.ak" || {
    echo "bounty-entitlement-vectors: generator produced no output" >&2
    exit 1
}

canonicalize() {
    tr -d '[:space:]' <"$1"
}

same() {
    canonicalize "$1" >"$work/a.txt"
    canonicalize "$2" >"$work/b.txt"
    cmp -s "$work/a.txt" "$work/b.txt"
}

vectors=$(grep -c '^pub const ' "$committed")
if [[ "$vectors" -lt 1 ]]; then
    echo "bounty-entitlement-vectors: committed module declares no vectors" >&2
    exit 1
fi

if ! same "$committed" "$work/regenerated.ak"; then
    echo "bounty-entitlement-vectors: FAIL committed module drifted from the Haskell source" >&2
    diff -u "$committed" "$work/regenerated.ak" >&2 || true
    exit 1
fi

# ---------------------------------------------------------------------
# Verdict control: the set must be able to distinguish.
# ---------------------------------------------------------------------
accepted=$(grep -c '^pub const verdict_[a-z_]*: Int = 0$' "$committed" || true)
rejected=$(grep '^pub const verdict_[a-z_]*: Int = ' "$committed" |
    grep -vc ' = 0$' || true)
reasons=$(grep '^pub const verdict_[a-z_]*: Int = ' "$committed" |
    sed 's/.* = //' | sort -u | wc -l)

if [[ "$accepted" -lt 1 ]]; then
    echo "bounty-entitlement-vectors: no accepted verdict row; every rejection would lack an honest neighbour" >&2
    exit 1
fi
if [[ "$rejected" -lt 1 ]]; then
    echo "bounty-entitlement-vectors: no rejected verdict row; the matcher could be a constant" >&2
    exit 1
fi
if [[ "$reasons" -lt 3 ]]; then
    echo "bounty-entitlement-vectors: verdict rows carry fewer than three distinct outcomes; the set does not prove the two languages agree on the REASON" >&2
    exit 1
fi

# ---------------------------------------------------------------------
# Negative control. The comparison above is only evidence if it can fail:
# corrupt exactly one nibble of the committed digest and require the same
# comparison to reject it.
# ---------------------------------------------------------------------
corrupt="$work/corrupt.ak"
awk '
  /^pub const evidence_digest: ByteArray =$/ { found = 1; print; next }
  found && /^  #"/ {
    line = $0
    first = substr(line, 5, 1)
    replacement = (first == "0") ? "1" : "0"
    print substr(line, 1, 4) replacement substr(line, 6)
    found = 0
    next
  }
  /^pub const evidence_digest: ByteArray = #"/ {
    first = substr($0, index($0, "#\"") + 2, 1)
    replacement = (first == "0") ? "1" : "0"
    print substr($0, 1, index($0, "#\"") + 1) replacement \
      substr($0, index($0, "#\"") + 3)
    next
  }
  { print }
' "$committed" >"$corrupt"

if ! grep -q '^pub const evidence_digest: ByteArray' "$corrupt"; then
    echo "bounty-entitlement-vectors: negative control could not locate evidence_digest" >&2
    exit 1
fi
if same "$committed" "$corrupt"; then
    echo "bounty-entitlement-vectors: negative control did not change the module" >&2
    exit 1
fi
if same "$corrupt" "$work/regenerated.ak"; then
    echo "bounty-entitlement-vectors: FAIL negative control passed a corrupted vector" >&2
    exit 1
fi

if [[ "$verbose" -eq 1 ]]; then
    echo "bounty-entitlement-vectors: source $generator_source"
    echo "bounty-entitlement-vectors: committed $committed"
    echo "bounty-entitlement-vectors: verdict rows accepted=$accepted rejected=$rejected distinct-outcomes=$reasons"
    echo "bounty-entitlement-vectors: negative control corrupted evidence_digest and was rejected:"
    diff -u "$committed" "$corrupt" | sed -n '4,8p' || true
fi

echo "bounty-entitlement-vectors: PASS vectors=$vectors verdict-rows=$((accepted + rejected)) distinct-outcomes=$reasons negative-control=PASS"
