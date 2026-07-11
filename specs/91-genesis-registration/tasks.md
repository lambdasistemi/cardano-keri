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

- [ ] T911 — **RED.** Author `accept.sh` asserting the decision content markers
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
- [ ] T912 — **GREEN (identity-model.md).** Rewrite §7c to the full hybrid decision:
  both axes; decisions 1 & 2; the teeth state machine; the signed-package shape; the
  evidence/integration separation; the trust enumeration; #92/#68/#24 consequences;
  honest capability language. Update the intro line and §10 open-thread 3 (genesis
  no longer "attested-only, pending"); update §7a to reflect #97 (≤1-chunk byte
  binding on-chain, projection attested) instead of the flat "genesis is not
  cryptographic"; update §8 cascade (#24/#68 bullets) to the new base case.
- [ ] T913 — **GREEN (system-architecture.md).** Update §6 (decision note),
  §9 decision 1 (oracle-gated registration / permissionless challenge) & decision 2
  (MPFS-with-oracle) consistently with the shifted mandatory-attester premise, and
  the §3 R-KEL note. No decision left on the obsolete mandatory-attester-for-
  everything rationale.
- [ ] T914 — **GREEN (completeness + gate).** `accept.sh` + `./gate.sh` pass; both
  docs internally consistent. Commit once: `docs(identity-model): select hybrid
  genesis — crypto byte binding + attested/challengeable projection (§7c)`, body
  trailer `Tasks: T911, T912, T913, T914`.

## Orchestrator finalization (post-slice, after review + push)

- [ ] T915 — Update PR #95 body and issue #91: remove the obsolete premise, state
  the hybrid decision + the two boundaries, link #97/#98 and #99/#100. (`gh`, no
  file commit.)
- [ ] T916 — Finalization audit; drop `gate.sh` (`chore: drop gate.sh (ready for
  review)`); `gh pr ready 95`; confirm fresh CI green. Do **not** merge — epic
  owner performs guarded merge. Report `COMPLETE` on STATUS.

## Explicitly out of scope (guard rails)

- No `onchain/`, `offchain/`, `spikes/`, `*.ak`, `*.hs`, manifests, hashes.
- No CESR parser / projection verifier; no adjudicator/governance-quorum code.
- No edits to sibling `specs/*/` (only `68-keystate-shape` + `91-genesis-registration`).
- Do not start #92; do not implement #24/#68.
