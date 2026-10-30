//// Clause properties of the consumer predicate (#343), table-driven over
//// generated variations of the corpus anchor row (the `aiken/fuzz` module is
//// not a dependency). Each test names the Lean theorem of
//// `lean/CardanoKeri/ConsumerGoals.lean` it mirrors (CI01-CI16) and runs the
//// accepting case beside its refusals, so that dropping or weakening a clause
//// turns at least one test red.
////
//// Interpretation: test interpretation, not the registry byte layout.

use aiken/builtin
use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/address.{Address, Credential, Script, VerificationKey}
use cardano/assets.{Value}
use cardano/transaction.{
  DatumHash, InlineDatum, NoDatum, Output, OutputReference,
}
use cardano_keri/consumer.{
  Absent, Context, Convicted, DecodedDatum, Environment, Hash, Live, Params,
  Present, PublishedRelease, State, TerminationPending, Token,
  authenticated_context, consumable_holding, consumable_state, registry_asset,
  representative_asset,
}
use cardano_keri/consumer_corpus_vectors as vec
use cardano_keri/consumer_table_interpretation.{
  Query, Tables, table_code, table_hash, table_key_of, verdict,
}
use cardano_keri/consumer_test_interpretation as test_interpretation

// ---------------------------------------------------------------------
// Variations of the anchor row (born at 2, W = 5, now = 7: maturity is exact)
// ---------------------------------------------------------------------

fn base() -> Query {
  vec.row_positive_anchor()
}

fn with_environment(q: Query, e: Environment) -> Query {
  Query { ..q, environment: e }
}

fn with_output(q: Query, o: Output) -> Query {
  Query { ..q, output: o }
}

fn with_value(q: Query, v: Value) -> Query {
  with_output(q, Output { ..q.output, value: v })
}

fn with_datum(q: Query, d: transaction.Datum) -> Query {
  with_output(q, Output { ..q.output, datum: d })
}

fn with_credential(q: Query, c: Credential) -> Query {
  let a = q.output.address
  with_output(
    q,
    Output { ..q.output, address: Address { ..a, payment_credential: c } },
  )
}

/// The decoder answers `d` for the raw datum the anchor output carries.
fn with_decoded(q: Query, d: DecodedDatum) -> Query {
  Query {
    ..q,
    tables: Tables {
      ..q.tables,
      datums: [(q.context.release, builtin.i_data(711), d)],
    },
  }
}

fn with_state(q: Query, s: State) -> Query {
  with_decoded(q, DecodedDatum { aid: q.context.aid, state: s })
}

fn with_now(q: Query, now: Int) -> Query {
  Query { ..q, now }
}

fn with_w(q: Query, w: Int) -> Query {
  Query { ..q, params: Params { ..q.params, w } }
}

/// The representative token the anchor row's own output holds (read from the
/// corpus row, not from the predicate).
fn anchor_token(q: Query) -> Token {
  expect [_lovelace, (policy, name, 1)] = assets.flatten(q.output.value)
  Token { policy, name }
}

fn value_of(t: Token, n: Int) -> Value {
  if n == 0 {
    assets.from_lovelace(14)
  } else {
    assets.from_lovelace(14) |> assets.add(t.policy, t.name, n)
  }
}

fn live(born_at: Int) -> State {
  Present(
    Live {
      sn: 0,
      epoch: 0,
      poisoned: False,
      frozen: False,
      born_at,
      refund_to: 42,
      pool: 5,
    },
  )
}

fn live_with(poisoned: Bool, frozen: Bool, born_at: Int) -> State {
  Present(
    Live { sn: 0, epoch: 0, poisoned, frozen, born_at, refund_to: 42, pool: 5 },
  )
}

fn refuses_all(qs: List<Query>) -> Bool {
  list.all(qs, fn(q) { !verdict(q) })
}

fn flip_byte(b: ByteArray) -> ByteArray {
  builtin.append_bytearray(#"01", b)
}

// ---------------------------------------------------------------------
// CI01 / CI02: acceptance is exactly the conjunction of the clauses
// ---------------------------------------------------------------------

fn conjunction_variant(
  network: Bool,
  release: Bool,
  credential: Bool,
  quantity: Bool,
  aid: Bool,
  state: Bool,
) -> Query {
  let q = base()
  let q = if network {
    q
  } else {
    with_environment(
      q,
      Environment { ..q.environment, network: q.context.network + 1 },
    )
  }
  let q = if release {
    q
  } else {
    with_environment(q, Environment { ..q.environment, release: None })
  }
  let q = if credential {
    q
  } else {
    with_credential(q, Script(#"aa"))
  }
  let q = if quantity {
    q
  } else {
    with_value(q, value_of(anchor_token(q), 2))
  }
  let q = if aid {
    q
  } else {
    with_decoded(q, DecodedDatum { aid: q.context.aid + 1, state: live(2) })
  }
  if state {
    q
  } else {
    with_state(q, live_with(False, True, 2))
  }
}

test ci01_ci02_acceptance_is_exactly_the_conjunction() {
  let bools = [True, False]
  list.all(
    bools,
    fn(n) {
      list.all(
        bools,
        fn(r) {
          list.all(
            bools,
            fn(c) {
              list.all(
                bools,
                fn(qty) {
                  list.all(
                    bools,
                    fn(a) {
                      list.all(
                        bools,
                        fn(s) {
                          verdict(conjunction_variant(n, r, c, qty, a, s)) == (
                            n && r && c && qty && a && s
                          )
                        },
                      )
                    },
                  )
                },
              )
            },
          )
        },
      )
    },
  )
}

// ---------------------------------------------------------------------
// CI03: for a realizing output the verdict is the old lifecycle predicate
// ---------------------------------------------------------------------

/// Each state with the Lean's `consumableState` verdict at W = 5, now = 7,
/// stated by hand: present, unfrozen, unpoisoned and bornAt + 5 <= 7.
fn lifecycle_states() -> List<(State, Bool)> {
  [
    (Absent, False),
    (Convicted, False),
    (TerminationPending(Hash { epoch: 1, sn: 3 }), False),
    (live_with(False, False, 2), True),
    (live_with(False, False, 1), True),
    (live_with(False, False, 0), True),
    (live_with(False, False, 3), False),
    (live_with(True, False, 2), False),
    (live_with(False, True, 2), False),
    (live_with(True, True, 2), False),
    (live_with(False, False, 7), False),
    (live_with(False, False, 8), False),
  ]
}

test ci03_realized_holding_agrees_with_the_lifecycle_predicate() {
  let q = base()
  list.all(
    lifecycle_states(),
    fn(entry) {
      let (s, eligible) = entry
      let held = when s is {
        Absent -> False
        Convicted -> False
        _ -> True
      }
      // the realizing output holds the token exactly when the state has one
      let realized = if held {
        with_state(q, s)
      } else {
        with_value(with_state(q, s), value_of(anchor_token(q), 0))
      }
      verdict(realized) == ( held && eligible ) && consumable_state(
        q.params,
        q.now,
        s,
      ) == eligible
    },
  )
}

// ---------------------------------------------------------------------
// CI04: wrong network
// ---------------------------------------------------------------------

test ci04_wrong_network_refused() {
  let q = base()
  verdict(q) && refuses_all(
    [
      with_environment(
        q,
        Environment { ..q.environment, network: q.context.network + 1 },
      ),
      with_environment(q, Environment { ..q.environment, network: 764824073 }),
    ],
  )
}

// ---------------------------------------------------------------------
// CI05: unresolved or different complete release
// ---------------------------------------------------------------------

test ci05_wrong_or_unknown_release_refused() {
  let q = base()
  let r = q.context.release
  verdict(q) && refuses_all(
    [
      with_environment(q, Environment { ..q.environment, release: None }),
      with_environment(
        q,
        Environment {
          ..q.environment,
          release: Some(
            PublishedRelease {
              ..r,
              application_policy: flip_byte(r.application_policy),
            },
          ),
        },
      ),
      with_environment(
        q,
        Environment {
          ..q.environment,
          release: Some(
            PublishedRelease {
              ..r,
              application_credential: Script(
                flip_byte(
                  when r.application_credential is {
                    Script(h) -> h
                    VerificationKey(h) -> h
                  },
                ),
              ),
            },
          ),
        },
      ),
      with_environment(
        q,
        Environment {
          ..q.environment,
          release: Some(
            PublishedRelease { ..r, state_program: flip_byte(r.state_program) },
          ),
        },
      ),
      with_environment(
        q,
        Environment {
          ..q.environment,
          release: Some(
            PublishedRelease { ..r, state_policy: flip_byte(r.state_policy) },
          ),
        },
      ),
    ],
  )
}

// ---------------------------------------------------------------------
// CI06: wrong application credential, even with the token and a live datum
// ---------------------------------------------------------------------

test ci06_wrong_credential_refused() {
  let q = base()
  let good = q.context.release.application_credential
  let bytes = when good is {
    Script(h) -> h
    VerificationKey(h) -> h
  }
  verdict(q) && verdict(with_credential(q, good)) && refuses_all(
    [
      with_credential(q, Script(flip_byte(bytes))),
      // same hash, other credential kind
      with_credential(q, VerificationKey(bytes)),
    ],
  )
}

// ---------------------------------------------------------------------
// CI07: total quantity of the representative asset must be one
// ---------------------------------------------------------------------

test ci07_wrong_quantity_refused() {
  let q = base()
  let t = anchor_token(q)
  verdict(q) && refuses_all(
    [
      with_value(q, value_of(t, 0)),
      with_value(q, value_of(t, 2)),
      with_value(q, value_of(t, 3)),
      // two entries of one, summed by the ledger value
      with_value(
        q,
        assets.from_lovelace(14)
          |> assets.add(t.policy, t.name, 1)
          |> assets.add(t.policy, t.name, 1),
      ),
    ],
  )
}

// ---------------------------------------------------------------------
// CI08: another singleton asset, wrong policy or wrong name
// ---------------------------------------------------------------------

test ci08_wrong_asset_refused() {
  let q = base()
  let t = anchor_token(q)
  let other_policy = assets.from_lovelace(14)
    |> assets.add(flip_byte(t.policy), t.name, 1)
  let other_name = assets.from_lovelace(14)
    |> assets.add(t.policy, flip_byte(t.name), 1)
  let coexisting = assets.from_lovelace(14)
    |> assets.add(t.policy, t.name, 1)
    |> assets.add(flip_byte(t.policy), flip_byte(t.name), 5)
  verdict(q) && refuses_all(
    [
      with_value(q, other_policy),
      with_value(q, other_name),
      with_value(q, assets.from_lovelace(14)),
    ],
  ) && verdict(with_value(q, coexisting))
}

// ---------------------------------------------------------------------
// CI09: non-application, absent or rejected datum
// ---------------------------------------------------------------------

test ci09_malformed_datum_refused() {
  let q = base()
  verdict(q) && refuses_all(
    [
      with_datum(q, NoDatum),
      with_datum(
        q,
        DatumHash(
          #"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
        ),
      ),
      // an inline datum the decoder rejects
      with_datum(q, InlineDatum(builtin.i_data(999))),
      with_datum(q, InlineDatum(builtin.constr_data(1, [builtin.i_data(0)]))),
    ],
  )
}

// ---------------------------------------------------------------------
// CI10: the decoded datum is for another AID
// ---------------------------------------------------------------------

test ci10_wrong_datum_aid_refused() {
  let q = base()
  verdict(q) && refuses_all(
    [
      with_decoded(q, DecodedDatum { aid: q.context.aid + 1, state: live(2) }),
      with_decoded(q, DecodedDatum { aid: 0, state: live(2) }),
    ],
  )
}

// ---------------------------------------------------------------------
// CI11: any state the lifecycle predicate refuses
// ---------------------------------------------------------------------

test ci11_ineligible_state_refused() {
  let q = base()
  verdict(q) && refuses_all(
    [
      with_state(q, Absent),
      with_state(q, Convicted),
      with_state(q, live_with(False, True, 2)),
      with_state(q, live_with(True, False, 2)),
      with_state(q, live_with(True, True, 2)),
      // one slot short of maturity
      with_now(q, 6),
      with_state(q, live_with(False, False, 3)),
    ],
  ) && verdict(with_now(q, 8)) && verdict(with_now(q, 7)) && verdict(
    with_w(with_now(with_state(q, live_with(False, False, 7)), 7), 0),
  ) && !verdict(
    with_w(with_now(with_state(q, live_with(False, False, 7)), 6), 0),
  )
}

// ---------------------------------------------------------------------
// CI12: pending termination, at any time
// ---------------------------------------------------------------------

test ci12_retained_custody_refused() {
  let q = base()
  let h = Hash { epoch: 0, sn: 0 }
  verdict(q) && list.all(
    [0, 1, 7, 100, 1000000],
    fn(now) {
      refuses_all(
        [
          with_now(with_state(q, TerminationPending(h)), now),
          with_w(with_now(with_state(q, TerminationPending(h)), now), 0),
        ],
      )
    },
  )
}

// ---------------------------------------------------------------------
// The Lean formulas for the registry and representative assets
// ---------------------------------------------------------------------

test registry_and_representative_formulas_follow_the_tables() {
  let q = base()
  let hash = table_hash(q.tables)
  let code = table_code(q.tables)
  expect [(_, state_name), ..] = q.tables.hashes
  let registry = registry_asset(hash, code, q.context)
  registry == Token { policy: q.context.release.state_policy, name: state_name } && representative_asset(
    hash,
    code,
    table_key_of(q.tables),
    q.context,
  ) == anchor_token(q)
}

// ---------------------------------------------------------------------
// CI13 - CI16: names separate keys, registries and seeds, so a rival
// registry's token never selects the consumer's context
// ---------------------------------------------------------------------

fn decode_from(
  datums: List<(Data, DecodedDatum)>,
) -> fn(PublishedRelease, Data) -> Option<DecodedDatum> {
  fn(_release, raw) {
    when list.filter(datums, fn(entry) { entry.1st == raw }) is {
      [entry] -> Some(entry.2nd)
      _ -> None
    }
  }
}

fn representative_of(c: Context) -> Token {
  representative_asset(
    test_interpretation.hash,
    test_interpretation.code,
    test_interpretation.key_of,
    c,
  )
}

fn seed(tx: ByteArray, index: Int) -> OutputReference {
  OutputReference { transaction_id: tx, output_index: index }
}

/// The Lean formula over the documented test layout, written out
/// independently of the predicate and of the shared module's functions.
fn expected_representative(c: Context) -> Token {
  let registry_name = blake2b_256(
    bytearray.concat(
      #"00",
      bytearray.concat(
        c.seed.transaction_id,
        bytearray.from_int_big_endian(c.seed.output_index, 8),
      ),
    ),
  )
  Token {
    policy: c.release.state_policy,
    name: blake2b_256(
      bytearray.concat(
        #"01",
        bytearray.concat(
          c.release.state_policy,
          bytearray.concat(
            registry_name,
            bytearray.from_int_big_endian(c.aid, 8),
          ),
        ),
      ),
    ),
  }
}

fn fixed_context() -> Context {
  Context {
    ..base().context,
    seed: seed(
      #"0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728",
      3,
    ),
  }
}

fn holding_of(t: Token, n: Int) -> Output {
  let o = base().output
  Output { ..o, value: value_of(t, n) }
}

fn accepts_with(c: Context, o: Output) -> Bool {
  let decoded = DecodedDatum { aid: c.aid, state: live(2) }
  let q = base()
  consumable_holding(
    test_interpretation.hash,
    test_interpretation.code,
    test_interpretation.key_of,
    decode_from([(builtin.i_data(711), decoded)]),
    c,
    q.environment,
    q.params,
    q.now,
    o,
  )
}

test ci13_ci14_ci15_names_separate_keys_registries_and_seeds() {
  let c = fixed_context()
  let other_aid = Context { ..c, aid: c.aid + 1 }
  let other_registry = Context {
    ..c,
    release: PublishedRelease {
      ..c.release,
      state_policy: flip_byte(c.release.state_policy),
    },
  }
  let other_seed_index = Context { ..c, seed: seed(c.seed.transaction_id, 4) }
  let other_seed_tx = Context {
    ..c,
    seed: seed(flip_byte(c.seed.transaction_id), 3),
  }
  representative_of(c) == expected_representative(c) && registry_asset(
    test_interpretation.hash,
    test_interpretation.code,
    c,
  ) != registry_asset(
    test_interpretation.hash,
    test_interpretation.code,
    other_seed_index,
  ) && list.all(
    [other_aid, other_registry, other_seed_index, other_seed_tx],
    fn(d) {
      representative_of(c) != representative_of(d) && representative_of(d) == expected_representative(
        d,
      )
    },
  )
}

test ci16_rival_seed_token_refused() {
  let c = fixed_context()
  let rival = Context { ..c, seed: seed(c.seed.transaction_id, 4) }
  let own = expected_representative(c)
  let theirs = expected_representative(rival)
  accepts_with(c, holding_of(own, 1)) && list.all(
    [1, 2, 5],
    fn(n) { !accepts_with(c, holding_of(theirs, n)) },
  ) && accepts_with(rival, holding_of(theirs, 1)) && !accepts_with(
    rival,
    holding_of(own, 1),
  )
}

// ---------------------------------------------------------------------
// The environment is an argument of the predicate, never read from the output
// ---------------------------------------------------------------------

test authenticated_context_needs_network_and_complete_release() {
  let q = base()
  authenticated_context(q.context, q.environment) && !authenticated_context(
    q.context,
    Environment { ..q.environment, release: None },
  ) && !authenticated_context(
    q.context,
    Environment { ..q.environment, network: q.context.network + 1 },
  )
}
