{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.LedgerEvaluation
Description : the ledger's own script evaluation of a built transaction, and the negative control that names its cause

A transaction a builder wrote is handed to the ledger's script evaluator ('evalTxExUnits'), under the protocol
parameters and cost models recorded from the preprod node, against the outputs it spends and reads. The answer
of each purpose is its typed failure or acceptance, so a refusal is attributed to the purpose and to the
execution of a script, not to a failure of the set-up. A negative control edits a transaction that the ledger
accepts, and requires the edit to be applied, refused at the purposes it is meant to be refused at and
accepted at the others.
-}
module Cardano.KERI.Deployment.LedgerEvaluation (
    parameters,
    systemStart,
    evaluated,
    measuredBudgets,
    Answers,
    accepts,
    Purpose (..),
    purposeOf,
    refusedAt,
    setUpFailureAt,
    acceptedAt,
    Judgement (..),
    judge,
    negative,
    withMint,
    onPolicy,
    mintOf,
) where

import Cardano.KERI.Deployment.RefusalAt (Verdict (..), verdictAt)
import Cardano.KERI.Deployment.RegistryTransactions (mintingIndex)
import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (..), evalTxExUnits)
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (inputsTxBodyL, mintTxBodyL)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.BaseTypes (natVersion)
import Cardano.Ledger.Binary (decodeFull')
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (PParams)
import Cardano.Ledger.Mary.Value (AssetName (..), MultiAsset (..), PolicyID (..))
import Cardano.Ledger.Plutus.ExUnits (ExUnits)
import Cardano.Ledger.State (UTxO (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Slotting.EpochInfo (fixedEpochInfo)
import Cardano.Slotting.Slot (EpochSize (..))
import Cardano.Slotting.Time (SystemStart (..), mkSlotLength)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.Either (isRight)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Lens.Micro ((%~), (&), (^.))
import Paths_cardano_keri (getDataFileName)
import Test.Hspec (shouldBe)

-- | The preprod protocol parameters of the node the protocol major 11 runs on.
parameters :: IO (PParams ConwayEra)
parameters = do
    path <- getDataFileName "deployment-test/fixtures/koios/preprod-protocol-parameters.cbor"
    bytes <- BS.readFile path
    either (fail . show) pure (decodeFull' (natVersion @11) bytes)

{- | Slot 1,000 is the instant the specs' interval starts at, and a slot is a
second.
-}
systemStart :: SystemStart
systemStart = SystemStart (posixSecondsToUTCTime (fromIntegral ((1_700_000_000 :: Integer) - 1_000)))

-- | The execution units the ledger measures for each purpose of the transaction, or the typed failure it gives.
measuredBudgets ::
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    Map (ConwayPlutusPurpose AsIx ConwayEra) (Either (TransactionScriptFailure ConwayEra) ExUnits)
measuredBudgets params utxo tx =
    evalTxExUnits params tx (UTxO utxo) (fixedEpochInfo (EpochSize 432_000) (mkSlotLength 1)) systemStart

-- | Every purpose of the transaction as the ledger answers it: the typed failure it gives, not its text.
evaluated ::
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    Answers
evaluated params utxo tx =
    Map.map
        void
        (evalTxExUnits params tx (UTxO utxo) (fixedEpochInfo (EpochSize 432_000) (mkSlotLength 1)) systemStart)

-- | The ledger's answer for each purpose of a transaction: its typed script failure, or acceptance.
type Answers = Map (ConwayPlutusPurpose AsIx ConwayEra) (Either (TransactionScriptFailure ConwayEra) ())

accepts :: Answers -> Bool
accepts answers = not (Map.null answers) && all isRight (Map.elems answers)

-- | A purpose an edit is meant to be refused at, or must leave accepted.
data Purpose = Minting PolicyID | SpendingOf TxIn

purposeOf :: ConwayTx -> Purpose -> ConwayPlutusPurpose AsIx ConwayEra
purposeOf tx = \case
    Minting policy -> ConwayMinting (AsIx (mintingIndex policy (tx ^. bodyTxL . mintTxBodyL)))
    SpendingOf ref -> ConwaySpending (AsIx (fromIntegral (Set.findIndex ref (tx ^. bodyTxL . inputsTxBodyL))))

{- | Whether the script of the purpose ran and failed: the ledger's typed validation failure at that
purpose. A failure of the set-up, of the translation of the transaction, of balancing or of another
purpose is not one.
-}
refusedAt :: ConwayTx -> Answers -> Purpose -> Bool
refusedAt tx answers purpose = verdictAt answers (purposeOf tx purpose) == ExecutedFailure

-- | Whether the ledger failed the purpose without running its script: a failure of the set-up or of the translation.
setUpFailureAt :: ConwayTx -> Answers -> Purpose -> Bool
setUpFailureAt tx answers purpose = verdictAt answers (purposeOf tx purpose) == NotExecuted

acceptedAt :: ConwayTx -> Answers -> Purpose -> Bool
acceptedAt tx answers purpose = Map.lookup (purposeOf tx purpose) answers == Just (Right ())

{- | What a negative control found: the untouched transaction accepted; the edit applied; each purpose
it is meant to be refused at refused by an executed script; each purpose it must leave accepted accepted.
-}
data Judgement = Judgement
    { positiveAccepted :: Bool
    , editApplied :: Bool
    , refusedAsMeant :: Bool
    , keptAsMeant :: Bool
    }
    deriving stock (Eq, Show)

judge ::
    (Eq a) =>
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    -- | the edit
    (ConwayTx -> ConwayTx) ->
    -- | what the edit is meant to change, read from the transaction
    (ConwayTx -> a) ->
    -- | the purposes it is meant to be refused at
    [Purpose] ->
    -- | the purposes that stay accepted
    [Purpose] ->
    Judgement
judge params utxo original edit changed refusedPurposes keptPurposes =
    Judgement
        { positiveAccepted = accepts (evaluated params utxo original)
        , editApplied = changed tampered /= changed original
        , refusedAsMeant = all (refusedAt original answers) refusedPurposes
        , keptAsMeant = all (acceptedAt original answers) keptPurposes
        }
  where
    tampered = edit original
    answers = evaluated params utxo tampered

-- | A negative control that cannot pass for the wrong reason: every part of the judgement holds.
negative ::
    (Eq a) =>
    PParams ConwayEra ->
    Map TxIn (TxOut ConwayEra) ->
    ConwayTx ->
    (ConwayTx -> ConwayTx) ->
    (ConwayTx -> a) ->
    [Purpose] ->
    [Purpose] ->
    IO ()
negative params utxo original edit changed refusedPurposes keptPurposes =
    judge params utxo original edit changed refusedPurposes keptPurposes
        `shouldBe` Judgement{positiveAccepted = True, editApplied = True, refusedAsMeant = True, keptAsMeant = True}

-- | The mint of a transaction, edited.
withMint :: (Map PolicyID (Map AssetName Integer) -> Map PolicyID (Map AssetName Integer)) -> ConwayTx -> ConwayTx
withMint edit tx = tx & bodyTxL . mintTxBodyL %~ (\(MultiAsset assets) -> MultiAsset (edit assets))

-- | One policy's tokens in a mint, edited.
onPolicy :: PolicyID -> (Map AssetName Integer -> Map AssetName Integer) -> Map PolicyID (Map AssetName Integer) -> Map PolicyID (Map AssetName Integer)
onPolicy policy edit = Map.adjust edit policy

mintOf :: ConwayTx -> MultiAsset
mintOf tx = tx ^. bodyTxL . mintTxBodyL
