//// S0 cursor derivation (S0-F03 / S0-M03).
////
//// Consumes a staging-bound parsed token plus a historical proof.

use aiken/crypto.{blake2b_256}
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{root}
use aiken/primitive/bytearray
use cardano_keri/m12/record.{bind_parsed_event}
use cardano_keri/m12/types.{
  Abandoned, CursorState, Established, EventKind, FullyWitnessed,
  HistoricalProof, Inception, Interaction, ParsedEvent, PartiallyWitnessed,
  Rotated, Rotation, Unwitnessed,
}

fn keri_state_of(kind: EventKind) {
  when kind is {
    Inception -> Established
    Rotation -> Rotated
    Interaction -> Established
  }
}

fn grade_of(event: ParsedEvent) {
  if event.witness_count > 0 && event.receipt_count >= event.witness_count {
    FullyWitnessed
  } else if event.receipt_count > 0 {
    PartiallyWitnessed
  } else {
    Unwitnessed
  }
}

/// S0-F03 — derive every cursor field from a bound token + history proof.
pub fn derive_cursor(
  old: CursorState,
  event: ParsedEvent,
  proof: HistoricalProof,
  now: Int,
) -> Option<CursorState> {
  if now < old.last_moved_slot {
    None
  } else {
    when bind_parsed_event(event.raw, event) is {
      None -> None
      Some(parsed) -> {
        let new_keys = blake2b_256(parsed.key_material)
        let trie = mpf.from_root(proof.prior_snapshot_digest)
        let updated = mpf.update(
          trie,
          proof.key,
          proof.proof,
          old.keys_digest,
          new_keys,
        )
        expect bytearray.length(root(updated)) == 32
        let next = CursorState {
          keys_digest: new_keys,
          keri_state: if parsed.threshold == 0 {
            Abandoned
          } else {
            keri_state_of(parsed.kind)
          },
          grade: grade_of(parsed),
          last_moved_slot: now,
          registration_slot: old.registration_slot,
        }
        if next == old {
          None
        } else {
          Some(next)
        }
      }
    }
  }
}
