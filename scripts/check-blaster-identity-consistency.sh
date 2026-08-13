#!/usr/bin/env bash
# #234 Stage-D Slice 2 — STANDING repository-CI contract: every identity
# documented in the Blaster trust-base table
# (docs/architecture/blaster-tractability.md) must byte-match its
#
# ── OUTPUT CONTRACT (stable repository interface; consumers may parse this) ──
#
# EXIT CODES — the authoritative verdict, and the ONLY thing a consumer needs:
#   0  every declared component was documented exactly once, every lock-backed
#      row documented every identity field its lock node carries, every
#      comparison matched, and every extraction reported a status this script
#      could classify (GREEN)
#   1  drift, an unclassified row, a missing declared component, a duplicate
#      row, a lock-backed row MISSING AN EXPECTED FIELD, a failed self-test leg,
#      or an extraction that could not be evaluated (RED)
#   any other code is an ERROR and must be treated as RED, never as a pass.
#
# MACHINE-READABLE LINES — `CBIC_RESULT <key>=<value>`, one key per line,
# recognised ONLY at the START of a line, each key emitted AT MOST ONCE per run.
# Diagnostic replays of a child run's output are indented and prefixed
# `[child]`, so they can never be mistaken for this run's own records.
#
#   normal mode:  classified_rows, lock_backed_rows, compared_fields, mismatches
#   --self-test:  selftest=pass|fail; one `<seed>_rc` key per seeded negative
#                 control leg — seed_h_rc, seed_k_rc, seed_rc2_rc —
#                 then red_rc, green_rc, missing_nonlock_rc,
#                 missing_lockbacked_rc, duplicate_rc — each the exit code of one
#                 seeded negative-control leg — plus `failures` (the number of
#                 misbehaving legs) when and only when selftest=fail.
#
#                 Seed attribution is recorded in each leg's label: seeds H, I
#                 and the rc-2 control are the ticket owner's; seeds J and K
#                 were contributed by the NAVIGATOR and were not proposed by
#                 the authoring seat. An author's seed set tests what the
#                 author imagined; seed H exists because that is not enough.
#
# Absent keys mean the run did not reach them. Every key a run DOES compute is
# reported on the failing path exactly as on the passing path.
#
#
# ── WHAT THIS CHECKER DOES NOT AUTHENTICATE (declared, not implied) ─────────
#
# M8 requires an explicit out-of-scope declaration. A checker that APPEARS to
# authenticate something it cannot is the same defect as an unlabelled theorem,
# so the limits are stated here rather than left to be discovered by a seed.
#
# This checker authenticates ONE thing: that each row of the Pinned trust base
# table which is backed by a flake.lock node documents every identity field
# (rev, narHash) that its resolved node carries, byte for byte, and that the
# node's source owner/repo is the one declared for that component. That
# evidence is read from STRUCTURED data (flake.lock, via jq) only.
#
# It does NOT establish, and must not be cited for:
#
#   * NON-LOCK identities — the Z3 and Lean rows are classified as non-lock and
#     their documented values are NEVER compared to anything. An earlier version
#     compared Z3 against text scraped from offchain/flake.nix; that was removed
#     deliberately. Scraping prose for an authority produced three further ways
#     to be wrong (right value read from the wrong column, and a reporting copy
#     of the value mistaken for the definition) faster than it closed anything.
#   * COLUMN SEMANTICS — a row's cells are scanned for identity-shaped tokens.
#     A correct token placed in the wrong column is not detected.
#   * GRAPH BINDING — that the lock graph still implements the input/follows
#     relations declared in offchain/flake.nix. Rebinding an input to a
#     DIFFERENT node of the SAME repository, and documenting that node's genuine
#     identities, passes: owner/repo provenance cannot distinguish them.
#
# These are UNENFORCED DOCUMENTATION RESIDUALS, not invariants delegated to
# anything else. Believe Nix about the ACTUAL BUILD GRAPH it consumes — but no
# accepted check authenticates these Markdown claims against it. Nothing does.
# WHAT THE COUNTERS ARE, STATED HONESTLY (REVIEW-019). An earlier version of
# this header claimed the counters were purely diagnostic and that "the exit
# code never depends on one". That was false: `mismatches` is verdict-bearing —
# normal mode fails when it exceeds zero — and the classified/lock-backed counts
# guard the run. The accurate statement is:
#
#   * `mismatches` is VERDICT-BEARING and is reflected in the exit code;
#   * `compared_fields` is DIAGNOSTIC — it is a global total, and a global total
#     is FORGEABLE: a partial extraction can lower it while every remaining
#     comparison still matches. Coverage is therefore enforced PER COMPONENT
#     against the lock node, never by asserting on this number. A consumer must
#     not infer coverage from it.
#
# Born from two escaped incidents: the doc once paired NEW revisions with OLD
# narHashes, and a correction then mis-transcribed one narHash character —
# gate v2 passed both. Neither class of drift may pass silently again:
#
#   * EVERY row of the table must classify as lock-backed or as an explicitly
#     named non-lock identity; an unclassified row is a failure, never a skip.
#   * The declared component set is the single source of truth: every declared
#     component must appear EXACTLY ONCE. A missing row is a named failure
#     (naming every missing component); a duplicate row is rejected
#     immediately, by name. A deleted trust-base row can never report green.
#   * A lock-backed row resolves its authoritative node by traversing
#     `follows` recursively from the root node — never by guessing generated
#     node-name suffixes.
#   * Every documented rev/narHash/lastModified occurrence is compared
#     byte-for-byte; a field documented later comes under the check
#     automatically.
#   * Success reports exactly what was compared so a vacuous pass is visible.
#
# --self-test falsifies the checker on TEMPORARY copies (the worktree is only
# ever read): it seeds the exact one-byte narHash corruption of the incident
# into the Lean-Blaster row and requires the real normal mode to reject it
# (RED leg), requires the uncorrupted control copy to pass (GREEN leg), and
# runs the presence regression vectors — a missing non-lock row, a missing
# lock-backed row, and a duplicate known row — each of which the real normal
# mode must reject with a named diagnostic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
usage: check-blaster-identity-consistency.sh [--repo-root <dir>] [--self-test]
       check-blaster-identity-consistency.sh --identity-manifest <json>
         --blueprint <plutus.json> --expected-commit <sha>
         --expected-aiken <version> --expected-variant <name>
         --expected-era <era> --expected-selection <method>
         --expected-version-derived <variant>
         --expected-verification-receipt <label>
         --expected-toolchain <identity>
         --expected-lock-sha256 <hex>
         --expected-lean-blaster-rev <sha>
         --expected-plutus-core-rev <sha>
         --expected-ledger-api-rev <sha> [--repo-root <dir>]
       check-blaster-identity-consistency.sh --retained-receipt <path>
         --retained-log <path> --expected-receipt-sha256 <hex>
         --expected-log-sha256 <hex> --expected-commit <sha>
         --expected-aiken <version> --expected-variant <name>
         --expected-era <era> [--repo-root <dir>]

  --repo-root <dir>  repository root containing docs/architecture/
                     blaster-tractability.md and offchain/flake.lock
                     (default: parent of this script's directory)
  --self-test        seeded RED/GREEN falsification on temporary copies only
  --identity-manifest
                     verify a computed baseline manifest against its blueprint
  --retained-receipt verify and reject the authenticated historical RED record
EOF
}

fail() { echo "check-blaster-identity-consistency: FAIL: $*" >&2; exit 1; }

REPO_ROOT=""
SELF_TEST=0
IDENTITY_MANIFEST=""
BLUEPRINT=""
RETAINED_RECEIPT=""
RETAINED_LOG=""
EXPECTED_RECEIPT_SHA256=""
EXPECTED_LOG_SHA256=""
EXPECTED_COMMIT=""
EXPECTED_AIKEN=""
EXPECTED_VARIANT=""
EXPECTED_ERA=""
EXPECTED_SELECTION=""
EXPECTED_VERSION_DERIVED=""
EXPECTED_VERIFICATION_RECEIPT=""
EXPECTED_TOOLCHAIN=""
EXPECTED_LOCK_SHA256=""
EXPECTED_LEAN_BLASTER_REV=""
EXPECTED_PLUTUS_CORE_REV=""
EXPECTED_LEDGER_API_REV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) [ $# -ge 2 ] || { usage >&2; exit 2; }; REPO_ROOT=$2; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --identity-manifest) [ $# -ge 2 ] || { usage >&2; exit 2; }; IDENTITY_MANIFEST=$2; shift 2 ;;
    --blueprint) [ $# -ge 2 ] || { usage >&2; exit 2; }; BLUEPRINT=$2; shift 2 ;;
    --retained-receipt) [ $# -ge 2 ] || { usage >&2; exit 2; }; RETAINED_RECEIPT=$2; shift 2 ;;
    --retained-log) [ $# -ge 2 ] || { usage >&2; exit 2; }; RETAINED_LOG=$2; shift 2 ;;
    --expected-receipt-sha256) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_RECEIPT_SHA256=$2; shift 2 ;;
    --expected-log-sha256) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_LOG_SHA256=$2; shift 2 ;;
    --expected-commit) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_COMMIT=$2; shift 2 ;;
    --expected-aiken) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_AIKEN=$2; shift 2 ;;
    --expected-variant) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_VARIANT=$2; shift 2 ;;
    --expected-era) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_ERA=$2; shift 2 ;;
    --expected-selection) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_SELECTION=$2; shift 2 ;;
    --expected-version-derived) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_VERSION_DERIVED=$2; shift 2 ;;
    --expected-verification-receipt) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_VERIFICATION_RECEIPT=$2; shift 2 ;;
    --expected-toolchain) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_TOOLCHAIN=$2; shift 2 ;;
    --expected-lock-sha256) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_LOCK_SHA256=$2; shift 2 ;;
    --expected-lean-blaster-rev) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_LEAN_BLASTER_REV=$2; shift 2 ;;
    --expected-plutus-core-rev) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_PLUTUS_CORE_REV=$2; shift 2 ;;
    --expected-ledger-api-rev) [ $# -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_LEDGER_API_REV=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -d "$REPO_ROOT" ] || fail "repo root '$REPO_ROOT' is not a directory"

DOC_REL="docs/architecture/blaster-tractability.md"
NIX_REL="offchain/flake.nix"
LOCK_REL="offchain/flake.lock"
JUST_REL="justfile"
CI_REL=".github/workflows/ci.yml"
DOC_FILE="$REPO_ROOT/$DOC_REL"
LOCK_FILE="$REPO_ROOT/$LOCK_REL"
NIX_FILE="$REPO_ROOT/$NIX_REL"
JUST_FILE="$REPO_ROOT/$JUST_REL"
CI_FILE="$REPO_ROOT/$CI_REL"

command -v jq >/dev/null 2>&1 || fail "jq is required"
if [ -z "$IDENTITY_MANIFEST" ] && [ -z "$RETAINED_RECEIPT" ]; then
  [ -r "$DOC_FILE" ] || fail "cannot read $DOC_REL from repo root '$REPO_ROOT'"
  [ -r "$LOCK_FILE" ] || fail "cannot read $LOCK_REL from repo root '$REPO_ROOT'"
  [ -r "$NIX_FILE" ] || fail "cannot read $NIX_REL from repo root '$REPO_ROOT'"
  [ -r "$JUST_FILE" ] || fail "cannot read $JUST_REL from repo root '$REPO_ROOT'"
  [ -r "$CI_FILE" ] || fail "cannot read $CI_REL from repo root '$REPO_ROOT'"
  jq -e . "$LOCK_FILE" >/dev/null 2>&1 || fail "$LOCK_REL is not valid JSON"
fi

trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }

# --- lock resolution: traverse `follows` recursively from the root node ---

RESOLVE_DEPTH=0


# --- rc-classified jq (REVIEW-020 seed P) -----------------------------------
# Seed P: a PATH-local jq that emits correct output and then exits 2 produced a
# fully GREEN run. `resolve_input` ran jq inside `resolve_spec`, which callers
# consumed as `node=$(resolve_spec ...)` — and bash CLEARS errexit inside a
# command substitution, so both the non-zero status and any `fail` were confined
# to a subshell the parent never heard from.
#
# I had claimed every extraction was classified. That was false: I audited the
# PIPELINES and never the COMMAND SUBSTITUTIONS — the same half-done port, one
# layer down. Two things are therefore required, and the first is useless
# without the second:
#   1. classify jq's exit status;
#   2. make the failure exit the PARENT shell, which means these producers must
#      not be called through `$( )` at all. They set globals instead.
JQ_OUT=""
_jq() { # <what> <jq-args...> -> sets JQ_OUT; any non-zero status is COULD-NOT-EVALUATE
  local what=$1; shift
  local rc
  set +e; JQ_OUT=$(jq "$@" 2>/dev/null); rc=$?; set -e
  [ "$rc" = 0 ] \
    || fail "COULD-NOT-EVALUATE: $what: jq exited $rc — plausible output from a failed evidence producer must never be consumed"
}
# These three resolvers set RESOLVED_NODE instead of printing it. They used to
# be consumed as `node=$(resolve_spec ...)`, and a command substitution is a
# subshell: errexit is cleared inside it and `fail` cannot exit the parent, so
# every guard below was unenforceable from the caller's side (REVIEW-020 seed P).
RESOLVED_NODE=""

resolve_input() { # <node> <input-key> -> sets RESOLVED_NODE
  local node=$1 key=$2 v t
  RESOLVE_DEPTH=$((RESOLVE_DEPTH + 1))
  [ "$RESOLVE_DEPTH" -le 64 ] || fail "follows resolution exceeded depth 64 (follows cycle?) at node '$node' input '$key'"
  _jq "input '$key' of lock node '$node'" -c --arg n "$node" --arg k "$key" '.nodes[$n].inputs[$k] // empty' "$LOCK_FILE"
  v=$JQ_OUT
  [ -n "$v" ] || fail "lock node '$node' has no input '$key'"
  _jq "type of input '$key' of node '$node'" -rn --argjson v "$v" '$v | type'
  t=$JQ_OUT
  case "$t" in
    string) _jq "value of input '$key' of node '$node'" -rn --argjson v "$v" '$v'; RESOLVED_NODE=$JQ_OUT ;;
    array)  resolve_follows_path "$v" ;;
    *) fail "lock input '$key' of node '$node' has unexpected type '$t'" ;;
  esac
  [ -n "$RESOLVED_NODE" ] || fail "COULD-NOT-EVALUATE: input '$key' of node '$node' resolved to an empty node name"
}

resolve_follows_path() { # <compact JSON path array> -> sets RESOLVED_NODE
  local segs=$1 cur=root n i seg
  _jq "length of follows path" -rn --argjson s "$segs" '$s | length'
  n=$JQ_OUT
  case "$n" in ''|*[!0-9]*) fail "COULD-NOT-EVALUATE: follows path length '$n' is not a number" ;; esac
  [ "$n" -ge 1 ] || fail "empty follows path in $LOCK_REL"
  for ((i = 0; i < n; i++)); do
    _jq "segment $i of follows path" -rn --argjson s "$segs" --argjson i "$i" '$s[$i]'
    seg=$JQ_OUT
    [ -n "$seg" ] || fail "COULD-NOT-EVALUATE: follows path segment $i is empty"
    resolve_input "$cur" "$seg"
    cur=$RESOLVED_NODE
  done
  RESOLVED_NODE=$cur
}

resolve_spec() { # <input-key>... -> sets RESOLVED_NODE, walking from the root node
  local cur=root k
  for k in "$@"; do
    resolve_input "$cur" "$k"
    cur=$RESOLVED_NODE
  done
  RESOLVED_NODE=$cur
}

# --- the single component oracle ---
# Every component the Pinned trust base table must document, exactly once.
# Record format:  <component>|LOCK <input-key path from the root node>
#            or:  <component>|NONLOCK <reason>
# BOTH the classification oracle (classify_row) and the presence oracle (the
# duplicate/missing reconciliation in normal_mode) derive from this one
# declaration, so the two can never drift apart again.

COMPONENT_ORACLE=(
  'Lean|NONLOCK version pin leanprover/lean4:v4.24.0 (not a flake.lock node)'
  'Lean-Blaster|LOCK leanBlaster'
  'PlutusCoreBlaster|LOCK plutusCoreBlaster'
  'CardanoLedgerApiBlaster|LOCK cardanoLedgerApiBlaster'
  'lean4-nix|LOCK lean4Nix'
  'Lean nixpkgs|LOCK leanNixpkgs'
  'Z3|NONLOCK version pin + fetchurl source hash (not a flake.lock node)'
  'Aiken|LOCK aikenNixpkgs'
)

classify_row() { # <component> -> "LOCK <key>..." | "NONLOCK <reason>"; rc 1 if not declared
  local rec
  for rec in "${COMPONENT_ORACLE[@]}"; do
    if [ "${rec%%|*}" = "$1" ]; then
      printf '%s\n' "${rec#*|}"
      return 0
    fi
  done
  return 1
}

# --- table parsing and field extraction ---

table_rows_raw() { # <doc> -> every `|` line of the Pinned trust base section
  awk '
    /^## Pinned trust base[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## /                 { exit }
    in_section && /^[[:space:]]*\|/      { print }
  ' "$1"
}

split_row() { # <row> -> populates ROW_CELLS with the pipe-separated cells
  local body=${1#*|}
  body=${body%|*}
  IFS='|' read -r -a ROW_CELLS <<< "$body"
}

row_component() { # <row> -> trimmed backtick-free Component cell
  local c
  split_row "$1"
  [ "${#ROW_CELLS[@]}" -ge 1 ] || return 1
  c=${ROW_CELLS[0]//\`/}
  trim "$c"
}

tokens_of_cell() { # <cell> -> one candidate identity token per line
  # REVIEW-019: this ended `| grep -v '^$' || true` and was consumed through an
  # unchecked process substitution, so a grep that exited 2 after emitting a
  # PARTIAL token stream was indistinguishable from a clean short row. That is
  # how a coverage shrink forged a total with unchanged bytes and unchanged
  # tree — something no content hash or preimage can detect, because the file
  # is innocent and only the RUNTIME status was lost.
  #
  # Rewritten in pure bash: no pipeline, no external process, therefore no exit
  # code to mishandle and no `|| true` to mask one. Word splitting on the
  # separators does exactly what the tr/tr/grep chain did.
  local t=${1//\`/ } tok
  t=${t//,/ }; t=${t//(/ }; t=${t//)/ }; t=${t//:/ }
  for tok in $t; do
    [ -n "$tok" ] && printf '%s\n' "$tok"
  done
  return 0
}

# --- comparison ---

COMPARED=0
MISMATCHES=0
DIAGNOSTICS=()


# --- explicit extraction status (REVIEW-019) --------------------------------
# Every extraction in this file now classifies its exit status. Previously each
# site ended `|| true`, which collapses "no match" (rc 1) and "grep failed after
# emitting a partial stream" (rc >= 2) into the same empty result. A forged rc 2
# therefore produced a smaller-but-consistent comparison total with the file
# bytes and the tracked tree completely unchanged — invisible to any content
# hash, pin, or preimage, because only the RUNTIME status was lost.
#
# _EXTRACT_OUT is used instead of a command substitution on purpose: `fail`
# inside `$( ... )` runs in a SUBSHELL and would only exit that subshell,
# leaving the caller to continue with an empty value — the very defect this
# guard exists to prevent.
_EXTRACT_OUT=""
_extract() { # <what> <cmd...>  -> sets _EXTRACT_OUT; rc 0/1 authoritative, else CNE
  local what=$1; shift
  local rc
  set +e; _EXTRACT_OUT=$("$@" 2>/dev/null); rc=$?; set -e
  case "$rc" in
    0|1) return 0 ;;
    *) fail "COULD-NOT-EVALUATE: $what: extraction exited $rc — a partial or failed extraction must never be read as 'no match'" ;;
  esac
}

compare_field() { # <component> <field> <documented> <node>
  # REVIEW-019: record WHICH field was compared, not merely how many. A global
  # total is forgeable; a per-component field set is not.
  local comp=$1 field=$2 doc=$3 node=$4 lockv
  _jq "locked.$field of node '$node'" -r --arg n "$node" --arg f "$field" '.nodes[$n].locked[$f] // empty' "$LOCK_FILE"
  lockv=$JQ_OUT
  COMPARED=$((COMPARED + 1))
  ROW_SEEN_FIELDS+=("$field")
  if [ -z "$lockv" ]; then
    MISMATCHES=$((MISMATCHES + 1))
    DIAGNOSTICS+=("MISMATCH component='$comp' field='$field' documented='$doc' lock=<absent in node '$node'>")
  elif [ "$lockv" != "$doc" ]; then
    MISMATCHES=$((MISMATCHES + 1))
    DIAGNOSTICS+=("MISMATCH component='$comp' field='$field' documented='$doc' lock='$lockv' (node '$node')")
  else
    echo "  [OK] component='$comp' field='$field' matches node '$node'"
  fi
}


# --- the coverage invariant (REVIEW-019 seed H) -----------------------------
# Seed H removed ONE narHash from ONE documented row, keeping the row, the
# revision, every declared component, the lock and the exact checker bytes. The
# old test — `ROW_FIELDS > 0`, "does this row document SOME comparable field" —
# accepted it, and so did a global compared-fields total. Neither the external
# hash pin nor the whole-tree preimage can see it in repository CI, where the
# checker's exit code is the only thing standing.
#
# The expectation is now derived from the AUTHORITATIVE LOCK NODE rather than
# from the documentation being checked: whichever identity fields the lock node
# carries, the row must document. A row cannot shrink its own obligations,
# because the obligation is not written on the row.
#
# lastModified is deliberately NOT required: it is not documented today, and
# requiring it would fail every current row. It is compared when present, which
# is the existing behaviour.
IDENTITY_FIELDS=(rev narHash)


# --- provenance and non-lock authority (REVIEW-019 seeds J and K) -----------
# Seat attribution for both seeds: NAVIGATOR. Neither was proposed by this seat.
#
# SEED K showed that resolving a component through the root input key and then
# trusting whatever node that key points at makes the ROOT KEY its own
# provenance proof. Rebinding `root.inputs.plutusCoreBlaster` to the
# CardanoLedgerApiBlaster node and documenting that node's genuine rev and
# narHash produced rc 0 with a full field set: every expected field present,
# every comparison matching — against the wrong project. Field NAMES and field
# COUNTS cannot detect this; only binding the component to an expected SOURCE
# can.
COMPONENT_SOURCE=(
  'Lean-Blaster|paolino/Lean-blaster'
  'PlutusCoreBlaster|input-output-hk/PlutusCoreBlaster'
  'CardanoLedgerApiBlaster|input-output-hk/CardanoLedgerApiBlaster'
  'lean4-nix|lenianiva/lean4-nix'
  'Lean nixpkgs|nixos/nixpkgs'
  'Aiken|NixOS/nixpkgs'
)

expected_source_of() { # <component> -> owner/repo, or empty if undeclared
  local comp=$1 rec
  for rec in "${COMPONENT_SOURCE[@]}"; do
    case "$rec" in "$comp|"*) printf '%s\n' "${rec#*|}"; return 0 ;; esac
  done
  return 0
}

require_node_provenance() { # <component> <node>
  local comp=$1 node=$2 want got type
  want=$(expected_source_of "$comp")
  [ -n "$want" ] \
    || fail "COULD-NOT-EVALUATE: component '$comp' is lock-backed but declares no expected source; provenance cannot be established"
  _jq "locked.type of node '$node'" -r --arg n "$node" '.nodes[$n].locked.type // empty' "$LOCK_FILE"
  type=$JQ_OUT
  [ "$type" = github ] \
    || fail "COULD-NOT-EVALUATE: lock node '$node' for '$comp' has type '${type:-<absent>}'; this check only knows how to authenticate github sources"
  _jq "locked source of node '$node'" -r --arg n "$node" '.nodes[$n].locked | "\(.owner)/\(.repo)"' "$LOCK_FILE"
  got=$JQ_OUT
  # Case-insensitive: nixpkgs appears as both nixos/nixpkgs and NixOS/nixpkgs.
  [ "${got,,}" = "${want,,}" ] \
    || fail "row '$comp' resolves to lock node '$node', whose source is '$got', but '$comp' must come from '$want' — the input key is not proof of provenance; a rebound key would otherwise compare valid values against the wrong project"
}

# SEED J showed the other half: a row classified NONLOCK is never compared at
# all, so corrupting the Z3 source hash by one byte passed with rc 0. The
# authority for that value exists in offchain/flake.nix, so it is compared here
# rather than the contract being narrowed. The expected value is EXTRACTED from
# the authority, never written down twice: a second copy is one more thing to
# drift.
EXPECTED_FIELDS=""
expected_fields_of_node() { # <node> -> sets EXPECTED_FIELDS (never via command substitution)
  local node=$1 f v
  EXPECTED_FIELDS=""
  for f in "${IDENTITY_FIELDS[@]}"; do
    _jq "locked.$f of node '$node'" -r --arg n "$node" --arg f "$f" '.nodes[$n].locked[$f] // empty' "$LOCK_FILE"
    v=$JQ_OUT
    [ -n "$v" ] && EXPECTED_FIELDS+="$f"$'\n'
  done
  return 0
}

require_expected_fields() { # <component> <node>; uses ROW_SEEN_FIELDS
  local comp=$1 node=$2 f seen missing=()
  expected_fields_of_node "$node"
  local exp=$EXPECTED_FIELDS
  [ -n "$exp" ] || fail "COULD-NOT-EVALUATE: lock node '$node' for '$comp' carries none of: ${IDENTITY_FIELDS[*]} — the expectation cannot be established"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    local found=0
    for seen in ${ROW_SEEN_FIELDS[@]+"${ROW_SEEN_FIELDS[@]}"}; do
      [ "$seen" = "$f" ] && { found=1; break; }
    done
    [ "$found" = 1 ] || missing+=("$f")
  done <<< "$exp"
  [ "${#missing[@]}" = 0 ] \
    || fail "row '$comp' is lock-backed but does not document ${missing[*]} — lock node '$node' carries $(printf '%s ' $exp)); a row may not silently drop an identity field it is required to pin"
}
count_row_fields() { # <component> <node> <raw-row>; sets ROW_FIELDS, updates COMPARED
  local comp=$1 node=$2 line=$3 c tok field
  ROW_SEEN_FIELDS=()
  ROW_FIELDS=0
  split_row "$line"
  for c in "${ROW_CELLS[@]:1}"; do
    while IFS= read -r tok; do
      [ -n "$tok" ] || continue
      field=""
      if [[ $tok =~ ^[0-9a-f]{40}$ ]]; then
        field=rev
      elif [[ $tok =~ ^sha256-[A-Za-z0-9+/]+={0,2}$ ]]; then
        field=narHash
      fi
      if [ -n "$field" ]; then
        compare_field "$comp" "$field" "$tok" "$node"
        ROW_FIELDS=$((ROW_FIELDS + 1))
      fi
    done < <(tokens_of_cell "$c")
  done
  # lastModified is not documented today; the moment a row documents it, it is
  # compared automatically — extraction keys on the explicit label, never on
  # bare digits.
  if [[ $line == *lastModified* ]]; then
    # REVIEW-019: extraction status classified before any token is consumed.
    _extract "lastModified tokens for '$comp'" grep -oE 'lastModified[^0-9]{0,12}[0-9]{9,11}' <<< "$line"
    local m num
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      num=${m//[^0-9]/}
      compare_field "$comp" lastModified "$num" "$node"
      ROW_FIELDS=$((ROW_FIELDS + 1))
    done <<< "$_EXTRACT_OUT"
  fi
}

# --- frozen baseline identity ----------------------------------------------

require_identity_arguments() {
  [ -n "$EXPECTED_COMMIT" ] || fail "expected identity is missing commit"
  [ -n "$EXPECTED_AIKEN" ] || fail "expected identity is missing aiken"
  [ -n "$EXPECTED_VARIANT" ] || fail "expected identity is missing variant"
  [ -n "$EXPECTED_ERA" ] || fail "expected identity is missing era"
  [[ $EXPECTED_COMMIT =~ ^[0-9a-f]{40}$ ]] \
    || fail "expected commit '$EXPECTED_COMMIT' is not a 40-byte hex identity"
}

require_manifest_identity_arguments() {
  require_identity_arguments
  [ -n "$EXPECTED_TOOLCHAIN" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: toolchain"
  [ -n "$EXPECTED_LOCK_SHA256" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: lock_sha256"
  [ -n "$EXPECTED_LEAN_BLASTER_REV" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: upstream.lean_blaster"
  [ -n "$EXPECTED_PLUTUS_CORE_REV" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: upstream.plutus_core_blaster"
  [ -n "$EXPECTED_LEDGER_API_REV" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: upstream.cardano_ledger_api_blaster"
  [ -n "$EXPECTED_SELECTION" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: selection"
  [ -n "$EXPECTED_VERSION_DERIVED" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: version_derived"
  [ -n "$EXPECTED_VERIFICATION_RECEIPT" ] \
    || fail "COULD-NOT-EVALUATE: identity field lacks external expectation: verification-receipt.receipt"
}

# Enumerate every leaf in the published manifest. Each line is
# PATH<TAB>JSON-VALUE. `scalars` omits null, so use the structural definition
# of a leaf: anything that is neither an object nor an array.
enumerate_manifest_leaf_population() { # <json> <output>
  jq -r '
    def path_string($path):
      reduce $path[] as $part ("";
        if ($part | type) == "number" then
          . + "[\($part)]"
        elif . == "" then
          ($part | tostring)
        else
          . + "." + ($part | tostring)
        end);
    paths(type != "object" and type != "array") as $path
    | [path_string($path), (getpath($path) | tojson)] | @tsv
  ' "$1" | LC_ALL=C sort -t $'\t' -k1,1 > "$2"
}

# Enumerate every object and array, including the manifest root. Comparing
# this population with the independently built expected document makes an
# empty or future container visible even when it has no leaf beneath it.
enumerate_manifest_container_population() { # <json> <output>
  jq -r '
    def path_string($path):
      reduce $path[] as $part ("";
        if ($part | type) == "number" then
          . + "[\($part)]"
        elif . == "" then
          ($part | tostring)
        else
          . + "." + ($part | tostring)
        end);
    (([]), paths(type == "object" or type == "array")) as $path
    | if ($path | length) == 0 then "$" else path_string($path) end
  ' "$1" | LC_ALL=C sort > "$2"
}

# Build the expectation population only from caller-supplied authorities and
# the source-built blueprint. Nothing in this function reads the manifest
# under test. The resulting document is consumed by the same enumerator as the
# observed manifest, keeping the coverage denominator and expectation registry
# in one instrument without making them one computation.
build_expected_identity_population() { # <blueprint> <blueprint-sha> <output> <work>
  local blueprint=$1 blueprint_sha=$2 output=$3 work=$4
  local title params code program_sha

  : > "$work/programs.jsonl"
  while IFS=$'\t' read -r title params code; do
    program_sha=$(printf '%s' "$code" | sha256sum | cut -d ' ' -f 1)
    jq -cn --arg title "$title" --argjson params "$params" \
      --arg program_sha256 "$program_sha" \
      '{title:$title, params:$params, program_sha256:$program_sha256}' \
      >> "$work/programs.jsonl"
  done < <(jq -r '.validators[] |
    [.title, ((.parameters // []) | length), .compiledCode] | @tsv' "$blueprint")
  jq -s . "$work/programs.jsonl" > "$work/programs.json"

  jq -n \
    --arg commit "$EXPECTED_COMMIT" \
    --arg aiken "$EXPECTED_AIKEN" \
    --arg toolchain "$EXPECTED_TOOLCHAIN" \
    --arg variant "$EXPECTED_VARIANT" \
    --arg era "$EXPECTED_ERA" \
    --arg selection "$EXPECTED_SELECTION" \
    --arg version_derived "$EXPECTED_VERSION_DERIVED" \
    --arg verification_receipt "$EXPECTED_VERIFICATION_RECEIPT" \
    --arg blueprint_sha256 "$blueprint_sha" \
    --arg lock_sha256 "$EXPECTED_LOCK_SHA256" \
    --arg lean_blaster "$EXPECTED_LEAN_BLASTER_REV" \
    --arg plutus_core "$EXPECTED_PLUTUS_CORE_REV" \
    --arg ledger_api "$EXPECTED_LEDGER_API_REV" \
    --slurpfile programs "$work/programs.json" '
    def identity: {
      commit:$commit, aiken:$aiken, toolchain:$toolchain,
      variant:$variant, ledger_language:"PlutusV3", era:$era,
      blueprint_sha256:$blueprint_sha256
    };
    ($programs[0]) as $ps |
    {
      schema:"cardano-keri-baseline-v1",
      identity:(identity + {
        built_from:"source",
        validating_aiken:$aiken,
        selection:$selection,
        version_derived:$version_derived,
        lock_sha256:$lock_sha256,
        upstream:{lean_blaster:$lean_blaster,
          plutus_core_blaster:$plutus_core,
          cardano_ledger_api_blaster:$ledger_api}
      }),
      blueprint_sha256:$blueprint_sha256,
      programs:$ps,
      records: (
        [(identity + {record:"manifest"})]
        + [$ps[] | identity + {record:"program", title:.title,
            params:.params, program_sha256:.program_sha256}]
        + [
            (identity + {record:"baseline"}),
            (identity + {record:"evaluation-identity"}),
            (identity + {record:"verification-receipt",
              receipt:$verification_receipt})
          ]
      )
    }' > "$output"
}

reconcile_identity_field_population() { # <manifest> <blueprint> <blueprint-sha>
  local manifest=$1 blueprint=$2 blueprint_sha=$3
  local work fields expected_fields reconciled unexpected first unexpected_path
  local missing missing_path duplicate_expected mismatch_path expected_value actual_value
  local containers covered_containers uncovered_containers uncovered_container
  work=$(mktemp -d "${TMPDIR:-/tmp}/identity-field-coverage.XXXXXXXX") \
    || fail "COULD-NOT-EVALUATE: identity-field coverage scratch allocation failed"
  trap "rm -rf '$work'" EXIT

  build_expected_identity_population \
    "$blueprint" "$blueprint_sha" "$work/expected.json" "$work"
  enumerate_manifest_leaf_population "$manifest" "$work/actual.tsv"
  enumerate_manifest_leaf_population "$work/expected.json" "$work/expected.tsv"
  enumerate_manifest_container_population "$manifest" "$work/actual.containers"
  enumerate_manifest_container_population "$work/expected.json" "$work/expected.containers"
  cut -f1 "$work/actual.tsv" > "$work/actual.paths"
  cut -f1 "$work/expected.tsv" > "$work/expected.paths"

  duplicate_expected=$(uniq -d "$work/expected.paths" | head -1)
  [ -z "$duplicate_expected" ] \
    || fail "COULD-NOT-EVALUATE: duplicate reconciled expectation: $duplicate_expected"

  fields=$(wc -l < "$work/actual.paths"); fields=${fields//[[:space:]]/}
  expected_fields=$(wc -l < "$work/expected.paths"); expected_fields=${expected_fields//[[:space:]]/}
  reconciled=$(LC_ALL=C comm -12 "$work/actual.paths" "$work/expected.paths" | wc -l)
  reconciled=${reconciled//[[:space:]]/}
  unexpected=$((fields - reconciled))
  containers=$(wc -l < "$work/actual.containers"); containers=${containers//[[:space:]]/}
  expected_containers=$(wc -l < "$work/expected.containers")
  expected_containers=${expected_containers//[[:space:]]/}
  covered_containers=$(LC_ALL=C comm -12 \
    "$work/actual.containers" "$work/expected.containers" | wc -l)
  covered_containers=${covered_containers//[[:space:]]/}
  uncovered_containers=$((containers - covered_containers))
  missing_containers=$(LC_ALL=C comm -13 \
    "$work/actual.containers" "$work/expected.containers" | wc -l)
  missing_containers=${missing_containers//[[:space:]]/}

  echo "CBIC_IDENTITY_RESULT fields=$fields"
  echo "CBIC_IDENTITY_RESULT reconciled=$reconciled"
  echo "CBIC_IDENTITY_RESULT unexpected=$unexpected"
  echo "CBIC_IDENTITY_RESULT containers=$containers"
  echo "CBIC_IDENTITY_RESULT expected_containers=$expected_containers"
  echo "CBIC_IDENTITY_RESULT uncovered_containers=$uncovered_containers"
  echo "CBIC_IDENTITY_RESULT missing_containers=$missing_containers"
  echo "CBIC_IDENTITY_RESULT enumerated_by=jq-leaf-and-container-paths"

  if [ "$unexpected" -ne 0 ]; then
    unexpected_path=$(LC_ALL=C comm -23 \
      "$work/actual.paths" "$work/expected.paths" | head -1)
    fail "COULD-NOT-EVALUATE: identity field lacks reconciled expectation: ${unexpected_path:-<unnamed>} (externally-unexpected field set)"
  fi

  if [ "$uncovered_containers" -ne 0 ]; then
    uncovered_container=$(LC_ALL=C comm -23 \
      "$work/actual.containers" "$work/expected.containers" | head -1)
    fail "COULD-NOT-EVALUATE: manifest container lacks structural expectation: ${uncovered_container:-<unnamed>}"
  fi

  if [ "$missing_containers" -ne 0 ]; then
    missing_container=$(LC_ALL=C comm -13 \
      "$work/actual.containers" "$work/expected.containers" | head -1)
    fail "COULD-NOT-EVALUATE: declared container absent from the artifact: ${missing_container:-<unnamed>}"
  fi

  missing=$((expected_fields - reconciled))
  if [ "$missing" -ne 0 ]; then
    missing_path=$(LC_ALL=C comm -13 \
      "$work/actual.paths" "$work/expected.paths" | head -1)
    first=${missing_path##*.}
    fail "unnamed identity input: ${first:-<unnamed>} path=${missing_path:-<unnamed>} (identity schema moved)"
  fi

  # The expectation registry is not merely a denominator. Its values drive the
  # comparisons whose coverage the verdict publishes; a path-only intersection
  # would recreate the self-referential count under a more elaborate name.
  awk -F '\t' '
    NR == FNR { expected[$1] = $2; next }
    ($1 in expected) && expected[$1] != $2 {
      print $1 "\t" expected[$1] "\t" $2
    }
  ' "$work/expected.tsv" "$work/actual.tsv" > "$work/mismatches.tsv"
  if IFS=$'\t' read -r mismatch_path expected_value actual_value \
      < "$work/mismatches.tsv"; then
    first=${mismatch_path##*.}
    case "$mismatch_path" in
      identity.*)
        fail "identity input moved: $first path=$mismatch_path expected=$expected_value actual=$actual_value"
        ;;
      records*)
        fail "inconsistent identity input: $first path=$mismatch_path expected=$expected_value actual=$actual_value"
        ;;
      programs*|blueprint_sha256|schema)
        fail "manifest input moved: $first path=$mismatch_path expected=$expected_value actual=$actual_value"
        ;;
      *)
        fail "identity input moved: $mismatch_path expected=$expected_value actual=$actual_value"
        ;;
    esac
  fi
}

identity_manifest_mode() {
  require_manifest_identity_arguments
  [ -r "$IDENTITY_MANIFEST" ] || fail "cannot read identity manifest '$IDENTITY_MANIFEST'"
  [ -r "$BLUEPRINT" ] || fail "cannot read blueprint '$BLUEPRINT'"
  jq -e . "$IDENTITY_MANIFEST" >/dev/null 2>&1 \
    || fail "identity manifest is not valid JSON"
  jq -e . "$BLUEPRINT" >/dev/null 2>&1 \
    || fail "blueprint schema: artifact is not valid JSON"

  jq -e '.validators | type == "array" and length > 0' "$BLUEPRINT" >/dev/null 2>&1 \
    || fail "blueprint schema: validators must be a non-empty array"
  jq -e '[.validators[].title | type == "string" and length > 0 and test("^[^[:space:]]+$")] | all' \
    "$BLUEPRINT" >/dev/null 2>&1 \
    || fail "blueprint schema: title must be a non-empty whitespace-free string"
  jq -e '[.validators[].compiledCode | type == "string" and length > 0 and
      test("^[0-9A-Fa-f]+$") and ((length % 2) == 0)] | all' \
    "$BLUEPRINT" >/dev/null 2>&1 \
    || fail "blueprint schema: compiledCode must be non-empty even-length hex on every row"
  jq -e '[.validators[] | ((.parameters // []) | type) == "array"] | all' \
    "$BLUEPRINT" >/dev/null 2>&1 \
    || fail "blueprint schema: parameters must be an array on every row"

  local titles distinct_programs
  titles=$(jq -er '.validators | length' "$BLUEPRINT")
  distinct_programs=$(jq -er '[.validators[].compiledCode] | unique | length' "$BLUEPRINT")
  [ "$titles" -eq 23 ] \
    || fail "manifest cardinality moved: titles expected=23 actual=$titles"
  [ "$distinct_programs" -eq 8 ] \
    || fail "manifest cardinality moved: programs expected=8 actual=$distinct_programs"
  jq -e '([.validators[].title] | length) == ([.validators[].title] | unique | length)' \
    "$BLUEPRINT" >/dev/null 2>&1 \
    || fail "blueprint schema: duplicate title"

  local actual_blueprint_sha manifest_blueprint_sha
  actual_blueprint_sha=$(sha256sum "$BLUEPRINT" | cut -d ' ' -f 1)
  reconcile_identity_field_population \
    "$IDENTITY_MANIFEST" "$BLUEPRINT" "$actual_blueprint_sha"
  manifest_blueprint_sha=$(jq -r '.blueprint_sha256 // empty' "$IDENTITY_MANIFEST")
  [ "$manifest_blueprint_sha" = "$actual_blueprint_sha" ] \
    || fail "manifest input moved: blueprint_sha256 expected=$actual_blueprint_sha actual=${manifest_blueprint_sha:-<unnamed>}"

  local got identity_keys upstream_keys
  got=$(jq -r '.schema // empty' "$IDENTITY_MANIFEST")
  [ "$got" = cardano-keri-baseline-v1 ] \
    || fail "manifest input moved: schema expected=cardano-keri-baseline-v1 actual=${got:-<unnamed>}"
  identity_keys=$(jq -r '.identity | keys | sort | join(",")' "$IDENTITY_MANIFEST")
  [ "$identity_keys" = "aiken,blueprint_sha256,built_from,commit,era,ledger_language,lock_sha256,selection,toolchain,upstream,validating_aiken,variant,version_derived" ] \
    || fail "identity schema moved: unexpected or externally-unexpected field set: ${identity_keys:-<unnamed>}"
  upstream_keys=$(jq -r '.identity.upstream | keys | sort | join(",")' "$IDENTITY_MANIFEST")
  [ "$upstream_keys" = "cardano_ledger_api_blaster,lean_blaster,plutus_core_blaster" ] \
    || fail "identity schema moved: unexpected upstream field set: ${upstream_keys:-<unnamed>}"
  got=$(jq -r '.identity.commit // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_COMMIT" ] \
    || fail "identity input moved: commit expected=$EXPECTED_COMMIT actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.aiken // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_AIKEN" ] \
    || fail "identity input moved: aiken expected=$EXPECTED_AIKEN actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.validating_aiken // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_AIKEN" ] \
    || fail "identity input moved: validating_aiken expected=$EXPECTED_AIKEN actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.variant // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_VARIANT" ] \
    || fail "identity input moved: variant expected=$EXPECTED_VARIANT actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.era // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_ERA" ] \
    || fail "identity input moved: era expected=$EXPECTED_ERA actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.toolchain // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_TOOLCHAIN" ] \
    || fail "identity input moved: toolchain expected=$EXPECTED_TOOLCHAIN actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.lock_sha256 // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_LOCK_SHA256" ] \
    || fail "identity input moved: lock_sha256 expected=$EXPECTED_LOCK_SHA256 actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.upstream.lean_blaster // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_LEAN_BLASTER_REV" ] \
    || fail "identity input moved: upstream.lean_blaster expected=$EXPECTED_LEAN_BLASTER_REV actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.upstream.plutus_core_blaster // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_PLUTUS_CORE_REV" ] \
    || fail "identity input moved: upstream.plutus_core_blaster expected=$EXPECTED_PLUTUS_CORE_REV actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.upstream.cardano_ledger_api_blaster // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_LEDGER_API_REV" ] \
    || fail "identity input moved: upstream.cardano_ledger_api_blaster expected=$EXPECTED_LEDGER_API_REV actual=${got:-<unnamed>}"
  [ "$(jq -r '.identity.ledger_language // empty' "$IDENTITY_MANIFEST")" = PlutusV3 ] \
    || fail "identity input moved: ledger_language"
  [ "$(jq -r '.identity.built_from // empty' "$IDENTITY_MANIFEST")" = source ] \
    || fail "identity input moved: built_from"
  got=$(jq -r '.identity.selection // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_SELECTION" ] \
    || fail "identity input moved: selection expected=$EXPECTED_SELECTION actual=${got:-<unnamed>}"
  got=$(jq -r '.identity.version_derived // empty' "$IDENTITY_MANIFEST")
  [ "$got" = "$EXPECTED_VERSION_DERIVED" ] \
    || fail "identity input moved: version_derived expected=$EXPECTED_VERSION_DERIVED actual=${got:-<unnamed>}"
  [ "$got" != "$EXPECTED_VARIANT" ] \
    || fail "identity input moved: version_derived silently stands in for explicit variant"
  [ "$(jq -r '.identity.blueprint_sha256 // empty' "$IDENTITY_MANIFEST")" = "$actual_blueprint_sha" ] \
    || fail "manifest input moved: identity.blueprint_sha256"

  local manifest_programs i=0 title params code expected_title expected_params
  local expected_program_sha manifest_title manifest_params manifest_program_sha
  manifest_programs=$(jq -er '.programs | length' "$IDENTITY_MANIFEST")
  [ "$manifest_programs" -eq "$titles" ] \
    || fail "manifest cardinality moved: program rows expected=$titles actual=$manifest_programs"
  while IFS=$'\t' read -r title params code; do
    expected_title=$title
    expected_params=$params
    expected_program_sha=$(printf '%s' "$code" | sha256sum | cut -d ' ' -f 1)
    manifest_title=$(jq -r --argjson i "$i" '.programs[$i].title // empty' "$IDENTITY_MANIFEST")
    manifest_params=$(jq -r --argjson i "$i" '.programs[$i].params // empty' "$IDENTITY_MANIFEST")
    manifest_program_sha=$(jq -r --argjson i "$i" '.programs[$i].program_sha256 // empty' "$IDENTITY_MANIFEST")
    [ "$manifest_title" = "$expected_title" ] \
      || fail "manifest input moved: title row=$i expected=$expected_title actual=${manifest_title:-<unnamed>}"
    [ "$manifest_params" = "$expected_params" ] \
      || fail "manifest input moved: params title=$expected_title expected=$expected_params actual=${manifest_params:-<unnamed>}"
    [ "$manifest_program_sha" = "$expected_program_sha" ] \
      || fail "manifest input moved: program_sha256 title=$expected_title expected=$expected_program_sha actual=${manifest_program_sha:-<unnamed>}"
    i=$((i + 1))
  done < <(jq -r '.validators[] | [.title, ((.parameters // []) | length), .compiledCode] | @tsv' "$BLUEPRINT")
  [ "$i" -eq "$titles" ] || fail "COULD-NOT-EVALUATE: blueprint row traversal stopped at $i of $titles"

  jq -e '[.records[] | select(.record == "program") |
      {title, params, program_sha256}] == .programs' "$IDENTITY_MANIFEST" >/dev/null 2>&1 \
    || fail "inconsistent identity input: program records do not equal manifest rows"
  for spec in manifest:1 baseline:1 evaluation-identity:1 verification-receipt:1; do
    local kind=${spec%%:*} want=${spec##*:} count
    count=$(jq -r --arg kind "$kind" '[.records[] | select(.record == $kind)] | length' "$IDENTITY_MANIFEST")
    [ "$count" -eq "$want" ] \
      || fail "identity record inventory moved: kind=$kind expected=$want actual=$count"
  done

  local records_checked record index=0 value record_kind record_keys expected_record_keys
  records_checked=$(jq -er '.records | length' "$IDENTITY_MANIFEST")
  [ "$records_checked" -eq $((titles + 4)) ] \
    || fail "identity record inventory moved: expected=$((titles + 4)) actual=$records_checked"
  while IFS= read -r record; do
    for field in commit aiken toolchain variant ledger_language era blueprint_sha256; do
      value=$(jq -r --arg field "$field" '.[$field] // empty' <<< "$record")
      [ -n "$value" ] || fail "unnamed identity input: $field record_index=$index"
    done
    record_kind=$(jq -r '.record // empty' <<< "$record")
    record_keys=$(jq -r 'keys | sort | join(",")' <<< "$record")
    case "$record_kind" in
      manifest|baseline|evaluation-identity)
        expected_record_keys="aiken,blueprint_sha256,commit,era,ledger_language,record,toolchain,variant"
        ;;
      program)
        expected_record_keys="aiken,blueprint_sha256,commit,era,ledger_language,params,program_sha256,record,title,toolchain,variant"
        ;;
      verification-receipt)
        expected_record_keys="aiken,blueprint_sha256,commit,era,ledger_language,receipt,record,toolchain,variant"
        ;;
      *) fail "identity record schema moved: unnamed or unexpected record kind at index=$index" ;;
    esac
    [ "$record_keys" = "$expected_record_keys" ] \
      || fail "identity record schema moved: kind=$record_kind index=$index expected=$expected_record_keys actual=$record_keys"
    value=$(jq -r '.commit' <<< "$record")
    [ "$value" = "$EXPECTED_COMMIT" ] \
      || fail "inconsistent identity input: commit record_index=$index expected=$EXPECTED_COMMIT actual=$value"
    value=$(jq -r '.aiken' <<< "$record")
    [ "$value" = "$EXPECTED_AIKEN" ] \
      || fail "inconsistent identity input: aiken record_index=$index expected=$EXPECTED_AIKEN actual=$value"
    value=$(jq -r '.toolchain' <<< "$record")
    [ "$value" = "$EXPECTED_TOOLCHAIN" ] \
      || fail "inconsistent identity input: toolchain record_index=$index expected=$EXPECTED_TOOLCHAIN actual=$value"
    value=$(jq -r '.variant' <<< "$record")
    [ "$value" = "$EXPECTED_VARIANT" ] \
      || fail "inconsistent identity input: variant record_index=$index expected=$EXPECTED_VARIANT actual=$value"
    value=$(jq -r '.blueprint_sha256' <<< "$record")
    [ "$value" = "$actual_blueprint_sha" ] \
      || fail "inconsistent identity input: blueprint_sha256 record_index=$index expected=$actual_blueprint_sha actual=$value"
    value=$(jq -r '.ledger_language' <<< "$record")
    [ "$value" = PlutusV3 ] \
      || fail "inconsistent identity input: ledger_language record_index=$index expected=PlutusV3 actual=$value"
    value=$(jq -r '.era' <<< "$record")
    [ "$value" = "$EXPECTED_ERA" ] \
      || fail "inconsistent identity input: era record_index=$index expected=$EXPECTED_ERA actual=$value"
    if [ "$record_kind" = verification-receipt ]; then
      value=$(jq -r '.receipt // empty' <<< "$record")
      [ "$value" = "$EXPECTED_VERIFICATION_RECEIPT" ] \
        || fail "inconsistent identity input: receipt record_index=$index expected=$EXPECTED_VERIFICATION_RECEIPT actual=${value:-<unnamed>}"
    fi
    index=$((index + 1))
  done < <(jq -c '.records[]' "$IDENTITY_MANIFEST")
  [ "$index" -eq "$records_checked" ] \
    || fail "COULD-NOT-EVALUATE: identity record traversal stopped at $index of $records_checked"

  echo "CBIC_IDENTITY_RESULT records_checked=$records_checked"
  echo "CBIC_IDENTITY_RESULT inconsistent=0"
  echo "CBIC_IDENTITY_RESULT titles=$titles"
  echo "CBIC_IDENTITY_RESULT programs=$distinct_programs"
  echo "check-blaster-identity-consistency: OK — baseline manifest and every carried record share one complete identity"
}

retained_receipt_mode() {
  require_identity_arguments
  [ -r "$RETAINED_RECEIPT" ] || fail "cannot read retained receipt '$RETAINED_RECEIPT'"
  [ -r "$RETAINED_LOG" ] || fail "cannot read retained log '$RETAINED_LOG'"
  [ -n "$EXPECTED_RECEIPT_SHA256" ] || fail "retained receipt expected digest is unnamed"
  [ -n "$EXPECTED_LOG_SHA256" ] || fail "retained log expected digest is unnamed"
  local actual_receipt_sha actual_log_sha
  actual_receipt_sha=$(sha256sum "$RETAINED_RECEIPT" | cut -d ' ' -f 1)
  actual_log_sha=$(sha256sum "$RETAINED_LOG" | cut -d ' ' -f 1)
  [ "$actual_receipt_sha" = "$EXPECTED_RECEIPT_SHA256" ] \
    || fail "retained receipt digest moved: expected=$EXPECTED_RECEIPT_SHA256 actual=$actual_receipt_sha"
  [ "$actual_log_sha" = "$EXPECTED_LOG_SHA256" ] \
    || fail "retained log digest moved: expected=$EXPECTED_LOG_SHA256 actual=$actual_log_sha"
  grep -Fq "$EXPECTED_LOG_SHA256" "$RETAINED_RECEIPT" \
    || fail "retained receipt does not bind the authenticated raw log digest"

  local observed_commit observed_aiken observed_variant inconsistent=0
  observed_commit=$(sed -n 's/^artifact\.source_identity=\([0-9a-f]\{40\}\)$/\1/p' "$RETAINED_LOG" | head -1)
  observed_aiken=$(sed -n 's/^toolchain\.aiken=\([^:]*\):.*$/\1/p' "$RETAINED_LOG" | head -1)
  observed_variant=$(grep -Eo '^identity\.variant=[^ ]+|^variant=[^ ]+' "$RETAINED_LOG" | head -1 | cut -d= -f2 || true)
  if [ -z "$observed_commit" ]; then
    echo "unnamed identity input: commit" >&2
    inconsistent=$((inconsistent + 1))
  elif [ "$observed_commit" != "$EXPECTED_COMMIT" ]; then
    echo "inconsistent identity input: commit expected=$EXPECTED_COMMIT actual=$observed_commit" >&2
    inconsistent=$((inconsistent + 1))
  fi
  if [ -z "$observed_aiken" ]; then
    echo "unnamed identity input: aiken" >&2
    inconsistent=$((inconsistent + 1))
  elif [ "$observed_aiken" != "$EXPECTED_AIKEN" ]; then
    echo "inconsistent identity input: aiken expected=$EXPECTED_AIKEN actual=$observed_aiken" >&2
    inconsistent=$((inconsistent + 1))
  fi
  if [ -z "$observed_variant" ]; then
    echo "unnamed identity input: variant" >&2
    inconsistent=$((inconsistent + 1))
  elif [ "$observed_variant" != "$EXPECTED_VARIANT" ]; then
    echo "inconsistent identity input: variant expected=$EXPECTED_VARIANT actual=$observed_variant" >&2
    inconsistent=$((inconsistent + 1))
  fi
  echo "CBIC_IDENTITY_RESULT records_checked=1"
  echo "CBIC_IDENTITY_RESULT inconsistent=$inconsistent"
  [ "$inconsistent" -eq 0 ] \
    || fail "retained pre-slice receipt is REFUTED under the frozen identity"
  fail "retained pre-slice receipt unexpectedly describes the frozen identity"
}

# --- normal mode ---


# Emitted on EVERY exit path of normal mode, once. A consumer therefore sees
# what the run computed even when it failed early, which is what the contract
# promises. Guarded so the success path and the trap cannot both report.
NORMAL_RESULT_EMITTED=0
classified=0
lock_backed=0
validating_aiken_pins=0
historical_c_records=0
emit_normal_result() {
  [ "$NORMAL_RESULT_EMITTED" = 0 ] || return 0
  NORMAL_RESULT_EMITTED=1
  echo "CBIC_RESULT classified_rows=$classified"
  echo "CBIC_RESULT lock_backed_rows=$lock_backed"
  echo "CBIC_RESULT compared_fields=$COMPARED"
  echo "CBIC_RESULT mismatches=$MISMATCHES"
  echo "CBIC_RESULT validating_aiken_pins=$validating_aiken_pins"
  echo "CBIC_RESULT historical_c_records=$historical_c_records"
}

check_aiken_pin_owner() { # <owner-label> <file> <flake|command> <expected-rev>
  local owner=$1 file=$2 mode=$3 expected=$4 line armed=0 rev
  local -A seen=()
  while IFS= read -r line; do
    if [ "$mode" = flake ]; then
      if [[ $line == *aikenNixpkgs.url* ]]; then
        armed=1
        if [[ $line =~ github:NixOS/nixpkgs/([0-9a-f]{40}) ]]; then
          seen[${BASH_REMATCH[1]}]=1
          armed=0
        fi
        continue
      fi
      [ "$armed" -eq 1 ] || continue
      if [[ $line =~ github:NixOS/nixpkgs/([0-9a-f]{40}) ]]; then
        seen[${BASH_REMATCH[1]}]=1
        armed=0
      elif [[ $line == *';'* ]]; then
        armed=0
      fi
    elif [[ $line =~ github:NixOS/nixpkgs/([0-9a-f]{40})#aiken ]]; then
      seen[${BASH_REMATCH[1]}]=1
    fi
  done < "$file"
  if [ "${#seen[@]}" -ne 1 ]; then
    fail "validating Aiken pin moved: $owner names ${#seen[@]} distinct revisions (expected exactly one: $expected)"
  fi
  for rev in "${!seen[@]}"; do
    [ "$rev" = "$expected" ] \
      || fail "validating Aiken pin moved: $owner expected=$expected actual=$rev"
  done
  validating_aiken_pins=$((validating_aiken_pins + 1))
}

check_non_artifact_identity_axes() {
  resolve_spec aikenNixpkgs
  local aiken_node=$RESOLVED_NODE expected_aiken_rev
  _jq "validating Aiken revision" -r --arg n "$aiken_node" '.nodes[$n].locked.rev // empty' "$LOCK_FILE"
  expected_aiken_rev=$JQ_OUT
  [[ $expected_aiken_rev =~ ^[0-9a-f]{40}$ ]] \
    || fail "COULD-NOT-EVALUATE: validating Aiken lock node '$aiken_node' has no revision"
  check_aiken_pin_owner offchain/flake.nix "$NIX_FILE" flake "$expected_aiken_rev"
  check_aiken_pin_owner justfile "$JUST_FILE" command "$expected_aiken_rev"
  check_aiken_pin_owner .github/workflows/ci.yml "$CI_FILE" command "$expected_aiken_rev"

  local historical_marker='Historical evidence identity: `PlutusV3 / pre-Conway / defaultFunSemanticsVariantC`.'
  grep -Fqx "$historical_marker" "$DOC_FILE" \
    || fail "historical C material relabelled or unnamed: expected exact marker '$historical_marker'"
  grep -Fq '896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c' "$DOC_FILE" \
    || fail "historical C material relabelled: retired pre-#219 blueprint identity is missing"
  grep -Fq '713c747bc83226c71fdcf6b6c174832fd4f69d738439842990d68e163ac26a9a' "$DOC_FILE" \
    || fail "historical C material relabelled: retired pre-#219 program identity is missing"
  historical_c_records=1
}
normal_mode() {
  local rows
  rows=$(table_rows_raw "$DOC_FILE")
  [ -n "$rows" ] || fail "no 'Pinned trust base' table found in $DOC_REL"

  local -a all=()
  mapfile -t all <<< "$rows"
  [ "${#all[@]}" -ge 3 ] || fail "'Pinned trust base' table has no data rows in $DOC_REL"
  case "${all[0]}" in
    *Component*) ;;
    *) fail "table header lacks a Component column: ${all[0]}" ;;
  esac
  case "${all[1]}" in
    *[![:space:]|:-]*) fail "second table line is not a markdown separator: ${all[1]}" ;;
  esac

  local line comp cls node row_fields
  # REVIEW-020: these were locals, and the result block was emitted only after
  # complete reconciliation — so a named early failure (seed H) exited having
  # computed four counters and reported NONE of them, contradicting the
  # contract's own rule. They are globals now, and an EXIT trap reports
  # whatever the run actually reached, on every path.
  classified=0; lock_backed=0
  trap emit_normal_result EXIT
  local -a spec=()
  local -A observed=()

  for line in "${all[@]:2}"; do
    comp=$(row_component "$line")
    [ -n "$comp" ] || fail "table row with empty Component cell: $line"

    # Presence oracle, part 1: reject a duplicate immediately, naming it.
    if [ -n "${observed[$comp]+present}" ]; then
      fail "duplicate row for component '$comp': each Pinned trust base component must be documented exactly once"
    fi
    observed[$comp]=present

    if ! cls=$(classify_row "$comp"); then
      fail "unclassified row '$comp': every Pinned trust base row must be lock-backed or an explicitly named non-lock identity"
    fi
    classified=$((classified + 1))

    case "$cls" in
      NONLOCK*)
        echo "row '$comp': explicitly named non-lock identity (${cls#NONLOCK })"
        ;;
      LOCK*)
        lock_backed=$((lock_backed + 1))
        read -r -a spec <<< "${cls#LOCK }"
        # No command substitution: a failure inside must exit the PARENT shell.
        resolve_spec "${spec[@]}"
        node=$RESOLVED_NODE
        echo "row '$comp': lock-backed, resolved lock node '$node' (input path from root: ${spec[*]})"
        count_row_fields "$comp" "$node" "$line"
        [ "$ROW_FIELDS" -gt 0 ] || fail "row '$comp' is lock-backed but documents no comparable identity fields (vacuous row)"
        require_node_provenance "$comp" "$node"
        require_expected_fields "$comp" "$node"
        ;;
    esac
  done

  # Presence oracle, part 2: reconcile the observed rows against EVERY
  # component declared in the single oracle; name every missing one.
  local -a missing=()
  local rec
  for rec in "${COMPONENT_ORACLE[@]}"; do
    comp=${rec%%|*}
    [ -n "${observed[$comp]+present}" ] || missing+=("'$comp'")
  done
  [ "${#missing[@]}" -eq 0 ] \
    || fail "missing Pinned trust base component(s): ${missing[*]} — every declared component must be documented exactly once"

  check_non_artifact_identity_axes

  emit_normal_result

  echo "classified rows: $classified"
  echo "lock-backed rows: $lock_backed"
  echo "compared fields: $COMPARED"
  echo "mismatches: $MISMATCHES"

  if [ "$MISMATCHES" -gt 0 ]; then
    echo "check-blaster-identity-consistency: FAIL — documented identities diverge from $LOCK_REL:" >&2
    printf '%s\n' "${DIAGNOSTICS[@]}" >&2
    exit 1
  fi
  [ "$classified" -gt 0 ] || fail "no rows classified (vacuous pass)"
  [ "$lock_backed" -gt 0 ] || fail "no lock-backed rows classified (vacuous pass)"
  echo "check-blaster-identity-consistency: OK — every documented identity byte-matches its authoritative lock node"
}

# --- self-test: seeded falsification on temporary copies only ---

# Tamper helpers for the presence regression vectors. Both operate on a COPY of
# the doc and identify a row exactly the way normal mode does: first table cell,
# backticks and whitespace stripped.

drop_row_for() { # <src-doc> <dst-doc> <component> — drop the row of <component>
  awk -v comp="$3" '
    {
      if ($0 ~ /^[[:space:]]*\|/) {
        cell = $0
        sub(/^[[:space:]]*\|/, "", cell)
        sub(/\|.*$/, "", cell)
        gsub(/[`[:space:]]/, "", cell)
        if (cell == comp) next
      }
      print
    }' "$1" > "$2"
}

dup_row_for() { # <src-doc> <dst-doc> <component> — emit the row of <component> twice
  awk -v comp="$3" '
    {
      print
      if ($0 ~ /^[[:space:]]*\|/) {
        cell = $0
        sub(/^[[:space:]]*\|/, "", cell)
        sub(/\|.*$/, "", cell)
        gsub(/[`[:space:]]/, "", cell)
        if (cell == comp) print
      }
    }' "$1" > "$2"
}

self_test_mode() {
  local line lb_hash='' c tok comp

  # Extract the Lean-Blaster documented narHash programmatically from the doc.
  while IFS= read -r line; do
    comp=$(row_component "$line")
    [ "$comp" = "Lean-Blaster" ] || continue
    split_row "$line"
    for c in "${ROW_CELLS[@]:1}"; do
      while IFS= read -r tok; do
        if [[ $tok =~ ^sha256-[A-Za-z0-9+/]+={0,2}$ ]]; then
          lb_hash=$tok
        fi
      done < <(tokens_of_cell "$c")
    done
  done < <(table_rows_raw "$DOC_FILE" | sed -n '3,$p')
  [ -n "$lb_hash" ] || fail "self-test: Lean-Blaster row yielded no documented narHash — extraction broken"

  local count
  # REVIEW-019: a forgeable count. `|| true` made rc>=2 indistinguishable
  # from "no occurrences", so a partial extraction produced a smaller total.
  _extract "occurrence count for count" grep -F -o -- "$lb_hash" "$DOC_FILE"
  count=0; if [ -n "$_EXTRACT_OUT" ]; then while IFS= read -r _x; do count=$(( count + 1 )); done <<< "$_EXTRACT_OUT"; fi
  echo "self-test: Lean-Blaster documented narHash extracted programmatically from $DOC_REL"
  echo "self-test: occurrences of that exact narHash in $DOC_REL: $count (required exactly 1)"
  [ "$count" -eq 1 ] || fail "self-test: expected exactly 1 occurrence of the documented narHash, found $count"

  case "$lb_hash" in
    *P0O7Mp*) ;;
    *) fail "self-test: extracted narHash does not contain the incident context 'P0O7Mp'; refusing to seed a different corruption" ;;
  esac
  local corrupted=${lb_hash/P0O7Mp/P0N7Mp}
  [ "$corrupted" != "$lb_hash" ] || fail "self-test: seeded corruption was a no-op"


# --- uniform seeded negative-control legs (REVIEW-019 item 4) ---------------
# The five original legs were five inline blocks, and every gate defect this
# ticket chased had the same origin: one more hand-written call site with its
# own way of getting the exit status wrong. New legs therefore go through ONE
# helper. A new seed is a mutator function and an expected diagnostic, not
# another block of copied plumbing.
#
# Seat attribution is recorded per seed: seeds H and I are the ticket owner's,
# seeds J and K are the NAVIGATOR's and were not proposed by this seat.
SEED_LEG_FAILURES=0

run_seed_leg() { # <key> <label> <expected-diagnostic-substring> <mutator-fn>
  local key=$1 label=$2 expect=$3 mut=$4 pathpfx=${5:-} root out rc
  root=$(mktemp -d "${TMPDIR:-/tmp}/blaster-identity-seed-$key.XXXXXXXX") \
    || fail "COULD-NOT-EVALUATE: $label: mktemp failed"
  mkdir -p "$root/$(dirname "$DOC_REL")" "$root/$(dirname "$LOCK_REL")" \
    "$root/$(dirname "$NIX_REL")" "$root/$(dirname "$CI_REL")" \
    || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: could not build the scratch tree"; }
  cp -- "$DOC_FILE" "$root/$DOC_REL"   || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: doc copy failed"; }
  cp -- "$LOCK_FILE" "$root/$LOCK_REL" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: lock copy failed"; }
  cp -- "$NIX_FILE" "$root/$NIX_REL"   || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: nix copy failed"; }
  cp -- "$JUST_FILE" "$root/$JUST_REL" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: justfile copy failed"; }
  cp -- "$CI_FILE" "$root/$CI_REL"     || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: CI copy failed"; }
  "$mut" "$root" || { rm -rf "$root"; fail "COULD-NOT-EVALUATE: $label: the seed mutator failed, so the control never ran"; }
  set +e
  if [ -n "$pathpfx" ]; then
    out=$(PATH="$root/$pathpfx:$PATH" "$SELF" --repo-root "$root" 2>&1); rc=$?
  else
    out=$("$SELF" --repo-root "$root" 2>&1); rc=$?
  fi
  set -e
  rm -rf "$root"
  # A negative control must fail FOR THE STATED REASON. A leg that exits
  # non-zero for an unrelated reason is a vacuous control, so the expected
  # diagnostic is required as well as the exit code.
  if [ "$rc" -ne 0 ] && [[ $out == *"$expect"* ]]; then
    echo "$label: exit code $rc (required non-zero), expected diagnostic present"
  else
    SEED_LEG_FAILURES=$((SEED_LEG_FAILURES + 1))
    echo "$label: FAIL — exit $rc (required non-zero) and/or missing diagnostic '$expect'" >&2
    printf '%s\n' "$out" | sed 's/^/    [child] /' >&2
  fi
  echo "CBIC_RESULT ${key}_rc=$rc"
}

# seed H (ticket owner): drop ONE narHash from ONE lock-backed row.
_seed_h() { local r=$1 t
  t=$(grep -F 'PlutusCoreBlaster' "$r/$DOC_REL" | grep -oE 'sha256-[A-Za-z0-9+/=]{40,}' | head -1)
  [ -n "$t" ] || return 1
  _seed_sub "$r/$DOC_REL" "$t" ""
}
# seed J (NAVIGATOR): corrupt an explicitly NON-LOCK identity by one byte.
# seed K (NAVIGATOR): rebind the root input so valid values compare to the
# WRONG project's node.
_seed_k() { local r=$1
  _seed_sub "$r/$LOCK_REL" '"plutusCoreBlaster": "plutusCoreBlaster"' '"plutusCoreBlaster": "cardanoLedgerApiBlaster"'
}

# rc-2 control (ticket owner, per A-t234-015 item 4): an extraction that
# emits PARTIAL output and then fails must be COULD-NOT-EVALUATE, never read
# as "no match". This is the shape that forged a smaller comparison total
# with every file byte and the whole tracked tree unchanged.
_seed_rc2() { local r=$1 jqbin
  jqbin=$(command -v jq) || return 1
  mkdir -p "$r/badbin" || return 1
  # jq is the only external evidence producer normal mode still uses, so it is
  # the one that must be controlled. This stub answers the root input lookup
  # with CORRECT output and then exits 2 — the shape that produced a fully
  # green run in REVIEW-020 seed P, because the caller consumed it through a
  # command substitution where errexit does not apply.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'for a in "$@"; do case "$a" in *inputs*) %s "$@"; exit 2 ;; esac; done\n' "$jqbin"
    printf 'exec %s "$@"\n' "$jqbin"
  } > "$r/badbin/jq" || return 1
  chmod 755 "$r/badbin/jq" || return 1
}

_seed_sub() { # <file> <literal-from> <literal-to>  — literal, never regex
  local f=$1 a=$2 b=$3 out="" l
  [ -n "$a" ] || return 1
  grep -qF -- "$a" "$f" || return 1
  while IFS= read -r l; do out+="${l//"$a"/"$b"}"$'\n'; done < "$f"
  printf '%s' "$out" > "$f"
}
  local red_root green_root miss_nonlock_root miss_lock_root dup_root
  red_root=$(mktemp -d "${TMPDIR:-/tmp}/blaster-identity-selftest-red.XXXXXXXX")
  green_root=$(mktemp -d "${TMPDIR:-/tmp}/blaster-identity-selftest-green.XXXXXXXX")
  miss_nonlock_root=$(mktemp -d "${TMPDIR:-/tmp}/blaster-identity-selftest-miss-nonlock.XXXXXXXX")
  miss_lock_root=$(mktemp -d "${TMPDIR:-/tmp}/blaster-identity-selftest-miss-lock.XXXXXXXX")
  dup_root=$(mktemp -d "${TMPDIR:-/tmp}/blaster-identity-selftest-dup.XXXXXXXX")
  # Double quotes on purpose: the temp paths are expanded into the trap NOW,
  # while the locals are in scope; the EXIT trap itself fires after the
  # function returns, when they no longer are.
  trap "rm -rf '$red_root' '$green_root' '$miss_nonlock_root' '$miss_lock_root' '$dup_root'" EXIT

  local r
  for r in "$red_root" "$green_root" "$miss_nonlock_root" "$miss_lock_root" "$dup_root"; do
    mkdir -p "$r/docs/architecture" "$r/offchain" "$r/.github/workflows"
    # The non-lock authority (offchain/flake.nix) is now part of every scratch
    # root: without it the checker cannot establish the Z3 identity and every
    # leg would report could-not-evaluate instead of testing what it names.
    cp "$NIX_FILE" "$r/$NIX_REL"
    cp "$JUST_FILE" "$r/$JUST_REL"
    cp "$CI_FILE" "$r/$CI_REL"
    cp "$LOCK_FILE" "$r/$LOCK_REL"
  done
  cp "$DOC_FILE" "$green_root/$DOC_REL"

  # Seed exactly the incident's one-byte corruption (O -> N) in the RED copy:
  # fixed-string awk replacement, no regex and no delimiter hazards.
  awk -v pat="$lb_hash" -v rep="$corrupted" '
    { i = index($0, pat)
      if (i > 0) { print substr($0, 1, i - 1) rep substr($0, i + length(pat)) }
      else print
    }' "$DOC_FILE" > "$red_root/$DOC_REL"

  local orig_left bad_now
  # REVIEW-019: a forgeable count. `|| true` made rc>=2 indistinguishable
  # from "no occurrences", so a partial extraction produced a smaller total.
  _extract "occurrence count for orig_left" grep -F -o -- "$lb_hash" "$red_root/$DOC_REL"
  orig_left=0; if [ -n "$_EXTRACT_OUT" ]; then while IFS= read -r _x; do orig_left=$(( orig_left + 1 )); done <<< "$_EXTRACT_OUT"; fi
  # REVIEW-019: a forgeable count. `|| true` made rc>=2 indistinguishable
  # from "no occurrences", so a partial extraction produced a smaller total.
  _extract "occurrence count for bad_now" grep -F -o -- "$corrupted" "$red_root/$DOC_REL"
  bad_now=0; if [ -n "$_EXTRACT_OUT" ]; then while IFS= read -r _x; do bad_now=$(( bad_now + 1 )); done <<< "$_EXTRACT_OUT"; fi
  { [ "$orig_left" -eq 0 ] && [ "$bad_now" -eq 1 ]; } \
    || fail "self-test: seeding changed zero or multiple occurrences (original left=$orig_left, corrupted=$bad_now)"
  echo "self-test: seeded exactly the incident one-byte corruption into a temporary doc copy (1 occurrence)"

  # Presence regression vectors (CORRECTION-2): every surviving identity in
  # these copies still byte-matches the lock, yet the table itself is wrong.
  # The checker must reject each copy — a deleted row can never report green.
  drop_row_for "$DOC_FILE" "$miss_nonlock_root/$DOC_REL" 'Lean'
  drop_row_for "$DOC_FILE" "$miss_lock_root/$DOC_REL" 'Aiken'
  dup_row_for  "$DOC_FILE" "$dup_root/$DOC_REL" 'Z3'
  for r in "$miss_nonlock_root" "$miss_lock_root" "$dup_root"; do
    cmp -s "$DOC_FILE" "$r/$DOC_REL" && fail "self-test: tampering produced an unmodified doc copy for $r"
  done
  echo "self-test: seeded the three presence vectors into temporary doc copies (missing non-lock row, missing lock-backed row, duplicate row)"

  echo "self-test: RED leg — real normal-mode checker against the corrupted temporary copy:"
  local red_out red_rc
  set +e; red_out=$("$SELF" --repo-root "$red_root" 2>&1); red_rc=$?; set -e
  local red_diag
  # REVIEW-019: this decides whether a self-test leg passed, so rc>=2 must
  # be could-not-evaluate, not an absent diagnostic.
  _extract "red_diag self-test diagnostic" bash -c "printf '%s
' "$red_out" | grep -F "component='Lean-Blaster'" | grep -F "field='narHash'""
  red_diag=$_EXTRACT_OUT

  echo "self-test: GREEN leg — real normal-mode checker against the uncorrupted temporary control copy:"
  local green_out green_rc
  set +e; green_out=$("$SELF" --repo-root "$green_root" 2>&1); green_rc=$?; set -e

  echo "self-test: MISSING-NONLOCK leg — real normal-mode checker against the copy missing the non-lock 'Lean' row:"
  local mn_out mn_rc mn_diag
  set +e; mn_out=$("$SELF" --repo-root "$miss_nonlock_root" 2>&1); mn_rc=$?; set -e
  # REVIEW-019: this decides whether a self-test leg passed, so rc>=2 must
  # be could-not-evaluate, not an absent diagnostic.
  _extract "mn_diag self-test diagnostic" bash -c "printf '%s
' "$mn_out" | grep -F 'missing Pinned trust base component(s):' | grep -F "'Lean'""
  mn_diag=$_EXTRACT_OUT

  echo "self-test: MISSING-LOCKBACKED leg — real normal-mode checker against the copy missing the lock-backed 'Aiken' row:"
  local ml_out ml_rc ml_diag
  set +e; ml_out=$("$SELF" --repo-root "$miss_lock_root" 2>&1); ml_rc=$?; set -e
  # REVIEW-019: this decides whether a self-test leg passed, so rc>=2 must
  # be could-not-evaluate, not an absent diagnostic.
  _extract "ml_diag self-test diagnostic" bash -c "printf '%s
' "$ml_out" | grep -F 'missing Pinned trust base component(s):' | grep -F "'Aiken'""
  ml_diag=$_EXTRACT_OUT

  echo "self-test: DUPLICATE leg — real normal-mode checker against the copy with the known 'Z3' row duplicated:"
  local dup_out dup_rc dup_diag
  set +e; dup_out=$("$SELF" --repo-root "$dup_root" 2>&1); dup_rc=$?; set -e
  # REVIEW-019: this decides whether a self-test leg passed, so rc>=2 must
  # be could-not-evaluate, not an absent diagnostic.
  _extract "dup_diag self-test diagnostic" bash -c "printf '%s
' "$dup_out" | grep -F 'duplicate' | grep -F "'Z3'""
  dup_diag=$_EXTRACT_OUT

  local failures=0
  if [ "$red_rc" -ne 0 ] && [ -n "$red_diag" ]; then
    echo "RED leg: exit code $red_rc (required non-zero) — corrupted Lean-Blaster narHash detected"
    echo "RED leg: checker diagnostic:"
    printf '%s\n' "$red_diag" | sed 's/^/    /'
  else
    failures=$((failures + 1))
    echo "RED leg: FAIL — exit code $red_rc (required non-zero), Lean-Blaster narHash diagnostic: ${red_diag:-<none>}" >&2
    printf '%s\n' "$red_out" | sed 's/^/    [child] /' >&2
  fi
  if [ "$green_rc" -eq 0 ]; then
    echo "GREEN leg: exit code $green_rc (required 0) — uncorrupted control passes"
  else
    failures=$((failures + 1))
    echo "GREEN leg: FAIL — exit code $green_rc (required 0)" >&2
    printf '%s\n' "$green_out" | sed 's/^/    [child] /' >&2
  fi
  if [ "$mn_rc" -ne 0 ] && [ -n "$mn_diag" ]; then
    echo "MISSING-NONLOCK leg: exit code $mn_rc (required non-zero) — missing component 'Lean' named"
    printf '%s\n' "$mn_diag" | sed 's/^/    /'
  else
    failures=$((failures + 1))
    echo "MISSING-NONLOCK leg: FAIL — exit code $mn_rc (required non-zero), missing-'Lean' diagnostic: ${mn_diag:-<none>}" >&2
    printf '%s\n' "$mn_out" | sed 's/^/    [child] /' >&2
  fi
  if [ "$ml_rc" -ne 0 ] && [ -n "$ml_diag" ]; then
    echo "MISSING-LOCKBACKED leg: exit code $ml_rc (required non-zero) — missing component 'Aiken' named"
    printf '%s\n' "$ml_diag" | sed 's/^/    /'
  else
    failures=$((failures + 1))
    echo "MISSING-LOCKBACKED leg: FAIL — exit code $ml_rc (required non-zero), missing-'Aiken' diagnostic: ${ml_diag:-<none>}" >&2
    printf '%s\n' "$ml_out" | sed 's/^/    [child] /' >&2
  fi
  if [ "$dup_rc" -ne 0 ] && [ -n "$dup_diag" ]; then
    echo "DUPLICATE leg: exit code $dup_rc (required non-zero) — duplicate component 'Z3' named"
    printf '%s\n' "$dup_diag" | sed 's/^/    /'
  else
    failures=$((failures + 1))
    echo "DUPLICATE leg: FAIL — exit code $dup_rc (required non-zero), duplicate-'Z3' diagnostic: ${dup_diag:-<none>}" >&2
    printf '%s\n' "$dup_out" | sed 's/^/    [child] /' >&2
  fi

  echo "self-test: seeded coverage legs (seed attribution recorded per leg)"
  run_seed_leg seed_h "SEED-H leg (owner) — one narHash dropped from a lock-backed row" \
    "does not document narHash" _seed_h
  run_seed_leg seed_k "SEED-K leg (NAVIGATOR) — root input rebound to the wrong project node" \
    "must come from" _seed_k
  run_seed_leg seed_rc2 "RC2 leg (owner) — jq emits correct output then exits 2" \
    "COULD-NOT-EVALUATE" _seed_rc2 badbin
  failures=$((failures + SEED_LEG_FAILURES))

  if [ "$failures" -eq 0 ]; then

    # REVIEW-018: the stated contract is ONE key=value per line. This line
    # carried six keys, so the contract and the bytes disagreed. The bytes now
    # match the contract — a consumer parsing per line gets every key.
    echo "CBIC_RESULT selftest=pass"
    echo "CBIC_RESULT red_rc=$red_rc"
    echo "CBIC_RESULT green_rc=$green_rc"
    echo "CBIC_RESULT missing_nonlock_rc=$mn_rc"
    echo "CBIC_RESULT missing_lockbacked_rc=$ml_rc"
    echo "CBIC_RESULT duplicate_rc=$dup_rc"
    echo "self-test: PASS — RED $red_rc, GREEN $green_rc, MISSING-NONLOCK $mn_rc, MISSING-LOCKBACKED $ml_rc, DUPLICATE $dup_rc"
  else
    # REVIEW-019: this path emitted only selftest=fail and failures, omitting
    # five rc keys the run HAD reached — contradicting the contract's own rule
    # that an absent key means the run did not reach it. Every key the run
    # computed is now reported, on failure exactly as on success.
    echo "CBIC_RESULT selftest=fail"
    echo "CBIC_RESULT red_rc=$red_rc"
    echo "CBIC_RESULT green_rc=$green_rc"
    echo "CBIC_RESULT missing_nonlock_rc=$mn_rc"
    echo "CBIC_RESULT missing_lockbacked_rc=$ml_rc"
    echo "CBIC_RESULT duplicate_rc=$dup_rc"
    echo "CBIC_RESULT failures=$failures"
    echo "self-test: FAIL — $failures leg(s) misbehaved (RED $red_rc, GREEN $green_rc, MISSING-NONLOCK $mn_rc, MISSING-LOCKBACKED $ml_rc, DUPLICATE $dup_rc)" >&2
    exit 1
  fi
}

if [ -n "$IDENTITY_MANIFEST" ] && [ -n "$RETAINED_RECEIPT" ]; then
  fail "identity-manifest and retained-receipt modes are mutually exclusive"
elif [ -n "$IDENTITY_MANIFEST" ]; then
  [ "$SELF_TEST" -eq 0 ] || fail "identity-manifest mode cannot be combined with --self-test"
  identity_manifest_mode
elif [ -n "$RETAINED_RECEIPT" ]; then
  [ "$SELF_TEST" -eq 0 ] || fail "retained-receipt mode cannot be combined with --self-test"
  retained_receipt_mode
elif [ "$SELF_TEST" -eq 1 ]; then
  self_test_mode
else
  normal_mode
fi
