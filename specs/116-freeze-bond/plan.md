# Plan: reopen #116 — freeze-bond state core

**Target branch**: `feat/116-freeze-bond`  
**Base**: `2aa2d29adb79d503c40f6b9353852cf8433bafcd`
**Spec**: `specs/116-freeze-bond/spec.md`  
**Status**: A-014 ratified; Lean-traceability addendum folded; R1 accepted

## Summary

Land the common `B`/`W_freeze`, ARMED datum/role, deadline,
protected-reserve, Claim, and conviction-routing model first. Register and every Advance path are
intentionally closed in the final #116 revision so neither #114 nor #115
behavior is silently implemented here. The protocol set is non-deployable
until #114 and #115 land in order.

## Technical context

- Aiken/Plutus V3 combined checkpoint validator.
- Haskell parity library and Hspec tests under `offchain/`.
- Haskell-generated Aiken vectors and drift checks.
- Existing keripy enforcement evidence and #106 binding are reused unchanged.
- `Transaction.validity_range` is POSIX milliseconds.
- Full `./gate.sh` per slice; memory and CPU must each retain >=25% headroom.
- The 17 proved declarations in `lean/CardanoKeri/Goals.lean` and seed lemmas
  in `Invariants.lean` are present from merged #124 and drive an executable
  traceability gate in R4.

## Dependency barrier (`T116-R0`)

The epic owner reopens #116 and creates its branch from then-current
`origin/main`; the ticket owner installs and validates `gate.sh` before any
pair dispatch. #114, #115, and #117 remain undispatched. The resulting #116
revision is explicitly **NO DEPLOY** because Register, Advance, and Close are
staging-closed.

## Constitution check

- Design authority is external and operator-ratified; the ticket owner records
  implementable rules while the driver/navigator own the ticket's designated
  documentation slice.
- New ARMED wire data is versioned; `CheckpointDatumV1`, existing role tags,
  domain strings, and TombstoneV1 are not mutated.
- Every pure and wire rule has Haskell/Aiken parity and generated vectors.
- Every behavior slice is RED -> GREEN and one bisect-safe commit.
- The pair-owned documentation slice is a separate bisect-safe commit gated by
  `mkdocs build --strict` and lychee.
- No confidential operator material enters the repository artifacts.
- No violation or exception is proposed.

## Module map

New isolated model surface:

```text
offchain/lib/Cardano/KERI/AID/Checkpoint/FreezeBond.hs
offchain/test/Cardano/KERI/AID/Checkpoint/FreezeBondSpec.hs
offchain/app/GenFreezeBondVectors.hs
onchain/lib/cardano_keri/checkpoint/freeze_bond.ak
onchain/lib/cardano_keri/checkpoint/freeze_bond_tests.ak
onchain/lib/cardano_keri/checkpoint/freeze_bond_vectors.ak
```

Live integration amends:

```text
offchain/lib/Cardano/KERI/AID/Checkpoint/Enforcement.hs
offchain/test/Cardano/KERI/AID/Checkpoint/EnforcementSpec.hs
offchain/app/GenEnforcementVectors.hs
onchain/lib/cardano_keri/checkpoint/enforcement.ak
onchain/lib/cardano_keri/checkpoint/enforcement_tests.ak
onchain/lib/cardano_keri/checkpoint/enforcement_vectors.ak
onchain/lib/cardano_keri/checkpoint/role.ak
onchain/lib/cardano_keri/checkpoint/role_tests.ak
onchain/validators/checkpoint.ak
onchain/validators/checkpoint_tests.ak
onchain/validators/checkpoint_measurements.ak
offchain/cardano-keri.cabal
offchain/test/Main.hs
justfile
```

R4 traceability bootstrap adds:

```text
lean/traceability.csv
scripts/check-lean-traceability.sh
offchain/lib/Cardano/KERI/AID/Checkpoint/LifecycleModel.hs
offchain/test/Cardano/KERI/AID/Checkpoint/LifecycleModelSpec.hs
offchain/app/GenLifecycleTraceVectors.hs
onchain/lib/cardano_keri/checkpoint/lifecycle_model.ak
onchain/lib/cardano_keri/checkpoint/lifecycle_model_tests.ak
onchain/lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak
```

The pure model mirrors the entire ratified #124 lifecycle, including future
#114/#115/#117 steps, but may not open those live validator branches. Exact
module filenames may change only after a Q-file; the CSV and gate-script paths
are fixed.

Exact file placement may consolidate the new pure model into Enforcement if
that produces a smaller coherent API, but it may not mix #114/#115 auth work
into this branch.

## Slice R1 — freeze-bond schema and parity foundation (`T116-R1`)

RED first adds Haskell tests for:

- `freeze_bond` floor/one-below and positive `freeze_window`;
- exact role values;
- `ArmedV1 { checkpoint : CheckpointDatumV1, hunter_pkh, deadline }` wire
  golden and 28-byte hunter validation;
- finite arm upper endpoint `u`, `deadline = u + freeze_window`, and raw
  just-before/exact/after response/claim endpoint verdicts; and
- existing role tags plus new ARMED tag `0x02`.

GREEN adds the smallest Haskell/Aiken model, role extension, generator,
generated vectors, test wiring, and drift recipes. No validator dispatch
changes in this slice.

Commit: `feat(116): model freeze-bond state and deadline` with exactly
`Tasks: T116-R1`.

## Slice R2 — arm and claim wiring with staging closures (`T116-R2`)

RED full-context tests prove the delivered direct Freeze behavior, absent
Claim path, old applied arity, and permissive dispatch disagree with the new
matrix.

GREEN:

- applies `freeze_bond` and `freeze_window` and checks all parameter
  predicates before dispatch;
- classifies role `0x02` only through the version-tagged ArmedV1 wrapper whose
  `checkpoint` is the inner CheckpointDatumV1;
- replaces ACTIVE -> FROZEN with ACTIVE -> ARMED using unchanged enforcement
  evidence, a finite arm upper endpoint `u`, and deadline `u + W_freeze`;
- adds ARMED -> FROZEN Claim whose validity lower endpoint is `>= deadline`
  and whose named datumless enterprise-key payout is exactly `B`;
- preserves the complete input Value on Arm, subtracts exactly `B` lovelace
  from the continuing state on Claim, conservatively retains `D_reg`, minimum
  ADA, token, extra lovelace, and extra assets, and forbids own-policy
  mint/burn; and
- explicitly fail-closes Register, every Advance, and Convict pending their
  owning slices/tickets.

The RED/GREEN role matrix also pins the #116 half of the normative bounded
adversarial interference invariant: a behind ACTIVE state can be armed once;
repeated Arm from ARMED rejects; before the deadline no proof-free #116 action
can mutate ARMED; exact/late Claim boundaries are deterministic. The future
ordinary Advance response remains the single reserved progress path under
advance-totality and is intentionally staging-closed until #115.

The temporary Convict closure keeps the R2 HEAD safe until exact payout routing
lands in R3. Extra unrelated inputs/outputs remain allowed.
Stable R2 full-context Arm/Claim test identifiers are retained as code-level
evidence for R4's traceability map where applicable.

Commit: `feat(116): wire armed freeze and bond claim` with exactly
`Tasks: T116-R2`.

## Slice R3 — exact conviction routing (`T116-R3`)

RED proves Convict is staging-closed and records wrong-beneficiary,
under/over-payment, same-output reuse, retained protected-reserve, and ARMED
hunter-redirection canaries.

GREEN extends the redeemer with `convictor_pkh` and named output indices,
reopens Convict for ACTIVE/ARMED/FROZEN, writes the unchanged exact tombstone,
and enforces:

- ACTIVE: `D_reg+B` to convictor;
- ARMED: `D_reg` to convictor and `B` to the recorded hunter at distinct
  indices; and
- FROZEN: `D_reg` to convictor.

All named payouts are exact datumless enterprise-key lovelace values. The
tombstone keeps only its protected terminal value; unreserved surplus remains
ordinary transaction change. Existing evidence, conflict, terminality, and
self-conviction behavior remains.
Stable R3 full-context Convict/value-conservation identifiers are retained as
code-level evidence for R4's traceability map where applicable.

Commit: `feat(116): route conviction deposits and freeze bonds` with exactly
`Tasks: T116-R3`.

## Slice R4 — executable Lean traceability and measurements (`T116-R4`)

RED first adds Haskell properties against a missing pure lifecycle model. The
model gives every `Step` constructor in the merged Lean lifecycle its own
named pure mirror function plus a total dispatcher. The nine
per-transition goals are direct QuickCheck properties; the eight
trace/reachability goals use monadic state-machine generation of valid and
adversarial interleavings. `Invariants.lean` lemma names seed property names
and failure labels.

GREEN adds the isolated pure Haskell and Aiken lifecycle mirrors, one Haskell
generator for shared theorem/verdict vectors, matching Aiken verdict tests,
and all cabal/Main/just drift wiring. It checks in
`lean/traceability.csv` with exactly one row for each of the 17 extracted
theorems and the four honest-limit header statements. Fixed-path
`scripts/check-lean-traceability.sh` extracts theorem names and fails on
mapping cardinality/name drift, blank/duplicate/extra rows, or nonexistent
mapped Haskell/Aiken test identifiers. The normal gate runs the script and
vector regeneration. Future-action model cases remain test-only and may not
weaken the R2 staging closures.

Measure full validator ACCEPT contexts for 2-key/7-key Arm, Claim, and Convict
from ACTIVE/ARMED/FROZEN, including reserve-preserving surplus contexts.
Record raw units, usage, and headroom in
`specs/116-freeze-bond/MEASUREMENTS.md`; do not edit the historical
`specs/116-enforcement/MEASUREMENTS.md`.

Any memory or CPU headroom below 25.00% is a hard stop and Q-file. The slice
also runs repository-wide symbol checks proving no registry/batcher/sequencer
surface, verifies Register/Advance remain intentionally closed, and requires
17/17 executable traceability rows.

Commit: `test(116): trace and measure freeze-bond state paths` with exactly
`Tasks: T116-R4`.

## Slice R5 — freeze lifecycle documentation (`T116-R5`)

The driver/navigator update only #116's assigned narrative fragments after
R4 is green:

- the lag/freeze state and incentive paragraphs in
  `docs/design/trust-model.md`;
- the freeze-bond question/answer and residual-risk fragments in
  `docs/blog/self-certifying-identities-on-cardano.md`; and
- the freeze-state and incentive framing fragments in
  `docs/milestones-deck/index.html`.

The theorem is the centerpiece: the M1 blog explains why permissionless
projection is safe on one sovereign UTxO, shows the state machine and per-move
adversarial table; `trust-model.md` states advance-totality and the normative
bounded adversarial interference invariant; the deck carries “anyone can
project the public truth; no one can lie about it or lock you out of it.” The text also
covers ARMED `0x02`, `W_freeze` endpoint deadlines, B/D_reg arithmetic,
permissionless response/thaw, donated third-party funds, and abandonment-only
economics.

Every held-#117 mention names CLOSING `0x03`, distinct `W_close`, required
single-transaction ordinary Advance-void, and the ban on cryptographic
express-close. It does not edit registration- or normal-advance-owned
fragments. `mkdocs build --strict`, lychee, and the full gate must pass.

Commit: `docs(116): explain the bonded freeze lifecycle` with exactly
`Tasks: T116-R5`.

## Ordering and bisect safety

`R1 -> R2 -> R3 -> R4 -> R5` is strict. R1 is behavior-neutral. R2 atomically
changes the applied arity and Arm/Claim transition while closing every path
whose final value semantics are not yet owned. R3 reopens Convict only with
complete payout welds. R4 is test-only: pure traceability plus measurements,
with no live dispatch. R5 documents only the
#116-owned narrative after behavior and measurements are stable. Every HEAD
builds and passes the full gate.

After R5, #116 may merge but the protocol set remains **NO DEPLOY**. #114 is
created from that updated main; no pair works ahead on a stale base.
The R4 pure model includes future actions only because it mirrors the already
proved ratified lifecycle; it is not an implementation of #114/#115/#117.

## Review and gate obligations

- Driver/navigator use RED approval, GREEN approval, one commit, and exact
  trailer per slice.
- Workers edit documentation only in R5 and only in its named fragments; they
  never edit proposal artifacts, historical specs, #117, `gate.sh`, PR
  metadata, or sibling authentication paths.
- Ticket owner reviews every changed file and fresh gate output before
  checking tasks or pushing.
- Generated vector modules are never hand-edited.
- The R4 owner audit extracts the theorem inventory independently and requires
  exactly 17/17 unique map rows whose mapped identifiers exist and execute; a
  green measurement table alone is insufficient.
- Scope drift into Register/Advance authentication is a Q-file stop.
- No mark-ready, merge, or deployment action is implied by this plan.
