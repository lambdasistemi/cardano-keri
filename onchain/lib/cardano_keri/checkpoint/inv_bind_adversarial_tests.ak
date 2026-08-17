//// #291 INV-BIND adversarial proofs (`aiken check -m inv_bind_adversarial`).
////
//// Eight rows. Each asserts the current offset binder rejects a crafted
//// event. Production binders are unchanged, so the rows stay RED.
//// Grind bytes are the sealed #134 witnesses. Malformed rows transform
//// committed `pos_2key` event bytes. Aiken observes `event_binding`
//// only; Haskell verifies exact-byte signatures.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/checkpoint/advance.{
  AdvanceEventValid, AdvanceEvidence, event_binding as advance_event_binding,
}
use cardano_keri/checkpoint/datum.{CheckpointDatumV1}
use cardano_keri/checkpoint/registration.{
  RegistrationEvidence, RegistrationValid, event_binding,
}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/threshold.{Unweighted}

const grind_dip_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303135665f222c2274223a22646970222c2264223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c2269223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c2273223a2230222c226b74223a2231222c226b223a5b224447646a706e3445757831304b4e69587456325265466f4d705276526366585f4c754d613155393436775f6a225d2c226e74223a2231222c226e223a5b2245494f79556f567a3059576a5159446963705f66366836586b31645775493330446675576d6a4e6f746f6d32225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d2c226469223a22454a53383557374b534d744a616d5746525669756234794e6872743673506431644b6b6c534959434e325345227d"

const grind_drt_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22647274222c2264223a224546424c4364534f4654665a472d4c36744c30726f74704c6a3831664d734e5a73373639543364697a513655222c2269223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c2273223a2231222c2270223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c226b74223a2231222c226b223a5b2244462d4d564e46374c7a5f5274756e41334f6577747347416d4b62766e70757853516f327a6347317263704f225d2c226e74223a2231222c226e223a5b22454a4a386d4e794e35736b71313965466932454c695865476b63316d474848355737324c36424b5a4167784f225d2c226274223a2230222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d"

const reordered_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2264223a2245445078775f59484631647a6f41356e554f7165386b335835637957477a575647314359486c4f494e303261222c2269223a2245445078775f59484631647a6f41356e554f7165386b335835637957477a575647314359486c4f494e303261222c2274223a22696370222c2273223a2230222c226b74223a2232222c226b223a5b2244414c4b695f51783562627357456b57617a75586c51533144714f364879644455394a3473434c323674416d222c2244504d737432746c677242487a7a52343832436245676675793744595f654b7277487672614d724c4e4c4e4d225d2c226e74223a2232222c226e223a5b2245467342585f746570315a635947513079554436355f43336e5a4d5053726d4738524e6735614a734d484657222c22454a4933723834355a666f6e5673696657615f4a65346d3537702d765a6f53493453507648396b48764a4144225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

const grind_dip_aid: ByteArray =
  #"c984f9542ba37646924c769c7a9dcdf2e437c26149098c53acc74a9a514d418b"

const grind_dip_k: ByteArray =
  #"6763a67e04bb1d7428d897b55d91785a0ca51bd171f5ff2ee31ad54f78eb0fe3"

const grind_dip_n: ByteArray =
  #"83b2528573d185a34180e2729fdfea1e97935756b88df40dfb969a3368b689b6"

const grind_drt_k: ByteArray =
  #"5f8c54d17b2f3fd1b6e9c0dce7b0b6c18098a6ef9e9bb1490a36cdc1b5adca4e"

const grind_drt_n: ByteArray =
  #"927c98dc8de6c92ad7d7858b610b89778691cd661871f95bbd8be81299020c4e"

const grind_dip_sig: ByteArray =
  #"1f28284c5dd3220aaf3aa023edfc81fa743c63dc5a9e20ccc6264f7908afb75dbfb9673f7b2af740edd4bd4a9ba38bd086f3185b682c3e66e3fd726e43d01806"

const grind_drt_sig: ByteArray =
  #"969b16c44c91d90ad5190afc117083e4bea5010b066cc97135f0f2051389d521b8dffe4c4e6753d525f48b9b02e6552b6b749b8245b061a3e14f045a04c95c01"

fn grind_dip_datum() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: grind_dip_aid,
    cur_keys: [grind_dip_k],
    cur_threshold: Unweighted(1),
    next_keys: [grind_dip_n],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 0,
    native_sn: 0,
  }
}

fn grind_drt_datum() -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: grind_dip_aid,
    cur_keys: [grind_drt_k],
    cur_threshold: Unweighted(1),
    next_keys: [grind_drt_n],
    next_threshold: Unweighted(1),
    witnesses: [],
    toad: 0,
    seq: 1,
    native_sn: 1,
  }
}

fn grind_dip_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    event_bytes: grind_dip_bytes,
    off_t: 237,
    off_i: 91,
    off_s: 142,
    off_k: [160],
    off_kt: 151,
    off_n: [222],
    off_nt: 213,
    off_b: [],
    off_bt: 275,
    ctrl_sigs: [(0, grind_dip_sig)],
    wit_receipts: [],
  }
}

fn grind_drt_evidence() -> AdvanceEvidence {
  AdvanceEvidence {
    event_bytes: grind_drt_bytes,
    off_t: 59,
    off_i: 91,
    off_s: 142,
    off_k: [211],
    off_kt: 202,
    off_n: [273],
    off_nt: 264,
    off_br: [],
    off_ba: [],
    off_bt: 326,
    wit_cut: [],
    wit_add: [],
    ctrl_sigs: [(0, grind_drt_sig)],
    wit_receipts: [],
  }
}

fn with_bytes(
  e: RegistrationEvidence,
  bytes: ByteArray,
) -> RegistrationEvidence {
  RegistrationEvidence { ..e, event_bytes: bytes }
}

fn patch_version(bytes: ByteArray, digits: ByteArray) -> ByteArray {
  bytearray.concat(
    bytearray.concat(bytearray.take(bytes, 16), digits),
    bytearray.drop(bytes, 22),
  )
}

fn append_before_end(bytes: ByteArray, extra: ByteArray) -> ByteArray {
  let n = bytearray.length(bytes)
  bytearray.concat(
    bytearray.concat(bytearray.take(bytes, n - 1), extra),
    bytearray.drop(bytes, n - 1),
  )
}

fn replace_at(bytes: ByteArray, off: Int, byte: ByteArray) -> ByteArray {
  bytearray.concat(
    bytearray.concat(bytearray.take(bytes, off), byte),
    bytearray.drop(bytes, off + 1),
  )
}

fn version_size_bytes() -> ByteArray {
  patch_version(vec.pos_2key_evidence.event_bytes, "000188")
}

fn trailing_bytes() -> ByteArray {
  bytearray.concat(vec.pos_2key_evidence.event_bytes, "!")
}

fn duplicate_bytes() -> ByteArray {
  patch_version(
    append_before_end(vec.pos_2key_evidence.event_bytes, ",\"s\":\"1\""),
    "000191",
  )
}

fn delimiter_bytes() -> ByteArray {
  replace_at(vec.pos_2key_evidence.event_bytes, 34, ";")
}

fn unknown_bytes() -> ByteArray {
  patch_version(
    append_before_end(vec.pos_2key_evidence.event_bytes, ",\"zz\":\"0\""),
    "000192",
  )
}

fn reordered_evidence() -> RegistrationEvidence {
  RegistrationEvidence {
    ..vec.pos_2key_evidence,
    event_bytes: reordered_bytes,
    off_t: 132,
    off_i: 81,
  }
}

fn row_reg_accepts(e: RegistrationEvidence) -> Bool {
  event_binding(vec.pos_2key_datum, e) == RegistrationValid
}

fn grind_dip_accepts() -> Bool {
  event_binding(grind_dip_datum(), grind_dip_evidence()) == RegistrationValid
}

fn grind_drt_accepts() -> Bool {
  advance_event_binding(grind_drt_datum(), grind_drt_evidence()) == AdvanceEventValid
}

fn count_legacy_accepts() -> Int {
  list.length(
    list.filter(
      [
        grind_dip_accepts(),
        grind_drt_accepts(),
        row_reg_accepts(
          with_bytes(vec.pos_2key_evidence, version_size_bytes()),
        ),
        row_reg_accepts(with_bytes(vec.pos_2key_evidence, trailing_bytes())),
        row_reg_accepts(
          with_bytes(vec.pos_2key_evidence, duplicate_bytes()),
        ),
        row_reg_accepts(reordered_evidence()),
        row_reg_accepts(
          with_bytes(vec.pos_2key_evidence, delimiter_bytes()),
        ),
        row_reg_accepts(with_bytes(vec.pos_2key_evidence, unknown_bytes())),
      ],
      fn(ok) { ok },
    ),
  )
}

test inv_bind_adversarial_census() {
  expect count_legacy_accepts() == 8
  fail @"INV-BIND-CAN-FAIL fixtures=8 legacy_accepts=8 wrong_reason=0"
}

test inv_bind_adversarial_fx291_grind_dip() {
  event_binding(grind_dip_datum(), grind_dip_evidence()) != RegistrationValid
}

test inv_bind_adversarial_fx291_grind_drt() {
  advance_event_binding(grind_drt_datum(), grind_drt_evidence()) != AdvanceEventValid
}

test inv_bind_adversarial_fx291_version_size() {
  event_binding(
    vec.pos_2key_datum,
    with_bytes(vec.pos_2key_evidence, version_size_bytes()),
  ) != RegistrationValid
}

test inv_bind_adversarial_fx291_trailing() {
  event_binding(
    vec.pos_2key_datum,
    with_bytes(vec.pos_2key_evidence, trailing_bytes()),
  ) != RegistrationValid
}

test inv_bind_adversarial_fx291_duplicate() {
  event_binding(
    vec.pos_2key_datum,
    with_bytes(vec.pos_2key_evidence, duplicate_bytes()),
  ) != RegistrationValid
}

test inv_bind_adversarial_fx291_reordered() {
  event_binding(vec.pos_2key_datum, reordered_evidence()) != RegistrationValid
}

test inv_bind_adversarial_fx291_delimiter() {
  event_binding(
    vec.pos_2key_datum,
    with_bytes(vec.pos_2key_evidence, delimiter_bytes()),
  ) != RegistrationValid
}

test inv_bind_adversarial_fx291_unknown() {
  event_binding(
    vec.pos_2key_datum,
    with_bytes(vec.pos_2key_evidence, unknown_bytes()),
  ) != RegistrationValid
}
