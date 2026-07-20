//// #114 S5 — the V1 checkpoint combined validator scaffold: the
//// `Register` mint branch (spec R1-R8) and fail-closed spend paths (R10).
////
//// The applied script's hash is BOTH the checkpoint token policy id and
//// the payment credential of the state output (#92: status is the
//// address). The mint branch COMPOSES, never re-derives: R3/R4/R6/R7/R8
//// delegate to the S3 `registration_predicate` over the reconstructed
//// message (nothing message-shaped is caller-supplied), R5 consumes the
//// S4 hash-proof token (no blake3 on this path), and only the
//// transaction-shape checks R1/R2/R5 live here.
////
//// Gate-room (A-001 QC): no check assumes a fixed input count or rejects
//// inputs beyond the one R5 names — the `Register` shape leaves room for
//// the #116 unicity-gate reference/consumed input. Duplicate-mint of the
//// same `(policy, aid_asset_name)` is the documented temporary
//// pre-deployment residual; the unicity/absence gate is #116 scope.
////
//// #115 S6 adds the `Advance` spend branch (V1-V7): KERI rotation
//// admission over the tip checkpoint UTxO, delegating V4-V7 to the S5
//// `advance_predicate`. #116 S4 opens ACTIVE Freeze and ordinary-Advance
//// thaw from FROZEN; `Convict`/`Close` remain explicit fail-closed
//// placeholders before the deployment freeze.

use aiken/collection/dict
use aiken/collection/list
use aiken/merkle_patricia_forestry.{Proof}
use cardano/address.{Script, from_script}
use cardano/assets.{PolicyId, lovelace_of, quantity_of, tokens}
use cardano/transaction.{
  InlineDatum, OutputReference, Spend, Transaction, find_input,
}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, V1}
use cardano_keri/checkpoint/enforcement.{
  EnforcementBindingValid, EnforcementEvidence, FreezeValid,
  bind_enforcement_evidence, freeze_predicate,
}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate,
}
use cardano_keri/checkpoint/role.{Active, Frozen, Registry}
use cardano_keri/checkpoint/unicity.{RegistryDatumV1}

/// The ledger min-ADA floor the R8 deposit arithmetic runs over (spec R8:
/// state-output lovelace `>= min_ada + d_reg`). A conservative fixed
/// constant — the same floor the repo's test harness
/// (`cage_context.min_ada`) and the S3 shared vectors'
/// `DeploymentContext` use; the true protocol `coinsPerUTxOByte` minimum
/// for this output is lower, so the check only ever over-collects.
pub const checkpoint_min_ada: Int = 2_000_000

/// The checkpoint mint redeemer. `Register` carries the S3
/// `RegistrationEvidence` (the full keripy `icp` serialization,
/// prover-supplied offsets, and the controller signatures over the
/// reconstructed `InceptionMessage` preimage).
pub type MintRedeemer {
  BootstrapRegistry
  Register {
    evidence: RegistrationEvidence,
    registry_ref: OutputReference,
    absence_proof: Proof,
  }
}

/// The checkpoint spend redeemer. `Advance` carries the S5 `AdvanceEvidence`
/// and runs V1-V7 (KERI rotation admission). `Freeze` carries the signed KERI
/// wire evidence that opens ACTIVE -> FROZEN; `Convict`/`Close` remain
/// fail-closed placeholders.
pub type SpendRedeemer {
  Advance { evidence: AdvanceEvidence }
  Freeze { evidence: EnforcementEvidence }
  Convict
  RecordRegistration
  Close
}

validator checkpoint(
  _version: Int,
  hash_proof_policy: PolicyId,
  network_id: Int,
  d_reg: Int,
  registry_seed: OutputReference,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      BootstrapRegistry -> validate_bootstrap(registry_seed, policy_id, tx)
      Register { evidence, registry_ref, absence_proof } ->
        validate_register(
          hash_proof_policy,
          network_id,
          d_reg,
          registry_seed,
          evidence,
          registry_ref,
          absence_proof,
          policy_id,
          tx,
        )
    }
  }

  spend(
    _datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect rdm: SpendRedeemer = redeemer
    when rdm is {
      Advance { evidence } ->
        validate_advance(network_id, d_reg, evidence, own_ref, tx)
      Freeze { evidence } -> validate_freeze(evidence, own_ref, tx)
      Convict -> fail
      RecordRegistration ->
        validate_record_registration(registry_seed, own_ref, tx)
      Close -> fail
    }
  }

  else(_) {
    fail
  }
}

/// The `Register` branch: R1/R2/R5 transaction shape here, R3/R4/R6/R7/R8
/// delegated to the S3 predicate.
fn validate_register(
  hash_proof_policy: PolicyId,
  network_id: Int,
  d_reg: Int,
  registry_seed: OutputReference,
  evidence: RegistrationEvidence,
  registry_ref: OutputReference,
  absence_proof: Proof,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, redeemers, .. } = tx
  // R2 — exactly one output at the ACTIVE address
  // `Address(Script(own_policy), None)` (the full address, so the
  // staking-credential axis stays free for the #116/#117 role encoding,
  // spec O4), holding the inline V1 datum. The one-element expect IS the
  // datum-confusion guard: a second output at that address rejects.
  let active = from_script(policy_id)
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == active },
  )
  expect InlineDatum(datum_data) = state_output.datum
  // Fails closed on any non-V1 datum constructor (#68 version sum).
  expect V1(d): CheckpointDatum = datum_data
  // R1 — single-Pair mint: exactly [Pair(deriveAidAssetName(D.cesr_aid), 1)]
  // under this policy (full-map inspection; the name is derived from the
  // datum's AID, never caller-copied).
  let aid_name = deriveAidAssetName(d.cesr_aid)
  expect [Pair(minted_name, minted_qty)] = dict.to_pairs(
    tokens(mint, policy_id),
  )
  expect minted_name == aid_name
  expect minted_qty == 1
  // R2 (cont.) — the state output carries the minted token.
  expect quantity_of(state_output.value, policy_id, aid_name) == 1
  // R5 — some input carries the proof token named over the PAIR
  // (event_bytes, aid) at quantity one (`list.any`: extra inputs are
  // never rejected — gate-room), and the transaction burns it (the
  // hash-proof policy's full mint map is exactly that burn).
  let proof_name = proof_token_name(evidence.event_bytes, d.cesr_aid)
  expect
    list.any(
      inputs,
      fn(input) {
        quantity_of(input.output.value, hash_proof_policy, proof_name) == 1
      },
    )
  expect [Pair(burned_name, burned_qty)] = dict.to_pairs(
    tokens(mint, hash_proof_policy),
  )
  expect burned_name == proof_name
  expect burned_qty == -1
  // U1/U2 — consume the named REGISTRY tip, preserve its complete value,
  // and advance its MPFS root by one absence-proven marker insertion.
  let thread_name = unicity.registry_thread_name(registry_seed)
  expect Some(registry_input) = find_input(inputs, registry_ref)
  expect registry_input.output.address == role.address(policy_id, Registry)
  expect quantity_of(registry_input.output.value, policy_id, thread_name) == 1
  expect InlineDatum(old_registry_data) = registry_input.output.datum
  expect old_registry: RegistryDatumV1 = old_registry_data
  expect [registry_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(policy_id, Registry) },
  )
  expect registry_output.value == registry_input.output.value
  expect quantity_of(registry_output.value, policy_id, thread_name) == 1
  expect InlineDatum(new_registry_data) = registry_output.datum
  expect new_registry: RegistryDatumV1 = new_registry_data
  expect
    unicity.insert_registered(old_registry.root, aid_name, absence_proof) == new_registry.root
  // U3 — the named registry input must execute RecordRegistration in the
  // same transaction. Exactly one redeemer for that spend purpose is admitted.
  expect [Pair(_, registry_redeemer_data)] = list.filter(
    redeemers,
    fn(pair) { pair.1st == Spend(registry_ref) },
  )
  expect registry_redeemer: SpendRedeemer = registry_redeemer_data
  expect registry_redeemer == RecordRegistration
  // R3/R4/R6/R7/R8 — the S3 predicate over the reconstructed message,
  // the datum, the state output's lovelace, and the redeemer evidence.
  let ctx = DeploymentContext {
    network_id,
    checkpoint_policy_id: policy_id,
    min_ada: checkpoint_min_ada,
    d_reg,
  }
  expect
    registration_predicate(ctx, d, lovelace_of(state_output.value), evidence) == RegistrationValid
  True
}

/// One-shot registry creation: exact seed consumption, one thread mint, and
/// one REGISTRY output rooted at the empty MPFS trie.
fn validate_bootstrap(
  registry_seed: OutputReference,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect [_] = list.filter(
    inputs,
    fn(input) { input.output_reference == registry_seed },
  )
  let thread_name = unicity.registry_thread_name(registry_seed)
  expect [Pair(minted_name, minted_qty)] = dict.to_pairs(
    tokens(mint, policy_id),
  )
  expect minted_name == thread_name
  expect minted_qty == 1
  expect [registry_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(policy_id, Registry) },
  )
  expect quantity_of(registry_output.value, policy_id, thread_name) == 1
  expect InlineDatum(registry_data) = registry_output.datum
  expect registry: RegistryDatumV1 = registry_data
  expect registry.root == unicity.empty_root()
  True
}

/// Registry spend coupling. The exact non-thread +1 under the own policy
/// necessarily invokes the paired Register mint handler in the ledger.
fn validate_record_registration(
  registry_seed: OutputReference,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Registry)
  expect InlineDatum(registry_data) = own_input.output.datum
  expect _: RegistryDatumV1 = registry_data
  let thread_name = unicity.registry_thread_name(registry_seed)
  expect quantity_of(own_input.output.value, own_hash, thread_name) == 1
  expect [registry_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Registry) },
  )
  expect registry_output.value == own_input.output.value
  expect InlineDatum(successor_data) = registry_output.datum
  expect _: RegistryDatumV1 = successor_data
  expect [Pair(minted_name, minted_qty)] = dict.to_pairs(tokens(mint, own_hash))
  expect minted_name != thread_name
  expect minted_qty == 1
  True
}

/// Permissionless ACTIVE -> FROZEN transition. The signed wire evidence is
/// EE0-EE9-bound before the pure freeze predicate runs; the state output then
/// preserves the input datum and complete value exactly at the FROZEN role.
fn validate_freeze(
  evidence: EnforcementEvidence,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(tip_data) = own_input.output.datum
  expect V1(tip): CheckpointDatum = tip_data
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect EnforcementBindingValid(decoded) = bind_enforcement_evidence(
    tip.cesr_aid,
    evidence,
  )
  expect freeze_predicate(tip, decoded) == FreezeValid
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Frozen) },
  )
  expect state_output.value == own_input.output.value
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect InlineDatum(successor_data) = state_output.datum
  expect successor_data == tip_data
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  True
}

/// The `Advance` branch: V1 own input / V2 successor output / V3 deposit
/// continuity live here; V4-V7 delegate to the S5 `advance_predicate` over
/// a `SpentCheckpoint` built EXCLUSIVELY from the deployment parameters,
/// the named spent outref, and OLD — nothing message-shaped beyond the
/// evidence's own delta lists is caller-supplied.
fn validate_advance(
  network_id: Int,
  d_reg: Int,
  evidence: AdvanceEvidence,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  // V1 — resolve the named own input at exactly ACTIVE or FROZEN, carrying
  // exactly one checkpoint token derived from its inline V1(OLD) datum.
  // TOMBSTONE, REGISTRY, unknown roles, and non-V1 datums fail before the
  // advance predicate.
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect
    own_input.output.address == role.address(own_hash, Active) || own_input.output.address == role.address(
      own_hash,
      Frozen,
    )
  expect InlineDatum(old_datum_data) = own_input.output.datum
  expect V1(old): CheckpointDatum = old_datum_data
  let aid_name = deriveAidAssetName(old.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  // V2 — exactly one ACTIVE successor output (the one-element filter is
  // the datum-confusion guard, as in R2), carrying the same token at
  // quantity one and inline V1(NEW); no mint/burn under own_hash — the
  // token moves, it never mints.
  let active = from_script(own_hash)
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == active },
  )
  expect InlineDatum(new_datum_data) = state_output.datum
  expect V1(new): CheckpointDatum = new_datum_data
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  // V3 — deposit continuity (mechanism as R8; economics stay O3/#117).
  expect lovelace_of(state_output.value) >= checkpoint_min_ada + d_reg
  // V4-V7 — the S5 predicate over the SpentCheckpoint built exclusively
  // from deployment parameters, the named spent outref, and OLD.
  let spent = SpentCheckpoint {
    network_id,
    policy_id: own_hash,
    aid_asset_name: aid_name,
    txid: own_ref.transaction_id,
    index: own_ref.output_index,
    cesr_aid: old.cesr_aid,
    witnesses: old.witnesses,
    next_keys: old.next_keys,
    next_threshold: old.next_threshold,
    seq: old.seq,
    native_sn: old.native_sn,
  }
  expect advance_predicate(spent, new, evidence) == AdvancePredicateValid
  True
}
