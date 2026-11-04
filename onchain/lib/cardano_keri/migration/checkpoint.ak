//// Checkpoint-family migration enforcement (#254, MOD-254-CHECKPOINT-FAMILY).
////
//// One entry, one authorization rule. `validate_checkpoint_migrate_out` is the
//// source generation's exit arm.
////
//// Authorization is **data, not caller identity**: the only thing that can
//// move a checkpoint is a quorum of its own current controller keys signing
//// `migration_message`. There is deliberately no governance key, no payment
//// credential, no `extra_signatories` fallback and no relayer allowlist, so a
//// valid package stays valid whoever submits it.
////
//// The Haskell mirror is `Cardano.KERI.AID.Migration.Checkpoint` and
//// `offchain/app/GenCheckpointMigrationVectors.hs` is the sole source of
//// `checkpoint_vectors.ak`'s byte fixtures.

use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{verify_ed25519_signature}
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, Value, from_asset, merge, quantity_of, tokens}
use cardano/transaction.{
  InlineDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV2, DatumValid, Live, datum_v2_well_formed,
}
use cardano_keri/checkpoint/message.{aid_digest, deriveAidAssetName}
use cardano_keri/checkpoint/role
use cardano_keri/checkpoint/threshold.{evaluate}
use cardano_keri/migration/types.{
  CheckpointActive, MigrationAuthorization, MigrationPredecessor, MigrationRole,
  MigrationTarget, migration_domain,
}

// ---------------------------------------------------------
// Message inputs
// ---------------------------------------------------------

/// Everything about the generation being left, as the *transaction* observes
/// it — never as the caller asserts it. `state` is the source's own projected
/// state carried verbatim, exactly as `MigrationAuthorization.source_state`
/// carries it.
pub type MigrationSource {
  network_id: Int,
  source_policy: PolicyId,
  source_ref: OutputReference,
  source_role: MigrationRole,
  source_state: Data,
}

/// The canonical, versioned, domain-separated migration preimage. Field order
/// is protocol surface: it changes only by a new applied program hash.
/// Every caller-controlled field that could redirect identity, value, or
/// successor selection appears here, which is what makes a signature over it
/// unreplayable onto a different move.
pub type MigrationMessage {
  domain: ByteArray,
  network_id: Int,
  source_policy: PolicyId,
  source_ref: OutputReference,
  source_role: MigrationRole,
  source_state: Data,
  target_policy: PolicyId,
  target_role: MigrationRole,
  target_address: Address,
  legacy_refund_address: Option<Address>,
}

/// A decoded lifecycle position with its checkpoint state.
pub type CheckpointRoleState {
  state_role: MigrationRole,
  checkpoint: CheckpointDatumV2,
}

/// The single admitted value difference across a migration: one named token
/// moves from the source policy to the target policy and nothing else changes.
pub type PolicyReplacement {
  source_policy: PolicyId,
  target_policy: PolicyId,
  asset_name: ByteArray,
  source_value: Value,
  successor_value: Value,
}

/// Why a migration was refused. Each class maps one-for-one onto a generated
/// Aiken vector and onto a Haskell `MigrationError` constructor, so a parity
/// disagreement is observable as a class change and not only as a byte change.
pub type MigrationError {
  /// the carried source projection is not a well-formed checkpoint datum
  MigrationDatumIllFormed
  /// the current controller threshold is not met by valid distinct indices
  MigrationQuorumUnsatisfied
  /// a KEL projection field changed across the move
  MigrationIdentityChanged
  /// the lifecycle position changed across the move
  MigrationRoleChanged
  /// value moved by more than the one admitted policy-token replacement
  MigrationValueChanged
}

/// `MigrationValid` ≙ `Right ()`, `MigrationInvalid(e)` ≙ `Left e`.
pub type MigrationVerdict {
  MigrationValid
  MigrationInvalid(MigrationError)
}

// ---------------------------------------------------------
// Behaviour (S254-1B RED: modelled surface, fail-closed bodies)
// ---------------------------------------------------------

/// Build the sole canonical signed migration preimage.
pub fn migration_message(
  source: MigrationSource,
  target: MigrationTarget,
) -> MigrationMessage {
  MigrationMessage {
    domain: migration_domain,
    network_id: source.network_id,
    source_policy: source.source_policy,
    source_ref: source.source_ref,
    source_role: source.source_role,
    source_state: source.source_state,
    target_policy: target.target_policy,
    target_role: target.target_role,
    target_address: target.target_address,
    legacy_refund_address: target.legacy_refund_address,
  }
}

/// Evaluate the source checkpoint's *own* current controller quorum over the
/// canonical message. Nothing else in the transaction can authorize a move.
///
/// Three properties, each with a named control: an index outside `[0, n)`
/// never counts, a repeated index never counts twice, and a signature that
/// does not verify never counts. `list.at` returning `None` establishes the
/// first, `list.unique` the second, and the Ed25519 check the third.
pub fn checkpoint_migration_authorized(
  source_state: CheckpointDatumV2,
  message: MigrationMessage,
  signatures: List<(Int, ByteArray)>,
) -> MigrationVerdict {
  when datum_v2_well_formed(source_state) is {
    DatumValid -> {
      expect Live { keys, .. } = source_state
      let preimage = cbor.serialise(message)
      let signed = verified_indices(keys.cur_keys, preimage, signatures)
      if evaluate(keys.cur_threshold, list.length(keys.cur_keys), signed) {
        MigrationValid
      } else {
        MigrationInvalid(MigrationQuorumUnsatisfied)
      }
    }
    _ -> MigrationInvalid(MigrationDatumIllFormed)
  }
}

/// The distinct current-key positions whose Ed25519 signature verified.
fn verified_indices(
  keys: List<ByteArray>,
  message: ByteArray,
  signatures: List<(Int, ByteArray)>,
) -> List<Int> {
  list.unique(
    list.filter_map(
      signatures,
      fn(pair) {
        let (index, signature) = pair
        when list.at(keys, index) is {
          Some(key) ->
            if verify_ed25519_signature(key, message, signature) {
              Some(index)
            } else {
              None
            }
          None -> None
        }
      },
    ),
  )
}

/// Check that identity, lifecycle position, role payload, and protected value
/// all survive the move, admitting only the one policy-token replacement.
///
/// The value rule is an equality against the source value with exactly one
/// token swapped, not a list of things that must not change: an equality
/// catches every redirection, including ones nobody enumerated.
pub fn checkpoint_transition_continuous(
  source: CheckpointRoleState,
  successor: CheckpointRoleState,
  value_change: PolicyReplacement,
) -> MigrationVerdict {
  if source.checkpoint != successor.checkpoint {
    MigrationInvalid(MigrationIdentityChanged)
  } else if source.state_role != successor.state_role {
    MigrationInvalid(MigrationRoleChanged)
  } else {
    let expected = value_change.source_value
      |> merge(
          from_asset(value_change.source_policy, value_change.asset_name, -1),
        )
      |> merge(
          from_asset(value_change.target_policy, value_change.asset_name, 1),
        )
    if value_change.successor_value != expected {
      MigrationInvalid(MigrationValueChanged)
    } else {
      MigrationValid
    }
  }
}

/// The source view an authorization proposes.
fn source_of(authorization: MigrationAuthorization) -> MigrationSource {
  let predecessor = authorization.source
  MigrationSource {
    network_id: authorization.network_id,
    source_policy: predecessor.predecessor_policy,
    source_ref: predecessor.predecessor_ref,
    source_role: authorization.source_role,
    source_state: authorization.source_state,
  }
}

/// The lifecycle position a source address occupies, as a migration role.
/// Tombstone is deliberately absent: a burnt row is an end state, not
/// something that can be migrated, so it fails closed here.
fn migration_role_of(policy: PolicyId, address: Address) -> MigrationRole {
  expect Some(role.Active) = role.classify(policy, address)
  CheckpointActive
}

/// The decoded state of a checkpoint output.
fn role_state_of(
  observed_role: MigrationRole,
  output: Output,
) -> CheckpointRoleState {
  expect InlineDatum(datum_data) = output.datum
  let state = datum.read(datum_data)
  expect Live { .. } = state
  CheckpointRoleState { state_role: observed_role, checkpoint: state }
}

/// The exact one-for-one token replacement both entry paths must enforce: the
/// source name burned once under the source policy, the same name minted once
/// under the target policy, and nothing else under either.
fn exact_token_replacement(
  source_policy: PolicyId,
  target_policy: PolicyId,
  asset_name: ByteArray,
  tx: Transaction,
) -> Bool {
  expect dict.to_pairs(tokens(tx.mint, source_policy)) == [Pair(asset_name, -1)]
  expect dict.to_pairs(tokens(tx.mint, target_policy)) == [Pair(asset_name, 1)]
  True
}

/// The single output holding the target token, or nothing when the successor
/// is absent or duplicated. Ambiguity and absence are both refusals; the arms
/// never pick "the first" candidate.
fn sole_successor(
  policy_id: PolicyId,
  asset_name: ByteArray,
  tx: Transaction,
) -> Option<Output> {
  when
    list.filter(
      tx.outputs,
      fn(output) { quantity_of(output.value, policy_id, asset_name) > 0 },
    )
  is {
    [output] -> Some(output)
    _ -> None
  }
}

/// The source generation's exit arm.
///
/// It proves the named source is genuinely consumed, that the source's own
/// controllers authorized this exact move, and that the transaction burns
/// exactly the source token. Where the successor lands is the entry arm's
/// business: that is the program which owns the target address.
pub fn validate_checkpoint_migrate_out(
  authorization: MigrationAuthorization,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let observed_role = migration_role_of(own_hash, own_input.output.address)
  let source_role_state = role_state_of(observed_role, own_input.output)
  let predecessor = authorization.source
  expect predecessor.predecessor_policy == own_hash
  expect predecessor.predecessor_ref == own_ref
  expect authorization.source_role == observed_role
  // The carried payload is the source's own projection, not a caller's
  // restatement of it: decode it through the frozen codec and require it to
  // equal what the consumed output actually holds.
  expect authorization.source_state == datum.write(source_role_state.checkpoint)
  let source = source_of(authorization)
  expect
    checkpoint_migration_authorized(
      source_role_state.checkpoint,
      migration_message(source, authorization.target),
      authorization.controller_signatures,
    ) == MigrationValid
  expect Live { aid, .. } = source_role_state.checkpoint
  expect Some(digest) = aid_digest(aid)
  let asset_name = deriveAidAssetName(digest)
  expect dict.to_pairs(tokens(tx.mint, own_hash)) == [Pair(asset_name, -1)]
  // The exit is inseparable from its successor. Burning the source token and
  // creating nothing is not a migration, it is destruction of the identity —
  // and it would be authorized by exactly the same package. So the same
  // signed target that the controllers approved must actually be composed
  // here: one confined successor, at the signed address and role, carrying
  // the one-for-one token replacement and all protected value.
  let target = authorization.target
  expect Some(successor_output) = sole_successor(
    target.target_policy,
    asset_name,
    tx,
  )
  expect successor_output.address == target.target_address
  let successor_role = migration_role_of(
    target.target_policy,
    successor_output.address,
  )
  expect successor_role == target.target_role
  let successor_role_state = role_state_of(successor_role, successor_output)
  expect exact_token_replacement(own_hash, target.target_policy, asset_name, tx)
  expect
    checkpoint_transition_continuous(
      source_role_state,
      successor_role_state,
      PolicyReplacement {
        source_policy: own_hash,
        target_policy: target.target_policy,
        asset_name,
        source_value: own_input.output.value,
        successor_value: successor_output.value,
      },
    ) == MigrationValid
  True
}

/// The migration proof a promoted observation carries: the source generation is
/// leaving under its own controller quorum.
///
/// The proof carries only prover-supplied evidence. The checkpoint policy and
/// the consumed output arrive from the observer claim, which the checkpoint
/// program independently requires to name its own policy and its own consumed
/// output, so no redeemer value can substitute either identity.
pub type MigrationProof {
  MigrateOutProof { authorization: MigrationAuthorization }
}

/// The promoted observer entry (A-001): run the heavy migration verdict.
///
/// Placement moved to an observer-sized component because the applied Register
/// program cannot carry these checks and remain deployable under the released
/// signed-reference transaction ceiling. Responsibility did not move: this is
/// still MOD-254-CHECKPOINT-FAMILY.
pub fn validate_migration_observation(
  source_ref: OutputReference,
  proof: MigrationProof,
  tx: Transaction,
) -> Bool {
  let MigrateOutProof { authorization } = proof
  validate_checkpoint_migrate_out(authorization, source_ref, tx)
}
