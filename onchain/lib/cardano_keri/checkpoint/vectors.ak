//// Auto-generated Aiken checkpoint fixtures for #68 — DO NOT EDIT.
////
//// Regenerate with `just gen-checkpoint-vectors` (runs
//// offchain/app/GenCheckpointVectors.hs). Each constant is the exact
//// canonical Plutus-Data CBOR (or blake2b_256 digest) the Haskell
//// encoder emits, so it is byte-identical to the Slice-2/3 hspec
//// goldens. Slices 5/6 assert the Aiken encoder reproduces these
//// bytes; `just check-checkpoint-vectors` forbids drift.

/// threshold: integer m-of-n (Unweighted 3)
pub const golden_threshold_integer: ByteArray = #"d8799f03ff"

/// threshold: single-clause weighted [[1/2, 1/2]]
pub const golden_threshold_single_clause: ByteArray =
  #"d87a9f9f9fd8799f0102ffd8799f0102ffffffff"

/// threshold: multi-clause weighted [[1/1], [1/1]]
pub const golden_threshold_multi_clause: ByteArray =
  #"d87a9f9f9fd8799f0101ffff9fd8799f0101ffffffff"

/// threshold: 1-of-1 as Unweighted 1
pub const golden_threshold_1of1: ByteArray = #"d8799f01ff"

/// threshold: 1-of-1 as Weighted [[1/1]]
pub const golden_threshold_weighted_1of1: ByteArray =
  #"d87a9f9f9fd8799f0101ffffffff"

/// datum: 1-of-1 (Unweighted 1, witnessless)
pub const golden_datum_1of1: ByteArray =
  #"d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000000ffff"

/// datum: integer m-of-n (Unweighted 2, 3 keys)
pub const golden_datum_integer_m_of_n: ByteArray =
  #"d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f582001010101010101010101010101010101010101010101010101010101010101015820020202020202020202020202020202020202020202020202020202020202020258200303030303030303030303030303030303030303030303030303030303030303ffd8799f02ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000507ffff"

/// datum: single-clause weighted [[1/2, 1/2]]
pub const golden_datum_weighted: ByteArray =
  #"d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0102ffd8799f0102ffffffff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000204ffff"

/// datum: multi-clause weighted [[1/1], [1/1]]
pub const golden_datum_multi_clause: ByteArray =
  #"d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f5820010101010101010101010101010101010101010101010101010101010101010158200202020202020202020202020202020202020202020202020202020202020202ffd87a9f9f9fd8799f0101ffff9fd8799f0101ffffffff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000103ffff"

/// datum: witnessed (non-empty witnesses, toad=2)
pub const golden_datum_witnessed: ByteArray =
  #"d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a9f5820b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b15820b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2ff020309ffff"

/// datum: witnessless (toad=0, empty witnesses)
pub const golden_datum_witnessless: ByteArray =
  #"d8799fd8799f5820aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58200a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a80000000ffff"

/// next_commitment: canonical CBOR of NextCommitment [k2] (Unweighted 1)
pub const golden_next_commitment_cbor: ByteArray =
  #"d8799f9f58200202020202020202020202020202020202020202020202020202020202020202ffd8799f01ffff"

/// next_commitment: keyset_commit (blake2b_256 of the canonical CBOR)
pub const golden_next_commitment_digest: ByteArray =
  #"7a3a5a75a5237ec477925c6cc500f6db3aa85cdb341295e5d78c81bdf278a8eb"

/// derivation: the fixed cesr_aid preimage (0x00..0x1f)
pub const golden_derivation_cesr_aid: ByteArray =
  #"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

/// derivation: aid_asset_name = blake2b_256(tag ++ 0x46 ++ cesr_aid)
pub const golden_aid_asset_name: ByteArray =
  #"c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac9"

/// derivation negative: wrong code 0x45 (not 0x46)
pub const negative_aid_asset_name_wrong_code: ByteArray =
  #"67cf5c95ae280e04d9d4b50854cc74aa198f0ff0335c615758e50f40dbb78536"

/// derivation negative: one-bit-flipped cesr_aid
pub const negative_aid_asset_name_mutated_aid: ByteArray =
  #"1e56b40cc1a6f1163f08fb24bcb29fe85bc4f5c721c9a4afac5a10588aafa3f0"

/// message: InceptionMessage (icp) canonical CBOR
pub const golden_inception_message: ByteArray =
  #"d8799f581e63617264616e6f2d6b6572692f636865636b706f696e742f6963702f763101581ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc5820c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac95820000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f9f58200101010101010101010101010101010101010101010101010101010101010101ffd8799f01ff58207a3a5a75a5237ec477925c6cc500f6db3aa85cdb341295e5d78c81bdf278a8eb800000ff"

/// message: AdvanceMessage (valid succession) canonical CBOR
pub const golden_advance_message: ByteArray =
  #"d8799f581e63617264616e6f2d6b6572692f636865636b706f696e742f6164762f763101581ccccccccccccccccccccccccccccccccccccccccccccccccccccccccc5820c8451c7348ab75c013738557db1eff061db499cd0baeef6ae90cd4f533e75ac95820000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f5820d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d00158206100bd9bb638fdadbe0727294eb099f38a3698b643a15f24023acd14cb310d6d00009f58201111111111111111111111111111111111111111111111111111111111111111ffd8799f01ff582024e5e385402220b63c92320512d818037a7f7cc24d9ec03bff16a7d4f1afbe9e80000101ff"
