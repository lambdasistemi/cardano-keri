//// #271 S271-1 — the combined bounty-commitment minting policy and
//// spending validator (`MOD-271-COMMITMENT`).
////
//// One applied script hash serves as both the commitment marker's policy id
//// and the commitment output's payment credential, which is what lets the
//// spending side authenticate its own policy without the circular parameter
//// an embedded self-hash would require. The mint side learns its policy from
//// the ledger argument; the spend side derives it from the credential of the
//// input it is spending.
////
//// The program is deliberately family-independent: nothing here reads a
//// checkpoint datum, evaluates KERI evidence, or claims any checkpoint is
//// protected. #254 S254-E adopts the component and owns that coupling.

use aiken/collection/dict
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{OutputReference, Transaction}
use cardano_keri/bounty_commitment.{
  BountyMint, BountySpend, CommitmentParameters, Open, Retire, Reveal, Sweep,
  all_burns, inline_commitment, script_outputs, validate_commitment_open,
  validate_commitment_reveal, validate_commitment_sweep,
} as protocol

validator bounty_commitment(parameters: CommitmentParameters) {
  mint(redeemer: BountyMint, policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      // Opening: the unique script output names the commitment being
      // created; every load-bearing check lives in the shared predicate.
      Open { seed_ref } ->
        when script_outputs(tx, policy_id) is {
          [out] ->
            when inline_commitment(out.datum) is {
              Some(datum) ->
                validate_commitment_open(
                  parameters,
                  seed_ref,
                  datum,
                  policy_id,
                  tx,
                )
              None -> False
            }
          _ -> False
        }

      // Retiring a marker is always permitted: a marker only ever lives in
      // a commitment output, so destroying it necessarily spends that
      // output and runs the spend handler, which owns the burn shape.
      Retire -> all_burns(dict.to_pairs(tokens(tx.mint, policy_id)))
    }
  }

  spend(
    _datum: Option<Data>,
    redeemer: BountySpend,
    own_ref: OutputReference,
    tx: Transaction,
  ) {
    // The datum is re-read from the spent input rather than trusted from
    // the ledger argument, because the same read also proves the input
    // actually holds its own seed-derived marker and deposit.
    when redeemer is {
      Reveal(reveal) ->
        validate_commitment_reveal(parameters, reveal, own_ref, tx)
      Sweep(sweep) -> validate_commitment_sweep(parameters, sweep, own_ref, tx)
    }
  }

  else(_) {
    fail
  }
}
