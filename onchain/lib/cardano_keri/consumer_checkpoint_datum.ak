//// The consumer's datum decoder (#343): the Lean `CardanoKeri.CheckpointDatum`
//// decoder (lean/CardanoKeri/CheckpointDatum.lean), declaration by
//// declaration, over the inline datum as Plutus `Data`.
////
//// Lean name -> Aiken: bool? -> bool, nat? -> nat, byteString? -> byte_string,
//// bytesList? -> bytes_list, weight? -> weight, clause? -> clause, threshold?
//// -> threshold, keyMaterial? -> key_material, decodeData -> decode_data,
//// decode -> decode.
////
//// The datum is version 2 only: constructor 1 with one field, which is a live
//// datum (constructor 0, eight fields) or a termination-pending datum
//// (constructor 1, four fields). Every shape error anywhere in the datum,
//// including inside the key material, is a refusal. The fields it reads are
//// validated (`sn`, `epoch` and `born_at` non-negative; `aid` and `refund_to`
//// byte strings); the key material is read for its shape only. The pool is
//// not in the datum and decodes as 0.
////
//// The decoder is total. Plutus unwrapping builtins abort on the wrong kind
//// of `Data`, so every unwrap here follows a kind test (`choose_data`):
//// a datum the decoder does not accept is `None`, never a failure, and a
//// relying contract that scans reference inputs skips it.
////
//// The raw-bytes layer of the Lean (`parse`, `ofBytes?`, `cbor`) has no
//// counterpart here: on chain the ledger delivers the inline datum already as
//// `Data`. Tests read the vectors' bytes with `aiken/cbor.deserialise`, which
//// stands in for the ledger's parse. Not for mainnet.

use aiken/builtin
use cardano_keri/consumer.{
  DecodedDatum, Hash, Live, Present, PublishedRelease, TerminationPending,
}
use cardano_keri/consumer_identity_bytes.{pack}

/// Lean `Threshold`.
pub type Threshold {
  Unweighted(Int)
  Weighted(List<List<(Int, Int)>>)
}

/// Lean `KeyMaterial`: the key material a checkpoint carries and the
/// consumer does not read.
pub type KeyMaterial {
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  witnesses: List<ByteArray>,
  toad: Int,
}

fn is_constr(d: Data) -> Bool {
  builtin.choose_data(d, True, False, False, False, False)
}

fn is_list(d: Data) -> Bool {
  builtin.choose_data(d, False, False, True, False, False)
}

fn is_int(d: Data) -> Bool {
  builtin.choose_data(d, False, False, False, True, False)
}

fn is_bytes(d: Data) -> Bool {
  builtin.choose_data(d, False, False, False, False, True)
}

/// The fields of a constructor of this index; any other `Data` is `None`.
fn constr_fields(d: Data, index: Int) -> Option<List<Data>> {
  if is_constr(d) {
    let Pair(i, fields) = builtin.un_constr_data(d)
    if i == index {
      Some(fields)
    } else {
      None
    }
  } else {
    None
  }
}

/// Lean `List.mapM` in `Option`.
fn map_m(xs: List<a>, f: fn(a) -> Option<b>) -> Option<List<b>> {
  when xs is {
    [] -> Some([])
    [x, ..rest] ->
      when f(x) is {
        None -> None
        Some(y) ->
          when map_m(rest, f) is {
            None -> None
            Some(ys) -> Some([y, ..ys])
          }
      }
  }
}

/// Lean `bool?`: `False` is constructor 0 and `True` constructor 1, no fields.
pub fn bool(d: Data) -> Option<Bool> {
  when constr_fields(d, 0) is {
    Some([]) -> Some(False)
    _ ->
      when constr_fields(d, 1) is {
        Some([]) -> Some(True)
        _ -> None
      }
  }
}

/// Lean `nat?`: a non-negative integer.
pub fn nat(d: Data) -> Option<Int> {
  if is_int(d) {
    let n = builtin.un_i_data(d)
    if n >= 0 {
      Some(n)
    } else {
      None
    }
  } else {
    None
  }
}

/// Lean `byteString?`: a byte string of bytes.
pub fn byte_string(d: Data) -> Option<ByteArray> {
  if is_bytes(d) {
    Some(builtin.un_b_data(d))
  } else {
    None
  }
}

/// Lean `bytesShape?`: the elements of `bytes_list`.
fn bytes_shape(d: Data) -> Option<ByteArray> {
  byte_string(d)
}

/// Lean `bytesList?`: a list of byte strings.
pub fn bytes_list(d: Data) -> Option<List<ByteArray>> {
  if is_list(d) {
    map_m(builtin.un_list_data(d), bytes_shape)
  } else {
    None
  }
}

/// Lean `weight?`: a weight `num/den` is constructor 0 with two integers.
pub fn weight(d: Data) -> Option<(Int, Int)> {
  when constr_fields(d, 0) is {
    Some([n, den]) ->
      if is_int(n) && is_int(den) {
        Some((builtin.un_i_data(n), builtin.un_i_data(den)))
      } else {
        None
      }
    _ -> None
  }
}

/// Lean `clause?`: a list of weights.
pub fn clause(d: Data) -> Option<List<(Int, Int)>> {
  if is_list(d) {
    map_m(builtin.un_list_data(d), weight)
  } else {
    None
  }
}

/// Lean `threshold?`: unweighted is constructor 0 with an integer, weighted
/// is constructor 1 with a list of clauses.
pub fn threshold(d: Data) -> Option<Threshold> {
  when constr_fields(d, 0) is {
    Some([m]) ->
      if is_int(m) {
        Some(Unweighted(builtin.un_i_data(m)))
      } else {
        None
      }
    _ ->
      when constr_fields(d, 1) is {
        Some([cs]) ->
          if is_list(cs) {
            when map_m(builtin.un_list_data(cs), clause) is {
              Some(clauses) -> Some(Weighted(clauses))
              None -> None
            }
          } else {
            None
          }
        _ -> None
      }
  }
}

/// Lean `keyMaterial?`: constructor 0 with six fields.
pub fn key_material(d: Data) -> Option<KeyMaterial> {
  when constr_fields(d, 0) is {
    Some([ck, ct, nk, nt, ws, toad]) ->
      when (bytes_list(ck), threshold(ct), bytes_list(nk), threshold(nt)) is {
        (
          Some(cur_keys),
          Some(cur_threshold),
          Some(next_keys),
          Some(next_threshold),
        ) ->
          when bytes_list(ws) is {
            Some(witnesses) ->
              if is_int(toad) {
                Some(
                  KeyMaterial {
                    cur_keys,
                    cur_threshold,
                    next_keys,
                    next_threshold,
                    witnesses,
                    toad: builtin.un_i_data(toad),
                  },
                )
              } else {
                None
              }
            None -> None
          }
        _ -> None
      }
    _ -> None
  }
}

/// The live form of `decode_data`: eight fields.
fn live_datum(fields: List<Data>) -> Option<DecodedDatum> {
  when fields is {
    [aid, sn, epoch, poisoned, frozen, born_at, refund_to, keys] ->
      when (byte_string(aid), nat(sn), nat(epoch), bool(poisoned)) is {
        (Some(aid), Some(sn), Some(epoch), Some(poisoned)) ->
          when
            (
              bool(frozen),
              nat(born_at),
              byte_string(refund_to),
              key_material(keys),
            )
          is {
            (Some(frozen), Some(born_at), Some(refund_to), Some(_)) ->
              Some(
                DecodedDatum {
                  aid: pack(aid),
                  state: Present(
                    Live {
                      sn,
                      epoch,
                      poisoned,
                      frozen,
                      born_at,
                      refund_to: pack(refund_to),
                      pool: 0,
                    },
                  ),
                },
              )
            _ -> None
          }
        _ -> None
      }
    _ -> None
  }
}

/// The termination-pending form of `decode_data`: four fields.
fn pending_datum(fields: List<Data>) -> Option<DecodedDatum> {
  when fields is {
    [aid, sn, epoch, keys] ->
      when (byte_string(aid), nat(sn), nat(epoch), key_material(keys)) is {
        (Some(aid), Some(sn), Some(epoch), Some(_)) ->
          Some(
            DecodedDatum {
              aid: pack(aid),
              state: TerminationPending(Hash { epoch, sn }),
            },
          )
        _ -> None
      }
    _ -> None
  }
}

/// Lean `decodeData`: version 2 only, every shape checked, the read fields
/// validated, the pool left at zero.
pub fn decode_data(d: Data) -> Option<DecodedDatum> {
  when constr_fields(d, 1) is {
    Some([form]) ->
      when constr_fields(form, 0) is {
        Some(fields) -> live_datum(fields)
        None ->
          when constr_fields(form, 1) is {
            Some(fields) -> pending_datum(fields)
            None -> None
          }
      }
    _ -> None
  }
}

/// Lean `decode`: the consumer's decoder on a raw application datum. The
/// release does not select the layout at this model revision.
pub fn decode(_release: PublishedRelease, raw: Data) -> Option<DecodedDatum> {
  decode_data(raw)
}
