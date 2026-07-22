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
//// inputs beyond the one R5 names. Duplicate-mint of the same
//// `(policy, aid_asset_name)` is the documented controller self-harm
//// residual; registration has no shared coordinating state.
////
//// #115 S6 adds the `Advance` spend branch (V1-V7): KERI rotation
//// admission over the tip checkpoint UTxO, delegating V4-V7 to the S5
//// `advance_predicate`. #116 S4 opens ACTIVE Freeze and ordinary-Advance
//// thaw from FROZEN. #116 R3 opens ACTIVE|ARMED|FROZEN Convict, routes the
//// protected deposit and freeze bond by explicit output index, writes the
//// exact terminal tombstone, and pre-dispatches every named input by
//// role+datum; `Close` remains explicitly fail-closed before deployment.

use aiken/collection/dict
use aiken/collection/list
use aiken/interval
use aiken/primitive/bytearray
use cardano/address.{Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, Value, from_asset, from_lovelace, lovelace_of, merge, quantity_of,
  tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, find_input,
}
use cardano_keri/checkpoint/advance.{
  AdvanceEvidence, AdvancePredicateValid, advance_predicate,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{
  ConvictValid, EnforcementBindingValid, EnforcementEvidence, FreezeValid,
  TombstoneV1, bind_enforcement_evidence, convict_predicate, freeze_predicate,
}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumValid, ArmedV1, armed_datum_well_formed,
  freeze_bond_valid, freeze_window_valid,
}
use cardano_keri/checkpoint/message.{SpentCheckpoint, deriveAidAssetName}
use cardano_keri/checkpoint/registration.{
  DeploymentContext, RegistrationEvidence, RegistrationValid, proof_token_name,
  registration_predicate, valid_registration_deposit,
}
use cardano_keri/checkpoint/role.{Active, Armed, Frozen, Tombstone}

/// The ledger min-ADA floor the R8 deposit arithmetic runs over (spec R8:
/// state-output lovelace `>= min_ada + d_reg`). A conservative fixed
/// constant — the same floor the repo's test harness
/// (`cage_context.min_ada`) and the S3 shared vectors'
/// `DeploymentContext` use; the true protocol `coinsPerUTxOByte` minimum
/// for this output is lower, so the check only ever over-collects.
pub const checkpoint_min_ada: Int = 2_000_000

/// The checkpoint mint redeemer. `Register` carries the S3
/// `RegistrationEvidence` (the full keripy `icp` serialization,
/// prover-supplied offsets, controller signatures, and witness receipts
/// over the exact KERI event bytes).
pub type MintRedeemer {
  Register { evidence: RegistrationEvidence }
}

/// The checkpoint spend redeemer. `Advance` carries the S5 `AdvanceEvidence`
/// and runs V1-V7 (KERI rotation admission). `Freeze` carries the signed KERI
/// wire evidence that opens ACTIVE -> ARMED; `ClaimFreeze` opens ARMED ->
/// FROZEN; `Convict` carries the witnessed conflicting event, the convictor,
/// and explicit payout indices for ACTIVE|ARMED|FROZEN -> TOMBSTONE. `Close`
/// remains fail-closed.
pub type SpendRedeemer {
  Advance { evidence: AdvanceEvidence }
  Freeze { evidence: EnforcementEvidence, hunter_pkh: ByteArray }
  ClaimFreeze { hunter_output_index: Int }
  Convict {
    evidence: EnforcementEvidence,
    convictor_pkh: ByteArray,
    convictor_output_index: Int,
    hunter_output_index: Int,
  }
  Close
}

/// Exact named-input classification performed before any branch predicate.
/// A tombstone is classified so it can be rejected explicitly by the dispatch
/// matrix; unknown roles and every role/datum mismatch fail during dispatch.
type SpendInputRole {
  ActiveCheckpoint
  ArmedCheckpoint
  FrozenCheckpoint
  TerminalTombstone
}

validator checkpoint(
  _version: Int,
  hash_proof_policy: PolicyId,
  network_id: Int,
  d_reg: Int,
  freeze_bond: Int,
  freeze_window: Int,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, tx: Transaction) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect freeze_window_valid(freeze_window)
    let Register { evidence } = redeemer
    validate_register(
      hash_proof_policy,
      d_reg,
      freeze_bond,
      evidence,
      policy_id,
      tx,
    )
  }

  spend(
    _datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect freeze_window_valid(freeze_window)
    expect rdm: SpendRedeemer = redeemer
    expect Some(input_role) = classify_spend_input(
      d_reg,
      freeze_bond,
      own_ref,
      tx,
    )
    when rdm is {
      Freeze { evidence, hunter_pkh } ->
        when input_role is {
          ActiveCheckpoint ->
            validate_arm(freeze_window, evidence, hunter_pkh, own_ref, tx)
          _ -> fail
        }
      ClaimFreeze { hunter_output_index } ->
        when input_role is {
          ArmedCheckpoint ->
            validate_claim(freeze_bond, hunter_output_index, own_ref, tx)
          _ -> fail
        }
      Convict {
        evidence,
        convictor_pkh,
        convictor_output_index,
        hunter_output_index,
      } ->
        when input_role is {
          ActiveCheckpoint ->
            validate_convict_active(
              d_reg,
              freeze_bond,
              evidence,
              convictor_pkh,
              convictor_output_index,
              hunter_output_index,
              own_ref,
              tx,
            )
          ArmedCheckpoint ->
            validate_convict_armed(
              d_reg,
              freeze_bond,
              evidence,
              convictor_pkh,
              convictor_output_index,
              hunter_output_index,
              own_ref,
              tx,
            )
          FrozenCheckpoint ->
            validate_convict_frozen(
              d_reg,
              evidence,
              convictor_pkh,
              convictor_output_index,
              hunter_output_index,
              own_ref,
              tx,
            )
          TerminalTombstone -> fail
        }
      _ -> fail
    }
  }

  else(_) {
    fail
  }
}

/// Classify the named input by its whole role address and exact inline datum
/// family before dispatching a redeemer. In particular, TOMBSTONE is a known
/// terminal role with no admitted redeemer.
fn classify_spend_input(
  d_reg: Int,
  freeze_bond: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Option<SpendInputRole> {
  expect Some(own_input) = find_input(tx.inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect InlineDatum(datum_data) = own_input.output.datum
  if own_input.output.address == role.address(own_hash, Active) {
    expect V1(tip): CheckpointDatum = datum_data
    expect
      checkpoint_input_value_valid(
        own_hash,
        tip.cesr_aid,
        checkpoint_min_ada + d_reg + freeze_bond,
        own_input.output.value,
      )
    Some(ActiveCheckpoint)
  } else if own_input.output.address == role.address(own_hash, Armed) {
    expect armed: ArmedDatum = datum_data
    expect ArmedDatumValid = armed_datum_well_formed(armed)
    let ArmedV1 { checkpoint: armed_checkpoint, .. } = armed
    expect
      checkpoint_input_value_valid(
        own_hash,
        armed_checkpoint.cesr_aid,
        checkpoint_min_ada + d_reg + freeze_bond,
        own_input.output.value,
      )
    Some(ArmedCheckpoint)
  } else if own_input.output.address == role.address(own_hash, Frozen) {
    expect V1(tip): CheckpointDatum = datum_data
    expect
      checkpoint_input_value_valid(
        own_hash,
        tip.cesr_aid,
        checkpoint_min_ada + d_reg,
        own_input.output.value,
      )
    Some(FrozenCheckpoint)
  } else if own_input.output.address == role.address(own_hash, Tombstone) {
    expect _: TombstoneV1 = datum_data
    Some(TerminalTombstone)
  } else {
    None
  }
}

/// A live checkpoint input carries exactly the one AID token derived from its
/// inner datum and meets the protected lovelace reserve for its role.
fn checkpoint_input_value_valid(
  own_hash: PolicyId,
  cesr_aid: ByteArray,
  reserve: Int,
  value: Value,
) -> Bool {
  let aid_name = deriveAidAssetName(cesr_aid)
  dict.to_pairs(tokens(value, own_hash)) == [Pair(aid_name, 1)] && lovelace_of(
    value,
  ) >= reserve
}

/// The `Register` branch: R1/R2/R5 transaction shape here, R3/R4/R6/R7/R8
/// delegated to the S3 predicate.
fn validate_register(
  hash_proof_policy: PolicyId,
  d_reg: Int,
  freeze_bond: Int,
  evidence: RegistrationEvidence,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
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
  // R2 (cont.) — the state output's complete own-policy map is exactly the
  // derived AID token at quantity one. Assets under foreign policies remain
  // ordinary checkpoint-custodied surplus.
  expect
    dict.to_pairs(tokens(state_output.value, policy_id)) == [Pair(aid_name, 1)]
  // Register is independent of all existing checkpoint roles. Reference
  // inputs remain available as history, but no consumed input may be locked
  // by this checkpoint script, including malformed same-script state.
  expect
    list.all(
      inputs,
      fn(input) { input.output.address.payment_credential != Script(policy_id) },
    )
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
  // R3/R4/R6/R7/R8 — the S3 predicate over the exact inception-event
  // evidence, the datum, and the state output's lovelace.
  let ctx = DeploymentContext { min_ada: checkpoint_min_ada, d_reg }
  expect
    registration_predicate(ctx, d, lovelace_of(state_output.value), evidence) == RegistrationValid
  // Live bonded reserve weld: keep the shared predicate generic over d_reg,
  // while the applied checkpoint also protects the independent freeze bond.
  expect
    lovelace_of(state_output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  True
}

/// Permissionless ACTIVE -> ARMED transition. The signed wire evidence is
/// EE0-EE9-bound before the unchanged freeze predicate runs. The raw finite
/// validity upper endpoint anchors the stored deadline; inclusivity is never
/// normalized inward.
fn validate_arm(
  freeze_window: Int,
  evidence: EnforcementEvidence,
  hunter_pkh: ByteArray,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = tx
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
  expect !interval.is_empty(validity_range)
  expect interval.Finite(upper) = validity_range.upper_bound.bound_type
  let deadline = upper + freeze_window
  let armed = ArmedV1 { checkpoint: tip, hunter_pkh, deadline }
  expect ArmedDatumValid = armed_datum_well_formed(armed)
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Armed) },
  )
  expect state_output.value == own_input.output.value
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect InlineDatum(successor_data) = state_output.datum
  expect successor: ArmedDatum = successor_data
  expect successor == armed
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  True
}

/// Permissionless ARMED -> FROZEN claim at or after the stored hard deadline.
/// The named enterprise-key output receives exactly B and the continuing
/// checkpoint keeps the complete input Value minus precisely that lovelace.
fn validate_claim(
  freeze_bond: Int,
  hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, validity_range, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Armed)
  expect InlineDatum(armed_data) = own_input.output.datum
  expect armed: ArmedDatum = armed_data
  expect ArmedDatumValid = armed_datum_well_formed(armed)
  let ArmedV1 { checkpoint: tip, hunter_pkh, deadline } = armed
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect !interval.is_empty(validity_range)
  expect interval.Finite(lower) = validity_range.lower_bound.bound_type
  expect lower >= deadline
  expect Some(hunter_output) = list.at(outputs, hunter_output_index)
  expect hunter_output.address == from_verification_key(hunter_pkh)
  expect hunter_output.value == from_lovelace(freeze_bond)
  expect NoDatum = hunter_output.datum
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Frozen) },
  )
  let expected_value = own_input.output.value
    |> merge(from_lovelace(-freeze_bond))
  expect state_output.value == expected_value
  expect quantity_of(state_output.value, own_hash, aid_name) == 1
  expect InlineDatum(successor_data) = state_output.datum
  expect V1(successor): CheckpointDatum = successor_data
  expect successor == tip
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  True
}

/// ACTIVE conviction routes the protected deposit and bond together to the
/// named convictor before applying the shared terminal transition.
fn validate_convict_active(
  d_reg: Int,
  freeze_bond: Int,
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  _hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Active)
  expect InlineDatum(tip_data) = own_input.output.datum
  expect V1(tip): CheckpointDatum = tip_data
  expect bytearray.length(convictor_pkh) == 28
  expect
    expect_exact_payout(
      outputs,
      convictor_output_index,
      convictor_pkh,
      d_reg + freeze_bond,
    )
  validate_convict_terminal(tip, evidence, own_ref, tx)
}

/// ARMED conviction keeps the two protected payouts distinct: the deposit
/// goes to the convictor and the bond goes to the hunter stored in the datum.
fn validate_convict_armed(
  d_reg: Int,
  freeze_bond: Int,
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Armed)
  expect InlineDatum(armed_data) = own_input.output.datum
  expect armed: ArmedDatum = armed_data
  expect ArmedDatumValid = armed_datum_well_formed(armed)
  let ArmedV1 { checkpoint: tip, hunter_pkh, .. } = armed
  expect bytearray.length(convictor_pkh) == 28
  expect convictor_output_index != hunter_output_index
  expect
    expect_exact_payout(outputs, convictor_output_index, convictor_pkh, d_reg)
  expect
    expect_exact_payout(outputs, hunter_output_index, hunter_pkh, freeze_bond)
  validate_convict_terminal(tip, evidence, own_ref, tx)
}

/// FROZEN conviction routes only the protected registration deposit because
/// the freeze bond has already left checkpoint state.
fn validate_convict_frozen(
  d_reg: Int,
  evidence: EnforcementEvidence,
  convictor_pkh: ByteArray,
  convictor_output_index: Int,
  _hunter_output_index: Int,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  expect own_input.output.address == role.address(own_hash, Frozen)
  expect InlineDatum(tip_data) = own_input.output.datum
  expect V1(tip): CheckpointDatum = tip_data
  expect bytearray.length(convictor_pkh) == 28
  expect
    expect_exact_payout(outputs, convictor_output_index, convictor_pkh, d_reg)
  validate_convict_terminal(tip, evidence, own_ref, tx)
}

/// Shared conviction core: bind and validate the witnessed fork, then move
/// only min-ADA plus the quantity-one AID token into the exact tombstone.
/// Every unreserved input residual remains ordinary transaction change.
fn validate_convict_terminal(
  tip: CheckpointDatumV1,
  evidence: EnforcementEvidence,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect EnforcementBindingValid(decoded) = bind_enforcement_evidence(
    tip.cesr_aid,
    evidence,
  )
  expect convict_predicate(tip, decoded) == ConvictValid
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Tombstone) },
  )
  let terminal_value = from_lovelace(checkpoint_min_ada)
    |> merge(from_asset(own_hash, aid_name, 1))
  expect state_output.value == terminal_value
  expect InlineDatum(tombstone_data) = state_output.datum
  expect tombstone: TombstoneV1 = tombstone_data
  expect
    tombstone == TombstoneV1 {
      cesr_aid: tip.cesr_aid,
      convicted_at_native_sn: tip.native_sn,
      evidence_said: evidence.said,
    }
  expect dict.to_pairs(tokens(mint, own_hash)) == []
  True
}

/// Resolve one explicitly named payout. Equality against a lovelace-only
/// Value and `NoDatum` prevents hidden assets or datum-bearing substitutes.
fn expect_exact_payout(
  outputs: List<Output>,
  output_index: Int,
  recipient_pkh: ByteArray,
  lovelace: Int,
) -> Bool {
  expect Some(output) = list.at(outputs, output_index)
  expect output.address == from_verification_key(recipient_pkh)
  expect output.value == from_lovelace(lovelace)
  expect NoDatum = output.datum
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
  // TOMBSTONE, unknown roles, and non-V1 datums fail before the
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
