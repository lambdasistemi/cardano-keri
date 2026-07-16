//// Byte-identity + derivation + F10 verdict-parity tests for the Aiken
//// signed-message codec (#68 Slice 6). The `cbor.serialise` asserts mirror the
//// frozen `vectors.ak` message goldens produced by the Slice-2/3 Haskell
//// encoder (`Cardano.KERI.AID.Checkpoint.Message`), the `deriveAidAssetName`
//// asserts pin the frozen `CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x46 ‖ cesr_aid`
//// preimage, and the `validate_inception` / `advance_equalities` asserts mirror
//// the Slice-3 hspec `MessageSpec` verdicts one-for-one — including the
//// security-critical eq6 pre-rotation invariant (a stolen spent-current quorum
//// maps to no revealed-successor position and is rejected). Field order
//// (11 icp / 17 adv), the `Constr 0` tags, and the seven equalities are
//// protocol surface, frozen against the vectors + the Slice-3 semantics.

use aiken/cbor
use aiken/collection/list
use aiken/crypto
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, NextCommitment, keyset_commit,
}
use cardano_keri/checkpoint/message.{
  AdvanceDomainMismatch, AdvanceInvalid, AdvanceMessage, AdvanceValid,
  DelegatedInceptionRejected, Dip, Drt, Eq1NetworkPolicyMismatch,
  Eq2AssetOrAidMismatch, Eq3OutRefMismatch,
  Eq4PriorMismatch, Eq5SequenceMismatch, Eq6SuccessorQuorumUnsatisfied,
  Eq7CreatedStateMismatch, Icp, InceptionAidWidth, InceptionAssetMismatch,
  InceptionDomainMismatch, InceptionInvalid, InceptionMessage, InceptionValid,
  RevealedSuccessorSigners, SpentCheckpoint, advance_domain, advance_equalities,
  checkpoint_asset_domain_tag, deriveAidAssetName, inception_domain,
  validate_inception,
}
use cardano_keri/checkpoint/threshold.{Unweighted, evaluate}
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

const key99: ByteArray =
  #"9999999999999999999999999999999999999999999999999999999999999999"

const key55: ByteArray =
  #"5555555555555555555555555555555555555555555555555555555555555555"

const policy_ee: ByteArray =
  #"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

// ---------------------------------------------------------
// Fixture builders (digests use blake2b_256 builtins, so these are fns not
// consts; each mirrors the matching MessageSpec Haskell fixture)
// ---------------------------------------------------------

// spent.next_digest == keyset_commit over the REVEALED successor set [nk11].
fn spent_next() -> ByteArray {
  keyset_commit(
    NextCommitment { next_keys: [nk11], next_threshold: Unweighted(1) },
  )
}

fn new_next() -> ByteArray {
  keyset_commit(
    NextCommitment { next_keys: [nk22], next_threshold: Unweighted(1) },
  )
}

fn valid_icp() -> InceptionMessage {
  InceptionMessage {
    domain: inception_domain,
    network_id: 1,
    checkpoint_policy_id: policy,
    aid_asset_name: deriveAidAssetName(vectors.golden_derivation_cesr_aid),
    cesr_aid: vectors.golden_derivation_cesr_aid,
    cur_keys: [k1],
    cur_threshold: Unweighted(1),
    next_digest: keyset_commit(
      NextCommitment { next_keys: [k2], next_threshold: Unweighted(1) },
    ),
    witnesses: [],
    toad: 0,
    native_sn: 0,
  }
}

fn valid_adv() -> AdvanceMessage {
  AdvanceMessage {
    domain: advance_domain,
    network_id: 1,
    checkpoint_policy_id: policy,
    aid_asset_name: deriveAidAssetName(vectors.golden_derivation_cesr_aid),
    cesr_aid: vectors.golden_derivation_cesr_aid,
    spent_txid,
    spent_index: 1,
    prior_commit: spent_next(),
    prior_seq: 0,
    prior_native_sn: 0,
    new_cur_keys: [nk11],
    new_cur_threshold: Unweighted(1),
    new_next_digest: new_next(),
    new_witnesses: [],
    new_toad: 0,
    seq_to: 1,
    native_sn_to: 1,
  }
}

// The spent checkpoint context validAdv is validated against.
fn spent() -> SpentCheckpoint {
  SpentCheckpoint {
    network_id: 1,
    policy_id: policy,
    aid_asset_name: deriveAidAssetName(vectors.golden_derivation_cesr_aid),
    txid: spent_txid,
    index: 1,
    cesr_aid: vectors.golden_derivation_cesr_aid,
    next_digest: spent_next(),
    seq: 0,
    native_sn: 0,
  }
}

// The created datum matching validAdv's new-state fields (eq7 baseline).
fn created_valid() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: vectors.golden_derivation_cesr_aid,
    cur_keys: [nk11],
    cur_threshold: Unweighted(1),
    next_digest: new_next(),
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

// The attacker holds the full SPENT-CURRENT quorum [k1, k2] — and nothing else.
fn sigs_stolen_current() -> RevealedSuccessorSigners {
  RevealedSuccessorSigners([k1, k2])
}

// Positions in `keyset` whose digest is among the `controlled` evidence — the
// same key-based mapping eq6 performs; used here to demonstrate that one
// attacker evidence satisfies the spent-current threshold yet fails the
// revealed-successor threshold.
fn positions_in(
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

// ---------------------------------------------------------
// deriveAidAssetName — golden + sensitivity negatives
// ---------------------------------------------------------

test derive_aid_asset_name() {
  deriveAidAssetName(vectors.golden_derivation_cesr_aid) == vectors.golden_aid_asset_name
}

// Wrong V1 derivation code 0x45 (not 0x46) yields a different digest.
test derive_wrong_code() {
  crypto.blake2b_256(
    bytearray.concat(
      checkpoint_asset_domain_tag,
      bytearray.concat(#"45", vectors.golden_derivation_cesr_aid),
    ),
  ) == vectors.negative_aid_asset_name_wrong_code
}

// A one-bit-flipped AID yields a different digest.
test derive_mutated_aid() {
  deriveAidAssetName(cesr_a_flipped) == vectors.negative_aid_asset_name_mutated_aid
}

// ---------------------------------------------------------
// InceptionMessage byte-identity
// ---------------------------------------------------------

test inception_message() {
  cbor.serialise(valid_icp()) == vectors.golden_inception_message
}

// ---------------------------------------------------------
// AdvanceMessage byte-identity
// ---------------------------------------------------------

test advance_message() {
  cbor.serialise(valid_adv()) == vectors.golden_advance_message
}

// ---------------------------------------------------------
// validate_inception (exact rejections, mirroring MessageSpec)
// ---------------------------------------------------------

test inception_accepts_valid() {
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

test inception_rejects_31_byte_aid() {
  let short = bytearray.take(vectors.golden_derivation_cesr_aid, 31)
  validate_inception(
    Icp,
    InceptionMessage {
      ..valid_icp(),
      cesr_aid: short,
      aid_asset_name: deriveAidAssetName(short),
    },
  ) == InceptionInvalid(InceptionAidWidth)
}

test inception_rejects_33_byte_aid() {
  let long = bytearray.concat(vectors.golden_derivation_cesr_aid, #"00")
  validate_inception(
    Icp,
    InceptionMessage {
      ..valid_icp(),
      cesr_aid: long,
      aid_asset_name: deriveAidAssetName(long),
    },
  ) == InceptionInvalid(InceptionAidWidth)
}

test inception_rejects_mutated_aid_original_asset() {
  validate_inception(
    Icp,
    InceptionMessage { ..valid_icp(), cesr_aid: cesr_a_flipped },
  ) == InceptionInvalid(InceptionAssetMismatch)
}

// ---------------------------------------------------------
// advance_equalities — the seven F10 equalities (exact rejections)
// ---------------------------------------------------------

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

// eq6 — the parent #21 pre-rotation invariant (security-critical). The SAME
// attacker evidence satisfies the spent-current quorum but maps to no successor
// position, so the advance is rejected.
test stolen_quorum_satisfies_spent_current() {
  evaluate(Unweighted(2), 2, positions_in([k1, k2], [k1, k2])) == True
}

test stolen_quorum_fails_successor() {
  evaluate(Unweighted(1), 1, positions_in([nk11], [k1, k2])) == False
}

test advance_stolen_current_quorum_rejected() {
  advance_equalities(
    spent(),
    valid_adv(),
    created_valid(),
    sigs_stolen_current(),
  ) == AdvanceInvalid(Eq6SuccessorQuorumUnsatisfied)
}

test advance_duplicate_successor_key_rejected() {
  let dup_key =
    #"4444444444444444444444444444444444444444444444444444444444444444"
  let dup_commit = keyset_commit(
    NextCommitment {
      next_keys: [dup_key, dup_key],
      next_threshold: Unweighted(2),
    },
  )
  advance_equalities(
    SpentCheckpoint { ..spent(), next_digest: dup_commit },
    AdvanceMessage {
      ..valid_adv(),
      prior_commit: dup_commit,
      new_cur_keys: [dup_key, dup_key],
      new_cur_threshold: Unweighted(2),
    },
    CheckpointDatumV1 {
      ..created_valid(),
      cur_keys: [dup_key, dup_key],
      cur_threshold: Unweighted(2),
    },
    RevealedSuccessorSigners([dup_key]),
  ) == AdvanceInvalid(Eq6SuccessorQuorumUnsatisfied)
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

// eq4 — reveal binds the successor to spent.next_digest.
test advance_wrong_prior_commit() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), prior_commit: zero32 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq4PriorMismatch)
}

test advance_substituted_successor_keys() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), new_cur_keys: [key99] },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq4PriorMismatch)
}

// eq2 — AID / asset binding.
test advance_crossed_cesr_aid() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), cesr_aid: key55 },
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

test advance_cross_policy() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), checkpoint_policy_id: policy_ee },
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
test advance_created_seq_mismatch() {
  advance_equalities(
    spent(),
    valid_adv(),
    CheckpointDatumV1 { ..created_valid(), seq: 9 },
    sigs_revealed(),
  ) == AdvanceInvalid(Eq7CreatedStateMismatch)
}

test advance_substituted_new_next() {
  advance_equalities(
    spent(),
    AdvanceMessage { ..valid_adv(), new_next_digest: zero32 },
    created_valid(),
    sigs_revealed(),
  ) == AdvanceInvalid(Eq7CreatedStateMismatch)
}
