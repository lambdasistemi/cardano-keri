use aiken/primitive/bytearray

// RFC 4648 §5: url-safe base64url, unpadded
// A-Z=0-25, a-z=26-51, 0-9=52-61, -=62, _=63

fn char(idx: Int) -> Int {
  if idx < 26 {
    65 + idx
  } else if idx < 52 {
    97 + idx - 26
  } else if idx < 62 {
    48 + idx - 52
  } else if idx == 62 {
    45
  } else {
    95
  }
}

// bytearray.push prepends; use this to append a single encoded char
fn emit(out: ByteArray, idx: Int) -> ByteArray {
  bytearray.concat(out, bytearray.push(#"", char(idx)))
}

// Accumulator bits cycle: 0 -> 2 -> 4 -> 0 per byte processed
type State {
  acc: Int,
  bits: Int,
  out: ByteArray,
}

fn flush(state: State) -> ByteArray {
  if state.bits == 0 {
    state.out
  } else {
    let shift =
      if state.bits == 2 {
        16
      } else {
        4
      }
    emit(state.out, state.acc * shift)
  }
}

pub fn encode(bytes: ByteArray) -> ByteArray {
  let final =
    bytearray.foldl(
      bytes,
      State { acc: 0, bits: 0, out: #"" },
      fn(byte, state) {
        let new_acc = state.acc * 256 + byte
        let new_bits = state.bits + 8
        if new_bits == 12 {
          let o = emit(state.out, new_acc / 64)
          State { acc: 0, bits: 0, out: emit(o, new_acc % 64) }
        } else if new_bits == 10 {
          State {
            acc: new_acc % 16,
            bits: 4,
            out: emit(state.out, new_acc / 16),
          }
        } else {
          // new_bits == 8
          State {
            acc: new_acc % 4,
            bits: 2,
            out: emit(state.out, new_acc / 4),
          }
        }
      },
    )
  flush(final)
}
