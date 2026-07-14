# Tasks — #92 R-KEL checkpoint advance-storage & contention model (sovereign decision)

Task IDs are numeric (`T92NN`) so the `Tasks:` commit trailer satisfies the
finalization commit-gate. **The storage-shape decision is made** (operator-ratified
sovereign Candidate A, `answers/A-001-thresholds.md`, NOTE-021). The ticket owner
`%1292` authors the ticket-local artifacts (spec/plan/tasks/accept.sh/DECISION.md);
the **canonical / non-ticket-owned documentation** edits are **reviewed
driver+navigator slices** (`%1291` driver Opus 4.8 high; `%1293` navigator Codex
gpt-5.6-sol high). The pair does **not** push — the ticket owner verifies the exact
committed SHA (`accept.sh ds<N>` RED-before → GREEN-after, plus `./gate.sh`) and
pushes.

## Bootstrap (ticket owner — done)

- [X] T92-B1 — Clean start; bootstrap worktree + branch `docs/92-checkpoint-contention`.
- [X] T92-B2 — Add PR-life `gate.sh`; open draft PR #104. `chore: add gate.sh` (`b14d4c3`).
- [X] T92-B3 — Author `spec.md` (planning record; superseded framing at `fdc0818`).
- [X] T9201 — Gate-lifecycle commit `chore(92): make acceptance gate tolerant until
  decision` (`684e842`).
- [X] T9200 — Initial planning commit `docs(92): add checkpoint-contention plan,
  tasks, and RED acceptance skeleton` (`fdc0818`).

## Slice 0 — sovereign-decision ticket-owner artifacts (ticket owner; this run)

Amend the ticket-owned artifacts to the operator-ratified sovereign decision. One
ticket-owner commit: `docs(92): select the sovereign per-AID checkpoint (Candidate A)
— decision + acceptance contract`, `Tasks: T9202` (T9200 already landed at `fdc0818`).

- [X] T9202 — Sovereign-decision ticket-owned artifacts complete (spec.md, DECISION.md,
  accept.sh, plan.md, tasks.md). Detail (non-task):
  - `spec.md` reframed from "open pending evidence" to the **sovereign decision**: the
    Operator-decision section (sovereignty/unrelated-AID-isolation invariant; B rejected
    = shared/global UTxO serializes unrelated identities; C rejected = grindable public
    lane / sovereignty-depends-on-shard; A selected = own uniquely-tokenized UTxO);
    **universal re-authorization** (spent checkpoint not a CIP-31 ref input; every future
    action re-references the current checkpoint + matches AID/key sequence;
    Execute/Refresh-Re-sign/Cancel-Reclaim/Expire lifecycle; rotation does not erase
    bytes); the **indexer/discovery trust boundary** (Plutus cannot query the global
    UTxO set; resolver supplies the outref; stale outref fails ledger validation →
    refresh; outage blocks liveness not authority); the **ACDC boundary correction**
    (not normally directly signed; sealed into the issuer KEL; preserved through
    rotations; spec URL; the three-question split; the admission-cache split; the
    historical-vs-current-action split in the downstream-trust / user-story bullets);
    the **emergency-freeze residual**; **batched fan-in** (one CIP-31 ref input per
    acting AID); the matrix/evidence/measurement sections reframed as **A-implementation
    sizing (downstream), not selection**; FR2/success-criteria/out-of-scope flipped;
    NOTE-021 added; NOTE-015/016 marked superseded/rescoped.
  - `DECISION.md` authored (ticket-owned): the sovereign machine headers
    `SELECTED_CANDIDATE=A`, `REJECTED_CANDIDATES=B,C`, `SELECTION_BASIS=sovereignty`,
    `SELECTION_RULE`, `OPERATOR_RATIFIED` (A-001), `SOVEREIGNTY_INVARIANT`, `B_REJECTION`,
    `C_REJECTION`, `RESIDUAL_RISKS`, `MEASUREMENT_RESIDUAL`, `RKEL_CLASSIFICATION`,
    `CAGE_INVARIANTS`; the selected/rejected write-ups; residual risks; preservation.
  - `accept.sh` rewritten to the sovereign contract: targets `spec` / `decision` /
    `ds1` / `ds2` / `ds3` / `ds4` / `ds5` / `docs` / `final`. `spec` + `decision` GREEN
    at this commit; `ds1..ds5` + `docs` + `final` fail-safe **RED** until the
    documentation slices land. Removed the B/C measurement-contest gates
    (thresholds/matrix/ordering/smoke/cross-bound refs). `sh -n` clean, `chmod +x`.
  - `plan.md`, `tasks.md` (this file): the sovereign structure, exact owned-file set,
    DS1–DS5 dispositions, the sovereign commit history.

## DS1 — canonical model (reviewed pair; `accept.sh ds1` RED→GREEN)

Owned files: `specs/68-keystate-shape/identity-model.md`,
`specs/68-keystate-shape/system-architecture.md`. One bisect-safe commit.
`docs(92): resolve identity-model thread 8 + system-architecture to the sovereign
per-AID checkpoint`, `Tasks: T9210`.

- [ ] T9210 — **Correct.** Resolve `identity-model.md` §10 **thread 8** (per-`cesr_aid`
  UTxO vs MPFS trie) to the **sovereign per-AID uniquely-tokenized checkpoint UTxO**
  (Candidate A, operator-ratified sovereignty invariant); update the §7c consequence
  line ("the trie-vs-per-AID-UTxO storage shape stays #92's call" → decided) and the
  §3/§6 R-KEL/keystate note. Carry the decision into `system-architecture.md` (§3 R-KEL
  note + §6 registry). **Preserve** the R-KEL on-chain-checkpoint classification (NOT a
  watcher mirror — `check_canonical`'s forbid guard) and the #99 cage invariants; do
  **not** reopen the #91 logical decisions. RED-before / GREEN-after `accept.sh ds1`.

## DS2 — ACDC boundary correction (reviewed pair; `accept.sh ds2` RED→GREEN)

Owned file: `docs/acdc-primer.md`. One bisect-safe commit.
`docs(acdc): correct the ACDC issuance-seal boundary (not signed under current keys)`,
`Tasks: T9211`.

- [ ] T9211 — **Correct.** Rewrite the "signed by the issuer's current key / signing
  key was the issuer's current key at issuance" claim (L54–56): an ACDC is **not
  normally directly signed**; its **issuance / TEL state event is sealed into the
  issuer's KEL**, binding it to the **key state at that historical change** and
  **preserved through later rotations** — cite
  https://trustoverip.github.io/kswg-acdc-specification/. Correct the "Issuer key is
  current | Layer-1 AID registry proof" table row (L194) to the three-question split
  (the sovereign checkpoint answers *who authorizes now*; the ACDC issuance-seal answers
  *issued then, unrevoked now*). **Preserve** the admission-cache credential-plane
  `trie_key` usage (L200–201). RED-before / GREEN-after `accept.sh ds2` (positive
  issuance-seal markers + the negative guard on the "current key" claim).

## DS3 — architecture current-auth + discovery (reviewed pair; `accept.sh ds3` RED→GREEN)

Owned files: `docs/architecture/overview.md`, `docs/architecture/value-auth.md`,
`docs/architecture/veridian-bridge.md`, `docs/architecture/identity-ops.md`,
`docs/index.md`. One bisect-safe commit.
`docs(architecture): reframe current-auth + discovery to the sovereign per-AID
checkpoint`, `Tasks: T9212`.

- [ ] T9212 — Per-file disposition:
  - `value-auth.md` — **correct/supersede**: the cage "resolves the authorizing
    identity by `trie_key`" + "inclusion proof valid … against a root in the window"
    current-authorization path → the **sovereign per-AID checkpoint reference** (read
    the AID's own checkpoint UTxO via CIP-31 ref input; delta-0 rotation invalidates
    pending authorizations). Neutralise the negative-guard line (rewrite or add the
    superseded/#92 forward pointer). **Preserve** freeze-registry mechanics with the
    honest attacker-contendable note.
  - `overview.md` — **correct** the high-level trust summary to sovereign per-AID +
    generic discovery; **superseded-pointer** on the Layer-1 MPF-trie / sliding-window
    registry mechanics (mechanical re-cut is downstream #24).
  - `veridian-bridge.md` — **superseded-pointer**: the SDK/redeemer/inclusion-proof
    flow is the old #24 shape; add the #92 sovereign-per-AID forward pointer (re-cut
    downstream). Freeze-registry honesty note.
  - `identity-ops.md` — **extend** the existing 2026-07-09 supersede banner with the
    #92 sovereign per-AID storage decision pointer.
  - `index.md` — **annotate** the registry mermaid + `trie_key` framing with the #92
    sovereign per-AID pointer (L65 partial supersede already present).
  - Each file must carry the `accept.sh ds3` sovereign `#92` forward-pointer marker.

## DS4 — design trust/UX/DeFi/aid (reviewed pair; `accept.sh ds4` RED→GREEN)

Owned files: `docs/design/trust-model.md`, `docs/design/user-experience.md`,
`docs/design/defi-gate.md`, `docs/design/aid-model.md`. One bisect-safe commit.
`docs(design): reframe trust/UX/DeFi/aid current-auth to sovereign discovery`,
`Tasks: T9213`.

- [ ] T9213 — Per-file disposition:
  - `trust-model.md` — **correct**: "value-write authorization against a key-state
    snapshot … checks the key-state at `trie_key` at that snapshot" → the **sovereign
    per-AID checkpoint reference**; the "KEL-replay-authoritative cesr_aid→trie_key
    resolution" → **generic asset-name discovery** (no KEL replay in hot actions).
    Neutralise the negative-guard line. **Preserve** historical credential admission.
  - `user-experience.md` — **correct** the "What you can trust (with KEL replay)"
    table + `trie_key`/freeze framing to sovereign per-AID + generic discovery;
    **preserve** the KEL-for-historical-credential admission split.
  - `defi-gate.md` — **correct** "Issuer key is current | Layer-1 AID registry proof"
    → the sovereign checkpoint answers current authority; **preserve** the
    credential-chain MPF proofs as the admission plane (admission-cache split).
  - `aid-model.md` — **targeted pointer**: mostly legitimate genesis binding /
    front-run defense (preserve); the `trie_key`-as-current-cage-auth framing gets the
    sovereign per-AID pointer (L119–120 partial supersede already present).
  - Each file must carry the `accept.sh ds4` sovereign `#92` forward-pointer marker.

## DS5 — downstream-consequence specs + business-case audit (reviewed pair; `accept.sh ds5` RED→GREEN)

Owned files: `specs/24-keystate/spec.md`, `specs/23-identity-auth/spec.md`,
`docs/design/business-cases/{index,institutional-contracts,regulated-defi,security-tokens,spo-delegation}.md`.
One bisect-safe commit.
`docs(92): superseded-pointer #24/#23 + business-case current-auth audit`,
`Tasks: T9214`.

- [ ] T9214 — Per-file disposition:
  - `specs/24-keystate/spec.md`, `specs/23-identity-auth/spec.md` —
    **superseded-pointer**: the single-registry + MPF-trie + depth-10 window /
    `identity_root` inclusion is the Candidate-B legacy the sovereign decision re-cuts;
    add a precise **superseded + forward-pointer** disposition to the #92 sovereign
    per-AID decision (the mechanical re-cut is downstream #24/#23, not done here).
  - `business-cases/index.md`, `regulated-defi.md`, `institutional-contracts.md`,
    `security-tokens.md`, `spo-delegation.md` — **audit**: **preserve** the
    admission-cache credential-plane `trie_key` and the GLEIF→QVI→LE hierarchy (record
    why each untouched occurrence is legitimate/historical); **correct / superseded-
    pointer** the current-actor "L1 registry proof / `trie_key` Active / cur_pubkey
    matches signer" resolution to the sovereign per-AID checkpoint.
  - Each named file must carry the `accept.sh ds5` sovereign `#92` forward-pointer
    marker; each preserved (untouched-mechanism) occurrence has a recorded reason.

## Orchestrator finalization (ticket owner; after all DS slices + epic acceptance)

- [ ] T92-F1 — Update PR #104 body + issue #92: state the **sovereign per-AID
  (Candidate A)** decision, link #97/#99, note R-KEL classification + #99 invariants
  preserved, and the honest measurement / R-FRZ residuals. (`gh`, no file commit.)
- [ ] T92-F2 — Finalization audit (commit-gate over all commits; no open tasks; stamp
  satisfied `spec.md` success criteria); confirm `accept.sh final` GREEN + `./gate.sh`
  GREEN + fresh CI green; make `gate.sh` `final` strict, then drop `gate.sh`
  (`chore: drop gate.sh (ready for review)`); `gh pr ready 104`. **Do not merge** — the
  epic owner performs the guarded merge. **GATE: finalization runs only after explicit
  epic-owner acceptance.** Report `COMPLETE`.

## Explicitly out of scope (guard rails)

- **Re-opening the storage-shape selection** (decided — Candidate A, sovereignty).
- **Performing the Candidate-A implementation-sizing measurements / building a
  validator prototype**, or any B/C comparison measurement — downstream, behavior-
  changing, not authored here.
- **Re-cutting the emergency-freeze (R-FRZ)** mechanism — a downstream residual.
- **Mechanically re-cutting** the #24/#23 validator/redeemer/SDK shapes — downstream;
  #92 adds a superseded + forward-pointer disposition only.
- Reopening the #91 logical decisions, oracle gating, semantic-projection trust, or the
  R-KEL checkpoint-vs-mirror classification — fixed inputs; escalate a real
  contradiction to the epic owner.
- Rewriting the **legitimate** GLEIF→QVI→LE credential hierarchy, the genesis binding /
  front-run defense, or the admission-cache credential plane.
