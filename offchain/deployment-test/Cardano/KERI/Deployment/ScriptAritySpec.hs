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
) where

import Cardano.KERI.Deployment.Manifest (
    Reference (..),
    mkManifest,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint (..),
    ScriptArtifact (..),
    Validator (..),
    deriveBoardScript,
    deriveV1Scripts,
    loadBlueprint,
    mkAppliedArtifact,
    scriptHashText,
    v1CheckpointVersion,
    v1FreezeBond,
    v1FreezeWindow,
    v1NetworkDiscriminator,
    v1RegistrationBond,
 )
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.List (nub, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import PlutusCore qualified as PLC
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.V3 (serialiseUPLC, uncheckedDeserialiseUPLC)
import System.Environment (getEnv)
import System.IO (hClose)
import System.IO.Temp (withSystemTempFile)
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
    declared <- either fail pure (declaredParameters value)
    programs <- either fail pure (compiledPrograms value)
    blueprint <- loadBlueprint path >>= either fail pure
    artifacts <- either fail pure (deriveV1Scripts blueprint)
    board <- either fail pure (deriveBoardScript blueprint)
    pure
        Fixture
            { fixtureValue = value
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
spec = beforeAll withFixture $
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
            -- The exact eight-argument list, in order, built from the sibling
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

registerArguments :: Fixture -> IO [Data]
registerArguments fixture = do
    raw <- programOf fixture registerTitle
    artifact <-
        maybe
            (fail "the register artifact was not published")
            pure
            ( lookup
                registerTitle
                [ (artifactBlueprintTitle candidate, candidate)
                | candidate <- fixtureArtifacts fixture
                ]
            )
    either fail pure (appliedArguments raw (artifactProgram artifact))

{- | What the corrected register must be applied to: the four sibling policy
hashes this same derivation produced, then the four deployment integers.  No
element of this list is written down twice.
-}
expectedRegisterArguments :: Fixture -> IO [Data]
expectedRegisterArguments fixture = do
    migration <- policyOf "observer-migration"
    lifecycle <- policyOf "observer-lifecycle"
    advance <- policyOf "observer-advance"
    enforcement <- policyOf "observer-enforcement"
    pure
        [ B migration
        , B lifecycle
        , B advance
        , B enforcement
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
    concatMap versionShapedKeys (toList items)
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
