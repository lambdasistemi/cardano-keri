//// S0-F06 / S0-M06 — Tx-A proof-token policy.
////
//// Owns the bounded (<= 1024 B) KERI Blake3 SAID proof and the pair-bound
//// mint. Burning is always permitted so Tx-B can consume the token.
////
//// Recomputed `d` is bound to `cesr_aid`. Qualified `i` is an independent
//// canonical span and need not equal `d` (ordinary rot/drt). A-019 /
//// A-015: dress both SAID spans only for self-addressing inception
//// (icp/dip); dress `d` only for present-prior rot/drt so `i` stays in
//// the preimage.

use aiken/collection/dict
use aiken/primitive/bytearray
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/blake3
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/m12/event_decoder.{
  DecodeOk, EventVariant, VariantDip, VariantDrt, VariantIcp, VariantRot,
  decode_establishment_event,
}
use cardano_keri/m12/proof_token.{
  all_burns, dummy_span, proof_token_name, slice_matches, splice_dummies,
}

/// S0-F06 — Blake3 SAID + mint identity, or an all-burn mint map.
pub fn validate_staging_token(
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  off_i: Int,
  off_d: Int,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  let entries = dict.to_pairs(tokens(tx.mint, policy_id))
  if all_burns(entries) {
    True
  } else {
    when decode_establishment_event(raw_event) is {
      DecodeOk(ev) -> and {
          bytearray.length(raw_event) >= 1,
          bytearray.length(raw_event) <= 1024,
          bytearray.length(cesr_aid) == 32,
          0 <= off_d,
          off_d + 44 <= off_i,
          off_i + 44 <= bytearray.length(raw_event),
          slice_matches(raw_event, off_d, qb64_aid(cesr_aid)),
          canonical_qualified_aid_slice(raw_event, off_i),
          slice_matches(raw_event, off_i, ev.aid),
          self_addressing_i_holds(ev.variant, raw_event, off_i, cesr_aid),
          blake3.verify(
            dress_said_preimage(raw_event, ev.variant, off_i, off_d),
            cesr_aid,
          ),
          entries == [Pair(proof_token_name(raw_event, cesr_aid), 1)],
        }
      _ -> False
    }
  }
}

fn self_addressing_i_holds(
  variant: EventVariant,
  raw: ByteArray,
  off_i: Int,
  cesr_aid: ByteArray,
) -> Bool {
  when variant is {
    VariantIcp | VariantDip -> slice_matches(raw, off_i, qb64_aid(cesr_aid))
    VariantRot | VariantDrt -> True
  }
}

fn dress_said_preimage(
  raw: ByteArray,
  variant: EventVariant,
  off_i: Int,
  off_d: Int,
) -> ByteArray {
  when variant is {
    VariantIcp | VariantDip -> splice_dummies(raw, off_i, off_d)
    VariantRot | VariantDrt -> splice_dummy_d(raw, off_d)
  }
}

fn splice_dummy_d(raw: ByteArray, off_d: Int) -> ByteArray {
  bytearray.take(raw, off_d)
    |> bytearray.concat(dummy_span)
    |> bytearray.concat(bytearray.drop(raw, off_d + 44))
}

fn canonical_qualified_aid_slice(raw: ByteArray, off: Int) -> Bool {
  off >= 0 && off + 44 <= bytearray.length(raw) && is_canonical_aid(
    bytearray.take(bytearray.drop(raw, off), 44),
  )
}

fn is_canonical_aid(value: ByteArray) -> Bool {
  if bytearray.length(value) != 44 {
    False
  } else {
    let code = bytearray.at(value, 0)
    let second = bytearray.at(value, 1)
    ( code == 69 || code == 68 ) && second >= 65 && second <= 80 && base64url_tail(
      value,
      1,
    )
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
