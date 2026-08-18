//// S0 lineage genesis / successor / close surface (S0-F04 / S0-M04).
////
//// Derives inherited/final event and occupancy roots and closed/cursor
//// flags on every accepting transition.

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/interval
use aiken/primitive/bytearray
use cardano/transaction.{InlineDatum, Input, OutputReference, Transaction}
use cardano_keri/m12/types.{
  Close, CursorState, Established, Genesis, LineageAction, LineageState,
  Successor, Unwitnessed,
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

fn genesis_cursor(identity: ByteArray, now: Int) -> CursorState {
  CursorState {
    keys_digest: identity,
    keri_state: Established,
    grade: Unwitnessed,
    last_moved_slot: now,
    registration_slot: now,
  }
}

/// S0-F04 — purpose/time plus derived roots and flags.
pub fn validate_lineage_transition(
  old: Option<LineageState>,
  action: LineageAction,
  tx: Transaction,
) -> Option<LineageState> {
  let Transaction { inputs, reference_inputs, validity_range, .. } = tx
  when validity_range.lower_bound.bound_type is {
    interval.Finite(now) ->
      when action is {
        Genesis { identity } ->
          when old is {
            Some(_) -> None
            None ->
              if binds_identity(inputs, identity) {
                Some(
                  LineageState {
                    lineage_id: identity,
                    registration_slot: now,
                    predecessor_id: None,
                    event_root: blake2b_256(identity),
                    occupancy_root: blake2b_256(
                      identity |> bytearray.concat(#"01"),
                    ),
                    cursor: genesis_cursor(identity, now),
                    closed: False,
                  },
                )
              } else {
                None
              }
          }
        Successor { predecessor } ->
          when old is {
            None -> None
            Some(state) ->
              if and {
                !state.closed,
                predecessor_present(reference_inputs, predecessor),
                now >= state.registration_slot,
                when state.predecessor_id is {
                  None -> True
                  Some(expected) -> expected == predecessor
                },
              } {
                Some(
                  LineageState {
                    lineage_id: state.lineage_id,
                    registration_slot: state.registration_slot,
                    predecessor_id: Some(predecessor),
                    event_root: blake2b_256(
                      state.event_root |> bytearray.concat(predecessor),
                    ),
                    occupancy_root: state.occupancy_root,
                    cursor: state.cursor,
                    closed: False,
                  },
                )
              } else {
                None
              }
          }
        Close { marker } ->
          when old is {
            None -> None
            Some(state) ->
              if and {
                !state.closed,
                now >= state.registration_slot,
                blake2b_256(state.lineage_id) == marker,
              } {
                Some(
                  LineageState {
                    lineage_id: state.lineage_id,
                    registration_slot: state.registration_slot,
                    predecessor_id: state.predecessor_id,
                    event_root: state.event_root,
                    occupancy_root: state.occupancy_root,
                    cursor: state.cursor,
                    closed: True,
                  },
                )
              } else {
                None
              }
          }
      }
    _ -> None
  }
}
