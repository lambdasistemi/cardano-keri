//// Byte-identity tests for the Aiken `CheckpointDatumV1` + `NextCommitment`
//// codec (#68 Slice 6). Each `cbor.serialise` assert mirrors a frozen
//// `vectors.ak` golden produced by the Slice-2/3 Haskell encoder
//// (`Cardano.KERI.AID.Checkpoint.Datum`) — this file is one half of the
//// cross-language parity proof. Field order (8 datum fields), the `V1`
//// wrapper (Constr 0 wrapping the inner Constr 0), and the `NextCommitment`
//// preimage are protocol surface; they change only by minting a new version
//// tag. `keyset_commit` reproduces the Haskell `blake2b_256`-of-canonical-CBOR
//// commitment.

use aiken/cbor
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, NextCommitment, V1, keyset_commit,
}
use cardano_keri/checkpoint/threshold.{Unweighted, Weight, Weighted}
use cardano_keri/checkpoint/vectors

// ---------------------------------------------------------
// Field fixtures (identical to the GenCheckpointVectors.hs inputs)
// ---------------------------------------------------------

const cesr_datum: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const k1: ByteArray =
  #"0101010101010101010101010101010101010101010101010101010101010101"

const k2: ByteArray =
  #"0202020202020202020202020202020202020202020202020202020202020202"

const k3: ByteArray =
  #"0303030303030303030303030303030303030303030303030303030303030303"

const next_const: ByteArray =
  #"0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a"

const w1: ByteArray =
  #"b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1"

const w2: ByteArray =
  #"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"

// ---------------------------------------------------------
// Datum byte-identity: cbor.serialise(V1(record)) == vectors.const
// ---------------------------------------------------------

test datum_1of1() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1],
        cur_threshold: Unweighted(1),
        next_digest: next_const,
        witnesses: [],
        toad: 0,
        seq: 0,
        native_sn: 0,
      },
    ),
  ) == vectors.golden_datum_1of1
}

test datum_integer_m_of_n() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2, k3],
        cur_threshold: Unweighted(2),
        next_digest: next_const,
        witnesses: [],
        toad: 0,
        seq: 5,
        native_sn: 7,
      },
    ),
  ) == vectors.golden_datum_integer_m_of_n
}

test datum_weighted() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2],
        cur_threshold: Weighted(
          [[Weight { num: 1, den: 2 }, Weight { num: 1, den: 2 }]],
        ),
        next_digest: next_const,
        witnesses: [],
        toad: 0,
        seq: 2,
        native_sn: 4,
      },
    ),
  ) == vectors.golden_datum_weighted
}

test datum_multi_clause() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1, k2],
        cur_threshold: Weighted(
          [[Weight { num: 1, den: 1 }], [Weight { num: 1, den: 1 }]],
        ),
        next_digest: next_const,
        witnesses: [],
        toad: 0,
        seq: 1,
        native_sn: 3,
      },
    ),
  ) == vectors.golden_datum_multi_clause
}

test datum_witnessed() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1],
        cur_threshold: Unweighted(1),
        next_digest: next_const,
        witnesses: [w1, w2],
        toad: 2,
        seq: 3,
        native_sn: 9,
      },
    ),
  ) == vectors.golden_datum_witnessed
}

test datum_witnessless() {
  cbor.serialise(
    V1(
      CheckpointDatumV1 {
        cesr_aid: cesr_datum,
        cur_keys: [k1],
        cur_threshold: Unweighted(1),
        next_digest: next_const,
        witnesses: [],
        toad: 0,
        seq: 0,
        native_sn: 0,
      },
    ),
  ) == vectors.golden_datum_witnessless
}

// ---------------------------------------------------------
// NextCommitment preimage + keyset_commit digest
// ---------------------------------------------------------

const next_commitment: NextCommitment =
  NextCommitment { next_keys: [k2], next_threshold: Unweighted(1) }

test next_commitment_cbor() {
  cbor.serialise(next_commitment) == vectors.golden_next_commitment_cbor
}

test next_commitment_digest() {
  keyset_commit(next_commitment) == vectors.golden_next_commitment_digest
}
