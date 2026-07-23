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

## Slice R1 — family-split withdraw-0 observer forwarding

Goal: re-home the already-merged evidence predicates into two observers by
family without changing accepted transaction semantics: observer_lifecycle
owns Register (and the reserved fail-closed Advance tag), while
observer_enforcement owns Freeze and Convict. The A-004 forward probe rejected
checkpoint-plus-Register / Freeze+Convict+Advance at 12,239 / 20,092 bytes, so
the pre-agreed family split is binding and the scratch probe is removed before
commit.

RED:

- add exact family-ran coupling tests for missing withdrawal, nonzero amount,
  wrong family observer credential, missing/wrong Withdraw redeemer, wrong
  action, wrong h, and wrong own outref;
- prove Register cannot use observer_enforcement, Freeze/Convict cannot use
  observer_lifecycle, ObserveAdvance stays fail-closed in R1, and ClaimFreeze
  needs neither observer;
- add certifying-purpose tests proving each observer accepts plain
  registration of its own credential but rejects deregistration and every
  other certificate constructor, plus unregistered-reward-account live
  negatives per observer where the node-client harness can express them;
- port existing positive and adversarial predicate contexts through the
  selected family observer and demonstrate the checkpoint no longer supplies
  that verification;
- add exact applied-size assertions for checkpoint, observer_lifecycle, and
  observer_enforcement and observe the current single-observer partition fail.

GREEN:

- expose observer_lifecycle (ObserveRegister; ObserveAdvance reserved and
  fail-closed in R1) and observer_enforcement (ObserveFreeze/ObserveConvict),
  each using the same small claim plus opaque evidence envelope and admitting
  only Withdraw;
- parameterize checkpoint by both observer hashes, select exactly one family
  hash per action, and retain slim ran-checks plus all state, Value,
  checkpoint-policy token, role, payout, and deadline rules;
- move the event-derived hash-proof input/burn calculation into
  observer_lifecycle's ObserveRegister and remove the fresh-message-only
  network_id parameter;
- update the blueprint loader/builder to apply both observers first, derive
  both hashes, then apply checkpoint while retaining one checkpoint h;
- freeze final parameter order as lifecycle(version, hash-proof policy,
  D_reg), enforcement(version), then checkpoint(version, lifecycle hash,
  enforcement hash, D_reg, freeze bond, freeze window); network_id remains
  deleted;
- construct all three reference-script transaction shapes; and
- register both observer stake credentials in devnet setup before the first
  selected-family transaction through an exhaustive whitelist accepting only
  plain registration of the observer's own credential while keeping
  deregistration and every other certificate constructor fail closed;
- require all three exact applied programs to be less than 16,133 bytes.

Primary owned files:

- onchain/validators/checkpoint.ak
- onchain/validators/checkpoint_observer.ak
- onchain/lib/cardano_keri/checkpoint/observer.ak
- onchain/lib/cardano_keri/checkpoint/observer_tests.ak
- onchain/validators/checkpoint_tests.ak
- onchain/validators/checkpoint_observer_tests.ak
- offchain/e2e/CheckpointTxBuilder.hs
- offchain/e2e/CheckpointE2ESpec.hs
- justfile, only the applied-size recipe and gate wiring

No Advance branch is opened in R1. The full existing gate plus focused Aiken
contexts and exact three-program sizing must pass. The A-004 probe does not
consume the cap; after two failed complete reviewed attempts of this family
split, stop with a Q-file. Shared predicate libraries stay read-only and
mint/spend splitting is forbidden.

Commit: feat(115): split checkpoint evidence observers

Trailer: Tasks: T115-R1

## Slice R2 — restore the production transaction cap

Goal: remove the temporary size fiction immediately after R1 proves all three
final-arity programs deployable.

RED:

- a source guard fails while the 32,768 rewrite and NON-DEPLOYABLE runtime
  banner exist;
- the stock-genesis checkpoint E2E must expose any reference-script
  creation or transaction-size regression.

GREEN:

- delete e2eGenesis and route checkpoint E2E to the stock 16,384 genesis;
- delete the banner and overage tuple;
- add each observer's exhaustive certifying whitelist: accept only plain
  registration of its own script credential; reject deregistration,
  delegation, DRep, pool, and every other certificate constructor;
- build the registration certificate's `ConwayCertifying (AsIx 0)` redeemer
  and script-integrity material before balancing;
- make the permanent just ci gate reject any of the three programs at or above 16,133
  and reject 32768 in executable/configuration surfaces;
- settle all three reference-script creation transactions on the local stock
  devnet;
- rerun the truthful old-cost boundary, preserving explicit
  PENDING(blocked-on=#190) positive hash-proof rows.
- record follow-up debt without widening R2: `submitSettling` currently proves
  only mempool acceptance despite its name. R2 keeps the settlement barrier
  local to observer registration; a later slice or follow-up ticket should
  either rename the helper or make its global contract actually settle.

Primary owned files:

- offchain/flake.nix
- offchain/e2e/CheckpointTxBuilder.hs
- offchain/e2e/CheckpointE2ESpec.hs
- justfile, only deployability/source guards and E2E labels
- onchain/validators/checkpoint_observer.ak
- onchain/validators/checkpoint_observer_tests.ak

Commit: fix(115): restore the production transaction cap

Trailer: Tasks: T115-R2

## Slice R3 — event-own advance authentication

Goal: delete fresh Cardano authorization and make the exact KERI event the
sole signature preimage while completing the ratified four-program topology.

Before RED, the driver restores every previously owned R3 implementation,
test, fixture, pin, and recipe path byte-exactly to the navigator-approved
pre-probe GREEN diff. Root-owned spec.md, plan.md, and tasks.md remain
untouched. The scratch probe is evidence, not a production edit or reusable
RED.

RED:

- convert positive controller evidence to signatures over event_bytes;
- prove old AdvanceMessage signatures, event-byte mutations, wrong indices,
  duplicate indices, stolen-current quorum, under-threshold evidence,
  malformed witness deltas, receipt games, and AE offset misdirection reject;
- preserve the genuine GLEIF 3-of-7 and witnessed rotations;
- introduce a dedicated observer_advance and prove observer_lifecycle is
  Register-only, observer_advance is Advance-only, and
  observer_enforcement remains Freeze/Convict-only;
- prove checkpoint selects the lifecycle, advance, or enforcement credential
  exactly by action, with missing, nonzero, extra, cross-family, and
  wrong-action withdrawals rejected and ClaimFreeze requiring no observer;
- prove observer_advance plain registration succeeds while deregistration and
  every other certificate constructor fail;
- prove the final checkpoint fourth-hash parameter and three-way observer
  selection, all four exact applied-size rows, and all four stock-cap signed
  reference-script transaction shapes;
- prove the fourth-program observer_advance registration choreography in the
  builder and E2E harness, including witness, ConwayCertifying redeemer,
  collateral, prepareWallet split, and pollOutput settlement; and
- run the fresh focused production oracle, including all 47 Haskell and 65
  Aiken cases represented in the approved probe. No scratch result substitutes
  for watching this RED fail for the intended missing topology.

GREEN:

- delete AdvanceMessage, advance_domain, reconstruction, canonical-CBOR
  signature helpers, goldens, and stale exports in both languages;
- refactor the pure transition predicate around OLD, NEW, and
  AdvanceEvidence;
- count only distinct NEW.cur_keys signatures over event_bytes, then apply
  both the NEW current threshold and OLD next-key commitment threshold;
- preserve AE1-AE10, W1-W3, exact incoming-set receipts, and the no-d/no-p
  ruling;
- implement observer_advance for Advance and reduce observer_lifecycle to
  Register; keep observer_enforcement Freeze/Convict-only;
- apply the two A-017-approved representation-preserving changes: share the
  equivalent ACTIVE address/from_script result and express the certifying
  whitelist as RegisterCredential success with every other constructor
  failing;
- add the fourth observer hash and three-way action selection to checkpoint,
  apply/load all four programs in E2E, and register observer_advance with the
  same reviewed witness/redeemer/collateral/wallet-split/settlement
  choreography; do not restore the four redundant action-wallet splits removed
  by A-013;
- independently re-prove the production semantic oracle and per-context
  execution units, require every applied program below 16,133 bytes,
  observer_advance no larger than 15,333 bytes with at least 800 bytes slack,
  and construct all four signed reference-script shapes at stock 16,384; and
- after all validator changes, repin only offchain/flake.nix outputHash using
  the A-009 observed-hash discovery cycle and preserve observer-title proof.

Exact R3 ownership fence:

- offchain/lib/Cardano/KERI/AID/Checkpoint/Advance.hs
- offchain/lib/Cardano/KERI/AID/Checkpoint/Message.hs
- offchain/flake.nix, outputHash only when the tracked on-chain blueprint
  change requires the fixed-output repin; use the observed-hash discovery
  cycle and do not change any other flake field
- offchain/test/Cardano/KERI/AID/Checkpoint/AdvanceSpec.hs
- offchain/test/Cardano/KERI/AID/Checkpoint/MessageSpec.hs
- offchain/app/GenAdvanceVectors.hs
- offchain/app/GenCheckpointVectors.hs
- offchain/e2e/CheckpointTxBuilder.hs
- offchain/e2e/CheckpointE2ESpec.hs
- offchain/test/keri-fixtures/gen_fixtures.py
- offchain/test/keri-fixtures/fixtures/advance.json
- offchain/test/keri-fixtures/fixtures/manifest.json
  (these three fixture paths are writable only through the pinned oracle when
  it must regenerate signature fields; no hand-edited generated evidence)
- onchain/lib/cardano_keri/checkpoint/advance.ak
- onchain/lib/cardano_keri/checkpoint/advance_tests.ak
- onchain/lib/cardano_keri/checkpoint/advance_vectors.ak
- onchain/lib/cardano_keri/checkpoint/message.ak
- onchain/lib/cardano_keri/checkpoint/message_tests.ak
- onchain/lib/cardano_keri/checkpoint/observer.ak
- onchain/lib/cardano_keri/checkpoint/observer_tests.ak
- onchain/lib/cardano_keri/checkpoint/vectors.ak
- onchain/validators/checkpoint.ak
- onchain/validators/checkpoint_tests.ak
- onchain/validators/checkpoint_observer.ak
- onchain/validators/checkpoint_observer_tests.ak
- onchain/validators/checkpoint_measurements.ak, mechanical checkpoint-arity
  co-change only: add one advance_hash constant and thread it in the same
  argument position through the existing checkpoint.checkpoint.mint/spend
  calls; do not change benchmark shapes, thresholds, row content, or any
  other R6-owned behavior
- justfile, affected vector drift plus four-program deployability-size and
  signed-reference-shape wiring only

Standing compile-coupling rule for this and every later slice: when a required
arity/type co-change reaches into another slice's owned file, the driver
discloses it, the navigator checks its content, the pair blocks, and root
rules on the exact scope. No mechanical carve-out is silent or self-approved.

The R3 commit body must state that checkpoint_measurements.ak changed
mechanically because checkpoint gained the advance-observer hash parameter,
and that no R6 benchmark behavior changed.

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
- measure full selected-observer-plus-checkpoint contexts at final parameter
  arity and record all four applied program sizes;
- retain limits of 10,500,000 memory and 7,500,000,000 CPU per ACCEPT row;
- record exact units, headroom, all four applied sizes, parameter CBOR, and
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
- apply and create all four reference scripts, then build/submit Register,
  Arm, Claim and the extended Advance/response/thaw demo;
- register all three observer stake credentials in setup, including the
  fourth-program observer_advance witness/redeemer/collateral/prepareWallet
  split/pollOutput settlement choreography, and record every dedicated or
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
- state all three observer-registration liveness dependencies using the final
  invariant: each observer's stake credential is creatable once by anyone and
  removable by no one; its whitelist accepts only plain registration and
  rejects deregistration and every other certificate constructor;
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
2. Recompute all four applied sizes independently and inspect the 13-row
   report.
3. Manually run the preprod recipe. Record all four reference-script txids,
   all three observer stake-registration proofs, Register, Arm, Claim, and the
   rolling demo transaction ids and explorer URLs. Never place secret material
   in logs.
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
- Any of checkpoint, observer_lifecycle, observer_advance, or
  observer_enforcement at or above 16,133 bytes; observer_advance above 15,333
  bytes or below 800 bytes of slack; or failure of any of the four signed
  reference-script shapes at stock cap. The historical two-attempt R1 limit
  and A-004 forward-probe exclusion remain recorded in the R1 evidence.
- Any ACCEPT row below 25.00 percent headroom.
- Gate failure after one retry.
- Unfunded preprod wallet, leaked/incorrect key permissions, or public-network
  failure requiring operator action.
- Any need for mint/spend split, #117 work, a weakened evidence predicate, an
  unplanned trusted service, or files outside the active slice.
