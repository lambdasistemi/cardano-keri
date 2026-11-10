{- |
Module      : Cardano.KERI.Deployment.Registry
Description : The scripts of one registry, derived from one set of terms

A registry's scripts depend on each other: the application is applied to the
registration observer and to the amounts of the deposit, the state script to
the application, the checkpoint validator to the state script, the registry's
name and the same amounts. This module derives all of them from one
'RegistryTerms' and one seed, in that order, so the amounts the checkpoint
validator and the application each carry cannot disagree: no entry point takes
them separately.
-}
module Cardano.KERI.Deployment.Registry (
    RegistryTerms (..),
    RegistryScripts (..),
    registryMinimumDeposit,
    registryInitialFloor,
    deriveRegistryScripts,
) where

import Cardano.Crypto.Hash.Blake2b (Blake2b_256)
import Cardano.Crypto.Hash.Class (digest)
import Cardano.KERI.AID.Application (
    ApplicationParameters,
    OutputReference,
    RegistryIdentity (..),
    statePolicy,
    stateProgram,
    stateTokenName,
 )
import Cardano.KERI.AID.Checkpoint.FreezeBond (freezeBondValid)
import Cardano.KERI.AID.Checkpoint.Registration (validRegistrationDeposit)
import Cardano.KERI.AID.Checkpoint.Value (checkpointMinAda)
import Cardano.KERI.Deployment.Script (
    Blueprint,
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    computeScriptHash,
    deriveCheckpointScript,
    deriveObserverScripts,
    mkAppliedArtifact,
    requireValidator,
    scriptHashBytes,
 )
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString.Short qualified as SBS
import Data.Proxy (Proxy (..))
import PlutusCore.Data (Data (..))

{- | Everything a registry's deployment is parameterised by. The checkpoint
terms feed the registration observer, the checkpoint validator and the
application; the request parameters feed the application and its
configuration record. The minimum ADA of a checkpoint output is not a field:
the checkpoint validator holds it as a constant, so the application's floors
add the library's one value of it ('checkpointMinAda').
-}
data RegistryTerms = RegistryTerms
    { registryCheckpointTerms :: !CheckpointTerms
    , registryParameters :: !ApplicationParameters
    }
    deriving stock (Eq, Show)

-- | The scripts of one registry and the facts they are derived from.
data RegistryScripts = RegistryScripts
    { scriptsObservers :: !Observers
    , scriptsApplication :: !ScriptArtifact
    , scriptsTemplate :: !ByteString
    -- ^ the state script up to its parameter, published at genesis
    , scriptsStateProgram :: !SBS.ShortByteString
    , scriptsStateHash :: !ByteString
    , scriptsSeed :: !OutputReference
    , scriptsRegistry :: !RegistryIdentity
    , scriptsCheckpoint :: !ScriptArtifact
    }
    deriving stock (Eq, Show)

{- | The least deposit a booking commits: the minimum ADA of a checkpoint output,
the checkpoint deposit and the freeze bond.
-}
registryMinimumDeposit :: RegistryTerms -> Integer
registryMinimumDeposit terms =
    checkpointMinAda
        + termsDeposit (registryCheckpointTerms terms)
        + termsFreezeBond (registryCheckpointTerms terms)

{- | What a fold's holding must hold: the least deposit and one premium, the
checkpoint's own floor.
-}
registryInitialFloor :: RegistryTerms -> Integer
registryInitialFloor terms =
    registryMinimumDeposit terms
        + termsPremium (registryCheckpointTerms terms)

{- | Derive the scripts of the registry created by spending @seed@, from the
state template, the terms and the blueprint.

Terms the checkpoint validator or the registration observer would refuse for
every transaction are refused here: a deposit or a freeze bond below its
floor makes every arm fail, so a fold the application accepts would lock its
deposit.
-}
deriveRegistryScripts ::
    ByteString ->
    RegistryTerms ->
    OutputReference ->
    Blueprint ->
    Either String RegistryScripts
deriveRegistryScripts template terms seed blueprint = do
    let checkpointTerms = registryCheckpointTerms terms
    unless (validRegistrationDeposit (termsDeposit checkpointTerms)) $
        Left "the registration deposit is below its floor: the observer refuses every registration"
    unless (freezeBondValid (termsFreezeBond checkpointTerms)) $
        Left "the freeze bond is below its floor: the checkpoint validator refuses every spend"
    observers <- deriveObserverScripts checkpointTerms blueprint
    (applicationValidator, applicationProgram) <-
        requireValidator
            blueprint
            "keri_application.keri_application.mint"
            "keri-application"
    application <-
        mkAppliedArtifact
            "keri-application"
            "validator-and-minting-policy"
            applicationValidator
            [ B (digest (Proxy @Blake2b_256) template)
            , B (scriptHashBytes (artifactScriptHash (observerLifecycle observers)))
            , I (registryMinimumDeposit terms)
            , I (registryInitialFloor terms)
            , I (termsNetwork checkpointTerms)
            ]
            applicationProgram
    let applicationPolicy = scriptHashBytes (artifactScriptHash application)
        program = SBS.toShort (stateProgram template applicationPolicy)
        stateHash = scriptHashBytes (computeScriptHash program)
        registry =
            RegistryIdentity
                { registryStatePolicy = stateHash
                , registryName = stateTokenName seed
                }
    if stateHash == statePolicy template applicationPolicy
        then pure ()
        else Left "the state script's hash is not the state policy of the application"
    checkpoint <- deriveCheckpointScript checkpointTerms registry observers blueprint
    pure
        RegistryScripts
            { scriptsObservers = observers
            , scriptsApplication = application
            , scriptsTemplate = template
            , scriptsStateProgram = program
            , scriptsStateHash = stateHash
            , scriptsSeed = seed
            , scriptsRegistry = registry
            , scriptsCheckpoint = checkpoint
            }
