{- |
Module      : Cardano.KERI.ChainQuery.ProgramSpec
Description : #257 RED — operation surface and free-monad composition

Proves RQ-257-01 (the operation functor contains exactly the six current
snapshot reads), RQ-257-02 (programs are provider-neutral and compose with
ordinary 'Monad' syntax), and INV-257-PROVIDER (a program short-circuits on
the first error and never invokes a later operation — no fallback).
-}
module Cardano.KERI.ChainQuery.ProgramSpec (spec) where

import Cardano.KERI.ChainQuery.Interpreter (
    ChainQueryInterpreter,
    chainQueryInterpreter,
    runChainQuery,
 )
import Cardano.KERI.ChainQuery.Program (
    boardCatalog,
    currentCheckpoint,
    liveCheckpoints,
    payerUtxos,
    referenceScripts,
    storeWatermark,
 )
import Cardano.KERI.ChainQuery.Types (
    BoardLocator (..),
    ChainQueryError (..),
    ChainReference,
    CheckpointLocator (..),
    ColdOr (Cold),
    QuerySource (SourceLocal),
    SnapshotConsistency (AtomicLocal),
 )
import Codec.Binary.Bech32 qualified as Bech32
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

spec :: Spec
spec = describe "Cardano.KERI.ChainQuery.Program" $ do
    it "composes all six operations in the declared order (RQ-257-01/02)" $ do
        callLog <- newIORef []
        let interpreter = loggingInterpreter callLog
            program = do
                _ <- currentCheckpoint testCheckpointLocator testAid
                _ <- liveCheckpoints testCheckpointLocator
                _ <- referenceScripts [canonicalHashHex 0x02, canonicalHashHex 0x03]
                _ <- boardCatalog testBoardLocator
                _ <- payerUtxos [canonicalAddress 0x04]
                storeWatermark
        result <- runChainQuery interpreter program
        result `shouldBe` Right Cold
        calls <- readIORef callLog
        reverse calls
            `shouldBe` [ "currentCheckpoint"
                       , "liveCheckpoints"
                       , "referenceScripts"
                       , "boardCatalog"
                       , "payerUtxos"
                       , "storeWatermark"
                       ]

    it "threads a pure computation between operations without an extra call" $ do
        callLog <- newIORef []
        let interpreter = loggingInterpreter callLog
            program = do
                checkpoints <- liveCheckpoints testCheckpointLocator
                let doubled = length checkpoints * 2 + 1
                _ <- payerUtxos (replicate doubled (canonicalAddress 0x05))
                storeWatermark
        _ <- runChainQuery interpreter program
        calls <- readIORef callLog
        reverse calls `shouldBe` ["liveCheckpoints", "payerUtxos", "storeWatermark"]

    it "short-circuits on the first error and never invokes a later operation (INV-257-PROVIDER)" $ do
        callLog <- newIORef []
        let interpreter =
                loggingInterpreterWith callLog $ \hashes -> do
                    modifyIORef' callLog ("referenceScripts" :)
                    pure (Left (ProviderFailure ("boom: " <> T.pack (show hashes))))
            program = do
                _ <- currentCheckpoint testCheckpointLocator testAid
                _ <- referenceScripts [canonicalHashHex 0x02]
                boardCatalog testBoardLocator
        result <- runChainQuery interpreter program
        case result of
            Left (ProviderFailure _) -> pure ()
            other -> fail ("expected ProviderFailure, got " <> show other)
        calls <- readIORef callLog
        reverse calls `shouldBe` ["currentCheckpoint", "referenceScripts"]

{- | A well-formed 44-character KERI E-code identifier, and genuinely
canonical hex\/bech32 locator\/address\/hash fixtures -- so every operation
in this file's programs actually reaches the interpreter under test
(DATA-INV-257-01's structural, eager validation rejects a non-canonical
argument before any interpreter is ever invoked, at either provider).
-}
testAid :: Text
testAid = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

testCheckpointLocator :: CheckpointLocator
testCheckpointLocator =
    CheckpointLocator
        { checkpointLocatorPolicyId = canonicalHashHex 0x00
        , checkpointLocatorAddress = canonicalAddress 0x00
        }

testBoardLocator :: BoardLocator
testBoardLocator =
    BoardLocator
        { boardLocatorPolicyId = canonicalHashHex 0x01
        , boardLocatorAddress = canonicalAddress 0x01
        }

canonicalHashHex :: Word8 -> Text
canonicalHashHex byte = TE.decodeUtf8 (convertToBase Base16 (BS.replicate 28 byte))

canonicalAddress :: Word8 -> Text
canonicalAddress byte = Bech32.encodeLenient addrTestHrp (Bech32.dataPartFromBytes (BS.replicate 28 byte))

addrTestHrp :: Bech32.HumanReadablePart
addrTestHrp = either (error . show) id (Bech32.humanReadablePartFromText "addr_test")

{- | An interpreter that logs every call it receives (in reverse-call order)
and answers every operation with an empty/cold, always-succeeding value.
-}
loggedCall :: IORef [String] -> String -> IO a -> IO (Either ChainQueryError a)
loggedCall callLog name answer = do
    modifyIORef' callLog (name :)
    Right <$> answer

loggingInterpreterWith ::
    IORef [String] ->
    ([Text] -> IO (Either ChainQueryError [ChainReference])) ->
    ChainQueryInterpreter IO
loggingInterpreterWith callLog referenceScriptsOp =
    chainQueryInterpreter
        (\_ _ -> loggedCall callLog "currentCheckpoint" (pure Nothing))
        (\_ -> loggedCall callLog "liveCheckpoints" (pure []))
        referenceScriptsOp
        (\_ -> loggedCall callLog "boardCatalog" (pure []))
        (\_ -> loggedCall callLog "payerUtxos" (pure []))
        (loggedCall callLog "storeWatermark" (pure Cold))
        SourceLocal
        AtomicLocal

loggingInterpreter :: IORef [String] -> ChainQueryInterpreter IO
loggingInterpreter callLog =
    loggingInterpreterWith callLog (\_ -> loggedCall callLog "referenceScripts" (pure []))
