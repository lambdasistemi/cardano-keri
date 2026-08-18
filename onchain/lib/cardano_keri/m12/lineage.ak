//// S0 lineage genesis / successor / close surface (S0-F04 / S0-M04).

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/primitive/bytearray
use cardano/transaction.{InlineDatum, Input, OutputReference, Transaction}
use cardano_keri/m12/types.{
  Close, Genesis, LineageAction, LineageState, Successor,
}

fn predecessor_present(
  reference_inputs: List<Input>,
  predecessor: ByteArray,
) -> Bool {
  list.any(
    reference_inputs,
    fn(input) {
      when input.output.datum is {
        InlineDatum(datum) ->
          if datum is prior: LineageState {
            prior.lineage_id == predecessor && !prior.closed
          } else {
            False
          }
        _ -> False
      }
    },
  )
}

fn binds_identity(inputs: List<Input>, identity: ByteArray) -> Bool {
  list.any(
    inputs,
    fn(input) {
      let OutputReference { transaction_id, output_index } = input.output_reference
      blake2b_256(
        transaction_id
          |> bytearray.concat(bytearray.from_int_big_endian(output_index, 2)),
      ) == identity
    },
  )
}

/// S0-F04 — inspect purpose/time and the named lineage branches.
pub fn validate_lineage_transition(
  old: Option<LineageState>,
  action: LineageAction,
  tx: Transaction,
) -> Bool {
  let Transaction { inputs, reference_inputs, validity_range, .. } = tx
  when validity_range.lower_bound.bound_type is {
    interval.Finite(now) ->
      when action is {
        Genesis { identity } ->
          when old is {
            Some(_) -> False
            None -> binds_identity(inputs, identity)
          }
        Successor { predecessor } ->
          when old is {
            None -> False
            Some(state) -> and {
                !state.closed,
                predecessor_present(reference_inputs, predecessor),
                now >= state.registration_slot,
                when state.predecessor_id is {
                  None -> True
                  Some(expected) -> expected == predecessor
                },
              }
          }
        Close { marker } ->
          when old is {
            None -> False
            Some(state) -> and {
                !state.closed,
                now >= state.registration_slot,
                blake2b_256(state.lineage_id) == marker,
              }
          }
      }
    _ -> False
  }
}
