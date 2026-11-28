//// The production binding of a registration, a rotation and the proof of an own digest, beside the reference reading
//// on identical vectors: the matched harness figures (`aiken check -m measure_`) and agreement of the verdicts.

use cardano_keri/checkpoint/advance.{
  AdvanceEventValid, event_binding as advance_binding,
}
use cardano_keri/checkpoint/advance_vectors as adv
use cardano_keri/checkpoint/binding_reference.{
  InceptionBound, RotationBound, inception_axis, proven_by_parsing,
  rotation_axis,
}
use cardano_keri/checkpoint/own_digest.{proven}
use cardano_keri/checkpoint/registration.{RegistrationValid, event_binding}
use cardano_keri/checkpoint/registration_vectors as vec
use cardano_keri/checkpoint/spelling_fixture

test measure_registration_witnessed_reference() {
  inception_axis(
    vec.pos_witnessed_datum,
    spelling_fixture.of_view(vec.pos_witnessed_datum),
    vec.pos_witnessed_evidence.event_bytes,
  ) == InceptionBound
}

test measure_registration_witnessed_production() {
  event_binding(
    vec.pos_witnessed_datum,
    spelling_fixture.of_view(vec.pos_witnessed_datum),
    vec.pos_witnessed_evidence,
  ) == RegistrationValid
}

test measure_registration_2key_reference() {
  inception_axis(
    vec.pos_2key_datum,
    spelling_fixture.of_view(vec.pos_2key_datum),
    vec.pos_2key_evidence.event_bytes,
  ) == InceptionBound
}

test measure_registration_2key_production() {
  event_binding(
    vec.pos_2key_datum,
    spelling_fixture.of_view(vec.pos_2key_datum),
    vec.pos_2key_evidence,
  ) == RegistrationValid
}

test measure_advance_2key_reference() {
  rotation_axis(
    adv.pos_adv_wit_2key_created,
    spelling_fixture.of_view(adv.pos_adv_wit_2key_created),
    adv.pos_adv_wit_2key_evidence.wit_cut,
    adv.pos_adv_wit_2key_evidence.wit_add,
    adv.pos_adv_wit_2key_evidence.event_bytes,
  ) == RotationBound
}

test measure_advance_2key_production() {
  advance_binding(
    adv.pos_adv_wit_2key_created,
    spelling_fixture.of_view(adv.pos_adv_wit_2key_created),
    adv.pos_adv_wit_2key_evidence,
  ) == AdvanceEventValid
}

test measure_advance_7key_reference() {
  rotation_axis(
    adv.pos_adv_wit_7key_created,
    spelling_fixture.of_view(adv.pos_adv_wit_7key_created),
    adv.pos_adv_wit_7key_evidence.wit_cut,
    adv.pos_adv_wit_7key_evidence.wit_add,
    adv.pos_adv_wit_7key_evidence.event_bytes,
  ) == RotationBound
}

test measure_advance_7key_production() {
  advance_binding(
    adv.pos_adv_wit_7key_created,
    spelling_fixture.of_view(adv.pos_adv_wit_7key_created),
    adv.pos_adv_wit_7key_evidence,
  ) == AdvanceEventValid
}

test measure_proof_393_reference() {
  proven_by_parsing(
    vec.pos_2key_evidence.event_bytes,
    vec.pos_2key_datum.cesr_aid,
  )
}

test measure_proof_393_production() {
  proven(vec.pos_2key_evidence.event_bytes, vec.pos_2key_datum.cesr_aid)
}
