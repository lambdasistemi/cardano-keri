//// Locator asset-name derivation + pure advance transition (#115 R3).
////
//// Mirrors the Haskell `Cardano.KERI.AID.Checkpoint.Message`:
//// `deriveAidAssetName` over the frozen 65-byte
//// `CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x45 ‖ cesr_aid` preimage, and the pure
//// advance transition equalities over OLD (`SpentCheckpoint`), NEW
//// (created `CheckpointDatumV1`), evidence witness-delta lists, and
//// revealed successor signers.
////
//// The advance is authorized by the KERI dual-threshold rule: the signer
//// evidence must satisfy the rotation's own current threshold over
//// `NEW.cur_keys` AND the spent checkpoint's pre-rotation threshold
//// (`next_threshold`) over the committed `next_keys` digests. Partial/reserve
//// rotation is supported. R3 deletes the Cardano-specific `AdvanceMessage`
//// signed preimage; controller signatures verify over exact KERI
//// `event_bytes` in `advance.ak`. The pure transition binds AID continuity,
//// sequence advance, the incoming-set witness rule (W1-W3), dual-threshold
//// controller evidence, and successor well-formedness.

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
// Advance transition context
// ---------------------------------------------------------

/// The spent checkpoint context an advance is validated against: its
/// deployment, identity-asset name, exact `TxOutRef`, current witness set
/// (the W1-W3 delta base), and prior key-state projection fields —
/// including the committed `(next_keys, next_threshold)` pair the
/// dual-threshold rule evaluates (mirrors the Slice-3 `SpentCheckpoint`). A
/// validation-context type, not a wire type; the spend/observer branch fills
/// it from the spent inline datum.
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
/// evidence). eq6 maps this evidence onto `NEW.cur_keys` positions (the
/// rotation's own threshold) AND onto the spent checkpoint's committed
/// `next_keys` positions (the pre-rotation threshold) — KERI's dual-threshold
/// rule. A stolen spent-current quorum maps to no committed `next_keys`
/// position, so it fails the pre-rotation threshold and is rejected (mirrors
/// the Slice-3 `RevealedSuccessorSigners`).
pub type RevealedSuccessorSigners {
  RevealedSuccessorSigners(List<ByteArray>)
}

/// Which advance transition check rejected (mirrors the Haskell
/// `AdvanceError` after R3 message deletion).
pub type AdvanceError {
  /// AID crossed or spent locator is not `deriveAidAssetName(cesr_aid)`.
  Eq2AssetOrAidMismatch
  /// `NEW.seq /= OLD.seq + 1` or `NEW.native_sn` did not advance.
  Eq5SequenceMismatch
  /// W1: `wit_cut` entries are not pairwise distinct, or one is not a
  /// member of the spent witness set.
  EqW1CutInvalid
  /// W2: `wit_add` entries are not pairwise distinct, overlap `wit_cut`, or
  /// one is already among the surviving (uncut) witnesses.
  EqW2AddInvalid
  /// eq6: the revealed set did not satisfy NEW's current threshold.
  Eq6CurrentQuorumUnsatisfied
  /// eq6: the evidence did not satisfy the spent checkpoint's committed
  /// `(next_keys, next_threshold)` — the KERI pre-rotation gate.
  Eq6PriorNextQuorumUnsatisfied
  /// eq7: created witnesses are not the W3-derived incoming set.
  Eq7CreatedStateMismatch
  /// eq8: the created datum failed `datum_well_formed` (F18 + rule 14).
  Eq8CreatedIllFormed(DatumError)
}

/// The advance acceptance verdict. `AdvanceValid` ≙ `Right ()`,
/// `AdvanceInvalid(e)` ≙ `Left e`.
pub type AdvanceVerdict {
  AdvanceValid
  AdvanceInvalid(AdvanceError)
}

/// The pure advance transition checks, in order, against OLD, NEW, and the
/// evidence witness-delta lists. W1/W2 validate the witness delta against the
/// spent witness set. eq6 is the KERI dual-threshold rule over the revealed
/// signers. eq7 (W3) requires `NEW.witnesses` equal the derived incoming set
/// (survivors in spent order, then adds in add order). eq8 requires NEW to be
/// well-formed.
pub fn advance_equalities(
  spent: SpentCheckpoint,
  created: CheckpointDatumV1,
  wit_cut: List<ByteArray>,
  wit_add: List<ByteArray>,
  signers: RevealedSuccessorSigners,
) -> AdvanceVerdict {
  let RevealedSuccessorSigners(controlled) = signers
  // The surviving (uncut) witnesses, in spent order — the W3 derivation
  // base, reused by the W2 check and eq7 below.
  let survivors = list.filter(spent.witnesses, fn(w) { !list.has(wit_cut, w) })
  let new_set = list.concat(survivors, wit_add)
  if !(created.cesr_aid == spent.cesr_aid && spent.aid_asset_name == deriveAidAssetName(
    spent.cesr_aid,
  )) {
    // AID continuity + spent locator well-formedness.
    AdvanceInvalid(Eq2AssetOrAidMismatch)
  } else if !(created.seq == spent.seq + 1 && created.native_sn > spent.native_sn) {
    // Exact successor sequence; native KERI sequence advances.
    AdvanceInvalid(Eq5SequenceMismatch)
  } else if !(distinct(wit_cut) && list.all(
    wit_cut,
    fn(w) { list.has(spent.witnesses, w) },
  )) {
    // W1: wit_cut entries are pairwise distinct and all members of the
    // spent witness set.
    AdvanceInvalid(EqW1CutInvalid)
  } else if !(distinct(wit_add) && list.all(
    wit_add,
    fn(w) { !list.has(wit_cut, w) },
  ) && list.all(wit_add, fn(w) { !list.has(survivors, w) })) {
    // W2: wit_add entries are pairwise distinct, disjoint from wit_cut, and
    // not already among the survivors.
    AdvanceInvalid(EqW2AddInvalid)
  } else if !evaluate(
    created.cur_threshold,
    list.length(created.cur_keys),
    positions_in(created.cur_keys, controlled),
  ) {
    // eq6a: the evidence satisfies NEW's own current threshold.
    AdvanceInvalid(Eq6CurrentQuorumUnsatisfied)
  } else if !evaluate(
    spent.next_threshold,
    list.length(spent.next_keys),
    positions_in(
      spent.next_keys,
      list.map(
        list.filter(controlled, fn(k) { list.has(created.cur_keys, k) }),
        next_key_digest,
      ),
    ),
  ) {
    // eq6b: the evidence revealed in NEW.cur_keys satisfies the committed
    // (next_keys, next_threshold) — the KERI pre-rotation gate.
    AdvanceInvalid(Eq6PriorNextQuorumUnsatisfied)
  } else if created.witnesses != new_set {
    // eq7 (W3): NEW.witnesses equal the derived incoming set.
    AdvanceInvalid(Eq7CreatedStateMismatch)
  } else {
    // eq8: nothing ill-formed can be written.
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
