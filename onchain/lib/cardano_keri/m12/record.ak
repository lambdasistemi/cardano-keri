//// S0 record helpers: staging-bound token identity + append (S0-F01,
//// S0-F02, S0-M02).
////
//// After the staged parser-policy split, append consumes a token whose
//// SAID was already bound by the staging member. It does not reparse
//// raw KERI bytes.

use aiken/crypto.{blake2b_256}
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{root}
use aiken/primitive/bytearray
use cardano_keri/m12/types.{HistoricalProof, ParsedEvent, RecordState}

/// S0-F01 — accept only a parser-policy-bound 32-byte SAID token.
pub fn bind_parsed_event(
  raw_event: ByteArray,
  claimed: ParsedEvent,
) -> Option<ParsedEvent> {
  if claimed.raw != raw_event {
    None
  } else if bytearray.length(claimed.said) != 32 {
    None
  } else if bytearray.length(raw_event) == 0 {
    None
  } else {
    Some(claimed)
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
