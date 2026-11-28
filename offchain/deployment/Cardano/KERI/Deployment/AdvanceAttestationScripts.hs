{- |
Module      : Cardano.KERI.Deployment.AdvanceAttestationScripts
Description : the applied programs of the two-policy advance

The derivation chain of the attested generation: the fact policy applied to the
version, the change policy applied to the version and the fact policy's hash, and
the checkpoint applied (as the deployed generation's, with the same registry,
application and terms) to the change policy's hash in place of the advance
observer's. The enforcement and entitlement observers are those of the deployed
generation.
-}
module Cardano.KERI.Deployment.AdvanceAttestationScripts (
    AdvanceAttestation (..),
    deriveAdvanceAttestation,
    deriveAttestedCheckpoint,
) where

import Cardano.KERI.Deployment.Script (
    Blueprint,
    CheckpointTerms (..),
    Observers (..),
    RegistryIdentity,
    ScriptArtifact (..),
    applyCheckpointParams,
    mkAppliedArtifact,
    requireValidator,
    scriptHashBytes,
    v1CheckpointVersion,
 )
import Data.ByteString (ByteString)
import PlutusCore.Data (Data (..))

-- | The two attestation policies, the second applied to the first.
data AdvanceAttestation = AdvanceAttestation
    { attestationFact :: !ScriptArtifact
    , attestationChange :: !ScriptArtifact
    }
    deriving stock (Eq, Show)

-- | The fact policy and the change policy of a blueprint.
deriveAdvanceAttestation :: Blueprint -> Either String AdvanceAttestation
deriveAdvanceAttestation blueprint = do
    (factValidator, factProgram) <-
        requireValidator
            blueprint
            "event_attestation.event_attestation.mint"
            "event-attestation"
    fact <-
        mkAppliedArtifact
            "event-attestation"
            "minting-policy"
            factValidator
            [I v1CheckpointVersion]
            factProgram
    (changeValidator, changeProgram) <-
        requireValidator
            blueprint
            "advance_attestation.advance_attestation.mint"
            "advance-attestation"
    change <-
        mkAppliedArtifact
            "advance-attestation"
            "minting-policy"
            changeValidator
            [I v1CheckpointVersion, B (scriptHashBytes (artifactScriptHash fact))]
            changeProgram
    pure (AdvanceAttestation fact change)

{- | The checkpoint validator applied to a registry, the policy of its application,
the change policy (in place of the advance observer), the enforcement and entitlement
observers of the deployed generation and the terms.
-}
deriveAttestedCheckpoint ::
    CheckpointTerms ->
    RegistryIdentity ->
    ByteString ->
    AdvanceAttestation ->
    Observers ->
    Blueprint ->
    Either String ScriptArtifact
deriveAttestedCheckpoint terms registry applicationPolicy attestation observers blueprint = do
    (validator, program) <-
        requireValidator
            blueprint
            "checkpoint_register.checkpoint_register.spend"
            "checkpoint-register"
    mkAppliedArtifact
        "checkpoint-register"
        "validator-and-minting-policy"
        validator
        ( applyCheckpointParams
            registry
            (scriptHashBytes (artifactScriptHash (attestationChange attestation)))
            (scriptHashBytes (artifactScriptHash (observerEnforcement observers)))
            (scriptHashBytes (artifactScriptHash (observerEntitlement observers)))
            (termsNetwork terms)
            (termsDeposit terms)
            (termsFreezeBond terms)
            (termsPremium terms)
            applicationPolicy
        )
        program
