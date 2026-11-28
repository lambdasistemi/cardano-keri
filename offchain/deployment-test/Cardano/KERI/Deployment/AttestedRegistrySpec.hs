{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.AttestedRegistrySpec
Description : the registry of the attested generation, derived beside the deployed generation's

The attested generation's registry is the deployed generation's with another
checkpoint validator, and the two policies that mint the change attestation the
checkpoint requires. These examples derive both from their own blueprints
(@KERI_CHECKPOINT_BLUEPRINT@, the deployed generation's, and
@KERI_ATTESTED_BLUEPRINT@, the current source build) over the same terms and seed,
and pin what the attested generation's identities are: the policy identifiers and
the applied program sizes.
-}
module Cardano.KERI.Deployment.AttestedRegistrySpec (spec) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    OutputReference (..),
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.Deployment.AdvanceAttestationScripts (
    AdvanceAttestation (..),
    deriveAdvanceAttestation,
    deriveAttestedCheckpoint,
 )
import Cardano.KERI.Deployment.Registry (
    AttestedRegistry (..),
    RegistryScripts (..),
    RegistryTerms (..),
    deriveAttestedRegistryScripts,
    deriveRegistryScripts,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint,
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    loadBlueprint,
    scriptHashBytes,
    scriptHashText,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (isLeft)
import Data.Text (Text)
import System.Environment (getEnv)
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

terms :: RegistryTerms
terms =
    RegistryTerms
        { registryCheckpointTerms =
            CheckpointTerms
                { termsNetwork = 0
                , termsDeposit = 1_000_000_000
                , termsFreezeBond = 5_000_000
                , termsPremium = 2_000_000
                }
        , registryParameters =
            ApplicationParameters
                { registrationCost = 2
                , minimumTip = 1
                , processTime = 5
                , bookingWidth = 1
                }
        , registryMinimumAda = 2_000_000
        , registryTerminationCarrier = 1_000_000
        }

seed :: Word -> OutputReference
seed n = OutputReference (BS.replicate 32 0x77) (fromIntegral n)

blueprints :: IO (Blueprint, Blueprint)
blueprints = do
    deployed <- getEnv "KERI_CHECKPOINT_BLUEPRINT" >>= loadBlueprint >>= either fail pure
    attested <- getEnv "KERI_ATTESTED_BLUEPRINT" >>= loadBlueprint >>= either fail pure
    pure (deployed, attested)

derive :: Word -> IO (RegistryScripts, AttestedRegistry)
derive n = do
    (deployed, attested) <- blueprints
    old <- either fail pure (deriveRegistryScripts stateTemplate terms (seed n) deployed)
    new <- either fail pure (deriveAttestedRegistryScripts stateTemplate terms (seed n) attested)
    pure (old, new)

hashOf :: ScriptArtifact -> Text
hashOf = scriptHashText . artifactScriptHash

size :: ScriptArtifact -> Int
size = SBS.length . artifactProgram

spec :: Spec
spec = describe "the registry of the attested generation" $ do
    it "is the deployed generation's registry with another checkpoint validator" $ do
        (old, new) <- derive 0
        let scripts = attestedScripts new
        -- every observer but the advance observer, which the attested generation no longer deploys
        (\o -> o{observerAdvance = observerAdvance (scriptsObservers old)}) (scriptsObservers scripts) `shouldBe` scriptsObservers old
        scriptsAttestation scripts `shouldBe` scriptsAttestation old
        scriptsApplication scripts `shouldBe` scriptsApplication old
        scriptsTemplate scripts `shouldBe` scriptsTemplate old
        scriptsStateProgram scripts `shouldBe` scriptsStateProgram old
        scriptsStateHash scripts `shouldBe` scriptsStateHash old
        scriptsSeed scripts `shouldBe` scriptsSeed old
        scriptsRegistry scripts `shouldBe` scriptsRegistry old
        scriptsCheckpoint scripts `shouldNotBe` scriptsCheckpoint old
        hashOf (scriptsCheckpoint scripts) `shouldNotBe` hashOf (scriptsCheckpoint old)
    it "derives its checkpoint and its two policies by the derivations of the policies" $ do
        (_, attested) <- blueprints
        (_, new) <- derive 0
        policies <- either fail pure (deriveAdvanceAttestation attested)
        attestedPolicies new `shouldBe` policies
        checkpoint <-
            either
                fail
                pure
                ( deriveAttestedCheckpoint
                    (registryCheckpointTerms terms)
                    (scriptsRegistry (attestedScripts new))
                    (scriptHashBytes (artifactScriptHash (scriptsApplication (attestedScripts new))))
                    policies
                    (scriptsObservers (attestedScripts new))
                    attested
                )
        scriptsCheckpoint (attestedScripts new) `shouldBe` checkpoint
    it "depends on the seed in its checkpoint validator only, as the deployed generation does" $ do
        (_, a) <- derive 0
        (_, b) <- derive 1
        attestedPolicies a `shouldBe` attestedPolicies b
        scriptsApplication (attestedScripts a) `shouldBe` scriptsApplication (attestedScripts b)
        scriptsStateHash (attestedScripts a) `shouldBe` scriptsStateHash (attestedScripts b)
        hashOf (scriptsCheckpoint (attestedScripts a)) `shouldNotBe` hashOf (scriptsCheckpoint (attestedScripts b))
    it "is refused over the blueprint of the deployed generation, which carries no change policy" $ do
        (deployed, _) <- blueprints
        deriveAttestedRegistryScripts stateTemplate terms (seed 0) deployed `shouldSatisfy` isLeft
    it "has the policy identifiers and applied program sizes recorded for it" $ do
        (old, new) <- derive 0
        let policies = attestedPolicies new
            scripts = attestedScripts new
        -- the two policies depend on the version and on each other only: the identifiers do not move with the registry
        (hashOf (attestationFact policies), hashOf (attestationChange policies))
            `shouldBe` ("8820ee6877973be5ee1be2de32af53bdea3fb4afd253965678ecdf29", "c51fb1d0b78e838a68d65b1e1c5ad852e0996b92ec23498b7af1c38a")
        (size (attestationFact policies), size (attestationChange policies), size (scriptsCheckpoint scripts))
            `shouldBe` (10_661, 12_903, 8_911)
        size (scriptsCheckpoint old) `shouldBe` 8_957
        hashOf (scriptsCheckpoint scripts) `shouldBe` "b4d42977c768e4c1678c6bbce128a956e19c63eb376bf8def3e64bec"
        hashOf (scriptsApplication scripts) `shouldBe` "ef613f113b7d89aaa0fc62b172f1c5569d7bd3d38bf735a36403a941"
        -- the deployed generation's checkpoint over the same terms and seed, for the record: it is not the attested one
        hashOf (scriptsCheckpoint old) `shouldBe` "738dc75d29890a795d427e08bbedd1e166bd98b5f39e5d01c5fc70fe"
