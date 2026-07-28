module Main (main) where

import Cardano.KERI.Deployment.ManifestSpec qualified as ManifestSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec ManifestSpec.spec
