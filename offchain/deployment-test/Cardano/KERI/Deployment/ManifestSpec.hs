{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.ManifestSpec (spec) where

import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
    endpointBoardManifestValidationErrors,
    mkEndpointBoardManifest,
 )
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
    manifestValidationErrors,
    mkManifest,
 )
import Cardano.KERI.Deployment.Publisher (parseTransactionId)
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    boardAddress,
    deriveBoardScript,
    deriveV1Scripts,
    loadBlueprint,
    scriptHashText,
 )
import Data.Aeson qualified as Aeson
import Data.ByteString.Short qualified as SBS
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as T
import System.Environment (getEnv)
import Test.Hspec (
    Spec,
    aroundAll,
    describe,
    it,
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
                programLength "observer-advance" artifacts `shouldBe` 16_130
        describe "M1 endpoint-board script" $ do
            it "derives the frozen policy id and preprod address" $ \_ -> do
                board <- loadBoardArtifact
                artifactName board `shouldBe` "endpoint-board"
                artifactBlueprintTitle board
                    `shouldBe` "endpoint_board.endpoint_board.mint"
                scriptHashText (artifactScriptHash board)
                    `shouldBe` expectedBoardPolicy
                boardAddress board `shouldBe` Right expectedBoardAddress
            it "round-trips and validates the reproducible board manifest" $ \_ -> do
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
        describe "cardano-cli compatibility" $ do
            it "accepts both legacy text and current JSON txid output" $ \_ -> do
                parseTransactionId (T.unpack testTxId)
                    `shouldBe` Right testTxId
                parseTransactionId
                    ("{\"txhash\":\"" <> T.unpack testTxId <> "\"}")
                    `shouldBe` Right testTxId

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
