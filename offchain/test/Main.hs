module Main (main) where

import Cardano.AID.CESRSpec qualified as CESRSpec
import Cardano.AID.Ed25519Spec qualified as Ed25519Spec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    Ed25519Spec.spec
    CESRSpec.spec
