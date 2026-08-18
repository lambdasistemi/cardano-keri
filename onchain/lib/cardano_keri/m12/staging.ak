//// S0 staging / proof-token surface (S0-F06 / S0-M06).

use aiken/collection/dict
use aiken/collection/list
use cardano/assets.{AssetName, PolicyId, tokens}
use cardano/transaction.{Transaction}
use cardano_keri/m12/record.{bind_parsed_event}
use cardano_keri/m12/types.{ParsedEvent}

/// S0-F06 — bind parsed bytes then require token identity and output.
pub fn validate_staging_token(
  raw_event: ByteArray,
  claimed: ParsedEvent,
  policy_id: PolicyId,
  tx: Transaction,
) -> Bool {
  when bind_parsed_event(raw_event, claimed) is {
    None -> False
    Some(parsed) -> {
      let name: AssetName = parsed.said
      and {
        dict.to_pairs(tokens(tx.mint, policy_id)) == [Pair(name, 1)],
        list.any(
          tx.outputs,
          fn(out) {
            dict.to_pairs(tokens(out.value, policy_id)) == [Pair(name, 1)]
          },
        ),
      }
    }
  }
}
