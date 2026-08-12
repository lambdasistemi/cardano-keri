//// Canonical endpoint-board authorization protocol (#253 S253-1).
////
//// The M1 board (#165) authenticated only the KERI endpoint bytes, so a
//// witness signature said nothing about which Cardano record carried it.
//// V2 adds a second, independent witness signature over one canonical
//// message that also names the board policy, the Cardano owner, the record
//// sequence, and a one-use nonce output reference.
////
//// The signed bytes are canonical Plutus Data CBOR of `BoardAuthorizationV2`
//// — never JSON, text, a raw concatenation, the endpoint-signature bytes, or
//// a caller-supplied preimage. The reader reconstructs them from a trusted
//// policy id plus the typed V2 datum, so a producer cannot choose what a
//// verifier will check.
////
//// This module owns the vocabulary and the predicates only. Wiring them into
//// the deployed validator lifecycle is S253-2 and is deliberately absent.

use aiken/cbor
use aiken/crypto.{verify_ed25519_signature}
use aiken/primitive/bytearray

/// Domain separator for the V2 authorization message. Changing this string
/// invalidates every signature ever produced under it, which is the point:
/// no other cardano-keri message can be replayed as a board authorization.
pub const board_authorization_domain: ByteArray =
  "cardano-keri/endpoint-board/authorization/v2"

/// Exact width of a raw Ed25519 verification key.
pub const witness_key_width: Int = 32

/// Exact width of a raw Ed25519 signature.
pub const signature_width: Int = 64

/// Exact width of a Cardano payment key hash.
pub const owner_key_hash_width: Int = 28

/// Exact width of a ledger transaction id.
pub const nonce_tx_id_width: Int = 32

/// The one-use ledger output reference bound into an authorization.
///
/// Wire shape: `Constr 0 [B nonce_tx_id, I nonce_output_index]`.
pub type BoardNonce {
  nonce_tx_id: ByteArray,
  nonce_output_index: Int,
}

/// The versioned endpoint-board wire datum.
///
/// The constructor index is released protocol data, not an implementation
/// detail: `BoardV1` must stay constructor 0 with exactly the four frozen
/// #165 fields, and `BoardV2` must stay constructor 1 with exactly seven.
pub type BoardDatum {
  BoardV1 {
    witness_key: ByteArray,
    endpoint_record: ByteArray,
    endpoint_signature: ByteArray,
    owner_key_hash: ByteArray,
  }
  BoardV2 {
    witness_key: ByteArray,
    endpoint_record: ByteArray,
    endpoint_signature: ByteArray,
    owner_key_hash: ByteArray,
    sequence: Int,
    nonce: BoardNonce,
    authorization_signature: ByteArray,
  }
}

/// A typed view of the V2 variant's fields.
///
/// This is NOT a wire type and must never be serialised: on the wire a V2
/// datum is `BoardDatum.BoardV2`, which carries constructor index 1. This
/// record exists so the authorization functions can take a V2 datum that is
/// V2 by construction instead of re-checking a version at every call.
pub type BoardDatumV2 {
  witness_key: ByteArray,
  endpoint_record: ByteArray,
  endpoint_signature: ByteArray,
  owner_key_hash: ByteArray,
  sequence: Int,
  nonce: BoardNonce,
  authorization_signature: ByteArray,
}

/// The canonical signed authorization message.
///
/// Wire shape: `Constr 0` with this exact field order. Every field here is
/// covered by `authorization_signature`; anything absent from this record is
/// not something the witness agreed to.
pub type BoardAuthorizationV2 {
  domain: ByteArray,
  board_policy_id: ByteArray,
  witness_key: ByteArray,
  endpoint_record: ByteArray,
  owner_key_hash: ByteArray,
  sequence: Int,
  nonce: BoardNonce,
}

/// Project the typed V2 fields out of a versioned datum.
///
/// A V1 datum yields `None`: it carries no authorization at all and must
/// never be promoted as though it did.
pub fn board_datum_v2(datum: BoardDatum) -> Option<BoardDatumV2> {
  when datum is {
    BoardV1 { .. } -> None
    BoardV2 {
      witness_key,
      endpoint_record,
      endpoint_signature,
      owner_key_hash,
      sequence,
      nonce,
      authorization_signature,
    } ->
      Some(
        BoardDatumV2 {
          witness_key,
          endpoint_record,
          endpoint_signature,
          owner_key_hash,
          sequence,
          nonce,
          authorization_signature,
        },
      )
  }
}

/// FUN-253-AUTH-RECONSTRUCT: rebuild the signed message from trusted inputs.
///
/// The policy id comes from the verifier's own identity, never from the
/// datum, which is what stops an authorization signed for one board version
/// from being replayed at another.
pub fn reconstruct_board_authorization(
  policy_id: ByteArray,
  datum: BoardDatumV2,
) -> BoardAuthorizationV2 {
  BoardAuthorizationV2 {
    domain: board_authorization_domain,
    board_policy_id: policy_id,
    witness_key: datum.witness_key,
    endpoint_record: datum.endpoint_record,
    owner_key_hash: datum.owner_key_hash,
    sequence: datum.sequence,
    nonce: datum.nonce,
  }
}

/// FUN-253-AUTH-BYTES: canonical Plutus Data CBOR of the authorization.
pub fn board_authorization_bytes(
  authorization: BoardAuthorizationV2,
) -> ByteArray {
  cbor.serialise(authorization)
}

/// FUN-253-AUTH-VERIFY: the witness authorized exactly this bound record.
///
/// The width guards come first because the Ed25519 builtin aborts on a
/// mis-sized key or signature; a malformed datum must be rejected, not fatal.
pub fn verify_board_authorization(
  policy_id: ByteArray,
  datum: BoardDatumV2,
) -> Bool {
  and {
    bytearray.length(datum.witness_key) == witness_key_width,
    bytearray.length(datum.authorization_signature) == signature_width,
    verify_ed25519_signature(
      datum.witness_key,
      board_authorization_bytes(
        reconstruct_board_authorization(policy_id, datum),
      ),
      datum.authorization_signature,
    ),
  }
}

/// The independent #165 endpoint signature over the raw KERI record bytes.
///
/// This is a separate check from the authorization and neither replaces the
/// other: one proves the endpoint bytes are the witness's, the other proves
/// the witness accepted this Cardano binding of them.
pub fn verify_endpoint_signature(datum: BoardDatumV2) -> Bool {
  and {
    bytearray.length(datum.witness_key) == witness_key_width,
    bytearray.length(datum.endpoint_signature) == signature_width,
    verify_ed25519_signature(
      datum.witness_key,
      datum.endpoint_record,
      datum.endpoint_signature,
    ),
  }
}

/// Every byte-level V2 rule: widths, non-negative counters, expected key,
/// and BOTH witness signatures.
pub fn datum_v2_is_authentic(
  expected_key: ByteArray,
  policy_id: ByteArray,
  datum: BoardDatumV2,
) -> Bool {
  and {
    bytearray.length(expected_key) == witness_key_width,
    datum.witness_key == expected_key,
    bytearray.length(datum.endpoint_record) > 0,
    bytearray.length(datum.endpoint_signature) == signature_width,
    bytearray.length(datum.owner_key_hash) == owner_key_hash_width,
    bytearray.length(datum.nonce.nonce_tx_id) == nonce_tx_id_width,
    datum.sequence >= 0,
    datum.nonce.nonce_output_index >= 0,
    // Both, independently. Neither signature stands in for the other.
    verify_endpoint_signature(datum),
    verify_board_authorization(policy_id, datum),
  }
}
