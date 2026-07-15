//// Frozen signed inception/advance message domains + locator asset-name
//// derivation (#68 Slice 6).
////
//// Mirrors the Slice-3 Haskell `Cardano.KERI.AID.Checkpoint.Message`
//// byte-for-byte: the two domain-separated signed preimages
//// (`InceptionMessage` = Constr 0, 11 fields; `AdvanceMessage` = Constr 0,
//// 17 fields) and `deriveAidAssetName` over the frozen 65-byte
//// `CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x46 ‖ cesr_aid` preimage encode to the
//// exact canonical Plutus-Data CBOR / `blake2b_256` digest the Haskell
//// encoder emits (see `vectors.ak`). Domain strings, constructor indices, and
//// field order are protocol surface; they change only by minting a new
//// version tag. Each message binds the deployment (`network_id`,
//// `checkpoint_policy_id`) and token (`aid_asset_name`), and every carried
//// `aid_asset_name` must equal `deriveAidAssetName(cesr_aid)`.

use aiken/collection/list
use aiken/crypto
use aiken/primitive/bytearray
use cardano_keri/checkpoint/datum.{
  CheckpointDatumV1, NextCommitment, keyset_commit,
}
use cardano_keri/checkpoint/threshold.{Threshold, evaluate}

// ---------------------------------------------------------
// Frozen constants
// ---------------------------------------------------------

/// `CHECKPOINT_ASSET_DOMAIN_TAG = UTF8("cardano-keri/checkpoint-asset/v1")` —
/// a constant 32-byte domain tag.
pub const checkpoint_asset_domain_tag: ByteArray =
  #"63617264616e6f2d6b6572692f636865636b706f696e742d61737365742f7631"

/// The frozen inception message domain: `UTF8("cardano-keri/checkpoint/icp/v1")`.
pub const inception_domain: ByteArray =
  #"63617264616e6f2d6b6572692f636865636b706f696e742f6963702f7631"

/// The frozen advance message domain: `UTF8("cardano-keri/checkpoint/adv/v1")`.
pub const advance_domain: ByteArray =
  #"63617264616e6f2d6b6572692f636865636b706f696e742f6164762f7631"

// ---------------------------------------------------------
// Locator asset-name derivation (#92 -> #68 pin)
// ---------------------------------------------------------

/// `aid_asset_name = blake2b_256(CHECKPOINT_ASSET_DOMAIN_TAG ‖ 0x46 ‖ cesr_aid)`
/// over the fixed 65-byte preimage. `0x46` = ASCII `'F'`, the V1 F-only
/// (Blake2b-256) derivation code. The asset name is a deterministic label of
/// the AID; changing either constant requires a new version tag.
pub fn deriveAidAssetName(cesr_aid: ByteArray) -> ByteArray {
  crypto.blake2b_256(
    bytearray.concat(
      checkpoint_asset_domain_tag,
      bytearray.concat(#"46", cesr_aid),
    ),
  )
}

// ---------------------------------------------------------
// Inception message (icp) — Constr 0, 11 fields in frozen order
// ---------------------------------------------------------

/// The signed inception preimage (Constr 0; 11 fields in frozen order).
pub type InceptionMessage {
  domain: ByteArray,
  network_id: Int,
  checkpoint_policy_id: ByteArray,
  aid_asset_name: ByteArray,
  cesr_aid: ByteArray,
  cur_keys: List<ByteArray>,
  cur_threshold: Threshold,
  next_digest: ByteArray,
  witnesses: List<ByteArray>,
  toad: Int,
  native_sn: Int,
}

// ---------------------------------------------------------
// Advance message (rotation / two-seal handoff) — Constr 0, 17 fields
// ---------------------------------------------------------

/// The signed advance preimage (Constr 0; 17 fields in frozen order). The
/// advance is authorized by the revealed successor set
/// (`new_cur_keys`/`new_cur_threshold`), never the spent current set (KERI
/// pre-rotation).
pub type AdvanceMessage {
  domain: ByteArray,
  network_id: Int,
  checkpoint_policy_id: ByteArray,
  aid_asset_name: ByteArray,
  cesr_aid: ByteArray,
  spent_txid: ByteArray,
  spent_index: Int,
  prior_commit: ByteArray,
  prior_seq: Int,
  prior_native_sn: Int,
  new_cur_keys: List<ByteArray>,
  new_cur_threshold: Threshold,
  new_next_digest: ByteArray,
  new_witnesses: List<ByteArray>,
  new_toad: Int,
  seq_to: Int,
  native_sn_to: Int,
}

// ---------------------------------------------------------
// Inception validation (event-type + AID/asset binding)
// ---------------------------------------------------------

/// The attested KERI inception event type. V1 accepts only `Icp`; a delegated
/// (`Dip`) or rotation (`Drt`) inception is rejected.
pub type EventType {
  Icp
  Dip
  Drt
}

/// An inception rejection reason (mirrors the Slice-3 `InceptionError`).
pub type InceptionError {
  /// A delegated (`Dip`) or rotation (`Drt`) inception was attested.
  DelegatedInceptionRejected
  /// `cesr_aid` is not exactly 32 bytes (malformed AID width).
  InceptionAidWidth
  /// `aid_asset_name /= deriveAidAssetName(cesr_aid)`.
  InceptionAssetMismatch
}

/// The inception acceptance verdict. Aiken's prelude has no `Result`, so this
/// mirrors the Slice-3 `Either InceptionError ()`: `InceptionValid` ≙ `Right ()`,
/// `InceptionInvalid(e)` ≙ `Left e`.
pub type InceptionVerdict {
  InceptionValid
  InceptionInvalid(InceptionError)
}

/// Registration acceptance predicate: the attested event must be a
/// non-delegated `icp`, the `cesr_aid` must be a well-formed 32-byte AID, and
/// the carried asset name must be the AID's own derived locator (a copied
/// caller name is insufficient). The width check precedes the derivation check
/// so a malformed AID is rejected on width, not on a coincidental derivation.
pub fn validate_inception(
  event: EventType,
  message: InceptionMessage,
) -> InceptionVerdict {
  when event is {
    Icp ->
      if bytearray.length(message.cesr_aid) != 32 {
        InceptionInvalid(InceptionAidWidth)
      } else if message.aid_asset_name != deriveAidAssetName(message.cesr_aid) {
        InceptionInvalid(InceptionAssetMismatch)
      } else {
        InceptionValid
      }
    _ -> InceptionInvalid(DelegatedInceptionRejected)
  }
}

// ---------------------------------------------------------
// Advance validation (the seven F10 equalities) — #77 / parent #21
// ---------------------------------------------------------

/// The spent checkpoint context an advance is validated against: its
/// deployment, identity-asset name, exact `TxOutRef`, and prior key-state
/// projection fields (mirrors the Slice-3 `SpentCheckpoint`).
pub type SpentCheckpoint {
  network_id: Int,
  policy_id: ByteArray,
  aid_asset_name: ByteArray,
  txid: ByteArray,
  index: Int,
  cesr_aid: ByteArray,
  next_digest: ByteArray,
  seq: Int,
  native_sn: Int,
}

/// The key digests of the raw keys that produced valid signatures (the signer
/// evidence). eq6 maps this evidence onto `new_cur_keys` positions and
/// `evaluate`s the REVEALED successor threshold. Because the evidence is
/// key-based, the SAME evidence can be evaluated against the spent-current set:
/// a stolen spent-current quorum satisfies the spent-current threshold yet maps
/// to no successor position, so it fails the successor threshold and is
/// rejected (mirrors the Slice-3 `RevealedSuccessorSigners`).
pub type RevealedSuccessorSigners {
  RevealedSuccessorSigners(List<ByteArray>)
}

/// Which of the seven F10 advance equalities rejected (mirrors the Slice-3
/// `AdvanceError`).
pub type AdvanceError {
  /// eq1: `network_id` / `checkpoint_policy_id` do not match the deployment.
  Eq1NetworkPolicyMismatch
  /// eq2: asset name is not the AID's derived locator, or the AID crossed.
  Eq2AssetOrAidMismatch
  /// eq3: `(spent_txid, spent_index)` is not the spent `TxOutRef`.
  Eq3OutRefMismatch
  /// eq4: the reveal does not match `spent.next_digest` / prior fields.
  Eq4PriorMismatch
  /// eq5: `seq_to /= spent.seq + 1` or `native_sn_to` did not advance.
  Eq5SequenceMismatch
  /// eq6: the REVEALED successor set did not authorize the advance.
  Eq6SuccessorQuorumUnsatisfied
  /// eq7: the created datum does not equal the message's new-state fields.
  Eq7CreatedStateMismatch
}

/// The advance acceptance verdict. `AdvanceValid` ≙ `Right ()`,
/// `AdvanceInvalid(e)` ≙ `Left e` (mirrors the Slice-3
/// `Either AdvanceError ()`).
pub type AdvanceVerdict {
  AdvanceValid
  AdvanceInvalid(AdvanceError)
}

/// The seven F10 advance equalities, checked in order against the actual
/// created checkpoint datum. Crucially eq6 evaluates the signer evidence
/// against the REVEALED successor set (`new_cur_keys`/`new_cur_threshold`), not
/// the spent current set — so a full stolen spent-current quorum yields no
/// successor authorization and is rejected. eq7 requires the created datum to
/// equal the message's new-state fields exactly (nothing written that was not
/// signed).
pub fn advance_equalities(
  spent: SpentCheckpoint,
  message: AdvanceMessage,
  created: CheckpointDatumV1,
  signers: RevealedSuccessorSigners,
) -> AdvanceVerdict {
  let RevealedSuccessorSigners(controlled) = signers
  // eq1: deployment (network + policy) binding.
  if !(message.network_id == spent.network_id && message.checkpoint_policy_id == spent.policy_id) {
    AdvanceInvalid(Eq1NetworkPolicyMismatch)
  } else if !(message.aid_asset_name == deriveAidAssetName(message.cesr_aid) && message.aid_asset_name == spent.aid_asset_name && message.cesr_aid == spent.cesr_aid) {
    // eq2: asset name is the AID's own derived locator, spent asset, and AID.
    AdvanceInvalid(Eq2AssetOrAidMismatch)
  } else if !(message.spent_txid == spent.txid && message.spent_index == spent.index) {
    // eq3: exact spent TxOutRef.
    AdvanceInvalid(Eq3OutRefMismatch)
  } else if !(message.prior_commit == spent.next_digest && message.prior_commit == keyset_commit(
    NextCommitment {
      next_keys: message.new_cur_keys,
      next_threshold: message.new_cur_threshold,
    },
  ) && message.prior_seq == spent.seq && message.prior_native_sn == spent.native_sn) {
    // eq4: the reveal matches the pre-committed successor and prior fields.
    AdvanceInvalid(Eq4PriorMismatch)
  } else if !(message.seq_to == spent.seq + 1 && message.native_sn_to > spent.native_sn) {
    // eq5: exact successor sequence; native KERI sequence advances.
    AdvanceInvalid(Eq5SequenceMismatch)
  } else if !evaluate(
    message.new_cur_threshold,
    list.length(message.new_cur_keys),
    successor_positions(message.new_cur_keys, controlled),
  ) {
    // eq6: the REVEALED successor set authorizes (NOT the spent current set).
    AdvanceInvalid(Eq6SuccessorQuorumUnsatisfied)
  } else if created != expected_created(message) {
    // eq7: the created datum equals the message's new-state fields exactly.
    AdvanceInvalid(Eq7CreatedStateMismatch)
  } else {
    AdvanceValid
  }
}

/// Positions in `keys` whose digest is among the `controlled` signer evidence
/// — the key-based mapping eq6 evaluates against the revealed successor set. A
/// spent-current key never appears in the successor `keys`, so its evidence
/// contributes no position.
fn successor_positions(
  keys: List<ByteArray>,
  controlled: List<ByteArray>,
) -> List<Int> {
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
/// (eq7 baseline): the successor key-state projected forward one step.
fn expected_created(message: AdvanceMessage) -> CheckpointDatumV1 {
  CheckpointDatumV1 {
    cesr_aid: message.cesr_aid,
    cur_keys: message.new_cur_keys,
    cur_threshold: message.new_cur_threshold,
    next_digest: message.new_next_digest,
    witnesses: message.new_witnesses,
    toad: message.new_toad,
    seq: message.seq_to,
    native_sn: message.native_sn_to,
  }
}
