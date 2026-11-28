//// Qualified spellings of identifiers and keys in the checkpoint datum.
////
//// The datum keeps what the event signed: the identifier `i` and each current key `k` as their exact 44 character
//// qualified text (code, then the base64url of the raw payload). The raw 32 byte payload is derived here, at the
//// boundaries that need it: the proof token name, the signature checks and the key set rules.

use aiken/primitive/bytearray
use cardano_keri/base64url

/// Code byte `B`: an Ed25519 verification key that cannot rotate.
pub const code_b: Int = 66

/// Code byte `D`: an Ed25519 verification key that can rotate.
pub const code_d: Int = 68

/// Code byte `E`: a 256 bit digest.
pub const code_e: Int = 69

/// The raw 32 byte payload of a 44 character qualified text whose code is one of `codes`. The first character after
/// the code carries two padding bits, which must be zero: `None` unless `qualify(code, payload) == text`.
pub fn payload_of(text: ByteArray, codes: List<Int>) -> Option<ByteArray> {
  if bytearray.length(text) == 44 && list_has(codes, bytearray.at(text, 0)) {
    when base64url.decode(bytearray.push(bytearray.drop(text, 1), 65)) is {
      Some(raw) ->
        if bytearray.at(raw, 0) == 0 {
          Some(bytearray.drop(raw, 1))
        } else {
          None
        }
      None -> None
    }
  } else {
    None
  }
}

fn list_has(xs: List<Int>, x: Int) -> Bool {
  when xs is {
    [] -> False
    [y, ..ys] -> y == x || list_has(ys, x)
  }
}

/// The qualified text of a raw 32 byte payload under a code.
pub fn qualify(code: Int, payload: ByteArray) -> ByteArray {
  bytearray.push(
    bytearray.drop(base64url.encode(bytearray.push(payload, 0)), 1),
    code,
  )
}

/// The code and raw payload of an identifier: a key (`B`, `D`) or a digest (`E`).
pub fn identifier_parts(text: ByteArray) -> Option<(Int, ByteArray)> {
  when payload_of(text, [code_b, code_d, code_e]) is {
    Some(payload) -> Some((bytearray.at(text, 0), payload))
    None -> None
  }
}

/// The raw payload of an identifier of any of the three codes.
pub fn identifier_payload(text: ByteArray) -> Option<ByteArray> {
  payload_of(text, [code_b, code_d, code_e])
}

/// The raw payload of a current key: a `B` or `D` verification key.
pub fn key_payload(text: ByteArray) -> Option<ByteArray> {
  payload_of(text, [code_b, code_d])
}

/// The raw payload of a digest text, code `E`.
pub fn digest_payload(text: ByteArray) -> Option<ByteArray> {
  payload_of(text, [code_e])
}

/// The raw payloads of a list of current keys, in order, or `None` when one of them is not a qualified key.
pub fn key_payloads(texts: List<ByteArray>) -> Option<List<ByteArray>> {
  when texts is {
    [] -> Some([])
    [text, ..rest] ->
      when key_payload(text) is {
        Some(raw) ->
          when key_payloads(rest) is {
            Some(raws) -> Some([raw, ..raws])
            None -> None
          }
        None -> None
      }
  }
}
