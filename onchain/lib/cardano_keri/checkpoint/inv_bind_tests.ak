//// #291 INV-BIND decoder proofs (`aiken check -m inv_bind`).
////
//// Parity over committed vector events, counted framing mutation of
//// the four establishment shapes, and the GREEN adversarial census
//// that lives in `inv_bind_adversarial_tests.ak`.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/checkpoint/advance_vectors as adv
use cardano_keri/checkpoint/event_decoder.{
  DecodeErr, DecodeOk, EventVariant, VariantDip, VariantDrt, VariantIcp,
  VariantRot, decode_establishment_event,
}
use cardano_keri/checkpoint/registration_vectors as vec

fn decode_ok(raw: ByteArray) -> Bool {
  when decode_establishment_event(raw) is {
    DecodeOk(_) -> True
    DecodeErr(_) -> False
  }
}

fn variant_of(raw: ByteArray, expected: EventVariant) -> Bool {
  when decode_establishment_event(raw) is {
    DecodeOk(ev) -> ev.variant == expected && bytearray.length(ev.said) == 44
    DecodeErr(_) -> False
  }
}

fn flip_at(raw: ByteArray, i: Int) -> ByteArray {
  let b = bytearray.at(raw, i)
  let nb = if b == 255 { 254 } else { b + 1 }
  bytearray.concat(
    bytearray.concat(bytearray.take(raw, i), bytearray.push(#"", nb)),
    bytearray.drop(raw, i + 1),
  )
}

fn count_accepts(raw: ByteArray, positions: List<Int>) -> Int {
  list.foldl(
    positions,
    0,
    fn(i, acc) { if decode_ok(flip_at(raw, i)) { acc + 1 } else { acc } },
  )
}

const icp_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a2245445078775f59484631647a6f41356e554f7165386b335835637957477a575647314359486c4f494e303261222c2269223a2245445078775f59484631647a6f41356e554f7165386b335835637957477a575647314359486c4f494e303261222c2273223a2230222c226b74223a2232222c226b223a5b2244414c4b695f51783562627357456b57617a75586c51533144714f364879644455394a3473434c323674416d222c2244504d737432746c677242487a7a52343832436245676675793744595f654b7277487672614d724c4e4c4e4d225d2c226e74223a2232222c226e223a5b2245467342585f746570315a635947513079554436355f43336e5a4d5053726d4738524e6735614a734d484657222c22454a4933723834355a666f6e5673696657615f4a65346d3537702d765a6f53493453507648396b48764a4144225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

const dip_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303135665f222c2274223a22646970222c2264223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c2269223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c2273223a2230222c226b74223a2231222c226b223a5b224447646a706e3445757831304b4e69587456325265466f4d705276526366585f4c754d613155393436775f6a225d2c226e74223a2231222c226e223a5b2245494f79556f567a3059576a5159446963705f66366836586b31645775493330446675576d6a4e6f746f6d32225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d2c226469223a22454a53383557374b534d744a616d5746525669756234794e6872743673506431644b6b6c534959434e325345227d"

const rot_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22726f74222c2264223a22454e4f4e785a54744c725239725f5a4863386d4a4248572d345f39655230464d35327942474e30726879754f222c2269223a22454c385a4a4f486730756b365a775a576c6855785965536b51444e38774974515a344b4835335430522d422d222c2273223a2231222c2270223a22454c385a4a4f486730756b365a775a576c6855785965536b51444e38774974515a344b4835335430522d422d222c226b74223a2231222c226b223a5b224450486f4f4732317a326c6c5830355a777552776f4d7153466f6c6f4f7a2d544a44536b435857515f636a6c225d2c226e74223a2231222c226e223a5b224546596d6f79657566375f7176524f4e4e655267326978596a763674434368425264767247774e6867526749225d2c226274223a2231222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d"

const drt_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303136305f222c2274223a22647274222c2264223a224546424c4364534f4654665a472d4c36744c30726f74704c6a3831664d734e5a73373639543364697a513655222c2269223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c2273223a2231222c2270223a22454d6d452d5651726f335a476b6b78326e4871647a664c6b4e384a6853516d4d55367a48537070525455474c222c226b74223a2231222c226b223a5b2244462d4d564e46374c7a5f5274756e41334f6577747347416d4b62766e70757853516f327a6347317263704f225d2c226e74223a2231222c226e223a5b22454a4a386d4e794e35736b71313965466932454c695865476b63316d474848355737324c36424b5a4167784f225d2c226274223a2230222c226272223a5b5d2c226261223a5b5d2c2261223a5b5d7d"

const icp_pos: List<Int> =
  [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 33, 34, 35, 36, 37, 38, 39, 84, 85, 86,
    87, 88, 89, 90, 135, 136, 137, 138, 139, 140, 141, 143, 144, 145, 146, 147,
    148, 149, 150, 152, 153, 154, 155, 156, 157, 158, 159, 204, 205, 206, 251,
    252, 253, 254, 255, 256, 257, 258, 259, 261, 262, 263, 264, 265, 266, 267,
    268, 313, 314, 315, 360, 361, 362, 363, 364, 365, 366, 367, 368, 370, 371,
    372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386,
    387, 388, 389, 390, 391, 392,
  ]

const dip_pos: List<Int> =
  [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 33, 34, 35, 36, 37, 38, 39, 84, 85, 86,
    87, 88, 89, 90, 135, 136, 137, 138, 139, 140, 141, 143, 144, 145, 146, 147,
    148, 149, 150, 152, 153, 154, 155, 156, 157, 158, 159, 204, 205, 206, 207,
    208, 209, 210, 211, 212, 214, 215, 216, 217, 218, 219, 220, 221, 266, 267,
    268, 269, 270, 271, 272, 273, 274, 276, 277, 278, 279, 280, 281, 282, 283,
    284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298,
    299, 300, 301, 302, 303, 304, 349, 350,
  ]

const rot_pos: List<Int> =
  [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 33, 34, 35, 36, 37, 38, 39, 84, 85, 86,
    87, 88, 89, 90, 135, 136, 137, 138, 139, 140, 141, 143, 144, 145, 146, 147,
    148, 149, 194, 195, 196, 197, 198, 199, 200, 201, 203, 204, 205, 206, 207,
    208, 209, 210, 255, 256, 257, 258, 259, 260, 261, 262, 263, 265, 266, 267,
    268, 269, 270, 271, 272, 317, 318, 319, 320, 321, 322, 323, 324, 325, 327,
    328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342,
    343, 344, 345, 346, 347, 348, 349, 350, 351,
  ]

const drt_pos: List<Int> = rot_pos

test inv_bind_parity_census() {
  let rows =
    [
      variant_of(vec.pos_2key_evidence.event_bytes, VariantIcp),
      variant_of(vec.pos_witnessed_evidence.event_bytes, VariantIcp),
      variant_of(vec.pos_weighted_evidence.event_bytes, VariantIcp),
      variant_of(vec.pos_7key_evidence.event_bytes, VariantIcp),
      variant_of(vec.e1_dip_evidence.event_bytes, VariantDip),
      variant_of(vec.e1_drt_evidence.event_bytes, VariantDrt),
      variant_of(adv.pos_adv_wit_2key_evidence.event_bytes, VariantRot),
      variant_of(adv.pos_adv_wit_7key_evidence.event_bytes, VariantRot),
      variant_of(adv.pos_adv_keep_evidence.event_bytes, VariantRot),
      variant_of(adv.pos_adv_downgrade_evidence.event_bytes, VariantRot),
      variant_of(icp_bytes, VariantIcp),
      variant_of(dip_bytes, VariantDip),
      variant_of(rot_bytes, VariantRot),
      variant_of(drt_bytes, VariantDrt),
    ]
  let events = list.length(rows)
  let mismatches = list.length(list.filter(rows, fn(ok) { !ok }))
  expect events >= 10
  expect mismatches == 0
  trace @"INV-BIND-PARITY events=14 mismatches=0" True
}

test inv_bind_mutation_census() {
  let icp_n = list.length(icp_pos)
  let dip_n = list.length(dip_pos)
  let rot_n = list.length(rot_pos)
  let drt_n = list.length(drt_pos)
  let positions = icp_n + dip_n + rot_n + drt_n
  let accepted =
    count_accepts(icp_bytes, icp_pos) + count_accepts(dip_bytes, dip_pos) + count_accepts(
      rot_bytes,
      rot_pos,
    ) + count_accepts(drt_bytes, drt_pos)
  expect positions == 496
  expect accepted == 0
  trace
    @"INV-BIND-MUTATION shapes=4 framing_positions=496 mutants=496 accepted=0"
    True
}
