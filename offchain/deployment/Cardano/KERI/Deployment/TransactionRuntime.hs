{- |
Module      : Cardano.KERI.Deployment.TransactionRuntime
Description : Indexer-neutral in-process transaction runtime capability
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

#181 Slice 1: an indexer-neutral capability binding protocol-parameter
query, script evaluation, signing, pure transaction-id derivation, local
submission, and settlement observation to one caller-supplied transaction
evolution. This module owns only the call order and fail-closed control
flow (FR-3/FR-4/FR-5 and the load-bearing invariants in the \#181 in-process
transaction-path spec); it does not know how the indexer
follower or node connection are stored — the higher \#177 composition layer
supplies real 'queryProtocolParamsH', 'evaluateTxH', and 'submitTx'-backed
implementations plus the concrete draft builder.

'runTransactionOperationGeneric' is deliberately generic over the raw
per-purpose evaluation map's key\/failure types so it can be exercised with
lightweight stand-ins in tests without constructing internal ledger
'Cardano.Ledger.Alonzo.Plutus.Evaluate.TransactionScriptFailure' values.
'runTransactionOperation' is the exact, pinned production boundary: it fixes
'TransactionRuntime''s @trEvaluate@ to the real
@ConwayTx -> m (EvaluateTxResult ConwayEra)@ shape 'evaluateTxH' returns and
is a thin wrapper over the generic core.
-}
module Cardano.KERI.Deployment.TransactionRuntime (
    -- * Runtime capability
    TransactionRuntime (..),
    TransactionRuntimeError (..),
    runTransactionOperation,
    runTransactionOperationGeneric,

    -- * Evaluation classification
    classifyEvaluation,

    -- * Pure transaction id
    transactionId,

    -- * Signing
    TransactionSigningError (..),
    PureSignError (..),
    signWithCardanoCliKey,
) where

import Cardano.Ledger.Api.Tx (txIdTx)
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.TxIn (TxId)

-- cardano-node-clients is new relative to pair base 8bc604e: this Slice 1
-- runtime module deliberately introduces it for 'ConwayTx',
-- 'EvaluateTxResult', and 'SubmitResult', the shared in-process query/
-- submission types the higher #177 composition layer will supply.
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Cardano.Tx.Sign.Core (
    PureSignError (..),
    attachPaymentWitness,
    decodePaymentSigningKey,
    mkPaymentWitness,
    signConwayTxBodyHash,
 )
import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.List (intercalate)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map

-- ---------------------------------------------------------------------------
-- Errors

-- | Failure of one runtime operation. Both cases are fail-closed.
data TransactionRuntimeError
    = {- | At least one script purpose failed evaluation; carries the
      actionable per-purpose detail from 'classifyEvaluation'.
      -}
      TransactionEvaluationRejected !ByteString
    | -- | The node rejected submission; carries its stated reason.
      TransactionSubmissionRejected !ByteString
    deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Evaluation classification

{- | Fold a raw per-purpose evaluation result into pass/fail. Every entry
must be 'Right' for the whole operation to proceed; any 'Left' rejects the
operation with every failing purpose named (never silently dropped by a
@rights@\/@mapMaybe@-shaped filter).

Deliberately parametric over @purpose@\/@failure@: production instantiates
it at the real pinned @'EvaluateTxResult' 'ConwayEra'@ shape
(@Map (PlutusPurpose AsIx ConwayEra) (Either (TransactionScriptFailure
ConwayEra) ExUnits)@) via 'runTransactionOperation'; tests may instantiate
it at lightweight stand-ins.
-}
classifyEvaluation ::
    (Show purpose, Show failure) =>
    Map purpose (Either failure success) ->
    Either ByteString ()
classifyEvaluation results =
    case [(purpose, err) | (purpose, Left err) <- Map.toList results] of
        [] -> Right ()
        failures ->
            Left . BS8.pack $
                intercalate
                    "; "
                    [show purpose <> ": " <> show err | (purpose, err) <- failures]

-- ---------------------------------------------------------------------------
-- Pure transaction id

{- | The pure transaction id of a signed ledger transaction. Never parsed
from subprocess output (FR-4).
-}
transactionId :: ConwayTx -> TxId
transactionId = txIdTx

-- ---------------------------------------------------------------------------
-- Signing

{- | Wraps 'Cardano.Tx.Sign.Core.PureSignError' for this module's own error
surface; carries the pinned pure-signing-core failure unchanged.
-}
newtype TransactionSigningError = TransactionSigningError PureSignError
    deriving stock (Eq, Show)

{- | Sign a Conway transaction with a Cardano CLI-shaped
@PaymentSigningKeyShelley_ed25519@ key envelope, returning the transaction
with one detached vkey witness attached.

Composes exactly the four operations of the pure, indexer\/node-neutral
@cardano-tx-tools:tx-sign-core@ sublibrary — 'decodePaymentSigningKey',
'signConwayTxBodyHash', 'mkPaymentWitness', 'attachPaymentWitness' — none of
it is reimplemented (FR-4). This crosses no @Vault@\/@Witness@\/
@AttachWitness@ boundary: those gated, node-client-adjacent modules are not
imported here.
-}
signWithCardanoCliKey ::
    Value -> ConwayTx -> Either TransactionSigningError ConwayTx
signWithCardanoCliKey keyEnvelope tx =
    case decodePaymentSigningKey keyEnvelope of
        Left err -> Left (TransactionSigningError err)
        Right signKey ->
            let signature = signConwayTxBodyHash signKey tx
                witness = mkPaymentWitness signKey signature
             in Right (attachPaymentWitness witness tx)

-- ---------------------------------------------------------------------------
-- Runtime capability

{- | Indexer-neutral capability binding protocol query, script evaluation,
signing, submission, and settlement observation to one caller-supplied
transaction evolution. The higher composition layer supplies the real
'Cardano.Node.Client.Provider.queryProtocolParamsH',
'Cardano.Node.Client.Provider.evaluateTxH',
'signWithCardanoCliKey'-backed signing, and
'Cardano.Node.Client.Submitter.submitTx' implementations.
-}
data TransactionRuntime m = TransactionRuntime
    { trQueryProtocolParams :: m (PParams ConwayEra)
    , trEvaluate :: ConwayTx -> m (EvaluateTxResult ConwayEra)
    , trSign :: ConwayTx -> m ConwayTx
    , trSubmit :: ConwayTx -> m SubmitResult
    , trObserve :: TxId -> m ()
    }

{- | Run one transaction operation end to end against a single caller-built
draft: query protocol parameters, evaluate the draft, fail closed on
rejection, else sign, derive the pure id from the signed transaction,
submit, fail closed on rejection, else observe settlement and return the
id.

The reported/observed id is always 'transactionId' of the *signed*
transaction, never the submitter's echoed id — this is invariant 3 from the
\#181 in-process transaction-path spec.
-}
runTransactionOperationGeneric ::
    (Monad m, Show purpose, Show failure) =>
    m (PParams ConwayEra) ->
    (ConwayTx -> m (Map purpose (Either failure success))) ->
    (ConwayTx -> m ConwayTx) ->
    (ConwayTx -> m SubmitResult) ->
    (TxId -> m ()) ->
    (PParams ConwayEra -> ConwayTx) ->
    m (Either TransactionRuntimeError TxId)
runTransactionOperationGeneric queryPParams evaluate sign submit observe buildDraft = do
    pparams <- queryPParams
    let draft = buildDraft pparams
    evaluated <- evaluate draft
    case classifyEvaluation evaluated of
        Left detail -> pure (Left (TransactionEvaluationRejected detail))
        Right () -> do
            signed <- sign draft
            let txId = transactionId signed
            result <- submit signed
            case result of
                Rejected reason -> pure (Left (TransactionSubmissionRejected reason))
                Submitted _submittedId -> observe txId >> pure (Right txId)

{- | Thin, exact-boundary wrapper: the production 'TransactionRuntime' calls
the generic core with the real pinned 'EvaluateTxResult' and
'classifyEvaluation' directly — no adapter hides the raw map.
-}
runTransactionOperation ::
    (Monad m) =>
    TransactionRuntime m ->
    (PParams ConwayEra -> ConwayTx) ->
    m (Either TransactionRuntimeError TxId)
runTransactionOperation TransactionRuntime{..} =
    runTransactionOperationGeneric
        trQueryProtocolParams
        trEvaluate
        trSign
        trSubmit
        trObserve
