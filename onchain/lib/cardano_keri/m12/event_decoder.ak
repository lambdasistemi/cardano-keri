//// S0 port of the INV-BIND bytes-only establishment decoder from
//// sibling #291. That work is UNMERGED and PENDING: it exists only as
//// proven commits on `feat/291-inv-bind` and is not on `main`.
////
//// Source: cardano-keri@d57e4354ac03cca9f64165e762626bd2a279e944
//// (`fix(291): remove obsolete integer array helper`), which descends
//// from 7f49dd8b64dbbc9a10d08f257c8b1e39dcf0dddb
//// (`fix(291): restore p/di parity from event bytes`), file
//// `onchain/lib/cardano_keri/checkpoint/event_decoder.ak`. Copied into
//// the owned M12 namespace so S0 does not edit legacy M1 files. The
//// copy is faithful: the whole textual difference is `aiken fmt` line
//// wrapping and record-field punning, with no semantic edit.
////
//// Because the dependency is unmerged, the measured `append` and
//// `cursor` rows in specs/m11-s0-size-failfast/SIZE-REPORT.md are
//// measurements of code `main` does not yet have. If #291 changes
//// before it lands, both rows must be remeasured.
////
//// #291 bytes-only total parse of one KERI establishment event.
//// Derives variant, protected values, and SAID blanking from complete
//// event bytes. No caller offset is accepted.

use aiken/collection/list
use aiken/primitive/bytearray

/// Structural establishment-event variant.
pub type EventVariant {
  VariantIcp
  VariantDip
  VariantRot
  VariantDrt
}

/// Closed total-parse rejection.
pub type EventDecodeError {
  ErrLengthBound
  ErrVersionPrefix
  ErrVersionSize
  ErrFraming
  ErrFieldOrder
  ErrValueShape
  ErrUnsupportedType
  ErrTrailing
}

type ParseResult<a> {
  Ok(a)
  Err(EventDecodeError)
}

/// Protected raw spellings from a successful total parse.
pub type DecodedEstablishmentEvent {
  variant: EventVariant,
  said: ByteArray,
  aid: ByteArray,
  seq: ByteArray,
  prior: ByteArray,
  kt: ByteArray,
  k: List<ByteArray>,
  nt: ByteArray,
  n: List<ByteArray>,
  bt: ByteArray,
  b: List<ByteArray>,
  br: List<ByteArray>,
  ba: List<ByteArray>,
  di: ByteArray,
  said_preimage: ByteArray,
}

/// Decode verdict.
pub type EventDecodeVerdict {
  DecodeOk(DecodedEstablishmentEvent)
  DecodeErr(EventDecodeError)
}

const hashes_44: ByteArray = "############################################"

/// Decode one bounded establishment event from bytes alone.
pub fn decode_establishment_event(raw: ByteArray) -> EventDecodeVerdict {
  let n = bytearray.length(raw)
  if n < 1 || n > 1024 {
    DecodeErr(ErrLengthBound)
  } else {
    when parse_object(raw) is {
      Err(e) -> DecodeErr(e)
      Ok(fields) ->
        when fields is {
          [(v_name, v_val, _), ..rest] ->
            if v_name != "v" {
              DecodeErr(ErrFieldOrder)
            } else {
              when check_version(n, v_val) is {
                Err(e) -> DecodeErr(e)
                Ok(_) -> assemble(rest, raw)
              }
            }
          [] -> DecodeErr(ErrFieldOrder)
        }
    }
  }
}

/// SAID-blanked preimage from a successful total parse.
pub fn decode_said_preimage(raw: ByteArray) -> EventDecodeVerdict {
  decode_establishment_event(raw)
}

fn check_version(n: Int, v: ByteArray) -> ParseResult<Int> {
  if bytearray.length(v) != 17 {
    Err(ErrVersionPrefix)
  } else if bytearray.take(v, 10) != "KERI10JSON" {
    Err(ErrVersionPrefix)
  } else if byte_at(v, 16) != 95 {
    Err(ErrVersionPrefix)
  } else {
    when parse_hex6(bytearray.take(bytearray.drop(v, 10), 6)) is {
      Err(e) -> Err(e)
      Ok(size) ->
        if size == n {
          Ok(size)
        } else {
          Err(ErrVersionSize)
        }
    }
  }
}

fn parse_hex6(bs: ByteArray) -> ParseResult<Int> {
  hex_acc(bs, 0, 0)
}

fn hex_acc(bs: ByteArray, i: Int, acc: Int) -> ParseResult<Int> {
  if i == 6 {
    Ok(acc)
  } else {
    when hex_digit(byte_at(bs, i)) is {
      None -> Err(ErrVersionPrefix)
      Some(d) -> hex_acc(bs, i + 1, acc * 16 + d)
    }
  }
}

fn hex_digit(c: Int) -> Option<Int> {
  if c >= 48 && c <= 57 {
    Some(c - 48)
  } else if c >= 97 && c <= 102 {
    Some(c - 87)
  } else {
    None
  }
}

fn parse_object(
  raw: ByteArray,
) -> ParseResult<List<(ByteArray, ByteArray, Int)>> {
  let n = bytearray.length(raw)
  if n < 2 || byte_at(raw, 0) != 123 || byte_at(raw, n - 1) != 125 {
    Err(ErrFraming)
  } else {
    when parse_fields(raw, 1, []) is {
      Err(e) -> Err(e)
      Ok((fs, i)) ->
        if i == n - 1 {
          Ok(list.reverse(fs))
        } else {
          Err(ErrTrailing)
        }
    }
  }
}

fn parse_fields(
  raw: ByteArray,
  i: Int,
  acc: List<(ByteArray, ByteArray, Int)>,
) -> ParseResult<(List<(ByteArray, ByteArray, Int)>, Int)> {
  if byte_at(raw, i) == 125 {
    Ok((acc, i))
  } else {
    when parse_string(raw, i) is {
      Err(e) -> Err(e)
      Ok((name, i1)) ->
        if byte_at(raw, i1) != 58 {
          Err(ErrFraming)
        } else {
          when parse_value(raw, i1 + 1) is {
            Err(e) -> Err(e)
            Ok((val, start, i2)) -> {
              let acc2 = [(name, val, start), ..acc]
              if byte_at(raw, i2) == 44 {
                parse_fields(raw, i2 + 1, acc2)
              } else if byte_at(raw, i2) == 125 {
                Ok((acc2, i2))
              } else {
                Err(ErrFraming)
              }
            }
          }
        }
    }
  }
}

fn parse_string(raw: ByteArray, i: Int) -> ParseResult<(ByteArray, Int)> {
  if byte_at(raw, i) != 34 {
    Err(ErrFraming)
  } else {
    scan_string(raw, i + 1, i + 1)
  }
}

fn scan_string(
  raw: ByteArray,
  j: Int,
  start: Int,
) -> ParseResult<(ByteArray, Int)> {
  if j >= bytearray.length(raw) {
    Err(ErrFraming)
  } else if byte_at(raw, j) == 92 {
    Err(ErrFraming)
  } else if byte_at(raw, j) == 34 {
    Ok((bytearray.take(bytearray.drop(raw, start), j - start), j + 1))
  } else {
    scan_string(raw, j + 1, start)
  }
}

fn parse_value(raw: ByteArray, i: Int) -> ParseResult<(ByteArray, Int, Int)> {
  if byte_at(raw, i) == 34 {
    when parse_string(raw, i) is {
      Err(e) -> Err(e)
      Ok((content, j)) -> Ok((content, i + 1, j))
    }
  } else if byte_at(raw, i) == 91 {
    when skip_array(raw, i + 1, 1, False) is {
      Err(e) -> Err(e)
      Ok(j) -> Ok((bytearray.take(bytearray.drop(raw, i), j - i), i, j))
    }
  } else {
    Err(ErrValueShape)
  }
}

fn skip_array(
  raw: ByteArray,
  j: Int,
  depth: Int,
  in_str: Bool,
) -> ParseResult<Int> {
  if j >= bytearray.length(raw) {
    Err(ErrFraming)
  } else if in_str && byte_at(raw, j) == 92 {
    Err(ErrFraming)
  } else if in_str && byte_at(raw, j) == 34 {
    skip_array(raw, j + 1, depth, False)
  } else if in_str {
    skip_array(raw, j + 1, depth, True)
  } else if byte_at(raw, j) == 34 {
    skip_array(raw, j + 1, depth, True)
  } else if byte_at(raw, j) == 91 {
    skip_array(raw, j + 1, depth + 1, False)
  } else if byte_at(raw, j) == 93 {
    if depth == 1 {
      Ok(j + 1)
    } else {
      skip_array(raw, j + 1, depth - 1, False)
    }
  } else {
    skip_array(raw, j + 1, depth, False)
  }
}

fn assemble(
  rest: List<(ByteArray, ByteArray, Int)>,
  raw: ByteArray,
) -> EventDecodeVerdict {
  when rest is {
    [] -> DecodeErr(ErrFieldOrder)
    [(t_name, t_val, _), ..] ->
      if t_name != "t" {
        DecodeErr(ErrFieldOrder)
      } else {
        when parse_type(t_val) is {
          Err(e) -> DecodeErr(e)
          Ok(variant) ->
            if field_names(rest) != expected_names(variant) {
              DecodeErr(ErrFieldOrder)
            } else {
              finish(variant, rest, raw)
            }
        }
      }
  }
}

fn finish(
  variant: EventVariant,
  rest: List<(ByteArray, ByteArray, Int)>,
  raw: ByteArray,
) -> EventDecodeVerdict {
  when
    (
      req("d", rest),
      req("i", rest),
      req("s", rest),
      req("kt", rest),
      req_list("k", rest),
      req("nt", rest),
      req_list("n", rest),
      req("bt", rest),
      start_of("d", rest),
      start_of("i", rest),
    )
  is {
    (
      Ok(said),
      Ok(aid),
      Ok(seq),
      Ok(kt),
      Ok(k),
      Ok(nt),
      Ok(n),
      Ok(bt),
      Ok(d_start),
      Ok(i_start),
    ) ->
      if bytearray.length(said) != 44 || bytearray.length(aid) != 44 {
        DecodeErr(ErrValueShape)
      } else {
        DecodeOk(
          DecodedEstablishmentEvent {
            variant,
            said,
            aid,
            seq,
            prior: prior_of(variant, rest),
            kt,
            k,
            nt,
            n,
            bt,
            b: list_of_icp(variant, rest),
            br: list_of_rot(variant, rest, "br"),
            ba: list_of_rot(variant, rest, "ba"),
            di: di_of(variant, rest),
            said_preimage: blank(raw, d_start, i_start),
          },
        )
      }
    _ -> DecodeErr(ErrFieldOrder)
  }
}

fn parse_type(t: ByteArray) -> ParseResult<EventVariant> {
  if t == "icp" {
    Ok(VariantIcp)
  } else if t == "dip" {
    Ok(VariantDip)
  } else if t == "rot" {
    Ok(VariantRot)
  } else if t == "drt" {
    Ok(VariantDrt)
  } else {
    Err(ErrUnsupportedType)
  }
}

fn expected_names(v: EventVariant) -> List<ByteArray> {
  when v is {
    VariantIcp ->
      ["t", "d", "i", "s", "kt", "k", "nt", "n", "bt", "b", "c", "a"]
    VariantDip ->
      ["t", "d", "i", "s", "kt", "k", "nt", "n", "bt", "b", "c", "a", "di"]
    VariantRot ->
      ["t", "d", "i", "s", "p", "kt", "k", "nt", "n", "bt", "br", "ba", "a"]
    VariantDrt ->
      ["t", "d", "i", "s", "p", "kt", "k", "nt", "n", "bt", "br", "ba", "a"]
  }
}

fn field_names(fs: List<(ByteArray, ByteArray, Int)>) -> List<ByteArray> {
  list.map(fs, fn(f) { f.1st })
}

fn req(
  name: ByteArray,
  fs: List<(ByteArray, ByteArray, Int)>,
) -> ParseResult<ByteArray> {
  when list.filter(fs, fn(f) { f.1st == name }) is {
    [(_, v, _)] -> Ok(v)
    _ -> Err(ErrFieldOrder)
  }
}

fn req_list(
  name: ByteArray,
  fs: List<(ByteArray, ByteArray, Int)>,
) -> ParseResult<List<ByteArray>> {
  when req(name, fs) is {
    Err(e) -> Err(e)
    Ok(raw) -> parse_string_array(raw)
  }
}

fn start_of(
  name: ByteArray,
  fs: List<(ByteArray, ByteArray, Int)>,
) -> ParseResult<Int> {
  when list.filter(fs, fn(f) { f.1st == name }) is {
    [(_, _, s)] -> Ok(s)
    _ -> Err(ErrFieldOrder)
  }
}

fn prior_of(
  variant: EventVariant,
  fs: List<(ByteArray, ByteArray, Int)>,
) -> ByteArray {
  when variant is {
    VariantRot | VariantDrt ->
      when req("p", fs) is {
        Ok(v) -> v
        Err(_) -> #""
      }
    _ -> #""
  }
}

fn di_of(
  variant: EventVariant,
  fs: List<(ByteArray, ByteArray, Int)>,
) -> ByteArray {
  when variant is {
    VariantDip ->
      when req("di", fs) is {
        Ok(v) -> v
        Err(_) -> #""
      }
    _ -> #""
  }
}

fn list_of_icp(
  variant: EventVariant,
  fs: List<(ByteArray, ByteArray, Int)>,
) -> List<ByteArray> {
  when variant is {
    VariantIcp | VariantDip ->
      when req_list("b", fs) is {
        Ok(xs) -> xs
        Err(_) -> []
      }
    _ -> []
  }
}

fn list_of_rot(
  variant: EventVariant,
  fs: List<(ByteArray, ByteArray, Int)>,
  name: ByteArray,
) -> List<ByteArray> {
  when variant is {
    VariantRot | VariantDrt ->
      when req_list(name, fs) is {
        Ok(xs) -> xs
        Err(_) -> []
      }
    _ -> []
  }
}

fn parse_string_array(raw: ByteArray) -> ParseResult<List<ByteArray>> {
  let n = bytearray.length(raw)
  if n < 2 || byte_at(raw, 0) != 91 || byte_at(raw, n - 1) != 93 {
    Err(ErrValueShape)
  } else if n == 2 {
    Ok([])
  } else {
    scan_arr(raw, 1, n - 1, [])
  }
}

fn scan_arr(
  raw: ByteArray,
  i: Int,
  end: Int,
  acc: List<ByteArray>,
) -> ParseResult<List<ByteArray>> {
  if i >= end {
    Ok(list.reverse(acc))
  } else {
    when parse_string(raw, i) is {
      Err(e) -> Err(e)
      Ok((s, j)) ->
        if byte_at(raw, j) == 44 {
          scan_arr(raw, j + 1, end, [s, ..acc])
        } else if byte_at(raw, j) == 93 {
          Ok(list.reverse([s, ..acc]))
        } else {
          Err(ErrValueShape)
        }
    }
  }
}

fn blank(raw: ByteArray, d_start: Int, i_start: Int) -> ByteArray {
  bytearray.concat(
    bytearray.concat(
      bytearray.concat(
        bytearray.concat(bytearray.take(raw, d_start), hashes_44),
        bytearray.take(
          bytearray.drop(raw, d_start + 44),
          i_start - d_start - 44,
        ),
      ),
      hashes_44,
    ),
    bytearray.drop(raw, i_start + 44),
  )
}

fn byte_at(raw: ByteArray, i: Int) -> Int {
  if i < 0 || i >= bytearray.length(raw) {
    0
  } else {
    bytearray.at(raw, i)
  }
}
