# Plan — #92 R-KEL checkpoint advance-storage & contention model

## Nature of the work

Design-**decision** ticket. **The decision has been made by the operator**
(`answers/A-001-thresholds.md`, ratified 2026-07-14): **Candidate A — the sovereign
per-AID uniquely-tokenized checkpoint UTxO — is selected** on the operator-ratified
**sovereignty / unrelated-AID isolation invariant**, **not** on a
throughput/capital/cost measurement contest and **not** conditional on ratifying B/C
thresholds (NOTE-021). The deliverable is therefore:

- the **ticket-owner decision record** — `spec.md` (reframed to the sovereign
  decision + the normative Candidate-A / universal-re-authorization / ACDC-boundary /
  emergency-freeze / batched-fan-in semantics), `DECISION.md` (the sovereign machine
  headers), and the rewritten `accept.sh` acceptance **contract** whose `final` target
  gates the **sovereign** deliverable (no B/C measurement contest); and
- a **repository-wide semantic consistency pass** that drives the **canonical /
  non-ticket-owned docs** to carry the sovereign per-AID decision and corrects (or
  marks superseded) every stale claim — delivered as **reviewed driver+navigator
  documentation slices**.

The **Candidate-A implementation-sizing measurements + the live-boundary smoke remain
required as a downstream implementation gate**, honestly recorded as a residual —
**never fabricated, back-filled, or represented as the selection reason**, and **not**
a precondition of this decision. The prototype/harness/measurement that would produce
them is **behavior-changing** and belongs to a **downstream implementation ticket**;
this design ticket writes **no validators**.

The ticket owner (`%1292`) authors the ticket-local `spec/plan/tasks/accept.sh` **and
`DECISION.md`** (all under `specs/92-checkpoint-contention/`), `gate.sh`, PR/issue
metadata, verification, and status. It **never** writes production or evidence code,
tests, fixtures, harnesses, behavior-changing configuration, **or the non-ticket-owned
canonical docs** — those semantic-surface edits are **reviewed driver+navigator
slices** (`%1291` driver Opus 4.8, `%1293` navigator Codex gpt-5.6-sol).

## Owned-file set (whole ticket)

Ticket-owner-owned (the sovereign-decision commit + finalization):

- `specs/92-checkpoint-contention/spec.md`   (the sovereign decision record)
- `specs/92-checkpoint-contention/plan.md`   (this file)
- `specs/92-checkpoint-contention/tasks.md`
- `specs/92-checkpoint-contention/DECISION.md` (the sovereign machine headers:
  `SELECTED_CANDIDATE=A`, `REJECTED_CANDIDATES=B,C`, `SELECTION_BASIS=sovereignty`,
  the invariant, the B/C sovereign rejection reasons, the operator ratification, the
  residual risks, and the downstream measurement residual)
- `specs/92-checkpoint-contention/accept.sh` (the rewritten acceptance **contract**:
  `spec` / `decision` / `docs` / `final` staged targets, gating the **sovereign**
  deliverable — no B/C measurement contest)
- `gate.sh` (keep tolerant-then-strict / drop at finalization)
- PR #104 body, issue #92 metadata (via `gh`, not files)

Slice-owned reviewed **documentation** slices (driver `%1291` + navigator `%1293`),
each slice pins its own subset — the **canonical / non-ticket-owned semantic
surfaces** the sovereign decision must land in and the stale claims it must correct
or mark superseded:

The set is **exact** (per the plan-review audit): every file is named, with its
disposition — **correct** the flow, or add a **precise superseded + forward-pointer**
disposition to the #92 sovereign decision (used where the mechanical re-cut is
downstream #24/#23), or **preserve** legitimate content with a recorded reason. Each
reviewed slice is one bisect-safe commit; the pair does **not** push; the ticket owner
inspects, runs `accept.sh docs`/`final` + `./gate.sh`, and pushes.

- **DS1 — canonical model** (gates `accept.sh final` `check_canonical`; **correct**):
  `specs/68-keystate-shape/identity-model.md` (§10 **thread 8** resolved to the
  sovereign per-AID checkpoint; §7c consequence; §3/§6 R-KEL/keystate note) and
  `specs/68-keystate-shape/system-architecture.md` (§3 R-KEL note, §6 registry) — carry
  the decision; **preserve** the R-KEL on-chain-checkpoint classification (not a
  mirror) and the #99 invariants.
- **DS2 — ACDC boundary** (**correct**): `docs/acdc-primer.md` — an ACDC is not
  normally directly signed (issuance/TEL sealed into the issuer's KEL, preserved through
  rotations; the spec URL); the "issuer key is current via Layer-1 AID registry proof"
  table row → the three-question split / sovereign checkpoint; **preserve** the
  admission-cache credential-plane `trie_key` usage.
- **DS3 — architecture current-auth + discovery** (**correct** high-level trust;
  **superseded-pointer** on mechanical SDK/registry shapes, re-cut downstream #24):
  `docs/architecture/overview.md`, `docs/architecture/value-auth.md`,
  `docs/architecture/veridian-bridge.md`, `docs/architecture/identity-ops.md`
  (already banner-superseded 2026-07-09 — extend with the #92 per-AID storage
  decision), `docs/index.md` (registry mermaid + `trie_key` framing → sovereign per-AID
  pointer; L65 partial supersede already present). **Preserve** freeze-registry
  mechanics but add the honest attacker-contendable boundary note.
- **DS4 — design trust/UX/DeFi/aid** (**correct** current-auth + KEL-replay-for-
  discovery; **preserve** genesis binding, admission-cache split, QVI hierarchy):
  `docs/design/trust-model.md` (value-write auth against a key-state snapshot →
  sovereign per-AID checkpoint; KEL-replay-for-discovery → generic asset-name discovery,
  no KEL replay in hot actions), `docs/design/user-experience.md` ("What you can trust
  (with KEL replay)" table + `trie_key`/freeze framing), `docs/design/defi-gate.md`
  ("issuer key current via Layer-1 AID registry proof" → sovereign checkpoint; the
  credential-chain MPF proofs stay the admission plane), `docs/design/aid-model.md`
  (targeted pointer — mostly legitimate genesis/front-run defense; L119-120 partial
  supersede already present).
- **DS5 — downstream-consequence specs + business cases** (**superseded-pointer** +
  **audit-and-record**): `specs/24-keystate/spec.md` and `specs/23-identity-auth/spec.md`
  (single-registry + MPF-trie + depth-10 window / `identity_root` inclusion = the
  Candidate-B legacy the sovereign decision re-cuts; the mechanical re-cut is downstream
  #24/#23 — add a superseded + forward-pointer disposition); `docs/design/business-cases/`
  `{index,institutional-contracts,regulated-defi,security-tokens,spo-delegation}.md` —
  **audit**: preserve the admission-cache credential-plane `trie_key` and QVI hierarchy
  (record why each untouched occurrence is legitimate/historical), correct/superseded-
  pointer the current-actor "L1 registry proof / `trie_key` Active" resolution to the
  sovereign per-AID checkpoint.

**Do not blindly rewrite legitimate material**: the GLEIF→QVI→LE credential-issuance
hierarchy, the pre-rotation genesis binding, the front-run defense, and the
admission-cache credential plane are **preserved**; only the **current-authorization /
discovery** framing that presents the old Candidate-B shape as live is corrected or
marked superseded.

**Downstream (NOT this ticket; named residual, not owned here):**

- The **Candidate-A implementation-sizing** prototype/harness/measurement and the
  **live-boundary smoke** — behavior-changing, a downstream implementation gate. If
  ever produced, evidence lives under `spikes/92-checkpoint-contention/**` +
  `specs/92-checkpoint-contention/evidence/**`; it is **not** authored here and does
  **not** gate this decision. **B/C comparison artifacts are deferred/withdrawn.**
- The **emergency-freeze (R-FRZ)** sovereign re-cut — a downstream dependency.

**Forbidden for every actor in this ticket** (guard rails):

- No production code under `onchain/`, `offchain/` **except** additive, clearly
  labelled evidence harness wiring that a spike genuinely requires (the smoke
  reuses `offchain/e2e/…/MpfProof.hs` `prove` and the `withDevnet` family). Any
  prototype **validator** lives under `spikes/92-checkpoint-contention/`, never in
  `onchain/validators/cage.ak` / `#24` / `#68` production paths.
- No absorbing #24 (full lifecycle/protocol), #25 (proof construction), #44 (live
  devnet product), or #68 (wire-schema freeze) — only their **consequences** are
  documented.
- No CESR parser / projection verifier, no adjudicator/governance-quorum code.
- No edits to sibling `specs/*/` other than the DS-owned surfaces:
  `68-keystate-shape` (DS1 canonical model), `24-keystate` and `23-identity-auth`
  (DS5 **superseded + forward-pointer** disposition only — the mechanical re-cut is
  downstream #24/#23), and `92-checkpoint-contention` (ticket-owned). Any other
  sibling spec is out of scope.
- No reopening of the #91 logical decisions, oracle gating, semantic-projection
  trust, the #91 teeth state machine, or the R-KEL checkpoint-vs-mirror
  classification — fixed inputs; a concrete contradiction is **escalated** to the
  epic owner, not silently resolved.

## accept.sh contract (the sovereign-decision acceptance contract)

`specs/92-checkpoint-contention/accept.sh` is a **real POSIX-shell** acceptance check
that gates the **sovereign** #92 deliverable. It exposes four targets — `spec`,
`decision`, `docs`, and the default `final` — and is:

- **structural (`spec`, GREEN at this HEAD)** — over `spec.md`: the operator-decision
  framing (sovereignty invariant, B/C sovereign rejection, A-selection), the
  logical/physical split, three named candidates, the Candidate-A minted AID-bound
  steady checkpoint asset (`(checkpoint_policy_id, aid_asset_name)`, native
  `blake2b_256` locator **not BLAKE3** + BLAKE3-locator negative guard, #99 combined
  policy-id=script-hash naming/binding with **inductive** mint-placement +
  spend-continuation caging, `CheckpointStateOutput`, datum/address distinction,
  `delta = 0` rotation, generic `(policy_id, asset_name)` discovery, the C9 falsifier +
  the **QVI-database negative guard**, the indexer-supplies-freshness-not-truth line,
  the ACDC user story), the **inductive downstream trust boundary**, the **universal
  re-authorization** semantics, the **ACDC boundary correction** (not normally directly
  signed; sealed into the issuer KEL; preserved through rotations; the spec URL; the
  three-question split; the admission-cache split), the **emergency-freeze residual**,
  **batched fan-in**, the transient-cage lifecycle, and the honesty NOTES
  (013/017/018/019/020/**021**);
- **sovereign-decision (`decision`, GREEN once `DECISION.md` lands)** — `DECISION.md`
  carries the machine headers `SELECTED_CANDIDATE=A`, `REJECTED_CANDIDATES=B,C`
  (exactly the complement), `SELECTION_BASIS=sovereignty`, plus non-empty
  `SELECTION_RULE`, `OPERATOR_RATIFIED` (A-001), `SOVEREIGNTY_INVARIANT`,
  `B_REJECTION`, `C_REJECTION`, `RESIDUAL_RISKS`, and `MEASUREMENT_RESIDUAL`; the B/C
  rejection reasons are **sovereign** (B serializes unrelated identities; C is a
  grindable public lane / sovereignty-depends-on-shard); the measurement residual is
  framed as **downstream A-implementation sizing**; and R-KEL + #99 are preserved;
- **DS documentation (`ds1`..`ds5`, then `docs`/`final`)** — each of the FIVE DS
  groups has its own RED-before/GREEN-after target, and `docs`/`final` go GREEN **only
  when all five** land (never after one canonical slice):
  - `ds1` (`check_canonical`) — `identity-model.md` §10 thread 8 resolved + per-AID
    sovereign checkpoint; `system-architecture.md` registry/checkpoint; **R-KEL
    on-chain-checkpoint classification preserved** (a `forbid_pred` rejects an
    R-KEL-as-mirror reclassification).
  - `ds2` — `docs/acdc-primer.md` issuance-seal positives + a narrow negative guard on
    the live "signature under the issuer's current key" claim.
  - `ds3` — `overview`/`value-auth`/`veridian-bridge`/`identity-ops` + `docs/index.md`:
    per-file sovereign `#92` forward-pointer markers + a narrow negative guard on the
    live "cage resolves current identity by `trie_key`/windowed-root" claim.
  - `ds4` — `trust-model`/`user-experience`/`defi-gate`/`aid-model`: per-file markers +
    a narrow negative guard on the live "key-state snapshot at `trie_key`" claim.
  - `ds5` — `specs/24-keystate`, `specs/23-identity-auth`, and all five
    `business-cases/*`: per-file sovereign `#92` forward-pointer markers.
- **negatively guarded (`final`)** — the decision must **not** be represented as a
  measured throughput/capital/cost-matrix win (a `forbid_pred` on `DECISION.md`), and
  the spec must **not** re-frame the storage shape as "unselected / open pending
  evidence" on the current-authorization path;
- **fail-safe** — every gate first tests artifact existence and treats absence as RED
  (never a crash, never a false pass); **structured-file-first** — `DECISION.md`
  selection is read from machine headers; prose grep drives the DS1–DS5 per-surface
  sovereign-pointer markers + narrow negative guards, plus R-KEL preservation.

**No B/C measurement contest.** The rewritten contract **removed** the
threshold-ratification / filled-matrix / evidence.json / live-smoke / cross-bound-ref
gates that made the (now-made) decision impossible until arbitrary B/C thresholds were
ratified — those are downstream A-sizing concerns (superseded sections above), not
`final` gates.

## gate.sh — `spec` strict; `final` tolerant-then-strict; drop at finalization

`gate.sh` (bootstrapped at `b14d4c3`, made tolerant by **T9201**) runs
`git diff --check` (strict), then `accept.sh spec` (strict, GREEN at this HEAD), then
the **`final` `accept.sh` verdict (run + reported, tolerant in flight)**, then plain
`just ci` (strict). The **`final` verdict** is legitimately **RED after the
ticket-owner sovereign-decision commit** (the DS1–DS5 documentation surfaces are not
yet updated) and goes **GREEN only after all five reviewed documentation slices
(DS1–DS5)** land — not after any single canonical slice. At
**finalization** the tolerance is removed (make `final` strict) and `gate.sh` is
dropped (`chore: drop gate.sh (ready for review)`) — **only after epic-owner
acceptance**. The tolerance is bounded to `final` ONLY — never to `spec`,
`git diff --check`, or `just ci`.

## Slice breakdown (each = one bisect-safe commit, `Tasks:` trailer)

The sovereign decision replaces the old evidence-gated 9-slice contest. There are now
a **ticket-owner sovereign-decision commit** and one-or-more **reviewed documentation
slices** for the canonical / consistency surfaces; the measurement contest is
**deferred downstream**.

### Slice 0 — sovereign-decision ticket-owner artifacts (ticket owner)

`spec.md` (reframed to the sovereign decision + normative semantics), `plan.md`,
`tasks.md`, `accept.sh` (rewritten sovereign contract), and **`DECISION.md`** (the
sovereign machine headers). Landed as the ticket-owner sovereign-decision commit;
`accept.sh spec` and `accept.sh decision` are **GREEN** at this commit, `accept.sh
final` is legitimately **RED** on the DS1–DS5 documentation checks (each `accept.sh
ds<N>` slice flips its own group; `final` goes GREEN once all five land).
`docs(92): select the sovereign per-AID checkpoint (Candidate A) — decision +
acceptance contract`, `Tasks: T9202` (T9200 planning already landed at `fdc0818`; gate
lifecycle T9201 at `684e842`).

### DS1–DS5 — reviewed documentation slices (pair)

Drive the **canonical / non-ticket-owned semantic surfaces** (§Owned-file set, exact)
to carry the sovereign per-AID decision and correct / mark-superseded every stale
claim. Each is one bisect-safe reviewed commit with a real `accept.sh ds<N>`
RED-before / GREEN-after target; the pair does **not** push; the ticket owner
inspects, runs `accept.sh ds<N>` (then `docs`/`final`) + `./gate.sh`, and pushes. The
exact owned files and per-file dispositions are in `tasks.md` DS1–DS5.

- **DS1** — `specs/68-keystate-shape/identity-model.md` + `system-architecture.md`
  (canonical model; gate `accept.sh ds1` = `check_canonical`).
- **DS2** — `docs/acdc-primer.md` (ACDC boundary correction; gate `accept.sh ds2`).
- **DS3** — `docs/architecture/{overview,value-auth,veridian-bridge,identity-ops}.md`
  + `docs/index.md` (current-auth + discovery; gate `accept.sh ds3`).
- **DS4** — `docs/design/{trust-model,user-experience,defi-gate,aid-model}.md`
  (design trust/UX/DeFi/aid; gate `accept.sh ds4`).
- **DS5** — `specs/24-keystate/spec.md`, `specs/23-identity-auth/spec.md`, and
  `docs/design/business-cases/{index,institutional-contracts,regulated-defi,security-tokens,spo-delegation}.md`
  (downstream-consequence superseded-pointers + business-case current-auth audit;
  gate `accept.sh ds5`).

## Commit history (explicit — conventional subjects + numeric task IDs)

| # | Subject | Owner | `Tasks:` | accept.sh |
|---|---|---|---|---|
| — | `chore(92): make acceptance gate tolerant until decision` | ticket owner | T9201 | (gate lifecycle, landed `684e842`) |
| 0a | `docs(92): add checkpoint-contention plan, tasks, and RED acceptance skeleton` | ticket owner | T9200 | (superseded framing, landed `fdc0818`) |
| 0b | `docs(92): select the sovereign per-AID checkpoint (Candidate A) — decision + acceptance contract` | ticket owner | T9202 | `spec`+`decision` GREEN; `final` RED on all DS1–DS5 (docs unedited) |
| DS1 | `docs(92): resolve identity-model thread 8 + system-architecture to the sovereign per-AID checkpoint` | pair | T9210 | `accept.sh ds1` (check_canonical) GREEN |
| DS2 | `docs(acdc): correct the ACDC issuance-seal boundary (not signed under current keys)` | pair | T9211 | `accept.sh ds2` GREEN |
| DS3 | `docs(architecture): reframe current-auth + discovery to the sovereign per-AID checkpoint` | pair | T9212 | `accept.sh ds3` GREEN |
| DS4 | `docs(design): reframe trust/UX/DeFi/aid current-auth to sovereign discovery` | pair | T9213 | `accept.sh ds4` GREEN |
| DS5 | `docs(92): superseded-pointer #24/#23 + business-case current-auth audit` | pair | T9214 | `accept.sh ds5` GREEN |
| — | `chore: drop gate.sh (ready for review)` | ticket owner | — | (finalize, after epic acceptance) |

Each documentation slice is one bisect-safe reviewed commit with a **real
RED-before/GREEN-after `accept.sh` target** — `ds1` (`check_canonical`), `ds2`
(ACDC issuance-seal positives + a narrow negative guard rejecting the live
"signature under the issuer's current key" claim), `ds3`/`ds4`/`ds5` (per-file
sovereign `#92` forward-pointer markers + narrow negative guards on the load-bearing
live current-auth claims, with historical/admission/QVI/genesis exemptions). `final`
requires **all five groups** — it cannot go GREEN while any DS surface stays stale.
The pair does not push; the ticket owner verifies the exact committed SHA, runs the
slice's staged `accept.sh ds<N>` (RED-before → GREEN-after) plus `./gate.sh`, and
pushes.

## Orchestrator-owned finalization (post-slice)

- Verify `accept.sh final` GREEN + `./gate.sh` GREEN at committed HEAD; fresh GitHub
  CI green.
- Update PR #104 body + issue #92: state the **sovereign per-AID (Candidate A)**
  decision, link #97/#99, note the R-KEL classification + #99 invariants preserved,
  and the honest measurement/R-FRZ residuals.
- Finalization audit (commit-gate over all commits, no open tasks, satisfied
  `spec.md` success criteria stamped); make `gate.sh` `final` strict, then drop
  `gate.sh` **last** (`chore: drop gate.sh (ready for review)`); `gh pr ready 104`.
  **Do not merge** — the epic owner performs the guarded merge. **GATE: finalization
  runs only after explicit epic-owner acceptance.** Report `COMPLETE` on STATUS.

## Reporting / hard stops

Append durable milestones to `STATUS.md` (START done; inventory done; sovereign-decision
SHA; per-slice RED/GREEN + reviewed SHAs; pushes; CI; COMPLETE/BLOCKED). Genuine
decisions go in `questions/`. Between accepted slices the default is **auto-continue**;
pause only on a real Q-file blocker, an analyzer surprise, an owned-surface conflict, or
a gate failing again after one bounded repair.

## Risks / notes

- **The Candidate-A implementation-sizing measurements + live-boundary smoke are a
  downstream gate, not a #92 blocker** (NOTE-021). They are recorded as a residual, not
  performed here, and never fabricated or presented as the selection reason.
- **Candidate A needs a generic off-chain asset index** (an exact `(policy_id,
  asset_name) → current unspent output` lookup answerable by any indexer/node/sidecar/
  replica — **not** a bespoke QVI-owned `AID → UTxO` directory, NOTE-019); this is a
  downstream A-implementation availability cost, not a free property, and it supplies
  freshness, **not** identity truth (re-checked against the ledger).
- **C's `lane = f(cesr_aid)` grindability is a rejection reason, not a tuning knob**
  (NOTE-017/NOTE-021): a public/grindable lane lets a hostile AID target a victim's
  lane, and makes sovereignty depend on shard machinery — which is exactly why C is
  rejected. No lane sweep or targeted-victim measurement is performed for #92.
- **The Candidate-A advance path is unbuilt and unmeasured** — a **downstream**
  implementation gate. When sized downstream, do **not** let a unit/golden proof stand
  in for the live node boundary, and do **not** sum the registration pipeline and the
  rotation advance into one per-tx figure (NOTE-013/018). None of this gates the #92
  decision.
