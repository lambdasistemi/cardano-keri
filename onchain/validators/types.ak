use aiken/crypto.{VerificationKeyHash}
use aiken/merkle_patricia_forestry.{Proof}
use cardano/transaction.{OutputReference}
use lib.{TokenId}

pub type Mint {
  asset: OutputReference,
}

/// Migration of a cage thread token from the pinned predecessor policy to this
/// cage policy. The predecessor policy is a `mpfCage` validator parameter (not a
/// caller-supplied field), so an attacker-created predecessor cannot satisfy the
/// migration by construction.
pub type Migration {
  tokenId: TokenId,
}

pub type MintRedeemer {
  Minting(Mint)
  Migrating(Migration)
  Burning(TokenId)
}

/// Owner authorization for a value-write operation.
/// Proves the requester controls the AID registered in the identity trie.
pub type OwnerAuth {
  /// Key in the identity_root MPF trie identifying this AID.
  owner_aid: ByteArray,
  /// MPF inclusion proof: identity_root[owner_aid] = blake2b_256(owner_key).
  identity_proof: Proof,
  /// Raw Ed25519 public key (32 bytes). blake2b_256(owner_key) must match
  /// the value at owner_aid in the identity trie.
  owner_key: ByteArray,
  /// Ed25519 signature (64 bytes) over blake2b_256(domain ++ request_out_ref).
  owner_sig: ByteArray,
}

pub type RequestAction {
  /// Apply the request's MPF operation using value_proof, after verifying
  /// the owner's identity and signature via auth.
  UpdateAction { value_proof: Proof, auth: OwnerAuth }
  /// Reject the request (expiry or dishonest timestamp).
  Rejected
}

pub type UpdateRedeemer {
  End
  Contribute(OutputReference)
  Modify(List<RequestAction>)
  Retract(OutputReference)
}

/// State datum extended with identity_root.
pub type State {
  owner: VerificationKeyHash,
  /// Current MPF root of the value trie.
  root: ByteArray,
  /// Snapshot of the AID identity registry MPF root.
  /// Maps owner_aid -> blake2b_256(cur_pubkey).
  /// Oracle may update this field in the Modify output datum.
  identity_root: ByteArray,
  tip: Int,
  process_time: Int,
  retract_time: Int,
}

pub type Operation {
  Insert(ByteArray)
  Delete(ByteArray)
  Update(ByteArray, ByteArray)
}

pub type Request {
  requestToken: TokenId,
  requestOwner: VerificationKeyHash,
  requestKey: ByteArray,
  requestValue: Operation,
  tip: Int,
  submitted_at: Int,
}

pub type CageDatum {
  RequestDatum(Request)
  StateDatum(State)
}
