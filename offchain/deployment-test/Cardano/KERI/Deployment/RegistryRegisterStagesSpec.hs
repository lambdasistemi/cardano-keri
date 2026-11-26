{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryRegisterStagesSpec
Description : what @register@ says of each stage it stopped at: the premint that settled, the booking that was never built, and the purpose an evaluation refused

@register@ is two transactions. After the premint settled, a stop of the run is a stop of
the second stage and says the first landed; a stop before the booking exists is not a
settled booking; an evaluation that refuses the booking names the redeemer purpose the
evaluator named and attributes it to no policy the command cannot know it to be.
-}
module Cardano.KERI.Deployment.RegistryRegisterStagesSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand (renderRegisterFailure)
import Cardano.KERI.Deployment.RegistryChain (Observation (..), Refusal (..), RegistryRuntime (..), SubmitError (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Faults (..), noFaults)
import Cardano.KERI.Deployment.RegistryRegister
import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (UnknownTxIn))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Data.Text qualified as T
import Test.Hspec

zeroLine :: String
zeroLine = "nothing was submitted; nothing was spent"

-- | A runtime whose observations after the first (the premint's) have no slot left to book in.
horizonAtTheTipAfterTheFirst :: RegistryRuntime -> IO RegistryRuntime
horizonAtTheTipAfterTheFirst runtime = do
    calls <- newIORef (0 :: Int)
    pure
        runtime
            { rtObserve = do
                n <- atomicModifyIORef' calls (\c -> (c + 1, c))
                observed <- rtObserve runtime
                pure (if n >= 1 then observed{obsHorizonSlot = obsTipSlot observed} else observed)
            }

spec :: Spec
spec = describe "#559 what register says of the stage it stopped at" $ around_ withinOneMinute $ do
    it "keeps the settled premint when the booking's own interval cannot be formed: a refusal after it, not a zero spend" $ do
        world <- newWorld 1_000
        export <- loadExport "kli-export-single.cesr"
        sent0 <- submissionsMade world
        runtime <- horizonAtTheTipAfterTheFirst (runtimeOf noFaults world)
        outcome <- registerRegistration runtime (\_ -> pure ()) (registerRequestOf world export)
        transactions <- accepted world
        case outcome of
            Left failure@(RegisterRefusedAfterPremint premintId _ (NoBookingIntervalYet _)) -> do
                premintId `shouldBe` transactionId (last transactions)
                let said = renderRegisterFailure failure
                    atLine needle = lookup True (zip (map (needle `isInfixOf`) said) [0 :: Int ..])
                    premintLine = atLine (T.unpack (renderTransactionId premintId))
                    refusalLine = atLine "refused by the command before building the booking"
                said `shouldSatisfy` any ("the premint of the hash proof settled" `isInfixOf`)
                said `shouldSatisfy` any ("the booking was not built" `isInfixOf`)
                said `shouldSatisfy` (zeroLine `notElem`)
                -- the whole report is read against the one transaction that settled: the premint is named first, and the
                -- refusal is placed after it, never "before any transaction"
                said `shouldSatisfy` (not . any ("before any transaction" `isInfixOf`))
                (premintLine, refusalLine) `shouldSatisfy` (\(p, r) -> maybe False (\a -> maybe False (a <) r) p)
            other -> expectationFailure ("not a refusal after the premint: " <> show other)
        submissionsMade world >>= (`shouldBe` (sent0 + 1))
    forM_ [("the premint's own report", "premint" :: String), ("the booking's window", "window")] $ \(label, stage) ->
        it ("says the booking was never built when " <> label <> " cannot be written, and does not present the premint as a settled booking") $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            sent0 <- submissionsMade world
            let report event = case (stage, event) of
                    ("premint", PremintSettledForBooking{}) -> ioError (userError "the report cannot be written")
                    ("window", BookingWindow{}) -> ioError (userError "the report cannot be written")
                    _ -> pure ()
            outcome <- registerRegistration (runtimeOf noFaults world) report (registerRequestOf world export)
            transactions <- accepted world
            case outcome of
                Left failure@(RegisterStoppedAfterPremint premintId _ message) -> do
                    premintId `shouldBe` transactionId (last transactions)
                    message `shouldSatisfy` ("the report cannot be written" `isInfixOf`)
                    let said = renderRegisterFailure failure
                    said `shouldSatisfy` any ("the premint of the hash proof settled" `isInfixOf`)
                    said `shouldSatisfy` any ("the booking was not built" `isInfixOf`)
                    said `shouldSatisfy` (not . any ("registry register settled" `isInfixOf`))
                    said `shouldSatisfy` (not . any ("booking-transaction:" `isInfixOf`))
                other -> expectationFailure ("not a stop after the premint: " <> show other)
            submissionsMade world >>= (`shouldBe` (sent0 + 1))
    forM_ [0, 1, 2 :: Integer] $ \purpose ->
        it ("names minting purpose " <> show purpose <> " when the evaluation refuses that purpose, and attributes it to no policy") $ do
            world <- newWorld 1_000
            export <- loadExport "kli-export-single.cesr"
            let missing = TxIn (TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 0xee))))) (TxIx 0)
                refusingOnly =
                    noFaults
                        { distortEvaluation = \_ ->
                            Map.mapWithKey
                                (\p answer -> if p == ConwayMinting (AsIx (fromInteger purpose)) then Left (UnknownTxIn missing) else answer)
                        }
            outcome <- registerRegistration (runtimeOf refusingOnly world) (\_ -> pure ()) (registerRequestOf world export)
            case outcome of
                Left failure@(RegisterAfterPremint _ _ (EvaluationFailed message)) -> do
                    message `shouldSatisfy` (("minting purpose " <> show purpose <> ":") `isInfixOf`)
                    let said = renderRegisterFailure failure
                    said `shouldSatisfy` any (("minting purpose " <> show purpose <> ":") `isInfixOf`)
                    said `shouldSatisfy` any ("the node's evaluation refused the booking" `isInfixOf`)
                    said `shouldSatisfy` (not . any ("the application's" `isInfixOf`))
                other -> expectationFailure ("not an evaluation refusal after the premint: " <> show other)
