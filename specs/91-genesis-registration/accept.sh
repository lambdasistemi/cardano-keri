#!/bin/sh
# accept.sh — mechanical decision-acceptance check for cardano-keri #91.
#
# Asserts the FR1–FR8 decision content of the hybrid genesis/registration record
# is present in the two design docs, and that the obsolete premise and the
# over-strong phrasings NOTE-006/007 forbid are ABSENT. Authored RED-first: it
# fails on the pre-decision tree and passes only after the decision slice lands.
#
# Design nuance (see brief / spec FR9): the boundary statements the docs SHOULD
# carry are *negations* ("not on-chain-decidable", "off-chain-reproducible"). We
# do NOT forbid the bare substring — that would reject the legitimate negated
# boundary. Forbidden checks target only the positive/asserting forms; each uses
# an ADJACENCY-scoped negation guard (a negation must sit next to the asserting
# verb to exempt a line) so an unrelated `not` elsewhere on the line cannot mask
# a real forbidden assertion.
#
# Exit 0 = all assertions hold (GREEN). Exit 1 = one or more failed (RED).

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)
IM="$REPO/specs/68-keystate-shape/identity-model.md"
SA="$REPO/specs/68-keystate-shape/system-architecture.md"

fail=0

# --- helpers ---------------------------------------------------------------

# req LABEL FILE PATTERN  — assert PATTERN present in FILE (case-insensitive ERE).
req() {
  if ! grep -iEq "$3" "$2"; then
    printf 'FAIL[present]: %s\n' "$1"
    fail=1
  fi
}

# either LABEL PATTERN  — assert PATTERN present in IM *or* SA.
either() {
  if ! grep -iEq "$2" "$IM" "$SA"; then
    printf 'FAIL[present]: %s\n' "$1"
    fail=1
  fi
}

# forbid LABEL FILES SUBJECT_RE VERB_RE NEG_RE
#   flag lines in FILES matching VERB_RE and SUBJECT_RE but NOT NEG_RE.
#   VERB_RE should encode asserting adjacency; NEG_RE should be adjacency-scoped
#   (negation next to the verb), never a bare line-level "not".
forbid() {
  _label=$1; _files=$2; _subj=$3; _verb=$4; _neg=$5
  # shellcheck disable=SC2086
  _hits=$(grep -iE "$_verb" $_files 2>/dev/null \
          | grep -iE "$_subj" \
          | grep -ivE "$_neg" || true)
  if [ -n "$_hits" ]; then
    printf 'FAIL[forbid]: %s\n' "$_label"
    printf '  %s\n' "$_hits"
    fail=1
  fi
}

# forbid_lit LABEL FILES PATTERN — flag any line matching PATTERN (unconditional).
forbid_lit() {
  # shellcheck disable=SC2086
  _hits=$(grep -iE "$3" $2 2>/dev/null || true)
  if [ -n "$_hits" ]; then
    printf 'FAIL[forbid]: %s\n' "$1"
    printf '  %s\n' "$_hits"
    fail=1
  fi
}

# --- deliverables exist ----------------------------------------------------

[ -f "$IM" ] || { echo "FAIL: missing $IM"; exit 1; }
[ -f "$SA" ] || { echo "FAIL: missing $SA"; exit 1; }

# ============================================================================
# FR1 — §7c hybrid selection on both axes; §7a no longer "not cryptographic"
# ============================================================================
req "IM: §7c section heading present"            "$IM" '(^|[^0-9])7c[.:) ]'
req "IM: §7c selects a *hybrid* genesis"         "$IM" 'hybrid'
req "IM: byte binding cryptographic for single-chunk" "$IM" \
    '(single-chunk|1-chunk|1024)[^.]*(crypto|on-chain)'
req "IM: multi-chunk (>1-chunk) is attested"     "$IM" \
    '(multi-chunk|>[[:space:]]*1-chunk|>[[:space:]]*1024)[^.]*attest'
req "IM: Axis 2 — semantic projection is ATTESTED"        "$IM" \
    '(semantic )?projection[^.]*attest|attest[^.]*(semantic )?projection'
req "IM: Axis 2 — projection is challengeable / freeze-policed" "$IM" \
    'projection[^.]*(challeng|freeze|policed)|(challeng|freeze)[^.]*projection'
req "IM: §7a reflects #97 byte binding on-chain" "$IM" \
    '#97'

# ============================================================================
# FR2 — NOTE-003 projection boundary + NOTE-004 remedy (b); deferred verifier
# ============================================================================
either "NOTE-003 projection boundary named"      'NOTE-003'
either "NOTE-004 adjudication boundary named"     'NOTE-004'
either "byte binding distinguished from semantic projection" \
       'semantic projection'
either "NOTE-004 remedy (b): permissionless challenge/freeze" \
       'permissionless[^.]*(challenge|freeze)|(challenge|freeze)[^.]*permissionless'
either "NOTE-004 remedy (b): trusted-adjudicated slash/unfreeze" \
       '(trusted|governance|quorum)[^.]*(slash|unfreeze|adjudicat)|(slash|unfreeze)[^.]*(trusted|governance|quorum)'
either "deferred on-chain CESR projection verifier named" \
       '(deferred|future)[^.]*CESR[^.]*projection[^.]*verifier|CESR[^.]*projection[^.]*verifier[^.]*(defer|future)'

# ============================================================================
# FR4 / Decision 1 & 2 — oracle-gated registration, permissionless challenge;
#                        MPFS-with-oracle
# ============================================================================
either "Decision 1 labelled"                     'decision 1'
either "registration is oracle-gated"            '(oracle-gated|gated[^.]*oracle|oracle[^.]*gat)'
either "Decision 1 DISTINGUISHES gating from permissionless challenge (same clause)" \
       'gated.*permissionless|permissionless.*gated'
either "Decision 2 labelled"                      'decision 2'
either "registry model = MPFS-with-oracle"        'MPFS-with-oracle'
req    "SA: §6 decision note resolves MPFS-with-oracle" "$SA" 'MPFS-with-oracle'
req    "SA: §9 resolves decision 1 (gating vs permissionless)" "$SA" \
       '(oracle-gated|gated).*permissionless|permissionless.*(oracle-gated|gated)'
req    "SA: §3 R-KEL note reflects byte binding"  "$SA" \
       '(#97|byte binding|blake3\(icp\))'

# ============================================================================
# FR7 — teeth state machine: bonds, windows, tier rule, transitions, states
# ============================================================================
req "IM: bond_reg parameter"                     "$IM" 'bond_reg'
req "IM: bond_chal parameter"                     "$IM" 'bond_chal'
req "IM: Δ_challenge window"                       "$IM" 'Δ_challenge'
req "IM: Δ_adjud window"                           "$IM" 'Δ_adjud'
req "IM: Δ_post window"                            "$IM" 'Δ_post'
req "IM: Δ_challenge > 0 stated"                  "$IM" \
    'Δ_challenge[^.]*>[[:space:]]*0|Δ[[:space:]]*>[[:space:]]*0'
req "IM: leaf states provisional / active / frozen" "$IM" 'provisional'
req "IM: active state named"                       "$IM" '\bactive\b'
req "IM: frozen state named"                       "$IM" '\bfrozen\b'
req "IM: tier rule (bond_reg scales with attestation surface)" "$IM" \
    'tier rule|bond_reg\([^)]*1-chunk|bond_reg\([^)]*chunk'
req "IM: transition Register → provisional posts bond_reg" "$IM" \
    'bond_reg[^.]*provisional|provisional[^.]*bond_reg|register[^.]*provisional'
req "IM: transition Challenge (permissionless bonded) → frozen" "$IM" \
    'bond_chal[^.]*frozen|challenge[^.]*frozen|frozen[^.]*(bond_chal|challenge)'
req "IM: challenge blocks gated actions" "$IM" \
    'gated action|gated[^.]*block|block[^.]*gated'
req "IM: adjudicate UPHELD — bond_reg slashed / bounty / retracted" "$IM" \
    '(upheld|slash)[^.]*(bounty|slash|retract)|slash[^.]*bounty'
req "IM: adjudicate REJECTED — bond_chal forfeited to registrant, prior state" "$IM" \
    'forfeit[^.]*registrant|(rejected|false[- ]challenge)[^.]*forfeit'
req "IM: adjudicate TIMEOUT — both bonds escrowed (conjunct 1)" "$IM" \
    'both bonds[^.]*escrow'
req "IM: adjudicate TIMEOUT — leaf stays frozen / fail-safe (conjunct 2)" "$IM" \
    '((stays|stay|remains|remain)[^.]*frozen|frozen[^.]*fail-safe|fail-safe[^.]*frozen)'
req "IM: Activate after Δ_challenge (provisional → active)" "$IM" \
    'Δ_challenge[^.]*active|active[^.]*Δ_challenge|activate[^.]*Δ_challenge'
req "IM: Δ_post finite post-activation window / bond_reg release" "$IM" \
    'Δ_post[^.]*(post-activation|release|finite|retain)|(release|retain)[^.]*Δ_post'

# ============================================================================
# FR8 — signed registration package shape (full projected key-state tuple)
# ============================================================================
req "IM: package binds domain/version tag"        "$IM" '(domain/version|domain[- ]separation|protocol id)'
req "IM: package binds full 32-byte AID"          "$IM" '(32-byte|complete 32|full[^.]*AID)'
req "IM: package binds inception commitment"      "$IM" '(input_commitment|inception commitment)'
req "IM: package binds nonce / consumed ref"      "$IM" '(nonce|consumed[- ]output|consumed ref)'
req "IM: package carries the tier"                "$IM" '\btier\b'
# full projected key-state tuple (keys, kt, next_digest, witnesses, toad, native_sn)
req "IM: projected key-state — keys₀"             "$IM" '(keys.?0|keys₀)'
req "IM: projected key-state — threshold kt₀"     "$IM" '(kt.?0|kt₀)'
req "IM: projected key-state — next_digest₀"      "$IM" 'next_digest'
req "IM: projected key-state — witnesses₀"        "$IM" '(witnesses.?0|witnesses₀)'
req "IM: projected key-state — toad₀"             "$IM" 'toad'
req "IM: projected key-state — native_sn₀"        "$IM" '(native_sn|native sequence)'
# both signatures required, independently
req "IM: controller signs with claimed keys₀"     "$IM" \
    'controller[^.]*sign'
req "IM: oracle / attester co-signs"              "$IM" \
    '(oracle|attester)[^.]*co-?sign'
req "IM: witness-circularity note"                "$IM" '(circular|circularity)'

# ============================================================================
# FR5 — consequences for #92 / #68 / #24, without absorbing them
# ============================================================================
either "#97 evidence link present"                '#97'
either "#99 evidence link present"                '#99'
req "IM: #92 consequence — 2-tx Step/Finish checkpoint chain" "$IM" \
    '(2-tx|two-tx|step[- /]*finish|checkpoint (chain|step))'
req "IM: #92 consequence — cage-confined intermediate as REQUIRED invariant" "$IM" \
    '(required|must)[^.]*(#24|#92|integration)[^.]*invariant|invariant[^.]*(#24|#92)|(#24|#92)[^.]*invariant'
req "IM: #92 consequence — #99 Modify N is NOT the genesis batch bound" "$IM" \
    '(not|isn.t)[^.]*genesis[^.]*(batch )?bound|Modify[^.]*not[^.]*genesis|N[^.]*not[^.]*genesis[^.]*bound'
req "IM: #92 consequence — integrated path must be remeasured" "$IM" 'remeasur'
req "IM: #68 consequence — pin CESR serialization / datum-redeemer / projection fields" "$IM" \
    '#68[^.]*(serializ|datum|redeemer|projection|CESR|golden)|(serializ|golden)[^.]*#68'
req "IM: #68 consequence — Haskell AND Aiken golden parity"   "$IM" \
    '(haskell[^.]*aiken|aiken[^.]*haskell)[^.]*golden|golden[^.]*(haskell[^.]*aiken|aiken[^.]*haskell)|haskell/aiken[^.]*golden|golden[^.]*haskell/aiken'
req "IM: #24 consequence — re-cut base case (crypto byte-binding + challengeable projection + cage)" "$IM" \
    '#24[^.]*(base case|re-?cut|byte-binding genesis|cage)|(base case|re-?cut)[^.]*#24'

# ============================================================================
# Evidence / integration separation (honesty) + #99 scope
# ============================================================================
req "IM: #99 insufficiency scoped to post-genesis mutation" "$IM" \
    'post-genesis mutation'

# ============================================================================
# NOTE-006 scope + trust-assumption enumeration
# ============================================================================
req "IM: byte binding prevents inception-byte SUBSTITUTION (not impersonation)" "$IM" \
    'inception-byte substitution|substitution of[^.]*inception'
req "IM: overall genesis authority attester-trusted at projection boundary" "$IM" \
    'overall genesis authority'
req "IM: attester-trusted phrasing present"        "$IM" 'attester-trusted'
# censorship — both conjuncts required independently (not disjunctive):
req "IM: censorship detectable/attributable ONLY with signed-receipt/SLA" "$IM" \
    '(only|detectab|attributab)[^.]*(signed[- ]receipt|SLA)|(signed[- ]receipt|SLA)[^.]*(only|detectab|attributab)'
req "IM: censorship — otherwise an availability failure" "$IM" \
    'availability failure'
# adjudication timeout — both conjuncts required independently:
req "IM: adjudication timeout — both bonds stay escrowed" "$IM" \
    'both bonds[^.]*escrow'
req "IM: adjudication timeout — leaf stays frozen (fail-safe)" "$IM" \
    '((leaf )?(stays|stay|remains|remain)[^.]*frozen|frozen[^.]*fail-safe|fail-safe[^.]*frozen)'
req "IM: indefinite frozen-state griefing under quorum failure named" "$IM" \
    '(indefinite[^.]*frozen|frozen[^.]*grief)'
# scannable trust-assumption enumeration — distinctive multi-word labels
req "IM: trust enum — controller"                 "$IM" 'controller'
req "IM: trust enum — witnesses"                  "$IM" 'witnesses'
req "IM: trust enum — oracle/attester"            "$IM" '(oracle|attester)'
req "IM: trust enum — challenge / fraud-proof"    "$IM" '(fraud[- ]proof|challenge / fraud|challenge/fraud)'
req "IM: trust enum — gating / censorship"        "$IM" '(gating / censorship|gating/censorship|gating[^.]*censorship)'
req "IM: trust enum — slashing / bonds"           "$IM" '(slashing / bonds|slashing/bonds|slashing[^.]*bonds)'
req "IM: trust enum — adjudicator liveness/collusion" "$IM" \
    '(adjudicator[^.]*(liveness|collusion)|liveness[^.]*collusion)'
req "IM: trust enum — activation timing"          "$IM" 'activation timing'
req "IM: trust enum — objectively checkable on-chain (yes/no)" "$IM" \
    'objectively checkable on-chain'

# ============================================================================
# FR6 / FR9 — FORBIDDEN: obsolete premise (as the current stance)
# ============================================================================
forbid_lit "obsolete 'genesis is not cryptographic' as current stance" "$IM" \
    'genesis is not cryptographic|genesis cannot be cryptographic'
forbid_lit "obsolete 'cannot be adjudicated on-chain'" "$IM $SA" \
    'cannot be adjudicated on-chain'
forbid_lit "obsolete 'DOES NOT FIT' verdict" "$IM $SA" \
    'does not fit'
forbid_lit "obsolete 'attested-registration track' framing" "$IM" \
    'attested-registration track|attested-only'

# Stale universal premises that contradict the #91 hybrid selection. Correctly
# scoped statements (multi-chunk / tree / credential-plane / historical blake2b)
# survive via NEG_RE; only the flat universal assertions are flagged.
forbid_lit "flat 'base case no longer self-certifying on-chain' premise" "$IM $SA" \
    'no longer self-certifying|is not self-certifying on-chain'
forbid "universal 'cannot recompute Blake3 SAID on-chain' (unscoped)" \
    "$IM $SA" \
    '(blake3 said on-chain|recompute a[^.]*blake3)' \
    'cannot' \
    '(multi-chunk|tree|single-chunk|≤|<=|credential|#97|>[[:space:]]*1-chunk)'
forbid_lit "universal 'never Blake3' premise" "$IM $SA" \
    '\bnever blake3\b'

# ============================================================================
# FR6 / FR9 — FORBIDDEN: over-strong phrasings (asserting forms only).
# Each verb encodes asserting adjacency so a "not/never" breaks the match.
# ============================================================================
# projection / >1-chunk asserted objectively provable|checkable|decidable|verifiable on-chain.
forbid "projection/>1-chunk asserted objectively provable/checkable/decidable on-chain" \
    "$IM $SA" \
    '(projection|multi-chunk|>[[:space:]]*1-chunk|attested (digest|byte binding))' \
    '(is|are|becomes|remains|stays|it.?s|:)[[:space:]]+objectively (provable|checkable|decidable|verifiable) on-chain' \
    '(≤|<=|single-chunk)'

# byte binding alone "prevents/precludes/eliminates ... impersonation" (asserting).
# NEG exempts only when the negation sits adjacent to the verb.
forbid "byte binding alone 'prevents ... impersonation' (asserting synonym)" \
    "$IM $SA" \
    'impersonation' \
    '(prevent|preclude|stop|eliminat|bar|rule[- ]out)' \
    '((not|never|cannot|n.t|only|without|neither|nor)[[:space:]]+([a-z’'"'"'-]+[[:space:]]+){0,3}(prevent|preclude|stop|eliminat|bar|rule)|substitution,?[[:space:]]*not)'

# cross-AID / overall impersonation declared impossible/precluded/ruled-out.
# Negation-aware: "does not preclude impersonation" / "impersonation is not
# impossible" are exempted; the positive counterpart is flagged.
forbid "'impersonation impossible/precluded/ruled-out' (asserting form)" \
    "$IM $SA" \
    'impersonation' \
    '(impersonation[[:space:]]+(is[[:space:]]+|are[[:space:]]+|becomes[[:space:]]+)?(impossible|precluded|ruled[- ]out|eliminated|prevented)|impossible to impersonate|precludes?[[:space:]]+(all[[:space:]]+|any[[:space:]]+)?impersonation)' \
    '((not|never|cannot|n.t|no)[[:space:]]+([a-z-]+[[:space:]]+){0,3}(preclude|impossible|impersonat|eliminat|prevent|rule)|impersonation[[:space:]]+(is[[:space:]]+|are[[:space:]]+)(not|never))'

# "provable censorship" unqualified (asserting) — "provable only with ..." survives.
forbid "'provable censorship' unqualified (asserting)" \
    "$IM $SA" \
    '(censorship|refus)' \
    'provabl' \
    '(provable[[:space:]]+only|only[[:space:]]+([a-z]+[[:space:]]+){0,3}(with|when|via|if)|availability|receipt|sla|detectab|attributab|not provable)'

# "makes ... freeze ... safe" (asserting). "fail-safe" / "safe default" survive.
forbid "'makes ... freeze ... safe' (asserting)" \
    "$IM $SA" \
    '(freeze|grief)' \
    '\bsafe\b' \
    '(fail-safe|safe default|(not|never|no)[[:space:]]+([a-z]+[[:space:]]+){0,3}safe|does not make|mitigat)'

# present-tense "is/are confined" as an implemented fact (must be "MUST be confined").
forbid_lit "'is/are confined' as an implemented fact" "$IM $SA" \
    '\b(is|are) confined\b'

# production-readiness / generic-KERI interop claim.
forbid_lit "production-readiness claim" "$IM $SA" \
    'production[- ]read'
forbid_lit "generic-KERI interop claim" "$IM $SA" \
    'generic[- ]keri'

# ============================================================================
# FR10 / NOTE-008 — canonical-doc consistency correction (Slice 2).
# RED on 8babc57 (current HEAD docs); GREEN after the three fixes. NOT a #92
# storage-layout choice: these assert *classification/qualification* wording
# only, never a per-AID-UTxO vs trie physical-storage selection.
#
# Guards tightened per navigator Q-001: each positive check requires the
# *specific* intended wording (not a loose keyword), is negation-aware where a
# misclassifying/negated sentence could otherwise pass, and is scoped to the
# owning section (§0 / §3) so an out-of-section sentence cannot satisfy it.
# Section slices below are line-based: heading "## N." opens, next "## N."
# closes; the pattern must be satisfied on one physical line within the slice.
# ============================================================================

IM_S3=$(awk '/^## 3\./{f=1;next} /^## [0-9]/{f=0} f' "$IM")
SA_S0=$(awk '/^## 0\./{f=1;next} /^## [0-9]/{f=0} f' "$SA")
SA_S3=$(awk '/^## 3\./{f=1;next} /^## [0-9]/{f=0} f' "$SA")

# (1) identity-model.md §3: the bare "nothing to trust" overclaim must be
#     QUALIFIED to "no additional watcher/oracle trust for post-genesis
#     advances" (genesis projection stays attester-trusted per §7a/§7c). Two
#     sided: (a) any bare "no … to trust" line lacking that *specific*
#     qualification is flagged — so "nothing to trust in the oracle" still
#     fails; (b) the specific positive qualification must be present.
_n008_bare=$(printf '%s\n' "$IM_S3" | grep -iE 'no[a-z ]* to trust' \
             | grep -ivE 'no additional[^.]*(watcher|oracle)[^.]*trust[^.]*post-genesis' || true)
if [ -n "$_n008_bare" ]; then
  printf 'FAIL[forbid]: %s\n' "IM §3: unqualified 'nothing to trust' overclaim (must scope to no additional watcher/oracle trust for post-genesis advances)"
  printf '  %s\n' "$_n008_bare"
  fail=1
fi
if ! printf '%s\n' "$IM_S3" | grep -iEq \
     'no additional[^.]*(watcher|oracle)[^.]*trust[^.]*post-genesis|post-genesis[^.]*no additional[^.]*(watcher|oracle)[^.]*trust'; then
  printf 'FAIL[present]: %s\n' "IM §3: 'no additional watcher/oracle trust for post-genesis advances' qualification present"
  fail=1
fi

# (2) system-architecture.md §3: identity R-KEL SET APART from the
#     watcher-consensus "Proof-builder-anchored" mirror family — positive
#     classification, negation-aware (a "R-KEL is not set apart …" sentence fails).
if ! printf '%s\n' "$SA_S3" | grep -iEq 'R-KEL[^.]*set apart[^.]*(proof-builder|mirror)'; then
  printf 'FAIL[present]: %s\n' "SA §3: identity R-KEL set apart from the Proof-builder-anchored mirror family"
  fail=1
fi
_n008_kelneg=$(printf '%s\n' "$SA_S3" \
  | grep -iE 'R-KEL[^.]*(\bnot\b|\bnever\b|isn['"'"'’]t|\bis not\b)[^.]*(set apart|separat|reclassif)|(\bnot\b|\bnever\b)[^.]*(part of|within|member of)[^.]*(proof-builder|mirror)[^.]*R-KEL' || true)
if [ -n "$_n008_kelneg" ]; then
  printf 'FAIL[forbid]: %s\n' "SA §3: R-KEL classification must not be negated/misclassified"
  printf '  %s\n' "$_n008_kelneg"
  fail=1
fi

# (2b) STRUCTURAL (Q-002/Q-003): identity R-KEL must NOT remain a row inside the
#      Proof-builder-anchored mirror table specifically. Scoped to that ONE table
#      block (its "Proof-builder-anchored" heading through the end of its
#      contiguous "|"-row run) so a valid FR10 relocation — an R-KEL row in a
#      *separate* on-chain-checkpoint table, or a prose-only classification — is
#      NOT falsely rejected. FR10 forbids the row under the mirror family only,
#      not table representation as such.
_pba_table=$(awk '
  /Proof-builder-anchored/ {inpba=1}
  inpba && /^\|/ {intable=1; print; next}
  inpba && intable && !/^\|/ {exit}
' "$SA")
if printf '%s\n' "$_pba_table" | grep -qiE '^\|[[:space:]]*\**R-KEL\**[[:space:]]*\|'; then
  printf 'FAIL[forbid]: %s\n' "SA §3: identity R-KEL still a row inside the Proof-builder-anchored mirror table (must be relocated out)"
  fail=1
fi

# (3) system-architecture.md §3: identity R-KEL positively RELATED to the native
#     R-ID registry (checkpoint over the R-ID-seeded key-state) — storage-neutral,
#     negation-aware ("R-ID unrelated to R-KEL" fails).
if ! printf '%s\n' "$SA_S3" | grep -iEq \
     'R-KEL[^.]*(checkpoint|advance|advances|over|seeded|seeds)[^.]*R-ID|R-ID[^.]*(seed|seeds|register|registry|key-state)[^.]*R-KEL'; then
  printf 'FAIL[present]: %s\n' "SA §3: identity R-KEL related to the native R-ID registry (checkpoint over the R-ID seeds)"
  fail=1
fi
_n008_idneg=$(printf '%s\n' "$SA_S3" \
  | grep -iE 'R-KEL[^.]*(\bnot\b|\bnever\b|isn['"'"'’]t|\bis not\b|\bunrelated\b|\bindependent\b)[^.]*(over|checkpoint|advance|advances|seed|seeds|seeded|related|register|registry|key-state)[^.]*R-ID|R-ID[^.]*(\bnot\b|\bnever\b|isn['"'"'’]t|\bis not\b|\bunrelated\b|\bindependent\b)[^.]*(over|checkpoint|advance|advances|seed|seeds|seeded|related|register|registry|key-state)[^.]*R-KEL|R-KEL[^.]*(\bunrelated\b|not related|independent of)[^.]*R-ID|R-ID[^.]*(\bunrelated\b|not related|independent of)[^.]*R-KEL' || true)
if [ -n "$_n008_idneg" ]; then
  printf 'FAIL[forbid]: %s\n' "SA §3: R-KEL↔R-ID relation must be positive (no 'not over'/unrelated/independent)"
  printf '  %s\n' "$_n008_idneg"
  fail=1
fi

# (4) system-architecture.md §0 ONLY: the closure Merkle-mirror framing EXCLUDES
#     identity R-KEL. Scoped to §0 so a §3 exclusion cannot satisfy it.
if ! printf '%s\n' "$SA_S0" | grep -iEq 'R-KEL[^.]*exclud[a-z]*[^.]*mirror|exclud[a-z]*[^.]*mirror[^.]*R-KEL'; then
  printf 'FAIL[present]: %s\n' "SA §0: closure Merkle-mirror framing excludes identity R-KEL"
  fail=1
fi
# negation-aware (Q-002): reject "R-KEL must not be excluded …" and its inverse.
_n008_s0neg=$(printf '%s\n' "$SA_S0" \
  | grep -iE 'R-KEL[^.]*(\bnot\b|\bnever\b|isn['"'"'’]t|\bis not\b)[^.]*exclud|exclud[a-z]*[^.]*(\bnot\b|\bnever\b)[^.]*(from )?(the )?(closure|merkle|mirror)?[^.]*R-KEL' || true)
if [ -n "$_n008_s0neg" ]; then
  printf 'FAIL[forbid]: %s\n' "SA §0: R-KEL mirror-exclusion must not be negated (no 'must not be excluded')"
  printf '  %s\n' "$_n008_s0neg"
  fail=1
fi

# (5) system-architecture.md §3 ONLY: the R-MAP AID note is TIER-SCOPED — the
#     SAME R-MAP row must carry BOTH tiers (≤1-chunk byte binding on-chain /
#     >1-chunk residual oracle mapping). R-MAP adjacency required, so the R-KEL
#     row's tier wording cannot satisfy it.
if ! printf '%s\n' "$SA_S3" | grep -iE 'R-MAP' \
     | grep -iEq '1-chunk[^.]*(byte binding|on-chain)[^.]*>[^.]*1-chunk[^.]*residual[^.]*(oracle|map)'; then
  printf 'FAIL[present]: %s\n' "SA §3: R-MAP AID note tier-scoped (R-MAP row: ≤1-chunk byte binding on-chain / >1-chunk residual oracle mapping)"
  fail=1
fi
# negation-aware (Q-002): on the R-MAP row, neither tier clause may be negated —
# reject "byte binding is not on-chain" and "residual oracle mapping is not required".
_n008_mapneg=$(printf '%s\n' "$SA_S3" | grep -iE 'R-MAP' \
  | grep -iE '(\bnot\b|\bnever\b|n['"'"'’]t)[^.]*(on-chain|residual|byte binding|required|mapping)|(on-chain|residual|byte binding|mapping|required)[^.]*(\bis\b|\bare\b|stays|\bbe\b)?[[:space:]]*(\bnot\b|\bnever\b|n['"'"'’]t)' || true)
if [ -n "$_n008_mapneg" ]; then
  printf 'FAIL[forbid]: %s\n' "SA §3: R-MAP tier clauses must not be negated (positive on-chain / residual-oracle claims required)"
  printf '  %s\n' "$_n008_mapneg"
  fail=1
fi

# --- verdict ---------------------------------------------------------------

if [ "$fail" -ne 0 ]; then
  echo "accept.sh: FAIL (decision content not satisfied)"
  exit 1
fi
echo "accept.sh: OK (hybrid genesis/registration decision record satisfied)"
exit 0
