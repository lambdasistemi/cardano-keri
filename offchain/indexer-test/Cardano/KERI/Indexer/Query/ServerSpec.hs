{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.Query.ServerSpec
Description : #176 Slice 1 application-level contract tests (RED)

The frozen public contract from @specs\/176-query-endpoint\/spec.md@ at base
@0c11bf2@, exercised against the real 'mkQueryApplication' \/WAI 'Application'
over a real in-memory upstream indexer — never a mocked HTTP layer. Currently
red against the RED-phase stub in "Cardano.KERI.Indexer.Query.Server" (every
route answers a fixed 501); every assertion below encodes the actual frozen
behavior GREEN must produce.
-}
module Cardano.KERI.Indexer.Query.ServerSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.AID.CESR (qb64Aid, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatum (V1), CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..), Weight (..))
import Cardano.KERI.Deployment.EndpointBoard (EndpointRecord (..), parseEndpointRecord)
import Cardano.KERI.Deployment.EndpointBoardManifest (frozenEndpointBoardPolicyId)
import Cardano.KERI.Indexer.Query.Server (mkQueryApplication)
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.KERI.Indexer.Query.Types (hexBytes, qb64Witness)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Scripts.Data (
    Data (..),
    Datum (..),
    dataToBinaryData,
 )
import Cardano.Ledger.Api.Tx.Out (datumTxOutL, mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Credential (
    Credential (ScriptHashObj),
    StakeReference (StakeRefNull),
 )
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Node.Client.N2C.Reconnect (DisconnectInfo (..), UpstreamStatus (..))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent.STM (STM, atomically, newTVarIO, readTVar, writeTVar)
import Data.Aeson (Value, decode, object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as BSL8
import Data.ByteString.Short qualified as SBS
import Data.Function ((&))
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction (..))
import Lens.Micro ((.~))
import Network.HTTP.Types (status200, status400, status500, status503)
import Network.Wai (defaultRequest)
import Network.Wai.Test (
    SResponse (..),
    Session,
    request,
    runSession,
    setPath,
 )
import Paths_cardano_keri (getDataFileName)
import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "Cardano.KERI.Indexer.Query.Server (#176 Slice 1 contract)" $ do
    readySpec
    checkpointSpec
    boardSpec
    boardListSpec
    watchabilitySpec
    noCacheSpec
    rollbackSkewSpec
    readinessGateSpec
    oneTransactionSpec
    swaggerSpec

-- ---------------------------------------------------------------------------
-- /ready

readySpec :: Spec
readySpec = describe "GET /ready" $ do
    it "reports ready with the store watermark and zero lag when healthy" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x01 [checkpointCreate (sampleTxIn 0x10) aidX datumX0]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 100 100))
            resp <- runSession (get "/ready") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            decode (simpleBody resp)
                `shouldBe` Just
                    ( object
                        [ "ready" .= True
                        , "as_of_slot" .= (100 :: Int)
                        , "tip_lag_slots" .= (0 :: Int)
                        , "upstream" .= ("connected" :: Text)
                        , "reason" .= (Nothing :: Maybe Text)
                        ]
                    )

    it "reports not-ready with a non-null reason on a cold store" $
        withInMemoryIndexerRunner $ \_handle runner -> do
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 0 0))
            resp <- runSession (get "/ready") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            withObject resp $ \obj -> do
                KeyMap.lookup "ready" obj `shouldBe` Just (Aeson.Bool False)
                KeyMap.lookup "reason" obj `shouldSatisfy` (/= Just Aeson.Null)

-- ---------------------------------------------------------------------------
-- /checkpoint/{aid}

checkpointSpec :: Spec
checkpointSpec = describe "GET /checkpoint/{aid}" $ do
    it "returns the exact frozen shape for a known unweighted-threshold AID" $
        withInMemoryIndexerRunner $ \handle runner -> do
            let txIn = sampleTxIn 0x20
            applyBatch handle 50 0x02 [checkpointCreate txIn aidX datumX0]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 50 50))
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            decode (simpleBody resp)
                `shouldBe` Just (expectedCheckpointJson aidX txIn datumX0 50 0)

    it "returns the exact frozen shape for a genuinely weighted-multi-clause threshold" $
        withInMemoryIndexerRunner $ \handle runner -> do
            let txIn = sampleTxIn 0x21
                datum =
                    datumX0
                        { cdCurThreshold = Weighted [[Weight 1 2, Weight 1 2]]
                        , cdNextThreshold = Weighted [[Weight 1 3]]
                        }
            applyBatch handle 51 0x03 [checkpointCreate txIn aidX datum]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 51 51))
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            decode (simpleBody resp)
                `shouldBe` Just (expectedCheckpointJson aidX txIn datum 51 0)

    it "returns 200 with checkpoint:null for an unknown but well-formed AID" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 10 0x04 []
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 10 10))
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            withObject resp $ \obj ->
                KeyMap.lookup "checkpoint" obj `shouldBe` Just Aeson.Null

    it "returns 400 for a malformed CESR AID" $
        withInMemoryIndexerRunner $ \_handle runner -> do
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 0 0))
            resp <- runSession (get "/checkpoint/not-a-real-aid") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status400

-- ---------------------------------------------------------------------------
-- /board/{witness_key}

boardSpec :: Spec
boardSpec = describe "GET /board/{witness_key}" $ do
    it "resolves an authenticated record by B-code witness key" $
        withInMemoryIndexerRunner $ \handle runner -> do
            record <- loadRecord "witness-1-oobi.cesr"
            let txIn = sampleTxIn 0x30
            applyBatch handle 60 0x05 [boardCreate txIn record]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 60 60))
            resp <-
                runSession (get ("/board/" <> qb64Witness (endpointWitnessKey record))) $
                    mkQueryApplication handle'
            simpleStatus resp `shouldBe` status200
            decode (simpleBody resp)
                `shouldBe` Just (expectedBoardJson record txIn 60 0)

    it "returns 200 with board:null for an unknown but well-formed witness key" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 5 0x06 []
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 5 5))
                unknownKey = BS.replicate 32 0x99
            resp <-
                runSession (get ("/board/" <> qb64Witness unknownKey)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            withObject resp $ \obj ->
                KeyMap.lookup "board" obj `shouldBe` Just Aeson.Null

    it "returns 400 for a malformed witness key" $
        withInMemoryIndexerRunner $ \_handle runner -> do
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 0 0))
            resp <- runSession (get "/board/not-a-real-key") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status400

    it "fails the whole route closed (500) on a forged board record, even for an unrelated valid key" $
        withInMemoryIndexerRunner $ \handle runner -> do
            good <- loadRecord "witness-1-oobi.cesr"
            forged <- loadRecord "witness-2-oobi.cesr"
            let forged' =
                    forged
                        { endpointEventBytes =
                            replaceOnce "witness-2" "witness-X" (endpointEventBytes forged)
                        }
            applyBatch
                handle
                61
                0x07
                [ boardCreate (sampleTxIn 0x31) good
                , boardCreate (sampleTxIn 0x32) forged'
                ]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 61 61))
            resp <-
                runSession (get ("/board/" <> qb64Witness (endpointWitnessKey good))) $
                    mkQueryApplication handle'
            simpleStatus resp `shouldBe` status500

-- ---------------------------------------------------------------------------
-- /board

boardListSpec :: Spec
boardListSpec = describe "GET /board catalog" $ do
    it "returns the complete authenticated catalog with transactional freshness" $
        withInMemoryIndexerRunner $ \handle runner -> do
            first <- loadRecord "witness-1-oobi.cesr"
            second <- loadRecord "witness-2-oobi.cesr"
            let firstTxIn = sampleTxIn 0x33
                secondTxIn = sampleTxIn 0x34
            applyBatch
                handle
                62
                0x17
                [ boardCreate firstTxIn first
                , boardCreate secondTxIn second
                ]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 62 64))
            resp <- runSession (get "/board") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            decode (simpleBody resp)
                `shouldBe` Just (expectedBoardListJson [(first, firstTxIn), (second, secondTxIn)] 62 2)

    it "returns an empty array for an empty authenticated catalog" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 6 0x18 []
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 6 6))
            resp <- runSession (get "/board") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            withObject resp $ \obj ->
                KeyMap.lookup "board" obj `shouldBe` Just (Aeson.Array mempty)

    it "fails the whole catalog closed on one forged record" $
        withInMemoryIndexerRunner $ \handle runner -> do
            good <- loadRecord "witness-1-oobi.cesr"
            forged <- loadRecord "witness-2-oobi.cesr"
            let forged' =
                    forged
                        { endpointEventBytes =
                            replaceOnce "witness-2" "witness-X" (endpointEventBytes forged)
                        }
            applyBatch
                handle
                63
                0x19
                [ boardCreate (sampleTxIn 0x35) good
                , boardCreate (sampleTxIn 0x36) forged'
                ]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 63 63))
            resp <- runSession (get "/board") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status500

    it "returns 503 without a board payload when readiness fails" $
        withInMemoryIndexerRunner $ \handle runner -> do
            record <- loadRecord "witness-1-oobi.cesr"
            applyBatch handle 64 0x1a [boardCreate (sampleTxIn 0x37) record]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness disconnectedReadiness)
            resp <- runSession (get "/board") (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status503
            withObject resp $ \obj -> do
                KeyMap.lookup "error" obj `shouldBe` Just (Aeson.String "service_unavailable")
                KeyMap.member "board" obj `shouldBe` False

-- ---------------------------------------------------------------------------
-- /watchability/{aid}

watchabilitySpec :: Spec
watchabilitySpec = describe "GET /watchability/{aid}" $ do
    it "reports missing declared witnesses in canonical B-code form" $
        withInMemoryIndexerRunner $ \handle runner -> do
            listed <- loadRecord "witness-1-oobi.cesr"
            missing <- loadRecord "witness-2-oobi.cesr"
            let datum =
                    datumX0{cdWitnesses = [endpointWitnessKey listed, endpointWitnessKey missing]}
            applyBatch
                handle
                70
                0x08
                [ checkpointCreate (sampleTxIn 0x40) aidX datum
                , boardCreate (sampleTxIn 0x41) listed
                ]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 70 70))
            resp <- runSession (get ("/watchability/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            decode (simpleBody resp)
                `shouldBe` Just
                    ( object
                        [ "aid" .= TE.decodeUtf8 (qb64Aid aidX)
                        , "as_of_slot" .= (70 :: Int)
                        , "tip_lag_slots" .= (0 :: Int)
                        , "watchability"
                            .= object
                                [ "checkpoint_present" .= True
                                , "witnesses_declared" .= (2 :: Int)
                                , "witnesses_listed" .= (1 :: Int)
                                , "missing_witnesses"
                                    .= [TE.decodeUtf8 (qb64Witness (endpointWitnessKey missing))]
                                ]
                        ]
                    )

    it "reports checkpoint_present:false with zero counts when no checkpoint exists" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 3 0x09 []
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 3 3))
            resp <- runSession (get ("/watchability/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            withObject resp $ \obj ->
                case KeyMap.lookup "watchability" obj of
                    Just (Aeson.Object inner) -> do
                        KeyMap.lookup "checkpoint_present" inner `shouldBe` Just (Aeson.Bool False)
                        KeyMap.lookup "witnesses_declared" inner `shouldBe` Just (Aeson.Number 0)
                        KeyMap.lookup "witnesses_listed" inner `shouldBe` Just (Aeson.Number 0)
                        KeyMap.lookup "missing_witnesses" inner `shouldBe` Just (Aeson.Array mempty)
                    other -> expectationFailure ("not a watchability object: " <> show other)

    it "fails closed (500) when the board catalog is corrupted" $
        withInMemoryIndexerRunner $ \handle runner -> do
            forged <- loadRecord "witness-1-oobi.cesr"
            let forged' =
                    forged
                        { endpointEventBytes =
                            replaceOnce "witness-1" "witness-X" (endpointEventBytes forged)
                        }
                datum = datumX0{cdWitnesses = [endpointWitnessKey forged']}
            applyBatch
                handle
                72
                0x0a
                [ checkpointCreate (sampleTxIn 0x42) aidX datum
                , boardCreate (sampleTxIn 0x43) forged'
                ]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 72 72))
            resp <- runSession (get ("/watchability/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status500

-- ---------------------------------------------------------------------------
-- No cache: mutate between two requests

noCacheSpec :: Spec
noCacheSpec = describe "no cache" $
    it "reflects a mutation on the very next request" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 0 0x15 []
            let handle' =
                    QueryHandle runner checkpointAddress checkpointPolicy boardAddress
                app1 = mkQueryApplication (handle' (constReadiness (readinessAt 0 0)))
            resp1 <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) app1
            withObject resp1 $ \obj ->
                KeyMap.lookup "checkpoint" obj `shouldBe` Just Aeson.Null
            applyBatch handle 20 0x0b [checkpointCreate (sampleTxIn 0x50) aidX datumX0]
            let app2 = mkQueryApplication (handle' (constReadiness (readinessAt 20 20)))
            resp2 <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) app2
            withObject resp2 $ \obj ->
                KeyMap.lookup "checkpoint" obj `shouldSatisfy` (/= Just Aeson.Null)

-- ---------------------------------------------------------------------------
-- FR-3: rollback with readiness skew

rollbackSkewSpec :: Spec
rollbackSkewSpec = describe "rollback with readiness skew (FR-3)" $
    it "reports the lower store watermark and drops rolled-back data, ignoring a stale-high readiness" $
        withInMemoryIndexerRunner $ \handle runner -> do
            let txIn = sampleTxIn 0x60
            applyBatch handle 10 0x0c []
            applyBatch handle 30 0x0d [checkpointCreate txIn aidX datumX0]
            -- Readiness still reports the pre-rollback high processed slot (30);
            -- the transactional watermark must win, never this stale value.
            let staleReadiness = readinessAt 30 30
            rollbackTo handle (Indexer.SlotNo 10)
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness staleReadiness)
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status200
            withObject resp $ \obj -> do
                KeyMap.lookup "as_of_slot" obj `shouldBe` Just (Aeson.Number 10)
                KeyMap.lookup "checkpoint" obj `shouldBe` Just Aeson.Null

-- ---------------------------------------------------------------------------
-- FR-3/PROVE-LIST 2: fail-closed 503 on disconnected/lag-over-60, and
-- PROVE-LIST 5's reconnect-recovery half, for a representative data route.

readinessGateSpec :: Spec
readinessGateSpec = describe "readiness gate: fail-closed 503 (FR-3)" $ do
    it "returns 503 with no checkpoint key when upstream is disconnected, even though data exists" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 40 0x0e [checkpointCreate (sampleTxIn 0x70) aidX datumX0]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness disconnectedReadiness)
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status503
            withObject resp $ \obj -> do
                KeyMap.lookup "ready" obj `shouldBe` Just (Aeson.Bool False)
                KeyMap.lookup "error" obj `shouldBe` Just (Aeson.String "service_unavailable")
                KeyMap.member "checkpoint" obj `shouldBe` False

    it "returns 503 with no checkpoint key when tip lag exceeds 60 slots" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x0f [checkpointCreate (sampleTxIn 0x71) aidX datumX0]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 100 161))
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status503
            withObject resp $ \obj -> do
                KeyMap.lookup "ready" obj `shouldBe` Just (Aeson.Bool False)
                KeyMap.member "checkpoint" obj `shouldBe` False

    it "returns 503 with no checkpoint key when the store watermark is ahead of the sampled tip (impossible tip)" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 100 0x13 [checkpointCreate (sampleTxIn 0x73) aidX datumX0]
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (constReadiness (readinessAt 100 40))
            resp <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) (mkQueryApplication handle')
            simpleStatus resp `shouldBe` status503
            withObject resp $ \obj -> do
                KeyMap.lookup "ready" obj `shouldBe` Just (Aeson.Bool False)
                KeyMap.member "checkpoint" obj `shouldBe` False

    it "recovers to 200 once upstream reconnects, on the same running process" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyBatch handle 50 0x14 [checkpointCreate (sampleTxIn 0x72) aidX datumX0]
            readinessVar <- newTVarIO disconnectedReadiness
            let handle' =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (readTVar readinessVar)
                app = mkQueryApplication handle'
            resp1 <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) app
            simpleStatus resp1 `shouldBe` status503
            withObject resp1 $ \obj -> KeyMap.member "checkpoint" obj `shouldBe` False
            atomically (writeTVar readinessVar (readinessAt 50 50))
            resp2 <- runSession (get ("/checkpoint/" <> qb64Aid aidX)) app
            simpleStatus resp2 `shouldBe` status200
            withObject resp2 $ \obj ->
                KeyMap.lookup "checkpoint" obj `shouldSatisfy` (/= Just Aeson.Null)

disconnectedReadiness :: Readiness
disconnectedReadiness =
    Readiness
        { rProcessedSlot = Just (Indexer.SlotNo 40)
        , rTipSlot = Just (Indexer.SlotNo 40)
        , rUpstream =
            UpstreamDisconnected
                DisconnectInfo
                    { diReason = "#176 ServerSpec injected disconnect"
                    , diAttempt = 1
                    , diSinceMs = 0
                    }
        , rUpdatedAt = fixedTime
        }

-- ---------------------------------------------------------------------------
-- Exactly one transaction per composed response

oneTransactionSpec :: Spec
oneTransactionSpec = describe "one transaction per response (FR-2)" $ do
    it "/ready runs exactly one transaction" $
        countedTransactionsFor "/ready" `shouldReturnCount` 1
    it "/checkpoint/{aid} runs exactly one transaction" $
        countedTransactionsFor ("/checkpoint/" <> qb64Aid aidX) `shouldReturnCount` 1
    it "/board/{witness_key} runs exactly one transaction" $
        countedTransactionsFor ("/board/" <> qb64Witness (BS.replicate 32 0x77))
            `shouldReturnCount` 1
    it "/board catalog runs exactly one transaction" $
        countedTransactionsFor "/board" `shouldReturnCount` 1
    it "/watchability/{aid} runs exactly one transaction (both address scans + watermark)" $
        countedTransactionsFor ("/watchability/" <> qb64Aid aidX) `shouldReturnCount` 1

shouldReturnCount :: IO Int -> Int -> IO ()
shouldReturnCount action expected = action >>= (`shouldBe` expected)

countedTransactionsFor :: ByteString -> IO Int
countedTransactionsFor path =
    withInMemoryIndexerRunner $ \_handle runner -> do
        counter <- newIORef (0 :: Int)
        let countingRunner =
                RunTransaction
                    { runTransaction = \tx -> do
                        atomicModifyIORef' counter (\n -> (n + 1, ()))
                        runTransaction runner tx
                    }
            handle' =
                QueryHandle
                    countingRunner
                    checkpointAddress
                    checkpointPolicy
                    boardAddress
                    (constReadiness (readinessAt 0 0))
        _ <- runSession (get path) (mkQueryApplication handle')
        readIORef counter

-- ---------------------------------------------------------------------------
-- GET /swagger.json and GET /swagger-ui (T176-S1-7/FR-9 HTTP-level serving)

swaggerSpec :: Spec
swaggerSpec = describe "GET /swagger.json and /swagger-ui" $ do
    it "serves the committed OpenAPI document" $
        withInMemoryIndexerRunner $ \_handle runner -> do
            resp <- runSession (get "/swagger.json") (mkQueryApplication (queryHandleFor runner))
            simpleStatus resp `shouldBe` status200
            case decode (simpleBody resp) of
                Just (Aeson.Object obj) -> KeyMap.member "openapi" obj `shouldBe` True
                other -> expectationFailure ("expected an OpenAPI JSON object, got " <> show other)

    it "serves a Swagger UI page that references /swagger.json" $
        withInMemoryIndexerRunner $ \_handle runner -> do
            resp <- runSession (get "/swagger-ui") (mkQueryApplication (queryHandleFor runner))
            simpleStatus resp `shouldBe` status200
            let body = BSL8.toStrict (simpleBody resp)
            BS.isInfixOf "swagger-ui" body `shouldBe` True
            BS.isInfixOf "/swagger.json" body `shouldBe` True

queryHandleFor :: RunTransaction IO cf Cols op -> QueryHandle cf op
queryHandleFor runner =
    QueryHandle
        runner
        checkpointAddress
        checkpointPolicy
        boardAddress
        (constReadiness (readinessAt 0 0))

-- ---------------------------------------------------------------------------
-- HTTP helpers

get :: ByteString -> Session SResponse
get path = request (setPath defaultRequest path)

withObject :: SResponse -> (Aeson.Object -> IO ()) -> IO ()
withObject resp check =
    case decode (simpleBody resp) of
        Just (Aeson.Object obj) -> check obj
        other -> expectationFailure ("not a JSON object: " <> show other)

-- ---------------------------------------------------------------------------
-- Golden JSON builders (hand-specified per spec.md — an independent oracle
-- from the production 'Cardano.KERI.Indexer.Query.Types.ToJSON' instances)

expectedCheckpointJson ::
    ByteString -> Indexer.TxIn -> CheckpointDatumV1 -> Int -> Int -> Value
expectedCheckpointJson aid txIn datum asOfSlot tipLag =
    object
        [ "aid" .= TE.decodeUtf8 (qb64Aid aid)
        , "as_of_slot" .= asOfSlot
        , "tip_lag_slots" .= tipLag
        , "checkpoint"
            .= object
                [ "tx_id" .= hexBytes (Indexer.txInId txIn)
                , "output_index" .= Indexer.txInIx txIn
                , "sequence" .= cdSeq datum
                , "native_sequence" .= cdNativeSn datum
                , "current_keys" .= map (TE.decodeUtf8 . qb64Verkey) (cdCurKeys datum)
                , "current_threshold" .= thresholdJson (cdCurThreshold datum)
                , "next_key_digests" .= map (TE.decodeUtf8 . qb64Aid) (cdNextKeys datum)
                , "next_threshold" .= thresholdJson (cdNextThreshold datum)
                , "witnesses" .= map (TE.decodeUtf8 . qb64Witness) (cdWitnesses datum)
                , "witness_threshold" .= cdToad datum
                ]
        ]

expectedBoardJson :: EndpointRecord -> Indexer.TxIn -> Int -> Int -> Value
expectedBoardJson record txIn asOfSlot tipLag =
    object
        [ "witness_key" .= TE.decodeUtf8 (qb64Witness (endpointWitnessKey record))
        , "as_of_slot" .= asOfSlot
        , "tip_lag_slots" .= tipLag
        , "board"
            .= object
                [ "aid" .= endpointAid record
                , "scheme" .= endpointScheme record
                , "url" .= endpointUrl record
                , "tx_id" .= hexBytes (Indexer.txInId txIn)
                , "output_index" .= Indexer.txInIx txIn
                , "lovelace" .= (2_000_000 :: Int)
                , "owner_key_hash" .= hexBytes boardOwner
                ]
        ]

expectedBoardListJson :: [(EndpointRecord, Indexer.TxIn)] -> Int -> Int -> Value
expectedBoardListJson records asOfSlot tipLag =
    object
        [ "as_of_slot" .= asOfSlot
        , "tip_lag_slots" .= tipLag
        , "board" .= map (uncurry expectedBoardListEntryJson) records
        ]

expectedBoardListEntryJson :: EndpointRecord -> Indexer.TxIn -> Value
expectedBoardListEntryJson record txIn =
    object
        [ "witness_key" .= TE.decodeUtf8 (qb64Witness (endpointWitnessKey record))
        , "aid" .= endpointAid record
        , "scheme" .= endpointScheme record
        , "url" .= endpointUrl record
        , "tx_id" .= hexBytes (Indexer.txInId txIn)
        , "output_index" .= Indexer.txInIx txIn
        , "lovelace" .= (2_000_000 :: Int)
        , "owner_key_hash" .= hexBytes boardOwner
        ]

thresholdJson :: Threshold -> Value
thresholdJson (Unweighted n) = object ["type" .= ("unweighted" :: Text), "value" .= n]
thresholdJson (Weighted clauses) =
    object
        [ "type" .= ("weighted" :: Text)
        , "clauses"
            .= map
                ( map
                    ( \(Weight num den) ->
                        object ["numerator" .= num, "denominator" .= den]
                    )
                )
                clauses
        ]

-- ---------------------------------------------------------------------------
-- Fixtures shared across this file

aidX :: ByteString
aidX = BS.replicate 32 0x31

datumX0 :: CheckpointDatumV1
datumX0 =
    CheckpointDatumV1
        { cdCesrAid = aidX
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }

checkpointPolicy :: PolicyID
checkpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just h -> h
                Nothing -> error "ServerSpec: invalid checkpoint policy id width"

checkpointLedgerAddress :: Addr
checkpointLedgerAddress =
    let PolicyID scriptHash = checkpointPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

checkpointAddress :: Indexer.Address
checkpointAddress = Indexer.Address (serialiseAddr checkpointLedgerAddress)

boardPolicy :: PolicyID
boardPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (hexBytesOrError frozenEndpointBoardPolicyId) of
                Just h -> h
                Nothing -> error "ServerSpec: invalid frozen board policy id width"

boardLedgerAddress :: Addr
boardLedgerAddress =
    let PolicyID scriptHash = boardPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

boardAddress :: Indexer.Address
boardAddress = Indexer.Address (serialiseAddr boardLedgerAddress)

boardOwner :: ByteString
boardOwner = BS.replicate 28 0x33

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

boardCreate :: Indexer.TxIn -> EndpointRecord -> UtxoOp
boardCreate txIn record = UtxoCreate txIn boardAddress (boardOutput record)

boardOutput :: EndpointRecord -> Indexer.TxOut
boardOutput record =
    Indexer.TxOut $
        serialize'
            (eraProtVerLow @ConwayEra)
            (baseTxOut & datumTxOutL .~ inlineDatum (boardDatum record))
  where
    baseTxOut :: TxOut ConwayEra
    baseTxOut =
        mkBasicTxOut
            boardLedgerAddress
            ( MaryValue
                (Coin 2_000_000)
                ( MultiAsset $
                    Map.singleton
                        boardPolicy
                        ( Map.singleton
                            (AssetName . SBS.toShort $ endpointWitnessKey record)
                            1
                        )
                )
            )

boardDatum :: EndpointRecord -> PLC.Data
boardDatum record =
    PLC.Constr
        0
        [ PLC.B (endpointWitnessKey record)
        , PLC.B (endpointEventBytes record)
        , PLC.B (endpointSignature record)
        , PLC.B boardOwner
        ]

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

constReadiness :: Readiness -> STM Readiness
constReadiness = pure

loadRecord :: FilePath -> IO EndpointRecord
loadRecord name = do
    path <- getDataFileName ("deployment-test/fixtures/" <> name)
    bytes <- BS.readFile path
    case parseEndpointRecord bytes of
        Left err -> expectationFailure err >> fail err
        Right record -> pure record

replaceOnce :: ByteString -> ByteString -> ByteString -> ByteString
replaceOnce needle replacement haystack =
    let (before, match) = BS.breakSubstring needle haystack
     in if BS.null match
            then haystack
            else before <> replacement <> BS.drop (BS.length needle) match

hexBytesOrError :: Text -> ByteString
hexBytesOrError hexInput =
    case convertFromBase Base16 (TE.encodeUtf8 hexInput) of
        Right bytes -> bytes
        Left err -> error ("ServerSpec: invalid hex fixture: " <> err)
