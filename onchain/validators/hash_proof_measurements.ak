//// Hash-proof minting-policy ex-unit measurements (#114 S4).
////
//// Mirrors the `cage_measurements.ak` / #97 R2 precedent: every fixture is
//// a top-level `const` (folded at compile time, not charged to the
//// measured cost) and each `test measure_*` invokes the REAL
//// `hash_proof.hash_proof.mint` handler on its ACCEPT path over a full
//// `Transaction`, so `aiken check --plain-numbers -m measure_hash_proof`
//// (justfile `measure-hash-proof`) reports the mem/cpu of one honest Tx-A
//// mint per size tier, against the mainnet per-tx budget
//// (memory 14,000,000; CPU 10,000,000,000).
////
//// Cells: ~300 B class (the committed keripy honest_2key icp, 393 B),
//// GEDA-scale (synthetic 966 B — the GLEIF External Delegated AID
//// inception scale; no committed fixture sits near it), and the 1024 B
//// single-chunk boundary. Synthetic vectors use the deterministic
//// blank-first construction (Q-001/A-001: filler byte i % 256, spans at
//// off_d = 9 / off_i = 61 dressed with `"#"×44`, digest = blake3 of the
//// blank, `qb64_aid(digest)` substituted into both spans) — blake3 of
//// arbitrary bytes is still the binding being priced. Fixture literals
//// are declared privately here because Aiken forbids `pub` exports in a
//// module importing a validator; the honest_2key/boundary constants are
//// byte-identical to `hash_proof_tests.ak` and each was SAID-verified
//// (`blake3(said_blank) == aid`) before committing. The headroom verdict
//// is the re-verifiable claim in `specs/114-registration/MEASUREMENTS.md`
//// (S6).
////
//// This module adds NO validator behavior; measurement infrastructure only.

use cage_context.{mint_context}
use cardano/assets.{PolicyId, from_asset}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/registration.{proof_token_name}
use hash_proof.{HashProofRedeemer}

const policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

// ---------------------------------------------------------------------
// ~300 B class — the committed keripy honest_2key icp (393 B)
// ---------------------------------------------------------------------

const honest2_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2269223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

const honest2_aid: ByteArray =
  #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e5"

const honest2_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: honest2_bytes,
    cesr_aid: honest2_aid,
    off_i: 91,
    off_d: 40,
  }

// ---------------------------------------------------------------------
// GEDA-scale synthetic vector (966 B)
// ---------------------------------------------------------------------

const geda_bytes: ByteArray =
  #"00010203040506070845446f39594b5a737a4f474b30474344394e6a413255324d76486b457951474b6b576d4f35376f5a516e433935363738393a3b3c45446f39594b5a737a4f474b30474344394e6a413255324d76486b457951474b6b576d4f35376f5a516e4339696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5"

/// blake3 of the dressed 966 B blank.
const geda_aid: ByteArray =
  #"3a3d60a66ccce18ad06083f4d8c0d94d8cbc7904c9018a91698ee7ba194270bd"

const geda_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: geda_bytes,
    cesr_aid: geda_aid,
    off_i: 61,
    off_d: 9,
  }

// ---------------------------------------------------------------------
// 1024 B single-chunk boundary synthetic vector
// ---------------------------------------------------------------------

const boundary_bytes: ByteArray =
  #"000102030405060708454274365f504654536a356f75525a61595076364837766d6b4c4d79393932357a6b6f4b443573614631756235363738393a3b3c454274365f504654536a356f75525a61595076364837766d6b4c4d79393932357a6b6f4b4435736146317562696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"

/// blake3 of the dressed 1024 B blank.
const boundary_aid: ByteArray =
  #"1b7afcf1534a3e68b9165a60fbfa1fbbe690b332f7ddb9ce4a0a0f9b1a175b9b"

const boundary_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: boundary_bytes,
    cesr_aid: boundary_aid,
    off_i: 61,
    off_d: 9,
  }

// ---------------------------------------------------------------------
// one honest mint transaction per size tier (consts: construction not
// charged to the measured handler cost)
// ---------------------------------------------------------------------

const tx_393: Transaction =
  mint_context(
    [],
    [],
    from_asset(policy, proof_token_name(honest2_bytes, honest2_aid), 1),
  )

const tx_966: Transaction =
  mint_context(
    [],
    [],
    from_asset(policy, proof_token_name(geda_bytes, geda_aid), 1),
  )

const tx_1024: Transaction =
  mint_context(
    [],
    [],
    from_asset(policy, proof_token_name(boundary_bytes, boundary_aid), 1),
  )

// honest_2key, 393 B: 7 compressed blake3 blocks + the H2a span checks +
// the H3 blake2b name recomputation.
test measure_hash_proof_mint_393b() {
  hash_proof.hash_proof.mint(honest2_redeemer, policy, tx_393)
}

// GEDA-scale, 966 B: 16 compressed blocks.
test measure_hash_proof_mint_966b() {
  hash_proof.hash_proof.mint(geda_redeemer, policy, tx_966)
}

// 1024 B single-chunk boundary: 16 compressed blocks over the full chunk —
// the top of the H1 tier (spike #88: the blake3 core alone measured
// 54.3% cpu / 71.7% mem of the mainnet budget here).
test measure_hash_proof_mint_1024b() {
  hash_proof.hash_proof.mint(boundary_redeemer, policy, tx_1024)
}
