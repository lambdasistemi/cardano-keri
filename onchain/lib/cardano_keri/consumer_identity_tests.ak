//// Properties of the concrete identity bytes (#343), over the Lean vectors
//// and over generated variations (the `aiken/fuzz` module is not a
//// dependency, so the variations are explicit tables). The vectors module
//// carries one test per claim and vector; this module carries what no single
//// vector shows: the carrier laws, every serialisation width, the binding of
//// each committed field, and the predicate itself running on the concrete
//// bytes.
////
//// The datum decoder is the Lean's (`consumer_checkpoint_datum.decode`).

use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address, Script}
use cardano/assets.{from_lovelace}
use cardano/transaction.{InlineDatum, Output, OutputReference}
use cardano_keri/consumer.{
  Context, Environment, Params, PublishedRelease, StatePreimage, Token,
  consumable_holding, registry_asset, representative_asset,
}
use cardano_keri/consumer_checkpoint_datum as decoder
use cardano_keri/consumer_checkpoint_datum_check.{live_datum}
use cardano_keri/consumer_identity_bytes as bytes
use cardano_keri/consumer_identity_check.{IdentityVector, context_of}
use cardano_keri/consumer_identity_vectors.{vectors}

// ---------------------------------------------------------------------
// The vectors themselves
// ---------------------------------------------------------------------

test there_are_eight_vectors_with_distinct_names() {
  let vs = vectors()
  list.length(vs) == 8 && list.all(
    vs,
    fn(a) {
      list.all(
        vs,
        fn(b) {
          a == b || a.active_name != b.active_name && a.state_name != b.active_name
        },
      )
    },
  )
}

// ---------------------------------------------------------------------
// The byte carrier (Lean BL1, BL2, BL3, BL4)
// ---------------------------------------------------------------------

test carrier_known_values() {
  bytes.pack(#"") == 0 && bytes.pack(#"00") == 1 && bytes.pack(#"ff") == 256 && bytes.pack(
    #"0000",
  ) == 257 && bytes.pack(#"0100") == 2 + 256 && bytes.unpack(0) == #"" && bytes.unpack(
    1,
  ) == #"00" && bytes.unpack(256) == #"ff" && bytes.unpack(257) == #"0000"
}

fn byte_strings() -> List<ByteArray> {
  [
    #"", #"00", #"0000", #"000000", #"01", #"ff", #"ffff", #"00ff00", #"ff00ff",
    #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
    #"00000000000000000000000000000000000000000000000000000000000000000000000000",
    #"45884a9da5e1b6d8a3e1c0bb2e1f6f7c8d9a0b1c2d3e4f5061728394a5b6c7d8e9f0a1b2c3d4e5f60718293a4b5c6d7e8f90",
  ]
}

fn numbers() -> List<Int> {
  [
    0, 1, 2, 255, 256, 257, 258, 65535, 65536, 65537, 16777216, 4294967296,
    18446744073709551616,
    123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890,
  ]
}

test unpack_after_pack_is_the_byte_string() {
  list.all(byte_strings(), fn(bs) { bytes.unpack(bytes.pack(bs)) == bs })
}

test pack_after_unpack_is_the_number() {
  list.all(numbers(), fn(n) { bytes.pack(bytes.unpack(n)) == n })
}

test the_carrier_separates_byte_strings_and_numbers() {
  let packed = list.map(byte_strings(), fn(bs) { (bs, bytes.pack(bs)) })
  let unpacked = list.map(numbers(), fn(n) { (n, bytes.unpack(n)) })
  list.all(
    packed,
    fn(a) { list.all(packed, fn(b) { a.1st == b.1st == ( a.2nd == b.2nd ) }) },
  ) && list.all(
    unpacked,
    fn(m) { list.all(unpacked, fn(n) { m.1st == n.1st == ( m.2nd == n.2nd ) }) },
  )
}

// ---------------------------------------------------------------------
// Serialisation widths of the output index (an independent restatement of
// the Lean `head`, written here and not read from the module under test)
// ---------------------------------------------------------------------

fn head_zero(n: Int) -> ByteArray {
  if n < 24 {
    bytearray.from_int_big_endian(n, 1)
  } else if n < 256 {
    bytearray.concat(#"18", bytearray.from_int_big_endian(n, 1))
  } else if n < 65536 {
    bytearray.concat(#"19", bytearray.from_int_big_endian(n, 2))
  } else if n < 4294967296 {
    bytearray.concat(#"1a", bytearray.from_int_big_endian(n, 4))
  } else {
    bytearray.concat(#"1b", bytearray.from_int_big_endian(n, 8))
  }
}

fn indexes() -> List<Int> {
  [
    0, 1, 23, 24, 25, 255, 256, 257, 65535, 65536, 4294967295, 4294967296,
    18446744073709551615,
  ]
}

test state_preimage_follows_every_integer_width() {
  let tx = #"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
  list.all(
    indexes(),
    fn(i) {
      bytes.code(
        StatePreimage {
          seed: OutputReference { transaction_id: tx, output_index: i },
        },
      ) == bytearray.concat(
        #"d8799fd8799f5820",
        bytearray.concat(tx, bytearray.concat(head_zero(i), #"ffff")),
      )
    },
  )
}

test state_preimage_of_a_wide_index_is_a_tagged_number() {
  let tx = #"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
  bytes.code(
    StatePreimage {
      seed: OutputReference {
        transaction_id: tx,
        output_index: 18446744073709551616,
      },
    },
  ) == bytearray.concat(
    #"d8799fd8799f5820",
    bytearray.concat(tx, #"c249010000000000000000ffff"),
  )
}

// ---------------------------------------------------------------------
// Each committed field binds the names
// ---------------------------------------------------------------------

fn first_byte_changed(b: ByteArray) -> ByteArray {
  bytearray.concat(
    bytearray.from_int_big_endian(( bytearray.at(b, 0) + 1 ) % 256, 1),
    bytearray.drop(b, 1),
  )
}

fn last_byte_changed(b: ByteArray) -> ByteArray {
  let n = bytearray.length(b)
  bytearray.concat(
    bytearray.take(b, n - 1),
    bytearray.from_int_big_endian(( bytearray.at(b, n - 1) + 1 ) % 256, 1),
  )
}

fn named(c: Context) -> (ByteArray, ByteArray) {
  let registry = registry_asset(bytes.hash, bytes.code, c)
  let representative = representative_asset(
    bytes.hash,
    bytes.code,
    bytes.key_of,
    c,
  )
  (registry.name, representative.name)
}

/// The base context varied in every committed field: seed transaction id,
/// seed output index, state policy and AID.
fn grid(base: Context) -> List<Context> {
  let txs = [
    base.seed.transaction_id,
    first_byte_changed(base.seed.transaction_id),
    last_byte_changed(base.seed.transaction_id),
  ]
  let indexes = [base.seed.output_index, 1, 24, 256]
  let policies = [
    base.release.state_policy,
    last_byte_changed(base.release.state_policy),
  ]
  let aids = [base.aid, base.aid + 1, base.aid - 1]
  list.flat_map(
    txs,
    fn(tx) {
      list.flat_map(
        indexes,
        fn(index) {
          list.flat_map(
            policies,
            fn(policy) {
              list.map(
                aids,
                fn(aid) {
                  Context {
                    ..base,
                    release: PublishedRelease {
                      ..base.release,
                      state_policy: policy,
                    },
                    seed: OutputReference {
                      transaction_id: tx,
                      output_index: index,
                    },
                    aid,
                  }
                },
              )
            },
          )
        },
      )
    },
  )
}

fn first_vector() -> IdentityVector {
  expect [v, ..] = vectors()
  v
}

test committed_fields_bind_the_active_name() {
  let contexts = grid(context_of(first_vector()))
  let names = list.map(contexts, fn(c) { named(c).2nd })
  list.length(contexts) == 72 && list.all(
    names,
    fn(a) { list.length(list.filter(names, fn(b) { a == b })) == 1 },
  )
}

test the_registry_name_binds_the_seed_alone() {
  let seeds = list.map(
    grid(context_of(first_vector())),
    fn(c) { (c.seed, named(c).1st) },
  )
  list.all(
    seeds,
    fn(a) { list.all(seeds, fn(b) { a.1st == b.1st == ( a.2nd == b.2nd ) }) },
  )
}

// ---------------------------------------------------------------------
// The predicate runs on the concrete bytes
// ---------------------------------------------------------------------

fn holding(t: Token, quantity: Int, aid: Int) -> Output {
  let datum: Data = live_datum(aid, 2)
  Output {
    address: Address {
      payment_credential: Script(
        #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      stake_credential: None,
    },
    value: from_lovelace(3000000) |> assets.add(t.policy, t.name, quantity),
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

/// The predicate over the concrete bytes and the Lean decoder,
/// for the holding as the context's own AID would carry it.
fn accepts(c: Context, t: Token, quantity: Int) -> Bool {
  consumable_holding(
    bytes.hash,
    bytes.code,
    bytes.key_of,
    decoder.decode,
    c,
    Environment { network: c.network, release: Some(c.release) },
    Params { d: 3, b: 2, p: 1, w: 1 },
    7,
    holding(t, quantity, c.aid),
  )
}

test a_holding_named_by_the_concrete_bytes_is_accepted_and_no_rival_is() {
  list.all(
    vectors(),
    fn(v) {
      accepts(context_of(v), v.asset, 1) && list.all(
        vectors(),
        fn(w) { v == w || !accepts(context_of(v), w.asset, 1) },
      )
    },
  )
}

test a_second_copy_of_the_concrete_asset_is_refused() {
  list.all(
    vectors(),
    fn(v) {
      accepts(context_of(v), v.asset, 1) && !accepts(context_of(v), v.asset, 2)
    },
  )
}
