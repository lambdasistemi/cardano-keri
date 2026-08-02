{- |
Module      : Cardano.KERI.CLI.Backend.DispatchSpec
Description : #177 Slice 1 T177-S1-9 dispatch wiring guard (RED)

Proves 'resolveBackend' — the exact dispatch table production @ckeri status@
uses — routes each 'SelectedBackend' to its own constructor and never another
one (FR-5's no-fallback, at the wiring layer). This is the test the driver
deliberately breaks (one swapped arm) and restores per T177-S1-9.
-}
module Cardano.KERI.CLI.Backend.DispatchSpec (spec) where

import Cardano.KERI.CLI.Backend (
    BackendError (..),
    QueryBackend (..),
    SelectedBackend (..),
    resolveBackend,
    runBackendCheckpointByAid,
    runBackendListCheckpoints,
    runBackendPayerUtxos,
 )
import Cardano.KERI.Deployment.ChainIndex (KoiosToken)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "resolveBackend dispatch wiring (T177-S1-9)" $ do
    it "SelectedLocal invokes only the local constructor" $ do
        (calls, openLocal, openEndpoint, openKoios) <- fakeConstructors
        resolved <- resolveBackend openLocal openEndpoint openKoios (SelectedLocal "/tmp/store")
        qbSourceLabel resolved `shouldBe` "FAKE-LOCAL"
        calls `shouldReturnOnly` ["local"]

    it "SelectedEndpoint invokes only the endpoint constructor" $ do
        (calls, openLocal, openEndpoint, openKoios) <- fakeConstructors
        resolved <- resolveBackend openLocal openEndpoint openKoios (SelectedEndpoint "https://ckeri.dev.plutimus.com")
        qbSourceLabel resolved `shouldBe` "FAKE-ENDPOINT"
        calls `shouldReturnOnly` ["endpoint"]

    it "SelectedKoios invokes only the koios constructor" $ do
        (calls, openLocal, openEndpoint, openKoios) <- fakeConstructors
        resolved <- resolveBackend openLocal openEndpoint openKoios (SelectedKoios "https://preprod.koios.rest/api/v1" Nothing)
        qbSourceLabel resolved `shouldBe` "FAKE-KOIOS"
        calls `shouldReturnOnly` ["koios"]

    it "SelectedLocal plus list invokes one constructor and only the list operation" $ do
        (calls, openLocal, openEndpoint, openKoios) <- fakeConstructors
        resolved <- resolveBackend openLocal openEndpoint openKoios (SelectedLocal "/tmp/store")
        result <- runBackendListCheckpoints resolved
        result `shouldSatisfy` isUnsupported "fake list"
        calls `shouldReturnOnly` ["local", "list"]

    it "SelectedEndpoint plus checkpoint invokes one constructor and only checkpoint-by-AID" $ do
        (calls, openLocal, openEndpoint, openKoios) <- fakeConstructors
        resolved <- resolveBackend openLocal openEndpoint openKoios (SelectedEndpoint "https://ckeri.dev.plutimus.com")
        result <- runBackendCheckpointByAid resolved "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        result `shouldSatisfy` isUnsupported "fake checkpoint"
        calls `shouldReturnOnly` ["endpoint", "checkpoint"]

    it "SelectedKoios plus payer invokes one constructor and only payer UTxOs" $ do
        (calls, openLocal, openEndpoint, openKoios) <- fakeConstructors
        resolved <- resolveBackend openLocal openEndpoint openKoios (SelectedKoios "https://preprod.koios.rest/api/v1" Nothing)
        result <- runBackendPayerUtxos resolved "addr_test1vzyg8ndhzscnk7krsfrvrhvddlplsp8320qlr3x28ptphgqlxnx9d"
        result `shouldSatisfy` isUnsupported "fake payer"
        calls `shouldReturnOnly` ["koios", "payer"]

shouldReturnOnly :: IO [Text] -> [Text] -> IO ()
shouldReturnOnly getCalls expected = do
    calls <- getCalls
    calls `shouldBe` expected

fakeConstructors ::
    IO
        ( IO [Text]
        , FilePath -> IO QueryBackend
        , Text -> IO QueryBackend
        , Text -> Maybe KoiosToken -> IO QueryBackend
        )
fakeConstructors = do
    ref <- newIORef []
    let record label = modifyIORef' ref (<> [label])
        openLocal _ = record "local" >> pure (fakeBackend ref "FAKE-LOCAL")
        openEndpoint _ = record "endpoint" >> pure (fakeBackend ref "FAKE-ENDPOINT")
        openKoios _ _ = record "koios" >> pure (fakeBackend ref "FAKE-KOIOS")
    pure (readIORef ref, openLocal, openEndpoint, openKoios)

fakeBackend :: IORef [Text] -> Text -> QueryBackend
fakeBackend calls label =
    QueryBackend
        { qbSourceLabel = label
        , qbStatus = \_ -> error "DispatchSpec: qbStatus not exercised here"
        , qbBoardByWitness = \_ -> error "DispatchSpec: qbBoardByWitness not exercised here"
        , qbListCheckpoints = record "list" "fake list"
        , qbCheckpointByAid = \_ -> record "checkpoint" "fake checkpoint"
        , qbPayerUtxos = \_ -> record "payer" "fake payer"
        }
  where
    record operation capability = do
        modifyIORef' calls (<> [operation])
        pure (Left (UnsupportedCapability capability))

isUnsupported :: Text -> Either BackendError a -> Bool
isUnsupported expected (Left (UnsupportedCapability actual)) = actual == expected
isUnsupported _ _ = False
