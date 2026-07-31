{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.AtomicitySpec
Description : Verify KERI inherits the upstream block transaction boundary

The negative control deliberately commits KERI's configured handler before
failing and proves that the derived checkpoint and payer reads expose the
partial state. The production-path test installs the same handler list through
the upstream follower seam, fails a second handler inside the block
transaction, and proves neither store-backed view nor the rollback point can
escape independently.
-}
module Cardano.KERI.Indexer.AtomicitySpec (spec) where

import Cardano.KERI.Indexer.Codecs (
    CheckpointRecord (..),
 )
import Cardano.KERI.Indexer.Config (
    IndexerConfig (..),
 )
import Cardano.KERI.Indexer.Follower (
    mkChainSyncConfig,
 )
import Cardano.KERI.Indexer.FollowerSpec (
    baseConfig,
    m1Manifest,
 )
import Cardano.KERI.Indexer.Reads (
    CheckpointView (..),
    liveCheckpoints,
    payerUtxos,
 )
import Cardano.KERI.Indexer.ReadsSpec (
    checkpointCreate,
    checkpointDatum,
    checkpointView,
 )
import Cardano.Node.Client.BlockIndexer.Handler (
    HandlerContext (..),
    IndexerHandler (..),
 )
import Cardano.Node.Client.BlockIndexer.Handler qualified as Handler
import Cardano.Node.Client.UTxOIndexer.Follower (
    ChainSyncConfig (..),
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withFollowerHandlers,
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    Address (..),
    BlockHash (..),
    SlotNo (..),
    TxIn (..),
    TxOut (..),
 )
import Control.Exception (
    IOException,
    try,
 )
import Control.Monad.IO.Class (
    liftIO,
 )
import Data.ByteString qualified as BS
import Data.List.NonEmpty (
    NonEmpty (..),
 )
import Database.KV.Transaction (
    RunTransaction (..),
 )
import Test.Hspec (
    Expectation,
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldContain,
    shouldReturn,
 )

spec :: Spec
spec =
    describe "KERI follower transaction inheritance" $ do
        it "detects the unsafe outside-transaction boundary" $
            withInMemoryIndexerRunner $ \handle runner -> do
                result <-
                    runOutsideTransactionProbe
                        runner
                        (csHandlers $ probeConfig handle)
                expectProbeFailure result

                fmap crAid <$> liveCheckpoints (checkpointView handle)
                    `shouldReturn` [probeAid]
                payerUtxos handle payerAddress
                    `shouldReturn` [(payerTxIn, payerTxOut)]
                getRollbackHistory handle `shouldReturn` []

        it "does not expose checkpoint or payer state from a failed block" $
            withInMemoryIndexerRunner $ \handle _runner -> do
                let config = probeConfig handle
                initial <- newFollowerState handle False
                let failingState =
                        withFollowerHandlers
                            (csInterestSet config)
                            (csHandlers config <> (crashingHandler :| []))
                            initial

                result <-
                    try @IOException $
                        processFollowerBlock
                            handle
                            failingState
                            2_160
                            True
                            probeSlot
                            probeHash
                            probeOps
                expectProbeFailure result

                assertNoDerivedState handle

                cleanInitial <- newFollowerState handle False
                let configuredState =
                        withFollowerHandlers
                            (csInterestSet config)
                            (csHandlers config)
                            cleanInitial
                (_next, processed) <-
                    processFollowerBlock
                        handle
                        configuredState
                        2_160
                        True
                        probeSlot
                        probeHash
                        probeOps
                processed `shouldBe` True
                assertCommittedDerivedState handle

runOutsideTransactionProbe ::
    RunTransaction IO cf columns op ->
    NonEmpty (IndexerHandler columns [UtxoOp]) ->
    IO (Either IOException a)
runOutsideTransactionProbe runner handlers =
    try @IOException $ do
        _ <-
            runTransaction runner $
                Handler.followHandlers handlers probeContext probeOps
        ioError (userError probeFailure)

crashingHandler :: IndexerHandler columns [UtxoOp]
crashingHandler =
    IndexerHandler
        { handlerRestore = \_context _ops -> pure ()
        , handlerFollow =
            \_context _ops -> liftIO $ ioError (userError probeFailure)
        , handlerRollback = \_context _ops -> pure ()
        }

probeConfig :: IndexerHandle -> ChainSyncConfig
probeConfig handle =
    mkChainSyncConfig
        baseConfig
            { icFundingAddrs =
                [ cvAddress (checkpointView handle)
                , payerAddress
                ]
            }
        m1Manifest

probeContext :: HandlerContext SlotNo BlockHash
probeContext =
    HandlerContext
        { hcSlot = probeSlot
        , hcMeta = Just probeHash
        }

probeOps :: [UtxoOp]
probeOps =
    [ checkpointCreate checkpointTxIn probeAid (checkpointDatum probeAid 0)
    , UtxoCreate payerTxIn payerAddress payerTxOut
    ]

assertNoDerivedState :: IndexerHandle -> Expectation
assertNoDerivedState handle = do
    liveCheckpoints (checkpointView handle) `shouldReturn` []
    payerUtxos handle payerAddress `shouldReturn` []
    getRollbackHistory handle `shouldReturn` []

assertCommittedDerivedState :: IndexerHandle -> Expectation
assertCommittedDerivedState handle = do
    fmap crAid <$> liveCheckpoints (checkpointView handle)
        `shouldReturn` [probeAid]
    payerUtxos handle payerAddress
        `shouldReturn` [(payerTxIn, payerTxOut)]
    fmap length (getRollbackHistory handle) `shouldReturn` 1

expectProbeFailure :: Either IOException a -> Expectation
expectProbeFailure result =
    case result of
        Left exception -> show exception `shouldContain` probeFailure
        Right _ -> expectationFailure "atomicity probe did not fail"

probeSlot :: SlotNo
probeSlot = SlotNo 42

probeHash :: BlockHash
probeHash = BlockHash (BS.replicate 32 0xA4)

probeAid :: BS.ByteString
probeAid = BS.replicate 32 0x71

checkpointTxIn :: TxIn
checkpointTxIn = TxIn (BS.replicate 32 0x72) 0

payerAddress :: Address
payerAddress = Address (BS.replicate 29 0x73)

payerTxIn :: TxIn
payerTxIn = TxIn (BS.replicate 32 0x74) 1

payerTxOut :: TxOut
payerTxOut = TxOut "atomicity-probe-payer-output"

probeFailure :: String
probeFailure = "KERI atomicity probe"
