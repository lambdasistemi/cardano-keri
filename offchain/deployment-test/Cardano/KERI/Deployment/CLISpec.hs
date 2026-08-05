{- |
Module      : Cardano.KERI.Deployment.CLISpec
Description : #181 Slice 2C register composition fail-closed proof
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

The register command deliberately retains parsing, plan construction,
read-only chain preflight, and warnings while Slice 4 owns the real runtime
composition. This compiled-behaviour proof injects observable read/query/
output capabilities and freezes their order before the fail-closed stop.
-}
module Cardano.KERI.Deployment.CLISpec (spec) where

import Cardano.KERI.Deployment.CLI (
    RegisterRuntime (..),
    RegisterSettings (..),
    runRegisterWith,
 )
import Cardano.KERI.Deployment.ChainIndex (ChainAssetUtxo (..))
import Cardano.KERI.Deployment.EndpointBoardManifest (
    readEndpointBoardManifest,
 )
import Cardano.KERI.Deployment.Manifest (readManifest)
import Control.Exception (SomeException, displayException, try)
import Data.ByteString qualified as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Paths_cardano_keri (getDataFileName)
import System.Directory (doesFileExist)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
 )

spec :: Spec
spec =
    describe "runRegister composition boundary" $
        it "fails closed before funding, build, sign, submit, or success until Slice 4 composition" $ do
            kelPath <-
                getDataFileName
                    "deployment-test/fixtures/kli-export-2-of-5.cesr"
            manifestPath <-
                requiredPath
                    [ "../deploy/preprod/m1-manifest.json"
                    , "deploy/preprod/m1-manifest.json"
                    ]
            boardManifestPath <-
                requiredPath
                    [ "../deploy/preprod/board-manifest.json"
                    , "deploy/preprod/board-manifest.json"
                    ]
            callsRef <- newIORef ([] :: [String])
            let record calls tag action =
                    modifyIORef' calls (tag :) >> action
                mkRuntime calls =
                    RegisterRuntime
                        { registerReadKel = \path ->
                            record calls "read-kel" (BS.readFile path)
                        , registerReadManifest = \path ->
                            record calls "read-manifest" (readManifest path)
                        , registerQueryAssets = \_ _ _ _ ->
                            record
                                calls
                                "query-assets"
                                ( pure
                                    [ ChainAssetUtxo
                                        "existing-checkpoint"
                                        0
                                        "checkpoint-address"
                                        1_007_000_000
                                        []
                                        Nothing
                                    ]
                                )
                        , registerReadBoardManifest = \path ->
                            record
                                calls
                                "read-board-manifest"
                                (readEndpointBoardManifest path)
                        , registerQueryBoard = \_ _ _ _ ->
                            record calls "query-board-catalog" (pure [])
                        , registerWriteLine = \_ ->
                            record calls "warning" (pure ())
                        , registerStop = \message ->
                            record calls "stop" (fail message)
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
                        , registerCardanoCli = "unused-cardano-cli"
                        , registerManifest = manifestPath
                        , registerBoardManifest = boardManifestPath
                        , registerKoiosUrl = "unused-koios"
                        , registerKoiosToken = Nothing
                        , registerTimeoutSeconds = 30
                        , registerAllowUnlistedWitnesses = True
                        , registerAllowExistingCheckpoint = True
                        , registerEscrowLovelace = 1_007_000_000
                        }
            result <-
                try (runRegisterWith runtime settings) ::
                    IO (Either SomeException ())
            case result of
                Left exception ->
                    displayException exception
                        `shouldContain` "registering pending #181 Slice 4 composition"
                Right () -> fail "runRegisterWith did not fail closed"
            reverse <$> readIORef callsRef
                >>= ( `shouldBe`
                        [ "read-kel"
                        , "read-manifest"
                        , "query-assets"
                        , "read-board-manifest"
                        , "query-board-catalog"
                        , "warning"
                        , "warning"
                        , "stop"
                        ]
                    )
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
            reverse <$> readIORef preflightCallsRef
                >>= ( `shouldBe`
                        [ "read-kel"
                        , "read-manifest"
                        , "query-assets"
                        , "read-board-manifest"
                        , "query-board-catalog"
                        ]
                    )

requiredPath :: [FilePath] -> IO FilePath
requiredPath [] = fail "cannot locate a required register preflight fixture"
requiredPath (candidate : rest) =
    doesFileExist candidate >>= \case
        True -> pure candidate
        False -> requiredPath rest
