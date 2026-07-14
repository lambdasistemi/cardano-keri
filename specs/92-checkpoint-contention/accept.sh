#!/bin/sh
# accept.sh — final-acceptance contract for cardano-keri #92
# (design(onchain): R-KEL checkpoint advance-storage & contention model —
#  per-AID UTxO vs MPFS trie vs lane-shard).
#
# This is the *final* deliverable check, authored RED-first by the ticket owner
# as the acceptance CONTRACT and extended per measurement slice by the pair. It
# has two layers plus a STAGED invocation:
#
#   (1) STRUCTURAL checks over specs/92-checkpoint-contention/spec.md — the
#       planning record must be well-formed (logical/physical split, three named
#       candidates, falsifiable matrix, transient-cage lifecycle, provenance
#       vocabulary, #68/#24/#25/#44 consequences, R-KEL classification, the
#       NOTE-013/016/017/018/019/020 honesty boundaries — including the native
#       blake2b_256 locator derivation (NOT BLAKE3), the inductive mint-placement +
#       spend-continuation caging, and the inductive downstream trust boundary).
#       These PASS at planning HEAD.
#
#   (2) FINAL-DELIVERABLE gates — thresholds ratified before measurement (the
#       ratifying commit is COMPUTED from git history, never self-stamped —
#       NOTE-003 item 1), the machine-readable evidence FILLED (no
#       MEASURE/PROVE/VERIFY placeholder outcomes) over the fixed 10-column
#       schema with provenance, the structured live-boundary smoke recorded,
#       EXACTLY ONE candidate selected with EXACTLY TWO distinct rejected
#       alternatives + residual risks, and the canonical docs carrying the
#       decision. These are RED until the decision slice lands the artifacts.
#
# STAGED MODE (NOTE-003 item 4). Because the full `final` verdict is legitimately
# RED until Slice 9, this script also exposes `accept.sh <slice-target>` giving
# every in-flight slice a real RED-before / GREEN-after target:
#
#     spec          Layer-1 structural self-check only (GREEN at planning HEAD).
#     schema        (Slice 1) 10-column matrix.tsv schema shape + parsed
#                   evidence.json skeleton materialized (placeholders allowed).
#     thresholds    (Slice 2) thresholds.md ratified with concrete values/units.
#     registration  (Slice 3) C1a + C3b/C5/`C7 COMMON` registration-side rows
#                   non-placeholder (does NOT demand the A/B/C-scoped C7 rows —
#                   those land in Slice 7; NOTE-004 item 2).
#     candidate-A   (Slice 4) A's C1b/C3/C6/C9 rows non-placeholder.
#     candidate-B   (Slice 5) B's C1b/C3/C6/C9 rows non-placeholder.
#     candidate-C   (Slice 6) C's C1b/C3/C6/C9 rows non-placeholder.
#     contention    (Slice 7) C2/C4/C7/C8 non-placeholder (matrix complete).
#     smoke         (Slice 8) matrix filled + structured live-smoke + REPORT.
#     final         (default; Slice 9) the whole contract.
#
# The pair EXTENDS each staged target per slice with finer evidence-schema
# assertions (RED-first) and flips the gate.sh `final` hook strict at Slice 9.
#
# EXPECTED RESULT (this planning HEAD):
#   - `final` (no argument)          -> RED  (thresholds/evidence/decision absent).
#   - `spec`  (planning/static)      -> GREEN (spec.md well-formed).
#   - every other staged target      -> RED, safely (its slice's artifacts absent).
#   - RED on origin/main (no spec dir at all).
#
# DESIGN RULES (brief / recovery constraint 7):
#   - FAIL-SAFE: every gate first tests artifact existence; absence is RED, never
#     a crash and never a false pass.
#   - STRUCTURED-FILE-FIRST (NOTE-003 item 3): evidence.json is PARSED with `jq`
#     (fail CLOSED if jq is absent), matrix.tsv is validated by header +
#     column-count + vocabulary + duplicate row-key + coverage over the fixed
#     10-column schema, the selection is read from DECISION.md machine headers,
#     and git ordering uses REPO-RELATIVE pathspecs. Prose grep is used only for
#     the canonical-doc decision presence + R-KEL-classification preservation.
#   - VALUE/UNIT-VALIDATED (NOTE-003 item 8, NOTE-004 item 1): thresholds.md
#     carries a fixed 4-column TAB block (key/value/unit/provenance) with the 13
#     required keys; each value is validated against its grammar and each unit
#     against the key's allowed unit (placeholders rejected, K_PROVISIONAL ∈
#     K_SWEEP) — not the mere presence of tokens. Commit references must be FULL
#     40-hex (NOTE-004 item 4); the recorded thresholds_commit must EQUAL the
#     COMPUTED threshold-file commit and STRICTLY PREDATE the latest data-bearing
#     revision of EVERY measurement artifact (matrix/evidence.json/REPORT/
#     live-smoke + raw logs).
#   - NEGATIVE GUARDS: a named selection with unfilled cells / missing provenance
#     / threshold-ordering violation / absent smoke/report is RED ("selection
#     without evidence" forbidden); a FILLED matrix with NO selection is ALSO RED
#     (permanent non-selection fails #92's deliverable).
#
# Exit 0 = the requested target's gates hold (GREEN). Exit 1 = one or more failed
# (RED). Exit 2 = unknown staged target.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)

# Repo-relative pathspecs (for git-log ordering — NEVER an absolute path).
REL_DIR="specs/92-checkpoint-contention"
REL_THRESHOLDS="$REL_DIR/thresholds.md"
REL_EVID="$REL_DIR/evidence"
REL_MATRIX="$REL_EVID/matrix.tsv"
REL_EVJSON="$REL_EVID/evidence.json"
REL_REPORT="$REL_EVID/REPORT.md"
REL_LIVESMOKE="$REL_EVID/live-smoke.tsv"

SPEC="$SCRIPT_DIR/spec.md"
THRESHOLDS="$SCRIPT_DIR/thresholds.md"
EVID_DIR="$SCRIPT_DIR/evidence"
MATRIX="$EVID_DIR/matrix.tsv"
EVJSON="$EVID_DIR/evidence.json"
REPORT="$EVID_DIR/REPORT.md"
LIVESMOKE="$EVID_DIR/live-smoke.tsv"
DECISION="$SCRIPT_DIR/DECISION.md"
IM="$REPO/specs/68-keystate-shape/identity-model.md"
SA="$REPO/specs/68-keystate-shape/system-architecture.md"

MODE="${1:-final}"
fail=0
DECISION_SELECTED=""

# --- helpers ---------------------------------------------------------------

# present LABEL FILE PATTERN — assert PATTERN present in FILE (case-insensitive ERE).
present() {
  if [ ! -f "$2" ]; then
    printf 'FAIL[present]: %s (missing file: %s)\n' "$1" "$2"; fail=1; return
  fi
  if ! grep -iEq -- "$3" "$2"; then
    printf 'FAIL[present]: %s\n' "$1"; fail=1
  fi
}

# red LABEL — RED marker used when a required artifact/gate is missing/violated.
red() { printf 'FAIL[gate]: %s\n' "$1"; fail=1; }

# forbid_pred LABEL FILE MATCH_RE NEG_RE — flag lines matching MATCH_RE but NOT
#   NEG_RE (an adjacency-scoped negation exemption).
forbid_pred() {
  [ -f "$2" ] || return 0
  _hits=$(grep -iE -- "$3" "$2" 2>/dev/null | grep -ivE -- "$4" || true)
  if [ -n "$_hits" ]; then
    printf 'FAIL[forbid]: %s\n' "$1"; printf '  %s\n' "$_hits"; fail=1
  fi
}

# kv FILE KEY — echo the value of a `KEY=value` machine header (first match), trimmed.
kv() {
  [ -f "$1" ] || return 0
  grep -iE -- "^[#[:space:]]*$2[[:space:]]*=" "$1" 2>/dev/null \
    | head -n1 | sed -E "s/^[#[:space:]]*$2[[:space:]]*=[[:space:]]*//" \
    | tr -d '"' | tr -d "'" | awk '{$1=$1;print}'
}

# have_jq — the structured parser MUST be present; callers fail CLOSED otherwise.
have_jq() { command -v jq >/dev/null 2>&1; }

# is_hex40 SHA — a commit reference must be a FULL 40-char lowercase/upper hex SHA
#   (NOTE-004 item 4). Abbreviated / non-hex references are rejected.
is_hex40() {
  case "$1" in
    *[!0-9a-fA-F]*) return 1 ;;
  esac
  [ ${#1} -eq 40 ]
}

# ============================================================================
# LAYER 1 — STRUCTURAL checks over spec.md (PASS at planning HEAD)
# ============================================================================
layer1_spec() {
  # FR1 — logical/physical split + NOTE-014 (per-AID UTxO does not reopen unicity)
  present "spec: logical/physical distinction table"        "$SPEC" 'logical/physical|logical.*physical.*distinction'
  present "spec: NOTE-014 (logical unicity vs physical layout)" "$SPEC" 'NOTE-014'
  present "spec: fixed MPFS-with-oracle logical gate named"  "$SPEC" 'MPFS-with-oracle'

  # FR3 — three named candidates + validator-shape sketches
  present "spec: Candidate A — per-cesr_aid checkpoint UTxO" "$SPEC" 'Candidate A|per-.?cesr_aid.? checkpoint UTxO'
  present "spec: Candidate B — singleton MPFS"               "$SPEC" 'Candidate B|singleton MPFS'
  present "spec: Candidate C — lane-shard hybrid"            "$SPEC" 'Candidate C|lane-shard'

  # FR4 — falsifiable matrix: every material criterion present (incl. C9 discovery)
  for c in C1a C1b C2 C3 C3b C4 C5 C6 C7 C8 C9; do
    present "spec: matrix criterion $c present" "$SPEC" "(^|[^0-9a-z])$c([^0-9a-z]|\$)"
  done
  present "spec: matrix criteria carry a falsifier"          "$SPEC" 'falsifier'
  present "spec: NOTE-016 thresholds ratified before measurement" "$SPEC" 'NOTE-016'

  # FR5/FR16 — Candidate A minted AID-bound steady checkpoint asset + generic
  #   discovery (C9) + ACDC user story + datum/address distinction (NOTE-019).
  present "spec: NOTE-019 (minted AID-bound steady asset; generic discovery)" "$SPEC" 'NOTE-019'
  present "spec: steady checkpoint locator/state token for a registered AID" "$SPEC" \
      'steady checkpoint locator/state token|steady checkpoint locator|locator/state token for'
  present "spec: full asset id (checkpoint_policy_id, aid_asset_name)" "$SPEC" \
      '\(checkpoint_policy_id, ?aid_asset_name\)'
  present "spec: aid_asset_name domain-separated 32-byte derivation of qualified AID" "$SPEC" \
      'aid_asset_name.*(domain-separated|blake2b).*(32-byte|qualified)|(domain-separated|32-byte).*aid_asset_name'
  # The locator name must derive via the NATIVE blake2b_256 Plutus builtin — BLAKE3 is
  #   the expensive #97/#98 genesis binding, unnecessary for a cheap locator label.
  present "spec: aid_asset_name uses native blake2b_256 builtin (not BLAKE3)" "$SPEC" \
      'blake2b_256\(CHECKPOINT_ASSET_DOMAIN_TAG|aid_asset_name[^A-Za-z0-9]*:?=[^A-Za-z0-9]*blake2b_256|native .?blake2b_256'
  # NEGATIVE guard — reject a BLAKE3 *locator* derivation (blake3 over the asset
  #   domain tag / aid_asset_name), WITHOUT rejecting the legitimate #97/#98
  #   `blake3(icp) == cesr_aid` GENESIS binding or the spikes/97-blake3-multitx path.
  #   MATCH scopes blake3 to the asset locator (asset-name / domain tag / locator);
  #   the exemption tokens keep contrasting/"not BLAKE3"/genesis/icp prose legal.
  forbid_pred "spec: asset-name locator must NOT derive via BLAKE3 (use native blake2b_256; #97 blake3(icp) genesis binding stays legal)" \
      "$SPEC" \
      'blake3[^.]{0,40}(aid_asset_name|CHECKPOINT_ASSET_DOMAIN_TAG|asset[ -]?name|locator[ -]?(label|token))|(aid_asset_name|CHECKPOINT_ASSET_DOMAIN_TAG)[^.]{0,40}blake3' \
      'not[[:space:]]+blake3|not[[:space:]]+BLAKE3|blake2b|native|genesis|icp|instead|rather|unnecessary|expensive|#97|#98|withdrawn|reject'
  present "spec: derivation preserves CESR derivation-code/domain distinction" "$SPEC" \
      'derivation-code/domain distinction|derivation code.*distinct'
  present "spec: no second identity encoding (reconciled with #91 canonical AID)" "$SPEC" \
      'no second identity encoding|invents no second identity|not a competing AID|no.*second identity'
  present "spec: #99 combined script — policy id == checkpoint validator script hash (names/binds)" "$SPEC" \
      'targetScriptHash == policyId|script hash is.*BOTH.*policy id|policy id .*= .*script hash|checkpoint_policy_id. = the.*script hash'
  # The equality NAMES/BINDS the combined script; it does NOT alone confine the asset.
  #   The token is caged INDUCTIVELY by mint-placement + spend-continuation (+ the
  #   migration/close exits) — assert both the caveat and the inductive rules.
  present "spec: equality names/binds the combined script (not equality-alone confinement)" "$SPEC" \
      'names and binds the combined script|names/binds.*combined script|caged inductively|does not.{0,40}(non-transferable|force it to)'
  present "spec: token caged inductively by mint-placement + spend-continuation" "$SPEC" \
      'mint-placement \+ spend-continuation|induction over its own mint/spend|mint-placement.{0,40}spend-continuation'
  present "spec: CheckpointStateOutput shape (address/value/datum)" "$SPEC" 'CheckpointStateOutput'
  present "spec: datum does not own an address (TxOut locked at script-hash address)" "$SPEC" \
      'itself own an address|datum does not.{0,60}own an address'
  present "spec: current key state lives in inline CheckpointDatum" "$SPEC" 'CheckpointDatum'
  present "spec: mint exactly one token, +1, only after Finish + oracle + MPFS unicity" "$SPEC" \
      'exactly once, quantity .\+1|minted .exactly once|exactly one.*token.*rejects.*extra'
  present "spec: normal rotation is a delta = 0 transition" "$SPEC" \
      'delta = 0|delta=0|no mint or burn for the steady asset'
  present "spec: rotation new.seq = old.seq + 1 with AID/asset-name invariant" "$SPEC" \
      'new\.seq = old\.seq \+ 1'
  present "spec: generic multi-asset (policy_id, asset_name) discovery lookup" "$SPEC" \
      'generic multi-asset .\(policy_id, ?asset_name\)|\(policy_id, ?asset_name\) . current unspent output'
  present "spec: C9 falsifier rejects exclusive/authoritative issuer/QVI database" "$SPEC" \
      'exclusive/authoritative issuer/QVI database|exclusive.*QVI.*database|authoritative.*QVI.*database'
  present "spec: ACDC holder user story (Alice derives asset ids, generic indexer)" "$SPEC" \
      'ACDC holder user story|ACDC-facing user story|Alice.*derives the asset id'
  # Inductive downstream trust boundary (NOTE-020): CIP-31 ref read runs no spend
  #   validator; the consumer replays no KERI history / genesis-BLAKE3 / MPF proof
  #   (inherited inductively); app signature under authenticated keys stays app work.
  present "spec: downstream reads via CIP-31 reference input (read, not spent) — no spend validator runs" "$SPEC" \
      'read, not spent|does not execute the checkpoint spending validator'
  present "spec: transition facts inherited inductively (no KERI replay / genesis-BLAKE3 recompute / MPF proof)" "$SPEC" \
      'inherited inductively|does not replay KERI'
  present "spec: only a bounded provenance/state boundary check downstream" "$SPEC" \
      'bounded provenance/state boundary check|bounded boundary check'
  present "spec: app payload signature stays application work; checkpoint cannot pre-prove a future payload" "$SPEC" \
      'cannot pre-prove a future payload|remain application work|stays .{0,20}application. work'
  # NEGATIVE guard — the bespoke/authoritative QVI-owned AID->UTxO database framing
  #   must be WITHDRAWN, not asserted as a live requirement of Candidate A. Any line
  #   that AFFIRMATIVELY says A's discovery REQUIRES/NEEDS/DEPENDS-ON such a database
  #   is RED unless the same line marks it as a withdrawal, a falsifier, or a
  #   rejected pattern (framing|withdrawn|falsifier|reject|eliminat|lacks|generic|
  #   no longer|rather than|instead|neither|not …). The legitimate mentions — the C9
  #   falsifier row, the NOTE-019 withdrawal, and the success-criteria rejection —
  #   all carry one of those exemption tokens; a bald affirmative regression does not.
  forbid_pred "spec: Candidate A must NOT require a bespoke/authoritative QVI-owned AID->UTxO database (withdrawn — must be a falsifier/withdrawal only)" \
      "$SPEC" \
      '(requires?|needs?|depends on|must use)[^.]*(bespoke|exclusive|authoritative|QVI-owned|QVI-specific)[^.]*(database|directory|AID . ?(current-?)?UTxO index)' \
      '(framing|withdrawn|withdraw|falsifier|falsif|reject|eliminat|lacks|no longer|rather than|instead of|generic|neither|is not|does not|no bespoke|not[[:space:]])'

  # FR6/FR7 — transient inception-cage lifecycle (mint/Step/Finish/timeout)
  present "spec: transient token minted tied to the consumed attempt input" "$SPEC" \
      'tied to the consumed attempt input'
  present "spec: Step preserves exactly one transient token" "$SPEC" 'preserves exactly one'
  present "spec: Finish burns-or-promotes the token exactly once" "$SPEC" \
      'burns?-or-promotes|burns/promotes|consumes[ -]and[ -]burns'
  present "spec: bounded deposit-funded timeout/reclaim path" "$SPEC" \
      'deposit-funded|bounded timeout|reclaim/burn'
  present "spec: C3b transient-cage bloat/abandoned-attempt criterion" "$SPEC" 'C3b'

  # FR11 — downstream consequences documented (not absorbed)
  for d in '#68' '#24' '#25' '#44'; do
    present "spec: downstream consequence $d documented" "$SPEC" "$d"
  done

  # FR12 — NOTE-013 (#99 Modify N is NOT a genesis/checkpoint-advance batch bound)
  present "spec: NOTE-013 (#99 Modify N not a checkpoint-advance batch bound)" "$SPEC" 'NOTE-013'
  present "spec: NOTE-018 (transient token vs steady token; Step/Finish != rotation)" "$SPEC" 'NOTE-018'
  present "spec: NOTE-017 (lane grindable; average != adversarial)" "$SPEC" 'NOTE-017'
  present "spec: NOTE-020 (native BLAKE2b locator; inductive caging; inductive downstream trust)" "$SPEC" 'NOTE-020'

  # FR13 — live-boundary-smoke limitation stated
  present "spec: live-smoke devnet limitation (maxTxExUnits / evalTxExUnits)" "$SPEC" \
      'maxTxExUnits|evalTxExUnits'

  # FR14 — evidence provenance vocabulary + boundary discipline
  present "spec: evidence measured cells"    "$SPEC" 'measured'
  present "spec: evidence derived cells"     "$SPEC" 'derived'
  present "spec: evidence estimated cells"   "$SPEC" 'estimated'
  present "spec: evidence declared cells"    "$SPEC" 'declared'
  present "spec: evidence unsupported cells" "$SPEC" 'unsupported'
  present "spec: registration-pipeline vs rotation-advance measured at own boundaries" \
      "$SPEC" 'registration pipeline'
  present "spec: rotation advance measured separately"       "$SPEC" 'rotation advance'
  present "spec: disjoint transactions never summed"         "$SPEC" 'never sum|never summ|not[^.]*sum'

  # FR15 — R-KEL classification preserved in the planning record
  present "spec: R-KEL preserved as on-chain checkpoint over settled R-ID" "$SPEC" \
      'checkpoint over settled R-ID'
}

# ============================================================================
# EVIDENCE SCHEMA — fixed 10-column matrix.tsv (NOTE-003 item 2/3)
#   criterion candidate scenario transaction metric value unit class outcome provenance
# ============================================================================
check_matrix_schema() {
  if [ ! -f "$MATRIX" ]; then
    red "evidence/matrix.tsv absent — 10-column evidence schema not materialized (Slice 1)"
    return
  fi
  _errs=$(awk -F '\t' '
    function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }
    BEGIN{
      split("C1a C1b C2 C3 C3b C4 C5 C6 C7 C8 C9", T, " "); for(i in T) CRIT[T[i]]=1
      split("A B C COMMON", T, " "); for(i in T) CAND[T[i]]=1
      split("single average adversarial targeted-victim peak abandoned batch population", T, " "); for(i in T) SCEN[T[i]]=1
      split("Step Finish Activation Rotation Read n/a", T, " "); for(i in T) TXN[T[i]]=1
      split("mem_units cpu_units bytes ada advances/block blocks count bool n/a", T, " "); for(i in T) UNIT[T[i]]=1
      split("measured derived estimated declared unsupported", T, " "); for(i in T) CLASS[T[i]]=1
      split("PASS FAIL MEASURE PROVE VERIFY", T, " "); for(i in T) OUT[T[i]]=1
    }
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    {
      if (!h) {
        h=1
        want="criterion candidate scenario transaction metric value unit class outcome provenance"
        got=trim($1); for(i=2;i<=NF;i++) got=got" "trim($i)
        if (NF!=10 || got!=want) print "bad header (need 10-col \""want"\"): got [\""got"\"]"
        next
      }
      if (NF!=10) { print "row "NR": expected 10 tab-separated columns, got "NF; next }
      cr=trim($1); ca=trim($2); sc=trim($3); tx=trim($4); me=trim($5)
      va=trim($6); un=trim($7); cl=trim($8); ou=trim($9); pr=trim($10)
      if (cr==""||ca==""||sc==""||tx==""||me==""||va==""||un==""||cl==""||ou==""||pr=="")
        print "row "NR": empty field(s) — all 10 columns must be non-empty"
      if (!(cr in CRIT))  print "row "NR": criterion not in vocabulary ["cr"]"
      if (!(ca in CAND))  print "row "NR": candidate not in {A,B,C,COMMON} ["ca"]"
      if (!(sc in SCEN))  print "row "NR": scenario not in vocabulary ["sc"]"
      if (!(tx in TXN))   print "row "NR": transaction not in vocabulary ["tx"]"
      if (!(un in UNIT))  print "row "NR": unit not in vocabulary ["un"]"
      if (!(cl in CLASS)) print "row "NR": class not in {measured,derived,estimated,declared,unsupported} ["cl"]"
      if (!(ou in OUT))   print "row "NR": outcome not in {PASS,FAIL,MEASURE,PROVE,VERIFY} ["ou"]"
      k=cr"|"ca"|"sc"|"tx"|"me
      if (k in SEEN) print "row "NR": duplicate row-key ["k"]"
      SEEN[k]=1
    }
    END { if (!h) print "matrix.tsv has no header row" }
  ' "$MATRIX" 2>/dev/null)
  if [ -n "$_errs" ]; then
    printf 'FAIL[schema]: matrix.tsv 10-column schema violations:\n'
    printf '  %s\n' "$_errs"
    fail=1
  fi
}

# evidence.json must PARSE with jq (fail CLOSED without it) and hold the skeleton keys.
check_evidence_json_skeleton() {
  if [ ! -f "$EVJSON" ]; then
    red "evidence/evidence.json absent — evidence skeleton not materialized (Slice 1)"
    return
  fi
  if ! have_jq; then
    red "jq unavailable — cannot PARSE evidence.json (fail closed — NOTE-003 item 3)"
    return
  fi
  if ! jq -e . "$EVJSON" >/dev/null 2>&1; then
    red "evidence.json is not valid JSON (jq parse failed)"
    return
  fi
  for k in tool_versions commands protocol_parameters thresholds_commit selection; do
    jq -e "has(\"$k\")" "$EVJSON" >/dev/null 2>&1 \
      || red "evidence.json missing top-level key '$k'"
  done
}

# thresholds.md ratified with concrete VALUE + UNIT + PROVENANCE per required key —
# and NO self-referential commit stamp (NOTE-003 item 1, NOTE-004 item 1).
#
# The ratified block is a fixed 4-column, TAB-separated table delimited by the
# literal markers `<!-- THRESHOLDS:BEGIN -->` / `<!-- THRESHOLDS:END -->`, header
# row `key<TAB>value<TAB>unit<TAB>provenance`, exactly ONE row per required key.
# check_thresholds_values PARSES and VALIDATES each key's value against its grammar
# and its unit against the key's allowed unit, rejects placeholders, requires
# non-empty provenance, enforces K_SWEEP powers-of-two with K_PROVISIONAL ∈ K_SWEEP
# and C6_PROOF_REDEEMER_CAP < C6_WHOLE_TX_CAP headroom (C3B_ABANDONED_ADA_CAP=0 is a
# valid strict cap) — not the mere presence of tokens like C2/C3 and one digit
# somewhere (NOTE-003 item 8).
check_thresholds_values() {
  if [ ! -f "$THRESHOLDS" ]; then
    red "thresholds.md absent — thresholds not ratified before measurement (Slice 2, NOTE-016)"
    return
  fi
  if grep -iEq -- '^[#[:space:]]*RATIFIED_COMMIT[[:space:]]*=' "$THRESHOLDS"; then
    red "thresholds.md carries a self-referential RATIFIED_COMMIT= stamp — forbidden (NOTE-003 item 1); the ratifying SHA is COMPUTED from git history"
  fi
  _errs=$(awk -F '\t' '
    function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }
    function ispint(v){ return (v ~ /^[0-9]+$/ && v+0 > 0) }
    function ispnum(v){ return (v ~ /^[0-9]+(\.[0-9]+)?$/ && v+0 > 0) }
    function isnnum(v){ return (v ~ /^[0-9]+(\.[0-9]+)?$/ && v+0 >= 0) }
    function ispow2(n){ n=n+0; if(n<1) return 0; while(n%2==0) n=n/2; return (n==1) }
    function isph(v){ return (v=="MEASURE"||v=="TBD"||v=="TODO"||v=="???"||v=="n/a"||v=="N/A"||v=="NA") }
    BEGIN{
      NKEY=split("C2_ADVANCE_SLO C3_CAPITAL_LOCK_CAP C3B_BLOAT_CAP C3B_ABANDONED_ADA_CAP C4_EMERGENCY_LATENCY_SLO C6_PROOF_REDEEMER_CAP C6_WHOLE_TX_CAP C6_READ_EXMEM_CAP C6_READ_EXCPU_CAP C8_DOWNSTREAM_CAP TIMEOUT K_SWEEP K_PROVISIONAL", K, " ")
      for(i=1;i<=NKEY;i++) REQ[K[i]]=1
      TYPE["C2_ADVANCE_SLO"]="pnum";           UNIT["C2_ADVANCE_SLO"]="advances/block"
      TYPE["C3_CAPITAL_LOCK_CAP"]="pint";       UNIT["C3_CAPITAL_LOCK_CAP"]="ada"
      TYPE["C3B_BLOAT_CAP"]="pint";             UNIT["C3B_BLOAT_CAP"]="count"
      TYPE["C3B_ABANDONED_ADA_CAP"]="nnum";     UNIT["C3B_ABANDONED_ADA_CAP"]="ada"
      TYPE["C4_EMERGENCY_LATENCY_SLO"]="pnum";  UNIT["C4_EMERGENCY_LATENCY_SLO"]="blocks"
      TYPE["C6_PROOF_REDEEMER_CAP"]="pint";     UNIT["C6_PROOF_REDEEMER_CAP"]="bytes"
      TYPE["C6_WHOLE_TX_CAP"]="pint";           UNIT["C6_WHOLE_TX_CAP"]="bytes"
      TYPE["C6_READ_EXMEM_CAP"]="pint";         UNIT["C6_READ_EXMEM_CAP"]="mem_units"
      TYPE["C6_READ_EXCPU_CAP"]="pint";         UNIT["C6_READ_EXCPU_CAP"]="cpu_units"
      TYPE["C8_DOWNSTREAM_CAP"]="pint";         UNIT["C8_DOWNSTREAM_CAP"]="count"
      TYPE["TIMEOUT"]="pint";                   UNIT["TIMEOUT"]="blocks"
      TYPE["K_SWEEP"]="klist";                  UNIT["K_SWEEP"]="count"
      TYPE["K_PROVISIONAL"]="kmember";          UNIT["K_PROVISIONAL"]="count"
    }
    /<!--[[:space:]]*THRESHOLDS:BEGIN[[:space:]]*-->/ { inblk=1; began=1; next }
    /<!--[[:space:]]*THRESHOLDS:END[[:space:]]*-->/   { inblk=0; ended=1; next }
    inblk {
      if ($0 ~ /^[ \t\r]*$/) next
      if (!hdr) {
        hdr=1
        hh=trim($1); for(i=2;i<=NF;i++) hh=hh" "trim($i)
        if (NF!=4 || hh!="key value unit provenance")
          print "bad thresholds header (need 4-col TAB \"key value unit provenance\"): got [\""hh"\"] NF="NF
        next
      }
      if (NF!=4) { print "thresholds row "NR": expected 4 tab-separated columns, got "NF; next }
      kk=trim($1); vv=trim($2); uu=trim($3); pp=trim($4)
      if (!(kk in REQ)) { print "thresholds row "NR": unknown key ["kk"]"; next }
      CNT[kk]++
      if (CNT[kk]>1) { print "thresholds key ["kk"] appears more than once"; next }
      VAL[kk]=vv
      if (isph(vv)) print "thresholds key ["kk"] has placeholder value ["vv"]"
      else {
        t=TYPE[kk]
        if (t=="pint")    { if(!ispint(vv)) print "thresholds key ["kk"] value ["vv"] is not a positive integer" }
        else if (t=="pnum"){ if(!ispnum(vv)) print "thresholds key ["kk"] value ["vv"] is not a positive number" }
        else if (t=="nnum"){ if(!isnnum(vv)) print "thresholds key ["kk"] value ["vv"] is not a non-negative number" }
        else if (t=="kmember"){ if(!ispint(vv)) print "thresholds key ["kk"] value ["vv"] is not a positive integer" }
        else if (t=="klist"){
          if (vv !~ /^[0-9]+(,[0-9]+)+$/) print "thresholds K_SWEEP ["vv"] is not a comma-list of >=2 positive integers"
          else { m=split(vv, KS, ","); ok=1; p2=1
                 for(j=1;j<=m;j++){ if(!(KS[j] ~ /^[0-9]+$/ && KS[j]+0>0)) ok=0; if(!ispow2(KS[j])) p2=0 }
                 if (m<2 || !ok) print "thresholds K_SWEEP ["vv"] is not a comma-list of >=2 positive integers"
                 else if (!p2) print "thresholds K_SWEEP ["vv"] entries must all be powers of two"
                 else SWEEP=vv }
        }
      }
      if (uu != UNIT[kk]) print "thresholds key ["kk"] unit ["uu"] != required ["UNIT[kk]"]"
      if (pp == "")       print "thresholds key ["kk"] has empty provenance"
    }
    END{
      if (!began) print "thresholds block start marker <!-- THRESHOLDS:BEGIN --> not found"
      else if (!ended) print "thresholds block end marker <!-- THRESHOLDS:END --> not found (unterminated block)"
      else if (!hdr) print "thresholds block has no header row"
      for(i=1;i<=NKEY;i++) if (CNT[K[i]]+0==0) print "thresholds missing required key ["K[i]"]"
      if (("K_PROVISIONAL" in VAL) && SWEEP!="") {
        kp=VAL["K_PROVISIONAL"]; found=0; m=split(SWEEP, KS, ",")
        for(j=1;j<=m;j++) if(KS[j]==kp) found=1
        if (!found) print "K_PROVISIONAL ["kp"] is not a member of K_SWEEP ["SWEEP"]"
      }
      if (("C6_PROOF_REDEEMER_CAP" in VAL) && ("C6_WHOLE_TX_CAP" in VAL) && ispint(VAL["C6_PROOF_REDEEMER_CAP"]) && ispint(VAL["C6_WHOLE_TX_CAP"])) {
        if (VAL["C6_PROOF_REDEEMER_CAP"]+0 >= VAL["C6_WHOLE_TX_CAP"]+0)
          print "C6_PROOF_REDEEMER_CAP ["VAL["C6_PROOF_REDEEMER_CAP"]"] must be < C6_WHOLE_TX_CAP ["VAL["C6_WHOLE_TX_CAP"]"] (real headroom)"
      }
    }
  ' "$THRESHOLDS" 2>/dev/null)
  if [ -n "$_errs" ]; then
    printf 'FAIL[thresholds]: ratified value/unit/provenance block violations:\n'
    printf '  %s\n' "$_errs"; fail=1
  fi
}

# require_nonplaceholder CRITERION [CANDIDATE] — the staged targets assert that a
# criterion's (optionally candidate-scoped) rows EXIST and none carry a
# MEASURE/PROVE/VERIFY placeholder outcome (RED before the slice, GREEN after).
require_nonplaceholder() {
  _c="$1"; _ca="${2:-}"
  _lbl="$_c${_ca:+/$_ca}"
  if [ ! -f "$MATRIX" ]; then
    red "staged: matrix.tsv absent — cannot check $_lbl"; return
  fi
  _res=$(awk -F '\t' -v k="$_c" -v ca="$_ca" '
    function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }
    /^[ \t]*#/ { next }  /^[ \t]*$/ { next }
    { if(!h){h=1;next} }
    { c=trim($1); cc=trim($2); ou=trim($9)
      if (c==k && (ca==""||cc==ca)) { seen++; if(ou=="MEASURE"||ou=="PROVE"||ou=="VERIFY") ph++ } }
    END { print seen+0" "ph+0 }
  ' "$MATRIX" 2>/dev/null)
  set -- $_res; _seen=$1; _ph=$2
  if [ "${_seen:-0}" -eq 0 ]; then
    red "staged: no matrix rows for $_lbl yet (RED before this slice materializes them)"
  elif [ "${_ph:-0}" -ne 0 ]; then
    red "staged: $_lbl still has placeholder (MEASURE/PROVE/VERIFY) outcomes (RED before this slice)"
  fi
}

# FINAL matrix completeness (fixed coverage map — NOTE-004 item 2): every listed
# criterion×candidate×scenario×transaction cell must be PRESENT and non-placeholder;
# no MEASURE/PROVE/VERIFY outcome may remain; and `COMMON` may appear ONLY on the
# genuinely shared rows (C1a Step/Finish, C3b, C5, and the C7 registration lifecycle).
check_matrix_filled() {
  [ -f "$MATRIX" ] || { red "evidence/matrix.tsv absent — matrix not filled from delegated measurement"; return; }
  # Required cells: criterion,candidate,scenario,transaction (metric family is
  # illustrative — the hard contract is presence + non-placeholder of each cell).
  _req="C1a,COMMON,single,Step C1a,COMMON,single,Finish \
C1a,A,single,Activation C1a,B,single,Activation C1a,C,single,Activation \
C1b,A,single,Rotation C1b,B,single,Rotation C1b,C,single,Rotation \
C2,A,average,Rotation C2,A,adversarial,Rotation C2,B,average,Rotation C2,B,adversarial,Rotation C2,C,average,Rotation C2,C,adversarial,Rotation \
C3,A,population,n/a C3,B,population,n/a C3,C,population,n/a \
C3b,COMMON,peak,n/a C3b,COMMON,abandoned,n/a \
C4,A,average,Rotation C4,A,targeted-victim,Rotation C4,B,average,Rotation C4,B,targeted-victim,Rotation C4,C,average,Rotation C4,C,targeted-victim,Rotation \
C5,COMMON,single,n/a \
C6,A,single,Read C6,B,single,Read C6,C,single,Read \
C7,COMMON,single,n/a C7,A,single,n/a C7,B,single,n/a C7,C,single,n/a \
C8,A,single,n/a C8,B,single,n/a C8,C,single,n/a \
C9,A,single,n/a C9,B,single,n/a C9,C,single,n/a"
  _errs=$(awk -F '\t' -v req="$_req" '
    function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }
    /^[ \t]*#/ { next }  /^[ \t]*$/ { next }
    { if(!h){h=1;next} }
    {
      cr=trim($1); ca=trim($2); sc=trim($3); tx=trim($4); ou=trim($9)
      if (ou=="MEASURE"||ou=="PROVE"||ou=="VERIFY")
        print "placeholder outcome remains at "cr"/"ca"/"sc"/"tx" ("ou")"
      else
        PRESENT[cr"|"ca"|"sc"|"tx]=1
      if (ca=="COMMON") {
        legal = ( (cr=="C1a" && (tx=="Step"||tx=="Finish")) || cr=="C3b" || cr=="C5" || cr=="C7" )
        if (!legal) print "COMMON candidate not permitted for "cr"/"tx" (must be A/B/C — NOTE-004 item 2)"
      }
    }
    END{
      n=split(req, R, " ")
      for(i=1;i<=n;i++){
        split(R[i], F, ",")
        if (!((F[1]"|"F[2]"|"F[3]"|"F[4]) in PRESENT))
          print "missing/placeholder required cell "F[1]"/"F[2]"/"F[3]"/"F[4]
      }
    }
  ' "$MATRIX" 2>/dev/null)
  if [ -n "$_errs" ]; then
    printf 'FAIL[gate]: matrix coverage/placeholder violations:\n'
    printf '  %s\n' "$_errs"; fail=1
  fi
}

# Thresholds ratified BEFORE measurement (NOTE-004 item 4). The ratifying SHA is
# COMPUTED from git history, must EQUAL the recorded thresholds_commit, and must be
# a STRICT ANCESTOR of the LATEST commit of EVERY data-bearing measurement artifact
# — matrix.tsv, evidence.json, REPORT.md, live-smoke.tsv, and any committed raw
# measurement logs (when present) — not just matrix.tsv. Skeleton/schema commits may
# predate thresholds; the latest data-bearing revision of each must follow. Every SHA
# it handles is full-40-hex validated; all pathspecs are repo-relative.

# _ordering_after LABEL REL_PATH — assert _computed strictly precedes REL_PATH's
#   latest commit (used only when REL_PATH has a committed revision).
_ordering_after() {
  _m=$(git -C "$REPO" log -1 --format=%H -- "$2" 2>/dev/null)
  if [ -z "$_m" ]; then
    red "cannot resolve the latest commit for $1 (ordering unproven — must be committed)"; return
  fi
  is_hex40 "$_m" || { red "latest commit for $1 is not a full 40-hex SHA ('$_m')"; return; }
  if [ "$_computed" = "$_m" ]; then
    red "thresholds ratified in the SAME commit as $1 (must be a PRIOR reviewed commit)"
  elif ! git -C "$REPO" merge-base --is-ancestor "$_computed" "$_m" 2>/dev/null; then
    red "ratified thresholds commit is not a strict ancestor of $1 (NOTE-016 ordering)"
  fi
}

check_ordering() {
  if ! command -v git >/dev/null 2>&1 || ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    red "no git context to prove thresholds predate measurement (ordering unproven — RED)"; return
  fi
  _computed=$(git -C "$REPO" log -1 --format=%H -- "$REL_THRESHOLDS" 2>/dev/null)
  if [ -z "$_computed" ]; then
    red "thresholds.md has no commit in history — cannot COMPUTE the ratified commit (ordering unproven)"; return
  fi
  is_hex40 "$_computed" || { red "computed thresholds commit is not a full 40-hex SHA ('$_computed')"; return; }
  # recorded thresholds_commit (from evidence.json) must be full-40-hex and EQUAL the computed commit.
  _recorded=""
  if [ -f "$EVJSON" ] && have_jq; then
    _recorded=$(jq -r '.thresholds_commit // ""' "$EVJSON" 2>/dev/null)
  fi
  if [ -z "$_recorded" ]; then
    red "evidence.json records no thresholds_commit (ordering unproven)"
  elif ! is_hex40 "$_recorded"; then
    red "evidence.json thresholds_commit is not a full 40-hex SHA ('$_recorded')"
  else
    _rec_full=$(git -C "$REPO" rev-parse --verify --quiet "${_recorded}^{commit}" 2>/dev/null)
    [ "$_rec_full" = "$_computed" ] \
      || red "evidence thresholds_commit ($_recorded) != COMPUTED thresholds-file commit ($_computed)"
  fi
  [ -f "$MATRIX" ]    && _ordering_after "matrix.tsv"     "$REL_MATRIX"
  [ -f "$EVJSON" ]    && _ordering_after "evidence.json"  "$REL_EVJSON"
  [ -f "$REPORT" ]    && _ordering_after "REPORT.md"      "$REL_REPORT"
  [ -f "$LIVESMOKE" ] && _ordering_after "live-smoke.tsv" "$REL_LIVESMOKE"
  # ...and any committed raw measurement logs under evidence/ (when present). A
  # `for` loop (not a pipe) keeps `fail` in the current shell, not a subshell.
  _logs=$(git -C "$REPO" ls-files -- "$REL_EVID/*.log" "$REL_EVID/*/*.log" "$REL_EVID/raw" 2>/dev/null)
  for _lg in $_logs; do
    [ -n "$_lg" ] && _ordering_after "raw log $_lg" "$_lg"
  done
  # Guard: at least matrix.tsv must resolve, else ordering is unproven.
  if [ ! -f "$MATRIX" ]; then
    red "cannot resolve the measurement commit for matrix.tsv (ordering unproven)"
  fi
}

# FINAL evidence.json — parsed, non-empty provenance, resolved selection.
check_evidence_json_final() {
  if [ ! -f "$EVJSON" ]; then red "evidence/evidence.json absent (raw + machine-readable evidence)"; return; fi
  if ! have_jq; then red "jq unavailable — cannot PARSE evidence.json (fail closed — NOTE-003 item 3)"; return; fi
  if ! jq -e . "$EVJSON" >/dev/null 2>&1; then red "evidence.json is not valid JSON (jq parse failed)"; return; fi
  for k in tool_versions commands protocol_parameters thresholds_commit selection; do
    jq -e "has(\"$k\")" "$EVJSON" >/dev/null 2>&1 || red "evidence.json missing top-level key '$k'"
  done
  jq -e '.tool_versions      | length > 0' "$EVJSON" >/dev/null 2>&1 || red "evidence.json tool_versions is empty"
  jq -e '.commands           | length > 0' "$EVJSON" >/dev/null 2>&1 || red "evidence.json commands is empty"
  jq -e '.protocol_parameters| length > 0' "$EVJSON" >/dev/null 2>&1 || red "evidence.json protocol_parameters is empty"
  _sel=$(jq -r '.selection // ""' "$EVJSON" 2>/dev/null)
  case "$_sel" in A|B|C) : ;; *) red "evidence.json .selection is not A|B|C at final ('$_sel')" ;; esac
}

# REPORT.md distinguishes the five evidence classes.
check_report() {
  if [ ! -f "$REPORT" ]; then red "evidence/REPORT.md absent (human-readable evidence report)"; return; fi
  for cls in measured derived estimated declared unsupported; do
    present "REPORT.md distinguishes '$cls' cells" "$REPORT" "$cls"
  done
}

# Structured live-boundary smoke — fixed 11-column contract (NOTE-004 item 5):
#   candidate tx_id network node_version protocol_params tx_tool_version \
#   inspect validate phase1 phase2 note
# requires the SELECTED candidate, a real (64-hex) tx id, node/network/protocol
# provenance, the cardano-tx-tools version, structured `cardano-tx-tools`
# inspect=PASS + validate=PASS, and explicit node Phase-1=PASS / Phase-2=PASS
# (structured columns, not substring presence). Single-tx boundary smoke, not a
# throughput/load claim.
check_smoke() {
  if [ ! -f "$LIVESMOKE" ]; then
    red "evidence/live-smoke.tsv absent — no live checkpoint-advance smoke recorded"; return
  fi
  _sel=""
  if [ -f "$EVJSON" ] && have_jq; then _sel=$(jq -r '.selection // ""' "$EVJSON" 2>/dev/null); fi
  _errs=$(awk -F '\t' -v sel="$_sel" '
    function trim(s){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",s); return s }
    /^[ \t]*#/ { next }  /^[ \t]*$/ { next }
    {
      if(!h){ h=1
        want="candidate tx_id network node_version protocol_params tx_tool_version inspect validate phase1 phase2 note"
        got=trim($1); for(i=2;i<=NF;i++) got=got" "trim($i)
        if (NF!=11 || got!=want) print "bad header (need 11-col \""want"\"): got [\""got"\"]"
        next }
      rows++
      if (NF!=11){ print "row "NR": expected 11 tab-separated columns, got "NF; next }
      ca=trim($1); tx=trim($2); nw=trim($3); nv=trim($4); pp=trim($5); tv=trim($6)
      ins=trim($7); val=trim($8); p1=trim($9); p2=trim($10); nt=trim($11)
      if (ca!="A" && ca!="B" && ca!="C") print "row "NR": candidate not A/B/C ["ca"]"
      if (sel!="" && ca!=sel)            print "row "NR": candidate ["ca"] != selected ["sel"]"
      if (tx !~ /^[0-9a-fA-F]{64}$/)     print "row "NR": tx_id is not a real 64-hex tx id ["tx"]"
      if (nw=="") print "row "NR": empty network"
      if (nv=="") print "row "NR": empty node_version"
      if (pp=="") print "row "NR": empty protocol_params"
      if (tv=="") print "row "NR": empty tx_tool_version"
      if (ins!="PASS") print "row "NR": cardano-tx-tools inspect != PASS ["ins"]"
      if (val!="PASS") print "row "NR": cardano-tx-tools validate != PASS ["val"]"
      if (p1!="PASS")  print "row "NR": node phase1 != PASS ["p1"]"
      if (p2!="PASS")  print "row "NR": node phase2 != PASS ["p2"]"
      if (nt=="") print "row "NR": empty note"
    }
    END{ if(!h) print "live-smoke.tsv has no header row"; if(rows+0==0) print "live-smoke.tsv has no data rows" }
  ' "$LIVESMOKE" 2>/dev/null)
  if [ -n "$_errs" ]; then
    printf 'FAIL[smoke]: live-smoke.tsv contract violations:\n'
    printf '  %s\n' "$_errs"; fail=1
  fi
  # The #99 devnet limitation must be stated verbatim (comment or note column).
  present "live-smoke states the #99 devnet limitation" "$LIVESMOKE" \
      'maxTxExUnits|140|conservative|declared'
}

# DECISION.md machine headers — EXACTLY ONE selected + EXACTLY TWO distinct
# rejected (neither == selection), selection rule, evidence/threshold refs,
# non-empty residual risks. Sets DECISION_SELECTED for the negative guards.
check_decision() {
  if [ ! -f "$DECISION" ]; then
    red "DECISION.md absent — no candidate selected (permanent non-selection fails #92)"; return
  fi
  _sel=$(kv "$DECISION" 'SELECTED_CANDIDATE')
  case "$_sel" in
    A|B|C) : ;;
    "") red "DECISION.md missing 'SELECTED_CANDIDATE=<A|B|C>' machine header"; _sel="" ;;
    *)  red "DECISION.md SELECTED_CANDIDATE not exactly one of A|B|C (got '$_sel')"; _sel="" ;;
  esac
  DECISION_SELECTED="$_sel"

  _rej=$(kv "$DECISION" 'REJECTED_CANDIDATES')
  if [ -z "$_rej" ]; then
    red "DECISION.md missing 'REJECTED_CANDIDATES=' machine header"
  else
    _rej_norm=$(printf '%s' "$_rej" | tr ',;' '  ' | tr -s ' ')
    _n=0; _bad=0; _dupe=0; _sa=0; _sb=0; _sc=0
    for r in $_rej_norm; do
      _n=$((_n+1))
      case "$r" in
        A) [ $_sa -eq 1 ] && _dupe=1; _sa=1 ;;
        B) [ $_sb -eq 1 ] && _dupe=1; _sb=1 ;;
        C) [ $_sc -eq 1 ] && _dupe=1; _sc=1 ;;
        *) _bad=1 ;;
      esac
      [ -n "$_sel" ] && [ "$r" = "$_sel" ] && _bad=1
    done
    [ $_n -eq 2 ]   || red "DECISION.md REJECTED_CANDIDATES must list exactly two (got $_n: '$_rej')"
    [ $_dupe -eq 0 ] || red "DECISION.md REJECTED_CANDIDATES has duplicates ('$_rej')"
    [ $_bad -eq 0 ]  || red "DECISION.md REJECTED_CANDIDATES malformed or includes the selected candidate ('$_rej' vs selected '$_sel')"
    # exactly-one + two-distinct-from-{A,B,C}-not-selected ==> a clean partition.
  fi

  for hkey in SELECTION_RULE EVIDENCE_REF THRESHOLDS_COMMIT RESIDUAL_RISKS; do
    _v=$(kv "$DECISION" "$hkey")
    [ -n "$_v" ] || red "DECISION.md missing/empty machine header '$hkey='"
  done
  _dtc=$(kv "$DECISION" 'THRESHOLDS_COMMIT')
  case "$_dtc" in
    "") : ;;  # empty already flagged above
    *) is_hex40 "$_dtc" || red "DECISION.md THRESHOLDS_COMMIT is not a full 40-hex SHA ('$_dtc')" ;;
  esac
  _deref=$(kv "$DECISION" 'EVIDENCE_REF')
  case "$_deref" in
    "") : ;;  # empty already flagged above
    *) is_hex40 "$_deref" || red "DECISION.md EVIDENCE_REF is not a full 40-hex SHA ('$_deref')" ;;
  esac

  # --- cross-bound references (NOTE-004 item 3) ----------------------------
  # SELECTED_CANDIDATE == evidence.json.selection == live-smoke.candidate;
  # THRESHOLDS_COMMIT == COMPUTED threshold-file commit == evidence.json.thresholds_commit;
  # EVIDENCE_REF resolves to the actual latest evidence/** commit.
  if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # (a) selection triple-binding.
    if [ -n "$_sel" ]; then
      _ejsel=""
      if [ -f "$EVJSON" ] && have_jq; then _ejsel=$(jq -r '.selection // ""' "$EVJSON" 2>/dev/null); fi
      [ "$_ejsel" = "$_sel" ] \
        || red "DECISION SELECTED_CANDIDATE ('$_sel') != evidence.json.selection ('$_ejsel')"
      if [ -f "$LIVESMOKE" ]; then
        _lsbad=$(awk -F '\t' -v s="$_sel" '
          function trim(x){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",x); return x }
          /^[ \t]*#/ { next }  /^[ \t]*$/ { next }
          { if(!h){h=1;next} }
          { c=trim($1); if(c!=s) print c }
        ' "$LIVESMOKE" 2>/dev/null)
        [ -z "$_lsbad" ] \
          || red "live-smoke.tsv candidate(s) [$(echo $_lsbad | tr '\n' ' ')] != DECISION selection ('$_sel')"
      else
        red "live-smoke.tsv absent — cannot cross-bind DECISION selection to the live smoke"
      fi
    fi
    # (b) threshold-commit triple-binding.
    _computed=$(git -C "$REPO" log -1 --format=%H -- "$REL_THRESHOLDS" 2>/dev/null)
    if [ -z "$_computed" ]; then
      red "cannot COMPUTE threshold-file commit to cross-bind DECISION.THRESHOLDS_COMMIT"
    else
      if [ -n "$_dtc" ] && is_hex40 "$_dtc"; then
        _dtc_full=$(git -C "$REPO" rev-parse --verify --quiet "${_dtc}^{commit}" 2>/dev/null)
        [ "$_dtc_full" = "$_computed" ] \
          || red "DECISION THRESHOLDS_COMMIT ('$_dtc') != COMPUTED threshold-file commit ('$_computed')"
      fi
      _ejtc=""
      if [ -f "$EVJSON" ] && have_jq; then _ejtc=$(jq -r '.thresholds_commit // ""' "$EVJSON" 2>/dev/null); fi
      if [ -n "$_ejtc" ] && is_hex40 "$_ejtc"; then
        _ejtc_full=$(git -C "$REPO" rev-parse --verify --quiet "${_ejtc}^{commit}" 2>/dev/null)
        [ "$_ejtc_full" = "$_computed" ] \
          || red "evidence.json thresholds_commit ('$_ejtc') != COMPUTED threshold-file commit ('$_computed')"
      else
        red "evidence.json thresholds_commit missing / not full-40-hex for DECISION cross-binding ('$_ejtc')"
      fi
    fi
    # (c) EVIDENCE_REF must be a full 40-hex SHA before we resolve/compare it.
    _eref=$(kv "$DECISION" 'EVIDENCE_REF')
    if [ -n "$_eref" ] && is_hex40 "$_eref"; then
      _eref_full=$(git -C "$REPO" rev-parse --verify --quiet "${_eref}^{commit}" 2>/dev/null)
      if [ -z "$_eref_full" ]; then
        red "DECISION EVIDENCE_REF ('$_eref') does not resolve to a commit"
      else
        _evlast=$(git -C "$REPO" log -1 --format=%H -- "$REL_EVID" 2>/dev/null)
        if [ -z "$_evlast" ]; then
          red "cannot resolve the latest evidence/** commit for EVIDENCE_REF cross-binding"
        else
          [ "$_eref_full" = "$_evlast" ] \
            || red "DECISION EVIDENCE_REF ('$_eref' -> $_eref_full) != latest evidence/** commit ($_evlast)"
        fi
      fi
    fi
  else
    red "no git context to cross-bind DECISION references (NOTE-004 item 3)"
  fi
}

# Canonical docs carry the decision (prose presence) + R-KEL preservation.
check_canonical() {
  present "identity-model: §10 thread 8 resolved by the #92 storage selection" "$IM" \
      'thread 8[^.]*(decid|resolv|select|closed)|#92[^.]*(select|decid)[^.]*(storage|checkpoint)|(storage|checkpoint)[^.]*shape[^.]*(select|decid)'
  present "system-architecture: §6 registry carries the #92 checkpoint-storage decision" "$SA" \
      '#92[^.]*(checkpoint|advance)[^.]*(storage|shape)[^.]*(decid|select)|(decid|select)[^.]*#92[^.]*(checkpoint|storage)'
  # Preservation: R-KEL stays an on-chain checkpoint, NOT a watcher-attested mirror.
  present "identity-model/system-architecture: R-KEL preserved as on-chain checkpoint over R-ID" \
      "$SA" 'R-KEL[^.]*checkpoint[^.]*R-ID|checkpoint over settled R-ID'
  forbid_pred "R-KEL must not be reclassified as a watcher-attested / mirror-root mirror" \
      "$SA" \
      'R-KEL[^.]{0,28}(watcher[- ]?(attested|computed)?[- ]?)?mirror' \
      'R-KEL[^.]{0,20}(not|never|isn.t|no[[:space:]]+longer|set[[:space:]]+apart|separat|apart|orthogonal|distinct|unlike|exclud)'
}

# NEGATIVE guards (selection integrity).
negative_guards() {
  # (N1) selection WITHOUT complete evidence is forbidden.
  if [ -n "$DECISION_SELECTED" ]; then
    _un=0
    [ -f "$MATRIX" ]     || _un=1
    [ -f "$LIVESMOKE" ]  || _un=1
    [ -f "$THRESHOLDS" ] || _un=1
    [ -f "$REPORT" ]     || _un=1
    [ -f "$EVJSON" ]     || _un=1
    if [ "$_un" -ne 0 ]; then
      red "NEGATIVE: candidate '$DECISION_SELECTED' selected WITHOUT complete threshold-ordered/filled/smoked/reported evidence"
    fi
    # The SELECTED candidate's own A/B/C rows AND every shared COMMON row must be
    # terminal PASS/FAIL with NO FAIL/unsupported/placeholder (the two REJECTED
    # candidates keep their falsifying cells honestly — not checked here).
    if [ -f "$MATRIX" ]; then
      _selbad=$(awk -F '\t' -v s="$DECISION_SELECTED" '
        function trim(x){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",x); return x }
        /^[ \t]*#/ { next }  /^[ \t]*$/ { next }
        { if(!h){h=1;next} }
        { ca=trim($2); if(ca==s || ca=="COMMON"){ ou=trim($9); cl=trim($8)
            if(ou=="MEASURE"||ou=="PROVE"||ou=="VERIFY"||ou=="FAIL"||cl=="unsupported") print trim($1)"/"ca } }
      ' "$MATRIX" 2>/dev/null)
      if [ -n "$_selbad" ]; then
        printf 'FAIL[gate]: NEGATIVE: selected candidate %s / shared COMMON rows have unfilled/unsupported/FAIL criteria: %s\n' \
            "$DECISION_SELECTED" "$(echo "$_selbad" | tr '\n' ' ')"; fail=1
      fi
    fi
  fi
  # (N2) a FILLED matrix with NO selection is incomplete (permanent non-selection fails #92).
  if [ -f "$MATRIX" ] && [ -z "$DECISION_SELECTED" ]; then
    _anyph=$(awk -F '\t' '
      function trim(x){ gsub(/^[ \t\r]+|[ \t\r]+$/,"",x); return x }
      /^[ \t]*#/ { next }  /^[ \t]*$/ { next }
      { if(!h){h=1;next} }
      { ou=trim($9); if(ou=="MEASURE"||ou=="PROVE"||ou=="VERIFY") p=1 }
      END{ print p+0 }
    ' "$MATRIX" 2>/dev/null)
    if [ "${_anyph:-0}" -eq 0 ]; then
      red "NEGATIVE: matrix is filled but no candidate is selected (permanent non-selection fails #92)"
    fi
  fi
}

# ============================================================================
# Deliverable exists (fail-safe hard stop for every mode)
# ============================================================================
if [ ! -f "$SPEC" ]; then
  echo "FAIL: missing $SPEC (RED — no #92 planning record; expected on origin/main)"
  exit 1
fi

# ============================================================================
# Dispatch — staged targets (RED-before / GREEN-after per slice) + `final`.
# ============================================================================
case "$MODE" in
  spec)
    layer1_spec
    ;;
  schema)
    layer1_spec
    check_matrix_schema
    check_evidence_json_skeleton
    ;;
  thresholds)
    layer1_spec
    check_matrix_schema
    check_thresholds_values
    ;;
  registration)
    layer1_spec
    check_matrix_schema
    check_thresholds_values
    require_nonplaceholder C1a
    require_nonplaceholder C3b COMMON
    require_nonplaceholder C5  COMMON
    require_nonplaceholder C7  COMMON
    ;;
  candidate-A)
    layer1_spec; check_matrix_schema; check_thresholds_values
    require_nonplaceholder C1b A
    require_nonplaceholder C3  A
    require_nonplaceholder C6  A
    require_nonplaceholder C9  A
    ;;
  candidate-B)
    layer1_spec; check_matrix_schema; check_thresholds_values
    require_nonplaceholder C1b B
    require_nonplaceholder C3  B
    require_nonplaceholder C6  B
    require_nonplaceholder C9  B
    ;;
  candidate-C)
    layer1_spec; check_matrix_schema; check_thresholds_values
    require_nonplaceholder C1b C
    require_nonplaceholder C3  C
    require_nonplaceholder C6  C
    require_nonplaceholder C9  C
    ;;
  contention)
    layer1_spec; check_matrix_schema; check_thresholds_values
    require_nonplaceholder C2
    require_nonplaceholder C4
    require_nonplaceholder C7
    require_nonplaceholder C8
    ;;
  smoke)
    layer1_spec
    check_matrix_schema
    check_thresholds_values
    check_matrix_filled
    check_smoke
    check_report
    ;;
  final)
    layer1_spec
    check_matrix_schema
    check_thresholds_values
    check_ordering
    check_matrix_filled
    check_evidence_json_final
    check_report
    check_smoke
    check_decision
    check_canonical
    negative_guards
    ;;
  *)
    echo "accept.sh: unknown target '$MODE'"
    echo "usage: accept.sh [spec|schema|thresholds|registration|candidate-A|candidate-B|candidate-C|contention|smoke|final]"
    exit 2
    ;;
esac

# --- verdict ---------------------------------------------------------------
if [ "$fail" -ne 0 ]; then
  echo "accept.sh[$MODE]: FAIL (RED — #92 target '$MODE' not yet satisfied)"
  exit 1
fi
echo "accept.sh[$MODE]: OK (GREEN — #92 target '$MODE' satisfied)"
exit 0
