//// Finite-table interpretation for the consumer predicate: test interpretation,
//// not the registry byte layout.
////
//// The four Lean interpretation inputs (hash, code, key map, datum decoder) are
//// read from explicit finite tables. A lookup that finds no entry, or more than
//// one, is an interpretation failure (`fail`), never a verdict: the Lean's
//// `Interpretation` is total, so an incomplete table is not an interpretation.

use aiken/collection/list
use cardano/assets.{AssetName}
use cardano/transaction.{Output}
use cardano_keri/consumer.{
  Context, DecodedDatum, Environment, Params, Preimage, PublishedRelease,
  consumable_holding,
}

pub type Tables {
  keys: List<(Int, ByteArray)>,
  codes: List<(Preimage, ByteArray)>,
  hashes: List<(ByteArray, AssetName)>,
  datums: List<(PublishedRelease, Data, DecodedDatum)>,
}

/// One consumer question: the tables, what the consumer fixes, and the
/// candidate holding.
pub type Query {
  tables: Tables,
  context: Context,
  environment: Environment,
  params: Params,
  now: Int,
  output: Output,
}

fn lookup(entries: List<(k, v)>, key: k) -> v {
  when list.filter(entries, fn(entry) { entry.1st == key }) is {
    [entry] -> entry.2nd
    _ -> fail @"incomplete-or-ambiguous-interpretation"
  }
}

pub fn table_hash(t: Tables) -> fn(ByteArray) -> AssetName {
  fn(code) { lookup(t.hashes, code) }
}

pub fn table_code(t: Tables) -> fn(Preimage) -> ByteArray {
  fn(preimage) { lookup(t.codes, preimage) }
}

pub fn table_key_of(t: Tables) -> fn(Int) -> ByteArray {
  fn(aid) { lookup(t.keys, aid) }
}

pub fn table_decode(
  t: Tables,
) -> fn(PublishedRelease, Data) -> Option<DecodedDatum> {
  fn(release, raw) {
    when
      list.filter(
        t.datums,
        fn(entry) {
          let (r, d, _) = entry
          r == release && d == raw
        },
      )
    is {
      [] -> None
      [(_, _, decoded)] -> Some(decoded)
      _ -> fail @"incomplete-or-ambiguous-interpretation"
    }
  }
}

/// The predicate over the query's own tables.
pub fn verdict(q: Query) -> Bool {
  consumable_holding(
    table_hash(q.tables),
    table_code(q.tables),
    table_key_of(q.tables),
    table_decode(q.tables),
    q.context,
    q.environment,
    q.params,
    q.now,
    q.output,
  )
}
