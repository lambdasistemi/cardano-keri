{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.ManifestSpec (spec) where

import Cardano.Crypto.Hash.Class (digest)
import Cardano.Crypto.Hash.SHA256 (SHA256)
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
    Blueprint (..),
    ScriptArtifact (..),
    Validator (..),
    boardAddress,
    deriveBoardV0Script,
    deriveV1Scripts,
    loadBlueprint,
    scriptHashText,
 )
import Data.Aeson (FromJSON (..), withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.List (sort)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import System.Environment (getEnv, lookupEnv)
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
                        , "observer-entitlement"
                        , "observer-lifecycle"
                        , -- #254 A-001: the promoted migration observer is a
                          -- v1 family component, published beside the M1 set.
                          "observer-migration"
                        ]
            it "preserves the stock signed-reference transaction budget" $ \artifacts -> do
                map (SBS.length . artifactProgram) artifacts
                    `shouldSatisfy` all (<= 16_133)
                -- #254 S254-E: re-derived from deriveV1Scripts after the
                -- observer split, not reused from A-002 (14_876) or S254-R
                -- (14_775). Transitive compiled drift; the 16_133 ceiling
                -- is unchanged.
                programLength "observer-advance" artifacts `shouldBe` 14_876
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
            -- #263 (INV-263-UNPARKED): formerly parked. This test's
            -- `endpointBoardManifestValidationErrors` call transitively
            -- compares the manifest against production code's
            -- `frozenEndpointBoardPolicyId`/`frozenEndpointBoardAddress`,
            -- which is exactly what could not hold while the repository owned
            -- no copy of the deployed program. It holds now because
            -- `loadBoardArtifact` derives the board from the RECOVERED
            -- artifact (`KERI_BOARD_BLUEPRINT`) rather than from the current
            -- source-built checkpoint blueprint, whose endpoint-board
            -- validator is a different, non-deployed program. Nothing in
            -- `EndpointBoardManifest.hs` was weakened, parameterized away, or
            -- bypassed to unpark it.
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
                withSystemTempDirectory "ckeri-board-manifest" $ \directory -> do
                    let output = directory <> "/board-manifest.json"
                    writeEndpointBoardManifestAtomic output manifest
                    mode <- fileMode <$> getFileStatus output
                    mode `intersectFileModes` groupReadMode
                        `shouldBe` groupReadMode
                    mode `intersectFileModes` otherReadMode
                        `shouldBe` otherReadMode
        -- #263 (RQ-263-01/03, INV-263-REPRODUCIBLE, DATA-INV-263-01/02/05).
        -- The permanent identity proof. It is deliberately NOT a comparison of
        -- JSON fields against each other: the artifact's bytes are decoded by
        -- the real production `loadBlueprint` and hashed by the real
        -- production `deriveBoardV0Script`/`computeScriptHash`, so the values
        -- asserted here are DERIVED from the checked-in program, and a single
        -- perturbed nibble changes all three of length, digest, and policy.
        describe "#263 recovered endpoint-board artifact" $ do
            it "production-derives the deployed board identity from the repository bytes" $ \_ -> do
                artifact <- loadBoardArtifact
                artifactBlueprintTitle artifact `shouldBe` recoveredBoardTitle
                SBS.length (artifactProgram artifact)
                    `shouldBe` recoveredProgramBytes
                sha256Hex (SBS.fromShort (artifactProgram artifact))
                    `shouldBe` recoveredProgramSha256
                scriptHashText (artifactScriptHash artifact)
                    `shouldBe` expectedBoardPolicy
                boardAddress artifact `shouldBe` Right expectedBoardAddress
            it "keeps exactly one validator and provenance its own payload confirms" $ \_ -> do
                path <- boardBlueprintPath
                blueprint <- loadBlueprint path >>= either fail pure
                -- PROMOTE-263-02: the compact artifact promotes the deployed
                -- board and nothing else; the other 22 historical validators
                -- have no consumer and are not retained.
                map vTitle (validators blueprint)
                    `shouldBe` [recoveredBoardTitle]
                artifact <- either fail pure (deriveBoardV0Script blueprint)
                provenance <- readBoardProvenance path
                provenanceSourceCommit provenance `shouldBe` recoveredSourceCommit
                provenanceCompiler provenance `shouldBe` "aiken 1.1.21"
                provenanceSourceBlueprintBytes provenance `shouldBe` 581_696
                provenanceSourceBlueprintSha256 provenance
                    `shouldBe` recoveredSourceBlueprintSha256
                -- DAT-263-PROVENANCE: metadata is never trusted about its own
                -- payload. Both program facts must equal what the decoded
                -- bytes actually are, not merely the frozen literals -- so a
                -- provenance block edited to match a tampered program still
                -- fails.
                provenanceProgramBytes provenance
                    `shouldBe` SBS.length (artifactProgram artifact)
                provenanceProgramSha256 provenance
                    `shouldBe` sha256Hex (SBS.fromShort (artifactProgram artifact))
                provenanceProgramBytes provenance `shouldBe` recoveredProgramBytes
                provenanceProgramSha256 provenance `shouldBe` recoveredProgramSha256
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
            it "rejects a truncated reference list rather than dropping an artifact" $ \artifacts -> do
                let names = map artifactName artifacts
                    full = referencesFor artifacts
                    short = take (length artifacts - 1) full
                zipExact names short
                    `shouldSatisfy` either (const True) (const False)
                zipExact names full
                    `shouldSatisfy` either (const False) (const True)
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

{- | #263 (DAT-263-BOARD-BINDING, EDGE-263-04): the board artifact comes from
its OWN required binding, never from @KERI_CHECKPOINT_BLUEPRINT@. The current
source-built checkpoint blueprint stays independently consumed for the five V1
checkpoint validators above; its endpoint-board validator is a different,
non-deployed program and must never stand in for the recovered one. There is
deliberately no fallback: an unset or empty binding fails closed rather than
silently reverting to the checkpoint blueprint, which is precisely the
substitution this ticket exists to make impossible.
-}
boardBlueprintPath :: IO FilePath
boardBlueprintPath = do
    value <- lookupEnv "KERI_BOARD_BLUEPRINT"
    case value of
        Just path | not (null path) -> pure path
        _ ->
            fail
                "KERI_BOARD_BLUEPRINT is unset or empty; the recovered \
                \endpoint-board artifact identity proof cannot run"

loadBoardArtifact :: IO ScriptArtifact
loadBoardArtifact = do
    path <- boardBlueprintPath
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (deriveBoardV0Script blueprint)

{- | The recovery record carried beside the program in the compact artifact.

Decoded through its own envelope so the assertions read the artifact's real
@provenance@ object rather than a re-encoding of it.
-}
data BoardProvenance = BoardProvenance
    { provenanceSourceCommit :: !Text
    , provenanceCompiler :: !Text
    , provenanceSourceBlueprintBytes :: !Int
    , provenanceSourceBlueprintSha256 :: !Text
    , provenanceProgramBytes :: !Int
    , provenanceProgramSha256 :: !Text
    }
    deriving stock (Show, Eq)

instance FromJSON BoardProvenance where
    parseJSON = withObject "BoardProvenance" $ \objectValue ->
        BoardProvenance
            <$> objectValue .: "sourceCommit"
            <*> objectValue .: "compiler"
            <*> objectValue .: "sourceBlueprintBytes"
            <*> objectValue .: "sourceBlueprintSha256"
            <*> objectValue .: "programBytes"
            <*> objectValue .: "programSha256"

newtype BoardArtifactEnvelope = BoardArtifactEnvelope BoardProvenance

instance FromJSON BoardArtifactEnvelope where
    parseJSON = withObject "BoardArtifactEnvelope" $ \objectValue ->
        BoardArtifactEnvelope <$> objectValue .: "provenance"

readBoardProvenance :: FilePath -> IO BoardProvenance
readBoardProvenance path = do
    BoardArtifactEnvelope provenance <-
        Aeson.eitherDecodeFileStrict' path >>= either fail pure
    pure provenance

{- | SHA-256 of raw bytes as lowercase hex, computed here rather than read from
the artifact -- the whole point of 'provenanceProgramSha256''s assertion.
-}
sha256Hex :: ByteString -> Text
sha256Hex =
    TE.decodeUtf8 . convertToBase Base16 . digest (Proxy @SHA256)

recoveredBoardTitle :: Text
recoveredBoardTitle = "endpoint_board.endpoint_board.mint"

recoveredProgramBytes :: Int
recoveredProgramBytes = 3_158

recoveredProgramSha256 :: Text
recoveredProgramSha256 =
    "b9562988d5d1c8995a0e58a4ebbec21848352f8b1e9e363b46dc3b36bd8543fe"

recoveredSourceCommit :: Text
recoveredSourceCommit = "95b554fbdc9dee5b4437d3a8deeb882f114a0bf3"

recoveredSourceBlueprintSha256 :: Text
recoveredSourceBlueprintSha256 =
    "896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c"

expectedBoardPolicy :: Text
expectedBoardPolicy = "54494f8a1b2930241b7b9fa010f61f2cf6307daabfab69efbf91210c"

expectedBoardAddress :: Text
expectedBoardAddress =
    "addr_test1wp2yjnu2rv5nqfqm0w06qy8kruk0vvra42l6k600h7gjzrqpd4hm4"

requireManifest :: [ScriptArtifact] -> IO Manifest
requireManifest artifacts =
    either fail pure $ do
        pairs <-
            zipExact
                (map artifactName artifacts)
                (referencesFor artifacts)
        mkManifest
            "https://github.com/lambdasistemi/cardano-keri"
            "0000000000000000000000000000000000000000"
            testBlueprintDigest
            "2026-07-28T00:00:00Z"
            artifacts
            pairs

{- | One reference per published artifact, derived from the artifact list.

A hand-written upper bound would have to agree with 'deriveV1Scripts'
and would silently drop the last name when it did not.  Indexing the
artifacts themselves makes that drift impossible.
-}
referencesFor :: [ScriptArtifact] -> [Reference]
referencesFor artifacts =
    [ Reference testTxId index
    | (index, _) <- zip [0 ..] artifacts
    ]

{- | Pair names with references, or fail.

'zip' truncates the longer side.  That is how a six-reference fixture
left @checkpoint-register@ unpublished in the manifest while the
artifact list had already grown to seven.  Equal length is required.
-}
zipExact :: [a] -> [b] -> Either String [(a, b)]
zipExact xs ys
    | length xs == length ys = Right (zip xs ys)
    | otherwise =
        Left $
            "manifest references: "
                <> show (length ys)
                <> " references for "
                <> show (length xs)
                <> " artifacts; zip would drop the tail"

testTxId :: Text
testTxId =
    "0000000000000000000000000000000000000000000000000000000000000000"

testBlueprintDigest :: Text
testBlueprintDigest =
    "0000000000000000000000000000000000000000000000000000000000000000"
