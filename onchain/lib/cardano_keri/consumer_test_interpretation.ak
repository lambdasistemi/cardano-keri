//// The declared test interpretation of the consumer predicate: test
//// interpretation, not the registry byte layout.
////
//// Hash, codec, AID-to-key map and datum decoder as plain functions the
//// consumer validator and the connected tests share. A later real byte
//// binding replaces this one module; the predicate is unchanged.
////
////   code(State seed)               0x00 ++ transaction id ++ output index (8 bytes)
////   code(Active registry key)      0x01 ++ registry policy ++ registry name ++ key
////   hash                           blake2b-256
////   key_of(aid)                    the AID as 8 big-endian bytes
////   decode(release, raw)           raw is the decoded datum itself: a
////                                  `DecodedDatum` as Plutus data (a datum of
////                                  any other shape is a failure)

use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/assets.{AssetName}
use cardano_keri/consumer.{
  ActivePreimage, DecodedDatum, Preimage, PublishedRelease, StatePreimage,
}

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

pub fn decode(_release: PublishedRelease, raw: Data) -> Option<DecodedDatum> {
  expect decoded: DecodedDatum = raw
  Some(decoded)
}
