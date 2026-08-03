module Main (main) where

import Cardano.KERI.CLI.Backend.ConfigSpec qualified as ConfigSpec
import Cardano.KERI.CLI.Backend.ContractSpec qualified as ContractSpec
import Cardano.KERI.CLI.Backend.DispatchSpec qualified as DispatchSpec
import Cardano.KERI.CLI.Backend.EndpointSpec qualified as EndpointSpec
import Cardano.KERI.CLI.Backend.KoiosSpec qualified as KoiosSpec
import Cardano.KERI.CLI.Backend.LocalSpec qualified as LocalSpec
import Cardano.KERI.CLI.ProductionSpec qualified as ProductionSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    ConfigSpec.spec
    ContractSpec.spec
    DispatchSpec.spec
    EndpointSpec.spec
    KoiosSpec.spec
    LocalSpec.spec
    ProductionSpec.spec
