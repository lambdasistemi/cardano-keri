{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.AdvanceTransaction
Description : Build and settle V1 Advance through the in-process runtime

#181 Slice 3 replaces the external transaction runner with the shared
in-process build kernel; \#232 moves it onto the bounded-collateral
'Cardano.KERI.Deployment.TransactionRuntime.runPlutusTransactionBuild'.
The caller supplies a coherent funding snapshot, resolved reference scripts,
and the observer reward account; this module owns the ledger body and its
operation-specific checks.
-}
module Cardano.KERI.Deployment.AdvanceTransaction (
    AdvancePlan (..),
    AdvanceConfig (..),
    AdvanceCheckError (..),
    AdvanceError (..),
    AdvanceObservationTimeout (..),
    AdvanceResult (..),
    mkAdvancePlan,
    runAdvanceTransaction,
    awaitAdvance,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (..))
import Cardano.KERI.AID.Checkpoint.Message (SpentCheckpoint (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceObserverRedeemerData,
    advanceSpendRedeemerData,
    asPlcData,
 )
import Cardano.KERI.ChainQuery (
    ActiveCheckpoint (..),
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.Advance (AdvancePackage (..))
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.Registration (
    plutusDataFromJson,
    plutusDataJson,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    AggregateExUnitsError,
    CollateralContract (..),
    FundingPair (..),
    PayerSelectionError,
    TransactionBuildError,
    TransactionRuntime (..),
    checkAggregateExUnits,
    fundingSpends,
    runPlutusTransactionBuild,
    selectFundingPair,
 )
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    decodeAddr,
    serialiseAccountAddress,
 )
import Cardano.Ledger.Api.Tx.Out (referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxCert (
    ConwayDelegCert (ConwayRegCert),
    ConwayTxCert (ConwayTxCertDeleg),
 )
import Cardano.Ledger.Core (
    PParams,
    TxOut,
    hashScript,
    ppKeyDepositL,
 )
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Hashes (
    ScriptHash (..),
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Tx.Build (
    CertWitness (ScriptCert),
    Check (..),
    InterpretIO (..),
    TxBuild,
    certify,
    payTo',
    reference,
    spend,
    spendScript,
    valid,
    withdrawScript,
 )
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Data.Aeson (Value)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Lens.Micro ((^.))
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Text.Read (readMaybe)

data AdvancePlan = AdvancePlan
    { planSpentReference :: !Text
    , planCheckpointReference :: !Text
    , planAdvanceReference :: !Text
    , planAdvanceRewardAddress :: !Text
    , planCheckpointPolicy :: !Text
    , planCheckpointAssetName :: !Text
    , planCheckpointAddress :: !Text
    , planStateOutput :: !Text
    , planSpendRedeemer :: !Value
    , planObserverRedeemer :: !Value
    , planSuccessorDatum :: !Value
    }
    deriving stock (Show, Eq)

data AdvanceConfig = AdvanceConfig
    { advanceRuntime :: !(TransactionRuntime IO)
    , advanceReferenceUtxos :: ![(TxIn, TxOut ConwayEra)]
    , advanceFundingAddress :: !Addr
    , advanceObserverRewardAccount :: !AccountAddress
    }

newtype AdvanceCheckError
    = AdvanceAggregateExUnitsExceeded AggregateExUnitsError
    deriving stock (Eq, Show)

data AdvanceError
    = AdvanceFundingSelectionFailed !PayerSelectionError
    | AdvancePlanRejected !String
    | AdvanceBuildFailed !(TransactionBuildError AdvanceCheckError)
    deriving stock (Eq, Show)

data AdvanceObservationTimeout
    = AdvanceObservationTimeout !Text !Text !Text !Text
    deriving stock (Eq, Show)

data AdvanceResult = AdvanceResult
    { resultObserverRegistrationTxId :: !(Maybe TxId)
    , resultAdvanceTxId :: !TxId
    }
    deriving stock (Eq, Show)

newtype RawData = RawData Data

instance ToData RawData where
    toBuiltinData (RawData datum) = BuiltinData datum

mkAdvancePlan :: Manifest -> AdvancePackage -> Either String AdvancePlan
mkAdvancePlan manifest package = do
    checkpoint <- scriptNamed "checkpoint-register" manifest
    observer <- scriptNamed "observer-advance" manifest
    policy <- decodeHexSized "checkpoint policy" 28 (scriptHash checkpoint)
    observerHash <-
        decodeHexSized
            "observer-advance script hash"
            28
            (scriptHash observer)
    planAdvanceRewardAddress <- rewardAddress observerHash
    let active = advanceActiveCheckpoint package
        spent = advanceSpent package
        planSpentReference = advanceSpentReference package
        planCheckpointReference = renderReference (scriptReference checkpoint)
        planAdvanceReference = renderReference (scriptReference observer)
        planCheckpointPolicy = scriptHash checkpoint
        planCheckpointAssetName = activeCheckpointAssetName active
        planCheckpointAddress = activeCheckpointAddress active
        planStateOutput = renderStateOutput active
        planSpendRedeemer = plutusDataJson advanceSpendRedeemerData
        planObserverRedeemer =
            plutusDataJson $
                advanceObserverRedeemerData
                    policy
                    (scTxid spent)
                    (scIndex spent)
                    (advanceEvidence package)
        planSuccessorDatum =
            plutusDataJson $ asPlcData $ V1 $ advanceSuccessor package
    pure AdvancePlan{..}

runAdvanceTransaction ::
    AdvanceConfig ->
    AdvancePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Bool ->
    IO (Either AdvanceError AdvanceResult)
runAdvanceTransaction config plan fundingInputs activeInput registerObserver =
    case advanceInputs config plan fundingInputs activeInput registerObserver of
        Left err -> pure (Left err)
        Right AdvanceInputs{..} -> do
            let runtime = advanceRuntime config
            pparams <- trQueryProtocolParams runtime
            let frozenRuntime = runtime{trQueryProtocolParams = pure pparams}
            result <-
                runPlutusTransactionBuild
                    frozenRuntime
                    advanceInterpret
                    (fundingSpends advanceFunding <> [advanceActiveInput])
                    advanceReferences
                    (advanceFundingAddress config)
                    CollateralContract
                        { collateralInput = fundingCollateral advanceFunding
                        , collateralReturnAddress = advanceFundingAddress config
                        }
                    (advanceProgram pparams config registerObserver AdvanceInputs{..})
            pure $
                first AdvanceBuildFailed result >>= \txId ->
                    Right
                        AdvanceResult
                            { resultObserverRegistrationTxId =
                                if registerObserver then Just txId else Nothing
                            , resultAdvanceTxId = txId
                            }

data AdvanceInputs = AdvanceInputs
    { advanceFunding :: !FundingPair
    , advanceActiveInput :: !(TxIn, TxOut ConwayEra)
    , advanceReferences :: ![(TxIn, TxOut ConwayEra)]
    , advanceCheckpointAddress :: !Addr
    , advanceSpendData :: !RawData
    , advanceObserverData :: !RawData
    , advanceSuccessorData :: !RawData
    }

advanceInputs ::
    AdvanceConfig ->
    AdvancePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Bool ->
    Either AdvanceError AdvanceInputs
advanceInputs config plan fundingInputs activeInput registerObserver = do
    spent <- planTxIn (planSpentReference plan)
    unless (fst activeInput == spent) $
        Left (AdvancePlanRejected "resolved active checkpoint disagrees with the plan")
    checkpointHash <- planScriptHash "checkpoint policy" (planCheckpointPolicy plan)
    observerHash <- observerScriptHash config plan
    checkpointReference <-
        resolveReference
            "checkpoint reference script hash"
            checkpointHash
            (planCheckpointReference plan)
            (advanceReferenceUtxos config)
    observerReference <-
        resolveReference
            "advance observer reference script hash"
            observerHash
            (planAdvanceReference plan)
            (advanceReferenceUtxos config)
    assetName <- planAssetName "checkpoint asset name" (planCheckpointAssetName plan)
    requireCheckpointAsset (PolicyID checkpointHash) assetName activeInput
    advanceCheckpointAddress <- planAddress (planCheckpointAddress plan)
    advanceSpendData <- rawPlanData "advance spend redeemer" (planSpendRedeemer plan)
    advanceObserverData <- rawPlanData "advance observer redeemer" (planObserverRedeemer plan)
    advanceSuccessorData <- rawPlanData "successor datum" (planSuccessorDatum plan)
    advanceFunding <-
        first AdvanceFundingSelectionFailed $
            selectFundingPair
                isPlainUtxo
                (Coin $ if registerObserver then 8_000_000 else 5_000_000)
                fundingInputs
    pure
        AdvanceInputs
            { advanceActiveInput = activeInput
            , advanceReferences = [checkpointReference, observerReference]
            , ..
            }

advanceProgram ::
    PParams ConwayEra ->
    AdvanceConfig ->
    Bool ->
    AdvanceInputs ->
    TxBuild AdvanceCtx AdvanceCheckError ()
advanceProgram
    pparams
    config
    registerObserver
    AdvanceInputs
        { advanceFunding = funding
        , ..
        } = do
        mapM_ (spend . fst) (fundingSpends funding)
        _ <- spendScript (fst advanceActiveInput) advanceSpendData
        _ <-
            payTo'
                advanceCheckpointAddress
                (snd advanceActiveInput ^. valueTxOutL)
                advanceSuccessorData
        mapM_ (reference . fst) advanceReferences
        when registerObserver $ do
            let credential =
                    case advanceObserverRewardAccount config of
                        AccountAddress _ (AccountId value) -> value
            _ <-
                certify
                    ( ConwayTxCertDeleg $
                        ConwayRegCert credential (SJust $ pparams ^. ppKeyDepositL)
                    )
                    (ScriptCert $ RawData $ I 0)
            pure ()
        withdrawScript
            (advanceObserverRewardAccount config)
            (Coin 0)
            advanceObserverData
        valid (advanceCheck pparams)

data AdvanceCtx a

advanceInterpret :: InterpretIO AdvanceCtx
advanceInterpret = InterpretIO (\case {})

advanceCheck :: PParams ConwayEra -> ConwayTx -> Check AdvanceCheckError
advanceCheck pparams tx =
    case checkAggregateExUnits pparams tx of
        Pass -> Pass
        LedgerFail failure -> LedgerFail failure
        CustomFail failure ->
            CustomFail (AdvanceAggregateExUnitsExceeded failure)

awaitAdvance ::
    (Text -> Text -> IO [ChainAssetUtxo]) ->
    Int ->
    Int ->
    Text ->
    Text ->
    Text ->
    Text ->
    IO (Either AdvanceObservationTimeout ChainAssetUtxo)
awaitAdvance queryAsset pollMicros timeoutSeconds policy asset txId address = do
    started <- getCurrentTime
    let loop = do
            queried <- try (queryAsset policy asset)
            case queried of
                Right outputs ->
                    case filter matches outputs of
                        output : _ -> pure (Right output)
                        [] -> retry started
                Left (_ :: SomeException) -> retry started
        matches output =
            chainAssetTxId output == txId
                && chainAssetAddress output == address
                && any matchesAsset (chainAssetList output)
        matchesAsset chainAsset =
            chainAssetPolicy chainAsset == policy
                && chainAssetName chainAsset == asset
                && chainAssetQuantity chainAsset == 1
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt >= fromIntegral timeoutSeconds
                then
                    pure $
                        Left (AdvanceObservationTimeout policy asset txId address)
                else threadDelay pollMicros >> loop
    loop

observerScriptHash ::
    AdvanceConfig -> AdvancePlan -> Either AdvanceError ScriptHash
observerScriptHash config plan = do
    unless
        (renderRewardAccount (advanceObserverRewardAccount config) == planAdvanceRewardAddress plan)
        (Left $ AdvancePlanRejected "advance observer reward account disagrees with the plan")
    case advanceObserverRewardAccount config of
        AccountAddress _ (AccountId (ScriptHashObj hash)) -> Right hash
        AccountAddress _ (AccountId KeyHashObj{}) ->
            Left $ AdvancePlanRejected "advance observer reward account is not script-backed"

resolveReference ::
    String ->
    ScriptHash ->
    Text ->
    [(TxIn, TxOut ConwayEra)] ->
    Either AdvanceError (TxIn, TxOut ConwayEra)
resolveReference label expected rendered rows = do
    txIn <- planTxIn rendered
    row@(_, txOut) <-
        maybe
            (Left $ AdvancePlanRejected $ label <> " UTxO is unresolved")
            Right
            (find ((== txIn) . fst) rows)
    case txOut ^. referenceScriptTxOutL of
        SNothing -> Left $ AdvancePlanRejected $ label <> " UTxO has no script"
        SJust script
            | hashScript script == expected -> Right row
            | otherwise -> Left $ AdvancePlanRejected $ label <> " disagrees with the plan"

requireCheckpointAsset ::
    PolicyID ->
    AssetName ->
    (TxIn, TxOut ConwayEra) ->
    Either AdvanceError ()
requireCheckpointAsset policy assetName (_, txOut) =
    case txOut ^. valueTxOutL of
        MaryValue _ (MultiAsset assets)
            | (Map.lookup policy assets >>= Map.lookup assetName) == Just 1 -> Right ()
        _ -> Left $ AdvancePlanRejected "active checkpoint does not carry the planned singleton"

isPlainUtxo :: TxOut ConwayEra -> Bool
isPlainUtxo txOut =
    case (txOut ^. referenceScriptTxOutL, txOut ^. valueTxOutL) of
        (SNothing, MaryValue _ (MultiAsset assets)) -> Map.null assets
        _ -> False

rawPlanData :: String -> Value -> Either AdvanceError RawData
rawPlanData label =
    first (AdvancePlanRejected . ((label <> ": ") <>))
        . fmap RawData
        . plutusDataFromJson

planScriptHash :: String -> Text -> Either AdvanceError ScriptHash
planScriptHash label encoded = do
    bytes <- first AdvancePlanRejected (decodeHexSized label 28 encoded)
    maybe
        (Left $ AdvancePlanRejected $ label <> " is not a ledger hash")
        (Right . ScriptHash)
        (hashFromBytes bytes)

planAssetName :: String -> Text -> Either AdvanceError AssetName
planAssetName label encoded = do
    bytes <- planHex label encoded
    if BS.length bytes <= 32
        then Right (AssetName $ SBS.toShort bytes)
        else Left (AdvancePlanRejected $ label <> " exceeds 32 bytes")

planTxIn :: Text -> Either AdvanceError TxIn
planTxIn rendered =
    case T.splitOn "#" rendered of
        [encodedId, renderedIx] -> do
            rawId <- planHex "reference transaction id" encodedId
            unless (BS.length rawId == 32) $
                Left $
                    AdvancePlanRejected "reference transaction id is not 32 bytes"
            digest <-
                maybe
                    (Left $ AdvancePlanRejected "reference transaction id is not a ledger hash")
                    Right
                    (hashFromBytes rawId)
            txIx <-
                maybe
                    (Left $ AdvancePlanRejected "reference transaction index is invalid")
                    Right
                    (readMaybe $ T.unpack renderedIx)
            pure (TxIn (TxId $ unsafeMakeSafeHash digest) (TxIx txIx))
        _ -> Left (AdvancePlanRejected "reference must have txid#index form")

planHex :: String -> Text -> Either AdvanceError ByteString
planHex label encoded =
    first
        (const $ AdvancePlanRejected $ label <> " is not hexadecimal")
        (convertFromBase Base16 $ TE.encodeUtf8 encoded)

planAddress :: Text -> Either AdvanceError Addr
planAddress encoded = do
    (_, dataPart) <-
        first
            (AdvancePlanRejected . ("checkpoint address is not Bech32: " <>) . show)
            (Bech32.decodeLenient encoded)
    bytes <-
        maybe
            (Left $ AdvancePlanRejected "checkpoint address data is invalid")
            Right
            (Bech32.dataPartToBytes dataPart)
    address <-
        maybe
            (Left $ AdvancePlanRejected "checkpoint address is not a Shelley address")
            Right
            (decodeAddr bytes :: Maybe Addr)
    case address of
        Addr Testnet _ _ -> Right address
        Addr Mainnet _ _ -> Left (AdvancePlanRejected "checkpoint address belongs to mainnet")
        AddrBootstrap{} -> Left (AdvancePlanRejected "checkpoint address is a Byron address")

scriptNamed :: Text -> Manifest -> Either String ScriptEntry
scriptNamed name manifest =
    case filter ((== name) . scriptName) (manifestScripts manifest) of
        [script] -> Right script
        _ -> Left ("manifest script is not unique: " <> T.unpack name)

renderReference :: Reference -> Text
renderReference scriptReference =
    referenceTxId scriptReference
        <> "#"
        <> T.pack (show $ referenceIndex scriptReference)

renderStateOutput :: ActiveCheckpoint -> Text
renderStateOutput active =
    activeCheckpointAddress active
        <> "+"
        <> T.pack (show $ activeCheckpointLovelace active)
        <> T.concat (map renderAsset $ activeCheckpointAssets active)
  where
    renderAsset asset =
        " + "
            <> T.pack (show $ chainAssetQuantity asset)
            <> " "
            <> chainAssetPolicy asset
            <> "."
            <> chainAssetName asset

decodeHexSized :: String -> Int -> Text -> Either String ByteString
decodeHexSized label expected encoded = do
    bytes <-
        either
            (const $ Left $ label <> " is not hexadecimal")
            Right
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == expected) $
        Left (label <> " has the wrong byte length")
    pure bytes

rewardAddress :: ByteString -> Either String Text
rewardAddress raw = do
    hash <-
        maybe
            (Left "observer-advance script hash is not a ledger hash")
            (Right . ScriptHash)
            (hashFromBytes raw)
    pure $
        renderRewardAccount $
            AccountAddress Testnet (AccountId $ ScriptHashObj hash)

renderRewardAccount :: AccountAddress -> Text
renderRewardAccount account@(AccountAddress network _) =
    Bech32.encodeLenient
        ( either
            (error . show)
            id
            ( Bech32.humanReadablePartFromText $
                case network of
                    Testnet -> "stake_test"
                    Mainnet -> "stake"
            )
        )
        (Bech32.dataPartFromBytes $ serialiseAccountAddress account)
