//// The booking, fold, return and termination transactions the application
//// tests run over.
////
//// Every transaction is built from the generated vectors; every name derived
//// from a fact (an approval, an active token, a configuration token) is
//// computed with the public Singular functions, never with the code under
//// test, so changing a fact changes everything derived from it. `accepts`
//// runs the handlers the ledger would run: the mint handler when the
//// application policy is minted or burned, the spend handler of every input
//// at the application address, each with the redeemer the transaction
//// carries for it.

use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{Address, Credential, Script, from_script}
use cardano/assets.{
  AssetName, PolicyId, Value, add, from_lovelace, tokens, zero,
}
use cardano/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, OutputReference, ScriptPurpose,
  Spend, Transaction, Withdraw, placeholder,
}
use cardano_keri/application/action.{
  Action, BookRegistration, BookTermination, FoldRegistration, FoldTermination,
  ReturnRegistration, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{
  ApplicationParameters, Configuration, Registration, RegistrationData,
}
use cardano_keri/application/row_vectors as rows
use cardano_keri/checkpoint/datum as checkpoint_datum
use cardano_keri/checkpoint/datum.{TerminationPending}
use cardano_keri/checkpoint/observer.{
  ObserverClaim, ObserverEnvelope, observe_register,
}
use singular_state/preimage.{
  RegistryIdentity, active_token_name, approval_name, configuration_token_name,
  initial_datum_hash, registration_preimage, termination_preimage,
}

// ---- the deployment -----------------------------------------------------------

pub fn application() -> PolicyId {
  cfg.application_policy
}

pub fn registry() -> RegistryIdentity {
  RegistryIdentity { policy: cfg.state_policy, name: cfg.registry_name }
}

pub fn foreign_registry() -> RegistryIdentity {
  RegistryIdentity { policy: cfg.foreign_state_policy, name: cfg.registry_name }
}

pub fn parameters() -> ApplicationParameters {
  ApplicationParameters {
    registration_cost: cfg.registration_cost,
    minimum_tip: cfg.minimum_tip,
    process_time: cfg.process_time,
    retract_time: 0,
    booking_width: cfg.booking_width,
  }
}

/// The hash the checkpoint credential of the scenario is the script of.
pub fn checkpoint_hash() -> ByteArray {
  when cfg.checkpoint_credential is {
    Script(hash) -> hash
    _ -> fail @"the scenario's checkpoint credential is a script"
  }
}

pub fn app_address() -> Address {
  from_script(application())
}

pub fn checkpoint_address() -> Address {
  held.address_of(cfg.checkpoint_credential)
}

// ---- running the handlers -----------------------------------------------------

fn redeemer_of(tx: Transaction, purpose: ScriptPurpose) -> Option<Data> {
  when
    list.filter_map(
      tx.redeemers,
      fn(Pair(candidate, redeemer)) {
        if candidate == purpose {
          Some(redeemer)
        } else {
          None
        }
      },
    )
  is {
    [redeemer, ..] -> Some(redeemer)
    [] -> None
  }
}

/// Whether the application runs at all: its policy is minted or burned, or an
/// input sits at its address.
pub fn application_runs(tx: Transaction) -> Bool {
  application_mints(tx) || list.any(tx.inputs, at_application)
}

fn application_mints(tx: Transaction) -> Bool {
  !list.is_empty(dict.to_pairs(tokens(tx.mint, application())))
}

fn at_application(input: Input) -> Bool {
  input.output.address.payment_credential == Script(application())
}

/// The verdict of the application over a transaction, given its two handlers
/// (a test module imports the validator): every handler the ledger would run
/// accepts. A transaction the application does not run in
/// is accepted by it.
pub fn accepts(
  run_mint: fn(List<Action>, Transaction) -> Bool,
  run_spend: fn(SpendAction, OutputReference, Transaction) -> Bool,
  tx: Transaction,
) -> Bool {
  and {
    if application_mints(tx) {
      when redeemer_of(tx, Mint(application())) is {
        Some(raw) -> {
          expect actions: List<Action> = raw
          run_mint(actions, tx)
        }
        None -> False
      }
    } else {
      True
    },
    list.all(
      list.filter(tx.inputs, at_application),
      fn(input) {
        when redeemer_of(tx, Spend(input.output_reference)) is {
          Some(raw) -> {
            expect action: SpendAction = raw
            run_spend(action, input.output_reference, tx)
          }
          None -> False
        }
      },
    ),
  }
}

// ---- values and outputs -------------------------------------------------------

pub fn mint_of(items: List<(PolicyId, AssetName, Int)>) -> Value {
  list.foldl(
    items,
    zero,
    fn((policy, name, quantity), acc) { add(acc, policy, name, quantity) },
  )
}

fn token(policy: PolicyId, name: AssetName, quantity: Int) -> Value {
  add(zero, policy, name, quantity)
}

fn with_lovelace(lovelace: Int, extra: Value) -> Value {
  add(extra, "", "", lovelace)
}

fn as_data(value: Data) -> Data {
  value
}

/// The approval of a request, from the public Singular preimage.
pub fn approval_of(data: RegistrationData) -> AssetName {
  approval_name(
    registration_preimage(
      data.key,
      data.registry,
      data.holding_address,
      initial_datum_hash(data.initial_datum),
      data.deposit,
    ),
  )
}

pub fn active_of(data: RegistrationData) -> AssetName {
  active_token_name(data.registry, data.key)
}

pub fn termination_approval_of(
  registry: RegistryIdentity,
  key: ByteArray,
) -> AssetName {
  approval_name(termination_preimage(key, registry))
}

/// A request output: at the application address, carrying the request and its
/// approval.
pub fn request_output(data: RegistrationData, lovelace: Int) -> Output {
  Output {
    address: app_address(),
    value: with_lovelace(lovelace, token(application(), approval_of(data), 1)),
    datum: InlineDatum(Registration { registration: data }),
    reference_script: None,
  }
}

pub fn request_input(index: Int, data: RegistrationData, lovelace: Int) -> Input {
  Input {
    output_reference: reference(60 + index),
    output: request_output(data, lovelace),
  }
}

pub fn reference(index: Int) -> OutputReference {
  OutputReference { transaction_id: #"0a0b0c0d", output_index: index }
}

/// The configuration record of `registry`, naming `checkpoint` as the
/// checkpoint validator's credential.
pub fn config_output(
  registry: RegistryIdentity,
  checkpoint: Credential,
) -> Output {
  Output {
    address: app_address(),
    value: with_lovelace(
      cfg.record_lovelace,
      token(application(), configuration_token_name(registry), 1),
    ),
    datum: InlineDatum(
      Configuration {
        parameters: parameters(),
        checkpoint_credential: checkpoint,
      },
    ),
    reference_script: None,
  }
}

pub fn config_input(
  index: Int,
  registry: RegistryIdentity,
  checkpoint: Credential,
) -> Input {
  Input {
    output_reference: reference(index),
    output: config_output(registry, checkpoint),
  }
}

pub fn range(lower: Int, upper: Int) -> Interval<Int> {
  Interval {
    lower_bound: IntervalBound { bound_type: Finite(lower), is_inclusive: True },
    upper_bound: IntervalBound {
      bound_type: Finite(upper),
      is_inclusive: False,
    },
  }
}

pub fn donation_of(amount: Int) -> Option<Int> {
  if amount == 0 {
    None
  } else {
    Some(amount)
  }
}

pub fn envelope(claim: ObserverClaim, payload: Data) -> Data {
  let value: Data = ObserverEnvelope { claim, payload }
  value
}

// ---- booking ------------------------------------------------------------------

pub type Booking {
  data: RegistrationData,
  lovelace: Int,
  mint: Int,
  references: Bool,
  lower: Int,
  upper: Int,
  checkpoint: Credential,
  actions: List<Action>,
  /// How many identical request outputs the transaction creates.
  copies: Int,
}

/// Lean row `booking`: a perfect booking.
pub fn booking() -> Booking {
  Booking {
    data: rows.request_data(9001),
    lovelace: 18,
    mint: 1,
    references: True,
    lower: 9,
    upper: 10,
    checkpoint: cfg.checkpoint_credential,
    actions: [BookRegistration { output_index: 0 }],
    copies: 1,
  }
}

pub fn booking_tx(b: Booking) -> Transaction {
  Transaction {
    ..placeholder,
    outputs: list.repeat(request_output(b.data, b.lovelace), b.copies),
    mint: mint_of([(application(), approval_of(b.data), b.mint)]),
    // No record of another registry exists under this application: a record is
    // created only for a registry whose state policy was checked at its genesis.
    reference_inputs: if b.references {
      [config_input(50, registry(), b.checkpoint)]
    } else {
      []
    },
    validity_range: range(b.lower, b.upper),
    redeemers: [Pair(Mint(application()), as_data(b.actions))],
  }
}

// ---- fold ---------------------------------------------------------------------

pub type Fold {
  data: RegistrationData,
  request_lovelace: Int,
  holding_lovelace: Int,
  holding_address: Address,
  holding_datum: Data,
  holding_active: Int,
  burn: Int,
  active_mint: Int,
  lower: Int,
  upper: Int,
  donation: Int,
  /// The claim of the registration observer's withdrawal; None leaves the
  /// withdrawal out.
  claim: Option<ObserverClaim>,
  withdrawn: Int,
  redeemer: SpendAction,
  /// A second request input at the application address, with its redeemer.
  second: Option<(RegistrationData, Option<SpendAction>)>,
  /// The payload of the observer envelope (the evidence the observer reads).
  payload: Data,
  /// Inputs and mint items beside the fold's own (a hash-proof token and
  /// its burn, for a transaction the real observer runs over).
  extra_inputs: List<Input>,
  extra_mint: List<(PolicyId, AssetName, Int)>,
}

pub fn attestation() -> ObserverClaim {
  ObserverClaim {
    action: observe_register,
    checkpoint_policy: checkpoint_hash(),
    own_ref: None,
  }
}

/// Lean row `fold-at-deadline`: a perfect fold.
pub fn fold() -> Fold {
  let data = rows.request_data(9001)
  Fold {
    data,
    request_lovelace: 18,
    holding_lovelace: 15,
    holding_address: checkpoint_address(),
    holding_datum: rows.initial_datum(0),
    holding_active: 1,
    burn: -1,
    active_mint: 1,
    lower: 12,
    upper: 15,
    donation: 2,
    claim: Some(attestation()),
    withdrawn: 0,
    redeemer: FoldRegistration { holding_index: 0 },
    second: None,
    payload: builtin.i_data(0),
    extra_inputs: [],
    extra_mint: [],
  }
}

pub fn holding_output(f: Fold) -> Output {
  Output {
    address: f.holding_address,
    value: with_lovelace(
      f.holding_lovelace,
      token(f.data.registry.policy, active_of(f.data), f.holding_active),
    ),
    datum: InlineDatum(f.holding_datum),
    reference_script: None,
  }
}

pub fn fold_tx(f: Fold) -> Transaction {
  let second_inputs = when f.second is {
    Some((data, _)) -> [request_input(1, data, f.request_lovelace)]
    None -> []
  }
  let second_redeemers = when f.second is {
    Some((_, Some(action))) -> [Pair(Spend(reference(61)), as_data(action))]
    _ -> []
  }
  let second_approval = when f.second is {
    Some((data, _)) -> [(application(), approval_of(data), f.burn)]
    None -> []
  }
  let burns = mint_of(
    list.concat(
      [
        (application(), approval_of(f.data), f.burn),
        (f.data.registry.policy, active_of(f.data), f.active_mint),
      ],
      list.concat(second_approval, f.extra_mint),
    ),
  )
  let withdrawals = when f.claim is {
    Some(_) -> [Pair(Script(rows.observer_hash), f.withdrawn)]
    None -> []
  }
  let observer = when f.claim is {
    Some(claim) ->
      [Pair(Withdraw(Script(rows.observer_hash)), envelope(claim, f.payload))]
    None -> []
  }
  let burn_redeemer = if f.burn == 0 {
    []
  } else {
    let none: List<Action> = []
    [Pair(Mint(application()), as_data(none))]
  }
  Transaction {
    ..placeholder,
    inputs: list.concat(
      [request_input(0, f.data, f.request_lovelace), ..second_inputs],
      f.extra_inputs,
    ),
    outputs: [holding_output(f)],
    mint: burns,
    reference_inputs: [
      config_input(50, f.data.registry, cfg.checkpoint_credential),
    ],
    validity_range: range(f.lower, f.upper),
    treasury_donation: donation_of(f.donation),
    withdrawals,
    redeemers: list.concat(
      list.concat(
        [Pair(Spend(reference(60)), as_data(f.redeemer))],
        second_redeemers,
      ),
      list.concat(burn_redeemer, observer),
    ),
  }
}

// ---- return -------------------------------------------------------------------

pub type Return {
  data: RegistrationData,
  request_lovelace: Int,
  pays: List<(Address, Int)>,
  burn: Int,
  lower: Int,
  upper: Int,
}

/// Lean row `return-at-deadline`: a perfect return.
pub fn returned() -> Return {
  Return {
    data: rows.request_data(9001),
    request_lovelace: 18,
    pays: [(rows.refund_address, 17), (rows.spender_address, 1)],
    burn: -1,
    lower: 15,
    upper: 20,
  }
}

pub fn return_tx(r: Return) -> Transaction {
  let none: List<Action> = []
  Transaction {
    ..placeholder,
    inputs: [request_input(0, r.data, r.request_lovelace)],
    outputs: list.map(
      r.pays,
      fn((address, lovelace)) {
        Output {
          address,
          value: from_lovelace(lovelace),
          datum: NoDatum,
          reference_script: None,
        }
      },
    ),
    mint: mint_of([(application(), approval_of(r.data), r.burn)]),
    reference_inputs: [
      config_input(50, r.data.registry, cfg.checkpoint_credential),
    ],
    validity_range: range(r.lower, r.upper),
    redeemers: list.concat(
      [Pair(Spend(reference(60)), as_data(ReturnRegistration))],
      if r.burn == 0 {
        []
      } else {
        [Pair(Mint(application()), as_data(none))]
      },
    ),
  }
}

// ---- termination ----------------------------------------------------------------

pub type Termination {
  approval_burn: Int,
  active_burn: Int,
  redeemer: SpendAction,
  datum: transaction.Datum,
  lovelace: Int,
  registry: RegistryIdentity,
  /// The key whose termination is folded.
  key: ByteArray,
  /// Whether the registry's configuration record is a reference input.
  references: Bool,
  /// The treasury donation of the transaction.
  donation: Int,
}

/// Lean row `termination-fold`: a pending termination spent by its fold.
pub fn termination() -> Termination {
  Termination {
    approval_burn: -1,
    active_burn: -1,
    redeemer: FoldTermination { registry: registry(), key: rows.key_e },
    datum: NoDatum,
    lovelace: 3,
    registry: registry(),
    key: rows.key_e,
    references: True,
    donation: 2,
  }
}

pub fn pending_output(t: Termination) -> Output {
  Output {
    address: app_address(),
    value: with_lovelace(
      t.lovelace,
      add(
        token(t.registry.policy, active_token_name(t.registry, t.key), 1),
        application(),
        termination_approval_of(t.registry, t.key),
        1,
      ),
    ),
    datum: t.datum,
    reference_script: None,
  }
}

pub fn termination_tx(t: Termination) -> Transaction {
  let none: List<Action> = []
  Transaction {
    ..placeholder,
    inputs: [
      Input { output_reference: reference(80), output: pending_output(t) },
    ],
    mint: mint_of(
      [
        (
          application(),
          termination_approval_of(t.registry, t.key),
          t.approval_burn,
        ),
        (t.registry.policy, active_token_name(t.registry, t.key), t.active_burn),
      ],
    ),
    reference_inputs: if t.references {
      [config_input(50, registry(), cfg.checkpoint_credential)]
    } else {
      []
    },
    treasury_donation: donation_of(t.donation),
    validity_range: range(12, 15),
    redeemers: list.concat(
      [Pair(Spend(reference(80)), as_data(t.redeemer))],
      if t.approval_burn == 0 {
        []
      } else {
        [Pair(Mint(application()), as_data(none))]
      },
    ),
  }
}

// ---- termination booking ----------------------------------------------------------

/// The pending-termination datum of the AID whose key is `aid`, as a conviction
/// writes it.
pub fn pending_datum_of(aid: ByteArray) -> Data {
  checkpoint_datum.write(TerminationPending { aid, sn: 0, epoch: 0 })
}

pub type TerminationBooking {
  /// The registry the booking names: the action, the request and the approval.
  registry: RegistryIdentity,
  /// The key the booking names.
  key: ByteArray,
  /// The key the spent pending output holds the active token of.
  pending_key: ByteArray,
  pending_datum: Data,
  pending_address: Address,
  pending_lovelace: Int,
  pending_holds_active: Bool,
  /// Whether the pending output also holds a token of no registry.
  pending_extra_token: Bool,
  request_lovelace: Int,
  request_datum: transaction.Datum,
  /// How many termination requests the transaction places.
  copies: Int,
  /// What the booker keeps; no output when zero.
  booker_lovelace: Int,
  /// The termination approvals minted.
  mint: Int,
  references: Bool,
  actions: List<Action>,
}

/// The pending output a conviction leaves.
pub fn pending_reference() -> OutputReference {
  reference(81)
}

/// Lean row `termination-booking`: anyone books the termination of a convicted
/// checkpoint.
pub fn termination_booking() -> TerminationBooking {
  TerminationBooking {
    registry: registry(),
    key: rows.key_e,
    pending_key: rows.key_e,
    pending_datum: rows.variant(8),
    pending_address: checkpoint_address(),
    pending_lovelace: 4,
    pending_holds_active: True,
    pending_extra_token: False,
    request_lovelace: 3,
    request_datum: NoDatum,
    copies: 1,
    booker_lovelace: 1,
    mint: 1,
    references: True,
    actions: [
      BookTermination {
        pending: pending_reference(),
        output_index: 0,
        registry: registry(),
        key: rows.key_e,
      },
    ],
  }
}

pub fn termination_booking_tx(b: TerminationBooking) -> Transaction {
  let held = if b.pending_holds_active {
    with_lovelace(
      b.pending_lovelace,
      token(b.registry.policy, active_token_name(b.registry, b.pending_key), 1),
    )
  } else {
    from_lovelace(b.pending_lovelace)
  }
  let pending = Output {
    address: b.pending_address,
    value: if b.pending_extra_token {
      add(held, "no-registry", "extra", 1)
    } else {
      held
    },
    datum: InlineDatum(b.pending_datum),
    reference_script: None,
  }
  let request = Output {
    address: app_address(),
    value: with_lovelace(
      b.request_lovelace,
      add(
        token(b.registry.policy, active_token_name(b.registry, b.key), 1),
        application(),
        termination_approval_of(b.registry, b.key),
        1,
      ),
    ),
    datum: b.request_datum,
    reference_script: None,
  }
  let booker = if b.booker_lovelace == 0 {
    []
  } else {
    [
      Output {
        address: rows.spender_address,
        value: from_lovelace(b.booker_lovelace),
        datum: NoDatum,
        reference_script: None,
      },
    ]
  }
  Transaction {
    ..placeholder,
    inputs: [Input { output_reference: pending_reference(), output: pending }],
    outputs: list.concat(list.repeat(request, b.copies), booker),
    mint: mint_of(
      [(application(), termination_approval_of(b.registry, b.key), b.mint)],
    ),
    reference_inputs: if b.references {
      [config_input(50, registry(), cfg.checkpoint_credential)]
    } else {
      []
    },
    validity_range: range(12, 15),
    redeemers: [Pair(Mint(application()), as_data(b.actions))],
  }
}

// ---- a delivered checkpoint ----------------------------------------------------

/// A transaction of the checkpoint's own lifecycle spending the delivered
/// checkpoint at `address`; no application action.
pub fn checkpoint_spend(address: Address) -> Transaction {
  let data = rows.request_data(9001)
  let output = Output {
    address,
    value: with_lovelace(15, token(data.registry.policy, active_of(data), 1)),
    datum: InlineDatum(rows.initial_datum(0)),
    reference_script: None,
  }
  Transaction {
    ..placeholder,
    inputs: [Input { output_reference: reference(70), output }],
    outputs: [output],
    validity_range: range(16, 17),
  }
}

/// A spend of the checkpoint input, as the application sees it when the input
/// sits at its own address: the redeemers an attacker may attach.
pub fn possible_actions() -> List<SpendAction> {
  [
    FoldRegistration { holding_index: 0 },
    ReturnRegistration,
    FoldTermination { registry: registry(), key: rows.key_e },
  ]
}

/// Lean row `termination-approval-minted`: a termination approval minted onto
/// a pending termination, with no action.
pub fn termination_minted() -> Transaction {
  let t = termination()
  let none: List<Action> = []
  Transaction {
    ..placeholder,
    outputs: [pending_output(t)],
    mint: mint_of(
      [(application(), termination_approval_of(t.registry, rows.key_e), 1)],
    ),
    validity_range: range(12, 15),
    redeemers: [Pair(Mint(application()), as_data(none))],
  }
}
