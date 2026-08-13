{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.ScriptAritySpec
Description : #254 S254-R permanent deployment arity and version-remnant control

Every artifact the deployment derivation publishes must apply exactly the
arguments its blueprint entry declares.  This module is the permanent control
for that class, written for the defect recorded in A-007: the combined register
declared eight applied parameters while @deriveV1Scripts@ applied nine, so the
ninth argument occupied the slot the ledger fills with the script context and
the derived hash, policy id and address were identities of a program that could
not settle a transaction.

Three design rules make the result mean what it says.

__The two counts come from different places.__  The declared count is read from
the live blueprint JSON by this module's own parser, never from the production
module under test.  The applied count is recovered structurally from the
artifact's own bytes.  A duplicated hand-authored @8@ on both sides would have
passed while the branch was broken, so neither side is ever written down here.

__The recovery proves itself.__  'appliedArguments' does not merely count
@Apply@ nodes: it re-applies the argument list it recovered to the raw
blueprint program and requires the result to be byte-identical to the artifact
it read them from.  A wrong recovery cannot survive that, so a green from this
oracle is not a green from a miscount.

__A retained version argument must be declared.__  @v1CheckpointVersion@ is not
banned outright: the three observers genuinely declare a @_version@ parameter
and the deployed manifest schema genuinely carries a @checkpointVersion@ field.
What is banned is a version argument with no declaration behind it, which is
exactly what the register carried.  The sweep therefore checks positions
against declarations rather than searching for a forbidden word.
-}
module Cardano.KERI.Deployment.ScriptAritySpec (
    spec,
    emitRegisterIdentity,
    derivedControlMain,
) where

import Cardano.KERI.Deployment.EndpointBoardManifest (
    frozenEndpointBoardPolicyId,
 )
import Cardano.KERI.Deployment.Manifest (
    Reference (..),
    mkManifest,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint (..),
    ScriptArtifact (..),
    Validator (..),
    applyCommitmentParams,
    applyParams,
    deriveBoardTargetScript,
    deriveV1Scripts,
    extractCompiledCodeExact,
    loadBlueprint,
    mkAppliedArtifact,
    scriptHashText,
    v1CheckpointVersion,
    v1CommitmentParameters,
    v1FreezeBond,
    v1FreezeWindow,
    v1NetworkDiscriminator,
    v1RegistrationBond,
 )
import Control.Exception (SomeException, displayException, try)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Data qualified as SYB
import Data.Either (lefts, rights)
import Data.Foldable (forM_, toList)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf, nub, sort, tails)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.Data.EnumSet qualified as EnumSet
import GHC.Data.FastString (mkFastString)
import GHC.Data.StringBuffer (stringToStringBuffer)
import GHC.Hs.Expr (HsExpr (HsApp, HsVar))
import GHC.Hs.Extension (GhcPs)
import GHC.LanguageExtensions.Type (Extension)
import GHC.Parser (parseModule)
import GHC.Parser.Lexer (
    ParseResult (PFailed, POk),
    ParserOpts,
    initParserState,
    mkParserOpts,
    unP,
 )
import GHC.Types.Name.Occurrence (occNameString)
import GHC.Types.Name.Reader (RdrName, rdrNameOcc)
import GHC.Types.SrcLoc (GenLocated (L), mkRealSrcLoc)
import GHC.Utils.Error (emptyDiagOpts)
import PlutusCore qualified as PLC
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.V3 (serialiseUPLC, uncheckedDeserialiseUPLC)
import System.Directory (
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
 )
import System.Environment (getEnv, setEnv)
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.FilePath (takeExtension, (</>))
import System.IO (hClose, hPutStrLn, stderr)
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import System.Posix.IO (closeFd, createFile, dupTo, stdError, stdOutput)
import System.Posix.Process (
    ProcessStatus (..),
    executeFile,
    exitImmediately,
    forkProcess,
    getProcessStatus,
 )
import Test.Hspec (
    Spec,
    beforeAll,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldNotBe,
    shouldSatisfy,
 )
import UntypedPlutusCore (Program (..), applyProgram)
import UntypedPlutusCore qualified as UPLC

-- | The production blueprint plus everything derived from it once.
data Fixture = Fixture
    { fixtureValue :: Aeson.Value
    -- ^ the live blueprint, parsed here rather than by the module under test
    , fixtureTitles :: [Text]
    {- ^ every validator title the blueprint carries, in order and NOT
    deduplicated: a census that asks about duplicates has to be given a
    list that could still contain one
    -}
    , fixtureDeclared :: Map Text [Text]
    -- ^ blueprint title to its declared parameter titles, in order
    , fixturePrograms :: Map Text SBS.ShortByteString
    -- ^ blueprint title to its unapplied compiled program
    , fixtureValidators :: Map Text Validator
    -- ^ blueprint title to the production module's own parse of the entry
    , fixtureArtifacts :: [ScriptArtifact]
    -- ^ every artifact @deriveV1Scripts@ publishes
    , fixtureBoard :: ScriptArtifact
    -- ^ the parameter-free endpoint board, from its own derivation
    }

-- | The blueprint entry the whole slice is about.
registerTitle :: Text
registerTitle = "checkpoint_register.checkpoint_register.mint"

-- | Load the live blueprint and derive everything the deployment publishes.
withFixture :: IO Fixture
withFixture = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    bytes <- BS.readFile path
    value <- either fail pure (Aeson.eitherDecodeStrict' bytes)
    titles <- either fail pure (validatorTitles value)
    declared <- either fail pure (declaredParameters value)
    programs <- either fail pure (compiledPrograms value)
    blueprint <- loadBlueprint path >>= either fail pure
    artifacts <- either fail pure (deriveV1Scripts blueprint)
    predecessor <- either fail pure (decodeHex frozenEndpointBoardPolicyId)
    board <-
        either
            fail
            pure
            (deriveBoardTargetScript predecessor blueprint)
    pure
        Fixture
            { fixtureValue = value
            , fixtureTitles = titles
            , fixtureDeclared = declared
            , fixturePrograms = programs
            , fixtureValidators =
                Map.fromList
                    [ (vTitle validator, validator)
                    | validator <- validators blueprint
                    ]
            , fixtureArtifacts = artifacts
            , fixtureBoard = board
            }

spec :: Spec
spec = do
    boardTargetApplicationSpec
    registerAritySpec

registerAritySpec :: Spec
registerAritySpec = beforeAll withFixture $
    describe "S254-R register deployment arity" $ do
        it
            "s254_r_all_derived_validator_arities_match_live_blueprint"
            $ \fixture -> do
                -- Every artifact the deployment publishes, not only the one
                -- A-007 reported: the class is what is under control here.
                publishedArtifacts fixture `shouldSatisfy` ((>= 6) . length)
                sequence_
                    [ case result of
                        Left err ->
                            expectationFailure (T.unpack title <> ": " <> err)
                        Right (declared, applied) ->
                            (title, applied) `shouldBe` (title, declared)
                    | (title, result) <-
                        map (arityOf fixture) (publishedArtifacts fixture)
                    ]
                -- Reading one handler entry only says something about the
                -- deployed program if every handler of that validator declares
                -- the same parameters.
                sequence_
                    [ (validator, length (nub declarations)) `shouldBe` (validator, 1)
                    | (validator, declarations) <- siblingDeclarations fixture
                    ]

        it
            "s254_r_every_blueprint_group_is_bound_or_unapplied"
            $ \fixture -> do
                -- "Every live-blueprint validator", not "every artifact this
                -- derivation happens to publish". The publication list covers
                -- seven groups; the blueprint carries more, and a group whose
                -- program is applied somewhere else would keep an unchecked
                -- deployment identity out of every control above.
                let rawTitles = fixtureTitles fixture
                    classified = map fst groupBoundaries
                -- Set equality both ways, over the RAW title list: a new group
                -- in the blueprint is unclassified and fails, a classification
                -- whose group has gone is stale and fails, and a duplicated
                -- validator entry fails rather than being collapsed.
                groupCensus rawTitles classified `shouldBe` Right ()
                -- Shown able to fail, on each of the three ways it can. A
                -- census only ever observed passing is not a census.
                groupCensus (rawTitles <> ["s254r_new.s254r_new.mint"]) classified
                    `shouldSatisfy` isLeft
                groupCensus
                    (filter ((/= "hash_proof.hash_proof") . validatorOf) rawTitles)
                    classified
                    `shouldSatisfy` isLeft
                groupCensus (rawTitles <> take 1 rawTitles) classified
                    `shouldSatisfy` isLeft
                sequence_
                    [ case boundary of
                        PublishedBy name -> do
                            artifact <- artifactNamed fixture name
                            arguments <- recoveredArguments fixture artifact
                            (group, length arguments)
                                `shouldBe` (group, declaredForGroup fixture group)
                        AppliedBy _ apply -> do
                            -- Bound, not exempted: the test drives the
                            -- production applier and recovers what it applied.
                            raw <- groupProgram fixture group
                            arguments <-
                                either fail pure (appliedArguments raw (apply raw))
                            (group, length arguments)
                                `shouldBe` (group, declaredForGroup fixture group)
                        Unapplied _ ->
                            -- Classified raw. It must genuinely not be
                            -- published, or the classification is a lie.
                            [ artifactName artifact
                            | artifact <- publishedArtifacts fixture
                            , validatorOf (artifactBlueprintTitle artifact)
                                == group
                            ]
                                `shouldBe` []
                    | (group, boundary) <- groupBoundaries
                    ]

        it "s254_r_declared_arity_mutant_rejects" $ \fixture -> do
            -- Control first: the unmutated live blueprint must derive, or the
            -- rejection below would prove nothing.
            reDerive fixture id >>= (`shouldSatisfy` isRight)
            let extend parameters = parameters <> [syntheticParameter]
            -- The mutation must have landed. A mutant that silently failed to
            -- apply reports "caught" while having tested nothing.
            mutated <- declaredCountAfter fixture extend
            mutated `shouldBe` succ (declaredCount fixture)
            outcome <- reDerive fixture extend
            outcome `shouldSatisfy` isLeft

        it "s254_r_application_arity_mutant_rejects" $ \fixture -> do
            -- Oracle control only, never the production leg: the recovery
            -- must be able to see an over-application at all.  This applies a
            -- ninth argument to the raw register program -- the exact stray
            -- version integer A-007 reported -- and requires nine back.
            raw <- programOf fixture registerTitle
            canonical <- registerArguments fixture
            let overApplied =
                    applyArgumentList (I v1CheckpointVersion : canonical) raw
            case appliedArguments raw overApplied of
                Left err -> expectationFailure ("oracle: " <> err)
                Right recovered ->
                    length recovered `shouldBe` succ (length canonical)
            -- The production leg.  The blueprint declaration is left exactly
            -- as the live toolchain produced it; only the application plan is
            -- mutated, and it is routed through the same constructor
            -- `deriveV1Scripts` publishes every artifact through.  A parallel
            -- test-only applier would prove nothing about what ships.
            validator <- blueprintValidator fixture registerTitle
            let publish plan =
                    mkAppliedArtifact
                        "checkpoint-register"
                        "validator-and-minting-policy"
                        validator
                        plan
                        raw
            -- Control: the exact plan the live derivation applies is accepted,
            -- so the rejections below are about arity and nothing else.
            publish canonical `shouldSatisfy` isRight
            -- One argument too many, and one too few: no artifact may be
            -- published from either.
            publish (I v1CheckpointVersion : canonical) `shouldSatisfy` isLeft
            publish (init canonical) `shouldSatisfy` isLeft

        it "s254_r_register_version_argument_absent" $ \fixture -> do
            applied <- registerArguments fixture
            expected <- expectedRegisterArguments fixture
            -- The exact nine-argument list, in order, built from the sibling
            -- artifacts this same derivation produced.
            applied `shouldBe` expected
            -- Stated separately so a failure names the defect rather than
            -- printing two long lists.
            take 1 applied `shouldNotBe` [I v1CheckpointVersion]
            length applied `shouldBe` declaredCount fixture

        it "s254_r_version_remnant_sweep_is_complete" $ \fixture -> do
            -- 0. The census must see every published artifact exactly once,
            --    under a distinct title.  Without this a duplicate or missing
            --    title could leave an artifact unexamined while the example
            --    still passed.
            let censusTitles = map fst (appliedArgumentLists fixture)
            length censusTitles
                `shouldBe` length (publishedArtifacts fixture)
            nub censusTitles `shouldBe` censusTitles
            -- 1. Every retained version argument sits at a position the
            --    blueprint declares as a version parameter.  This is the rule
            --    whose absence produced A-007.  A recovery that failed is a
            --    failure here, never a silently skipped artifact.
            sequence_
                [ case recovered of
                    Left err ->
                        expectationFailure (T.unpack title <> ": " <> err)
                    Right arguments ->
                        sequence_
                            [ (title, position, arguments !! position)
                                `shouldBe` (title, position, I v1CheckpointVersion)
                            | (position, parameter) <-
                                zip [0 ..] (declaredFor fixture title)
                            , isVersionShaped parameter
                            , position < length arguments
                            ]
                | (title, recovered) <- appliedArgumentLists fixture
                ]
            -- 2. The register declares no version parameter and applies
            --    exactly what it declares, so no undeclared version argument
            --    can be hiding in its list.
            filter isVersionShaped (declaredFor fixture registerTitle)
                `shouldBe` []
            applied <- registerArguments fixture
            length applied `shouldBe` declaredCount fixture
            -- 3. The serialized manifest surface carries exactly one
            --    version-shaped key.  It is retained, not cut: the deployed
            --    preprod manifest carries this field and must keep parsing.
            manifest <-
                either
                    fail
                    pure
                    ( mkManifest
                        "https://github.com/lambdasistemi/cardano-keri"
                        (T.replicate 40 "0")
                        "blueprint-digest"
                        "2026-08-13T00:00:00Z"
                        (fixtureArtifacts fixture)
                        (references (fixtureArtifacts fixture))
                    )
            sort (versionShapedKeys (Aeson.toJSON manifest))
                `shouldBe` ["checkpointVersion"]

boardTargetApplicationSpec :: Spec
boardTargetApplicationSpec =
    describe "S254-2 target board application" $
        it "s254_2_board_target_applies_frozen_predecessor_policy" $ do
            path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
            blueprint <- loadBlueprint path >>= either fail pure
            raw <-
                maybe
                    (fail "target board compiled code is absent")
                    pure
                    ( extractCompiledCodeExact
                        "endpoint_board.endpoint_board.mint"
                        blueprint
                    )
            predecessor <- either fail pure (decodeHex frozenEndpointBoardPolicyId)
            artifact <-
                either fail pure (deriveBoardTargetScript predecessor blueprint)
            arguments <-
                either fail pure (appliedArguments raw $ artifactProgram artifact)
            arguments `shouldBe` [B predecessor]

            let substituted = BS.replicate 28 0
            substitutedArtifact <-
                either fail pure (deriveBoardTargetScript substituted blueprint)
            substitutedArguments <-
                either
                    fail
                    pure
                    (appliedArguments raw $ artifactProgram substitutedArtifact)
            substitutedArguments `shouldBe` [B substituted]
            substitutedArguments `shouldNotBe` arguments

-- ---------------------------------------------------------------------------
-- The structural oracle
-- ---------------------------------------------------------------------------

{- | The exact argument list an artifact carries, recovered from its bytes.

The recovered list is verified by re-application: it must reproduce the
artifact byte for byte from the raw blueprint program.  This is what makes a
count from this function evidence rather than an assumption about how many
@Apply@ nodes a compiled program happens to have.
-}
appliedArguments ::
    SBS.ShortByteString ->
    SBS.ShortByteString ->
    Either String [Data]
appliedArguments raw applied
    | depth < 0 =
        Left "artifact applies fewer arguments than the blueprint program"
    | otherwise = do
        arguments <- collect depth appliedTerm []
        if applyArgumentList arguments raw == applied
            then Right arguments
            else Left "recovered arguments do not reproduce the artifact"
  where
    Program _ _ rawTerm = uncheckedDeserialiseUPLC raw
    Program _ _ appliedTerm = uncheckedDeserialiseUPLC applied
    depth = spine appliedTerm - spine rawTerm
    spine (UPLC.Apply _ function _) = 1 + spine function :: Int
    spine _ = 0
    collect 0 _ accumulated = Right accumulated
    collect count (UPLC.Apply _ function argument) accumulated =
        case constantData argument of
            Just value -> collect (count - 1) function (value : accumulated)
            Nothing -> Left "an applied argument is not a Data constant"
    collect _ _ _ = Left "the artifact is not an application spine"

{- | The @Data@ payload of a constant term, when it carries one.

Kept separate so the universe refinement happens under an explicit signature;
inside an inferred local binding the refined type escapes its scope.
-}
constantData :: UPLC.Term name PLC.DefaultUni fun ann -> Maybe Data
constantData (UPLC.Constant _ (PLC.Some (PLC.ValueOf universe value))) =
    case universe of
        PLC.DefaultUniData -> Just value
        _ -> Nothing
constantData _ = Nothing

{- | Apply a @Data@ argument list to a compiled program.

Deliberately a separate implementation from the production applier: the oracle
must not inherit the behaviour it is judging.
-}
applyArgumentList :: [Data] -> SBS.ShortByteString -> SBS.ShortByteString
applyArgumentList arguments code =
    serialiseUPLC (foldl apply (uncheckedDeserialiseUPLC code) arguments)
  where
    apply program value =
        let Program _ versionTag _ = program
            argument =
                Program
                    ()
                    versionTag
                    ( UPLC.Constant
                        ()
                        (PLC.Some (PLC.ValueOf PLC.DefaultUniData value))
                    )
         in either (error . ("ScriptAritySpec: " <>) . show) id $
                applyProgram program argument

-- ---------------------------------------------------------------------------
-- Blueprint reading, independent of the production parser
-- ---------------------------------------------------------------------------

{- | Every validator title, in blueprint order, with nothing collapsed.

'declaredParameters' builds a 'Map' and would silently keep one of a duplicate
pair; asking that map about duplicates could only ever answer no.
-}
validatorTitles :: Aeson.Value -> Either String [Text]
validatorTitles value = do
    entries <- validatorEntries value
    traverse (textField "title") entries

declaredParameters :: Aeson.Value -> Either String (Map Text [Text])
declaredParameters value = do
    entries <- validatorEntries value
    Map.fromList <$> traverse entry entries
  where
    entry object = do
        title <- textField "title" object
        pure (title, parameterTitles object)

compiledPrograms ::
    Aeson.Value ->
    Either String (Map Text SBS.ShortByteString)
compiledPrograms value = do
    entries <- validatorEntries value
    Map.fromList . concat <$> traverse entry entries
  where
    entry object = do
        title <- textField "title" object
        case KeyMap.lookup "compiledCode" object of
            Just (Aeson.String hex) -> do
                bytes <- decodeHex hex
                pure [(title, SBS.toShort bytes)]
            _ -> pure []

validatorEntries :: Aeson.Value -> Either String [Aeson.Object]
validatorEntries (Aeson.Object object) =
    case KeyMap.lookup "validators" object of
        Just (Aeson.Array items) -> traverse expectObject (toList items)
        _ -> Left "blueprint carries no validators array"
  where
    expectObject (Aeson.Object entry) = Right entry
    expectObject _ = Left "a blueprint validator is not an object"
validatorEntries _ = Left "blueprint is not a JSON object"

parameterTitles :: Aeson.Object -> [Text]
parameterTitles object =
    case KeyMap.lookup "parameters" object of
        Just (Aeson.Array parameters) -> map titleOf (toList parameters)
        _ -> []
  where
    titleOf (Aeson.Object parameter) =
        case KeyMap.lookup "title" parameter of
            Just (Aeson.String title) -> title
            _ -> ""
    titleOf _ = ""

textField :: Key.Key -> Aeson.Object -> Either String Text
textField key object =
    case KeyMap.lookup key object of
        Just (Aeson.String value) -> Right value
        _ -> Left ("blueprint entry has no " <> Key.toString key)

decodeHex :: Text -> Either String ByteString
decodeHex = convertFromBase Base16 . TE.encodeUtf8

-- ---------------------------------------------------------------------------
-- Fixture accessors
-- ---------------------------------------------------------------------------

publishedArtifacts :: Fixture -> [ScriptArtifact]
publishedArtifacts fixture =
    fixtureArtifacts fixture <> [fixtureBoard fixture]

declaredFor :: Fixture -> Text -> [Text]
declaredFor fixture title =
    Map.findWithDefault [] title (fixtureDeclared fixture)

declaredCount :: Fixture -> Int
declaredCount fixture = length (declaredFor fixture registerTitle)

programOf :: Fixture -> Text -> IO SBS.ShortByteString
programOf fixture title =
    maybe
        (fail (T.unpack title <> " has no compiled code in the blueprint"))
        pure
        (Map.lookup title (fixturePrograms fixture))

-- | The production module's own parse of one live blueprint entry.
blueprintValidator :: Fixture -> Text -> IO Validator
blueprintValidator fixture title =
    maybe
        (fail (T.unpack title <> " is absent from the blueprint"))
        pure
        (Map.lookup title (fixtureValidators fixture))

{- | The declared and applied counts of one artifact, or why they could not be
compared.
-}
arityOf :: Fixture -> ScriptArtifact -> (Text, Either String (Int, Int))
arityOf fixture artifact = (title, result)
  where
    title = artifactBlueprintTitle artifact
    result = do
        raw <-
            maybe
                (Left "no compiled code in the blueprint")
                Right
                (Map.lookup title (fixturePrograms fixture))
        arguments <- appliedArguments raw (artifactProgram artifact)
        pure (length (declaredFor fixture title), length arguments)

{- | Every published artifact's recovered argument list, or the reason it could
not be recovered.

One entry per published artifact, unconditionally: a recovery that fails must
surface as a failure of whatever example is reading it, never as an artifact
quietly missing from a census.
-}
appliedArgumentLists :: Fixture -> [(Text, Either String [Data])]
appliedArgumentLists fixture =
    [ (title, recovery artifact title)
    | artifact <- publishedArtifacts fixture
    , let title = artifactBlueprintTitle artifact
    ]
  where
    recovery artifact title = do
        raw <-
            maybe
                (Left "no compiled code in the blueprint")
                Right
                (Map.lookup title (fixturePrograms fixture))
        appliedArguments raw (artifactProgram artifact)

-- | The published register artifact.
registerArtifact :: Fixture -> IO ScriptArtifact
registerArtifact fixture =
    maybe
        (fail "the register artifact was not published")
        pure
        ( lookup
            registerTitle
            [ (artifactBlueprintTitle candidate, candidate)
            | candidate <- fixtureArtifacts fixture
            ]
        )

registerArguments :: Fixture -> IO [Data]
registerArguments fixture = do
    raw <- programOf fixture registerTitle
    artifact <- registerArtifact fixture
    either fail pure (appliedArguments raw (artifactProgram artifact))

{- | Emit the corrected register's deployment identity for the M8 compiled
target recipe.

Every field is computed here, from the live blueprint and the production
derivation, so the recipe prints the identity the deployment would actually
publish rather than a value restated beside it.  The program digest is the
SHA-256 of the exact @compiledCode@ hex the blueprint carries, which is how the
flake extracts the program the Lean CEK executes; the recipe requires the two
digests to be equal, so the announced identity and the executed program cannot
be different validators.
-}
emitRegisterIdentity :: IO ()
emitRegisterIdentity = do
    fixture <- withFixture
    validator <- blueprintValidator fixture registerTitle
    hex <-
        maybe
            (fail "the register carries no compiled code")
            pure
            (vCompiledCode validator)
    artifact <- registerArtifact fixture
    applied <- registerArguments fixture
    putStrLn $
        "register-identity title="
            <> T.unpack registerTitle
            <> " program_sha256="
            <> T.unpack (sha256Hex (TE.encodeUtf8 hex))
            <> " script_hash="
            <> T.unpack (scriptHashText (artifactScriptHash artifact))
            <> " declared_args="
            <> show (length (vParameters validator))
            <> " applied_args="
            <> show (length applied)

sha256Hex :: ByteString -> Text
sha256Hex bytes =
    TE.decodeUtf8 (convertToBase Base16 (hash bytes :: Digest SHA256))

{- | What the corrected register must be applied to: the five sibling policy
hashes this same derivation produced, then the four deployment integers.  No
element of this list is written down twice.
-}
expectedRegisterArguments :: Fixture -> IO [Data]
expectedRegisterArguments fixture = do
    migration <- policyOf "observer-migration"
    lifecycle <- policyOf "observer-lifecycle"
    advance <- policyOf "observer-advance"
    enforcement <- policyOf "observer-enforcement"
    entitlement <- policyOf "observer-entitlement"
    pure
        [ B migration
        , B lifecycle
        , B advance
        , B enforcement
        , B entitlement
        , I v1NetworkDiscriminator
        , I v1RegistrationBond
        , I v1FreezeBond
        , I v1FreezeWindow
        ]
  where
    policyOf name =
        case filter ((== name) . artifactName) (fixtureArtifacts fixture) of
            [artifact] ->
                either
                    fail
                    pure
                    (decodeHex (scriptHashText (artifactScriptHash artifact)))
            _ -> fail (T.unpack name <> " was not published exactly once")

-- ---------------------------------------------------------------------------
-- The blueprint-group boundary census
-- ---------------------------------------------------------------------------

{- | How this repository applies arguments to one blueprint validator group.

Every group in the live blueprint carries exactly one of these. There is no
default and no fallthrough: an unrecognised group fails the census rather than
being assumed harmless, because the failure mode being closed here is precisely
a validator whose program acquires an applied identity somewhere nobody
enumerated.
-}
data Boundary
    = -- | published by the deployment derivation under this artifact name
      PublishedBy Text
    | -- | applied by a named production applier the census drives directly
      AppliedBy Text (SBS.ShortByteString -> SBS.ShortByteString)
    | -- | no application boundary in this repository, with the reason
      Unapplied Text

{- | The complete classification of live blueprint groups at this candidate.

Cage is bound, not excused: `applyParams` is a real production application
boundary that does not run through 'mkAppliedArtifact' — its consumer,
@offchain/e2e/CageTxBuilder.hs@, is outside this slice's fence — so the census
drives that exact applier and recovers what it applied instead of taking its
arity on trust.

@checkpoint.checkpoint@ is the legacy M1 group in THIS live blueprint, and it
is classified raw and unpublished: the deployment derivation does not touch it,
so it produces no artifact and no identity. It is classified rather than
omitted, so it cannot quietly acquire one.

That is a separate fact from the M8 S2 evidence, which executes a
@checkpoint.checkpoint.spend@ program taken from the FROZEN baseline blueprint.
That is a different artifact of a different blueprint, it publishes no identity
either, and it is classified on its own row in the application-site census in
@scripts/check-version-remnant-sweep.sh@. The two are deliberately not conflated
here: "this live group is unapplied" and "that frozen program is executed as
evidence" are different claims about different bytes.

S254-E's entitlement group will appear here after rebase, and will have to enter
this same census.
-}
groupBoundaries :: [(Text, Boundary)]
groupBoundaries =
    [ ("hash_proof.hash_proof", PublishedBy "hash-proof")
    ,
        ( "bounty_commitment.bounty_commitment"
        , AppliedBy
            "applyCommitmentParams"
            (applyCommitmentParams v1CommitmentParameters)
        )
    ,
        ( "checkpoint_observer.observer_lifecycle"
        , PublishedBy "observer-lifecycle"
        )
    ,
        ( "checkpoint_observer.observer_advance"
        , PublishedBy "observer-advance"
        )
    ,
        ( "checkpoint_observer.observer_enforcement"
        , PublishedBy "observer-enforcement"
        )
    ,
        ( "checkpoint_observer.observer_entitlement"
        , PublishedBy "observer-entitlement"
        )
    ,
        ( "checkpoint_observer.observer_migration"
        , PublishedBy "observer-migration"
        )
    ,
        ( "checkpoint_register.checkpoint_register"
        , PublishedBy "checkpoint-register"
        )
    , ("endpoint_board.endpoint_board", PublishedBy "endpoint-board")
    ,
        ( "cage.mpfCage"
        , AppliedBy
            "applyParams"
            (applyParams v1CheckpointVersion cagePredecessorPolicy)
        )
    ,
        ( "checkpoint.checkpoint"
        , Unapplied
            "legacy M1 group: no off-chain application site; the M8 S2 \
            \evidence executes it from the frozen baseline with Lean-supplied \
            \parameters and publishes no identity"
        )
    ]

{- | Every name an 'AppliedBy' row declares.

The scanner's recognized-applier set is derived from this list.  A newly
named applier therefore cannot enter an unscanned parallel hand-list.
-}
appliedByNames :: [String]
appliedByNames =
    nub
        [ T.unpack name
        | (_, AppliedBy name _) <- groupBoundaries
        ]

{- | A placeholder predecessor policy for the Cage boundary, at the exact
28-byte width a policy id has. The census is about how many arguments
'applyParams' applies, not which policy it names.
-}
cagePredecessorPolicy :: ByteString
cagePredecessorPolicy = BS.replicate 28 0

{- | The group census, as a value rather than as an expectation.

Returning 'Either' is what lets the census be shown rejecting a new group, a
missing group and a duplicate title, instead of only ever being observed
passing. It is given the raw title list precisely so the duplicate check has
something to find.
-}
groupCensus :: [Text] -> [Text] -> Either String ()
groupCensus rawTitles classified
    | nub rawTitles /= rawTitles =
        Left "the blueprint carries a duplicate validator title"
    | nub classified /= classified =
        Left "the classification carries a duplicate group"
    | not (null unclassified) =
        Left ("unclassified blueprint groups: " <> show unclassified)
    | not (null vanished) =
        Left ("classified groups absent from the blueprint: " <> show vanished)
    | otherwise = Right ()
  where
    present = nub (map validatorOf rawTitles)
    unclassified = filter (`notElem` classified) present
    vanished = filter (`notElem` present) classified

-- | The declared parameter count of a group, from any of its handler entries.
declaredForGroup :: Fixture -> Text -> Int
declaredForGroup fixture group =
    case [ parameters
         | (title, parameters) <- Map.toList (fixtureDeclared fixture)
         , validatorOf title == group
         ] of
        (parameters : _) -> length parameters
        [] -> -1

{- | The unapplied compiled program of a group, from any handler entry carrying
one. Every handler of an Aiken validator compiles to the same program.
-}
groupProgram :: Fixture -> Text -> IO SBS.ShortByteString
groupProgram fixture group =
    case [ program
         | (title, program) <- Map.toList (fixturePrograms fixture)
         , validatorOf title == group
         ] of
        (program : _) -> pure program
        [] -> fail (T.unpack group <> " carries no compiled code")

artifactNamed :: Fixture -> Text -> IO ScriptArtifact
artifactNamed fixture name =
    case filter ((== name) . artifactName) (publishedArtifacts fixture) of
        [artifact] -> pure artifact
        _ -> fail (T.unpack name <> " was not published exactly once")

recoveredArguments :: Fixture -> ScriptArtifact -> IO [Data]
recoveredArguments fixture artifact = do
    raw <- programOf fixture (artifactBlueprintTitle artifact)
    either fail pure (appliedArguments raw (artifactProgram artifact))

-- | Declared parameter lists, grouped by the validator that owns them.
siblingDeclarations :: Fixture -> [(Text, [[Text]])]
siblingDeclarations fixture =
    Map.toList $
        Map.fromListWith
            (<>)
            [ (validatorOf title, [parameters])
            | (title, parameters) <- Map.toList (fixtureDeclared fixture)
            ]

-- | The @module.validator@ prefix shared by every handler of one validator.
validatorOf :: Text -> Text
validatorOf = T.intercalate "." . take 2 . T.splitOn "."

-- ---------------------------------------------------------------------------
-- Blueprint mutation
-- ---------------------------------------------------------------------------

syntheticParameter :: Aeson.Value
syntheticParameter =
    Aeson.object
        [ "title" Aeson..= ("s254_r_synthetic" :: Text)
        , "schema" Aeson..= Aeson.object []
        ]

{- | Re-run the production derivation over a blueprint whose register
declaration has been mutated.
-}
reDerive ::
    Fixture ->
    ([Aeson.Value] -> [Aeson.Value]) ->
    IO (Either String [ScriptArtifact])
reDerive fixture mutate =
    withMutatedBlueprint fixture mutate $ \path -> do
        blueprint <- loadBlueprint path
        pure (blueprint >>= deriveV1Scripts)

-- | The register's declared parameter count after a mutation.
declaredCountAfter ::
    Fixture ->
    ([Aeson.Value] -> [Aeson.Value]) ->
    IO Int
declaredCountAfter fixture mutate =
    withMutatedBlueprint fixture mutate $ \path -> do
        bytes <- BS.readFile path
        value <- either fail pure (Aeson.eitherDecodeStrict' bytes)
        declared <- either fail pure (declaredParameters value)
        pure (length (Map.findWithDefault [] registerTitle declared))

{- | Write the live blueprint back out with every register handler's declared
parameter list transformed, and hand the result to an action.

All handler entries of the validator are mutated together, because that is the
only shape a real blueprint can have.
-}
withMutatedBlueprint ::
    Fixture ->
    ([Aeson.Value] -> [Aeson.Value]) ->
    (FilePath -> IO r) ->
    IO r
withMutatedBlueprint fixture mutate action =
    withSystemTempFile "s254-r-blueprint.json" $ \path handle -> do
        hClose handle
        BSL.writeFile path (Aeson.encode (mutateValue (fixtureValue fixture)))
        action path
  where
    mutateValue (Aeson.Object object) =
        case KeyMap.lookup "validators" object of
            Just validators ->
                Aeson.Object
                    ( KeyMap.insert
                        "validators"
                        (mutateValidators validators)
                        object
                    )
            Nothing -> Aeson.Object object
    mutateValue value = value
    mutateValidators (Aeson.Array items) = Aeson.Array (fmap mutateEntry items)
    mutateValidators value = value
    mutateEntry (Aeson.Object entry)
        | Right title <- textField "title" entry
        , validatorOf title == validatorOf registerTitle =
            Aeson.Object
                ( KeyMap.insert
                    "parameters"
                    (Aeson.toJSON (mutate (currentParameters entry)))
                    entry
                )
    mutateEntry value = value
    currentParameters entry =
        case KeyMap.lookup "parameters" entry of
            Just (Aeson.Array parameters) -> toList parameters
            _ -> []

-- ---------------------------------------------------------------------------
-- Small shared helpers
-- ---------------------------------------------------------------------------

{- | A version-shaped parameter title.  Aiken renders an unused parameter with a
leading underscore, so both spellings count.
-}
isVersionShaped :: Text -> Bool
isVersionShaped title = "version" `T.isInfixOf` T.toLower title

-- | Every object key anywhere in a JSON value whose name mentions a version.
versionShapedKeys :: Aeson.Value -> [Text]
versionShapedKeys (Aeson.Object object) =
    filter isVersionShaped (map Key.toText (KeyMap.keys object))
        <> concatMap versionShapedKeys (KeyMap.elems object)
versionShapedKeys (Aeson.Array items) =
    concatMap versionShapedKeys items
versionShapedKeys _ = []

-- | Distinct placeholder references, one per published artifact.
references :: [ScriptArtifact] -> [(Text, Reference)]
references artifacts =
    [ (artifactName artifact, Reference (referenceId index) 0)
    | (index, artifact) <- zip [0 :: Int ..] artifacts
    ]
  where
    referenceId index =
        T.justifyRight 64 '0' (T.pack (show index))

isLeft :: Either a b -> Bool
isLeft = either (const True) (const False)

isRight :: Either a b -> Bool
isRight = not . isLeft

-- ---------------------------------------------------------------------------
-- The S254-R derived deployment control
-- ---------------------------------------------------------------------------

{- | Constructor internals the PublishedBy path actually uses.

These are not a parallel 'AppliedBy' list.  Names declared by
'groupBoundaries' enter 'applierNames' by derivation.
-}
primitiveHeads :: [String]
primitiveHeads =
    [ "applyDataArgs"
    , "applyProgram"
    , "mkAppliedArtifact"
    , "runProgram"
    ]

{- | The production appliers whose application expressions the census
inventories.

These are identifier names, not source patterns.  The census asks the syntax
tree which expressions apply a function whose head is one of these names, so a
call spelled across three lines, wrapped in parentheses, carrying a type
annotation, or sharing a line with another call is the same one row as a call
spelled plainly — which is exactly the class of question the rejected
source-text control could not answer.

The set is the constructor internals plus every 'AppliedBy' name.  A
hand-maintained parallel list is the defect this derivation closes.
-}
applierNames :: [String]
applierNames = nub (primitiveHeads ++ appliedByNames)

{- | Directory names the walk never descends into.

Build output is not source: a generated module inside @dist-newstyle@ is not a
production applier and its presence must not be able to move a census count.
The list is skipped by name rather than by content, so it cannot be used to
excuse a tracked source file.
-}
skippedDirectories :: [FilePath]
skippedDirectories =
    [ ".git"
    , ".lake"
    , ".stack-work"
    , "dist-newstyle"
    , "node_modules"
    , "result"
    ]

{- | The two source paths the self-test mutates, named once.

They are the production surfaces the frozen gate's probes edit: the deployment
script module that carries the version-shaped deployment constants, and the
Cage transaction builder that is the one production applier outside
@offchain/deployment@.
-}
deploymentScriptPath :: FilePath
deploymentScriptPath = deploymentModule "Script"

{- | A module of the censused deployment library, by its module name.

The census tables below name several of these, and spelling the shared prefix
once keeps a table row from silently naming a path that does not exist: a
misspelled path would appear as a @missing@ row rather than as a typo.
-}
deploymentModule :: String -> FilePath
deploymentModule name =
    "offchain/deployment/Cardano/KERI/Deployment/" <> name <> ".hs"

-- | The single declared production applier outside the deployment directory.
cageBuilderPath :: FilePath
cageBuilderPath = "offchain/e2e/CageTxBuilder.hs"

{- | Deployment proof that drives production appliers as a test.

It is not a production application surface, but it necessarily mentions
'AppliedBy' names.  The discovery sweep would otherwise treat those
mentions as an incomplete horizon.
-}
entitlementSpecPath :: FilePath
entitlementSpecPath =
    "offchain/deployment-test/Cardano/KERI/Deployment/BountyEntitlementSpec.hs"

{- | One census row: a module, an identifier, and how many times that identifier
occurs in that module's syntax tree.

The count is an occurrence count over AST nodes, never over lines or matches,
so two occurrences on one line are two and a mention inside a comment or a
string literal is none.
-}
data CensusRow = CensusRow FilePath String Int
    deriving stock (Eq, Ord, Show)

-- | A census row in the form the control prints when it disagrees.
renderRow :: CensusRow -> String
renderRow (CensusRow path name count) =
    path <> ":" <> name <> "=" <> show count

{- | Where the census looks, as a value rather than as a constant.

It is a value so that every skip and exclusion the control relies on can be
perturbed by the self-test and shown to be load-bearing.  An exclusion that
cannot be shown to matter is indistinguishable from a suppression.
-}
data ScanConfig = ScanConfig
    { scanRoot :: FilePath
    , scanHorizonRoot :: FilePath
    , scanHorizonExtras :: [FilePath]
    , scanExclusions :: [FilePath]
    }

{- | The censused horizon at this candidate.

@offchain/deployment@ enters by directory walk, so a new production deployment
module is covered automatically and cannot rot out of the horizon.  The Cage
builder is hand-declared because it is the one production applier outside that
directory, and a hand-declared path is guarded twice: it must exist, and the
discovery sweep independently fails if any other module mentions an applier.

The exclusions are this module, which necessarily names every applier, and
'BountyEntitlementSpec', which drives production appliers as a test.
Leaving this module inside the horizon would make the control a census of
itself.  Each exclusion is proved load-bearing by its own falsification
leg.
-}
defaultScanConfig :: FilePath -> ScanConfig
defaultScanConfig root =
    ScanConfig
        { scanRoot = root
        , scanHorizonRoot = "offchain/deployment"
        , scanHorizonExtras = [cageBuilderPath]
        , scanExclusions =
            [ "offchain/deployment-test/Cardano/KERI/Deployment/ScriptAritySpec.hs"
            , entitlementSpecPath
            ]
        }

{- | What one scan concluded.

The three outcomes are deliberately distinct exit codes.  A broken instrument
must never be readable as a catch: if the parser fails, an exclusion is stale,
or the blueprint cannot be loaded, the control reports 2 and no caller can
mistake that for the 1 it returns when the census genuinely disagrees.
-}
data ScanVerdict
    = -- | applications, version occurrences, blueprint groups, removed, kept
      ScanClean Int Int Int Int Int
    | -- | the census disagrees with what this control declares
      ScanCatch [String]
    | -- | the instrument could not answer, and says so instead of passing
      ScanBroken String

-- | 0 clean, 1 census catch, 2 broken instrument.
verdictCode :: ScanVerdict -> Int
verdictCode ScanClean{} = 0
verdictCode ScanCatch{} = 1
verdictCode ScanBroken{} = 2

{- | Every Haskell module under one relative directory, as paths relative to the
scan root, sorted.
-}
haskellFiles :: FilePath -> FilePath -> IO [FilePath]
haskellFiles root relative = do
    isDirectory <- doesDirectoryExist (root </> relative)
    if not isDirectory
        then pure []
        else do
            entries <- listDirectory (root </> relative)
            fmap (sort . concat) (mapM descend entries)
  where
    descend entry
        | entry `elem` skippedDirectories = pure []
        | otherwise = do
            let child = if null relative then entry else relative </> entry
            isDirectory <- doesDirectoryExist (root </> child)
            if isDirectory
                then haskellFiles root child
                else pure [child | takeExtension child == ".hs"]

{- | The exact module list the census observes, or the reason it cannot be
built.

Every failure here is fail-closed.  A declared extra that no longer exists, an
exclusion that no longer names a file, or a horizon walk that found nothing are
all reported as a broken instrument, because each of them is a way for a census
to report success while observing less than it claims.
-}
resolveHorizon :: ScanConfig -> IO (Either String [FilePath])
resolveHorizon config = do
    walked <- haskellFiles (scanRoot config) (scanHorizonRoot config)
    missingExtras <- absentPaths (scanHorizonExtras config)
    staleExclusions <- absentPaths (scanExclusions config)
    let horizon = sort (nub (walked <> scanHorizonExtras config))
        kept = filter (`notElem` scanExclusions config) horizon
    pure $ case () of
        ()
            | not (null missingExtras) ->
                Left ("declared horizon paths absent: " <> show missingExtras)
            | not (null staleExclusions) ->
                Left ("declared exclusions absent: " <> show staleExclusions)
            | null walked ->
                Left ("no modules under " <> scanHorizonRoot config)
            | null kept ->
                Left "every horizon module is excluded"
            | otherwise -> Right kept
  where
    absentPaths = fmap concat . mapM check
    check path = do
        present <- doesFileExist (scanRoot config </> path)
        pure [path | not present]

{- | The conservative discovery sweep over everything the census does not
observe.

This is a substring sweep, and that is deliberate: it decides /routing/, never
/admission/.  Admission is the syntax tree's job.  A substring sweep can only
over-report, and over-reporting fails the scan, so the failure mode it has is
the safe one.  Its purpose is that the hand-declared half of the horizon cannot
silently stop being complete — the exact rot that falsified this slice's earlier
source-text controls three times.
-}
discoverySweep :: ScanConfig -> [FilePath] -> IO (Either String ())
discoverySweep config horizon = do
    everything <- haskellFiles (scanRoot config) ""
    let outside =
            [ path
            | path <- everything
            , path `notElem` horizon
            , path `notElem` scanExclusions config
            ]
    mentions <- mapM mentioning outside
    pure $ case sort (concat mentions) of
        [] -> Right ()
        found ->
            Left ("appliers mentioned outside the horizon: " <> show found)
  where
    mentioning path = do
        source <- readSource (scanRoot config </> path)
        pure [path | any (`isInfixOf` source) applierNames]

{- | Observe every module in the horizon, or fail on the first module the
parser cannot answer for.

A parse error is a scan failure, never a skip and never a catch.  A parser that
failed open would censuse nothing while reporting success.
-}
observeHorizon ::
    ScanConfig ->
    [FilePath] ->
    IO (Either String ([CensusRow], [CensusRow]))
observeHorizon config horizon = do
    observations <- mapM observe horizon
    pure $ case lefts observations of
        (reason : _) -> Left reason
        [] ->
            let pairs = rights observations
             in Right
                    ( sort (concatMap fst pairs)
                    , sort (concatMap snd pairs)
                    )
  where
    observe path = do
        source <- readSource (scanRoot config </> path)
        pure (observeModule path source)

{- | The Haskell dialect this control parses.

'GHC.Parser' is given its permitted extension set explicitly; it does not read a
module's own @LANGUAGE@ pragmas, because in a real compilation the driver does
that.  The dialect is therefore declared here rather than discovered, and a
module outside it is a scan /failure/, never a silent skip.  Measured at the
repair base: the horizon's own pragmas are @DataKinds@, @NumericUnderscores@,
@OverloadedStrings@, @ScopedTypeVariables@ and @TypeApplications@, and the rest
is @GHC2021@ plus the package's @default-extensions@.
-}
declaredDialect :: [String]
declaredDialect =
    [ "BangPatterns"
    , "BinaryLiterals"
    , "DataKinds"
    , "DerivingStrategies"
    , "DerivingVia"
    , "DuplicateRecordFields"
    , "EmptyCase"
    , "ExistentialQuantification"
    , "ExplicitForAll"
    , "ExplicitNamespaces"
    , "FlexibleContexts"
    , "FlexibleInstances"
    , "GADTs"
    , "GADTSyntax"
    , "HexFloatLiterals"
    , "ImportQualifiedPost"
    , "InstanceSigs"
    , "KindSignatures"
    , "LambdaCase"
    , "MultiParamTypeClasses"
    , "MultiWayIf"
    , "NamedFieldPuns"
    , "NamedWildCards"
    , "NumericUnderscores"
    , "OverloadedStrings"
    , "PatternSynonyms"
    , "PolyKinds"
    , "PostfixOperators"
    , "RankNTypes"
    , "RecordWildCards"
    , "ScopedTypeVariables"
    , "StandaloneDeriving"
    , "StandaloneKindSignatures"
    , "StarIsType"
    , "StrictData"
    , "TupleSections"
    , "TypeApplications"
    , "TypeFamilies"
    , "TypeOperators"
    , "ViewPatterns"
    ]

{- | Resolve the declared dialect against the parser's own extension
enumeration.

The names are checked against @[minBound .. maxBound]@ rather than trusted, so a
name this parser does not know is reported instead of quietly contributing no
extension and leaving the dialect narrower than it reads.
-}
dialect :: Either String (EnumSet.EnumSet Extension)
dialect =
    case filter (`notElem` map show universe) declaredDialect of
        [] ->
            Right
                (EnumSet.fromList [e | e <- universe, show e `elem` declaredDialect])
        unknown ->
            Left ("the declared dialect names unknown extensions: " <> show unknown)
  where
    universe = [minBound .. maxBound] :: [Extension]

{- | Parser options for the declared dialect.

Comments and Haddock are deliberately not kept.  That is what makes the two
@FALSE-POSITIVE → IGNORE@ legs hold structurally: a version-shaped word inside a
comment contributes no node to the tree, so there is no suppression rule here
that could be relaxed later.
-}
parserOptions :: EnumSet.EnumSet Extension -> ParserOpts
parserOptions extensions =
    mkParserOpts extensions emptyDiagOpts [] False False False True

{- | Derive one module's application sites and version-shaped identifier
occurrences from its syntax tree.

A parse failure is 'Left', which the scan reports as a broken instrument (exit
2).  Neither the baseline probe (expects 0) nor any catch probe (expects 1)
accepts that, so a parser that stopped working cannot be mistaken for either a
clean tree or a catch.
-}
observeModule :: FilePath -> String -> Either String ([CensusRow], [CensusRow])
observeModule path source = do
    extensions <- dialect
    let state =
            initParserState
                (parserOptions extensions)
                (stringToStringBuffer source)
                (mkRealSrcLoc (mkFastString path) 1 1)
    case unP parseModule state of
        PFailed _ ->
            Left ("GHC.Parser rejected " <> path <> "; a horizon module must parse")
        POk _ parsed ->
            Right (tally (applicationSites parsed), tally (versionOccurrences parsed))
  where
    tally occurrences =
        [ CensusRow path occurrence count
        | (occurrence, count) <-
            Map.toList (Map.fromListWith (+) [(o, 1 :: Int) | o <- occurrences])
        ]

{- | Every application expression whose function spine ends in an applier.

This counts syntax-tree nodes, not lines and not tokens.  @f a b c@ is one
'HsApp' spine and therefore one site however it is laid out, which is why two
applications on one line are two sites and an application split across lines is
still one.  The spine head must be an 'HsVar': a parenthesised or annotated
application is reached by ordinary recursion instead, so it is counted exactly
once rather than once per enclosing wrapper.

Recursion continues into the arguments of a recorded site, so an applier applied
inside another applier's argument is its own site.
-}
applicationSites :: (SYB.Data a) => a -> [String]
applicationSites node = case SYB.cast node :: Maybe (HsExpr GhcPs) of
    Just expression
        | (Just applier, arguments) <- peel expression [] ->
            applier : concatMap applicationSites arguments
    _ -> concat (SYB.gmapQ applicationSites node)
  where
    peel (HsApp _ (L _ function) argument) arguments =
        peel function (argument : arguments)
    peel (HsVar _ (L _ identifier)) arguments
        | named <- occNameString (rdrNameOcc identifier)
        , named `elem` applierNames =
            (Just named, arguments)
    peel _ arguments = (Nothing, arguments)

{- | Every version-shaped name occurrence in the syntax tree.

The census is over 'RdrName' nodes, so it sees a binder, a use, and a record
field alike, and it sees them wherever the layout puts them.  It cannot see a
comment or a string literal, because neither contributes an 'RdrName'.
-}
versionOccurrences :: (SYB.Data a) => a -> [String]
versionOccurrences node = case SYB.cast node :: Maybe RdrName of
    Just identifier
        | named <- occNameString (rdrNameOcc identifier)
        , isVersionShaped (T.pack named) ->
            [named]
    _ -> concat (SYB.gmapQ versionOccurrences node)

{- | The application sites this candidate declares.

Measured from the syntax trees of the horizon at the repair base.  Both
directions of 'reconcile' are checked, so a site appearing and a site
disappearing are equally a catch.
-}
declaredApplications :: [CensusRow]
declaredApplications =
    [ CensusRow deploymentScriptPath "applyCommitmentParams" 1
    , CensusRow deploymentScriptPath "applyDataArgs" 4
    , CensusRow deploymentScriptPath "applyProgram" 1
    , CensusRow deploymentScriptPath "mkAppliedArtifact" 9
    , CensusRow cageBuilderPath "applyParams" 1
    ]

{- | The version-shaped name occurrences this candidate declares.

Every row is a name the corrected tree still uses, and each is a use rather
than a residue: the manifest and endpoint-board schema versions are published
fields, @v1CheckpointVersion@ is the surviving checkpoint-family constant the
register no longer applies, and @cageVersion@ belongs to the cage harness.  A
row disappearing is as much a catch as a row appearing, so cutting one of these
without amending this table fails the control.
-}
declaredVersions :: [CensusRow]
declaredVersions =
    [ CensusRow (deploymentModule "EndpointBoard") "replyVersion" 2
    , CensusRow (deploymentModule "EndpointBoard") "validateEventVersion" 4
    , CensusRow (deploymentModule "EndpointBoard") "version" 2
    , CensusRow
        (deploymentModule "EndpointBoardManifest")
        "endpointBoardManifestSchemaVersion"
        4
    , CensusRow
        (deploymentModule "EndpointBoardTransaction")
        "endpointBoardManifestSchemaVersion"
        1
    , CensusRow (deploymentModule "Manifest") "manifestSchemaVersion" 4
    , CensusRow (deploymentModule "Manifest") "parameterCheckpointVersion" 3
    , CensusRow (deploymentModule "Manifest") "v1CheckpointVersion" 2
    , CensusRow deploymentScriptPath "v1CheckpointVersion" 7
    , CensusRow deploymentScriptPath "version" 10
    , CensusRow deploymentScriptPath "versionTag" 2
    , CensusRow cageBuilderPath "cageVersion" 4
    ]

{- | The facts the compiled blueprint proves about the corrected register, and
how many validator groups it classifies.

Nothing here reads source text of any language.  The declared arity comes from
the blueprint JSON, the applied arity is recovered from the artifact's own
bytes by 'appliedArguments' (which proves its recovery by re-application), and
the argument list is compared against the sibling identities this same
derivation published.  That is why the sweep's @removed@ count is a count of
proved facts rather than of deleted lines.
-}
blueprintFacts :: IO (Either String (Int, Int))
blueprintFacts = do
    outcome <- try attempt
    pure $ case outcome of
        Left err -> Left (displayException (err :: SomeException))
        Right facts -> facts
  where
    attempt = do
        fixture <- withFixture
        applied <- registerArguments fixture
        expected <- expectedRegisterArguments fixture
        let declared = declaredFor fixture registerTitle
            classified = map fst groupBoundaries
            proved :: [(String, Bool)]
            proved =
                [ ("register declares no version-shaped parameter", not (any isVersionShaped declared))
                , ("register applies exactly its declared parameters", length applied == length declared)
                , ("register applies this derivation's own arguments", applied == expected)
                ]
        pure $ case groupCensus (fixtureTitles fixture) classified of
            Left reason -> Left reason
            Right () -> case [name | (name, held) <- proved, not held] of
                [] -> Right (length classified, length proved)
                unproved -> Left ("blueprint facts unproved: " <> show unproved)

{- | Compare what this control declares against what the syntax trees say.

Both directions are reported.  A census that only notices additions cannot see
an application site or a version-shaped identifier disappearing, and a
disappearance is how a control quietly stops observing the thing it exists for.
-}
reconcile :: String -> [CensusRow] -> [CensusRow] -> [String]
reconcile label declared observed =
    [ label <> " unexpected " <> renderRow row
    | row <- observed
    , row `notElem` declared
    ]
        <> [ label <> " missing " <> renderRow row
           | row <- declared
           , row `notElem` observed
           ]

{- | One scan of one tree.

The order is deliberate: horizon, then discovery sweep, then parse, then
blueprint, then reconciliation.  Everything that could make the instrument
unable to answer is settled before any verdict about the tree is formed, so a
catch is always a statement about the tree and never about the control.
-}
runScan :: ScanConfig -> IO ScanVerdict
runScan config = do
    resolved <- resolveHorizon config
    case resolved of
        Left reason -> pure (ScanBroken reason)
        Right horizon -> do
            swept <- discoverySweep config horizon
            case swept of
                Left reason -> pure (ScanBroken reason)
                Right () -> do
                    observed <- observeHorizon config horizon
                    case observed of
                        Left reason -> pure (ScanBroken reason)
                        Right (applications, versions) ->
                            conclude applications versions <$> blueprintFacts
  where
    conclude applications versions facts
        | Left reason <- facts = ScanBroken reason
        | null applications =
            ScanBroken "the horizon contains no application sites"
        | null versions =
            ScanBroken "the horizon contains no version-shaped identifiers"
        | Right (groups, removed) <- facts =
            case reconcile "application" declaredApplications applications
                <> reconcile "version" declaredVersions versions of
                [] ->
                    ScanClean
                        (sum [count | CensusRow _ _ count <- applications])
                        (sum [count | CensusRow _ _ count <- versions])
                        groups
                        removed
                        (length versions)
                differences -> ScanCatch differences

{- | Print the scan verdict.

The passing case carries its own quantities, so a pass that observed nothing is
distinguishable from a pass that observed the tree.  The @kept@ count is the
number of version-shaped identifier occurrences the census retains as declared,
and @removed@ is the number of blueprint facts proved about the corrected
register.
-}
emitScan :: ScanVerdict -> IO ()
emitScan (ScanClean applications versions groups removed kept) = do
    putStrLn $
        "S254R_DERIVED_CONTROL source=ghc-lib-parser applications="
            <> show applications
            <> " versions="
            <> show versions
            <> " blueprint_groups="
            <> show groups
    putStrLn $
        "S254-R version-remnant-sweep: PASS removed="
            <> show removed
            <> " kept="
            <> show kept
emitScan (ScanCatch differences) = do
    forM_ differences (hPutStrLn stderr)
    hPutStrLn
        stderr
        "S254-R version-remnant-sweep: FAIL the derived census disagrees"
emitScan (ScanBroken reason) =
    hPutStrLn stderr ("S254-R version-remnant-sweep: BROKEN " <> reason)

{- | The derived control's command line.

@scan@ is the production verdict; @self-test@ is the permanent RED-to-GREEN
demonstration that the frozen source-text control misses what this one catches
and cries wolf where this one is silent.
-}
derivedControlMain :: [String] -> IO ()
derivedControlMain arguments = case arguments of
    ("scan" : rest) -> case flagValue "--root" rest of
        Nothing -> usage
        Just root -> do
            verdict <- runScan (defaultScanConfig root)
            emitScan verdict
            finish (verdictCode verdict)
    ("self-test" : rest) -> case flagValue "--repo-root" rest of
        Nothing -> usage
        Just root -> do
            code <- runSelfTest root (flagValue "--legacy-ref" rest)
            finish code
    _ -> usage
  where
    usage = do
        hPutStrLn
            stderr
            "usage: scan --root DIR | self-test --repo-root DIR [--legacy-ref REF]"
        finish 2

-- | Exit with a scan verdict code.
finish :: Int -> IO ()
finish 0 = exitSuccess
finish code = exitWith (ExitFailure code)

-- | The value of a @--flag value@ pair, if it is present.
flagValue :: String -> [String] -> Maybe String
flagValue flag arguments = case dropWhile (/= flag) arguments of
    (_ : value : _) -> Just value
    _ -> Nothing

{- | One permanent RED-to-GREEN case.

@caseCatchable@ says which way round the two controls must come out.  The
frozen control must miss a catchable mutation and must cry wolf on a benign
one; the derived control must do the opposite in both directions.  Either half
failing fails the self-test, so this cannot degrade into a demonstration that
only ever shows the new control passing.
-}
data SelfTestCase = SelfTestCase
    { caseName :: String
    , caseCatchable :: Bool
    , caseEvidence :: String
    , caseMutate :: FilePath -> IO (Either String ())
    }

-- | The marker the frozen control prints when it ran to a clean conclusion.
legacyPassMarker :: String
legacyPassMarker = "S254-R version-remnant-sweep: PASS"

{- | The five challenges this slice was rejected for not answering.

Three are real defects the frozen control cannot see because it reasons about
lines: a second application on a line it already matched, a version-shaped
identifier introduced inside an existing line, and an application wearing a
type annotation.  Two are non-defects it reports anyway, because a comment and
a string literal look like source text to a source-text control and are simply
not present in a syntax tree.
-}
selfTestCases :: [SelfTestCase]
selfTestCases =
    [ SelfTestCase
        { caseName = "same-line-application"
        , caseCatchable = True
        , caseEvidence = legacyPassMarker
        , caseMutate = mutateSameLineApplication
        }
    , SelfTestCase
        { caseName = "same-line-version"
        , caseCatchable = True
        , caseEvidence = legacyPassMarker
        , caseMutate = mutateSameLineVersion
        }
    , SelfTestCase
        { caseName = "annotated-application"
        , caseCatchable = True
        , caseEvidence = legacyPassMarker
        , caseMutate = mutateAnnotatedApplication
        }
    , SelfTestCase
        { caseName = "comment-only-version"
        , caseCatchable = False
        , caseEvidence = "v1CommentOnlyVersion"
        , caseMutate = mutateCommentOnly
        }
    , SelfTestCase
        { caseName = "string-only-version"
        , caseCatchable = False
        , caseEvidence = "v1StringOnlyVersion"
        , caseMutate = mutateStringOnly
        }
    ]

{- | One falsification leg: a perturbation of the control's own configuration
or surroundings that must make it report a broken instrument.

Each leg also requires the same tree to scan clean unperturbed, so a leg cannot
pass because everything is broken.  That requirement is what makes the legs
report RED while the syntax-tree seam is missing rather than passing vacuously.
-}
data SelfTestLeg = SelfTestLeg
    { legName :: String
    , legPerturb :: FilePath -> ScanConfig -> IO (Either String ScanConfig)
    }

{- | A hidden rebinding of one 'AppliedBy' name outside the scan horizon.

Generated from 'appliedByNames', so a newly declared applier cannot enter
the census without this control covering it.  The plant is a source-only
binding: discovery must refuse it, which is how a name the scanner cannot
see is distinguished from one it can.
-}
hiddenRebindingLeg :: String -> SelfTestLeg
hiddenRebindingLeg name =
    SelfTestLeg ("hidden-rebinding-" <> name) $ \tree config -> do
        present <- doesDirectoryExist (tree </> "offchain")
        if not present
            then pure (Left "offchain is absent from the materialized tree")
            else do
                writeSource
                    (tree </> "offchain/S254RHidden" <> name <> ".hs")
                    ( unlines
                        [ "module S254RHidden" <> name <> " where"
                        , "s254r_hidden_" <> name <> " = " <> name
                        ]
                    )
                pure (Right config)

{- | Every derived skip, exclusion and fail-closed branch, each shown to be
load-bearing.

An exclusion nobody can show mattering is a suppression; a skip nobody can show
mattering is a hole.  The hidden-rebinding legs close the class that a
census row can name an applier the scanner cannot see.
-}
selfTestLegs :: [SelfTestLeg]
selfTestLegs =
    [ SelfTestLeg "exclusion-removed" $ \_ config ->
        pure (Right config{scanExclusions = []})
    , SelfTestLeg "entitlement-spec-exclusion-removed" $ \_ config ->
        pure
            ( Right
                config
                    { scanExclusions =
                        filter
                            (/= entitlementSpecPath)
                            (scanExclusions config)
                    }
            )
    , SelfTestLeg "stale-exclusion" $ \_ config ->
        pure
            ( Right
                config
                    { scanExclusions =
                        scanExclusions config <> ["offchain/deployment/Absent.hs"]
                    }
            )
    , SelfTestLeg "declared-extra-absent" $ \_ config ->
        pure (Right config{scanHorizonExtras = ["offchain/e2e/Absent.hs"]})
    , SelfTestLeg "vacuous-horizon" $ \_ config ->
        pure (Right config{scanHorizonRoot = "offchain/no-such-horizon"})
    , SelfTestLeg "undeclared-applier-surface" $ \tree config -> do
        present <- doesDirectoryExist (tree </> "offchain")
        if not present
            then pure (Left "offchain is absent from the materialized tree")
            else do
                writeSource
                    (tree </> "offchain/S254RUndeclared.hs")
                    (unlines ["module S254RUndeclared where", "u = applyParams"])
                pure (Right config)
    , SelfTestLeg "unparseable-horizon" $ \tree config -> do
        let path = tree </> deploymentScriptPath
        source <- readSource path
        writeSource path (source <> "\ns254rUnparseable = (\n")
        pure (Right config)
    ]
        <> map hiddenRebindingLeg appliedByNames

{- | Run the self-test.

With @--legacy-ref@ the frozen control runs beside the derived one and the
markers carry both verdicts; that is the form the frozen gate consumes.
Without it only the derived half runs, so the launcher can execute the same
demonstration in CI without depending on a particular commit staying
reachable.
-}
runSelfTest :: FilePath -> Maybe String -> IO Int
runSelfTest repoRoot legacyRef = do
    caseResults <- mapM reportCase selfTestCases
    legResults <- mapM reportLeg selfTestLegs
    if and (caseResults <> legResults)
        then do
            putStrLn "S254R_DERIVED_SELFTEST selftest=pass"
            pure 0
        else do
            hPutStrLn stderr "S254R_DERIVED_SELFTEST selftest=fail"
            pure 1
  where
    reportCase testCase = do
        (line, held) <- runSelfTestCase repoRoot legacyRef testCase
        putStrLn line
        pure held
    reportLeg leg = do
        (line, held) <- runSelfTestLeg repoRoot legacyRef leg
        putStrLn line
        pure held

{- | Materialize the candidate, mutate it, and read both controls' verdicts.

The derived half always scans HEAD.  Declared census rows are measured
from this candidate; materializing the frozen source-text sweep's tree
would make every IGNORE case fail for stale counts rather than for the
parser property under test.

The frozen half, when requested, materializes the legacy ref separately
so it still runs the historical source-text sweep against that tree.
-}
runSelfTestCase ::
    FilePath -> Maybe String -> SelfTestCase -> IO (String, Bool)
runSelfTestCase repoRoot legacyRef testCase =
    withSystemTempDirectory "s254r-case" $ \scratch -> do
        let derivedTree = scratch </> "derived"
        materialized <- materializeRef repoRoot "HEAD" derivedTree
        case materialized of
            Left reason -> pure (harness reason)
            Right () -> do
                mutated <- caseMutate testCase derivedTree
                case mutated of
                    Left reason -> pure (harness reason)
                    Right () -> do
                        verdict <- runScan (defaultScanConfig derivedTree)
                        let derived = newLabel testCase (verdictCode verdict)
                        case legacyRef of
                            Nothing ->
                                pure
                                    ( marker <> " new=" <> derived
                                    , derived == expectedNew testCase
                                    )
                            Just ref ->
                                runFrozenHalf scratch ref derived
  where
    marker = "S254R_DERIVED_SELFTEST case=" <> caseName testCase
    harness reason = (marker <> " harness=broken reason=" <> show reason, False)
    runFrozenHalf scratch ref derived = do
        let frozenTree = scratch </> "frozen"
        materialized <- materializeRef repoRoot ref frozenTree
        case materialized of
            Left reason -> pure (harness reason)
            Right () -> do
                mutated <- caseMutate testCase frozenTree
                case mutated of
                    Left reason -> pure (harness reason)
                    Right () -> do
                        (code, output) <- runLegacy scratch frozenTree
                        let frozen = oldLabel testCase code output
                        pure
                            ( marker
                                <> " old="
                                <> frozen
                                <> " new="
                                <> derived
                            , frozen == expectedOld testCase
                                && derived == expectedNew testCase
                            )

{- | Run one falsification leg against the candidate tree.

Legs prove the current control's configuration is load-bearing, so they
materialize HEAD rather than the frozen source-text sweep's tree.
Both halves are required: unperturbed the tree must scan clean, perturbed it
must report a broken instrument.
-}
runSelfTestLeg :: FilePath -> Maybe String -> SelfTestLeg -> IO (String, Bool)
runSelfTestLeg repoRoot _legacyRef leg =
    withSystemTempDirectory "s254r-leg" $ \scratch -> do
        let tree = scratch </> "tree"
        materialized <- materializeRef repoRoot "HEAD" tree
        case materialized of
            Left reason -> pure (harness reason)
            Right () -> do
                clean <- runScan (defaultScanConfig tree)
                perturbed <- legPerturb leg tree (defaultScanConfig tree)
                case perturbed of
                    Left reason -> pure (harness reason)
                    Right config -> do
                        broken <- runScan config
                        pure
                            ( report (verdictCode clean) (verdictCode broken)
                            , verdictCode clean == 0 && verdictCode broken == 2
                            )
  where
    marker = "S254R_DERIVED_LEG name=" <> legName leg
    report clean broken =
        marker <> " unperturbed=" <> show clean <> " perturbed=" <> show broken
    harness reason = (marker <> " harness=broken reason=" <> show reason, False)

-- | What the frozen control must do with a mutation.
expectedOld :: SelfTestCase -> String
expectedOld testCase
    | caseCatchable testCase = "MISS"
    | otherwise = "FALSE-POSITIVE"

-- | What the derived control must do with the same mutation.
expectedNew :: SelfTestCase -> String
expectedNew testCase
    | caseCatchable testCase = "CATCH"
    | otherwise = "IGNORE"

{- | What the frozen control did, with its own output required as evidence that
it ran at all.

Without the evidence check, a frozen control that died before reaching its
first surface would exit non-zero and be recorded as a faithful
@FALSE-POSITIVE@, and one whose external tools were missing from a strict PATH
could exit zero and be recorded as a faithful @MISS@.  Both would make the
demonstration pass for the wrong reason, so neither label is available without
the frozen control's own marker in its own output.
-}
oldLabel :: SelfTestCase -> Int -> String -> String
oldLabel testCase code output
    | not (caseEvidence testCase `isInfixOf` output) = "NO-EVIDENCE"
    | caseCatchable testCase = if code == 0 then "MISS" else "CAUGHT-" <> show code
    | otherwise = if code /= 0 then "FALSE-POSITIVE" else "QUIET"

-- | What the derived control did with the same mutation.
newLabel :: SelfTestCase -> Int -> String
newLabel testCase code
    | code == 2 = "BROKEN"
    | caseCatchable testCase = if code == 1 then "CATCH" else "MISS"
    | otherwise = if code == 0 then "IGNORE" else "FALSE-POSITIVE"

{- | Run the frozen source-text control this slice replaces, against a
materialized tree.

The working directory is deliberately left alone: the frozen script reads its
surfaces from @S254R_SWEEP_ROOT@ and this is exactly how the frozen gate
invokes it, so its verdicts here are the same already-frozen facts the gate
recorded and not behaviour this slice can influence.
-}
runLegacy :: FilePath -> FilePath -> IO (Int, String)
runLegacy scratch tree = do
    let record = scratch </> "legacy.log"
        script = tree </> "scripts/check-version-remnant-sweep.sh"
    code <- spawnCapture script [] [("S254R_SWEEP_ROOT", tree)] record
    present <- doesFileExist record
    output <- if present then readSource record else pure ""
    pure (code, output)

{- | Materialize a committed tree without touching any working copy.

@git archive@ writes to a file rather than a pipe so the whole materialization
is two ordinary spawns, and the result is proved non-empty by requiring the
frozen control's own script to be present before any probe runs on it.
-}
materializeRef :: FilePath -> String -> FilePath -> IO (Either String ())
materializeRef repoRoot ref target = do
    createDirectoryIfMissing True target
    let archive = target <> ".tar"
        record = target <> ".log"
    archived <-
        spawnCapture
            "git"
            ["-C", repoRoot, "archive", "--format=tar", "-o", archive, ref]
            []
            record
    if archived /= 0
        then pure (Left ("git archive " <> ref <> " exited " <> show archived))
        else do
            extracted <-
                spawnCapture "tar" ["-x", "-f", archive, "-C", target] [] record
            if extracted /= 0
                then pure (Left ("tar exited " <> show extracted))
                else do
                    present <-
                        doesFileExist
                            (target </> "scripts/check-version-remnant-sweep.sh")
                    pure $
                        if present
                            then Right ()
                            else Left (ref <> " materialized without a sweep script")

{- | Run a program with extra environment, capture its combined output, and
return its exit code.

An exec that fails exits 127 rather than falling through into the parent's
runtime, so a missing tool is a visible failure instead of a duplicated
process.
-}
spawnCapture :: FilePath -> [String] -> [(String, String)] -> FilePath -> IO Int
spawnCapture program arguments environment output = do
    child <- forkProcess $ do
        descriptor <- createFile output 0o644
        _ <- dupTo descriptor stdOutput
        _ <- dupTo descriptor stdError
        closeFd descriptor
        forM_ environment (uncurry setEnv)
        attempt <- try (executeFile program True arguments Nothing)
        case attempt of
            Left err -> hPutStrLn stderr (displayException (err :: SomeException))
            Right () -> pure ()
        exitImmediately (ExitFailure 127)
    status <- getProcessStatus True False child
    pure $ case status of
        Just (Exited ExitSuccess) -> 0
        Just (Exited (ExitFailure code)) -> code
        Just _ -> 128
        Nothing -> 129

{- | Apply one mutation and prove it materialized before any verdict is read.

The proof is a count of occurrences in the file as written back, not a claim
that the edit was attempted.  A mutation whose anchor has moved reports the
anchor as absent instead of silently doing nothing.
-}
mutateFile ::
    FilePath ->
    FilePath ->
    (String -> Maybe String) ->
    [(String, Int)] ->
    IO (Either String ())
mutateFile tree relative transform expectations = do
    let path = tree </> relative
    present <- doesFileExist path
    if not present
        then pure (Left (relative <> " is absent from the materialized tree"))
        else do
            source <- readSource path
            case transform source of
                Nothing ->
                    pure (Left ("the mutation anchor is absent from " <> relative))
                Just mutated -> do
                    writeSource path mutated
                    written <- readSource path
                    pure $ case [ name <> "=" <> show seen <> " want " <> show want
                                | (name, want) <- expectations
                                , let seen = countOccurrences name written
                                , seen /= want
                                ] of
                        [] -> Right ()
                        wrong -> Left (relative <> ": " <> show wrong)

-- | A second application of an applier on a line that already carries one.
mutateSameLineApplication :: FilePath -> IO (Either String ())
mutateSameLineApplication tree =
    mutateFile
        tree
        cageBuilderPath
        (replaceLineSuffix anchor (anchor <> " `seq` " <> call))
        [(call, 2)]
  where
    call = "applyParams cageVersion predecessorPolicy cageCode"
    anchor = "applied = " <> call

-- | A version-shaped identifier introduced inside an existing line.
mutateSameLineVersion :: FilePath -> IO (Either String ())
mutateSameLineVersion tree =
    mutateFile
        tree
        deploymentScriptPath
        (replaceWholeLine "v1CheckpointVersion = 0" replacement)
        [("v1InjectedVersionRemnant", 2)]
  where
    replacement =
        "v1CheckpointVersion = let v1InjectedVersionRemnant = 1 \
        \in v1InjectedVersionRemnant - 1"

-- | An application wearing a type annotation.
mutateAnnotatedApplication :: FilePath -> IO (Either String ())
mutateAnnotatedApplication tree =
    mutateFile
        tree
        cageBuilderPath
        (appendLines added)
        [("s254rAnnotatedApplication", 2), (annotated, 1)]
  where
    annotated =
        "(applyParams cageVersion predecessorPolicy cageCode \
        \:: SBS.ShortByteString)"
    added =
        [ ""
        , "s254rAnnotatedApplication :: SBS.ShortByteString -> SBS.ShortByteString"
        , "s254rAnnotatedApplication cageCode ="
        , "    " <> annotated
        ]

-- | A version-shaped word that exists only inside a comment.
mutateCommentOnly :: FilePath -> IO (Either String ())
mutateCommentOnly tree =
    mutateFile
        tree
        deploymentScriptPath
        ( replaceWholeLine
            "v1NetworkDiscriminator = 0"
            "v1NetworkDiscriminator = 0 -- v1CommentOnlyVersion"
        )
        [("v1CommentOnlyVersion", 1)]

-- | A version-shaped word that exists only inside a string literal.
mutateStringOnly :: FilePath -> IO (Either String ())
mutateStringOnly tree =
    mutateFile
        tree
        deploymentScriptPath
        (appendLines ["", "s254rStringOnly = \"v1StringOnlyVersion\""])
        [("v1StringOnlyVersion", 1)]

-- | Replace an exact line suffix wherever it ends a line.
replaceLineSuffix :: String -> String -> String -> Maybe String
replaceLineSuffix suffix replacement source
    | not (any (suffix `isSuffixOf`) sourceLines) = Nothing
    | otherwise = Just (unlines (map rewrite sourceLines))
  where
    sourceLines = lines source
    rewrite line
        | suffix `isSuffixOf` line =
            take (length line - length suffix) line <> replacement
        | otherwise = line

-- | Replace an exact whole line wherever it occurs.
replaceWholeLine :: String -> String -> String -> Maybe String
replaceWholeLine target replacement source
    | target `notElem` sourceLines = Nothing
    | otherwise = Just (unlines (map rewrite sourceLines))
  where
    sourceLines = lines source
    rewrite line
        | line == target = replacement
        | otherwise = line

-- | Append lines to a module.
appendLines :: [String] -> String -> Maybe String
appendLines added source = Just (unlines (lines source <> added))

-- | How many times one string occurs in another, overlaps included.
countOccurrences :: String -> String -> Int
countOccurrences needle haystack =
    length [() | candidate <- tails haystack, needle `isPrefixOf` candidate]

{- | Read a source file as text without depending on the process locale.

The control runs inside build sandboxes whose locale is @C@, where a
locale-sensitive read would throw on the first non-ASCII byte and a fail-closed
scan would report a broken instrument for an unrelated reason.
-}
readSource :: FilePath -> IO String
readSource path = T.unpack . TE.decodeUtf8 <$> BS.readFile path

-- | Write a source file as UTF-8, for the same reason.
writeSource :: FilePath -> String -> IO ()
writeSource path = BS.writeFile path . TE.encodeUtf8 . T.pack
