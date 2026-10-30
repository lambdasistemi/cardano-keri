//// The consumer predicate (#343), RED stub: every function is a placeholder
//// that cannot satisfy the Lean `consumableHoldingB`. Replaced by the
//// transcription in the GREEN commit.

use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Output, OutputReference}

/// Lean `PublishedRelease`.
pub type PublishedRelease {
  application_policy: PolicyId,
  application_credential: Credential,
  state_program: ByteArray,
  state_policy: PolicyId,
}

/// Lean `Singular.TokenId`.
pub type Token {
  policy: PolicyId,
  name: AssetName,
}

/// Lean `Context`: fixed by the relying contract.
pub type Context {
  network: Int,
  release: PublishedRelease,
  seed: OutputReference,
  aid: Int,
}

/// Lean `Environment`: `release: None` is an unresolved release.
pub type Environment {
  network: Int,
  release: Option<PublishedRelease>,
}

/// Lean `Preimage`, the two constructors the predicate uses.
pub type Preimage {
  StatePreimage { seed: OutputReference }
  ActivePreimage { registry: Token, key: ByteArray }
}

/// Lean `Checkpoint.Params`; the predicate reads only `w`.
pub type Params {
  d: Int,
  b: Int,
  p: Int,
  w: Int,
}

/// Lean `Checkpoint.Hash`.
pub type Hash {
  epoch: Int,
  sn: Int,
}

/// Lean `Checkpoint.Live`.
pub type Live {
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: Int,
  pool: Int,
}

/// Lean `Checkpoint.State`.
pub type State {
  Absent
  Present(Live)
  Parked(Hash)
  TerminationPending(Hash)
  Convicted
}

/// Lean `DecodedDatum`.
pub type DecodedDatum {
  aid: Int,
  state: State,
}

/// Lean `Interpretation`, as four function parameters of the predicate: the
/// hash, the codec, the AID-to-key map and the datum decoder. The candidate
/// output never selects them. (Data types cannot hold functions, so there is
/// no record to bundle them in.)
pub type HashFn =
  fn(ByteArray) -> AssetName

pub type CodeFn =
  fn(Preimage) -> ByteArray

pub type KeyFn =
  fn(Int) -> ByteArray

pub type DecodeFn =
  fn(PublishedRelease, Data) -> Option<DecodedDatum>

pub fn registry_asset(_hash: HashFn, _code: CodeFn, c: Context) -> Token {
  Token { policy: c.release.state_policy, name: #"" }
}

pub fn representative_asset(
  _hash: HashFn,
  _code: CodeFn,
  _key_of: KeyFn,
  c: Context,
) -> Token {
  Token { policy: c.release.state_policy, name: #"" }
}

pub fn decoded(
  _decode: DecodeFn,
  _c: Context,
  _o: Output,
) -> Option<DecodedDatum> {
  None
}

pub fn authenticated_context(_c: Context, _e: Environment) -> Bool {
  False
}

pub fn consumable_state(_p: Params, _now: Int, _s: State) -> Bool {
  False
}

pub fn consumable_holding(
  _hash: HashFn,
  _code: CodeFn,
  _key_of: KeyFn,
  _decode: DecodeFn,
  _c: Context,
  _e: Environment,
  _p: Params,
  _now: Int,
  _o: Output,
) -> Bool {
  False
}
