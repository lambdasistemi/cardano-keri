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
use cardano/address.{Credential, Script, from_script, from_verification_key}
use cardano/assets.{
  PolicyId, Value, from_asset, from_lovelace, lovelace_of, merge, quantity_of,
  tokens,
}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction, Withdraw,
  find_input,
}
use cardano_keri/checkpoint/datum.{CheckpointDatum, CheckpointDatumV1, V1}
use cardano_keri/checkpoint/enforcement.{TombstoneV1}
use cardano_keri/checkpoint/freeze_bond.{
  ArmedDatum, ArmedDatumValid, ArmedV1, armed_datum_well_formed,
  freeze_bond_valid, freeze_window_valid,
}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_advance, observe_convict,
  observe_freeze, observe_register,
}
use cardano_keri/checkpoint/registration.{valid_registration_deposit}
use cardano_keri/checkpoint/role.{Active, Armed, Frozen, Tombstone}

/// The ledger min-ADA floor the R8 deposit arithmetic runs over (spec R8:
/// state-output lovelace `>= min_ada + d_reg`). A conservative fixed
/// constant — the same floor the repo's test harness
/// (`cage_context.min_ada`) and the S3 shared vectors'
/// `DeploymentContext` use; the true protocol `coinsPerUTxOByte` minimum
/// for this output is lower, so the check only ever over-collects.
pub const checkpoint_min_ada: Int = 2_000_000

/// The checkpoint mint redeemer. R1 slims `Register` to a bare state-machine
/// command: it carries NO evidence. The RegistrationEvidence moved to the
/// zero-lovelace withdrawal observer, which runs the unchanged registration
/// predicate; the checkpoint validates only the exact observer claim.
pub type MintRedeemer {
  Register
}

/// The checkpoint spend redeemer. R1 slims every evidence-bearing branch:
/// `Advance` is bare and remains rejected in R1; `Freeze` retains only the
/// hunter pkh; `ClaimFreeze` is unchanged and needs no observer; `Convict`
/// retains only the convictor pkh and the two payout indices; `Close` remains
/// fail-closed. The EnforcementEvidence moved to the observer.
pub type SpendRedeemer {
  Advance
  Freeze { hunter_pkh: ByteArray }
  ClaimFreeze { hunter_output_index: Int }
  Convict {
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
  lifecycle_hash: PolicyId,
  advance_hash: PolicyId,
  enforcement_hash: PolicyId,
  d_reg: Int,
  freeze_bond: Int,
  freeze_window: Int,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, tx: Transaction) {
    expect valid_registration_deposit(d_reg)
    expect freeze_bond_valid(freeze_bond)
    expect freeze_window_valid(freeze_window)
    let Register = redeemer
    // Register → lifecycle observer at zero; no extra family observers.
    expect
      ran_check(
        lifecycle_hash,
        lifecycle_hash,
        advance_hash,
        enforcement_hash,
        policy_id,
        observe_register,
        None,
        tx,
      )
    validate_register(d_reg, freeze_bond, policy_id, tx)
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
    expect Some(own_input) = find_input(tx.inputs, own_ref)
    expect Script(own_hash) = own_input.output.address.payment_credential
    when rdm is {
      Advance -> {
        // Advance → advance observer; state-machine body fail-closed until R4.
        expect
          ran_check(
            advance_hash,
            lifecycle_hash,
            advance_hash,
            enforcement_hash,
            own_hash,
            observe_advance,
            Some(own_ref),
            tx,
          )
        fail
      }
      Freeze { hunter_pkh } ->
        when input_role is {
          ActiveCheckpoint -> {
            expect
              ran_check(
                enforcement_hash,
                lifecycle_hash,
                advance_hash,
                enforcement_hash,
                own_hash,
                observe_freeze,
                Some(own_ref),
                tx,
              )
            validate_arm(freeze_window, hunter_pkh, own_ref, tx)
          }
          _ -> fail
        }
      ClaimFreeze { hunter_output_index } ->
        when input_role is {
          ArmedCheckpoint -> {
            // ClaimFreeze needs no observer: reject any family withdrawal.
            expect
              no_family_observer_withdrawal(
                lifecycle_hash,
                advance_hash,
                enforcement_hash,
                tx,
              )
            validate_claim(freeze_bond, hunter_output_index, own_ref, tx)
          }
          _ -> fail
        }
      Convict { convictor_pkh, convictor_output_index, hunter_output_index } -> {
        expect
          ran_check(
            enforcement_hash,
            lifecycle_hash,
            advance_hash,
            enforcement_hash,
            own_hash,
            observe_convict,
            Some(own_ref),
            tx,
          )
        when input_role is {
          ActiveCheckpoint ->
            validate_convict_active(
              d_reg,
              freeze_bond,
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
              convictor_pkh,
              convictor_output_index,
              hunter_output_index,
              own_ref,
              tx,
            )
          FrozenCheckpoint ->
            validate_convict_frozen(
              d_reg,
              convictor_pkh,
              convictor_output_index,
              hunter_output_index,
              own_ref,
              tx,
            )
          TerminalTombstone -> fail
        }
      }
      _ -> fail
    }
  }

  else(_) {
    fail
  }
}

/// Exact family selection ran-check (R3 four-program). The transaction must
/// contain `Pair(Script(selected_hash), 0)` and a matching Withdraw redeemer
/// whose claim has the expected action, checkpoint h, and own_ref. No other
/// of the three family observer credentials may appear in withdrawals (extra
/// / cross-family reject). Unrelated non-family withdrawals are not rejected.
/// The checkpoint reads only the claim; the payload stays opaque.
fn ran_check(
  selected_hash: PolicyId,
  lifecycle_hash: PolicyId,
  advance_hash: PolicyId,
  enforcement_hash: PolicyId,
  checkpoint_policy: PolicyId,
  expected_action: Int,
  expected_own_ref: Option<OutputReference>,
  tx: Transaction,
) -> Bool {
  let credential: Credential = Script(selected_hash)
  // Selected family credential withdrawn at exactly zero lovelace.
  expect
    list.any(
      tx.withdrawals,
      fn(Pair(w_cred, w_lovelace)) { w_cred == credential && w_lovelace == 0 },
    )
  // No extra / cross-family observer credential withdrawals.
  expect
    list.all(
      tx.withdrawals,
      fn(Pair(w_cred, _w_lovelace)) {
        when w_cred is {
          Script(h) ->
            if h == lifecycle_hash || h == advance_hash || h == enforcement_hash {
              h == selected_hash
            } else {
              True
            }
          _ -> True
        }
      },
    )
  // Matching Withdraw redeemer with the expected claim.
  expect
    list.any(
      tx.redeemers,
      fn(Pair(purpose, rdm)) {
        when purpose is {
          Withdraw(r_cred) ->
            if r_cred == credential {
              expect envelope: ObserverEnvelope = rdm
              let ObserverClaim { action, checkpoint_policy: claim_h, own_ref }
                = envelope.claim
              action == expected_action && claim_h == checkpoint_policy && own_ref == expected_own_ref
            } else {
              False
            }
          _ -> False
        }
      },
    )
  True
}

/// ClaimFreeze needs no observer: reject any of the three family credentials
/// in withdrawals.
fn no_family_observer_withdrawal(
  lifecycle_hash: PolicyId,
  advance_hash: PolicyId,
  enforcement_hash: PolicyId,
  tx: Transaction,
) -> Bool {
  list.all(
    tx.withdrawals,
    fn(Pair(w_cred, _w_lovelace)) {
      when w_cred is {
        Script(h) ->
          h != lifecycle_hash && h != advance_hash && h != enforcement_hash
        _ -> True
      }
    },
  )
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

/// The `Register` branch: R1/R2/R5 transaction shape here. The R3/R4/R6/R7/R8
/// evidence verification (registration predicate) and the distinct hash-proof
/// event-derived proof input/burn moved to the observer; the checkpoint keeps
/// only the state-machine, own-policy token, and reserve mechanics and never
/// decodes the evidence payload.
fn validate_register(
  d_reg: Int,
  freeze_bond: Int,
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
  // Live bonded reserve weld: the state output protects the independent
  // registration deposit and freeze bond. The registration predicate's own
  // reserve check now runs in the observer over the same lovelace quantity.
  expect
    lovelace_of(state_output.value) >= checkpoint_min_ada + d_reg + freeze_bond
  True
}

/// Permissionless ACTIVE -> ARMED transition. The signed wire evidence is
/// EE0-EE9-bound and the freeze predicate runs in the observer; the
/// checkpoint keeps the deadline anchor, the ArmedV1 successor construction,
/// and the complete-Value preservation. The raw finite validity upper
/// endpoint anchors the stored deadline; inclusivity is never normalized
/// inward.
fn validate_arm(
  freeze_window: Int,
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
/// named convictor before applying the shared terminal transition. The
/// witnessed-fork evidence is bound and validated in the observer.
fn validate_convict_active(
  d_reg: Int,
  freeze_bond: Int,
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
  validate_convict_terminal(tip, own_ref, tx)
}

/// ARMED conviction keeps the two protected payouts distinct: the deposit
/// goes to the convictor and the bond goes to the hunter stored in the datum.
fn validate_convict_armed(
  d_reg: Int,
  freeze_bond: Int,
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
  validate_convict_terminal(tip, own_ref, tx)
}

/// FROZEN conviction routes only the protected registration deposit because
/// the freeze bond has already left checkpoint state.
fn validate_convict_frozen(
  d_reg: Int,
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
  validate_convict_terminal(tip, own_ref, tx)
}

/// Shared conviction core: the witnessed fork is bound and validated in the
/// observer, which also pins the tombstone's `evidence_said` to the decoded
/// evidence SAID (A-003 Option C). The checkpoint moves only min-ADA plus the
/// quantity-one AID token into the exact tombstone and pins the tombstone
/// fields it can derive from the spent datum (cesr_aid, convicted_at_native_sn);
/// it never sees the evidence SAID. Every unreserved input residual remains
/// ordinary transaction change.
fn validate_convict_terminal(
  tip: CheckpointDatumV1,
  own_ref: OutputReference,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, outputs, mint, .. } = tx
  expect Some(own_input) = find_input(inputs, own_ref)
  expect Script(own_hash) = own_input.output.address.payment_credential
  let aid_name = deriveAidAssetName(tip.cesr_aid)
  expect quantity_of(own_input.output.value, own_hash, aid_name) == 1
  expect [state_output] = list.filter(
    outputs,
    fn(output) { output.address == role.address(own_hash, Tombstone) },
  )
  let terminal_value = from_lovelace(checkpoint_min_ada)
    |> merge(from_asset(own_hash, aid_name, 1))
  expect state_output.value == terminal_value
  expect InlineDatum(tombstone_data) = state_output.datum
  expect tombstone: TombstoneV1 = tombstone_data
  expect tombstone.cesr_aid == tip.cesr_aid
  expect tombstone.convicted_at_native_sn == tip.native_sn
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
