#!/bin/sh
# accept.sh — final-acceptance contract for cardano-keri #92
# (design(onchain): R-KEL checkpoint advance-storage & contention model —
#  the SOVEREIGN per-AID checkpoint UTxO, Candidate A).
#
# OPERATOR DECISION (answers/A-001-thresholds.md, ratified 2026-07-14).
# The operator selected **Candidate A** — one sovereign, per-AID, quantity-one
# uniquely-tokenized checkpoint UTxO — as a normative security/product decision.
# Sovereignty and unrelated-AID isolation are the LOAD-BEARING selection criteria:
# unrelated issuers and attacker-created AIDs must not be able to contend with,
# serialize, or delay an AID's current-authority checkpoint / rotation / recovery /
# re-authorization path. The selection is NOT conditional on A winning a
# throughput/capital/cost contest, and it does NOT wait on ratifying arbitrary B/C
# measurement thresholds.
#
#   - B is REJECTED because a single/global/shared checkpoint-root UTxO serializes
#     unrelated identities on one contended UTxO.
#   - C is REJECTED because a public/grindable lane (`lane = f(cesr_aid)`) lets
#     hostile AIDs target a victim's lane, making sovereignty depend on shard
#     machinery.
#   - A is SELECTED because each AID's current-authority state advances through its
#     OWN uniquely-tokenized UTxO; unrelated AIDs cannot consume or serialize it.
#
# Candidate-A COST / TX-SIZE / MIN-ADA / BATCH-FAN-IN measurements and the
# live-boundary smoke REMAIN required — but as *Candidate-A implementation sizing
# and live-boundary honesty*, a DOWNSTREAM implementation gate, NOT as the reason A
# was chosen and NOT as a precondition of this design decision. They must never be
# fabricated, back-filled, or represented as the selection basis. This design
# ticket writes NO validators.
#
# This script has one STRUCTURAL layer over spec.md plus the SOVEREIGN-DECISION
# deliverable gates, and exposes staged targets:
#
#     spec      Layer-1 structural self-check of the planning/decision record
#               (GREEN at this HEAD once the sovereign spec landed).
#     decision  spec + DECISION.md sovereign machine-header contract
#               (GREEN after the ticket-owner DECISION.md lands).
#     ds1       DS1 canonical model — identity-model thread 8 + system-architecture.
#     ds2       DS2 ACDC boundary — docs/acdc-primer.md.
#     ds3       DS3 architecture current-auth + discovery — overview/value-auth/
#               veridian-bridge/identity-ops + docs/index.md.
#     ds4       DS4 design trust/UX/DeFi/aid — trust-model/user-experience/defi-gate/
#               aid-model.
#     ds5       DS5 downstream-consequence specs + business cases — specs/24-keystate,
#               specs/23-identity-auth + docs/design/business-cases/*.
#     ds6       DS6 loss/fork semantics + superwatcher live-duty contract (reopen,
#               NOTE-022) — super-watcher/identity-model/trust-model/user-experience/
#               veridian-bridge/amaru-integration/roadmap/vlei.
#     docs      decision + ALL SIX DS groups (ds1..ds6) carry the sovereign decision.
#     final     (default) docs + selection-integrity negative guards.
#
# EXPECTED RESULT while the documentation slices are still pending:
#   - `spec`     -> GREEN (spec.md well-formed + sovereign).
#   - `decision` -> GREEN once DECISION.md is present and well-formed.
#   - each `ds<N>` -> RED, safely, until its group's surfaces are reconciled; GREEN
#     after that reviewed slice lands.
#   - `docs`/`final` -> RED until ALL SIX DS groups (every exact surface) land; final
#     cannot go GREEN while any DS surface stays stale.
#   - RED on origin/main (no spec dir at all).
#
# DESIGN RULES:
#   - FAIL-SAFE: every gate first tests artifact existence; absence is RED, never a
#     crash and never a false pass.
#   - STRUCTURED-FILE-FIRST: DECISION.md selection is read from machine headers
#     (KEY=value); prose grep drives the DS1..DS5 documentation checks (per-surface
#     sovereign #92 forward-pointer markers + narrow negative guards on live
#     current-auth claims, with historical/admission/QVI/genesis exemptions), the
#     canonical R-KEL-classification preservation, and the spec's structural claims.
#   - HONEST RESIDUAL, NOT A BLOCKER: the A-implementation-sizing + live-boundary
#     measurement obligation is recorded as a residual (MEASUREMENT_RESIDUAL) so its
#     absence is never mistaken for "no decision" — but it does NOT gate `final`.
#   - NEGATIVE GUARDS: the decision must NOT be represented as a measured
#     throughput/capital/cost-matrix win; no fabricated measurement may stand in as
#     the selection basis; B/C rejection reasoning must be present and sovereign.
#
# Exit 0 = the requested target's gates hold (GREEN). Exit 1 = one or more failed
# (RED). Exit 2 = unknown staged target.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)

SPEC="$SCRIPT_DIR/spec.md"
DECISION="$SCRIPT_DIR/DECISION.md"

# DS1 — canonical model (gates final via check_canonical).
IM="$REPO/specs/68-keystate-shape/identity-model.md"
SA="$REPO/specs/68-keystate-shape/system-architecture.md"
# DS2 — ACDC boundary.
AP="$REPO/docs/acdc-primer.md"
# DS3 — architecture current-auth + discovery.
ARCH_OVERVIEW="$REPO/docs/architecture/overview.md"
ARCH_VALUEAUTH="$REPO/docs/architecture/value-auth.md"
ARCH_VERIDIAN="$REPO/docs/architecture/veridian-bridge.md"
ARCH_IDENTITYOPS="$REPO/docs/architecture/identity-ops.md"
DOC_INDEX="$REPO/docs/index.md"
# DS4 — design trust/UX/DeFi/aid.
DSG_TRUST="$REPO/docs/design/trust-model.md"
DSG_UX="$REPO/docs/design/user-experience.md"
DSG_DEFI="$REPO/docs/design/defi-gate.md"
DSG_AID="$REPO/docs/design/aid-model.md"
# DS5 — downstream-consequence specs + business cases.
SPEC24="$REPO/specs/24-keystate/spec.md"
SPEC23="$REPO/specs/23-identity-auth/spec.md"
BC_INDEX="$REPO/docs/design/business-cases/index.md"
BC_REGDEFI="$REPO/docs/design/business-cases/regulated-defi.md"
BC_INST="$REPO/docs/design/business-cases/institutional-contracts.md"
BC_SECURITY="$REPO/docs/design/business-cases/security-tokens.md"
BC_SPO="$REPO/docs/design/business-cases/spo-delegation.md"
# DS6 — loss/fork semantics + superwatcher live-duty contract (reopen 2026-07-15, NOTE-022).
SW="$REPO/docs/design/super-watcher.md"
ARCH_AMARU="$REPO/docs/architecture/amaru-integration.md"
DOC_ROADMAP="$REPO/docs/roadmap.md"
DSG_VLEI="$REPO/docs/design/vlei.md"
# (IM, SA, DSG_TRUST, DSG_UX, DSG_AID, ARCH_VERIDIAN reused from DS1/DS3/DS4.)

# SPTR — a forward pointer to the #92 sovereign per-AID checkpoint decision. The
# reviewed documentation slices add this (a correction or a superseded+pointer note),
# so its presence marks that a stale-Candidate-B surface was consciously reconciled.
SPTR='sovereign per-AID|per-AID sovereign|per-AID (sovereign )?checkpoint|#92[^.]*(sovereign|per-AID)|(sovereign|per-AID)[^.]*#92|92-checkpoint-contention|sovereign checkpoint (UTxO|decision)'

# EXEMPT — tokens that neutralise a narrow negative guard on ONE stale line: the pair
# either rewrites the line or annotates it as superseded/historical, and must preserve
# the legitimate admission-cache / credential / QVI / genesis planes.
EXEMPT='superseded|no longer|historical|formerly|previously|earlier (design|draft|shape)|#92|sovereign|per-AID|withdrawn|admission|credential[- ]?plane|deprecated|not the current|instead|correction|not normally|rather|genesis|QVI-issued|is not|does not'

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

# require_pointer LABEL FILE — assert FILE carries a forward pointer to the #92
#   sovereign per-AID decision (a correction or a superseded-note). Fail-safe: a
#   missing file is RED (the surface must exist and be reconciled).
require_pointer() { present "$1" "$2" "$SPTR"; }

# kv FILE KEY — echo the value of a `KEY=value` machine header (first match), trimmed.
kv() {
  [ -f "$1" ] || return 0
  grep -iE -- "^[#[:space:]]*$2[[:space:]]*=" "$1" 2>/dev/null \
    | head -n1 | sed -E "s/^[#[:space:]]*$2[[:space:]]*=[[:space:]]*//" \
    | tr -d '"' | tr -d "'" | awk '{$1=$1;print}'
}

# ============================================================================
# LAYER 1 — STRUCTURAL checks over spec.md (PASS at this HEAD)
# ============================================================================
layer1_spec() {
  # --- Sovereign decision framing (operator decision A-001) ----------------
  present "spec: operator decision — sovereignty selects Candidate A" "$SPEC" \
      'operator[- ]?ratified sovereignty invariant|sovereignty selects Candidate A|operator[^.]*selected[^.]*Candidate A'
  present "spec: sovereignty / unrelated-AID isolation is load-bearing" "$SPEC" \
      'unrelated-AID isolation|unrelated[^.]*AIDs?[^.]*cannot[^.]*(contend|consume|serialize|delay)'
  present "spec: Candidate A selected — own uniquely-tokenized per-AID UTxO" "$SPEC" \
      'own[^.]*uniquely[- ]?tokeni[sz]ed[^.]*UTxO|per-AID[^.]*(sovereign|own)[^.]*(UTxO|checkpoint)'
  present "spec: B rejected — shared/global UTxO serializes unrelated identities" "$SPEC" \
      'B is rejected[^.]*(shared|global|single)[^.]*(serial|contend|delay|unrelated)|(shared|global|single)[^.]*UTxO[^.]*serial'
  present "spec: C rejected — grindable public lane / sovereignty depends on shard machinery" "$SPEC" \
      'C is rejected[^.]*(grind|lane|shard)|grindable[^.]*lane[^.]*(target|victim)|sovereignty[^.]*depend[^.]*shard'
  present "spec: NOTE-021 (operator sovereign decision recorded)" "$SPEC" 'NOTE-021'
  # Selection must NOT be represented as a measured throughput/capital/cost win.
  present "spec: measurements are A-implementation sizing, NOT the selection reason" "$SPEC" \
      'implementation[- ]?sizing[^.]*not[^.]*selection|not[^.]*(the )?reason[^.]*(A )?was (chosen|selected)|not[^.]*selection evidence'
  present "spec: measurements must not be fabricated/back-filled" "$SPEC" \
      'not[^.]*fabricat|no fabricated|not[^.]*back[- ]?fill'

  # --- Logical/physical split (fixed inputs preserved) ---------------------
  present "spec: logical/physical distinction table"        "$SPEC" 'logical/physical|logical.*physical.*distinction'
  present "spec: NOTE-014 (logical unicity vs physical layout)" "$SPEC" 'NOTE-014'
  present "spec: fixed MPFS-with-oracle logical registration gate named" "$SPEC" 'MPFS-with-oracle'

  # --- Three named candidates (A selected; B/C rejected, kept for the record)
  present "spec: Candidate A — per-cesr_aid checkpoint UTxO" "$SPEC" 'Candidate A|per-.?cesr_aid.? checkpoint UTxO'
  present "spec: Candidate B — singleton MPFS"               "$SPEC" 'Candidate B|singleton MPFS'
  present "spec: Candidate C — lane-shard hybrid"            "$SPEC" 'Candidate C|lane-shard'

  # --- Candidate A minted AID-bound steady checkpoint asset (NOTE-019/020) --
  present "spec: NOTE-019 (minted AID-bound steady asset; generic discovery)" "$SPEC" 'NOTE-019'
  present "spec: NOTE-020 (native BLAKE2b locator; inductive caging; inductive downstream trust)" "$SPEC" 'NOTE-020'
  present "spec: steady checkpoint locator/state token for a registered AID" "$SPEC" \
      'steady checkpoint locator/state token|steady checkpoint locator|locator/state token for'
  present "spec: full asset id (checkpoint_policy_id, aid_asset_name)" "$SPEC" \
      '\(checkpoint_policy_id, ?aid_asset_name\)'
  present "spec: aid_asset_name domain-separated 32-byte derivation of qualified AID" "$SPEC" \
      'aid_asset_name.*(domain-separated|blake2b).*(32-byte|qualified)|(domain-separated|32-byte).*aid_asset_name'
  # The locator name must derive via the NATIVE blake2b_256 builtin — BLAKE3 stays
  #   the expensive #97/#98 genesis binding, unnecessary for a cheap locator label.
  present "spec: aid_asset_name uses native blake2b_256 builtin (not BLAKE3)" "$SPEC" \
      'blake2b_256\(CHECKPOINT_ASSET_DOMAIN_TAG|aid_asset_name[^A-Za-z0-9]*:?=[^A-Za-z0-9]*blake2b_256|native .?blake2b_256'
  # NEGATIVE guard — reject a BLAKE3 *locator* derivation (blake3 over the asset
  #   domain tag / aid_asset_name), WITHOUT rejecting the legitimate #97/#98
  #   `blake3(icp) == cesr_aid` GENESIS binding or the spikes/97-blake3-multitx path.
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
  present "spec: indexer supplies location/freshness for liveness only, not identity truth" "$SPEC" \
      'location and freshness for liveness only|not[^.]*identity truth|never[^.]*identity truth'
  present "spec: ACDC holder user story (Alice derives asset ids, generic indexer)" "$SPEC" \
      'ACDC holder user story|ACDC-facing user story|Alice.*derives the asset id'

  # --- Inductive downstream trust boundary (NOTE-020) ----------------------
  present "spec: downstream reads via CIP-31 reference input (read, not spent) — no spend validator runs" "$SPEC" \
      'read, not spent|does not execute the checkpoint spending validator'
  present "spec: transition facts inherited inductively (no KERI replay / genesis-BLAKE3 recompute / MPF proof)" "$SPEC" \
      'inherited inductively|does not replay KERI'
  present "spec: only a bounded provenance/state boundary check downstream" "$SPEC" \
      'bounded provenance/state boundary check|bounded boundary check'
  present "spec: app payload signature stays application work; checkpoint cannot pre-prove a future payload" "$SPEC" \
      'cannot pre-prove a future payload|remain application work|stays .{0,20}application. work'
  # NEGATIVE guard — the bespoke/authoritative QVI-owned AID->UTxO database framing
  #   must be WITHDRAWN, not asserted as a live requirement of Candidate A.
  forbid_pred "spec: Candidate A must NOT require a bespoke/authoritative QVI-owned AID->UTxO database (withdrawn — must be a falsifier/withdrawal only)" \
      "$SPEC" \
      '(requires?|needs?|depends on|must use)[^.]*(bespoke|exclusive|authoritative|QVI-owned|QVI-specific)[^.]*(database|directory|AID . ?(current-?)?UTxO index)' \
      '(framing|withdrawn|withdraw|falsifier|falsif|reject|eliminat|lacks|no longer|rather than|instead of|generic|neither|is not|does not|no bespoke|not[[:space:]])'

  # --- Universal re-authorization on rotation (normative) ------------------
  present "spec: universal re-authorization on rotation" "$SPEC" \
      'universal re-authorization|universal re-authori[sz]ation'
  present "spec: spent checkpoint is NOT available as a CIP-31 reference input (pending auths stale)" "$SPEC" \
      'spent checkpoint is not available as a CIP-31 reference input|not available as a[^.]*reference input'
  present "spec: every future action resolves + references the current checkpoint, AID/key sequence must match" "$SPEC" \
      'resolve[^.]*reference[^.]*current checkpoint|AID/key sequence[^.]*match|key sequence to match the datum'
  present "spec: cross-protocol lifecycle (Execute / Refresh-Re-sign / Cancel-Reclaim / Expire-Cleanup)" "$SPEC" \
      'Execute[^.]*Refresh[^.]*Cancel[^.]*Expire|Refresh/Re-sign[^.]*Cancel/Reclaim'
  present "spec: rotation does not erase bytes; value-bearing stale UTxOs need a current-AID reclaim path" "$SPEC" \
      'does not erase bytes|rotation[^.]*not[^.]*(erase|delete)[^.]*bytes'
  present "spec: distinguish historical credential evidence (ACDC issuance/TEL seals remain historical)" "$SPEC" \
      'historical credential evidence|issuance/TEL seals remain historical|remain historical evidence'

  # --- ACDC boundary correction (normative) --------------------------------
  present "spec: ACDC is not normally directly signed (issuance/TEL seal into issuer KEL)" "$SPEC" \
      'not normally directly signed|sealed into the issuer.s KEL|issuance[^.]*seal[^.]*KEL'
  present "spec: ACDC binding preserved through later key rotations" "$SPEC" \
      'preserv[^.]*verifiab[^.]*rotation|preserved through later key rotations|verifiab[^.]*through[^.]*rotation'
  present "spec: ACDC spec URL cited" "$SPEC" \
      'trustoverip.github.io/kswg-acdc-specification'
  present "spec: three-question authority split (A answers who authorizes now / ACDC was issued then / dApp authorizes action)" "$SPEC" \
      'who controls/authorizes for this AID now|was this credential[^.]*issued then|does that identity/credential authorize this action'
  present "spec: admission-cache split preserved (historical at admission; current checkpoint on subsequent actions)" "$SPEC" \
      'admission-cache split|historical credential-chain validation at admission'

  # --- Emergency freeze honesty + downstream residual ---------------------
  present "spec: emergency freeze (R-FRZ) separate mechanism preserved with honest contention/trust boundary" "$SPEC" \
      'R-FRZ|emergency freeze'
  present "spec: sovereign emergency path must not reintroduce a shared attacker-contendable UTxO (downstream residual)" "$SPEC" \
      'must not reintroduce a shared attacker-contendable UTxO|shared attacker-contendable UTxO'

  # --- Batched dApp fan-in -------------------------------------------------
  present "spec: batched dApp fan-in needs one reference input per distinct acting AID; measurement is an implementation gate" "$SPEC" \
      'one[^.]*reference input per[^.]*acting AID|per distinct acting AID'

  # --- Transient inception-cage lifecycle ---------------------------------
  present "spec: transient token minted tied to the consumed attempt input" "$SPEC" \
      'tied to the consumed attempt input'
  present "spec: Step preserves exactly one transient token" "$SPEC" 'preserves exactly one'
  present "spec: Finish burns-or-promotes the token exactly once" "$SPEC" \
      'burns?-or-promotes|burns/promotes|consumes[ -]and[ -]burns'
  present "spec: bounded deposit-funded timeout/reclaim path" "$SPEC" \
      'deposit-funded|bounded timeout|reclaim/burn'

  # --- Downstream consequences documented (not absorbed) ------------------
  for d in '#68' '#24' '#25' '#44'; do
    present "spec: downstream consequence $d documented" "$SPEC" "$d"
  done

  # --- Honesty boundaries kept --------------------------------------------
  present "spec: NOTE-013 (#99 Modify N not a checkpoint-advance batch bound)" "$SPEC" 'NOTE-013'
  present "spec: NOTE-018 (transient token vs steady token; Step/Finish != rotation)" "$SPEC" 'NOTE-018'
  present "spec: NOTE-017 (lane grindable; average != adversarial)" "$SPEC" 'NOTE-017'
  present "spec: live-smoke devnet limitation (maxTxExUnits / evalTxExUnits)" "$SPEC" \
      'maxTxExUnits|evalTxExUnits'
  present "spec: registration-pipeline vs rotation-advance measured at own boundaries" \
      "$SPEC" 'registration pipeline'
  present "spec: rotation advance measured separately"       "$SPEC" 'rotation advance'
  present "spec: disjoint transactions never summed"         "$SPEC" 'never sum|never summ|not[^.]*sum'

  # --- R-KEL classification preserved -------------------------------------
  present "spec: R-KEL preserved as on-chain checkpoint over settled R-ID" "$SPEC" \
      'checkpoint over settled R-ID'

  # --- Reopen: loss/fork semantics + superwatcher live-duty contract (NOTE-022) ---
  present "spec: NOTE-022 (reopen — normative loss/fork + superwatcher contract)" "$SPEC" 'NOTE-022'
  present "spec: reopen section — loss/fork semantics + superwatcher live-duty contract" "$SPEC" \
      'Loss / fork semantics and the superwatcher live-duty contract|superwatcher live-duty contract'
  present "spec: (1) KERI sole state machine; checkpoint is a projection, not a second sovereign history" "$SPEC" \
      'sole identity state machine'
  present "spec: (1) spend-linearized projection of current authority, not a second independently sovereign history" "$SPEC" \
      'spend-linearized projection of current authority|not a second[^.]*independently sovereign identity history'
  present "spec: (2) sync-lag honesty — old key stale in KERI; Cardano enforces only on successor/freeze/evidence" "$SPEC" \
      'Cardano enforcement changes only when a successor'
  present "spec: (2) NOT operationally stale everywhere immediately" "$SPEC" \
      'operationally stale everywhere immediately'
  present "spec: (3) superwatcher = permissionless cross-plane relayer + evidence submitter" "$SPEC" \
      'permissionless cross-plane relayer'
  present "spec: (3) superwatcher is NOT oracle/authority/custodian/backup/recovery/indexer" "$SPEC" \
      'not[^.]*(trusted oracle|identity authority|key custodian|backup service|recovery authority|authoritative indexer)'
  present "spec: (4) never chooses truth when cryptographic evidence is absent" "$SPEC" \
      'never chooses truth when cryptographic evidence is absent'
  present "spec: (5) loss/recovery — lost all next/recovery material is unrecoverable/abandonable" "$SPEC" \
      'lost current and all[^.]*(next|recovery) material[^.]*(no Cardano recovery|unrecoverable/abandonable)|unrecoverable/abandonable under this design'
  present "spec: (5) witness-threshold collusion — cannot manufacture a canonical truth branch" "$SPEC" \
      'cannot manufacture a canonical'
  present "spec: (6) fork/divergence — unreceipted local KEL fork has no accepted authority" "$SPEC" \
      'unreceipted[^.]*KEL fork[^.]*no accepted authority'
  present "spec: (6) KERI-ahead/Cardano-behind is sync lag, not a second valid identity branch" "$SPEC" \
      'synchronization lag, not a second valid identity'
  present "spec: (7) consumer contract fails closed once a later event/freeze/proof is presented" "$SPEC" \
      'fail closed[^.]*(later witnessed event|active freeze)'
  present "spec: (7) publish an anchoring-freshness policy/SLA; #92 invents no universal numeric timeout" "$SPEC" \
      'publish an anchoring-freshness'
  present "spec: (7) #92 does not invent one universal numeric timeout" "$SPEC" \
      'does not invent one universal numeric timeout|no universal numeric timeout'
  present "spec: (8) generic indexer boundary — liveness only, never identity truth; not an authoritative resolver" "$SPEC" \
      'not[^.]*(turned into an )?authoritative resolver'
}

# ============================================================================
# DECISION.md — sovereign machine-header contract
#   SELECTED_CANDIDATE=A ; REJECTED_CANDIDATES=B,C ; SELECTION_BASIS=sovereignty ;
#   plus the operator-ratification / invariant / B & C rejection reasons /
#   residual-risks / measurement-residual headers, and preservation of R-KEL +
#   #99 cage invariants. Sets DECISION_SELECTED for the negative guards.
# ============================================================================
check_decision_sovereign() {
  if [ ! -f "$DECISION" ]; then
    red "DECISION.md absent — the operator-ratified sovereign selection is not recorded"; return
  fi

  _sel=$(kv "$DECISION" 'SELECTED_CANDIDATE')
  case "$_sel" in
    A) : ;;
    "") red "DECISION.md missing 'SELECTED_CANDIDATE=A' machine header"; _sel="" ;;
    *)  red "DECISION.md SELECTED_CANDIDATE must be 'A' (operator-ratified sovereign selection); got '$_sel'"; _sel="" ;;
  esac
  DECISION_SELECTED="$_sel"

  # REJECTED must be exactly {B,C} — the complement of the sovereign A selection.
  _rej=$(kv "$DECISION" 'REJECTED_CANDIDATES')
  if [ -z "$_rej" ]; then
    red "DECISION.md missing 'REJECTED_CANDIDATES=' machine header"
  else
    _rej_norm=$(printf '%s' "$_rej" | tr ',;' '  ' | tr -s ' ')
    _n=0; _sb=0; _sc=0; _bad=0
    for r in $_rej_norm; do
      _n=$((_n+1))
      case "$r" in
        B) _sb=1 ;;
        C) _sc=1 ;;
        *) _bad=1 ;;
      esac
    done
    { [ $_n -eq 2 ] && [ $_sb -eq 1 ] && [ $_sc -eq 1 ] && [ $_bad -eq 0 ]; } \
      || red "DECISION.md REJECTED_CANDIDATES must be exactly 'B,C' (got '$_rej')"
  fi

  # Selection BASIS is sovereignty — not a throughput/capital/cost matrix.
  _basis=$(kv "$DECISION" 'SELECTION_BASIS')
  case "$_basis" in
    *[Ss]overeign*) : ;;
    "") red "DECISION.md missing 'SELECTION_BASIS=' machine header (must name sovereignty)" ;;
    *)  red "DECISION.md SELECTION_BASIS must name sovereignty (got '$_basis')" ;;
  esac

  # Required non-empty machine headers.
  for hkey in SELECTION_RULE OPERATOR_RATIFIED SOVEREIGNTY_INVARIANT B_REJECTION C_REJECTION RESIDUAL_RISKS MEASUREMENT_RESIDUAL; do
    _v=$(kv "$DECISION" "$hkey")
    [ -n "$_v" ] || red "DECISION.md missing/empty machine header '$hkey='"
  done

  # The B/C rejection reasons must be SOVEREIGN (not cost/throughput).
  present "DECISION: B rejected — shared/global UTxO serializes unrelated identities" "$DECISION" \
      '(shared|global|single)[^.]*(serial|contend|delay|unrelated)|serial[^.]*unrelated'
  present "DECISION: C rejected — grindable public lane / sovereignty depends on shard machinery" "$DECISION" \
      '(grind|public lane|lane[^.]*target|shard machinery|depend[^.]*shard)'
  present "DECISION: sovereignty invariant — unrelated AIDs cannot contend/serialize/delay" "$DECISION" \
      'unrelated[^.]*(cannot|never)[^.]*(contend|consume|serialize|delay)|unrelated-AID isolation'
  present "DECISION: operator ratification provenance (A-001)" "$DECISION" \
      'A-001|answers/A-001|operator[- ]?ratified'
  # MEASUREMENT_RESIDUAL must frame measurements as implementation-sizing/downstream,
  # NOT as the selection basis.
  present "DECISION: measurement residual = downstream A-implementation sizing / live-boundary (not selection evidence)" "$DECISION" \
      'implementation[- ]?sizing|live-boundary|downstream[^.]*(measure|sizing|gate)'
  present "DECISION: R-KEL classification + #99 cage invariants preserved" "$DECISION" \
      'R-KEL[^.]*preserv|preserv[^.]*R-KEL|#99[^.]*(invariant|cage)[^.]*preserv|preserv[^.]*#99'

  # NEGATIVE guard — the decision must NOT claim it rests on a measured
  # throughput/capital/cost-matrix win (that would misrepresent the sovereign basis).
  forbid_pred "DECISION: selection must NOT be represented as a measured throughput/capital/cost-matrix win" \
      "$DECISION" \
      '(select|chosen|basis|because|won|dominat)[^.]{0,60}(throughput|advances/block|capital[- ]?(lock|cap|budget)|cheapest|lowest[- ]?cost|cost[- ]?matrix|measured[^.]{0,20}(better|superior|dominant))' \
      '(sovereign|not[[:space:]]|never|residual|implementation|sizing|downstream|regardless|independent of|even if)'
}

# ============================================================================
# Canonical docs carry the sovereign per-AID decision + preserve R-KEL / #99.
# ============================================================================
check_canonical() {
  present "identity-model: §10 thread 8 resolved by the sovereign per-AID checkpoint selection" "$IM" \
      'thread 8[^.]*(decid|resolv|select|closed|sovereign|per-AID)|(per-AID|sovereign)[^.]*checkpoint[^.]*(select|decid|resolv)|#92[^.]*(select|decid)[^.]*(per-AID|sovereign|checkpoint)'
  present "identity-model: carries the per-AID sovereign (own uniquely-tokenized) checkpoint UTxO decision" "$IM" \
      'per-AID[^.]*(sovereign|own)[^.]*(UTxO|checkpoint)|sovereign[^.]*per-AID[^.]*checkpoint|uniquely[- ]?tokeni[sz]ed[^.]*UTxO'
  present "system-architecture: registry/checkpoint carries the #92 sovereign per-AID storage decision" "$SA" \
      '#92[^.]*(checkpoint|advance)[^.]*(per-AID|sovereign|storage|shape)|(per-AID|sovereign)[^.]*checkpoint[^.]*(decid|select)|#92[^.]*(decid|select)[^.]*(per-AID|sovereign)'

  # Preservation: R-KEL stays an on-chain checkpoint, NOT a watcher-attested mirror.
  present "system-architecture: R-KEL preserved as on-chain checkpoint over settled R-ID" \
      "$SA" 'R-KEL[^.]*checkpoint[^.]*R-ID|checkpoint over settled R-ID'
  forbid_pred "R-KEL must not be reclassified as a watcher-attested / mirror-root mirror" \
      "$SA" \
      'R-KEL[^.]{0,28}(watcher[- ]?(attested|computed)?[- ]?)?mirror' \
      'R-KEL[^.]{0,20}(not|never|isn.t|no[[:space:]]+longer|set[[:space:]]+apart|separat|apart|orthogonal|distinct|unlike|exclud)'
}

# ============================================================================
# DS2 — ACDC boundary (docs/acdc-primer.md). Positive: the issuance-seal
#   correction + spec URL. Negative: the live "signature under the issuer's
#   CURRENT key" claim must be corrected (exempted by a correction token).
# ============================================================================
check_ds2_acdc() {
  present "DS2 acdc-primer: ACDC not normally directly signed / sealed into the issuer KEL" "$AP" \
      'not normally directly signed|sealed into the issuer.?s KEL|issuance[^.]*seal[^.]*KEL|issuance seal'
  present "DS2 acdc-primer: verifiability preserved through later key rotations" "$AP" \
      'preserv[^.]*rotation|through later key rotation|remains? verifiable'
  present "DS2 acdc-primer: ACDC spec URL cited" "$AP" \
      'trustoverip.github.io/kswg-acdc-specification'
  forbid_pred "DS2 acdc-primer: must NOT claim an ACDC is verified by a signature under the issuer's CURRENT key" \
      "$AP" \
      'signing key was the issuer.?s current key|signed (directly )?by the issuer.?s current key|verif[^.]*signature[^.]*under[^.]*current key' \
      "$EXEMPT"
}

# ============================================================================
# DS3 — architecture current-auth + discovery. Positive: each surface carries a
#   sovereign #92 pointer. Negative: the load-bearing live "cage resolves current
#   identity by trie_key" claim in value-auth.md must be corrected/superseded.
# ============================================================================
check_ds3_arch() {
  require_pointer "DS3 overview: sovereign per-AID #92 pointer present"       "$ARCH_OVERVIEW"
  require_pointer "DS3 value-auth: sovereign per-AID #92 pointer present"     "$ARCH_VALUEAUTH"
  require_pointer "DS3 veridian-bridge: sovereign per-AID #92 pointer present" "$ARCH_VERIDIAN"
  require_pointer "DS3 identity-ops: sovereign per-AID #92 pointer present"   "$ARCH_IDENTITYOPS"
  require_pointer "DS3 index: sovereign per-AID #92 pointer present"          "$DOC_INDEX"
  forbid_pred "DS3 value-auth: must NOT present the cage resolving current identity by trie_key/windowed-root as live" \
      "$ARCH_VALUEAUTH" \
      'resolves the authorizing identity by .?trie_key|inclusion proof valid[^.]*root in the[^.]*window' \
      "$EXEMPT"
}

# ============================================================================
# DS4 — design trust/UX/DeFi/aid. Positive: each surface carries a sovereign #92
#   pointer. Negative: the live "value-write authorization against a key-state
#   snapshot at trie_key" claim in trust-model.md must be corrected/superseded.
# ============================================================================
check_ds4_design() {
  require_pointer "DS4 trust-model: sovereign per-AID #92 pointer present"      "$DSG_TRUST"
  require_pointer "DS4 user-experience: sovereign per-AID #92 pointer present"  "$DSG_UX"
  require_pointer "DS4 defi-gate: sovereign per-AID #92 pointer present"        "$DSG_DEFI"
  require_pointer "DS4 aid-model: sovereign per-AID #92 pointer present"        "$DSG_AID"
  forbid_pred "DS4 trust-model: must NOT present current-key authorization as a key-state snapshot read at trie_key" \
      "$DSG_TRUST" \
      'checks the key-state at .?trie_key. at that snapshot|authorization is valid for the specific block' \
      "$EXEMPT"
}

# ============================================================================
# DS5 — downstream-consequence specs (#24/#23) superseded-pointer + business-case
#   current-auth audit. Positive: each named surface carries a sovereign #92
#   pointer (the admission-cache credential plane + QVI hierarchy are preserved,
#   exempted, and recorded as legitimate).
# ============================================================================
check_ds5_downstream() {
  require_pointer "DS5 specs/24-keystate: superseded-by-#92 sovereign pointer present" "$SPEC24"
  require_pointer "DS5 specs/23-identity-auth: superseded-by-#92 sovereign pointer present" "$SPEC23"
  require_pointer "DS5 business-cases/index: sovereign per-AID #92 pointer present"    "$BC_INDEX"
  require_pointer "DS5 business-cases/regulated-defi: sovereign per-AID #92 pointer present" "$BC_REGDEFI"
  require_pointer "DS5 business-cases/institutional-contracts: sovereign per-AID #92 pointer present" "$BC_INST"
  require_pointer "DS5 business-cases/security-tokens: sovereign per-AID #92 pointer present" "$BC_SECURITY"
  require_pointer "DS5 business-cases/spo-delegation: sovereign per-AID #92 pointer present" "$BC_SPO"
}

# ============================================================================
# DS6 — loss/fork semantics + superwatcher live-duty contract (reopen, NOTE-022).
#   Positive: each surface carries the normative contract (KERI-sole-machine +
#   projection-not-second-history, honest sync-lag, superwatcher = permissionless
#   cross-plane relayer/evidence submitter, enumerated live duties, loss/recovery +
#   fork/divergence outcomes, fail-closed consumer contract, indexer boundary intact).
#   Negative: the retired convergence-enforcer-by-burn LIVE role, the "two independent
#   state machines" live claim, "old key stale everywhere immediately," the
#   "pending open thread 4" correspondence hedge, a live "convergence mechanism"
#   framing, and the "second, independently ordered record for divergence" claim must
#   all be gone (superseded/historical-exempt).
# ============================================================================
check_ds6_superwatcher() {
  # --- super-watcher.md: live-duty contract; legacy divergence-burn quarantined ---
  present "DS6 super-watcher: superwatcher = permissionless cross-plane relayer + evidence submitter" "$SW" \
      'permissionless cross-plane relayer'
  present "DS6 super-watcher: NOT oracle/authority/custodian/backup/recovery/indexer" "$SW" \
      'not[^.]*(trusted oracle|identity authority|key custodian|backup service|recovery authority|authoritative indexer)'
  present "DS6 super-watcher: enumerated live duties (relay / submit-proof / trigger-freeze / R-TEL)" "$SW" \
      'relay a fully witnessed anchoring|request or trigger the applicable freeze|submit[^.]*(duplicity|correspondence)[^.]*proof'
  present "DS6 super-watcher: never chooses truth when cryptographic evidence is absent" "$SW" \
      'never chooses truth when cryptographic evidence'
  present "DS6 super-watcher: legacy divergence-burn quarantined as a historical appendix" "$SW" \
      'historical appendix|legacy[^.]*divergence[- ]?burn'
  # NEGATIVE — the LIVE role must NOT be the convergence-enforcer-by-burn.
  forbid_pred "DS6 super-watcher: LIVE role must NOT be 'enforces convergence by punishing forks'" \
      "$SW" \
      'is a permissionless off-chain agent that monitors both registries and enforces convergence by punishing forks' \
      "$EXEMPT"
  # NEGATIVE — 'two independent state machines' must be superseded/historical, not live.
  forbid_pred "DS6 super-watcher: 'two independent state machines' must be superseded/historical" \
      "$SW" \
      'are two independent state machines' \
      "$EXEMPT"

  # --- identity-model.md: loss/recovery + fork/divergence + superwatcher + sync-lag ---
  present "DS6 identity-model: loss/recovery outcomes enumerated (no next/recovery ⇒ unrecoverable)" "$IM" \
      'unrecoverable/abandonable|lost current and all[^.]*(next|recovery) material'
  present "DS6 identity-model: witness-threshold collusion — cannot manufacture a canonical truth branch" "$IM" \
      'cannot manufacture a canonical'
  present "DS6 identity-model: fork/divergence outcomes (unreceipted fork ⇒ no authority; KERI-ahead = lag)" "$IM" \
      'unreceipted[^.]*KEL fork[^.]*no accepted authority|synchronization lag, not a second valid identity'
  present "DS6 identity-model: superwatcher = permissionless cross-plane relayer/evidence submitter" "$IM" \
      'permissionless cross-plane relayer|relayer and evidence submitter'
  present "DS6 identity-model: sync-lag honesty — Cardano enforces only on successor/freeze/evidence" "$IM" \
      'Cardano enforcement changes only when a successor|stale in KERI[^.]*Cardano[^.]*(enforce|change)[^.]*only'

  # --- trust-model.md: superwatcher relayer reframe + honest consumer contract ---
  present "DS6 trust-model: superwatcher = cross-plane relayer/evidence submitter" "$DSG_TRUST" \
      'cross-plane relayer|relayer and evidence submitter'
  present "DS6 trust-model: honest consumer contract — fail closed + anchoring-freshness policy/SLA" "$DSG_TRUST" \
      'fail[ -]?closed[^.]*(later|witnessed|freeze|proof|event)|anchoring-freshness[^.]*(policy|SLA)'
  # NEGATIVE — the old key must NOT be claimed operationally stale everywhere immediately.
  forbid_pred "DS6 trust-model: must NOT claim the old key is operationally stale everywhere immediately" \
      "$DSG_TRUST" \
      '(old|prior|stolen)[^.]*key[^.]*(immediately|instantly)[^.]*(stale|inert|invalid|revoked)[^.]*everywhere|(immediately|instantly)[^.]*(stale|inert|invalid|revoked) everywhere' \
      "$EXEMPT"

  # --- user-experience.md: loss/recovery + fork UX + honest consumer sync-lag ---
  present "DS6 user-experience: loss/recovery + fork user outcomes present" "$DSG_UX" \
      'lost[^.]*(private )?key|forgot[^.]*(AID|OOBI)|lost.*(next|recovery) material|unrecoverable'
  present "DS6 user-experience: honest — a Cardano-only consumer may still accept the old key during lag" "$DSG_UX" \
      'may (still )?accept the old[^.]*key|old checkpoint key[^.]*until[^.]*(successor|freeze|rotation)[^.]*land'

  # --- veridian-bridge.md: superwatcher live duties; correspondence a defined duty ---
  present "DS6 veridian-bridge: superwatcher live-duty contract (relayer/evidence/correspondence)" "$ARCH_VERIDIAN" \
      'cross-plane relayer|relayer and evidence submitter|correspondence[^.]*(proof|fraud)[^.]*(permissionless|freeze|defined)'
  # NEGATIVE — correspondence policing must NOT be hedged as "pending open thread 4".
  # Narrow exemption (NOT the full EXEMPT — its 'credential-plane' token co-occurs on
  # the live hedge line and would falsely neutralise this guard).
  forbid_pred "DS6 veridian-bridge: correspondence must NOT be hedged as 'pending open thread 4'" \
      "$ARCH_VERIDIAN" \
      'pending open thread 4' \
      'superseded|historical|no longer|formerly|resolved|defined (live )?duty|#92'

  # --- amaru-integration.md: superwatcher = cross-plane relayer/evidence, not 'convergence mechanism' ---
  present "DS6 amaru-integration: superwatcher = permissionless cross-plane relayer/evidence submitter" "$ARCH_AMARU" \
      'cross-plane relayer|relayer and evidence submitter'
  # NEGATIVE — must NOT frame the superwatcher as a live 'convergence mechanism/enforcement'
  # (the live "super watcher convergence mechanism is built directly on this property"
  # wraps across lines, so match the single-line "convergence mechanism is built" too).
  forbid_pred "DS6 amaru-integration: must NOT frame the superwatcher as a live convergence mechanism" \
      "$ARCH_AMARU" \
      'convergence mechanism is built|super.?watcher[^.]*convergence (mechanism|enforcement)|convergence (mechanism|enforcement)[^.]*super.?watcher' \
      "$EXEMPT"

  # --- roadmap.md: M5 reframed to the live-duty contract ---
  present "DS6 roadmap: superwatcher M5 = relayer/evidence/freeze/R-TEL live duties" "$DOC_ROADMAP" \
      'cross-plane relayer|relayer and evidence submitter|anchoring[^.]*freshness[^.]*(relay|evidence|freeze|R-TEL|polic)'

  # --- vlei.md: checkpoint is a projection the superwatcher relays, not a 'second record for divergence' ---
  forbid_pred "DS6 vlei: must NOT frame the checkpoint as a 'second, independently ordered record ... detect divergence'" \
      "$DSG_VLEI" \
      'second, independently ordered record' \
      "$EXEMPT"
}

# ============================================================================
# NEGATIVE guards (selection integrity for the sovereign decision).
# ============================================================================
negative_guards() {
  # (N1) A must be the selection — never B or C (the rejected, contended shapes).
  case "$DECISION_SELECTED" in
    A) : ;;
    "") : ;;  # absence already flagged by check_decision_sovereign
    *)  red "NEGATIVE: selected candidate '$DECISION_SELECTED' is not the operator-ratified sovereign A" ;;
  esac
  # (N2) The spec must not have re-opened the decision as 'unselected / pending evidence'
  #      on the current-authorization path (that would contradict the operator decision).
  forbid_pred "NEGATIVE: spec must not still frame the storage decision as unselected/open-pending-evidence" \
      "$SPEC" \
      '(no candidate is selected|remains? unselected|decision (is|stays) open)[^.]{0,40}(pending evidence|until[^.]*threshold|until[^.]*measur)' \
      '(superseded|no longer|was |previously|earlier draft|withdrawn|operator|sovereign|historical)'
}

# ============================================================================
# Deliverable exists (fail-safe hard stop for every mode)
# ============================================================================
if [ ! -f "$SPEC" ]; then
  echo "FAIL: missing $SPEC (RED — no #92 planning/decision record; expected on origin/main)"
  exit 1
fi

# ============================================================================
# Dispatch — staged targets (RED-before / GREEN-after) + `final`.
# ============================================================================
case "$MODE" in
  spec)
    layer1_spec
    ;;
  decision)
    layer1_spec
    check_decision_sovereign
    ;;
  ds1)  # canonical model (identity-model thread 8 + system-architecture)
    layer1_spec
    check_canonical
    ;;
  ds2)  # ACDC boundary correction
    layer1_spec
    check_ds2_acdc
    ;;
  ds3)  # architecture current-auth + discovery
    layer1_spec
    check_ds3_arch
    ;;
  ds4)  # design trust/UX/DeFi/aid
    layer1_spec
    check_ds4_design
    ;;
  ds5)  # downstream-consequence specs + business cases
    layer1_spec
    check_ds5_downstream
    ;;
  ds6)  # loss/fork semantics + superwatcher live-duty contract (reopen, NOTE-022)
    layer1_spec
    check_ds6_superwatcher
    ;;
  docs)  # the full documentation pass — all six DS groups
    layer1_spec
    check_decision_sovereign
    check_canonical
    check_ds2_acdc
    check_ds3_arch
    check_ds4_design
    check_ds5_downstream
    check_ds6_superwatcher
    ;;
  final)
    layer1_spec
    check_decision_sovereign
    check_canonical
    check_ds2_acdc
    check_ds3_arch
    check_ds4_design
    check_ds5_downstream
    check_ds6_superwatcher
    negative_guards
    ;;
  *)
    echo "accept.sh: unknown target '$MODE'"
    echo "usage: accept.sh [spec|decision|ds1|ds2|ds3|ds4|ds5|ds6|docs|final]"
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
