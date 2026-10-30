//// The concrete identity bytes of the consumer predicate (#343): the Lean
//// `CardanoKeri.ConsumerIdentity.Bytes` interpretation, in Aiken.
////
//// Placeholder: no bytes yet.

use cardano/assets.{AssetName}
use cardano_keri/consumer.{Preimage}

pub fn pack(_bytes: ByteArray) -> Int {
  0
}

pub fn unpack(_n: Int) -> ByteArray {
  #""
}

pub fn hash(_code: ByteArray) -> AssetName {
  #""
}

pub fn code(_preimage: Preimage) -> ByteArray {
  #""
}

pub fn key_of(_aid: Int) -> ByteArray {
  #""
}

pub fn aid_of_cesr(_text: ByteArray) -> Int {
  0
}
