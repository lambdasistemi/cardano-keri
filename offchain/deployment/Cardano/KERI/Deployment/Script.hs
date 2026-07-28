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
    applyParams,
    applyCheckpointParams,
    applyLifecycleParams,
    applyAdvanceParams,
    mkCageScript,
    computeScriptHash,
    cagePolicyId,
    cageScriptAddr,
    deriveV1Scripts,
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
import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
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

instance FromJSON Blueprint where
    parseJSON = withObject "Blueprint" $ \o -> Blueprint <$> o .: "validators"

loadBlueprint :: FilePath -> IO (Either String Blueprint)
loadBlueprint path = Aeson.eitherDecodeStrict' <$> BS.readFile path

extractCompiledCode :: Text -> Blueprint -> Maybe SBS.ShortByteString
extractCompiledCode prefix blueprint =
    snd <$> extractValidator prefix blueprint

extractValidator :: Text -> Blueprint -> Maybe (Text, SBS.ShortByteString)
extractValidator prefix blueprint = do
    validator <-
        find (T.isPrefixOf prefix . vTitle) (validators blueprint)
    validatorProgram validator

extractValidatorExact :: Text -> Blueprint -> Maybe (Text, SBS.ShortByteString)
extractValidatorExact title blueprint = do
    validator <-
        find ((== title) . vTitle) (validators blueprint)
    validatorProgram validator

validatorProgram :: Validator -> Maybe (Text, SBS.ShortByteString)
validatorProgram validator = do
    hex <- vCompiledCode validator
    bytes <- decodeHex hex
    pure (vTitle validator, SBS.toShort bytes)

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

applyCheckpointParams ::
    Integer ->
    ByteString ->
    ByteString ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCheckpointParams version lifecycleHash advanceHash enforcementHash network registrationBond freezeBond freezeWindow =
    applyDataArgs
        [ I version
        , B lifecycleHash
        , B advanceHash
        , B enforcementHash
        , I network
        , I registrationBond
        , I freezeBond
        , I freezeWindow
        ]

applyLifecycleParams ::
    Integer ->
    ByteString ->
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyLifecycleParams version proofPolicy registrationBond =
    applyDataArgs [I version, B proofPolicy, I registrationBond]

applyAdvanceParams ::
    Integer ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyAdvanceParams version =
    applyDataArgs [I version]

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
    (hashProofTitle, hashProofProgram) <-
        require "hash_proof.hash_proof.mint" "hash-proof"
    let hashProofHash = computeScriptHash hashProofProgram
        hashProof =
            artifact
                "hash-proof"
                hashProofTitle
                "minting-policy"
                hashProofProgram
    (lifecycleTitle, lifecycleProgram) <-
        require
            "checkpoint_observer.observer_lifecycle.withdraw"
            "observer-lifecycle"
    let appliedLifecycle =
            applyLifecycleParams
                v1CheckpointVersion
                (scriptHashBytes hashProofHash)
                v1RegistrationBond
                lifecycleProgram
        lifecycleHash = computeScriptHash appliedLifecycle
        lifecycle =
            artifact
                "observer-lifecycle"
                lifecycleTitle
                "withdrawal-observer"
                appliedLifecycle
    (advanceTitle, advanceProgram) <-
        require
            "checkpoint_observer.observer_advance.withdraw"
            "observer-advance"
    let appliedAdvance =
            applyAdvanceParams v1CheckpointVersion advanceProgram
        advanceHash = computeScriptHash appliedAdvance
        advance =
            artifact
                "observer-advance"
                advanceTitle
                "withdrawal-observer"
                appliedAdvance
    (enforcementTitle, enforcementProgram) <-
        require
            "checkpoint_observer.observer_enforcement.withdraw"
            "observer-enforcement"
    let appliedEnforcement =
            applyAdvanceParams v1CheckpointVersion enforcementProgram
        enforcementHash = computeScriptHash appliedEnforcement
        enforcement =
            artifact
                "observer-enforcement"
                enforcementTitle
                "withdrawal-observer"
                appliedEnforcement
    (checkpointTitle, checkpointProgram) <-
        require
            "checkpoint_register.checkpoint_register.mint"
            "checkpoint-register"
    let appliedCheckpoint =
            applyCheckpointParams
                v1CheckpointVersion
                (scriptHashBytes lifecycleHash)
                (scriptHashBytes advanceHash)
                (scriptHashBytes enforcementHash)
                v1NetworkDiscriminator
                v1RegistrationBond
                v1FreezeBond
                v1FreezeWindow
                checkpointProgram
        checkpoint =
            artifact
                "checkpoint-register"
                checkpointTitle
                "validator-and-minting-policy"
                appliedCheckpoint
    pure [hashProof, lifecycle, advance, enforcement, checkpoint]
  where
    require title name =
        maybe
            (Left $ T.unpack name <> " compiled code not found in production blueprint")
            Right
            (extractValidatorExact title blueprint)
    artifact name title role program =
        ScriptArtifact
            { artifactName = name
            , artifactBlueprintTitle = title
            , artifactRole = role
            , artifactProgram = program
            , artifactScriptHash = computeScriptHash program
            }

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
    let address =
            Addr
                Testnet
                (ScriptHashObj (artifactScriptHash checkpoint))
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
