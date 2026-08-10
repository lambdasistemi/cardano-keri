{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Indexer.ChainQuerySpec
Description : #257 RED — local interpreter: one-run execution and atomicity

Proves FUN-257-LOCAL-TRANSLATE/T257-S2-03 (the public local runner invokes
the existing 'RunTransaction' exactly once for a whole multi-operation
program, reusing the countingRunner pattern from
"Cardano.KERI.Indexer.Query.TxSpec") and INV-257-ATOMIC/INV-257-WATERMARK
(T257-S2-04/05): a whole program's rows and watermark always describe the
same applied version, and the property is proven able to fail under an
intentional split-run mutation — two separate transaction calls with a block
application deterministically interleaved between them, via explicit
'MVar' synchronization rather than a timing-dependent race.
-}
module Cardano.KERI.Indexer.ChainQuerySpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    interpreterConsistency,
    interpreterSource,
    runChainQuery,
 )
import Cardano.KERI.ChainQuery.Program (boardCatalog, currentCheckpoint, payerUtxos, referenceScripts, storeWatermark)
import Cardano.KERI.ChainQuery.Types (
    BoardLocator (..),
    ChainQueryError (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    QuerySnapshot (..),
    QuerySource (SourceLocal),
    SnapshotConsistency (AtomicLocal, LegacySequential),
 )
import Cardano.KERI.Indexer.ChainQuery (localInterpreter, queryHandleLocalScope, runLocalChainQuery)
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..), payerUtxosTxAcrossAddresses, watermarkTx)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Out (mkBasicTxOut)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Binary (serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut, eraProtVerLow)
import Cardano.Ledger.Credential (Credential (KeyHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..))
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..), PolicyID (..))
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (UpstreamConnected))
import Cardano.Node.Client.UTxOIndexer.Columns (Cols)
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (
    IndexerHandle (..),
    UtxoOp (..),
    withInMemoryIndexerRunner,
 )
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent.Async (async, wait)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.STM (STM)
import Control.Monad (join)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Maybe (fromJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.Word (Word8)
import Database.KV.Transaction (RunTransaction (..), Transaction)
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

spec :: Spec
spec = describe "Cardano.KERI.Indexer.ChainQuery (#257 S257-2)" $ do
    it "invokes the existing transaction runner exactly once for a multi-operation program (T257-S2-03)" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x10) addrA]
            counter <- newIORef (0 :: Int)
            let qHandle = queryHandleLocalScope (testQueryHandle (countingRunner counter runner))
            result <- runLocalChainQuery qHandle (payerUtxos [addrText addrA])
            count <- readIORef counter
            count `shouldBe` 1
            case result of
                Right snapshot -> case snapshotValue snapshot of
                    Right utxos -> length utxos `shouldBe` 1
                    Left err -> fail ("expected a resolved payer list, got " <> show err)
                Left err -> fail ("expected a snapshot, got " <> show err)

    it "the concurrent property is observed failing under an intentional split-run mutation (T257-S2-05)" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x10) addrA]
            advanceSignal <- newEmptyMVar
            advanced <- newEmptyMVar
            writer <- async $ do
                takeMVar advanceSignal
                applyAtSlot handle (Indexer.SlotNo 20) (blockHash 0x02) [payerCreate (sampleTxIn 0x11) addrA]
                putMVar advanced ()
            -- MUTATION: two separate transactions instead of the local
            -- interpreter's single composed transaction. Deterministically
            -- interleave a block application between them.
            rowsBefore <- runTransaction runner (payerUtxosTxAcrossAddresses [addrA])
            putMVar advanceSignal ()
            takeMVar advanced
            watermarkAfter <- runTransaction runner watermarkTx
            wait writer
            -- The split-run rows describe slot 10 (one row) while the
            -- watermark describes slot 20 — an incoherent pair a whole
            -- one-shot program can never produce.
            length rowsBefore `shouldBe` 1
            watermarkAfter `shouldNotBe` Just (Indexer.SlotNo 10)

    it "a whole one-shot program never produces that incoherent pair (INV-257-ATOMIC restored)" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x10) addrA]
            let qHandle = queryHandleLocalScope (testQueryHandle runner)
            advanced <- newEmptyMVar
            -- The concurrent writer races against the reader with no
            -- handshake at all: it starts immediately and may run before,
            -- during (blocked on the runner's own mutex), or after the
            -- reader's single composed transaction. Every outcome must
            -- still be coherent.
            writer <- async $ do
                applyAtSlot handle (Indexer.SlotNo 20) (blockHash 0x02) [payerCreate (sampleTxIn 0x11) addrA]
                putMVar advanced ()
            result <- runLocalChainQuery qHandle (payerUtxos [addrText addrA])
            takeMVar advanced
            wait writer
            case result of
                Right snapshot -> case (snapshotWatermark snapshot, snapshotValue snapshot) of
                    (Populated watermark, Right utxos) -> do
                        -- Coherent by construction: either the watermark is
                        -- still slot 10 and exactly one row is visible, or
                        -- the watermark has advanced to slot 20 and exactly
                        -- two rows are visible — never one row with slot 20,
                        -- and never two rows with slot 10.
                        expectedRowCount watermark `shouldBe` length utxos
                        -- DATA-INV-257-02: the watermark's block hash must be
                        -- the EXACT hash of its own bound slot, not just a
                        -- row-count-consistent slot number — a constant or
                        -- swapped hash must fail this.
                        watermarkBlockHash watermark `shouldBe` expectedBlockHash watermark
                    (Cold, _) -> fail "expected a populated watermark"
                    (_, Left err) -> fail ("expected a resolved payer list, got " <> show err)
                Left err -> fail ("expected a snapshot, got " <> show err)

    it "the named coherence property fails under a production-path split-transaction mutation, then passes restored (T257-S2-04, frozen production-path proof)" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyAtSlot handle (Indexer.SlotNo 10) (blockHash 0x01) [payerCreate (sampleTxIn 0x10) addrA]
            advanceSignal <- newEmptyMVar
            advanced <- newEmptyMVar
            writer <- async $ do
                takeMVar advanceSignal
                applyAtSlot handle (Indexer.SlotNo 20) (blockHash 0x02) [payerCreate (sampleTxIn 0x11) addrA]
                putMVar advanced ()
            -- 'syncingRunner' releases the concurrent writer exactly after
            -- its FIRST wrapped transaction call and forces any SECOND call
            -- to wait for the writer's commit. A correct single-transaction
            -- 'runLocalChainQuery' makes exactly one call, so the release
            -- happens only after its (already-computed) coherent result --
            -- deterministically slot 10\/one row every time. A
            -- split-transaction defect's second call is forced to observe
            -- the writer's already-applied block while its first call could
            -- not have -- reproducing T257-S2-04's incoherent pair against
            -- the real production entrypoint, not a bespoke bypass.
            wrapped <- syncingRunner advanceSignal advanced runner
            let qHandle = queryHandleLocalScope (testQueryHandle wrapped)
            result <- runLocalChainQuery qHandle (payerUtxos [addrText addrA])
            wait writer
            case result of
                Right snapshot -> case (snapshotWatermark snapshot, snapshotValue snapshot) of
                    (Populated watermark, Right utxos) -> do
                        expectedRowCount watermark `shouldBe` length utxos
                        watermarkBlockHash watermark `shouldBe` expectedBlockHash watermark
                    (Cold, _) -> fail "expected a populated watermark"
                    (_, Left err) -> fail ("expected a resolved payer list, got " <> show err)
                Left err -> fail ("expected a snapshot, got " <> show err)

    describe "local interpreter locator validation fails closed before any store effect (DATA-INV-257-01)" $ do
        -- A-006/DATA-INV-257-01: these run through 'runChainQuery', the only
        -- publicly reachable path, because 'ChainQueryInterpreter' no longer
        -- has field selectors to invoke directly (see
        -- "Cardano.KERI.ChainQuery.Interpreter"). Reaching the interpreter at
        -- all now requires a 'ChainQuery' value, and those can only come from
        -- Program.hs's eagerly validating smart constructors.
        it "rejects an empty checkpoint locator" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                let qHandle = queryHandleLocalScope (testQueryHandle runner)
                result <-
                    runTransaction runner $
                        runChainQuery
                            (localInterpreter qHandle)
                            (currentCheckpoint (CheckpointLocator "" "") validAidText)
                join result `shouldSatisfy` isLeftInvalidLocator

        it "rejects a checkpoint locator that disagrees with the store's own configuration, rather than silently answering for it" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                -- Canonical in SHAPE, so Program.hs's eager validation passes
                -- it through and the store-identity check inside the local
                -- interpreter is what must reject it. The pre-A-006 version of
                -- this test used non-canonical strings, which are rejected
                -- earlier and left this branch untested.
                let qHandle = queryHandleLocalScope (testQueryHandle runner)
                result <-
                    runTransaction runner $
                        runChainQuery
                            (localInterpreter qHandle)
                            (currentCheckpoint mismatchingCheckpointLocator validAidText)
                join result `shouldSatisfy` isLeftInvalidLocator

        it "rejects an empty board locator" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                let qHandle = queryHandleLocalScope (testQueryHandle runner)
                result <-
                    runTransaction runner $
                        runChainQuery (localInterpreter qHandle) (boardCatalog (BoardLocator "" ""))
                join result `shouldSatisfy` isLeftInvalidLocator

        it "rejects a board locator whose address disagrees with the store's own board address, rather than silently answering for it" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                -- Canonical in shape for the same reason as the checkpoint
                -- case above: only the store-identity branch can reject it.
                let qHandle = queryHandleLocalScope (testQueryHandle runner)
                result <-
                    runTransaction runner $
                        runChainQuery (localInterpreter qHandle) (boardCatalog mismatchingBoardLocator)
                join result `shouldSatisfy` isLeftInvalidLocator

        it "structurally rejects a malformed current-checkpoint AID before ever invoking the interpreter, with an otherwise-valid locator (NOTE-020)" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                result <-
                    runTransaction runner $
                        runChainQuery
                            (poisonExceptWatermark Cold)
                            (currentCheckpoint validCheckpointLocatorForHandle "not-a-valid-keri-aid")
                case result of
                    Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                    Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

        it "structurally rejects an empty payer-address set before ever invoking the interpreter, rather than answering it vacuously (NOTE-020)" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                result <- runTransaction runner $ runChainQuery (poisonExceptWatermark Cold) (payerUtxos [])
                case result of
                    Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                    Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

        it "structurally rejects a malformed reference hash before ever invoking the interpreter (NOTE-020)" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                result <-
                    runTransaction runner $
                        runChainQuery (poisonExceptWatermark Cold) (referenceScripts ["not-canonical-hex"])
                case result of
                    Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                    Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

        it "structurally rejects a buried invalid board locator reachable only via a real earlier operation's result, without ever invoking any interpreter field for it (NOTE-020)" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                -- 'poisonExceptWatermark' crashes if ANY field besides the
                -- watermark is ever invoked -- proving this structurally
                -- (DATA-INV-257-01 is not enumerable: no finite fabricated
                -- result set exhausts arbitrary value-sensitive
                -- continuations), not by counting effects on a store that
                -- always legitimately answers the watermark read.
                result <-
                    runTransaction runner $
                        runChainQuery
                            (poisonExceptWatermark (Populated testWatermark))
                            ( do
                                watermark <- storeWatermark
                                case watermark of
                                    Cold -> pure (Right [])
                                    Populated _ -> boardCatalog (BoardLocator "buried-bad-policy" "buried-bad-address")
                            )
                case result of
                    Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                    Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

        it "structurally rejects a buried invalid payer-address set reachable only via a real earlier operation's result, without ever invoking any interpreter field for it (NOTE-020)" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                result <-
                    runTransaction runner $
                        runChainQuery
                            (poisonExceptWatermark (Populated testWatermark))
                            ( do
                                watermark <- storeWatermark
                                case watermark of
                                    Cold -> pure (Right [])
                                    Populated _ -> payerUtxos []
                            )
                case result of
                    Right inner -> inner `shouldSatisfy` isLeftInvalidLocator
                    Left err -> fail ("expected a pure structural rejection, got an interpreter-level error " <> show err)

    describe "the actual production localInterpreter reports its own real provenance (not a fake stand-in), DATA-INV-257-03" $
        it "reports SourceLocal and AtomicLocal, never LegacySequential (INV-257-CONSISTENCY)" $
            withInMemoryIndexerRunner $ \_handle runner -> do
                let interpreter = localInterpreter (queryHandleLocalScope (testQueryHandle runner))
                interpreterSource interpreter `shouldBe` SourceLocal
                interpreterConsistency interpreter `shouldBe` AtomicLocal
                interpreterConsistency interpreter `shouldNotBe` LegacySequential
  where
    expectedRowCount watermark
        | watermarkSlot watermark >= 20 = 2 :: Int
        | otherwise = 1
    expectedBlockHash watermark
        | watermarkSlot watermark >= 20 = hexBS (BS.replicate 32 0x02)
        | otherwise = hexBS (BS.replicate 32 0x01)
    hexBS = TE.decodeUtf8 . convertToBase Base16

isLeftInvalidLocator :: Either ChainQueryError a -> Bool
isLeftInvalidLocator (Left (InvalidLocator _)) = True
isLeftInvalidLocator _ = False

{- | Every field except the watermark crashes if ever invoked (NOTE-020:
proving DATA-INV-257-01 structurally, not by enumeration -- no finite
fabricated result set exhausts arbitrary value-sensitive continuations). A
program that reads a genuine watermark result and branches to a buried
invalid operation must never reach that operation's interpreter field,
however the buried argument was derived -- if a deliberate boundary bypass
ever let it through, this interpreter observably crashes rather than
silently answering.
-}
poisonExceptWatermark :: ColdOr ChainWatermark -> ChainQueryInterpreter (Transaction IO cf Cols op)
poisonExceptWatermark watermark =
    chainQueryInterpreter
        (\_ _ -> error "poison: current-checkpoint must never be reached")
        (\_ -> error "poison: live-checkpoints must never be reached")
        (\_ -> error "poison: reference-scripts must never be reached")
        (\_ -> error "poison: board-catalog must never be reached")
        (\_ -> error "poison: payer-utxos must never be reached")
        (pure (Right watermark))
        SourceLocal
        AtomicLocal

{- | A non-degenerate, distinguishable watermark -- so the "populated"
branch of the buried-operation tests is genuinely reachable via a real
interpreter result, not a placeholder.
-}
testWatermark :: ChainWatermark
testWatermark = ChainWatermark 42 "aabbccdd"

{- | 'QueryHandle' has 'StrictData' fields (this codebase's convention), so
every field is forced at construction time regardless of which operation a
program actually exercises. None of this spec's programs read board\/
checkpoint freshness, so 'unusedCheckpointPolicy'\/'unusedReadiness' below
are harmless fixed values -- never bottoms -- rather than the 'error' calls
a lazy-language instinct might reach for.
-}
testQueryHandle :: RunTransaction IO cf Cols op -> QueryHandle cf op
testQueryHandle runner =
    QueryHandle
        { qhRunner = runner
        , qhCheckpointAddress = addrA
        , qhCheckpointPolicy = unusedCheckpointPolicy
        , qhBoardAddress = addrA
        , qhReadiness = unusedReadiness
        }

-- | Never read: none of this spec's programs consult the checkpoint policy.
unusedCheckpointPolicy :: PolicyID
unusedCheckpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just h -> h
                Nothing -> error "ChainQuerySpec: invalid checkpoint policy id width"

{- | A checkpoint locator that matches 'testQueryHandle''s own
'unusedCheckpointPolicy'\/'addrA' configuration exactly -- the same hex\/
bech32 rendering 'checkpointLocatorOk' computes internally -- so a test can
isolate a DIFFERENT malformed argument (e.g. the AID) without the locator
itself also being the reason for rejection.
-}
validCheckpointLocatorForHandle :: CheckpointLocator
validCheckpointLocatorForHandle =
    CheckpointLocator (TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 0x41))) (addrText addrA)

{- | A canonical AID, so a locator test is not accidentally passing because
the AID was the malformed argument (A-006).
-}
validAidText :: T.Text
validAidText = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

{- | Canonical in shape but NOT the handle's own policy id, so Program.hs's
eager shape validation admits it and only the local interpreter's
store-identity check can reject it (A-006).
-}
mismatchingCheckpointLocator :: CheckpointLocator
mismatchingCheckpointLocator =
    CheckpointLocator (TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 0x42))) (addrText addrA)

{- | Canonical in shape but NOT the handle's own board address, for the same
reason as 'mismatchingCheckpointLocator' (A-006).
-}
mismatchingBoardLocator :: BoardLocator
mismatchingBoardLocator =
    BoardLocator
        (TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 0x41)))
        (addrText (Indexer.Address (BS.replicate 28 0xB2)))

{- | Never read: none of this spec's programs consult board/checkpoint
freshness, and neither does the #257 local interpreter's translation of
the six DAT-257-OP families.
-}
unusedReadiness :: STM Readiness
unusedReadiness =
    pure
        Readiness
            { rProcessedSlot = Nothing
            , rTipSlot = Nothing
            , rUpstream = UpstreamConnected
            , rUpdatedAt = UTCTime (fromGregorian 2026 1 1) 0
            }

payerCreate :: Indexer.TxIn -> Indexer.Address -> UtxoOp
payerCreate txIn addr = UtxoCreate txIn addr (payerOutput addr)

{- | A real CBOR-encoded ledger 'TxOut' (the #257 local interpreter decodes
the indexed payload as a genuine ledger output, not an opaque byte string).
-}
payerOutput :: Indexer.Address -> Indexer.TxOut
payerOutput (Indexer.Address bytes) =
    Indexer.TxOut $
        serialize' (eraProtVerLow @ConwayEra) txOut
  where
    keyHash =
        fromJust (hashFromBytes bytes)
    txOut :: TxOut ConwayEra
    txOut =
        mkBasicTxOut
            (Addr Testnet (KeyHashObj (KeyHash keyHash)) StakeRefNull)
            (MaryValue (Coin 5_000_000) (MultiAsset mempty))

sampleTxIn :: Word8 -> Indexer.TxIn
sampleTxIn byte = Indexer.TxIn (BS.replicate 32 byte) 0

addrA :: Indexer.Address
addrA = Indexer.Address (BS.replicate 28 0xA1)

{- | The bech32 rendering the algebra's payer-address argument expects
(matching Koios's address format); the local interpreter decodes it back
to the exact same raw bytes to scan the store.
-}
addrText :: Indexer.Address -> T.Text
addrText (Indexer.Address bytes) =
    Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes bytes)

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp =
    either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

blockHash :: Word8 -> Indexer.BlockHash
blockHash byte = Indexer.BlockHash (BS.replicate 32 byte)

countingRunner ::
    IORef Int ->
    RunTransaction IO cf Cols op ->
    RunTransaction IO cf Cols op
countingRunner counter runner =
    RunTransaction
        { runTransaction = \tx -> do
            atomicModifyIORef' counter (\n -> (n + 1, ()))
            runTransaction runner tx
        }

{- | Deterministically interleaves a concurrent writer around the WRAPPED
runner's own transaction calls, independent of how many calls the entrypoint
under test actually makes (T257-S2-04's frozen production-path proof,
avoiding a bespoke bypass of the real runner). The FIRST wrapped call
executes normally, then releases 'advanceSignal' (letting a waiting writer
proceed); any SECOND call blocks on 'advanced' until that writer's commit
lands. A correct single-transaction entrypoint makes exactly one call, so
the release fires only after its own coherent result is already computed
and the writer's later commit cannot affect it. A defect that splits one
program's rows and watermark into two separate transaction calls is forced
to observe its first call's pre-write state and its second call's
post-write state -- reproducing the exact incoherent pair.
-}
syncingRunner ::
    MVar () ->
    MVar () ->
    RunTransaction IO cf Cols op ->
    IO (RunTransaction IO cf Cols op)
syncingRunner advanceSignal advanced runner = do
    callCount <- newIORef (0 :: Int)
    pure
        RunTransaction
            { runTransaction = \tx -> do
                n <- atomicModifyIORef' callCount (\c -> (c + 1, c + 1))
                if n == 1
                    then do
                        result <- runTransaction runner tx
                        putMVar advanceSignal ()
                        pure result
                    else do
                        takeMVar advanced
                        runTransaction runner tx
            }
