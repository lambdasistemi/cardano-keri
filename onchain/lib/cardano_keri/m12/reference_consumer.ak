//// S0 reference cursor consumer (S0-F08 / S0-M09).

use aiken/collection/dict
use aiken/collection/list
use aiken/interval
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{InlineDatum, Input, Transaction}
use cardano_keri/m12/consumer_predicates.{cursor_policy_allows}
use cardano_keri/m12/types.{CursorPolicy, CursorState}

fn cursor_from_reference(
  reference_inputs: List<Input>,
  expected_lineage: PolicyId,
) -> Option<CursorState> {
  when
    list.find(
      reference_inputs,
      fn(input) {
        when dict.to_pairs(tokens(input.output.value, expected_lineage)) is {
          [Pair(_, qty)] -> qty > 0
          _ -> False
        }
      },
    )
  is {
    None -> None
    Some(input) ->
      when input.output.datum is {
        InlineDatum(datum) ->
          if datum is cursor: CursorState {
            Some(cursor)
          } else {
            None
          }
        _ -> None
      }
  }
}

/// S0-F08 — decode cursor-like reference data, then S0-F07.
pub fn validate_reference_consumer(
  policy: CursorPolicy,
  expected_lineage: PolicyId,
  tx: Transaction,
) -> Bool {
  let Transaction { reference_inputs, validity_range, .. } = tx
  when validity_range.lower_bound.bound_type is {
    interval.Finite(now) ->
      when cursor_from_reference(reference_inputs, expected_lineage) is {
        None -> False
        Some(cursor) -> cursor_policy_allows(policy, cursor, now)
      }
    _ -> False
  }
}
