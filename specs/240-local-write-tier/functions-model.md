# Functions model — #240 local-only write tier

Artifact ceiling: 6,000 bytes and 150 lines.

Only new or changed public signatures are modeled. Types are in
`data-model.md`; ownership is in `modules-model.md`.

## MOD-240-LOCAL

### withLocalQueryScope

- **Requirement / slice:** RQ-240-03/04/07, S240-1.
- **Signature:** `withLocalQueryScope settings action -> IO result`
- **Arguments:** `settings : LocalSettings`; `action : forall cf op. LocalQueryScope cf op -> IO result`.
- **Result:** `IO result`.
- **Constraints/effects:** brackets one store runner; scope cannot escape; no
  provider fallback.

### runLocalChainQuery

- **Requirement / slice:** RQ-240-03/04, S240-1.
- **Signature:** `runLocalChainQuery scope program -> IO (Either ChainQueryError (QuerySnapshot result))`
- **Arguments:** `scope : LocalQueryScope cf op`; `program : ChainQuery result`.
- **Result:** local atomic query snapshot.
- **Constraints/effects:** exactly one transaction-runner invocation for the
  whole program and watermark.

### localReferenceScriptsTx

- **Requirement / slice:** RQ-240-05, S240-1.
- **Signature:** `localReferenceScriptsTx scriptHashes -> Transaction effect columns operations (Either ChainQueryError [ChainReference])`
- **Arguments:** `scriptHashes : [Text]`.
- **Result:** exact ordered reference rows or named failure.
- **Constraints/effects:** derives only from live stored outputs; validates
  exact cardinality and script hash; no HTTP/node effect.

### localSettlementObserver

- **Requirement / slice:** RQ-240-06, S240-1.
- **Signature:** `localSettlementObserver scope -> SettlementObserver IO`
- **Arguments:** `scope : LocalQueryScope cf op`.
- **Result:** follower-backed asset observer.
- **Constraints/effects:** fresh temporal store observation per probe; no
  snapshot claim.

### localReferenceObservation

- **Requirement / slice:** RQ-240-05/06, S240-1.
- **Signature:** `localReferenceObservation scope scriptHash -> IO (Either ChainQueryError [ChainReference])`
- **Arguments:** `scope : LocalQueryScope cf op`; `scriptHash : Text`.
- **Result:** current exact local reference result.
- **Constraints/effects:** uses the same derived reference semantics as the
  snapshot operation.

### localTransactionSettled

- **Requirement / slice:** RQ-240-06, S240-1.
- **Signature:** `localTransactionSettled scope transactionId -> IO Bool`
- **Arguments:** `scope : LocalQueryScope cf op`; `transactionId : TxId`.
- **Result:** whether the follower currently tracks an output of that exact
  transaction.
- **Constraints/effects:** temporal observation, fail closed at caller boundary,
  never a `ChainQueryF` operation.

## MOD-240-WRITE-COMPOSITION

### writeSettingsParser changes

- **Requirement / slice:** RQ-240-07, S240-1.
- **Signature:** existing deploy/register/advance/close/board parser signatures
  return their existing settings types with `LocalSettings`, not provider
  fields.
- **Arguments:** opt-env-conf option/environment/YAML sources.
- **Result:** provider-unrepresentable write settings.
- **Constraints/effects:** preserve precedence and existing non-provider
  command behavior.

### write runners

- **Requirement / slice:** RQ-240-01/03/04/06, S240-1.
- **Signature:** existing `runDeploy`, `runRegister`, `runAdvance`, `runClose`,
  and `runBoard` public signatures remain `settings -> IO ()`.
- **Arguments:** corresponding local-only write settings.
- **Result:** existing command output or closed failure.
- **Constraints/effects:** open one local scope, compose a complete snapshot
  before each transaction build, then use local temporal settlement; no
  provider dependency/callback.

## MOD-240-DEPLOYMENT

No builder gains a query function. Existing builder signatures remain based on
resolved `TxIn`/`TxOut`, checkpoint, board, and reference values. Any changed
settlement argument is typed as a temporal capability and cannot be used during
transaction construction.

## MOD-240-FOCUSED-GATE

### local-write-path-check

- **Requirement / slice:** RQ-240-09/10/11, S240-1.
- **Signature:** repository check application with no user arguments.
- **Arguments:** candidate source and compiled focused test executables.
- **Result:** exit zero only with non-zero complete invariant coverage.
- **Constraints/effects:** invoked by `just local-write-path-check` and
  `ci-offchain`; every Nix evaluation passes `--no-write-lock-file`.
