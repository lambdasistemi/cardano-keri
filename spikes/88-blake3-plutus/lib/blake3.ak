use aiken/builtin
use aiken/primitive/bytearray

const no_flags = #"00000000"

const chunk_start = #"00000001"

const chunk_end_root = #"0000000a"

const chunk_start_end_root = #"0000000b"

const full_block_len = #"00000040"

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

// Initial compression state. Round-to-round values do not rebuild this
// record: `permute` passes the live fields through continuations instead.
// The a-rows (s0..s3) and c-rows (s8..s11) accumulate un-reduced additions
// as integers. The b-rows and d-rows stay as exact 4-byte big-endian words;
// b also keeps an integer shadow (s4..s7) because it feeds additions.
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

// Additions are left un-reduced mod 2^32; over 7 rounds a word
// accumulates at most ~57 * 2^32 < 2^40, so a width-5 big-endian
// conversion plus dropping the top byte recovers the exact u32. This and
// the other hot helpers are function-valued constants deliberately: Aiken
// inlines constants but keeps named functions out of line.
const truncate32 =
  fn(x: Int) {
    builtin.slice_bytearray(1, 4, builtin.integer_to_bytearray(True, 5, x))
  }

const word =
  fn(padded: ByteArray, offset: Int) {
    builtin.bytearray_to_integer(
      False,
      builtin.slice_bytearray(offset, 4, padded),
    )
  }

// CPS keeps the 20 live state values out of a State record between rounds.
// The final eight arguments are byte shadows already computed by the last
// diagonal mixes. Intermediate continuations discard them; the seventh
// continuation uses them to form Output without converting the final a/c
// integers a second time. Aiken erases those discarded arguments.
const round =
  fn(
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
    then: fn(
      Int,
      Int,
      Int,
      Int,
      Int,
      Int,
      Int,
      Int,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      Int,
      Int,
      Int,
      Int,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
      ByteArray,
    ) ->
      Output,
  ) {
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
    let dab0 = truncate32(da0)
    let ddb0 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dab0, vdb), -8)
    let dc0 = vc + builtin.bytearray_to_integer(True, ddb0)
    let dcb0 = truncate32(dc0)
    let dbb0 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dcb0, vbb), -7)
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
    let dab1 = truncate32(da1)
    let ddb1 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dab1, vdb), -8)
    let dc1 = vc + builtin.bytearray_to_integer(True, ddb1)
    let dcb1 = truncate32(dc1)
    let dbb1 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dcb1, vbb), -7)
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
    let dab2 = truncate32(da2)
    let ddb2 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dab2, vdb), -8)
    let dc2 = vc + builtin.bytearray_to_integer(True, ddb2)
    let dcb2 = truncate32(dc2)
    let dbb2 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dcb2, vbb), -7)
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
    let dab3 = truncate32(da3)
    let ddb3 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dab3, vdb), -8)
    let dc3 = vc + builtin.bytearray_to_integer(True, ddb3)
    let dcb3 = truncate32(dc3)
    let dbb3 =
      builtin.rotate_bytearray(builtin.xor_bytearray(False, dcb3, vbb), -7)
    let db3 = builtin.bytearray_to_integer(True, dbb3)

    then(
      da0,
      da1,
      da2,
      da3,
      db3,
      db0,
      db1,
      db2,
      dbb3,
      dbb0,
      dbb1,
      dbb2,
      dc2,
      dc3,
      dc0,
      dc1,
      ddb1,
      ddb2,
      ddb3,
      ddb0,
      dab0,
      dab1,
      dab2,
      dab3,
      dcb2,
      dcb3,
      dcb0,
      dcb1,
    )
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
) -> Output {
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

  round(
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
    fn(
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
      _ab0,
      _ab1,
      _ab2,
      _ab3,
      _cb8,
      _cb9,
      _cb10,
      _cb11,
    ) {
      round(
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
        fn(
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
          _ab0,
          _ab1,
          _ab2,
          _ab3,
          _cb8,
          _cb9,
          _cb10,
          _cb11,
        ) {
          round(
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
            fn(
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
              _ab0,
              _ab1,
              _ab2,
              _ab3,
              _cb8,
              _cb9,
              _cb10,
              _cb11,
            ) {
              round(
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
                fn(
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
                  _ab0,
                  _ab1,
                  _ab2,
                  _ab3,
                  _cb8,
                  _cb9,
                  _cb10,
                  _cb11,
                ) {
                  round(
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
                    fn(
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
                      _ab0,
                      _ab1,
                      _ab2,
                      _ab3,
                      _cb8,
                      _cb9,
                      _cb10,
                      _cb11,
                    ) {
                      round(
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
                        fn(
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
                          _ab0,
                          _ab1,
                          _ab2,
                          _ab3,
                          _cb8,
                          _cb9,
                          _cb10,
                          _cb11,
                        ) {
                          round(
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
                              _s0,
                              _s1,
                              _s2,
                              _s3,
                              _s4,
                              _s5,
                              _s6,
                              _s7,
                              b4,
                              b5,
                              b6,
                              b7,
                              _s8,
                              _s9,
                              _s10,
                              _s11,
                              d12,
                              d13,
                              d14,
                              d15,
                              ab0,
                              ab1,
                              ab2,
                              ab3,
                              cb8,
                              cb9,
                              cb10,
                              cb11,
                            ) {
                              Output {
                                w0: builtin.xor_bytearray(False, ab0, cb8),
                                w1: builtin.xor_bytearray(False, ab1, cb9),
                                w2: builtin.xor_bytearray(False, ab2, cb10),
                                w3: builtin.xor_bytearray(False, ab3, cb11),
                                w4: builtin.xor_bytearray(False, b4, d12),
                                w5: builtin.xor_bytearray(False, b5, d13),
                                w6: builtin.xor_bytearray(False, b6, d14),
                                w7: builtin.xor_bytearray(False, b7, d15),
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
  block_len: ByteArray,
  flags: ByteArray,
) -> Output {
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
      d14: block_len,
      d15: flags,
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
      if offset == 0 {
        chunk_start
      } else {
        no_flags
      }
    let Output { w0, w1, w2, w3, w4, w5, w6, w7 } =
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
        full_block_len,
        flags,
      )

    hash_go(
      padded,
      len,
      offset + 64,
      builtin.bytearray_to_integer(True, w0),
      builtin.bytearray_to_integer(True, w1),
      builtin.bytearray_to_integer(True, w2),
      builtin.bytearray_to_integer(True, w3),
      builtin.bytearray_to_integer(True, w4),
      builtin.bytearray_to_integer(True, w5),
      builtin.bytearray_to_integer(True, w6),
      builtin.bytearray_to_integer(True, w7),
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
    input,
    len,
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
