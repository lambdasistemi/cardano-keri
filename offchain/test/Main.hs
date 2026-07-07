module Main (main) where

import Cardano.AID.CESRSpec qualified as CESRSpec
import Cardano.AID.Cage.SignSpec qualified as SignSpec
import Cardano.AID.Cage.TypesSpec qualified as TypesSpec
import Cardano.AID.Ed25519Spec qualified as Ed25519Spec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    Ed25519Spec.spec
    CESRSpec.spec
    TypesSpec.spec
    SignSpec.spec
