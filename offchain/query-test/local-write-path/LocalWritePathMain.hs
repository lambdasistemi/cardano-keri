module Main (main) where

import Cardano.KERI.Indexer.LocalWritePathSpec qualified as LocalWritePathSpec
import Cardano.KERI.Indexer.PublicSurfaceSpec qualified as PublicSurfaceSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    LocalWritePathSpec.spec
    PublicSurfaceSpec.spec
