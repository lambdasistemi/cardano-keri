//// The reference reading of an inception, a rotation and the own-digest proof: the structural reader of
//// `event_decoder` applied field by field. Tests only. The production bindings rebuild the canonical event and
//// compare it whole; this module names, for a refused event, the field that differs, and is the oracle the
//// rebuilt bindings are checked against.

use aiken/collection/list
use aiken/primitive/bytearray
use cardano_keri/blake3
use cardano_keri/checkpoint/datum.{KeyStateView}
use cardano_keri/checkpoint/event_decoder.{
  DecodeErr, DecodeOk, EventDecodeError, VariantIcp, VariantRot,
  decode_establishment_event,
}
use cardano_keri/checkpoint/message.{qb64_aid}
use cardano_keri/checkpoint/qualified.{
  code_b, code_d, code_e, digest_payload, identifier_payload,
}
use cardano_keri/checkpoint/registration.{
  QualifiedSpelling, qb64_witness_verkey, respell_hex, respell_threshold,
}
use cardano_keri/checkpoint/threshold.{Unweighted}

/// The field of an inception that differs from the datum.
pub type InceptionAxis {
  InceptionBound
  InceptionUndecodable(EventDecodeError)
  EventTypeDiffers
  AidDiffers
  SequenceDiffers
  CurKeysDiffer
  CurThresholdDiffers
  NextKeysDiffer
  NextThresholdDiffers
  WitnessesDiffer
  ToadDiffers
  PrefixDiffers
}

/// The field of a rotation that differs from the successor datum or the evidence.
pub type RotationAxis {
  RotationBound
  RotationUndecodable(EventDecodeError)
  RotationTypeDiffers
  RotationAidDiffers
  RotationSequenceDiffers
  RotationCurKeysDiffer
  RotationCurThresholdDiffers
  RotationNextKeysDiffer
  RotationNextThresholdDiffers
  RotationCutDiffers
  RotationAddDiffers
  RotationToadDiffers
}

pub fn inception_axis(
  d: KeyStateView,
  q: QualifiedSpelling,
  event_bytes: ByteArray,
) -> InceptionAxis {
  when decode_establishment_event(event_bytes) is {
    DecodeErr(err) -> InceptionUndecodable(err)
    DecodeOk(ev) ->
      if ev.variant != VariantIcp {
        EventTypeDiffers
      } else if ev.aid != q.aid {
        AidDiffers
      } else if ev.seq != "0" {
        SequenceDiffers
      } else if ev.k != q.cur_keys {
        CurKeysDiffer
      } else if ev.kt != respell_threshold(d.cur_threshold) {
        CurThresholdDiffers
      } else if ev.n != list.map(d.next_keys, qb64_aid) {
        NextKeysDiffer
      } else if ev.nt != respell_threshold(d.next_threshold) {
        NextThresholdDiffers
      } else if ev.b != list.map(d.witnesses, qb64_witness_verkey) {
        WitnessesDiffer
      } else if ev.bt != respell_hex(d.toad) {
        ToadDiffers
      } else if !prefix_fits(d, q, ev.said, ev.anchor == []) {
        PrefixDiffers
      } else {
        InceptionBound
      }
  }
}

fn prefix_fits(
  d: KeyStateView,
  q: QualifiedSpelling,
  said: ByteArray,
  anchor_empty: Bool,
) -> Bool {
  let code = bytearray.at(q.aid, 0)
  if code == code_e {
    said == q.aid
  } else if code == code_d {
    q.cur_keys == [q.aid] && d.cur_threshold == Unweighted(1)
  } else if code == code_b {
    q.cur_keys == [q.aid] && d.cur_threshold == Unweighted(1) && d.next_keys == [] && d.witnesses == [] && anchor_empty
  } else {
    False
  }
}

pub fn rotation_axis(
  new: KeyStateView,
  q: QualifiedSpelling,
  wit_cut: List<ByteArray>,
  wit_add: List<ByteArray>,
  event_bytes: ByteArray,
) -> RotationAxis {
  when decode_establishment_event(event_bytes) is {
    DecodeErr(err) -> RotationUndecodable(err)
    DecodeOk(ev) ->
      if ev.variant != VariantRot {
        RotationTypeDiffers
      } else if ev.aid != q.aid {
        RotationAidDiffers
      } else if ev.seq != respell_hex(new.native_sn) {
        RotationSequenceDiffers
      } else if ev.k != q.cur_keys {
        RotationCurKeysDiffer
      } else if ev.kt != respell_threshold(new.cur_threshold) {
        RotationCurThresholdDiffers
      } else if ev.n != list.map(new.next_keys, qb64_aid) {
        RotationNextKeysDiffer
      } else if ev.nt != respell_threshold(new.next_threshold) {
        RotationNextThresholdDiffers
      } else if ev.b != list.map(wit_cut, qb64_witness_verkey) {
        RotationCutDiffers
      } else if ev.ba != list.map(wit_add, qb64_witness_verkey) {
        RotationAddDiffers
      } else if ev.bt != respell_hex(new.toad) {
        RotationToadDiffers
      } else {
        RotationBound
      }
  }
}

/// The own-digest proof by the structural reader: the event is an inception, the payload of its identifier is the
/// claimed one, and its `d` is the blake3 of the dressed preimage.
pub fn proven_by_parsing(input_bytes: ByteArray, cesr_aid: ByteArray) -> Bool {
  when decode_establishment_event(input_bytes) is {
    DecodeOk(event) ->
      event.variant == VariantIcp && identifier_payload(event.aid) == Some(
        cesr_aid,
      ) && when digest_payload(event.said) is {
        Some(digest) -> blake3.verify(event.said_preimage, digest)
        None -> False
      }
    _ -> False
  }
}
