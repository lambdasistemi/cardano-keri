module Main (main) where

import Cardano.KERI.Deployment.AdvanceSpec qualified as AdvanceSpec
import Cardano.KERI.Deployment.ChainIndexSpec qualified as ChainIndexSpec
import Cardano.KERI.Deployment.CheckpointMigrationSpec qualified as CheckpointMigrationSpec
import Cardano.KERI.Deployment.CloseSpec qualified as CloseSpec
import Cardano.KERI.Deployment.EndpointBoardSpec qualified as EndpointBoardSpec
import Cardano.KERI.Deployment.EndpointBoardTransactionSpec qualified as EndpointBoardTransactionSpec
import Cardano.KERI.Deployment.KELSpec qualified as KELSpec
import Cardano.KERI.Deployment.ManifestSpec qualified as ManifestSpec
import Cardano.KERI.Deployment.RegistrationSpec qualified as RegistrationSpec
import Cardano.KERI.Deployment.TransactionRuntimeSpec qualified as TransactionRuntimeSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    AdvanceSpec.spec
    ChainIndexSpec.spec
    CloseSpec.spec
    EndpointBoardSpec.spec
    EndpointBoardTransactionSpec.spec
    KELSpec.spec
    ManifestSpec.spec
    CheckpointMigrationSpec.spec
    RegistrationSpec.spec
    TransactionRuntimeSpec.spec
