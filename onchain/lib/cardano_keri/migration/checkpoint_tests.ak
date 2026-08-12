//// Executable controls for checkpoint-family migration (#254 S254-1B).
////
//// Every value here is built from the `fixture_` inputs in
//// `checkpoint_vectors.ak`, which the Haskell oracle emitted alongside the
//// `golden_` encodings it computed from the same material. Comparing an
//// Aiken-built value against an Aiken-built expectation would assert Aiken
//// against itself; comparing it against a Haskell-computed golden is what
//// makes these parity controls.
////
//// Each control is deliberately two-sided: it asserts the *accepting* case
//// and the named mutant in the same test. A one-sided rejection control
//// passes just as happily against a rule that rejects everything, which is
//// exactly the failure mode a fail-closed body would hide.

use aiken/cbor
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{add, zero}
use cardano/transaction.{OutputReference}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/threshold.{Unweighted}
use cardano_keri/migration/checkpoint.{
  CheckpointRoleState, MigrationInvalid, MigrationSource, MigrationSuccessor,
  MigrationValid, PolicyReplacement, Predecessor,
  checkpoint_migration_authorized, checkpoint_transition_continuous,
  migration_message, valid_migration_edge,
}
use cardano_keri/migration/checkpoint_vectors as vec
use cardano_keri/migration/types.{
  CheckpointActive, CheckpointFrozen, MigrationOrigin, MigrationTarget,
  ValidatorVersion,
}

// ---------------------------------------------------------
// Fixture material, built from the generator's own inputs
// ---------------------------------------------------------

fn source_datum() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: vec.fixture_cesr_aid,
    cur_keys: [
      vec.fixture_ctrl_key_0,
      vec.fixture_ctrl_key_1,
      vec.fixture_ctrl_key_2,
    ],
    cur_threshold: Unweighted(2),
    next_keys: [vec.fixture_next_key_0, vec.fixture_next_key_1],
    next_threshold: Unweighted(1),
    witnesses: [vec.fixture_witness_key],
    toad: 1,
    seq: 7,
    native_sn: 4,
  }
}

fn source_ref() -> OutputReference {
  OutputReference { transaction_id: vec.fixture_source_txid, output_index: 1 }
}

fn mutant_ref() -> OutputReference {
  OutputReference { transaction_id: vec.fixture_mutant_txid, output_index: 1 }
}

fn source_origin() -> MigrationOrigin {
  MigrationOrigin {
    source_version: ValidatorVersion { value: 1 },
    source_policy: vec.fixture_source_policy,
    source_ref: source_ref(),
  }
}

/// The successor lands at a real role address of the target policy:
/// `role.address(policy, Active)` is `from_script(policy)`. A target address
/// that is not a role address of its own policy is unreachable at the
/// transaction boundary.
fn target_address() -> Address {
  Address {
    payment_credential: Script(vec.fixture_target_policy),
    stake_credential: None,
  }
}

fn refund_address() -> Address {
  Address {
    payment_credential: VerificationKey(vec.fixture_refund_vkey),
    stake_credential: None,
  }
}

fn migration_target() -> MigrationTarget {
  MigrationTarget {
    target_version: ValidatorVersion { value: 2 },
    target_policy: vec.fixture_target_policy,
    target_role: CheckpointActive,
    target_address: target_address(),
    legacy_refund_address: None,
  }
}

fn source() -> MigrationSource {
  MigrationSource {
    network_id: 1,
    source_version: ValidatorVersion { value: 1 },
    source_policy: vec.fixture_source_policy,
    source_ref: source_ref(),
    source_role: CheckpointActive,
    source_state: source_state(),
  }
}

/// The carried projection, exactly as the authorization carries it.
fn source_state() -> Data {
  cbor.deserialise(vec.golden_source_state)
    |> fn(decoded) {
        expect Some(state) = decoded
        state
      }
}

/// Canonical bytes of the message built from a source/target pair.
fn encoded(s: MigrationSource, t: MigrationTarget) -> ByteArray {
  cbor.serialise(migration_message(s, t))
}

/// The canonical bytes of the golden move.
fn golden() -> ByteArray {
  encoded(source(), migration_target())
}

fn sigs(pairs: List<(Int, ByteArray)>) -> List<(Int, ByteArray)> {
  pairs
}

/// Whether the source's own controller quorum authorizes a signature set over
/// the golden message.
fn authorized(signatures: List<(Int, ByteArray)>) -> Bool {
  checkpoint_migration_authorized(
    source_datum(),
    migration_message(source(), migration_target()),
    signatures,
  ) == MigrationValid
}

/// The satisfying quorum: two distinct controllers.
fn quorum() -> List<(Int, ByteArray)> {
  sigs([(0, vec.fixture_sig_0), (1, vec.fixture_sig_1)])
}

fn successor_of(
  version: Int,
  origin: Option<MigrationOrigin>,
) -> MigrationSuccessor {
  MigrationSuccessor {
    successor_version: ValidatorVersion { value: version },
    successor_policy: vec.fixture_target_policy,
    successor_origin: origin,
    successor_role: CheckpointActive,
  }
}

fn pinned() -> Predecessor {
  Predecessor {
    predecessor_version: ValidatorVersion { value: 1 },
    predecessor_policy: vec.fixture_source_policy,
  }
}

fn active_role(d: CheckpointDatumV1) -> CheckpointRoleState {
  CheckpointRoleState {
    state_role: CheckpointActive,
    checkpoint: d,
    hunter_pkh: None,
    deadline: None,
  }
}

/// The source value: protected lovelace plus exactly one source-policy token.
fn source_value() -> assets.Value {
  zero
    |> add("", "", 8_000_000)
    |> add(vec.fixture_source_policy, vec.fixture_aid_asset_name, 1)
}

/// The successor value: the same lovelace, the token under the target policy.
fn successor_value() -> assets.Value {
  zero
    |> add("", "", 8_000_000)
    |> add(vec.fixture_target_policy, vec.fixture_aid_asset_name, 1)
}

fn replacement(successor: assets.Value) -> PolicyReplacement {
  PolicyReplacement {
    source_policy: vec.fixture_source_policy,
    target_policy: vec.fixture_target_policy,
    asset_name: vec.fixture_aid_asset_name,
    source_value: source_value(),
    successor_value: successor,
  }
}

// ---------------------------------------------------------
// Canonical message and replay binding (INV-254-REPLAY)
// ---------------------------------------------------------

test checkpoint_migration_message_is_canonical() {
  // The Aiken encoder reproduces the Haskell oracle's bytes exactly, and the
  // frozen domain is the one the shared protocol landed.
  and {
    golden() == vec.golden_message,
    migration_message(source(), migration_target()).domain == vec.golden_migration_domain,
  }
}

test checkpoint_migration_message_binds_network() {
  and {
    golden() == vec.golden_message,
    encoded(MigrationSource { ..source(), network_id: 0 }, migration_target()) == vec.negative_message_network,
    encoded(MigrationSource { ..source(), network_id: 0 }, migration_target()) != golden(),
  }
}

test checkpoint_migration_message_binds_source_family() {
  // Both halves of the source family identity — which generation, and which
  // minting policy — are pinned by the signature.
  let other_version = MigrationSource {
    ..source(),
    source_version: ValidatorVersion { value: 2 },
  }
  let other_policy = MigrationSource {
    ..source(),
    source_policy: vec.fixture_target_policy,
  }
  and {
    encoded(other_version, migration_target()) == vec.negative_message_source_version,
    encoded(other_version, migration_target()) != golden(),
    encoded(other_policy, migration_target()) == vec.negative_message_source_policy,
    encoded(other_policy, migration_target()) != golden(),
  }
}

test checkpoint_migration_message_binds_source_outref() {
  let redirected = MigrationSource { ..source(), source_ref: mutant_ref() }
  and {
    encoded(redirected, migration_target()) == vec.negative_message_source_ref,
    encoded(redirected, migration_target()) != golden(),
  }
}

test checkpoint_migration_message_binds_source_role() {
  let redirected = MigrationSource { ..source(), source_role: CheckpointFrozen }
  and {
    encoded(redirected, migration_target()) == vec.negative_message_source_role,
    encoded(redirected, migration_target()) != golden(),
  }
}

test checkpoint_migration_message_binds_source_state() {
  expect Some(mutated) = cbor.deserialise(vec.golden_mutant_source_state)
  let redirected = MigrationSource { ..source(), source_state: mutated }
  and {
    encoded(redirected, migration_target()) == vec.negative_message_source_state,
    encoded(redirected, migration_target()) != golden(),
  }
}

test checkpoint_migration_message_binds_target_family() {
  // Which generation the move lands on, and under which minting policy, are
  // both signed — a package cannot be steered to another family.
  let other_version = MigrationTarget {
    ..migration_target(),
    target_version: ValidatorVersion { value: 3 },
  }
  let other_policy = MigrationTarget {
    ..migration_target(),
    target_policy: vec.fixture_source_policy,
  }
  and {
    encoded(source(), other_version) == vec.negative_message_target_version,
    encoded(source(), other_version) != golden(),
    encoded(source(), other_policy) == vec.negative_message_target_policy,
    encoded(source(), other_policy) != golden(),
  }
}

test checkpoint_migration_message_binds_target_role() {
  let redirected = MigrationTarget {
    ..migration_target(),
    target_role: CheckpointFrozen,
  }
  and {
    encoded(source(), redirected) == vec.negative_message_target_role,
    encoded(source(), redirected) != golden(),
  }
}

test checkpoint_migration_message_binds_target_address() {
  // Dropping only the delegation part still redirects where value lands.
  let redirected = MigrationTarget {
    ..migration_target(),
    target_address: Address {
      payment_credential: Script(vec.fixture_target_script),
      stake_credential: None,
    },
  }
  and {
    encoded(source(), redirected) == vec.negative_message_target_address,
    encoded(source(), redirected) != golden(),
  }
}

test checkpoint_migration_message_binds_legacy_refund() {
  let redirected = MigrationTarget {
    ..migration_target(),
    legacy_refund_address: Some(refund_address()),
  }
  and {
    encoded(source(), redirected) == vec.negative_message_refund,
    encoded(source(), redirected) != golden(),
  }
}

// ---------------------------------------------------------
// Controller authority (INV-254-AUTHORITY)
// ---------------------------------------------------------

test checkpoint_migration_quorum_shortfall_rejects() {
  // No signature set at all, and one valid controller signature, are both
  // genuinely short of the 2-of-3 rule the source datum carries.
  and {
    authorized(quorum()),
    !authorized(sigs([])),
    !authorized(sigs([(0, vec.fixture_sig_0)])),
  }
}

test checkpoint_migration_foreign_signer_rejects() {
  // A perfectly valid signature by a key outside the current set adds nothing.
  and {
    authorized(quorum()),
    !authorized(sigs([(0, vec.fixture_sig_0), (1, vec.fixture_foreign_sig)])),
  }
}

test checkpoint_migration_duplicate_index_never_counts() {
  // The same controller twice is one controller, not a quorum.
  and {
    authorized(quorum()),
    !authorized(sigs([(0, vec.fixture_sig_0), (0, vec.fixture_sig_0)])),
  }
}

test checkpoint_migration_out_of_range_index_never_counts() {
  // An index past the end of the key list cannot be made to count.
  and {
    authorized(quorum()),
    !authorized(sigs([(0, vec.fixture_sig_0), (9, vec.fixture_sig_2)])),
  }
}

test checkpoint_migration_replayed_signature_rejects() {
  // A real controller signature, but made over a redirected message: the
  // whole point of binding every field into the preimage.
  and {
    authorized(quorum()),
    !authorized(
      sigs([(0, vec.fixture_sig_0_over_mutant), (1, vec.fixture_sig_1)]),
    ),
  }
}

test checkpoint_migration_permissionless_relay() {
  // Authorization is data. The same package is valid regardless of who
  // submits it, so there is no submitter input to vary — the control is that
  // the accepting case depends only on the signature set and the source
  // state, and continues to hold when nothing else is supplied.
  and {
    authorized(quorum()),
    authorized(sigs([(1, vec.fixture_sig_1), (0, vec.fixture_sig_0)])),
  }
}

// ---------------------------------------------------------
// Permanent family edge (INV-254-LINKAGE)
// ---------------------------------------------------------

test checkpoint_migration_edge_accepts_exact_successor() {
  and {
    valid_migration_edge(
      source(),
      successor_of(2, Some(source_origin())),
      pinned(),
    ) == MigrationValid,
    // A skipped generation is not an edge.
    valid_migration_edge(
      source(),
      successor_of(3, Some(source_origin())),
      pinned(),
    ) != MigrationValid,
  }
}

test checkpoint_migration_foreign_predecessor_rejects() {
  let foreign = Predecessor {
    predecessor_version: ValidatorVersion { value: 1 },
    predecessor_policy: vec.fixture_legacy_policy,
  }
  and {
    valid_migration_edge(
      source(),
      successor_of(2, Some(source_origin())),
      pinned(),
    ) == MigrationValid,
    valid_migration_edge(
      source(),
      successor_of(2, Some(source_origin())),
      foreign,
    ) != MigrationValid,
  }
}

test checkpoint_migration_origin_must_be_actual_source() {
  // An origin naming a different spent output, and an absent origin, are both
  // refused: a migrated row must record where it actually came from.
  let wrong_ref = MigrationOrigin {
    ..source_origin(),
    source_ref: mutant_ref(),
  }
  and {
    valid_migration_edge(
      source(),
      successor_of(2, Some(source_origin())),
      pinned(),
    ) == MigrationValid,
    valid_migration_edge(source(), successor_of(2, Some(wrong_ref)), pinned()) != MigrationValid,
    valid_migration_edge(source(), successor_of(2, None), pinned()) != MigrationValid,
  }
}

// ---------------------------------------------------------
// Identity, role and value continuity (INV-254-IDENTITY, INV-254-VALUE)
// ---------------------------------------------------------

test checkpoint_migration_preserves_kel_projection() {
  let moved = CheckpointDatumV1 { ..source_datum(), seq: 8 }
  and {
    checkpoint_transition_continuous(
      active_role(source_datum()),
      active_role(source_datum()),
      replacement(successor_value()),
    ) == MigrationValid,
    // Migration performs no KERI advancement: a bumped counter is a changed
    // identity, not a successor.
    checkpoint_transition_continuous(
      active_role(source_datum()),
      active_role(moved),
      replacement(successor_value()),
    ) != MigrationValid,
  }
}

test checkpoint_migration_preserves_role_payload() {
  // ACTIVE must stay ACTIVE, and a successor that invents an ARMED payload is
  // not the role it claims to be.
  let invented = CheckpointRoleState {
    state_role: CheckpointActive,
    checkpoint: source_datum(),
    hunter_pkh: Some(vec.fixture_refund_vkey),
    deadline: Some(99),
  }
  and {
    checkpoint_transition_continuous(
      active_role(source_datum()),
      active_role(source_datum()),
      replacement(successor_value()),
    ) == MigrationValid,
    checkpoint_transition_continuous(
      active_role(source_datum()),
      invented,
      replacement(successor_value()),
    ) != MigrationValid,
  }
}

test checkpoint_migration_value_admits_only_policy_replacement() {
  // Protected lovelace may not be skimmed, and the source token may not
  // survive alongside the new one.
  let skimmed = zero
    |> add("", "", 7_000_000)
    |> add(vec.fixture_target_policy, vec.fixture_aid_asset_name, 1)
  let retained = successor_value()
    |> add(vec.fixture_source_policy, vec.fixture_aid_asset_name, 1)
  and {
    checkpoint_transition_continuous(
      active_role(source_datum()),
      active_role(source_datum()),
      replacement(successor_value()),
    ) == MigrationValid,
    checkpoint_transition_continuous(
      active_role(source_datum()),
      active_role(source_datum()),
      replacement(skimmed),
    ) != MigrationValid,
    checkpoint_transition_continuous(
      active_role(source_datum()),
      active_role(source_datum()),
      replacement(retained),
    ) != MigrationValid,
  }
}
