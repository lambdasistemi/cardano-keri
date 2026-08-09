{- |
Module      : Cardano.KERI.ChainQuery.InterpreterSpec
Description : #257 RED — both interpreter semantics via fake interpreters

Proves DAT-257-RESULT: every successful snapshot states its source and
consistency (DATA-INV-257-03), and the watermark is always attached even
when the composed program never calls 'Cardano.KERI.ChainQuery.Program.storeWatermark'
directly. Exercised against two fake interpreters standing in for "both
interpreter semantics" (RQ-257-05) without any live provider.
-}
module Cardano.KERI.ChainQuery.InterpreterSpec (spec) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    runChainQuerySnapshot,
 )
import Cardano.KERI.ChainQuery.Program (currentCheckpoint)
import Cardano.KERI.ChainQuery.Types (
    ChainQueryError (..),
    ChainWatermark (..),
    CheckpointLocator (..),
    ColdOr (Cold, Populated),
    QuerySnapshot (..),
    QuerySource (..),
    SnapshotConsistency (..),
 )
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Test.Hspec (
    Spec,
    describe,
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
                    (pure (Right Cold))
                    SourceKoios
                    LegacySequential
        result <- runChainQuerySnapshot ambiguousInterpreter (currentCheckpoint testLocator testAid)
        case result of
            Left (AmbiguousCurrentState _) -> pure ()
            other -> fail ("expected AmbiguousCurrentState, got " <> show other)

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

{- | Answers every operation successfully with an empty/absent value, always
reporting the given source, consistency, and watermark.
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
        (pure (Right watermark))
        source
        consistency
