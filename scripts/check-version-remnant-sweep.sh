#!/usr/bin/env bash
# #254 T254-109 (S254-R) — launcher for the derived version-remnant census.
#
# This file used to BE the census: a source-text sweep that stripped comments,
# matched line patterns and kept an allowlist of permitted lines. That control
# was rejected, and rightly: what it observed was the spelling of the tree, so
# it missed a second applier on one line, it missed a version-shaped name on a
# line it had already excused, and it cried wolf over the word "version" in a
# comment or a string. Its own exclusion list was the load-bearing part, and an
# exclusion nobody can falsify is a suppression.
#
# The census now derives its facts from authoritative structure instead:
#
#   * application sites and version-shaped identifier occurrences come from the
#     Haskell syntax trees produced by GHC's own parser, so they are nodes and
#     roles rather than lines and tokens;
#   * the register's declared and applied parameter arity comes from the
#     COMPILED Plutus blueprint and from the applied artifact's own bytes, so no
#     Aiken source is read;
#   * the checkpoint-migration and M8 facts stay with the existing compiled
#     target proof, so no Lean source is read.
#
# There is deliberately no scanner and no lexer below this comment. Everything
# this script does is resolve the verification-only control and hand it the
# tree. The frozen form of the old sweep survives in Git history, where the
# control's own `self-test` materializes it and requires it to miss what the
# derived census catches — which is the permanent evidence that replacing it was
# an improvement rather than a change of opinion.
#
# ── OUTPUT CONTRACT (unchanged from v1) ────────────────────────────────────
#
#   exit 0  every remnant accounted for; prints exactly one
#           `S254-R version-remnant-sweep: PASS removed=<n> kept=<n>` line
#   exit 1  the derived census disagrees with what this candidate declares
#   exit 2  the instrument could not answer (unparseable module, missing
#           blueprint, vacuous horizon) — never reported as a pass or a catch
#
# `--self-test` runs the control's permanent RED-to-GREEN demonstration against
# the frozen legacy sweep. It materializes throwaway trees under a temporary
# directory and never mutates this repository or any historical fixture.

set -euo pipefail

repo_root=${S254R_SWEEP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

# The commit whose tree carries the frozen source-text sweep the self-test
# measures the derived control against. It is the slice's repair base.
legacy_ref=${S254R_LEGACY_REF:-81646212756d758705d486d26c841bff0155c3eb}

control=$(
    cd "$repo_root/offchain" &&
        nix build --quiet --no-write-lock-file --no-link --print-out-paths \
            .#s254r-derived-controls
)/bin/s254r-derived-controls

case ${1-} in
--self-test)
    exec "$control" self-test --repo-root "$repo_root" --legacy-ref "$legacy_ref"
    ;;
"")
    exec "$control" scan --root "$repo_root"
    ;;
*)
    printf 'usage: %s [--self-test]\n' "$(basename "$0")" >&2
    exit 64
    ;;
esac
