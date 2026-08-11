# Data model — #232 bounded phase-2 collateral loss

Artifact ceiling: 5,000 bytes and 130 lines.

## New data

### DAT-232-COLLATERAL-CONTRACT — `CollateralContract`

Fields:

- `collateralInput`: the one resolved plain ADA-only collateral `TxIn` and
  Conway `TxOut` selected from the atomic funding snapshot;
- `collateralReturnAddress`: the operation's funding `Addr`.

The product maximum is not caller-configurable: it is fixed at
**5,000,000 lovelace** by the shared runtime.

### DAT-232-COLLATERAL-FAILURE — `CollateralSafetyError`

Named failure cases distinguish:

- protocol-required total above the product maximum;
- collateral value too small for exact total plus a valid return;
- missing or unexpected collateral input set;
- missing or mismatched declared total;
- missing, misaddressed, non-ADA-only, or value-mismatched return output;
- violation of total-plus-return conservation.

Each quantitative case carries required, available, declared, or maximum
lovelace as applicable.

## Reused data

### DAT-232-PROTOCOL — Conway `PParams`

The same immutable snapshot already used for fee convergence supplies the
collateral percentage and min-UTxO calculation.

### DAT-232-FINAL-BODY — converged `ConwayTx`

The post-balance body exposes final fee, collateral inputs, total collateral,
and collateral return. Only a body satisfying the contract may reach signing.

## State invariants

- **DATA-INV-232-01:** accepted total collateral equals the ceiling of final fee
  multiplied by the snapshot collateral percentage and divided by 100.
- **DATA-INV-232-02:** accepted total collateral is at most
  5,000,000 lovelace.
- **DATA-INV-232-03:** exactly the resolved contract input appears as
  collateral and never as a regular spending input.
- **DATA-INV-232-04:** one present ADA-only return output pays the contract's
  funding address and is min-UTxO-valid.
- **DATA-INV-232-05:** total collateral plus return lovelace equals the resolved
  collateral input lovelace.
- **DATA-INV-232-06:** a script-free transaction carries no collateral contract
  and retains absent total/return fields.
