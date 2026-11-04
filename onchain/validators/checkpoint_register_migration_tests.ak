//// #136 — real-script tests for the register-only checkpoint vertical.

use aiken/builtin
use aiken/cbor
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cage_context.{
  input_at, min_ada, mint_context, out_ref, owner_vkh, seed_tx_id, spend_context,
}
use cardano/address.{
  Address, Credential, Script, from_script, from_verification_key,
  with_delegation_script,
}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/certificate.{RegisterCredential, UnregisterCredential}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, ScriptPurpose,
  Transaction, Withdraw, placeholder,
}
use cardano_keri/bounty_commitment.{
  BountyAction, BountyCommitment, BountyCommitmentV1, BountyRevealV1,
  BountyScope, CommitmentFamily, CommitmentParameters, ConvictEntitlement,
  commitment_domain, commitment_hash, commitment_preimage, commitment_schema,
  marker_name,
}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/advance_vectors as advance_vec
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, KeyMaterial, KeyStateView, Live, TerminationPending,
}
use cardano_keri/checkpoint/enforcement.{EnforcementEvidence}
use cardano_keri/checkpoint/enforcement_vectors as enforcement_vec
use cardano_keri/checkpoint/entitlement.{
  EnforcementProofV1, enforcement_evidence_digest,
}
use cardano_keri/checkpoint/message.{
  SpentCheckpoint, deriveAidAssetName, qb64_aid,
}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_migration, observe_register,
}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, proof_token_name,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/retired_layout.{retired_layout}
use cardano_keri/checkpoint/role.{Active}
use cardano_keri/checkpoint/threshold.{Unweighted}
use cardano_keri/migration/checkpoint.{MigrateOutProof,
  MigrationProof} as migration_checkpoint
use cardano_keri/migration/checkpoint_vectors as mig_vec
use cardano_keri/migration/types.{
  CheckpointActive, MigrationAuthorization, MigrationPredecessor,
  MigrationTarget,
}
use checkpoint_observer
use checkpoint_register.{Advance}

/// The applied network these fixtures deploy under, matching the `network_id`
/// argument every applied register in this module is built with.
const network_id: Int = 1

const hp_policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

/// The promoted #254 migration observer this applied program requires for a
/// migrate arm. These regression tests exercise the pre-migration lifecycle,
/// which never withdraws under it.
const migration_hash: PolicyId =
  #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const lifecycle_hash: PolicyId =
  #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const advance_hash: PolicyId =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const enforcement_hash: PolicyId =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const entitlement_hash: PolicyId =
  #"ffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

test lifecycle_observer_registration_is_permissionless() {
  checkpoint_observer.observer_lifecycle.publish(
    0,
    hp_policy,
    d_reg,
    0,
    RegisterCredential { credential: Script(lifecycle_hash), deposit: Never },
    placeholder,
  )
}

test lifecycle_observer_deregistration_fails_closed() fail {
  checkpoint_observer.observer_lifecycle.publish(
    0,
    hp_policy,
    d_reg,
    0,
    UnregisterCredential { credential: Script(lifecycle_hash), refund: Never },
    placeholder,
  )
}

const mig_source_policy: PolicyId = mig_vec.fixture_source_policy

const mig_target_policy: PolicyId = mig_vec.fixture_target_policy

fn mig_keys() -> KeyMaterial {
  KeyMaterial {
    cur_keys: [
      mig_vec.fixture_ctrl_key_0,
      mig_vec.fixture_ctrl_key_1,
      mig_vec.fixture_ctrl_key_2,
    ],
    cur_threshold: Unweighted(2),
    next_keys: [mig_vec.fixture_next_key_0, mig_vec.fixture_next_key_1],
    next_threshold: Unweighted(1),
    witnesses: [mig_vec.fixture_witness_key],
    toad: 1,
  }
}

/// The live source the generator signed over, at epoch `epoch`.
fn mig_source_at(epoch: Int) -> CheckpointDatumV2 {
  Live {
    aid: qb64_aid(mig_vec.fixture_cesr_aid),
    sn: 4,
    epoch,
    poisoned: False,
    frozen: False,
    born_at: 1_800_000_000_000,
    refund_to: bytearray.concat(#"61", mig_vec.fixture_refund_vkey),
    keys: mig_keys(),
  }
}

fn mig_source_datum() -> CheckpointDatumV2 {
  mig_source_at(7)
}

/// The same identifier as a pending termination.
fn mig_pending_datum() -> CheckpointDatumV2 {
  TerminationPending {
    aid: qb64_aid(mig_vec.fixture_cesr_aid),
    sn: 4,
    epoch: 7,
  }
}

/// The same key state as the version 1 record.
fn mig_version_1_datum() -> KeyStateView {
  KeyStateView {
    cesr_aid: mig_vec.fixture_cesr_aid,
    cur_keys: mig_keys().cur_keys,
    cur_threshold: Unweighted(2),
    next_keys: mig_keys().next_keys,
    next_threshold: Unweighted(1),
    witnesses: mig_keys().witnesses,
    toad: 1,
    seq: 7,
    native_sn: 4,
  }
}

fn mig_source_ref() -> OutputReference {
  OutputReference {
    transaction_id: mig_vec.fixture_source_txid,
    output_index: 1,
  }
}

fn mig_predecessor() -> MigrationPredecessor {
  MigrationPredecessor {
    predecessor_policy: mig_source_policy,
    predecessor_ref: mig_source_ref(),
  }
}

fn mig_target() -> MigrationTarget {
  MigrationTarget {
    target_policy: mig_target_policy,
    target_role: CheckpointActive,
    target_address: from_script(mig_target_policy),
    legacy_refund_address: None,
  }
}

/// The controller-signed package. `signed_state` is what the quorum actually
/// put its signatures over, which is the whole subject of the replay control.
fn mig_authorization(signed_state: Data) -> MigrationAuthorization {
  mig_authorization_by(
    signed_state,
    [(0, mig_vec.fixture_sig_0), (1, mig_vec.fixture_sig_1)],
  )
}

fn mig_authorization_by(
  signed_state: Data,
  signatures: List<(Int, ByteArray)>,
) -> MigrationAuthorization {
  MigrationAuthorization {
    domain: mig_vec.golden_migration_domain,
    network_id: 1,
    source: mig_predecessor(),
    source_role: CheckpointActive,
    source_state: signed_state,
    target: mig_target(),
    controller_signatures: signatures,
  }
}

fn mig_signed_state() -> Data {
  expect Some(state) = cbor.deserialise(mig_vec.golden_source_state)
  state
}

const mig_protected: Int = min_ada + d_reg + freeze_bond

fn mig_source_input(carried: CheckpointDatumV2) -> Input {
  input_at(
    mig_source_ref(),
    Output {
      address: from_script(mig_source_policy),
      value: from_lovelace(mig_protected)
        |> merge(
            from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, 1),
          ),
      datum: InlineDatum(datum.write(carried)),
      reference_script: None,
    },
  )
}

/// The consumed source with an arbitrary inline datum.
fn mig_source_input_of(datum: Data) -> Input {
  input_at(
    mig_source_ref(),
    Output {
      address: from_script(mig_source_policy),
      value: from_lovelace(mig_protected)
        |> merge(
            from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, 1),
          ),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  )
}

fn mig_successor_output(carried: CheckpointDatumV2) -> Output {
  Output {
    address: from_script(mig_target_policy),
    value: from_lovelace(mig_protected)
      |> merge(from_asset(mig_target_policy, mig_vec.fixture_aid_asset_name, 1)),
    datum: InlineDatum(datum.write(carried)),
    reference_script: None,
  }
}

fn mig_replacement_mint() -> Value {
  from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, -1)
    |> merge(from_asset(mig_target_policy, mig_vec.fixture_aid_asset_name, 1))
}

/// The claim names the policy of the program that is asking. Migrate-out is
/// asked by the source generation, migrate-in by the target generation, so the
/// two directions carry different policies and different applied observers.
fn mig_envelope(
  claim_policy: PolicyId,
  proof: MigrationProof,
) -> ObserverEnvelope {
  ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_migration,
      checkpoint_policy: claim_policy,
      own_ref: Some(mig_source_ref()),
    },
    payload: proof,
  }
}

/// Run the promoted observer of one generation over a real transaction.
fn run_migration_observer(
  claim_policy: PolicyId,
  proof: MigrationProof,
  tx: Transaction,
) -> Bool {
  checkpoint_observer.observer_migration.withdraw(
    mig_envelope(claim_policy, proof),
    0,
    tx,
  )
}

/// The source program observes its own exit under the source policy.
fn run_migrate_out(proof: MigrationProof, tx: Transaction) -> Bool {
  run_migration_observer(mig_source_policy, proof, tx)
}

// INV-254-REPLAY — the signed projection must be the consumed projection.
//
// The package below is genuinely controller-signed and its quorum verifies:
// the signatures really do cover `golden_source_state`. What differs is the
// state the transaction actually consumes and lands. Nothing about the
// message bytes is wrong, so a message-inequality control cannot see this;
// only the transaction boundary can.
test migration_boundary_rejects_signed_state_mismatch() fail {
  let consumed = mig_source_at(23)
  let tx = spend_context(
    [mig_source_input(consumed)],
    [],
    [mig_successor_output(consumed)],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// INV-254-VALUE — migrate-out is inseparable from its successor.
//
// A controller-authorized exit that burns the source token and creates no
// successor destroys the identity. The burn is exactly the authorized one, so
// only successor composition can refuse this.
test migration_boundary_rejects_migrate_out_without_successor() fail {
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [],
    from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, -1),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// A redirected successor is the same class: the value leaves the family.
test migration_boundary_rejects_migrate_out_redirected_successor() fail {
  let elsewhere = Output {
    ..mig_successor_output(mig_source_datum()),
    address: from_verification_key(owner_vkh),
  }
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [elsewhere],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// The composed migrate-out is accepted, so the two controls above are not
// passing because migrate-out rejects everything.
test migration_boundary_accepts_composed_migrate_out() {
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

fn mig_refusal_tx(source_datum: Data, successor_datum: Data) -> Transaction {
  spend_context(
    [mig_source_input_of(source_datum)],
    [],
    [
      Output {
        ..mig_successor_output(mig_source_datum()),
        datum: InlineDatum(successor_datum),
      },
    ],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
}

/// The golden bytes are the datum the Haskell oracle signed over.
test migration_source_is_the_golden_projection() {
  let datum: Data = datum.write(mig_source_datum())
  let pending: Data = datum.write(mig_pending_datum())
  let version_1: Data = retired_layout(mig_version_1_datum())
  and {
    cbor.serialise(datum) == mig_vec.golden_source_datum,
    cbor.serialise(pending) == mig_vec.golden_pending_source_state,
    cbor.serialise(version_1) == mig_vec.golden_version_1_source_state,
  }
}

// The composed exit, with the source and successor datums alone replaced by
// the version 1 record of the same key state, under a package the controllers
// signed over that record.
test migration_boundary_refuses_a_version_1_source() fail {
  let version_1: Data = retired_layout(mig_version_1_datum())
  let state: Data = mig_vec.golden_version_1_source_state |> cbor_data
  run_migrate_out(
    MigrateOutProof {
      authorization: mig_authorization_by(
        state,
        [
          (0, mig_vec.fixture_version_1_sig_0),
          (1, mig_vec.fixture_version_1_sig_1),
        ],
      ),
    },
    mig_refusal_tx(version_1, version_1),
  )
}

// The same, for a pending termination of the same key state.
test migration_boundary_refuses_a_pending_source() fail {
  let pending: Data = datum.write(mig_pending_datum())
  let state: Data = mig_vec.golden_pending_source_state |> cbor_data
  run_migrate_out(
    MigrateOutProof {
      authorization: mig_authorization_by(
        state,
        [(0, mig_vec.fixture_pending_sig_0), (1, mig_vec.fixture_pending_sig_1)],
      ),
    },
    mig_refusal_tx(pending, pending),
  )
}

fn cbor_data(bytes: ByteArray) -> Data {
  expect Some(data) = cbor.deserialise(bytes)
  data
}

/// The exit as the register program itself sees it: the migration observer
/// is withdrawn with a claim naming the source, and the source datum is the one
/// given. The successor is not read by this arm.
fn migrate_out_arm(source_datum: Data) -> Bool {
  let tx = mig_refusal_tx(source_datum, datum.write(mig_source_datum()))
  let credential = Script(migration_hash)
  let envelope = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_migration,
      checkpoint_policy: mig_source_policy,
      own_ref: Some(mig_source_ref()),
    },
    payload: builtin.i_data(0),
  }
  let redeemer: Data = envelope
  removed_spend(
    removed_spend_redeemer(2, []),
    mig_source_ref(),
    Transaction {
      ..tx,
      withdrawals: [Pair(credential, 0)],
      redeemers: [Pair(Withdraw(credential), redeemer)],
    },
  )
}

test migrate_out_arm_accepts_a_live_source() {
  migrate_out_arm(datum.write(mig_source_datum()))
}

test migrate_out_arm_refuses_a_version_1_source() fail {
  migrate_out_arm(retired_layout(mig_version_1_datum()))
}

test migrate_out_arm_refuses_a_pending_source() fail {
  migrate_out_arm(datum.write(mig_pending_datum()))
}

// The accepted exit with a second checkpoint of the same policy and key state
// in the transaction: the program is run for that second input, while the
// observation and the controllers' package name the first. Only the comparison
// between the claim and the spent input can refuse it.
test migrate_out_refuses_an_observation_of_another_input() fail {
  let other_ref = OutputReference {
    transaction_id: mig_vec.fixture_source_txid,
    output_index: 5,
  }
  let other = input_at(
    other_ref,
    Output {
      address: from_script(mig_source_policy),
      value: from_lovelace(mig_protected)
        |> merge(
            from_asset(mig_source_policy, mig_vec.fixture_aid_asset_name, 1),
          ),
      datum: InlineDatum(datum.write(mig_source_datum())),
      reference_script: None,
    },
  )
  let base = spend_context(
    [mig_source_input(mig_source_datum()), other],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  let credential = Script(migration_hash)
  let envelope = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_migration,
      checkpoint_policy: mig_source_policy,
      own_ref: Some(mig_source_ref()),
    },
    payload: builtin.i_data(0),
  }
  let redeemer: Data = envelope
  let tx = Transaction {
    ..base,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
  removed_spend(removed_spend_redeemer(2, []), other_ref, tx) && run_migrate_out(
    MigrateOutProof { authorization: mig_authorization(mig_signed_state()) },
    tx,
  )
}

// Cut by epic ruling NOTE-006 (2026-08-12), sha256
// 1ef670c52897ebdda575805ac8a4fcf011bcc3749a3d5632c6d5c196a588c4d1:
//
//   migration_lifecycle_native_register_is_version_one_no_origin
//   migration_lifecycle_migrated_row_advances_retaining_origin
//   migration_lifecycle_advance_may_not_rewrite_origin
//
// These asserted that a datum-carried generation integer and a stored
// predecessor back-pointer survive ordinary lifecycle transitions. Both
// fields are CUT:
// the script hash already identifies the validator, and the migration
// transaction — spend the predecessor, burn its token, mint the successor,
// atomically — is a more durable lineage record than a datum field no M1
// consumer reads. Audit finding 3 was the sync-gap between that integer and
// the hash, so the cut dissolves the finding rather than repairing it.
//
// This is a ruling-driven feature cut, not a test evasion. The properties
// were genuinely RED against `0e6b445` and were not made to pass; the
// behaviour they demanded is no longer wanted. Their value/replay siblings
// above survive untouched, and those carry 2 of the 3 audit findings.

/// The Data of a spend redeemer constructor, handed to the validator as is:
/// the validator's own decoder is what accepts or refuses it.
fn removed_spend_redeemer(index: Int, fields: List<Data>) -> Data {
  builtin.constr_data(index, fields)
}

fn spend_data(redeemer: checkpoint_register.SpendRedeemer) -> Data {
  let data: Data = redeemer
  data
}

fn mint_data(redeemer: checkpoint_register.MintRedeemer) -> Data {
  let data: Data = redeemer
  data
}

fn removed_spend(
  redeemer: Data,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    2_000_000,
    None,
    redeemer,
    own_ref,
    tx,
  )
}

fn removed_mint(redeemer: Data, mint_policy: PolicyId, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.mint(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    2_000_000,
    redeemer,
    mint_policy,
    tx,
  )
}

/// A transaction that enters this generation from its predecessor: the source
/// is spent, one token is minted under the successor policy, and the migration
/// observer is withdrawn with a claim naming the successor and the source.
fn migrate_in_tx() -> Transaction {
  let tx = spend_context(
    [mig_source_input(mig_source_datum())],
    [],
    [mig_successor_output(mig_source_datum())],
    mig_replacement_mint(),
    [],
    interval.everything,
    0,
  )
  let credential = Script(migration_hash)
  let envelope = ObserverEnvelope {
    claim: ObserverClaim {
      action: observe_migration,
      checkpoint_policy: mig_target_policy,
      own_ref: Some(mig_source_ref()),
    },
    payload: builtin.i_data(0),
  }
  let redeemer: Data = envelope
  Transaction {
    ..tx,
    withdrawals: [Pair(credential, 0)],
    redeemers: [Pair(Withdraw(credential), redeemer)],
  }
}

fn removed_mint_redeemer(index: Int) -> Data {
  let source_ref: Data = mig_source_ref()
  builtin.constr_data(index, [source_ref])
}

test migrate_in_mint_is_refused() fail {
  removed_mint(removed_mint_redeemer(2), mig_target_policy, migrate_in_tx())
}

test legacy_migrate_in_mint_is_refused() fail {
  removed_mint(removed_mint_redeemer(3), mig_target_policy, migrate_in_tx())
}
