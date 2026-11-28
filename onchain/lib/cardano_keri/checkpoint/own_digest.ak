//// The own-digest proof of an inception: the event's `d` is the blake3 of the event with `d` blanked, and with `i`
//// blanked as well when the identifier is itself a digest (keripy's dressing); the payload of `i` is the claimed raw
//// identifier.
////
//// It reads the two places the keripy layout fixes, `d` at byte 40 and `i` at byte 91, after comparing the bytes around
//// them with the canonical text: the version string, the type and the separators. It proves exactly the statement the
//// proof token carries; the registration binder, which requires the same bytes to be the canonical inception of the
//// datum, is what ties every other field.

use aiken/builtin
use aiken/primitive/bytearray
use cardano_keri/blake3
use cardano_keri/checkpoint/qualified.{digest_payload, identifier_payload}
use cardano_keri/checkpoint/registration.{hex6}

const dress: ByteArray = "############################################"

pub fn proven(input_bytes: ByteArray, cesr_aid: ByteArray) -> Bool {
  let size = bytearray.length(input_bytes)
  size >= 142 && size <= 1024 && builtin.slice_bytearray(0, 40, input_bytes) == bytearray.concat(
    bytearray.concat("{\"v\":\"KERI10JSON", hex6(size)),
    "_\",\"t\":\"icp\",\"d\":\"",
  ) && builtin.slice_bytearray(84, 7, input_bytes) == "\",\"i\":\"" && builtin.slice_bytearray(
    135,
    7,
    input_bytes,
  ) == "\",\"s\":\"" && {
    let said = builtin.slice_bytearray(40, 44, input_bytes)
    let aid = builtin.slice_bytearray(91, 44, input_bytes)
    when (digest_payload(said), identifier_payload(aid)) is {
      (Some(digest), Some(payload)) -> {
        let first = bytearray.at(aid, 0)
        let digest_identifier = aid == said || first >= 69 && first <= 73
        let blank_d = bytearray.concat(
          bytearray.concat(builtin.slice_bytearray(0, 40, input_bytes), dress),
          bytearray.drop(input_bytes, 84),
        )
        let preimage = if digest_identifier {
          bytearray.concat(
            bytearray.concat(builtin.slice_bytearray(0, 91, blank_d), dress),
            bytearray.drop(blank_d, 135),
          )
        } else {
          blank_d
        }
        payload == cesr_aid && blake3.verify(preimage, digest)
      }
      _ -> False
    }
  }
}
