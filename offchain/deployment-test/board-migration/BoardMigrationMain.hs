{- |
Module      : Main
Description : Focused #181 Slice 3 endpoint-board migration proof runner
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Main (main) where

import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry (..),
    reconcileBoardMigration,
 )
import Cardano.KERI.Deployment.EndpointBoardTransactionSpec qualified as EndpointBoardTransactionSpec
import Cardano.KERI.Deployment.TransactionRuntime.RestrictedPathSpec qualified as RestrictedPathSpec
import Control.Monad (when)
import Data.Aeson (FromJSON (..), (.:))
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import System.Environment (getEnv)
import System.Exit (exitFailure)
import System.FilePath (replaceFileName)
import System.IO (hPutStrLn, stderr)
import Test.Hspec (
    Spec,
    describe,
    it,
    runIO,
    shouldBe,
    shouldSatisfy,
 )
import Test.Hspec.Core.Runner (
    evaluateSummary,
    hspecResult,
    summaryExamples,
 )

main :: IO ()
main = do
    putStrLn "board-migration-tests: focused runner"
    summary <- hspecResult spec
    when (summaryExamples summary == 0) $ do
        hPutStrLn stderr "board-migration-tests: zero examples selected"
        exitFailure
    evaluateSummary summary

spec :: Spec
spec = do
    EndpointBoardTransactionSpec.spec
    RestrictedPathSpec.spec
    boardInventorySpec

boardInventorySpec :: Spec
boardInventorySpec = do
    expectedPreprodBoardAids <- runIO readPreprodBoardAids
    describe "S254-2 board inventory reconciliation" $ do
        it "reconciles all three frozen witness identities one-for-one" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                successorBoardInventory
                `shouldSatisfy` isRight

        it "s254_2_board_expected_inventory_duplicate_identity_rejects" $
            reconcileBoardMigration
                (expectedPreprodBoardAids <> [witnessOneAid])
                sourceBoardInventory
                successorBoardInventory
                `shouldBe` Left
                    "expected witness identity appears more than once"

        it "s254_2_board_source_inventory_extra_foreign_row_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                (sourceBoardInventory <> [boardRow plausibleForeignAid 4])
                successorBoardInventory
                `shouldBe` Left
                    "source board inventory does not match the expected witnesses"

        it "s254_2_board_successor_inventory_extra_foreign_row_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                (successorBoardInventory <> [successorRow plausibleForeignAid 4])
                `shouldBe` Left
                    "successor board inventory does not match the expected witnesses"

        it "s254_2_board_inventory_missing_row_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                (drop 1 successorBoardInventory)
                `shouldSatisfy` isLeft

        it "s254_2_board_source_inventory_duplicate_row_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                ( sourceOne
                    { boardUrl = "https://attacker.invalid"
                    }
                    : sourceBoardInventory
                )
                successorBoardInventory
                `shouldBe` Left
                    "source board witness identity appears more than once"

        it "s254_2_board_inventory_duplicate_row_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                (successorOne : successorBoardInventory)
                `shouldBe` Left
                    "successor board witness identity appears more than once"

        it "s254_2_board_inventory_changed_row_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                ( sourceOne
                    { boardUrl = "https://attacker.invalid"
                    }
                    : drop 1 sourceBoardInventory
                )
                `shouldSatisfy` isLeft

        it "s254_2_board_inventory_changed_witness_key_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                ( sourceOne
                    { boardWitnessKey = BS.replicate 32 0x7f
                    }
                    : drop 1 sourceBoardInventory
                )
                `shouldSatisfy` isLeft

        it "s254_2_board_inventory_changed_scheme_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                ( sourceOne
                    { boardScheme = "http"
                    }
                    : drop 1 sourceBoardInventory
                )
                `shouldSatisfy` isLeft

        it "s254_2_board_inventory_changed_lovelace_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                ( sourceOne
                    { boardLovelace = 4_000_001
                    }
                    : drop 1 sourceBoardInventory
                )
                `shouldSatisfy` isLeft

        it "s254_2_board_inventory_changed_owner_key_hash_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                ( sourceOne
                    { boardOwnerKeyHash = BS.replicate 28 0x44
                    }
                    : drop 1 sourceBoardInventory
                )
                `shouldSatisfy` isLeft

        it "s254_2_board_inventory_substituted_identity_rejects" $
            reconcileBoardMigration
                expectedPreprodBoardAids
                sourceBoardInventory
                ( successorRow plausibleForeignAid 1
                    : drop 1 successorBoardInventory
                )
                `shouldSatisfy` isLeft
newtype WitnessAnchor = WitnessAnchor {witnessAnchorAid :: Text}

instance FromJSON WitnessAnchor where
    parseJSON =
        Aeson.withObject "preprod witness anchor" $ \object ->
            WitnessAnchor <$> object .: "aid"

-- D-004's expected identities come from the committed deployment artifact.
-- The source/successor fixtures remain independent, so changing either side
-- makes the positive reconciliation control fail.
readPreprodBoardAids :: IO [Text]
readPreprodBoardAids = do
    boardBlueprintPath <- getEnv "KERI_BOARD_BLUEPRINT"
    decoded <-
        Aeson.eitherDecodeFileStrict'
            (replaceFileName boardBlueprintPath "witnesses.json")
    anchors <- either fail pure decoded
    pure (map witnessAnchorAid anchors)

fixturePreprodBoardAids :: [Text]
fixturePreprodBoardAids =
    [ witnessOneAid
    , witnessTwoAid
    , witnessThreeAid
    ]

plausibleForeignAid :: Text
plausibleForeignAid = "BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

witnessOneAid, witnessTwoAid, witnessThreeAid :: Text
witnessOneAid = "BCZT7to0flgH8Kb98kiOkexEJYNQcyhuldaS__c5QaLI"
witnessTwoAid = "BBkK9o9mMm_nIu5yl3x3L7ti8cYoKg-AoxpqQapMcE5B"
witnessThreeAid = "BNP31dFWbqS_oUe2CUu24Ct7cQjpk3DscLzbpGT5OEz4"

sourceBoardInventory :: [BoardEntry]
sourceBoardInventory = zipWith boardRow fixturePreprodBoardAids [1 ..]

successorBoardInventory :: [BoardEntry]
successorBoardInventory = zipWith successorRow fixturePreprodBoardAids [1 ..]

successorOne :: BoardEntry
successorOne = successorRow witnessOneAid 1

sourceOne :: BoardEntry
sourceOne = boardRow witnessOneAid 1

successorRow :: Text -> Int -> BoardEntry
successorRow aid marker =
    (boardRow aid marker)
        { boardTxId = replicateText 64 (marker + 10)
        }

boardRow :: Text -> Int -> BoardEntry
boardRow aid marker =
    BoardEntry
        { boardWitnessKey = BS.replicate 32 (fromIntegral marker)
        , boardAid = aid
        , boardScheme = "https"
        , boardUrl = "https://witness.preprod.plutimus.com"
        , boardTxId = replicateText 64 marker
        , boardIndex = 0
        , boardLovelace = 4_000_000
        , boardOwnerKeyHash = BS.replicate 28 0x33
        }

replicateText :: Int -> Int -> Text
replicateText width marker =
    T.replicate width (T.singleton $ toEnum (fromEnum 'a' + marker `mod` 6))

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _) = False
