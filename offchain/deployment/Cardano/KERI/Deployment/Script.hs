{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.Script
Description : Reproducible application of the M1 V1 Plutus scripts

This module is the single off-chain source of truth for applying the production
checkpoint parameters.  Both the E2E transaction builder and @ckeri@ consume
the resulting 'ScriptArtifact's.
-}
module Cardano.KERI.Deployment.Script (
    Blueprint (..),
    Validator (..),
    ScriptArtifact (..),
    loadBlueprint,
    extractCompiledCode,
    mkAppliedArtifact,
    applyParams,
    applyCheckpointParams,
    applyPredecessorParam,
    applyLifecycleParams,
    applyAdvanceParams,
    mkCageScript,
    computeScriptHash,
    cagePolicyId,
    cageScriptAddr,
    deriveBoardScript,
    deriveV1Scripts,
    boardAddress,
    checkpointAddress,
    scriptHashText,
    v1CheckpointVersion,
    v1NetworkDiscriminator,
    v1RegistrationBond,
    v1FreezeBond,
    v1FreezeWindow,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Alonzo.Scripts (fromPlutusScript, mkPlutusScript)
import Cardano.Ledger.BaseTypes (Network (Testnet))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (Script, hashScript)
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..))
import Cardano.Ledger.Mary.Value (PolicyID (..))
import Cardano.Ledger.Plutus.Language (
    Language (PlutusV3),
    Plutus (..),
    PlutusBinary (..),
 )
import Codec.Binary.Bech32 qualified as Bech32
import Data.Aeson (FromJSON (..), withObject, (.!=), (.:), (.:?))
import Data.Aeson qualified as Aeson
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Char (isDigit)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import PlutusCore qualified as PLC
import PlutusCore.Data (Data (..))
import PlutusLedgerApi.V3 (serialiseUPLC, uncheckedDeserialiseUPLC)
import UntypedPlutusCore (Program (..), applyProgram)
import UntypedPlutusCore qualified as UPLC

data Validator = Validator
    { vTitle :: Text
    , vHash :: Text
    , vCompiledCode :: Maybe Text
    , vParameters :: [Text]
    {- ^ the titles of the applied parameters this validator declares, in
    order.  The blueprint is the only place a declared arity comes from.
    -}
    }
    deriving stock (Show, Eq)

newtype Blueprint = Blueprint
    { validators :: [Validator]
    }
    deriving stock (Show, Eq)

data ScriptArtifact = ScriptArtifact
    { artifactName :: Text
    , artifactBlueprintTitle :: Text
    , artifactRole :: Text
    , artifactProgram :: SBS.ShortByteString
    , artifactScriptHash :: ScriptHash
    }
    deriving stock (Show, Eq)

instance FromJSON Validator where
    parseJSON = withObject "Validator" $ \o ->
        Validator
            <$> o .: "title"
            <*> o .: "hash"
            <*> o .:? "compiledCode"
            <*> (map parameterTitle <$> (o .:? "parameters" .!= []))

newtype Parameter = Parameter {parameterTitle :: Text}
    deriving stock (Show, Eq)

instance FromJSON Parameter where
    parseJSON = withObject "Parameter" $ \o ->
        Parameter <$> (o .:? "title" .!= "")

instance FromJSON Blueprint where
    parseJSON = withObject "Blueprint" $ \o -> Blueprint <$> o .: "validators"

loadBlueprint :: FilePath -> IO (Either String Blueprint)
loadBlueprint path = Aeson.eitherDecodeStrict' <$> BS.readFile path

extractCompiledCode :: Text -> Blueprint -> Maybe SBS.ShortByteString
extractCompiledCode prefix blueprint =
    snd <$> extractValidator prefix blueprint

extractValidator ::
    Text -> Blueprint -> Maybe (Validator, SBS.ShortByteString)
extractValidator prefix blueprint = do
    validator <-
        find (T.isPrefixOf prefix . vTitle) (validators blueprint)
    validatorProgram validator

extractValidatorExact ::
    Text -> Blueprint -> Maybe (Validator, SBS.ShortByteString)
extractValidatorExact title blueprint = do
    validator <-
        find ((== title) . vTitle) (validators blueprint)
    validatorProgram validator

validatorProgram :: Validator -> Maybe (Validator, SBS.ShortByteString)
validatorProgram validator = do
    hex <- vCompiledCode validator
    bytes <- decodeHex hex
    pure (validator, SBS.toShort bytes)

decodeHex :: Text -> Maybe BS.ByteString
decodeHex text
    | odd (T.length text) = Nothing
    | otherwise = BS.pack <$> go (T.unpack text)
  where
    go [] = Just []
    go (a : b : rest) = do
        high <- hexDigit a
        low <- hexDigit b
        (high * 16 + low :) <$> go rest
    go _ = Nothing

    hexDigit character
        | isDigit character =
            Just $ fromIntegral (fromEnum character - fromEnum '0')
        | character >= 'a' && character <= 'f' =
            Just $ fromIntegral (fromEnum character - fromEnum 'a' + 10)
        | character >= 'A' && character <= 'F' =
            Just $ fromIntegral (fromEnum character - fromEnum 'A' + 10)
        | otherwise = Nothing

applyParams :: Integer -> ByteString -> SBS.ShortByteString -> SBS.ShortByteString
applyParams version predecessorPolicy =
    applyDataArgs [I version, B predecessorPolicy]

{- | Build one published deployment artifact from a blueprint validator and the
exact argument plan applied to it.

Every V1 artifact is constructed here, so a caller cannot publish an
application this constructor has not accepted, and the plan a validator is
applied to is always visible beside the declaration it has to match.
-}
mkAppliedArtifact ::
    Text ->
    Text ->
    Validator ->
    [Data] ->
    SBS.ShortByteString ->
    Either String ScriptArtifact
mkAppliedArtifact name role validator plan program =
    let applied = applyDataArgs plan program
     in Right
            ScriptArtifact
                { artifactName = name
                , artifactBlueprintTitle = vTitle validator
                , artifactRole = role
                , artifactProgram = applied
                , artifactScriptHash = computeScriptHash applied
                }

{- | The one lineage input a #254 successor program takes: the single
predecessor minting policy it accepts.  Release identity is the resulting
hash, so no generation integer is applied.
-}
applyPredecessorParam :: ByteString -> [Data]
applyPredecessorParam predecessorPolicy =
    [B predecessorPolicy]

applyCheckpointParams ::
    Integer ->
    ByteString ->
    ByteString ->
    ByteString ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    [Data]
applyCheckpointParams version migrationHash lifecycleHash advanceHash enforcementHash network registrationBond freezeBond freezeWindow =
    [ I version
    , B migrationHash
    , B lifecycleHash
    , B advanceHash
    , B enforcementHash
    , I network
    , I registrationBond
    , I freezeBond
    , I freezeWindow
    ]

applyLifecycleParams :: Integer -> ByteString -> Integer -> [Data]
applyLifecycleParams version proofPolicy registrationBond =
    [I version, B proofPolicy, I registrationBond]

applyAdvanceParams :: Integer -> [Data]
applyAdvanceParams version =
    [I version]

applyDataArgs :: [Data] -> SBS.ShortByteString -> SBS.ShortByteString
applyDataArgs arguments code =
    serialiseUPLC $
        foldl applyDataArg (uncheckedDeserialiseUPLC code) arguments
  where
    applyDataArg program dat =
        let Program _ versionTag _ = program
            argument =
                Program
                    ()
                    versionTag
                    (UPLC.Constant () (PLC.Some (PLC.ValueOf PLC.DefaultUniData dat)))
         in either
                (error . ("applyDataArgs: " <>) . show)
                id
                (applyProgram program argument)

mkCageScript :: SBS.ShortByteString -> Script ConwayEra
mkCageScript bytes =
    case mkPlutusScript (Plutus @PlutusV3 (PlutusBinary bytes)) of
        Just script -> fromPlutusScript script
        Nothing -> error "mkCageScript: invalid PlutusV3 script"

computeScriptHash :: SBS.ShortByteString -> ScriptHash
computeScriptHash = hashScript @ConwayEra . mkCageScript

cagePolicyId :: SBS.ShortByteString -> PolicyID
cagePolicyId = PolicyID . computeScriptHash

cageScriptAddr :: SBS.ShortByteString -> Network -> Addr
cageScriptAddr bytes network =
    Addr network (ScriptHashObj (computeScriptHash bytes)) StakeRefNull

{- | The deployed M1 checkpoint family generation.  The @v1@ in the name refers
to the M1 manifest schema, not the family generation, and this value is
released history: it stays @0@ and is never relabelled as the #254 family.
-}
v1CheckpointVersion :: Integer
v1CheckpointVersion = 0

v1NetworkDiscriminator :: Integer
v1NetworkDiscriminator = 0

v1RegistrationBond :: Integer
v1RegistrationBond = 1_000_000_000

v1FreezeBond :: Integer
v1FreezeBond = 5_000_000

v1FreezeWindow :: Integer
v1FreezeWindow = 10_000

deriveV1Scripts :: Blueprint -> Either String [ScriptArtifact]
deriveV1Scripts blueprint = do
    (hashProofValidator, hashProofProgram) <-
        require "hash_proof.hash_proof.mint" "hash-proof"
    hashProof <-
        mkAppliedArtifact
            "hash-proof"
            "minting-policy"
            hashProofValidator
            []
            hashProofProgram
    let hashProofHash = artifactScriptHash hashProof
    (lifecycleValidator, lifecycleProgram) <-
        require
            "checkpoint_observer.observer_lifecycle.withdraw"
            "observer-lifecycle"
    lifecycle <-
        mkAppliedArtifact
            "observer-lifecycle"
            "withdrawal-observer"
            lifecycleValidator
            ( applyLifecycleParams
                v1CheckpointVersion
                (scriptHashBytes hashProofHash)
                v1RegistrationBond
            )
            lifecycleProgram
    let lifecycleHash = artifactScriptHash lifecycle
    (advanceValidator, advanceProgram) <-
        require
            "checkpoint_observer.observer_advance.withdraw"
            "observer-advance"
    advance <-
        mkAppliedArtifact
            "observer-advance"
            "withdrawal-observer"
            advanceValidator
            (applyAdvanceParams v1CheckpointVersion)
            advanceProgram
    let advanceHash = artifactScriptHash advance
    (enforcementValidator, enforcementProgram) <-
        require
            "checkpoint_observer.observer_enforcement.withdraw"
            "observer-enforcement"
    enforcement <-
        mkAppliedArtifact
            "observer-enforcement"
            "withdrawal-observer"
            enforcementValidator
            (applyAdvanceParams v1CheckpointVersion)
            enforcementProgram
    let enforcementHash = artifactScriptHash enforcement
    -- #254 A-001: the promoted migration observer, derived as a v1 family
    -- component and applied to the checkpoint program by hash.  Its
    -- predecessor pin is an applied parameter, never a redeemer field.
    (migrationValidator, migrationProgram) <-
        require
            "checkpoint_observer.observer_migration.withdraw"
            "observer-migration"
    -- The successor observer is applied with exactly one input: the single
    -- predecessor policy it accepts.  Its own hash is its release identity, so
    -- there is no generation integer to apply.
    migration <-
        mkAppliedArtifact
            "observer-migration"
            "withdrawal-observer"
            migrationValidator
            (applyPredecessorParam (scriptHashBytes hashProofHash))
            migrationProgram
    let migrationHash = artifactScriptHash migration
    (checkpointValidator, checkpointProgram) <-
        require
            "checkpoint_register.checkpoint_register.mint"
            "checkpoint-register"
    let appliedCheckpoint =
            mkAppliedArtifact
                "checkpoint-register"
                "validator-and-minting-policy"
                checkpointValidator
                ( applyCheckpointParams
                    v1CheckpointVersion
                    (scriptHashBytes migrationHash)
                    (scriptHashBytes lifecycleHash)
                    (scriptHashBytes advanceHash)
                    (scriptHashBytes enforcementHash)
                    v1NetworkDiscriminator
                    v1RegistrationBond
                    v1FreezeBond
                    v1FreezeWindow
                )
                checkpointProgram
    checkpoint <- appliedCheckpoint
    pure [hashProof, lifecycle, advance, enforcement, migration, checkpoint]
  where
    require title name =
        maybe
            (Left $ T.unpack name <> " compiled code not found in production blueprint")
            Right
            (extractValidatorExact title blueprint)

{- | Derive the parameter-free endpoint-board combined validator exactly.

The mint handler is the canonical blueprint entry because every handler of a
combined Aiken validator carries the same compiled program.
-}
deriveBoardScript :: Blueprint -> Either String ScriptArtifact
deriveBoardScript blueprint = do
    (validator, program) <-
        maybe
            (Left "endpoint-board compiled code not found in production blueprint")
            Right
            (extractValidatorExact "endpoint_board.endpoint_board.mint" blueprint)
    mkAppliedArtifact
        "endpoint-board"
        "validator-and-minting-policy"
        validator
        []
        program

scriptHashBytes :: ScriptHash -> ByteString
scriptHashBytes (ScriptHash hash) = hashToBytes hash

scriptHashText :: ScriptHash -> Text
scriptHashText =
    TE.decodeUtf8 . convertToBase Base16 . scriptHashBytes

checkpointAddress :: [ScriptArtifact] -> Either String Text
checkpointAddress artifacts = do
    checkpoint <-
        case filter ((== "checkpoint-register") . artifactName) artifacts of
            [match] -> Right match
            _ -> Left "checkpoint-register artifact not found uniquely"
    artifactAddress checkpoint

{- | Render the endpoint-board enterprise address on preprod/testnet.

The script is parameter-free, so this address and its policy ID are a single
reproducible contract seam.
-}
boardAddress :: ScriptArtifact -> Either String Text
boardAddress artifact
    | artifactName artifact == "endpoint-board" = artifactAddress artifact
    | otherwise = Left "endpoint-board artifact required"

artifactAddress :: ScriptArtifact -> Either String Text
artifactAddress artifact = do
    let address =
            Addr
                Testnet
                (ScriptHashObj (artifactScriptHash artifact))
                StakeRefNull
    hrp <-
        either
            (Left . show)
            Right
            (Bech32.humanReadablePartFromText "addr_test")
    pure $
        Bech32.encodeLenient
            hrp
            (Bech32.dataPartFromBytes (serialiseAddr address))
