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
    QueryBackend (..),
    SelectedBackend (..),
    resolveBackend,
 )
import Cardano.KERI.Deployment.ChainIndex (KoiosToken)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Test.Hspec (Spec, describe, it, shouldBe)

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
        openLocal _ = record "local" >> pure (fakeBackend "FAKE-LOCAL")
        openEndpoint _ = record "endpoint" >> pure (fakeBackend "FAKE-ENDPOINT")
        openKoios _ _ = record "koios" >> pure (fakeBackend "FAKE-KOIOS")
    pure (readIORef ref, openLocal, openEndpoint, openKoios)

fakeBackend :: Text -> QueryBackend
fakeBackend label =
    QueryBackend
        { qbSourceLabel = label
        , qbStatus = \_ -> error "DispatchSpec: qbStatus not exercised here"
        , qbBoardByWitness = \_ -> error "DispatchSpec: qbBoardByWitness not exercised here"
        }
