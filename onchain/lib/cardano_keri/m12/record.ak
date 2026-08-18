//// S0 record helpers: bytes-anchored bind + append transition (S0-F01,
//// S0-F02, S0-M02).

use aiken/crypto.{blake2b_256}
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{root}
use aiken/primitive/bytearray
use cardano_keri/m12/types.{
  HistoricalProof, Inception, Interaction, ParsedEvent, RecordState, Rotation,
}

/// Bytes-only parse of the measurement event layout.
///
/// Layout (minimum 70 bytes): kind, sequence, 32-byte keys, threshold,
/// witness count, receipt count, then remaining payload. SAID is
/// `blake2b_256(raw)`.
pub fn parse_event_bytes(raw: ByteArray) -> Option<ParsedEvent> {
  let len = bytearray.length(raw)
  if len < 70 {
    None
  } else {
    let kind = when bytearray.at(raw, 0) is {
      0 -> Some(Inception)
      1 -> Some(Rotation)
      2 -> Some(Interaction)
      _ -> None
    }
    when kind is {
      None -> None
      Some(event_kind) -> {
        let sequence = bytearray.at(raw, 1)
        let key_material = raw |> bytearray.drop(2) |> bytearray.take(32)
        let threshold = bytearray.at(raw, 34)
        let witness_count = bytearray.at(raw, 35)
        let receipt_count = bytearray.at(raw, 36)
        Some(
          ParsedEvent {
            raw,
            kind: event_kind,
            sequence,
            said: blake2b_256(raw),
            key_material,
            threshold,
            witness_count,
            receipt_count,
          },
        )
      }
    }
  }
}

/// S0-F01 — total, bytes-anchored bind of a claimed parse.
pub fn bind_parsed_event(
  raw_event: ByteArray,
  claimed: ParsedEvent,
) -> Option<ParsedEvent> {
  when parse_event_bytes(raw_event) is {
    None -> None
    Some(parsed) ->
      if claimed.raw != raw_event {
        None
      } else if claimed.said != parsed.said {
        None
      } else if claimed.kind != parsed.kind {
        None
      } else if claimed.sequence != parsed.sequence {
        None
      } else if claimed.key_material != parsed.key_material {
        None
      } else if claimed.threshold != parsed.threshold {
        None
      } else if claimed.witness_count != parsed.witness_count {
        None
      } else if claimed.receipt_count != parsed.receipt_count {
        None
      } else {
        Some(parsed)
      }
  }
}

/// S0-F02 — authenticated-map insert plus derived occupancy/count.
pub fn apply_record_append(
  old: RecordState,
  event: ParsedEvent,
  proof: HistoricalProof,
) -> Option<RecordState> {
  when bind_parsed_event(event.raw, event) is {
    None -> None
    Some(parsed) -> {
      let trie = mpf.from_root(old.event_root)
      let updated = mpf.insert(trie, proof.key, parsed.said, proof.proof)
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
