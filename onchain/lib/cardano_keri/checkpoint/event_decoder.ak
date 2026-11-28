//// The structural reader of one signed KERI establishment event (binding A: strict parsing).
////
//// Everything the validators trust about the fields of an inception or a rotation is read here, from the exact signed
//// bytes alone: no caller supplies a position. The reader consumes exactly one compact JSON object, the fields in
//// the order of the variant, and returns the protected spellings, a typed projection of the anchor array and the
//// preimage of the event's own digest.
////
//// Profile. Compact JSON as keripy emits it: no whitespace. Strings are valid UTF-8 without raw control characters;
//// a backslash is followed by one of `" \ / b f n r t` or by `u` and four hexadecimal digits of either case (an
//// escaped surrogate, paired or lone, is admissible and its escape bytes are kept; a raw encoding of a surrogate is
//// not valid UTF-8); numbers follow the JSON grammar; the literals are `true`, `false` and `null`. The version string
//// declares the byte length of the whole event. Field values keep their canonical wire spellings: identifiers and
//// digests are 44 base64url characters, witnesses 44, hexadecimal integers have no leading zero, and which
//// spellings a registration or an advance accepts is checked by their binders, not here.
////
//// Supported variants: `icp` and `rot`. Any other type is refused.

use aiken/builtin
use aiken/primitive/bytearray

pub type EventVariant {
  VariantIcp
  VariantRot
}

pub type EventDecodeError {
  /// The length is not in 1 to 1,024.
  ErrLengthBound
  /// The version string is not `KERI10JSON`, six hexadecimal digits and `_`.
  ErrVersionPrefix
  /// The declared size differs from the length of the bytes.
  ErrVersionSize
  /// The bytes are not the compact JSON of the profile: a delimiter, a string, a number or a literal is malformed.
  ErrFraming
  /// A field is not the one the variant has at this place, or is missing or repeated.
  ErrFieldOrder
  /// A known field has a value of the wrong shape: not a string, not an array, or the wrong width or alphabet.
  ErrValueShape
  /// The type is neither `icp` nor `rot`.
  ErrUnsupportedType
  /// Bytes follow the complete event.
  ErrTrailing
}

/// The kind of one anchor element.
pub type AnchorKind {
  KindObject
  KindArray
  KindString
  KindNumber
  KindTrue
  KindFalse
  KindNull
}

/// One element of the anchor array: its kind and its exact bytes as signed.
pub type AnchorItem {
  kind: AnchorKind,
  bytes: ByteArray,
}

/// The protected spellings of a decoded event. A list field is the list of its string contents; a threshold is the
/// content of its string or the exact bytes of its array.
pub type DecodedEstablishmentEvent {
  variant: EventVariant,
  said: ByteArray,
  aid: ByteArray,
  seq: ByteArray,
  /// `p` of a rotation, empty for an inception.
  prior: ByteArray,
  kt: ByteArray,
  k: List<ByteArray>,
  nt: ByteArray,
  n: List<ByteArray>,
  bt: ByteArray,
  /// `b` of an inception, `br` of a rotation.
  b: List<ByteArray>,
  /// `ba` of a rotation, empty for an inception.
  ba: List<ByteArray>,
  anchor: List<AnchorItem>,
  /// The preimage of the event's own digest: `d` dressed, and `i` as well when the identifier is self-addressing.
  said_preimage: ByteArray,
}

pub type EventDecodeVerdict {
  DecodeOk(DecodedEstablishmentEvent)
  DecodeErr(EventDecodeError)
}

type Parsed<a> {
  Got(a, Int)
  Bad(EventDecodeError)
}

fn then(p: Parsed<a>, f: fn(a, Int) -> Parsed<b>) -> Parsed<b> {
  when p is {
    Got(x, pos) -> f(x, pos)
    Bad(e) -> Bad(e)
  }
}

// ---------------------------------------------------------------------------
// bytes
// ---------------------------------------------------------------------------

fn byte_at(raw: ByteArray, pos: Int) -> Int {
  if pos >= 0 && pos < bytearray.length(raw) {
    builtin.index_bytearray(raw, pos)
  } else {
    -1
  }
}

fn part(raw: ByteArray, start: Int, length: Int) -> ByteArray {
  builtin.slice_bytearray(start, length, raw)
}

fn has_at(raw: ByteArray, pos: Int, text: ByteArray) -> Bool {
  let n = bytearray.length(text)
  pos >= 0 && pos + n <= bytearray.length(raw) && part(raw, pos, n) == text
}

fn is_digit(b: Int) -> Bool {
  b >= 48 && b <= 57
}

fn is_hex_digit(b: Int) -> Bool {
  is_digit(b) || b >= 65 && b <= 70 || b >= 97 && b <= 102
}

fn is_lower_hex(b: Int) -> Bool {
  is_digit(b) || b >= 97 && b <= 102
}

fn is_base64url(b: Int) -> Bool {
  is_digit(b) || b >= 65 && b <= 90 || b >= 97 && b <= 122 || b == 45 || b == 95
}

fn all_bytes(raw: ByteArray, start: Int, end: Int, ok: fn(Int) -> Bool) -> Bool {
  if start >= end {
    True
  } else {
    ok(byte_at(raw, start)) && all_bytes(raw, start + 1, end, ok)
  }
}

fn hex_run(raw: ByteArray, pos: Int, count: Int) -> Bool {
  all_bytes(raw, pos, pos + count, is_hex_digit)
}

// ---------------------------------------------------------------------------
// strings: UTF-8 and escapes
// ---------------------------------------------------------------------------

fn continuation(raw: ByteArray, pos: Int, low: Int, high: Int) -> Bool {
  let b = byte_at(raw, pos)
  b >= low && b <= high
}

// The position after the one UTF-8 sequence that starts at `pos` (RFC 3629: no overlong form, no surrogate, nothing
// above U+10FFFF), or -1.
fn utf8_end(raw: ByteArray, pos: Int) -> Int {
  let b0 = byte_at(raw, pos)
  if b0 >= 0 && b0 < 128 {
    pos + 1
  } else if b0 >= 194 && b0 <= 223 {
    if continuation(raw, pos + 1, 128, 191) {
      pos + 2
    } else {
      -1
    }
  } else if b0 == 224 {
    if continuation(raw, pos + 1, 160, 191) && continuation(
      raw,
      pos + 2,
      128,
      191,
    ) {
      pos + 3
    } else {
      -1
    }
  } else if b0 == 237 {
    if continuation(raw, pos + 1, 128, 159) && continuation(
      raw,
      pos + 2,
      128,
      191,
    ) {
      pos + 3
    } else {
      -1
    }
  } else if b0 >= 225 && b0 <= 239 {
    if continuation(raw, pos + 1, 128, 191) && continuation(
      raw,
      pos + 2,
      128,
      191,
    ) {
      pos + 3
    } else {
      -1
    }
  } else if b0 == 240 {
    if continuation(raw, pos + 1, 144, 191) && continuation(
      raw,
      pos + 2,
      128,
      191,
    ) && continuation(raw, pos + 3, 128, 191) {
      pos + 4
    } else {
      -1
    }
  } else if b0 >= 241 && b0 <= 243 {
    if continuation(raw, pos + 1, 128, 191) && continuation(
      raw,
      pos + 2,
      128,
      191,
    ) && continuation(raw, pos + 3, 128, 191) {
      pos + 4
    } else {
      -1
    }
  } else if b0 == 244 {
    if continuation(raw, pos + 1, 128, 143) && continuation(
      raw,
      pos + 2,
      128,
      191,
    ) && continuation(raw, pos + 3, 128, 191) {
      pos + 4
    } else {
      -1
    }
  } else {
    -1
  }
}

// The position after the closing quote of the string whose content starts at `pos`, or -1.
fn string_after(raw: ByteArray, pos: Int) -> Int {
  let b = byte_at(raw, pos)
  if b == 34 {
    pos + 1
  } else if b == 92 {
    let e = byte_at(raw, pos + 1)
    if e == 117 {
      if hex_run(raw, pos + 2, 4) {
        string_after(raw, pos + 6)
      } else {
        -1
      }
    } else if e == 34 || e == 92 || e == 47 || e == 98 || e == 102 || e == 110 || e == 114 || e == 116 {
      string_after(raw, pos + 2)
    } else {
      -1
    }
  } else if b < 32 {
    -1
  } else {
    let next = utf8_end(raw, pos)
    if next < 0 {
      -1
    } else {
      string_after(raw, next)
    }
  }
}

// ---------------------------------------------------------------------------
// numbers, literals and containers
// ---------------------------------------------------------------------------

fn digits_end(raw: ByteArray, pos: Int) -> Int {
  if is_digit(byte_at(raw, pos)) {
    digits_end(raw, pos + 1)
  } else {
    pos
  }
}

// The position after the JSON number at `pos`, or -1.
fn number_after(raw: ByteArray, pos: Int) -> Int {
  let start = if byte_at(raw, pos) == 45 {
    pos + 1
  } else {
    pos
  }
  let lead = byte_at(raw, start)
  let integer_end = if lead == 48 {
    start + 1
  } else if lead >= 49 && lead <= 57 {
    digits_end(raw, start + 1)
  } else {
    -1
  }
  if integer_end < 0 {
    -1
  } else {
    let fraction_end = if byte_at(raw, integer_end) == 46 {
      let end = digits_end(raw, integer_end + 1)
      if end == integer_end + 1 {
        -1
      } else {
        end
      }
    } else {
      integer_end
    }
    if fraction_end < 0 {
      -1
    } else {
      let marker = byte_at(raw, fraction_end)
      if marker == 101 || marker == 69 {
        let sign = byte_at(raw, fraction_end + 1)
        let from = if sign == 43 || sign == 45 {
          fraction_end + 2
        } else {
          fraction_end + 1
        }
        let end = digits_end(raw, from)
        if end == from {
          -1
        } else {
          end
        }
      } else {
        fraction_end
      }
    }
  }
}

// The kind and the end of the compact JSON value at `pos`; the end is -1 when it is malformed.
fn value_after(raw: ByteArray, pos: Int) -> (AnchorKind, Int) {
  let b = byte_at(raw, pos)
  if b == 34 {
    (KindString, string_after(raw, pos + 1))
  } else if b == 91 {
    (KindArray, array_after(raw, pos))
  } else if b == 123 {
    (KindObject, object_after(raw, pos))
  } else if has_at(raw, pos, "true") {
    (KindTrue, pos + 4)
  } else if has_at(raw, pos, "false") {
    (KindFalse, pos + 5)
  } else if has_at(raw, pos, "null") {
    (KindNull, pos + 4)
  } else if b == 45 || is_digit(b) {
    (KindNumber, number_after(raw, pos))
  } else {
    (KindNull, -1)
  }
}

fn array_after(raw: ByteArray, pos: Int) -> Int {
  if has_at(raw, pos, "[]") {
    pos + 2
  } else {
    elements_after(raw, pos + 1)
  }
}

fn elements_after(raw: ByteArray, pos: Int) -> Int {
  let (_, end) = value_after(raw, pos)
  if end < 0 {
    -1
  } else if has_at(raw, end, ",") {
    elements_after(raw, end + 1)
  } else if has_at(raw, end, "]") {
    end + 1
  } else {
    -1
  }
}

fn object_after(raw: ByteArray, pos: Int) -> Int {
  if has_at(raw, pos, "{}") {
    pos + 2
  } else {
    members_after(raw, pos + 1)
  }
}

fn members_after(raw: ByteArray, pos: Int) -> Int {
  if byte_at(raw, pos) != 34 {
    -1
  } else {
    let after_name = string_after(raw, pos + 1)
    if after_name < 0 || byte_at(raw, after_name) != 58 {
      -1
    } else {
      let (_, end) = value_after(raw, after_name + 1)
      if end < 0 {
        -1
      } else if has_at(raw, end, ",") {
        members_after(raw, end + 1)
      } else if has_at(raw, end, "}") {
        end + 1
      } else {
        -1
      }
    }
  }
}

// ---------------------------------------------------------------------------
// the fields
// ---------------------------------------------------------------------------

// The position after `name` when `raw` has it at `pos`; otherwise the field is not the one expected here.
fn key(raw: ByteArray, pos: Int, name: ByteArray) -> Parsed<Int> {
  if has_at(raw, pos, name) {
    Got(0, pos + bytearray.length(name))
  } else if has_at(raw, pos, ",\"") {
    // another member name here: a lexically malformed one is a framing error, a valid one the wrong field
    if string_after(raw, pos + 2) < 0 {
      Bad(ErrFraming)
    } else {
      Bad(ErrFieldOrder)
    }
  } else {
    Bad(ErrFraming)
  }
}

// Any lexically valid string at `pos`: its content, spelling kept (escapes unexpanded). Which spellings a field
// accepts is the business of the binder that compares it.
fn any_string(raw: ByteArray, pos: Int) -> Parsed<ByteArray> {
  if byte_at(raw, pos) != 34 {
    Bad(ErrValueShape)
  } else {
    let after = string_after(raw, pos + 1)
    if after < 0 {
      Bad(ErrFraming)
    } else {
      Got(part(raw, pos + 1, after - pos - 2), after)
    }
  }
}

// A string of `width` characters of the base64url alphabet at `pos`, which is the position of its opening quote.
fn fixed_string(raw: ByteArray, pos: Int, width: Int) -> Parsed<ByteArray> {
  if byte_at(raw, pos) != 34 {
    Bad(ErrValueShape)
  } else {
    let after = string_after(raw, pos + 1)
    if after < 0 {
      Bad(ErrFraming)
    } else if after - pos - 2 != width || !all_bytes(
      raw,
      pos + 1,
      pos + 1 + width,
      is_base64url,
    ) {
      Bad(ErrValueShape)
    } else {
      Got(part(raw, pos + 1, width), after)
    }
  }
}

// A string of lowercase hexadecimal digits without a leading zero (but `0` itself).
fn hex_string(raw: ByteArray, pos: Int) -> Parsed<ByteArray> {
  if byte_at(raw, pos) != 34 {
    Bad(ErrValueShape)
  } else {
    let after = string_after(raw, pos + 1)
    let length = after - pos - 2
    if after < 0 {
      Bad(ErrFraming)
    } else if length < 1 || !all_bytes(
      raw,
      pos + 1,
      pos + 1 + length,
      is_lower_hex,
    ) {
      Bad(ErrValueShape)
    } else if length > 1 && byte_at(raw, pos + 1) == 48 {
      Bad(ErrValueShape)
    } else {
      Got(part(raw, pos + 1, length), after)
    }
  }
}

// A threshold: a hexadecimal string, or an array of strings and arrays (its exact bytes).
fn threshold(raw: ByteArray, pos: Int) -> Parsed<ByteArray> {
  let b = byte_at(raw, pos)
  if b == 34 {
    hex_string(raw, pos)
  } else if b == 91 {
    let (_, end) = value_after(raw, pos)
    if end < 0 {
      Bad(ErrFraming)
    } else {
      Got(part(raw, pos, end - pos), end)
    }
  } else {
    Bad(ErrValueShape)
  }
}

// An array of strings of `width` characters (`[]` included).
fn fixed_list(raw: ByteArray, pos: Int, width: Int) -> Parsed<List<ByteArray>> {
  if byte_at(raw, pos) != 91 {
    Bad(ErrValueShape)
  } else if has_at(raw, pos, "[]") {
    Got([], pos + 2)
  } else {
    fixed_items(raw, pos + 1, width)
  }
}

fn fixed_items(raw: ByteArray, pos: Int, width: Int) -> Parsed<List<ByteArray>> {
  when fixed_string(raw, pos, width) is {
    Bad(e) -> Bad(e)
    Got(item, after) ->
      if has_at(raw, after, ",") {
        when fixed_items(raw, after + 1, width) is {
          Got(rest, end) -> Got([item, ..rest], end)
          Bad(e) -> Bad(e)
        }
      } else if has_at(raw, after, "]") {
        Got([item], after + 1)
      } else if byte_at(raw, after) < 0 {
        Bad(ErrFraming)
      } else {
        Bad(ErrFraming)
      }
  }
}

// The configuration traits of an inception: an array of strings (any content of the string grammar).
fn trait_list(raw: ByteArray, pos: Int) -> Parsed<Int> {
  if byte_at(raw, pos) != 91 {
    Bad(ErrValueShape)
  } else {
    let end = array_after(raw, pos)
    if end < 0 {
      Bad(ErrFraming)
    } else {
      Got(0, end)
    }
  }
}

// The anchor array: each element a complete compact JSON value, with its kind and exact bytes.
/// The anchor array at `pos` and the position after it: the one scanner the rebuilt binding needs.
pub fn anchor_after(raw: ByteArray, pos: Int) -> Option<(List<AnchorItem>, Int)> {
  when anchor_array(raw, pos) is {
    Got(items, end) -> Some((items, end))
    Bad(_) -> None
  }
}

fn anchor_array(raw: ByteArray, pos: Int) -> Parsed<List<AnchorItem>> {
  if byte_at(raw, pos) != 91 {
    Bad(ErrValueShape)
  } else if has_at(raw, pos, "[]") {
    Got([], pos + 2)
  } else {
    anchor_items(raw, pos + 1)
  }
}

fn anchor_items(raw: ByteArray, pos: Int) -> Parsed<List<AnchorItem>> {
  let (kind, end) = value_after(raw, pos)
  if end < 0 {
    Bad(ErrFraming)
  } else {
    let item = AnchorItem { kind, bytes: part(raw, pos, end - pos) }
    if has_at(raw, end, ",") {
      when anchor_items(raw, end + 1) is {
        Got(rest, last) -> Got([item, ..rest], last)
        Bad(e) -> Bad(e)
      }
    } else if has_at(raw, end, "]") {
      Got([item], end + 1)
    } else {
      Bad(ErrFraming)
    }
  }
}

// ---------------------------------------------------------------------------
// the event
// ---------------------------------------------------------------------------

/// The digest dressing: forty-four `#`.
const dress: ByteArray = "############################################"

fn blank(raw: ByteArray, start: Int) -> ByteArray {
  bytearray.concat(
    bytearray.concat(part(raw, 0, start), dress),
    bytearray.drop(raw, start + 44),
  )
}

/// Decode one establishment event from its exact signed bytes.
pub fn decode_establishment_event(raw: ByteArray) -> EventDecodeVerdict {
  let length = bytearray.length(raw)
  if length < 1 || length > 1024 {
    DecodeErr(ErrLengthBound)
  } else if !has_at(raw, 0, "{\"v\":\"KERI10JSON") || !hex_run(raw, 16, 6) || !has_at(
    raw,
    22,
    "_\"",
  ) {
    DecodeErr(ErrVersionPrefix)
  } else if bytearray.length(raw) != hex_value(raw, 16, 6, 0) {
    DecodeErr(ErrVersionSize)
  } else if !has_at(raw, 24, ",\"t\":\"") {
    DecodeErr(ErrFieldOrder)
  } else if has_at(raw, 30, "icp\",") {
    decode_variant(raw, VariantIcp)
  } else if has_at(raw, 30, "rot\",") {
    decode_variant(raw, VariantRot)
  } else {
    DecodeErr(ErrUnsupportedType)
  }
}

fn hex_value(raw: ByteArray, pos: Int, count: Int, acc: Int) -> Int {
  if count == 0 {
    acc
  } else {
    let b = byte_at(raw, pos)
    let digit = if b <= 57 {
      b - 48
    } else if b <= 70 {
      b - 55
    } else {
      b - 87
    }
    hex_value(raw, pos + 1, count - 1, acc * 16 + digit)
  }
}

fn decode_variant(raw: ByteArray, variant: EventVariant) -> EventDecodeVerdict {
  // `,"d":"` follows the type
  let parsed = key(raw, 34, ",\"d\":")
    |> then(fn(_, p) { fixed_string(raw, p, 44) })
    |> then(
        fn(said, p) {
          key(raw, p, ",\"i\":")
            |> then(fn(_, q) { fixed_string(raw, q, 44) })
            |> then(
                fn(aid, q) {
                  key(raw, q, ",\"s\":")
                    |> then(fn(_, r) { any_string(raw, r) })
                    |> then(fn(seq, r) { Got((said, aid, seq), r) })
                },
              )
        },
      )
  when parsed is {
    Bad(e) -> DecodeErr(e)
    Got((said, aid, seq), p) ->
      when variant is {
        VariantIcp -> decode_icp(raw, said, aid, seq, p)
        VariantRot -> decode_rot(raw, said, aid, seq, p)
      }
  }
}

fn decode_icp(
  raw: ByteArray,
  said: ByteArray,
  aid: ByteArray,
  seq: ByteArray,
  p: Int,
) -> EventDecodeVerdict {
  let parsed = key(raw, p, ",\"kt\":")
    |> then(fn(_, q) { threshold(raw, q) })
    |> then(
        fn(kt, q) {
          key(raw, q, ",\"k\":")
            |> then(fn(_, r) { fixed_list(raw, r, 44) })
            |> then(
                fn(k, r) {
                  key(raw, r, ",\"nt\":")
                    |> then(fn(_, s) { threshold(raw, s) })
                    |> then(
                        fn(nt, s) {
                          key(raw, s, ",\"n\":")
                            |> then(fn(_, t) { fixed_list(raw, t, 44) })
                            |> then(
                                fn(n, t) {
                                  key(raw, t, ",\"bt\":")
                                    |> then(fn(_, u) { hex_string(raw, u) })
                                    |> then(
                                        fn(bt, u) {
                                          key(raw, u, ",\"b\":")
                                            |> then(
                                                fn(_, v) {
                                                  fixed_list(raw, v, 44)
                                                },
                                              )
                                            |> then(
                                                fn(b, v) {
                                                  key(raw, v, ",\"c\":")
                                                    |> then(
                                                        fn(_, w) {
                                                          trait_list(raw, w)
                                                        },
                                                      )
                                                    |> then(
                                                        fn(_, w) {
                                                          key(raw, w, ",\"a\":")
                                                            |> then(
                                                                fn(_, x) {
                                                                  anchor_array(
                                                                    raw,
                                                                    x,
                                                                  )
                                                                },
                                                              )
                                                            |> then(
                                                                fn(anchor, x) {
                                                                  Got(
                                                                    (
                                                                      kt,
                                                                      k,
                                                                      nt,
                                                                      n,
                                                                      bt,
                                                                      b,
                                                                      anchor,
                                                                    ),
                                                                    x,
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
                },
              )
        },
      )
  when parsed is {
    Bad(e) -> DecodeErr(e)
    Got((kt, k, nt, n, bt, b, anchor), end) ->
      finish(
        raw,
        end,
        DecodedEstablishmentEvent {
          variant: VariantIcp,
          said,
          aid,
          seq,
          prior: "",
          kt,
          k,
          nt,
          n,
          bt,
          b,
          ba: [],
          anchor,
          said_preimage: preimage(raw, said, aid),
        },
      )
  }
}

fn decode_rot(
  raw: ByteArray,
  said: ByteArray,
  aid: ByteArray,
  seq: ByteArray,
  p: Int,
) -> EventDecodeVerdict {
  let parsed = key(raw, p, ",\"p\":")
    |> then(fn(_, q) { fixed_string(raw, q, 44) })
    |> then(
        fn(prior, q) {
          key(raw, q, ",\"kt\":")
            |> then(fn(_, r) { threshold(raw, r) })
            |> then(
                fn(kt, r) {
                  key(raw, r, ",\"k\":")
                    |> then(fn(_, s) { fixed_list(raw, s, 44) })
                    |> then(
                        fn(k, s) {
                          key(raw, s, ",\"nt\":")
                            |> then(fn(_, t) { threshold(raw, t) })
                            |> then(
                                fn(nt, t) {
                                  key(raw, t, ",\"n\":")
                                    |> then(fn(_, u) { fixed_list(raw, u, 44) })
                                    |> then(
                                        fn(n, u) {
                                          key(raw, u, ",\"bt\":")
                                            |> then(
                                                fn(_, v) { hex_string(raw, v) },
                                              )
                                            |> then(
                                                fn(bt, v) {
                                                  key(raw, v, ",\"br\":")
                                                    |> then(
                                                        fn(_, w) {
                                                          fixed_list(raw, w, 44)
                                                        },
                                                      )
                                                    |> then(
                                                        fn(br, w) {
                                                          key(
                                                            raw,
                                                            w,
                                                            ",\"ba\":",
                                                          )
                                                            |> then(
                                                                fn(_, x) {
                                                                  fixed_list(
                                                                    raw,
                                                                    x,
                                                                    44,
                                                                  )
                                                                },
                                                              )
                                                            |> then(
                                                                fn(ba, x) {
                                                                  key(
                                                                    raw,
                                                                    x,
                                                                    ",\"a\":",
                                                                  )
                                                                    |> then(
                                                                        fn(_, y) {
                                                                          anchor_array(
                                                                            raw,
                                                                            y,
                                                                          )
                                                                        },
                                                                      )
                                                                    |> then(
                                                                        fn(
                                                                          anchor,
                                                                          y,
                                                                        ) {
                                                                          Got(
                                                                            (
                                                                              prior,
                                                                              kt,
                                                                              k,
                                                                              nt,
                                                                              n,
                                                                              bt,
                                                                              br,
                                                                              ba,
                                                                              anchor,
                                                                            ),
                                                                            y,
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
                        },
                      )
                },
              )
        },
      )
  when parsed is {
    Bad(e) -> DecodeErr(e)
    Got((prior, kt, k, nt, n, bt, br, ba, anchor), end) ->
      finish(
        raw,
        end,
        DecodedEstablishmentEvent {
          variant: VariantRot,
          said,
          aid,
          seq,
          prior,
          kt,
          k,
          nt,
          n,
          bt,
          b: br,
          ba,
          anchor,
          said_preimage: preimage(raw, said, aid),
        },
      )
  }
}

// The object closes with the last byte.
fn finish(
  raw: ByteArray,
  end: Int,
  event: DecodedEstablishmentEvent,
) -> EventDecodeVerdict {
  if byte_at(raw, end) != 125 {
    DecodeErr(ErrFraming)
  } else if end + 1 != bytearray.length(raw) {
    DecodeErr(ErrTrailing)
  } else {
    DecodeOk(event)
  }
}

// `d` dressed; `i` dressed as well when the identifier is self-addressing (a digest code), kept when it is a key.
fn preimage(raw: ByteArray, said: ByteArray, aid: ByteArray) -> ByteArray {
  let d_start = 40
  let dressed = blank(raw, d_start)
  let first = bytearray.take(aid, 1)
  let self_addressing = aid == said || first == "E" || first == "F" || first == "G" || first == "H" || first == "I"
  if self_addressing {
    blank(dressed, 91)
  } else {
    dressed
  }
}
