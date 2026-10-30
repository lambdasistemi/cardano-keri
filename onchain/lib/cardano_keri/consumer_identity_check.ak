//// The claims of the Lean concrete interpretation, one function each, over an
//// `IdentityVector` (the generated vectors module builds the vectors and runs
//// one test per claim and vector).
////
//// Every expected byte string is the Lean's, taken from the vector; the Aiken
//// concrete interpretation is the thing under test.

use cardano/address.{Script}
use cardano/transaction.{OutputReference}
use cardano_keri/consumer.{
  ActivePreimage, Context, PublishedRelease, StatePreimage, Token,
  registry_asset, representative_asset,
}
use cardano_keri/consumer_identity_bytes as bytes

/// One vector of `lean/consumer-identity-vectors.json`. `aid` is the Lean
/// `aidOfCesr` of the qualified CESR text, whose UTF-8 bytes are `key`.
pub type IdentityVector {
  state_policy: ByteArray,
  seed: OutputReference,
  aid: Int,
  state_preimage: ByteArray,
  state_name: ByteArray,
  key: ByteArray,
  active_preimage: ByteArray,
  active_name: ByteArray,
  asset: Token,
}

/// The relying contract's fixed context for a vector: the state policy, the
/// seed and the AID. The other release fields do not take part in naming.
pub fn context_of(v: IdentityVector) -> Context {
  Context {
    network: 0,
    release: PublishedRelease {
      application_policy: #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      application_credential: Script(
        #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      state_program: #"dddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      state_policy: v.state_policy,
    },
    seed: v.seed,
    aid: v.aid,
  }
}

/// `code (State seed)` is the vector's state preimage.
pub fn state_preimage_ok(v: IdentityVector) -> Bool {
  bytes.code(StatePreimage { seed: v.seed }) == v.state_preimage
}

/// The registry name is the hash of the state preimage, alone and as the
/// predicate's own `registry_asset` computes it.
pub fn state_name_ok(v: IdentityVector) -> Bool {
  let registry = registry_asset(bytes.hash, bytes.code, context_of(v))
  bytes.hash(v.state_preimage) == v.state_name && registry == Token {
    policy: v.state_policy,
    name: v.state_name,
  }
}

/// The key of the AID is its CESR text bytes: the Lean carrier `unpack`.
pub fn key_ok(v: IdentityVector) -> Bool {
  bytes.key_of(v.aid) == v.key
}

/// The AID of the CESR text bytes is the Lean `aidOfCesr`: the other direction.
pub fn aid_ok(v: IdentityVector) -> Bool {
  bytes.aid_of_cesr(v.key) == v.aid
}

/// `code (Active registry key)` is the vector's active preimage.
pub fn active_preimage_ok(v: IdentityVector) -> Bool {
  bytes.code(
    ActivePreimage {
      registry: Token { policy: v.state_policy, name: v.state_name },
      key: v.key,
    },
  ) == v.active_preimage
}

/// The active name is the hash of the active preimage.
pub fn active_name_ok(v: IdentityVector) -> Bool {
  bytes.hash(v.active_preimage) == v.active_name
}

/// The representative asset, as the predicate computes it from the context,
/// is the vector's asset: the state policy and the active name.
pub fn asset_ok(v: IdentityVector) -> Bool {
  representative_asset(bytes.hash, bytes.code, bytes.key_of, context_of(v)) == v.asset
}
