{- |
Module      : Main
Description : Focused #181 Slice 2B Publisher migration proof runner
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Runs only the in-process Publisher migration proofs. The explicit
example-count floor turns Hspec's otherwise-successful zero-selection result
into a failure, so a stale matcher or an omitted spec cannot satisfy the
Slice 2B gate.
-}
module Main (main) where

import Cardano.KERI.Deployment.PublisherSpec qualified as PublisherSpec
import Cardano.KERI.Deployment.TransactionRuntime.RestrictedPathSpec qualified as RestrictedPathSpec
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
    putStrLn "publisher-migration-tests: focused runner"
    summary <- hspecResult spec
    when (summaryExamples summary == 0) $ do
        hPutStrLn stderr "publisher-migration-tests: zero examples selected"
        exitFailure
    evaluateSummary summary

spec :: Spec
spec = do
    PublisherSpec.spec
    RestrictedPathSpec.spec
