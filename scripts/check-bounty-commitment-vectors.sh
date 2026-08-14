#!/usr/bin/env bash
# #271 S271-1 — Haskell/Aiken parity gate for the bounty-commitment wire.
#
# One Haskell computation (offchain/app/GenBountyCommitmentVectors.hs) is the
# sole source of every canonical byte string, commitment hash, and marker name
# in the committed Aiken vectors module. This script regenerates them and
# rejects any drift, then proves it could have detected drift by corrupting a
# committed vector and requiring the same comparison to fail.
#
# It deliberately does not shell out to `aiken`: it compares the two modules
# with whitespace removed, so it is a content check that runs before any
# build-like step. `just format-check-onchain` independently guarantees the
# committed module's layout.
#
# Usage:
#   scripts/check-bounty-commitment-vectors.sh              # check
#   scripts/check-bounty-commitment-vectors.sh --self-test  # check, verbosely
set -euo pipefail

committed=onchain/lib/cardano_keri/bounty_commitment_vectors.ak
generator=app/GenBountyCommitmentVectors.hs

verbose=0
case "${1:-}" in
"") ;;
--self-test) verbose=1 ;;
*)
    echo "bounty-commitment-vectors: unknown argument '$1'" >&2
    exit 2
    ;;
esac

root=$(git rev-parse --show-toplevel)
cd "$root"

test -f "$committed" || {
    echo "bounty-commitment-vectors: missing committed module $committed" >&2
    exit 1
}
test -f "offchain/$generator" || {
    echo "bounty-commitment-vectors: missing generator offchain/$generator" >&2
    exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The generator is the oracle. If it cannot run, nothing below may pass.
(
    cd offchain
    nix develop --quiet --no-write-lock-file -c \
        runghc "$generator" "$work/regenerated.ak"
)
test -s "$work/regenerated.ak" || {
    echo "bounty-commitment-vectors: generator produced no output" >&2
    exit 1
}

# Content comparison: identical modulo layout.
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
    echo "bounty-commitment-vectors: committed module declares no vectors" >&2
    exit 1
fi

if ! same "$committed" "$work/regenerated.ak"; then
    echo "bounty-commitment-vectors: FAIL committed module drifted from the Haskell oracle" >&2
    diff -u "$committed" "$work/regenerated.ak" >&2 || true
    exit 1
fi

# Negative control. The check above is only evidence if it can fail: corrupt
# exactly one nibble of one committed vector and require the same comparison
# to reject it. A checker that passes this corrupted copy would have been
# passing everything.
corrupt="$work/corrupt.ak"
awk '
  /^pub const commitment_hash: ByteArray =$/ { found = 1; print; next }
  found && /^  #"/ {
    # flip the first hex digit of the digest to a different value
    line = $0
    first = substr(line, 5, 1)
    replacement = (first == "0") ? "1" : "0"
    print substr(line, 1, 4) replacement substr(line, 6)
    found = 0
    next
  }
  { print }
' "$committed" >"$corrupt"

if ! grep -q '^pub const commitment_hash: ByteArray =$' "$corrupt"; then
    echo "bounty-commitment-vectors: negative control could not locate commitment_hash" >&2
    exit 1
fi
if same "$committed" "$corrupt"; then
    echo "bounty-commitment-vectors: negative control did not change the module" >&2
    exit 1
fi
if same "$corrupt" "$work/regenerated.ak"; then
    echo "bounty-commitment-vectors: FAIL negative control passed a corrupted vector" >&2
    exit 1
fi

if [[ "$verbose" -eq 1 ]]; then
    echo "bounty-commitment-vectors: oracle offchain/$generator"
    echo "bounty-commitment-vectors: committed $committed"
    echo "bounty-commitment-vectors: negative control corrupted commitment_hash and was rejected:"
    diff -u "$committed" "$corrupt" | sed -n '4,8p' || true
fi

echo "bounty-commitment-vectors: PASS vectors=$vectors negative-control=PASS"
