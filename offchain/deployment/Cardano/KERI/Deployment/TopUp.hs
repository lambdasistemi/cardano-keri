{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE RecordWildCards #-}

{- |
Module      : Cardano.KERI.Deployment.TopUp
Description : Build the package, the plan and the transaction of a top-up (#346, #522)

A top-up adds at least one premium to the pool of a live checkpoint whose
top-up mark is clear. Anyone may make it: no signature, no rotation evidence,
no observer. The package states what the transaction must write (the marked
successor and the lovelace it holds); the plan renders it with the
redeemer; the runner builds, signs and settles it through the shared
in-process build kernel, the payer funding the added lovelace.
-}
module Cardano.KERI.Deployment.TopUp (
    TopUpPackage (..),
    TopUpPlan (..),
    TopUpConfig (..),
    TopUpError (..),
    mkTopUpPackage,
    checkTopUpPackage,
    mkTopUpPlan,
    runTopUpTransaction,
) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (..), CheckpointDatumV2)
import Cardano.KERI.AID.Checkpoint.TopUp (
    TopUpInput (..),
    TopUpParams (..),
    TopUpRefusal (..),
    TopUpSettlement (..),
    markedLive,
    topUpRefusalName,
    topUpSettlement,
    topUpVerdict,
 )
import Cardano.KERI.AID.Checkpoint.Value (checkpointMinAda)
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData, topUpSpendRedeemerData)
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.AdvanceTransaction (
    AdvanceError (..),
    RawData (..),
    isPlainUtxo,
    planAddress,
    planAssetName,
    planScriptHash,
    planTxIn,
    rawPlanData,
    renderReference,
    requireCheckpointAsset,
    resolveReference,
    scriptNamed,
    successorValue,
 )
import Cardano.KERI.Deployment.Manifest (
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.KERI.Deployment.TransactionRuntime (
    CollateralContract (..),
    FundingPair (..),
    PayerSelectionError,
    TransactionBuildError,
    TransactionRuntime (..),
    fundingSpends,
    runPlutusTransactionBuild,
    selectFundingPair,
 )
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut)
import Cardano.Ledger.Mary.Value (MaryValue, PolicyID (..))
import Cardano.Ledger.TxIn (TxId, TxIn (..))
import Cardano.Tx.Build (
    Check (..),
    InterpretIO (..),
    TxBuild,
    payTo',
    reference,
    spend,
    spendScript,
    valid,
 )
import Control.Monad (unless, void)
import Data.Aeson (Value)
import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void)

-- | What a top-up writes: the marked successor and what it holds.
data TopUpPackage = TopUpPackage
    { topUpAid :: !Text
    , topUpActiveCheckpoint :: !ActiveCheckpoint
    , topUpSpentReference :: !Text
    , topUpAmount :: !Integer
    -- ^ lovelace added to the pool
    , topUpSuccessorFacts :: !CheckpointDatumV2
    -- ^ the spent datum with the top-up mark set
    , topUpSuccessorLovelace :: !Integer
    -- ^ what the successor holds, exactly
    , topUpPoolAfter :: !Integer
    }
    deriving stock (Show, Eq)

-- | The rendered top-up: the redeemer, the successor datum and its lovelace.
data TopUpPlan = TopUpPlan
    { topUpPlanSpentReference :: !Text
    , topUpPlanCheckpointReference :: !Text
    , topUpPlanCheckpointPolicy :: !Text
    , topUpPlanCheckpointAssetName :: !Text
    , topUpPlanCheckpointAddress :: !Text
    , topUpPlanSpendRedeemer :: !Value
    , topUpPlanSuccessorDatum :: !Value
    , topUpPlanSuccessorLovelace :: !Integer
    , topUpPlanAmount :: !Integer
    }
    deriving stock (Show, Eq)

data TopUpConfig = TopUpConfig
    { topUpRuntime :: !(TransactionRuntime IO)
    , topUpReferenceUtxos :: ![(TxIn, TxOut ConwayEra)]
    , topUpFundingAddress :: !Addr
    }

data TopUpError
    = TopUpFundingSelectionFailed !PayerSelectionError
    | TopUpPlanRejected !String
    | TopUpBuildFailed !(TransactionBuildError Void)
    deriving stock (Eq, Show)

params :: DeploymentParameters -> Integer -> TopUpParams
params parameters premium =
    TopUpParams
        { tuMinAda = checkpointMinAda
        , tuDeposit = parameterRegistrationBond parameters
        , tuBond = parameterFreezeBond parameters
        , tuPremium = premium
        }

premiumOf :: DeploymentParameters -> Either String Integer
premiumOf =
    maybe
        (Left "the manifest has no premiumLovelace: its generation has no premium and cannot be topped up")
        Right
        . parameterPremium

refusalText :: TopUpRefusal -> String
refusalText refusal =
    "top-up refused (" <> topUpRefusalName refusal <> ")"

{- | The package of a top-up of this live checkpoint by this many lovelace.
'Left' with the Lean's refusal name when the amount is below the premium or
the checkpoint has already been topped up since its last rotation.
-}
mkTopUpPackage ::
    Manifest -> ActiveCheckpoint -> Integer -> Either String TopUpPackage
mkTopUpPackage manifest active amount = do
    unless
        ( networkName (manifestNetwork manifest) == "preprod"
            && networkMagic (manifestNetwork manifest) == 1
        )
        (Left "top-up manifest is not preprod network magic 1")
    premium <- premiumOf (manifestParameters manifest)
    let facts = activeCheckpointFacts active
        lovelace = activeCheckpointLovelace active
        topUpParams = params (manifestParameters manifest) premium
    case premiseRefusal topUpParams facts lovelace amount of
        Just refusal -> Left (refusalText refusal)
        Nothing -> Right ()
    successorFacts <-
        maybe (Left "top-up refused (not-live)") Right (markedLive facts)
    settlement <-
        maybe
            (Left "top-up refused (below-floor)")
            Right
            (topUpSettlement topUpParams facts lovelace amount)
    pure
        TopUpPackage
            { topUpAid = activeCheckpointAid active
            , topUpActiveCheckpoint = active
            , topUpSpentReference =
                activeCheckpointTxId active
                    <> "#"
                    <> T.pack (show $ activeCheckpointIndex active)
            , topUpAmount = amount
            , topUpSuccessorFacts = successorFacts
            , topUpSuccessorLovelace = tsSuccessorLovelace settlement
            , topUpPoolAfter = tsPool settlement
            }

{- | The first premise of the Lean that refuses a top-up of this amount, told
by running the verdict over a successor that is the spent datum itself: the
premises that name the spent state and the amount come before the ones that
compare the successor.
-}
premiseRefusal ::
    TopUpParams -> CheckpointDatumV2 -> Integer -> Integer -> Maybe TopUpRefusal
premiseRefusal topUpParams facts lovelace amount =
    case topUpVerdict
        topUpParams
        TopUpInput
            { tiSpentDatum = facts
            , tiSpentLovelace = lovelace
            , tiAmount = amount
            , tiSuccessorDatum = facts
            , tiSuccessorLovelace = lovelace
            } of
        Left refusal
            | refusal `notElem` [TopUpSuccessorNotTheMarkedCopy, TopUpSuccessorValueMismatch] ->
                Just refusal
        _ -> Nothing

{- | The Haskell verdict of the top-up this package describes: the check the
validator will make, made before a transaction is built.
-}
checkTopUpPackage :: Manifest -> TopUpPackage -> Either String ()
checkTopUpPackage manifest package = do
    premium <- premiumOf (manifestParameters manifest)
    let active = topUpActiveCheckpoint package
    first refusalText $
        topUpVerdict
            (params (manifestParameters manifest) premium)
            TopUpInput
                { tiSpentDatum = activeCheckpointFacts active
                , tiSpentLovelace = activeCheckpointLovelace active
                , tiAmount = topUpAmount package
                , tiSuccessorDatum = topUpSuccessorFacts package
                , tiSuccessorLovelace = topUpSuccessorLovelace package
                }

{- | The plan of a top-up: the TopUp spend redeemer carrying the amount, the
marked datum and the exact successor lovelace.
-}
mkTopUpPlan :: Manifest -> TopUpPackage -> Either String TopUpPlan
mkTopUpPlan manifest package = do
    checkpoint <- scriptNamed "checkpoint-register" manifest
    let active = topUpActiveCheckpoint package
    pure
        TopUpPlan
            { topUpPlanSpentReference = topUpSpentReference package
            , topUpPlanCheckpointReference =
                renderReference (scriptReference checkpoint)
            , topUpPlanCheckpointPolicy = scriptHash checkpoint
            , topUpPlanCheckpointAssetName = activeCheckpointAssetName active
            , topUpPlanCheckpointAddress = activeCheckpointAddress active
            , topUpPlanSpendRedeemer =
                plutusDataJson (topUpSpendRedeemerData (topUpAmount package))
            , topUpPlanSuccessorDatum =
                plutusDataJson (asPlcData (V2 (topUpSuccessorFacts package)))
            , topUpPlanSuccessorLovelace = topUpSuccessorLovelace package
            , topUpPlanAmount = topUpAmount package
            }

-- | The inputs of the transaction, resolved against the plan.
data TopUpInputs = TopUpInputs
    { txFunding :: !FundingPair
    , txActiveInput :: !(TxIn, TxOut ConwayEra)
    , txReferences :: ![(TxIn, TxOut ConwayEra)]
    , txCheckpointAddress :: !Addr
    , txSpendData :: !RawData
    , txSuccessorData :: !RawData
    , txSuccessorValue :: !MaryValueOf
    }

type MaryValueOf = Cardano.Ledger.Mary.Value.MaryValue

{- | Build, sign and settle a top-up. The payer's inputs fund the added
lovelace; the change returns to the funding address. Nothing is signed by the
checkpoint's controller.
-}
runTopUpTransaction ::
    TopUpConfig ->
    TopUpPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    IO (Either TopUpError TxId)
runTopUpTransaction config plan fundingInputs activeInput =
    case topUpInputs config plan fundingInputs activeInput of
        Left err -> pure (Left err)
        Right inputs -> do
            let runtime = topUpRuntime config
            pparams <- trQueryProtocolParams runtime
            let frozenRuntime = runtime{trQueryProtocolParams = pure pparams}
            result <-
                runPlutusTransactionBuild
                    frozenRuntime
                    topUpInterpret
                    (fundingSpends (txFunding inputs) <> [txActiveInput inputs])
                    (txReferences inputs)
                    (topUpFundingAddress config)
                    CollateralContract
                        { collateralInput = fundingCollateral (txFunding inputs)
                        , collateralReturnAddress = topUpFundingAddress config
                        }
                    (topUpProgram inputs)
            pure (first TopUpBuildFailed result)

topUpInputs ::
    TopUpConfig ->
    TopUpPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Either TopUpError TopUpInputs
topUpInputs config plan fundingInputs activeInput = do
    let rejected = Left . TopUpPlanRejected
    spent <- planned (planTxIn (topUpPlanSpentReference plan))
    unless (fst activeInput == spent) $
        rejected "resolved active checkpoint disagrees with the plan"
    checkpointHash <-
        planned (planScriptHash "checkpoint policy" (topUpPlanCheckpointPolicy plan))
    checkpointReference <-
        planned
            ( resolveReference
                "checkpoint reference script hash"
                checkpointHash
                (topUpPlanCheckpointReference plan)
                (topUpReferenceUtxos config)
            )
    assetName <-
        planned (planAssetName "checkpoint asset name" (topUpPlanCheckpointAssetName plan))
    planned (requireCheckpointAsset (PolicyID checkpointHash) assetName activeInput)
    txCheckpointAddress <-
        planned (planAddress (topUpPlanCheckpointAddress plan))
    txSpendData <-
        planned (rawPlanData "top-up spend redeemer" (topUpPlanSpendRedeemer plan))
    txSuccessorData <-
        planned (rawPlanData "successor datum" (topUpPlanSuccessorDatum plan))
    let txSuccessorValue = successorValue (topUpPlanSuccessorLovelace plan) activeInput
    txFunding <-
        first TopUpFundingSelectionFailed $
            selectFundingPair
                isPlainUtxo
                (Coin $ topUpPlanAmount plan + 5_000_000)
                fundingInputs
    pure
        TopUpInputs
            { txActiveInput = activeInput
            , txReferences = [checkpointReference]
            , ..
            }

topUpProgram :: TopUpInputs -> TxBuild TopUpCtx Void ()
topUpProgram TopUpInputs{..} = do
    mapM_ (spend . fst) (fundingSpends txFunding)
    _ <- spendScript (fst txActiveInput) txSpendData
    void (payTo' txCheckpointAddress txSuccessorValue txSuccessorData)
    mapM_ (reference . fst) txReferences
    valid (const Pass)

data TopUpCtx a

-- | The plan helpers of the Advance builder fail only by rejecting the plan.
planned :: Either AdvanceError a -> Either TopUpError a
planned = first $ \case
    AdvancePlanRejected message -> TopUpPlanRejected message
    other -> TopUpPlanRejected (show other)

topUpInterpret :: InterpretIO TopUpCtx
topUpInterpret = InterpretIO (\case {})
