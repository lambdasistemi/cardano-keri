# R1 — event-derived MPF key

Milestone M1.2 requirement R1. Semantic authority is A-019 §2, SHA-256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf`.
The frozen acceptance gate is `r1-event-key-v2`, SHA-256
`e22c0811fed611ad7aa1eeca07de71299b4dccaf370b9375e65768135177ecd1`.

## Outcome

An authenticated event occupies the MPF slot derived only from its verified
KERI identity `(i, s, p, d)`. A submitter supplies only the MPF sibling proof
and cannot select the key, location, prior snapshot, settlement order, or any
event identity component.

The V1 key is `blake2b_256` over canonical Plutus data with this exact shape:

`Constr 0 [B "cardano-keri/event-key/v1", B i, I s, option-p, B d]`

`option-p` is `Constr 0 []` for `icp`/`dip`, and `Constr 1 [B p]` otherwise.
The values `i`, `p`, and `d` retain canonical qualified CESR bytes; `s` is the
integer decoded from canonical lowercase hexadecimal event text.

## Requirements

- **R1-R01** Derive the key only from the verified event body using the exact
  V1 domain, field order, constructors, encoding, and digest above.
- **R1-R02** Reject unknown or non-canonical qualification, non-canonical
  sequence text, and an absent/present prior inconsistent with event type.
- **R1-R03** `HistoricalProof` contains only the MPF sibling proof. Remove its
  `key`, `location`, and `prior_snapshot_digest` fields and every consumption.
- **R1-R04** Insert the verified SAID at the derived key; never pass a
  submitter-selected key to the MPF operation.
- **R1-R05** Pin independent golden values for both prior constructors and
  every supported CESR derivation code. A newly supported code makes the proof
  incomplete until a vector is added.
- **R1-R06** Two valid rival SAIDs at one `(i, s, p)` coexist and remain
  independently retrievable.
- **R1-R07** Preserve the six frozen hardening controls: clean-tree refusal;
  exact candidate receipts; measured-source closure from a committed recipe;
  changed non-onchain flake-input classification; per-leg token/capacity
  accounting; and exact base CI-surface mirroring with named residual jobs.
- **R1-R08** No semantic choice outside A-019 §2 is made in this slice.

## Invariants

| ID | Severity | Success meaning | Failure meaning |
|---|---|---|---|
| R1-I01 | BLOCKING | MPF key is a pure function of verified `i/s/p/d` | any caller or redeemer value changes the key |
| R1-I02 | BLOCKING | domain and five-field Plutus shape are exact | domain, tag, field, order, encoding, or digest differs |
| R1-I03 | BLOCKING | canonical hex `s` becomes its integer value | length, text bytes, non-canonical spelling, or redeemer integer is used |
| R1-I04 | BLOCKING | prior absence and presence have distinct exact constructors | the tags collapse or mismatch event type |
| R1-I05 | BLOCKING | qualified `i/p/d` retain supported CESR codes and canonical spelling | qualification is stripped, unknown, or non-canonical |
| R1-I06 | BLOCKING | `HistoricalProof` has only `proof` and no removed field is consumed | `key`, `location`, or `prior_snapshot_digest` survives |
| R1-I07 | BLOCKING | record insertion receives `parsed.event_key`, verified SAID, and sibling proof | submitter-selected key reaches insertion |
| R1-I08 | BLOCKING | rival SAIDs at one location coexist and remain retrievable | one rival overwrites or aliases the other |
| R1-I09 | BLOCKING | supported CESR code set and independent golden rows are in bijection | a supported code has no accepted vector |
| R1-I10 | BLOCKING | every frozen mutation class reddens for its named cause | any `i/s/p-tag/p/d/domain/order/submitter-key` mutant survives |
| R1-I11 | ADVISORY | candidate source and build surfaces are reproducibly bound and measured | recipe, source manifest, flake declaration, receipt, or CI mirror drifts |
| R1-I12 | BLOCKING | no out-of-authority semantic decision enters product code | implementation invents policy outside A-019 §2 |

## Observable acceptance

The exact frozen v2 gate must accept the committed candidate, and a fresh
Codex-family auditor must report every blocking invariant satisfied. The gate
must remain independently falsifiable by its sealed controls. Full realization
and CI are acceptance requirements but may run only after their separate
capacity and runner authorizations.

## Out of scope

R2 event leaves and key-state snapshots, R3 whole-record cursor semantics, R4
`keripy` parity/abstention, and any arrival-order or settlement-order policy.
