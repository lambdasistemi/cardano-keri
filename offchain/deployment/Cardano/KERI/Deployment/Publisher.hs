{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.Publisher
Description : Publish applied scripts through cardano-cli and wait for settlement
-}
module Cardano.KERI.Deployment.Publisher (
    PublishConfig (..),
    publishScripts,
    parseTransactionId,
    writeScriptEnvelope,
) where

import Cardano.KERI.Deployment.ChainIndex (
    ChainReference (..),
    KoiosToken,
    queryReferenceScripts,
 )
import Cardano.KERI.Deployment.Manifest (Reference (..))
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    scriptHashText,
 )
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
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
import Data.Bits (shiftR)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Char (isHexDigit)
import Data.List (maximumBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (
    UTCTime,
    diffUTCTime,
    getCurrentTime,
 )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)

data PublishConfig = PublishConfig
    { publishCardanoCli :: FilePath
    , publishNetworkMagic :: Int
    , publishNodeSocket :: FilePath
    , publishFundingAddress :: Text
    , publishSigningKeyFile :: FilePath
    , publishReferenceLovelace :: Integer
    , publishKoiosUrl :: Text
    , publishKoiosToken :: Maybe KoiosToken
    , publishTimeoutSeconds :: Int
    }
    deriving stock (Show, Eq)

data WalletUtxo = WalletUtxo
    { walletLovelace :: Integer
    , walletReferenceScript :: Maybe Value
    }
    deriving stock (Show)

newtype TransactionIdOutput = TransactionIdOutput
    { transactionIdOutput :: Text
    }

instance FromJSON WalletUtxo where
    parseJSON = withObject "WalletUtxo" $ \o -> do
        value <- o .: "value"
        walletLovelace <- withObject "WalletValue" (.: "lovelace") value
        walletReferenceScript <- o .:? "referenceScript"
        pure WalletUtxo{..}

instance FromJSON TransactionIdOutput where
    parseJSON = withObject "TransactionIdOutput" $ \o ->
        TransactionIdOutput <$> o .: "txhash"

publishScripts ::
    PublishConfig ->
    [ScriptArtifact] ->
    IO [(Text, Reference)]
publishScripts config artifacts =
    withSystemTempDirectory "ckeri-deploy" $ \directory ->
        traverse (publishOne config directory) artifacts

publishOne ::
    PublishConfig ->
    FilePath ->
    ScriptArtifact ->
    IO (Text, Reference)
publishOne config directory artifact = do
    let name = T.unpack (artifactName artifact)
        envelope = directory </> name <> ".plutus"
        queryOutput = directory </> name <> "-wallet.json"
        txBody = directory </> name <> ".body"
        signedTx = directory </> name <> ".signed"
        scriptHash = scriptHashText (artifactScriptHash artifact)
    writeScriptEnvelope envelope artifact
    txIn <- queryLargestPlainUtxo config queryOutput
    _ <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "build"
            , "--tx-in"
            , T.unpack txIn
            , "--tx-out"
            , T.unpack (publishFundingAddress config)
                <> "+"
                <> show (publishReferenceLovelace config)
            , "--tx-out-reference-script-file"
            , envelope
            , "--change-address"
            , T.unpack (publishFundingAddress config)
            , "--testnet-magic"
            , show (publishNetworkMagic config)
            , "--socket-path"
            , publishNodeSocket config
            , "--out-file"
            , txBody
            ]
    _ <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "sign"
            , "--tx-body-file"
            , txBody
            , "--signing-key-file"
            , publishSigningKeyFile config
            , "--testnet-magic"
            , show (publishNetworkMagic config)
            , "--out-file"
            , signedTx
            ]
    txIdOutput <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "txid"
            , "--tx-file"
            , signedTx
            ]
    txId <-
        either
            (fail . (("cardano-cli returned an invalid transaction id for " <> name <> ": ") <>))
            pure
            (parseTransactionId txIdOutput)
    _ <-
        runCardanoCli
            config
            [ "conway"
            , "transaction"
            , "submit"
            , "--tx-file"
            , signedTx
            , "--testnet-magic"
            , show (publishNetworkMagic config)
            , "--socket-path"
            , publishNodeSocket config
            ]
    reference <- waitForReference config scriptHash txId
    putStrLn $
        "deployed "
            <> name
            <> " hash="
            <> T.unpack scriptHash
            <> " reference="
            <> T.unpack (referenceTxId reference)
            <> "#"
            <> show (referenceIndex reference)
    pure (artifactName artifact, reference)

queryLargestPlainUtxo :: PublishConfig -> FilePath -> IO Text
queryLargestPlainUtxo config output = do
    _ <-
        runCardanoCli
            config
            [ "query"
            , "utxo"
            , "--address"
            , T.unpack (publishFundingAddress config)
            , "--testnet-magic"
            , show (publishNetworkMagic config)
            , "--socket-path"
            , publishNodeSocket config
            , "--out-file"
            , output
            ]
    wallet <-
        eitherDecodeFileStrict' output
            >>= either (fail . ("cannot decode funding UTxOs: " <>)) pure
    let candidates =
            [ (txIn, utxo)
            | (txIn, utxo) <- Map.toList (wallet :: Map Text WalletUtxo)
            , isNothing (walletReferenceScript utxo)
            , walletLovelace utxo
                > publishReferenceLovelace config + 2_000_000
            ]
    case candidates of
        [] -> fail "no plain funding UTxO can cover the reference output and fee"
        _ ->
            pure . fst $
                maximumBy (comparing $ walletLovelace . snd) candidates

runCardanoCli :: PublishConfig -> [String] -> IO String
runCardanoCli config arguments = do
    (exitCode, output, err) <-
        readProcessWithExitCode (publishCardanoCli config) arguments ""
    case exitCode of
        ExitSuccess -> pure output
        ExitFailure code ->
            fail $
                unlines
                    [ "cardano-cli failed with exit " <> show code
                    , "stderr: " <> err
                    , "stdout: " <> output
                    ]

waitForReference :: PublishConfig -> Text -> Text -> IO Reference
waitForReference config scriptHash txId = do
    started <- getCurrentTime
    go started
  where
    go started = do
        result <-
            try $
                queryReferenceScripts
                    (publishKoiosUrl config)
                    (publishKoiosToken config)
                    [scriptHash]
        case result of
            Right chainReferences ->
                case [ Reference (chainTxId reference) (chainIndex reference)
                     | reference <- chainReferences
                     , chainScriptHash reference == scriptHash
                     , chainTxId reference == txId
                     ] of
                    reference : _ -> pure reference
                    [] -> retry started
            Left (_ :: SomeException) -> retry started
    retry :: UTCTime -> IO Reference
    retry started = do
        now <- getCurrentTime
        if diffUTCTime now started
            >= fromIntegral (publishTimeoutSeconds config)
            then
                fail $
                    "timed out waiting for unspent reference "
                        <> T.unpack txId
                        <> " with script hash "
                        <> T.unpack scriptHash
            else threadDelay 5_000_000 >> go started

writeScriptEnvelope :: FilePath -> ScriptArtifact -> IO ()
writeScriptEnvelope path artifact =
    Aeson.encodeFile path $
        object
            [ "type" .= ("PlutusScriptV3" :: Text)
            , "description"
                .= ("cardano-keri M1 " <> artifactName artifact)
            , "cborHex"
                .= hexText
                    (cborByteString $ SBS.fromShort $ artifactProgram artifact)
            ]

cborByteString :: BS.ByteString -> BS.ByteString
cborByteString bytes
    | lengthBytes < 24 =
        BS.cons (0x40 + fromIntegral lengthBytes) bytes
    | lengthBytes <= 0xff =
        BS.pack [0x58, fromIntegral lengthBytes] <> bytes
    | lengthBytes <= 0xffff =
        BS.pack
            [ 0x59
            , fromIntegral (lengthBytes `shiftR` 8)
            , fromIntegral lengthBytes
            ]
            <> bytes
    | lengthBytes <= 0xffff_ffff =
        BS.pack
            [ 0x5a
            , fromIntegral (lengthBytes `shiftR` 24)
            , fromIntegral (lengthBytes `shiftR` 16)
            , fromIntegral (lengthBytes `shiftR` 8)
            , fromIntegral lengthBytes
            ]
            <> bytes
    | otherwise = error "cborByteString: script is too large"
  where
    lengthBytes = BS.length bytes

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

parseTransactionId :: String -> Either String Text
parseTransactionId output =
    validate $
        case Aeson.eitherDecodeStrict'
            (TE.encodeUtf8 $ T.strip $ T.pack output) of
            Right decoded -> transactionIdOutput decoded
            Left _ -> T.strip (T.pack output)
  where
    validate txId
        | T.length txId == 64 && T.all isHexDigit txId =
            Right (T.toLower txId)
        | otherwise = Left "expected 64 hexadecimal characters"
