module Main (main) where

import Cardano.KERI.CLI.Backend.ConfigSpec qualified as ConfigSpec
import Cardano.KERI.CLI.Backend.ContractSpec qualified as ContractSpec
import Cardano.KERI.CLI.Backend.DispatchSpec qualified as DispatchSpec
import Cardano.KERI.CLI.Backend.EndpointSpec qualified as EndpointSpec
import Cardano.KERI.CLI.Backend.KoiosSpec qualified as KoiosSpec
import Cardano.KERI.CLI.Backend.LocalRegistryStoreSpec qualified as LocalRegistryStoreSpec
import Cardano.KERI.CLI.Backend.LocalSpec qualified as LocalSpec
import Cardano.KERI.CLI.CommandSurfaceSpec qualified as CommandSurfaceSpec
import Cardano.KERI.CLI.ProductionSpec qualified as ProductionSpec
import Cardano.KERI.CLI.RegistryAwareDeploymentSpec qualified as RegistryAwareDeploymentSpec
import Cardano.KERI.CLI.RegistryBookingGroupSpec qualified as RegistryBookingGroupSpec
import Cardano.KERI.CLI.RegistryGroupSpec qualified as RegistryGroupSpec
import Cardano.KERI.CLI.WriteCompositionBoundarySpec qualified as WriteCompositionBoundarySpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    ConfigSpec.spec
    ContractSpec.spec
    DispatchSpec.spec
    EndpointSpec.spec
    KoiosSpec.spec
    LocalSpec.spec
    LocalRegistryStoreSpec.spec
    CommandSurfaceSpec.spec
    ProductionSpec.spec
    RegistryGroupSpec.spec
    RegistryBookingGroupSpec.spec
    RegistryAwareDeploymentSpec.spec
    WriteCompositionBoundarySpec.spec
