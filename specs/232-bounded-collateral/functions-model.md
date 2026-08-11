# Functions model — #232 bounded phase-2 collateral loss

Artifact ceiling: 5,000 bytes and 130 lines.

Only changed public signatures are modeled. Module ownership is in
`modules-model.md`; data and invariants are in `data-model.md`.

## Collateral policy

- **FUN-232-VALIDATE:** `validateCollateralSafety protocolParameters collateralContract transaction -> Either CollateralSafetyError transaction`

Constraints:

- the result is accepted only for the exact protocol-relative total and an
  absolute maximum of 5,000,000 lovelace;
- the return address/value and total-plus-return conservation are checked from
  final body fields and the resolved input, not from caller claims;
- every rejection is typed and occurs before signing.

## Plutus build kernel

- **FUN-232-PLUTUS-BUILD:** `runPlutusTransactionBuild runtime interpreter spendingInputs referenceInputs changeAddress collateralContract program -> IO (Either TransactionBuildError transactionId)`

Constraints:

- the kernel owns collateral resolution options and the explicit return-address
  instruction;
- it invokes **FUN-232-VALIDATE** after convergence and before signing;
- collateral safety rejection is preserved as a named
  `TransactionBuildError` case;
- the existing script-free build entry point remains available to Publisher.

## Operation call sites

- **FUN-232-REGISTRATION:** registration premint/register supply the shared
  funding pair's collateral input and `registerFundingAddress`.
- **FUN-232-ADVANCE:** advance supplies the shared funding pair's collateral
  input and `advanceFundingAddress`.
- **FUN-232-CLOSE:** close supplies the shared funding pair's collateral input
  and `closeFundingAddress`, independently of `closeChangeAddress`.
- **FUN-232-BOARD:** board post/update/retire supply the shared funding pair's
  collateral input and `boardFundingAddress`, independently of
  `boardChangeAddress`.

Signature spellings may use existing domain names; the explicit arguments,
effects, ordering, and safety relationships above are fixed.
