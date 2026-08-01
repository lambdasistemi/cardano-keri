{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.ShellSpec (spec) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV1,
 )
import Cardano.KERI.AID.Checkpoint.Message (
    deriveAidAssetName,
 )
import Cardano.KERI.Indexer.Codecs (
    CheckpointRecord (..),
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
 )
import Cardano.KERI.Indexer.ReadsSpec (
    checkpointCreate,
    checkpointDatum,
    checkpointView,
 )
import Cardano.KERI.Indexer.Shell (
    Command (..),
    QueryAction (..),
    StatusView (..),
    completeVerbs,
    handleLine,
    helpText,
    localQueryAction,
    parseCommand,
    progressLine,
    renderStatus,
    verbNames,
 )
import Cardano.Node.Client.N2C.Reconnect (
    DisconnectInfo (..),
    UpstreamStatus (..),
 )
import Cardano.Node.Client.UTxOIndexer.Follower (
    FollowerHandle (..),
    Readiness (..),
    initialReadiness,
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexer,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Binary.Bech32 (
    dataPartFromBytes,
    encodeLenient,
    humanReadablePartFromText,
 )
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async qualified as Async
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Control.Monad (forever)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.Either (isLeft)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text qualified as Text
import Data.Time.Clock (getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Word (Word16, Word8)
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldContain,
    shouldMatchList,
    shouldNotBe,
    shouldReturn,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "#188 runnable follower shell" $ do
    parseCommandSpec
    verbCompletionSpec
    controlVerbSpec
    rejectionSpec
    freshnessSpec
    readinessRenderingSpec
    progressLineSpec
    dispatchCounterSpec

-- ---------------------------------------------------------------------------
-- parseCommand

parseCommandSpec :: Spec
parseCommandSpec =
    describe "parseCommand" $ do
        it "parses each zero-argument verb" $ do
            parseCommand "status" `shouldBe` Right CmdStatus
            parseCommand "list" `shouldBe` Right CmdList
            parseCommand "help" `shouldBe` Right CmdHelp
            parseCommand "quit" `shouldBe` Right CmdQuit

        it "parses checkpoint <AID> for a valid 44-character E-code AID" $ do
            let aid = BS.replicate 32 0x21
                aidText = BS8.unpack (qb64Aid aid)
            parseCommand ("checkpoint " <> aidText) `shouldBe` Right (CmdCheckpoint aid)

        it "parses payer <ADDRESS> for a valid bech32 address" $ do
            let address = testAddress 0x31
                addressText = encodeTestAddress address
            parseCommand ("payer " <> addressText) `shouldBe` Right (CmdPayer address)

        it "rejects an unknown verb" $
            parseCommand "frobnicate" `shouldSatisfy` isLeft

        it "rejects checkpoint/payer given the wrong argument count" $ do
            parseCommand "checkpoint" `shouldSatisfy` isLeft
            parseCommand "checkpoint a b" `shouldSatisfy` isLeft
            parseCommand "payer" `shouldSatisfy` isLeft
            parseCommand "status extra" `shouldSatisfy` isLeft

        it "rejects a too-short AID" $
            parseCommand ("checkpoint " <> replicate 43 'A') `shouldSatisfy` isLeft

        it "rejects a correctly-sized but wrong-prefix AID (a verkey, not a SAID)" $ do
            let wrongPrefix = BS8.unpack (qb64Verkey (BS.replicate 32 0x22))
            parseCommand ("checkpoint " <> wrongPrefix) `shouldSatisfy` isLeft

        it "rejects an invalid bech32 address" $
            parseCommand "payer not-a-real-address" `shouldSatisfy` isLeft

-- ---------------------------------------------------------------------------
-- verb completion

verbCompletionSpec :: Spec
verbCompletionSpec =
    describe "completeVerbs" $ do
        it "completes 'c' to exactly checkpoint" $
            completeVerbs "c" `shouldBe` ["checkpoint"]
        it "completes the empty prefix to every verb" $
            completeVerbs "" `shouldMatchList` verbNames
        it "completes an unmatched prefix to nothing" $
            completeVerbs "zz" `shouldBe` []

-- ---------------------------------------------------------------------------
-- control verbs (quit/help), no IO

controlVerbSpec :: Spec
controlVerbSpec =
    describe "handleLine control verbs" $ do
        it "quit signals termination without any query IO" $
            handleLine bombQueryAction "quit" `shouldReturn` Nothing
        it "help returns the help text without any query IO" $
            handleLine bombQueryAction "help" `shouldReturn` Just helpText

-- ---------------------------------------------------------------------------
-- rejection behavior: zero IO on malformed input

rejectionSpec :: Spec
rejectionSpec =
    describe "malformed input performs zero query IO" $ do
        it "an unknown verb is rejected without IO" $
            assertConciseRejection =<< handleLine bombQueryAction "frobnicate"

        it "a too-short AID is rejected without IO" $
            assertConciseRejection =<< handleLine bombQueryAction "checkpoint short"

        it "a wrong-prefix AID is rejected without IO" $ do
            let wrongPrefix = BS8.unpack (qb64Verkey (BS.replicate 32 0x23))
            assertConciseRejection =<< handleLine bombQueryAction ("checkpoint " <> wrongPrefix)

        it "an invalid bech32 address is rejected without IO" $
            assertConciseRejection =<< handleLine bombQueryAction "payer not-a-real-address"
  where
    assertConciseRejection result =
        case result of
            Nothing -> expectationFailure "a rejection must not signal quit"
            Just message -> message `shouldSatisfy` (not . null)

-- | Every field throws if invoked: proves a code path performs zero IO.
bombQueryAction :: QueryAction
bombQueryAction =
    QueryAction
        { qaStatus = error "#188 unexpected IO: status"
        , qaList = error "#188 unexpected IO: list"
        , qaCheckpoint = \_ -> error "#188 unexpected IO: checkpoint"
        , qaPayer = \_ -> error "#188 unexpected IO: payer"
        }

-- ---------------------------------------------------------------------------
-- FR4 freshness: real in-memory store, crossing the production seam

freshnessSpec :: Spec
freshnessSpec =
    describe "the local query action re-reads the real store" $ do
        it "list/checkpoint observe a fresh apply" $
            withInMemoryIndexer $ \handle ->
                withFollowerHandle (pureReadiness UpstreamConnected) $ \_readinessVar fh -> do
                    let view = checkpointView handle
                        qa = localQueryAction view fh
                        aid = BS.replicate 32 0x41
                        datum = checkpointDatum aid 0
                        txIn = sampleTxIn 0x41 0

                    beforeCheckpoint <- qaCheckpoint qa aid
                    beforeCheckpoint `shouldBe` Nothing
                    (beforeRecords, _) <- qaList qa
                    beforeRecords `shouldBe` []

                    applyAtSlot
                        handle
                        (Indexer.SlotNo 1)
                        (blockHash 0x51)
                        [checkpointCreate txIn aid datum]

                    let expected = expectedRecord handle aid datum txIn
                    afterCheckpoint <- qaCheckpoint qa aid
                    afterCheckpoint `shouldBe` Just expected
                    (afterRecords, _) <- qaList qa
                    afterRecords `shouldBe` [expected]

        it "list/checkpoint observe a spend" $
            withInMemoryIndexer $ \handle ->
                withFollowerHandle (pureReadiness UpstreamConnected) $ \_readinessVar fh -> do
                    let view = checkpointView handle
                        qa = localQueryAction view fh
                        aid = BS.replicate 32 0x42
                        datum = checkpointDatum aid 0
                        txIn = sampleTxIn 0x42 0
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 1)
                        (blockHash 0x52)
                        [checkpointCreate txIn aid datum]
                    present <- qaCheckpoint qa aid
                    present `shouldBe` Just (expectedRecord handle aid datum txIn)

                    applyAtSlot handle (Indexer.SlotNo 2) (blockHash 0x53) [UtxoSpend txIn]

                    gone <- qaCheckpoint qa aid
                    gone `shouldBe` Nothing

        it "list/checkpoint observe a real rollback, distinct from a spend" $
            withInMemoryIndexer $ \handle ->
                withFollowerHandle (pureReadiness UpstreamConnected) $ \_readinessVar fh -> do
                    let view = checkpointView handle
                        qa = localQueryAction view fh
                        aid = BS.replicate 32 0x43
                        datum = checkpointDatum aid 0
                        txIn = sampleTxIn 0x43 0
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 1)
                        (blockHash 0x54)
                        [checkpointCreate txIn aid datum]
                    present <- qaCheckpoint qa aid
                    present `shouldBe` Just (expectedRecord handle aid datum txIn)

                    rollbackTo handle (Indexer.SlotNo 0)

                    gone <- qaCheckpoint qa aid
                    gone `shouldBe` Nothing
                    getRollbackHistory handle `shouldReturn` []

        it "status re-reads readiness fresh on every call" $
            withInMemoryIndexer $ \handle -> do
                now <- getCurrentTime
                withFollowerHandle (initialReadiness now) $ \readinessVar fh -> do
                    let qa = localQueryAction (checkpointView handle) fh
                    initialStatus <- qaStatus qa
                    readinessKey (svReadiness initialStatus) `shouldBe` readinessKey (initialReadiness now)

                    let lagged =
                            (initialReadiness now)
                                { rProcessedSlot = Just (Indexer.SlotNo 100)
                                , rTipSlot = Just (Indexer.SlotNo 130)
                                }
                    atomically (writeTVar readinessVar lagged)

                    after <- qaStatus qa
                    readinessKey (svReadiness after) `shouldBe` readinessKey lagged
                    readinessKey (svReadiness after) `shouldNotBe` readinessKey (svReadiness initialStatus)

        it "status answers immediately from local state when upstream is disconnected" $
            withInMemoryIndexer $ \handle -> do
                now <- getCurrentTime
                let disconnected =
                        (initialReadiness now)
                            { rProcessedSlot = Just (Indexer.SlotNo 12)
                            , rTipSlot = Just (Indexer.SlotNo 12)
                            , rUpstream =
                                UpstreamDisconnected (DisconnectInfo "no route to host" 1 1_000)
                            }
                withFollowerHandle disconnected $ \_readinessVar fh -> do
                    applyAtSlot handle (Indexer.SlotNo 12) (blockHash 0x73) []
                    let qa = localQueryAction (checkpointView handle) fh
                    status <- qaStatus qa
                    rUpstream (svReadiness status)
                        `shouldBe` UpstreamDisconnected (DisconnectInfo "no route to host" 1 1_000)
                    svStorePoint status `shouldBe` Just (Indexer.SlotNo 12, blockHash 0x73)

        it "payer observes creates and spends between calls" $
            withInMemoryIndexer $ \handle ->
                withFollowerHandle (pureReadiness UpstreamConnected) $ \_readinessVar fh -> do
                    let qa = localQueryAction (checkpointView handle) fh
                        payer = Indexer.Address (BS.replicate 29 0x61)
                        kept = (sampleTxIn 0x71 0, Indexer.TxOut "shell-payer-kept")
                        spent = (sampleTxIn 0x72 1, Indexer.TxOut "shell-payer-spent")

                    empty <- qaPayer qa payer
                    empty `shouldBe` []

                    applyAtSlot
                        handle
                        (Indexer.SlotNo 1)
                        (blockHash 0x62)
                        [ UtxoCreate (fst kept) payer (snd kept)
                        , UtxoCreate (fst spent) payer (snd spent)
                        ]
                    afterCreate <- qaPayer qa payer
                    afterCreate `shouldBe` [kept, spent]

                    applyAtSlot handle (Indexer.SlotNo 2) (blockHash 0x63) [UtxoSpend (fst spent)]
                    afterSpend <- qaPayer qa payer
                    afterSpend `shouldBe` [kept]

        it "handleLine list re-reads the real store across two dispatches" $
            withInMemoryIndexer $ \handle ->
                withFollowerHandle (pureReadiness UpstreamConnected) $ \_readinessVar fh -> do
                    let qa = localQueryAction (checkpointView handle) fh
                    before <- handleLine qa "list"
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 1)
                        (blockHash 0x81)
                        [ checkpointCreate
                            (sampleTxIn 0x81 0)
                            (BS.replicate 32 0x81)
                            (checkpointDatum (BS.replicate 32 0x81) 0)
                        ]
                    after <- handleLine qa "list"
                    before `shouldNotBe` after

-- ---------------------------------------------------------------------------
-- readiness rendering

readinessRenderingSpec :: Spec
readinessRenderingSpec =
    describe "renderStatus" $ do
        it "renders the initial no-progress state distinctly from a lagged connected state" $ do
            now <- getCurrentTime
            let initial = StatusView (initialReadiness now) Nothing
                lagged =
                    StatusView
                        (initialReadiness now)
                            { rProcessedSlot = Just (Indexer.SlotNo 90)
                            , rTipSlot = Just (Indexer.SlotNo 130)
                            }
                        (Just (Indexer.SlotNo 90, blockHash 0x71))
            renderStatus initial `shouldNotBe` renderStatus lagged

        it "renders a disconnected upstream distinctly, while still reporting the retained store point" $ do
            now <- getCurrentTime
            let disconnectedReadiness =
                    (initialReadiness now)
                        { rProcessedSlot = Just (Indexer.SlotNo 90)
                        , rTipSlot = Just (Indexer.SlotNo 130)
                        , rUpstream = UpstreamDisconnected (DisconnectInfo "connection refused" 2 4_000)
                        }
                connectedSameSlots =
                    (initialReadiness now)
                        { rProcessedSlot = Just (Indexer.SlotNo 90)
                        , rTipSlot = Just (Indexer.SlotNo 130)
                        }
                storedPoint = Just (Indexer.SlotNo 90, blockHash 0x72)
                renderedDisconnected = renderStatus (StatusView disconnectedReadiness storedPoint)
            renderedDisconnected
                `shouldNotBe` renderStatus (StatusView connectedSameSlots storedPoint)
            renderedDisconnected `shouldSatisfy` (not . null)
            -- FR2/FR5: disconnected status still reports the store's
            -- retained persisted point, not just an upstream flag.
            renderedDisconnected `shouldContain` "90"
            renderedDisconnected `shouldContain` "72727272"

-- ---------------------------------------------------------------------------
-- FR3 progressLine freshness

progressLineSpec :: Spec
progressLineSpec =
    describe "progressLine" $
        it "recomputes fresh output from two distinct snapshots" $
            withInMemoryIndexer $ \handle -> do
                now <- getCurrentTime
                withFollowerHandle (initialReadiness now) $ \readinessVar fh -> do
                    let qa = localQueryAction (checkpointView handle) fh
                    firstSample <- progressLine qa
                    applyAtSlot
                        handle
                        (Indexer.SlotNo 1)
                        (blockHash 0x64)
                        [ checkpointCreate
                            (sampleTxIn 0x44 0)
                            (BS.replicate 32 0x44)
                            (checkpointDatum (BS.replicate 32 0x44) 0)
                        ]
                    atomically $
                        writeTVar
                            readinessVar
                            (initialReadiness now)
                                { rProcessedSlot = Just (Indexer.SlotNo 5)
                                , rTipSlot = Just (Indexer.SlotNo 5)
                                }
                    secondSample <- progressLine qa
                    firstSample `shouldNotBe` secondSample

-- ---------------------------------------------------------------------------
-- Supplementary counter-only dispatch proof (not sufficient alone)

dispatchCounterSpec :: Spec
dispatchCounterSpec =
    describe "dispatch re-invokes the query action on each call (supplementary)" $
        it "counts two IO invocations for two status dispatches" $ do
            now <- getCurrentTime
            counter <- newIORef (0 :: Int)
            -- QueryAction's fields are StrictData: forcing the record to
            -- read ANY field (as handleLine must, to reach qaStatus) forces
            -- every field's outer thunk together. So the untouched fields
            -- here must be harmless values, not `error` sentinels (those
            -- belong to bombQueryAction, whose call sites never force the
            -- record at all).
            let qa =
                    QueryAction
                        { qaStatus =
                            modifyIORef' counter (+ 1)
                                >> pure (StatusView (initialReadiness now) Nothing)
                        , qaList = pure ([], [])
                        , qaCheckpoint = \_ -> pure Nothing
                        , qaPayer = \_ -> pure []
                        }
            _ <- handleLine qa "status"
            _ <- handleLine qa "status"
            readIORef counter `shouldReturn` (2 :: Int)

-- ---------------------------------------------------------------------------
-- Helpers

withFollowerHandle :: Readiness -> (TVar Readiness -> FollowerHandle -> IO a) -> IO a
withFollowerHandle initial action =
    Async.withAsync (forever (threadDelay maxBound)) $ \asyncHandle -> do
        readinessVar <- newTVarIO initial
        action
            readinessVar
            FollowerHandle
                { fhReadiness = readTVar readinessVar
                , fhAsync = asyncHandle
                }

-- | 'Readiness' has no upstream 'Eq' instance; compare its comparable fields.
readinessKey :: Readiness -> (Maybe Indexer.SlotNo, Maybe Indexer.SlotNo, UpstreamStatus)
readinessKey r = (rProcessedSlot r, rTipSlot r, rUpstream r)

pureReadiness :: UpstreamStatus -> Readiness
pureReadiness upstream =
    Readiness
        { rProcessedSlot = Nothing
        , rTipSlot = Nothing
        , rUpstream = upstream
        , rUpdatedAt = posixSecondsToUTCTime 0
        }

expectedRecord ::
    IndexerHandle -> ByteString -> CheckpointDatumV1 -> Indexer.TxIn -> CheckpointRecord
expectedRecord handle aid datum txIn =
    CheckpointRecord
        { crAid = aid
        , crAssetName = deriveAidAssetName aid
        , crTxIn = txIn
        , crAddress = cvAddress (checkpointView handle)
        , crDatum = datum
        }

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)

sampleTxIn :: Word8 -> Word16 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte)

testAddress :: Word8 -> Address
testAddress tag = Indexer.Address (BS.cons tag (BS.replicate 28 tag))

encodeTestAddress :: Address -> String
encodeTestAddress (Indexer.Address bytes) =
    case humanReadablePartFromText "addr_test" of
        Left err -> error $ "ShellSpec: invalid test HRP: " <> show err
        Right hrp -> Text.unpack (encodeLenient hrp (dataPartFromBytes bytes))
