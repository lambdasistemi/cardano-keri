{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.AdvanceTransaction
Description : Build and settle the V1 reference-script Advance transaction
-}
module Cardano.KERI.Deployment.AdvanceTransaction (
    AdvancePlan (..),
    AdvanceRunnerConfig (..),
    AdvanceFiles (..),
    AdvanceResult (..),
    mkAdvancePlan,
    advanceBuildArguments,
    observerRegistrationBuildArguments,
    runAdvanceTransaction,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (..))
import Cardano.KERI.AID.Checkpoint.Message (SpentCheckpoint (..))
import Cardano.KERI.AID.Checkpoint.Wire (
    advanceObserverRedeemerData,
    advanceSpendRedeemerData,
    asPlcData,
 )
import Cardano.KERI.Deployment.Advance (AdvancePackage (..))
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
    KoiosToken,
    queryAssetUtxos,
 )
import Cardano.KERI.Deployment.CheckpointIndex (ActiveCheckpoint (..))
import Cardano.KERI.Deployment.LegacyCardanoCli (renderCardanoCliFailure)
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.Publisher (parseTransactionId)
import Cardano.KERI.Deployment.Registration (plutusDataJson)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    serialiseAccountAddress,
 )
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Codec.Binary.Bech32 qualified as Bech32
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
import Data.ByteString (ByteString)
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
import PlutusCore.Data (Data (I))
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

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

data AdvanceRunnerConfig = AdvanceRunnerConfig
    { runnerCardanoCli :: !FilePath
    , runnerNetworkMagic :: !Int
    , runnerNodeSocket :: !FilePath
    , runnerFundingAddress :: !Text
    , runnerSigningKeyFile :: !FilePath
    , runnerKoiosUrl :: !Text
    , runnerKoiosToken :: !(Maybe KoiosToken)
    , runnerTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

data AdvanceFiles = AdvanceFiles
    { filesSpendRedeemer :: !FilePath
    , filesObserverRedeemer :: !FilePath
    , filesObserverCertificateRedeemer :: !FilePath
    , filesObserverCertificate :: !FilePath
    , filesObserverRegistrationBody :: !FilePath
    , filesObserverRegistrationSigned :: !FilePath
    , filesSuccessorDatum :: !FilePath
    , filesBody :: !FilePath
    , filesSigned :: !FilePath
    }
    deriving stock (Show, Eq)

data AdvanceResult = AdvanceResult
    { resultObserverRegistrationTxId :: !(Maybe Text)
    , resultAdvanceTxId :: !Text
    }
    deriving stock (Show, Eq)

data WalletUtxo = WalletUtxo
    { walletLovelace :: !Integer
    , walletReferenceScript :: !(Maybe Value)
    , walletAssetCount :: !Int
    }
    deriving stock (Show)

newtype ProtocolParameters = ProtocolParameters
    { protocolStakeAddressDeposit :: Integer
    }

instance FromJSON ProtocolParameters where
    parseJSON = withObject "ProtocolParameters" $ \o ->
        ProtocolParameters <$> o .: "stakeAddressDeposit"

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

mkAdvancePlan :: Manifest -> AdvancePackage -> Either String AdvancePlan
mkAdvancePlan manifest package = do
    checkpoint <- scriptNamed "checkpoint-register" manifest
    observer <- scriptNamed "observer-advance" manifest
    policy <-
        decodeHexSized
            "checkpoint policy"
            28
            (scriptHash checkpoint)
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
            plutusDataJson $
                asPlcData $
                    V1 $
                        advanceSuccessor package
    pure AdvancePlan{..}

advanceBuildArguments ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    AdvanceFiles ->
    Text ->
    Text ->
    [String]
advanceBuildArguments config plan files funding collateral =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack (planSpentReference plan)
    , "--spending-tx-in-reference"
    , T.unpack (planCheckpointReference plan)
    , "--spending-plutus-script-v3"
    , "--spending-reference-tx-in-inline-datum-present"
    , "--spending-reference-tx-in-redeemer-file"
    , filesSpendRedeemer files
    , "--tx-in"
    , T.unpack funding
    , "--tx-in-collateral"
    , T.unpack collateral
    , "--tx-out"
    , T.unpack (planStateOutput plan)
    , "--tx-out-inline-datum-file"
    , filesSuccessorDatum files
    , "--change-address"
    , T.unpack (runnerFundingAddress config)
    , "--withdrawal"
    , T.unpack (planAdvanceRewardAddress plan) <> "+0"
    , "--withdrawal-tx-in-reference"
    , T.unpack (planAdvanceReference plan)
    , "--withdrawal-plutus-script-v3"
    , "--withdrawal-reference-tx-in-redeemer-file"
    , filesObserverRedeemer files
    , "--testnet-magic"
    , show (runnerNetworkMagic config)
    , "--socket-path"
    , runnerNodeSocket config
    , "--out-file"
    , filesBody files
    ]

observerRegistrationBuildArguments ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    AdvanceFiles ->
    Text ->
    Text ->
    [String]
observerRegistrationBuildArguments config plan files funding collateral =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack funding
    , "--tx-in-collateral"
    , T.unpack collateral
    , "--change-address"
    , T.unpack (runnerFundingAddress config)
    , "--certificate-file"
    , filesObserverCertificate files
    , "--certificate-tx-in-reference"
    , T.unpack (planAdvanceReference plan)
    , "--certificate-plutus-script-v3"
    , "--certificate-reference-tx-in-redeemer-file"
    , filesObserverCertificateRedeemer files
    , "--testnet-magic"
    , show (runnerNetworkMagic config)
    , "--socket-path"
    , runnerNodeSocket config
    , "--out-file"
    , filesObserverRegistrationBody files
    ]

runAdvanceTransaction ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    IO AdvanceResult
runAdvanceTransaction config plan = do
    when (runnerTimeoutSeconds config <= 0) $
        fail "timeout-seconds must be positive"
    withSystemTempDirectory "ckeri-advance" $ \directory -> do
        let files = advanceFiles directory
        writeAdvanceFiles files plan
        resultObserverRegistrationTxId <-
            ensureObserverRegistered config plan files directory
        mapM_
            (putStrLn . ("observer registration txid: " <>) . T.unpack)
            resultObserverRegistrationTxId
        wallet <- queryWallet config (directory </> "wallet.json")
        (funding, collateral) <-
            selectFundingPair 5_000_000 "checkpoint advance" wallet
        _ <-
            runCardanoCli
                config
                (advanceBuildArguments config plan files funding collateral)
        txId <- signSubmit config (filesBody files) (filesSigned files)
        _ <-
            waitForAsset
                config
                (planCheckpointPolicy plan)
                (planCheckpointAssetName plan)
                txId
                (planCheckpointAddress plan)
        pure AdvanceResult{resultAdvanceTxId = txId, ..}

advanceFiles :: FilePath -> AdvanceFiles
advanceFiles directory =
    AdvanceFiles
        { filesSpendRedeemer = directory </> "spend-redeemer.json"
        , filesObserverRedeemer = directory </> "observer-redeemer.json"
        , filesObserverCertificateRedeemer =
            directory </> "observer-certificate-redeemer.json"
        , filesObserverCertificate =
            directory </> "observer-registration.cert"
        , filesObserverRegistrationBody =
            directory </> "observer-registration.body"
        , filesObserverRegistrationSigned =
            directory </> "observer-registration.signed"
        , filesSuccessorDatum = directory </> "successor-datum.json"
        , filesBody = directory </> "advance.body"
        , filesSigned = directory </> "advance.signed"
        }

writeAdvanceFiles :: AdvanceFiles -> AdvancePlan -> IO ()
writeAdvanceFiles files plan = do
    Aeson.encodeFile (filesSpendRedeemer files) (planSpendRedeemer plan)
    Aeson.encodeFile (filesObserverRedeemer files) (planObserverRedeemer plan)
    Aeson.encodeFile
        (filesObserverCertificateRedeemer files)
        (plutusDataJson $ I 0)
    Aeson.encodeFile (filesSuccessorDatum files) (planSuccessorDatum plan)

ensureObserverRegistered ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    AdvanceFiles ->
    FilePath ->
    IO (Maybe Text)
ensureObserverRegistered config plan files directory = do
    registered <-
        observerRegistered
            config
            plan
            (directory </> "observer-stake-address-info.json")
    if registered
        then pure Nothing
        else do
            writeObserverCertificate
                config
                plan
                files
                (directory </> "protocol-parameters.json")
            wallet <-
                queryWallet config (directory </> "wallet-observer-registration.json")
            (funding, collateral) <-
                selectFundingPair
                    8_000_000
                    "observer stake registration"
                    wallet
            _ <-
                runCardanoCli
                    config
                    ( observerRegistrationBuildArguments
                        config
                        plan
                        files
                        funding
                        collateral
                    )
            txId <-
                signSubmit
                    config
                    (filesObserverRegistrationBody files)
                    (filesObserverRegistrationSigned files)
            waitForObserverRegistration config plan txId directory
            pure (Just txId)

observerRegistered ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    FilePath ->
    IO Bool
observerRegistered config plan output = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "stake-address-info"
            , "--address"
            , T.unpack (planAdvanceRewardAddress plan)
            , "--testnet-magic"
            , show (runnerNetworkMagic config)
            , "--socket-path"
            , runnerNodeSocket config
            , "--out-file"
            , output
            ]
    accounts <-
        eitherDecodeFileStrict' output
            >>= either
                (fail . ("cannot decode advance observer stake address info: " <>))
                pure
    pure (not $ null (accounts :: [Value]))

writeObserverCertificate ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    AdvanceFiles ->
    FilePath ->
    IO ()
writeObserverCertificate config plan files parametersFile = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "protocol-parameters"
            , "--testnet-magic"
            , show (runnerNetworkMagic config)
            , "--socket-path"
            , runnerNodeSocket config
            , "--out-file"
            , parametersFile
            ]
    parameters <-
        eitherDecodeFileStrict' parametersFile
            >>= either
                (fail . ("cannot decode protocol parameters: " <>))
                pure
    _ <-
        runCardanoCli
            config
            [ "conway"
            , "stake-address"
            , "registration-certificate"
            , "--stake-address"
            , T.unpack (planAdvanceRewardAddress plan)
            , "--key-reg-deposit-amt"
            , show (protocolStakeAddressDeposit parameters)
            , "--out-file"
            , filesObserverCertificate files
            ]
    pure ()

waitForObserverRegistration ::
    AdvanceRunnerConfig ->
    AdvancePlan ->
    Text ->
    FilePath ->
    IO ()
waitForObserverRegistration config plan txId directory = do
    started <- getCurrentTime
    go started
  where
    go started = do
        result <-
            ( try $
                observerRegistered
                    config
                    plan
                    (directory </> "observer-stake-address-info-settled.json")
            ) ::
                IO (Either SomeException Bool)
        case result of
            Right True -> pure ()
            _ -> retry started
    retry started = do
        now <- getCurrentTime
        if diffUTCTime now started
            >= fromIntegral (runnerTimeoutSeconds config)
            then
                fail $
                    "timed out waiting for advance observer registration \
                    \transaction "
                        <> T.unpack txId
            else threadDelay 5_000_000 >> go started

queryWallet ::
    AdvanceRunnerConfig ->
    FilePath ->
    IO (Map Text WalletUtxo)
queryWallet config output = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "utxo"
            , "--address"
            , T.unpack (runnerFundingAddress config)
            , "--testnet-magic"
            , show (runnerNetworkMagic config)
            , "--socket-path"
            , runnerNodeSocket config
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
    AdvanceRunnerConfig ->
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
            , runnerSigningKeyFile config
            , "--testnet-magic"
            , show (runnerNetworkMagic config)
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
            , show (runnerNetworkMagic config)
            , "--socket-path"
            , runnerNodeSocket config
            ]
    pure txId

runCardanoCli :: AdvanceRunnerConfig -> [String] -> IO String
runCardanoCli config arguments = do
    (exitCode, output, err) <-
        readProcessWithExitCode (runnerCardanoCli config) arguments ""
    case exitCode of
        ExitSuccess -> pure output
        ExitFailure code ->
            fail (renderCardanoCliFailure code err output)

waitForAsset ::
    AdvanceRunnerConfig ->
    Text ->
    Text ->
    Text ->
    Text ->
    IO Text
waitForAsset config policyId assetName txId expectedAddress = do
    started <- getCurrentTime
    go started
  where
    go started = do
        result <-
            try $
                queryAssetUtxos
                    (runnerKoiosUrl config)
                    (runnerKoiosToken config)
                    policyId
                    assetName
        case result of
            Right utxos ->
                case filter matches utxos of
                    [utxo] ->
                        pure $
                            chainAssetTxId utxo
                                <> "#"
                                <> T.pack (show $ chainAssetIndex utxo)
                    _ -> retry started
            Left (_ :: SomeException) -> retry started
    matches utxo =
        chainAssetTxId utxo == txId
            && chainAssetAddress utxo == expectedAddress
            && any isSingleton (chainAssetList utxo)
    isSingleton asset =
        chainAssetPolicy asset == policyId
            && chainAssetName asset == assetName
            && chainAssetQuantity asset == 1
    retry :: UTCTime -> IO Text
    retry started = do
        now <- getCurrentTime
        if diffUTCTime now started
            >= fromIntegral (runnerTimeoutSeconds config)
            then
                fail $
                    "timed out waiting for settled asset "
                        <> T.unpack policyId
                        <> "."
                        <> T.unpack assetName
                        <> " in transaction "
                        <> T.unpack txId
            else threadDelay 5_000_000 >> go started

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

scriptNamed :: Text -> Manifest -> Either String ScriptEntry
scriptNamed name manifest =
    case filter ((== name) . scriptName) (manifestScripts manifest) of
        [script] -> Right script
        _ -> Left ("manifest script is not unique: " <> T.unpack name)

renderReference :: Reference -> Text
renderReference reference =
    referenceTxId reference <> "#" <> T.pack (show $ referenceIndex reference)

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
    scriptHash <-
        maybe
            (Left "observer-advance script hash is not a ledger hash")
            (Right . ScriptHash)
            (hashFromBytes raw)
    hrp <-
        either
            (Left . show)
            Right
            (Bech32.humanReadablePartFromText "stake_test")
    pure $
        Bech32.encodeLenient
            hrp
            ( Bech32.dataPartFromBytes $
                serialiseAccountAddress $
                    AccountAddress
                        Testnet
                        (AccountId $ ScriptHashObj scriptHash)
            )
