//// #495 — the registry checkpoint has no owner exit.
////
//// A live checkpoint is alive until it is convicted. The former owner-close
//// spend and its burn are written here as raw redeemer data, exactly as they
//// were encoded when the exit existed, together with the controller-signed
//// evidence that made the exit valid. Each test hands that data to the real
//// validator through its redeemer decoder; none of it may be accepted.
////
//// The signed evidence is a frozen wire fixture. It binds the policy
//// `policy`, network 1, the spent output below and the refund address, so on
//// the code that still had the exit it is accepted — which is what makes the
//// refusals below able to fail.

use aiken/interval
use cage_context.{input_at, min_ada, spend_context}
use cardano/address.{Address, Inline, Script, VerificationKey, from_script}
use cardano/assets.{PolicyId, from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, NoDatum, Output, OutputReference, Transaction,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1, V1}
use cardano_keri/checkpoint/message.{deriveAidAssetName}
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint_register.{MintRedeemer, SpendRedeemer}

const policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

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

const freeze_window: Int = 10_000

/// The wire shape of the former owner-close evidence.
type FormerCloseEvidence {
  refund_address: Address,
  ctrl_sigs: List<(Int, ByteArray)>,
}

/// The former spend redeemer, constructor 0.
type FormerSpend {
  FormerClose { evidence: FormerCloseEvidence }
}

/// The former mint redeemer, constructor 1.
type FormerMint {
  FormerRegister
  FormerCloseBurn { checkpoint_ref: OutputReference }
}

fn spent_ref() -> OutputReference {
  OutputReference {
    transaction_id: #"d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1",
    output_index: 3,
  }
}

fn tip() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    cur_keys: [
      #"8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
      #"8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
    ],
    cur_threshold: Unweighted(2),
    next_keys: [
      #"7777777777777777777777777777777777777777777777777777777777777777",
    ],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 5,
    native_sn: 9,
  }
}

/// Both controller keys signed the former close message for this checkpoint,
/// network and refund address.
fn former_evidence() -> FormerCloseEvidence {
  FormerCloseEvidence {
    refund_address: Address {
      payment_credential: VerificationKey(
        #"44444444444444444444444444444444444444444444444444444444",
      ),
      stake_credential: Some(
        Inline(
          Script(#"55555555555555555555555555555555555555555555555555555555"),
        ),
      ),
    },
    ctrl_sigs: [
      (
        0,
        #"b6ce7b30bf194d87c211d172fa7329867dc859f653b35981429537b2c906cbfad085e910e8deeda8ccd57e066efb164edadd170eff5b717efe2d141e25c1b806",
      ),
      (
        1,
        #"f1f24c065632359a9bd08b968377847500904c3d313105ab1ef8bfd8d862dd75c69cb59999e8eeefd9903c7ee8bf81b8f5008196ec3007e5d73538a2a571f103",
      ),
    ],
  }
}

/// The owner-exit transaction: the live checkpoint is spent, its token is
/// burned, and its whole value goes to the signed refund address.
fn exit_tx() -> Transaction {
  let aid_name = deriveAidAssetName(tip().cesr_aid)
  let bonded = min_ada + d_reg + freeze_bond
  let own_input = input_at(
    spent_ref(),
    Output {
      address: from_script(policy),
      value: from_lovelace(bonded) |> merge(from_asset(policy, aid_name, 1)),
      datum: InlineDatum(V1(tip())),
      reference_script: None,
    },
  )
  let refund = Output {
    address: former_evidence().refund_address,
    value: from_lovelace(bonded),
    datum: NoDatum,
    reference_script: None,
  }
  spend_context(
    [own_input],
    [],
    [refund],
    from_asset(policy, aid_name, -1),
    [],
    interval.everything,
    0,
  )
}

fn run_spend(redeemer: SpendRedeemer, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.spend(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    None,
    redeemer,
    spent_ref(),
    tx,
  )
}

fn run_mint(redeemer: MintRedeemer, tx: Transaction) -> Bool {
  checkpoint_register.checkpoint_register.mint(
    migration_hash,
    lifecycle_hash,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    1,
    d_reg,
    freeze_bond,
    freeze_window,
    redeemer,
    policy,
    tx,
  )
}

/// S1. The controllers' signed close of a live checkpoint is not an action.
test owner_close_spend_is_refused() fail {
  let wire: Data = FormerClose { evidence: former_evidence() }
  expect redeemer: SpendRedeemer = wire
  run_spend(redeemer, exit_tx())
}

/// S1 and S2 together: the whole owner-exit transaction (the former close
/// spend and the former close burn of the same checkpoint) cannot be
/// satisfied.
test owner_exit_transaction_is_refused() fail {
  let spend_wire: Data = FormerClose { evidence: former_evidence() }
  let mint_wire: Data = FormerCloseBurn { checkpoint_ref: spent_ref() }
  expect spend_redeemer: SpendRedeemer = spend_wire
  expect mint_redeemer: MintRedeemer = mint_wire
  let tx = exit_tx()
  run_mint(mint_redeemer, tx) && run_spend(spend_redeemer, tx)
}
