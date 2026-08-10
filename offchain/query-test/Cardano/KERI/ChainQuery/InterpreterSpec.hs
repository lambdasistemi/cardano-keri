{-# LANGUAGE RankNTypes #-}

{- |
Module      : Cardano.KERI.ChainQuery.InterpreterSpec
Description : #257 RED — both interpreter semantics via fake interpreters

Proves DAT-257-RESULT: every successful snapshot states its source and
consistency (DATA-INV-257-03), and the watermark is always attached even
when the composed program never calls 'Cardano.KERI.ChainQuery.Program.storeWatermark'
directly. Exercised against two fake interpreters standing in for "both
interpreter semantics" (RQ-257-05) without any live provider.

\#262 A-262-01 repair: also proves the eager-rejection contract at the layer
where it can actually fail -- the PUBLIC PRODUCTION SNAPSHOT RUNNER, not the
bare 'Cardano.KERI.ChainQuery.Interpreter.runChainQuery' one layer below it.
See 'eagerRejectionThroughProductionRunners'.
-}
module Cardano.KERI.ChainQuery.InterpreterSpec (spec) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    runChainQuery,
    runChainQueryResultSnapshot,
    runChainQuerySnapshot,
 )
import Cardano.KERI.ChainQuery.Program (
    ChainQuery,
    boardCatalog,
    boardCatalogWithOutputs,
    currentCheckpoint,
    liveCheckpoints,
    outputAt,
    payerUtxos,
    referenceScripts,
    storeWatermark,
 )
import Cardano.KERI.ChainQuery.Types (
    BoardLocator (..),
    ChainQueryError (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    OutputLocator (..),
    QuerySnapshot (..),
    QuerySource (..),
    SnapshotConsistency (..),
 )
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Foldable (for_)
import Data.Functor (void)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldNotBe,
 )

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.Interpreter" $ do
    it "attaches AtomicLocal consistency and a populated watermark for the local interpreter shape" $ do
        result <-
            runChainQuerySnapshot
                (fakeInterpreter SourceLocal AtomicLocal (Populated testWatermark))
                (currentCheckpoint testLocator testAid)
        case result of
            Right snapshot -> do
                snapshotSource snapshot `shouldBe` SourceLocal
                snapshotConsistency snapshot `shouldBe` AtomicLocal
                snapshotWatermark snapshot `shouldBe` Populated testWatermark
            Left err -> fail ("expected a snapshot, got " <> show err)

    it "attaches LegacySequential consistency for the Koios interpreter shape (RQ-257-05)" $ do
        result <-
            runChainQuerySnapshot
                (fakeInterpreter SourceKoios LegacySequential (Populated testWatermark))
                (currentCheckpoint testLocator testAid)
        case result of
            Right snapshot -> snapshotConsistency snapshot `shouldBe` LegacySequential
            Left err -> fail ("expected a snapshot, got " <> show err)

    it "never renders a LegacySequential snapshot as AtomicLocal (INV-257-CONSISTENCY)" $ do
        result <-
            runChainQuerySnapshot
                (fakeInterpreter SourceKoios LegacySequential (Populated testWatermark))
                (currentCheckpoint testLocator testAid)
        case result of
            Right snapshot -> snapshotConsistency snapshot `shouldNotBe` AtomicLocal
            Left err -> fail ("expected a snapshot, got " <> show err)

    it "reports the explicit cold-store case rather than a populated watermark" $ do
        result <-
            runChainQuerySnapshot
                (fakeInterpreter SourceLocal AtomicLocal Cold)
                (currentCheckpoint testLocator testAid)
        case result of
            Right snapshot -> snapshotWatermark snapshot `shouldBe` Cold
            Left err -> fail ("expected a snapshot, got " <> show err)

    it "propagates an operation error instead of returning a partial snapshot" $ do
        let ambiguousInterpreter :: ChainQueryInterpreter IO
            ambiguousInterpreter =
                chainQueryInterpreter
                    (\_ _ -> pure (Left (AmbiguousCurrentState "two live checkpoints")))
                    (\_ -> pure (Right []))
                    (\_ -> pure (Right []))
                    (\_ -> pure (Right []))
                    (\_ -> pure (Right []))
                    (\_ -> pure (Right []))
                    (\_ -> pure (Left (UnsupportedOperation "outputAt")))
                    (pure (Right Cold))
                    SourceKoios
                    LegacySequential
        result <- runChainQuerySnapshot ambiguousInterpreter (currentCheckpoint testLocator testAid)
        case result of
            Left (AmbiguousCurrentState _) -> pure ()
            other -> fail ("expected AmbiguousCurrentState, got " <> show other)

    eagerRejectionThroughProductionRunners

{- | A-262-01 (RQ-262-03\/DATA-INV-262-01): an eagerly rejected argument
reaches the caller having invoked ZERO interpreter handlers -- including the
watermark handler -- through the PUBLIC PRODUCTION SNAPSHOT RUNNER.

This is a repair, and the layer is the whole point of it. The shipped
eager-rejection proof ran against
'Cardano.KERI.ChainQuery.Interpreter.runChainQuery', one layer BELOW what
production calls. At that layer the contract held and the suite was green,
while the runner production actually used composed 'storeWatermark' onto
every program unconditionally and dispatched it after the rejection. A proof
aimed where the failure cannot occur reports the absence of a failure it
could never have seen.

The instrument is the fresh auditor's own frozen two-layer shape
(@commit-auditor-s1-v1@, @eager-rejection-snapshot.hs@, receipt sha256
@4fefa0bc0833017e573af7ff60e2321baef483ba74e578172ae56f7dfed1e50e@): a
call-logging interpreter, proved able to observe a known effect BEFORE any
absence it reports is believed, then run against every rejectable family.

Three things make the zero non-vacuous, and all three are executed here:

  * the detector is shown observing a real watermark effect before any
    absence it reports is believed;
  * a VALID program through the same runner is required to log a non-empty
    call list -- otherwise "logged nothing" would also be true of a runner
    that does nothing at all;
  * the unconditional-watermark runner is asserted to STILL read the
    watermark after an eager rejection, so the reason it is excluded from
    the write path stays a tested fact rather than a comment, and the
    detector is proved able to go the other way.
-}
eagerRejectionThroughProductionRunners :: Spec
eagerRejectionThroughProductionRunners =
    describe
        "#262 RQ-262-03/DATA-INV-262-01 -- an eagerly rejected argument invokes \
        \zero handlers through the public production snapshot runner (A-262-01)"
        $ do
            it "self-test: the detector observes a known watermark effect" $ do
                calls <- newIORef []
                _ <- runChainQuery (loggingInterpreter calls) storeWatermark
                readIORef calls `shouldReturnList` ["storeWatermark"]

            it "self-test: a VALID program through the production runner still dispatches, so an empty log is not vacuous" $ do
                calls <- newIORef []
                _ <-
                    runProductionSnapshot
                        productionRunners
                        (loggingInterpreter calls)
                        (currentCheckpoint testLocator testAid)
                logged <- readIORef calls
                logged `shouldNotBe` []

            for_ rejectableFamilies $ \(label, program) ->
                it (label <> ": zero handlers, zero watermark handler, InvalidLocator") $ do
                    calls <- newIORef []
                    outcome <-
                        runProductionSnapshot
                            productionRunners
                            (loggingInterpreter calls)
                            program
                    logged <- readIORef calls
                    logged `shouldBe` []
                    case outcome of
                        Left (InvalidLocator _) -> pure ()
                        other ->
                            expectationFailure
                                ("expected a named InvalidLocator, got " <> show other)

            it "the unconditional-watermark runner still reads the watermark after an eager rejection, which is exactly why the write path must not name it" $ do
                calls <- newIORef []
                _ <-
                    runChainQuerySnapshot
                        (loggingInterpreter calls)
                        (outputAt invalidOutputLocator)
                readIORef calls `shouldReturnList` ["storeWatermark"]

{- | Every smart constructor that can reject a concrete argument eagerly,
each paired with an argument it must reject. Enumerated rather than sampled:
a family missing from this list is a family whose production runner nobody
checks, which is precisely how the repaired defect survived.
-}
rejectableFamilies :: [(String, ChainQuery (Either ChainQueryError ()))]
rejectableFamilies =
    [ ("outputAt", void' (outputAt invalidOutputLocator))
    , ("boardCatalogWithOutputs", void' (boardCatalogWithOutputs invalidBoardLocator))
    , ("boardCatalog", void' (boardCatalog invalidBoardLocator))
    , ("currentCheckpoint", void' (currentCheckpoint invalidCheckpointLocator testAid))
    , ("currentCheckpoint (malformed AID)", void' (currentCheckpoint testLocator "not-an-aid"))
    , ("liveCheckpoints", void' (liveCheckpoints invalidCheckpointLocator))
    , ("payerUtxos (empty selector)", void' (payerUtxos []))
    , ("payerUtxos (malformed address)", void' (payerUtxos ["not-an-address"]))
    , ("referenceScripts", void' (referenceScripts ["not-canonical-hex"]))
    ]

-- | Erase a family's result type so one list can carry every family.
void' :: ChainQuery (Either ChainQueryError a) -> ChainQuery (Either ChainQueryError ())
void' = fmap void

invalidOutputLocator :: OutputLocator
invalidOutputLocator =
    OutputLocator{outputLocatorTxId = T.replicate 64 "A", outputLocatorIndex = 0}

invalidBoardLocator :: BoardLocator
invalidBoardLocator =
    BoardLocator{boardLocatorPolicyId = "not-a-policy-id", boardLocatorAddress = "not-an-address"}

invalidCheckpointLocator :: CheckpointLocator
invalidCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = "not-a-policy-id"
        , checkpointLocatorAddress = "not-an-address"
        }

{- | The public production snapshot runner under test, behind one named
field so this property is aimed at whatever the write path actually calls.
Binding it to the layer BELOW production is the defect this repair exists to
close, so the binding is stated once, here, and nowhere else.
-}
newtype SnapshotRunners = SnapshotRunners
    { runProductionSnapshot ::
        forall a.
        ChainQueryInterpreter IO ->
        ChainQuery (Either ChainQueryError a) ->
        IO (Either ChainQueryError (QuerySnapshot a))
    }

productionRunners :: SnapshotRunners
productionRunners = SnapshotRunners{runProductionSnapshot = runChainQueryResultSnapshot}

{- | A call-logging interpreter: every handler records its own name. Total,
so an unexpected invocation shows up as an extra log entry rather than an
exception that could be confused with unrelated breakage.
-}
loggingInterpreter :: IORef [String] -> ChainQueryInterpreter IO
loggingInterpreter calls =
    chainQueryInterpreter
        (\_ _ -> observed "currentCheckpoint" (Right Nothing))
        (\_ -> observed "liveCheckpoints" (Right []))
        (\_ -> observed "referenceScripts" (Right []))
        (\_ -> observed "boardCatalog" (Right []))
        (\_ -> observed "boardCatalogWithOutputs" (Right []))
        (\_ -> observed "payerUtxos" (Right []))
        (\_ -> observed "outputAt" (Left (UnsupportedOperation "unexpected test effect")))
        (observed "storeWatermark" (Right Cold))
        SourceLocal
        AtomicLocal
  where
    observed label result = modifyIORef' calls (<> [label]) >> pure result

shouldReturnList :: IO [String] -> [String] -> IO ()
shouldReturnList action expected = action >>= (`shouldBe` expected)

{- | A canonical checkpoint locator and AID, so every operation this file
composes actually reaches the fake interpreter under test rather than
being rejected structurally before interpretation (DATA-INV-257-01).
-}
testAid :: Text
testAid = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

testLocator :: CheckpointLocator
testLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 0x00))
        , checkpointLocatorAddress = Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes (BS.replicate 28 0x00))
        }

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

testWatermark :: ChainWatermark
testWatermark =
    ChainWatermark
        { watermarkSlot = 42
        , watermarkBlockHash = "deadbeef"
        }

{- | Answers every collection-valued operation successfully with an
empty\/absent value, always reporting the given source, consistency, and
watermark.

\#262: the exact-output operation has no empty value to answer with -- it
resolves exactly one row or fails (RQ-262-01) -- so this double accounts for
it with a named 'UnsupportedOperation' rather than inventing an output. No
example here composes it; a future one that did would see an explicit
refusal, never a fabricated row.
-}
fakeInterpreter ::
    QuerySource -> SnapshotConsistency -> ColdOr ChainWatermark -> ChainQueryInterpreter IO
fakeInterpreter source consistency watermark =
    chainQueryInterpreter
        (\_ _ -> pure (Right Nothing))
        (\_ -> pure (Right []))
        (\_ -> pure (Right []))
        (\_ -> pure (Right []))
        (\_ -> pure (Right []))
        (\_ -> pure (Right []))
        (\_ -> pure (Left (UnsupportedOperation "outputAt")))
        (pure (Right watermark))
        source
        consistency
