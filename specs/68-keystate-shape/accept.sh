#!/bin/sh
# accept.sh — staged acceptance contract for cardano-keri #68
# (design(identity): freeze the sovereign per-AID `CheckpointDatumV1` wire contract).
#
# ONE fail-safe harness driving the whole #68 deliverable from a single frozen
# planning record (`spec.md`) to byte-identical Aiken/Haskell golden parity. It has
# exactly two kinds of target:
#
#   * `spec`  — a Layer-1 STRUCTURAL self-check of `spec.md`: the frozen wire
#               contract must stay well-formed (all 8 `CheckpointDatumV1` fields in
#               order, the `Threshold` sum, the F18 rule table, the pinned locator
#               derivation, both message domains, the revealed-successor
#               authorization, the Freshness statement, and the #81 boundary). This
#               is GREEN at planning HEAD (spec.md is committed) and is enforced
#               STRICTLY by `gate.sh`.
#
#   * `threshold` `datum` `messages` `vectors` `aiken` `parity` `docs` — the STAGED
#               deliverable targets. Each asserts that its executable artifact (the
#               Haskell codec, the Aiken mirror, the committed fixtures, or the
#               reconciled downstream doc) is present and load-bearing. They are
#               LEGITIMATELY RED until their pair slice lands (`plan.md` slices
#               2..8); each turns GREEN when its artifact exists. They never crash on
#               an absent artifact — absence is a clean one-line RED.
#
#   * `final` (default) — `spec` then every staged target. GREEN only when the whole
#               contract is built; RED (safely) while any slice is still pending.
#
# DESIGN RULES:
#   - FAIL-SAFE: every staged gate first tests artifact existence; a missing file is
#     RED, never a crash and never a false pass.
#   - NO EXTERNAL TOOLS: the harness depends only on `grep`, `test`, and `sh`. The
#     heavy executable proof (hspec, `aiken check`, the fixtures drift check) runs in
#     `just ci` via `gate.sh`; here we assert the artifacts those suites live in
#     exist and carry their load-bearing symbols.
#   - REAL TEETH: `spec` greps the actual frozen tokens (field order, table rows,
#     domain strings, the `MAX_WEIGHT_DENOM` value) — never a trivial `true`.
#
# Exit 0 = the requested target's gates hold (GREEN). Exit 1 = one or more failed
# (RED). Exit 2 = unknown target.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)

SPEC="$SCRIPT_DIR/spec.md"

# --- Staged deliverable artifacts (created by plan.md slices 2..8) ---------
# Slice 2 — Haskell threshold codec.
HS_THRESHOLD="$REPO/offchain/lib/Cardano/KERI/AID/Checkpoint/Threshold.hs"
# Slice 3 — Haskell datum + message codec (deriveAidAssetName lives with messages).
HS_DATUM="$REPO/offchain/lib/Cardano/KERI/AID/Checkpoint/Datum.hs"
HS_MESSAGE="$REPO/offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs"
# Slice 4 — shared golden/negative vector generator + committed fixtures.
GEN_VECTORS="$REPO/offchain/app/GenCheckpointVectors.hs"
# Slice 5 — Aiken threshold codec.
AK_THRESHOLD="$REPO/onchain/lib/cardano_keri/checkpoint/threshold.ak"
AK_THRESHOLD_TESTS="$REPO/onchain/lib/cardano_keri/checkpoint/threshold_tests.ak"
# Slice 6 — Aiken datum + message codec (byte-identity parity).
AK_DATUM="$REPO/onchain/lib/cardano_keri/checkpoint/datum.ak"
AK_MESSAGE="$REPO/onchain/lib/cardano_keri/checkpoint/message.ak"
# Slice 7 — #24 recut onto the frozen contract.
SPEC24="$REPO/specs/24-keystate/spec.md"

MODE="${1:-final}"
fail=0

# --- helpers ---------------------------------------------------------------

# present LABEL PATTERN — assert PATTERN present in spec.md (case-insensitive ERE).
present() {
  if ! grep -iEq -- "$2" "$SPEC"; then
    printf 'FAIL[spec]: %s\n' "$1"; fail=1
  fi
}

# present_fixed LABEL STRING — assert literal STRING present in spec.md.
present_fixed() {
  if ! grep -Fq -- "$2" "$SPEC"; then
    printf 'FAIL[spec]: %s\n' "$1"; fail=1
  fi
}

# pending TARGET REASON — one-line fail-safe RED for a staged target.
pending() { printf 'RED: %s pending — %s\n' "$1" "$2"; fail=1; }

# need_file TARGET FILE DESC — RED (never crash) if FILE is absent.
need_file() {
  [ -f "$2" ] && return 0
  pending "$1" "$3 not yet created (missing: ${2#$REPO/})"
  return 1
}

# need_symbol TARGET FILE PATTERN DESC — RED if FILE lacks the load-bearing symbol.
need_symbol() {
  [ -f "$2" ] || return 0
  grep -iEq -- "$3" "$2" && return 0
  pending "$1" "$4 (missing symbol in ${2#$REPO/})"
}

# docs24 LABEL PATTERN — assert PATTERN present in specs/24 (case-insensitive ERE).
# Each `docs24` line is an independently load-bearing anchor of `check_docs`.
docs24() {
  if ! grep -iEq -- "$2" "$SPEC24"; then
    printf 'FAIL[docs]: %s\n' "$1"; fail=1
  fi
}

# ============================================================================
# `spec` — Layer-1 STRUCTURAL self-check of the frozen wire contract.
# ============================================================================
check_spec() {
  # --- The 8 CheckpointDatumV1 fields, in the frozen positional order --------
  # Each `<index>  <field>` line pins both presence AND position (Constr 0 order).
  present "spec: fields declared in EXACTLY this order" 'fields in EXACTLY this order'
  present "spec: field 0 cesr_aid"      '^[[:space:]]*0[[:space:]]+cesr_aid'
  present "spec: field 1 cur_keys"      '^[[:space:]]*1[[:space:]]+cur_keys'
  present "spec: field 2 cur_threshold" '^[[:space:]]*2[[:space:]]+cur_threshold'
  present "spec: field 3 next_digest"   '^[[:space:]]*3[[:space:]]+next_digest'
  present "spec: field 4 witnesses"     '^[[:space:]]*4[[:space:]]+witnesses'
  present "spec: field 5 toad"          '^[[:space:]]*5[[:space:]]+toad'
  present "spec: field 6 seq"           '^[[:space:]]*6[[:space:]]+seq'
  present "spec: field 7 native_sn"     '^[[:space:]]*7[[:space:]]+native_sn'

  # --- Threshold sum with both constructors ---------------------------------
  # Anchored to the declaration block: the sum header at line-start (not the
  # unrelated `cur_threshold = Unweighted(1)` prose) and each constructor on its
  # own `| Ctor (...)` line (not the F18 `Unweighted(m)` table rows).
  present "spec: Threshold sum header"             '^Threshold[[:space:]]*='
  present "spec: Threshold constructor Unweighted" '^[[:space:]]*\|[[:space:]]*Unweighted[[:space:]]*\(m'
  present "spec: Threshold constructor Weighted"   '^[[:space:]]*\|[[:space:]]*Weighted[[:space:]]*\(clauses'

  # --- F18 rule table rows 1..14 + the ratified MAX_WEIGHT_DENOM value -------
  for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    present "spec: F18 rule table row $n" "^\|[[:space:]]*$n[[:space:]]*\|"
  done
  present "spec: F18 references MAX_WEIGHT_DENOM"       'MAX_WEIGHT_DENOM'
  present_fixed "spec: ratified MAX_WEIGHT_DENOM value" '4294967296'

  # --- Both message domains, verbatim ---------------------------------------
  present_fixed "spec: inception domain string" 'cardano-keri/checkpoint/icp/v1'
  present_fixed "spec: advance domain string"   'cardano-keri/checkpoint/adv/v1'

  # --- Deployment / token-binding context fields ----------------------------
  present "spec: network_id context field"           'network_id'
  present "spec: checkpoint_policy_id context field" 'checkpoint_policy_id'
  present "spec: aid_asset_name context field"       'aid_asset_name'
  present "spec: spent_txid context field"           'spent_txid'

  # --- Pinned locator derivation (native blake2b_256, not BLAKE3) -----------
  present "spec: CHECKPOINT_ASSET_DOMAIN_TAG pinned"             'CHECKPOINT_ASSET_DOMAIN_TAG'
  present "spec: deriveAidAssetName is the executable derivation" 'deriveAidAssetName'
  present "spec: derivation code 0x46 (F-only V1)"               '0x46'
  present_fixed "spec: asset domain tag string"                  'cardano-keri/checkpoint-asset/v1'

  # --- The seven F10 advance equalities, each anchored on its OWN binding -----
  # Load-bearing: each grep matches the distinctive equality expression, so
  # deleting that numbered binding fails its check (not a shared context-field name).
  present "spec: F10 eq1 — network_id/checkpoint_policy_id bound to deployment" \
      'network_id.{0,3}equals the deployment network id'
  present "spec: F10 eq2 — aid_asset_name == deriveAidAssetName(cesr_aid)" \
      'aid_asset_name == deriveAidAssetName\(cesr_aid\)'
  present "spec: F10 eq3 — (spent_txid, spent_index) == the spent TxOutRef" \
      '\(spent_txid,[[:space:]]*spent_index\).{0,3}equals the .?TxOutRef'
  present "spec: F10 eq4 — prior_commit == spent.next_digest" \
      'prior_commit == spent\.next_digest'
  present "spec: F10 eq5 — seq_to == spent.seq + 1" \
      'seq_to == spent\.seq \+ 1'
  present "spec: F10 eq6 — signatures satisfy the REVEALED successor set (authorization)" \
      'signatures satisfy the[^.]*revealed successor set'
  present "spec: F10 eq7 — created datum equals V1{ cesr_aid, new_cur_keys, ... }" \
      'created checkpoint datum equals .?V1\{[[:space:]]*cesr_aid'

  # --- Stolen-current-quorum rejection (parent #21 pre-rotation invariant) ---
  present "spec: full stolen/spent-current quorum signing an advance is rejected" \
      'full spent-current quorum signing|full stolen current quorum is rejected'

  # --- Freshness: the removal statement, all three tokens on one line --------
  # Tight: dropping identity_root OR root_window OR sliding window fails this check.
  present "spec: Freshness — No identity_root, no root_window, no sliding window" \
      'No[^.]*identity_root[^.]*root_window[^.]*sliding window'

  # --- #81 delegation boundary: no delegator/di field -----------------------
  present "spec: #81 — no delegator/di field" \
      'no[^.]*.delegator.[^.]*(#81|di field)|.delegator./.di. field \(#81\)|#81[^.]*no .?delegator'
}

# ============================================================================
# Staged deliverable targets — fail-safe RED until their slice lands.
# ============================================================================
# Each staged check is a CONJUNCTION: fail-safe artifact prechecks + load-bearing
# structural anchors (a bare/superficial placeholder lacks the concrete type/predicate/
# test/derivation wiring below), with `gate.sh`'s `just ci` supplying the executable
# half (hspec bytes, `aiken check`, the fixtures drift check). An empty file greens
# nothing.
check_threshold() {
  need_file threshold "$HS_THRESHOLD" "Haskell threshold codec (Cardano.KERI.AID.Checkpoint.Threshold)" || return
  need_symbol threshold "$HS_THRESHOLD" 'data Threshold' "threshold module lacks the Threshold type"
  need_symbol threshold "$HS_THRESHOLD" 'Weighted'       "threshold module lacks the Weighted constructor"
  need_symbol threshold "$HS_THRESHOLD" 'evaluate'       "threshold module lacks the F18 evaluate predicate"
}

check_datum() {
  need_file datum "$HS_DATUM" "Haskell datum codec (Cardano.KERI.AID.Checkpoint.Datum)" || return
  need_symbol datum "$HS_DATUM" 'CheckpointDatumV1' "datum module lacks CheckpointDatumV1"
  need_symbol datum "$HS_DATUM" 'fromData|FromData'  "datum module lacks the PlutusData codec wiring"
}

check_messages() {
  need_file messages "$HS_MESSAGE" "Haskell message codec (Cardano.KERI.AID.Checkpoint.Message)" || return
  need_symbol messages "$HS_MESSAGE" 'AdvanceMessage'    "message module lacks the AdvanceMessage preimage type"
  need_symbol messages "$HS_MESSAGE" 'InceptionMessage'  "message module lacks the InceptionMessage preimage type"
  need_symbol messages "$HS_MESSAGE" 'deriveAidAssetName' "message module lacks deriveAidAssetName"
}

check_vectors() {
  need_file vectors "$GEN_VECTORS" "shared golden/negative vector generator (GenCheckpointVectors.hs)" || return
  need_symbol vectors "$GEN_VECTORS" '^main '          "vector generator lacks an executable main"
  need_symbol vectors "$GEN_VECTORS" 'golden|negative' "vector generator emits no golden/negative families"
}

check_aiken() {
  need_file aiken "$AK_THRESHOLD" "Aiken threshold codec (onchain/lib/cardano_keri/checkpoint/threshold.ak)" || return
  need_file aiken "$AK_THRESHOLD_TESTS" "Aiken threshold byte-identity tests (threshold_tests.ak)" || return
  need_symbol aiken "$AK_THRESHOLD" 'Threshold'  "Aiken threshold module lacks the Threshold type"
  need_symbol aiken "$AK_THRESHOLD_TESTS" '^test | test ' "Aiken threshold tests file wires no test blocks"
}

check_parity() {
  need_file parity "$AK_DATUM" "Aiken datum codec (onchain/lib/cardano_keri/checkpoint/datum.ak)" || return
  need_file parity "$AK_MESSAGE" "Aiken message codec (onchain/lib/cardano_keri/checkpoint/message.ak)" || return
  need_symbol parity "$AK_DATUM" 'CheckpointDatumV1|Datum'      "Aiken datum module lacks the datum type"
  need_symbol parity "$AK_MESSAGE" 'deriveAidAssetName|Message' "Aiken message module lacks the message/derivation wiring"
}

# docs — `specs/24-keystate/spec.md` reconciled onto the frozen #68 contract.
#
# LOAD-BEARING over FOUR independent elements — removing or weakening ANY one of
# them makes `docs` RED (mutation-tested at slice time):
#
#   1. the strengthened supersession banner: the Candidate-B registry/trie/root
#      storage & discovery mechanics are HISTORICAL, NON-NORMATIVE, and superseded
#      WHOLESALE for current-authority storage and discovery;
#   2. the sovereign per-AID quantity-one checkpoint currentness + exact-asset
#      discovery story (the index/outref is a liveness hint; ledger revalidation is
#      authority — a stale answer is retry/failure, not forged authority);
#   3. a pointer to the frozen #68 `CheckpointDatumV1` / message contract
#      (`specs/68-keystate-shape/spec.md`);
#   4. the named downstream #24 mechanical-recut obligation.
#
# It is deliberately PURELY POSITIVE: it does NOT scan the retained, annotated
# Candidate-B body for `identity_root` / `root_window` / `trie_key` terms, so the
# historical validator body kept for the #24 recut never fails the gate. `just ci`
# (Docs-links) supplies the link-integrity half in `gate.sh`.
check_docs() {
  need_file docs "$SPEC24" "downstream #24 recut surface (specs/24-keystate/spec.md)" || return

  # -- Element 1 — Candidate-B storage/trie/root mechanics marked historical,
  #    non-normative, superseded WHOLESALE for current-authority storage+discovery.
  docs24 "el1 supersession: historical, non-normative, superseded wholesale" \
      'historical, non-normative, and supersed[a-z]* wholesale'
  docs24 "el1 supersession: superseded for current-authority storage and discovery" \
      'current-authority storage and discovery'
  docs24 "el1 supersession: the retained body is the rejected Candidate-B lineage" \
      'rejected Candidate-B lineage'

  # -- Element 2 — sovereign per-AID quantity-one checkpoint currentness + exact-asset
  #    discovery; index/outref = liveness hint, ledger revalidation = authority.
  docs24 "el2 currentness: sovereign per-AID quantity-one checkpoint" \
      'per-AID, quantity-one[^.]*checkpoint'
  docs24 "el2 currentness: currentness is the unspent checkpoint tip" \
      'unspent checkpoint tip'
  docs24 "el2 discovery: exact-asset lookup enforces the (policy_id, asset_name) shape" \
      'exact-asset[^.]*\(policy_id, asset_name\)'
  docs24 "el2 authority: the index/outref is a liveness hint ONLY (not authoritative)" \
      'liveness hint only'
  docs24 "el2 authority: the resolved checkpoint is re-validated against the ledger" \
      're-validated against the ledger'

  # -- Element 3 — pointer to the frozen #68 CheckpointDatumV1 / message contract.
  docs24 "el3 pointer: names the frozen #68 spec file specs/68-keystate-shape/spec.md" \
      'specs/68-keystate-shape/spec\.md'
  docs24 "el3 pointer: names the frozen CheckpointDatumV1 datum" \
      'CheckpointDatumV1'
  docs24 "el3 pointer: names the frozen InceptionMessage message type" \
      'InceptionMessage'
  docs24 "el3 pointer: names the frozen AdvanceMessage message type" \
      'AdvanceMessage'

  # -- Element 4 — the named downstream #24 mechanical-recut obligation.
  docs24 "el4 obligation: the mechanical recut is downstream #24" \
      'mechanical re-?cut is downstream #24'
}

# ============================================================================
# Fail-safe hard stop — the planning record must exist for every mode.
# ============================================================================
if [ ! -f "$SPEC" ]; then
  echo "FAIL: missing $SPEC (RED — no #68 wire-contract record; expected on origin/main)"
  exit 1
fi

# ============================================================================
# Dispatch.
# ============================================================================
case "$MODE" in
  spec)      check_spec ;;
  threshold) check_threshold ;;
  datum)     check_datum ;;
  messages)  check_messages ;;
  vectors)   check_vectors ;;
  aiken)     check_aiken ;;
  parity)    check_parity ;;
  docs)      check_docs ;;
  final)
    check_spec
    check_threshold
    check_datum
    check_messages
    check_vectors
    check_aiken
    check_parity
    check_docs
    ;;
  *)
    echo "accept.sh: unknown target '$MODE'"
    echo "usage: accept.sh [spec|threshold|datum|messages|vectors|aiken|parity|docs|final]"
    exit 2
    ;;
esac

# --- verdict ---------------------------------------------------------------
if [ "$fail" -ne 0 ]; then
  echo "accept.sh[$MODE]: FAIL (RED — #68 target '$MODE' not yet satisfied)"
  exit 1
fi
echo "accept.sh[$MODE]: OK (GREEN — #68 target '$MODE' satisfied)"
exit 0
