{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Indexer.RollbackSpec (spec) where

import Cardano.KERI.Indexer.Codecs (
    CheckpointRecord,
 )
import Cardano.KERI.Indexer.Reads (
    checkpointForAid,
    liveCheckpoints,
 )
import Cardano.KERI.Indexer.ReadsSpec (
    checkpointCreate,
    checkpointDatum,
    checkpointView,
 )
import Cardano.Node.Client.UTxOIndexer.Columns (
    Cols (..),
 )
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerFollowerState,
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types (
    AddrKey,
    Address,
    BlockHash (..),
    SlotNo (..),
    TxIn (..),
    TxOut,
 )
import ChainFollower.Rollbacks.Types (
    RollbackPoint,
 )
import Control.Monad (
    foldM,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.Word (
    Word16,
    Word8,
 )
import Database.KV.Cursor (
    Cursor,
    Entry (..),
    firstEntry,
    nextEntry,
 )
import Database.KV.Transaction (
    KV,
    RunTransaction (..),
    iterating,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
 )
import Test.QuickCheck (
    Gen,
    Property,
    checkCoverage,
    choose,
    chooseInt,
    conjoin,
    counterexample,
    cover,
    forAll,
    ioProperty,
    property,
    tabulate,
    (===),
 )

spec :: Spec
spec =
    describe "rollback exactness"
        $ it
            "matches replay over the complete checkpoint store after a fork"
        $ property
        $ checkCoverage
        $ forAll genForkCase
        $ \fork ->
            tabulate
                "rollback path"
                ["branch A spends and restores a prefix checkpoint"]
                $ cover
                    100
                    (branchASpendsPrefix fork)
                    "branch A spends a prefix checkpoint"
                $ ioProperty (rollbackExactness fork)

{- |
FR-6 / epic ruling A-002 inheritance argument: the upstream engine owns
the inverse and the KERI checkpoint view is a pure function of
@AddressIndex@, so exact store rollback necessarily yields an exact view.
Both arms deliberately start with @newFollowerState False@ and use the
same within-stability-window signal, keeping every row in following phase
and preventing restoration sentinels from making @RollbackCol@ differ for
an unrelated phase-shape reason.

The one upstream exception is documented by
@UTxOIndexer.Indexer.applyRollbackEntry@: restoring a spent prefix UTxO
writes the abandoned block's rollback slot/hash into @ObservationCol@
instead of its original creation point. Workaround-for=UNFILED: compare
that column's key set exactly, and assert its values still differ. That
last sentinel is intentionally self-policing: when upstream fixes the
imprecision, this test turns red so the exclusion must be removed.
-}
rollbackExactness :: ForkCase -> IO Property
rollbackExactness fork = do
    live <- runLiveArm fork
    replay <- runReplayArm fork
    pure $
        conjoin
            [ namedEquality
                "TxInCol"
                (storeTxIns $ armStore live)
                (storeTxIns $ armStore replay)
            , namedEquality
                "AddressIndex"
                (storeAddresses $ armStore live)
                (storeAddresses $ armStore replay)
            , namedEquality
                "RollbackCol"
                (storeRollbacks $ armStore live)
                (storeRollbacks $ armStore replay)
            , namedEquality
                "ObservationCol key set"
                (map fst . storeObservations $ armStore live)
                (map fst . storeObservations $ armStore replay)
            , counterexample
                "workaround-for=UNFILED is stale: ObservationCol values now match"
                ( lookup
                    (prefixCheckpointTxIn fork)
                    (storeObservations $ armStore live)
                    /= lookup
                        (prefixCheckpointTxIn fork)
                        (storeObservations $ armStore replay)
                )
            , counterexample
                "replay store is empty"
                (not . null . storeTxIns $ armStore replay)
            , counterexample
                "replay store has no checkpoint-shaped records"
                (not . null $ armCheckpoints replay)
            , namedEquality
                "liveCheckpoints"
                (armCheckpoints live)
                (armCheckpoints replay)
            , namedEquality
                "checkpointForAid"
                (armAidLookups live)
                (armAidLookups replay)
            ]

runLiveArm :: ForkCase -> IO ArmResult
runLiveArm fork =
    withInMemoryIndexerRunner $ \handle runner -> do
        initial <- newFollowerState handle False
        afterPrefix <- applyBlocks handle initial (prefixBlocks fork)
        afterBranchA <- applyBlocks handle afterPrefix (branchABlocks fork)
        afterRollback <-
            rollbackFollowerState handle afterBranchA (forkPoint fork)
        _afterBranchB <-
            applyBlocks handle afterRollback (branchBBlocks fork)
        collectArmResult handle runner (winningAids fork)

runReplayArm :: ForkCase -> IO ArmResult
runReplayArm fork =
    withInMemoryIndexerRunner $ \handle runner -> do
        initial <- newFollowerState handle False
        afterPrefix <- applyBlocks handle initial (prefixBlocks fork)
        _afterBranchB <-
            applyBlocks handle afterPrefix (branchBBlocks fork)
        collectArmResult handle runner (winningAids fork)

applyBlocks ::
    IndexerHandle ->
    IndexerFollowerState ->
    [ForkBlock] ->
    IO IndexerFollowerState
applyBlocks handle = foldM (applyBlock handle)

applyBlock ::
    IndexerHandle ->
    IndexerFollowerState ->
    ForkBlock ->
    IO IndexerFollowerState
applyBlock handle state ForkBlock{blockSlot, blockHash, blockOps} = do
    (next, processed) <-
        processFollowerBlock
            handle
            state
            10_000
            True
            blockSlot
            blockHash
            blockOps
    if processed
        then pure next
        else fail "RollbackSpec: follower declined a generated block"

collectArmResult ::
    IndexerHandle ->
    RunTransaction IO cf Cols op ->
    [ByteString] ->
    IO ArmResult
collectArmResult handle runner aids = do
    let view = checkpointView handle
    armStore <- dumpStore runner
    armCheckpoints <- liveCheckpoints view
    armAidLookups <-
        traverse
            (\aid -> (aid,) <$> checkpointForAid view aid)
            aids
    pure ArmResult{armStore, armCheckpoints, armAidLookups}

dumpStore :: RunTransaction IO cf Cols op -> IO StoreDump
dumpStore runner = do
    storeTxIns <- dumpColumn runner TxInCol
    storeAddresses <- dumpColumn runner AddressIndex
    storeObservations <- dumpColumn runner ObservationCol
    storeRollbacks <- dumpColumn runner RollbackCol
    pure
        StoreDump
            { storeTxIns
            , storeAddresses
            , storeObservations
            , storeRollbacks
            }

dumpColumn ::
    RunTransaction IO cf Cols op ->
    Cols (KV key value) ->
    IO [(key, value)]
dumpColumn RunTransaction{runTransaction} column =
    runTransaction $ iterating column collectEntries

collectEntries ::
    (Monad m) =>
    Cursor m (KV key value) [(key, value)]
collectEntries =
    firstEntry >>= go
  where
    go Nothing = pure []
    go (Just Entry{entryKey, entryValue}) = do
        rest <- nextEntry >>= go
        pure ((entryKey, entryValue) : rest)

namedEquality ::
    (Eq a, Show a) =>
    String ->
    a ->
    a ->
    Property
namedEquality columnName live replay =
    counterexample
        ( columnName
            <> " diverged\nlive: "
            <> show live
            <> "\nreplay: "
            <> show replay
        )
        (live === replay)

genForkCase :: Gen ForkCase
genForkCase =
    ForkCase
        <$> choose (0, maxBound)
        <*> chooseInt (1, 3)
        <*> chooseInt (1, 3)
        <*> chooseInt (1, 3)

prefixBlocks :: ForkCase -> [ForkBlock]
prefixBlocks fork@ForkCase{prefixLength} =
    [ checkpointBlock
        fork
        prefixDomain
        index
        index
    | index <- [1 .. prefixLength]
    ]

branchABlocks :: ForkCase -> [ForkBlock]
branchABlocks fork@ForkCase{prefixLength, branchALength} =
    [ ForkBlock
        { blockSlot = SlotNo . fromIntegral $ prefixLength + index
        , blockHash = taggedBlockHash fork branchADomain index
        , blockOps =
            [UtxoSpend $ prefixCheckpointTxIn fork | index == 1]
                <> [checkpointOp fork branchADomain index]
        }
    | index <- [1 .. branchALength]
    ]

branchBBlocks :: ForkCase -> [ForkBlock]
branchBBlocks fork@ForkCase{prefixLength, branchBLength} =
    [ checkpointBlock
        fork
        branchBDomain
        index
        (prefixLength + index)
    | index <- [1 .. branchBLength]
    ]

checkpointBlock ::
    ForkCase ->
    Word8 ->
    Int ->
    Int ->
    ForkBlock
checkpointBlock fork domain index slot =
    ForkBlock
        { blockSlot = SlotNo (fromIntegral slot)
        , blockHash = taggedBlockHash fork domain index
        , blockOps = [checkpointOp fork domain index]
        }

checkpointOp :: ForkCase -> Word8 -> Int -> UtxoOp
checkpointOp fork domain index =
    checkpointCreate
        (taggedTxIn fork domain index)
        (taggedAid fork domain index)
        ( checkpointDatum
            (taggedAid fork domain index)
            (fromIntegral index)
        )

prefixCheckpointTxIn :: ForkCase -> TxIn
prefixCheckpointTxIn fork = taggedTxIn fork prefixDomain 1

winningAids :: ForkCase -> [ByteString]
winningAids fork@ForkCase{prefixLength, branchBLength} =
    [taggedAid fork prefixDomain index | index <- [1 .. prefixLength]]
        <> [taggedAid fork branchBDomain index | index <- [1 .. branchBLength]]

forkPoint :: ForkCase -> SlotNo
forkPoint ForkCase{prefixLength} = SlotNo (fromIntegral prefixLength)

branchASpendsPrefix :: ForkCase -> Bool
branchASpendsPrefix fork =
    case branchABlocks fork of
        ForkBlock{blockOps} : _ ->
            UtxoSpend (prefixCheckpointTxIn fork) `elem` blockOps
        [] -> False

taggedTxIn :: ForkCase -> Word8 -> Int -> TxIn
taggedTxIn fork domain index =
    TxIn
        { txInId = taggedBytes fork domain index
        , txInIx = fromIntegral index :: Word16
        }

taggedAid :: ForkCase -> Word8 -> Int -> ByteString
taggedAid fork domain =
    taggedBytes fork (domain + 1)

taggedBlockHash :: ForkCase -> Word8 -> Int -> BlockHash
taggedBlockHash fork domain index =
    BlockHash (taggedBytes fork (domain + 2) index)

taggedBytes :: ForkCase -> Word8 -> Int -> ByteString
taggedBytes ForkCase{forkSalt} domain index =
    BS.pack [forkSalt, domain, fromIntegral index]
        <> BS.replicate 29 domain

prefixDomain, branchADomain, branchBDomain :: Word8
prefixDomain = 0x10
branchADomain = 0x40
branchBDomain = 0x70

data ForkCase = ForkCase
    { forkSalt :: !Word8
    , prefixLength :: !Int
    , branchALength :: !Int
    , branchBLength :: !Int
    }
    deriving stock (Eq, Show)

data ForkBlock = ForkBlock
    { blockSlot :: !SlotNo
    , blockHash :: !BlockHash
    , blockOps :: ![UtxoOp]
    }
    deriving stock (Eq, Show)

data StoreDump = StoreDump
    { storeTxIns :: ![(TxIn, Address)]
    , storeAddresses :: ![(AddrKey, TxOut)]
    , storeObservations :: ![(TxIn, (SlotNo, BlockHash))]
    , storeRollbacks ::
        ![(SlotNo, RollbackPoint [UtxoOp] BlockHash)]
    }
    deriving stock (Eq, Show)

data ArmResult = ArmResult
    { armStore :: !StoreDump
    , armCheckpoints :: ![CheckpointRecord]
    , armAidLookups ::
        ![(ByteString, Maybe CheckpointRecord)]
    }
    deriving stock (Eq, Show)
