#!/usr/bin/env bash
set -euo pipefail

# #254 S254-E — focused entitlement M8 output contract.
#
# This script validates the CONTRACT of `just bounty-entitlement-blaster`: the
# exact identity rows, the exact mutant rows, the controls that must precede
# them, and the vocabulary that must never appear. It is deliberately NOT the
# semantic oracle — every semantic row is computed by the tracked Lean module
# from the imported production programs, and this script can only reject.
#
# It also carries its own falsification controls, because a contract checker
# that accepts anything is the same defect as a proof that cannot fail: each
# control feeds the checker a transcript that violates exactly one clause and
# requires it to reject.
#
# Usage:
#   test-entitlement-contract.sh [transcript]
#
# With no argument it runs the real recipe and checks its output. With a file
# it checks that transcript, which is how the controls below drive it.

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'test-entitlement-contract: %s\n' "$*" >&2
    exit 1
}

# The exact role/title pair the recipe must identify, declared once so a
# control cannot silently cover fewer.
roles=(commitment)
titles=(
    'bounty_commitment.bounty_commitment.spend'
)

# The exact mutant classes the frozen slice gate requires.
classes=(entitlement age scope payout)

check_transcript() {
    local transcript="$1"

    # Exactly one identity row, naming its title and a full-width program hash.
    local identities
    identities="$(grep -cE '^M8\.entitlement-target role=(commitment) title=[^ ]+ program_sha256=[0-9a-f]{64}$' "$transcript" || true)"
    [[ "$identities" -eq 1 ]] ||
        fail "expected exactly 1 target identity row, found $identities"

    local index
    for index in "${!roles[@]}"; do
        grep -qE "^M8\.entitlement-target role=${roles[$index]} title=${titles[$index]} program_sha256=[0-9a-f]{64}\$" \
            "$transcript" ||
            fail "missing identity row for role ${roles[$index]} at ${titles[$index]}"
    done

    # The instrument's own positive control must have settled before any
    # mutant is believed.
    grep -qE '^M8\.entitlement-control case=applied-parameters role=commitment outcome=HALT steps=[0-9]+$' \
        "$transcript" ||
        fail "the commitment program did not settle on its parameters alone"

    # The accepted honest neighbour. Without it four rejections establish
    # nothing about the fields they vary.
    grep -qE '^M8\.entitlement-control case=honest-reveal outcome=ACCEPT steps=[0-9]+$' \
        "$transcript" ||
        fail "the honest matured reveal was not accepted; the mutant rows have no accepted neighbour"

    # Exactly the four required classes, each rejected.
    local class
    for class in "${classes[@]}"; do
        grep -qE "^M8\.entitlement-mutant class=${class} outcome=REJECT\$" \
            "$transcript" ||
            fail "compiled ${class} mutant was not rejected"
    done
    local mutants
    mutants="$(grep -cE '^M8\.entitlement-mutant class=(entitlement|age|scope|payout) outcome=REJECT$' "$transcript" || true)"
    [[ "$mutants" -eq 4 ]] ||
        fail "expected exactly 4 rejected mutant rows, found $mutants"

    # A refused builtin dispatch is not a rejection and must never be reported
    # as one. If the evaluator could not evaluate a program, the run says so.
    if grep -qE '^M8\.entitlement-mutant .* outcome=COULD-NOT-EVALUATE$' \
        "$transcript"; then
        fail "a mutant row reports COULD-NOT-EVALUATE; that is not evidence of enforcement"
    fi
    if grep -qE '^M8\.entitlement-mutant .* outcome=ACCEPT$' "$transcript"; then
        fail "a mutant row was ACCEPTED by the program"
    fi
}

# ---------------------------------------------------------------------
# Falsification controls: each violates exactly one clause.
# ---------------------------------------------------------------------
# `check_transcript` reports a violation by calling `fail`, which exits. A
# control therefore runs it in a SUBSHELL: the exit ends the subshell and the
# `if` observes the status, instead of taking the whole script down with it.
control() {
    local name="$1" transcript="$2"
    if (check_transcript "$transcript") 2>/dev/null; then
        fail "control '$name' was ACCEPTED by the checker; the checker cannot fail"
    fi
    printf 'test-entitlement-contract: control %s rejected\n' "$name"
}

if [[ $# -ge 1 ]]; then
    check_transcript "$1"
    printf 'test-entitlement-contract: PASS (supplied transcript)\n'
    exit 0
fi

cd "$repo_root"
just bounty-entitlement-blaster >"$work/real.txt"
check_transcript "$work/real.txt"

# Control A: one mutant downgraded to a non-rejection.
sed 's/^M8\.entitlement-mutant class=age outcome=REJECT$/M8.entitlement-mutant class=age outcome=COULD-NOT-EVALUATE/' \
    "$work/real.txt" >"$work/control-a.txt"
control "age-not-rejected" "$work/control-a.txt"

# Control B: the honest neighbour removed.
grep -v '^M8\.entitlement-control case=honest-reveal' "$work/real.txt" \
    >"$work/control-b.txt"
control "honest-neighbour-absent" "$work/control-b.txt"

# Control D: the instrument's own control did not settle.
sed 's/^\(M8\.entitlement-control case=applied-parameters role=commitment outcome=\)HALT/\1ERROR/' \
    "$work/real.txt" >"$work/control-d.txt"
control "commitment-control-unsettled" "$work/control-d.txt"

printf 'test-entitlement-contract: PASS targets=1 mutants=4 controls=3\n'
