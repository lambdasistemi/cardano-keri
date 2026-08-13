//// #271 S271-1 — full-transaction proofs for the combined bounty
//// commitment program (T271-102/103/104).
////
//// Every test drives the REAL handlers —
//// `bounty_commitment.bounty_commitment.mint` and `.spend` — on a complete
//// `Transaction`, following the #99/#114 precedent. The honest transaction
//// of each shape is built once; every rejection case is that exact
//// transaction with one field changed, so a rejection can only be caused by
//// the mutation under test.
////
//// The protocol fixture (scope, parameters, marker, hashes) comes from the
//// Haskell-generated vectors through `bounty_commitment_tests`, so the
//// transactions here and the parity proofs there are the same commitment.

use aiken/interval.{Interval, NegativeInfinity, PositiveInfinity}
use bounty_commitment
use cage_context.{spend_context}
use cardano/address.{Address, Script, from_verification_key}
use cardano/assets.{PolicyId, Value, from_asset, from_lovelace, merge, zero}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use cardano_keri/bounty_commitment.{
  BountyCommitment, BountyCommitmentV1, BountyRevealV1, BountyScope,
  CommitmentParameters, ExpiredCommitmentSweepV1, Open, Retire, Reveal, Sweep,
} as protocol
use cardano_keri/bounty_commitment_tests.{
  alt_expires_at, alt_lifetime, alt_parameters, between, commitment,
  example_lifetime, flip_last, from_slot, other_seed_ref, parameters, scope,
  seed_ref, until_slot, window,
}
use cardano_keri/bounty_commitment_vectors as vec

/// The applied program's own script hash: simultaneously the marker policy
/// id and the commitment output's payment credential.
const policy: PolicyId =
  #"b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0"

/// A foreign script, used to prove a look-alike output elsewhere is inert.
const other_policy: PolicyId =
  #"f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0"

/// Where the live commitment sits — also `reveal().commitment_ref`.
fn own_ref() -> OutputReference {
  OutputReference {
    transaction_id: #"0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c",
    output_index: 0,
  }
}

fn script_address() -> Address {
  Address { payment_credential: Script(policy), stake_credential: None }
}

/// Exactly one marker plus exactly the applied deposit.
fn confined_value() -> Value {
  from_lovelace(vec.commit_deposit)
    |> merge(from_asset(policy, vec.marker, 1))
}

fn commitment_output(value: Value, datum: BountyCommitment) -> Output {
  Output {
    address: script_address(),
    value,
    datum: InlineDatum(datum),
    reference_script: None,
  }
}

fn payout(pkh: ByteArray, lovelace: Int) -> Output {
  Output {
    address: from_verification_key(pkh),
    value: from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn funding(ref: OutputReference, lovelace: Int) -> Input {
  Input { output_reference: ref, output: payout(vec.payee, lovelace) }
}

// ---------------------------------------------------------------------
// Opening (T271-102)
// ---------------------------------------------------------------------

fn open_tx() -> Transaction {
  spend_context(
    [funding(seed_ref(), 20_000_000)],
    [],
    [commitment_output(confined_value(), commitment())],
    from_asset(policy, vec.marker, 1),
    [vec.payee],
    until_slot(vec.commit_upper, True),
    0,
  )
}

fn opens(tx: Transaction) -> Bool {
  bounty_commitment.bounty_commitment.mint(
    parameters(),
    Open { seed_ref: seed_ref() },
    policy,
    tx,
  )
}

test bounty_commitment_open_accepts_the_honest_opening() {
  opens(open_tx())
}

test bounty_commitment_open_requires_the_exact_seed() {
  and {
    // the declared seed is not among the inputs
    !opens(
      Transaction {
        ..open_tx(),
        inputs: [funding(other_seed_ref(), 20_000_000)],
      },
    ),
    // a different seed would derive a different marker name
    !bounty_commitment.bounty_commitment.mint(
      parameters(),
      Open { seed_ref: other_seed_ref() },
      policy,
      open_tx(),
    ),
  }
}

test bounty_commitment_open_rejects_a_datum_asserted_marker() {
  // The datum (and the mint) name a marker the seed does not derive: the
  // identity may not be asserted, only consumed into existence.
  let forged = BountyCommitmentV1 {
    ..commitment(),
    scope: BountyScope { ..scope(), marker: vec.other_marker },
    marker: vec.other_marker,
  }
  !opens(
    Transaction {
      ..open_tx(),
      outputs: [
        commitment_output(
          from_lovelace(vec.commit_deposit)
            |> merge(from_asset(policy, vec.other_marker, 1)),
          forged,
        ),
      ],
      mint: from_asset(policy, vec.other_marker, 1),
    },
  )
}

test bounty_commitment_open_confines_exactly_one_marker() {
  and {
    // a second marker minted under the same policy
    !opens(
      Transaction {
        ..open_tx(),
        mint: from_asset(policy, vec.marker, 1)
          |> merge(from_asset(policy, vec.other_marker, 1)),
      },
    ),
    // quantity two of the authentic name
    !opens(
      Transaction {
        ..open_tx(),
        mint: from_asset(policy, vec.marker, 2),
        outputs: [
          commitment_output(
            from_lovelace(vec.commit_deposit)
              |> merge(from_asset(policy, vec.marker, 2)),
            commitment(),
          ),
        ],
      },
    ),
    // the marker escapes to a second script output
    !opens(
      Transaction {
        ..open_tx(),
        mint: from_asset(policy, vec.marker, 2),
        outputs: [
          commitment_output(confined_value(), commitment()),
          commitment_output(confined_value(), commitment()),
        ],
      },
    ),
    // nothing minted at all: a look-alike output with no marker
    !opens(
      Transaction {
        ..open_tx(),
        mint: zero,
        outputs: [
          commitment_output(from_lovelace(vec.commit_deposit), commitment()),
        ],
      },
    ),
  }
}

test bounty_commitment_open_confines_exactly_the_deposit() {
  and {
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [
          commitment_output(
            from_lovelace(vec.commit_deposit - 1)
              |> merge(from_asset(policy, vec.marker, 1)),
            commitment(),
          ),
        ],
      },
    ),
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [
          commitment_output(
            from_lovelace(vec.commit_deposit + 1)
              |> merge(from_asset(policy, vec.marker, 1)),
            commitment(),
          ),
        ],
      },
    ),
    // an extra foreign asset riding along
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [
          commitment_output(
            confined_value() |> merge(from_asset(other_policy, "x", 1)),
            commitment(),
          ),
        ],
      },
    ),
  }
}

test bounty_commitment_open_requires_an_inline_datum() {
  and {
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [
          Output {
            address: script_address(),
            value: confined_value(),
            datum: DatumHash(vec.commitment_hash),
            reference_script: None,
          },
        ],
      },
    ),
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [
          Output {
            address: script_address(),
            value: confined_value(),
            datum: NoDatum,
            reference_script: None,
          },
        ],
      },
    ),
  }
}

test bounty_commitment_open_requires_the_payee_signature() {
  and {
    !opens(Transaction { ..open_tx(), extra_signatories: [] }),
    // somebody else's signature is not the payee's consent
    !opens(
      Transaction {
        ..open_tx(),
        extra_signatories: [flip_last(vec.payee), vec.recipient],
      },
    ),
    // the payee among several signers is still consent
    opens(
      Transaction { ..open_tx(), extra_signatories: [vec.recipient, vec.payee] },
    ),
  }
}

test bounty_commitment_open_stores_the_raw_upper_endpoint() {
  and {
    // an exclusive raw endpoint is stored exactly as declared
    opens(
      Transaction {
        ..open_tx(),
        validity_range: until_slot(vec.commit_upper, False),
      },
    ),
    // the stored endpoint must be the transaction's own endpoint
    !opens(
      Transaction {
        ..open_tx(),
        validity_range: until_slot(vec.commit_upper + 1, True),
      },
    ),
    // an unbounded opening has no endpoint to store
    !opens(
      Transaction {
        ..open_tx(),
        validity_range: window(NegativeInfinity, False, PositiveInfinity, False),
      },
    ),
  }
}

test bounty_commitment_open_requires_derived_timing() {
  let bad_age = BountyCommitmentV1 {
    ..commitment(),
    scope: BountyScope { ..scope(), eligible_after: vec.commit_upper },
  }
  let bad_life = BountyCommitmentV1 {
    ..commitment(),
    scope: BountyScope { ..scope(), expires_at: vec.expires_at + 1 },
  }
  and {
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [commitment_output(confined_value(), bad_age)],
      },
    ),
    !opens(
      Transaction {
        ..open_tx(),
        outputs: [commitment_output(confined_value(), bad_life)],
      },
    ),
  }
}

test bounty_commitment_open_rejects_a_foreign_network() {
  let foreign = BountyCommitmentV1 {
    ..commitment(),
    scope: BountyScope { ..scope(), network: vec.network + 1 },
  }
  !opens(
    Transaction {
      ..open_tx(),
      outputs: [commitment_output(confined_value(), foreign)],
    },
  )
}

test bounty_commitment_open_rejects_a_reference_script() {
  !opens(
    Transaction {
      ..open_tx(),
      outputs: [
        Output {
          address: script_address(),
          value: confined_value(),
          datum: InlineDatum(commitment()),
          reference_script: Some(other_policy),
        },
      ],
    },
  )
}

// ---------------------------------------------------------------------
// Reveal (T271-103)
// ---------------------------------------------------------------------

fn reveal() -> BountyRevealV1 {
  BountyRevealV1 {
    commitment_ref: own_ref(),
    nonce: vec.nonce,
    refund_index: vec.refund_index,
  }
}

fn commitment_input() -> Input {
  Input {
    output_reference: own_ref(),
    output: commitment_output(confined_value(), commitment()),
  }
}

fn reveal_tx() -> Transaction {
  spend_context(
    [commitment_input()],
    [],
    // index 0 is unrelated change; the refund must be at refund_index
    [payout(vec.recipient, 3_000_000), payout(vec.payee, vec.commit_deposit)],
    from_asset(policy, vec.marker, -1),
    [vec.payee],
    between(vec.eligible_after, True, vec.expires_at, True),
    0,
  )
}

fn reveals(tx: Transaction) -> Bool {
  bounty_commitment.bounty_commitment.spend(
    parameters(),
    None,
    Reveal(reveal()),
    own_ref(),
    tx,
  )
}

test bounty_commitment_reveal_accepts_at_both_exact_boundaries() {
  and {
    reveals(reveal_tx()),
    // the exclusive spellings of the same two instants
    reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(
          vec.commit_upper,
          False,
          vec.expires_at + 1,
          False,
        ),
      },
    ),
  }
}

test bounty_commitment_reveal_rejects_a_same_slot_interval() {
  and {
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(vec.commit_upper, True, vec.expires_at, True),
      },
    ),
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(
          vec.commit_upper - 1,
          False,
          vec.expires_at,
          True,
        ),
      },
    ),
  }
}

test bounty_commitment_reveal_rejects_after_expiry() {
  and {
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(
          vec.eligible_after,
          True,
          vec.expires_at + 1,
          True,
        ),
      },
    ),
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: from_slot(vec.eligible_after, True),
      },
    ),
  }
}

test bounty_commitment_reveal_burns_exactly_one_marker() {
  and {
    // no burn at all
    !reveals(Transaction { ..reveal_tx(), mint: zero }),
    // burning two
    !reveals(
      Transaction { ..reveal_tx(), mint: from_asset(policy, vec.marker, -2) },
    ),
    // burning one while minting another under the same policy
    !reveals(
      Transaction {
        ..reveal_tx(),
        mint: from_asset(policy, vec.marker, -1)
          |> merge(from_asset(policy, vec.other_marker, 1)),
      },
    ),
    // burning somebody else's marker
    !reveals(
      Transaction {
        ..reveal_tx(),
        mint: from_asset(policy, vec.other_marker, -1),
      },
    ),
  }
}

test bounty_commitment_reveal_retains_no_marker() {
  // The marker is nominally burned, but an output still carries one.
  !reveals(
    Transaction {
      ..reveal_tx(),
      outputs: [
        payout(vec.recipient, 3_000_000),
        payout(vec.payee, vec.commit_deposit),
        commitment_output(confined_value(), commitment()),
      ],
    },
  )
}

test bounty_commitment_reveal_refunds_the_exact_deposit_to_the_payee() {
  and {
    // wrong amount, either direction
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.recipient, 3_000_000),
          payout(vec.payee, vec.commit_deposit - 1),
        ],
      },
    ),
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.recipient, 3_000_000),
          payout(vec.payee, vec.commit_deposit + 1),
        ],
      },
    ),
    // right amount, wrong beneficiary
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.recipient, 3_000_000),
          payout(flip_last(vec.payee), vec.commit_deposit),
        ],
      },
    ),
    // an index alias: the correct payout exists, but not at refund_index
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.payee, vec.commit_deposit),
          payout(vec.recipient, 3_000_000),
        ],
      },
    ),
  }
}

test bounty_commitment_reveal_refund_carries_nothing_else() {
  and {
    // a datum on the refund
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.recipient, 3_000_000),
          Output {
            address: from_verification_key(vec.payee),
            value: from_lovelace(vec.commit_deposit),
            datum: InlineDatum(commitment()),
            reference_script: None,
          },
        ],
      },
    ),
    // an extra asset on the refund
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.recipient, 3_000_000),
          Output {
            address: from_verification_key(vec.payee),
            value: from_lovelace(vec.commit_deposit)
              |> merge(from_asset(other_policy, "x", 1)),
            datum: NoDatum,
            reference_script: None,
          },
        ],
      },
    ),
    // a script-address refund is not the committed payee
    !reveals(
      Transaction {
        ..reveal_tx(),
        outputs: [
          payout(vec.recipient, 3_000_000),
          Output {
            address: Address {
              payment_credential: Script(vec.payee),
              stake_credential: None,
            },
            value: from_lovelace(vec.commit_deposit),
            datum: NoDatum,
            reference_script: None,
          },
        ],
      },
    ),
  }
}

test bounty_commitment_reveal_requires_the_payee_signature() {
  and {
    !reveals(Transaction { ..reveal_tx(), extra_signatories: [] }),
    !reveals(Transaction { ..reveal_tx(), extra_signatories: [vec.recipient] }),
  }
}

test bounty_commitment_reveal_rejects_a_counterfeit_input() {
  and {
    // a look-alike commitment output at the script address holding no marker
    !reveals(
      Transaction {
        ..reveal_tx(),
        inputs: [
          Input {
            output_reference: own_ref(),
            output: commitment_output(
              from_lovelace(vec.commit_deposit),
              commitment(),
            ),
          },
        ],
        mint: zero,
      },
    ),
    // the right marker, the wrong deposit
    !reveals(
      Transaction {
        ..reveal_tx(),
        inputs: [
          Input {
            output_reference: own_ref(),
            output: commitment_output(
              from_lovelace(vec.commit_deposit + 1)
                |> merge(from_asset(policy, vec.marker, 1)),
              commitment(),
            ),
          },
        ],
      },
    ),
    // an unparseable datum at the script address
    !reveals(
      Transaction {
        ..reveal_tx(),
        inputs: [
          Input {
            output_reference: own_ref(),
            output: Output {
              address: script_address(),
              value: confined_value(),
              datum: InlineDatum(vec.marker),
              reference_script: None,
            },
          },
        ],
      },
    ),
  }
}

test bounty_commitment_reveal_binds_its_redeemer_to_this_input() {
  // A reveal naming a different commitment cannot spend this one.
  !bounty_commitment.bounty_commitment.spend(
    parameters(),
    None,
    Reveal(BountyRevealV1 { ..reveal(), commitment_ref: other_seed_ref() }),
    own_ref(),
    reveal_tx(),
  )
}

test bounty_commitment_reveal_requires_a_full_width_nonce() {
  !bounty_commitment.bounty_commitment.spend(
    parameters(),
    None,
    Reveal(BountyRevealV1 { ..reveal(), nonce: #"1111" }),
    own_ref(),
    reveal_tx(),
  )
}

// ---------------------------------------------------------------------
// Expired sweep (T271-103)
// ---------------------------------------------------------------------

fn sweep() -> ExpiredCommitmentSweepV1 {
  ExpiredCommitmentSweepV1 {
    recipient_pkh: vec.recipient,
    payout_index: vec.payout_index,
  }
}

fn sweep_tx() -> Transaction {
  spend_context(
    [commitment_input()],
    [],
    [payout(vec.recipient, vec.commit_deposit)],
    from_asset(policy, vec.marker, -1),
    [vec.recipient],
    between(vec.expires_at + 1, True, vec.expires_at + 2_000, True),
    0,
  )
}

fn sweeps(tx: Transaction) -> Bool {
  bounty_commitment.bounty_commitment.spend(
    parameters(),
    None,
    Sweep(sweep()),
    own_ref(),
    tx,
  )
}

test bounty_commitment_sweep_accepts_the_first_post_expiry_instant() {
  and {
    sweeps(sweep_tx()),
    // the exclusive spelling of the same instant
    sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(
          vec.expires_at,
          False,
          vec.expires_at + 2_000,
          True,
        ),
      },
    ),
  }
}

test bounty_commitment_sweep_rejects_a_premature_interval() {
  and {
    !sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(
          vec.expires_at,
          True,
          vec.expires_at + 2_000,
          True,
        ),
      },
    ),
    !sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(
          vec.expires_at - 1,
          False,
          vec.expires_at + 2_000,
          True,
        ),
      },
    ),
    // still inside the reveal window
    !sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(vec.eligible_after, True, vec.expires_at, True),
      },
    ),
  }
}

test bounty_commitment_sweep_pays_the_exact_deposit_to_the_signer() {
  and {
    !sweeps(
      Transaction {
        ..sweep_tx(),
        outputs: [payout(vec.recipient, vec.commit_deposit - 1)],
      },
    ),
    !sweeps(
      Transaction {
        ..sweep_tx(),
        outputs: [payout(flip_last(vec.recipient), vec.commit_deposit)],
      },
    ),
    !sweeps(Transaction { ..sweep_tx(), extra_signatories: [] }),
    !sweeps(Transaction { ..sweep_tx(), extra_signatories: [vec.payee] }),
  }
}

test bounty_commitment_sweep_burns_the_marker() {
  and {
    !sweeps(Transaction { ..sweep_tx(), mint: zero }),
    !sweeps(
      Transaction {
        ..sweep_tx(),
        outputs: [
          payout(vec.recipient, vec.commit_deposit),
          commitment_output(confined_value(), commitment()),
        ],
        mint: zero,
      },
    ),
  }
}

test bounty_commitment_sweep_has_no_checkpoint_effect() {
  // A sweep grants no entitlement, so it may not touch the checkpoint
  // family it was scoped to.
  !sweeps(
    Transaction {
      ..sweep_tx(),
      mint: from_asset(policy, vec.marker, -1)
        |> merge(from_asset(vec.checkpoint_policy, "checkpoint", 1)),
    },
  )
}

// ---------------------------------------------------------------------
// Empty lifecycle intervals, through the real combined handlers
//
// Submission-1 audit findings 1 and 2: an empty finite interval denotes no
// ledger instant, so comparing its bounds independently held vacuously.
// `[1002,1001]` made both shipped reveal legs true and `[11001,11000]`
// satisfied the shipped sweep leg. Each case below is the honest
// transaction of its shape with only `validity_range` changed, and each
// group carries the mandated accepted boundaries as controls so the guard
// cannot pass by rejecting everything.
// ---------------------------------------------------------------------

test bounty_commitment_reveal_rejects_empty_finite_ranges() {
  and {
    // the exact interval the audit instrument applied
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(1002, True, 1001, True),
      },
    ),
    // zero-width exclusive: earliest 5001, latest 5000
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(5000, False, 5001, False),
      },
    ),
    // the window's own endpoints, reversed
    !reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(vec.expires_at, True, vec.eligible_after, True),
      },
    ),
    // controls: both mandated spellings still accept
    reveals(reveal_tx()),
    reveals(
      Transaction {
        ..reveal_tx(),
        validity_range: between(
          vec.commit_upper,
          False,
          vec.expires_at + 1,
          False,
        ),
      },
    ),
  }
}

test bounty_commitment_sweep_rejects_empty_finite_ranges() {
  and {
    // the exact interval the audit sweep instrument applied
    !sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(vec.expires_at + 1, True, vec.expires_at, True),
      },
    ),
    // zero-width exclusive straddling expiry
    !sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(
          vec.expires_at,
          False,
          vec.expires_at + 1,
          False,
        ),
      },
    ),
    // controls: the first post-expiry instant still accepts, either spelling
    sweeps(sweep_tx()),
    sweeps(
      Transaction {
        ..sweep_tx(),
        validity_range: between(
          vec.expires_at,
          False,
          vec.expires_at + 2_000,
          True,
        ),
      },
    ),
  }
}

test bounty_commitment_open_rejects_an_empty_opening_range() {
  and {
    // a reversed opening window still names commit_upper as its raw upper,
    // so without a non-emptiness guard the opening is admitted
    !opens(
      Transaction {
        ..open_tx(),
        validity_range: between(
          vec.commit_upper + 1,
          True,
          vec.commit_upper,
          True,
        ),
      },
    ),
    !opens(
      Transaction {
        ..open_tx(),
        validity_range: between(
          vec.commit_upper - 1,
          False,
          vec.commit_upper,
          False,
        ),
      },
    ),
    // controls: the raw endpoint is still stored, inclusively or exclusively
    opens(open_tx()),
    opens(
      Transaction {
        ..open_tx(),
        validity_range: until_slot(vec.commit_upper, False),
      },
    ),
  }
}

// ---------------------------------------------------------------------
// INV-271-YAGNI-LIFETIME / INV-271-LIFETIME — the release magnitude is an
// applied deployment parameter, proved through the REAL handlers at two
// distinct valid values, with invalid magnitudes rejected by the real open
// handler. Every transaction below is the honest one of its shape with only
// the datum's derived expiry and the validity range moved, so a verdict can
// only be caused by the applied lifetime under test.
// ---------------------------------------------------------------------

/// The deployment with an arbitrary applied release lifetime.
fn parameters_with_lifetime(life: Int) -> CommitmentParameters {
  CommitmentParameters { ..parameters(), commitment_lifetime: life }
}

/// The canonical commitment whose scope expiry is derived from `life`. The
/// stored hash is reused unchanged: the lifecycle handlers constrain its
/// width and never recompute it (`INV-271-REL-HASH-OPAQUE-TO-HANDLERS`).
fn commitment_with_lifetime(life: Int) -> BountyCommitment {
  BountyCommitmentV1 {
    ..commitment(),
    scope: BountyScope { ..scope(), expires_at: vec.commit_upper + life },
  }
}

fn open_tx_with_lifetime(life: Int) -> Transaction {
  Transaction {
    ..open_tx(),
    outputs: [
      commitment_output(confined_value(), commitment_with_lifetime(life)),
    ],
  }
}

fn opens_with(params: CommitmentParameters, tx: Transaction) -> Bool {
  bounty_commitment.bounty_commitment.mint(
    params,
    Open { seed_ref: seed_ref() },
    policy,
    tx,
  )
}

fn reveal_tx_with(life: Int, range: Interval<Int>) -> Transaction {
  Transaction {
    ..reveal_tx(),
    inputs: [
      Input {
        output_reference: own_ref(),
        output: commitment_output(
          confined_value(),
          commitment_with_lifetime(life),
        ),
      },
    ],
    validity_range: range,
  }
}

fn reveals_with(params: CommitmentParameters, tx: Transaction) -> Bool {
  bounty_commitment.bounty_commitment.spend(
    params,
    None,
    Reveal(reveal()),
    own_ref(),
    tx,
  )
}

fn sweep_tx_with(life: Int, range: Interval<Int>) -> Transaction {
  Transaction {
    ..sweep_tx(),
    inputs: [
      Input {
        output_reference: own_ref(),
        output: commitment_output(
          confined_value(),
          commitment_with_lifetime(life),
        ),
      },
    ],
    validity_range: range,
  }
}

fn sweeps_with(params: CommitmentParameters, tx: Transaction) -> Bool {
  bounty_commitment.bounty_commitment.spend(
    params,
    None,
    Sweep(sweep()),
    own_ref(),
    tx,
  )
}

test bounty_commitment_open_accepts_a_parameterized_lifetime() {
  and {
    opens_with(parameters(), open_tx_with_lifetime(example_lifetime())),
    opens_with(alt_parameters(), open_tx_with_lifetime(alt_lifetime())),
    // neither example's opening is admissible under the other's parameters:
    // the stored expiry must be derived from the lifetime actually applied
    !opens_with(alt_parameters(), open_tx_with_lifetime(example_lifetime())),
    !opens_with(parameters(), open_tx_with_lifetime(alt_lifetime())),
    // the shortest admissible release opens: one mature reveal slot exists
    opens_with(
      parameters_with_lifetime(vec.commit_min_age),
      open_tx_with_lifetime(vec.commit_min_age),
    ),
  }
}

test bounty_commitment_open_rejects_invalid_lifetime_parameters() {
  // Each datum is made self-consistent with the invalid magnitude it is
  // opened under, so the rejection can only come from the parameter rule
  // itself and never from a scope-derivation mismatch.
  and {
    !opens_with(parameters_with_lifetime(0), open_tx_with_lifetime(0)),
    !opens_with(parameters_with_lifetime(-1), open_tx_with_lifetime(-1)),
    // an expiry before the opening endpoint is unreachable in either
    // direction, and is refused for being an invalid release, not by luck
    !opens_with(
      parameters_with_lifetime(0 - example_lifetime()),
      open_tx_with_lifetime(0 - example_lifetime()),
    ),
  }
}

test bounty_commitment_reveal_final_boundary_follows_the_lifetime() {
  and {
    // each release accepts exactly its own final reveal slot
    reveals_with(
      parameters(),
      reveal_tx_with(
        example_lifetime(),
        between(vec.eligible_after, True, vec.expires_at, True),
      ),
    ),
    reveals_with(
      alt_parameters(),
      reveal_tx_with(
        alt_lifetime(),
        between(vec.eligible_after, True, alt_expires_at(), True),
      ),
    ),
    // one slot past its own expiry rejects, at both examples
    !reveals_with(
      parameters(),
      reveal_tx_with(
        example_lifetime(),
        between(vec.eligible_after, True, vec.expires_at + 1, True),
      ),
    ),
    !reveals_with(
      alt_parameters(),
      reveal_tx_with(
        alt_lifetime(),
        between(vec.eligible_after, True, alt_expires_at() + 1, True),
      ),
    ),
    // the longer example's window is long past expiry for the shorter
    // release: the boundary moved with the parameter, not with the protocol
    !reveals_with(
      alt_parameters(),
      reveal_tx_with(
        alt_lifetime(),
        between(vec.eligible_after, True, vec.expires_at, True),
      ),
    ),
    // exact one-slot maturity is unchanged by the release choice
    !reveals_with(
      alt_parameters(),
      reveal_tx_with(
        alt_lifetime(),
        between(vec.commit_upper, True, alt_expires_at(), True),
      ),
    ),
    // and an empty window stays empty whatever the release choice
    !reveals_with(
      alt_parameters(),
      reveal_tx_with(
        alt_lifetime(),
        between(alt_expires_at(), True, vec.eligible_after, True),
      ),
    ),
  }
}

test bounty_commitment_sweep_boundary_follows_the_lifetime() {
  and {
    // the first instant strictly after each release's own expiry sweeps
    sweeps_with(
      alt_parameters(),
      sweep_tx_with(
        alt_lifetime(),
        between(alt_expires_at() + 1, True, alt_expires_at() + 2_000, True),
      ),
    ),
    sweeps_with(
      alt_parameters(),
      sweep_tx_with(
        alt_lifetime(),
        between(alt_expires_at(), False, alt_expires_at() + 2_000, True),
      ),
    ),
    // at its own expiry is still premature
    !sweeps_with(
      alt_parameters(),
      sweep_tx_with(
        alt_lifetime(),
        between(alt_expires_at(), True, alt_expires_at() + 2_000, True),
      ),
    ),
    // the very same window is premature under the longer release, and the
    // longer release's own first post-expiry instant still sweeps
    !sweeps_with(
      parameters(),
      sweep_tx_with(
        example_lifetime(),
        between(alt_expires_at() + 1, True, alt_expires_at() + 2_000, True),
      ),
    ),
    sweeps_with(
      parameters(),
      sweep_tx_with(
        example_lifetime(),
        between(vec.expires_at + 1, True, vec.expires_at + 2_000, True),
      ),
    ),
  }
}

// ---------------------------------------------------------------------
// Policy branch separation
// ---------------------------------------------------------------------

test bounty_commitment_retire_is_burn_only() {
  and {
    bounty_commitment.bounty_commitment.mint(
      parameters(),
      Retire,
      policy,
      Transaction { ..reveal_tx(), mint: from_asset(policy, vec.marker, -1) },
    ),
    // Retire cannot be used to mint
    !bounty_commitment.bounty_commitment.mint(
      parameters(),
      Retire,
      policy,
      open_tx(),
    ),
    // Open cannot be used to burn
    !opens(
      Transaction { ..open_tx(), mint: from_asset(policy, vec.marker, -1) },
    ),
  }
}
