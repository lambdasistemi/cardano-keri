//// The concrete identity bytes of the consumer predicate (#343): the Lean
//// `CardanoKeri.ConsumerIdentity.Bytes` interpretation, in Aiken
//// (lean/CardanoKeri/ConsumerBytes.lean).
////
////   hash           BLAKE2b-256
////   code           the Plutus Data serialisation of the preimage: State is
////                  constructor 0 with the seed's OutputReference, Active is
////                  constructor 1 with the RegistryIdentity and the key
////   key_of(aid)    the Lean carrier `unpack` of the AID numeral: the AID's
////                  qualified CESR text bytes
////   aid_of_cesr    the Lean `aidOfCesr`: `pack` of the CESR text bytes
////
//// The constructors are built field by field here, so the bytes depend on the
//// Lean layout and not on the declaration order of the predicate's own types.
//// The datum decoder is not part of this module: the Lean keeps it an input,
//// and it is `consumer_checkpoint_datum`. Not for mainnet.

use aiken/builtin.{b_data, constr_data, i_data, serialise_data}
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/assets.{AssetName}
use cardano_keri/consumer.{ActivePreimage, Preimage, StatePreimage}

/// Lean `pack`: the bijective base-256 numeral of a byte string, least
/// significant digit first, so empty strings and leading zero bytes keep their
/// identity.
pub fn pack(bytes: ByteArray) -> Int {
  bytearray.foldr(bytes, 0, fn(byte, rest) { byte + 1 + 256 * rest })
}

/// Lean `unpack`: the byte string a numeral carries. A negative number carries
/// nothing.
pub fn unpack(n: Int) -> ByteArray {
  if n == 0 {
    #""
  } else {
    expect n > 0
    bytearray.push(unpack(( n - 1 ) / 256), ( n - 1 ) % 256)
  }
}

/// Lean `hash`: BLAKE2b-256 of the serialised preimage.
pub fn hash(code: ByteArray) -> AssetName {
  blake2b_256(code)
}

/// Lean `code`, for the two roles the predicate names.
pub fn code(preimage: Preimage) -> ByteArray {
  serialise_data(
    when preimage is {
      StatePreimage { seed } ->
        constr_data(
          0,
          [
            constr_data(
              0,
              [b_data(seed.transaction_id), i_data(seed.output_index)],
            ),
          ],
        )
      ActivePreimage { registry, key } ->
        constr_data(
          1,
          [
            constr_data(0, [b_data(registry.policy), b_data(registry.name)]),
            b_data(key),
          ],
        )
    },
  )
}

/// Lean `keyOf` over the carrier: the AID's CESR text bytes.
pub fn key_of(aid: Int) -> ByteArray {
  unpack(aid)
}

/// Lean `aidOfCesr`, on the UTF-8 bytes of the qualified CESR text.
pub fn aid_of_cesr(text: ByteArray) -> Int {
  pack(text)
}
