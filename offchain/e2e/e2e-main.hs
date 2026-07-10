-- | Entry point for the live-boundary withDevnet cage Phase-2 smoke.
module Main (main) where

import Test.Hspec (hspec)

import CageE2ESpec (spec)

main :: IO ()
main = hspec spec
