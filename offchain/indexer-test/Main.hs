module Main (main) where

import Cardano.KERI.Indexer.CodecsSpec qualified as CodecsSpec
import Cardano.KERI.Indexer.ReadsSpec qualified as ReadsSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    CodecsSpec.spec
    ReadsSpec.spec
