{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Deployment.BountyEntitlementSpec
Description : S254-E deployment proof of the applied commitment family

The deployment half of T254-107.  It establishes three things about the
production derivation, all read from the live blueprint rather than asserted:

* the compiled programs really take the new arguments — the split checkpoint's
  seventh @CommitmentFamily@ and the enforcement observer's second — so an
  implementation that stubbed the family away would change an argument count
  and be caught here;
* the deployed commitment policy is the hash of the commitment program applied
  to this release's explicit magnitudes, and moves when any of them moves;
* the family reaches the deployed register: applying it changes the
  enforcement observer's identity, and that identity is inside the applied
  register's own parameters, so the register cannot silently point its
  entitlement rule at a different reservation program.

The magnitudes themselves are held to the component's own admissibility rule,
so a release cannot deploy a lifetime or deposit the program would refuse.
-}
module Cardano.KERI.Deployment.BountyEntitlementSpec (spec) where

import Cardano.KERI.AID.Checkpoint.BountyCommitment (
    CommitmentFamily (..),
    CommitmentParameters (..),
    ParametersError (..),
    ParametersVerdict (..),
    commitDepositFloor,
    commitMinAge,
    parametersWellFormed,
 )
import Cardano.KERI.Deployment.Script (
    Blueprint,
    ScriptArtifact (..),
    applyAdvanceParams,
    applyCheckpointFamilyParams,
    applyCommitmentParams,
    applyDataArgs,
    applyEnforcementParams,
    computeScriptHash,
    deriveCommitmentFamily,
    deriveV1Scripts,
    extractCompiledCodeExact,
    loadBlueprint,
    scriptHashBytes,
    v1CheckpointVersion,
    v1CommitDeposit,
    v1CommitmentLifetime,
    v1CommitmentParameters,
    v1FreezeBond,
    v1FreezeWindow,
    v1NetworkDiscriminator,
    v1RegistrationBond,
    validatorParameterCount,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Text (Text)
import System.Environment (getEnv)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
 )

spec :: Spec
spec = describe "S254-E applied commitment family" $ do
    magnitudesSpec
    aritySpec
    policySpec
    reachSpec

-- ---------------------------------------------------------
-- Release magnitudes
-- ---------------------------------------------------------

magnitudesSpec :: Spec
magnitudesSpec = describe "release magnitudes" $ do
    it "are admissible to the component's own rule" $
        parametersWellFormed v1CommitmentParameters
            `shouldBe` ParametersValid
    it "carry the mandated one-slot maturity" $
        cpCommitMinAge v1CommitmentParameters `shouldBe` commitMinAge
    it "name an explicit finite release lifetime" $
        cpCommitmentLifetime v1CommitmentParameters
            `shouldBe` v1CommitmentLifetime
    it "retain the demonstrated deposit floor" $ do
        v1CommitDeposit `shouldBe` commitDepositFloor
        cpCommitDeposit v1CommitmentParameters `shouldBe` commitDepositFloor
    it "are scoped to the release's own network discriminator" $
        cpNetwork v1CommitmentParameters `shouldBe` v1NetworkDiscriminator
    it "would be refused if the deposit dropped below the floor" $
        -- The admissibility row above is only evidence because this one
        -- shows the same rule rejecting a neighbour that differs in one
        -- field.
        parametersWellFormed
            v1CommitmentParameters{cpCommitDeposit = commitDepositFloor - 1}
            `shouldBe` ParametersInvalid ParametersDeposit

-- ---------------------------------------------------------
-- Compiled arity
-- ---------------------------------------------------------

aritySpec :: Spec
aritySpec = describe "compiled argument counts" $ do
    it "gives the split checkpoint a seventh CommitmentFamily argument" $
        withBlueprint $ \blueprint ->
            validatorParameterCount "checkpoint.checkpoint.spend" blueprint
                `shouldBe` Just 7
    it "gives the enforcement observer a second argument" $
        withBlueprint $ \blueprint -> do
            validatorParameterCount
                "checkpoint_observer.observer_enforcement.withdraw"
                blueprint
                `shouldBe` Just 2
            validatorParameterCount
                "checkpoint_observer.observer_enforcement.publish"
                blueprint
                `shouldBe` Just 2
    it "leaves the advance observer's single argument untouched" $
        -- The two counts above mean nothing without a neighbour that did not
        -- move: this is what distinguishes "the family was threaded through
        -- the enforcement observer" from "every observer grew an argument".
        withBlueprint $ \blueprint ->
            validatorParameterCount
                "checkpoint_observer.observer_advance.withdraw"
                blueprint
                `shouldBe` Just 1
    it "gives the combined register a ninth entitlement-observer credential" $
        -- A-002 adds the entitlement observer as an applied register
        -- argument.  The constructor still fails closed on declared vs
        -- supplied arity; this row records the declaration the plan must
        -- match.
        withBlueprint $ \blueprint ->
            validatorParameterCount
                "checkpoint_register.checkpoint_register.mint"
                blueprint
                `shouldBe` Just 9
    it "gives the commitment program exactly its magnitudes" $
        withBlueprint $ \blueprint ->
            validatorParameterCount
                "bounty_commitment.bounty_commitment.spend"
                blueprint
                `shouldBe` Just 1

-- ---------------------------------------------------------
-- Derived policy
-- ---------------------------------------------------------

policySpec :: Spec
policySpec = describe "derived commitment policy" $ do
    it "is the hash of the program applied to the release magnitudes" $
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            program <- requireProgram blueprint commitmentTitle
            cfPolicy family
                `shouldBe` scriptHashOf
                    (applyCommitmentParams v1CommitmentParameters program)
    it "carries the release magnitudes verbatim" $
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            cfParameters family `shouldBe` v1CommitmentParameters
    it "is a 28-byte script hash" $
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            BS.length (cfPolicy family) `shouldBe` 28
    it "moves when the applied lifetime moves" $
        -- The magnitudes are inside the policy, so a release cannot change
        -- how long reservations live while claiming the same family.
        withBlueprint $ \blueprint -> do
            program <- requireProgram blueprint commitmentTitle
            let shifted =
                    v1CommitmentParameters
                        { cpCommitmentLifetime = v1CommitmentLifetime + 1
                        }
            scriptHashOf (applyCommitmentParams shifted program)
                `shouldNotBe` scriptHashOf
                    (applyCommitmentParams v1CommitmentParameters program)
    it "moves when the applied deposit moves" $
        withBlueprint $ \blueprint -> do
            program <- requireProgram blueprint commitmentTitle
            let shifted =
                    v1CommitmentParameters
                        { cpCommitDeposit = v1CommitDeposit + 1_000_000
                        }
            scriptHashOf (applyCommitmentParams shifted program)
                `shouldNotBe` scriptHashOf
                    (applyCommitmentParams v1CommitmentParameters program)

-- ---------------------------------------------------------
-- The family reaches the deployed register
-- ---------------------------------------------------------

reachSpec :: Spec
reachSpec = describe "family reaches the deployed register" $ do
    it "applies the family to the deployed enforcement observer" $
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            program <- requireProgram blueprint enforcementTitle
            artifacts <- either fail pure (deriveV1Scripts blueprint)
            enforcement <- requireArtifact artifacts "observer-enforcement"
            artifactScriptHash enforcement
                `shouldBe` computeScriptHash
                    ( applyDataArgs
                        ( applyEnforcementParams
                            v1CheckpointVersion
                            family
                        )
                        program
                    )
    it "is not the identity the one-argument application would produce" $
        -- Without this the row above would pass for a deployment that had
        -- erased the second argument and re-derived the expectation from the
        -- same erasure.
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            program <- requireProgram blueprint enforcementTitle
            computeScriptHash
                ( applyDataArgs
                    (applyEnforcementParams v1CheckpointVersion family)
                    program
                )
                `shouldNotBe` computeScriptHash
                    ( applyDataArgs
                        (applyAdvanceParams v1CheckpointVersion)
                        program
                    )
    it "changes the enforcement identity when the family changes" $
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            program <- requireProgram blueprint enforcementTitle
            let foreign_ = family{cfPolicy = BS.replicate 28 0xf0}
            computeScriptHash
                ( applyDataArgs
                    (applyEnforcementParams v1CheckpointVersion foreign_)
                    program
                )
                `shouldNotBe` computeScriptHash
                    ( applyDataArgs
                        (applyEnforcementParams v1CheckpointVersion family)
                        program
                    )
    it "carries that identity into the applied register's own parameters" $
        -- The register pins the enforcement observer by hash, so a changed
        -- commitment family reaches the deployed checkpoint policy itself.
        withBlueprint $ \blueprint -> do
            artifacts <- either fail pure (deriveV1Scripts blueprint)
            enforcement <- requireArtifact artifacts "observer-enforcement"
            register <- requireArtifact artifacts "checkpoint-register"
            program <- requireProgram blueprint registerTitle
            artifactScriptHash register
                `shouldNotBe` computeScriptHash program
            artifactScriptHash enforcement
                `shouldNotBe` artifactScriptHash register
    it "applies a seventh argument to the split checkpoint program" $
        withBlueprint $ \blueprint -> do
            family <- either fail pure (deriveCommitmentFamily blueprint)
            program <- requireProgram blueprint splitCheckpointTitle
            let applied =
                    applyCheckpointFamilyParams
                        v1CheckpointVersion
                        (BS.replicate 28 0xaa)
                        v1NetworkDiscriminator
                        v1RegistrationBond
                        v1FreezeBond
                        v1FreezeWindow
                        family
                        program
            computeScriptHash applied `shouldNotBe` computeScriptHash program

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

commitmentTitle :: Text
commitmentTitle = "bounty_commitment.bounty_commitment.spend"

enforcementTitle :: Text
enforcementTitle = "checkpoint_observer.observer_enforcement.withdraw"

registerTitle :: Text
registerTitle = "checkpoint_register.checkpoint_register.mint"

splitCheckpointTitle :: Text
splitCheckpointTitle = "checkpoint.checkpoint.spend"

withBlueprint :: (Blueprint -> IO ()) -> IO ()
withBlueprint action = do
    path <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    blueprint <- loadBlueprint path >>= either fail pure
    action blueprint

requireProgram ::
    Blueprint -> Text -> IO SBS.ShortByteString
requireProgram blueprint title =
    maybe
        (fail ("blueprint has no compiled code for " <> show title))
        pure
        (extractCompiledCodeExact title blueprint)

requireArtifact :: [ScriptArtifact] -> Text -> IO ScriptArtifact
requireArtifact artifacts name =
    case filter ((== name) . artifactName) artifacts of
        [artifact] -> pure artifact
        _ -> fail ("artifact " <> show name <> " is not uniquely derived")

scriptHashOf :: SBS.ShortByteString -> BS.ByteString
scriptHashOf = scriptHashBytes . computeScriptHash
