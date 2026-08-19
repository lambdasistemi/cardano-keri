//// S0 measurement-only family types (S0-M01 / S0-D01–D07).
////
//// These shapes exist so each skeleton can reach its named parse, proof,
//// and transition surface. They are not production schemas.

use aiken/merkle_patricia_forestry.{Proof}

/// Parsed KERI-like event kind used by the bytes parser.
pub type EventKind {
  Inception
  Rotation
  Interaction
}

/// S0-D01 — raw bytes plus derived identity the binders consume.
pub type ParsedEvent {
  raw: ByteArray,
  kind: EventKind,
  sequence: Int,
  said: ByteArray,
  key_material: ByteArray,
  threshold: Int,
  witness_count: Int,
  receipt_count: Int,
}

/// S0-D02 — append-only record occupancy.
pub type RecordState {
  event_root: ByteArray,
  occupancy_root: ByteArray,
  event_count: Int,
}

/// Adopted KERI projection used by the cursor and predicates.
pub type KeriState {
  Established
  Rotated
  Abandoned
}

/// Witness-quality grade used by cursor, escrow, and predicates.
pub type EvidenceGrade {
  Unwitnessed
  PartiallyWitnessed
  FullyWitnessed
}

/// S0-D03 — validator-derived cursor.
pub type CursorState {
  keys_digest: ByteArray,
  keri_state: KeriState,
  grade: EvidenceGrade,
  last_moved_slot: Int,
  registration_slot: Int,
}

/// S0-D04 — authenticated historical proof input.
pub type HistoricalProof {
  key: ByteArray,
  location: ByteArray,
  proof: Proof,
  prior_snapshot_digest: ByteArray,
}

/// S0-D05 — lineage thread state.
pub type LineageState {
  lineage_id: ByteArray,
  registration_slot: Int,
  predecessor_id: Option<ByteArray>,
  event_root: ByteArray,
  occupancy_root: ByteArray,
  cursor: CursorState,
  closed: Bool,
}

/// Lineage skeleton actions: genesis, successor, or close marker.
pub type LineageAction {
  Genesis { identity: ByteArray }
  Successor { predecessor: ByteArray }
  Close { marker: ByteArray }
}

/// S0-D06 — maintenance escrow state.
pub type EscrowState {
  funder: ByteArray,
  premium: Int,
  remaining_value: Int,
  notice_start: Option<Int>,
}

/// Escrow skeleton actions: witnessed service or notice close.
pub type EscrowAction {
  Service
  NoticeClose
}

/// S0-D07 — four-dimensional consumer policy.
pub type CursorPolicy {
  accepted_keys: ByteArray,
  accepted_states: List<KeriState>,
  minimum_grade: EvidenceGrade,
  maximum_age: Int,
}
