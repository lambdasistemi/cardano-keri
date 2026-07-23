# Spec: permissionless advance projection (#115 re-land)

Issue: https://github.com/lambdasistemi/cardano-keri/issues/115

Epic: https://github.com/lambdasistemi/cardano-keri/issues/24

Status: pre-implementation specification checkpoint. This document supersedes
the fresh-signature design delivered by PR #120 and the previous completed
contents of this directory. The implementation base is main at 91ccc71, after
the reopened #116 and #114 re-lands.

## Source of record

The refreshed issue body dated 2026-07-22 and its 2026-07-21 reopen comment
are authoritative. The inherited contracts in specs/68-keystate-shape,
specs/92-checkpoint-contention, specs/106-enforcement,
specs/114-permissionless-registration, and specs/116-freeze-bond remain
binding except where this ticket carries an explicit ratified amendment.

The following operator rulings are also binding:

- A-015 from #116: the deployable reference-script program budget is 16,133
  bytes; #115 begins with withdraw/observer forwarding and preserves one
  checkpoint hash h as both minting policy and payment credential.
- The 2026-07-22 burn axiom: live state belongs in the UTxO set, history
  belongs in transactions; Convict burns instead of writing a tombstone.
- The manual-preprod and rolling-demo directives in the ticket brief.

No implementation starts before the epic owner approves Q-001.

## Problem

The merged checkpoint can register, arm, claim, and convict, but ordinary
Advance is still fail closed. The dormant advance code authorizes a
Cardano-specific AdvanceMessage rather than the public KERI event itself,
only handles ACTIVE and FROZEN, and does not implement the reopened value and
deadline rules. The monolithic applied checkpoint is also 23,124 bytes,
6,991 bytes over the 16,133-byte creation-transaction budget, so it cannot be
deployed under the real 16,384-byte transaction cap.

This ticket makes a valid KERI rotation a permissionless projection. Anyone
may submit the public event because every accepted successor field,
destination, token quantity, and protected value is forced. The event's own
controller signatures and incoming witness receipts are the only
authentication evidence. No fresh Cardano-domain signature exists.

## Scope

### In scope

1. R1 first: move heavy KERI evidence verification into two zero-value
   withdrawal observers split by evidence family while the checkpoint retains
   mint/spend state-machine and exact observer-ran checks. The checkpoint and
   both applied observers must each be strictly below 16,133 bytes before
   feature work continues.
2. R2 second: delete the isolated 32 KiB devnet genesis, restore the stock
   16,384-byte cap, remove the NON-DEPLOYABLE banner, and permanently gate
   all three applied sizes plus the absence of executable 32,768-byte overrides.
3. Delete AdvanceMessage and its canonical-CBOR fresh-signature domain in
   Haskell and Aiken. Controller signatures verify the exact KERI event bytes.
4. Admit one Advance branch from ACTIVE, ARMED, and FROZEN with the exact
   deadline and value rules below.
5. Replace Convict tombstone creation with the ratified burn transition and
   remove tombstone-only production, schema, role, and lifecycle-model
   surfaces.
6. Preserve generated Haskell/Aiken byte and verdict parity, add
   advance-totality and bounded-interference adversarial coverage, and gate
   exactly thirteen full-handler ACCEPT measurements.
7. Activate the honest live-node surface at the stock cap, ship a
   manual-only preprod runner, settle all three reference scripts and the required
   lifecycle on preprod, and refresh the genuine-keripy demo.
8. Update the #115-owned advance/replay fragments in architecture, trust
   model, M1 blog, and M1 milestones deck.

### Out of scope

- Any #117 Close, CLOSING, consumer lookup, reap, W_close, or W_reap work.
- Mint/spend splitting. It breaks the single-h contract and still requires a
  fresh operator ruling.
- A global registry, mint-once gate, batcher, sequencer, authoritative
  indexer, or new trusted party.
- A KERI SAID proof over rotation bytes. The previously ratified event-slice,
  signature, and receipt boundary remains.
- Production KERI witness or watcher infrastructure. Local or simulated
  services are allowed around genuine keripy-verifiable artifacts.
- Any secret, live network, or preprod invocation in gate.sh, just ci, or a
  GitHub workflow.

## R1 deployable architecture

### Three applied scripts, one identity hash

The production blueprint has three independently applied Plutus V3 programs:

1. checkpoint: the existing minting policy and spending validator. Its script
   hash h remains the checkpoint policy id, ACTIVE payment credential, and
   input to every role-address derivation.
2. observer_lifecycle: a withdrawal validator for Register and, when R3 opens
   it, Advance. Those actions share KEL-event binding, threshold, signature,
   and receipt machinery.
3. observer_enforcement: a withdrawal validator for Freeze and Convict,
   sharing the enforcement-evidence binding and fork/lag predicates.

Both observer hashes are deployment parameters of checkpoint. Neither
observer becomes an AID identity or policy hash, and h is not split. Each
observer is parameterized only by immutable values needed by its own evidence
family; its redeemer names the checkpoint hash and action context. This avoids
a circular script-hash dependency. The old network_id deployment parameter
existed only to bind the deleted AdvanceMessage and is removed from the final
applied scripts.

The final R1 parameter order is exact: observer_lifecycle receives version,
hash-proof policy, and D_reg; observer_enforcement receives version only; and
checkpoint receives version, lifecycle observer hash, enforcement observer
hash, D_reg, freeze bond, and freeze window. Both observers are applied and
hashed before checkpoint. Event-own Advance does not restore network_id.

A-004 selected this family split after an independently reproduced forward
probe rejected the intermediate checkpoint-plus-Register partition: that
checkpoint applied at 12,239 bytes, but a Freeze+Convict+Advance observer
applied at 20,092 bytes and had -3,960 bytes of the required maximum-valid R3
slack. The scratch probe does not count as an implementation attempt and is
removed before the R1 commit. Shared predicate libraries remain read-only.

### Zero-withdrawal coupling

Every evidence-bearing transaction contains exactly the selected family
observer's reward-account entry at zero lovelace and a matching Withdraw
redeemer: observer_lifecycle for Register/Advance, observer_enforcement for
Freeze/Convict. A transaction cannot substitute the other family credential
or action. ClaimFreeze carries no KERI evidence and needs neither observer.
Evidence exists once, in the selected observer redeemer. The checkpoint
redeemers remain slim state-machine commands: Register and Advance carry no
evidence; Freeze retains hunter_pkh only; Convict retains beneficiaries and
output indices only.

Each observer's script stake credential must be registered before, or in, the
first transaction that selects it on every network. An unregistered reward
account cannot supply the required withdrawal and therefore cannot satisfy
the checkpoint ran-check. Devnet E2E registers both credentials before
lifecycle transactions. Manual preprod setup registers every deployed
observer in dedicated transactions or alongside reference-script creation,
and records every registration transaction id.

The observer redeemer is an envelope with a small claim
(action tag, checkpoint h, and optional own outref) plus an opaque evidence
payload. The checkpoint inspects only the claim and never imports or decodes
the evidence type. The observer checks the same claim and decodes the payload
as the exact evidence type selected by the action.

For each action, the checkpoint selects exactly one configured observer hash
and performs an inexpensive ran-check:

- its transaction contains Pair(Script(selected_observer_hash), 0);
- the redeemer map contains the matching Withdraw purpose;
- that redeemer decodes to the expected action for that observer family;
- the action names the same checkpoint h and, for spends, the same own input
  reference; and
- neither the other family observer nor any alternative credential or
  mismatched action can satisfy the check.

The selected observer sees the same transaction. observer_lifecycle validates:

- ObserveRegister: proof-token input and exact hash-proof-policy burn,
  inception event binding, event-own controller signatures, witness receipts,
  projection, and registration reserve predicate for the named h output;
- ObserveAdvance: rotation transition, event-own controller signatures,
  dual thresholds, witness delta, event binding, and incoming receipt quorum
  for the named h input and ACTIVE successor.

observer_enforcement validates:

- ObserveFreeze: existing enforcement binding plus freeze predicate for the
  named h input;
- ObserveConvict: existing enforcement binding plus conviction predicate for
  the named h input.

The checkpoint keeps all checkpoint-policy token, role, datum, output-count,
mint/burn, payout, deadline, and complete-Value arithmetic. The observer owns
the distinct hash-proof-policy proof input/burn check because computing its
event-derived token name is evidence verification. Moving verification
between scripts must not weaken a predicate, change vector verdicts, or bound
unrelated inputs/reference inputs. The observer action and checkpoint
ran-check are covered by mismatch, absent-withdrawal, nonzero-withdrawal,
wrong-purpose, wrong-h, wrong-outref, wrong-action, cross-family-observer, and
malformed-envelope negatives.

For R1 only, observer_enforcement also owns the tombstone `evidence_said`
equality; this transitional carve-out preserves the existing verdict until R5
deletes the tombstone surface and removes the check without residue.

### Stake-credential liveness

Each observer validator admits only its Withdraw purpose. Every certificate,
including deregistration of either observer's own script stake credential,
reaches that validator's fail-closed handler. Under Conway's
script-credential authorization rule, a deregistration therefore cannot be
authorized: no payment key, operator, or third party can remove either
registered credential. Focused full-context certificate tests pin both
refusals. The E2E coupling RED also covers an unregistered reward account per
observer if the node-client harness can construct the case; if it cannot, the
slice records the harness limitation and retains typed certificate refusals
plus live registered-path proof for both.

This matters for liveness: successful deregistration would make that observer
family's evidence-bearing checkpoint paths unsatisfiable, because the
checkpoint requires its withdrawal and the ledger requires the reward account
to be registered. Registration of both credentials plus fail-closed
certificate dispatch is therefore a deployment invariant, not an operator
convention.

### Size hard stop

R1 is accepted only when the exact final-arity applied checkpoint,
observer_lifecycle, and observer_enforcement programs are each less than
16,133 bytes. The measurement uses silent traces, the pinned Aiken toolchain,
and the same CBOR parameter order used by the off-chain transaction builder. A
full signed reference-script creation transaction for every program is also
constructed at the stock cap.

The A-004 probe is followed by at most two complete, reviewed RED/GREEN
attempts of this chosen family split. If any program still misses after those
attempts, the pair stops and files a Q-file. Checks may not be weakened,
traces required for behavior may not be hidden, shared predicate libraries
may not be edited for byte hunting, and mint/spend splitting may not be
attempted.

## R2 production-cap restoration

Immediately after R1:

- remove offchain/flake.nix e2eGenesis and every executable
  maxTxSize 16384 to 32768 rewrite;
- use the one stock cardano-node-clients genesis for cage and checkpoint E2E;
- remove the NON-DEPLOYABLE runtime banner and overage tuple;
- add a permanent hermetic size recipe invoked by just ci that builds and
  applies all three programs and rejects any size greater than or equal to
  16,133;
- add a permanent source guard rejecting 32768 in executable harness,
  workflow, or configuration files while allowing clearly labelled
  historical measurement/spec records; and
- rerun the checkpoint live-node boundary at stock 16,384.

The pinned devnet's old Plutus V3 price table remains an honest upstream
boundary tracked by cardano-node-clients#190. R2 does not falsify a positive
hash-proof settlement there. Rows blocked only by that price table remain
explicitly pending on #190; production-price positive settlement is proved
manually on preprod in this ticket.

## Permissionless Advance evidence

AdvanceEvidence continues to carry the exact keripy rotation serialization,
field offsets, ordered witness cut/add lists, indexed controller signatures,
and indexed witness receipts. Its signature meaning changes:

- ctrl_sigs indexes NEW.cur_keys and every counted signature verifies over
  event_bytes exactly;
- wit_receipts indexes the derived incoming witness set and verifies over
  the same event_bytes exactly.

AdvanceMessage, advance_domain, message reconstruction, canonical-CBOR
serialization, deployment fields, and out-ref fields are deleted from the
authorization surface. Transaction context binds h and the spent outref;
the event and successor datum bind the KERI transition. No compatibility
shim or fresh signature remains.

### State and event checks

For OLD, NEW, and evidence E, the observer checks in order:

1. NEW.cesr_aid equals OLD.cesr_aid; NEW.seq equals OLD.seq + 1; and
   NEW.native_sn is strictly greater than OLD.native_sn.
2. E.wit_cut is distinct and every member exists in OLD.witnesses.
3. E.wit_add is distinct, disjoint from cuts, and absent from survivors.
4. NEW.witnesses equals survivors in OLD order followed by additions in
   event order; NEW.toad is datum-well-formed.
5. Distinct valid controller signature positions satisfy
   NEW.cur_threshold over NEW.cur_keys.
6. Those same revealed valid keys, after blake3_256(qb64(verkey)), satisfy
   OLD.next_threshold against OLD.next_keys. Stolen OLD.current keys alone
   never authorize a rotation; a real partial 3-of-7 reserve reveal does.
7. AE1 through AE10 bind t, i, s, k, kt, n, nt, br, ba, and bt slices of
   event_bytes to NEW and the validated delta. Expected values are computed;
   offsets only locate.
8. If NEW.toad is zero, the incoming set and receipt list are both empty.
   Otherwise distinct valid receipts from the derived incoming set are at
   least NEW.toad. A cut or outgoing-only witness is at no eligible index.

Signatures and receipts always cover full event_bytes, never the event SAID.
The deliberate no-d/no-p and no-whole-event-Blake3 ruling remains. The only
Blake3 work in Advance is per-revealed-key pre-rotation commitment matching.

## Advance role and value matrix

Every successful Advance creates exactly one ACTIVE/V1 output with the same
derived AID token at quantity one. The complete own-policy mint map is empty.
The successor datum is the unique projection of the real next KERI event.

| Input role | Time condition | Successor complete Value |
| --- | --- | --- |
| ACTIVE | none | exactly input Value |
| ARMED | finite upper validity endpoint strictly before stored deadline | exactly input Value |
| FROZEN | none | exactly input Value plus exactly B lovelace |

ARMED response removes the ArmedV1 wrapper, advances the inner checkpoint,
returns to ACTIVE, and keeps B. At the exact deadline response rejects and
ClaimFreeze accepts. FROZEN thaw may be submitted by anyone but must add B;
third-party top-up is a donation with no independent refund right. All three
successors meet the ACTIVE reserve and preserve every unrelated native asset
and surplus unit. No alternate response or thaw redeemer exists.

Wrong role, duplicate ACTIVE output, wrong datum version, value drift, missing
or extra AID token, own-policy mint/burn, invalid or infinite required time
bound, non-increasing sequence, or any evidence failure rejects.

## Ratified conviction burn

Convict retains the existing witnessed-fork evidence and role-specific
beneficiaries, but the terminal shape changes:

- the full own-policy mint map is exactly the derived AID asset at quantity
  minus one;
- no checkpoint-role continuing output is created;
- ACTIVE pays exactly min-ADA + D_reg + B to the convictor;
- ARMED pays exactly min-ADA + D_reg to the convictor and exactly B to the
  stored hunter at a distinct output index;
- FROZEN pays exactly min-ADA + D_reg to the convictor;
- unrelated surplus remains ordinary transaction change.

TombstoneV1, the Tombstone role/tag, tombstone output predicates, terminal
dispatch, codec goldens, and their Haskell/Aiken tests are deleted. The pure
lifecycle state after conviction is Absent with a burned-token terminal
event in ledger history; fresh registration remains admissible. The tag 0x01
is freed but not reused by this ticket. #117 owns every other exit and reap
path.

## Models, vectors, and parity

Existing genuine keripy advance fixtures remain the oracle and are
regenerated only through the pinned fixture environment. The positive family
includes unwitnessed 2-key, witnessed 2-key, no-delta witnessed, witness
downgrade, and GLEIF-shaped 3-of-7 reserve rotation. Controller signatures in
generated vectors are re-derived over event_bytes, and the old
AdvanceMessage goldens disappear.

Required adversarial families cover:

- every AE1 through AE10 slice and offset-misdirection class;
- wrong-preimage, bad-index, duplicate-index, below-new-threshold, and
  below-old-commitment controller evidence;
- stolen current-key quorum and valid partial reserve reveal;
- malformed cut/add sets, wrong survivor order, datum mismatch, and bad bt;
- missing, duplicate, misindexed, cut, outgoing-only, and insufficient
  incoming receipts;
- absent or mismatched observer execution and action coupling;
- ACTIVE, ARMED, and FROZEN value/time/output/token negatives;
- repeated Arm, early/exact/late Claim/response boundary, and all live-role
  dispatch combinations;
- Convict without burn, wrong burn map, continuing tombstone, redirected
  payout, and re-registration after burn.

The pure Haskell lifecycle model, QuickCheck properties, generated
Haskell-to-Aiken vectors, and full Aiken contexts agree on:

- ordinary Advance is admissible from every reachable live role in this
  ticket: ACTIVE progress, ARMED response before deadline, FROZEN thaw;
- adversarial interference is bounded: a real next event makes progress,
  Arm opens one exclusive bounded window, Claim needs full-window absence,
  and Convict needs a real fork;
- conviction burns to Absent and does not bar a later registration; and
- value conservation includes the exact B top-up and freed min-ADA payout.

No #117 constructors are opened or changed. Existing future-model Closing
symbols remain abstract staging only.

## Thirteen-row measurement gate

The full applied scripts and real handler contexts are measured under the
strict internal ceiling of 14,000,000 memory and 10,000,000,000 CPU. Every
ACCEPT row must use at most 10,500,000 memory and 7,500,000,000 CPU, leaving
at least 25.00 percent headroom on both axes. A miss is a hard stop and Q-file,
never permission to weaken a fixture or predicate.

Exactly these thirteen rows are gated:

1. Register 2-key unwitnessed
2. Register witnessed 2-of-2 controller and 2-of-3 receipts
3. Register GLEIF-shaped 7-key
4. Arm 2-key
5. Arm 7-key
6. Claim
7. Convict ACTIVE burn
8. Convict ARMED burn
9. Convict FROZEN burn
10. Advance ACTIVE witnessed 2-key
11. Advance ACTIVE GLEIF 3-of-7
12. Advance ARMED response before deadline
13. Advance FROZEN thaw with B top-up

Each evidence-bearing row exercises the checkpoint and its selected family
observer in the same full transaction context and records per-script execution
units where the tool exposes them. MEASUREMENTS.md records exact units,
percentages, headroom, all three applied sizes, parameter CBOR, and the
stock-cap verdict.

## Live-node, preprod, and demo boundary

### Hermetic live-node gate

The repository E2E builder applies all three production scripts with final
parameter arity, posts all three reference scripts under stock maxTxSize
16,384, and runs every row the pinned devnet can price honestly. The existing exact
old-cost Plomin rejection and PENDING(blocked-on=#190) labels remain truthful
until the upstream fixture supports the production price table. No synthetic
validator, injected state UTxO, or widened cap substitutes.

### Manual-only preprod runner

A named just recipe invokes repository tooling only when the operator runs it.
It requires KERI_PREPROD_KEY_DIR in the environment, validates that the
directory is /home/paolino/.secrets/cardano-keri-preprod or an explicitly
provided equivalent, requires directory mode 700 and key-file mode 600, and
never prints key contents. It uses:

- socket /code/cardano-preprod/ipc/node.socket;
- cardano-cli from container cardano-preprod;
- testnet magic 1;
- payment address
  addr_test1vzdqjmt98smx8my6f5uum0szghuy8ff2hep2e64a9w2pehgnv4mdx;
- D_reg = 5,000,000 lovelace;
- B = 5,000,000 lovelace;
- W_freeze = 120,000 POSIX milliseconds;
- checkpoint version 0; the Cardano testnet network id is 0, but network id is
  no longer an applied script parameter after AdvanceMessage deletion.

The planning query found 10,000,000,000 lovelace at
b57dc12001e759ce06d25de1a5a2c0b9789e650a799663b27c6891f526d575ca#0,
so no funding blocker exists.

The recorded manual run must settle:

1. one reference-script creation transaction for checkpoint;
2. one reference-script creation transaction for observer_lifecycle;
3. one reference-script creation transaction for observer_enforcement;
4. stake-credential registration for both observers, either as dedicated setup
   transactions or in reference-script transactions;
5. a production-price permissionless Register of a genuine keripy AID;
6. Arm of that checkpoint from genuine later-event evidence; and
7. Claim at or after the stored deadline.

The rolling demo additionally exercises the #115 lifecycle available at the
final tree: ordinary ACTIVE advance, ARMED response, and FROZEN thaw using a
short genuine keripy KEL. If a genuine fork fixture can be demonstrated
without pretending to run production witness infrastructure, the demo may
also show Convict burn; it is not a substitute for the mandatory Aiken burn
tests.

Every introduced AID and KEL is produced and verified by the pinned keripy
oracle. Local or simulated witnesses/watchers are allowed. Output records
script hashes, AIDs, transaction ids, and explorer URLs without secret
material. The operator pastes explorer-verifiable transaction ids into the
PR body and mark-ready Q-file.

The preprod recipe is absent from gate.sh, just ci dependencies, Nix checks,
and .github workflows. CI remains hermetic.

## Pair-owned documentation

The implementation pair, never the ticket orchestrator, updates only the
#115-owned fragments in:

- docs/architecture/identity-ops.md;
- docs/design/trust-model.md;
- docs/blog/self-certifying-identities-on-cardano.md; and
- docs/milestones-deck/index.html.

The narrative makes permissionless projection and replay concrete, deletes
fresh Cardano authorization language, explains event-own signatures,
incoming receipts, ACTIVE/ARMED/FROZEN value behavior, and centers
advance-totality plus bounded adversarial interference. It says conviction
is recorded in the transaction history and the token is burned, not kept in a
tombstone UTxO. The trust model also states that the registered observer
credential is a liveness dependency and that its fail-closed certificate
handler makes deregistration unauthorized. The deck retains the approved
line: anyone can project the public truth; no one can lie about it or lock
you out of it.

All Close discussion remains a clearly held #117 design note with distinct
W_close. This ticket neither specifies nor implements it. Strict MkDocs,
link, and presentation checks must pass.

## Acceptance criteria

- [ ] The checkpoint and both observer exact applied programs are each less
      than 16,133 bytes and all three signed reference-script creation shapes
      fit stock 16,384.
- [ ] No executable 32,768-byte devnet override or NON-DEPLOYABLE banner
      remains; permanent size and source guards run in just ci.
- [ ] Family-split observer forwarding is transaction-coupled and every
      absent/mismatched withdrawal, cross-family credential, or observer action
      rejects without changing evidence verdicts.
- [ ] Both observer stake credentials are registered in devnet and preprod
      setup; certificate-purpose tests prove both observers refuse
      deregistration, and any unregistered-path limitation is explicit if the
      live harness cannot construct it.
- [ ] AdvanceMessage and every fresh-signature preimage/helper/golden are
      deleted. Controller signatures and witness receipts cover event_bytes.
- [ ] Real pinned-keripy witnessed rotations advance from ACTIVE; forged,
      under-signed, under-witnessed, or wrong-projection variants reject.
- [ ] A full stolen current-key set cannot rotate; GLEIF-shaped partial
      3-of-7 reserve reveal succeeds.
- [ ] ARMED response is accepted only before the deadline and preserves the
      complete Value; FROZEN thaw adds exactly B and preserves all else.
- [ ] Convict burns exactly one AID token, creates no tombstone, pays the
      role-specific protected value including freed min-ADA, and permits
      later registration.
- [ ] Haskell/Aiken bytes and verdicts agree; advance-totality and bounded
      interference properties are executable.
- [ ] Exactly thirteen full-handler rows pass with at least 25.00 percent
      memory and CPU headroom.
- [ ] Stock-cap live-node checks are honest about cardano-node-clients#190.
- [ ] The manual preprod record contains three reference-script txids,
      stake-registration evidence for both observers, and the Register, Arm,
      and Claim txids, all explorer-verifiable.
- [ ] The refreshed demo uses genuine pinned-keripy AIDs/KELs and proves
      ACTIVE advance, ARMED response, and FROZEN thaw on preprod.
- [ ] The named #115 documentation fragments pass their strict gates and no
      #117 implementation is present.
