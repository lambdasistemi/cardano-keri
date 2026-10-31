//// The declared test interpretation of the consumer predicate: test
//// interpretation, not the registry byte layout.
////
//// Hash, codec and AID-to-key map as plain functions the predicate's property
//// tests share. The concrete bytes are `consumer_identity_bytes` and the datum
//// decoder is `consumer_checkpoint_datum`; this module is only the fixture the
//// predicate tests run against.
////
////   code(State seed)               0x00 ++ transaction id ++ output index (8 bytes)
////   code(Active registry key)      0x01 ++ registry policy ++ registry name ++ key
////   hash                           blake2b-256
////   key_of(aid)                    the AID as 8 big-endian bytes

use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/assets.{AssetName}
use cardano_keri/consumer.{ActivePreimage, Preimage, StatePreimage}

pub fn hash(code: ByteArray) -> AssetName {
  blake2b_256(code)
}

pub fn code(preimage: Preimage) -> ByteArray {
  when preimage is {
    StatePreimage { seed } ->
      bytearray.concat(
        #"00",
        bytearray.concat(
          seed.transaction_id,
          bytearray.from_int_big_endian(seed.output_index, 8),
        ),
      )
    ActivePreimage { registry, key } ->
      bytearray.concat(
        #"01",
        bytearray.concat(registry.policy, bytearray.concat(registry.name, key)),
      )
  }
}

pub fn key_of(aid: Int) -> ByteArray {
  bytearray.from_int_big_endian(aid, 8)
}
