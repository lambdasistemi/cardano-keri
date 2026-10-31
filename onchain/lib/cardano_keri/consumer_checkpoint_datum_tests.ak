//// Properties of the consumer's checkpoint datum decoder (#343), over
//// generated variations of the Lean version 2 layout
//// (`CardanoKeri.CheckpointDatum`; the `aiken/fuzz` module is not a
//// dependency, so the variations are explicit tables). The vectors module
//// carries one decoder test and one consumer test per Lean row; this module
//// carries what no single row shows:
////
////   - the decoder never fails: a shape it does not accept is `None`, never an
////     abort (a relying contract iterating reference inputs must skip an
////     unrelated output's datum, not fail on it);
////   - each field the decoder reads: valid values decode to the Lean's
////     `DecodedDatum`, and every other kind of node in that position is
////     refused, including inside the key material;
////   - the release does not select the layout.
////
//// Theorems exhibited (`lean/CardanoKeri/CheckpointDatumGoals.lean`):
//// `decodeData_complete` and `decode_written` (valid values decode),
//// `decode_accepts_only_written`, `version_one_refused`,
//// `wrong_version_refused`, `version_arity_refused`, `unknown_form_refused`,
//// `live_arity_refused`, `pending_arity_refused`, `live_fields_typed`,
//// `pending_fields_typed` (the near-miss tables), `decode_release_independent`.

use aiken/builtin.{b_data, constr_data, i_data, list_data, map_data}
use aiken/collection/list
use cardano_keri/consumer.{
  DecodedDatum, Hash, Live, Present, PublishedRelease, TerminationPending,
}
use cardano_keri/consumer_checkpoint_datum_check.{context_for, decode_data}
use cardano_keri/consumer_identity_bytes.{pack}

// ---------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------

fn release() -> PublishedRelease {
  context_for(0).release
}

fn decoded(raw: Data) -> Option<DecodedDatum> {
  decode_data(release(), raw)
}

fn bool_data(b: Bool) -> Data {
  if b {
    constr_data(1, [])
  } else {
    constr_data(0, [])
  }
}

/// A 32-byte key, all `seed`.
fn key32(seed: Int) -> Data {
  b_data(bytes_of(seed, 32))
}

/// `n` bytes, all `seed`.
fn bytes_of(seed: Int, n: Int) -> ByteArray {
  if n == 0 {
    #""
  } else {
    builtin.cons_bytearray(seed % 256, bytes_of(seed, n - 1))
  }
}

fn unweighted(m: Int) -> Data {
  constr_data(0, [i_data(m)])
}

fn weight(n: Int, d: Int) -> Data {
  constr_data(0, [i_data(n), i_data(d)])
}

fn weighted(clauses: List<List<Data>>) -> Data {
  constr_data(1, [list_data(list.map(clauses, list_data))])
}

/// The six key material fields of the Lean `KeyMaterial`.
fn key_fields() -> List<Data> {
  [
    list_data([key32(1)]),
    unweighted(1),
    list_data([key32(2)]),
    unweighted(1),
    list_data([]),
    i_data(0),
  ]
}

fn keys() -> Data {
  constr_data(0, key_fields())
}

fn keys_with(fields: List<Data>) -> Data {
  constr_data(0, fields)
}

fn aid_bytes() -> ByteArray {
  #"454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550"
}

fn refund_bytes() -> ByteArray {
  #"0104070a0d101316191c1f2225282b2e3134373a3d404346494c4f52"
}

/// The eight fields of a live datum, in the Lean order.
fn live_fields_of(
  aid: ByteArray,
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
  k: Data,
) -> List<Data> {
  [
    b_data(aid),
    i_data(sn),
    i_data(epoch),
    bool_data(poisoned),
    bool_data(frozen),
    i_data(born_at),
    b_data(refund_to),
    k,
  ]
}

fn good_live() -> List<Data> {
  live_fields_of(aid_bytes(), 3, 1, False, True, 9, refund_bytes(), keys())
}

fn live(fields: List<Data>) -> Data {
  constr_data(1, [constr_data(0, fields)])
}

fn good_pending() -> List<Data> {
  [b_data(aid_bytes()), i_data(4), i_data(2), keys()]
}

fn pending(fields: List<Data>) -> Data {
  constr_data(1, [constr_data(1, fields)])
}

fn set_at(xs: List<Data>, i: Int, d: Data) -> List<Data> {
  when xs is {
    [] -> []
    [x, ..rest] ->
      if i == 0 {
        [d, ..rest]
      } else {
        [x, ..set_at(rest, i - 1, d)]
      }
  }
}

fn indices(n: Int) -> List<Int> {
  list.range(0, n - 1)
}

// ---------------------------------------------------------------------
// The decoder never fails
// ---------------------------------------------------------------------

fn arbitrary_data() -> List<Data> {
  [
    i_data(0),
    i_data(-1),
    b_data(#""),
    b_data(aid_bytes()),
    list_data([]),
    list_data(good_live()),
    map_data([]),
    map_data([Pair(i_data(1), i_data(2))]),
    constr_data(0, []),
    constr_data(1, []),
    constr_data(2, []),
    constr_data(7, [i_data(1)]),
    constr_data(1, [i_data(1)]),
    constr_data(1, [b_data(#"")]),
    constr_data(1, [list_data([])]),
    constr_data(1, [constr_data(2, [])]),
    constr_data(1, [constr_data(0, [])]),
    constr_data(1, [constr_data(1, [])]),
    constr_data(1, [constr_data(0, good_live()), constr_data(0, good_live())]),
    constr_data(0, [constr_data(0, good_live())]),
    constr_data(1, [constr_data(0, [constr_data(1, [constr_data(1, [])])])]),
    constr_data(1, [constr_data(1, good_live())]),
    constr_data(1, [constr_data(0, good_pending())]),
  ]
}

/// `decode_accepts_only_written`, `unknown_form_refused`, ...: whatever the
/// shape, the answer is `None` and nothing aborts.
test decoder_is_total_on_arbitrary_data() {
  list.all(arbitrary_data(), fn(d) { decoded(d) == None })
}

// ---------------------------------------------------------------------
// Version and form (version_one_refused, wrong_version_refused,
// version_arity_refused, unknown_form_refused)
// ---------------------------------------------------------------------

test version_one_is_refused() {
  decoded(constr_data(0, [constr_data(0, good_live())])) == None && decoded(
    constr_data(0, good_live()),
  ) == None
}

test other_versions_are_refused() {
  list.all(
    [2, 3, 6, 7, 127, 128, 1000],
    fn(version) {
      decoded(constr_data(version, [constr_data(0, good_live())])) == None
    },
  )
}

test version_arity_is_checked() {
  decoded(constr_data(1, [])) == None && decoded(
    constr_data(1, [constr_data(0, good_live()), constr_data(0, good_live())]),
  ) == None
}

test unknown_forms_are_refused() {
  list.all(
    [2, 3, 4, 100],
    fn(form) {
      decoded(constr_data(1, [constr_data(form, good_live())])) == None
    },
  )
}

// ---------------------------------------------------------------------
// Arity (live_arity_refused, pending_arity_refused)
// ---------------------------------------------------------------------

test live_arity_is_checked() {
  list.all(
    [0, 1, 2, 3, 4, 5, 6, 7, 9, 10],
    fn(n) {
      let fields = list.concat(good_live(), good_live()) |> list.take(n)
      n == 8 || decoded(live(fields)) == None
    },
  )
}

test pending_arity_is_checked() {
  list.all(
    [0, 1, 2, 3, 5, 6, 8],
    fn(n) {
      let fields = list.concat(good_pending(), good_pending()) |> list.take(n)
      decoded(pending(fields)) == None
    },
  )
}

// ---------------------------------------------------------------------
// Each field, valid: decodeData_complete, decode_written
// ---------------------------------------------------------------------

fn numbers() -> List<Int> {
  [
    0, 1, 23, 24, 255, 256, 65535, 65536, 4294967296, 9223372036854775807,
    18446744073709551615, 18446744073709551616, 18446744073709551621,
    1180591620717411303424,
  ]
}

fn byte_strings() -> List<ByteArray> {
  [
    #"",
    #"00",
    #"0000",
    #"ff",
    #"00ff00",
    aid_bytes(),
    refund_bytes(),
    bytes_of(7, 63),
    bytes_of(7, 64),
    bytes_of(7, 65),
    bytes_of(0, 70),
    bytes_of(255, 130),
  ]
}

fn live_state(
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
) -> Live {
  Live {
    sn,
    epoch,
    poisoned,
    frozen,
    born_at,
    refund_to: pack(refund_to),
    pool: 0,
  }
}

test live_sn_epoch_born_at_decode_for_every_number() {
  list.all(
    numbers(),
    fn(n) {
      decoded(
        live(live_fields_of(aid_bytes(), n, 0, False, False, 0, #"", keys())),
      ) == Some(
        DecodedDatum {
          aid: pack(aid_bytes()),
          state: Present(live_state(n, 0, False, False, 0, #"")),
        },
      ) && decoded(
        live(live_fields_of(aid_bytes(), 0, n, False, False, 0, #"", keys())),
      ) == Some(
        DecodedDatum {
          aid: pack(aid_bytes()),
          state: Present(live_state(0, n, False, False, 0, #"")),
        },
      ) && decoded(
        live(live_fields_of(aid_bytes(), 0, 0, False, False, n, #"", keys())),
      ) == Some(
        DecodedDatum {
          aid: pack(aid_bytes()),
          state: Present(live_state(0, 0, False, False, n, #"")),
        },
      )
    },
  )
}

test live_booleans_decode_in_every_combination() {
  list.all(
    [(False, False), (False, True), (True, False), (True, True)],
    fn(flags) {
      let (p, f) = flags
      decoded(live(live_fields_of(aid_bytes(), 1, 2, p, f, 3, #"", keys()))) == Some(
        DecodedDatum {
          aid: pack(aid_bytes()),
          state: Present(live_state(1, 2, p, f, 3, #"")),
        },
      )
    },
  )
}

test live_aid_and_refund_decode_for_every_byte_string() {
  list.all(
    byte_strings(),
    fn(bs) {
      decoded(live(live_fields_of(bs, 1, 2, False, False, 3, bs, keys()))) == Some(
        DecodedDatum {
          aid: pack(bs),
          state: Present(live_state(1, 2, False, False, 3, bs)),
        },
      )
    },
  )
}

test pending_fields_decode_for_every_value() {
  list.all(
    numbers(),
    fn(n) {
      list.all(
        byte_strings(),
        fn(bs) {
          decoded(pending([b_data(bs), i_data(n), i_data(n + 1), keys()])) == Some(
            DecodedDatum {
              aid: pack(bs),
              state: TerminationPending(Hash { epoch: n + 1, sn: n }),
            },
          )
        },
      )
    },
  )
}

fn valid_key_materials() -> List<Data> {
  [
    keys(),
    keys_with(
      [
        list_data([]),
        unweighted(0),
        list_data([]),
        unweighted(-3),
        list_data([]),
        i_data(-1),
      ],
    ),
    keys_with(
      [
        list_data([key32(1), key32(2), key32(3)]),
        weighted([[weight(1, 2), weight(1, 2)], [weight(1, 1)]]),
        list_data([key32(4)]),
        weighted([[weight(-1, 0)]]),
        list_data([key32(5), key32(6)]),
        i_data(18446744073709551616),
      ],
    ),
    keys_with(
      [
        list_data([b_data(#"")]),
        weighted([]),
        list_data([b_data(#""), b_data(#"00")]),
        weighted([[]]),
        list_data([key32(9)]),
        i_data(2),
      ],
    ),
  ]
}

/// The key material is read for its shape, never for its values: every shape
/// the Lean accepts decodes to the same state.
test valid_key_materials_decode() {
  list.all(
    valid_key_materials(),
    fn(k) {
      decoded(live(live_fields_of(aid_bytes(), 3, 1, False, True, 9, #"", k))) == Some(
        DecodedDatum {
          aid: pack(aid_bytes()),
          state: Present(live_state(3, 1, False, True, 9, #"")),
        },
      ) && decoded(pending([b_data(aid_bytes()), i_data(4), i_data(2), k])) == Some(
        DecodedDatum {
          aid: pack(aid_bytes()),
          state: TerminationPending(Hash { epoch: 2, sn: 4 }),
        },
      )
    },
  )
}

// ---------------------------------------------------------------------
// Each field, refused: live_fields_typed, pending_fields_typed
// ---------------------------------------------------------------------

/// Nodes that are not a byte string.
fn not_bytes() -> List<Data> {
  [
    i_data(0),
    i_data(-1),
    list_data([]),
    list_data([b_data(#"")]),
    map_data([]),
    constr_data(0, []),
    constr_data(0, [b_data(#"")]),
  ]
}

/// Nodes that are not a non-negative integer.
fn not_nat() -> List<Data> {
  [
    i_data(-1),
    i_data(-18446744073709551616),
    i_data(-18446744073709551617),
    b_data(#""),
    b_data(#"00"),
    list_data([]),
    list_data([i_data(1)]),
    map_data([]),
    constr_data(0, []),
    constr_data(0, [i_data(1)]),
  ]
}

/// Nodes that are not a Boolean.
fn not_bool() -> List<Data> {
  [
    i_data(0),
    i_data(1),
    b_data(#""),
    list_data([]),
    map_data([]),
    constr_data(2, []),
    constr_data(0, [i_data(0)]),
    constr_data(1, [i_data(0)]),
    constr_data(1, [constr_data(0, [])]),
  ]
}

/// Nodes that are not a key material.
fn not_keys() -> List<Data> {
  [
    i_data(0),
    b_data(#""),
    list_data([]),
    list_data(key_fields()),
    map_data([]),
    constr_data(1, key_fields()),
    constr_data(0, []),
    constr_data(0, list.take(key_fields(), 5)),
    constr_data(0, list.concat(key_fields(), [i_data(0)])),
  ]
}

fn live_replacements(i: Int) -> List<Data> {
  when i is {
    0 -> not_bytes()
    1 | 2 | 5 -> not_nat()
    3 | 4 -> not_bool()
    6 -> not_bytes()
    _ -> not_keys()
  }
}

fn pending_replacements(i: Int) -> List<Data> {
  when i is {
    0 -> not_bytes()
    1 | 2 -> not_nat()
    _ -> not_keys()
  }
}

test live_fields_are_typed() {
  list.all(
    indices(8),
    fn(i) {
      list.all(
        live_replacements(i),
        fn(r) { decoded(live(set_at(good_live(), i, r))) == None },
      )
    },
  )
}

test pending_fields_are_typed() {
  list.all(
    indices(4),
    fn(i) {
      list.all(
        pending_replacements(i),
        fn(r) { decoded(pending(set_at(good_pending(), i, r))) == None },
      )
    },
  )
}

/// Nodes that are not a list of byte strings.
fn not_bytes_list() -> List<Data> {
  [
    i_data(0),
    b_data(#""),
    map_data([]),
    constr_data(0, []),
    list_data([i_data(1)]),
    list_data([key32(1), i_data(1)]),
    list_data([list_data([])]),
    list_data([constr_data(0, [b_data(#"")])]),
  ]
}

/// Nodes that are not a threshold.
fn not_threshold() -> List<Data> {
  [
    i_data(1),
    b_data(#""),
    list_data([]),
    map_data([]),
    constr_data(2, [i_data(1)]),
    constr_data(0, []),
    constr_data(0, [b_data(#"")]),
    constr_data(0, [i_data(1), i_data(1)]),
    constr_data(1, []),
    constr_data(1, [i_data(1)]),
    constr_data(1, [list_data([i_data(1)])]),
    constr_data(1, [list_data([list_data([constr_data(0, [i_data(1)])])])]),
    constr_data(
      1,
      [list_data([list_data([constr_data(0, [i_data(1), b_data(#"")])])])],
    ),
    constr_data(
      1,
      [
        list_data(
          [list_data([constr_data(0, [i_data(1), i_data(2), i_data(3)])])],
        ),
      ],
    ),
    constr_data(
      1,
      [list_data([list_data([constr_data(1, [i_data(1), i_data(2)])])])],
    ),
    constr_data(1, [list_data([list_data([i_data(1)])]), i_data(0)]),
  ]
}

/// Nodes that are not an integer (`toad`).
fn not_int() -> List<Data> {
  [
    b_data(#""),
    list_data([]),
    list_data([i_data(0)]),
    map_data([]),
    constr_data(0, []),
    constr_data(0, [i_data(0)]),
  ]
}

fn key_replacements(i: Int) -> List<Data> {
  when i is {
    0 | 2 | 4 -> not_bytes_list()
    1 | 3 -> not_threshold()
    _ -> not_int()
  }
}

/// Every component of the key material is read for its shape, in a live and
/// in a pending-termination datum.
test key_material_components_are_typed() {
  list.all(
    indices(6),
    fn(i) {
      list.all(
        key_replacements(i),
        fn(r) {
          let k = keys_with(set_at(key_fields(), i, r))
          decoded(set_at(good_live(), 7, k) |> live) == None && decoded(
            set_at(good_pending(), 3, k) |> pending,
          ) == None
        },
      )
    },
  )
}

// ---------------------------------------------------------------------
// decode_release_independent
// ---------------------------------------------------------------------

test the_release_does_not_select_the_layout() {
  let other = PublishedRelease {
    application_policy: #"",
    application_credential: release().application_credential,
    state_program: #"01",
    state_policy: #"02",
  }
  list.all(
    [live(good_live()), pending(good_pending()), constr_data(0, good_live())],
    fn(d) { decode_data(release(), d) == decode_data(other, d) },
  )
}
