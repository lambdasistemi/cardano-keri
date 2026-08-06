{- |
Module      : Main
Description : Focused #181 Slice 3 Close migration proof runner
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0
-}
module Main (main) where

import Cardano.KERI.Deployment.CloseSpec qualified as CloseSpec
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
    putStrLn "close-migration-tests: focused runner"
    summary <- hspecResult spec
    when (summaryExamples summary == 0) $ do
        hPutStrLn stderr "close-migration-tests: zero examples selected"
        exitFailure
    evaluateSummary summary

spec :: Spec
spec = do
    CloseSpec.spec
    RestrictedPathSpec.spec
