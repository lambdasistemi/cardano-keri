module Main (main) where

import Cardano.KERI.Deployment.AdvancePackageSpec qualified as AdvancePackageSpec
import Cardano.KERI.Deployment.AdvanceSpec qualified as AdvanceSpec
import Cardano.KERI.Deployment.AttestationBoundarySpec qualified as AttestationBoundarySpec
import Cardano.KERI.Deployment.BountyEntitlementSpec qualified as BountyEntitlementSpec
import Cardano.KERI.Deployment.ChainIndexSpec qualified as ChainIndexSpec
import Cardano.KERI.Deployment.EndpointBoardSpec qualified as EndpointBoardSpec
import Cardano.KERI.Deployment.EndpointBoardTransactionSpec qualified as EndpointBoardTransactionSpec
import Cardano.KERI.Deployment.FreezePackageSpec qualified as FreezePackageSpec
import Cardano.KERI.Deployment.KELSpec qualified as KELSpec
import Cardano.KERI.Deployment.KoiosReadsSpec qualified as KoiosReadsSpec
import Cardano.KERI.Deployment.KoiosRegistryRuntimeSpec qualified as KoiosRegistryRuntimeSpec
import Cardano.KERI.Deployment.KoiosSettlementSpec qualified as KoiosSettlementSpec
import Cardano.KERI.Deployment.KoiosSubmissionSpec qualified as KoiosSubmissionSpec
import Cardano.KERI.Deployment.ManifestSpec qualified as ManifestSpec
import Cardano.KERI.Deployment.RegistrationEvidenceSpec qualified as RegistrationEvidenceSpec
import Cardano.KERI.Deployment.RegistrationSpec qualified as RegistrationSpec
import Cardano.KERI.Deployment.RegistryApplicationSpec qualified as RegistryApplicationSpec
import Cardano.KERI.Deployment.RegistryAttemptSpec qualified as RegistryAttemptSpec
import Cardano.KERI.Deployment.RegistryBookingCommandSpec qualified as RegistryBookingCommandSpec
import Cardano.KERI.Deployment.RegistryBookingEvaluationSpec qualified as RegistryBookingEvaluationSpec
import Cardano.KERI.Deployment.RegistryBookingShapeSpec qualified as RegistryBookingShapeSpec
import Cardano.KERI.Deployment.RegistryCollateralSpec qualified as RegistryCollateralSpec
import Cardano.KERI.Deployment.RegistryCommandDumpSpec qualified as RegistryCommandDumpSpec
import Cardano.KERI.Deployment.RegistryCommandSpec qualified as RegistryCommandSpec
import Cardano.KERI.Deployment.RegistryDeploySpec qualified as RegistryDeploySpec
import Cardano.KERI.Deployment.RegistryFilesSpec qualified as RegistryFilesSpec
import Cardano.KERI.Deployment.RegistryFoldHandoffSpec qualified as RegistryFoldHandoffSpec
import Cardano.KERI.Deployment.RegistryFoldSpec qualified as RegistryFoldSpec
import Cardano.KERI.Deployment.RegistryFoldV3Spec qualified as RegistryFoldV3Spec
import Cardano.KERI.Deployment.RegistryFutureDatumSpec qualified as RegistryFutureDatumSpec
import Cardano.KERI.Deployment.RegistryKoiosCommandSpec qualified as RegistryKoiosCommandSpec
import Cardano.KERI.Deployment.RegistryKoiosRecordedSpec qualified as RegistryKoiosRecordedSpec
import Cardano.KERI.Deployment.RegistryKoiosValidityEndSpec qualified as RegistryKoiosValidityEndSpec
import Cardano.KERI.Deployment.RegistryLegacyRecordCommandSpec qualified as RegistryLegacyRecordCommandSpec
import Cardano.KERI.Deployment.RegistryOneOutputSpec qualified as RegistryOneOutputSpec
import Cardano.KERI.Deployment.RegistryProviderSpec qualified as RegistryProviderSpec
import Cardano.KERI.Deployment.RegistryReadbackCommandSpec qualified as RegistryReadbackCommandSpec
import Cardano.KERI.Deployment.RegistryReadbackSpec qualified as RegistryReadbackSpec
import Cardano.KERI.Deployment.RegistryRegisterSpec qualified as RegistryRegisterSpec
import Cardano.KERI.Deployment.RegistryRegisterStagesSpec qualified as RegistryRegisterStagesSpec
import Cardano.KERI.Deployment.RegistryReplaySpec qualified as RegistryReplaySpec
import Cardano.KERI.Deployment.RegistryRequestSpec qualified as RegistryRequestSpec
import Cardano.KERI.Deployment.RegistryReturnCommandSpec qualified as RegistryReturnCommandSpec
import Cardano.KERI.Deployment.RegistryReturnSpec qualified as RegistryReturnSpec
import Cardano.KERI.Deployment.RegistryScriptsSpec qualified as RegistryScriptsSpec
import Cardano.KERI.Deployment.RegistryShortDepositSpec qualified as RegistryShortDepositSpec
import Cardano.KERI.Deployment.RegistrySnapshotSpec qualified as RegistrySnapshotSpec
import Cardano.KERI.Deployment.RegistryTransactionDumpSpec qualified as RegistryTransactionDumpSpec
import Cardano.KERI.Deployment.RegistryTransactionsSpec qualified as RegistryTransactionsSpec
import Cardano.KERI.Deployment.RegistryVaultSpec qualified as RegistryVaultSpec
import Cardano.KERI.Deployment.ScriptAritySpec qualified as ScriptAritySpec
import Cardano.KERI.Deployment.TopUpPackageSpec qualified as TopUpPackageSpec
import Cardano.KERI.Deployment.TopUpTransactionSpec qualified as TopUpTransactionSpec
import Cardano.KERI.Deployment.TransactionRuntimeSpec qualified as TransactionRuntimeSpec
import Cardano.KERI.Deployment.WalletHoldingSpec qualified as WalletHoldingSpec
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
    EndpointBoardSpec.spec
    EndpointBoardTransactionSpec.spec
    AdvancePackageSpec.spec
    FreezePackageSpec.spec
    TopUpPackageSpec.spec
    TopUpTransactionSpec.spec
    KELSpec.spec
    RegistrationEvidenceSpec.spec
    RegistryReadbackSpec.spec
    RegistryReadbackCommandSpec.spec
    RegistryFutureDatumSpec.spec
    KoiosReadsSpec.spec
    KoiosRegistryRuntimeSpec.spec
    KoiosSettlementSpec.spec
    KoiosSubmissionSpec.spec
    ManifestSpec.spec
    BountyEntitlementSpec.spec
    RegistrationSpec.spec
    RegistryScriptsSpec.spec
    AttestationBoundarySpec.spec
    RegistryFilesSpec.spec
    RegistryProviderSpec.spec
    RegistryKoiosCommandSpec.spec
    RegistryKoiosRecordedSpec.spec
    RegistryKoiosValidityEndSpec.spec
    RegistryDeploySpec.spec
    RegistrySnapshotSpec.spec
    RegistryRequestSpec.spec
    RegistryReturnSpec.spec
    RegistryReturnCommandSpec.spec
    RegistryShortDepositSpec.spec
    RegistryRegisterSpec.spec
    RegistryRegisterStagesSpec.spec
    WalletHoldingSpec.spec
    RegistryFoldSpec.spec
    RegistryReplaySpec.spec
    RegistryApplicationSpec.spec
    RegistryOneOutputSpec.spec
    RegistryCollateralSpec.spec
    RegistryCommandDumpSpec.spec
    RegistryTransactionDumpSpec.spec
    RegistryFoldV3Spec.spec
    RegistryFoldHandoffSpec.spec
    RegistryAttemptSpec.spec
    RegistryBookingCommandSpec.spec
    RegistryCommandSpec.spec
    RegistryTransactionsSpec.spec
    RegistryBookingShapeSpec.spec
    RegistryLegacyRecordCommandSpec.spec
    RegistryBookingEvaluationSpec.spec
    RegistryVaultSpec.spec
    ScriptAritySpec.spec
    TransactionRuntimeSpec.spec
