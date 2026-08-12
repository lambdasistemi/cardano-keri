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
import Cardano.KERI.Deployment.Script (
    checkpointFamilyV1Version,
    v1CheckpointVersion,
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

    it "retains the deployed generation beside the new one" $ do
        -- Released history is never relabelled: the deployed family keeps
        -- generation 0 and the new family is generation 1.
        map cfiVersion publishedCheckpointFamilies
            `shouldBe` [v1CheckpointVersion, checkpointFamilyV1Version]
        cfiPredecessor historicalCheckpointFamily `shouldBe` Nothing
        cfiPredecessor migrationCheckpointFamily `shouldBe` Just v1CheckpointVersion

    it "keeps the released manifest entry as the historical record" $ do
        cfiManifestPath historicalCheckpointFamily
            `shouldBe` "deploy/preprod/m1-manifest.json"
        cfiPolicy historicalCheckpointFamily
            `shouldBe` "0c16c12ce8ca60872cadd545d1282f07dc93b5d22a134e4425355734"

    it "reports a duplicated generation" $
        checkpointFamilyPublicationErrors
            [historicalCheckpointFamily, historicalCheckpointFamily]
            `shouldContain` [DuplicateFamilyVersion v1CheckpointVersion]

    it "reports a predecessor edge that names an unpublished generation" $
        checkpointFamilyPublicationErrors
            [migrationCheckpointFamily{cfiPredecessor = Just 9}]
            `shouldSatisfy` any isUnknownPredecessor

    it "reports a skipped generation" $
        checkpointFamilyPublicationErrors
            [ historicalCheckpointFamily
            , migrationCheckpointFamily
                { cfiVersion = 5
                , cfiPredecessor = Just v1CheckpointVersion
                }
            ]
            `shouldContain` [NonContiguousFamilies v1CheckpointVersion 5]

    it "reports a set with no first generation" $
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
            `shouldContain` [EmptyIdentityField v1CheckpointVersion "policy"]
  where
    isUnknownPredecessor = \case
        UnknownPredecessor _ _ -> True
        _ -> False
