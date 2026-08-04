{- |
Module      : Main
Description : Focused #181 Slice 2A build and signing proof runner
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Runs only the shared transaction-runtime proofs. The explicit example-count
floor turns Hspec's otherwise-successful zero-selection result into a failure,
so a stale matcher or an omitted spec cannot satisfy the Slice 2A gate.
-}
module Main (main) where

import Cardano.KERI.Deployment.TransactionRuntime.RestrictedPathSpec qualified as RestrictedPathSpec
import Cardano.KERI.Deployment.TransactionRuntimeSpec qualified as TransactionRuntimeSpec
import Control.Monad (when)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Test.Hspec (Spec)
import Test.Hspec.Core.Runner (
    evaluateSummary,
    hspecResult,
    summaryExamples,
 )

main :: IO ()
main = do
    putStrLn "transaction-build-sign-tests: focused runner"
    summary <- hspecResult spec
    when (summaryExamples summary == 0) $ do
        hPutStrLn stderr "transaction-build-sign-tests: zero examples selected"
        exitFailure
    evaluateSummary summary

spec :: Spec
spec = do
    TransactionRuntimeSpec.spec
    RestrictedPathSpec.spec
