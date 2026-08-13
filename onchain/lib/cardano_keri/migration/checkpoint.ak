//// Checkpoint-family migration enforcement (#254, MOD-254-CHECKPOINT-FAMILY).
////
//// Three entries, one authorization rule. `validate_checkpoint_migrate_out`
//// is the source generation's exit arm, `validate_checkpoint_migrate_in` the
//// successor generation's entry arm pinned to its exact predecessor, and
//// `validate_legacy_checkpoint_migrate_in` the one-off bridge out of the
//// immutable deployed preprod v0 program, which has no migrate-out arm of its
//// own and must therefore be left through its existing `Close`/`CloseBurn`.
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
use cardano/address.{Address, Script, from_script}
use cardano/assets.{
  PolicyId, Value, from_asset, from_lovelace, lovelace_of, merge, quantity_of,
  tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/checkpoint/datum.{
  CheckpointDatum, CheckpointDatumV1, DatumValid, V1, datum_well_formed,
}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, armed_checkpoint, armed_deadline, armed_hunter,
}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/role
use cardano_keri/checkpoint/threshold.{evaluate}
use cardano_keri/migration/types.{
  CheckpointActive, CheckpointArmed, CheckpointFrozen, MigrationAuthorization,
  MigrationPredecessor, MigrationRole, MigrationTarget, migration_domain,
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

/// The applied predecessor a target program pins. Both fields are compiled
/// into the successor program as parameters, so no datum or redeemer value can
/// substitute either identity.
pub type Predecessor {
  predecessor_policy: PolicyId,
}

/// A decoded lifecycle position plus its complete role payload. ARMED carries
/// its hunter and deadline; ACTIVE and FROZEN carry neither.
pub type CheckpointRoleState {
  state_role: MigrationRole,
  checkpoint: CheckpointDatumV1,
  hunter_pkh: Option<ByteArray>,
  deadline: Option<Int>,
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

/// The immutable identity of the deployed preprod v0 checkpoint program. It is
/// data, pinned by the target program, never derived by recompiling current
/// source: recompilation would produce different bytes and prove nothing about
/// what is actually on preprod.
pub type LegacyCheckpointIdentity {
  legacy_network_name: ByteArray,
  legacy_network_magic: Int,
  legacy_network_id: Int,
  legacy_policy: PolicyId,
  legacy_source_commit: ByteArray,
}

/// The v0 exit this bridge requires the same transaction to have performed:
/// its controller-authorized `Close` refund plus the exact `CloseBurn`.
pub type LegacyCloseEvidence {
  legacy_refund_address: Address,
  legacy_refund_lovelace: Int,
  legacy_burned_asset_name: ByteArray,
}

// ---------------------------------------------------------
// Verdicts
// ---------------------------------------------------------

/// Why a migration was refused. Each class maps one-for-one onto a generated
/// Aiken vector and onto a Haskell `MigrationError` constructor, so a parity
/// disagreement is observable as a class change and not only as a byte change.
pub type MigrationError {
  /// the carried source projection is not a well-formed checkpoint datum
  MigrationDatumIllFormed
  /// the current controller threshold is not met by valid distinct indices
  MigrationQuorumUnsatisfied
  /// the consumed source is not the successor program's pinned predecessor
  MigrationForeignPredecessor
  /// a KEL projection field changed across the move
  MigrationIdentityChanged
  /// the lifecycle position or its role payload changed across the move
  MigrationRoleChanged
  /// value moved by more than the one admitted policy-token replacement
  MigrationValueChanged
  /// the named predecessor output is not consumed by this transaction
  MigrationSourceMissing
  /// the behaviour required here is not implemented
  MigrationNotImplemented
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
  source_state: CheckpointDatumV1,
  message: MigrationMessage,
  signatures: List<(Int, ByteArray)>,
) -> MigrationVerdict {
  when datum_well_formed(source_state) is {
    DatumValid -> {
      let preimage = cbor.serialise(message)
      let signed = verified_indices(source_state.cur_keys, preimage, signatures)
      if evaluate(
        source_state.cur_threshold,
        list.length(source_state.cur_keys),
        signed,
      ) {
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

/// The lineage edge, as the transaction itself.
///
/// Release identity is the applied successor hash, so there is no version to
/// compare and no stored back-pointer to trust. What must hold is that the
/// exact output the controllers signed over is genuinely spent here, holding
/// its own token, under the one predecessor policy this successor program was
/// applied with.
///
/// This is also what makes a split transaction unrepresentable: the mint
/// requires this spend, so the burn and the mint cannot be in different
/// transactions.
pub fn valid_predecessor_transition(
  source: MigrationSource,
  expected_predecessor: Predecessor,
  tx: Transaction,
) -> MigrationVerdict {
  if source.source_policy != expected_predecessor.predecessor_policy {
    MigrationInvalid(MigrationForeignPredecessor)
  } else {
    when find_input(tx.inputs, source.source_ref) is {
      None -> MigrationInvalid(MigrationSourceMissing)
      Some(input) -> {
        // The observed consumed output is the naming authority. Deriving the
        // asset name from the signed payload instead would let a package name
        // the token it wants to move rather than the one it is actually
        // spending.
        let observed_role = migration_role_of(
          source.source_policy,
          input.output.address,
        )
        let observed = role_state_of(observed_role, input.output)
        let asset_name = deriveAidAssetName(observed.checkpoint.cesr_aid)
        if quantity_of(input.output.value, source.source_policy, asset_name) != 1 {
          MigrationInvalid(MigrationForeignPredecessor)
        } else {
          // Separately, the projection the quorum signed must be the one this
          // transaction consumes: the signature decides what was approved,
          // while every continuity check reads the observation.
          expect signed: CheckpointDatum = source.source_state
          if signed != V1(observed.checkpoint) {
            MigrationInvalid(MigrationIdentityChanged)
          } else {
            MigrationValid
          }
        }
      }
    }
  }
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
  } else if source.state_role != successor.state_role || source.hunter_pkh != successor.hunter_pkh || source.deadline != successor.deadline {
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

/// Which migration entry a promoted observation is proving.
///
/// The proof carries only prover-supplied evidence. Neither the applied
/// generation nor the pinned predecessor appears here: both arrive as the
/// observer's own applied parameters, so no redeemer value can substitute
/// either identity — which is the whole point of pinning them.
pub type MigrationProof {
  /// the source generation is leaving under its own controller quorum
  MigrateOutProof { authorization: MigrationAuthorization }
  /// the successor generation is entering from its pinned predecessor
  MigrateInProof { authorization: MigrationAuthorization }
  /// the successor is entering from the immutable deployed preprod v0 program
  LegacyMigrateInProof {
    close: LegacyCloseEvidence,
    authorization: MigrationAuthorization,
  }
}

/// The promoted observer entry (A-001): run the heavy migration verdict.
///
/// Placement moved to an observer-sized component because the applied Register
/// program cannot carry these checks and remain deployable under the released
/// signed-reference transaction ceiling. Responsibility did not move: this is
/// still MOD-254-CHECKPOINT-FAMILY, and it is still the same three modelled
/// entries below that decide.
///
/// `checkpoint_policy` and `source_ref` come from the observer claim, which the
/// checkpoint program independently requires to name its own policy and its own
/// consumed output. Neither side trusts the other's reading of the transaction:
/// each derives what it needs from `tx`.
pub fn validate_migration_observation(
  predecessor_policy: PolicyId,
  checkpoint_policy: PolicyId,
  source_ref: OutputReference,
  proof: MigrationProof,
  tx: Transaction,
) -> Bool {
  when proof is {
    MigrateOutProof { authorization } ->
      validate_checkpoint_migrate_out(authorization, source_ref, tx)
    MigrateInProof { authorization } ->
      validate_checkpoint_migrate_in(
        Predecessor { predecessor_policy },
        source_ref,
        authorization,
        checkpoint_policy,
        tx,
      )
    LegacyMigrateInProof { close, authorization } ->
      validate_legacy_checkpoint_migrate_in(
        preprod_v0_identity(),
        source_ref,
        close,
        authorization,
        checkpoint_policy,
        tx,
      )
  }
}

/// The immutable deployed preprod v0 checkpoint identity (T254-004). Pinned as
/// data: recompiling current source would produce different bytes and prove
/// nothing about what is actually deployed on preprod.
pub fn preprod_v0_identity() -> LegacyCheckpointIdentity {
  LegacyCheckpointIdentity {
    legacy_network_name: "preprod",
    legacy_network_magic: 1,
    legacy_network_id: 0,
    legacy_policy: #"0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734",
    legacy_source_commit: "50a582064ddfde15ebfa3649c6b6fea8d39fc697",
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
  expect Some(classified) = role.classify(policy, address)
  when classified is {
    role.Active -> CheckpointActive
    role.Frozen -> CheckpointFrozen
    role.Armed -> CheckpointArmed
    _ -> fail
  }
}

/// The decoded role payload of a checkpoint output, with its versioned record.
fn role_state_of(
  observed_role: MigrationRole,
  output: Output,
) -> CheckpointRoleState {
  expect InlineDatum(datum_data) = output.datum
  when observed_role is {
    CheckpointArmed -> {
      expect armed: ArmedDatum = datum_data
      // Both ARMED versions are observed and preserved identically: the
      // migration observer reads through the shared accessors, so a lean
      // ArmedV2 state migrates exactly as an ArmedV1 one does.
      CheckpointRoleState {
        state_role: CheckpointArmed,
        checkpoint: armed_checkpoint(armed),
        hunter_pkh: Some(armed_hunter(armed)),
        deadline: Some(armed_deadline(armed)),
      }
    }
    _ -> {
      expect V1(state): CheckpointDatum = datum_data
      CheckpointRoleState {
        state_role: observed_role,
        checkpoint: state,
        hunter_pkh: None,
        deadline: None,
      }
    }
  }
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
  expect carried: CheckpointDatum = authorization.source_state
  expect carried == V1(source_role_state.checkpoint)
  let source = source_of(authorization)
  expect
    checkpoint_migration_authorized(
      source_role_state.checkpoint,
      migration_message(source, authorization.target),
      authorization.controller_signatures,
    ) == MigrationValid
  let asset_name = deriveAidAssetName(source_role_state.checkpoint.cesr_aid)
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

/// The successor generation's entry arm, pinned to its exact predecessor.
///
/// The pinned `Predecessor` arrives as a program parameter, never from a datum
/// or redeemer, which is what makes "unknown version", "skipped version" and
/// "foreign family" unrepresentable rather than merely rejected.
pub fn validate_checkpoint_migrate_in(
  predecessor: Predecessor,
  source_ref: OutputReference,
  authorization: MigrationAuthorization,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  expect Some(source_input) = find_input(tx.inputs, source_ref)
  expect Script(source_hash) = source_input.output.address.payment_credential
  let observed_role = migration_role_of(
    source_hash,
    source_input.output.address,
  )
  let source_role_state = role_state_of(observed_role, source_input.output)
  let predecessor_named = authorization.source
  expect predecessor_named.predecessor_ref == source_ref
  expect predecessor_named.predecessor_policy == source_hash
  expect authorization.source_role == observed_role
  // The quorum signs over `source_state`, so that field decides what the
  // controllers actually approved. If it is not the projection this
  // transaction consumes, a valid signature over one checkpoint would
  // authorize moving a different one — and every later continuity check
  // reads the observed projection, so nothing downstream would notice.
  expect carried: CheckpointDatum = authorization.source_state
  expect carried == V1(source_role_state.checkpoint)
  let source = source_of(authorization)
  let target = authorization.target
  expect target.target_policy == policy_id
  let asset_name = deriveAidAssetName(source_role_state.checkpoint.cesr_aid)
  expect Some(successor_output) = sole_successor(policy_id, asset_name, tx)
  expect successor_output.address == target.target_address
  let successor_role = migration_role_of(policy_id, successor_output.address)
  expect successor_role == target.target_role
  let successor_role_state = role_state_of(successor_role, successor_output)
  expect
    checkpoint_migration_authorized(
      source_role_state.checkpoint,
      migration_message(source, target),
      authorization.controller_signatures,
    ) == MigrationValid
  expect valid_predecessor_transition(source, predecessor, tx) == MigrationValid
  expect exact_token_replacement(source_hash, policy_id, asset_name, tx)
  expect
    checkpoint_transition_continuous(
      source_role_state,
      successor_role_state,
      PolicyReplacement {
        source_policy: source_hash,
        target_policy: policy_id,
        asset_name,
        source_value: source_input.output.value,
        successor_value: successor_output.value,
      },
    ) == MigrationValid
  True
}

/// The one-off bridge out of the immutable deployed preprod v0 program.
///
/// Two things make this different from an ordinary migrate-in, and both are
/// load-bearing. First, v0 has no migrate-out arm, so the transaction must
/// show that program's own authorized `Close` refund and exact `CloseBurn`
/// instead — and because `Close` is the only authorized v0 exit, ARMED and
/// FROZEN v0 rows have none and are refused here rather than rewritten.
/// Second, the refunded value leaves to the refund address, so the successor
/// is capitalized *independently* with equal protected lovelace. That is a
/// recapitalization, not a transfer of the refunded ada.
pub fn validate_legacy_checkpoint_migrate_in(
  preprod_v0: LegacyCheckpointIdentity,
  source_ref: OutputReference,
  close: LegacyCloseEvidence,
  authorization: MigrationAuthorization,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  expect Some(source_input) = find_input(tx.inputs, source_ref)
  let predecessor = authorization.source
  // The only admitted legacy source is the exact committed preprod v0 family.
  expect predecessor.predecessor_policy == preprod_v0.legacy_policy
  expect authorization.network_id == preprod_v0.legacy_network_id
  expect predecessor.predecessor_ref == source_ref
  // v0 ARMED and FROZEN have no authorized exit at all: they block the
  // cutover rather than being rewritten through this bridge.
  expect authorization.source_role == CheckpointActive
  expect source_input.output.address == from_script(preprod_v0.legacy_policy)
  expect InlineDatum(source_data) = source_input.output.datum
  expect V1(source_state): CheckpointDatum = source_data
  // Same binding as the permanent entry: the projection the quorum signed
  // must be the projection this transaction consumes.
  expect legacy_carried: CheckpointDatum = authorization.source_state
  expect legacy_carried == V1(source_state)
  let asset_name = deriveAidAssetName(source_state.cesr_aid)
  expect close.legacy_burned_asset_name == asset_name
  let source = source_of(authorization)
  let target = authorization.target
  expect target.target_policy == policy_id
  expect target.legacy_refund_address == Some(close.legacy_refund_address)
  expect
    checkpoint_migration_authorized(
      source_state,
      migration_message(source, target),
      authorization.controller_signatures,
    ) == MigrationValid
  // The v0 program's own Close paid the refund out; this arm only checks it
  // was exact, and never counts it as the successor's capital.
  expect [refund] = list.filter(
    tx.outputs,
    fn(output) { output.address == close.legacy_refund_address },
  )
  expect lovelace_of(refund.value) == close.legacy_refund_lovelace
  expect
    exact_token_replacement(preprod_v0.legacy_policy, policy_id, asset_name, tx)
  expect Some(successor_output) = sole_successor(policy_id, asset_name, tx)
  expect successor_output.address == target.target_address
  expect InlineDatum(successor_data) = successor_output.datum
  expect V1(successor_state): CheckpointDatum = successor_data
  // The exact ACTIVE KEL projection survives, and the successor is funded
  // independently to the same protected lovelace the source held.
  expect successor_state == source_state
  expect
    lovelace_of(successor_output.value) == lovelace_of(
      source_input.output.value,
    )
  True
}
