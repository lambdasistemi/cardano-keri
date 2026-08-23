//// Executable reachability fixtures for the seven S0 handlers.
////
//// Each member has an honest accept and a reject that breaks its named
//// cost-bearing parse/proof/transition. Tests invoke the real handlers.

use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{Leaf, empty, root}
use aiken/primitive/bytearray
use cardano/address.{from_verification_key}
use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/blake3
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/m12/event_decoder.{DecodeOk, decode_establishment_event}
use cardano_keri/m12/event_key.{event_key_of}
use cardano_keri/m12/proof_token.{dummy_span, proof_token_name}
use cardano_keri/m12/record.{apply_record_append, bind_parsed_event}
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

const other_policy: ByteArray =
  #"5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b"

// Present-prior rotation from kli-export-2-of-5-rotation.cesr.
const rot_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303264385f222c2274223a22726f74222c2264223a22454f6366476e6e484e597568556e497946483672536856546a4a525255664d333752364a42582d51794a7a62222c2269223a224544756a734966555261627a58797942756c756b646c506b475f4258396434707836564551464d6433337a54222c2273223a2231222c2270223a224544756a734966555261627a58797942756c756b646c506b475f4258396434707836564551464d6433337a54222c226b74223a2232222c226b223a5b22444e6d5031713845436154584e7245376c6461412d44537277486f2d73315a494a44435f6858563765636e31222c22444670506e4e6a4c4b2d5f63776b4b4279326479585568526132444e66705a6970537431496b446f58742d41222c224441304536455a6230672d6832554a626d6b785854356349674f3359336a7062636b536b4c496b4d4d366876222c22444d424943505f644c33646d716450444e58477a68462d4e59487a5474453734546557375351796155754972222c22444b45584a39766878422d316c71696c6b6a71354c4b443270464e385a4138696f5266563251776338664633225d2c226e74223a2232222c226e223a5b22454e7479386c35696d6b4d493642625f4c314368377869516865646333557277637667595377584158713378222c224545624d674c384d7044306b416572745553445139716c41774469596f324859634855374c753830734e5861222c22454f533461527a794c6c642d5579434638687a327336326e6871754f4574664c385837313959775043516946222c22454877486e726543515a41764b5572726849584244764a7a61414b3051534f624849656b45796a4777326144222c2245466f6f5f65686a35794e39393174594964693069574235383276307177583559464d6f4a54495667497030225d2c226274223a2232222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d"

const rot_aid: ByteArray =
  #"e71f1a79c7358ba1527232147eab4a15538c945151f337ed1e89057f90c89cdb"

const rot_off_d: Int = 40

const rot_off_i: Int = 91

const rot_k_flip_at: Int = 254

fn flip_byte(raw: ByteArray, at: Int) -> ByteArray {
  bytearray.take(raw, at)
    |> bytearray.concat(#"30")
    |> bytearray.concat(bytearray.drop(raw, at + 1))
}

fn splice_span(raw: ByteArray, off: Int, span: ByteArray) -> ByteArray {
  bytearray.take(raw, off)
    |> bytearray.concat(span)
    |> bytearray.concat(bytearray.drop(raw, off + 44))
}

fn rival_digest(raw: ByteArray) -> ByteArray {
  blake3.hash(splice_span(flip_byte(raw, rot_k_flip_at), rot_off_d, dummy_span))
}

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

fn empty_proof() -> HistoricalProof {
  HistoricalProof { proof: [] }
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
    policy,
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof: empty_proof(),
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
    policy,
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_wrong_aid,
      proof: empty_proof(),
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
    policy,
    Some(old),
    AppendRedeemer {
      raw_event: raw,
      cesr_aid: honest2_aid,
      proof: empty_proof(),
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
    policy,
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof: empty_proof(),
    },
    self_ref,
    burn_tx(1),
  )
}

test reject_submitter_chosen_proof_policy() fail {
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  s0_append.s0_append.spend(
    other_policy,
    Some(old),
    AppendRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof: empty_proof(),
    },
    self_ref,
    burn_tx(1),
  )
}

test staging_accepts_distinct_i_and_d() {
  let name = proof_token_name(rot_bytes, rot_aid)
  let tx = Transaction { ..placeholder, mint: from_asset(policy, name, 1) }
  s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: rot_bytes,
      cesr_aid: rot_aid,
      off_i: rot_off_i,
      off_d: rot_off_d,
    },
    policy,
    tx,
  )
}

test present_prior_rivals_cross_staging_and_append() {
  expect DecodeOk(ev1) = decode_establishment_event(rot_bytes)
  let rot2_aid = rival_digest(rot_bytes)
  let rot2 = splice_span(
    flip_byte(rot_bytes, rot_k_flip_at),
    rot_off_d,
    qb64_aid(rot2_aid),
  )
  expect DecodeOk(ev2) = decode_establishment_event(rot2)
  expect Some(key_one) = event_key_of(ev1)
  expect Some(key_two) = event_key_of(ev2)
  let name1 = proof_token_name(rot_bytes, rot_aid)
  let name2 = proof_token_name(rot2, rot2_aid)
  let staged1 = s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: rot_bytes,
      cesr_aid: rot_aid,
      off_i: rot_off_i,
      off_d: rot_off_d,
    },
    policy,
    Transaction { ..placeholder, mint: from_asset(policy, name1, 1) },
  )
  let staged2 = s0_staging_proof_token.s0_staging_proof_token.mint(
    StagingRedeemer {
      raw_event: rot2,
      cesr_aid: rot2_aid,
      off_i: rot_off_i,
      off_d: rot_off_d,
    },
    policy,
    Transaction { ..placeholder, mint: from_asset(policy, name2, 1) },
  )
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  let appended1 = s0_append.s0_append.spend(
    policy,
    Some(old),
    AppendRedeemer {
      raw_event: rot_bytes,
      cesr_aid: rot_aid,
      proof: empty_proof(),
    },
    self_ref,
    burn_tx_for(rot_bytes, rot_aid, 1),
  )
  expect Some(first) = apply_record_append(
    old,
    rot_bytes,
    rot_aid,
    policy,
    empty_proof(),
    burn_tx_for(rot_bytes, rot_aid, 1),
  )
  let proof_for_two = [
    Leaf { skip: 0, key: blake2b_256(key_one), value: blake2b_256(rot_aid) },
  ]
  let proof_for_one = [
    Leaf { skip: 0, key: blake2b_256(key_two), value: blake2b_256(rot2_aid) },
  ]
  let appended2 = s0_append.s0_append.spend(
    policy,
    Some(first),
    AppendRedeemer {
      raw_event: rot2,
      cesr_aid: rot2_aid,
      proof: HistoricalProof { proof: proof_for_two },
    },
    self_ref,
    burn_tx_for(rot2, rot2_aid, 1),
  )
  let both = mpf.insert(empty, key_one, rot_aid, [])
    |> mpf.insert(key_two, rot2_aid, proof_for_two)
  and {
    staged1,
    staged2,
    appended1,
    appended2,
    key_one != key_two,
    bind_parsed_event(
      rot_bytes,
      rot_aid,
      policy,
      burn_tx_for(rot_bytes, rot_aid, 1),
    ) != None,
    bind_parsed_event(rot2, rot2_aid, policy, burn_tx_for(rot2, rot2_aid, 1)) != None,
    mpf.has(both, key_one, rot_aid, proof_for_one),
    mpf.has(both, key_two, rot2_aid, proof_for_two),
  }
}

test submitter_chosen_proof_key_is_rejected() {
  let old = RecordState {
    event_root: root(empty),
    occupancy_root: zeros32,
    event_count: 0,
  }
  expect DecodeOk(ev) = decode_establishment_event(honest2_bytes)
  expect Some(derived) = event_key_of(ev)
  expect Some(got) = apply_record_append(
    old,
    honest2_bytes,
    honest2_aid,
    policy,
    empty_proof(),
    burn_tx(1),
  )
  got.event_root == root(mpf.insert(empty, derived, honest2_aid, []))
}

// ---------------------------------------------------------------------
// cursor
// ---------------------------------------------------------------------

test accept_s0_cursor() {
  let old = CursorState {
    keys_digest: ones32,
    keri_state: Established,
    grade: Unwitnessed,
    last_moved_slot: 1,
    registration_slot: 1,
  }
  s0_cursor.s0_cursor.spend(
    Some(old),
    CursorRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_aid,
      proof_policy: policy,
      proof: empty_proof(),
    },
    self_ref,
    burn_tx(10),
  )
}

test reject_s0_cursor_proof() fail {
  // R1 removes cursor authority from proof fields. The frozen S0 name
  // now rejects by breaking the proof-token/event binding instead.
  let old = CursorState {
    keys_digest: ones32,
    keri_state: Established,
    grade: Unwitnessed,
    last_moved_slot: 1,
    registration_slot: 1,
  }
  s0_cursor.s0_cursor.spend(
    Some(old),
    CursorRedeemer {
      raw_event: honest2_bytes,
      cesr_aid: honest2_wrong_aid,
      proof_policy: policy,
      proof: empty_proof(),
    },
    self_ref,
    burn_tx_for(honest2_bytes, honest2_wrong_aid, 10),
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
