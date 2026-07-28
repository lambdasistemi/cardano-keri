module Main (main) where

import Cardano.KERI.Deployment.ChainIndexSpec qualified as ChainIndexSpec
import Cardano.KERI.Deployment.KELSpec qualified as KELSpec
import Cardano.KERI.Deployment.ManifestSpec qualified as ManifestSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    ChainIndexSpec.spec
    KELSpec.spec
    ManifestSpec.spec
