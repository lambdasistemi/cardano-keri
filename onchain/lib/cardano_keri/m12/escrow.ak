//// S0 maintenance-escrow service and notice-close (S0-F05 / S0-M05).

use aiken/collection/list
use aiken/interval
use cardano/assets.{lovelace_of}
use cardano/transaction.{Transaction}
use cardano_keri/m12/types.{
  EscrowAction, EscrowState, EvidenceGrade, FullyWitnessed, NoticeClose, Service,
}

/// S0-F05 — premium/residue checks over value and time context.
pub fn validate_escrow_transition(
  old: EscrowState,
  action: EscrowAction,
  grade: EvidenceGrade,
  tx: Transaction,
) -> Bool {
  let Transaction { outputs, validity_range, .. } = tx
  when validity_range.lower_bound.bound_type is {
    interval.Finite(now) ->
      when action is {
        Service -> and {
            grade == FullyWitnessed,
            old.remaining_value >= old.premium,
            list.any(
              outputs,
              fn(out) {
                lovelace_of(out.value) >= old.remaining_value - old.premium
              },
            ),
          }
        NoticeClose ->
          when old.notice_start is {
            None -> False
            Some(start) -> and {
                now >= start,
                list.any(
                  outputs,
                  fn(out) { lovelace_of(out.value) >= old.remaining_value },
                ),
              }
          }
      }
    _ -> False
  }
}
