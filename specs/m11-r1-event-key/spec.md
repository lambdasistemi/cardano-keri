# R1 — event-derived MPF key

Milestone M1.2 requirement R1. Semantic authority is A-019 §2, SHA-256
`5ac7e868641217f50e3989c4a5b8057a9b7fc4a92f257d0d2c173a56fd5a0cbf`.
The original acceptance gate is `r1-event-key-v2`, SHA-256
`e22c0811fed611ad7aa1eeca07de71299b4dccaf370b9375e65768135177ecd1`.
After submission-1 audit findings F1--F3 were accepted by A-007, R1 expands
to the existing trusted-policy and staging boundary. The post-change gate is
`r1-event-key-v4`; v2/v3 remain immutable evidence for the rejected world.

## Re-cut campaign binding

The R1 re-cut mandate, SHA-256
`d8eab8949b0ef3a5d0a32f78f4566f6109b7157d7e9866f93d94d7c34fe5fc20`,
continues forward from published candidate
`8aa1de397d044ec40b62ecf16adf51eaa0795288`. Semantic acceptance covers the
complete `84e3b715..candidate` delta; no prior unjudged GREEN is acceptance
credit. R1-I02--I06 and R1-I10 retain their KILLED evidence. All other rows
remain unresolved, and F1--F3 remain open until this campaign receives a
terminal semantic audit.

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
- **R1-R09** The proof-token policy accepted by `s0_append` is fixed in the
  applied validator, outside redeemer/caller authority, matching the deployed
  `checkpoint_observer` precedent.
- **R1-R10** Demonstrate two present-prior rival events through raw decoding,
  staging verification, token provenance, record binding, and append; staging
  treats the qualified `i` and recomputed qualified `d` as distinct fields.
- **R1-R11** Derive supported-code coverage only from the committed accepted
  vector manifest. A future supported code plus a dead matching source string
  remains incomplete and must make the gate RED.
- **R1-R12** Re-measure the compiled `s0_append.s0_append.spend` member after
  parameterization and update S0's size report with the new measured source
  identity and the continuing `size-only; transaction-fit unproven` caveat.
- **R1-R13** The rival-event proof independently stages and invokes the
  validator for each event, never substitutes a lower append helper, retrieves
  both resulting MPF entries independently, and changes enough of the dressed
  source that the second preimage is genuinely rival rather than `d`-only.
- **R1-R14** Every campaign instrument used as evidence demonstrates before
  semantic use that both its normal cleanup and a seeded cleanup/exit failure
  are observable. A teardown failure invalidates the instrument verdict.

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
| R1-I13 | BLOCKING | `s0_append` consumes one deployment-fixed trusted staging policy | a redeemer/caller selects the policy whose burn authenticates the event |
| R1-I14 | BLOCKING | each of two ordinary present-prior rivals independently crosses staging and the validator append boundary, both entries are independently retrieved, and their dressed preimages are genuinely rival | event two bypasses staging or validator append, uses a lower append helper, lacks its own retrieval, or changes only `d` in an otherwise shared dressed source |
| R1-I15 | BLOCKING | supported-code coverage is in bijection with accepted rows in the committed vector manifest | arbitrary source text or a dead list can satisfy coverage |
| R1-I16 | BLOCKING | the affected S0 append size row is freshly measured from the accepted parameterized source and discloses its caveat | the pre-parameterization 8,471-byte row is retained or presented as current |

## Observable acceptance

The inherited frozen v6 gate and the re-cut wrapper must accept the committed
candidate, and a fresh Codex auditor must semantically report the full
`84e3b715..candidate` delta with every blocking invariant terminally satisfied.
The gate and every auxiliary instrument must remain independently falsifiable,
including cleanup/exit behavior. Full realization and CI are acceptance
requirements but may run only after their separate capacity and runner
authorizations.

A-008 binds one known limit: v4's free F2 boundary-name scan is a placeholder,
not proof that the path executes. R1-I14 remains unverified, and R1 cannot be
accepted, until the exact candidate completes the authorized v4 `--full`
mutation and Aiken-check legs. Free plus selftest evidence cannot satisfy I14.

## Out of scope

R2 event leaves and key-state snapshots, R3 whole-record cursor semantics, R4
`keripy` parity/abstention, and any arrival-order or settlement-order policy.
