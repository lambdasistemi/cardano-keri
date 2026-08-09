{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.CLISpec
Description : #181 register preflight-to-live composition proof
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

This compiled-behaviour proof injects observable read/query/output/submission
capabilities and freezes their order across the live composition boundary.

NOTE-012 repair: the injected 'registerQuerySnapshot' capability is the one
named registration snapshot capability (INV-257-BUILDER, DATA-INV-257-03/04)
-- 'runRegisterWith' obtains its preflight existing-checkpoint and
board-catalog values from it, never from a bare query callback.
-}
module Cardano.KERI.Deployment.CLISpec (spec) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1 (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (Unweighted))
import Cardano.KERI.ChainQuery (
    ActiveCheckpoint (..),
    ChainWatermark (..),
    ColdOr (Cold, Populated),
    QuerySnapshot (..),
    QuerySource (SourceKoios, SourceLocal),
    SnapshotConsistency (AtomicLocal, LegacySequential),
 )
import Cardano.KERI.ChainQuery.Registration (RegistrationSnapshot (..))
import Cardano.KERI.Deployment.CLI (
    RegisterRuntime (..),
    RegisterSettings (..),
    renderQuerySnapshotDiagnostic,
    runRegisterWith,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    readEndpointBoardManifest,
 )
import Cardano.KERI.Deployment.Manifest (readManifest)
import Control.Exception (SomeException, displayException, try)
import Data.ByteString qualified as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Paths_cardano_keri (getDataFileName)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
 )

spec :: Spec
spec = do
    describe "renderQuerySnapshotDiagnostic (NOTE-018 item 2, DATA-INV-257-03)" $ do
        it "renders the exact source/consistency/watermark for a non-degenerate, distinguishable Koios-shaped snapshot" $
            renderQuerySnapshotDiagnostic sampleSnapshot
                `shouldBe` "registration snapshot: source=SourceKoios consistency=LegacySequential watermark=slot=12345 hash=cafebabe01"

        it "renders the exact source/consistency/watermark for a distinguishable local-shaped snapshot, never the Koios pair" $
            renderQuerySnapshotDiagnostic
                sampleSnapshot
                    { snapshotWatermark = Populated (ChainWatermark 67_890 "01deadbeef")
                    , snapshotSource = SourceLocal
                    , snapshotConsistency = AtomicLocal
                    }
                `shouldBe` "registration snapshot: source=SourceLocal consistency=AtomicLocal watermark=slot=67890 hash=01deadbeef"

        it "renders the explicit cold-store case rather than inventing a slot/hash" $
            renderQuerySnapshotDiagnostic sampleSnapshot{snapshotWatermark = Cold}
                `shouldBe` "registration snapshot: source=SourceKoios consistency=LegacySequential watermark=cold"

    describe "runRegister composition boundary" $
        -- #240: 'runRegisterWith' now brackets one real
        -- 'Cardano.KERI.Indexer.ChainQuery.withLocalQueryScope' store runner
        -- for the whole flow, even though 'registerQuerySnapshot'/
        -- 'registerSubmit' below are fully mocked and never touch the
        -- 'scope' they receive (both discard it). A fresh, empty temp
        -- directory is a genuine local store ('withRocksDBIndexerRunner'
        -- opens with @createIfMissing = True@) -- this is a real store
        -- bracket, not a stub.
        it "submits only after every read-only preflight and warning" $
            withSystemTempDirectory "ckeri-register-store" $ \storePath -> do
                kelPath <-
                    getDataFileName
                        "deployment-test/fixtures/kli-export-2-of-5.cesr"
                manifestPath <-
                    getDataFileName
                        "deployment-test/fixtures/register-preflight-m1-manifest.json"
                boardManifestPath <-
                    getDataFileName
                        "deployment-test/fixtures/register-preflight-board-manifest.json"
                callsRef <- newIORef ([] :: [String])
                linesRef <- newIORef ([] :: [String])
                let record calls tag action =
                        modifyIORef' calls (tag :) >> action
                    mkRuntime calls =
                        RegisterRuntime
                            { registerReadKel =
                                record calls "read-kel" . BS.readFile
                            , registerReadManifest =
                                record calls "read-manifest" . readManifest
                            , registerReadBoardManifest =
                                record calls "read-board-manifest"
                                    . readEndpointBoardManifest
                            , registerQuerySnapshot = \_ _ ->
                                record
                                    calls
                                    "query-snapshot"
                                    (pure (Right sampleSnapshot))
                            , registerWriteLine = \line ->
                                modifyIORef' linesRef (line :)
                                    >> record calls "warning" (pure ())
                            , registerSubmit = \_ _ _ _ ->
                                record calls "submit" (pure ())
                            }
                    runtime = mkRuntime callsRef
                    settings =
                        RegisterSettings
                            { registerNetwork = "preprod"
                            , registerNetworkMagic = 1
                            , registerKel = kelPath
                            , registerPayer = "unused-signing-key"
                            , registerNodeSocket = "unused-node-socket"
                            , registerFundingAddress = "unused-funding-address"
                            , registerManifest = manifestPath
                            , registerBoardManifest = boardManifestPath
                            , registerStorePath = storePath
                            , registerTimeoutSeconds = 30
                            , registerAllowUnlistedWitnesses = True
                            , registerAllowExistingCheckpoint = True
                            , registerEscrowLovelace = 1_007_000_000
                            }
                runRegisterWith runtime settings
                readIORef callsRef
                    >>= ( `shouldBe`
                            [ "read-kel"
                            , "read-manifest"
                            , "read-board-manifest"
                            , "query-snapshot"
                            , -- diagnostic print of the snapshot's real
                              -- source/consistency/watermark (NOTE-012)
                              "warning"
                            , "warning" -- missing witnesses
                            , "warning" -- existing checkpoint
                            , "submit"
                            ]
                        )
                        . reverse
                -- NOTE-018 item 2: prove the real production diagnostic-print
                -- call site emits the real renderer's exact output over the
                -- real (non-degenerate, distinguishable) envelope, not merely
                -- that some string was printed at the right position.
                capturedLines <- reverse <$> readIORef linesRef
                case capturedLines of
                    (firstDiagnosticLine : _) ->
                        firstDiagnosticLine `shouldBe` renderQuerySnapshotDiagnostic sampleSnapshot
                    [] -> fail "runRegisterWith never printed the query-snapshot diagnostic"
                preflightCallsRef <- newIORef ([] :: [String])
                preflightResult <-
                    try
                        ( runRegisterWith
                            (mkRuntime preflightCallsRef)
                            settings{registerAllowExistingCheckpoint = False}
                        ) ::
                        IO (Either SomeException ())
                case preflightResult of
                    Left exception ->
                        displayException exception
                            `shouldContain` "checkpoint already registered; refusing before premint"
                    Right () -> fail "runRegisterWith skipped registerPreflight"
                readIORef preflightCallsRef
                    >>= ( `shouldBe`
                            [ "read-kel"
                            , "read-manifest"
                            , "read-board-manifest"
                            , "query-snapshot"
                            , "warning" -- diagnostic print, before the preflight rejection
                            ]
                        )
                        . reverse

{- | Non-degenerate: a populated (not 'Cold') watermark with a distinguishable
slot/hash pair, and a distinguishable source\/consistency pair -- so a
constant, field-dropping, or mislabelled diagnostic renderer fails this
fixture even though it might satisfy a degenerate all-'Cold'\/all-zero one.
-}
sampleSnapshot :: QuerySnapshot RegistrationSnapshot
sampleSnapshot =
    QuerySnapshot
        { snapshotValue =
            RegistrationSnapshot
                { snapshotCurrentCheckpoint = Just sampleActiveCheckpoint
                , snapshotBoardCatalog = []
                , snapshotReferenceUtxos = []
                , snapshotPayerUtxos = []
                , snapshotStoreWatermark = Populated (ChainWatermark 12_345 "cafebabe01")
                }
        , snapshotWatermark = Populated (ChainWatermark 12_345 "cafebabe01")
        , snapshotSource = SourceKoios
        , snapshotConsistency = LegacySequential
        }

sampleActiveCheckpoint :: ActiveCheckpoint
sampleActiveCheckpoint =
    ActiveCheckpoint
        { activeCheckpointAid = "existing-aid"
        , activeCheckpointAssetName = "existing-checkpoint"
        , activeCheckpointTxId = "existing-checkpoint"
        , activeCheckpointIndex = 0
        , activeCheckpointAddress = "checkpoint-address"
        , activeCheckpointLovelace = 1_007_000_000
        , activeCheckpointAssets = []
        , activeCheckpointDatum = sampleDatum
        }

sampleDatum :: CheckpointDatumV1
sampleDatum =
    CheckpointDatumV1
        { cdCesrAid = BS.replicate 32 0x00
        , cdCurKeys = [BS.replicate 32 0x11]
        , cdCurThreshold = Unweighted 1
        , cdNextKeys = [BS.replicate 32 0x22]
        , cdNextThreshold = Unweighted 1
        , cdWitnesses = []
        , cdToad = 0
        , cdSeq = 0
        , cdNativeSn = 0
        }
