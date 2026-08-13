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
import Cardano.KERI.Deployment.ScriptAritySpec qualified as ScriptAritySpec
import Cardano.KERI.Deployment.TransactionRuntimeSpec qualified as TransactionRuntimeSpec
import System.Environment (lookupEnv)
import Test.Hspec (hspec)

{- | The deployment suite, plus one non-test mode.

@KERI_REGISTER_IDENTITY@ makes this binary emit the corrected register's
deployment identity instead of running the suite.  The M8 register recipe needs
that identity to come from the production derivation itself, and this binary is
already wired to the live blueprint, so reading it here keeps the announced
identity and the derived one the same value rather than two that must be kept
in step.  This mirrors the Lean evidence binary's own @MIGRATION_EVIDENCE@
entry point.
-}
main :: IO ()
main = do
    identityMode <- lookupEnv "KERI_REGISTER_IDENTITY"
    case identityMode of
        Just _ -> ScriptAritySpec.emitRegisterIdentity
        Nothing -> suite

suite :: IO ()
suite = hspec $ do
    AdvanceSpec.spec
    ChainIndexSpec.spec
    CloseSpec.spec
    EndpointBoardSpec.spec
    EndpointBoardTransactionSpec.spec
    KELSpec.spec
    ManifestSpec.spec
    CheckpointMigrationSpec.spec
    RegistrationSpec.spec
    ScriptAritySpec.spec
    TransactionRuntimeSpec.spec
