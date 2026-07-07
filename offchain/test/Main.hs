module Main (main) where

import Cardano.KERI.AID.CESRSpec qualified as CESRSpec
import Cardano.KERI.AID.Cage.SignSpec qualified as SignSpec
import Cardano.KERI.AID.Cage.TypesSpec qualified as TypesSpec
import Cardano.KERI.AID.Ed25519Spec qualified as Ed25519Spec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    Ed25519Spec.spec
    CESRSpec.spec
    TypesSpec.spec
    SignSpec.spec
