use aiken/builtin
use aiken/primitive/bytearray

const chunk_start = 1

const chunk_end = 2

const root = 8

const iv0 = 1779033703

const iv1 = 3144134277

const iv2 = 1013904242

const iv3 = 2773480762

const iv4 = 1359893119

const iv5 = 2600822924

const iv6 = 528734635

const iv7 = 1541459225

// Big-endian bytes of iv4..iv7, the initial b-column of the state.
const ivb4 = #"510e527f"

const ivb5 = #"9b05688c"

const ivb6 = #"1f83d9ab"

const ivb7 = #"5be0cd19"

const zero_word = #"00000000"

// 64 zero bytes: padding so every block read stays in bounds and
// out-of-range message words read as zero.
const zero_block =
  #"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

// The a-rows (s0..s3) and c-rows (s8..s11) accumulate un-reduced
// additions and live as integers. The b-rows and d-rows are always
// exact u32 rotation outputs and live as 4-byte big-endian words so
// the next xor can consume them without an integer round-trip; the
// b-rows keep an integer shadow (s4..s7) because they also feed
// additions.
type State {
  s0: Int,
  s1: Int,
  s2: Int,
  s3: Int,
  s4: Int,
  s5: Int,
  s6: Int,
  s7: Int,
  b4: ByteArray,
  b5: ByteArray,
  b6: ByteArray,
  b7: ByteArray,
  s8: Int,
  s9: Int,
  s10: Int,
  s11: Int,
  d12: ByteArray,
  d13: ByteArray,
  d14: ByteArray,
  d15: ByteArray,
}

// Additions are left un-reduced mod 2^32; over 7 rounds a word
// accumulates at most ~57 * 2^32 < 2^40, so a width-5 big-endian
// conversion plus dropping the top byte recovers the exact u32.
fn truncate32(x: Int) -> ByteArray {
  builtin.slice_bytearray(1, 4, builtin.integer_to_bytearray(True, 5, x))
}

// xor of two possibly un-reduced words, back to an exact u32.
fn xor32(x: Int, y: Int) -> Int {
  builtin.bytearray_to_integer(
    True,
    builtin.xor_bytearray(False, truncate32(x), truncate32(y)),
  )
}

fn word(padded: ByteArray, offset: Int) -> Int {
  builtin.bytearray_to_integer(False, builtin.slice_bytearray(offset, 4, padded))
}

fn round(
  state: State,
  m0: Int,
  m1: Int,
  m2: Int,
  m3: Int,
  m4: Int,
  m5: Int,
  m6: Int,
  m7: Int,
  m8: Int,
  m9: Int,
  m10: Int,
  m11: Int,
  m12: Int,
  m13: Int,
  m14: Int,
  m15: Int,
) -> State {
  let State {
    s0,
    s1,
    s2,
    s3,
    s4,
    s5,
    s6,
    s7,
    b4,
    b5,
    b6,
    b7,
    s8,
    s9,
    s10,
    s11,
    d12,
    d13,
    d14,
    d15,
  } = state

  // column 0: G(s0, s4, s8, s12)
  let va = s0 + s4 + m0
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), d12),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = s8 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), b4),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let ca0 = va + vb + m1
  let cdb0 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(ca0), vdb),
      -8,
    )
  let cc0 = vc + builtin.bytearray_to_integer(True, cdb0)
  let cbb0 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(cc0), vbb),
      -7,
    )
  let cb0 = builtin.bytearray_to_integer(True, cbb0)

  // column 1: G(s1, s5, s9, s13)
  let va = s1 + s5 + m2
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), d13),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = s9 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), b5),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let ca1 = va + vb + m3
  let cdb1 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(ca1), vdb),
      -8,
    )
  let cc1 = vc + builtin.bytearray_to_integer(True, cdb1)
  let cbb1 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(cc1), vbb),
      -7,
    )
  let cb1 = builtin.bytearray_to_integer(True, cbb1)

  // column 2: G(s2, s6, s10, s14)
  let va = s2 + s6 + m4
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), d14),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = s10 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), b6),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let ca2 = va + vb + m5
  let cdb2 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(ca2), vdb),
      -8,
    )
  let cc2 = vc + builtin.bytearray_to_integer(True, cdb2)
  let cbb2 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(cc2), vbb),
      -7,
    )
  let cb2 = builtin.bytearray_to_integer(True, cbb2)

  // column 3: G(s3, s7, s11, s15)
  let va = s3 + s7 + m6
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), d15),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = s11 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), b7),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let ca3 = va + vb + m7
  let cdb3 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(ca3), vdb),
      -8,
    )
  let cc3 = vc + builtin.bytearray_to_integer(True, cdb3)
  let cbb3 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(cc3), vbb),
      -7,
    )
  let cb3 = builtin.bytearray_to_integer(True, cbb3)

  // diagonal 0: G(s0, s5, s10, s15)
  let va = ca0 + cb1 + m8
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), cdb3),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = cc2 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), cbb1),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let da0 = va + vb + m9
  let ddb0 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(da0), vdb),
      -8,
    )
  let dc0 = vc + builtin.bytearray_to_integer(True, ddb0)
  let dbb0 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(dc0), vbb),
      -7,
    )
  let db0 = builtin.bytearray_to_integer(True, dbb0)

  // diagonal 1: G(s1, s6, s11, s12)
  let va = ca1 + cb2 + m10
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), cdb0),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = cc3 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), cbb2),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let da1 = va + vb + m11
  let ddb1 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(da1), vdb),
      -8,
    )
  let dc1 = vc + builtin.bytearray_to_integer(True, ddb1)
  let dbb1 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(dc1), vbb),
      -7,
    )
  let db1 = builtin.bytearray_to_integer(True, dbb1)

  // diagonal 2: G(s2, s7, s8, s13)
  let va = ca2 + cb3 + m12
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), cdb1),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = cc0 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), cbb3),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let da2 = va + vb + m13
  let ddb2 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(da2), vdb),
      -8,
    )
  let dc2 = vc + builtin.bytearray_to_integer(True, ddb2)
  let dbb2 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(dc2), vbb),
      -7,
    )
  let db2 = builtin.bytearray_to_integer(True, dbb2)

  // diagonal 3: G(s3, s4, s9, s14)
  let va = ca3 + cb0 + m14
  let vdb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(va), cdb2),
      -16,
    )
  let vd = builtin.bytearray_to_integer(True, vdb)
  let vc = cc1 + vd
  let vbb =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(vc), cbb0),
      -12,
    )
  let vb = builtin.bytearray_to_integer(True, vbb)
  let da3 = va + vb + m15
  let ddb3 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(da3), vdb),
      -8,
    )
  let dc3 = vc + builtin.bytearray_to_integer(True, ddb3)
  let dbb3 =
    builtin.rotate_bytearray(
      builtin.xor_bytearray(False, truncate32(dc3), vbb),
      -7,
    )
  let db3 = builtin.bytearray_to_integer(True, dbb3)

  State {
    s0: da0,
    s1: da1,
    s2: da2,
    s3: da3,
    s4: db3,
    s5: db0,
    s6: db1,
    s7: db2,
    b4: dbb3,
    b5: dbb0,
    b6: dbb1,
    b7: dbb2,
    s8: dc2,
    s9: dc3,
    s10: dc0,
    s11: dc1,
    d12: ddb1,
    d13: ddb2,
    d14: ddb3,
    d15: ddb0,
  }
}

fn permute(
  state: State,
  m0: Int,
  m1: Int,
  m2: Int,
  m3: Int,
  m4: Int,
  m5: Int,
  m6: Int,
  m7: Int,
  m8: Int,
  m9: Int,
  m10: Int,
  m11: Int,
  m12: Int,
  m13: Int,
  m14: Int,
  m15: Int,
) -> State {
  round(state, m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15)
    |> round(m2, m6, m3, m10, m7, m0, m4, m13, m1, m11, m12, m5, m9, m14, m15, m8)
    |> round(m3, m4, m10, m12, m13, m2, m7, m14, m6, m5, m9, m0, m11, m15, m8, m1)
    |> round(m10, m7, m12, m9, m14, m3, m13, m15, m4, m0, m11, m2, m5, m8, m1, m6)
    |> round(m12, m13, m9, m11, m15, m10, m14, m8, m7, m2, m5, m3, m0, m1, m6, m4)
    |> round(m9, m14, m11, m5, m8, m12, m15, m1, m13, m3, m0, m10, m2, m6, m4, m7)
    |> round(m11, m15, m5, m0, m1, m9, m8, m6, m14, m10, m2, m12, m3, m4, m7, m13)
}

// Single-chunk compression: the chunk counter is always 0 for
// inputs <= 1024 bytes, so s12/s13 are fixed at 0.
fn compress(
  padded: ByteArray,
  offset: Int,
  h0: Int,
  h1: Int,
  h2: Int,
  h3: Int,
  h4: Int,
  h5: Int,
  h6: Int,
  h7: Int,
  hb4: ByteArray,
  hb5: ByteArray,
  hb6: ByteArray,
  hb7: ByteArray,
  block_len: Int,
  flags: Int,
) -> State {
  let state =
    State {
      s0: h0,
      s1: h1,
      s2: h2,
      s3: h3,
      s4: h4,
      s5: h5,
      s6: h6,
      s7: h7,
      b4: hb4,
      b5: hb5,
      b6: hb6,
      b7: hb7,
      s8: iv0,
      s9: iv1,
      s10: iv2,
      s11: iv3,
      d12: zero_word,
      d13: zero_word,
      d14: builtin.integer_to_bytearray(True, 4, block_len),
      d15: builtin.integer_to_bytearray(True, 4, flags),
    }

  permute(
    state,
    word(padded, offset),
    word(padded, offset + 4),
    word(padded, offset + 8),
    word(padded, offset + 12),
    word(padded, offset + 16),
    word(padded, offset + 20),
    word(padded, offset + 24),
    word(padded, offset + 28),
    word(padded, offset + 32),
    word(padded, offset + 36),
    word(padded, offset + 40),
    word(padded, offset + 44),
    word(padded, offset + 48),
    word(padded, offset + 52),
    word(padded, offset + 56),
    word(padded, offset + 60),
  )
}

fn digest_word(x: Int, y: Int) -> ByteArray {
  builtin.integer_to_bytearray(False, 4, xor32(x, y))
}

// Reverse a 4-byte big-endian word into digest (little-endian) order.
fn le4(be: ByteArray) -> ByteArray {
  builtin.integer_to_bytearray(False, 4, builtin.bytearray_to_integer(True, be))
}

fn hash_go(
  padded: ByteArray,
  len: Int,
  offset: Int,
  blocks_compressed: Int,
  h0: Int,
  h1: Int,
  h2: Int,
  h3: Int,
  h4: Int,
  h5: Int,
  h6: Int,
  h7: Int,
  hb4: ByteArray,
  hb5: ByteArray,
  hb6: ByteArray,
  hb7: ByteArray,
) -> ByteArray {
  if len - offset > 64 {
    let flags =
      if blocks_compressed == 0 {
        chunk_start
      } else {
        0
      }
    let State {
      s0,
      s1,
      s2,
      s3,
      s4: _,
      s5: _,
      s6: _,
      s7: _,
      b4,
      b5,
      b6,
      b7,
      s8,
      s9,
      s10,
      s11,
      d12,
      d13,
      d14,
      d15,
    } =
      compress(
        padded,
        offset,
        h0,
        h1,
        h2,
        h3,
        h4,
        h5,
        h6,
        h7,
        hb4,
        hb5,
        hb6,
        hb7,
        64,
        flags,
      )

    let n4 = builtin.xor_bytearray(False, b4, d12)
    let n5 = builtin.xor_bytearray(False, b5, d13)
    let n6 = builtin.xor_bytearray(False, b6, d14)
    let n7 = builtin.xor_bytearray(False, b7, d15)

    hash_go(
      padded,
      len,
      offset + 64,
      blocks_compressed + 1,
      xor32(s0, s8),
      xor32(s1, s9),
      xor32(s2, s10),
      xor32(s3, s11),
      builtin.bytearray_to_integer(True, n4),
      builtin.bytearray_to_integer(True, n5),
      builtin.bytearray_to_integer(True, n6),
      builtin.bytearray_to_integer(True, n7),
      n4,
      n5,
      n6,
      n7,
    )
  } else {
    let flags =
      if blocks_compressed == 0 {
        chunk_start + chunk_end + root
      } else {
        chunk_end + root
      }
    let State {
      s0,
      s1,
      s2,
      s3,
      s4: _,
      s5: _,
      s6: _,
      s7: _,
      b4,
      b5,
      b6,
      b7,
      s8,
      s9,
      s10,
      s11,
      d12,
      d13,
      d14,
      d15,
    } =
      compress(
        padded,
        offset,
        h0,
        h1,
        h2,
        h3,
        h4,
        h5,
        h6,
        h7,
        hb4,
        hb5,
        hb6,
        hb7,
        len - offset,
        flags,
      )

    digest_word(s0, s8)
      |> bytearray.concat(digest_word(s1, s9))
      |> bytearray.concat(digest_word(s2, s10))
      |> bytearray.concat(digest_word(s3, s11))
      |> bytearray.concat(le4(builtin.xor_bytearray(False, b4, d12)))
      |> bytearray.concat(le4(builtin.xor_bytearray(False, b5, d13)))
      |> bytearray.concat(le4(builtin.xor_bytearray(False, b6, d14)))
      |> bytearray.concat(le4(builtin.xor_bytearray(False, b7, d15)))
  }
}

pub fn hash(input: ByteArray) -> ByteArray {
  let len = bytearray.length(input)
  expect len <= 1024

  let padded = bytearray.concat(input, zero_block)

  hash_go(
    padded,
    len,
    0,
    0,
    iv0,
    iv1,
    iv2,
    iv3,
    iv4,
    iv5,
    iv6,
    iv7,
    ivb4,
    ivb5,
    ivb6,
    ivb7,
  )
}

pub fn verify(input: ByteArray, expected_digest: ByteArray) -> Bool {
  hash(input) == expected_digest
}
