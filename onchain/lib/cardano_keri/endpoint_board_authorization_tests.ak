//// Cross-language proof for the #253 S253-1 board authorization protocol.
////
//// Every golden constant in this file was produced by an oracle that shares
//// no code with either implementation it judges: an independent CBOR encoder
//// written from RFC 8949 plus the canonical Plutus `serialiseData` rules, and
//// Ed25519 from OpenSSL. The same constants are asserted from Haskell in
//// `Cardano.KERI.Deployment.EndpointBoardSpec`, so agreement here and there
//// is byte parity between Aiken and Haskell, not a mirror of either one.
////
//// Oracle: `evidence/vector-oracle.mjs`, output `evidence/vector-oracle.json`.

use aiken/cbor
use aiken/crypto.{verify_ed25519_signature}
use cardano_keri/endpoint_board_authorization.{
  BoardAuthorizationV2, BoardDatum, BoardDatumV2, BoardNonce, BoardV1, BoardV2,
  board_authorization_bytes, board_authorization_domain, board_datum_v2,
  datum_v2_is_authentic, reconstruct_board_authorization,
  verify_board_authorization, verify_endpoint_signature,
}

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
  #"d8799f582c63617264616e6f2d6b6572692f656e64706f696e742d626f6172642f617574686f72697a6174696f6e2f7632581c54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d31581c3333333333333333333333333333333333333333333333333333333307d8799f5820111111111111111111111111111111111111111111111111111111111111111100ffff"

const small_authorization_signature: ByteArray =
  #"557039f68e7446091c0d8586b1b0876ce1e97570b512b5b0013ae1ba5cffeb244d6d16ff345fcc7846697f1383fcc7466827b299f81469069472a5351a52820b"

const small_endpoint_signature: ByteArray =
  #"1a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05"

const small_datum_v1_cbor: ByteArray =
  #"d8799f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d3158401a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c33333333333333333333333333333333333333333333333333333333ff"

const small_datum_v2_cbor: ByteArray =
  #"d87a9f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d3158401a809536db02202b8170a43cf531bc98cc3e478c7c7c8955d30505d2487fbba6989038e9ebbd79721d45766b6517e97021e7a8043670f84a18ff1198fd7a7c05581c3333333333333333333333333333333333333333333333333333333307d8799f5820111111111111111111111111111111111111111111111111111111111111111100ff5840557039f68e7446091c0d8586b1b0876ce1e97570b512b5b0013ae1ba5cffeb244d6d16ff345fcc7846697f1383fcc7466827b299f81469069472a5351a52820bff"

// -- vector "chunked": 65-byte record, one byte past the 64-byte limit, so
// -- the encoder must emit 5f 5840 <64> 41 <1> ff. Sequence 1000 needs a
// -- two-byte CBOR argument. These are the cases a naive encoder gets wrong.

const chunked_record: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabb"

const chunked_nonce_tx_id: ByteArray =
  #"2222222222222222222222222222222222222222222222222222222222222222"

const chunked_authorization_bytes: ByteArray =
  #"d8799f582c63617264616e6f2d6b6572692f656e64706f696e742d626f6172642f617574686f72697a6174696f6e2f7632581c54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f547295f5840aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa41bbff581c333333333333333333333333333333333333333333333333333333331903e8d8799f5820222222222222222222222222222222222222222222222222222222222222222205ffff"

const chunked_authorization_signature: ByteArray =
  #"f3018c4c388eb6da979bbb75d954b9481089ce791e8126a9137734b627b3d007449cf04da1668757f8573b5c3854623f36561d1fcf89531b3f502efc383d7909"

const chunked_endpoint_signature: ByteArray =
  #"7ad2ae84bf3feb749b85d8110cd9e03f6006eb9c58e4ab542935c67b24035f531925dbb19832099f3620494878669083ecb4e707851d9b7f972859ad53d3e50e"

const chunked_datum_v2_cbor: ByteArray =
  #"d87a9f5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f547295f5840aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa41bbff58407ad2ae84bf3feb749b85d8110cd9e03f6006eb9c58e4ab542935c67b24035f531925dbb19832099f3620494878669083ecb4e707851d9b7f972859ad53d3e50e581c333333333333333333333333333333333333333333333333333333331903e8d8799f5820222222222222222222222222222222222222222222222222222222222222222205ff5840f3018c4c388eb6da979bbb75d954b9481089ce791e8126a9137734b627b3d007449cf04da1668757f8573b5c3854623f36561d1fcf89531b3f502efc383d7909ff"

// -- controls

/// A different, unrelated key, and its genuine signature over the small
/// vector's exact bytes: a real signature by the wrong signer.
const foreign_key: ByteArray =
  #"332ebe8d27cb7323b3a401c1c13b5dd64bccc0e10ecda1c2b5d11a03779a85e5"

const foreign_authorization_signature: ByteArray =
  #"3d7b875a2f3dc1de4202ca5e2b4644042937efaf9054457930ad015a646bf6377aff3129a59d71f3198a1ef475c81dd3fd6d0180596c3526865fe3cbd919a408"

/// The exact bytes the same authorization would have under a `/v1` domain.
const wrong_domain_authorization_bytes: ByteArray =
  #"d8799f582c63617264616e6f2d6b6572692f656e64706f696e742d626f6172642f617574686f72697a6174696f6e2f7631581c54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c5820d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f54729536c6f632f736368656d652d766563746f722d31581c3333333333333333333333333333333333333333333333333333333307d8799f5820111111111111111111111111111111111111111111111111111111111111111100ffff"

// ---------------------------------------------------------------- fixtures

fn small_nonce() -> BoardNonce {
  BoardNonce { nonce_tx_id: small_nonce_tx_id, nonce_output_index: 0 }
}

fn small_datum() -> BoardDatumV2 {
  BoardDatumV2 {
    witness_key,
    endpoint_record: small_record,
    endpoint_signature: small_endpoint_signature,
    owner_key_hash,
    sequence: 7,
    nonce: small_nonce(),
    authorization_signature: small_authorization_signature,
  }
}

fn chunked_datum() -> BoardDatumV2 {
  BoardDatumV2 {
    witness_key,
    endpoint_record: chunked_record,
    endpoint_signature: chunked_endpoint_signature,
    owner_key_hash,
    sequence: 1000,
    nonce: BoardNonce {
      nonce_tx_id: chunked_nonce_tx_id,
      nonce_output_index: 5,
    },
    authorization_signature: chunked_authorization_signature,
  }
}

fn small_wire_v1() -> BoardDatum {
  BoardV1 {
    witness_key,
    endpoint_record: small_record,
    endpoint_signature: small_endpoint_signature,
    owner_key_hash,
  }
}

fn small_wire_v2() -> BoardDatum {
  BoardV2 {
    witness_key,
    endpoint_record: small_record,
    endpoint_signature: small_endpoint_signature,
    owner_key_hash,
    sequence: 7,
    nonce: small_nonce(),
    authorization_signature: small_authorization_signature,
  }
}

fn chunked_wire_v2() -> BoardDatum {
  BoardV2 {
    witness_key,
    endpoint_record: chunked_record,
    endpoint_signature: chunked_endpoint_signature,
    owner_key_hash,
    sequence: 1000,
    nonce: BoardNonce {
      nonce_tx_id: chunked_nonce_tx_id,
      nonce_output_index: 5,
    },
    authorization_signature: chunked_authorization_signature,
  }
}

// ------------------------------------------------------------ the protocol

test endpoint_board_authorization_authorization_domain_is_frozen() {
  board_authorization_domain == "cardano-keri/endpoint-board/authorization/v2"
}

test endpoint_board_authorization_v1_wire_is_constructor_0_with_four_frozen_fields() {
  cbor.serialise(small_wire_v1()) == small_datum_v1_cbor
}

test endpoint_board_authorization_v2_wire_is_constructor_1_with_seven_fields() {
  cbor.serialise(small_wire_v2()) == small_datum_v2_cbor
}

test endpoint_board_authorization_v2_wire_survives_a_chunked_record_and_wide_sequence() {
  cbor.serialise(chunked_wire_v2()) == chunked_datum_v2_cbor
}

test endpoint_board_authorization_authorization_bytes_match_the_independent_oracle() {
  board_authorization_bytes(
    reconstruct_board_authorization(policy_id, small_datum()),
  ) == small_authorization_bytes
}

/// The 65-byte record forces indefinite-length chunked CBOR. An encoder that
/// emits one definite-length string here still passes every short vector.
test endpoint_board_authorization_authorization_bytes_match_the_oracle_when_chunked() {
  board_authorization_bytes(
    reconstruct_board_authorization(policy_id, chunked_datum()),
  ) == chunked_authorization_bytes
}

test endpoint_board_authorization_authorization_verifies_for_both_vectors() {
  verify_board_authorization(policy_id, small_datum()) && verify_board_authorization(
    policy_id,
    chunked_datum(),
  )
}

test endpoint_board_authorization_authentic_v2_datum_is_accepted() {
  datum_v2_is_authentic(witness_key, policy_id, small_datum()) && datum_v2_is_authentic(
    witness_key,
    policy_id,
    chunked_datum(),
  )
}

test endpoint_board_authorization_v1_datum_never_projects_as_v2() {
  board_datum_v2(small_wire_v1()) == None
}

test endpoint_board_authorization_v2_datum_projects_to_its_typed_fields() {
  board_datum_v2(small_wire_v2()) == Some(small_datum())
}

// --------------------------------------------- INV-253-SIGNED-FIELDS mutants
//
// Each mutant changes exactly one ordered signed component and keeps every
// other datum field and both signatures untouched and individually valid.

test endpoint_board_authorization_mutating_the_policy_id_rejects() {
  !verify_board_authorization(
    #"00494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c",
    small_datum(),
  )
}

test endpoint_board_authorization_mutating_the_witness_key_rejects() {
  // A real key with a real signature over the real bytes, but not this
  // record's witness: the authorization must name its own signer.
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      witness_key: foreign_key,
      authorization_signature: foreign_authorization_signature,
    },
  )
}

test endpoint_board_authorization_mutating_the_endpoint_record_rejects() {
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      endpoint_record: #"6c6f632f736368656d652d766563746f722d32",
    },
  )
}

test endpoint_board_authorization_mutating_the_owner_key_hash_rejects() {
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      owner_key_hash: #"44444444444444444444444444444444444444444444444444444444",
    },
  )
}

test endpoint_board_authorization_mutating_the_sequence_rejects() {
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 { ..small_datum(), sequence: 8 },
  )
}

test endpoint_board_authorization_mutating_the_nonce_tx_id_rejects() {
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: #"3111111111111111111111111111111111111111111111111111111111111111",
        nonce_output_index: 0,
      },
    },
  )
}

test endpoint_board_authorization_mutating_the_nonce_output_index_rejects() {
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: small_nonce_tx_id,
        nonce_output_index: 1,
      },
    },
  )
}

/// The domain is a constant, so it is mutated where it is actually used: in
/// the signed bytes. A signature over the `/v1` spelling of this very same
/// record must not verify as a `/v2` authorization.
test endpoint_board_authorization_the_domain_is_inside_the_signed_bytes() {
  let wrong_domain = BoardAuthorizationV2 {
    domain: "cardano-keri/endpoint-board/authorization/v1",
    board_policy_id: policy_id,
    witness_key,
    endpoint_record: small_record,
    owner_key_hash,
    sequence: 7,
    nonce: small_nonce(),
  }
  and {
    board_authorization_bytes(wrong_domain) == wrong_domain_authorization_bytes,
    board_authorization_bytes(wrong_domain) != small_authorization_bytes,
    !verify_ed25519_signature(
      witness_key,
      wrong_domain_authorization_bytes,
      small_authorization_signature,
    ),
  }
}

/// A signature that is genuine, 64 bytes, and over exactly the right bytes,
/// but produced by another key.
test endpoint_board_authorization_a_foreign_signer_is_rejected() {
  !verify_board_authorization(
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      authorization_signature: foreign_authorization_signature,
    },
  )
}

// -------------------------------------------- INV-253-WITNESS-AUTH controls

/// Endpoint-only authentication must not promote: the endpoint signature is
/// genuine, the authorization is not.
test endpoint_board_authorization_endpoint_signature_alone_does_not_authorize() {
  let datum = BoardDatumV2 {
    ..small_datum(),
    authorization_signature: chunked_authorization_signature,
  }
  and {
    verify_endpoint_signature(datum),
    !verify_board_authorization(policy_id, datum),
    !datum_v2_is_authentic(witness_key, policy_id, datum),
  }
}

/// Authorization-only authentication must not promote either: the #165
/// endpoint guarantee is not absorbed by the new signature.
test endpoint_board_authorization_authorization_alone_does_not_authenticate_the_endpoint() {
  let datum = BoardDatumV2 {
    ..small_datum(),
    endpoint_signature: chunked_endpoint_signature,
  }
  and {
    verify_board_authorization(policy_id, datum),
    !verify_endpoint_signature(datum),
    !datum_v2_is_authentic(witness_key, policy_id, datum),
  }
}

// ------------------------------------------------------- shape and widths

test endpoint_board_authorization_a_wrong_expected_key_is_rejected() {
  !datum_v2_is_authentic(foreign_key, policy_id, small_datum())
}

test endpoint_board_authorization_a_short_witness_key_is_rejected() {
  let key = #"d9fcc94b4685d4ba2987c3cd42c6a6068a6dd4d240206fa657f7afe125f547"
  !datum_v2_is_authentic(
    key,
    policy_id,
    BoardDatumV2 { ..small_datum(), witness_key: key },
  )
}

test endpoint_board_authorization_an_empty_endpoint_record_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 { ..small_datum(), endpoint_record: #"" },
  )
}

test endpoint_board_authorization_a_short_endpoint_signature_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      endpoint_signature: #"1a809536db02202b8170a43cf531bc98",
    },
  )
}

test endpoint_board_authorization_a_short_authorization_signature_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      authorization_signature: #"557039f68e7446091c0d8586b1b0876c",
    },
  )
}

test endpoint_board_authorization_a_short_owner_key_hash_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      owner_key_hash: #"333333333333333333333333333333333333333333333333333333",
    },
  )
}

test endpoint_board_authorization_a_negative_sequence_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 { ..small_datum(), sequence: -1 },
  )
}

test endpoint_board_authorization_a_negative_nonce_output_index_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: small_nonce_tx_id,
        nonce_output_index: -1,
      },
    },
  )
}

test endpoint_board_authorization_a_short_nonce_tx_id_is_rejected() {
  !datum_v2_is_authentic(
    witness_key,
    policy_id,
    BoardDatumV2 {
      ..small_datum(),
      nonce: BoardNonce {
        nonce_tx_id: #"1111111111111111111111111111111111111111111111111111111111",
        nonce_output_index: 0,
      },
    },
  )
}
