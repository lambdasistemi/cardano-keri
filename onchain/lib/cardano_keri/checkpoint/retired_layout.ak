//// The retired checkpoint layout, for the tests that show it is refused: the
//// nine-field key state under outer constructor index 0. Nothing reads or
//// writes it any more; it exists only to build a datum a reader must refuse.

use aiken/builtin
use cardano_keri/checkpoint/datum.{KeyStateView}

pub fn retired_layout(record: KeyStateView) -> Data {
  let inner: Data = record
  builtin.constr_data(0, [inner])
}
