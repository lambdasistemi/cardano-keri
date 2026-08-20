# Functions model — S2 witness-mode

New and changed signatures only: names, explicit argument names, types, signature-level
constraints. No bodies, algorithms, control flow or helpers.

## `Cardano.KERI.Deployment.M12TxB`

The surface the slice must expose. Concrete type spellings are the commit owner's, provided they
satisfy the constraints stated here.

| function | shape | constraint |
|---|---|---|
| `buildTxBWithMode` | `mode -> pparams -> plan -> Either buildError tx` | the **only** construction entry point; `mode` selects REFERENCE or INLINE over the same `plan` |
| `buildTxB` | `pparams -> plan -> Either buildError tx` | the production selection, defined in terms of `buildTxBWithMode`; it may not construct independently |
| `txBWitnessMode` | `mode` | the production carriage constant, so the selection is a value the suite can assert on rather than a comment |
| `inspectTxB` | `pparams -> tx -> fit` | reports serialized size against the transaction-size limit; used by the INLINE control |
| `txBReferenceScriptFee` | `pparams -> refScriptBytes -> fee` | derives the tiered fee from the pinned parameters; must be total over the probe set |
| `txBCreationEnvelope` | `pparams -> signingContext -> script -> Either buildError envelopeRow` | builds and measures the **signed** reference-script creation transaction for one program; returns `program_bytes`, `creation_tx_bytes`, `signed`, and the derived verdict |
| `txBManifest` | `pparams -> plan -> tx -> manifest` | assembles the manifest value; carries provenance, residuals and the archived-RED Surface-B object |

Signature-level constraints that are contract, not preference:

- every fallible path returns `Either buildError`; no partial function, no `error`, no silent
  default. Fail-closed is the inherited posture and this slice does not relax it.
- `buildTxBWithMode` is total in `mode`: adding a carriage variant must not typecheck without
  handling it.
- `txBCreationEnvelope` takes the signing context explicitly. An envelope measured without
  witnesses is not an envelope, and the type is where that is enforced rather than remembered.
- nothing in this module takes a Surface-B SHA, a `surface_b_sha`, or any argument that would let
  a caller supply one.

## `…Deployment.TransactionRuntime.Fixtures` — changed

`testPParams` gains the pinned reference-script fee parameter. Signature unchanged; it stays a
shared value, and every existing reader must remain green.

## Removed from the seed

`validSurfaceSha` and any Surface-B SHA field, argument or validation. There is no accepted
Surface-B SHA and there never will be one in this campaign, so the shape must not exist to be
filled in later.
