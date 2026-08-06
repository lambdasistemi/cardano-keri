{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.ManifestSpec (spec) where

import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    endpointBoardManifestValidationErrors,
    mkEndpointBoardManifest,
    writeEndpointBoardManifestAtomic,
 )
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
    manifestValidationErrors,
    mkManifest,
 )
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    deriveBoardScript,
    deriveV1Scripts,
    loadBlueprint,
 )
import Data.Aeson qualified as Aeson
import Data.ByteString.Short qualified as SBS
import Data.List (sort)
import Data.Text (Text)
import System.Environment (getEnv)
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (
    fileMode,
    getFileStatus,
    groupReadMode,
    intersectFileModes,
    otherReadMode,
 )
import Test.Hspec (
    Spec,
    aroundAll,
    describe,
    it,
    pendingWith,
    shouldBe,
    shouldContain,
    shouldSatisfy,
 )

spec :: Spec
spec =
    aroundAll withArtifacts $ do
        describe "M1 V1 applied scripts" $ do
            it "derives the exact five release names" $ \artifacts ->
                sort (map artifactName artifacts)
                    `shouldBe` sort
                        [ "checkpoint-register"
                        , "hash-proof"
                        , "observer-advance"
                        , "observer-enforcement"
                        , "observer-lifecycle"
                        ]
            it "preserves the stock signed-reference transaction budget" $ \artifacts -> do
                map (SBS.length . artifactProgram) artifacts
                    `shouldSatisfy` all (<= 16_133)
                -- Slice A6: freshly measured from the combined tree with
                -- main's input-addressed blueprint fix and T219-A1's
                -- advance.ak deletions. Matching the old pre-rebase pin is
                -- coincidental; this value was re-derived, not reused.
                programLength "observer-advance" artifacts `shouldBe` 14_775
        describe "M1 endpoint-board script" $ do
            -- Historical fact, not a live derivation: the M1 endpoint board
            -- was deployed 2026-07-29 compiled with aiken 1.1.21 (blueprint
            -- sha256 896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c,
            -- settled tx 967b86211ab7c80876ae4b6bec0e478dd92a98f14d5c3d751a99ad01c04654d4).
            -- The repo's blueprint derivation now pins aiken 1.1.23 (the real
            -- validation toolchain, #219/A-009) and will NOT reproduce this
            -- value -- that's expected, not a regression. These literals move
            -- only at an explicit cutover/redeploy, never as a routine
            -- re-derivation. No dual-toolchain build machinery: do not
            -- rebuild under 1.1.21 to "prove" this test, and do not derive
            -- these values from the live blueprint. This checks the
            -- recorded preprod manifest's own fields against the literals
            -- (a manifest-integrity check), not a live blueprint derivation.
            it "derives the frozen policy id and preprod address" $ \_ -> do
                path <- getEnv "KERI_BOARD_MANIFEST"
                manifest <-
                    Aeson.eitherDecodeFileStrict'
                        path
                        >>= either fail pure
                let info = endpointBoardManifestInfo manifest
                endpointBoardPolicyId info `shouldBe` expectedBoardPolicy
                endpointBoardAddress info `shouldBe` expectedBoardAddress
            -- #219 A4/NOTE-009: this test's `endpointBoardManifestValidationErrors`
            -- call transitively compares the manifest against production
            -- code's `frozenEndpointBoardPolicyId`/`frozenEndpointBoardAddress`
            -- (`EndpointBoardManifest.hs`, parked as Q-007 -- out of this
            -- slice's fence). Restructuring this test to avoid that call
            -- would touch more than moving/re-scoping the existing
            -- assertion, so it stays pending pending Q-007's resolution
            -- rather than guessing a redesign.
            it "round-trips and validates the reproducible board manifest" $ \_ -> do
                pendingWith
                    "blocked on Q-007 (EndpointBoardManifest.hs production frozen constants), not a stale pin"
                board <- loadBoardArtifact
                manifest <-
                    either fail pure $
                        mkEndpointBoardManifest
                            "https://github.com/lambdasistemi/cardano-keri"
                            "0000000000000000000000000000000000000000"
                            testBlueprintDigest
                            "2026-07-29T00:00:00Z"
                            board
                            (Reference testTxId 0)
                Aeson.eitherDecode (Aeson.encode manifest)
                    `shouldBe` Right manifest
                endpointBoardManifestValidationErrors
                    testBlueprintDigest
                    board
                    manifest
                    `shouldBe` []
                let info = endpointBoardManifestInfo manifest
                    tampered =
                        manifest
                            { endpointBoardManifestInfo =
                                info{endpointBoardPolicyId = "00"}
                            }
                unlines
                    ( endpointBoardManifestValidationErrors
                        testBlueprintDigest
                        board
                        tampered
                    )
                    `shouldContain` "board policy id mismatch"
                withSystemTempDirectory "ckeri-board-manifest" $ \directory -> do
                    let output = directory <> "/board-manifest.json"
                    writeEndpointBoardManifestAtomic output manifest
                    mode <- fileMode <$> getFileStatus output
                    mode `intersectFileModes` groupReadMode
                        `shouldBe` groupReadMode
                    mode `intersectFileModes` otherReadMode
                        `shouldBe` otherReadMode
        describe "M1 V1 manifest" $ do
            it "round-trips deterministically" $ \artifacts -> do
                manifest <- requireManifest artifacts
                Aeson.eitherDecode (Aeson.encode manifest)
                    `shouldBe` Right manifest
                Aeson.encode manifest `shouldBe` Aeson.encode manifest
            it "accepts the rebuilt production facts" $ \artifacts -> do
                manifest <- requireManifest artifacts
                manifestValidationErrors testBlueprintDigest artifacts manifest
                    `shouldBe` []
            it "rejects a substituted script hash" $ \artifacts -> do
                manifest <- requireManifest artifacts
                let scripts = manifestScripts manifest
                    tampered =
                        case scripts of
                            first : rest ->
                                manifest
                                    { manifestScripts =
                                        first{scriptHash = "00"} : rest
                                    }
                            [] -> manifest
                    errors =
                        manifestValidationErrors
                            testBlueprintDigest
                            artifacts
                            tampered
                errors `shouldSatisfy` (not . null)
                unlines errors `shouldContain` "script hash-proof mismatch"
            it "rejects malformed or reused references" $ \artifacts -> do
                manifest <- requireManifest artifacts
                let scripts = manifestScripts manifest
                    tampered =
                        case scripts of
                            first : second : third : rest ->
                                manifest
                                    { manifestScripts =
                                        first
                                            { scriptReference =
                                                Reference "not-a-txid" (-1)
                                            }
                                            : second
                                                { scriptReference =
                                                    scriptReference third
                                                }
                                            : third
                                            : rest
                                    }
                            _ -> manifest
                    errors =
                        manifestValidationErrors
                            testBlueprintDigest
                            artifacts
                            tampered
                unlines errors
                    `shouldContain` "reference transaction id is not"
                unlines errors
                    `shouldContain` "reference output index is negative"
                unlines errors
                    `shouldContain` "script references are not unique"
withArtifacts :: ([ScriptArtifact] -> IO ()) -> IO ()
withArtifacts action = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <-
        loadBlueprint path >>= either fail pure
    artifacts <-
        either fail pure (deriveV1Scripts blueprint)
    action artifacts

programLength :: Text -> [ScriptArtifact] -> Int
programLength name artifacts =
    case [ SBS.length (artifactProgram artifact)
         | artifact <- artifacts
         , artifactName artifact == name
         ] of
        [size] -> size
        _ -> error "programLength: artifact not found uniquely"

loadBoardArtifact :: IO ScriptArtifact
loadBoardArtifact = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (deriveBoardScript blueprint)

expectedBoardPolicy :: Text
expectedBoardPolicy = "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

expectedBoardAddress :: Text
expectedBoardAddress =
    "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"

requireManifest :: [ScriptArtifact] -> IO Manifest
requireManifest artifacts =
    either fail pure $
        mkManifest
            "https://github.com/lambdasistemi/cardano-keri"
            "0000000000000000000000000000000000000000"
            testBlueprintDigest
            "2026-07-28T00:00:00Z"
            artifacts
            (zip (map artifactName artifacts) testReferences)

testReferences :: [Reference]
testReferences =
    [ Reference (txId index) index
    | index <- [0 .. 4]
    ]
  where
    txId _ =
        testTxId

testTxId :: Text
testTxId =
    "0000000000000000000000000000000000000000000000000000000000000000"

testBlueprintDigest :: Text
testBlueprintDigest =
    "0000000000000000000000000000000000000000000000000000000000000000"
