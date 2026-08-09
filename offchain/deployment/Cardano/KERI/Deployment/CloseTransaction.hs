{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.CloseTransaction
Description : Build and settle V1 Close through the in-process runtime

The immutable checkpoint reference witnesses both the state spend and marker
burn. The shared transaction kernel builds, signs, derives the pure id,
submits exactly the signed value, and observes settlement without an external
command.
-}
module Cardano.KERI.Deployment.CloseTransaction (
    ClosePlan (..),
    CloseConfig (..),
    CloseCheckError (..),
    CloseError (..),
    CloseObservationTimeout (..),
    CloseResult (..),
    mkClosePlan,
    runCloseTransaction,
    awaitClose,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Checkpoint.Close (closeSpendRedeemerData)
import Cardano.KERI.AID.Checkpoint.Wire (closeBurnRedeemerData)
import Cardano.KERI.ChainQuery (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.Close (ClosePackage (..))
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
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
    FundingPair (..),
    PayerSelectionError,
    TransactionBuildError,
    TransactionRuntime (..),
    checkAggregateExUnits,
    fundingSpends,
    runTransactionBuild,
    selectFundingPair,
 )
import Cardano.Ledger.Address (Addr (..), decodeAddr)
import Cardano.Ledger.Api.Tx.Out (referenceScriptTxOutL, valueTxOutL)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (
    PParams,
    TxOut,
    hashScript,
    mkBasicTxOut,
 )
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Tx.Balance (CollateralUtxos (..))
import Cardano.Tx.Build (
    BuildOptions (..),
    Check (..),
    InterpretIO (..),
    TxBuild,
    collateral,
    defaultBuildOptions,
    mint,
    output,
    reference,
    spend,
    spendScript,
    valid,
 )
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Data.Aeson (Value)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
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
import PlutusCore.Data (Data)
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Text.Read (readMaybe)

data ClosePlan = ClosePlan
    { closePlanSpentReference :: !Text
    , closePlanCheckpointReference :: !Text
    , closePlanPolicy :: !Text
    , closePlanAssetName :: !Text
    , closePlanRefundAddress :: !Text
    , closePlanRefundLovelace :: !Integer
    , closePlanRefundOutput :: !Text
    , closePlanSpendRedeemer :: !Value
    , closePlanMintRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data CloseConfig = CloseConfig
    { closeRuntime :: !(TransactionRuntime IO)
    , closeReferenceUtxos :: ![(TxIn, TxOut ConwayEra)]
    , closeFundingAddress :: !Addr
    , closeChangeAddress :: !Addr
    }

newtype CloseCheckError
    = CloseAggregateExUnitsExceeded AggregateExUnitsError
    deriving stock (Eq, Show)

data CloseError
    = CloseFundingSelectionFailed !PayerSelectionError
    | ClosePlanRejected !String
    | CloseBuildFailed !(TransactionBuildError CloseCheckError)
    deriving stock (Eq, Show)

newtype CloseObservationTimeout = CloseObservationTimeout TxId
    deriving stock (Eq, Show)

newtype CloseResult = CloseResult
    { closeResultTxId :: TxId
    }
    deriving stock (Eq, Show)

newtype RawData = RawData Data

instance ToData RawData where
    toBuiltinData (RawData datum) = BuiltinData datum

mkClosePlan :: Manifest -> ClosePackage -> Either String ClosePlan
mkClosePlan manifest package = do
    checkpoint <- scriptNamed "checkpoint-register" manifest
    let closePlanPolicy = checkpointPolicyId (manifestCheckpoint manifest)
    unless (scriptHash checkpoint == closePlanPolicy) $
        Left "manifest checkpoint policy does not match its script entry"
    _ <- decodeHexSized "checkpoint policy" 28 closePlanPolicy
    spentTxId <-
        decodeHexSized
            "checkpoint transaction id"
            32
            (activeCheckpointTxId $ closeActiveCheckpoint package)
    let closePlanSpentReference = closeSpentReference package
        closePlanCheckpointReference = renderReference (scriptReference checkpoint)
        closePlanAssetName =
            activeCheckpointAssetName (closeActiveCheckpoint package)
        closePlanRefundAddress = closeRefundAddress package
        closePlanRefundLovelace = closeRefundLovelace package
        closePlanRefundOutput =
            closePlanRefundAddress <> "+" <> T.pack (show closePlanRefundLovelace)
        closePlanSpendRedeemer =
            plutusDataJson $ closeSpendRedeemerData (closeEvidence package)
        closePlanMintRedeemer =
            plutusDataJson $
                closeBurnRedeemerData
                    spentTxId
                    (fromIntegral $ activeCheckpointIndex $ closeActiveCheckpoint package)
    pure ClosePlan{..}

runCloseTransaction ::
    CloseConfig ->
    ClosePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    IO (Either CloseError CloseResult)
runCloseTransaction config plan fundingInputs activeInput =
    case closeInputs config plan fundingInputs activeInput of
        Left err -> pure (Left err)
        Right inputs@CloseInputs{closeFunding = funding} -> do
            let runtime = closeRuntime config
            pparams <- trQueryProtocolParams runtime
            let frozenRuntime = runtime{trQueryProtocolParams = pure pparams}
                options =
                    defaultBuildOptions
                        { boCollateralUtxos =
                            CollateralUtxos [fundingCollateral funding]
                        }
            result <-
                runTransactionBuild
                    options
                    frozenRuntime
                    closeInterpret
                    (fundingSpends funding <> [activeInput])
                    (closeReferences inputs)
                    (closeChangeAddress config)
                    (closeProgram pparams inputs)
            pure (CloseResult <$> first CloseBuildFailed result)

data CloseInputs = CloseInputs
    { closeFunding :: !FundingPair
    , closeActiveInput :: !(TxIn, TxOut ConwayEra)
    , closeReferences :: ![(TxIn, TxOut ConwayEra)]
    , closeRefundAddr :: !Addr
    , closeRefundCoin :: !Integer
    , closePolicy :: !PolicyID
    , closeAssetName :: !AssetName
    , closeSpendData :: !RawData
    , closeMintData :: !RawData
    }

closeInputs ::
    CloseConfig ->
    ClosePlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Either CloseError CloseInputs
closeInputs config plan fundingInputs activeInput = do
    spent <- planTxIn (closePlanSpentReference plan)
    unless (fst activeInput == spent) $
        Left (ClosePlanRejected "resolved active checkpoint disagrees with the plan")
    policyHash <- planScriptHash "checkpoint policy" (closePlanPolicy plan)
    closeAssetName <- planAssetName "checkpoint asset name" (closePlanAssetName plan)
    requireCheckpointValue
        (Coin $ closePlanRefundLovelace plan)
        (PolicyID policyHash)
        closeAssetName
        activeInput
    checkpointReference <-
        resolveReference
            "checkpoint reference script hash"
            policyHash
            (closePlanCheckpointReference plan)
            (closeReferenceUtxos config)
    closeRefundAddr <- planAddress (closePlanRefundAddress plan)
    when (closeChangeAddress config == closeRefundAddr) $
        Left (ClosePlanRejected "change address must differ from the exact Close refund target")
    when (closePlanRefundLovelace plan <= 0) $
        Left (ClosePlanRejected "close refund must be positive")
    closeSpendData <- rawPlanData "close spend redeemer" (closePlanSpendRedeemer plan)
    closeMintData <- rawPlanData "close mint redeemer" (closePlanMintRedeemer plan)
    closeFunding <-
        first CloseFundingSelectionFailed $
            selectFundingPair isPlainUtxo (Coin 5_000_000) fundingInputs
    pure
        CloseInputs
            { closeActiveInput = activeInput
            , closeReferences = [checkpointReference]
            , closeRefundCoin = closePlanRefundLovelace plan
            , closePolicy = PolicyID policyHash
            , ..
            }

closeProgram ::
    PParams ConwayEra ->
    CloseInputs ->
    TxBuild CloseCtx CloseCheckError ()
closeProgram pparams CloseInputs{closeFunding = FundingPair{..}, ..} = do
    mapM_ (spend . fst) (fundingSpend : fundingAdditionalSpends)
    _ <- spendScript (fst closeActiveInput) closeSpendData
    collateral (fst fundingCollateral)
    _ <-
        output $
            mkBasicTxOut
                closeRefundAddr
                (MaryValue (Coin closeRefundCoin) $ MultiAsset mempty)
    mint closePolicy (Map.singleton closeAssetName (-1)) closeMintData
    mapM_ (reference . fst) closeReferences
    valid (closeCheck pparams)

data CloseCtx a

closeInterpret :: InterpretIO CloseCtx
closeInterpret = InterpretIO (\case {})

closeCheck :: PParams ConwayEra -> ConwayTx -> Check CloseCheckError
closeCheck pparams tx =
    case checkAggregateExUnits pparams tx of
        Pass -> Pass
        LedgerFail failure -> LedgerFail failure
        CustomFail failure -> CustomFail (CloseAggregateExUnitsExceeded failure)

awaitClose ::
    (TxId -> IO Bool) ->
    Int ->
    Int ->
    TxId ->
    IO (Either CloseObservationTimeout ())
awaitClose settled pollMicros timeoutSeconds txId = do
    started <- getCurrentTime
    let loop = do
            result <- try (settled txId)
            case result of
                Right True -> pure (Right ())
                Right False -> retry started
                Left (_ :: SomeException) -> retry started
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt >= fromIntegral timeoutSeconds
                then pure (Left $ CloseObservationTimeout txId)
                else threadDelay pollMicros >> loop
    loop

resolveReference ::
    String ->
    ScriptHash ->
    Text ->
    [(TxIn, TxOut ConwayEra)] ->
    Either CloseError (TxIn, TxOut ConwayEra)
resolveReference label expected rendered rows = do
    txIn <- planTxIn rendered
    row@(_, txOut) <-
        maybe
            (Left $ ClosePlanRejected $ label <> " UTxO is unresolved")
            Right
            (find ((== txIn) . fst) rows)
    case txOut ^. referenceScriptTxOutL of
        SNothing -> Left $ ClosePlanRejected $ label <> " UTxO has no script"
        SJust script
            | hashScript script == expected -> Right row
            | otherwise -> Left $ ClosePlanRejected $ label <> " disagrees with the plan"

requireCheckpointValue ::
    Coin ->
    PolicyID ->
    AssetName ->
    (TxIn, TxOut ConwayEra) ->
    Either CloseError ()
requireCheckpointValue expectedCoin policy assetName (_, txOut) =
    case txOut ^. valueTxOutL of
        MaryValue coin (MultiAsset assets)
            | coin == expectedCoin
                && assets == Map.singleton policy (Map.singleton assetName 1) ->
                Right ()
        _ ->
            Left $
                ClosePlanRejected
                    "active checkpoint value does not exactly match the singleton and refund plan"

isPlainUtxo :: TxOut ConwayEra -> Bool
isPlainUtxo txOut =
    case (txOut ^. referenceScriptTxOutL, txOut ^. valueTxOutL) of
        (SNothing, MaryValue _ (MultiAsset assets)) -> Map.null assets
        _ -> False

rawPlanData :: String -> Value -> Either CloseError RawData
rawPlanData label =
    first (ClosePlanRejected . ((label <> ": ") <>))
        . fmap RawData
        . plutusDataFromJson

planScriptHash :: String -> Text -> Either CloseError ScriptHash
planScriptHash label encoded = do
    bytes <- first ClosePlanRejected (decodeHexSized label 28 encoded)
    maybe
        (Left $ ClosePlanRejected $ label <> " is not a ledger hash")
        (Right . ScriptHash)
        (hashFromBytes bytes)

planAssetName :: String -> Text -> Either CloseError AssetName
planAssetName label encoded = do
    bytes <- planHex label encoded
    if BS.length bytes <= 32
        then Right (AssetName $ SBS.toShort bytes)
        else Left (ClosePlanRejected $ label <> " exceeds 32 bytes")

planTxIn :: Text -> Either CloseError TxIn
planTxIn rendered =
    case T.splitOn "#" rendered of
        [encodedId, renderedIx] -> do
            rawId <- planHex "reference transaction id" encodedId
            unless (BS.length rawId == 32) $
                Left $
                    ClosePlanRejected "reference transaction id is not 32 bytes"
            digest <-
                maybe
                    (Left $ ClosePlanRejected "reference transaction id is not a ledger hash")
                    Right
                    (hashFromBytes rawId)
            txIx <-
                maybe
                    (Left $ ClosePlanRejected "reference transaction index is invalid")
                    Right
                    (readMaybe $ T.unpack renderedIx)
            pure (TxIn (TxId $ unsafeMakeSafeHash digest) (TxIx txIx))
        _ -> Left (ClosePlanRejected "reference must have txid#index form")

planHex :: String -> Text -> Either CloseError ByteString
planHex label encoded =
    first
        (const $ ClosePlanRejected $ label <> " is not hexadecimal")
        (convertFromBase Base16 $ TE.encodeUtf8 encoded)

planAddress :: Text -> Either CloseError Addr
planAddress encoded = do
    (_, dataPart) <-
        first
            (ClosePlanRejected . ("refund address is not Bech32: " <>) . show)
            (Bech32.decodeLenient encoded)
    bytes <-
        maybe
            (Left $ ClosePlanRejected "refund address data is invalid")
            Right
            (Bech32.dataPartToBytes dataPart)
    address <-
        maybe
            (Left $ ClosePlanRejected "refund address is not a Shelley address")
            Right
            (decodeAddr bytes :: Maybe Addr)
    case address of
        Addr Testnet _ _ -> Right address
        Addr Mainnet _ _ -> Left (ClosePlanRejected "refund address belongs to mainnet")
        AddrBootstrap{} -> Left (ClosePlanRejected "refund address is a Byron address")

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
