# Data model

## Retirement ledger

`lean/traceability.csv` has one header and exactly 21 data rows:

- `lean_theorem`: the unique theorem identifier formerly declared by
  `CardanoKeri/Goals.lean`;
- `disposition`: exactly `RETIRED`;
- `owner_decision`: exactly the binding #366 epic-ruling URL.

The theorem denominator is the frozen historical source at the ticket base
`9b2e6b88937707cc2c571ae1e9e5f112dc248a30`. The executable driver derives
that source-order inventory from Git and compares it one-to-one with the CSV;
it does not trust a handwritten count alone.

## Proof inventory

The proof-trust probe discovers every top-level theorem declaration in
`CheckpointGoals.lean`, `RegistryGoals.lean`, `Cage.lean`, and
`Samaritan.lean`, generates one `#print axioms` command per theorem, and fails
closed on an empty/truncated inventory, `sorryAx`, or an axiom outside the
approved current set (`propext`, `Quot.sound`, or no axioms).

