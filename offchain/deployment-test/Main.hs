module Main (main) where

import Cardano.KERI.Deployment.AdvanceSpec qualified as AdvanceSpec
import Cardano.KERI.Deployment.BountyEntitlementSpec qualified as BountyEntitlementSpec
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
import System.Environment (getArgs, lookupEnv)
import Test.Hspec (hspec)

{- | The deployment suite, plus two non-test modes.

@KERI_REGISTER_IDENTITY@ makes this binary emit the corrected register's
deployment identity instead of running the suite.  The M8 register recipe needs
that identity to come from the production derivation itself, and this binary is
already wired to the live blueprint, so reading it here keeps the announced
identity and the derived one the same value rather than two that must be kept
in step.  This mirrors the Lean evidence binary's own @MIGRATION_EVIDENCE@
entry point.

A first argument of exactly @scan@ or @self-test@ runs the S254-R derived
deployment control instead of the suite.  The control is hosted here rather than
in a binary of its own because it must observe the same live blueprint fixture
this suite already loads: the arity truth it reports comes from the compiled
artifact, not from any source text, and a second executable would need a second
copy of that wiring.  Every other argument vector falls through untouched, so
@hspec@ keeps its own @--match@ and friends.
-}
main :: IO ()
main = do
    args <- getArgs
    case args of
        (command : _)
            | command == "scan" || command == "self-test" ->
                ScriptAritySpec.derivedControlMain args
        _ -> do
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
    BountyEntitlementSpec.spec
    RegistrationSpec.spec
    ScriptAritySpec.spec
    TransactionRuntimeSpec.spec
