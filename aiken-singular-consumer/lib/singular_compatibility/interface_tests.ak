//// Compatibility of the reusable KERI Aiken libraries with the published
//// Singular registry package (`singular/registry`, public Singular commit
//// d69ab005c3b710aeebf033d3c5cd08c56feb5643, issues #742 and #743).
////
//// Each test imports the KERI checkpoint namespaces and the Singular
//// `singular_state` namespaces together and exercises the values Singular
//// publishes for a registration: the registration approval, the active token
//// and the holding guards of a fold. The KERI values are the generated
//// registration vectors, so the holding carries a real KERI checkpoint datum.
////
//// This is dependency evidence only. It shows that the interface accepts KERI
//// values and commits to every field the approval names. It does not show that
//// a KERI approval policy exists, nor that KERI registration corresponds to the
//// redesigned Singular registration; those belong to the application work.

use aiken/cbor
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use cardano/address.{Address, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{InlineDatum, NoDatum, Output, OutputReference}
use cardano_keri/checkpoint/datum.{CheckpointDatum, CheckpointDatumV1, V1}
use cardano_keri/checkpoint/registration.{
  RegistrationValid, registration_predicate,
}
use cardano_keri/checkpoint/registration_vectors as vec
use singular_state/fold.{
  Register, approval_for, change_approval, registration_deposit,
  registration_placement, registry_identity,
}
use singular_state/preimage.{
  RegistrationApproval, RegistryIdentity, active_token_name, approval_name,
  configuration_token_name, state_token_name, termination_preimage,
}

// ---------------------------------------------------------
// Fixed deployment values. Only their distinctness matters.
// ---------------------------------------------------------

const state_policy: PolicyId =
  #"5151515151515151515151515151515151515151515151515151515151"

const other_state_policy: PolicyId =
  #"5252525252525252525252525252525252525252525252525252525252"

const application_policy: PolicyId =
  #"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"

const checkpoint_script: ByteArray =
  #"c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"

const owner_stake_key: ByteArray =
  #"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e"

const other_stake_key: ByteArray =
  #"5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f"

const seed: OutputReference =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000001",
    output_index: 0,
  }

const request: OutputReference =
  OutputReference {
    transaction_id: #"0000000000000000000000000000000000000000000000000000000000000002",
    output_index: 0,
  }

fn registry() -> RegistryIdentity {
  registry_identity(state_policy, seed)
}

fn holding_address(stake_key: ByteArray) -> Address {
  Address {
    payment_credential: Script(checkpoint_script),
    stake_credential: Some(Inline(VerificationKey(stake_key))),
  }
}

/// A KERI checkpoint output: the checkpoint datum inline, at the checkpoint
/// script, holding `lovelace` and `active` tokens of the key's active asset.
fn keri_holding(
  datum: CheckpointDatumV1,
  address: Address,
  lovelace: Int,
  active: Int,
) -> Output {
  let checkpoint: CheckpointDatum = V1(datum)
  let checkpoint_data: Data = checkpoint
  Output {
    address,
    value: assets.from_lovelace(lovelace)
      |> assets.add(
          state_policy,
          active_token_name(registry(), datum.cesr_aid),
          active,
        ),
    datum: InlineDatum(checkpoint_data),
    reference_script: None,
  }
}

/// The registration change of `key`, whose holding is output `holding`.
fn register(key: ByteArray, holding: Int, deposit: Int) {
  Register { request, key, holding, deposit, proof: [] }
}

/// The registration approval name, derived from the published `Preimage`
/// constructor and the hashing rule of Singular #742 alone: the blake2b-256
/// hash of the Plutus Data serialisation of the preimage, whose initial datum
/// is the blake2b-256 hash of the serialised holding datum.
fn expected_approval(
  datum: CheckpointDatumV1,
  address: Address,
  deposit: Int,
) -> AssetName {
  let checkpoint: CheckpointDatum = V1(datum)
  blake2b_256(
    cbor.serialise(
      RegistrationApproval {
        registry: registry(),
        key: datum.cesr_aid,
        holding_address: address,
        initial_datum: blake2b_256(cbor.serialise(checkpoint)),
        deposit,
      },
    ),
  )
}

/// The approval Singular recomputes for registering `key` in `registry` into
/// a KERI holding that carries `datum` at `address`.
fn approval_of(
  registry: RegistryIdentity,
  key: ByteArray,
  datum: CheckpointDatumV1,
  address: Address,
  deposit: Int,
) -> Option<AssetName> {
  approval_for(
    registry,
    [keri_holding(datum, address, vec.pos_witnessed_lovelace, 1)],
    register(key, 0, deposit),
  )
}

/// The approval Singular recomputes for the witnessed KERI vector.
fn witnessed_approval() -> Option<AssetName> {
  approval_of(
    registry(),
    vec.pos_witnessed_datum.cesr_aid,
    vec.pos_witnessed_datum,
    holding_address(owner_stake_key),
    vec.d_reg_floor,
  )
}

fn request_carrying(approval: AssetName) -> Output {
  Output {
    address: Address {
      payment_credential: VerificationKey(owner_stake_key),
      stake_credential: None,
    },
    value: assets.from_lovelace(2000000)
      |> assets.add(application_policy, approval, 1),
    datum: NoDatum,
    reference_script: None,
  }
}

/// Whether a request carrying the witnessed approval is admitted for a change
/// whose recomputed approval is `recomputed`.
fn admits_witnessed_approval(recomputed: Option<AssetName>) -> Bool {
  expect Some(approved) = witnessed_approval()
  expect Some(name) = recomputed
  change_approval(application_policy, request_carrying(approved), name)
}

// ---------------------------------------------------------
// The registration approval commits to the KERI holding
// ---------------------------------------------------------

test keri_checkpoint_holding_yields_its_registration_approval() {
  witnessed_approval() == Some(
    expected_approval(
      vec.pos_witnessed_datum,
      holding_address(owner_stake_key),
      vec.d_reg_floor,
    ),
  )
}

test witnessed_approval_admits_its_own_change() {
  admits_witnessed_approval(witnessed_approval())
}

test registry_is_committed() {
  !admits_witnessed_approval(
    approval_of(
      registry_identity(other_state_policy, seed),
      vec.pos_witnessed_datum.cesr_aid,
      vec.pos_witnessed_datum,
      holding_address(owner_stake_key),
      vec.d_reg_floor,
    ),
  )
}

test key_is_committed() {
  !admits_witnessed_approval(
    approval_of(
      registry(),
      vec.pos_weighted_datum.cesr_aid,
      vec.pos_witnessed_datum,
      holding_address(owner_stake_key),
      vec.d_reg_floor,
    ),
  )
}

test holding_stake_part_is_committed() {
  !admits_witnessed_approval(
    approval_of(
      registry(),
      vec.pos_witnessed_datum.cesr_aid,
      vec.pos_witnessed_datum,
      holding_address(other_stake_key),
      vec.d_reg_floor,
    ),
  )
}

test holding_payment_part_is_committed() {
  let elsewhere = Address {
    payment_credential: Script(application_policy),
    stake_credential: Some(Inline(VerificationKey(owner_stake_key))),
  }
  !admits_witnessed_approval(
    approval_of(
      registry(),
      vec.pos_witnessed_datum.cesr_aid,
      vec.pos_witnessed_datum,
      elsewhere,
      vec.d_reg_floor,
    ),
  )
}

test initial_checkpoint_datum_is_committed() {
  let other: CheckpointDatumV1 = CheckpointDatumV1 {
    ..vec.pos_weighted_datum,
    cesr_aid: vec.pos_witnessed_datum.cesr_aid,
  }
  !admits_witnessed_approval(
    approval_of(
      registry(),
      vec.pos_witnessed_datum.cesr_aid,
      other,
      holding_address(owner_stake_key),
      vec.d_reg_floor,
    ),
  )
}

test deposit_is_committed() {
  !admits_witnessed_approval(
    approval_of(
      registry(),
      vec.pos_witnessed_datum.cesr_aid,
      vec.pos_witnessed_datum,
      holding_address(owner_stake_key),
      vec.d_reg_floor + 1,
    ),
  )
}

test legacy_registration_predicate_and_approval_share_one_datum() {
  let address = holding_address(owner_stake_key)
  and {
    registration_predicate(
      vec.pos_witnessed_ctx,
      vec.pos_witnessed_datum,
      vec.pos_witnessed_lovelace,
      vec.pos_witnessed_evidence,
    ) == RegistrationValid,
    approval_of(
      registry(),
      vec.pos_witnessed_datum.cesr_aid,
      vec.pos_witnessed_datum,
      address,
      vec.pos_witnessed_ctx.d_reg,
    ) == Some(
      expected_approval(
        vec.pos_witnessed_datum,
        address,
        vec.pos_witnessed_ctx.d_reg,
      ),
    ),
  }
}

// ---------------------------------------------------------
// Token names of one KERI key
// ---------------------------------------------------------

test active_token_is_named_per_registry_and_key() {
  let key = vec.pos_witnessed_datum.cesr_aid
  let other_registry = registry_identity(other_state_policy, seed)
  and {
    active_token_name(registry(), key) != active_token_name(other_registry, key),
    active_token_name(registry(), key) != active_token_name(
      registry(),
      vec.pos_weighted_datum.cesr_aid,
    ),
  }
}

test role_names_of_one_key_never_coincide() {
  let key = vec.pos_witnessed_datum.cesr_aid
  let names = [
    state_token_name(seed),
    active_token_name(registry(), key),
    configuration_token_name(registry()),
    approval_name(termination_preimage(key, registry())),
    expected_approval(
      vec.pos_witnessed_datum,
      holding_address(owner_stake_key),
      vec.d_reg_floor,
    ),
  ]
  list.length(list.unique(names)) == list.length(names)
}

test registry_identity_is_the_state_token_of_its_seed() {
  registry() == RegistryIdentity {
    policy: state_policy,
    name: state_token_name(seed),
  }
}

// ---------------------------------------------------------
// Holding guards over a KERI checkpoint output
// ---------------------------------------------------------

test registration_placement_accepts_the_keri_holding() {
  let datum = vec.pos_witnessed_datum
  let holding = keri_holding(
    datum,
    holding_address(owner_stake_key),
    vec.pos_witnessed_lovelace,
    1,
  )
  registration_placement(
    registry(),
    [holding],
    [register(datum.cesr_aid, 0, vec.d_reg_floor)],
    request,
    datum.cesr_aid,
    0,
  )
}

test registration_placement_refuses_a_second_active_token() {
  let datum = vec.pos_witnessed_datum
  let holding = keri_holding(
    datum,
    holding_address(owner_stake_key),
    vec.pos_witnessed_lovelace,
    1,
  )
  !registration_placement(
    registry(),
    [holding, holding],
    [register(datum.cesr_aid, 0, vec.d_reg_floor)],
    request,
    datum.cesr_aid,
    0,
  )
}

test registration_deposit_holds_the_keri_registration_floor() {
  let datum = vec.pos_witnessed_datum
  let address = holding_address(owner_stake_key)
  and {
    registration_deposit(
      vec.d_reg_floor,
      keri_holding(datum, address, vec.d_reg_floor, 1),
    ),
    !registration_deposit(
      vec.d_reg_floor,
      keri_holding(datum, address, vec.d_reg_below_floor, 1),
    ),
  }
}
