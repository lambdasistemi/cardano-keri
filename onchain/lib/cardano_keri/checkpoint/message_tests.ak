//// Byte-identity + derivation + F10 verdict-parity tests for the Aiken
//// signed-message codec (#68 Slice 6). The `cbor.serialise` asserts mirror the
//// frozen `vectors.ak` message goldens produced by the Slice-2/3 Haskell
//// encoder (`Cardano.KERI.AID.Checkpoint.Message`), the `deriveAidAssetName`
//// asserts pin the frozen `CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x46 ‖ cesr_aid`
//// preimage, and the `validate_inception` / `advance_equalities` asserts mirror
//// the Slice-3 hspec `MessageSpec` verdicts one-for-one — including the
//// security-critical eq6 dual-threshold rule (a stolen spent-current quorum
//// maps to no committed next-key position and is rejected; a partial/reserve
//// rotation revealing a satisfiable subset is accepted). Field order
//// (12 icp / 17 adv), the `Constr 0` tags, and the eight checks are protocol
//// surface, frozen against the vectors + the Slice-3 semantics.

use aiken/cbor
use aiken/collection/list
use aiken/crypto
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, ThresholdIllFormed, ToadRange,
}
use cardano_keri/checkpoint/message.{
  AdvanceDomainMismatch, AdvanceInvalid, AdvanceMessage, AdvanceValid,
  DelegatedInceptionRejected, Dip, Drt, Eq1NetworkPolicyMismatch,
  Eq2AssetOrAidMismatch, Eq3OutRefMismatch, Eq4PriorMismatch,
  Eq5SequenceMismatch, Eq6CurrentQuorumUnsatisfied,
  Eq6PriorNextQuorumUnsatisfied, Eq7CreatedStateMismatch, Eq8CreatedIllFormed,
  Icp, InceptionAidWidth, InceptionAssetMismatch, InceptionDomainMismatch,
  InceptionIllFormed, InceptionInvalid, InceptionMessage, InceptionValid,
  RevealedSuccessorSigners, SpentCheckpoint, advance_domain, advance_equalities,
  checkpoint_asset_domain_tag, deriveAidAssetName, inception_domain,
  validate_inception,
}
use cardano_keri/checkpoint/threshold.{
  DuplicateKey, Unweighted, Weight, Weighted, evaluate,
}
use cardano_keri/checkpoint/vectors

// ---------------------------------------------------------
// Field fixtures (identical to the GenCheckpointVectors.hs / MessageSpec inputs)
// ---------------------------------------------------------

const k1: ByteArray =
  #"0101010101010101010101010101010101010101010101010101010101010101"

const k2: ByteArray =
  #"0202020202020202020202020202020202020202020202020202020202020202"

const policy: ByteArray =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const nk11: ByteArray =
  #"1111111111111111111111111111111111111111111111111111111111111111"

const nk22: ByteArray =
  #"2222222222222222222222222222222222222222222222222222222222222222"

const spent_txid: ByteArray =
  #"d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

// one-bit flip of byte 0 of the derivation golden's cesr_aid (0x00 -> 0x01)
const cesr_a_flipped: ByteArray =
  #"010102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

const zero32: ByteArray =
  #"0000000000000000000000000000000000000000000000000000000000000000"

const wrong_policy: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

const crossed_aid: ByteArray =
  #"5555555555555555555555555555555555555555555555555555555555555555"

// The derivation golden's fixed cesr_aid (0x00..0x1f), from vectors.ak.
fn cesr_a() -> ByteArray {
  vectors.golden_derivation_cesr_aid
}

fn aid_asset() -> ByteArray {
  deriveAidAssetName(cesr_a())
}

// ---------------------------------------------------------
// deriveAidAssetName: exact-byte goldens (cross-language pins)
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
      bytearray.concat(#"46", cesr_a()),
    ),
  )
}

test derivation_wrong_code_negative() {
  crypto.blake2b_256(
    bytearray.concat(
      checkpoint_asset_domain_tag,
      bytearray.concat(#"45", cesr_a()),
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

// ---------------------------------------------------------
// Inception fixture + byte identity + verdict parity
// ---------------------------------------------------------

fn valid_icp() -> InceptionMessage {
  InceptionMessage {
    domain: inception_domain,
    network_id: 1,
    checkpoint_policy_id: policy,
    aid_asset_name: aid_asset(),
    cesr_aid: cesr_a(),
    cur_keys: [k1],
    cur_threshold: Unweighted(1),
    next_keys: [k2],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    native_sn: 0,
  }
}

test inception_message_golden() {
  cbor.serialise(valid_icp()) == vectors.golden_inception_message
}

test inception_accepts_valid_icp() {
  validate_inception(Icp, valid_icp()) == InceptionValid
}

test inception_rejects_wrong_domain() {
  validate_inception(
    Icp,
    InceptionMessage { ..valid_icp(), domain: advance_domain },
  ) == InceptionInvalid(InceptionDomainMismatch)
}

test inception_rejects_dip() {
  validate_inception(Dip, valid_icp()) == InceptionInvalid(
    DelegatedInceptionRejected,
  )
}

test inception_rejects_drt() {
  validate_inception(Drt, valid_icp()) == InceptionInvalid(
    DelegatedInceptionRejected,
  )
}

test inception_rejects_substituted_asset() {
  validate_inception(
    Icp,
    InceptionMessage { ..valid_icp(), aid_asset_name: zero32 },
  ) == InceptionInvalid(InceptionAssetMismatch)
}

test inception_rejects_wrong_code_asset() {
  validate_inception(
    Icp,
    InceptionMessage {
      ..valid_icp(),
      aid_asset_name: vectors.negative_aid_asset_name_wrong_code,
    },
  ) == InceptionInvalid(InceptionAssetMismatch)
}

test inception_rejects_short_aid() {
  let short = bytearray.take(cesr_a(), 31)
  validate_inception(
    Icp,
    InceptionMessage {
      ..valid_icp(),
      cesr_aid: short,
      aid_asset_name: deriveAidAssetName(short),
    },
  ) == InceptionInvalid(InceptionAidWidth)
}

test inception_rejects_long_aid() {
  let long = bytearray.concat(cesr_a(), #"00")
  validate_inception(
    Icp,
    InceptionMessage {
      ..valid_icp(),
      cesr_aid: long,
      aid_asset_name: deriveAidAssetName(long),
    },
  ) == InceptionInvalid(InceptionAidWidth)
}

test inception_rejects_mutated_aid() {
  validate_inception(
    Icp,
    InceptionMessage { ..valid_icp(), cesr_aid: cesr_a_flipped },
  ) == InceptionInvalid(InceptionAssetMismatch)
}

test inception_rejects_nonzero_native_sn() {
  validate_inception(Icp, InceptionMessage { ..valid_icp(), native_sn: 1 }) == InceptionInvalid(
    message.InceptionNativeSnNonZero,
  )
}

test inception_rejects_ill_formed_toad() {
  validate_inception(Icp, InceptionMessage { ..valid_icp(), toad: 1 }) == InceptionInvalid(
    InceptionIllFormed(ToadRange),
  )
}

test inception_rejects_empty_next_keys() {
  validate_inception(Icp, InceptionMessage { ..valid_icp(), next_keys: [] }) == InceptionInvalid(
    InceptionIllFormed(datum.NextIllFormed(threshold.EmptyKeys)),
  )
}

// ---------------------------------------------------------
// Advance fixture (valid succession) + eq6 dual-threshold setup
// ---------------------------------------------------------

fn spent() -> SpentCheckpoint {
  SpentCheckpoint {
    network_id: 1,
    policy_id: policy,
    aid_asset_name: aid_asset(),
    txid: spent_txid,
    index: 1,
    cesr_aid: cesr_a(),
    next_keys: [nk11],
    next_threshold: Unweighted(1),
    seq: 0,
    native_sn: 0,
  }
}

fn valid_adv() -> AdvanceMessage {
  AdvanceMessage {
    domain: advance_domain,
    network_id: 1,
    checkpoint_policy_id: policy,
    aid_asset_name: aid_asset(),
    cesr_aid: cesr_a(),
    spent_txid,
    spent_index: 1,
    prior_seq: 0,
    prior_native_sn: 0,
    new_cur_keys: [nk11],
    new_cur_threshold: Unweighted(1),
    new_next_keys: [nk22],
    new_next_threshold: Unweighted(1),
    new_witnesses: [],
    new_toad: 0,
    seq_to: 1,
    native_sn_to: 1,
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

// The revealed successor key signs (its digest is in the evidence).
fn sigs_revealed() -> RevealedSuccessorSigners {
  RevealedSuccessorSigners([nk11])
}

// The attacker holds the full SPENT-CURRENT quorum — and nothing else.
fn sigs_stolen_current() -> RevealedSuccessorSigners {
  RevealedSuccessorSigners([k1, k2])
}

test advance_message_golden() {
  cbor.serialise(valid_adv()) == vectors.golden_advance_message
}

test advance_valid_succession() {
  advance_equalities(spent(), valid_adv(), created_valid(), sigs_revealed()) == AdvanceValid
}

test advance_wrong_domain() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), domain: inception_domain },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(AdvanceDomainMismatch)
}

// eq6 — the parent #21 pre-rotation invariant (security-critical).
fn positions_of(
  keyset: List<ByteArray>,
  controlled: List<ByteArray>,
) -> List<Int> {
  list.indexed_foldr(
    keyset,
    [],
    fn(i, k, acc) {
      if list.has(controlled, k) {
        [i, ..acc]
      } else {
        acc
      }
    },
  )
}

test stolen_quorum_satisfies_spent_current() {
  evaluate(Unweighted(2), 2, positions_of([k1, k2], [k1, k2])) == True
}

test stolen_quorum_maps_to_no_committed_next_position() {
  evaluate(Unweighted(1), 1, positions_of([nk11], [k1, k2])) == False
}

test advance_stolen_current_quorum_honest_message_rejected() {
  advance_equalities(
    spent(),
    valid_adv(),
    created_valid(),
    sigs_stolen_current(),
  ) == AdvanceInvalid(Eq6CurrentQuorumUnsatisfied)
}

test advance_stolen_current_quorum_crafted_message_rejected() {
  // The attacker reveals THEIR OWN keys as the successor set and satisfies
  // their own threshold, but none of their keys was pre-committed, so the
  // pre-rotation gate rejects.
  advance_equalities(
    spent(),
    AdvanceMessage {
      ..valid_adv(),
      new_cur_keys: [k1, k2],
      new_cur_threshold: Unweighted(2),
    },
    CheckpointDatumV1 {
      ..created_valid(),
      cur_keys: [k1, k2],
      cur_threshold: Unweighted(2),
    },
    sigs_stolen_current(),
  ) == AdvanceInvalid(Eq6PriorNextQuorumUnsatisfied)
}

test advance_substituted_successor_set_rejected() {
  let sub = #"9999999999999999999999999999999999999999999999999999999999999999"
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), new_cur_keys: [sub] },
    CheckpointDatumV1 { ..created_valid(), cur_keys: [sub] },
    RevealedSuccessorSigners([sub]),
  ) == AdvanceInvalid(Eq6PriorNextQuorumUnsatisfied)
}

// eq5 — sequence advance.
test advance_bad_seq_to() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), seq_to: 5 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq5SequenceMismatch)
}

test advance_non_increasing_native_sn() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), native_sn_to: 0 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq5SequenceMismatch)
}

// eq4 — the message binds the exact prior projection state.
test advance_wrong_prior_seq() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), prior_seq: 3 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq4PriorMismatch)
}

test advance_wrong_prior_native_sn() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), prior_native_sn: 3 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq4PriorMismatch)
}

// eq2 — AID / asset binding.
test advance_crossed_cesr_aid() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), cesr_aid: crossed_aid },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq2AssetOrAidMismatch)
}

test advance_cross_asset_name() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), aid_asset_name: zero32 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq2AssetOrAidMismatch)
}

// eq1 — deployment binding.
test advance_cross_network_id() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), network_id: 0 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq1NetworkPolicyMismatch)
}

test advance_cross_policy_id() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), checkpoint_policy_id: wrong_policy },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq1NetworkPolicyMismatch)
}

// eq3 — exact spent TxOutRef.
test advance_wrong_spent_txid() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), spent_txid: zero32 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq3OutRefMismatch)
}

test advance_wrong_spent_index() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), spent_index: 2 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq3OutRefMismatch)
}

// eq7 — the created datum equals the message's new-state fields.
test advance_created_disagrees_on_seq() {
  advance_equalities(
    spent(),
    valid_adv(),
    CheckpointDatumV1 { ..created_valid(), seq: 9 },
    sigs_revealed(),
  ) == AdvanceInvalid(Eq7CreatedStateMismatch)
}

test advance_substituted_new_next_keys() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), new_next_keys: [zero32] },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq7CreatedStateMismatch)
}

// eq8 — nothing ill-formed can be written.
test advance_ill_formed_toad_rejected() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), new_toad: 1 },
    CheckpointDatumV1 { ..created_valid(), toad: 1 },
    sigs_revealed(),
  ) == AdvanceInvalid(Eq8CreatedIllFormed(ToadRange))
}

test advance_duplicated_successor_key_rejected() {
  advance_equalities(
    spent(),
    AdvanceMessage {
      ..valid_adv(),
      new_cur_keys: [nk11, nk11],
      new_cur_threshold: Unweighted(2),
    },
    CheckpointDatumV1 {
      ..created_valid(),
      cur_keys: [nk11, nk11],
      cur_threshold: Unweighted(2),
    },
    sigs_revealed(),
  ) == AdvanceInvalid(Eq8CreatedIllFormed(ThresholdIllFormed(DuplicateKey)))
}

// ---------------------------------------------------------
// Partial (reserve) rotation — the KERI dual-threshold rule on the GLEIF
// production Root shape: 7 committed digests at nt = [[1/3 x7]], revealing
// indices {0, 5, 6} with a restated kt = [[1/3 x3]], re-committing the 4
// unexposed reserves plus 3 fresh digests. Verified against the live Root
// KEL (icp -> rot s=1).
// ---------------------------------------------------------

const rn0: ByteArray =
  #"3030303030303030303030303030303030303030303030303030303030303030"

const rn1: ByteArray =
  #"3131313131313131313131313131313131313131313131313131313131313131"

const rn2: ByteArray =
  #"3232323232323232323232323232323232323232323232323232323232323232"

const rn3: ByteArray =
  #"3333333333333333333333333333333333333333333333333333333333333333"

const rn4: ByteArray =
  #"3434343434343434343434343434343434343434343434343434343434343434"

const rn5: ByteArray =
  #"3535353535353535353535353535353535353535353535353535353535353535"

const rn6: ByteArray =
  #"3636363636363636363636363636363636363636363636363636363636363636"

const rf1: ByteArray =
  #"7171717171717171717171717171717171717171717171717171717171717171"

const rf2: ByteArray =
  #"7272727272727272727272727272727272727272727272727272727272727272"

const rf3: ByteArray =
  #"7373737373737373737373737373737373737373737373737373737373737373"

const aug: ByteArray =
  #"7777777777777777777777777777777777777777777777777777777777777777"

fn third(n: Int) -> threshold.Threshold {
  Weighted([list.repeat(Weight { num: 1, den: 3 }, n)])
}

fn reserve_spent() -> SpentCheckpoint {
  SpentCheckpoint {
    ..spent(),
    next_keys: [rn0, rn1, rn2, rn3, rn4, rn5, rn6],
    next_threshold: third(7),
  }
}

fn reserve_adv() -> AdvanceMessage {
  AdvanceMessage {
    ..valid_adv(),
    new_cur_keys: [rn0, rn5, rn6],
    new_cur_threshold: third(3),
    new_next_keys: [rn1, rn2, rn3, rn4, rf1, rf2, rf3],
    new_next_threshold: third(7),
  }
}

fn reserve_created() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    ..created_valid(),
    cur_keys: [rn0, rn5, rn6],
    cur_threshold: third(3),
    next_keys: [rn1, rn2, rn3, rn4, rf1, rf2, rf3],
    next_threshold: third(7),
  }
}

test advance_reserve_message_golden() {
  cbor.serialise(reserve_adv()) == vectors.golden_advance_reserve_message
}

test advance_reserve_rotation_accepted() {
  advance_equalities(
    reserve_spent(),
    reserve_adv(),
    reserve_created(),
    RevealedSuccessorSigners([rn0, rn5, rn6]),
  ) == AdvanceValid
}

test advance_reserve_insufficient_reveal_rejected() {
  // Two committed keys + one augmented fresh key satisfy the rotation's own
  // lenient threshold, but only 2/3 of the committed weight signs: the
  // pre-rotation gate rejects.
  advance_equalities(
    reserve_spent(),
    AdvanceMessage {
      ..reserve_adv(),
      new_cur_keys: [rn0, rn5, aug],
      new_cur_threshold: Unweighted(1),
    },
    CheckpointDatumV1 {
      ..reserve_created(),
      cur_keys: [rn0, rn5, aug],
      cur_threshold: Unweighted(1),
    },
    RevealedSuccessorSigners([rn0, aug]),
  ) == AdvanceInvalid(Eq6PriorNextQuorumUnsatisfied)
}

test advance_reserve_augmented_key_accepted() {
  // All three committed positions sign; the augmented (never-committed)
  // key's signature counts only toward the current threshold and the
  // advance passes.
  advance_equalities(
    reserve_spent(),
    AdvanceMessage {
      ..reserve_adv(),
      new_cur_keys: [rn0, rn5, rn6, aug],
      new_cur_threshold: Unweighted(3),
    },
    CheckpointDatumV1 {
      ..reserve_created(),
      cur_keys: [rn0, rn5, rn6, aug],
      cur_threshold: Unweighted(3),
    },
    RevealedSuccessorSigners([aug, rn0, rn5, rn6]),
  ) == AdvanceValid
}
