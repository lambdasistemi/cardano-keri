# Plan: reopen #114 — permissionless bonded registration

**Target branch**: `feat/114-permissionless-registration`
**Required base**: merged reopened #116
**Spec**: `specs/114-permissionless-registration/spec.md`
**Status**: ratified by A-014; implementation active on main `9de6860`

## Summary

Use the registration fixture's public KERI controller signatures and newly
exported witness receipts as the only Register signature evidence. Delete the
fresh InceptionMessage layer, then reopen #116's staging-closed mint branch
only for an ACTIVE output that protects at least `D_reg+B` plus checkpoint
minimum ADA and its AID token. Advance remains closed for #115. Preserve the
burn-axiom/audit fixes now on main, keep the 21-theorem traceability job live,
exercise the opened staging against a real node, and report the program-size
delta at every gate.

## Constitution check

- Existing protocol strings are deleted only with their obsolete feature and
  never repurposed.
- Keripy remains the byte/signature oracle; Haskell remains the generated
  vector source; Aiken consumes verbatim output.
- RED precedes GREEN and each slice is one green commit.
- Repeatable registration and no-global-unicity remain explicit.
- The pair owns only the named #114 registration documentation fragments; old
  specs, #115/#117 behavior, and confidential notes remain untouched.
- Main's convict-burn/reap design record and required Lean/traceability job are
  inputs. #114 implements no Convict, Reap, Advance, or Close transition.
- The applied program remains prominently NON-DEPLOYABLE until the #115 hard
  stop proves it fits the 16,133-byte creation-transaction budget.

## Owned surface

```text
offchain/test/keri-fixtures/gen_fixtures.py
offchain/test/keri-fixtures/fixtures/registration.json
offchain/test/keri-fixtures/fixtures/manifest.json
offchain/test/Cardano/KERI/AID/Checkpoint/RegistrationFixturesSpec.hs
offchain/lib/Cardano/KERI/AID/Checkpoint/Registration.hs
offchain/test/Cardano/KERI/AID/Checkpoint/RegistrationSpec.hs
offchain/app/GenRegistrationVectors.hs
offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs        # inception-only deletion
offchain/test/Cardano/KERI/AID/Checkpoint/MessageSpec.hs  # inception-only deletion
onchain/lib/cardano_keri/checkpoint/registration.ak
onchain/lib/cardano_keri/checkpoint/registration_tests.ak
onchain/lib/cardano_keri/checkpoint/registration_vectors.ak
onchain/lib/cardano_keri/checkpoint/message.ak             # inception-only deletion
onchain/lib/cardano_keri/checkpoint/message_tests.ak       # inception-only deletion
onchain/validators/checkpoint.ak
onchain/validators/checkpoint_tests.ak
onchain/validators/checkpoint_measurements.ak
lean/traceability.csv                                             # audit/conditional flip only
offchain/e2e/CheckpointE2ESpec.hs
offchain/e2e/CheckpointTxBuilder.hs
offchain/e2e/CageTxBuilder.hs                    # live-limit wording only
offchain/e2e/fixtures/mainnet-pparams-2026-07-22.json
offchain/cardano-keri.cabal
offchain/test/Main.hs
justfile
offchain/flake.nix
offchain/flake.lock                              # only if PV11 probe requires bump
specs/114-permissionless-registration/MEASUREMENTS.md

# R6 only, named fragments:
docs/architecture/veridian-bridge.md
docs/design/trust-model.md
docs/blog/self-certifying-identities-on-cardano.md
docs/milestones-deck/index.html
```

#114 must not change #116 Arm/Claim/Convict behavior, #115 Advance behavior,
#117 Close/Reap behavior, historical specs, or any other docs fragment.

## Dependency barrier (`T114-R0`)

The epic owner reopens #114 only after accepted reopened #116 is on main. The
ticket branch starts from that exact base, `gate.sh` is validated before pair
dispatch, and Register/Advance/Close staging closures plus final `B`/`W_freeze`
arity are checked; held #117's `W_close` is separate.
The revision remains **NO DEPLOY** because Advance and Close are closed and
the #115 size hard stop has not run. The PR body, measurements, and E2E output
all retain the NON-DEPLOYABLE banner.

## Slice R1 — witnessed inception oracle (`T114-R1`)

RED fixture tests require real indexed witness receipts over the witnessed
inception's exact raw bytes and prove every exported signature target is
`event_raw`.

GREEN extends only the deterministic keripy generator, committed JSON, loader
checks, and fixture tests. It removes no fresh-message code yet and changes no
validator behavior.

Commit: `test(114): export witnessed inception receipts` with exactly
`Tasks: T114-R1`.

## Slice R2 — permissionless registration predicate (`T114-R2`)

RED shared Haskell tests replace preimage-auth positives with event-own
controller signatures and receipt-threshold families; the old predicate must
fail them.

GREEN changes `RegistrationEvidence`, verifies distinct controller and witness
indices over `event_bytes`, enforces literal empty receipts at `toad=0`, and
keeps E1-E9/schema checks. Mirror it in Aiken and regenerate every vector.
Delete InceptionMessage-only production types/helpers/preimage vectors and
private-seed signing tests without touching AdvanceMessage.

The live mint branch remains staging-closed by #116, so this pure/model change
cannot create a checkpoint yet.

Commit: `refactor(114): authenticate inception events from the KEL` with
exactly `Tasks: T114-R2`.

## Slice R3 — reopen bonded Register (`T114-R3`)

RED full-context tests prove Register is closed and add protected-reserve,
repeat-registration, extra-input, mint/proof, old-signature, and receipt
canaries.

GREEN reopens only mint/Register, delegates to R2's event-own predicate, and
requires at least `checkpoint_min_ada+D_reg+B` lovelace plus exactly one AID
token. Missing/short `D_reg` or `B`, extra AID-policy assets, invalid applied
parameters, and controller-chosen parameter values reject; unrelated surplus
lovelace/assets are accepted and remain in checkpoint custody. Duplicate and
post-conviction registration remain accepted. A third-party bridger receives
no on-chain refund right; compensation is off chain.

Full-context vectors also pin #114's contribution to the normative theorem:
Register never consumes an existing checkpoint; duplicates create independent
state outputs; and a hostile submitter can project only the real signed and
witnessed inception event, never an invented state or a same-UTxO busy lock.

Audit all 21 Lean traceability rows. None of the current PENDING theorems is
registration-only, so do not pull Convict/Reap lifecycle behavior into #114 to
manufacture a CSV change. Flip a row only if this slice independently makes it
real by adding both named executable tests; otherwise preserve the sentinels.

Advance and Close remain fail closed.

Commit: `feat(114): enable permissionless bonded registration` with exactly
`Tasks: T114-R3`.

## Slice R4 — registration measurements (`T114-R4`)

Measure full Register contexts for 2-key unwitnessed, witnessed 2-of-2 with
2-of-3 receipts, and GLEIF-shaped 7-key inception. Include proof input/burn,
event signatures, receipts, reserve-at-floor and conservative-surplus state
values, and final parameter arity. Record the table in
`specs/114-permissionless-registration/MEASUREMENTS.md`.

Any memory or CPU headroom below 25.00% is a hard stop. Audit net deletion of
fresh-message signing surface and absence of registry/batcher/sequencer code.
Measure the exact applied checkpoint program and report current bytes,
`current - 19,565`, and `16,133 - current`. Keep the NON-DEPLOYABLE verdict
even if #114 happens to fit; the binding deployability decision remains #115.

Commit: `test(114): measure permissionless registration` with exactly
`Tasks: T114-R4`.

## Slice R5a — current-production devnet state (`T114-R5a`)

RED starts the real devnet, queries the pre-transition protocol parameters,
asserts the repository genesis lineage has the 251-entry Plutus V3 model, and
demonstrates that the production hash-proof witness cannot settle under that
stale state. It also records the pinned cardano-node version and tests whether
that binary can enact PV 11; a node-pin bump is authorized only on a proved
compatibility failure.

GREEN commits the full 2026-07-22 mainnet protocol-parameter snapshot as an
E2E fixture with a provenance envelope naming the mainnet node/socket lineage,
date, PV 11.0, and source digest. The same-day preprod digest is recorded as a
cross-check. The harness then uses the real protocol-parameter/hard-fork
transition path, polls enactment, and queries the node to assert PV 11.0 plus
the exact 350-entry V3 model content before settling a real production
hash-proof mint. Fixture-only assertions, synthetic evaluation, a genesis
cost-model patch, or a pending/waived witness are forbidden.

The sole genesis difference remains the existing drift-proved
`maxTxSize 16384 -> 32768`; its old/new assertions remain live and exunit
fields stay untouched. The live-node witness may use the current production
16.5M/10B limit. The measurement gate stays at the stricter internal 14M/10B
ceiling. Correct the E2E harness comment that labels 14M as a network maximum.
If the node pin changes, record the old/new versions and the compatibility
verdict and keep the lock delta in this slice.

Commit: `test(114): initialize production cost model on devnet` with exactly
`Tasks: T114-R5a`.

## Slice R5 — staged checkpoint devnet (`T114-R5`)

After restoring and rebasing the independently verified suspended R5 patch,
RED changes the named checkpoint E2E expectations from the #116 staging smoke
to the exact #114 matrix. GREEN extends the existing `CageTxBuilder`-pattern
harness and, after R5a's queried PV 11/350-entry initialization and under the
already drift-checked devnet-only 32-KiB override:

- settles hash-proof mint then permissionless Register with real
  `minADA+D_reg+B` escrow;
- settles Arm against that fresh production-lineage checkpoint;
- asserts Claim according to the actual #116 dispatch at this head (positive
  if live, explicit Phase-2 rejection if intentionally closed; never pending);
- proves Advance and Close still reach the production validator and reject;
- retains the loud NON-DEPLOYABLE output banner and single-field genesis
  override; and
- reruns the checkpoint size probe and the full E2E/CI gate.

Commit: `test(114): settle permissionless registration on devnet` with
exactly `Tasks: T114-R5`.

## Slice R6 — registration documentation (`T114-R6`)

After rebasing on accepted #116 documentation, the driver/navigator update
only #114-owned registration fragments:

- “Inception transaction” in `docs/architecture/veridian-bridge.md`;
- registration/duplicate-bridge guarantees in
  `docs/design/trust-model.md`;
- “Can someone register an identifier they do not own?” and the M1
  registration-availability bullet in the M1 blog; and
- the M1 registration speaker-note, key-state, and demo-registration fragments
  in the M1 slide deck.

The text removes fresh Cardano signing, registered-once, and anti-squat claims;
explains event-own public authentication, repeatable registrations, protected
`D_reg+B`, conservative surplus, and the third-party-donation residual.
It also corrects any #114-owned statement that calls 14M/10B the live mainnet
transaction maximum: that pair is the project's stricter internal measurement
ceiling, while the 2026-07-22 mainnet/preprod limit is 16.5M/10B.
It preserves the burn axiom: conviction history is the transaction, the
checkpoint is burned, and post-conviction registration is admissible; it does
not invent a tombstone or implement #117's reap machine.

The theorem is central: the blog's single-sovereign-UTxO argument, state
machine, and per-move table gain the Register row; trust-model carries
advance-totality and bounded adversarial interference normatively; the deck
carries “anyone can project the public truth; no one can lie about it or lock
you out of it.” Every #117 mention names CLOSING `0x03`, separate `W_close`,
required direct ordinary Advance-void, and no cryptographic express-close; it
never reuses `W_freeze`. #115 normal-Advance and #116 freeze fragments remain
untouched. Strict MkDocs, lychee, and the full gate must pass.

Commit: `docs(114): explain permissionless bonded registration` with exactly
`Tasks: T114-R6`.

## Ordering and bisect safety

`R1 -> R2 -> R3 -> R4 -> R5a -> R5 -> R6` is strict. Fixture material precedes
consumers. R2 is safe because #116 keeps mint closed. R3 atomically opens
Register with all auth/value checks and an explicit 21-row traceability audit.
R4 changes only measurement evidence. R5a proves the actual production-state
transition and hash-proof boundary on a real node. R5 proves the exact staging
matrix in that state. R6 changes only #114-owned narrative after behavior,
measurements, and live-boundary evidence are stable. Every HEAD passes the full
gate and records the current program bytes/deltas.

After R6, #114 may merge but remains **NO DEPLOY** because all Advance roles
are still closed. #115 starts only from the updated main.

## Review and gate obligations

- Pair protocol, exact trailers, full-file owner review, fresh per-slice gate,
  and generated-vector drift checks are mandatory.
- Worker scope includes only the named docs fragments in R6 and otherwise
  excludes docs; old specs, #116 behavior, all #117 files, PR metadata, and
  pushes are always excluded.
- A 25% miss, stale fresh-signing symbol, weakened offset/threshold canary,
  missing traceability identifier, failed real PV11 transition, non-350 model,
  E2E staging mismatch, or missing size delta is a Q-file stop.
- No mark-ready, merge, deployment, or #117 resume is authorized here.
