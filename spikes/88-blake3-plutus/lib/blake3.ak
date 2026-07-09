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

// 64 zero bytes: padding so every block read stays in bounds and
// out-of-range message words read as zero.
const zero_block =
  #"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

type State {
  s0: Int,
  s1: Int,
  s2: Int,
  s3: Int,
  s4: Int,
  s5: Int,
  s6: Int,
  s7: Int,
  s8: Int,
  s9: Int,
  s10: Int,
  s11: Int,
  s12: Int,
  s13: Int,
  s14: Int,
  s15: Int,
}

// Additions are left un-reduced mod 2^32; over 7 rounds a word
// accumulates at most ~57 * 2^32 < 2^40, so a width-5 big-endian
// conversion plus dropping the top byte recovers the exact u32.
fn truncate32(x: Int) -> ByteArray {
  builtin.slice_bytearray(1, 4, builtin.integer_to_bytearray(True, 5, x))
}

// rotr16(xor32(y, x)); x may be un-reduced, y must be an exact u32.
fn xr16(x: Int, y: Int) -> Int {
  builtin.bytearray_to_integer(
    True,
    builtin.rotate_bytearray(
      builtin.xor_bytearray(
        False,
        truncate32(x),
        builtin.integer_to_bytearray(True, 4, y),
      ),
      -16,
    ),
  )
}

fn xr12(x: Int, y: Int) -> Int {
  builtin.bytearray_to_integer(
    True,
    builtin.rotate_bytearray(
      builtin.xor_bytearray(
        False,
        truncate32(x),
        builtin.integer_to_bytearray(True, 4, y),
      ),
      -12,
    ),
  )
}

fn xr8(x: Int, y: Int) -> Int {
  builtin.bytearray_to_integer(
    True,
    builtin.rotate_bytearray(
      builtin.xor_bytearray(
        False,
        truncate32(x),
        builtin.integer_to_bytearray(True, 4, y),
      ),
      -8,
    ),
  )
}

fn xr7(x: Int, y: Int) -> Int {
  builtin.bytearray_to_integer(
    True,
    builtin.rotate_bytearray(
      builtin.xor_bytearray(
        False,
        truncate32(x),
        builtin.integer_to_bytearray(True, 4, y),
      ),
      -7,
    ),
  )
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
    s8,
    s9,
    s10,
    s11,
    s12,
    s13,
    s14,
    s15,
  } = state

  // column 0: G(s0, s4, s8, s12)
  let va = s0 + s4 + m0
  let vd = xr16(va, s12)
  let vc = s8 + vd
  let vb = xr12(vc, s4)
  let ca0 = va + vb + m1
  let cd0 = xr8(ca0, vd)
  let cc0 = vc + cd0
  let cb0 = xr7(cc0, vb)

  // column 1: G(s1, s5, s9, s13)
  let va = s1 + s5 + m2
  let vd = xr16(va, s13)
  let vc = s9 + vd
  let vb = xr12(vc, s5)
  let ca1 = va + vb + m3
  let cd1 = xr8(ca1, vd)
  let cc1 = vc + cd1
  let cb1 = xr7(cc1, vb)

  // column 2: G(s2, s6, s10, s14)
  let va = s2 + s6 + m4
  let vd = xr16(va, s14)
  let vc = s10 + vd
  let vb = xr12(vc, s6)
  let ca2 = va + vb + m5
  let cd2 = xr8(ca2, vd)
  let cc2 = vc + cd2
  let cb2 = xr7(cc2, vb)

  // column 3: G(s3, s7, s11, s15)
  let va = s3 + s7 + m6
  let vd = xr16(va, s15)
  let vc = s11 + vd
  let vb = xr12(vc, s7)
  let ca3 = va + vb + m7
  let cd3 = xr8(ca3, vd)
  let cc3 = vc + cd3
  let cb3 = xr7(cc3, vb)

  // diagonal 0: G(s0, s5, s10, s15)
  let va = ca0 + cb1 + m8
  let vd = xr16(va, cd3)
  let vc = cc2 + vd
  let vb = xr12(vc, cb1)
  let da0 = va + vb + m9
  let dd0 = xr8(da0, vd)
  let dc0 = vc + dd0
  let db0 = xr7(dc0, vb)

  // diagonal 1: G(s1, s6, s11, s12)
  let va = ca1 + cb2 + m10
  let vd = xr16(va, cd0)
  let vc = cc3 + vd
  let vb = xr12(vc, cb2)
  let da1 = va + vb + m11
  let dd1 = xr8(da1, vd)
  let dc1 = vc + dd1
  let db1 = xr7(dc1, vb)

  // diagonal 2: G(s2, s7, s8, s13)
  let va = ca2 + cb3 + m12
  let vd = xr16(va, cd1)
  let vc = cc0 + vd
  let vb = xr12(vc, cb3)
  let da2 = va + vb + m13
  let dd2 = xr8(da2, vd)
  let dc2 = vc + dd2
  let db2 = xr7(dc2, vb)

  // diagonal 3: G(s3, s4, s9, s14)
  let va = ca3 + cb0 + m14
  let vd = xr16(va, cd2)
  let vc = cc1 + vd
  let vb = xr12(vc, cb0)
  let da3 = va + vb + m15
  let dd3 = xr8(da3, vd)
  let dc3 = vc + dd3
  let db3 = xr7(dc3, vb)

  State {
    s0: da0,
    s1: da1,
    s2: da2,
    s3: da3,
    s4: db3,
    s5: db0,
    s6: db1,
    s7: db2,
    s8: dc2,
    s9: dc3,
    s10: dc0,
    s11: dc1,
    s12: dd1,
    s13: dd2,
    s14: dd3,
    s15: dd0,
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
      s8: iv0,
      s9: iv1,
      s10: iv2,
      s11: iv3,
      s12: 0,
      s13: 0,
      s14: block_len,
      s15: flags,
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
      s4,
      s5,
      s6,
      s7,
      s8,
      s9,
      s10,
      s11,
      s12,
      s13,
      s14,
      s15,
    } = compress(padded, offset, h0, h1, h2, h3, h4, h5, h6, h7, 64, flags)

    hash_go(
      padded,
      len,
      offset + 64,
      blocks_compressed + 1,
      xor32(s0, s8),
      xor32(s1, s9),
      xor32(s2, s10),
      xor32(s3, s11),
      xor32(s4, s12),
      xor32(s5, s13),
      xor32(s6, s14),
      xor32(s7, s15),
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
      s4,
      s5,
      s6,
      s7,
      s8,
      s9,
      s10,
      s11,
      s12,
      s13,
      s14,
      s15,
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
        len - offset,
        flags,
      )

    digest_word(s0, s8)
      |> bytearray.concat(digest_word(s1, s9))
      |> bytearray.concat(digest_word(s2, s10))
      |> bytearray.concat(digest_word(s3, s11))
      |> bytearray.concat(digest_word(s4, s12))
      |> bytearray.concat(digest_word(s5, s13))
      |> bytearray.concat(digest_word(s6, s14))
      |> bytearray.concat(digest_word(s7, s15))
  }
}

pub fn hash(input: ByteArray) -> ByteArray {
  let len = bytearray.length(input)
  expect len <= 1024

  let padded = bytearray.concat(input, zero_block)

  hash_go(padded, len, 0, 0, iv0, iv1, iv2, iv3, iv4, iv5, iv6, iv7)
}

pub fn verify(input: ByteArray, expected_digest: ByteArray) -> Bool {
  hash(input) == expected_digest
}
