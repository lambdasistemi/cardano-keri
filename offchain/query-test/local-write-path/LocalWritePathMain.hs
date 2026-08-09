module Main (main) where

import Cardano.KERI.Indexer.LocalWritePathSpec qualified as LocalWritePathSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec LocalWritePathSpec.spec
