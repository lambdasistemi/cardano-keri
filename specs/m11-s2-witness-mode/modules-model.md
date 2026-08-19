# Modules model — S2 witness-mode

Responsibility, dependency direction and placement only. No imports, bodies, algorithms or tests.

## New / changed components

### `Cardano.KERI.Deployment.M12TxB` — new, `offchain/deployment`

Owns the semantic M12 TxB plan, explicit witness carriage, fail-closed validation of the plan's
scripts and reference set, the reference-script fee derivation, the per-program signed
creation-transaction envelope measurement, and the provenance manifest value.

Pure. It constructs and inspects transactions against supplied protocol parameters and returns
data; it opens no socket, reads no environment, and holds no CLI or live-provider edge. That is
what lets the whole determination be a unit-testable claim rather than a deployment story.

Dependency direction: depends on the ledger API and on the existing
`Cardano.KERI.Deployment.Script` for script construction and hashing. Nothing in `deployment`
depends on it yet; the report and manifest are its only consumers in this slice.

**Both carriage branches live behind one plan type.** REFERENCE and INLINE are two renderings of
the *same* semantic plan, selected by an explicit mode argument — not two builders that could
drift apart. A second builder would make the INLINE control a claim about different code, which is
precisely the thing this slice exists to avoid.

### `Cardano.KERI.Deployment.M12TxBSpec` — new, `offchain/deployment-test`

Owns the focused suite `M11.S2.TxB.witness.mode`, including the two contract-named examples
`witness-mode/REFERENCE` and `witness-mode/INLINE`. Registered in the deployment-test `Main`.

### `…Deployment.TransactionRuntime.Fixtures` — changed, shared

`testPParams` gains the pinned reference-script fee parameter. **This is a shared record, not a
private fixture**: the change must be made against its then-current shape, and any other suite
reading `testPParams` must stay green. Promotion is correct here — the pinned parameter is a
property of the test ledger, not of this slice.

### `offchain/cardano-keri.cabal` — changed

Exposes the new module and its test module and declares whatever ledger dependency they add.

## Artifacts, owned by this slice

- `specs/m11-s2-witness-mode/txb-manifest.json` — the machine-checked provenance record; schema in
  `data-model.md`.
- `specs/m11-s2-witness-mode/WITNESS-MODE-REPORT.md` — the human-readable determination, its
  caveats and its residuals.

## Placement rules

- No production module outside `offchain/deployment` changes behavior in this slice.
- Nothing on-chain changes. `onchain/` and `scripts/s0/` arrive with the S0 integration and are
  read-only here — `scripts/s0/measure-family.sh` in particular is the digest control's source and
  must not be edited to satisfy it.
- No CLI surface, no new executable, no live-provider wiring.
