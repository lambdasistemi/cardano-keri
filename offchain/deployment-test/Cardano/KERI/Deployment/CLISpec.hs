{- |
Module      : Cardano.KERI.Deployment.CLISpec
Description : #181 register preflight-to-live composition proof
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

This compiled-behaviour proof injects observable read/query/output/submission
capabilities and freezes their order across the live composition boundary.
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
        it "submits only after every read-only preflight and warning" $ do
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
                        { registerReadKel =
                            record calls "read-kel" . BS.readFile
                        , registerReadManifest =
                            record calls "read-manifest" . readManifest
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
                        , registerReadBoardManifest =
                            record calls "read-board-manifest"
                                . readEndpointBoardManifest
                        , registerQueryBoard = \_ _ _ _ ->
                            record calls "query-board-catalog" (pure [])
                        , registerWriteLine = \_ ->
                            record calls "warning" (pure ())
                        , registerSubmit = \_ _ _ ->
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
                        , registerKoiosUrl = "unused-koios"
                        , registerKoiosToken = Nothing
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
                        , "query-assets"
                        , "read-board-manifest"
                        , "query-board-catalog"
                        , "warning"
                        , "warning"
                        , "submit"
                        ]
                    )
                    . reverse
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
                        , "query-assets"
                        , "read-board-manifest"
                        , "query-board-catalog"
                        ]
                    )
                    . reverse

requiredPath :: [FilePath] -> IO FilePath
requiredPath [] = fail "cannot locate a required register preflight fixture"
requiredPath (candidate : rest) =
    doesFileExist candidate >>= \case
        True -> pure candidate
        False -> requiredPath rest
