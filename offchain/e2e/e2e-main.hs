-- | Entry point for the live-boundary withDevnet E2E suite.
module Main (main) where

import Test.Hspec (hspec)

import CageE2ESpec qualified
import CheckpointE2ESpec qualified

main :: IO ()
main = hspec $ do
    CageE2ESpec.spec
    CheckpointE2ESpec.spec
