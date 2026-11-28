//// The hash-proof minting policy: tests (H1-H4).
////
//// Each test drives the REAL `hash_proof.hash_proof.mint` handler on a full `Transaction` (the
//// `cage_context.mint_context` harness). Honest mints cover the size tiers: the committed keripy `honest_2key` icp
//// (393 B), the committed `reg_witnessed` icp (533 B, reused from `registration_vectors.ak` with its proof-name
//// golden), and a one-chunk boundary event of exactly 1,024 B (the 393 B event with a filler anchor, its own digest
//// computed by blake3 over the dressed blank), plus an event whose identifier is a key: its `d` is the digest of
//// the event with `d` blanked only. The event is read from its own bytes; no position is supplied.

use aiken/primitive/bytearray
use cage_context.{mint_context}
use cardano/assets.{PolicyId, from_asset, merge}
use cardano/transaction.{Transaction}
use cardano_keri/checkpoint/advance_vectors as adv
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

const honest2_redeemer: HashProofRedeemer =
  HashProofRedeemer { input_bytes: honest2_bytes, cesr_aid: honest2_aid }

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

const witnessed_redeemer: HashProofRedeemer =
  HashProofRedeemer {
    input_bytes: vec.pos_witnessed_evidence.event_bytes,
    cesr_aid: vec.pos_witnessed_datum.cesr_aid,
  }

// ---------------------------------------------------------------------
// one-chunk boundary event of exactly 1,024 B
// ---------------------------------------------------------------------

/// The 393 B keripy event with the anchor `["x…x"]` sized to 1,024 B, version size `000400`, and its own digest in
/// `d` and `i` computed over the blank with both dressed.
const boundary_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303430305f222c2274223a22696370222c2264223a22454d53515f513247544f554267562d7a58514462656757685f39344f4a65326b57355f7142657279736c2d6c222c2269223a22454d53515f513247544f554267562d7a58514462656757685f39344f4a65326b57355f7142657279736c2d6c222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b227878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878225d7d"

/// blake3 of the dressed 1,024 B blank.
const boundary_aid: ByteArray =
  #"c490fd0d864ce501815fb35d00db7a05a1ffde0e25eda45b9fea05eaf2b25fa5"

const boundary_redeemer: HashProofRedeemer =
  HashProofRedeemer { input_bytes: boundary_bytes, cesr_aid: boundary_aid }

const boundary_name: ByteArray = proof_token_name(boundary_bytes, boundary_aid)

// ---------------------------------------------------------------------
// a key identifier: i is a D-code key, d the digest with d blanked only
// ---------------------------------------------------------------------

/// The 393 B event with `i` the qualified key `DAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8g`.
const key_prefix_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a2245476130636630445f646e5a394b6f4d4a637159666f6143496478546d657651734864744f4b573451614b59222c2269223a2244414543417751464267634943516f4c4441304f4478415245684d554652595847426b614778776448683867222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

/// The raw payload of that identifier: the key itself.
const key_prefix_aid: ByteArray =
  #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"

// ---------------------------------------------------------------------
// reg_oversize — committed keripy icp, 1271 B (H1 must reject)
// ---------------------------------------------------------------------

const oversize_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303466375f222c2274223a22696370222c2264223a2245434769556c42346a5a42504d76705f7a385755776b5369494364583043726a7a564f6d5974307169585050222c2269223a2245434769556c42346a5a42504d76705f7a385755776b5369494364583043726a7a564f6d5974307169585050222c2273223a2230222c226b74223a5b22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33225d2c226b223a5b22444777315f776f36594279323175454a30556e4c4c7647576a714b474849596c596e7a6379366d6e4e4f744a222c22444f78397050586c2d66313341397934676642354e79456472503564736d61794d427a662d58696633577461222c22444e68644b46554d67687277785f303933746e35742d63766b75334547466f706e624a4c53325a4843545874222c22444f4f3557664a6a4d3366556e37335f674b5a716e506f61577571376573443038664e7547416c7771384c2d222c22444b345465486f44366470736d2d4a4f3950396141676e7576685a76344f44495639673347397a354555736b222c224442487a33626b4b445f594e664958504c4d467656616f5574504258504e596857583251705f4b6e55486772222c22444c33574632655f7535544d2d65585937715159723454323056496777624730456e4350594e434951324553225d2c226e74223a5b22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33222c22312f33225d2c226e223a5b22454a613075416a7a5974716968537273594a6c47394b653777574c597050744b7967636b6368693653435966222c22454d766d37734d6654636f656a6a737a664f763543424f623070456548476b46584b61516a5950765a473062222c22454a59354e463164634e3261456b3231326749684b6a4a574b584c574a544170395941773074316558373330222c2245446854587832762d6e615a5764536e387174694c4b6136326b4b663050537055704445667275372d754150222c224544484a4d504a4e326a73665f6f675f55373444503156347037532d4c6c5952337533783241774841414971222c22454b4f4e46365f717334674277764e2d475757626341326c665166716462465765764d6d5344574e54337467222c2245416c52507447506e476d4d3650374936676b656f794b55566178334b62616a536b69703736646d2d626c67225d2c226274223a2235222c2262223a5b22424372426d7143305f4b544d554755573254354e554c444c62673836625766336650466d736255486d69747a222c22424a444d6f504863324a61595a6555394e4e515348426158315359334431395848394143524554756d384a72222c224246537259376754417a2d6c4e4b34774e424d724477746e5563736d6a664d324a355a3150654e5a33787645222c2242436b4c4835534d6d34337936422d30326c324a725563414f4763393852444764326d685f326e675f525a51222c22424a6e36763948304e75463143354a65732d435461515f454563583358576a63676a696d75774f347537464d222c22424867787244423774313778773870386344483143463432716a31794c336733484854497152465a62744243222c22424246685874704f4a355f744b686d55305866526b6434645a433855616c614c41497059345958357353305f225d2c2263223a5b5d2c2261223a5b5d7d"

const oversize_aid: ByteArray =
  #"21a25250788d904f32fa7fcfc594c244a2202757d02ae3cd53a662dd2a8973cf"

const oversize_redeemer: HashProofRedeemer =
  HashProofRedeemer { input_bytes: oversize_bytes, cesr_aid: oversize_aid }

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
  HashProofRedeemer { input_bytes: #"", cesr_aid: #"" }

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
// H1 rejections — size tier, identifier width, the event itself
// ---------------------------------------------------------------------

test reject_oversize_1271b() fail {
  hash_proof.hash_proof.mint(
    oversize_redeemer,
    policy,
    mint_only(proof_token_name(oversize_bytes, oversize_aid), 1),
  )
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
// H2 rejections — identifier payload and digest binding
// ---------------------------------------------------------------------

/// The identifier holds the genuine qb64; the claimed payload differs.
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

/// One byte flipped outside the identifier: the dressed preimage no longer hashes to `d`.
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

// ---------------------------------------------------------------------
// the event is read from its own bytes
// ---------------------------------------------------------------------

test accept_mint_key_identifier() {
  hash_proof.hash_proof.mint(
    HashProofRedeemer {
      input_bytes: key_prefix_bytes,
      cesr_aid: key_prefix_aid,
    },
    policy,
    mint_only(proof_token_name(key_prefix_bytes, key_prefix_aid), 1),
  )
}

/// The same event under the digest of the identifier of another: the payload must be the key's.
test reject_key_identifier_digest_payload() fail {
  hash_proof.hash_proof.mint(
    HashProofRedeemer { input_bytes: key_prefix_bytes, cesr_aid: honest2_aid },
    policy,
    mint_only(proof_token_name(key_prefix_bytes, honest2_aid), 1),
  )
}

test reject_bytes_that_are_not_an_event() fail {
  let junk = "not an event"
  hash_proof.hash_proof.mint(
    HashProofRedeemer { input_bytes: junk, cesr_aid: honest2_aid },
    policy,
    mint_only(proof_token_name(junk, honest2_aid), 1),
  )
}

/// A rotation is read as a rotation: only an inception is proved.
test reject_rotation_event() fail {
  let rot = adv.pos_adv_wit_2key_evidence.event_bytes
  hash_proof.hash_proof.mint(
    HashProofRedeemer { input_bytes: rot, cesr_aid: honest2_aid },
    policy,
    mint_only(proof_token_name(rot, honest2_aid), 1),
  )
}

// ---------------------------------------------------------------------
// the identifier field must be closed: the 44 characters the mint reads are the whole value of `i`
// ---------------------------------------------------------------------

/// The 393 B event with `i` one character longer than the 44 the mint reads (`<honest identifier>x`), its version size
/// `18a`, and its own digest computed over the preimage as the mint dresses it (the 44 characters blanked, the extra
/// one left).
const unclosed_identifier_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138615f222c2274223a22696370222c2264223a22454b624f6b6955734b6a474156392d2d6e72343179517a73684d375a42644839764554456a614f4867566536222c2269223a2245494c48363677574c5343633345365976585a33537443653436314a673676456b32357874706c6c4f74506c78222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

/// Matched control: a `B` key identifier (the key itself), `d` the digest of the event with `d` blanked.
const b_key_bytes: ByteArray =
  #"7b2276223a224b45524931304a534f4e3030303138395f222c2274223a22696370222c2264223a22454b4a43576d72582d334e636e366f695269725855444a6231393953742d4250645a71666b50464753664878222c2269223a22424345694979516c4a69636f4b536f724c4330754c7a41784d6a4d304e5459334f446b364f7a7739506a3941222c2273223a2230222c226b74223a2232222c226b223a5b2244446d69555565653470426e4e636551385233536c645a4368463467577768324a3139552d5a387446627538222c22444265764364594d375a6b4a6b57496656345a6843674f3445596c5a64677a75386a3537485861615776376f225d2c226e74223a2232222c226e223a5b22454f5466464c795759797166776c52315a706372324d5555536b6354526b4c316c7058726541615f74723949222c22454b454656726e2d49794e4f597a323056674f2d4a4563744b5161397a344e64535f77417454325f45554463225d2c226274223a2230222c2262223a5b5d2c2263223a5b5d2c2261223a5b5d7d"

const b_key_aid: ByteArray =
  #"2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40"

test accept_mint_b_key_identifier() {
  hash_proof.hash_proof.mint(
    HashProofRedeemer { input_bytes: b_key_bytes, cesr_aid: b_key_aid },
    policy,
    mint_only(proof_token_name(b_key_bytes, b_key_aid), 1),
  )
}

/// The payload is the honest one and the digest is right over the dressed preimage; only the field is not closed.
test reject_unclosed_identifier_field() fail {
  hash_proof.hash_proof.mint(
    HashProofRedeemer {
      input_bytes: unclosed_identifier_bytes,
      cesr_aid: honest2_aid,
    },
    policy,
    mint_only(proof_token_name(unclosed_identifier_bytes, honest2_aid), 1),
  )
}
