{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.CloseTransaction
Description : Build and settle the deployed V1 Close spend and CloseBurn

The immutable checkpoint reference is used twice in one transaction: once as
the spending validator and once as the minting policy. The only explicit state
output is the datum-free, exact-value refund selected by the controller.
-}
module Cardano.KERI.Deployment.CloseTransaction (
    ClosePlan (..),
    CloseRunnerConfig (..),
    CloseFiles (..),
    CloseResult (..),
    mkClosePlan,
    closeBuildArguments,
    runCloseTransaction,
) where

import Cardano.KERI.AID.Checkpoint.Close (closeSpendRedeemerData)
import Cardano.KERI.AID.Checkpoint.Wire (closeBurnRedeemerData)
import Cardano.KERI.Deployment.ChainIndex (
    ChainAssetUtxo (..),
    KoiosToken,
    queryAssetUtxos,
 )
import Cardano.KERI.Deployment.CheckpointIndex (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.Close (ClosePackage (..))
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.Publisher (parseTransactionId)
import Cardano.KERI.Deployment.Registration (
    plutusDataJson,
    renderCardanoCliFailure,
 )
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Data.Aeson (
    FromJSON (..),
    Value,
    eitherDecodeFileStrict',
    withObject,
    (.:),
    (.:?),
 )
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString qualified as BS
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

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

data CloseRunnerConfig = CloseRunnerConfig
    { closeRunnerCardanoCli :: !FilePath
    , closeRunnerNetworkMagic :: !Int
    , closeRunnerNodeSocket :: !FilePath
    , closeRunnerFundingAddress :: !Text
    , closeRunnerChangeAddress :: !Text
    , closeRunnerSigningKeyFile :: !FilePath
    , closeRunnerKoiosUrl :: !Text
    , closeRunnerKoiosToken :: !(Maybe KoiosToken)
    , closeRunnerTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

data CloseFiles = CloseFiles
    { closeFilesSpendRedeemer :: !FilePath
    , closeFilesMintRedeemer :: !FilePath
    , closeFilesBody :: !FilePath
    , closeFilesSigned :: !FilePath
    }
    deriving stock (Show, Eq)

newtype CloseResult = CloseResult
    { closeResultTxId :: Text
    }
    deriving stock (Show, Eq)

data WalletUtxo = WalletUtxo
    { walletLovelace :: !Integer
    , walletReferenceScript :: !(Maybe Value)
    , walletAssetCount :: !Int
    }
    deriving stock (Show)

instance FromJSON WalletUtxo where
    parseJSON = withObject "WalletUtxo" $ \o -> do
        value <- o .: "value"
        (walletLovelace, walletAssetCount) <-
            withObject "WalletValue" parseWalletValue value
        walletReferenceScript <- o .:? "referenceScript"
        pure WalletUtxo{..}
      where
        parseWalletValue values = do
            lovelace <- values .: "lovelace"
            let assetCount =
                    length
                        [ ()
                        | key <- KeyMap.keys values
                        , Key.toText key /= "lovelace"
                        ]
            pure (lovelace, assetCount)

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
        closePlanCheckpointReference =
            renderReference (scriptReference checkpoint)
        closePlanAssetName =
            activeCheckpointAssetName (closeActiveCheckpoint package)
        closePlanRefundAddress = closeRefundAddress package
        closePlanRefundLovelace = closeRefundLovelace package
        closePlanRefundOutput =
            closePlanRefundAddress
                <> "+"
                <> T.pack (show closePlanRefundLovelace)
        closePlanSpendRedeemer =
            plutusDataJson $
                closeSpendRedeemerData (closeEvidence package)
        closePlanMintRedeemer =
            plutusDataJson $
                closeBurnRedeemerData
                    spentTxId
                    (fromIntegral $ activeCheckpointIndex $ closeActiveCheckpoint package)
    pure ClosePlan{..}

closeBuildArguments ::
    CloseRunnerConfig ->
    ClosePlan ->
    CloseFiles ->
    Text ->
    Text ->
    [String]
closeBuildArguments config plan files funding collateral =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack (closePlanSpentReference plan)
    , "--spending-tx-in-reference"
    , T.unpack (closePlanCheckpointReference plan)
    , "--spending-plutus-script-v3"
    , "--spending-reference-tx-in-inline-datum-present"
    , "--spending-reference-tx-in-redeemer-file"
    , closeFilesSpendRedeemer files
    , "--tx-in"
    , T.unpack funding
    , "--tx-in-collateral"
    , T.unpack collateral
    , "--tx-out"
    , T.unpack (closePlanRefundOutput plan)
    , "--change-address"
    , T.unpack (closeRunnerChangeAddress config)
    , "--mint"
    , "-1 "
        <> assetId
            (closePlanPolicy plan)
            (closePlanAssetName plan)
    , "--mint-tx-in-reference"
    , T.unpack (closePlanCheckpointReference plan)
    , "--mint-plutus-script-v3"
    , "--mint-reference-tx-in-redeemer-file"
    , closeFilesMintRedeemer files
    , "--policy-id"
    , T.unpack (closePlanPolicy plan)
    , "--testnet-magic"
    , show (closeRunnerNetworkMagic config)
    , "--socket-path"
    , closeRunnerNodeSocket config
    , "--out-file"
    , closeFilesBody files
    ]

runCloseTransaction ::
    CloseRunnerConfig ->
    ClosePlan ->
    IO CloseResult
runCloseTransaction config plan = do
    when (closeRunnerTimeoutSeconds config <= 0) $
        fail "timeout-seconds must be positive"
    when (closeRunnerNetworkMagic config /= 1) $
        fail "close is frozen to preprod network magic 1"
    when (closeRunnerChangeAddress config == closePlanRefundAddress plan) $
        fail
            "change address must differ from the exact Close refund target"
    withSystemTempDirectory "ckeri-close" $ \directory -> do
        let files = closeFiles directory
        writeCloseFiles files plan
        wallet <- queryWallet config (directory </> "wallet.json")
        (funding, collateral) <-
            selectFundingPair 5_000_000 "checkpoint close" wallet
        _ <-
            runCardanoCli
                config
                (closeBuildArguments config plan files funding collateral)
        txId <- signSubmit config (closeFilesBody files) (closeFilesSigned files)
        waitForSpentCheckpoint config plan txId
        pure $ CloseResult txId

closeFiles :: FilePath -> CloseFiles
closeFiles directory =
    CloseFiles
        { closeFilesSpendRedeemer = directory </> "spend-redeemer.json"
        , closeFilesMintRedeemer = directory </> "mint-redeemer.json"
        , closeFilesBody = directory </> "close.body"
        , closeFilesSigned = directory </> "close.signed"
        }

writeCloseFiles :: CloseFiles -> ClosePlan -> IO ()
writeCloseFiles files plan = do
    Aeson.encodeFile
        (closeFilesSpendRedeemer files)
        (closePlanSpendRedeemer plan)
    Aeson.encodeFile
        (closeFilesMintRedeemer files)
        (closePlanMintRedeemer plan)

queryWallet ::
    CloseRunnerConfig ->
    FilePath ->
    IO (Map Text WalletUtxo)
queryWallet config output = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "utxo"
            , "--address"
            , T.unpack (closeRunnerFundingAddress config)
            , "--testnet-magic"
            , show (closeRunnerNetworkMagic config)
            , "--socket-path"
            , closeRunnerNodeSocket config
            , "--out-file"
            , output
            ]
    eitherDecodeFileStrict' output
        >>= either (fail . ("cannot decode funding UTxOs: " <>)) pure

selectFundingPair ::
    Integer ->
    String ->
    Map Text WalletUtxo ->
    IO (Text, Text)
selectFundingPair minimumFunding label wallet =
    case candidates of
        (funding, fundingUtxo) : (collateral, _) : _
            | walletLovelace fundingUtxo >= minimumFunding ->
                pure (funding, collateral)
            | otherwise ->
                fail $
                    label
                        <> " needs a plain funding UTxO of at least "
                        <> show minimumFunding
                        <> " lovelace"
        _ -> fail (label <> " needs two distinct plain funding UTxOs")
  where
    candidates =
        sortOn
            (Down . walletLovelace . snd)
            [ (txIn, utxo)
            | (txIn, utxo) <- Map.toList wallet
            , isNothing (walletReferenceScript utxo)
            , walletAssetCount utxo == 0
            ]

signSubmit ::
    CloseRunnerConfig ->
    FilePath ->
    FilePath ->
    IO Text
signSubmit config body signed = do
    _ <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "sign"
            , "--tx-body-file"
            , body
            , "--signing-key-file"
            , closeRunnerSigningKeyFile config
            , "--testnet-magic"
            , show (closeRunnerNetworkMagic config)
            , "--out-file"
            , signed
            ]
    txIdOutput <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "txid"
            , "--tx-file"
            , signed
            ]
    txId <- either fail pure (parseTransactionId txIdOutput)
    _ <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "submit"
            , "--tx-file"
            , signed
            , "--testnet-magic"
            , show (closeRunnerNetworkMagic config)
            , "--socket-path"
            , closeRunnerNodeSocket config
            ]
    pure txId

runCardanoCli :: CloseRunnerConfig -> [String] -> IO String
runCardanoCli config arguments = do
    (exitCode, output, err) <-
        readProcessWithExitCode (closeRunnerCardanoCli config) arguments ""
    case exitCode of
        ExitSuccess -> pure output
        ExitFailure code ->
            fail (renderCardanoCliFailure code err output)

waitForSpentCheckpoint ::
    CloseRunnerConfig ->
    ClosePlan ->
    Text ->
    IO ()
waitForSpentCheckpoint config plan txId = do
    started <- getCurrentTime
    go started
  where
    go started = do
        result <-
            try $
                queryAssetUtxos
                    (closeRunnerKoiosUrl config)
                    (closeRunnerKoiosToken config)
                    (closePlanPolicy plan)
                    (closePlanAssetName plan)
        case result of
            Right utxos
                | all (not . isSpentReference) utxos ->
                    pure ()
            Right _ -> retry started
            Left (_ :: SomeException) -> retry started
    isSpentReference utxo =
        chainAssetTxId utxo
            <> "#"
            <> T.pack (show $ chainAssetIndex utxo)
            == closePlanSpentReference plan
    retry :: UTCTime -> IO ()
    retry started = do
        now <- getCurrentTime
        if diffUTCTime now started
            >= fromIntegral (closeRunnerTimeoutSeconds config)
            then
                fail $
                    "timed out waiting for settled close transaction "
                        <> T.unpack txId
            else threadDelay 5_000_000 >> go started

scriptNamed :: Text -> Manifest -> Either String ScriptEntry
scriptNamed name manifest =
    case filter ((== name) . scriptName) (manifestScripts manifest) of
        [script] -> Right script
        _ -> Left ("manifest script is not unique: " <> T.unpack name)

renderReference :: Reference -> Text
renderReference reference =
    referenceTxId reference <> "#" <> T.pack (show $ referenceIndex reference)

decodeHexSized :: String -> Int -> Text -> Either String BS.ByteString
decodeHexSized label expected encoded = do
    bytes <-
        either
            (const $ Left $ label <> " is not hexadecimal")
            Right
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == expected) $
        Left (label <> " has the wrong byte length")
    pure bytes

assetId :: Text -> Text -> String
assetId policy name = T.unpack policy <> "." <> T.unpack name
