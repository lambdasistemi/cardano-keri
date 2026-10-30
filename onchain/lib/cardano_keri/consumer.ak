//// The consumer predicate (#343): the Lean `consumableHoldingB`
//// (lean/CardanoKeri/ConsumerIdentity.lean) clause for clause, over a
//// candidate holding read as a reference input.
////
//// The network, release, seed and AID come from the relying contract
//// (`Context`, `Environment`); hash, codec, AID-to-key map and datum decoder
//// are function parameters (the Lean `Interpretation`). Nothing is read from
//// the candidate output except what the Lean reads: its payment credential,
//// the total quantity of the representative asset, and its datum through the
//// decoder.
////
//// Lean name -> Aiken: registryAsset -> registry_asset, representativeAsset ->
//// representative_asset, decoded -> decoded, authenticatedContextB ->
//// authenticated_context, Checkpoint.consumableStateB -> consumable_state,
//// consumableHoldingB -> consumable_holding. A datum is "an application datum"
//// when it is inline; the decoder says whether it decodes.

use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Output, OutputReference}

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

/// Lean `registryAsset`: the release's state policy and the hash of the
/// code of the State preimage of the seed.
pub fn registry_asset(hash: HashFn, code: CodeFn, c: Context) -> Token {
  Token {
    policy: c.release.state_policy,
    name: hash(code(StatePreimage { seed: c.seed })),
  }
}

/// Lean `representativeAsset`: the registry's policy and the hash of the code
/// of the Active preimage of the registry asset and the AID's key.
pub fn representative_asset(
  hash: HashFn,
  code: CodeFn,
  key_of: KeyFn,
  c: Context,
) -> Token {
  let registry = registry_asset(hash, code, c)
  Token {
    policy: registry.policy,
    name: hash(code(ActivePreimage { registry, key: key_of(c.aid) })),
  }
}

/// Lean `decoded`: only an inline datum is an application datum, and the
/// decoder may still reject it.
pub fn decoded(decode: DecodeFn, c: Context, o: Output) -> Option<DecodedDatum> {
  when o.datum is {
    InlineDatum(raw) -> decode(c.release, raw)
    _ -> None
  }
}

/// Lean `authenticatedContextB`: the observed network is the intended one and
/// the resolved release is exactly the intended complete release.
pub fn authenticated_context(c: Context, e: Environment) -> Bool {
  e.network == c.network && e.release == Some(c.release)
}

/// Lean `Checkpoint.consumableStateB`: present, unfrozen, unpoisoned and at
/// least `w` old.
pub fn consumable_state(p: Params, now: Int, s: State) -> Bool {
  when s is {
    Present(l) -> !l.frozen && !l.poisoned && l.born_at + p.w <= now
    Parked(_) -> False
    TerminationPending(_) -> False
    Absent -> False
    Convicted -> False
  }
}

/// Lean `AH.quantity o (representativeAsset i c)`: the total quantity of the
/// representative asset in the output, over all entries.
pub fn representative_quantity(
  hash: HashFn,
  code: CodeFn,
  key_of: KeyFn,
  c: Context,
  o: Output,
) -> Int {
  let asset = representative_asset(hash, code, key_of, c)
  quantity_of(o.value, asset.policy, asset.name)
}

/// Lean `consumableHoldingB`. Clauses, in the Lean order: authenticated
/// context; application credential; total quantity of the representative
/// asset is one; a decoded datum for the intended AID in a consumable state.
pub fn consumable_holding(
  hash: HashFn,
  code: CodeFn,
  key_of: KeyFn,
  decode: DecodeFn,
  c: Context,
  e: Environment,
  p: Params,
  now: Int,
  o: Output,
) -> Bool {
  and {
    authenticated_context(c, e),
    o.address.payment_credential == c.release.application_credential,
    representative_quantity(hash, code, key_of, c, o) == 1,
    when decoded(decode, c, o) is {
      None -> False
      Some(d) -> d.aid == c.aid && consumable_state(p, now, d.state)
    },
  }
}
