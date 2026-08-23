//// Executable reachability fixtures for the seven S0 handlers.
////
//// Each member has an honest accept and a reject that breaks its named
//// cost-bearing parse/proof/transition. Tests invoke the real handlers.

use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{empty, root}
use aiken/primitive/bytearray
use cardano/address.{from_verification_key}
use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/m12/event_decoder.{DecodeOk, decode_establishment_event}
use cardano_keri/m12/event_key.{event_key_of}
use cardano_keri/m12/proof_token.{proof_token_name}
use cardano_keri/m12/record.{apply_record_append}
use cardano_keri/m12/types.{
  CursorPolicy, CursorState, EscrowState, Established, FullyWitnessed, Genesis,
  HistoricalProof, RecordState, Service, Unwitnessed,
}
use s0_append.{AppendRedeemer}
use s0_consumer_predicates.{PredicateRedeemer}
use s0_cursor.{CursorRedeemer}
use s0_lineage.{LineageRedeemer}
use s0_maintenance_escrow.{EscrowRedeemer}
use s0_reference_cursor_consumer.{ReferenceConsumerRedeemer}
use s0_staging_proof_token.{StagingRedeemer}

const policy: ByteArray =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

const vk: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const zeros32: ByteArray =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const ones32: ByteArray =
  #"1111111111111111111111111111111111111111111111111111111111111111"

const honest2_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2269223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

const honest2_aid: ByteArray =
  #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e5"

const honest2_wrong_aid: ByteArray =
  #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e4"

const honest2_off_d: Int = 40

const honest2_off_i: Int = 91

const self_ref: OutputReference =
  OutputReference { transaction_id: zeros32, output_index: 0 }

fn ada_out(lovelace: Int) -> Output {
  Output {
    address: from_verification_key(vk),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn tx_now(now: Int) -> Transaction {
  Transaction { ..placeholder, validity_range: interval.between(now, now + 10) }
}

fn burn_tx_for(raw: ByteArray, aid: ByteArray, now: Int) -> Transaction {
  let name = proof_token_name(raw, aid)
  let held = merge(from_lovelace(2_000_000), from_asset(policy, name, 1))
  Transaction {
    ..placeholder,
    inputs: [
      Input {
        output_reference: self_ref,
        output: Output {
          address: from_verification_key(vk),
          value: held,
          datum: NoDatum,
          reference_script: None,
        },
      },
    ],
    mint: from_asset(policy, name, -1),
    validity_range: interval.between(now, now + 10),
  }
}

fn burn_tx(now: Int) -> Transaction {
  burn_tx_for(honest2_bytes, honest2_aid, now)
}

fn flip_i_span(raw: ByteArray) -> ByteArray {
  let at = honest2_off_i + 43
  bytearray.take(raw, at)
    |> bytearray.concat(#"30")
    |> bytearray.concat(bytearray.drop(raw, at + 1))
}

// Offset of the `"s"` sequence-number digit: outside both 44-char SAID
// spans [40, 84) and [91, 135).
const honest2_off_seq: Int = 142

// `"s":"0"` becomes `"s":"1"`. Length, both offsets and both qb64 AID
// spans are untouched, so every staging conjunct except the Blake3 SAID
// relationship stays satisfiable on the result.
fn flip_seq_digit(raw: ByteArray) -> ByteArray {
  bytearray.take(raw, honest2_off_seq)
    |> bytearray.concat(#"31")
    |> bytearray.concat(bytearray.drop(raw, honest2_off_seq + 1))
}

fn empty_proof(key: ByteArray) -> HistoricalProof {
  HistoricalProof {
    key,
    location: key,
    proof: [],
    prior_snapshot_digest: root(empty),
  }
}

fn good_cursor() -> CursorState {
  CursorState {
    keys_digest: ones32,
    keri_state: Established,
    grade: FullyWitnessed,
    last_moved_slot: 5,
    registration_slot: 1,
  }
}

fn good_policy() -> CursorPolicy {
  CursorPolicy {
    accepted_keys: ones32,
    accepted_states: [Established],
    minimum_grade: Unwitnessed,
    maximum_age: 100,
  }
}

// ---------------------------------------------------------------------
// append
// ---------------------------------------------------------------------

test accept_s0_append() {
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  s0_append.s0_append.spend(
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof_policy: policy,
      proof: empty_proof(#"01"),
    },
    self_ref,
    burn_tx(1),
  )
}

test reject_s0_append_said() fail {
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  s0_append.s0_append.spend(
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_wrong_aid,
      proof_policy: policy,
      proof: empty_proof(#"01"),
    },
    self_ref,
    burn_tx_for(honest2_bytes, honest2_wrong_aid, 1),
  )
}

test reject_s0_append_aid() fail {
  let raw = flip_i_span(honest2_bytes)
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  s0_append.s0_append.spend(
    Some(old),
    AppendRedeemer {
      raw_event: raw,
      cesr_aid: honest2_aid,
      proof_policy: policy,
      proof: empty_proof(#"01"),
    },
    self_ref,
    burn_tx_for(raw, honest2_aid, 1),
  )
}

test reject_s0_append_proof() fail {
  let old = RecordState {
    event_root: ones32,
    occupancy_root: zeros32,
    event_count: 0,
  }
  s0_append.s0_append.spend(
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof_policy: policy,
      proof: empty_proof(#"01"),
    },
    self_ref,
    burn_tx(1),
  )
}

test submitter_chosen_proof_key_is_rejected() {
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  expect DecodeOk(ev) = decode_establishment_event(honest2_bytes)
  expect Some(derived) = event_key_of(ev)
  expect Some(got) =
    apply_record_append(
      old,
      honest2_bytes,
      honest2_aid,
      policy,
      empty_proof(#"01"),
      burn_tx(1),
    )
  got.event_root == root(mpf.insert(empty, derived, honest2_aid, []))
}

// ---------------------------------------------------------------------
// cursor
// ---------------------------------------------------------------------

test accept_s0_cursor() {
  let key = #"01"
  let prior = root(mpf.insert(empty, key, ones32, []))
  let old = CursorState {
    keys_digest: ones32,
    keri_state: Established,
    grade: Unwitnessed,
    last_moved_slot: 1,
    registration_slot: 1,
  }
  let proof = HistoricalProof {
    key,
    location: key,
    proof: [],
    prior_snapshot_digest: prior,
  }
  s0_cursor.s0_cursor.spend(
    Some(old),
    CursorRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof_policy: policy,
      proof,
    },
    self_ref,
    burn_tx(10),
  )
}

test reject_s0_cursor_proof() fail {
  let old = CursorState {
    keys_digest: ones32,
    keri_state: Established,
    grade: Unwitnessed,
    last_moved_slot: 1,
    registration_slot: 1,
  }
  let proof = HistoricalProof {
    key: #"01",
    location: #"01",
    proof: [],
    prior_snapshot_digest: zeros32,
  }
  s0_cursor.s0_cursor.spend(
    Some(old),
    CursorRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof_policy: policy,
      proof,
    },
    self_ref,
    burn_tx(10),
  )
}

// ---------------------------------------------------------------------
// lineage
// ---------------------------------------------------------------------

test accept_s0_lineage() {
  let input_ref = OutputReference { transaction_id: zeros32, output_index: 1 }
  let identity = blake2b_256(
    zeros32 |> bytearray.concat(bytearray.from_int_big_endian(1, 2)),
  )
  let spent = Input { output_reference: input_ref, output: ada_out(2_000_000) }
  let tx = Transaction {
    ..placeholder,
    inputs: [spent],
    validity_range: interval.between(20, 30),
  }
  s0_lineage.s0_lineage.spend(
    None,
    LineageRedeemer { action: Genesis { identity } },
    self_ref,
    tx,
  )
}

test reject_s0_lineage_identity() fail {
  s0_lineage.s0_lineage.spend(
    None,
    LineageRedeemer { action: Genesis { identity: ones32 } },
    self_ref,
    tx_now(20),
  )
}

// ---------------------------------------------------------------------
// escrow
// ---------------------------------------------------------------------

test accept_s0_escrow() {
  let old = EscrowState {
    funder: vk,
    premium: 10,
    remaining_value: 100,
    notice_start: None,
  }
  let tx = Transaction { ..tx_now(50), outputs: [ada_out(90)] }
  s0_maintenance_escrow.s0_maintenance_escrow.spend(
    Some(old),
    EscrowRedeemer { action: Service, grade: FullyWitnessed },
    self_ref,
    tx,
  )
}

test reject_s0_escrow_grade() fail {
  let old = EscrowState {
    funder: vk,
    premium: 10,
    remaining_value: 100,
    notice_start: None,
  }
  let tx = Transaction { ..tx_now(50), outputs: [ada_out(90)] }
  expect
    s0_maintenance_escrow.s0_maintenance_escrow.spend(
      Some(old),
      EscrowRedeemer { action: Service, grade: Unwitnessed },
      self_ref,
      tx,
    )
}

// ---------------------------------------------------------------------
// staging / SAID
// ---------------------------------------------------------------------

test accept_s0_staging() {
  let name = proof_token_name(honest2_bytes, honest2_aid)
  let tx = Transaction { ..placeholder, mint: from_asset(policy, name, 1) }
  s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      off_i: honest2_off_i,
      off_d: honest2_off_d,
    },
    policy,
    tx,
  )
}

test reject_s0_staging_said() fail {
  let name = proof_token_name(honest2_bytes, honest2_wrong_aid)
  let tx = Transaction { ..placeholder, mint: from_asset(policy, name, 1) }
  s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_wrong_aid,
      off_i: honest2_off_i,
      off_d: honest2_off_d,
    },
    policy,
    tx,
  )
}

test reject_s0_staging_oversize() fail {
  let raw = honest2_bytes
    |> bytearray.concat(honest2_bytes)
    |> bytearray.concat(honest2_bytes)
  let name = proof_token_name(raw, honest2_aid)
  let tx = Transaction { ..placeholder, mint: from_asset(policy, name, 1) }
  s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: raw,
      cesr_aid: honest2_aid,
      off_i: honest2_off_i,
      off_d: honest2_off_d,
    },
    policy,
    tx,
  )
}

// The isolating case. `reject_s0_staging_said` and
// `reject_s0_staging_oversize` both die at an earlier conjunct, so neither
// notices if `blake3.verify` stops verifying. Here the only relevant
// invalidity is the Blake3 SAID relationship: one byte outside both SAID
// spans is changed, so length, AID length, both offsets, both qb64 spans
// and the pair-bound mint identity all still hold. Replacing that one call
// with a constant makes this case, and only this case, go red - which is
// what `scripts/s0/check-reachability.sh self-test` proves on every run.
test reject_s0_staging_blake3() fail {
  let raw = flip_seq_digit(honest2_bytes)
  let name = proof_token_name(raw, honest2_aid)
  let tx = Transaction { ..placeholder, mint: from_asset(policy, name, 1) }
  s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: raw,
      cesr_aid: honest2_aid,
      off_i: honest2_off_i,
      off_d: honest2_off_d,
    },
    policy,
    tx,
  )
}

// ---------------------------------------------------------------------
// predicates
// ---------------------------------------------------------------------

test accept_s0_predicates() {
  s0_consumer_predicates.s0_consumer_predicates.spend(
    Some(good_cursor()),
    PredicateRedeemer { policy: good_policy() },
    self_ref,
    tx_now(10),
  )
}

test reject_s0_predicates_keys() fail {
  let policy = CursorPolicy { ..good_policy(), accepted_keys: zeros32 }
  expect
    s0_consumer_predicates.s0_consumer_predicates.spend(
      Some(good_cursor()),
      PredicateRedeemer { policy },
      self_ref,
      tx_now(10),
    )
}

// ---------------------------------------------------------------------
// reference consumer
// ---------------------------------------------------------------------

test accept_s0_reference() {
  let cursor = good_cursor()
  let token = from_asset(policy, #"01", 1)
  let ref_in = Input {
    output_reference: OutputReference {
      transaction_id: ones32,
      output_index: 0,
    },
    output: Output {
      address: from_verification_key(vk),
      value: merge(from_lovelace(2_000_000), token),
      datum: InlineDatum(cursor),
      reference_script: None,
    },
  }
  let tx = Transaction { ..tx_now(10), reference_inputs: [ref_in] }
  s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend(
    None,
    ReferenceConsumerRedeemer {
      policy: good_policy(),
      expected_lineage: policy,
    },
    self_ref,
    tx,
  )
}

test reject_s0_reference_datum() fail {
  let token = from_asset(policy, #"01", 1)
  let ref_in = Input {
    output_reference: OutputReference {
      transaction_id: ones32,
      output_index: 0,
    },
    output: Output {
      address: from_verification_key(vk),
      value: merge(from_lovelace(2_000_000), token),
      datum: NoDatum,
      reference_script: None,
    },
  }
  let tx = Transaction { ..tx_now(10), reference_inputs: [ref_in] }
  expect
    s0_reference_cursor_consumer.s0_reference_cursor_consumer.spend(
      None,
      ReferenceConsumerRedeemer {
        policy: good_policy(),
        expected_lineage: policy,
      },
      self_ref,
      tx,
    )
}
