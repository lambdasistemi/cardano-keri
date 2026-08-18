//// S0 staging / proof-token surface (S0-F06 / S0-M06).
////
//// Total-parses event bytes with the inherited INV-BIND decoder and
//// binds the KERI Blake3-256 SAID before minting the proof token.

use aiken/collection/dict
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/blake3
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/m12/event_decoder.{
  DecodeOk, DecodedEstablishmentEvent, VariantIcp, VariantRot,
  decode_establishment_event,
}
use cardano_keri/m12/types.{Inception, Interaction, ParsedEvent, Rotation}

fn kind_of(ev: DecodedEstablishmentEvent) {
  when ev.variant is {
    VariantIcp -> Inception
    VariantRot -> Rotation
    _ -> Interaction
  }
}

fn bound_event(raw: ByteArray, digest: ByteArray) -> Option<ParsedEvent> {
  if bytearray.length(digest) != 32 {
    None
  } else {
    when decode_establishment_event(raw) is {
      DecodeOk(ev) ->
        if ev.said != qb64_aid(digest) {
          None
        } else if ev.aid != qb64_aid(digest) && ev.variant == VariantIcp {
          None
        } else if !blake3.verify(ev.said_preimage, digest) {
          None
        } else {
          let key = when ev.k is {
            [first, ..] -> first
            [] -> digest
          }
          Some(
            ParsedEvent {
              raw,
              kind: kind_of(ev),
              sequence: bytearray.length(ev.seq),
              said: digest,
              key_material: key,
              threshold: bytearray.length(ev.kt),
              witness_count: list.length(ev.b),
              receipt_count: list.length(ev.b),
            },
          )
        }
      _ -> None
    }
  }
}

/// S0-F06 — inherited bytes-only parse, Blake3 SAID, then token identity.
pub fn validate_staging_token(
  raw_event: ByteArray,
  claimed: ParsedEvent,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  when bound_event(raw_event, claimed.said) is {
    None -> False
    Some(parsed) -> {
      let name: AssetName = parsed.said
      and {
        claimed.raw == raw_event,
        claimed.said == parsed.said,
        dict.to_pairs(tokens(tx.mint, policy_id)) == [Pair(name, 1)],
        list.any(
          tx.outputs,
          fn(out) {
            dict.to_pairs(tokens(out.value, policy_id)) == [Pair(name, 1)]
          },
        ),
      }
    }
  }
}
