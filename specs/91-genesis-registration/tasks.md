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
  Assertions:
  - identity-model §7c present and selects **hybrid** (byte binding: crypto
    ≤1-chunk / attested >1-chunk; projection: attested + challengeable);
  - the obsolete conclusion is absent as the *current* stance (no live
    "genesis cannot be cryptographic" / "cannot be adjudicated on-chain" /
    "DOES NOT FIT" framing);
  - NOTE-003 boundary named (byte binding ≠ semantic projection);
  - NOTE-004 remedy named (permissionless challenge/freeze; trusted-adjudicated
    slash/unfreeze; deferred on-chain CESR projection verifier);
  - **forbidden**: the phrase "objectively provable on-chain" (or close variant)
    adjacent to *projection* or *>1-chunk* binding;
  - trust-assumption enumeration present (controller, witnesses, oracle/attester,
    challenge/fraud-proof, gating/censorship, slashing/bonds, activation timing,
    on-chain-checkable-or-not);
  - #92, #68, #24 consequences present; #97 and #99 links present;
  - no production-readiness / generic-KERI claim.
- [ ] T912 — **GREEN (identity-model.md).** Rewrite §7c to the hybrid decision;
  update the intro line and §10 open-thread 3 (genesis no longer "attested-only,
  pending"); update §7a so it reflects #97 (≤1-chunk byte binding now on-chain,
  projection still attested) instead of the flat "genesis is not cryptographic";
  update §8 cascade (#24/#68 bullets) to the new base case.
- [ ] T913 — **GREEN (system-architecture.md).** Update §6 (decision note),
  §9 decisions 1 (gating) & 2 (registry) consistently with the hybrid decision and
  its shifted mandatory-attester premise, and the §3 R-KEL note. No decision left
  asserting the obsolete mandatory-attester rationale.
- [ ] T914 — **GREEN (content completeness).** Ensure §7c contains the single
  scannable trust-assumption enumeration and the explicit #92/#68/#24 consequences
  (without absorbing them) and honest capability language; `accept.sh` + `./gate.sh`
  pass. Commit once: `docs(identity-model): select hybrid genesis — crypto byte
  binding + attested/challengeable projection (§7c)`, body trailer
  `Tasks: T911, T912, T913, T914`.

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
