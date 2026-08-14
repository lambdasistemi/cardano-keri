//// Canonical endpoint-board authorization protocol (#253 S253-2).
////
//// The M1 board (#165) authenticated only the KERI endpoint bytes, so a
//// witness signature said nothing about which Cardano record carried it.
//// The authorized target adds a second, independent witness signature over
//// one canonical message that also names the target policy, the Cardano
//// owner, and a one-use nonce output reference.
////
//// The signed bytes are canonical Plutus Data CBOR of `BoardAuthorization`
//// — never JSON, text, a raw concatenation, the endpoint-signature bytes, or
//// a caller-supplied preimage. The reader reconstructs them from a trusted
//// policy id plus the typed authorized datum, so a producer cannot choose
//// what a verifier will check.
////
//// There is no datum version, version-only constructor, stored origin, or
//// sequence anywhere in this module. A release is selected by its applied
//// policy hash, and the two shapes are told apart structurally: the frozen
//// legacy datum is `Constr 0` with exactly four fields, the authorized datum
//// is `Constr 0` with exactly six. Ledger consumption of the exact nonce plus
//// transaction history orders a lineage; a stored counter added no rejection
//// that exact nonce does not already make.

use aiken/cbor
use aiken/crypto.{verify_ed25519_signature}
use aiken/primitive/bytearray
use cardano/transaction.{OutputReference}

/// Domain separator for the authorization message. Changing this string
/// invalidates every signature ever produced under it, which is the point:
/// no other cardano-keri message can be replayed as a board authorization.
pub const board_authorization_domain: ByteArray =
  "cardano-keri/endpoint-board/authorization"

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
/// Wire shape: `Constr 0 [B nonce_tx_id, I nonce_output_index]`, which is
/// exactly the ledger's own `OutputReference` encoding.
pub type BoardNonce {
  nonce_tx_id: ByteArray,
  nonce_output_index: Int,
}

/// The authorized endpoint-board wire datum.
///
/// The shape is released protocol data, not an implementation detail: it must
/// stay `Constr 0` with exactly these six fields in this order. The frozen
/// four-field `BoardDatumV1` of `endpoint_board_types` shares the constructor
/// index and is distinguished from this one by field count alone.
pub type AuthorizedBoardDatum {
  witness_key: ByteArray,
  endpoint_record: ByteArray,
  endpoint_signature: ByteArray,
  owner_key_hash: ByteArray,
  nonce: BoardNonce,
  authorization_signature: ByteArray,
}

/// The canonical signed authorization message.
///
/// Wire shape: `Constr 0` with this exact field order. Every field here is
/// covered by `authorization_signature`; anything absent from this record is
/// not something the witness agreed to.
pub type BoardAuthorization {
  domain: ByteArray,
  board_policy_id: ByteArray,
  witness_key: ByteArray,
  endpoint_record: ByteArray,
  owner_key_hash: ByteArray,
  nonce: BoardNonce,
}

/// Does this bound nonce name exactly this output reference?
///
/// The nonce is a ledger coordinate, not caller bytes: Post proves the named
/// output is consumed, and Update proves the named output is the exact board
/// predecessor being spent.
pub fn nonce_names(nonce: BoardNonce, reference: OutputReference) -> Bool {
  and {
    nonce.nonce_tx_id == reference.transaction_id,
    nonce.nonce_output_index == reference.output_index,
  }
}

/// The `OutputReference` a bound nonce names.
pub fn nonce_reference(nonce: BoardNonce) -> OutputReference {
  OutputReference {
    transaction_id: nonce.nonce_tx_id,
    output_index: nonce.nonce_output_index,
  }
}

/// FUN-253-AUTH-RECONSTRUCT: rebuild the signed message from trusted inputs.
///
/// The policy id comes from the verifier's own applied identity, never from
/// the datum, which is what stops an authorization signed for one applied
/// board policy from being replayed at another.
pub fn reconstruct_board_authorization(
  policy_id: ByteArray,
  datum: AuthorizedBoardDatum,
) -> BoardAuthorization {
  BoardAuthorization {
    domain: board_authorization_domain,
    board_policy_id: policy_id,
    witness_key: datum.witness_key,
    endpoint_record: datum.endpoint_record,
    owner_key_hash: datum.owner_key_hash,
    nonce: datum.nonce,
  }
}

/// FUN-253-AUTH-BYTES: canonical Plutus Data CBOR of the authorization.
pub fn board_authorization_bytes(authorization: BoardAuthorization) -> ByteArray {
  cbor.serialise(authorization)
}

/// FUN-253-AUTH-VERIFY: the witness authorized exactly this bound record.
///
/// The width guards come first because the Ed25519 builtin aborts on a
/// mis-sized key or signature; a malformed datum must be rejected, not fatal.
pub fn verify_board_authorization(
  policy_id: ByteArray,
  datum: AuthorizedBoardDatum,
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
pub fn verify_endpoint_signature(datum: AuthorizedBoardDatum) -> Bool {
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

/// FUN-253-DATUM-AUTHENTIC: every byte-level rule for an authorized datum —
/// widths, the expected witness key, and BOTH witness signatures.
pub fn datum_is_authentic(
  expected_key: ByteArray,
  policy_id: ByteArray,
  datum: AuthorizedBoardDatum,
) -> Bool {
  and {
    bytearray.length(expected_key) == witness_key_width,
    datum.witness_key == expected_key,
    bytearray.length(datum.endpoint_record) > 0,
    bytearray.length(datum.endpoint_signature) == signature_width,
    bytearray.length(datum.owner_key_hash) == owner_key_hash_width,
    bytearray.length(datum.nonce.nonce_tx_id) == nonce_tx_id_width,
    datum.nonce.nonce_output_index >= 0,
    // Both, independently. Neither signature stands in for the other.
    verify_endpoint_signature(datum),
    verify_board_authorization(policy_id, datum),
  }
}
