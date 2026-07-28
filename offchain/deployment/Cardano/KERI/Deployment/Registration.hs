{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.Registration
Description : Pure V1 registration material and cardano-cli wire encodings
-}
module Cardano.KERI.Deployment.Registration (
    RegistrationPlan (..),
    RegistrationRunnerConfig (..),
    RegistrationResult (..),
    RegistrationFiles (..),
    mkRegistrationPlan,
    premintBuildArguments,
    registerBuildArguments,
    runRegistration,
    plutusDataJson,
    plutusDataFromJson,
    renderCardanoCliFailure,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    asPlcData,
    registerObserverRedeemerData,
 )
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
    KoiosToken,
    queryAssetUtxos,
 )
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    Reference (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.Publisher (parseTransactionId)
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
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
 )
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
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
import PlutusCore.Data (Data (..))
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

data RegistrationPlan = RegistrationPlan
    { planAid :: !Text
    , planProofPolicy :: !Text
    , planProofName :: !Text
    , planProofReference :: !Text
    , planCheckpointPolicy :: !Text
    , planCheckpointName :: !Text
    , planCheckpointReference :: !Text
    , planCheckpointAddress :: !Text
    , planLifecycleReference :: !Text
    , planLifecycleRewardAddress :: !Text
    , planEscrowLovelace :: !Integer
    , planPremintRedeemer :: !Value
    , planCheckpointRedeemer :: !Value
    , planProofBurnRedeemer :: !Value
    , planObserverRedeemer :: !Value
    , planLifecycleCertificateRedeemer :: !Value
    , planCheckpointDatum :: !Value
    }
    deriving stock (Show, Eq)

data RegistrationRunnerConfig = RegistrationRunnerConfig
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

data RegistrationResult = RegistrationResult
    { resultPremintTxId :: !Text
    , resultRegisterTxId :: !Text
    }
    deriving stock (Show, Eq)

data RegistrationFiles = RegistrationFiles
    { filesPremintRedeemer :: !FilePath
    , filesCheckpointRedeemer :: !FilePath
    , filesProofBurnRedeemer :: !FilePath
    , filesObserverRedeemer :: !FilePath
    , filesLifecycleCertificateRedeemer :: !FilePath
    , filesLifecycleCertificate :: !FilePath
    , filesCheckpointDatum :: !FilePath
    , filesPremintBody :: !FilePath
    , filesPremintSigned :: !FilePath
    , filesRegisterBody :: !FilePath
    , filesRegisterSigned :: !FilePath
    }

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

mkRegistrationPlan ::
    Manifest ->
    Integer ->
    InceptionExport ->
    Either String RegistrationPlan
mkRegistrationPlan manifest escrow inception = do
    unless
        ( networkName (manifestNetwork manifest) == "preprod"
            && networkMagic (manifestNetwork manifest) == 1
        )
        (Left "registration manifest is not preprod network magic 1")
    when (escrow <= 0) $
        Left "escrow-lovelace must be positive"
    let expectedEscrow =
            2_000_000
                + parameterRegistrationBond (manifestParameters manifest)
                + parameterFreezeBond (manifestParameters manifest)
    when
        ( parameterRegistrationBond (manifestParameters manifest)
            /= 1_000_000_000
        )
        (Left "manifest registration bond is not the frozen M1 V1 value")
    when
        (parameterFreezeBond (manifestParameters manifest) /= 5_000_000)
        (Left "manifest freeze bond is not the frozen M1 V1 value")
    when (escrow > expectedEscrow) $
        Left "escrow-lovelace exceeds the frozen M1 V1 escrow"
    proof <- scriptNamed "hash-proof" manifest
    checkpoint <- scriptNamed "checkpoint-register" manifest
    lifecycle <- scriptNamed "observer-lifecycle" manifest
    let datum = inceptionDatum inception
        evidence = inceptionEvidence inception
        proofName =
            proofTokenName
                (reEventBytes evidence)
                (cdCesrAid datum)
        checkpointName = deriveAidAssetName (cdCesrAid datum)
        checkpointPolicy =
            checkpointPolicyId (manifestCheckpoint manifest)
    unless (scriptHash checkpoint == checkpointPolicy) $
        Left "manifest checkpoint policy does not match its script entry"
    lifecycleHash <- decodeHex28 "observer-lifecycle script hash" (scriptHash lifecycle)
    lifecycleRewardAddress <- rewardAddress lifecycleHash
    pure
        RegistrationPlan
            { planAid = inceptionAid inception
            , planProofPolicy = scriptHash proof
            , planProofName = hexText proofName
            , planProofReference = renderReference (scriptReference proof)
            , planCheckpointPolicy = checkpointPolicy
            , planCheckpointName = hexText checkpointName
            , planCheckpointReference =
                renderReference (scriptReference checkpoint)
            , planCheckpointAddress =
                checkpointAddressBech32 (manifestCheckpoint manifest)
            , planLifecycleReference =
                renderReference (scriptReference lifecycle)
            , planLifecycleRewardAddress = lifecycleRewardAddress
            , planEscrowLovelace = escrow
            , planPremintRedeemer =
                plutusDataJson $
                    Constr
                        0
                        [ B (reEventBytes evidence)
                        , B (cdCesrAid datum)
                        , I (fromIntegral $ reOffI evidence)
                        , I (fromIntegral $ inceptionDigestOffset inception)
                        ]
            , planCheckpointRedeemer = plutusDataJson (Constr 0 [])
            , planProofBurnRedeemer =
                plutusDataJson (Constr 0 [B "", B "", I 0, I 0])
            , planObserverRedeemer =
                plutusDataJson $
                    registerObserverRedeemerData
                        (decodeHexUnsafe checkpointPolicy)
                        evidence
            , planLifecycleCertificateRedeemer = plutusDataJson (I 0)
            , planCheckpointDatum = plutusDataJson (asPlcData $ V1 datum)
            }

premintBuildArguments ::
    RegistrationRunnerConfig ->
    RegistrationPlan ->
    RegistrationFiles ->
    Text ->
    Text ->
    Bool ->
    [String]
premintBuildArguments config plan files funding collateral registerLifecycle =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack funding
    , "--tx-in-collateral"
    , T.unpack collateral
    , "--tx-out"
    , T.unpack (runnerFundingAddress config)
        <> "+5000000 + 1 "
        <> assetId (planProofPolicy plan) (planProofName plan)
    , "--change-address"
    , T.unpack (runnerFundingAddress config)
    , "--mint"
    , "1 " <> assetId (planProofPolicy plan) (planProofName plan)
    , "--mint-tx-in-reference"
    , T.unpack (planProofReference plan)
    , "--mint-plutus-script-v3"
    , "--mint-reference-tx-in-redeemer-file"
    , filesPremintRedeemer files
    , "--policy-id"
    , T.unpack (planProofPolicy plan)
    ]
        <> lifecycleCertificateArguments
        <> [ "--testnet-magic"
           , show (runnerNetworkMagic config)
           , "--socket-path"
           , runnerNodeSocket config
           , "--out-file"
           , filesPremintBody files
           ]
  where
    lifecycleCertificateArguments
        | registerLifecycle =
            [ "--certificate-file"
            , filesLifecycleCertificate files
            , "--certificate-tx-in-reference"
            , T.unpack (planLifecycleReference plan)
            , "--certificate-plutus-script-v3"
            , "--certificate-reference-tx-in-redeemer-file"
            , filesLifecycleCertificateRedeemer files
            ]
        | otherwise = []

registerBuildArguments ::
    RegistrationRunnerConfig ->
    RegistrationPlan ->
    RegistrationFiles ->
    Text ->
    Text ->
    Text ->
    [String]
registerBuildArguments config plan files proofInput funding collateral =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack proofInput
    , "--tx-in"
    , T.unpack funding
    , "--tx-in-collateral"
    , T.unpack collateral
    , "--tx-out"
    , T.unpack (planCheckpointAddress plan)
        <> "+"
        <> show (planEscrowLovelace plan)
        <> " + 1 "
        <> assetId
            (planCheckpointPolicy plan)
            (planCheckpointName plan)
    , "--tx-out-inline-datum-file"
    , filesCheckpointDatum files
    , "--change-address"
    , T.unpack (runnerFundingAddress config)
    , "--mint"
    , "1 "
        <> assetId
            (planCheckpointPolicy plan)
            (planCheckpointName plan)
        <> " + -1 "
        <> assetId (planProofPolicy plan) (planProofName plan)
    , "--mint-tx-in-reference"
    , T.unpack (planCheckpointReference plan)
    , "--mint-plutus-script-v3"
    , "--mint-reference-tx-in-redeemer-file"
    , filesCheckpointRedeemer files
    , "--policy-id"
    , T.unpack (planCheckpointPolicy plan)
    , "--mint-tx-in-reference"
    , T.unpack (planProofReference plan)
    , "--mint-plutus-script-v3"
    , "--mint-reference-tx-in-redeemer-file"
    , filesProofBurnRedeemer files
    , "--policy-id"
    , T.unpack (planProofPolicy plan)
    , "--withdrawal"
    , T.unpack (planLifecycleRewardAddress plan) <> "+0"
    , "--withdrawal-tx-in-reference"
    , T.unpack (planLifecycleReference plan)
    , "--withdrawal-plutus-script-v3"
    , "--withdrawal-reference-tx-in-redeemer-file"
    , filesObserverRedeemer files
    , "--testnet-magic"
    , show (runnerNetworkMagic config)
    , "--socket-path"
    , runnerNodeSocket config
    , "--out-file"
    , filesRegisterBody files
    ]

runRegistration ::
    RegistrationRunnerConfig ->
    RegistrationPlan ->
    IO RegistrationResult
runRegistration config plan = do
    when (runnerTimeoutSeconds config <= 0) $
        fail "timeout-seconds must be positive"
    withSystemTempDirectory "ckeri-register" $ \directory -> do
        let files = registrationFiles directory
        writeRegistrationFiles files plan
        registerLifecycle <-
            lifecycleRegistrationRequired
                config
                plan
                (directory </> "stake-address-info.json")
        when registerLifecycle $
            writeLifecycleCertificate
                config
                plan
                files
                (directory </> "protocol-parameters.json")
        wallet <- queryWallet config (directory </> "wallet-premint.json")
        (premintFunding, premintCollateral) <-
            selectFundingPair
                8_000_000
                "hash-proof premint"
                wallet
        _ <-
            runCardanoCli
                config
                ( premintBuildArguments
                    config
                    plan
                    files
                    premintFunding
                    premintCollateral
                    registerLifecycle
                )
        premintTxId <-
            signSubmit config (filesPremintBody files) (filesPremintSigned files)
        proofInput <-
            waitForAsset
                config
                (planProofPolicy plan)
                (planProofName plan)
                premintTxId
                (runnerFundingAddress config)
        registeredWallet <-
            queryWallet config (directory </> "wallet-register.json")
        (registerFunding, registerCollateral) <-
            selectFundingPair
                (planEscrowLovelace plan + 5_000_000)
                "checkpoint registration"
                registeredWallet
        _ <-
            runCardanoCli
                config
                ( registerBuildArguments
                    config
                    plan
                    files
                    proofInput
                    registerFunding
                    registerCollateral
                )
        registerTxId <-
            signSubmit config (filesRegisterBody files) (filesRegisterSigned files)
        _ <-
            waitForAsset
                config
                (planCheckpointPolicy plan)
                (planCheckpointName plan)
                registerTxId
                (planCheckpointAddress plan)
        pure RegistrationResult{resultPremintTxId = premintTxId, resultRegisterTxId = registerTxId}

plutusDataJson :: Data -> Value
plutusDataJson = \case
    Constr constructor fields ->
        object
            [ "constructor" .= constructor
            , "fields" .= map plutusDataJson fields
            ]
    Map pairs ->
        object
            [ "map"
                .= [ object
                        [ "k" .= plutusDataJson key
                        , "v" .= plutusDataJson value
                        ]
                   | (key, value) <- pairs
                   ]
            ]
    List values -> object ["list" .= map plutusDataJson values]
    I value -> object ["int" .= value]
    B bytes -> object ["bytes" .= hexText bytes]

plutusDataFromJson :: Value -> Either String Data
plutusDataFromJson = parseEither parsePlutusData

parsePlutusData :: Value -> Parser Data
parsePlutusData = withObject "detailed Plutus data" $ \o -> do
    constructor <- o .:? "constructor"
    fields <- o .:? "fields"
    mapValues <- o .:? "map"
    listValues <- o .:? "list"
    integer <- o .:? "int"
    bytes <- o .:? "bytes"
    case ( constructor
         , fields
         , mapValues
         , listValues
         , integer
         , bytes
         ) of
        (Just tag, Just values, Nothing, Nothing, Nothing, Nothing) ->
            Constr tag <$> traverse parsePlutusData values
        (Nothing, Nothing, Just pairs, Nothing, Nothing, Nothing) ->
            Map <$> traverse parsePair pairs
        (Nothing, Nothing, Nothing, Just values, Nothing, Nothing) ->
            List <$> traverse parsePlutusData values
        (Nothing, Nothing, Nothing, Nothing, Just value, Nothing) ->
            pure (I value)
        (Nothing, Nothing, Nothing, Nothing, Nothing, Just encoded) ->
            B <$> parseHexBytes encoded
        _ -> fail "detailed Plutus data has an invalid or ambiguous shape"
  where
    parsePair = withObject "Plutus map pair" $ \pair ->
        (,)
            <$> (pair .: "k" >>= parsePlutusData)
            <*> (pair .: "v" >>= parsePlutusData)
    parseHexBytes encoded =
        either
            (const $ fail "Plutus bytes are not hexadecimal")
            pure
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)

registrationFiles :: FilePath -> RegistrationFiles
registrationFiles directory =
    RegistrationFiles
        { filesPremintRedeemer = directory </> "premint-redeemer.json"
        , filesCheckpointRedeemer = directory </> "checkpoint-redeemer.json"
        , filesProofBurnRedeemer = directory </> "proof-burn-redeemer.json"
        , filesObserverRedeemer = directory </> "observer-redeemer.json"
        , filesLifecycleCertificateRedeemer =
            directory </> "lifecycle-certificate-redeemer.json"
        , filesLifecycleCertificate =
            directory </> "lifecycle-registration.cert"
        , filesCheckpointDatum = directory </> "checkpoint-datum.json"
        , filesPremintBody = directory </> "premint.body"
        , filesPremintSigned = directory </> "premint.signed"
        , filesRegisterBody = directory </> "register.body"
        , filesRegisterSigned = directory </> "register.signed"
        }

writeRegistrationFiles :: RegistrationFiles -> RegistrationPlan -> IO ()
writeRegistrationFiles files plan = do
    Aeson.encodeFile (filesPremintRedeemer files) (planPremintRedeemer plan)
    Aeson.encodeFile (filesCheckpointRedeemer files) (planCheckpointRedeemer plan)
    Aeson.encodeFile (filesProofBurnRedeemer files) (planProofBurnRedeemer plan)
    Aeson.encodeFile (filesObserverRedeemer files) (planObserverRedeemer plan)
    Aeson.encodeFile
        (filesLifecycleCertificateRedeemer files)
        (planLifecycleCertificateRedeemer plan)
    Aeson.encodeFile (filesCheckpointDatum files) (planCheckpointDatum plan)

queryWallet ::
    RegistrationRunnerConfig ->
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

lifecycleRegistrationRequired ::
    RegistrationRunnerConfig ->
    RegistrationPlan ->
    FilePath ->
    IO Bool
lifecycleRegistrationRequired config plan output = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "stake-address-info"
            , "--address"
            , T.unpack (planLifecycleRewardAddress plan)
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
                (fail . ("cannot decode lifecycle stake address info: " <>))
                pure
    pure (null (accounts :: [Value]))

writeLifecycleCertificate ::
    RegistrationRunnerConfig ->
    RegistrationPlan ->
    RegistrationFiles ->
    FilePath ->
    IO ()
writeLifecycleCertificate config plan files parametersFile = do
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
            , T.unpack (planLifecycleRewardAddress plan)
            , "--key-reg-deposit-amt"
            , show (protocolStakeAddressDeposit parameters)
            , "--out-file"
            , filesLifecycleCertificate files
            ]
    pure ()

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
    RegistrationRunnerConfig ->
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

runCardanoCli :: RegistrationRunnerConfig -> [String] -> IO String
runCardanoCli config arguments = do
    (exitCode, output, err) <-
        readProcessWithExitCode (runnerCardanoCli config) arguments ""
    case exitCode of
        ExitSuccess -> pure output
        ExitFailure code ->
            fail (renderCardanoCliFailure code err output)

{- | Keep validator failures actionable without echoing cardano-cli's opaque,
multi-kilobyte base64 script dump. Other failures remain verbatim.
-}
renderCardanoCliFailure :: Int -> String -> String -> String
renderCardanoCliFailure code err output =
    unlines
        [ "cardano-cli failed with exit " <> show code
        , "stderr: " <> summariseValidatorFailure err
        , "stdout: " <> output
        ]

summariseValidatorFailure :: String -> String
summariseValidatorFailure err
    | "scripts have execution failures" `T.isInfixOf` rendered =
        T.unpack . T.unlines . filter isMachineFact . T.lines $ rendered
    | otherwise = err
  where
    rendered = T.pack err
    isMachineFact line =
        any
            (`T.isPrefixOf` T.stripStart line)
            [ "Command failed:"
            , "Error: The following scripts have execution failures:"
            , "the script for policyId "
            , "Script hash:"
            , "Script language:"
            , "Protocol version:"
            , "ScriptInfo:"
            , "Script evaluation error:"
            , "The machine terminated because of an error"
            , "Caused by:"
            ]

waitForAsset ::
    RegistrationRunnerConfig ->
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

assetId :: Text -> Text -> String
assetId policyId assetName =
    T.unpack policyId <> "." <> T.unpack assetName

scriptNamed :: Text -> Manifest -> Either String ScriptEntry
scriptNamed name manifest =
    case filter ((== name) . scriptName) (manifestScripts manifest) of
        [script] -> Right script
        _ -> Left ("manifest script is not unique: " <> T.unpack name)

renderReference :: Reference -> Text
renderReference reference =
    referenceTxId reference <> "#" <> T.pack (show $ referenceIndex reference)

hexText :: ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

decodeHex28 :: String -> Text -> Either String ByteString
decodeHex28 label encoded = do
    bytes <-
        either
            (const $ Left $ label <> " is not hexadecimal")
            Right
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == 28) $
        Left (label <> " is not 28 bytes")
    pure bytes

decodeHexUnsafe :: Text -> ByteString
decodeHexUnsafe encoded =
    either
        (error . ("mkRegistrationPlan: impossible manifest hex: " <>))
        id
        (convertFromBase Base16 $ TE.encodeUtf8 encoded)

rewardAddress :: ByteString -> Either String Text
rewardAddress raw = do
    hash <-
        maybe
            (Left "observer-lifecycle script hash is not a ledger hash")
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
                        (AccountId $ ScriptHashObj hash)
            )
