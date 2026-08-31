//// S0 record helpers: INV-BIND total parse + proof-token burn + append.

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{root}
use aiken/primitive/bytearray
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/m12/event_decoder.{
  DecodeOk, DecodedEstablishmentEvent, VariantDip, VariantIcp, VariantRot,
  decode_establishment_event,
}
use cardano_keri/m12/event_key.{event_key_of, event_sequence_of}
use cardano_keri/m12/proof_token.{consume_and_burn_proof}
use cardano_keri/m12/types.{
  HistoricalProof, Inception, Interaction, ParsedEvent, RecordState, Rotation,
}

fn kind_of(ev: DecodedEstablishmentEvent) {
  when ev.variant is {
    VariantIcp -> Inception
    VariantRot -> Rotation
    _ -> Interaction
  }
}

fn said_matches(ev: DecodedEstablishmentEvent, cesr_aid: ByteArray) -> Bool {
  let expected = qb64_aid(cesr_aid)
  ev.said == expected && when ev.variant is {
    VariantIcp | VariantDip -> ev.aid == expected
    _ -> True
  }
}

fn event_from_decode(
  raw: ByteArray,
  cesr_aid: ByteArray,
  ev: DecodedEstablishmentEvent,
) -> Option<ParsedEvent> {
  let key = when ev.k is {
    [first, ..] -> first
    [] -> cesr_aid
  }
  when (event_key_of(ev), event_sequence_of(ev)) is {
    (Some(derived_key), Some(sequence)) ->
      Some(
        ParsedEvent {
          raw,
          kind: kind_of(ev),
          sequence,
          said: cesr_aid,
          event_key: derived_key,
          key_material: key,
          threshold: bytearray.length(ev.kt),
          witness_count: list.length(ev.b),
          receipt_count: list.length(ev.b),
        },
      )
    _ -> None
  }
}

/// S0-F01 — bytes-only total parse plus matching proof-token burn.
pub fn bind_parsed_event(
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
  tx: Transaction,
) -> Option<ParsedEvent> {
  if bytearray.length(cesr_aid) != 32 {
    None
  } else if !consume_and_burn_proof(raw_event, cesr_aid, proof_policy, tx) {
    None
  } else {
    when decode_establishment_event(raw_event) is {
      DecodeOk(ev) ->
        if said_matches(ev, cesr_aid) {
          event_from_decode(raw_event, cesr_aid, ev)
        } else {
          None
        }
      _ -> None
    }
  }
}

/// S0-F02 — authenticated-map insert plus derived occupancy/count.
pub fn apply_record_append(
  old: RecordState,
  raw_event: ByteArray,
  cesr_aid: ByteArray,
  proof_policy: PolicyId,
  proof: HistoricalProof,
  tx: Transaction,
) -> Option<RecordState> {
  when bind_parsed_event(raw_event, cesr_aid, proof_policy, tx) is {
    None -> None
    Some(parsed) -> {
      let trie = mpf.from_root(old.event_root)
      let updated = mpf.insert(trie, parsed.event_key, parsed.said, proof.proof)
      Some(
        RecordState {
          event_root: root(updated),
          occupancy_root: blake2b_256(
            old.occupancy_root |> bytearray.concat(parsed.said),
          ),
          event_count: old.event_count + 1,
        },
      )
    }
  }
}
