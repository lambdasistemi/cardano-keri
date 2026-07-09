use aiken/builtin
use aiken/primitive/bytearray

const word_mod = 4294967296

const chunk_start = 1

const chunk_end = 2

const root = 8

type Cv {
  v0: Int,
  v1: Int,
  v2: Int,
  v3: Int,
  v4: Int,
  v5: Int,
  v6: Int,
  v7: Int,
}

type Block {
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
}

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

type Quad {
  a: Int,
  b: Int,
  c: Int,
  d: Int,
}

fn iv() -> Cv {
  Cv {
    v0: 1779033703,
    v1: 3144134277,
    v2: 1013904242,
    v3: 2773480762,
    v4: 1359893119,
    v5: 2600822924,
    v6: 528734635,
    v7: 1541459225,
  }
}

fn u32(n: Int) -> Int {
  n % word_mod
}

fn xor32(left: Int, right: Int) -> Int {
  builtin.xor_bytearray(
    False,
    bytearray.from_int_little_endian(left, 4),
    bytearray.from_int_little_endian(right, 4),
  )
    |> bytearray.to_int_little_endian
}

fn rotr16(x: Int) -> Int {
  x / 65536 + x % 65536 * 65536
}

fn rotr12(x: Int) -> Int {
  x / 4096 + x % 4096 * 1048576
}

fn rotr8(x: Int) -> Int {
  x / 256 + x % 256 * 16777216
}

fn rotr7(x: Int) -> Int {
  x / 128 + x % 128 * 33554432
}

fn byte_at_or_zero(input: ByteArray, ix: Int, len: Int) -> Int {
  if ix < len {
    bytearray.at(input, ix)
  } else {
    0
  }
}

fn read_word(input: ByteArray, offset: Int, len: Int) -> Int {
  byte_at_or_zero(input, offset, len) + byte_at_or_zero(input, offset + 1, len) * 256 + byte_at_or_zero(
    input,
    offset + 2,
    len,
  ) * 65536 + byte_at_or_zero(input, offset + 3, len) * 16777216
}

fn block(input: ByteArray, offset: Int, len: Int) -> Block {
  Block {
    m0: read_word(input, offset, len),
    m1: read_word(input, offset + 4, len),
    m2: read_word(input, offset + 8, len),
    m3: read_word(input, offset + 12, len),
    m4: read_word(input, offset + 16, len),
    m5: read_word(input, offset + 20, len),
    m6: read_word(input, offset + 24, len),
    m7: read_word(input, offset + 28, len),
    m8: read_word(input, offset + 32, len),
    m9: read_word(input, offset + 36, len),
    m10: read_word(input, offset + 40, len),
    m11: read_word(input, offset + 44, len),
    m12: read_word(input, offset + 48, len),
    m13: read_word(input, offset + 52, len),
    m14: read_word(input, offset + 56, len),
    m15: read_word(input, offset + 60, len),
  }
}

fn mix(a0: Int, b0: Int, c0: Int, d0: Int, mx: Int, my: Int) -> Quad {
  let a1 = u32(a0 + b0 + mx)
  let d1 = rotr16(xor32(d0, a1))
  let c1 = u32(c0 + d1)
  let b1 = rotr12(xor32(b0, c1))
  let a2 = u32(a1 + b1 + my)
  let d2 = rotr8(xor32(d1, a2))
  let c2 = u32(c1 + d2)
  let b2 = rotr7(xor32(b1, c2))

  Quad { a: a2, b: b2, c: c2, d: d2 }
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
  let q = mix(state.s0, state.s4, state.s8, state.s12, m0, m1)
  let state = State { ..state, s0: q.a, s4: q.b, s8: q.c, s12: q.d }

  let q = mix(state.s1, state.s5, state.s9, state.s13, m2, m3)
  let state = State { ..state, s1: q.a, s5: q.b, s9: q.c, s13: q.d }

  let q = mix(state.s2, state.s6, state.s10, state.s14, m4, m5)
  let state = State { ..state, s2: q.a, s6: q.b, s10: q.c, s14: q.d }

  let q = mix(state.s3, state.s7, state.s11, state.s15, m6, m7)
  let state = State { ..state, s3: q.a, s7: q.b, s11: q.c, s15: q.d }

  let q = mix(state.s0, state.s5, state.s10, state.s15, m8, m9)
  let state = State { ..state, s0: q.a, s5: q.b, s10: q.c, s15: q.d }

  let q = mix(state.s1, state.s6, state.s11, state.s12, m10, m11)
  let state = State { ..state, s1: q.a, s6: q.b, s11: q.c, s12: q.d }

  let q = mix(state.s2, state.s7, state.s8, state.s13, m12, m13)
  let state = State { ..state, s2: q.a, s7: q.b, s8: q.c, s13: q.d }

  let q = mix(state.s3, state.s4, state.s9, state.s14, m14, m15)

  State { ..state, s3: q.a, s4: q.b, s9: q.c, s14: q.d }
}

fn permute(state: State, msg: Block) -> State {
  let state =
    round(
      state,
      msg.m0,
      msg.m1,
      msg.m2,
      msg.m3,
      msg.m4,
      msg.m5,
      msg.m6,
      msg.m7,
      msg.m8,
      msg.m9,
      msg.m10,
      msg.m11,
      msg.m12,
      msg.m13,
      msg.m14,
      msg.m15,
    )
  let state =
    round(
      state,
      msg.m2,
      msg.m6,
      msg.m3,
      msg.m10,
      msg.m7,
      msg.m0,
      msg.m4,
      msg.m13,
      msg.m1,
      msg.m11,
      msg.m12,
      msg.m5,
      msg.m9,
      msg.m14,
      msg.m15,
      msg.m8,
    )
  let state =
    round(
      state,
      msg.m3,
      msg.m4,
      msg.m10,
      msg.m12,
      msg.m13,
      msg.m2,
      msg.m7,
      msg.m14,
      msg.m6,
      msg.m5,
      msg.m9,
      msg.m0,
      msg.m11,
      msg.m15,
      msg.m8,
      msg.m1,
    )
  let state =
    round(
      state,
      msg.m10,
      msg.m7,
      msg.m12,
      msg.m9,
      msg.m14,
      msg.m3,
      msg.m13,
      msg.m15,
      msg.m4,
      msg.m0,
      msg.m11,
      msg.m2,
      msg.m5,
      msg.m8,
      msg.m1,
      msg.m6,
    )
  let state =
    round(
      state,
      msg.m12,
      msg.m13,
      msg.m9,
      msg.m11,
      msg.m15,
      msg.m10,
      msg.m14,
      msg.m8,
      msg.m7,
      msg.m2,
      msg.m5,
      msg.m3,
      msg.m0,
      msg.m1,
      msg.m6,
      msg.m4,
    )
  let state =
    round(
      state,
      msg.m9,
      msg.m14,
      msg.m11,
      msg.m5,
      msg.m8,
      msg.m12,
      msg.m15,
      msg.m1,
      msg.m13,
      msg.m3,
      msg.m0,
      msg.m10,
      msg.m2,
      msg.m6,
      msg.m4,
      msg.m7,
    )

  round(
    state,
    msg.m11,
    msg.m15,
    msg.m5,
    msg.m0,
    msg.m1,
    msg.m9,
    msg.m8,
    msg.m6,
    msg.m14,
    msg.m10,
    msg.m2,
    msg.m12,
    msg.m3,
    msg.m4,
    msg.m7,
    msg.m13,
  )
}

fn initial_state(cv: Cv, counter: Int, block_len: Int, flags: Int) -> State {
  State {
    s0: cv.v0,
    s1: cv.v1,
    s2: cv.v2,
    s3: cv.v3,
    s4: cv.v4,
    s5: cv.v5,
    s6: cv.v6,
    s7: cv.v7,
    s8: 1779033703,
    s9: 3144134277,
    s10: 1013904242,
    s11: 2773480762,
    s12: counter % word_mod,
    s13: counter / word_mod,
    s14: block_len,
    s15: flags,
  }
}

fn compress_state(
  cv: Cv,
  msg: Block,
  block_len: Int,
  counter: Int,
  flags: Int,
) -> State {
  initial_state(cv, counter, block_len, flags)
    |> permute(msg)
}

fn compress_cv(
  cv: Cv,
  msg: Block,
  block_len: Int,
  counter: Int,
  flags: Int,
) -> Cv {
  let state = compress_state(cv, msg, block_len, counter, flags)

  Cv {
    v0: xor32(state.s0, state.s8),
    v1: xor32(state.s1, state.s9),
    v2: xor32(state.s2, state.s10),
    v3: xor32(state.s3, state.s11),
    v4: xor32(state.s4, state.s12),
    v5: xor32(state.s5, state.s13),
    v6: xor32(state.s6, state.s14),
    v7: xor32(state.s7, state.s15),
  }
}

fn root_cv(cv: Cv, msg: Block, block_len: Int, counter: Int, flags: Int) -> Cv {
  let state = compress_state(cv, msg, block_len, counter, flags + root)

  Cv {
    v0: xor32(state.s0, state.s8),
    v1: xor32(state.s1, state.s9),
    v2: xor32(state.s2, state.s10),
    v3: xor32(state.s3, state.s11),
    v4: xor32(state.s4, state.s12),
    v5: xor32(state.s5, state.s13),
    v6: xor32(state.s6, state.s14),
    v7: xor32(state.s7, state.s15),
  }
}

fn bytes_from_cv(cv: Cv) -> ByteArray {
  bytearray.from_int_little_endian(cv.v0, 4)
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v1, 4))
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v2, 4))
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v3, 4))
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v4, 4))
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v5, 4))
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v6, 4))
    |> bytearray.concat(bytearray.from_int_little_endian(cv.v7, 4))
}

fn hash_go(
  input: ByteArray,
  len: Int,
  offset: Int,
  blocks_compressed: Int,
  cv: Cv,
) -> ByteArray {
  if len - offset > 64 {
    let flags =
      if blocks_compressed == 0 {
        chunk_start
      } else {
        0
      }
    let cv = compress_cv(cv, block(input, offset, len), 64, 0, flags)

    hash_go(input, len, offset + 64, blocks_compressed + 1, cv)
  } else {
    let flags =
      if blocks_compressed == 0 {
        chunk_start + chunk_end
      } else {
        chunk_end
      }
    root_cv(cv, block(input, offset, len), len - offset, 0, flags)
      |> bytes_from_cv
  }
}

pub fn hash(input: ByteArray) -> ByteArray {
  let len = bytearray.length(input)
  expect len <= 1024

  hash_go(input, len, 0, 0, iv())
}

pub fn verify(input: ByteArray, expected_digest: ByteArray) -> Bool {
  hash(input) == expected_digest
}
