//// Frozen signed advance message domain + locator asset-name
//// derivation (#68 Slice 6).
////
//// Mirrors the Slice-3 Haskell `Cardano.KERI.AID.Checkpoint.Message`
//// byte-for-byte: the `AdvanceMessage` signed preimage (Constr 0, 18 fields)
//// and `deriveAidAssetName` over the frozen 65-byte
//// `CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x45 ‖ cesr_aid` preimage encode to the
//// exact canonical Plutus-Data CBOR / `blake2b_256` digest the Haskell
//// encoder emits (see `vectors.ak`). Domain strings, constructor indices, and
//// field order are protocol surface; they change only by minting a new
//// version tag.
////
//// The advance is authorized by the KERI dual-threshold rule: the signer
//// evidence must satisfy the rotation's own current threshold over
//// `new_cur_keys` AND the spent checkpoint's pre-rotation threshold
//// (`next_threshold`) over the committed `next_keys` digests. Partial/reserve
//// rotation is supported: any satisfiable subset of the committed digests may
//// be revealed, and `new_cur_threshold` may differ from the committed
//// `next_threshold` — exactly the KERI rotation-validation rule. Each message
//// binds the deployment (`network_id`, `checkpoint_policy_id`) and token
//// (`aid_asset_name`), and every carried `aid_asset_name` must equal
//// `deriveAidAssetName(cesr_aid)`.
////
//// The advance additionally carries the incoming-set witness rule (#115): the
//// signed preimage carries KERI's delta (`wit_cut`/`wit_add`) rather than a
//// full witness list, and `advance_equalities` derives the incoming set
//// (`new_set = (spent.witnesses - wit_cut) ++ wit_add`, survivors first in
//// spent order, then adds in add order) and requires the created datum's
//// witnesses to equal it exactly.

use aiken/collection/list
use aiken/crypto
use aiken/primitive/bytearray
use cardano_keri/base64url
use cardano_keri/blake3
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, DatumError, DatumInvalid, datum_well_formed,
}
use cardano_keri/checkpoint/threshold.{Threshold, evaluate}

// ---------------------------------------------------------
// Frozen constants
// ---------------------------------------------------------

/// `CHECKPOINT_ASSET_DOMAIN_TAG = UTF8("cardano-keri/checkpoint-asset/v1")` —
/// a constant 32-byte domain tag.
pub const checkpoint_asset_domain_tag: ByteArray =
  #"63617264616e6f2d6b6572692f636865636b706f696e742d61737365742f7631"

/// The frozen advance message domain: `UTF8("cardano-keri/checkpoint/adv/v1")`.
pub const advance_domain: ByteArray =
  #"63617264616e6f2d6b6572692f636865636b706f696e742f6164762f7631"

// ---------------------------------------------------------
// Locator asset-name derivation (#92 -> #68 pin)
// ---------------------------------------------------------

/// `aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x45 ‖ cesr_aid)`
/// over the fixed 65-byte preimage. `0x45` = ASCII `'E'`, the V1 E-native
/// (Blake3-256) derivation code — the production KERI AID default. The outer
/// hash stays `blake2b_256`: it is a Cardano-internal label of the AID, never
/// a KERI artifact, so the cheap native builtin is correct here. Changing
/// either constant requires a new version tag.
pub fn deriveAidAssetName(cesr_aid: ByteArray) -> ByteArray {
  crypto.blake2b_256(
    bytearray.concat(
      checkpoint_asset_domain_tag,
      bytearray.concat(#"45", cesr_aid),
    ),
  )
}

/// The fully qualified Base64url (qb64) form of a raw 32-byte transferable
/// Ed25519 verkey: code `'D'` followed by `b64url(0x00 ‖ key)` with the first
/// (always `'A'`) character replaced by the code — 44 ASCII characters. This
/// is the exact preimage KERI digests for KEL `n` entries.
pub fn qb64_verkey(key: ByteArray) -> ByteArray {
  bytearray.push(
    bytearray.drop(base64url.encode(bytearray.push(key, 0)), 1),
    68,
  )
}

/// The fully qualified Base64url (qb64) form of a raw 32-byte self-addressing
/// digest (E-code AID): code `'E'` (`0x45`) followed by `b64url(0x00 ‖ digest)`
/// with the first (always `'A'`) character replaced by the code — 44 ASCII
/// characters. The E-code analogue of `qb64_verkey`, mirroring the KERI `i`/`d`
/// SAID form (mirrors the Slice-3 Haskell `qb64Aid`); #24's on-chain AID
/// slice-check compares the event's `i` against this.
pub fn qb64_aid(digest: ByteArray) -> ByteArray {
  bytearray.push(
    bytearray.drop(base64url.encode(bytearray.push(digest, 0)), 1),
    69,
  )
}

/// A pre-rotation next-key digest: `blake3_256(qb64(verkey))` — the KERI KEL
/// `n` entry byte-for-byte. One single-block blake3 per revealing key, on the
/// rare rotation path only (never at plain authorization).
pub fn next_key_digest(key: ByteArray) -> ByteArray {
  blake3.hash(qb64_verkey(key))
}

// ---------------------------------------------------------
// Advance message (dual-threshold rotation + incoming-set witness
// admission) — Constr 0, 18 fields
// ---------------------------------------------------------

/// The signed advance preimage (Constr 0; 18 fields in frozen order). The
/// advance is authorized by the KERI dual-threshold rule (see the module
/// doc), never by the spent current set alone (KERI pre-rotation). Field 14
/// carries the rotation's witness-cut delta (`br`) and field 15 the
/// witness-add delta (`ba`) — the incoming witness set is never signed
/// directly; `advance_equalities` derives it.
pub type AdvanceMessage {
  domain: ByteArray,
  network_id: Int,
  checkpoint_policy_id: ByteArray,
  aid_asset_name: ByteArray,
  cesr_aid: ByteArray,
  spent_txid: ByteArray,
  spent_index: Int,
  prior_seq: Int,
  prior_native_sn: Int,
  new_cur_keys: List<ByteArray>,
  new_cur_threshold: Threshold,
  new_next_keys: List<ByteArray>,
  new_next_threshold: Threshold,
  wit_cut: List<ByteArray>,
  wit_add: List<ByteArray>,
  new_toad: Int,
  seq_to: Int,
  native_sn_to: Int,
}

// ---------------------------------------------------------
// Advance validation (the F10 checks) — #77 / parent #21
// ---------------------------------------------------------

/// The spent checkpoint context an advance is validated against: its
/// deployment, identity-asset name, exact `TxOutRef`, current witness set
/// (the W1-W3 delta base), and prior key-state projection fields —
/// including the committed `(next_keys, next_threshold)` pair the
/// dual-threshold rule evaluates (mirrors the Slice-3 `SpentCheckpoint`). A
/// validation-context type, not a wire type; the spend branch fills it from
/// the spent inline datum.
pub type SpentCheckpoint {
  network_id: Int,
  policy_id: ByteArray,
  aid_asset_name: ByteArray,
  txid: ByteArray,
  index: Int,
  cesr_aid: ByteArray,
  witnesses: List<ByteArray>,
  next_keys: List<ByteArray>,
  next_threshold: Threshold,
  seq: Int,
  native_sn: Int,
}

/// The key digests of the raw keys that produced valid signatures (the signer
/// evidence). eq6 maps this evidence onto `new_cur_keys` positions (the
/// rotation's own threshold) AND onto the spent checkpoint's committed
/// `next_keys` positions (the pre-rotation threshold) — KERI's dual-threshold
/// rule. A stolen spent-current quorum maps to no committed `next_keys`
/// position, so it fails the pre-rotation threshold and is rejected (mirrors
/// the Slice-3 `RevealedSuccessorSigners`).
pub type RevealedSuccessorSigners {
  RevealedSuccessorSigners(List<ByteArray>)
}

/// Which of the F10 advance checks rejected (mirrors the Slice-3
/// `AdvanceError`).
pub type AdvanceError {
  /// The signed preimage domain was not the frozen `adv` literal.
  AdvanceDomainMismatch
  /// eq1: `network_id` / `checkpoint_policy_id` do not match the deployment.
  Eq1NetworkPolicyMismatch
  /// eq2: asset name is not the AID's derived locator, or the AID crossed.
  Eq2AssetOrAidMismatch
  /// eq3: `(spent_txid, spent_index)` is not the spent `TxOutRef`.
  Eq3OutRefMismatch
  /// eq4: `prior_seq` / `prior_native_sn` do not match the spent datum.
  Eq4PriorMismatch
  /// eq5: `seq_to /= spent.seq + 1` or `native_sn_to` did not advance.
  Eq5SequenceMismatch
  /// W1: `wit_cut` entries are not pairwise distinct, or one is not a
  /// member of the spent witness set.
  EqW1CutInvalid
  /// W2: `wit_add` entries are not pairwise distinct, overlap `wit_cut`, or
  /// one is already among the surviving (uncut) witnesses.
  EqW2AddInvalid
  /// eq6: the revealed set did not satisfy its own current threshold.
  Eq6CurrentQuorumUnsatisfied
  /// eq6: the evidence did not satisfy the spent checkpoint's committed
  /// `(next_keys, next_threshold)` — the KERI pre-rotation gate.
  Eq6PriorNextQuorumUnsatisfied
  /// eq7: the created datum does not equal the message's new-state fields.
  Eq7CreatedStateMismatch
  /// eq8: the created datum failed `datum_well_formed` (F18 + rule 14).
  Eq8CreatedIllFormed(DatumError)
}

/// The advance acceptance verdict. `AdvanceValid` ≙ `Right ()`,
/// `AdvanceInvalid(e)` ≙ `Left e` (mirrors the Slice-3
/// `Either AdvanceError ()`).
pub type AdvanceVerdict {
  AdvanceValid
  AdvanceInvalid(AdvanceError)
}

/// The F10 advance checks, checked in order against the actual created
/// checkpoint datum. W1/W2 (between eq5 and eq6) validate the witness delta
/// against the spent witness set: `wit_cut` entries must be pairwise
/// distinct and all members of `spent.witnesses` (W1); `wit_add` entries
/// must be pairwise distinct, disjoint from `wit_cut`, and not already among
/// the surviving (uncut) witnesses (W2). eq6 is the KERI dual-threshold
/// rule: the signer evidence must satisfy the rotation's own
/// `new_cur_threshold` over `new_cur_keys` AND the spent checkpoint's
/// committed `next_threshold` over its `next_keys` digests — where only
/// evidence from keys revealed in `new_cur_keys` counts toward the
/// pre-rotation gate (in KERI, rotation signatures are indexed over the
/// event's own key list). A full stolen spent-current quorum maps to no
/// committed `next_keys` position and is rejected; partial/reserve rotation
/// (a satisfiable subset reveal, with a restated current threshold) is
/// accepted. eq7 (amended, W3) requires the created datum to equal the
/// message's new-state fields exactly, with its witnesses equal to the
/// derived incoming set — survivors (the spent witnesses minus `wit_cut`,
/// in spent order) followed by `wit_add` (in add order) — never the signed
/// lists directly; eq8 requires that state to be well-formed (which alone
/// bounds `new_toad`: rule 14 requires `0 <= new_toad <= length(new_set)`,
/// `0` only when `new_set` is empty).
pub fn advance_equalities(
  spent: SpentCheckpoint,
  message: AdvanceMessage,
  created: CheckpointDatumV1,
  signers: RevealedSuccessorSigners,
) -> AdvanceVerdict {
  let RevealedSuccessorSigners(controlled) = signers
  // The surviving (uncut) witnesses, in spent order — the W3 derivation
  // base, reused by the W2 check and eq7 below.
  let survivors = list.filter(
    spent.witnesses,
    fn(w) { !list.has(message.wit_cut, w) },
  )
  let new_set = list.concat(survivors, message.wit_add)
  if message.domain != advance_domain {
    AdvanceInvalid(AdvanceDomainMismatch)
  } else if !(message.network_id == spent.network_id && message.checkpoint_policy_id == spent.policy_id) {
    // eq1: deployment (network + policy) binding.
    AdvanceInvalid(Eq1NetworkPolicyMismatch)
  } else if !(message.aid_asset_name == deriveAidAssetName(message.cesr_aid) && message.aid_asset_name == spent.aid_asset_name && message.cesr_aid == spent.cesr_aid) {
    // eq2: asset name is the AID's own derived locator, spent asset, and AID.
    AdvanceInvalid(Eq2AssetOrAidMismatch)
  } else if !(message.spent_txid == spent.txid && message.spent_index == spent.index) {
    // eq3: exact spent TxOutRef.
    AdvanceInvalid(Eq3OutRefMismatch)
  } else if !(message.prior_seq == spent.seq && message.prior_native_sn == spent.native_sn) {
    // eq4: the message binds the exact prior projection state.
    AdvanceInvalid(Eq4PriorMismatch)
  } else if !(message.seq_to == spent.seq + 1 && message.native_sn_to > spent.native_sn) {
    // eq5: exact successor sequence; native KERI sequence advances.
    AdvanceInvalid(Eq5SequenceMismatch)
  } else if !(distinct(message.wit_cut) && list.all(
    message.wit_cut,
    fn(w) { list.has(spent.witnesses, w) },
  )) {
    // W1: wit_cut entries are pairwise distinct and all members of the
    // spent witness set (a dup cut or a cut of a non-member is a malformed
    // rotation — neither is otherwise caught, as set-wise both are no-ops).
    AdvanceInvalid(EqW1CutInvalid)
  } else if !(distinct(message.wit_add) && list.all(
    message.wit_add,
    fn(w) { !list.has(message.wit_cut, w) },
  ) && list.all(message.wit_add, fn(w) { !list.has(survivors, w) })) {
    // W2: wit_add entries are pairwise distinct, disjoint from wit_cut (no
    // cut-then-re-add in one event), and not already among the survivors
    // (no add-already-present).
    AdvanceInvalid(EqW2AddInvalid)
  } else if !evaluate(
    message.new_cur_threshold,
    list.length(message.new_cur_keys),
    positions_in(message.new_cur_keys, controlled),
  ) {
    // eq6a: the evidence satisfies the rotation's own current threshold.
    AdvanceInvalid(Eq6CurrentQuorumUnsatisfied)
  } else if !evaluate(
    spent.next_threshold,
    list.length(spent.next_keys),
    positions_in(
      spent.next_keys,
      list.map(
        list.filter(controlled, fn(k) { list.has(message.new_cur_keys, k) }),
        next_key_digest,
      ),
    ),
  ) {
    // eq6b: the evidence revealed in new_cur_keys satisfies the committed
    // (next_keys, next_threshold) — the KERI pre-rotation gate. Each
    // revealing key is digested once (blake3 over its 44-char qb64) to find
    // its committed position; the KEL n entries are matched byte-for-byte.
    AdvanceInvalid(Eq6PriorNextQuorumUnsatisfied)
  } else if created != expected_created(message, new_set) {
    // eq7 (amended, W3): the created datum equals the message's new-state
    // fields exactly, with witnesses equal to the derived incoming set.
    AdvanceInvalid(Eq7CreatedStateMismatch)
  } else {
    // eq8: nothing ill-formed can be written (F18 + rule 14 on the successor).
    when datum_well_formed(created) is {
      DatumInvalid(e) -> AdvanceInvalid(Eq8CreatedIllFormed(e))
      _ -> AdvanceValid
    }
  }
}

/// Pairwise distinctness (no duplicate `ByteArray` entries).
fn distinct(xs: List<ByteArray>) -> Bool {
  list.length(list.unique(xs)) == list.length(xs)
}

/// Positions in `keys` whose digest is among the `controlled` signer
/// evidence — the key-based mapping eq6 evaluates on both sides of the
/// dual-threshold rule.
fn positions_in(keys: List<ByteArray>, controlled: List<ByteArray>) -> List<Int> {
  list.indexed_foldr(
    keys,
    [],
    fn(i, k, acc) {
      if list.has(controlled, k) {
        [i, ..acc]
      } else {
        acc
      }
    },
  )
}

/// The checkpoint datum the advance message's new-state fields must produce
/// (eq7 baseline): the successor key-state projected forward one step, with
/// witnesses equal to the caller-supplied W3-derived incoming set.
fn expected_created(
  message: AdvanceMessage,
  new_set: List<ByteArray>,
) -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: message.cesr_aid,
    cur_keys: message.new_cur_keys,
    cur_threshold: message.new_cur_threshold,
    next_keys: message.new_next_keys,
    next_threshold: message.new_next_threshold,
    witnesses: new_set,
    toad: message.new_toad,
    seq: message.seq_to,
    native_sn: message.native_sn_to,
  }
}
