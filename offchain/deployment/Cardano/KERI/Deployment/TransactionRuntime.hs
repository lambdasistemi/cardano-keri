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
    -- * Funding selection
    FundingPair (..),
    PayerSelectionError (..),
    fundingSpends,
    selectFundingPair,

    -- * Runtime capability
    TransactionRuntime (..),
    TransactionRuntimeError (..),
    runTransactionOperation,
    runTransactionOperationGeneric,

    -- * Converged build/sign/submit kernel
    BuildEvaluationResult,
    TransactionBuildError (..),
    runTransactionBuild,
    runTransactionBuildGeneric,

    -- * Bounded phase-2 collateral safety (#232)
    CollateralContract (..),
    CollateralSafetyError (..),
    maximumCollateralLovelace,
    validateCollateralSafety,
    runPlutusTransactionBuild,

    -- * Aggregate execution-unit check
    AggregateExUnitsError (..),
    checkAggregateExUnits,

    -- * Evaluation classification
    classifyEvaluation,

    -- * Pure transaction id
    transactionId,
    renderTransactionId,

    -- * Signing
    TransactionSigningError (..),
    PureSignError (..),
    signWithPaymentKey,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Alonzo.PParams (ppMaxTxExUnitsL)
import Cardano.Ledger.Alonzo.Scripts (AsIx)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.PParams (ppCollateralPercentageL)
import Cardano.Ledger.Api.Tx (bodyTxL, txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    collateralReturnTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    totalCollateralTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    coinTxOutL,
    getMinCoinTxOut,
    mkBasicTxOut,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (StrictMaybe (SJust, SNothing))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose)
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Hashes (extractHash)
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits, pointWiseExUnits)
import Cardano.Ledger.TxIn (TxId, TxIn, unTxId)

-- cardano-node-clients is new relative to pair base 8bc604e: this Slice 1
-- runtime module deliberately introduces it for 'ConwayTx',
-- 'EvaluateTxResult', and 'SubmitResult', the shared in-process query/
-- submission types the higher #177 composition layer will supply.
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.Provider (EvaluateTxResult)
import Cardano.Node.Client.Submitter (SubmitResult (..))
import Cardano.Tx.Balance (BalanceError, CollateralUtxos (..))
import Cardano.Tx.Build (
    BuildError (..),
    BuildOptions (..),
    Check (..),
    InterpretIO,
    TxBuild,
    buildWith,
    collateral,
    defaultBuildOptions,
    mkPParamsBound,
    setCollateralReturn,
 )
import Cardano.Tx.Inputs (spendingIndex)
import Cardano.Tx.Sign.Core (
    PureSignError (..),
    attachPaymentWitness,
    decodePaymentSigningKey,
    mkPaymentWitness,
    signConwayTxBodyHash,
 )
import Data.Aeson (Value)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as BS8
import Data.Functor.Const (Const (..))
import Data.List (intercalate, sortBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Lens.Micro ((^.))

-- ---------------------------------------------------------------------------
-- Funding selection

-- | Distinct spending and collateral inputs selected from one indexed view.
data FundingPair = FundingPair
    { fundingSpend :: !(TxIn, TxOut ConwayEra)
    , fundingAdditionalSpends :: ![(TxIn, TxOut ConwayEra)]
    , fundingCollateral :: !(TxIn, TxOut ConwayEra)
    }
    deriving stock (Eq, Show)

fundingSpends :: FundingPair -> [(TxIn, TxOut ConwayEra)]
fundingSpends FundingPair{..} = fundingSpend : fundingAdditionalSpends

-- | Actionable failures from deterministic payer selection.
data PayerSelectionError
    = -- | The indexer returned no rows at all.
      EmptyIndexedSnapshot
    | -- | No eligible row carries the required spending value.
      InsufficientFundingValue
        { requiredFundingValue :: !Coin
        , greatestAvailableValue :: !Coin
        }
    | -- | A spend was selected, but no distinct collateral row remained.
      MissingCollateral
        { selectedFundingInput :: !TxIn
        }
    deriving stock (Eq, Show)

{- | Select a deterministic spending/collateral pair from a caller-supplied
indexed snapshot.

Rows are deduplicated by 'TxIn', filtered by the operation-owned eligibility
predicate, then ranked by descending lovelace and ascending 'TxIn'. The
smallest eligible row is reserved as collateral and the shortest descending
prefix whose aggregate value reaches the minimum is selected for spending.
Empty raw input remains distinguishable from a non-empty snapshot with no
eligible value.
-}
selectFundingPair ::
    (TxOut ConwayEra -> Bool) ->
    Coin ->
    [(TxIn, TxOut ConwayEra)] ->
    Either PayerSelectionError FundingPair
selectFundingPair _ _ [] = Left EmptyIndexedSnapshot
selectFundingPair eligible required rows =
    case ranked of
        [] -> insufficient (Coin 0)
        [spendRow]
            | outputCoin spendRow < required -> insufficient (outputCoin spendRow)
            | otherwise -> Left (MissingCollateral (fst spendRow))
        _ -> case reserveCollateral ranked of
            Nothing -> insufficient (Coin 0)
            Just (candidates, collateralRow) ->
                let available = sumCoins (map outputCoin candidates)
                 in if available < required
                        then insufficient available
                        else case takeRequired required candidates of
                            spendRow : additional ->
                                Right
                                    FundingPair
                                        { fundingSpend = spendRow
                                        , fundingAdditionalSpends = additional
                                        , fundingCollateral = collateralRow
                                        }
                            [] -> insufficient (Coin 0)
  where
    ranked =
        sortBy compareRank eligibleRows

    eligibleRows =
        filter (eligible . snd)
            . Map.elems
            $ Map.fromListWith
                preferDuplicate
                [(txIn, row) | row@(txIn, _) <- rows]

    eligibleInputs = Set.fromList (map fst eligibleRows)

    insufficient available =
        Left
            InsufficientFundingValue
                { requiredFundingValue = required
                , greatestAvailableValue = available
                }

    outputCoin (_, txOut) = getConst (coinTxOutL Const txOut)

    sumCoins :: [Coin] -> Coin
    sumCoins = foldr addCoin (Coin 0)

    reserveCollateral = go []
      where
        go _ [] = Nothing
        go spendingRows [collateralRow] =
            Just (reverse spendingRows, collateralRow)
        go spendingRows (row : remaining) =
            go (row : spendingRows) remaining

    addCoin :: Coin -> Coin -> Coin
    addCoin (Coin left) (Coin right) = Coin (left + right)

    takeRequired ::
        Coin ->
        [(TxIn, TxOut ConwayEra)] ->
        [(TxIn, TxOut ConwayEra)]
    takeRequired target = go (Coin 0)
      where
        go ::
            Coin ->
            [(TxIn, TxOut ConwayEra)] ->
            [(TxIn, TxOut ConwayEra)]
        go _ [] = []
        go accumulated (row : remaining)
            | addCoin accumulated (outputCoin row) >= target = [row]
            | otherwise =
                row : go (addCoin accumulated $ outputCoin row) remaining

    compareRank left right =
        compare
            (Down (outputCoin left), spendingIndex (fst left) eligibleInputs)
            (Down (outputCoin right), spendingIndex (fst right) eligibleInputs)

    -- Conflicting duplicate rows are not expected from a committed snapshot,
    -- but choosing by a total key keeps even malformed input order-independent.
    preferDuplicate left right =
        maxBy (outputCoin left, show (snd left)) (outputCoin right, show (snd right)) left right

    maxBy leftKey rightKey left right
        | leftKey >= rightKey = left
        | otherwise = right

-- ---------------------------------------------------------------------------
-- Errors

-- | Failure of one runtime operation. Both cases are fail-closed.
data TransactionRuntimeError
    = {- | At least one script purpose failed evaluation; carries the
      actionable per-purpose detail from 'classifyEvaluation'.
      -}
      TransactionEvaluationRejected !ByteString
    | -- | Signing failed before submission; carries the typed key failure.
      TransactionSigningRejected !TransactionSigningError
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

-- | Render a ledger transaction id for indexer queries and operator output.
renderTransactionId :: TxId -> Text
renderTransactionId =
    TE.decodeUtf8
        . convertToBase Base16
        . hashToBytes
        . extractHash
        . unTxId

-- ---------------------------------------------------------------------------
-- Signing

{- | Wraps 'Cardano.Tx.Sign.Core.PureSignError' for this module's own error
surface; carries the pinned pure-signing-core failure unchanged.
-}
newtype TransactionSigningError = TransactionSigningError PureSignError
    deriving stock (Eq, Show)

{- | Sign a Conway transaction with a standard Cardano
@PaymentSigningKeyShelley_ed25519@ key envelope, returning the transaction
with one detached vkey witness attached.

Composes exactly the four operations of the pure, indexer\/node-neutral
@cardano-tx-tools:tx-sign-core@ sublibrary — 'decodePaymentSigningKey',
'signConwayTxBodyHash', 'mkPaymentWitness', 'attachPaymentWitness' — none of
it is reimplemented (FR-4). This crosses no @Vault@\/@Witness@\/
@AttachWitness@ boundary: those gated, node-client-adjacent modules are not
imported here.
-}
signWithPaymentKey ::
    Value -> ConwayTx -> Either TransactionSigningError ConwayTx
signWithPaymentKey keyEnvelope tx =
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
'signWithPaymentKey'-backed signing, and
'Cardano.Node.Client.Submitter.submitTx' implementations.
-}
data TransactionRuntime m = TransactionRuntime
    { trQueryProtocolParams :: m (PParams ConwayEra)
    , trEvaluate :: ConwayTx -> m (EvaluateTxResult ConwayEra)
    , trSign :: ConwayTx -> m (Either TransactionSigningError ConwayTx)
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
    (ConwayTx -> m (Either TransactionSigningError ConwayTx)) ->
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
            signedResult <- sign draft
            case signedResult of
                Left err -> pure (Left (TransactionSigningRejected err))
                Right signed -> do
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

-- ---------------------------------------------------------------------------
-- Converged build/sign/submit kernel

-- | Exact evaluator shape consumed by pinned 'buildWith'.
type BuildEvaluationResult =
    Map
        (ConwayPlutusPurpose AsIx ConwayEra)
        (Either String ExUnits)

-- | Typed failure of the shared in-process build/sign/submit evolution.
data TransactionBuildError e
    = TransactionBuildEvaluationRejected
        !(ConwayPlutusPurpose AsIx ConwayEra)
        !String
    | TransactionBuildBalanceRejected !BalanceError
    | TransactionBuildChecksRejected ![Check e]
    | TransactionBuildInternalError !String
    | TransactionBuildSigningRejected !TransactionSigningError
    | TransactionBuildSubmissionRejected !ByteString
    | {- | \#232: the converged body could not prove a bounded phase-2
      collateral loss, so it was refused before signing.
      -}
      TransactionBuildCollateralRejected !CollateralSafetyError
    deriving stock (Eq, Show)

{- | Build one transaction to convergence with the pinned transaction-tool
kernel, then sign, derive its pure id, submit exactly that signed transaction,
and observe the derived id. Every failure is fail-closed at its phase.
-}
runTransactionBuildGeneric ::
    BuildOptions ->
    IO (PParams ConwayEra) ->
    (ConwayTx -> IO BuildEvaluationResult) ->
    (ConwayTx -> IO (Either TransactionSigningError ConwayTx)) ->
    (ConwayTx -> IO SubmitResult) ->
    (TxId -> IO ()) ->
    InterpretIO q ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    Addr ->
    TxBuild q e a ->
    IO (Either (TransactionBuildError e) TxId)
runTransactionBuildGeneric options =
    runTransactionBuildWith options acceptAnyConvergedBody
  where
    acceptAnyConvergedBody _pparams = Right

{- | The shared build/sign/submit evolution with one post-convergence,
pre-sign gate. The gate sees the protocol snapshot that balanced the body and
the converged body itself, and a rejection short-circuits before 'sign' is
ever called — which is what makes \#232's collateral refusal a refusal to
/sign/, not merely a refusal to submit.

Not exported: callers reach it through 'runTransactionBuildGeneric' (no gate,
the script-free path) or 'runPlutusTransactionBuild' (the bounded-collateral
gate), so no operation can supply a gate of its own.
-}
runTransactionBuildWith ::
    BuildOptions ->
    (PParams ConwayEra -> ConwayTx -> Either (TransactionBuildError e) ConwayTx) ->
    IO (PParams ConwayEra) ->
    (ConwayTx -> IO BuildEvaluationResult) ->
    (ConwayTx -> IO (Either TransactionSigningError ConwayTx)) ->
    (ConwayTx -> IO SubmitResult) ->
    (TxId -> IO ()) ->
    InterpretIO q ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    Addr ->
    TxBuild q e a ->
    IO (Either (TransactionBuildError e) TxId)
runTransactionBuildWith
    options
    gate
    queryPParams
    evaluate
    sign
    submit
    observe
    interpret
    inputUtxos
    referenceUtxos
    changeAddress
    program = do
        pparams <- queryPParams
        builtResult <-
            buildWith
                options
                (mkPParamsBound pparams)
                interpret
                evaluate
                inputUtxos
                referenceUtxos
                changeAddress
                program
        case builtResult of
            Left err -> pure (Left (mapBuildError err))
            Right built -> case gate pparams built of
                Left err -> pure (Left err)
                Right accepted -> do
                    signedResult <- sign accepted
                    case signedResult of
                        Left err -> pure (Left (TransactionBuildSigningRejected err))
                        Right signed -> do
                            let signedId = transactionId signed
                            submission <- submit signed
                            case submission of
                                Rejected reason ->
                                    pure (Left (TransactionBuildSubmissionRejected reason))
                                Submitted _submittedId -> do
                                    observe signedId
                                    pure (Right signedId)
      where
        mapBuildError (EvalFailure purpose detail) =
            TransactionBuildEvaluationRejected purpose detail
        mapBuildError (BalanceFailed err) =
            TransactionBuildBalanceRejected err
        mapBuildError (ChecksFailed failures) =
            TransactionBuildChecksRejected failures
        mapBuildError (BumpFeeFailed detail) =
            TransactionBuildInternalError detail

{- | Adapt the real node-client evaluation failure to the string detail
expected by pinned 'buildWith', preserving every purpose key.
-}
adaptEvaluation ::
    TransactionRuntime IO -> ConwayTx -> IO BuildEvaluationResult
adaptEvaluation TransactionRuntime{trEvaluate} tx =
    fmap (Map.map (first show)) (trEvaluate tx)

{- | Production record wrapper over 'runTransactionBuildGeneric'. This is the
script-free entry point: it adds no collateral resolution and no collateral
gate, so a body carrying no redeemer keeps absent Conway collateral fields
(DATA-INV-232-06).
-}
runTransactionBuild ::
    BuildOptions ->
    TransactionRuntime IO ->
    InterpretIO q ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    Addr ->
    TxBuild q e a ->
    IO (Either (TransactionBuildError e) TxId)
runTransactionBuild options runtime@TransactionRuntime{..} =
    runTransactionBuildGeneric
        options
        trQueryProtocolParams
        (adaptEvaluation runtime)
        trSign
        trSubmit
        trObserve

-- ---------------------------------------------------------------------------
-- Aggregate execution units

-- | The final transaction declares more aggregate budget than the snapshot permits.
data AggregateExUnitsError = AggregateExUnitsExceeded
    { aggregateDeclaredExUnits :: !ExUnits
    , aggregateMaximumExUnits :: !ExUnits
    }
    deriving stock (Eq, Show)

{- | Check the final transaction's semantic redeemer budgets against the
maximum aggregate execution units from the same protocol-parameter snapshot.
-}
checkAggregateExUnits ::
    PParams ConwayEra ->
    ConwayTx ->
    Check AggregateExUnitsError
checkAggregateExUnits pparams tx
    | pointWiseExUnits (<=) declared maximumUnits = Pass
    | otherwise =
        CustomFail
            AggregateExUnitsExceeded
                { aggregateDeclaredExUnits = declared
                , aggregateMaximumExUnits = maximumUnits
                }
  where
    txWits = getConst (witsTxL Const tx)
    Redeemers redeemers = getConst (rdmrsTxWitsL Const txWits)
    declared = foldMap snd redeemers
    maximumUnits = getConst (ppMaxTxExUnitsL Const pparams)

-- ---------------------------------------------------------------------------
-- Bounded phase-2 collateral safety (#232)

{- | The resolved collateral commitment one Plutus build is willing to expose
to a phase-2 failure: exactly one plain ADA-only funding UTxO, and the
operation's own funding address as the destination of the unused remainder.

The product maximum is deliberately not a field: it is fixed for every ckeri
Plutus transaction by 'maximumCollateralLovelace' and is not
caller-configurable (DAT-232-COLLATERAL-CONTRACT).
-}
data CollateralContract = CollateralContract
    { collateralInput :: !(TxIn, TxOut ConwayEra)
    -- ^ the one resolved ADA-only collateral input
    , collateralReturnAddress :: !Addr
    -- ^ the operation's funding address, which receives the remainder
    }
    deriving stock (Eq, Show)

{- | The absolute ceiling on what one ckeri Plutus transaction may lose to a
phase-2 script failure: 5,000,000 lovelace (5 ADA), independent of the
wallet's UTxO layout (RQ-232-02, DATA-INV-232-02).
-}
maximumCollateralLovelace :: Coin
maximumCollateralLovelace = Coin 5_000_000

{- | Every way a converged body can fail to prove a bounded phase-2 loss.
Each case names the violated property and carries the lovelace or identity it
disagreed about, so no rejection collapses into an unnamed failure
(DAT-232-COLLATERAL-FAILURE).
-}
data CollateralSafetyError
    = -- | The exact protocol requirement itself exceeds the product ceiling.
      CollateralRequirementAboveMaximum
        { collateralRequiredLovelace :: !Coin
        , collateralMaximumLovelace :: !Coin
        }
    | {- | The resolved input cannot fund the exact total and still leave a
      min-UTxO-valid return.
      -}
      CollateralInputInsufficient
        { collateralRequiredLovelace :: !Coin
        , collateralMinimumReturnLovelace :: !Coin
        , collateralAvailableLovelace :: !Coin
        }
    | -- | The body's collateral inputs are not exactly the contract's input.
      CollateralInputSetMismatch
        { collateralExpectedInput :: !TxIn
        , collateralDeclaredInputs :: !(Set TxIn)
        }
    | -- | The collateral input is also a regular spending input.
      CollateralInputAlsoSpent
        { collateralExpectedInput :: !TxIn
        }
    | -- | The resolved collateral input carries native assets.
      CollateralInputNotAdaOnly
        { collateralExpectedInput :: !TxIn
        }
    | -- | The body declares no total collateral at all.
      CollateralTotalMissing
        { collateralRequiredLovelace :: !Coin
        }
    | -- | The declared total is not the exact protocol requirement.
      CollateralTotalMismatch
        { collateralRequiredLovelace :: !Coin
        , collateralDeclaredLovelace :: !Coin
        }
    | -- | No collateral return is present, so the whole input is exposed.
      CollateralReturnMissing
        { collateralExpectedReturnLovelace :: !Coin
        }
    | -- | The collateral return pays somewhere other than the funding address.
      CollateralReturnMisaddressed
        { collateralExpectedReturnAddress :: !Addr
        , collateralDeclaredReturnAddress :: !Addr
        }
    | -- | The collateral return carries native assets.
      CollateralReturnNotAdaOnly
        { collateralDeclaredReturnAddress :: !Addr
        }
    | -- | The collateral return is below its own min-UTxO requirement.
      CollateralReturnBelowMinimum
        { collateralDeclaredReturnLovelace :: !Coin
        , collateralMinimumReturnLovelace :: !Coin
        }
    | -- | Declared total plus returned lovelace is not the input lovelace.
      CollateralConservationViolated
        { collateralDeclaredLovelace :: !Coin
        , collateralDeclaredReturnLovelace :: !Coin
        , collateralAvailableLovelace :: !Coin
        }
    deriving stock (Eq, Show)

{- | Decide whether one converged Conway body proves a bounded phase-2 loss
against the protocol snapshot that balanced it and the resolved collateral
contract. Every property is read from the final body and the resolved input —
never from a caller's claim — and every rejection is typed.
-}
validateCollateralSafety ::
    PParams ConwayEra ->
    CollateralContract ->
    ConwayTx ->
    Either CollateralSafetyError ConwayTx
validateCollateralSafety pparams contract tx
    | required > maximumCollateralLovelace =
        Left (CollateralRequirementAboveMaximum required maximumCollateralLovelace)
    | not (isAdaOnly resolvedOutput) =
        Left (CollateralInputNotAdaOnly resolvedInput)
    | declaredInputs /= Set.singleton resolvedInput =
        Left (CollateralInputSetMismatch resolvedInput declaredInputs)
    | Set.member resolvedInput (body ^. inputsTxBodyL) =
        Left (CollateralInputAlsoSpent resolvedInput)
    | available < required || residual < minimumResidualReturn =
        Left (CollateralInputInsufficient required minimumResidualReturn available)
    | otherwise = checkDeclaredTotal
  where
    body = tx ^. bodyTxL
    (resolvedInput, resolvedOutput) = collateralInput contract
    returnAddress = collateralReturnAddress contract
    declaredInputs = body ^. collateralInputsTxBodyL
    available = resolvedOutput ^. coinTxOutL
    required = requiredTotalCollateral pparams (body ^. feeTxBodyL)
    residual = clampedDifference available required
    minimumResidualReturn =
        getMinCoinTxOut pparams (adaOnlyOutput returnAddress residual)

    checkDeclaredTotal =
        case body ^. totalCollateralTxBodyL of
            SNothing -> Left (CollateralTotalMissing required)
            SJust declaredTotal
                | declaredTotal /= required ->
                    Left (CollateralTotalMismatch required declaredTotal)
                | otherwise -> checkDeclaredReturn declaredTotal

    checkDeclaredReturn declaredTotal =
        case body ^. collateralReturnTxBodyL of
            SNothing -> Left (CollateralReturnMissing residual)
            SJust returnOutput
                | declaredReturnAddress /= returnAddress ->
                    Left
                        ( CollateralReturnMisaddressed
                            returnAddress
                            declaredReturnAddress
                        )
                | not (isAdaOnly returnOutput) ->
                    Left (CollateralReturnNotAdaOnly returnAddress)
                | returned < minimumReturn ->
                    Left (CollateralReturnBelowMinimum returned minimumReturn)
                | addLovelace declaredTotal returned /= available ->
                    Left
                        ( CollateralConservationViolated
                            declaredTotal
                            returned
                            available
                        )
                | otherwise -> Right tx
              where
                declaredReturnAddress = returnOutput ^. addrTxOutL
                returned = returnOutput ^. coinTxOutL
                minimumReturn = getMinCoinTxOut pparams returnOutput

{- | @ceiling (fee * p / 100)@ for the snapshot's collateral percentage @p@ —
the exact amount the Conway ledger requires (DATA-INV-232-01). Derived here
from the protocol snapshot rather than accepted from the balancer's own
output, so a body whose declared total disagrees is refused.
-}
requiredTotalCollateral :: PParams ConwayEra -> Coin -> Coin
requiredTotalCollateral pparams (Coin fee) =
    Coin (ceilingDiv (fee * percentage) 100)
  where
    percentage = fromIntegral (pparams ^. ppCollateralPercentageL)
    ceilingDiv numerator denominator =
        (numerator + denominator - 1) `div` denominator

isAdaOnly :: TxOut ConwayEra -> Bool
isAdaOnly txOut =
    case txOut ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) -> Map.null assets

adaOnlyOutput :: Addr -> Coin -> TxOut ConwayEra
adaOnlyOutput address amount =
    mkBasicTxOut address (MaryValue amount (MultiAsset mempty))

addLovelace :: Coin -> Coin -> Coin
addLovelace (Coin left) (Coin right) = Coin (left + right)

-- | Never negative: a shortfall is reported by its own named case instead.
clampedDifference :: Coin -> Coin -> Coin
clampedDifference (Coin left) (Coin right) = Coin (max 0 (left - right))

{- | The bounded Plutus build kernel: converge one script-bearing transaction,
prove its collateral safety, and only then sign, submit, and observe it.

It owns the collateral resolution option and the explicit funding-address
return instruction, so no operation module constructs either independently
(MOD-232-WRITES, EDGE-232-03). 'runTransactionBuild' remains the script-free
entry point for Publisher.
-}
runPlutusTransactionBuild ::
    TransactionRuntime IO ->
    InterpretIO q ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    Addr ->
    CollateralContract ->
    TxBuild q e a ->
    IO (Either (TransactionBuildError e) TxId)
runPlutusTransactionBuild
    runtime@TransactionRuntime{..}
    interpret
    spendingInputs
    referenceInputs
    changeAddress
    contract
    program =
        runTransactionBuildWith
            collateralOptions
            collateralGate
            trQueryProtocolParams
            (adaptEvaluation runtime)
            trSign
            trSubmit
            trObserve
            interpret
            spendingInputs
            referenceInputs
            changeAddress
            boundedProgram
      where
        collateralOptions =
            defaultBuildOptions
                { boCollateralUtxos = CollateralUtxos [collateralInput contract]
                }

        collateralGate pparams built =
            first TransactionBuildCollateralRejected $
                validateCollateralSafety pparams contract built

        -- The contract is the single source of both instructions, so no
        -- operation builder declares a collateral input or a return
        -- destination of its own. Sequenced after the caller's program
        -- because 'setCollateralReturn' is last-write-wins upstream.
        boundedProgram = do
            result <- program
            collateral (fst (collateralInput contract))
            setCollateralReturn (collateralReturnAddress contract)
            pure result
