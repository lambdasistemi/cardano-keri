# S2 witness-mode determination — the no-B recut

Milestone M1.2, slice `s2w-witness-mode`. Authority: A-018 (final)
`1c9788a6a517b224698f2170e0757b2b8e8a8a2b744e87e81e78d89e93ddfd1b`, corrected by A-018-REV1
`ecc8be8152ad12dfad2de344590523ee1071ff8af3332f68fb937e0cd4e16abd`.

## The question this slice answers

Which limit actually governs the M12 family's central transaction, and does the family's TxB carry
its scripts as **reference inputs** or **inline witnesses**? The established pattern in shipped
code is reference carriage, but that is a strong prior about the *existing* path, not proof about
this family. A prior that is never tested is an assumption wearing evidence's clothes, so the
INLINE branch is built, kept and executed rather than argued away.

Two limits are routinely conflated and must not be:

- the **ledger aggregate** `maxRefScriptSizePerTx`, which bounds the reference-script bytes a
  *consuming* transaction may pull in;
- the **per-program envelope**: the signed transaction that *creates* one program's reference-script
  UTxO must itself fit the maximum transaction size.

A family can sit comfortably under the first and be undeployable under the second. Surface B's
cluster-8 live rejection (`18,732 > 16,133`) was an envelope failure, on rejected ancestry, and is
not evidence about this one.

## Scope

In: the off-chain TxB construction, both witness branches, the pinned-limit citation, the fee-tier
probe, the envelope-versus-aggregate measurement, and the report/manifest that carry the result.

Out, and not to be absorbed: the four DESIGN-NOTE-001 requirements (bytes-derived MPF key,
sufficient leaf snapshot, whole-record cursor, cursor-vs-`keripy` parity plus abstention). They are
later, separately gated slices. Also out: any Surface-C mutation, any push/PR/merge.

## Requirements

- **S2W-R1** A production TxB builder exists off-chain, selecting one witness carriage explicitly.
- **S2W-R2** The INLINE branch is a live executable path over the *same* semantic plan, not a dead
  constructor, and its serialized transaction size is measured.
- **S2W-R3** Both branches execute in the focused suite under the names `witness-mode/REFERENCE`
  and `witness-mode/INLINE`.
- **S2W-R4** Every ledger quantity is cited with pin provenance: package, package tarball digest,
  and the snapshot/genesis it was read from.
- **S2W-R5** The reference-script fee is probed at 25,599 / 25,600 / 25,601 / 25,617 / 26,448 and
  the tier boundary is *revealed* by the probe rather than straddled.
- **S2W-R6** The per-program signed creation-transaction envelope is measured per program and
  reported separately from the aggregate limit; the two never share a name or a value, and the
  envelope limit carries its own provenance.
- **S2W-R7** Surface B appears only as `status=ARCHIVED_RED` plus its evidence hash.
- **S2W-R8** The S0 binary-content digest control is carried and agrees with the candidate's own
  `scripts/s0/measure-family.sh`.
- **S2W-R9** Residuals `A3-F1` (advisory) and `F1-ERROR-CLASSIFICATION` (OPEN) are labeled in both
  manifest and report wherever decoder-dependent evidence is discussed.
- **S2W-R10** No number is inherited. Every measured quantity is regenerated on this ancestry.

## Invariants

| id | truth that must hold | how it fails |
|---|---|---|
| S2W-I1 | the witness-mode verdict is produced by executing both branches | either named example absent from the focused log |
| S2W-I2 | INLINE is preserved, executed, and measured | `inline_control` claims execution the log does not show, or reports no size |
| S2W-I3 | pinned quantities carry provenance | package, tarball digest or snapshot missing/empty |
| S2W-I4 | the fee table is producible by the pinned parameters | any probe disagreeing with an independent tier derivation |
| S2W-I5 | envelope and aggregate are distinct limits | same name or same value; a verdict contradicting its own measurement |
| S2W-I6 | the aggregate is derived, never asserted | `aggregate.ref_script_bytes` ≠ Σ `scripts[].bytes` |
| S2W-I7 | no Surface-B SHA exists in any form | a `surface_b_sha` key, that string in the report, or any 40-hex id in the `surface_b` subtree |
| S2W-I8 | the S0 digest control agrees three ways | source line 9, manifest `aiken_digest`, bound constant disagreeing |
| S2W-I9 | open residuals stay visible | A3-F1 or the F1 residual missing, or F1 marked anything but OPEN |
| S2W-I10 | both bound commits are ancestors and then-current `origin/main` is integrated | either ancestry check failing, or `origin/main` drift at final |

Enforcement: `s2w-no-b-v1.2`, frozen, sha256
`2317cddbdf24cbaf1c712da877ffc131bef3e13e7044e97587be8c79fe467b66`. `S2W-I3` is enforced by the
gate for both `.protocol` and the candidate-declared envelope limit.

## Observable success

`s2w-no-b-v1.2 --full` exits 0 on a candidate whose ancestry carries both bound commits and
then-current `origin/main`, with the focused suite green, both named examples present, and full CI
green — followed by a fresh independent audit and milestone acceptance.

## Explicit non-claims

Transaction-fit remains `size-only; transaction-fit unproven` except where this slice measures a
signed creation transaction and says so. The pair-token co-residency that forces append and cursor
together is a skeleton artifact, not a released invariant: this slice measures its cost and
neither ratifies nor redesigns it.
