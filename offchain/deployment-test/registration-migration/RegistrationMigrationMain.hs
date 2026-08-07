{- |
Module      : Main
Description : Focused #181 Slice 2C Registration migration proof runner
Copyright   : (c) Paolo Veronelli, 2026
License     : Apache-2.0

Runs only the in-process Registration and register-CLI fail-closed proofs.
The explicit example-count floor turns Hspec's otherwise-successful
zero-selection result into a failure, so a stale matcher or omitted spec
cannot satisfy the Slice 2C gate.
-}
module Main (main) where

import Cardano.KERI.Deployment.CLISpec qualified as CLISpec
import Cardano.KERI.Deployment.RegistrationSpec qualified as RegistrationSpec
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
    putStrLn "registration-migration-tests: focused runner"
    summary <- hspecResult spec
    when (summaryExamples summary == 0) $ do
        hPutStrLn stderr "registration-migration-tests: zero examples selected"
        exitFailure
    evaluateSummary summary

spec :: Spec
spec = do
    RegistrationSpec.spec
    CLISpec.spec
    RestrictedPathSpec.spec
