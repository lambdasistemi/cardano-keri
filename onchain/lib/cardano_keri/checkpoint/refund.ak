//// The refund address a version 2 checkpoint carries (Lean `Live.refundTo`).
////
//// The datum holds the address as ledger bytes: the header byte (address
//// type in the high nibble, network in the low one) followed by the payment
//// credential hash and, for a base address, the stake credential hash. The
//// registration check is on those bytes alone; a conviction compares the
//// ledger bytes of an output's address with them.

use aiken/primitive/bytearray
use cardano/address.{Address, Inline, Script, VerificationKey}

/// Whether the bytes are a Shelley address a transaction output can carry on
/// the network: a base address (types 0-3, 57 bytes) or an enterprise
/// address (types 6 and 7, 29 bytes). Pointer, reward and Byron addresses
/// are not payable here.
pub fn payable(network_id: Int, refund_to: ByteArray) -> Bool {
  if bytearray.length(refund_to) == 0 {
    False
  } else {
    let header = bytearray.at(refund_to, 0)
    let kind = header / 16
    let size = bytearray.length(refund_to)
    header % 16 == network_id && (
      kind <= 3 && size == 57 || ( kind == 6 || kind == 7 ) && size == 29
    )
  }
}

/// The ledger bytes of an address on the network, `None` for an address no
/// payable refund can equal (a pointer stake part).
pub fn ledger_bytes(network_id: Int, address: Address) -> Option<ByteArray> {
  let Address { payment_credential, stake_credential } = address
  let (payment_kind, payment_hash) = when payment_credential is {
    VerificationKey(hash) -> (0, hash)
    Script(hash) -> (1, hash)
  }
  when stake_credential is {
    None ->
      Some(bytearray.push(payment_hash, ( 6 + payment_kind ) * 16 + network_id))
    Some(Inline(VerificationKey(stake_hash))) ->
      Some(
        bytearray.push(
          bytearray.concat(payment_hash, stake_hash),
          payment_kind * 16 + network_id,
        ),
      )
    Some(Inline(Script(stake_hash))) ->
      Some(
        bytearray.push(
          bytearray.concat(payment_hash, stake_hash),
          ( payment_kind + 2 ) * 16 + network_id,
        ),
      )
    _ -> None
  }
}
