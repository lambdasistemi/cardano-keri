{- |
Module      : Main
Description : Focused #257 chain-query algebra proof runner

Runs the complete #257 focused proof: operation surface, both interpreter
semantics, settlement, Koios extended-response self-resolution, the local
interpreter's one-run/atomicity properties, and registration wiring. The
explicit example-count floor turns Hspec's otherwise-successful
zero-selection result into a failure, so a stale matcher or an omitted spec
cannot satisfy the gate (mirrors publisher-migration-tests/
registration-migration-tests's own runner shape).
-}
module Main (main) where

import Cardano.KERI.ChainQuery.InterpreterSpec qualified as InterpreterSpec
import Cardano.KERI.ChainQuery.Koios.DecodeSpec qualified as KoiosDecodeSpec
import Cardano.KERI.ChainQuery.ProgramSpec qualified as ProgramSpec
import Cardano.KERI.ChainQuery.RegistrationWiringSpec qualified as RegistrationWiringSpec
import Cardano.KERI.ChainQuery.SettlementSpec qualified as SettlementSpec
import Cardano.KERI.Indexer.ChainQuerySpec qualified as IndexerChainQuerySpec
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
    putStrLn "chain-query-tests: focused #257 runner"
    summary <- hspecResult spec
    when (summaryExamples summary == 0) $ do
        hPutStrLn stderr "chain-query-tests: zero examples selected"
        exitFailure
    evaluateSummary summary

spec :: Spec
spec = do
    ProgramSpec.spec
    InterpreterSpec.spec
    SettlementSpec.spec
    KoiosDecodeSpec.spec
    IndexerChainQuerySpec.spec
    RegistrationWiringSpec.spec
