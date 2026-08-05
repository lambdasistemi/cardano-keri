{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.EndpointBoardTransaction
Description : Build and settle endpoint-board post, update, and retire actions

The plans in this module are the off-chain mirror of the frozen board
validator. A post mints one raw-witness-key marker. An update spends and
recreates the exact marker value. A retire burns the marker and preserves the
complete lovelace deposit in one datum-free refund output.
-}
module Cardano.KERI.Deployment.EndpointBoardTransaction (
    BoardPostPlan (..),
    BoardUpdatePlan (..),
    BoardRetirePlan (..),
    BoardRunnerConfig (..),
    BoardFiles (..),
    BoardResult (..),
    selectBoardEntry,
    mkBoardPostPlan,
    mkBoardUpdatePlan,
    mkBoardRetirePlan,
    boardPostBuildArguments,
    boardUpdateBuildArguments,
    boardRetireBuildArguments,
    runBoardPostTransaction,
    runBoardUpdateTransaction,
    runBoardRetireTransaction,
) where

import Cardano.KERI.AID.Checkpoint.Close (
    AddressCredential (..),
    FullAddress (..),
 )
import Cardano.KERI.AID.Checkpoint.Wire (asPlcData)
import Cardano.KERI.Deployment.ChainIndex (
    ChainAssetUtxo (..),
    ChainTransactionUtxos (..),
    KoiosToken,
    queryAssetUtxos,
    queryTransactionUtxos,
 )
import Cardano.KERI.Deployment.Close (decodeRefundAddress)
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    EndpointRecord (..),
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    endpointBoardManifestSchema,
    frozenEndpointBoardAddress,
    frozenEndpointBoardPolicyId,
 )
import Cardano.KERI.Deployment.LegacyCardanoCli (renderCardanoCliFailure)
import Cardano.KERI.Deployment.Manifest (
    NetworkInfo (..),
    Reference (..),
 )
import Cardano.KERI.Deployment.Publisher (parseTransactionId)
import Cardano.KERI.Deployment.Registration (plutusDataJson)
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
    convertToBase,
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
import PlutusCore.Data (Data (..))
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

data BoardPostPlan = BoardPostPlan
    { boardPostPolicy :: !Text
    , boardPostAddress :: !Text
    , boardPostReference :: !Text
    , boardPostAssetName :: !Text
    , boardPostDepositLovelace :: !Integer
    , boardPostOutput :: !Text
    , boardPostDatum :: !Value
    , boardPostMintRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data BoardUpdatePlan = BoardUpdatePlan
    { boardUpdatePolicy :: !Text
    , boardUpdateAddress :: !Text
    , boardUpdateReference :: !Text
    , boardUpdateSpentReference :: !Text
    , boardUpdateAssetName :: !Text
    , boardUpdateDepositLovelace :: !Integer
    , boardUpdateOwnerKeyHash :: !Text
    , boardUpdateOutput :: !Text
    , boardUpdateDatum :: !Value
    , boardUpdateSpendRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data BoardRetirePlan = BoardRetirePlan
    { boardRetirePolicy :: !Text
    , boardRetireReference :: !Text
    , boardRetireSpentReference :: !Text
    , boardRetireAssetName :: !Text
    , boardRetireOwnerKeyHash :: !Text
    , boardRetireRefundAddress :: !Text
    , boardRetireRefundLovelace :: !Integer
    , boardRetireRefundOutput :: !Text
    , boardRetireSpendRedeemer :: !Value
    , boardRetireMintRedeemer :: !Value
    }
    deriving stock (Show, Eq)

data BoardRunnerConfig = BoardRunnerConfig
    { boardRunnerCardanoCli :: !FilePath
    , boardRunnerNetworkMagic :: !Int
    , boardRunnerNodeSocket :: !FilePath
    , boardRunnerFundingAddress :: !Text
    , boardRunnerChangeAddress :: !Text
    , boardRunnerSigningKeyFile :: !FilePath
    , boardRunnerKoiosUrl :: !Text
    , boardRunnerKoiosToken :: !(Maybe KoiosToken)
    , boardRunnerTimeoutSeconds :: !Int
    }
    deriving stock (Show, Eq)

data BoardFiles = BoardFiles
    { boardFilesDatum :: !FilePath
    , boardFilesSpendRedeemer :: !FilePath
    , boardFilesMintRedeemer :: !FilePath
    , boardFilesBody :: !FilePath
    , boardFilesSigned :: !FilePath
    }
    deriving stock (Show, Eq)

newtype BoardResult = BoardResult
    { boardResultTxId :: Text
    }
    deriving stock (Show, Eq)

data WalletUtxo = WalletUtxo
    { walletLovelace :: !Integer
    , walletReferenceScript :: !(Maybe Value)
    , walletAssetCount :: !Int
    }
    deriving stock (Show)

instance FromJSON WalletUtxo where
    parseJSON = withObject "WalletUtxo" $ \objectValue -> do
        value <- objectValue .: "value"
        (walletLovelace, walletAssetCount) <-
            withObject "WalletValue" parseWalletValue value
        walletReferenceScript <- objectValue .:? "referenceScript"
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

-- | Resolve one current witness record without hiding ratified duplicates.
selectBoardEntry ::
    Maybe Text ->
    BS.ByteString ->
    [BoardEntry] ->
    Either String BoardEntry
selectBoardEntry selectedReference witnessKey entries =
    case selectedReference of
        Just reference ->
            case filter ((== reference) . boardEntryReference) matching of
                [entry] -> Right entry
                [] ->
                    Left
                        "the selected board output is not a current record for \
                        \this witness"
                _ -> Left "the selected board output reference is ambiguous"
        Nothing ->
            case matching of
                [entry] -> Right entry
                [] -> Left "the witness has no current board record"
                _ ->
                    Left
                        "the witness has duplicate current board records; pass \
                        \--board-out-ref TXID#INDEX to select one explicitly"
  where
    matching =
        filter ((== witnessKey) . boardWitnessKey) entries

mkBoardPostPlan ::
    EndpointBoardManifest ->
    Text ->
    Integer ->
    EndpointRecord ->
    Either String BoardPostPlan
mkBoardPostPlan manifest ownerAddress deposit record = do
    info <- validatedBoardInfo manifest
    when (deposit <= 0) $
        Left "deposit-lovelace must be positive"
    owner <- paymentKeyHash ownerAddress
    let boardPostPolicy = endpointBoardPolicyId info
        boardPostAddress = endpointBoardAddress info
        boardPostReference = renderReference (endpointBoardReference info)
        boardPostAssetName = hexText (endpointWitnessKey record)
        boardPostDepositLovelace = deposit
        boardPostOutput =
            markerOutput
                boardPostAddress
                deposit
                boardPostPolicy
                boardPostAssetName
        boardPostDatum =
            endpointDatum owner record
        boardPostMintRedeemer = plutusDataJson (Constr 0 [])
    pure BoardPostPlan{..}

mkBoardUpdatePlan ::
    EndpointBoardManifest ->
    Text ->
    BoardEntry ->
    EndpointRecord ->
    Either String BoardUpdatePlan
mkBoardUpdatePlan manifest ownerAddress entry record = do
    info <- validatedBoardInfo manifest
    owner <- paymentKeyHash ownerAddress
    unless (owner == boardOwnerKeyHash entry) $
        Left "funding address payment key does not own the selected board record"
    unless (endpointWitnessKey record == boardWitnessKey entry) $
        Left "updated endpoint record belongs to a different witness"
    when (boardLovelace entry <= 0) $
        Left "selected board record has a non-positive deposit"
    let boardUpdatePolicy = endpointBoardPolicyId info
        boardUpdateAddress = endpointBoardAddress info
        boardUpdateReference = renderReference (endpointBoardReference info)
        boardUpdateSpentReference = boardEntryReference entry
        boardUpdateAssetName = hexText (boardWitnessKey entry)
        boardUpdateDepositLovelace = boardLovelace entry
        boardUpdateOwnerKeyHash = hexText owner
        boardUpdateOutput =
            markerOutput
                boardUpdateAddress
                boardUpdateDepositLovelace
                boardUpdatePolicy
                boardUpdateAssetName
        boardUpdateDatum = endpointDatum owner record
        boardUpdateSpendRedeemer = plutusDataJson (Constr 0 [])
    pure BoardUpdatePlan{..}

mkBoardRetirePlan ::
    EndpointBoardManifest ->
    Text ->
    Text ->
    BoardEntry ->
    Either String BoardRetirePlan
mkBoardRetirePlan manifest ownerAddress refundAddress entry = do
    info <- validatedBoardInfo manifest
    owner <- paymentKeyHash ownerAddress
    unless (owner == boardOwnerKeyHash entry) $
        Left "funding address payment key does not own the selected board record"
    refund <- decodeRefundAddress refundAddress
    when (boardLovelace entry <= 0) $
        Left "selected board record has a non-positive deposit"
    let boardRetirePolicy = endpointBoardPolicyId info
        boardRetireReference = renderReference (endpointBoardReference info)
        boardRetireSpentReference = boardEntryReference entry
        boardRetireAssetName = hexText (boardWitnessKey entry)
        boardRetireOwnerKeyHash = hexText owner
        boardRetireRefundAddress = refundAddress
        boardRetireRefundLovelace = boardLovelace entry
        boardRetireRefundOutput =
            refundAddress <> "+" <> T.pack (show boardRetireRefundLovelace)
        boardRetireSpendRedeemer =
            plutusDataJson (Constr 1 [asPlcData refund])
        boardRetireMintRedeemer = plutusDataJson (Constr 1 [])
    pure BoardRetirePlan{..}

boardPostBuildArguments ::
    BoardRunnerConfig ->
    BoardPostPlan ->
    BoardFiles ->
    Text ->
    Text ->
    [String]
boardPostBuildArguments config plan files funding collateral =
    transactionPrefix funding collateral
        <> [ "--tx-out"
           , T.unpack (boardPostOutput plan)
           , "--tx-out-inline-datum-file"
           , boardFilesDatum files
           , "--change-address"
           , T.unpack (boardRunnerChangeAddress config)
           , "--mint"
           , "1 "
                <> assetId
                    (boardPostPolicy plan)
                    (boardPostAssetName plan)
           ]
        <> mintReferenceArguments
            (boardPostReference plan)
            (boardPostPolicy plan)
            files
        <> transactionSuffix config files
  where
    transactionPrefix = commonTransactionPrefix config

boardUpdateBuildArguments ::
    BoardRunnerConfig ->
    BoardUpdatePlan ->
    BoardFiles ->
    Text ->
    Text ->
    [String]
boardUpdateBuildArguments config plan files funding collateral =
    spendPrefix
        config
        files
        (boardUpdateSpentReference plan)
        (boardUpdateReference plan)
        funding
        collateral
        <> [ "--tx-out"
           , T.unpack (boardUpdateOutput plan)
           , "--tx-out-inline-datum-file"
           , boardFilesDatum files
           , "--change-address"
           , T.unpack (boardRunnerChangeAddress config)
           , "--required-signer-hash"
           , T.unpack (boardUpdateOwnerKeyHash plan)
           ]
        <> transactionSuffix config files

boardRetireBuildArguments ::
    BoardRunnerConfig ->
    BoardRetirePlan ->
    BoardFiles ->
    Text ->
    Text ->
    [String]
boardRetireBuildArguments config plan files funding collateral =
    spendPrefix
        config
        files
        (boardRetireSpentReference plan)
        (boardRetireReference plan)
        funding
        collateral
        <> [ "--tx-out"
           , T.unpack (boardRetireRefundOutput plan)
           , "--change-address"
           , T.unpack (boardRunnerChangeAddress config)
           , "--mint"
           , "-1 "
                <> assetId
                    (boardRetirePolicy plan)
                    (boardRetireAssetName plan)
           ]
        <> mintReferenceArguments
            (boardRetireReference plan)
            (boardRetirePolicy plan)
            files
        <> [ "--required-signer-hash"
           , T.unpack (boardRetireOwnerKeyHash plan)
           ]
        <> transactionSuffix config files

runBoardPostTransaction ::
    BoardRunnerConfig ->
    BoardPostPlan ->
    IO BoardResult
runBoardPostTransaction config plan =
    runBoardTransaction
        config
        (boardPostDepositLovelace plan + 5_000_000)
        "endpoint-board post"
        (boardPostBuildArguments config plan)
        ( \files -> do
            Aeson.encodeFile (boardFilesDatum files) (boardPostDatum plan)
            Aeson.encodeFile
                (boardFilesMintRedeemer files)
                (boardPostMintRedeemer plan)
        )
        ( waitForBoardOutput
            config
            (boardPostPolicy plan)
            (boardPostAssetName plan)
            (boardPostAddress plan)
        )

runBoardUpdateTransaction ::
    BoardRunnerConfig ->
    BoardUpdatePlan ->
    IO BoardResult
runBoardUpdateTransaction config plan =
    runBoardTransaction
        config
        5_000_000
        "endpoint-board update"
        (boardUpdateBuildArguments config plan)
        ( \files -> do
            Aeson.encodeFile (boardFilesDatum files) (boardUpdateDatum plan)
            Aeson.encodeFile
                (boardFilesSpendRedeemer files)
                (boardUpdateSpendRedeemer plan)
        )
        ( waitForBoardOutput
            config
            (boardUpdatePolicy plan)
            (boardUpdateAssetName plan)
            (boardUpdateAddress plan)
        )

runBoardRetireTransaction ::
    BoardRunnerConfig ->
    BoardRetirePlan ->
    IO BoardResult
runBoardRetireTransaction config plan = do
    when
        (boardRunnerChangeAddress config == boardRetireRefundAddress plan)
        ( fail
            "change address must differ from the exact board retire refund target"
        )
    runBoardTransaction
        config
        5_000_000
        "endpoint-board retire"
        (boardRetireBuildArguments config plan)
        ( \files -> do
            Aeson.encodeFile
                (boardFilesSpendRedeemer files)
                (boardRetireSpendRedeemer plan)
            Aeson.encodeFile
                (boardFilesMintRedeemer files)
                (boardRetireMintRedeemer plan)
        )
        ( waitForBoardRetirement
            config
            (boardRetirePolicy plan)
            (boardRetireAssetName plan)
            (boardRetireSpentReference plan)
        )

runBoardTransaction ::
    BoardRunnerConfig ->
    Integer ->
    String ->
    (BoardFiles -> Text -> Text -> [String]) ->
    (BoardFiles -> IO ()) ->
    (Text -> IO ()) ->
    IO BoardResult
runBoardTransaction config minimumFunding label buildArguments writeFiles wait = do
    validateRunner config
    withSystemTempDirectory "ckeri-board" $ \directory -> do
        let files = boardFiles directory
        writeFiles files
        wallet <- queryWallet config (directory </> "wallet.json")
        (funding, collateral) <-
            selectFundingPair minimumFunding label wallet
        _ <-
            runCardanoCli config (buildArguments files funding collateral)
        txId <-
            signSubmit
                config
                (boardFilesBody files)
                (boardFilesSigned files)
        wait txId
        pure (BoardResult txId)

validateRunner :: BoardRunnerConfig -> IO ()
validateRunner config = do
    when (boardRunnerTimeoutSeconds config <= 0) $
        fail "timeout-seconds must be positive"
    when (boardRunnerNetworkMagic config /= 1) $
        fail "endpoint-board transactions are frozen to preprod network magic 1"

boardFiles :: FilePath -> BoardFiles
boardFiles directory =
    BoardFiles
        { boardFilesDatum = directory </> "datum.json"
        , boardFilesSpendRedeemer = directory </> "spend-redeemer.json"
        , boardFilesMintRedeemer = directory </> "mint-redeemer.json"
        , boardFilesBody = directory </> "board.body"
        , boardFilesSigned = directory </> "board.signed"
        }

queryWallet ::
    BoardRunnerConfig ->
    FilePath ->
    IO (Map Text WalletUtxo)
queryWallet config output = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "utxo"
            , "--address"
            , T.unpack (boardRunnerFundingAddress config)
            , "--testnet-magic"
            , show (boardRunnerNetworkMagic config)
            , "--socket-path"
            , boardRunnerNodeSocket config
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
    BoardRunnerConfig ->
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
            , boardRunnerSigningKeyFile config
            , "--testnet-magic"
            , show (boardRunnerNetworkMagic config)
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
            , show (boardRunnerNetworkMagic config)
            , "--socket-path"
            , boardRunnerNodeSocket config
            ]
    pure txId

runCardanoCli :: BoardRunnerConfig -> [String] -> IO String
runCardanoCli config arguments = do
    (exitCode, output, err) <-
        readProcessWithExitCode (boardRunnerCardanoCli config) arguments ""
    case exitCode of
        ExitSuccess -> pure output
        ExitFailure code ->
            fail (renderCardanoCliFailure code err output)

waitForBoardOutput ::
    BoardRunnerConfig ->
    Text ->
    Text ->
    Text ->
    Text ->
    IO ()
waitForBoardOutput config policy assetName expectedAddress txId =
    retryUntil config description $ do
        outputs <-
            queryAssetUtxos
                (boardRunnerKoiosUrl config)
                (boardRunnerKoiosToken config)
                policy
                assetName
        pure $
            any
                ( \output ->
                    chainAssetTxId output == txId
                        && chainAssetAddress output == expectedAddress
                )
                outputs
  where
    description =
        "settled endpoint-board output "
            <> T.unpack txId
            <> " for "
            <> T.unpack policy
            <> "."
            <> T.unpack assetName

waitForBoardRetirement ::
    BoardRunnerConfig ->
    Text ->
    Text ->
    Text ->
    Text ->
    IO ()
waitForBoardRetirement config policy assetName spentReference txId =
    retryUntil config description $ do
        outputs <-
            queryAssetUtxos
                (boardRunnerKoiosUrl config)
                (boardRunnerKoiosToken config)
                policy
                assetName
        transaction <-
            queryTransactionUtxos
                (boardRunnerKoiosUrl config)
                (boardRunnerKoiosToken config)
                [txId]
        pure $
            not (any ((== spentReference) . boardUtxoReference) outputs)
                && any ((== txId) . chainTransactionTxId) transaction
  where
    description =
        "settled endpoint-board retirement "
            <> T.unpack txId
            <> " consuming "
            <> T.unpack spentReference

retryUntil ::
    BoardRunnerConfig ->
    String ->
    IO Bool ->
    IO ()
retryUntil config description predicate = do
    started <- getCurrentTime
    go started
  where
    go started = do
        result <- try predicate
        case result of
            Right True -> pure ()
            Right False -> retry started
            Left (_ :: SomeException) -> retry started
    retry :: UTCTime -> IO ()
    retry started = do
        now <- getCurrentTime
        if diffUTCTime now started
            >= fromIntegral (boardRunnerTimeoutSeconds config)
            then fail ("timed out waiting for " <> description)
            else threadDelay 5_000_000 >> go started

validatedBoardInfo ::
    EndpointBoardManifest ->
    Either String EndpointBoardInfo
validatedBoardInfo manifest = do
    unless
        ( endpointBoardManifestSchemaVersion manifest
            == endpointBoardManifestSchema
        )
        (Left "endpoint-board manifest schema is not frozen V1")
    unless
        (endpointBoardManifestNetwork manifest == NetworkInfo "preprod" 1)
        (Left "endpoint-board manifest is not preprod network magic 1")
    let info = endpointBoardManifestInfo manifest
    unless
        ( endpointBoardPolicyId info == frozenEndpointBoardPolicyId
            && endpointBoardAddress info == frozenEndpointBoardAddress
        )
        (Left "endpoint-board manifest does not name the frozen policy and address")
    pure info

paymentKeyHash :: Text -> Either String BS.ByteString
paymentKeyHash address = do
    decoded <- decodeRefundAddress address
    case faPaymentCredential decoded of
        VerificationKeyCredential keyHash -> pure keyHash
        ScriptCredential _ ->
            Left "board ownership requires a Cardano payment verification key"

endpointDatum :: BS.ByteString -> EndpointRecord -> Value
endpointDatum owner record =
    plutusDataJson $
        Constr
            0
            [ B (endpointWitnessKey record)
            , B (endpointEventBytes record)
            , B (endpointSignature record)
            , B owner
            ]

commonTransactionPrefix ::
    BoardRunnerConfig ->
    Text ->
    Text ->
    [String]
commonTransactionPrefix _config funding collateral =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack funding
    , "--tx-in-collateral"
    , T.unpack collateral
    ]

spendPrefix ::
    BoardRunnerConfig ->
    BoardFiles ->
    Text ->
    Text ->
    Text ->
    Text ->
    [String]
spendPrefix config files spent reference funding collateral =
    [ "conway"
    , "transaction"
    , "build"
    , "--tx-in"
    , T.unpack spent
    , "--spending-tx-in-reference"
    , T.unpack reference
    , "--spending-plutus-script-v3"
    , "--spending-reference-tx-in-inline-datum-present"
    , "--spending-reference-tx-in-redeemer-file"
    , boardFilesSpendRedeemer files
    ]
        <> drop 3 (commonTransactionPrefix config funding collateral)

mintReferenceArguments ::
    Text ->
    Text ->
    BoardFiles ->
    [String]
mintReferenceArguments reference policy files =
    [ "--mint-tx-in-reference"
    , T.unpack reference
    , "--mint-plutus-script-v3"
    , "--mint-reference-tx-in-redeemer-file"
    , boardFilesMintRedeemer files
    , "--policy-id"
    , T.unpack policy
    ]

transactionSuffix ::
    BoardRunnerConfig ->
    BoardFiles ->
    [String]
transactionSuffix config files =
    [ "--testnet-magic"
    , show (boardRunnerNetworkMagic config)
    , "--socket-path"
    , boardRunnerNodeSocket config
    , "--out-file"
    , boardFilesBody files
    ]

markerOutput :: Text -> Integer -> Text -> Text -> Text
markerOutput address lovelace policy assetName =
    address
        <> "+"
        <> T.pack (show lovelace)
        <> " + 1 "
        <> policy
        <> "."
        <> assetName

renderReference :: Reference -> Text
renderReference reference =
    referenceTxId reference <> "#" <> T.pack (show $ referenceIndex reference)

boardEntryReference :: BoardEntry -> Text
boardEntryReference entry =
    boardTxId entry <> "#" <> T.pack (show $ boardIndex entry)

boardUtxoReference :: ChainAssetUtxo -> Text
boardUtxoReference output =
    chainAssetTxId output
        <> "#"
        <> T.pack (show $ chainAssetIndex output)

assetId :: Text -> Text -> String
assetId policy assetName =
    T.unpack policy <> "." <> T.unpack assetName

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16
