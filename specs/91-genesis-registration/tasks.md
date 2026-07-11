# Tasks — #91 genesis & registration decision record

Task IDs are numeric (`T91x`) so the `Tasks:` commit trailer satisfies the
finalization commit-gate. The decision slice is a `docs(...)` commit (trailer-
exempt by the gate) but still carries the trailer for the two-sided link.

## Orchestrator setup (done during intake)

- [X] T901 — Rebase `docs/91-genesis-registration` onto `origin/main`; resolve
  both deliverable files to merged evidence; drop the emptied obsolete commit;
  force-with-lease push. (branch == `origin/main` + gate.sh)
- [X] T902 — Add PR-life `gate.sh` (doc hygiene + tolerant-then-strict
  `accept.sh` hook). Commit `chore: add gate.sh`.
- [X] T903 — Author `specs/91-genesis-registration/{spec,plan,tasks}.md`,
  resolving NOTE-003 (projection boundary) and NOTE-004 (adjudication boundary).

## Slice 1 — the genesis/registration decision record  (driver + navigator, RED→GREEN)

Owned files: `specs/68-keystate-shape/identity-model.md`,
`specs/68-keystate-shape/system-architecture.md`,
`specs/91-genesis-registration/accept.sh`. One bisect-safe commit.

- [X] T911 — **RED.** Author `accept.sh` asserting the decision content markers
  below; demonstrate it fails on the pre-decision tree; log RED in `WIP.md`.
  Assertions (all from `spec.md`):
  - §7c present and selects **hybrid** (byte binding: crypto ≤1-chunk / attested
    >1-chunk; projection: attested + challengeable);
  - obsolete conclusion absent as the *current* stance (no live "genesis cannot be
    cryptographic" / "cannot be adjudicated on-chain" / "DOES NOT FIT");
  - NOTE-003 boundary named (byte binding ≠ semantic projection);
  - NOTE-004 remedy (b) named (permissionless challenge/freeze; trusted-adjudicated
    slash/unfreeze; deferred on-chain CESR projection verifier);
  - **decision 1** named = registration **oracle-gated**, challenge
    **permissionless** (and the two are distinguished); **decision 2** named =
    **MPFS-with-oracle**;
  - **teeth state machine** present: parameters `bond_reg`, `bond_chal`,
    `Δ_challenge`, `Δ_adjud`, `Δ_post`; the tier rule; false-challenge forfeiture;
    adjudication-timeout fail-safe freeze; provisional/active/frozen states;
  - **signed registration package** fields present (domain/version, full 32-byte
    AID, inception commitment, projected key-state, nonce/consumed-ref, tier) +
    controller & oracle signatures + witness-circularity note;
  - **evidence/integration separation** present: intermediate-value confinement
    phrased as a **required #24/#92 integration invariant** (not "is confined");
    explicit that #99 Modify N is **not** a genesis batch bound and the integrated
    path must be remeasured; **#99 insufficiency scoped to post-genesis mutation**,
    not genesis projection admission;
  - **NOTE-006 scope** present: byte binding prevents **inception-byte substitution**
    (not overall impersonation); **overall genesis authority attester-trusted** at
    the projection boundary; censorship **detectable only with signed-receipt/SLA**
    (else availability failure); on adjudication timeout **both bonds stay escrowed**
    + **indefinite frozen-state griefing under quorum failure** named;
  - **forbidden**: "objectively provable on-chain" (or close variant) adjacent to
    *projection* or *>1-chunk* binding; byte binding alone "prevents … impersonation";
    "cross-AID impersonation impossible" (or equivalent asserting form);
    "provable censorship"; "makes … freeze … safe"; any present-tense "is confined"
    implemented claim; any production-readiness / generic-KERI claim;
  - trust-assumption enumeration present (overall-genesis-authority, controller,
    witnesses, oracle/attester, challenge/fraud-proof, gating/censorship,
    slashing/bonds, adjudicator liveness/collusion, activation timing,
    on-chain-checkable-or-not);
  - #92, #68, #24 consequences present; #97 and #99 links present.
- [X] T912 — **GREEN (identity-model.md).** Rewrite §7c to the full hybrid decision:
  both axes; decisions 1 & 2; the teeth state machine; the signed-package shape; the
  evidence/integration separation; the trust enumeration; #92/#68/#24 consequences;
  honest capability language. Update the intro line and §10 open-thread 3 (genesis
  no longer "attested-only, pending"); update §7a to reflect #97 (≤1-chunk byte
  binding on-chain, projection attested) instead of the flat "genesis is not
  cryptographic"; update §8 cascade (#24/#68 bullets) to the new base case.
- [X] T913 — **GREEN (system-architecture.md).** Update §6 (decision note),
  §9 decision 1 (oracle-gated registration / permissionless challenge) & decision 2
  (MPFS-with-oracle) consistently with the shifted mandatory-attester premise, and
  the §3 R-KEL note. No decision left on the obsolete mandatory-attester-for-
  everything rationale.
- [X] T914 — **GREEN (completeness + gate).** `accept.sh` + `./gate.sh` pass; both
  docs internally consistent. Commit once: `docs(identity-model): select hybrid
  genesis — crypto byte binding + attested/challengeable projection (§7c)`, body
  trailer `Tasks: T911, T912, T913, T914`. **Executed:** 3 RED rounds (Q-001/002 +
  spot-check) and **3 GREEN passes** (2 blocks Q-003/Q-004; approval on pass 3).
  Q-003/Q-004 were **in-scope whole-file consistency
  fixes** — the navigator caught stale premises outside §7c (identity-model
  intro/§3/§7b/§8/§10; system-architecture §0/§1/§2/§9) that contradicted the
  selection; reconciling them is part of the same owned-file deliverable, not scope
  expansion. Committed at `8babc57`; accept.sh = 66 assertions + spot-check.

## Slice 2 — NOTE-008 canonical-doc consistency correction  (driver + navigator, RED→GREEN)

Epic-owner final audit found residual decision-consistency contradictions in the two
owned files. Same owned-file set (`identity-model.md`, `system-architecture.md`,
`accept.sh`). One bisect-safe commit. Not a #92 storage decision; not scope expansion.

- [X] T917 — **RED.** Strengthen `accept.sh` with assertions for the NOTE-008 fixes,
  demonstrate they fail on the current (8babc57) docs, log RED. Assertions:
  - identity-model §3 has **no unqualified "there is nothing to trust"** — must be
    qualified to *no additional watcher/oracle trust for post-genesis advances*
    (genesis projection stays attester-trusted per §7a/§7c);
  - system-architecture **R-KEL (identity) is not listed under the
    watcher-consensus/falsifiable "Proof-builder-anchored" mirror family** without an
    explicit checkpoint-vs-mirror separation; §0 closure Merkle-mirror framing
    **excludes identity R-KEL**;
  - the **R-MAP AID note is tier-scoped** (≤1-chunk byte binding on-chain / >1-chunk
    residual oracle mapping), not flat historical wording.
- [X] T918 — **GREEN.** Apply the three canonical-doc fixes:
  - `system-architecture.md` §0 (exclude identity R-KEL from the closure mirror
    framing); §3 (reclassify/separate the R-KEL on-chain checkpoint from the
    Proof-builder-anchored family + clarify relation to R-ID **without** selecting
    #92 storage; tier-scope the R-MAP AID note);
  - `identity-model.md` §3 (qualify "there is nothing to trust" to post-genesis
    advances only).
  `accept.sh` + `./gate.sh` pass. Commit once: `docs(identity-model): reconcile R-KEL
  classification + post-genesis trust qualification (NOTE-008)`, body trailer
  `Tasks: T917, T918`.

## Slice 3 — NOTE-010 whole-document R-KEL scan  (driver + navigator, RED→GREEN)

Epic-owner whole-diff scan found residual R-KEL-as-mirror statements beyond §0/§3.
Same owned-file set (`system-architecture.md`, `accept.sh`; `identity-model.md` only if
a stray R-KEL-mirror statement is found there). One bisect-safe commit. Not a #92
storage decision; not scope expansion; no economics change.

- [X] T919 — **RED.** Strengthen `accept.sh` (FR10-cont) so a live R-KEL-as-watcher-
  mirror classification in §4/§5/later summaries **fails**; demonstrate RED on
  `b22d794`. Assertions (section-scoped, negation-aware):
  - §4 does not call identity R-KEL a watcher mirror / does not map `closure
    identities → R-KEL` as a mirror root (closure computation preserved);
  - §5 does not group `R-KEL_N` with `R-TEL_N` as watcher-computed state roots under a
    single watcher-consensus trust layer (identity R-KEL = on-chain checkpoint over
    settled R-ID, freshness/submission concern);
  - §8/§11/concluding summaries do not classify R-KEL as a **proof-builder/
    watcher-attested/anchored mirror root** (grouped with R-MAP/R-ACDC as roots whose
    need/anchoring follows from Blake3/third-party credentials or the proof-builder layer);
  - **`anchored` polysemy (NOTE-011) — test BOTH directions:** (RED) §8 grouping R-KEL
    with R-MAP/R-ACDC as proof-builder-layer/credential-driven roots **fails**;
    (survive) "R-KEL is an on-chain checkpoint advanced/**anchored by witnessed seals**
    and **not** a watcher mirror" **passes** — do NOT reject legitimate checkpoint
    language just because `R-KEL` + `anchored` co-occur;
  - legitimate phrases survive ("R-KEL is not a watcher-attested mirror", "watch KELs
    to submit checkpoint advances"). No #92 storage assertion, no economics change.
- [X] T920 — **GREEN.** Reconcile `system-architecture.md` §4 (plane distinction),
  §5 (split state-root grouping / trust layer; preserve coordinator boundary for the
  actual mirror roots), §8/§11/conclusion (scope "anchored"/"mirror"/"KERI-mirror" to
  credential/external roots; retain watchers serving/submitting identity checkpoint
  material). `accept.sh` + `./gate.sh` pass. Commit once: `docs(system-architecture):
  scope R-KEL out of the watcher-mirror roots across §4/§5/summaries (NOTE-010)`, body
  trailer `Tasks: T919, T920`. **After push: STOP — do not drop gate / mark ready until
  the epic owner sends FINAL-AUDIT-ACCEPTED.**

## Slice 4 — NOTE-012 §11 anchored-root trust scope  (driver + navigator, RED→GREEN)

Epic-owner final audit found §11.1/§11.3 generic anchored-root/root-consensus trust
wording unscoped. Owned files: `system-architecture.md`, `accept.sh`. One bisect-safe
commit. **No economics/payer/reward redesign, no #92 storage.**

- [X] T921 — **RED.** Strengthen `accept.sh` (FR10-cont2) so removing the §11
  trust-layer scope is RED; demonstrate RED on `c495901`. Assertions (section-scoped,
  negation-aware, anchored-polysemy-aware per NOTE-011):
  - §11.1's proof-against-anchored-root correctness statement is scoped to the
    **credential/external mirror plane** (not a generic "the anchored root");
  - §11.3's "anchored roots + root-consensus", "provably-wrong anchored root" slashing,
    and "proofs against the root" are scoped to **credential/external mirror roots
    (R-TEL/R-ACDC/R-MAP)**, with identity R-KEL explicitly **outside** that
    root-consensus/slashing path;
  - legitimate "R-KEL … anchored by witnessed seals, not a watcher mirror" + "identity
    checkpoint advances are validator-checked; watchers serve/submit" survive.
  No #92 storage assertion, no economics assertion.
- [X] T922 — **GREEN.** Scope §11.1 (proof-against-anchored-root → credential/external
  mirror plane; preserve "identity checkpoint advances validator-checked, watchers
  serve/submit") and §11.3 (anchored roots / root-consensus / provably-wrong-root
  slashing / proof-checking → credential/external mirror roots; identity R-KEL outside
  the root-consensus/slashing path, freshness/submission concern). Check §11.4/§11.5 for
  the same generic-root sweep and scope if needed. Preserve the payer/reward mechanism
  verbatim. `accept.sh` + `./gate.sh` pass. Commit once: `docs(system-architecture):
  scope §11 anchored-root trust to the credential/external mirror plane (NOTE-012)`,
  body trailer `Tasks: T921, T922`. **After push: STOP — do not drop gate / mark ready
  until the epic owner sends FINAL-AUDIT-ACCEPTED.**

## Orchestrator finalization (post-slice, after review + push)

- [X] T915 — Update PR #95 body and issue #91: remove the obsolete premise, state
  the hybrid decision + the two boundaries, link #97/#98 and #99/#100. (`gh`, no
  file commit.)
- [X] T916 — Finalization audit (commit-gate over all commits + no open tasks);
  **stamp the satisfied `spec.md` success criteria and T915/T916** (do not leave
  completed criteria presented as open); drop `gate.sh` **last** (`chore: drop
  gate.sh (ready for review)`); `gh pr ready 95`; confirm fresh CI green (re-run if a
  spurious infra failure like "No space left on device" appears). Do **not** merge —
  epic owner performs guarded merge. Report `COMPLETE` on STATUS.
  **GATE: do not start T916 until the epic owner sends an explicit
  `FINAL-AUDIT-ACCEPTED` after the LATEST reviewed correction SHA is pushed
  (currently Slice 4 / NOTE-012; supersedes the earlier S3/NOTE-010 stop).**

## Explicitly out of scope (guard rails)

- No `onchain/`, `offchain/`, `spikes/`, `*.ak`, `*.hs`, manifests, hashes.
- No CESR parser / projection verifier; no adjudicator/governance-quorum code.
- No edits to sibling `specs/*/` (only `68-keystate-shape` + `91-genesis-registration`).
- Do not start #92; do not implement #24/#68.
