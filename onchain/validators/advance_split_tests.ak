//// R1 RED: the two-policy advance (fact policy, change policy) and the checkpoint spend, for rotation and freeze,
//// on the current datum layout. Each purpose is evaluated on its own over the same transaction, as the ledger does.
//// Positive cases (suffix `_accepts`) are RED against the stubs and the observer-based checkpoint; refusal cases
//// (`fail`) each have a positive twin and are only meaningful once the twin passes. The expected asset names are
//// generated independently (scripts/advance-split-vectors.mjs). Depositing rotation is a separate RED increment.

use advance_attestation
use aiken/builtin
use aiken/collection/list
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, add, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/checkpoint/advance_split_vectors as sv
use cardano_keri/checkpoint/split.{SignedFact, signed_name}
use cardano_keri/checkpoint/threshold.{Unweighted}
use checkpoint_register
use event_attestation

const event_policy: PolicyId =
  #"e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1"

const change_policy: PolicyId =
  #"c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"

const d_reg: Int = 1_000_000_000

const freeze_bond: Int = 5_000_000

const premium: Int = 2_000_000

const min_ada: Int = 2_000_000

const pool: Int = 3_000_000

/// One checkpoint of a transaction.
type Case {
  input: Input,
  successor: Output,
  payee: Output,
  successor_index: Int,
  payee_index: Int,
  envelope: Data,
  fact: Data,
  fact_name: ByteArray,
  change_name: ByteArray,
  own_ref: OutputReference,
  action: Int,
  token_name: ByteArray,
}

type Scenario {
  old_datum: Data,
  new_datum: Data,
  frozen_datum: Data,
  evidence: Data,
  freeze_payload: Data,
  fact: Data,
  txid: ByteArray,
  index: Int,
  token_name: ByteArray,
  fact_name: ByteArray,
  rotation_at_0: ByteArray,
  rotation_at_1: ByteArray,
  freeze_at_0: ByteArray,
  freeze_at_1: ByteArray,
}

fn two_key() -> Scenario {
  Scenario {
    old_datum: sv.two_key_old_datum(),
    new_datum: sv.two_key_new_datum(),
    frozen_datum: sv.two_key_frozen_datum(),
    evidence: sv.two_key_evidence(),
    freeze_payload: sv.two_key_freeze_payload(),
    fact: sv.two_key_fact(),
    txid: sv.two_key_txid,
    index: sv.two_key_index,
    token_name: sv.two_key_token_name,
    fact_name: sv.two_key_fact_name,
    rotation_at_0: sv.two_key_change_rotation_at_0,
    rotation_at_1: sv.two_key_change_rotation_at_1,
    freeze_at_0: sv.two_key_change_freeze_at_0,
    freeze_at_1: sv.two_key_change_freeze_at_1,
  }
}

fn unwitnessed() -> Scenario {
  Scenario {
    old_datum: sv.unwitnessed_old_datum(),
    new_datum: sv.unwitnessed_new_datum(),
    frozen_datum: sv.unwitnessed_frozen_datum(),
    evidence: sv.unwitnessed_evidence(),
    freeze_payload: sv.unwitnessed_freeze_payload(),
    fact: sv.unwitnessed_fact(),
    txid: sv.unwitnessed_txid,
    index: sv.unwitnessed_index,
    token_name: sv.unwitnessed_token_name,
    fact_name: sv.unwitnessed_fact_name,
    rotation_at_0: sv.unwitnessed_change_rotation_at_0,
    rotation_at_1: sv.unwitnessed_change_rotation_at_1,
    freeze_at_0: sv.unwitnessed_change_freeze_at_0,
    freeze_at_1: sv.unwitnessed_change_freeze_at_1,
  }
}

fn live_value(lovelace: Int, token_name: ByteArray) -> assets.Value {
  from_lovelace(lovelace)
    |> merge(from_asset(sv.state_policy, token_name, 1))
}

fn envelope_of(action: Int, ref: OutputReference, payload: Data) -> Data {
  let r: Data = ref
  builtin.constr_data(
    0,
    [
      builtin.constr_data(
        0,
        [
          builtin.i_data(action),
          builtin.b_data(sv.checkpoint_policy),
          builtin.constr_data(0, [r]),
        ],
      ),
      payload,
    ],
  )
}

/// A rotation (`action` 1) or a freeze (`action` 2) of one checkpoint, successor at `at`, payee or hunter at `payee_at`.
fn case_of(s: Scenario, action: Int, at: Int, payee_at: Int) -> Case {
  let ref = OutputReference { transaction_id: s.txid, output_index: s.index }
  let floor = min_ada + d_reg + freeze_bond
  let rotation = action == 1
  Case {
    input: Input {
      output_reference: ref,
      output: Output {
        address: from_script(sv.checkpoint_policy),
        value: live_value(
          if rotation {
            floor + pool
          } else {
            floor + 1_000_000
          },
          s.token_name,
        ),
        datum: InlineDatum(s.old_datum),
        reference_script: None,
      },
    },
    successor: Output {
      address: from_script(sv.checkpoint_policy),
      value: live_value(
        if rotation {
          floor + pool - premium
        } else {
          min_ada + d_reg + 1_000_000
        },
        s.token_name,
      ),
      datum: InlineDatum(
        if rotation {
          s.new_datum
        } else {
          s.frozen_datum
        },
      ),
      reference_script: None,
    },
    payee: Output {
      address: from_verification_key(
        #"aa00aa00aa00aa00aa00aa00aa00aa00aa00aa00aa00aa00aa00aa00",
      ),
      value: from_lovelace(
        if rotation {
          premium
        } else {
          freeze_bond
        },
      ),
      datum: NoDatum,
      reference_script: None,
    },
    successor_index: at,
    payee_index: payee_at,
    envelope: envelope_of(
      action,
      ref,
      if rotation {
        s.evidence
      } else {
        s.freeze_payload
      },
    ),
    fact: s.fact,
    fact_name: s.fact_name,
    change_name: if rotation {
      if at == 0 {
        s.rotation_at_0
      } else {
        s.rotation_at_1
      }
    } else if at == 0 {
      s.freeze_at_0
    } else {
      s.freeze_at_1
    },
    own_ref: ref,
    action,
    token_name: s.token_name,
  }
}

/// The attestations leave in a change output of the submitter; successors first, then payees, then change.
fn tx_of(cases: List<Case>) -> Transaction {
  let mint = list.foldl(
    cases,
    zero,
    fn(c, value) {
      value
        |> add(event_policy, c.fact_name, 1)
        |> add(change_policy, c.change_name, 1)
    },
  )
  let attestations = list.foldl(
    cases,
    zero,
    fn(c, value) {
      value
        |> add(event_policy, c.fact_name, 1)
        |> add(change_policy, c.change_name, 1)
    },
  )
  let change = Output {
    address: from_verification_key(
      #"bb00bb00bb00bb00bb00bb00bb00bb00bb00bb00bb00bb00bb00bb00",
    ),
    value: from_lovelace(5_000_000) |> merge(attestations),
    datum: NoDatum,
    reference_script: None,
  }
  Transaction {
    ..placeholder,
    inputs: list.map(cases, fn(c) { c.input }),
    outputs: list.concat(
      list.concat(
        list.map(cases, fn(c) { c.successor }),
        list.map(cases, fn(c) { c.payee }),
      ),
      [change],
    ),
    mint,
  }
}

fn facts_redeemer(cases: List<Case>) -> Data {
  builtin.constr_data(0, [builtin.list_data(list.map(cases, fn(c) { c.fact }))])
}

fn claims_redeemer(cases: List<Case>) -> Data {
  builtin.constr_data(
    0,
    [
      builtin.list_data(
        list.map(
          cases,
          fn(c) {
            builtin.constr_data(
              0,
              [c.envelope, builtin.i_data(c.successor_index)],
            )
          },
        ),
      ),
    ],
  )
}

fn fact_policy(cases: List<Case>, tx: Transaction) -> Bool {
  event_attestation.event_attestation.mint(
    0,
    facts_redeemer(cases),
    event_policy,
    tx,
  )
}

fn change_policy_runs(cases: List<Case>, tx: Transaction) -> Bool {
  advance_attestation.advance_attestation.mint(
    0,
    event_policy,
    claims_redeemer(cases),
    change_policy,
    tx,
  )
}

fn spend_of(c: Case, tx: Transaction) -> Bool {
  let kind: Data = if c.action == 1 {
    builtin.constr_data(
      0,
      [
        builtin.i_data(c.payee_index),
        builtin.constr_data(0, []),
        builtin.i_data(c.successor_index),
      ],
    )
  } else {
    builtin.constr_data(
      3,
      [builtin.i_data(c.payee_index), builtin.i_data(c.successor_index)],
    )
  }
  checkpoint_register.checkpoint_register.spend(
    sv.state_policy,
    sv.registry_name,
    change_policy,
    #"",
    #"",
    0,
    d_reg,
    freeze_bond,
    premium,
    #"",
    None,
    kind,
    c.own_ref,
    tx,
  )
}

fn only(cs: List<Case>) -> Case {
  expect [c] = cs
  c
}

// ---------------------------------------------------------------------------------------------
// one rotation: each purpose of the same transaction
// ---------------------------------------------------------------------------------------------
fn one_rotation() -> List<Case> {
  [case_of(two_key(), 1, 0, 1)]
}

test rotation_fact_accepts() {
  let cs = one_rotation()
  fact_policy(cs, tx_of(cs))
}

test rotation_change_accepts() {
  let cs = one_rotation()
  change_policy_runs(cs, tx_of(cs))
}

test rotation_spend_accepts() {
  let cs = one_rotation()
  spend_of(only(cs), tx_of(cs))
}

// ---------------------------------------------------------------------------------------------
// one freeze
// ---------------------------------------------------------------------------------------------
fn one_freeze() -> List<Case> {
  [case_of(two_key(), 2, 0, 1)]
}

test freeze_fact_accepts() {
  let cs = one_freeze()
  fact_policy(cs, tx_of(cs))
}

test freeze_change_accepts() {
  let cs = one_freeze()
  change_policy_runs(cs, tx_of(cs))
}

test freeze_spend_accepts() {
  let cs = one_freeze()
  spend_of(only(cs), tx_of(cs))
}

// ---------------------------------------------------------------------------------------------
// two distinct checkpoints at one address, each with its own successor (second at index 1; payees after)
// ---------------------------------------------------------------------------------------------
fn two_rotations() -> List<Case> {
  [case_of(two_key(), 1, 0, 2), case_of(unwitnessed(), 1, 1, 3)]
}

test two_fact_accepts() {
  let cs = two_rotations()
  fact_policy(cs, tx_of(cs))
}

test two_change_accepts() {
  let cs = two_rotations()
  change_policy_runs(cs, tx_of(cs))
}

test two_spend_first_accepts() {
  let cs = two_rotations()
  expect [a, _] = cs
  spend_of(a, tx_of(cs))
}

test two_spend_second_accepts() {
  let cs = two_rotations()
  expect [_, b] = cs
  spend_of(b, tx_of(cs))
}

// the same two checkpoints with their successors in the other order of the outputs: the claims name the new places
fn two_rotations_reordered() -> List<Case> {
  [case_of(two_key(), 1, 1, 2), case_of(unwitnessed(), 1, 0, 3)]
}

fn reordered_tx(cs: List<Case>) -> Transaction {
  let t = tx_of(cs)
  expect [oa, ob, pa, pb, ch] = t.outputs
  Transaction { ..t, outputs: [ob, oa, pa, pb, ch] }
}

test reordered_change_accepts() {
  let cs = two_rotations_reordered()
  change_policy_runs(cs, reordered_tx(cs))
}

test reordered_spend_first_accepts() {
  let cs = two_rotations_reordered()
  expect [a, _] = cs
  spend_of(a, reordered_tx(cs))
}

test reordered_spend_second_accepts() {
  let cs = two_rotations_reordered()
  expect [_, b] = cs
  spend_of(b, reordered_tx(cs))
}

// ---------------------------------------------------------------------------------------------
// refusals, each attributed to its purpose; the twin above must pass for the refusal to mean anything
// ---------------------------------------------------------------------------------------------
fn without(cs: List<Case>, keep_fact: Bool, keep_change: Bool) -> Transaction {
  let t = tx_of(cs)
  let mint = list.foldl(
    cs,
    zero,
    fn(c, value) {
      value
        |> if keep_fact {
            add(_, event_policy, c.fact_name, 1)
          } else {
            fn(v) { v }
          }
        |> if keep_change {
            add(_, change_policy, c.change_name, 1)
          } else {
            fn(v) { v }
          }
    },
  )
  Transaction { ..t, mint }
}

// the checkpoint refuses without the change asset in the mint field
test spend_refuses_without_change_asset() fail {
  let cs = two_rotations()
  expect [a, _] = cs
  spend_of(a, without(cs, True, False))
}

// the change policy refuses without the fact asset in the same mint field
test change_refuses_without_fact_asset() fail {
  let cs = two_rotations()
  change_policy_runs(cs, without(cs, False, True))
}

// the claim names the other successor place: refused by the change policy and by the checkpoint
test change_refuses_wrong_successor_index() fail {
  let cs = two_rotations()
  expect [a, b] = cs
  change_policy_runs([Case { ..a, successor_index: 1 }, b], tx_of(cs))
}

test spend_refuses_swapped_outputs_first() fail {
  let cs = two_rotations()
  expect [a, _] = cs
  spend_of(a, reordered_tx(cs))
}

test spend_refuses_swapped_outputs_second() fail {
  let cs = two_rotations()
  expect [_, b] = cs
  spend_of(b, reordered_tx(cs))
}

// a positive mint under the fact policy that no claim verifies, with the empty name
test fact_refuses_unverified_empty_name() fail {
  let cs = one_rotation()
  let t = tx_of(cs)
  fact_policy(cs, Transaction { ..t, mint: add(t.mint, event_policy, #"", 1) })
}

test change_refuses_unverified_extra_name() fail {
  let cs = one_rotation()
  let t = tx_of(cs)
  change_policy_runs(
    cs,
    Transaction { ..t, mint: add(t.mint, change_policy, #"ab", 1) },
  )
}

// Burn needs no evidence: a mint field holding only burns passes the policies' burn branch
test fact_burn_accepts() {
  let t = Transaction {
    ..placeholder,
    mint: add(zero, event_policy, #"01", -1),
  }
  event_attestation.event_attestation.mint(
    0,
    builtin.constr_data(1, []),
    event_policy,
    t,
  )
}

test change_burn_accepts() {
  let t = Transaction {
    ..placeholder,
    mint: add(zero, change_policy, #"01", -1),
  }
  advance_attestation.advance_attestation.mint(
    0,
    event_policy,
    builtin.constr_data(1, []),
    change_policy,
    t,
  )
}

// a burn does not excuse a positive unverified name beside it
test burn_does_not_excuse_unverified_positive() fail {
  let t = Transaction {
    ..placeholder,
    mint: add(add(zero, event_policy, #"01", -1), event_policy, #"02", 1),
  }
  event_attestation.event_attestation.mint(
    0,
    builtin.constr_data(1, []),
    event_policy,
    t,
  )
}

// a controller signature flipped in the fact: refused by the fact policy alone
test fact_refuses_flipped_signature() fail {
  let cs = one_rotation()
  let c = only(cs)
  fact_policy([Case { ..c, fact: flip_first_signature(c.fact) }], tx_of(cs))
}

fn flip_first_signature(fact: Data) -> Data {
  let Pair(tag, fields) = builtin.un_constr_data(fact)
  expect [e, k, kt, w, t, sk, st, sigs, rc] = fields
  let sig_list = builtin.un_list_data(sigs)
  expect [first, ..rest] = sig_list
  let pair = builtin.un_list_data(first)
  expect [ix, s] = pair
  let flipped = builtin.b_data(
    builtin.cons_bytearray(
      255,
      builtin.slice_bytearray(1, 63, builtin.un_b_data(s)),
    ),
  )
  builtin.constr_data(
    tag,
    [
      e,
      k,
      kt,
      w,
      t,
      sk,
      st,
      builtin.list_data([builtin.list_data([ix, flipped]), ..rest]),
      rc,
    ],
  )
}

// ---------------------------------------------------------------------------------------------
// Rotation and freeze controls. Every refusal below has a named positive twin earlier in this file;
// under the stubs and the legacy decoding the refusals are vacuous, and the list at the end of the handoff says which.
// ---------------------------------------------------------------------------------------------

/// The mint field of the given claims, each name at the given quantity.
fn mint_of(cs: List<Case>) -> assets.Value {
  list.foldl(
    cs,
    zero,
    fn(c, value) {
      value
        |> add(event_policy, c.fact_name, 1)
        |> add(change_policy, c.change_name, 1)
    },
  )
}

/// The mint field of the transaction, with the attestations of one case at chosen quantities (0 absent).
fn mint_with(
  cs: List<Case>,
  only_first_fact: Int,
  only_first_change: Int,
) -> assets.Value {
  expect [first, ..rest] = cs
  let others = mint_of(rest)
  others
    |> add(event_policy, first.fact_name, only_first_fact)
    |> add(change_policy, first.change_name, only_first_change)
}

// R1-1: the claims name the other successor places and the mint field holds the names of exactly those claims, while the
// outputs stay as they were: the claim names verify, so a refusal can only come from the successor selection.
fn swapped_claims_original_outputs() -> (List<Case>, Transaction) {
  // derived from the matched positive transaction (`reordered_tx(claimed)`, the twin of the three controls): only the two
  // successor outputs are exchanged; the change output holdings and the mint field are those of the positive transaction
  let claimed = two_rotations_reordered()
  let positive = reordered_tx(claimed)
  expect [first, second, payee_a, payee_b, change] = positive.outputs
  (
    claimed,
    Transaction {
      ..positive,
      outputs: [second, first, payee_a, payee_b, change],
    },
  )
}

test change_refuses_matched_names_other_successor() fail {
  let (claimed, tx) = swapped_claims_original_outputs()
  change_policy_runs(claimed, tx)
}

test spend_first_refuses_matched_name_other_successor() fail {
  let (claimed, tx) = swapped_claims_original_outputs()
  expect [a, _] = claimed
  spend_of(a, tx)
}

test spend_second_refuses_matched_name_other_successor() fail {
  let (claimed, tx) = swapped_claims_original_outputs()
  expect [_, b] = claimed
  spend_of(b, tx)
}

// R1-2: one checkpoint's attestation absent, the other's retained
test spend_first_refuses_own_change_asset_absent_other_retained() fail {
  let cs = two_rotations()
  expect [a, _] = cs
  spend_of(a, Transaction { ..tx_of(cs), mint: mint_with(cs, 1, 0) })
}

// its twin: the checkpoint whose own attestation is present accepts in the same transaction
test spend_second_accepts_when_first_change_asset_absent() {
  let cs = two_rotations()
  expect [_, b] = cs
  spend_of(b, Transaction { ..tx_of(cs), mint: mint_with(cs, 1, 0) })
}

test change_refuses_one_fact_asset_absent_other_retained() fail {
  let cs = two_rotations()
  change_policy_runs(cs, Transaction { ..tx_of(cs), mint: mint_with(cs, 0, 1) })
}

test fact_refuses_one_own_name_absent_other_retained() fail {
  let cs = two_rotations()
  fact_policy(cs, Transaction { ..tx_of(cs), mint: mint_with(cs, 0, 1) })
}

// exact +1: a quantity of two is not one
test spend_refuses_change_asset_at_two() fail {
  let cs = two_rotations()
  expect [a, _] = cs
  spend_of(a, Transaction { ..tx_of(cs), mint: mint_with(cs, 1, 2) })
}

test change_refuses_change_asset_at_two() fail {
  let cs = two_rotations()
  change_policy_runs(cs, Transaction { ..tx_of(cs), mint: mint_with(cs, 1, 2) })
}

test change_refuses_fact_asset_at_two() fail {
  let cs = two_rotations()
  change_policy_runs(cs, Transaction { ..tx_of(cs), mint: mint_with(cs, 2, 1) })
}

test fact_refuses_own_name_at_two() fail {
  let cs = two_rotations()
  fact_policy(cs, Transaction { ..tx_of(cs), mint: mint_with(cs, 2, 1) })
}

// R1-3: the own-name scan of both policies, the empty name included, with the Burn branch beside it
test change_refuses_unverified_empty_name() fail {
  let cs = one_rotation()
  let t = tx_of(cs)
  change_policy_runs(
    cs,
    Transaction { ..t, mint: add(t.mint, change_policy, #"", 1) },
  )
}

test fact_issue_accepts_beside_an_unrelated_burn() {
  let cs = one_rotation()
  let t = tx_of(cs)
  fact_policy(cs, Transaction { ..t, mint: add(t.mint, event_policy, #"", -1) })
}

test change_issue_accepts_beside_an_unrelated_burn() {
  let cs = one_rotation()
  let t = tx_of(cs)
  change_policy_runs(
    cs,
    Transaction { ..t, mint: add(t.mint, change_policy, #"", -1) },
  )
}

fn burn_only(policy: PolicyId, name: ByteArray) -> Transaction {
  Transaction { ..placeholder, mint: add(zero, policy, name, -1) }
}

fn burn_and_positive(policy: PolicyId, name: ByteArray) -> Transaction {
  Transaction {
    ..placeholder,
    mint: add(add(zero, policy, name, -1), policy, #"02", 1),
  }
}

fn fact_burn(tx: Transaction) -> Bool {
  event_attestation.event_attestation.mint(
    0,
    builtin.constr_data(1, []),
    event_policy,
    tx,
  )
}

fn change_burn(tx: Transaction) -> Bool {
  advance_attestation.advance_attestation.mint(
    0,
    event_policy,
    builtin.constr_data(1, []),
    change_policy,
    tx,
  )
}

test fact_burn_empty_name_accepts() {
  fact_burn(burn_only(event_policy, #""))
}

test change_burn_empty_name_accepts() {
  change_burn(burn_only(change_policy, #""))
}

test fact_burn_empty_name_does_not_excuse_positive() fail {
  fact_burn(burn_and_positive(event_policy, #""))
}

test change_burn_empty_name_does_not_excuse_positive() fail {
  change_burn(burn_and_positive(change_policy, #""))
}

test change_burn_does_not_excuse_unverified_positive() fail {
  change_burn(burn_and_positive(change_policy, #"01"))
}

// R1-3 (second repair): the empty name as the POSITIVE entry beside a negative nonempty entry, in both Burn purposes; the
// matched pure-burn controls are `fact_burn_accepts` and `change_burn_accepts` (a nonempty burn alone)
fn burn_nonempty_and_positive_empty(policy: PolicyId) -> Transaction {
  Transaction {
    ..placeholder,
    mint: add(add(zero, policy, #"01", -1), policy, #"", 1),
  }
}

test fact_burn_refuses_positive_empty_name_beside_nonempty_burn() fail {
  fact_burn(burn_nonempty_and_positive_empty(event_policy))
}

test change_burn_refuses_positive_empty_name_beside_nonempty_burn() fail {
  change_burn(burn_nonempty_and_positive_empty(change_policy))
}

// ---------------------------------------------------------------------------------------------
// R1-G1: the freeze change policy binds the indexed successor (the frozen copy of the spent checkpoint at the
// claimed index, at the checkpoint address). Twins first; each refusal is derived from a matched positive transaction.
// ---------------------------------------------------------------------------------------------
fn two_freezes() -> List<Case> {
  [case_of(two_key(), 2, 0, 2), case_of(unwitnessed(), 2, 1, 3)]
}

fn two_freezes_reordered() -> List<Case> {
  [case_of(two_key(), 2, 1, 2), case_of(unwitnessed(), 2, 0, 3)]
}

test freeze_two_fact_accepts() {
  let cs = two_freezes()
  fact_policy(cs, tx_of(cs))
}

test freeze_two_change_accepts() {
  let cs = two_freezes()
  change_policy_runs(cs, tx_of(cs))
}

test freeze_two_spend_first_accepts() {
  let cs = two_freezes()
  expect [a, _] = cs
  spend_of(a, tx_of(cs))
}

test freeze_two_spend_second_accepts() {
  let cs = two_freezes()
  expect [_, b] = cs
  spend_of(b, tx_of(cs))
}

test freeze_reordered_change_accepts() {
  let cs = two_freezes_reordered()
  change_policy_runs(cs, reordered_tx(cs))
}

// the claims name the other successor places; the mint holds exactly their names; only the two successor outputs are
// exchanged against the matched positive transaction
fn freeze_swapped_claims_original_outputs() -> (List<Case>, Transaction) {
  let claimed = two_freezes_reordered()
  let positive = reordered_tx(claimed)
  expect [first, second, payee_a, payee_b, change] = positive.outputs
  (
    claimed,
    Transaction {
      ..positive,
      outputs: [second, first, payee_a, payee_b, change],
    },
  )
}

test freeze_change_refuses_matched_names_other_successor() fail {
  let (claimed, tx) = freeze_swapped_claims_original_outputs()
  change_policy_runs(claimed, tx)
}

test freeze_spend_refuses_matched_name_other_successor() fail {
  let (claimed, tx) = freeze_swapped_claims_original_outputs()
  expect [a, _] = claimed
  spend_of(a, tx)
}

// the output at the claimed index is the spent datum unchanged (not frozen): refused by the change policy alone
test freeze_change_refuses_an_unfrozen_successor() fail {
  let s = two_key()
  let c = case_of(s, 2, 0, 1)
  let kept = Output { ..c.successor, datum: InlineDatum(s.old_datum) }
  let t = tx_of([c])
  expect [_, payee, change] = t.outputs
  change_policy_runs([c], Transaction { ..t, outputs: [kept, payee, change] })
}

test freeze_change_refuses_a_successor_at_another_address() fail {
  let c = case_of(two_key(), 2, 0, 1)
  let away = Output {
    ..c.successor,
    address: from_verification_key(
      #"cc00cc00cc00cc00cc00cc00cc00cc00cc00cc00cc00cc00cc00cc00",
    ),
  }
  let t = tx_of([c])
  expect [_, payee, change] = t.outputs
  change_policy_runs([c], Transaction { ..t, outputs: [away, payee, change] })
}

// the change policy enforces the input relationship of the claim: a claim naming an input the transaction does not spend
test change_refuses_a_claim_naming_an_input_not_spent() fail {
  let cs = one_rotation()
  let c = only(cs)
  let t = tx_of(cs)
  change_policy_runs(cs, Transaction { ..t, inputs: [] })
}

// the current threshold of the fact: the mint field holds the name of the altered fact, so only the signers' threshold can refuse
test fact_refuses_a_current_threshold_the_signers_do_not_meet() fail {
  let cs = one_rotation()
  let c = only(cs)
  expect f: SignedFact = c.fact
  let altered = SignedFact { ..f, cur_threshold: Unweighted(3) }
  let altered_data: Data = altered
  let t = tx_of(cs)
  fact_policy(
    [Case { ..c, fact: altered_data }],
    Transaction { ..t, mint: add(zero, event_policy, signed_name(altered), 1) },
  )
}
