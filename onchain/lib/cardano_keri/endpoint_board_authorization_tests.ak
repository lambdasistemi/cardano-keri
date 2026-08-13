//// Cross-language proof for the #253 S253-2 board authorization protocol.
////
//// Every golden constant in this file was produced by an oracle that shares
//// no code with either implementation it judges: an independent CBOR encoder
//// written from RFC 8949 plus the canonical Plutus `serialiseData` rules, and
//// Ed25519 from OpenSSL. The same constants are asserted from Haskell in
//// `Cardano.KERI.Deployment.EndpointBoardSpec`, so agreement here and there
//// is byte parity between Aiken and Haskell, not a mirror of either one.
////
//// Oracle: `evidence/vector-oracle.mjs`, output `evidence/vector-oracle.json`.
//// The S253-2 vectors drop `sequence`, drop the `/v2` domain suffix, and move
//// the authorized datum to `Constr 0` with six fields.

use aiken/cbor
use aiken/crypto.{verify_ed25519_signature}
use cardano/transaction.{OutputReference}
use cardano_keri/endpoint_board_authorization.{
  AuthorizedBoardDatum, BoardAuthorization, BoardNonce,
  board_authorization_bytes, board_authorization_domain, datum_is_authentic,
  nonce_names, nonce_reference, reconstruct_board_authorization,
  verify_board_authorization, verify_endpoint_signature,
}
use cardano_keri/endpoint_board_types.{BoardDatumV1}

// ---------------------------------------------------------------- vectors

/// Frozen test witness. Seed and derivation live in the oracle; this key
/// signs nothing but these vectors.
const witness_key: ByteArray =
  #"d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729"

const policy_id: ByteArray =
  #"54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

const owner_key_hash: ByteArray =
  #"33333333333333333333333333333333333333333333333333333333"

// -- vector "small": 19-byte record, short definite-length CBOR byte string.

const small_record: ByteArray = #"6c6f632f736368656d652d766563746f722d31"

const small_nonce_tx_id: ByteArray =
  #"1111111111111111111111111111111111111111111111111111111111111111"

const small_authorization_bytes: ByteArray =
  #"d8799f582963617264616e6f2d6b6572692f656e64706f696e742d626f6172642f617574686f72697a6174696f6e581c54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d31581c33333333333333333333333333333333333333333333333333333333d8799f5820111111111111111111111111111111111111111111111111111111111111111100ffff"

const small_authorization_signature: ByteArray =
  #"61c8bf526ed993529bf86bfde5f962396a363c7f927e6f8953e606e98e77b0213b49fbbb0008f757fabfe00113c383c27377c51e310fc818091a0632abba8006"

const small_endpoint_signature: ByteArray =
  #"1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

const small_legacy_datum_cbor: ByteArray =
  #"d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d3158401a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c33333333333333333333333333333333333333333333333333333333ff"

const small_authorized_datum_cbor: ByteArray =
  #"d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d3158401a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c33333333333333333333333333333333333333333333333333333333d8799f5820111111111111111111111111111111111111111111111111111111111111111100ff584061c8bf526ed993529bf86bfde5f962396a363c7f927e6f8953e606e98e77b0213b49fbbb0008f757fabfe00113c383c27377c51e310fc818091a0632abba8006ff"

// -- vector "chunked": 65-byte record, one byte past the 64-byte limit, so
// -- the encoder must emit 5f 5840 <64> 41 <1> ff. With `sequence` cut, the
// -- record is the only thing left that forces the chunked path, which is
// -- exactly why this vector survives the slimming.

const chunked_record: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabb"

const chunked_nonce_tx_id: ByteArray =
  #"2222222222222222222222222222222222222222222222222222222222222222"

const chunked_authorization_bytes: ByteArray =
  #"d8799f582963617264616e6f2d6b6572692f656e64706f696e742d626f6172642f617574686f72697a6174696f6e581c54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f547295f5840aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa41bbff581c33333333333333333333333333333333333333333333333333333333d8799f5820222222222222222222222222222222222222222222222222222222222222222205ffff"

const chunked_authorization_signature: ByteArray =
  #"d41f3c0b60c053d57b1bfc4bebebdb3bb8730880730ad90a1ac9a82c630da24011eb56050c6af1d29999c05db572d856baf098b0c2e439e628fa6d3369edbc05"

const chunked_endpoint_signature: ByteArray =
  #"7ad2ae84bf3feb749b85d8110cd9e03f6006eb9c58e4ab542935c67b24035f531925dbb19832099f3620494878669083ecb4e707851d9b7f972859ad53d3e50e"

const chunked_authorized_datum_cbor: ByteArray =
  #"d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f547295f5840aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa41bbff58407ad2ae84bf3feb749b85d8110cd9e03f6006eb9c58e4ab542935c67b24035f531925dbb19832099f3620494878669083ecb4e707851d9b7f972859ad53d3e50e581c33333333333333333333333333333333333333333333333333333333d8799f5820222222222222222222222222222222222222222222222222222222222222222205ff5840d41f3c0b60c053d57b1bfc4bebebdb3bb8730880730ad90a1ac9a82c630da24011eb56050c6af1d29999c05db572d856baf098b0c2e439e628fa6d3369edbc05ff"

// -- controls

/// A different, unrelated key, and its genuine signature over the small
/// vector's exact bytes: a real signature by the wrong signer.
const foreign_key: ByteArray =
  #"332ebe8d27cb7323b3a401c1c13b5dd64bccc0e10ecda1c2b5d11a03779a85e5"

const foreign_authorization_signature: ByteArray =
  #"8eeaee81b6110a87c0737157c8ba317947b7aa1d4b23ec340ab679456f9f971608488ead6d22d4dd1b0bf4a52081e1aa6913f0bba5e02c0c8718404ffd9b6b07"

/// The exact bytes this same record would produce under a different
/// cardano-keri domain. A cut spelling cannot serve as this control: the
/// frozen slice gate rejects the retired versioned identifier anywhere in the
/// protocol files, so the control uses a sibling protocol's domain instead.
const wrong_domain: ByteArray = "cardano-keri/endpoint-board/attestation"

const wrong_domain_authorization_bytes: ByteArray =
  #"d8799f582763617264616e6f2d6b6572692f656e64706f696e742d626f6172642f6174746573746174696f6e581c54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d31581c33333333333333333333333333333333333333333333333333333333d8799f5820111111111111111111111111111111111111111111111111111111111111111100ffff"

// ---------------------------------------------------------------- fixtures

fn small_nonce() -> BoardNonce {
  BoardNonce { nonce_tx_id: small_nonce_tx_id, nonce_output_index: 0 }
}

fn small_datum() -> AuthorizedBoardDatum {
  AuthorizedBoardDatum {
    witness_key,
    endpoint_record: small_record,
    endpoint_signature: small_endpoint_signature,
    owner_key_hash,
    nonce: small_nonce(),
    authorization_signature: small_authorization_signature,
  }
}

fn chunked_datum() -> AuthorizedBoardDatum {
  AuthorizedBoardDatum {
    witness_key,
    endpoint_record: chunked_record,
    endpoint_signature: chunked_endpoint_signature,
    owner_key_hash,
    nonce: BoardNonce {
      nonce_tx_id: chunked_nonce_tx_id,
      nonce_output_index: 5,
    },
    authorization_signature: chunked_authorization_signature,
  }
}

fn small_legacy_datum() -> BoardDatumV1 {
  BoardDatumV1 {
    witness_key,
    endpoint_record: small_record,
    endpoint_signature: small_endpoint_signature,
    owner_key_hash,
  }
}

// ------------------------------------------------------------ the protocol

test endpoint_board_s253_authorization_domain_is_stable_and_unversioned() {
  board_authorization_domain == "cardano-keri/endpoint-board/authorization"
}

/// INV-253-R03: the frozen legacy shape must stay constructor 0 with exactly
/// four fields, because that field count is the whole discriminator once the
/// authorized shape also uses constructor 0.
test endpoint_board_s253_legacy_wire_is_constructor_0_with_four_frozen_fields() {
  cbor.serialise(small_legacy_datum()) == small_legacy_datum_cbor
}

test endpoint_board_s253_authorized_wire_is_constructor_0_with_six_fields() {
  and {
    cbor.serialise(small_datum()) == small_authorized_datum_cbor,
    // Same constructor tag as the legacy shape (d879 = 121), different field
    // count: shape selection is structural, not versioned.
    cbor.serialise(small_datum()) != small_legacy_datum_cbor,
  }
}

/// The 65-byte record forces indefinite-length chunked CBOR. An encoder that
/// emits one definite-length string here still passes every short vector.
test endpoint_board_s253_authorized_wire_survives_a_chunked_record() {
  cbor.serialise(chunked_datum()) == chunked_authorized_datum_cbor
}

test endpoint_board_s253_authorization_bytes_match_six_field_oracle() {
  board_authorization_bytes(
    reconstruct_board_authorization(policy_id, small_datum()),
  ) == small_authorization_bytes
}

test endpoint_board_s253_authorization_bytes_match_the_oracle_when_chunked() {
  board_authorization_bytes(
    reconstruct_board_authorization(policy_id, chunked_datum()),
  ) == chunked_authorization_bytes
}

test endpoint_board_s253_authorization_verifies_for_both_vectors() {
  verify_board_authorization(policy_id, small_datum()) && verify_board_authorization(
    policy_id,
    chunked_datum(),
  )
}

test endpoint_board_s253_authentic_authorized_datum_is_accepted() {
  datum_is_authentic(witness_key, policy_id, small_datum()) && datum_is_authentic(
    witness_key,
    policy_id,
    chunked_datum(),
  )
}

// -------------------------------------------------- the nonce is a coordinate

test endpoint_board_s253_nonce_names_exactly_its_output_reference() {
  and {
    nonce_names(
      small_nonce(),
      OutputReference { transaction_id: small_nonce_tx_id, output_index: 0 },
    ),
    !nonce_names(
      small_nonce(),
      OutputReference { transaction_id: small_nonce_tx_id, output_index: 1 },
    ),
    !nonce_names(
      small_nonce(),
      OutputReference { transaction_id: chunked_nonce_tx_id, output_index: 0 },
    ),
    nonce_reference(small_nonce()) == OutputReference {
      transaction_id: small_nonce_tx_id,
      output_index: 0,
    },
  }
}

// --------------------------------------------- INV-253-SIGNED-FIELDS mutants
//
// Each mutant changes exactly one ordered signed component and keeps every
// other datum field and both signatures untouched and individually valid.

test endpoint_board_s253_mutating_the_policy_id_rejects() {
  !verify_board_authorization(
    #"00494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c",
    small_datum(),
  )
}

test endpoint_board_s253_mutating_the_witness_key_rejects() {
  // A real key with a real signature over the real bytes, but not this
  // record's witness: the authorization must name its own signer.
  !verify_board_authorization(
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      witness_key: foreign_key,
      authorization_signature: foreign_authorization_signature,
    },
  )
}

test endpoint_board_s253_mutating_the_endpoint_record_rejects() {
  !verify_board_authorization(
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      endpoint_record: #"6c6f632f736368656d652d766563746f722d32",
    },
  )
}

test endpoint_board_s253_mutating_the_owner_key_hash_rejects() {
  !verify_board_authorization(
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      owner_key_hash: #"44444444444444444444444444444444444444444444444444444444",
    },
  )
}

test endpoint_board_s253_mutating_the_nonce_tx_id_rejects() {
  !verify_board_authorization(
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: #"3111111111111111111111111111111111111111111111111111111111111111",
        nonce_output_index: 0,
      },
    },
  )
}

test endpoint_board_s253_mutating_the_nonce_output_index_rejects() {
  !verify_board_authorization(
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: small_nonce_tx_id,
        nonce_output_index: 1,
      },
    },
  )
}

/// The domain is a constant, so it is mutated where it is actually used: in
/// the signed bytes. A signature over another cardano-keri domain's spelling
/// of this very same record must not verify as a board authorization.
test endpoint_board_s253_the_domain_is_inside_the_signed_bytes() {
  let other_domain = BoardAuthorization {
    domain: wrong_domain,
    board_policy_id: policy_id,
    witness_key,
    endpoint_record: small_record,
    owner_key_hash,
    nonce: small_nonce(),
  }
  and {
    board_authorization_bytes(other_domain) == wrong_domain_authorization_bytes,
    board_authorization_bytes(other_domain) != small_authorization_bytes,
    !verify_ed25519_signature(
      witness_key,
      wrong_domain_authorization_bytes,
      small_authorization_signature,
    ),
  }
}

/// A signature that is genuine, 64 bytes, and over exactly the right bytes,
/// but produced by another key.
test endpoint_board_s253_a_foreign_signer_is_rejected() {
  !verify_board_authorization(
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      authorization_signature: foreign_authorization_signature,
    },
  )
}

// -------------------------------------------- INV-253-WITNESS-AUTH controls

/// Endpoint-only authentication must not promote: the endpoint signature is
/// genuine, the authorization is not.
test endpoint_board_s253_endpoint_signature_alone_does_not_authorize() {
  let datum = AuthorizedBoardDatum {
    ..small_datum(),
    authorization_signature: chunked_authorization_signature,
  }
  and {
    verify_endpoint_signature(datum),
    !verify_board_authorization(policy_id, datum),
    !datum_is_authentic(witness_key, policy_id, datum),
  }
}

/// Authorization-only authentication must not promote either: the #165
/// endpoint guarantee is not absorbed by the new signature.
test endpoint_board_s253_authorization_alone_does_not_authenticate_the_endpoint() {
  let datum = AuthorizedBoardDatum {
    ..small_datum(),
    endpoint_signature: chunked_endpoint_signature,
  }
  and {
    verify_board_authorization(policy_id, datum),
    !verify_endpoint_signature(datum),
    !datum_is_authentic(witness_key, policy_id, datum),
  }
}

// ------------------------------------------------------- shape and widths

test endpoint_board_s253_a_wrong_expected_key_is_rejected() {
  !datum_is_authentic(foreign_key, policy_id, small_datum())
}

test endpoint_board_s253_a_short_witness_key_is_rejected() {
  let key = #"d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f547"
  !datum_is_authentic(
    key,
    policy_id,
    AuthorizedBoardDatum { ..small_datum(), witness_key: key },
  )
}

test endpoint_board_s253_an_empty_endpoint_record_is_rejected() {
  !datum_is_authentic(
    witness_key,
    policy_id,
    AuthorizedBoardDatum { ..small_datum(), endpoint_record: #"" },
  )
}

test endpoint_board_s253_a_short_endpoint_signature_is_rejected() {
  !datum_is_authentic(
    witness_key,
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      endpoint_signature: #"1a809536db02202b8170a43cf531bc98",
    },
  )
}

test endpoint_board_s253_a_short_authorization_signature_is_rejected() {
  !datum_is_authentic(
    witness_key,
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      authorization_signature: #"557039f68e7446091c0d8586b1b0876c",
    },
  )
}

test endpoint_board_s253_a_short_owner_key_hash_is_rejected() {
  !datum_is_authentic(
    witness_key,
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      owner_key_hash: #"333333333333333333333333333333333333333333333333333333",
    },
  )
}

test endpoint_board_s253_a_negative_nonce_output_index_is_rejected() {
  !datum_is_authentic(
    witness_key,
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: small_nonce_tx_id,
        nonce_output_index: -1,
      },
    },
  )
}

test endpoint_board_s253_a_short_nonce_tx_id_is_rejected() {
  !datum_is_authentic(
    witness_key,
    policy_id,
    AuthorizedBoardDatum {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: #"1111111111111111111111111111111111111111111111111111111111",
        nonce_output_index: 0,
      },
    },
  )
}
