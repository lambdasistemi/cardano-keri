//// R1 event-derived MPF key (RED stub).
////
//// Production hashing, qualification, and fail-closed adaptation are
//// intentionally absent so the vector suite fails at assertions.

use cardano_keri/m12/event_decoder.{DecodedEstablishmentEvent}

const event_key_domain: ByteArray = "cardano-keri/event-key/v1"

const zeros32: ByteArray =
  #"0000000000000000000000000000000000000000000000000000000000000000"

/// Sole V1 key producer. RED stub ignores canonical inputs.
pub fn event_key(
  _i: ByteArray,
  _s: Int,
  _prior: Option<ByteArray>,
  _d: ByteArray,
) -> ByteArray {
  let _domain = event_key_domain
  zeros32
}

/// Adapt a verified decode. RED stub never rejects.
pub fn event_key_of(ev: DecodedEstablishmentEvent) -> Option<ByteArray> {
  Some(event_key(ev.aid, 0, None, ev.said))
}

/// Canonical hex `s` as integer. RED stub always yields 0.
pub fn event_sequence_of(_ev: DecodedEstablishmentEvent) -> Option<Int> {
  Some(0)
}
