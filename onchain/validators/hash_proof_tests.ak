//// #114 S4 — hash-proof minting policy tests (H1-H4, RED first).
////
//// Each test drives the REAL `hash_proof.hash_proof.mint` handler on a
//// full `Transaction` (the `cage_context.mint_context` harness; #99
//// precedent). Honest mints cover the three size tiers: the committed
//// keripy `honest_2key` icp (393 B, S1 bundle), the committed
//// `reg_witnessed` icp (533 B — reused straight from
//// `registration_vectors.ak`, with the S3 `witnessed_proof_name` golden
//// as the minted asset name), and a deterministic synthetic 1024 B
//// boundary vector (blank-first construction: dress two disjoint 44-char
//// spans with `"#"×44`, blake3 the blank, substitute `qb64_aid(digest)`
//// into both spans — no committed fixture approaches the boundary; blake3
//// of arbitrary bytes is still the binding, A-001/Q-001 ruling).
////
//// The keripy fixture spans sit at `off_d = 40`, `off_i = 91` (keripy
//// field order `v,t,d,i,...` is fixed; 91 matches the S1-exported `i`
//// offset — `d` is not exported by S1, located as the first of the two
//// qb64-AID occurrences and verified by the SAID relation
//// `blake3(said_blank) == aid` before committing, see Q-001/A-001).

use aiken/primitive/bytearray
use cage_context.{mint_context}
use cardano/assets.{PolicyId, from_asset, merge}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/registration.{proof_token_name}
use cardano_keri/checkpoint/registration_vectors as vec
use hash_proof.{HashProofRedeemer}

/// The policy id under test (the handler receives it as an argument;
/// the policy is parameter-free so any 28-byte id works).
const policy: PolicyId =
  #"4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a"

// ---------------------------------------------------------------------
// honest_2key — committed keripy icp, 393 B tier (S1 bundle honest_2key.json)
// ---------------------------------------------------------------------

/// The final keripy serialization (393 B).
const honest2_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2269223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

/// Raw 32-byte AID digest (decoded from the E-code prefix
/// EILH66wWLSCc3E6YvXZ3StCe461Jg6vEk25xtpllOtPl).
const honest2_aid: ByteArray =
  #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e5"

const honest2_off_d: Int = 40

const honest2_off_i: Int = 91

const honest2_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: honest2_bytes,
    cesr_aid: honest2_aid,
    off_i: honest2_off_i,
    off_d: honest2_off_d,
  }

const honest2_name: ByteArray = proof_token_name(honest2_bytes, honest2_aid)

/// honest_2key raw bytes with the LAST byte flipped (0x7d -> 0x7c) —
/// outside both spans, so H2a still passes and H2b must reject.
const honest2_tampered: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2269223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7c"

/// honest_2key AID with the last byte flipped — the spans still hold the
/// genuine qb64, so H2a must reject.
const honest2_wrong_aid: ByteArray =
  #"82c7ebac162d209cdc4e98bd76774ad09ee3ad4983abc4936e71b699653ad3e4"

// ---------------------------------------------------------------------
// reg_witnessed — committed keripy icp, 533 B tier (registration_vectors)
// ---------------------------------------------------------------------

/// `d` span offset for reg_witnessed (same keripy header shape; not
/// S1-exported, located + SAID-verified as documented above).
const witnessed_off_d: Int = 40

const witnessed_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: vec.pos_witnessed_evidence.event_bytes,
    cesr_aid: vec.pos_witnessed_datum.cesr_aid,
    off_i: vec.pos_witnessed_evidence.off_i,
    off_d: witnessed_off_d,
  }

// ---------------------------------------------------------------------
// synthetic 1024 B boundary vector (blank-first construction)
// ---------------------------------------------------------------------

/// 1024 B: filler byte i % 256 with qb64_aid(digest) substituted at
/// off_d = 9 and off_i = 61, where digest = blake3 of the dressed blank.
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

const boundary_name: ByteArray = proof_token_name(boundary_bytes, boundary_aid)

// ---------------------------------------------------------------------
// reg_oversize — committed keripy icp, 1271 B (H1 must reject)
// ---------------------------------------------------------------------

const oversize_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303466375f222c2274223a22696370222c2264223a2245434769556c42346a5a42504d76705f7a385755776b5369494364583043726a7a564f6d5974307169585050222c2269223a2245434769556c42346a5a42504d76705f7a385755776b5369494364583043726a7a564f6d5974307169585050222c2273223a2230222c226b74223a5b22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33225d2c226b223a5b22444777315f776f36594279323175454a30556e4c4c7647576a714b474849596c596e7a6379366d6e4e4f744a222c22444f78397050586c2d66313341397934676642354e79456472503564736d61794d427a662d58696633577461222c22444e68644b46554d67687277785f303933746e35742d63766b75334547466f706e624a4c53325a4843545874222c22444f4f3557664a6a4d3366556e37335f674b5a716e506f61577571376573443038664e7547416c7771384c2d222c22444b345465486f44366470736d2d4a4f3950396141676e7576685a76344f44495639673347397a354555736b222c224442487a33626b4b445f594e664958504c4d467656616f5574504258504e596857583251705f4b6e55486772222c22444c33574632655f7535544d2d65585937715159723454323056496777624730456e4350594e434951324553225d2c226e74223a5b22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33225d2c226e223a5b22454a613075416a7a5974716968537273594a6c47394b653777574c597050744b7967636b6368693653435966222c22454d766d37734d6654636f656a6a737a664f763543424f623070456548476b46584b61516a5950765a473062222c22454a59354e463164634e3261456b3231326749684b6a4a574b584c574a544170395941773074316558373330222c2245446854587832762d6e615a5764536e387174694c4b6136326b4b663050537055704445667275372d754150222c224544484a4d504a4e326a73665f6f675f55373444503156347037532d4c6c5952337533783241774841414971222c22454b4f4e46365f717334674277764e2d475757626341326c665166716462465765764d6d5344574e54337467222c2245416c52507447506e476d4d3650374936676b656f794b55566178334b62616a536b69703736646d2d626c67225d2c226274223a2235222c2262223a5b22424372426d7143305f4b544d554755573254354e554c444c62673836625766336650466d736255486d69747a222c22424a444d6f504863324a61595a6555394e4e515348426158315359334431395848394143524554756d384a72222c224246537259376754417a2d6c4e4b34774e424d724477746e5563736d6a664d324a355a3150654e5a33787645222c2242436b4c4835534d6d34337936422d30326c324a725563414f4763393852444764326d685f326e675f525a51222c22424a6e36763948304e75463143354a65732d435461515f454563583358576a63676a696d75774f347537464d222c22424867787244423774313778773870386344483143463432716a31794c336733484854497152465a62744243222c22424246685874704f4a355f744b686d55305866526b6434645a433855616c614c41497059345958357353305f225d2c2263223a5b5d2c2261223a5b5d7d"

const oversize_aid: ByteArray =
  #"21a25250788d904f32fa7fcfc594c244a2202757d02ae3cd53a662dd2a8973cf"

const oversize_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: oversize_bytes,
    cesr_aid: oversize_aid,
    off_i: 91,
    off_d: 40,
  }

// ---------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------

/// A mint-only transaction carrying `value` under no inputs/outputs
/// (the hash-proof policy inspects nothing but the mint map).
fn mint_only(name: ByteArray, qty: Int) -> Transaction {
  mint_context([], [], from_asset(policy, name, qty))
}

/// Redeemer content is ignored on the burn branch; an all-zero one keeps
/// that claim honest in every burn test.
const burn_redeemer: HashProofRedeemer =
  HashProofRedeemer { input_bytes: #"", cesr_aid: #"", off_i: 0, off_d: 0 }

// ---------------------------------------------------------------------
// honest mints (H1-H3) — the three size tiers
// ---------------------------------------------------------------------

test accept_mint_honest_2key_393b() {
  hash_proof.hash_proof.mint(
    honest2_redeemer,
    policy,
    mint_only(honest2_name, 1),
  )
}

/// The minted name is the S3 golden (`blake2b_256(final bytes ‖ aid)`) —
/// the H3 recomputation must land on the committed literal, proving Tx A
/// composes with the S5 R5 lookup.
test accept_mint_reg_witnessed_533b() {
  hash_proof.hash_proof.mint(
    witnessed_redeemer,
    policy,
    mint_only(vec.witnessed_proof_name, 1),
  )
}

test accept_mint_boundary_1024b() {
  hash_proof.hash_proof.mint(
    boundary_redeemer,
    policy,
    mint_only(boundary_name, 1),
  )
}

// ---------------------------------------------------------------------
// burn branch (H4)
// ---------------------------------------------------------------------

test accept_burn_single() {
  hash_proof.hash_proof.mint(burn_redeemer, policy, mint_only(honest2_name, -1))
}

/// Every entry strictly negative — batch burns are permitted.
test accept_burn_batch() {
  let value = from_asset(policy, honest2_name, -1)
    |> merge(from_asset(policy, vec.witnessed_proof_name, -2))
  hash_proof.hash_proof.mint(burn_redeemer, policy, mint_context([], [], value))
}

// ---------------------------------------------------------------------
// H1 rejections — size tier and span shape
// ---------------------------------------------------------------------

test reject_oversize_1271b() fail {
  hash_proof.hash_proof.mint(
    oversize_redeemer,
    policy,
    mint_only(proof_token_name(oversize_bytes, oversize_aid), 1),
  )
}

/// off_i = 60 overlaps the off_d = 40 span (40 + 44 > 60).
test reject_overlapping_spans() fail {
  let redeemer = HashProofRedeemer { ..honest2_redeemer, off_i: 60 }
  hash_proof.hash_proof.mint(redeemer, policy, mint_only(honest2_name, 1))
}

/// off_i = 1000 runs past the 393 B input.
test reject_out_of_range_span() fail {
  let redeemer = HashProofRedeemer { ..honest2_redeemer, off_i: 1000 }
  hash_proof.hash_proof.mint(redeemer, policy, mint_only(honest2_name, 1))
}

test reject_negative_off_d() fail {
  let redeemer = HashProofRedeemer { ..honest2_redeemer, off_d: -1 }
  hash_proof.hash_proof.mint(redeemer, policy, mint_only(honest2_name, 1))
}

/// 31-byte AID (genuine digest truncated), otherwise-honest package ->
/// the H1 width gate, not a span/digest mismatch, must reject (Q-002).
test reject_short_aid() fail {
  let aid = bytearray.take(honest2_aid, 31)
  let redeemer = HashProofRedeemer { ..honest2_redeemer, cesr_aid: aid }
  hash_proof.hash_proof.mint(
    redeemer,
    policy,
    mint_only(proof_token_name(honest2_bytes, aid), 1),
  )
}

/// 33-byte AID (genuine digest + trailing 0x00) -> H1 width gate (Q-002).
test reject_long_aid() fail {
  let aid = bytearray.concat(honest2_aid, #"00")
  let redeemer = HashProofRedeemer { ..honest2_redeemer, cesr_aid: aid }
  hash_proof.hash_proof.mint(
    redeemer,
    policy,
    mint_only(proof_token_name(honest2_bytes, aid), 1),
  )
}

// ---------------------------------------------------------------------
// H2 rejections — span content and digest binding
// ---------------------------------------------------------------------

/// Spans hold the genuine qb64; the claimed AID differs -> H2a.
test reject_wrong_aid() fail {
  let redeemer = HashProofRedeemer {
    ..honest2_redeemer,
    cesr_aid: honest2_wrong_aid,
  }
  hash_proof.hash_proof.mint(
    redeemer,
    policy,
    mint_only(proof_token_name(honest2_bytes, honest2_wrong_aid), 1),
  )
}

/// Both spans point one byte off the genuine content -> H2a.
test reject_wrong_span_offsets() fail {
  let redeemer = HashProofRedeemer { ..honest2_redeemer, off_d: 41, off_i: 92 }
  hash_proof.hash_proof.mint(redeemer, policy, mint_only(honest2_name, 1))
}

/// One byte flipped OUTSIDE the spans: H2a passes, the said-blank digest
/// no longer matches -> H2b.
test reject_tampered_bytes() fail {
  let redeemer = HashProofRedeemer {
    ..honest2_redeemer,
    input_bytes: honest2_tampered,
  }
  hash_proof.hash_proof.mint(
    redeemer,
    policy,
    mint_only(proof_token_name(honest2_tampered, honest2_aid), 1),
  )
}

// ---------------------------------------------------------------------
// H3 rejections — full-map mint shape
// ---------------------------------------------------------------------

test reject_multi_name_mint() fail {
  let value = from_asset(policy, honest2_name, 1)
    |> merge(from_asset(policy, vec.witnessed_proof_name, 1))
  hash_proof.hash_proof.mint(
    honest2_redeemer,
    policy,
    mint_context([], [], value),
  )
}

test reject_extra_quantity() fail {
  hash_proof.hash_proof.mint(
    honest2_redeemer,
    policy,
    mint_only(honest2_name, 2),
  )
}

/// Valid redeemer pair, but the minted name is another pair's name.
test reject_crossed_pair_name() fail {
  hash_proof.hash_proof.mint(
    honest2_redeemer,
    policy,
    mint_only(vec.witnessed_proof_name, 1),
  )
}

/// A burn entry beside the honest mint entry breaks the single-Pair H3
/// shape (the full-map inspection).
test reject_mint_with_extra_burn_entry() fail {
  let value = from_asset(policy, honest2_name, 1)
    |> merge(from_asset(policy, vec.witnessed_proof_name, -1))
  hash_proof.hash_proof.mint(
    honest2_redeemer,
    policy,
    mint_context([], [], value),
  )
}

// ---------------------------------------------------------------------
// H4 rejection — no positive entry may ride the burn branch
// ---------------------------------------------------------------------

test reject_burn_branch_positive() fail {
  let value = from_asset(policy, honest2_name, -1)
    |> merge(from_asset(policy, vec.witnessed_proof_name, 1))
  hash_proof.hash_proof.mint(burn_redeemer, policy, mint_context([], [], value))
}
