module Main (main) where

import Cardano.KERI.Indexer.CodecsSpec qualified as CodecsSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec CodecsSpec.spec
