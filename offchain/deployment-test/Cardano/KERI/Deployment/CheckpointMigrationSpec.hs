{- |
Module      : Cardano.KERI.Deployment.CheckpointMigrationSpec
Description : Published checkpoint-family identity controls, #254 S254-1B

Two-sided throughout: the coherent published set must be accepted and each
named corruption of it must be reported.  A validator that rejects everything
would pass a one-sided suite, which is precisely what the accepting example
exists to prevent.

The load-bearing example is the last one: the historical deployed family must
still be published, with its own generation, after the new family is added.
That is the check that fails if anyone ever relabels released history as the
new family instead of publishing beside it.
-}
module Cardano.KERI.Deployment.CheckpointMigrationSpec (spec) where

import Cardano.KERI.Deployment.CheckpointMigration
import Data.Text (
    Text,
 )
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldContain,
    shouldSatisfy,
 )

spec :: Spec
spec = describe "checkpoint migration publication" $ do
    it "publishes a coherent family set" $
        checkpointFamilyPublicationErrors publishedCheckpointFamilies `shouldBe` []

    it "retains the deployed family beside the new one" $ do
        -- Released history is never relabelled. Lineage is a policy, not a
        -- generation: the new family names the deployed policy it accepts.
        map cfiPolicy publishedCheckpointFamilies
            `shouldBe` [deployedPolicy, ""]
        cfiPredecessor historicalCheckpointFamily `shouldBe` Nothing
        cfiPredecessor migrationCheckpointFamily `shouldBe` Just deployedPolicy

    it "keeps the released manifest entry as the historical record" $ do
        cfiManifestPath historicalCheckpointFamily
            `shouldBe` "deploy/preprod/m1-manifest.json"
        cfiPolicy historicalCheckpointFamily `shouldBe` deployedPolicy

    it "reports a duplicated family policy" $
        checkpointFamilyPublicationErrors
            [historicalCheckpointFamily, historicalCheckpointFamily]
            `shouldContain` [DuplicateFamilyPolicy deployedPolicy]

    it "reports a predecessor edge that names an unpublished policy" $
        checkpointFamilyPublicationErrors
            [migrationCheckpointFamily{cfiPredecessor = Just "deadbeef"}]
            `shouldSatisfy` any isUnknownPredecessor

    it "reports a set with no first family" $
        checkpointFamilyPublicationErrors [migrationCheckpointFamily]
            `shouldSatisfy` any isUnknownPredecessor

    it "reports a dropped historical family" $
        -- Publishing only the new family is exactly the relabelling failure.
        checkpointFamilyPublicationErrors
            [migrationCheckpointFamily{cfiPredecessor = Nothing}]
            `shouldContain` [HistoricalFamilyNotPreserved]

    it "reports an empty released identity field" $
        checkpointFamilyPublicationErrors
            [historicalCheckpointFamily{cfiPolicy = ""}, migrationCheckpointFamily]
            `shouldContain` [EmptyIdentityField "" "policy"]
  where
    deployedPolicy :: Text
    deployedPolicy = "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"

    isUnknownPredecessor = \case
        UnknownPredecessor _ _ -> True
        _ -> False
