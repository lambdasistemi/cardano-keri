//// Independent golden vectors and rejection properties for R1 keys.
////
//// Expected digests are oracle data. They are never computed through
//// `event_key`. Mutation anchors in this file must remain unique.

use aiken/crypto.{blake2b_256}
use aiken/merkle_patricia_forestry as mpf
use aiken/merkle_patricia_forestry.{Leaf, empty}
use aiken/primitive/bytearray
use cardano_keri/m12/event_decoder.{
  DecodedEstablishmentEvent, EventVariant, VariantIcp, VariantRot,
}
use cardano_keri/m12/event_key.{event_key, event_key_of}

pub const supported_derivation_codes: List<ByteArray> = ["D", "E"]

const aid_code_E: ByteArray = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

const aid_code_D: ByteArray = "DAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"

const prior_said: ByteArray = "EDMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMz"

const rival_said_one: ByteArray = "EBERERERERERERERERERERERERERERERERERERERERER"

const rival_said_two: ByteArray = "ECIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIi"

const expected_prior_absent_code_E: ByteArray =
  #"078af063f314bbb688164d97101d4e6609ca00a2391bfacd27b0c6f25e29a39a"

const expected_prior_present_code_D: ByteArray =
  #"60fb93d502befb1599746cad0e3df41ec70bfef40f7596963fa19352c3512595"

const expected_rival_two: ByteArray =
  #"2b0689b3df28e3dae63c2f1cc6677dad2ed3b554de2c455b2d74dd79c12ef973"

fn decoded(
  variant: EventVariant,
  aid: ByteArray,
  sequence: ByteArray,
  prior: ByteArray,
  said: ByteArray,
) -> DecodedEstablishmentEvent {
  DecodedEstablishmentEvent {
    variant,
    said,
    aid,
    seq: sequence,
    prior,
    kt: "1",
    k: [],
    nt: "0",
    n: [],
    bt: "0",
    b: [],
    br: [],
    ba: [],
    di: #"",
    said_preimage: #"",
  }
}

test prior_absent_code_E() {
  event_key(aid_code_E, 0, None, rival_said_one) == expected_prior_absent_code_E
}

test prior_present_code_D() {
  event_key(aid_code_D, 16, Some(prior_said), rival_said_one) == expected_prior_present_code_D
}

test decoded_sequence_is_integer_not_text_length() {
  event_key_of(
    decoded(VariantRot, aid_code_D, "10", prior_said, rival_said_one),
  ) == Some(expected_prior_present_code_D)
}

test decoded_prior_absent_uses_distinct_constructor() {
  event_key_of(decoded(VariantIcp, aid_code_E, "0", #"", rival_said_one)) == Some(
    expected_prior_absent_code_E,
  )
}

test event_key_of_rejects_noncanonical_sequence() {
  and {
    event_key_of(
      decoded(VariantRot, aid_code_D, "010", prior_said, rival_said_one),
    ) == None,
    event_key_of(
      decoded(VariantRot, aid_code_D, "A", prior_said, rival_said_one),
    ) == None,
  }
}

test event_key_of_rejects_unknown_or_noncanonical_qualification() {
  let unknown_code = #"46" |> bytearray.concat(bytearray.drop(aid_code_E, 1))
  let noncanonical_payload = #"4551"
    |> bytearray.concat(bytearray.drop(aid_code_E, 2))
  and {
    event_key_of(decoded(VariantIcp, unknown_code, "0", #"", rival_said_one)) == None,
    event_key_of(
      decoded(VariantIcp, noncanonical_payload, "0", #"", rival_said_one),
    ) == None,
    event_key_of(decoded(VariantIcp, aid_code_E, "0", #"", aid_code_D)) == None,
  }
}

test event_key_of_rejects_prior_constructor_mismatch() {
  and {
    event_key_of(
      decoded(VariantIcp, aid_code_E, "0", prior_said, rival_said_one),
    ) == None,
    event_key_of(decoded(VariantRot, aid_code_D, "10", #"", rival_said_one)) == None,
  }
}

test rival_saids_at_one_location_coexist() {
  let key_one = event_key(aid_code_D, 16, Some(prior_said), rival_said_one)
  let key_two = event_key(aid_code_D, 16, Some(prior_said), rival_said_two)
  if key_one == key_two {
    False
  } else {
    let proof_for_two = [
      Leaf {
        skip: 0,
        key: blake2b_256(key_one),
        value: blake2b_256(rival_said_one),
      },
    ]
    let proof_for_one = [
      Leaf {
        skip: 0,
        key: blake2b_256(key_two),
        value: blake2b_256(rival_said_two),
      },
    ]
    let both = mpf.insert(empty, key_one, rival_said_one, [])
      |> mpf.insert(key_two, rival_said_two, proof_for_two)
    and {
      key_one == expected_prior_present_code_D,
      key_two == expected_rival_two,
      mpf.has(both, key_one, rival_said_one, proof_for_one),
      mpf.has(both, key_two, rival_said_two, proof_for_two),
    }
  }
}
