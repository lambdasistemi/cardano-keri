{- |
Module      : Cardano.KERI.CLI.ProductionSpec
Description : #177 Slice 1 NOTE-032 installed endpoint manifest-leak regression

Proves the composed production entrypoint ('runInstructions'\/
'Cardano.KERI.CLI.runBackendStatusCLI'), not just 'selectBackend' or
'Cardano.KERI.CLI.Backend.Endpoint.mkEndpointBackend' in isolation: the
installed @--endpoint@ shortcut must never read the local checkpoint\/board
manifests, since 'SelectedEndpoint' needs neither. Ported from the ticket
owner's independent audit of the packaged @ckeri@ binary
(@ckeri status --aid ... --endpoint ...@ from a checkout-free @\/tmp@ cwd
crashed on a missing @deploy\/preprod\/m1-manifest.json@).
-}
module Cardano.KERI.CLI.ProductionSpec (spec) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.CLI (Instructions (Status), runInstructions)
import Cardano.KERI.CLI.Backend (BackendSettings (..))
import Cardano.KERI.Indexer.Query.Server (mkQueryApplication)
import Cardano.KERI.Indexer.Query.Tx (QueryHandle (..))
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (PolicyID (..))
import Cardano.Node.Client.N2C.Reconnect (UpstreamStatus (..))
import Cardano.Node.Client.UTxOIndexer.Follower (Readiness (..))
import Cardano.Node.Client.UTxOIndexer.Indexer (applyAtSlot, withInMemoryIndexerRunner)
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Concurrent.STM (newTVarIO, readTVar)
import Control.Exception (SomeException, try)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Network.Wai.Handler.Warp qualified as Warp
import Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "runInstructions / runBackendStatusCLI production composition (NOTE-032)" $
    it "the installed --endpoint shortcut never reads the local manifest files" $
        withInMemoryIndexerRunner $ \handle runner -> do
            applyAtSlot handle (Indexer.SlotNo 100) (Indexer.BlockHash (BS.replicate 32 0x04)) []
            readinessVar <- newTVarIO (readinessAt 100 100)
            let queryHandle =
                    QueryHandle
                        runner
                        checkpointAddress
                        checkpointPolicy
                        boardAddress
                        (readTVar readinessVar)
            Warp.testWithApplication (pure (mkQueryApplication queryHandle)) $ \port -> do
                let baseUrl = "http://127.0.0.1:" <> T.pack (show port)
                    settings =
                        BackendSettings
                            { backendAid = aidText
                            , backendExplicit = Nothing
                            , backendEndpointUrl = Just baseUrl
                            , backendStorePath = Nothing
                            , backendManifest = "/nonexistent-177-note032/m1-manifest.json"
                            , backendBoardManifest = "/nonexistent-177-note032/board-manifest.json"
                            , backendKoiosUrl = "https://unused.example.invalid"
                            , backendKoiosToken = Nothing
                            }
                result <- try @SomeException (runInstructions (Status settings))
                result `shouldSatisfy` isRight
  where
    isRight (Right ()) = True
    isRight (Left _) = False

checkpointPolicy :: PolicyID
checkpointPolicy =
    PolicyID $
        ScriptHash $
            case hashFromBytes (BS.replicate 28 0x41) of
                Just h -> h
                Nothing -> error "ProductionSpec: invalid checkpoint policy id width"

checkpointLedgerAddress :: Addr
checkpointLedgerAddress =
    let PolicyID scriptHash = checkpointPolicy
     in Addr Testnet (ScriptHashObj scriptHash) StakeRefNull

checkpointAddress :: Indexer.Address
checkpointAddress = Indexer.Address (serialiseAddr checkpointLedgerAddress)

boardAddress :: Indexer.Address
boardAddress =
    Indexer.Address
        ( serialiseAddr
            ( Addr
                Testnet
                ( ScriptHashObj
                    ( ScriptHash
                        ( case hashFromBytes (BS.replicate 28 0x51) of
                            Just h -> h
                            Nothing -> error "ProductionSpec: invalid board policy id width"
                        )
                    )
                )
                StakeRefNull
            )
        )

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

aidText :: Text
aidText = "EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
