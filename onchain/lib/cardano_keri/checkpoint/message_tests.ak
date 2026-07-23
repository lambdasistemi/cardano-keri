//// Locator asset-name + pure advance transition tests (#115 R3).
////
//// Mirrors the Haskell `MessageSpec`: `deriveAidAssetName` goldens and
//// `advance_equalities` over OLD/NEW/wit_cut/wit_add/revealed signers.
//// AdvanceMessage CBOR goldens are deleted with the message surface.

use aiken/collection/list
use aiken/crypto
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, ThresholdIllFormed, ToadRange,
}
use cardano_keri/checkpoint/message.{
  AdvanceInvalid, AdvanceValid, Eq2AssetOrAidMismatch, Eq5SequenceMismatch,
  Eq6CurrentQuorumUnsatisfied, Eq6PriorNextQuorumUnsatisfied,
  Eq7CreatedStateMismatch, Eq8CreatedIllFormed, EqW1CutInvalid, EqW2AddInvalid,
  RevealedSuccessorSigners, SpentCheckpoint, advance_equalities,
  checkpoint_asset_domain_tag, deriveAidAssetName, next_key_digest, qb64_aid,
  qb64_verkey,
}
use cardano_keri/checkpoint/threshold.{
  DuplicateKey, Threshold, Unweighted, Weight, Weighted, evaluate,
}
use cardano_keri/checkpoint/vectors as vectors

const policy: ByteArray =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const nk11: ByteArray =
  #"1111111111111111111111111111111111111111111111111111111111111111"

const nk22: ByteArray =
  #"2222222222222222222222222222222222222222222222222222222222222222"

const spent_txid: ByteArray =
  #"d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

const cesr_a_flipped: ByteArray =
  #"010102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

const zero32: ByteArray =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const crossed_aid: ByteArray =
  #"5555555555555555555555555555555555555555555555555555555555555555"

const w1: ByteArray =
  #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"

const w2: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

const w3: ByteArray =
  #"b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3"

const w4: ByteArray =
  #"b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4"

const k1: ByteArray =
  #"0101010101010101010101010101010101010101010101010101010101010101"

const k2: ByteArray =
  #"0202020202020202020202020202020202020202020202020202020202020202"

fn cesr_a() -> ByteArray {
  vectors.golden_derivation_cesr_aid
}

fn aid_asset() -> ByteArray {
  deriveAidAssetName(cesr_a())
}

// ---------------------------------------------------------
// deriveAidAssetName + qb64 goldens
// ---------------------------------------------------------

test domain_tag_is_32_bytes() {
  bytearray.length(checkpoint_asset_domain_tag) == 32
}

test derivation_golden() {
  aid_asset() == vectors.golden_aid_asset_name
}

test derivation_definition() {
  aid_asset() == crypto.blake2b_256(
    bytearray.concat(
      checkpoint_asset_domain_tag,
      bytearray.concat(#"45", cesr_a()),
    ),
  )
}

test derivation_wrong_code_negative() {
  crypto.blake2b_256(
    bytearray.concat(
      checkpoint_asset_domain_tag,
      bytearray.concat(#"46", cesr_a()),
    ),
  ) == vectors.negative_aid_asset_name_wrong_code
}

test derivation_wrong_code_differs() {
  vectors.negative_aid_asset_name_wrong_code != vectors.golden_aid_asset_name
}

test derivation_mutated_aid_negative() {
  deriveAidAssetName(cesr_a_flipped) == vectors.negative_aid_asset_name_mutated_aid
}

test derivation_mutated_aid_differs() {
  vectors.negative_aid_asset_name_mutated_aid != vectors.golden_aid_asset_name
}

test qb64_aid_golden_zero() {
  qb64_aid(zero32) == "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}

test qb64_aid_golden_cesr_a() {
  qb64_aid(cesr_a()) == "EAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"
}

test qb64_aid_is_e_code_44_bytes() {
  let a = qb64_aid(cesr_a())
  bytearray.length(a) == 44 && bytearray.take(a, 1) == #"45"
}

test qb64_aid_shares_verkey_payload_differs_by_code() {
  bytearray.drop(qb64_aid(cesr_a()), 1) == bytearray.drop(
    qb64_verkey(cesr_a()),
    1,
  ) && qb64_aid(cesr_a()) != qb64_verkey(cesr_a())
}

// ---------------------------------------------------------
// Advance transition fixtures
// ---------------------------------------------------------

fn spent() -> SpentCheckpoint {
  SpentCheckpoint {
    network_id: 1,
    policy_id: policy,
    aid_asset_name: aid_asset(),
    txid: spent_txid,
    index: 1,
    cesr_aid: cesr_a(),
    witnesses: [],
    next_keys: [next_key_digest(nk11)],
    next_threshold: Unweighted(1),
    seq: 0,
    native_sn: 0,
  }
}

fn created_valid() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: cesr_a(),
    cur_keys: [nk11],
    cur_threshold: Unweighted(1),
    next_keys: [nk22],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 1,
    native_sn: 1,
  }
}

fn sigs_revealed() -> RevealedSuccessorSigners {
  RevealedSuccessorSigners([nk11])
}

fn sigs_stolen() -> RevealedSuccessorSigners {
  RevealedSuccessorSigners([k1, k2])
}

fn witnessed_spent() -> SpentCheckpoint {
  SpentCheckpoint { ..spent(), witnesses: [w1, w2, w3] }
}

fn witnessed_created() -> CheckpointDatumV1 {
  CheckpointDatumV1 { ..created_valid(), witnesses: [w2, w3, w4], toad: 2 }
}

fn witnessed_keep_created() -> CheckpointDatumV1 {
  CheckpointDatumV1 { ..created_valid(), witnesses: [w1, w2, w3], toad: 2 }
}

fn witnessed_downgrade_created() -> CheckpointDatumV1 {
  CheckpointDatumV1 { ..created_valid(), witnesses: [], toad: 0 }
}

// ---------------------------------------------------------
// advance_equalities positives and dual-threshold negatives
// ---------------------------------------------------------

test advance_valid_succession() {
  advance_equalities(spent(), created_valid(), [], [], sigs_revealed()) == AdvanceValid
}

test advance_stolen_current_quorum_honest_rejected() {
  advance_equalities(spent(), created_valid(), [], [], sigs_stolen()) == AdvanceInvalid(
    Eq6CurrentQuorumUnsatisfied,
  )
}

test advance_stolen_current_quorum_crafted_rejected() {
  let atk = CheckpointDatumV1 {
    ..created_valid(),
    cur_keys: [k1, k2],
    cur_threshold: Unweighted(2),
  }
  advance_equalities(spent(), atk, [], [], sigs_stolen()) == AdvanceInvalid(
    Eq6PriorNextQuorumUnsatisfied,
  )
}

test advance_substituted_successor_set_rejected() {
  let sub = #"9999999999999999999999999999999999999999999999999999999999999999"
  let created = CheckpointDatumV1 { ..created_valid(), cur_keys: [sub] }
  advance_equalities(spent(), created, [], [], RevealedSuccessorSigners([sub])) == AdvanceInvalid(
    Eq6PriorNextQuorumUnsatisfied,
  )
}

test advance_bad_seq() {
  advance_equalities(
    spent(),
    CheckpointDatumV1 { ..created_valid(), seq: 5 },
    [],
    [],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq5SequenceMismatch)
}

test advance_non_increasing_native_sn() {
  advance_equalities(
    spent(),
    CheckpointDatumV1 { ..created_valid(), native_sn: 0 },
    [],
    [],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq5SequenceMismatch)
}

test advance_crossed_cesr_aid() {
  advance_equalities(
    spent(),
    CheckpointDatumV1 { ..created_valid(), cesr_aid: crossed_aid },
    [],
    [],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq2AssetOrAidMismatch)
}

test advance_broken_spent_locator() {
  advance_equalities(
    SpentCheckpoint { ..spent(), aid_asset_name: zero32 },
    created_valid(),
    [],
    [],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq2AssetOrAidMismatch)
}

test advance_ill_formed_toad_rejected() {
  advance_equalities(
    spent(),
    CheckpointDatumV1 { ..created_valid(), toad: 1 },
    [],
    [],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq8CreatedIllFormed(ToadRange))
}

test advance_duplicated_successor_key_rejected() {
  let created = CheckpointDatumV1 {
    ..created_valid(),
    cur_keys: [nk11, nk11],
    cur_threshold: Unweighted(2),
  }
  advance_equalities(spent(), created, [], [], RevealedSuccessorSigners([nk11])) == AdvanceInvalid(
    Eq8CreatedIllFormed(ThresholdIllFormed(DuplicateKey)),
  )
}

// ---------------------------------------------------------
// W1-W3 witness-delta coverage
// ---------------------------------------------------------

test advance_witnessed_cut_add_accepted() {
  advance_equalities(
    witnessed_spent(),
    witnessed_created(),
    [w1],
    [w4],
    sigs_revealed(),
  ) == AdvanceValid
}

test advance_witnessed_keep_accepted() {
  advance_equalities(
    witnessed_spent(),
    witnessed_keep_created(),
    [],
    [],
    sigs_revealed(),
  ) == AdvanceValid
}

test advance_witnessed_downgrade_accepted() {
  advance_equalities(
    witnessed_spent(),
    witnessed_downgrade_created(),
    [w1, w2, w3],
    [],
    sigs_revealed(),
  ) == AdvanceValid
}

test advance_dup_cut_rejected() {
  advance_equalities(
    witnessed_spent(),
    witnessed_created(),
    [w1, w1],
    [w4],
    sigs_revealed(),
  ) == AdvanceInvalid(EqW1CutInvalid)
}

test advance_cut_non_member_rejected() {
  advance_equalities(
    witnessed_spent(),
    witnessed_created(),
    [w4],
    [w4],
    sigs_revealed(),
  ) == AdvanceInvalid(EqW1CutInvalid)
}

test advance_dup_add_rejected() {
  advance_equalities(
    witnessed_spent(),
    witnessed_created(),
    [w1],
    [w4, w4],
    sigs_revealed(),
  ) == AdvanceInvalid(EqW2AddInvalid)
}

test advance_add_present_rejected() {
  advance_equalities(
    witnessed_spent(),
    witnessed_created(),
    [w1],
    [w2],
    sigs_revealed(),
  ) == AdvanceInvalid(EqW2AddInvalid)
}

test advance_cut_add_overlap_rejected() {
  advance_equalities(
    witnessed_spent(),
    witnessed_created(),
    [w1],
    [w1],
    sigs_revealed(),
  ) == AdvanceInvalid(EqW2AddInvalid)
}

test advance_derived_set_mismatch_rejected() {
  advance_equalities(
    witnessed_spent(),
    CheckpointDatumV1 { ..witnessed_created(), witnesses: [w1, w2, w3] },
    [w1],
    [w4],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq7CreatedStateMismatch)
}

test advance_wrong_survivor_order_rejected() {
  advance_equalities(
    witnessed_spent(),
    CheckpointDatumV1 { ..witnessed_created(), witnesses: [w4, w2, w3] },
    [w1],
    [w4],
    sigs_revealed(),
  ) == AdvanceInvalid(Eq7CreatedStateMismatch)
}

// ---------------------------------------------------------
// Partial (reserve) rotation — GLEIF-shaped dual threshold
// ---------------------------------------------------------

fn rn(i: Int) -> ByteArray {
  // 0x30+i repeated 32 times — mirrors MessageSpec's rn helper.
  when i is {
    0 -> #"3030303030303030303030303030303030303030303030303030303030303030"
    1 -> #"3131313131313131313131313131313131313131313131313131313131313131"
    2 -> #"3232323232323232323232323232323232323232323232323232323232323232"
    3 -> #"3333333333333333333333333333333333333333333333333333333333333333"
    4 -> #"3434343434343434343434343434343434343434343434343434343434343434"
    5 -> #"3535353535353535353535353535353535353535353535353535353535353535"
    6 -> #"3636363636363636363636363636363636363636363636363636363636363636"
    _ -> zero32
  }
}

fn third(n: Int) -> Threshold {
  Weighted([list.repeat(Weight { num: 1, den: 3 }, n)])
}

fn reserve_spent() -> SpentCheckpoint {
  SpentCheckpoint {
    ..spent(),
    next_keys: [
      next_key_digest(rn(0)),
      next_key_digest(rn(1)),
      next_key_digest(rn(2)),
      next_key_digest(rn(3)),
      next_key_digest(rn(4)),
      next_key_digest(rn(5)),
      next_key_digest(rn(6)),
    ],
    next_threshold: third(7),
  }
}

fn reserve_created() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    ..created_valid(),
    cur_keys: [rn(0), rn(5), rn(6)],
    cur_threshold: third(3),
    next_keys: [
      next_key_digest(rn(1)),
      next_key_digest(rn(2)),
      next_key_digest(rn(3)),
      next_key_digest(rn(4)),
      #"7171717171717171717171717171717171717171717171717171717171717171",
      #"7272727272727272727272727272727272727272727272727272727272727272",
      #"7373737373737373737373737373737373737373737373737373737373737373",
    ],
    next_threshold: third(7),
  }
}

test advance_reserve_rotation_accepted() {
  advance_equalities(
    reserve_spent(),
    reserve_created(),
    [],
    [],
    RevealedSuccessorSigners([rn(0), rn(5), rn(6)]),
  ) == AdvanceValid
}

test advance_reserve_insufficient_reveal_rejected() {
  let aug = #"7777777777777777777777777777777777777777777777777777777777777777"
  let created = CheckpointDatumV1 {
    ..reserve_created(),
    cur_keys: [rn(0), rn(5), aug],
    cur_threshold: Unweighted(1),
  }
  advance_equalities(
    reserve_spent(),
    created,
    [],
    [],
    RevealedSuccessorSigners([rn(0), aug]),
  ) == AdvanceInvalid(Eq6PriorNextQuorumUnsatisfied)
}

// Sanity: stolen current quorum satisfies the spent-current threshold shape
// but maps to no committed next-key position.
test stolen_quorum_satisfies_spent_current() {
  evaluate(Unweighted(2), 2, [0, 1])
}

test stolen_quorum_maps_to_no_committed_next_position() {
  !evaluate(Unweighted(1), 1, [])
}
