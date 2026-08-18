//// S0 consumer predicate library (S0-F07 / S0-M07).
////
//// No always-true default: every policy dimension can independently deny.

use aiken/collection/list
use cardano_keri/m12/types.{
  CursorPolicy, CursorState, EvidenceGrade, FullyWitnessed, PartiallyWitnessed,
  Unwitnessed,
}

fn grade_rank(grade: EvidenceGrade) -> Int {
  when grade is {
    Unwitnessed -> 0
    PartiallyWitnessed -> 1
    FullyWitnessed -> 2
  }
}

/// S0-F07 — keys, KERI state, evidence grade, and freshness together.
pub fn cursor_policy_allows(
  policy: CursorPolicy,
  cursor: CursorState,
  now: Int,
) -> Bool {
  and {
    cursor.keys_digest == policy.accepted_keys,
    list.has(policy.accepted_states, cursor.keri_state),
    grade_rank(cursor.grade) >= grade_rank(policy.minimum_grade),
    now >= cursor.last_moved_slot,
    now - cursor.last_moved_slot <= policy.maximum_age,
  }
}
