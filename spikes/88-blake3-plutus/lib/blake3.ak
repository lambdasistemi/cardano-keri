use aiken/builtin
use aiken/primitive/bytearray

const no_flags = #"00000000"

const chunk_start = #"00000001"

const chunk_end_root = #"0000000a"

const chunk_start_end_root = #"0000000b"

const full_block_len = #"00000040"

const zero_word = #"00000000"

const z1 = #"00"

// One spare zero block appended to the input so every 4-byte message-word
// slice is exact; lane packing concatenates raw slices, so short tail
// slices would shift lane positions.
const zeros64 =
  #"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

// The four state rows live as lane-packed integers: lane j occupies bits
// [40*(3-j), 40*(3-j)+40) — 5-byte stride, one spare byte per lane. A lane
// accumulates un-reduced additions up to ~57 * 2^32 < 2^40, so lanes never
// carry into each other and the width-20 big-endian image keeps each exact
// u32 at bytes [5j+1, 5j+5).
//
// iv0..iv3 packed: 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
const iv0123 = 2364741403476308302023339026566427071707346234

// iv4..iv7 packed: 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
const iv4567 = 1807608005053212301540835567932073015297232153

// Big-endian bytes of iv4..iv7, the initial b-row byte shadows.
const ivb4 = #"510e527f"

const ivb5 = #"9b05688c"

const ivb6 = #"1f83d9ab"

const ivb7 = #"5be0cd19"

type Output {
  w0: ByteArray,
  w1: ByteArray,
  w2: ByteArray,
  w3: ByteArray,
  w4: ByteArray,
  w5: ByteArray,
  w6: ByteArray,
  w7: ByteArray,
}

// The hot helpers are function-valued constants deliberately: Aiken
// inlines constants but keeps named functions out of line.
//
// 4-byte word at `offset`; doubles as message-word load and lane
// extraction from a width-20 image.
const lane =
  fn(x: ByteArray, offset: Int) { builtin.slice_bytearray(offset, 4, x) }

// Four 4-byte words joined on a 5-byte stride (19 bytes): p q r s sit at
// offsets 0, 5, 10, 15. appendByteString is ~3 orders of magnitude
// cheaper than an integer conversion, which is what makes lane packing
// pay off.
const gap19 =
  fn(p: ByteArray, q: ByteArray, r: ByteArray, s: ByteArray) {
    builtin.append_bytearray(
      builtin.append_bytearray(p, builtin.append_bytearray(z1, q)),
      builtin.append_bytearray(
        builtin.append_bytearray(z1, r),
        builtin.append_bytearray(z1, s),
      ),
    )
  }

// One conversion packs four big-endian row words: p lands in lane 0,
// s in lane 3.
const pack_be =
  fn(p: ByteArray, q: ByteArray, r: ByteArray, s: ByteArray) {
    builtin.bytearray_to_integer(True, gap19(p, q, r, s))
  }

// Same layout read little-endian for raw message-word slices: the
// LE-read reverses lane order, so s lands in lane 0 and p in lane 3.
const pack_le =
  fn(p: ByteArray, q: ByteArray, r: ByteArray, s: ByteArray) {
    builtin.bytearray_to_integer(False, gap19(p, q, r, s))
  }

// Width-20 xor operand with each word at its lane's u32 position
// [5j+1, 5j+5); the spare bytes xor against un-reduced high bits and are
// sliced off with them.
const gap20 =
  fn(p: ByteArray, q: ByteArray, r: ByteArray, s: ByteArray) {
    builtin.append_bytearray(z1, gap19(p, q, r, s))
  }

// One compression round over lane-packed rows. All four G functions of a
// step run in one integer: one packed addition, one width-20 conversion,
// one width-20 xor, then per-lane slice+rotate and a cheap re-pack.
//
// a: a-rows s0..s3, packed.  bp: b-rows s4..s7, packed, with byte
// shadows b0..b3.  c: c-rows s8..s11, packed; c lanes never move —
// diagonal mixing permutes addend pack order and extraction offsets
// instead.  e0..e3: d-row byte words s12..s15.  m0..m15: raw 4-byte
// little-endian message-word slices.
//
// The continuation receives the next round's state plus the final
// width-20 a/c images, which only the last round reads.
const round =
  fn(
    a: Int,
    bp: Int,
    b0: ByteArray,
    b1: ByteArray,
    b2: ByteArray,
    b3: ByteArray,
    c: Int,
    e0: ByteArray,
    e1: ByteArray,
    e2: ByteArray,
    e3: ByteArray,
    m0: ByteArray,
    m1: ByteArray,
    m2: ByteArray,
    m3: ByteArray,
    m4: ByteArray,
    m5: ByteArray,
    m6: ByteArray,
    m7: ByteArray,
    m8: ByteArray,
    m9: ByteArray,
    m10: ByteArray,
    m11: ByteArray,
    m12: ByteArray,
    m13: ByteArray,
    m14: ByteArray,
    m15: ByteArray,
    then: fn(
      Int,
      Int,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      Int,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
    ) ->
      Output,
  ) {
    // columns: G_j mixes (s_j, s_{4+j}, s_{8+j}, s_{12+j}); every packed
    // integer and every gap20 operand is in lane order j = 0..3.
    let va = a + bp + pack_le(m6, m4, m2, m0)
    let vab = builtin.integer_to_bytearray(True, 20, va)
    let vx = builtin.xor_bytearray(False, vab, gap20(e0, e1, e2, e3))
    let vd0 = builtin.rotate_bytearray(lane(vx, 1), -16)
    let vd1 = builtin.rotate_bytearray(lane(vx, 6), -16)
    let vd2 = builtin.rotate_bytearray(lane(vx, 11), -16)
    let vd3 = builtin.rotate_bytearray(lane(vx, 16), -16)
    let vc = c + pack_be(vd0, vd1, vd2, vd3)
    let vcb = builtin.integer_to_bytearray(True, 20, vc)
    let wx = builtin.xor_bytearray(False, vcb, gap20(b0, b1, b2, b3))
    let vb0 = builtin.rotate_bytearray(lane(wx, 1), -12)
    let vb1 = builtin.rotate_bytearray(lane(wx, 6), -12)
    let vb2 = builtin.rotate_bytearray(lane(wx, 11), -12)
    let vb3 = builtin.rotate_bytearray(lane(wx, 16), -12)
    let ca = va + pack_be(vb0, vb1, vb2, vb3) + pack_le(m7, m5, m3, m1)
    let cab = builtin.integer_to_bytearray(True, 20, ca)
    let cx = builtin.xor_bytearray(False, cab, gap20(vd0, vd1, vd2, vd3))
    let cd0 = builtin.rotate_bytearray(lane(cx, 1), -8)
    let cd1 = builtin.rotate_bytearray(lane(cx, 6), -8)
    let cd2 = builtin.rotate_bytearray(lane(cx, 11), -8)
    let cd3 = builtin.rotate_bytearray(lane(cx, 16), -8)
    let cc = vc + pack_be(cd0, cd1, cd2, cd3)
    let ccb = builtin.integer_to_bytearray(True, 20, cc)
    let dx = builtin.xor_bytearray(False, ccb, gap20(vb0, vb1, vb2, vb3))
    let cb0 = builtin.rotate_bytearray(lane(dx, 1), -7)
    let cb1 = builtin.rotate_bytearray(lane(dx, 6), -7)
    let cb2 = builtin.rotate_bytearray(lane(dx, 11), -7)
    let cb3 = builtin.rotate_bytearray(lane(dx, 16), -7)

    // diagonals: G'_j mixes (s_j, s_{4+(j+1)%4}, s_{8+(j+2)%4},
    // s_{12+(j+3)%4}). a-space values stay in lane order j; c-space
    // addends pack as (G'_2, G'_3, G'_0, G'_1) and c-space extractions
    // for G'_j read lane (j+2)%4, i.e. offsets 11, 16, 1, 6.
    let ha = ca + pack_be(cb1, cb2, cb3, cb0) + pack_le(m14, m12, m10, m8)
    let hab = builtin.integer_to_bytearray(True, 20, ha)
    let hx = builtin.xor_bytearray(False, hab, gap20(cd3, cd0, cd1, cd2))
    let hd0 = builtin.rotate_bytearray(lane(hx, 1), -16)
    let hd1 = builtin.rotate_bytearray(lane(hx, 6), -16)
    let hd2 = builtin.rotate_bytearray(lane(hx, 11), -16)
    let hd3 = builtin.rotate_bytearray(lane(hx, 16), -16)
    let hc = cc + pack_be(hd2, hd3, hd0, hd1)
    let hcb = builtin.integer_to_bytearray(True, 20, hc)
    let ix = builtin.xor_bytearray(False, hcb, gap20(cb3, cb0, cb1, cb2))
    let hb0 = builtin.rotate_bytearray(lane(ix, 11), -12)
    let hb1 = builtin.rotate_bytearray(lane(ix, 16), -12)
    let hb2 = builtin.rotate_bytearray(lane(ix, 1), -12)
    let hb3 = builtin.rotate_bytearray(lane(ix, 6), -12)
    let ja = ha + pack_be(hb0, hb1, hb2, hb3) + pack_le(m15, m13, m11, m9)
    let jab = builtin.integer_to_bytearray(True, 20, ja)
    let jx = builtin.xor_bytearray(False, jab, gap20(hd0, hd1, hd2, hd3))
    let jd0 = builtin.rotate_bytearray(lane(jx, 1), -8)
    let jd1 = builtin.rotate_bytearray(lane(jx, 6), -8)
    let jd2 = builtin.rotate_bytearray(lane(jx, 11), -8)
    let jd3 = builtin.rotate_bytearray(lane(jx, 16), -8)
    let jc = hc + pack_be(jd2, jd3, jd0, jd1)
    let jcb = builtin.integer_to_bytearray(True, 20, jc)
    let kx = builtin.xor_bytearray(False, jcb, gap20(hb2, hb3, hb0, hb1))
    let jb0 = builtin.rotate_bytearray(lane(kx, 11), -7)
    let jb1 = builtin.rotate_bytearray(lane(kx, 16), -7)
    let jb2 = builtin.rotate_bytearray(lane(kx, 1), -7)
    let jb3 = builtin.rotate_bytearray(lane(kx, 6), -7)

    // G'_j writes its b to s_{4+(j+1)%4} and its d to s_{12+(j+3)%4}.
    then(
      ja,
      pack_be(jb3, jb0, jb1, jb2),
      jb3,
      jb0,
      jb1,
      jb2,
      jc,
      jd1,
      jd2,
      jd3,
      jd0,
      jab,
      jcb,
    )
  }

fn permute(
  a: Int,
  bp: Int,
  b0: ByteArray,
  b1: ByteArray,
  b2: ByteArray,
  b3: ByteArray,
  c: Int,
  e0: ByteArray,
  e1: ByteArray,
  e2: ByteArray,
  e3: ByteArray,
  m0: ByteArray,
  m1: ByteArray,
  m2: ByteArray,
  m3: ByteArray,
  m4: ByteArray,
  m5: ByteArray,
  m6: ByteArray,
  m7: ByteArray,
  m8: ByteArray,
  m9: ByteArray,
  m10: ByteArray,
  m11: ByteArray,
  m12: ByteArray,
  m13: ByteArray,
  m14: ByteArray,
  m15: ByteArray,
) -> Output {
  round(
    a,
    bp,
    b0,
    b1,
    b2,
    b3,
    c,
    e0,
    e1,
    e2,
    e3,
    m0,
    m1,
    m2,
    m3,
    m4,
    m5,
    m6,
    m7,
    m8,
    m9,
    m10,
    m11,
    m12,
    m13,
    m14,
    m15,
    fn(a, bp, b0, b1, b2, b3, c, e0, e1, e2, e3, _ab, _cb) {
      round(
        a,
        bp,
        b0,
        b1,
        b2,
        b3,
        c,
        e0,
        e1,
        e2,
        e3,
        m2,
        m6,
        m3,
        m10,
        m7,
        m0,
        m4,
        m13,
        m1,
        m11,
        m12,
        m5,
        m9,
        m14,
        m15,
        m8,
        fn(a, bp, b0, b1, b2, b3, c, e0, e1, e2, e3, _ab, _cb) {
          round(
            a,
            bp,
            b0,
            b1,
            b2,
            b3,
            c,
            e0,
            e1,
            e2,
            e3,
            m3,
            m4,
            m10,
            m12,
            m13,
            m2,
            m7,
            m14,
            m6,
            m5,
            m9,
            m0,
            m11,
            m15,
            m8,
            m1,
            fn(a, bp, b0, b1, b2, b3, c, e0, e1, e2, e3, _ab, _cb) {
              round(
                a,
                bp,
                b0,
                b1,
                b2,
                b3,
                c,
                e0,
                e1,
                e2,
                e3,
                m10,
                m7,
                m12,
                m9,
                m14,
                m3,
                m13,
                m15,
                m4,
                m0,
                m11,
                m2,
                m5,
                m8,
                m1,
                m6,
                fn(a, bp, b0, b1, b2, b3, c, e0, e1, e2, e3, _ab, _cb) {
                  round(
                    a,
                    bp,
                    b0,
                    b1,
                    b2,
                    b3,
                    c,
                    e0,
                    e1,
                    e2,
                    e3,
                    m12,
                    m13,
                    m9,
                    m11,
                    m15,
                    m10,
                    m14,
                    m8,
                    m7,
                    m2,
                    m5,
                    m3,
                    m0,
                    m1,
                    m6,
                    m4,
                    fn(a, bp, b0, b1, b2, b3, c, e0, e1, e2, e3, _ab, _cb) {
                      round(
                        a,
                        bp,
                        b0,
                        b1,
                        b2,
                        b3,
                        c,
                        e0,
                        e1,
                        e2,
                        e3,
                        m9,
                        m14,
                        m11,
                        m5,
                        m8,
                        m12,
                        m15,
                        m1,
                        m13,
                        m3,
                        m0,
                        m10,
                        m2,
                        m6,
                        m4,
                        m7,
                        fn(a, bp, b0, b1, b2, b3, c, e0, e1, e2, e3, _ab, _cb) {
                          round(
                            a,
                            bp,
                            b0,
                            b1,
                            b2,
                            b3,
                            c,
                            e0,
                            e1,
                            e2,
                            e3,
                            m11,
                            m15,
                            m5,
                            m0,
                            m1,
                            m9,
                            m8,
                            m6,
                            m14,
                            m10,
                            m2,
                            m12,
                            m3,
                            m4,
                            m7,
                            m13,
                            fn(
                              _a,
                              _bp,
                              fb0,
                              fb1,
                              fb2,
                              fb3,
                              _c,
                              fe0,
                              fe1,
                              fe2,
                              fe3,
                              fab,
                              fcb,
                            ) {
                              Output {
                                w0: builtin.xor_bytearray(
                                  False,
                                  lane(fab, 1),
                                  lane(fcb, 1),
                                ),
                                w1: builtin.xor_bytearray(
                                  False,
                                  lane(fab, 6),
                                  lane(fcb, 6),
                                ),
                                w2: builtin.xor_bytearray(
                                  False,
                                  lane(fab, 11),
                                  lane(fcb, 11),
                                ),
                                w3: builtin.xor_bytearray(
                                  False,
                                  lane(fab, 16),
                                  lane(fcb, 16),
                                ),
                                w4: builtin.xor_bytearray(False, fb0, fe0),
                                w5: builtin.xor_bytearray(False, fb1, fe1),
                                w6: builtin.xor_bytearray(False, fb2, fe2),
                                w7: builtin.xor_bytearray(False, fb3, fe3),
                              }
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
    },
  )
}

// Single-chunk compression: the chunk counter is always 0 for
// inputs <= 1024 bytes, so the first two d-rows are fixed at 0 and the
// c-rows always start at iv0..iv3.
fn compress(
  padded: ByteArray,
  offset: Int,
  a: Int,
  bp: Int,
  b0: ByteArray,
  b1: ByteArray,
  b2: ByteArray,
  b3: ByteArray,
  block_len: ByteArray,
  flags: ByteArray,
) -> Output {
  permute(
    a,
    bp,
    b0,
    b1,
    b2,
    b3,
    iv0123,
    zero_word,
    zero_word,
    block_len,
    flags,
    lane(padded, offset),
    lane(padded, offset + 4),
    lane(padded, offset + 8),
    lane(padded, offset + 12),
    lane(padded, offset + 16),
    lane(padded, offset + 20),
    lane(padded, offset + 24),
    lane(padded, offset + 28),
    lane(padded, offset + 32),
    lane(padded, offset + 36),
    lane(padded, offset + 40),
    lane(padded, offset + 44),
    lane(padded, offset + 48),
    lane(padded, offset + 52),
    lane(padded, offset + 56),
    lane(padded, offset + 60),
  )
}

// Reverse a 4-byte big-endian word into digest (little-endian) order.
const le4 =
  fn(be: ByteArray) {
    builtin.integer_to_bytearray(
      False,
      4,
      builtin.bytearray_to_integer(True, be),
    )
  }

fn hash_go(
  padded: ByteArray,
  len: Int,
  offset: Int,
  a: Int,
  bp: Int,
  b0: ByteArray,
  b1: ByteArray,
  b2: ByteArray,
  b3: ByteArray,
) -> ByteArray {
  if len - offset > 64 {
    let flags =
      if offset == 0 {
        chunk_start
      } else {
        no_flags
      }
    let Output { w0, w1, w2, w3, w4, w5, w6, w7 } =
      compress(padded, offset, a, bp, b0, b1, b2, b3, full_block_len, flags)

    hash_go(
      padded,
      len,
      offset + 64,
      pack_be(w0, w1, w2, w3),
      pack_be(w4, w5, w6, w7),
      w4,
      w5,
      w6,
      w7,
    )
  } else {
    let flags =
      if offset == 0 {
        chunk_start_end_root
      } else {
        chunk_end_root
      }
    let Output { w0, w1, w2, w3, w4, w5, w6, w7 } =
      compress(
        padded,
        offset,
        a,
        bp,
        b0,
        b1,
        b2,
        b3,
        builtin.integer_to_bytearray(True, 4, len - offset),
        flags,
      )

    le4(w0)
      |> bytearray.concat(le4(w1))
      |> bytearray.concat(le4(w2))
      |> bytearray.concat(le4(w3))
      |> bytearray.concat(le4(w4))
      |> bytearray.concat(le4(w5))
      |> bytearray.concat(le4(w6))
      |> bytearray.concat(le4(w7))
  }
}

pub fn hash(input: ByteArray) -> ByteArray {
  let len = bytearray.length(input)
  expect len <= 1024

  hash_go(
    builtin.append_bytearray(input, zeros64),
    len,
    0,
    iv0123,
    iv4567,
    ivb4,
    ivb5,
    ivb6,
    ivb7,
  )
}

pub fn verify(input: ByteArray, expected_digest: ByteArray) -> Bool {
  hash(input) == expected_digest
}
