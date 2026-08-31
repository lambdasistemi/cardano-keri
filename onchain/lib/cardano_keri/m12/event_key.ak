//// R1 event-derived MPF key.
////
//// The V1 preimage is canonical Plutus Data with this exact shape:
//// Constr 0 [B domain, B qualified-i, I decoded-s, option-p, B qualified-d].
//// option-p is Constr 0 [] when absent and Constr 1 [B p] when present.

use aiken/cbor
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano_keri/m12/event_decoder.{
  DecodedEstablishmentEvent, VariantDip, VariantDrt, VariantIcp, VariantRot,
}

const event_key_domain: ByteArray = "cardano-keri/event-key/v1"

/// Prior constructors are protocol: absent is 0, present is 1 with `p`.
type EventKeyPrior {
  PriorAbsent
  PriorPresent(ByteArray)
}

/// Five-field V1 preimage. Field order is the serialization contract.
type EventKeyPreimage {
  domain: ByteArray,
  aid: ByteArray,
  sequence: Int,
  prior: EventKeyPrior,
  said: ByteArray,
}

/// Derive the V1 MPF key from canonical, fully-qualified event identity.
pub fn event_key(
  i: ByteArray,
  s: Int,
  prior: Option<ByteArray>,
  d: ByteArray,
) -> ByteArray {
  let tagged_prior = when prior is {
    None -> PriorAbsent
    Some(p) -> PriorPresent(p)
  }
  blake2b_256(
    cbor.serialise(
      EventKeyPreimage {
        domain: event_key_domain,
        aid: i,
        sequence: s,
        prior: tagged_prior,
        said: d,
      },
    ),
  )
}

/// Adapt a verified decode. Unknown, non-canonical, or type-inconsistent
/// identity has no key. There is no sentinel digest.
pub fn event_key_of(ev: DecodedEstablishmentEvent) -> Option<ByteArray> {
  when event_sequence_of(ev) is {
    None -> None
    Some(sequence) ->
      if !is_canonical_aid(ev.aid) || !is_canonical_said(ev.said) {
        None
      } else {
        when ev.variant is {
          VariantIcp | VariantDip ->
            if ev.prior == #"" {
              Some(event_key(ev.aid, sequence, None, ev.said))
            } else {
              None
            }
          VariantRot | VariantDrt ->
            if is_canonical_said(ev.prior) {
              Some(event_key(ev.aid, sequence, Some(ev.prior), ev.said))
            } else {
              None
            }
        }
      }
  }
}

/// Decode canonical lowercase-hex `s` as its integer, or fail closed.
pub fn event_sequence_of(ev: DecodedEstablishmentEvent) -> Option<Int> {
  decode_canonical_sequence(ev.seq)
}

fn is_canonical_aid(value: ByteArray) -> Bool {
  is_canonical_qb64(value, True)
}

fn is_canonical_said(value: ByteArray) -> Bool {
  is_canonical_qb64(value, False)
}

// One-character qualified forms encode 0x00 || 32-byte payload as 44
// unpadded base64url characters, replacing the leading `A` with the
// derivation code. Character 2 therefore remains in A..P.
fn is_canonical_qb64(value: ByteArray, aid_allows_verkey: Bool) -> Bool {
  if bytearray.length(value) != 44 {
    False
  } else {
    let code = bytearray.at(value, 0)
    let code_ok = code == 69 || aid_allows_verkey && code == 68
    let second = bytearray.at(value, 1)
    code_ok && second >= 65 && second <= 80 && base64url_tail(value, 1)
  }
}

fn base64url_tail(value: ByteArray, offset: Int) -> Bool {
  if offset == bytearray.length(value) {
    True
  } else {
    let c = bytearray.at(value, offset)
    if c >= 65 && c <= 90 || c >= 97 && c <= 122 || c >= 48 && c <= 57 || c == 45 || c == 95 {
      base64url_tail(value, offset + 1)
    } else {
      False
    }
  }
}

fn decode_canonical_sequence(raw: ByteArray) -> Option<Int> {
  let length = bytearray.length(raw)
  if length == 0 {
    None
  } else if length > 1 && bytearray.at(raw, 0) == 48 {
    None
  } else {
    decode_hex_at(raw, 0, 0)
  }
}

fn decode_hex_at(raw: ByteArray, offset: Int, acc: Int) -> Option<Int> {
  if offset == bytearray.length(raw) {
    Some(acc)
  } else {
    when hex_digit(bytearray.at(raw, offset)) is {
      None -> None
      Some(digit) -> decode_hex_at(raw, offset + 1, acc * 16 + digit)
    }
  }
}

fn hex_digit(c: Int) -> Option<Int> {
  if c >= 48 && c <= 57 {
    Some(c - 48)
  } else if c >= 97 && c <= 102 {
    Some(c - 87)
  } else {
    None
  }
}
