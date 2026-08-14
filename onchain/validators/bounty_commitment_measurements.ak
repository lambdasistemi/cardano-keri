//// #254 S254-E — applied #271 commitment-program ex-unit measurements.
////
//// The adopted component became part of a settlement path in S254-E: a hunter
//// now opens a reservation, matures it, and reveals it inside the same story
//// that arms or convicts a checkpoint. Its cost is therefore part of the
//// entitled family's cost, and it had no measurement of its own.
////
//// These are the three lifecycle ACCEPT contexts of the APPLIED program —
//// `bounty_commitment.bounty_commitment`, with its real
//// `CommitmentParameters` argument — not calls to the pure predicates
//// underneath. A measurement of the predicates would miss exactly what the
//// applied program adds.
////
//// Like `measure-enforcement` and `measure-checkpoint`, this is an
//// INVOCATION: Aiken cannot assert its own ex-units in-test, so
//// `just measure-bounty-commitment` runs these with `--plain-numbers` and
//// mechanically enforces the exact titles and the caps.

use aiken/interval
use bounty_commitment as commitment_program
use cage_context.{out_ref, spend_context}
use cardano/address.{from_script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, placeholder,
}
use cardano_keri/bounty_commitment.{
  BountyCommitment, BountyCommitmentV1, BountyRevealV1, BountyScope,
  CommitmentParameters, ExpiredCommitmentSweepV1, FreezeEntitlement, Open,
  Retire, Reveal, Sweep, commitment_domain, commitment_hash, commitment_preimage,
  commitment_schema, marker_name,
}

// ---------------------------------------------------------------------
// Applied release identity
// ---------------------------------------------------------------------

/// The applied commitment policy. One script hash is both the marker's policy
/// id and the commitment output's payment credential, so a single constant
/// drives both sides of every fixture below.
const policy: PolicyId =
  #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

const checkpoint_policy: PolicyId =
  #"cccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

const network_id: Int = 0

/// EXPLICIT applied magnitudes. A finite named release lifetime, the mandated
/// one-slot maturity, and the demonstrated deposit floor. There is no protocol
/// default for the lifetime and none is recreated here.
const applied_lifetime: Int = 7_200

const applied_deposit: Int = 5_000_000

const parameters: CommitmentParameters =
  CommitmentParameters {
    network: network_id,
    commit_min_age: 1,
    commitment_lifetime: applied_lifetime,
    commit_deposit: applied_deposit,
  }

const payee: ByteArray =
  #"9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a"

const recipient: ByteArray =
  #"7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e7e"

const evidence_digest: ByteArray =
  #"edededededededededededededededededededededededededededededededed"

const nonce: ByteArray =
  #"1111111111111111111111111111111111111111111111111111111111111111"

const seed_txid: ByteArray =
  #"5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e"

const checkpoint_txid: ByteArray =
  #"c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"

const commitment_txid: ByteArray =
  #"0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c"

const commit_upper: Int = 1_000

// ---------------------------------------------------------------------
// The fixture
// ---------------------------------------------------------------------

fn seed_ref() -> OutputReference {
  out_ref(seed_txid, 7)
}

fn marker() -> ByteArray {
  marker_name(seed_ref())
}

fn commitment_ref() -> OutputReference {
  out_ref(commitment_txid, 0)
}

fn scope() -> BountyScope {
  BountyScope {
    domain: commitment_domain,
    schema: commitment_schema,
    network: network_id,
    checkpoint_policy,
    checkpoint_ref: out_ref(checkpoint_txid, 3),
    action: FreezeEntitlement,
    marker: marker(),
    commit_upper,
    eligible_after: commit_upper + 1,
    expires_at: commit_upper + applied_lifetime,
  }
}

fn commitment() -> BountyCommitment {
  let s = scope()
  BountyCommitmentV1 {
    scope: s,
    payee_pkh: payee,
    hash: commitment_hash(commitment_preimage(s, evidence_digest, payee, nonce)),
    marker: marker(),
  }
}

/// Exactly the applied deposit plus the quantity-one marker, and nothing else.
fn commitment_value() -> Value {
  from_lovelace(applied_deposit) |> merge(from_asset(policy, marker(), 1))
}

fn commitment_output() -> Output {
  Output {
    address: from_script(policy),
    value: commitment_value(),
    datum: InlineDatum(commitment()),
    reference_script: None,
  }
}

fn commitment_input() -> Input {
  Input { output_reference: commitment_ref(), output: commitment_output() }
}

/// A datum-free, reference-script-free enterprise payout of exactly the
/// deposit.
fn payout(pkh: ByteArray) -> Output {
  Output {
    address: from_verification_key(pkh),
    value: from_lovelace(applied_deposit),
    datum: NoDatum,
    reference_script: None,
  }
}

fn seed_input() -> Input {
  Input {
    output_reference: seed_ref(),
    output: Output {
      address: from_verification_key(payee),
      value: from_lovelace(applied_deposit + 2_000_000),
      datum: NoDatum,
      reference_script: None,
    },
  }
}

/// The opening transaction: the seed is consumed, the marker is minted at
/// quantity one, the single script output confines exactly marker plus
/// deposit, and the future beneficiary signs.
fn open_tx() -> Transaction {
  Transaction {
    ..placeholder,
    inputs: [seed_input()],
    outputs: [commitment_output()],
    mint: from_asset(policy, marker(), 1),
    extra_signatories: [payee],
    validity_range: interval.between(commit_upper - 100, commit_upper),
  }
}

/// The reveal transaction: matured, unexpired, exactly one marker burned, the
/// exact deposit refunded to the committed payee, and the payee signing.
fn reveal_tx() -> Transaction {
  spend_context(
    [commitment_input()],
    [],
    [payout(payee)],
    from_asset(policy, marker(), -1),
    [payee],
    interval.between(commit_upper + 1, commit_upper + 2),
    0,
  )
}

/// The expired-sweep transaction: strictly past expiry, the marker burned, the
/// deposit recovered by the signing recipient, and no checkpoint effect.
fn sweep_tx() -> Transaction {
  spend_context(
    [commitment_input()],
    [],
    [payout(recipient)],
    from_asset(policy, marker(), -1),
    [recipient],
    interval.between(
      commit_upper + applied_lifetime + 1,
      commit_upper + applied_lifetime + 2,
    ),
    0,
  )
}

// ---------------------------------------------------------------------
// The three applied-program ACCEPT contexts
// ---------------------------------------------------------------------

test measure_bounty_commitment_open() {
  commitment_program.bounty_commitment.mint(
    parameters,
    Open { seed_ref: seed_ref() },
    policy,
    open_tx(),
  )
}

test measure_bounty_commitment_reveal() {
  commitment_program.bounty_commitment.spend(
    parameters,
    None,
    Reveal(
      BountyRevealV1 {
        commitment_ref: commitment_ref(),
        nonce,
        refund_index: 0,
      },
    ),
    commitment_ref(),
    reveal_tx(),
  )
}

test measure_bounty_commitment_sweep() {
  commitment_program.bounty_commitment.spend(
    parameters,
    None,
    Sweep(
      ExpiredCommitmentSweepV1 { recipient_pkh: recipient, payout_index: 0 },
    ),
    commitment_ref(),
    sweep_tx(),
  )
}

/// Retirement is the mint side of both a reveal and a sweep, so it is measured
/// where it actually runs rather than assumed to be free.
test measure_bounty_commitment_retire() {
  commitment_program.bounty_commitment.mint(
    parameters,
    Retire,
    policy,
    reveal_tx(),
  )
}
