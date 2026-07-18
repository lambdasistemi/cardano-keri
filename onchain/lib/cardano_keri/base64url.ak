use aiken/primitive/bytearray

// RFC 4648 §5: url-safe base64url, unpadded
// A-Z=0-25, a-z=26-51, 0-9=52-61, -=62, _=63

/// The 64-byte url-safe alphabet, indexed by 6-bit group value.
const alphabet: ByteArray =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

// The alphabet byte (an ASCII code, never 0x00) for a 6-bit index.
fn char(idx: Int) -> Int {
  bytearray.at(alphabet, idx)
}

/// Encode 3 input bytes per step (the S5b ex-unit shape — no per-byte
/// constructor, no single-char concatenation): each 24-bit group reads as
/// one integer and packs 4 alphabet bytes into the integer accumulator;
/// the RFC 4648 tails pack 3 chars (2-byte tail, low 4 bits shifted left
/// 2) or 2 chars (1-byte tail, low 2 bits shifted left 4). The whole
/// output materializes once at the end via `from_int_big_endian` — exact,
/// never padded, because the leading alphabet byte is non-zero.
pub fn encode(bytes: ByteArray) -> ByteArray {
  let len = bytearray.length(bytes)
  if len == 0 {
    #""
  } else {
    let tail_chars = when len % 3 is {
      0 -> 0
      1 -> 2
      _ -> 3
    }
    encode_groups(bytes, 0, len, 0, len / 3 * 4 + tail_chars)
  }
}

// Fold the 3-byte groups (then the tail) of `bytes` from `off` into the
// alphabet-byte accumulator `acc`, emitting `out_len` bytes at the end.
fn encode_groups(
  bytes: ByteArray,
  off: Int,
  len: Int,
  acc: Int,
  out_len: Int,
) -> ByteArray {
  if off + 3 <= len {
    // 24-bit group -> 4 chars: bits 18-23, 12-17, 6-11, 0-5.
    let n = bytearray.to_int_big_endian(bytearray.slice(bytes, off, off + 2))
    let quad = (
      ( char(n / 262144) * 256 + char(n / 4096 % 64) ) * 256 + char(n / 64 % 64)
    ) * 256 + char(n % 64)
    encode_groups(bytes, off + 3, len, acc * 4294967296 + quad, out_len)
  } else if off + 2 == len {
    // 16-bit tail -> 3 chars: bits 10-15, 4-9, then bits 0-3 shifted
    // left 2 (RFC 4648 zero-fill).
    let n = bytearray.to_int_big_endian(bytearray.slice(bytes, off, off + 1))
    let triple = ( char(n / 1024) * 256 + char(n / 16 % 64) ) * 256 + char(
      n % 16 * 4,
    )
    bytearray.from_int_big_endian(acc * 16777216 + triple, out_len)
  } else if off + 1 == len {
    // 8-bit tail -> 2 chars: bits 2-7, then bits 0-1 shifted left 4.
    let n = bytearray.at(bytes, off)
    let pair = char(n / 4) * 256 + char(n % 4 * 16)
    bytearray.from_int_big_endian(acc * 65536 + pair, out_len)
  } else {
    // off == len: the input length was a multiple of 3.
    bytearray.from_int_big_endian(acc, out_len)
  }
}
