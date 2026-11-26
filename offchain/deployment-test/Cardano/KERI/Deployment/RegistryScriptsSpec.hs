{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryScriptsSpec
Description : one set of terms feeds the checkpoint validator and the application

The checkpoint validator and the application each carry the deposit, the
freeze bond, the premium and the network. Nothing on chain binds the two, so
the derivation takes them once. The expected applications below spell the
numbers out from the Aiken connected scenario (a deposit of 1,000,000,000, a
freeze bond of 5,000,000, a premium of 2,000,000, 2,000,000 of minimum ADA) and
apply the compiled programs from them directly.
-}
module Cardano.KERI.Deployment.RegistryScriptsSpec (spec) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    OutputReference (..),
    RegistryIdentity (..),
    statePolicy,
 )
import Cardano.KERI.AID.Application.StateTemplate (stateTemplate)
import Cardano.KERI.AID.Checkpoint.Datum (blake2b_256)
import Cardano.KERI.Deployment.Registry (
    RegistryScripts (..),
    RegistryTerms (..),
    deriveRegistryScripts,
    registryInitialFloor,
    registryMinimumDeposit,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint (..),
    CheckpointTerms (..),
    Observers (..),
    ScriptArtifact (..),
    Validator (..),
    applyCheckpointParams,
    applyDataArgs,
    deriveV1Scripts,
    loadBlueprint,
    observerArtifacts,
    requireValidator,
    scriptHashBytes,
 )
import Cardano.KERI.Deployment.Script qualified as Script
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Either (fromLeft)
import Data.Text (Text)
import Data.Text qualified as T
import PlutusCore.Data (Data (..))
import System.Environment (getEnv)
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

-- | The numbers of the Aiken connected scenario.
connectedTerms :: RegistryTerms
connectedTerms =
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

seedOf :: Integer -> OutputReference
seedOf = OutputReference (BS.replicate 32 0x77)

derivedWith :: RegistryTerms -> OutputReference -> IO RegistryScripts
derivedWith terms seed = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (deriveRegistryScripts stateTemplate terms seed blueprint)

-- | A compiled program of the blueprint, by title.
programOf :: Text -> IO (Script.Validator, SBS.ShortByteString)
programOf title = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <- loadBlueprint path >>= either fail pure
    either fail pure (requireValidator blueprint title title)

withDeposit :: Integer -> RegistryTerms -> RegistryTerms
withDeposit deposit terms =
    terms{registryCheckpointTerms = (registryCheckpointTerms terms){termsDeposit = deposit}}

withBond :: Integer -> RegistryTerms -> RegistryTerms
withBond bond terms =
    terms{registryCheckpointTerms = (registryCheckpointTerms terms){termsFreezeBond = bond}}

withPremium :: Integer -> RegistryTerms -> RegistryTerms
withPremium premium terms =
    terms{registryCheckpointTerms = (registryCheckpointTerms terms){termsPremium = premium}}

withNetwork :: Integer -> RegistryTerms -> RegistryTerms
withNetwork network terms =
    terms{registryCheckpointTerms = (registryCheckpointTerms terms){termsNetwork = network}}

withMinimumAda :: Integer -> RegistryTerms -> RegistryTerms
withMinimumAda minimumAda terms = terms{registryMinimumAda = minimumAda}

withCarrier :: Integer -> RegistryTerms -> RegistryTerms
withCarrier carrier terms = terms{registryTerminationCarrier = carrier}

spec :: Spec
spec = describe "a registry's scripts" $ do
    it "the floors are the connected scenario's: the booking floor and the fold's floor" $ do
        registryMinimumDeposit connectedTerms `shouldBe` 1_007_000_000
        registryInitialFloor connectedTerms `shouldBe` 1_009_000_000
    it "the application carries the floors and the checkpoint the amounts, as written out" $ do
        scripts <- derivedWith connectedTerms (seedOf 0)
        (_, applicationProgram) <- programOf "keri_application.keri_application.mint"
        (_, checkpointProgram) <- programOf "checkpoint_register.checkpoint_register.spend"
        let observers = scriptsObservers scripts
            hashOf = scriptHashBytes . artifactScriptHash
        artifactProgram (scriptsApplication scripts)
            `shouldBe` applyDataArgs
                [ B (blake2b_256 stateTemplate)
                , B (hashOf (scriptsAttestation scripts))
                , I 1_007_000_000
                , I 1_009_000_000
                , I 0
                , I 2_000_000
                , I 1_000_000
                ]
                applicationProgram
        artifactProgram (scriptsCheckpoint scripts)
            `shouldBe` applyDataArgs
                ( applyCheckpointParams
                    (scriptsRegistry scripts)
                    (hashOf (observerAdvance observers))
                    (hashOf (observerEnforcement observers))
                    (hashOf (observerEntitlement observers))
                    0
                    1_000_000_000
                    5_000_000
                    2_000_000
                    (hashOf (scriptsApplication scripts))
                )
                checkpointProgram
    it "the booking attestation policy is the hash-proof policy and the deposit, as written out" $ do
        scripts <- derivedWith connectedTerms (seedOf 0)
        (_, attestationProgram) <- programOf "booking_attestation.booking_attestation.mint"
        let observers = scriptsObservers scripts
            hashOf = scriptHashBytes . artifactScriptHash
        artifactProgram (scriptsAttestation scripts)
            `shouldBe` applyDataArgs
                [B (hashOf (observerHashProof observers)), I 1_000_000_000]
                attestationProgram
    it "the application is applied to the hash of that policy, and a substitute policy is another application" $ do
        base <- derivedWith connectedTerms (seedOf 0)
        other <- derivedWith (withDeposit 900_000_000 connectedTerms) (seedOf 0)
        (_, applicationProgram) <- programOf "keri_application.keri_application.mint"
        let hashOf = scriptHashBytes . artifactScriptHash
            applicationWith attestation =
                applyDataArgs
                    [ B (blake2b_256 stateTemplate)
                    , B attestation
                    , I 1_007_000_000
                    , I 1_009_000_000
                    , I 0
                    , I 2_000_000
                    , I 1_000_000
                    ]
                    applicationProgram
            attestationOf = hashOf . scriptsAttestation
        artifactProgram (scriptsApplication base)
            `shouldBe` applicationWith (attestationOf base)
        -- the application of the other deposit's attestation policy is not this application
        applicationWith (attestationOf other)
            `shouldNotBe` artifactProgram (scriptsApplication base)
        attestationOf base `shouldNotBe` attestationOf other
        -- the policy the application is applied to is not the registration observer
        attestationOf base
            `shouldNotBe` hashOf (observerLifecycle (scriptsObservers base))
    it "the historical V1 derivation neither needs nor lists the booking attestation policy" $ do
        scripts <- derivedWith connectedTerms (seedOf 0)
        path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
        current <- loadBlueprint path >>= either fail pure
        let legacy =
                current
                    { validators =
                        filter
                            (not . T.isPrefixOf "booking_attestation." . vTitle)
                            (validators current)
                    }
            application = scriptHashBytes (artifactScriptHash (scriptsApplication scripts))
            derive = deriveV1Scripts (scriptsRegistry scripts) application
        -- the control: the legacy blueprint lacks the entry, the current one has it
        any (T.isPrefixOf "booking_attestation." . vTitle) (validators current) `shouldBe` True
        any (T.isPrefixOf "booking_attestation." . vTitle) (validators legacy) `shouldBe` False
        before <- either fail pure (derive legacy)
        after <- either fail pure (derive current)
        map artifactName before
            `shouldBe` [ "hash-proof"
                       , "observer-lifecycle"
                       , "observer-advance"
                       , "observer-enforcement"
                       , "observer-entitlement"
                       , "checkpoint-register"
                       ]
        -- the entry being available moves nothing of the historical inventory
        after `shouldBe` before
        map artifactName (observerArtifacts (scriptsObservers scripts))
            `shouldBe` take 5 (map artifactName after)
    it "the new release still requires the policy, and lists it beside the observers" $ do
        scripts <- derivedWith connectedTerms (seedOf 0)
        path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
        current <- loadBlueprint path >>= either fail pure
        let legacy =
                current
                    { validators =
                        filter
                            (not . T.isPrefixOf "booking_attestation." . vTitle)
                            (validators current)
                    }
        fromLeft "derived" (deriveRegistryScripts stateTemplate connectedTerms (seedOf 0) legacy)
            `shouldBe` "booking-attestation compiled code not found in production blueprint"
        artifactName (scriptsAttestation scripts) `shouldBe` "booking-attestation"
        ("booking-attestation" `elem` map artifactName (observerArtifacts (scriptsObservers scripts)))
            `shouldBe` False
    it "the registration observer carries the same deposit" $ do
        base <- derivedWith connectedTerms (seedOf 0)
        other <- derivedWith (withDeposit 900_000_000 connectedTerms) (seedOf 0)
        artifactScriptHash (observerLifecycle (scriptsObservers base))
            `shouldNotBe` artifactScriptHash (observerLifecycle (scriptsObservers other))
    it "one changed amount moves the application and the checkpoint validator together" $ do
        base <- derivedWith connectedTerms (seedOf 0)
        bond <- derivedWith (withBond 6_000_000 connectedTerms) (seedOf 0)
        artifactScriptHash (scriptsApplication base)
            `shouldNotBe` artifactScriptHash (scriptsApplication bond)
        artifactScriptHash (scriptsCheckpoint base)
            `shouldNotBe` artifactScriptHash (scriptsCheckpoint bond)
        registryInitialFloor (withBond 6_000_000 connectedTerms) `shouldBe` 1_010_000_000
    it "terms the validator or the observer would refuse for every transaction are refused" $ do
        path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
        blueprint <- loadBlueprint path >>= either fail pure
        let derive = deriveRegistryScripts stateTemplate
            refused terms =
                either (const True) (const False) (derive terms (seedOf 0) blueprint)
        refused (withDeposit 4_999_999 connectedTerms) `shouldBe` True
        refused (withBond 4_999_999 connectedTerms) `shouldBe` True
        refused (withDeposit 5_000_000 (withBond 5_000_000 connectedTerms)) `shouldBe` False
        refused (withPremium (-1) connectedTerms) `shouldBe` True
        refused (withPremium 0 connectedTerms) `shouldBe` False
        refused (withNetwork 16 connectedTerms) `shouldBe` True
        refused (withNetwork (-1) connectedTerms) `shouldBe` True
        refused (withNetwork 15 connectedTerms) `shouldBe` False
        refused (withMinimumAda 2_000_001 connectedTerms) `shouldBe` True
        refused (withMinimumAda 1_999_999 connectedTerms) `shouldBe` True
        -- the carrier and the tip (1) fit in the minimum ADA (2_000_000) up to the boundary
        refused (withCarrier 2_000_000 connectedTerms) `shouldBe` True
        refused (withCarrier 1_999_999 connectedTerms) `shouldBe` False
        refused (withCarrier (-1) connectedTerms) `shouldBe` True
    it "the registry is named by the seed, and the checkpoint validator follows it" $ do
        first <- derivedWith connectedTerms (seedOf 0)
        second <- derivedWith connectedTerms (seedOf 1)
        registryName (scriptsRegistry first) `shouldNotBe` registryName (scriptsRegistry second)
        registryStatePolicy (scriptsRegistry first)
            `shouldBe` registryStatePolicy (scriptsRegistry second)
        artifactScriptHash (scriptsCheckpoint first)
            `shouldNotBe` artifactScriptHash (scriptsCheckpoint second)
    it "the registry's state policy is the hash of the template applied to the application" $ do
        scripts <- derivedWith connectedTerms (seedOf 0)
        let applicationPolicy = scriptHashBytes (artifactScriptHash (scriptsApplication scripts))
        registryStatePolicy (scriptsRegistry scripts)
            `shouldBe` statePolicy stateTemplate applicationPolicy
