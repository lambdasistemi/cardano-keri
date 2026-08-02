{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.CLI.Backend.EndpointSpec
Description : #177 Slice 1 T177-S1-4 endpoint contract client (RED)

(a) proves the client against the REAL @#176@ 'mkQueryApplication' over a
real Warp loopback server — this slice's live-boundary-smoke equivalent for
the endpoint contract, since unit tests alone can't prove the client and
producer actually agree on the wire shape. Both golden cases seed a real
store watermark via 'applyBatch' first (mirrors
"Cardano.KERI.Indexer.Query.ServerSpec"'s proven pattern — a cold store with
no watermark reports HTTP 503, not 200). (b) proves the client rejects
contract violations against a small hand-built stub 'Application'.
-}
module Cardano.KERI.CLI.Backend.EndpointSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.AID.CESR (qb64Aid, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (V1), CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.CLI.Backend (
    BackendError (..),
    CheckpointFields (..),
    Freshness (..),
    StatusView (..),
    runBackendCheckpointByAid,
    runBackendListCheckpoints,
    runBackendPayerUtxos,
    runBackendStatus,
 )
import Cardano.KERI.CLI.Backend.Endpoint (mkEndpointBackend)
import Cardano.KERI.Indexer.Query.Server (mkQueryApplication)
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.KERI.Indexer.Query.Types (hexTxId, qb64Witness)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), dataToBinaryData)
import Cardano.Ledger.Api.Tx.Out (datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (..))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (IndexerHandle, UtxoOp (..), applyAtSlot, withInMemoryIndexerRunner)
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent.STM (newTVarIO, readTVar)
import Data.Aeson (encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction)
import Lens.Micro ((.~))
import Network.HTTP.Types (status400, status503)
import Network.Wai (Application, responseLBS)
import Network.Wai.Handler.Warp qualified as Warp
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "endpoint backend #176 contract (T177-S1-4)" $ do
    goldenSpec
    violationSpec

-- ---------------------------------------------------------------------------
-- (a) golden path: the real producer application

goldenSpec :: Spec
goldenSpec = describe "golden path against the real mkQueryApplication" $ do
    it "an unregistered AID decodes as a closed (not-found) answer, not an error" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x04 []
            withRealServer runner $ \baseUrl -> do
                let backend = mkEndpointBackend baseUrl
                Right view <- runBackendStatus backend aidText
                svCheckpoint view `shouldBe` Nothing
                svAid view `shouldBe` aidText

    it "a populated checkpoint decodes with exact field-by-field parity" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x05 [checkpointCreate (sampleTxIn 0x30) aidY datumY]
            withRealServer runner $ \baseUrl -> do
                let backend = mkEndpointBackend baseUrl
                Right view <- runBackendStatus backend (renderAid aidY)
                svCheckpoint view `shouldBe` Just expectedFields

    it "checkpoint-by-AID reuses the strict #176 checkpoint response path" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x06 [checkpointCreate (sampleTxIn 0x30) aidY datumY]
            withRealServer runner $ \baseUrl -> do
                Right (freshness, checkpoint) <- runBackendCheckpointByAid (mkEndpointBackend baseUrl) (renderAid aidY)
                freshness `shouldBe` Freshness (Just 100) (Just 0)
                checkpoint `shouldBe` Just expectedFields

expectedFields :: CheckpointFields
expectedFields =
    CheckpointFields
        { cfTxId = hexTxId (BS.replicate 32 0x30)
        , cfOutputIndex = 0
        , cfSequence = 3
        , cfNativeSequence = 3
        , cfCurrentKeys = [TE.decodeUtf8 (qb64Verkey (BS.replicate 32 0x11))]
        , cfCurrentThreshold = Unweighted 1
        , cfWitnesses = [TE.decodeUtf8 (qb64Witness (BS.replicate 32 0x99))]
        , cfWitnessThreshold = 1
        }

withRealServer :: RunTransaction IO cf Cols op -> (Text -> IO a) -> IO a
withRealServer runner act = do
    readinessVar <- newTVarIO (readinessAt 100 100)
    let handle =
            QueryHandle
                runner
                checkpointAddress
                checkpointPolicy
                boardAddress
                (readTVar readinessVar)
    Warp.testWithApplication (pure (mkQueryApplication handle)) $ \port ->
        act ("http://127.0.0.1:" <> T.pack (show port))

checkpointPolicy :: PolicyID
checkpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just h -> h
                Nothing -> error "EndpointSpec: invalid checkpoint policy id width"

checkpointLedgerAddress :: Addr
checkpointLedgerAddress =
    let PolicyID scriptHash = checkpointPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

checkpointAddress :: Indexer.Address
checkpointAddress = Indexer.Address (serialiseAddr checkpointLedgerAddress)

boardAddress :: Indexer.Address
boardAddress =
    Indexer.Address
        ( serialiseAddr
            ( Addr
                Testnet
                ( ScriptHashObj
                    ( ScriptHash
                        ( case hashFromBytes (BS.replicate 28 0x51) of
                            Just h -> h
                            Nothing -> error "EndpointSpec: invalid board policy id width"
                        )
                    )
                )
                StakeRefNull
            )
        )

readinessAt :: Int -> Int -> Readiness
readinessAt processed tip =
    Readiness
        { rProcessedSlot = Just (Indexer.SlotNo (fromIntegral processed))
        , rTipSlot = Just (Indexer.SlotNo (fromIntegral tip))
        , rUpstream = UpstreamConnected
        , rUpdatedAt = fixedTime
        }

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 1) 0

-- ---------------------------------------------------------------------------
-- Populated-checkpoint fixture (mirrors LocalSpec.hs/Query.ServerSpec.hs)

aidY :: ByteString
aidY = BS.replicate 32 0x00

renderAid :: ByteString -> Text
renderAid = TE.decodeUtf8 . qb64Aid

datumY :: CheckpointDatumV1
datumY =
    CheckpointDatumV1
        { cdCesrAid = aidY
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = [BS.replicate 32 0x99]
        , cdToad = 1
        , cdSeq = 3
        , cdNativeSn = 3
        }

checkpointCreate :: Indexer.TxIn -> ByteString -> CheckpointDatumV1 -> UtxoOp
checkpointCreate txIn aid datum =
    UtxoCreate txIn checkpointAddress (checkpointOutput aid datum)

checkpointOutput :: ByteString -> CheckpointDatumV1 -> Indexer.TxOut
checkpointOutput aid datum =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (plutusData (V1 datum)))
  where
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            checkpointLedgerAddress
            ( MaryValue
                (Coin 5_000_000)
                ( MultiAsset $
                    Map.singleton
                        checkpointPolicy
                        (Map.singleton (AssetName . SBS.toShort $ deriveAidAssetName aid) 1)
                )
            )

inlineDatum :: PLC.Data -> Datum ConwayEra
inlineDatum datum = Datum (dataToBinaryData (Data datum))

plutusData :: (ToData a) => a -> PLC.Data
plutusData value =
    let BuiltinData datum = toBuiltinData value
     in datum

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte) 0

applyBatch :: IndexerHandle -> Int -> Word8 -> [UtxoOp] -> IO ()
applyBatch handle slot hashByte =
    applyAtSlot handle (Indexer.SlotNo (fromIntegral slot)) (blockHash hashByte)

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)

-- ---------------------------------------------------------------------------
-- (b) contract-violation rejections against a hand-built stub Application

violationSpec :: Spec
violationSpec = describe "contract-violation rejection" $ do
    it "checkpoint listing is a named unsupported capability, without another adapter" $ do
        result <- runBackendListCheckpoints (mkEndpointBackend "http://127.0.0.1:1")
        result `shouldSatisfy` isUnsupportedCapability

    it "payer UTxOs are a named unsupported capability, without another adapter" $ do
        result <-
            runBackendPayerUtxos
                (mkEndpointBackend "http://127.0.0.1:1")
                "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d"
        result `shouldSatisfy` isUnsupportedCapability

    it "HTTP 503 is a closed UpstreamUnavailable error" $
        withStubApp unavailableApp $ \baseUrl -> do
            result <- runBackendStatus (mkEndpointBackend baseUrl) aidText
            result `shouldSatisfy` isUpstreamUnavailable

    it "malformed JSON body is a closed MalformedResponse error" $
        withStubApp malformedJsonApp $ \baseUrl -> do
            result <- runBackendStatus (mkEndpointBackend baseUrl) aidText
            result `shouldSatisfy` isMalformedResponse

    it "a mismatched echoed AID is a closed MalformedResponse error" $
        withStubApp (mismatchedAidApp otherAidText) $ \baseUrl -> do
            result <- runBackendStatus (mkEndpointBackend baseUrl) aidText
            result `shouldSatisfy` isMalformedResponse

    it "a found checkpoint with a null as_of_slot is an impossible-freshness MalformedResponse" $
        withStubApp impossibleFreshnessApp $ \baseUrl -> do
            result <- runBackendStatus (mkEndpointBackend baseUrl) aidText
            result `shouldSatisfy` isMalformedResponse

isUpstreamUnavailable :: Either BackendError a -> Bool
isUpstreamUnavailable (Left (UpstreamUnavailable _)) = True
isUpstreamUnavailable _ = False

isMalformedResponse :: Either BackendError a -> Bool
isMalformedResponse (Left (MalformedResponse _)) = True
isMalformedResponse _ = False

isUnsupportedCapability :: Either BackendError a -> Bool
isUnsupportedCapability (Left (UnsupportedCapability _)) = True
isUnsupportedCapability _ = False

withStubApp :: Application -> (Text -> IO a) -> IO a
withStubApp app act =
    Warp.testWithApplication (pure app) $ \port ->
        act ("http://127.0.0.1:" <> T.pack (show port))

unavailableApp :: Application
unavailableApp _request respond =
    respond (responseLBS status503 [] "service unavailable")

malformedJsonApp :: Application
malformedJsonApp _request respond =
    respond (responseLBS status400 [] "{not json")

mismatchedAidApp :: Text -> Application
mismatchedAidApp echoedAid _request respond =
    respond $
        responseLBS
            status400
            []
            ( encode $
                object
                    [ "aid" .= echoedAid
                    , "as_of_slot" .= (100 :: Int)
                    , "tip_lag_slots" .= (0 :: Int)
                    , "checkpoint" .= (Nothing :: Maybe Int)
                    ]
            )

impossibleFreshnessApp :: Application
impossibleFreshnessApp _request respond =
    respond $
        responseLBS
            status400
            []
            ( encode $
                object
                    [ "aid" .= aidText
                    , "as_of_slot" .= (Nothing :: Maybe Int)
                    , "tip_lag_slots" .= (Nothing :: Maybe Int)
                    , "checkpoint" .= object ["tx_id" .= ("aa" :: Text)]
                    ]
            )

aidText :: Text
aidText = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

otherAidText :: Text
otherAidText = "EBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
