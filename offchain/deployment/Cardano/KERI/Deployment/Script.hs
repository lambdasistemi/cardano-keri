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
    extractCompiledCodeExact,
    mkAppliedArtifact,
    validatorParameterCount,
    applyParams,
    applyCheckpointParams,
    applyPredecessorParam,
    applyLifecycleParams,
    applyAdvanceParams,
    applyCommitmentParams,
    applyDataArgs,
    applyEnforcementParams,
    applyCheckpointFamilyParams,
    v1CommitmentParameters,
    v1CommitmentLifetime,
    v1CommitDeposit,
    deriveCommitmentFamily,
    mkCageScript,
    computeScriptHash,
    cagePolicyId,
    cageScriptAddr,
    deriveBoardScript,
    deriveBoardTargetScript,
    deriveV1Scripts,
    boardAddress,
    checkpointAddress,
    scriptHashBytes,
    scriptHashText,
    v1CheckpointVersion,
    v1NetworkDiscriminator,
    v1RegistrationBond,
    v1FreezeBond,
    v1FreezeWindow,
) where

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    CommitmentFamily (..),
    CommitmentParameters (..),
    commitMinAge,
 )
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
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
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

{- | The compiled program of one exactly-named blueprint validator.  Unlike
'extractCompiledCode' this refuses a prefix match, so a proof about one
handler can never read another's bytes.
-}
extractCompiledCodeExact :: Text -> Blueprint -> Maybe SBS.ShortByteString
extractCompiledCodeExact title blueprint =
    snd <$> extractValidatorExact title blueprint

{- | How many arguments a named compiled validator still expects.

#254 S254-E asserts these counts as deployment facts: the split checkpoint
takes a seventh @CommitmentFamily@ argument and the enforcement observer takes
a second, so an implementation that quietly dropped either would change this
number and be caught here rather than at settlement time.  The count is the
length of the blueprint parameter list — the only source of declared arity.
-}
validatorParameterCount :: Text -> Blueprint -> Maybe Int
validatorParameterCount title blueprint =
    length . vParameters
        <$> find ((== title) . vTitle) (validators blueprint)

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

The two counts are structural and neither is written down: the declared count
is the length of the parameter list the blueprint carries for this validator,
and the applied count is the length of the argument list actually applied.  A
mismatch fails closed, before any program, hash, address or manifest entry
exists to be published — #254 A-007 derived a register hash, policy id and
address from a nine-argument application of an eight-parameter program, and
those identities could not have settled a transaction.
-}
mkAppliedArtifact ::
    Text ->
    Text ->
    Validator ->
    [Data] ->
    SBS.ShortByteString ->
    Either String ScriptArtifact
mkAppliedArtifact name role validator plan program
    | declared /= supplied =
        Left $
            T.unpack (vTitle validator)
                <> " declares "
                <> show declared
                <> " applied parameters but the deployment supplies "
                <> show supplied
                <> "; no artifact is derived from an arity mismatch"
    | otherwise =
        let applied = applyDataArgs plan program
         in Right
                ScriptArtifact
                    { artifactName = name
                    , artifactBlueprintTitle = vTitle validator
                    , artifactRole = role
                    , artifactProgram = applied
                    , artifactScriptHash = computeScriptHash applied
                    }
  where
    declared = length (vParameters validator)
    supplied = length plan

{- | The one lineage input a #254 successor program takes: the single
predecessor minting policy it accepts.  Release identity is the resulting
hash, so no generation integer is applied.
-}
applyPredecessorParam :: ByteString -> [Data]
applyPredecessorParam predecessorPolicy =
    [B predecessorPolicy]

{- | The exact argument plan the combined register is applied to.

There is no version argument.  @checkpoint_register@ declares no version
parameter, so the integer this plan used to lead with occupied the slot the
ledger fills with the script context (#254 A-007).  After A-002 the plan is
nine arguments: the five sibling observer hashes (migration, lifecycle,
advance, enforcement, entitlement) then the four deployment integers.  The
constructor still fails closed on declared-vs-supplied arity.
-}
applyCheckpointParams ::
    ByteString ->
    ByteString ->
    ByteString ->
    ByteString ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    [Data]
applyCheckpointParams migrationHash lifecycleHash advanceHash enforcementHash entitlementHash network registrationBond freezeBond freezeWindow =
    [ B migrationHash
    , B lifecycleHash
    , B advanceHash
    , B enforcementHash
    , B entitlementHash
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

{- | Apply the single argument of the #271 commitment program: its explicit
release magnitudes.  The program learns its own policy from the ledger
context, so there is no self-hash to apply and no circularity to resolve.
-}
applyCommitmentParams ::
    CommitmentParameters ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCommitmentParams parameters =
    applyDataArgs [asData parameters]

{- | #254 S254-E: the enforcement observer now takes TWO applied arguments.

The second is the deployed commitment family it reconciles entitlement
against.  Applying it is not decoration: the observer's own program hash — and
therefore the applied checkpoint register that pins that hash — changes with
the commitment policy, so a release cannot silently point its entitlement rule
at a different reservation program.
-}
applyEnforcementParams ::
    Integer ->
    CommitmentFamily ->
    [Data]
applyEnforcementParams version family =
    [I version, asData family]

{- | #254 S254-E: the split checkpoint validator's SEVENTH applied argument.

The split family is not part of the M1 deployment derived by
'deriveV1Scripts' — the combined register is — but the argument is real and
its arity is observable in the compiled blueprint, which is what the
@bounty-entitlement-blaster@ M8 control applies and asserts.
-}
applyCheckpointFamilyParams ::
    Integer ->
    ByteString ->
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    CommitmentFamily ->
    SBS.ShortByteString ->
    SBS.ShortByteString
applyCheckpointFamilyParams version hashProofPolicy network registrationBond freezeBond freezeWindow family =
    applyDataArgs
        [ I version
        , B hashProofPolicy
        , I network
        , I registrationBond
        , I freezeBond
        , I freezeWindow
        , asData family
        ]

-- | Strip the 'BuiltinData' wrapper from a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

{- | Apply a list of Plutus 'Data' arguments to a compiled program.

This is the single UPLC application primitive.  Named production
appliers call it directly.
-}
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

{- | #254 S254-E: the release's explicit commitment lifetime, in slots.

There is no protocol default for this magnitude and the component publishes
none — a reservation's lifetime is a deployment choice, so it is named here,
once, as an applied argument.  Two hours of preprod slots is long enough for a
hunter to open, mature, gather evidence and reveal, and short enough that a
grinder's concurrent capital is tied up rather than parked indefinitely.
-}
v1CommitmentLifetime :: Integer
v1CommitmentLifetime = 7_200

{- | #254 S254-E: the release's applied commitment deposit, in lovelace.

Held at the component's demonstrated floor.  Be exact about what it buys: it
raises the concurrent capital an open-many\/reveal-one grinder must lock, and
it does not defeat that grind — the grinder may self-sweep its own expired
losers and recycle the deposit.
-}
v1CommitDeposit :: Integer
v1CommitDeposit = 5_000_000

{- | The release's applied commitment magnitudes.  Every value is explicit;
nothing here is read from an ambient manifest.
-}
v1CommitmentParameters :: CommitmentParameters
v1CommitmentParameters =
    CommitmentParameters
        { cpNetwork = v1NetworkDiscriminator
        , cpCommitMinAge = commitMinAge
        , cpCommitmentLifetime = v1CommitmentLifetime
        , cpCommitDeposit = v1CommitDeposit
        }

{- | Derive the deployed commitment family from the production blueprint.

The policy is the hash of the commitment program applied to
'v1CommitmentParameters' — read from the compiled blueprint, never asserted —
so the family the enforcement observer is applied to is the family that
actually exists.
-}
deriveCommitmentFamily :: Blueprint -> Either String CommitmentFamily
deriveCommitmentFamily blueprint = do
    (_, program) <-
        maybe
            (Left "bounty-commitment compiled code not found in production blueprint")
            Right
            (extractValidatorExact "bounty_commitment.bounty_commitment.spend" blueprint)
    let applied = applyCommitmentParams v1CommitmentParameters program
    pure
        CommitmentFamily
            { cfPolicy = scriptHashBytes (computeScriptHash applied)
            , cfParameters = v1CommitmentParameters
            }

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
    (entitlementValidator, entitlementProgram) <-
        require
            "checkpoint_observer.observer_entitlement.withdraw"
            "observer-entitlement"
    -- #254 S254-E / A-002: both split observers take the same two applied
    -- arguments and go through the S254-R constructor, each as its own
    -- published artifact.  The application-site census follows this shape;
    -- it is not a number to preserve.
    commitmentFamily <- deriveCommitmentFamily blueprint
    let familyPlan =
            applyEnforcementParams v1CheckpointVersion commitmentFamily
    enforcement <-
        mkAppliedArtifact
            "observer-enforcement"
            "withdrawal-observer"
            enforcementValidator
            familyPlan
            enforcementProgram
    entitlement <-
        mkAppliedArtifact
            "observer-entitlement"
            "withdrawal-observer"
            entitlementValidator
            familyPlan
            entitlementProgram
    let enforcementHash = artifactScriptHash enforcement
        entitlementHash = artifactScriptHash entitlement
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
                    (scriptHashBytes migrationHash)
                    (scriptHashBytes lifecycleHash)
                    (scriptHashBytes advanceHash)
                    (scriptHashBytes enforcementHash)
                    (scriptHashBytes entitlementHash)
                    v1NetworkDiscriminator
                    v1RegistrationBond
                    v1FreezeBond
                    v1FreezeWindow
                )
                checkpointProgram
    checkpoint <- appliedCheckpoint
    pure
        [ hashProof
        , lifecycle
        , advance
        , enforcement
        , entitlement
        , migration
        , checkpoint
        ]
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

{- | Derive the authorized endpoint-board target applied to its one accepted
predecessor policy.

This is deliberately separate from 'deriveBoardScript': that function
reproduces the frozen zero-parameter v0 artifact, while this function derives
the successor whose release identity includes its lineage pin.
-}
deriveBoardTargetScript :: ByteString -> Blueprint -> Either String ScriptArtifact
deriveBoardTargetScript acceptedPredecessorPolicy blueprint = do
    (validator, program) <-
        maybe
            (Left "endpoint-board target compiled code not found in production blueprint")
            Right
            (extractValidatorExact "endpoint_board.endpoint_board.mint" blueprint)
    mkAppliedArtifact
        "endpoint-board"
        "validator-and-minting-policy"
        validator
        (applyPredecessorParam acceptedPredecessorPolicy)
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
