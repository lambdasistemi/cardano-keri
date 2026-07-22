# Plan: permissionless advance projection (#115 re-land)

This plan supersedes the completed PR #120 plan. One reviewed,
bisect-safe commit lands per slice. Every behavior-changing slice uses the
persistent driver/navigator pair, RED before GREEN, explicit file ownership,
an independent navigator approval, the full ./gate.sh owner gate, and a
Tasks trailer.

Implementation is blocked until the epic owner approves Q-001.

## Baseline

- Base: main 91ccc71.
- Bootstrap: 49d6487, chore(115): add gate for permissionless advance.
- Draft PR: #132.
- Baseline just ci and ./gate.sh: green.
- Applied monolith: 23,124 bytes; budget: 16,133 bytes.
- Preprod balance: 10,000,000,000 lovelace at the ruled address and UTxO.

## Module map

- Evidence predicates: onchain/lib/cardano_keri/checkpoint and
  offchain/lib/Cardano/KERI/AID/Checkpoint.
- Deployment scripts: onchain/validators/checkpoint.ak plus the new
  onchain/validators/checkpoint_observer.ak.
- Full contexts and execution rows: onchain/validators/checkpoint_tests.ak
  and checkpoint_measurements.ak.
- Oracle and parity: offchain/test/keri-fixtures,
  offchain/app/GenAdvanceVectors.hs, generated Aiken vectors, and drift
  recipes in justfile.
- Lifecycle model: Lean CardanoKeri lifecycle/goals, Haskell
  LifecycleModel, generated lifecycle vectors, and Aiken lifecycle mirror.
- Real-node construction: offchain/e2e/CheckpointTxBuilder.hs,
  CheckpointE2ESpec.hs, offchain/flake.nix, and the E2E cabal component.
- Manual public-network tooling: a new manual preprod executable/script and
  a just recipe that is never a CI dependency.
- Narrative: identity-ops, trust-model, M1 blog, and milestones deck only.

## Slice R1 — withdraw-0 observer forwarding

Goal: re-home the already-merged Register, Freeze, and Convict evidence
verification without changing their accepted transaction semantics.

RED:

- add observer-ran coupling tests for missing withdrawal, nonzero amount,
  wrong observer credential, missing/wrong Withdraw redeemer, wrong action,
  wrong h, and wrong own outref;
- add a certificate-purpose rejection proving the observer cannot authorize
  its own deregistration, plus an unregistered-reward-account live negative
  where the node-client harness can express it;
- port existing positive and adversarial predicate contexts through the
  observer and demonstrate the monolithic checkpoint no longer supplies that
  verification;
- add exact applied-size assertions for both programs and observe the
  pre-restructure checkpoint failure.

GREEN:

- add checkpoint_observer with ObserveRegister, ObserveFreeze, and
  ObserveConvict, using a small claim plus opaque evidence envelope;
- parameterize checkpoint by the observer hash and replace inline heavy
  predicate calls and evidence-bearing checkpoint redeemers with exact slim
  ran-checks while retaining all state, Value, checkpoint-policy token, role,
  payout, and deadline rules;
- move the event-derived hash-proof input/burn calculation into
  ObserveRegister and remove the fresh-message-only network_id parameter;
- update the blueprint loader/builder to apply both scripts with one
  checkpoint h;
- construct both reference-script transaction shapes; and
- register the observer stake credential in devnet setup before the first
  evidence-bearing transaction and keep every certificate purpose fail
  closed;
- require each exact applied program to be less than 16,133 bytes.

Primary owned files:

- onchain/validators/checkpoint.ak
- onchain/validators/checkpoint_observer.ak
- onchain/validators/checkpoint_tests.ak
- onchain/validators/checkpoint_observer_tests.ak
- offchain/e2e/CheckpointTxBuilder.hs
- offchain/e2e/CheckpointE2ESpec.hs
- justfile, only the applied-size recipe and gate wiring

No Advance branch is opened in R1. The full existing gate plus focused Aiken
contexts and exact size probe must pass. After two failed reviewed attempts,
stop with a Q-file; mint/spend splitting is forbidden.

Commit: feat(115): forward checkpoint evidence to an observer

Trailer: Tasks: T115-R1

## Slice R2 — restore the production transaction cap

Goal: remove the temporary size fiction immediately after R1 proves both
programs deployable.

RED:

- a source guard fails while the 32,768 rewrite and NON-DEPLOYABLE runtime
  banner exist;
- the stock-genesis checkpoint E2E must expose any reference-script
  creation or transaction-size regression.

GREEN:

- delete e2eGenesis and route checkpoint E2E to the stock 16,384 genesis;
- delete the banner and overage tuple;
- make the permanent just ci gate reject either program at or above 16,133
  and reject 32768 in executable/configuration surfaces;
- settle both reference-script creation transactions on the local stock
  devnet;
- rerun the truthful old-cost boundary, preserving explicit
  PENDING(blocked-on=#190) positive hash-proof rows.

Primary owned files:

- offchain/flake.nix
- offchain/e2e/CheckpointTxBuilder.hs
- offchain/e2e/CheckpointE2ESpec.hs
- justfile, only deployability/source guards and E2E labels

Commit: fix(115): restore the production transaction cap

Trailer: Tasks: T115-R2

## Slice R3 — event-own advance authentication

Goal: delete fresh Cardano authorization and make the exact KERI event the
sole signature preimage.

RED:

- convert positive controller evidence to signatures over event_bytes;
- prove old AdvanceMessage signatures, event-byte mutations, wrong indices,
  duplicate indices, stolen-current quorum, under-threshold evidence,
  malformed witness deltas, receipt games, and AE offset misdirection reject;
- preserve the genuine GLEIF 3-of-7 and witnessed rotations.

GREEN:

- delete AdvanceMessage, advance_domain, reconstruction, canonical-CBOR
  signature helpers, goldens, and stale exports in both languages;
- refactor the pure transition predicate around OLD, NEW, and
  AdvanceEvidence;
- count only distinct NEW.cur_keys signatures over event_bytes, then apply
  both the NEW current threshold and OLD next-key commitment threshold;
- preserve AE1-AE10, W1-W3, exact incoming-set receipts, and the no-d/no-p
  ruling;
- add ObserveAdvance to the observer and regenerate shared verdict vectors.

Primary owned files:

- offchain/lib/Cardano/KERI/AID/Checkpoint/Advance.hs
- offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs
- offchain/test/Cardano/KERI/AID/Checkpoint/AdvanceSpec.hs
- offchain/test/Cardano/KERI/AID/Checkpoint/MessageSpec.hs
- offchain/app/GenAdvanceVectors.hs
- offchain/app/GenCheckpointVectors.hs
- offchain/test/keri-fixtures/gen_fixtures.py and advance fixture metadata
  only if the pinned oracle must regenerate signature fields
- onchain/lib/cardano_keri/checkpoint/advance.ak
- onchain/lib/cardano_keri/checkpoint/advance_tests.ak
- onchain/lib/cardano_keri/checkpoint/advance_vectors.ak
- onchain/lib/cardano_keri/checkpoint/message.ak
- onchain/lib/cardano_keri/checkpoint/message_tests.ak
- onchain/lib/cardano_keri/checkpoint/vectors.ak
- onchain/validators/checkpoint_observer.ak
- onchain/validators/checkpoint_observer_tests.ak
- justfile, only affected vector drift recipes

Commit: feat(115): authenticate advance with the KERI event

Trailer: Tasks: T115-R3

## Slice R4 — open ACTIVE, ARMED, and FROZEN Advance

Goal: make one state-machine branch implement progress, response, and thaw.

RED:

- full contexts for ACTIVE exact-Value progress;
- ARMED just-before acceptance and exact/after-deadline rejection;
- FROZEN exact input-plus-B thaw;
- wrong role, malformed wrapper/datum, duplicate output, token/mint, Value
  drift, reserve, observer coupling, and time-bound negatives;
- live dispatch matrix and existing Register/Freeze/Claim regressions.

GREEN:

- dispatch Advance from all three live roles;
- normalize the spent inner datum, require the unique ACTIVE successor, and
  couple the exact own outref to ObserveAdvance;
- preserve the complete Value from ACTIVE/ARMED and add exactly B from
  FROZEN;
- remove ArmedV1 only on a valid pre-deadline response;
- activate the production-shaped E2E builders without falsifying the
  old-cost hash-proof boundary.

Primary owned files:

- onchain/validators/checkpoint.ak
- onchain/validators/checkpoint_observer.ak
- onchain/validators/checkpoint_tests.ak
- onchain/validators/checkpoint_observer_tests.ak
- offchain/e2e/CheckpointTxBuilder.hs
- offchain/e2e/CheckpointE2ESpec.hs

Commit: feat(115): advance every live checkpoint role

Trailer: Tasks: T115-R4

## Slice R5 — burn on conviction

Goal: remove permanent tombstones and align every executable model with the
ratified burn axiom.

RED:

- Convict from ACTIVE, ARMED, and FROZEN rejects without the exact minus-one
  mint, with any extra own-policy entry, with a continuing checkpoint or
  tombstone, or with wrong min-ADA/deposit/bond routing;
- pure model properties require burn-to-Absent, burn terminality in the
  transaction, value conservation, and fresh re-registration.

GREEN:

- replace the terminal output with exact token burn and the role-specific
  protected payouts including freed min-ADA;
- remove TombstoneV1, Tombstone role/tag, output predicates, codec goldens,
  terminal dispatch, and stale tests in both languages;
- update Lean, Haskell, generated parity vectors, Aiken lifecycle mirror,
  and the traceability map from tombstone semantics to burn semantics;
- leave tag 0x01 unused and make no reap/Close change.

Primary owned files:

- onchain/validators/checkpoint.ak
- onchain/validators/checkpoint_tests.ak
- onchain/lib/cardano_keri/checkpoint/enforcement.ak
- onchain/lib/cardano_keri/checkpoint/enforcement_tests.ak
- onchain/lib/cardano_keri/checkpoint/role.ak
- onchain/lib/cardano_keri/checkpoint/role_tests.ak
- onchain/lib/cardano_keri/checkpoint/lifecycle_model.ak
- onchain/lib/cardano_keri/checkpoint/lifecycle_model_tests.ak
- onchain/lib/cardano_keri/checkpoint/lifecycle_model_vectors.ak
- offchain/lib/Cardano/KERI/AID/Checkpoint/Enforcement.hs
- offchain/lib/Cardano/KERI/AID/Checkpoint/FreezeBond.hs
- offchain/lib/Cardano/KERI/AID/Checkpoint/LifecycleModel.hs
- corresponding EnforcementSpec, FreezeBondSpec, and LifecycleModelSpec
- offchain/app/GenEnforcementVectors.hs
- offchain/app/GenFreezeBondVectors.hs
- offchain/app/GenLifecycleTraceVectors.hs
- generated enforcement/freeze/lifecycle vectors affected by deletion
- lean/CardanoKeri/Lifecycle.lean
- lean/CardanoKeri/Goals.lean
- the checked traceability artifact and checker if required by the new goal

Commit: feat(115): burn convicted checkpoints

Trailer: Tasks: T115-R5

## Slice R6 — thirteen-row lifecycle and deployability report

Goal: turn the final deployable behavior into standing mechanical budgets.

RED:

- exact-title gate fails until the four Advance contexts and burn-shaped
  Convict rows replace the old nine-row set;
- any absent units, non-pass status, less than 25.00 percent headroom, size
  regression, or title drift fails.

GREEN:

- gate exactly the thirteen rows listed in spec.md;
- measure full observer-plus-checkpoint contexts at final parameter arity;
- retain limits of 10,500,000 memory and 7,500,000,000 CPU per ACCEPT row;
- record exact units, headroom, both applied sizes, parameter CBOR, and
  stock-cap verdict in MEASUREMENTS.md;
- run the full stock-cap E2E boundary.

Primary owned files:

- onchain/validators/checkpoint_measurements.ak
- justfile, only measure-checkpoint and deployability reporting
- specs/115-advance/MEASUREMENTS.md
- offchain/e2e files only if measurement extraction needs final labels

Commit: test(115): gate the deployable lifecycle budget

Trailer: Tasks: T115-R6

## Slice R7 — manual preprod runner and rolling demo

Goal: ship safe operator tooling without placing a public network or secret in
CI.

RED:

- dry-run/config tests reject missing key-dir environment, wrong modes,
  wrong address/network parameters, secret-path leakage, and accidental CI
  invocation;
- generated demo artifacts fail if the pinned keripy oracle cannot verify
  their AID/KEL.

GREEN:

- add a manual just recipe and repository runner for the ruled socket,
  container, magic, D_reg, B, and 120-second freeze window;
- apply and create both reference scripts, then build/submit Register, Arm,
  Claim and the extended Advance/response/thaw demo;
- register the observer stake credential in setup and record the dedicated or
  combined setup transaction id;
- emit a redacted structured record with script hashes, AIDs, txids, and
  explorer URLs;
- add genuine pinned-keripy demo material and verification;
- prove by dependency inspection that gate.sh, just ci, Nix checks, and
  GitHub workflows do not invoke it.

The slice runs only hermetic dry-run/unit verification. The actual public
preprod run happens manually after the final local gate.

Expected owned files:

- a new offchain app/module for preprod transaction construction
- offchain/cardano-keri.cabal
- offchain/flake.nix, app exposure only and never checks
- a new scripts/preprod-checkpoint entry point
- a new scripts/demo or offchain demo artifact directory
- justfile, one standalone manual recipe
- focused hermetic tests for config/redaction/keripy verification

The exact new filenames are frozen in the driver brief after R6 discovery;
expansion beyond these categories requires a Q-file.

Commit: feat(115): add the manual preprod checkpoint demo

Trailer: Tasks: T115-R7

## Slice R8 — advance and burn narrative

Goal: make the public design match the delivered contract and demo.

RED:

- stale fresh-signature, tombstone-UTxO, privileged replay, or absorbent
  ARMED/FROZEN claims are identified in the four owned documents;
- required permissionless-projection, totality, interference, burn-history,
  and demo-policy statements are absent before the edit.

GREEN:

- update only the #115-owned fragments named by spec.md;
- make ordinary replay, response, thaw, event-own signatures, incoming
  receipts, burn history, and genuine-keripy rolling demo explicit;
- state the observer registration liveness dependency and why its
  fail-closed certificate handler prevents deregistration;
- preserve all #117 work as held design language;
- pass strict MkDocs, links, and presentation checks.

Owned files:

- docs/architecture/identity-ops.md
- docs/design/trust-model.md
- docs/blog/self-certifying-identities-on-cardano.md
- docs/milestones-deck/index.html

Commit: docs(115): explain permissionless checkpoint replay

Trailer: Tasks: T115-R8

## Final verification and external gates

After R8:

1. Run ./gate.sh from a clean final HEAD and retry once only on a genuine
   transient failure.
2. Recompute both applied sizes independently and inspect the 13-row report.
3. Manually run the preprod recipe. Record both reference-script txids,
   observer stake-registration evidence, Register, Arm, Claim, and the
   rolling demo transaction ids and explorer URLs. Never place secret
   material in logs.
4. Update the PR body with final contract, measurements, stock-cap result,
   preprod evidence, demo evidence, and exact verification.
5. Push, monitor all required checks, and address failures through a new
   reviewed slice if behavior changes.
6. Write the mark-ready Q-file. Do not run gh pr ready and do not merge until
   the epic owner's A-file authorizes readiness.
7. After authorization, mark ready, re-check CI, and park for the epic owner
   to merge. The epic owner, not this ticket orchestrator, performs the merge.

## Hard stops

- No implementation before A-001.
- Either applied script at or above 16,133 bytes after two reviewed R1
  attempts.
- Any ACCEPT row below 25.00 percent headroom.
- Gate failure after one retry.
- Unfunded preprod wallet, leaked/incorrect key permissions, or public-network
  failure requiring operator action.
- Any need for mint/spend split, #117 work, a weakened evidence predicate, an
  unplanned trusted service, or files outside the active slice.
