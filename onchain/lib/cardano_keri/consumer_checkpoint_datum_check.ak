//// The claims of the Lean version 2 checkpoint datum, one function each, over
//// a `DatumVector` (the generated vectors module builds the vectors and runs
//// two tests per vector).
////
//// Every expected value is the Lean's, taken from the vector; the decoder is
//// the thing under test. The raw-bytes layer (`CheckpointDatum.parse`) is the
//// ledger's: an inline datum arrives on chain already as `Data`. Here
//// `aiken/cbor.deserialise` stands in for it, so bytes that are not one whole
//// `Data` never reach the decoder.

use aiken/cbor
use cardano/address.{Address}
use cardano/assets.{from_lovelace}
use cardano/transaction.{InlineDatum, Output}
use cardano_keri/consumer.{
  Context, DecodedDatum, Environment, Params, PublishedRelease,
  consumable_holding, representative_asset,
}
use cardano_keri/consumer_identity_bytes as concrete
use cardano_keri/consumer_identity_check.{IdentityVector, context_of}
use cardano_keri/consumer_identity_vectors.{vector_transferable_aid}
use cardano_keri/consumer_test_interpretation as decoder

/// One row of `lean/checkpoint-datum-vectors.json`: the datum's CBOR bytes,
/// the `Data` the generator built for a datum the standard library cannot read
/// (a tagged big number), what the decoder returns, the AID the consumer is fixed on, and the
/// consumer's verdict on a genuine holding carrying the datum at `now`.
pub type DatumVector {
  datum: ByteArray,
  construction: Option<Data>,
  decoded: Option<DecodedDatum>,
  aid: Int,
  now: Int,
  accepted: Bool,
}

/// The vectors' parameters: only the juvenility window is read.
pub fn params() -> Params {
  Params { d: 3, b: 2, p: 1, w: 10 }
}

/// The relying contract's fixed context for a row: the first identity vector's
/// state policy and seed, and the row's AID.
pub fn context_for(aid: Int) -> Context {
  context_of(IdentityVector { ..vector_transferable_aid(), aid })
}

/// The decoder on the raw application datum, as the consumer calls it.
pub fn decode_data(release: PublishedRelease, raw: Data) -> Option<DecodedDatum> {
  decoder.decode(release, raw)
}

/// The ledger's parse of the row's datum: one whole `Data`, or nothing. The
/// standard library's reader panics on a tagged big number, so for those rows
/// the generator's own `Data` stands in.
pub fn read(v: DatumVector) -> Option<Data> {
  when v.construction is {
    Some(raw) -> Some(raw)
    None -> cbor.deserialise(v.datum)
  }
}

/// The decoder on the row's datum: the ledger's parse, then the decoder.
pub fn decode_row(
  release: PublishedRelease,
  v: DatumVector,
) -> Option<DecodedDatum> {
  when read(v) is {
    Some(raw) -> decode_data(release, raw)
    None -> None
  }
}

/// The decoder returns the row's `decoded`.
pub fn decode_ok(v: DatumVector) -> Bool {
  decode_row(context_for(v.aid).release, v) == v.decoded
}

/// A genuine holding of the context's representative asset carrying `raw`.
pub fn holding(c: Context, raw: Data) -> Output {
  let asset = representative_asset(
    concrete.hash,
    concrete.code,
    concrete.key_of,
    c,
  )
  Output {
    address: Address {
      payment_credential: c.release.application_credential,
      stake_credential: None,
    },
    value: from_lovelace(2000000) |> assets.add(asset.policy, asset.name, 1),
    datum: InlineDatum(raw),
    reference_script: None,
  }
}

/// The consumer predicate on the concrete identity bytes and this decoder,
/// for a holding carrying the row's datum. Bytes that are not one whole `Data`
/// cannot be an inline datum: no holding carries them.
pub fn consumer_accepts(c: Context, now: Int, v: DatumVector) -> Bool {
  when read(v) is {
    None -> False
    Some(raw) ->
      consumable_holding(
        concrete.hash,
        concrete.code,
        concrete.key_of,
        decoder.decode,
        c,
        Environment { network: c.network, release: Some(c.release) },
        params(),
        now,
        holding(c, raw),
      )
  }
}

/// The consumer's verdict is the row's.
pub fn verdict_ok(v: DatumVector) -> Bool {
  consumer_accepts(context_for(v.aid), v.now, v) == v.accepted
}
