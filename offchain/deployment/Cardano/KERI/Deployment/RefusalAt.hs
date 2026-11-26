{- |
Module      : Cardano.KERI.Deployment.RefusalAt
Description : what the evaluation of a transaction said of one purpose, and what counts as the script's refusal

A refusal of a transaction counts as the refusal of a script only when that script ran and failed:
the ledger's typed validation failure at the purpose. A failure to set the script up, an acceptance, a
refusal at another purpose or a purpose the evaluation did not cover is not one. The journeys on a
devnet and the reports of the installed commands read their refusals through this one definition.
-}
module Cardano.KERI.Deployment.RefusalAt (
    Verdict (..),
    verdictAt,
    requireRefusedAt,
    purposeName,
    renderEvaluationFailure,
    evaluationRefusedAt,
) where

import Cardano.Ledger.Alonzo.Plutus.Evaluate (TransactionScriptFailure (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Data.List (isInfixOf)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map

-- | What the evaluation said of one purpose.
data Verdict
    = -- | the script ran and failed: the typed validation failure
      ExecutedFailure
    | -- | the ledger failed the purpose without running its script
      NotExecuted
    | -- | the purpose was accepted
      Accepted
    | -- | the evaluation did not cover the purpose
      NotCovered
    deriving stock (Eq, Show)

-- | The verdict of an evaluation at a purpose.
verdictAt :: (Ord p) => Map p (Either (TransactionScriptFailure ConwayEra) a) -> p -> Verdict
verdictAt answers purpose = case Map.lookup purpose answers of
    Nothing -> NotCovered
    Just (Right _) -> Accepted
    Just (Left ValidationFailure{}) -> ExecutedFailure
    Just (Left _) -> NotExecuted

-- | Fail unless the script of the purpose ran and refused the transaction.
requireRefusedAt :: (Ord p, Show p) => String -> Map p (Either (TransactionScriptFailure ConwayEra) a) -> p -> IO ()
requireRefusedAt label answers purpose = case verdictAt answers purpose of
    ExecutedFailure -> pure ()
    verdict ->
        fail (label <> ": expected the failure of a script that ran at " <> show purpose <> ", found " <> show verdict <> detail)
  where
    detail = case Map.lookup purpose answers of
        Just (Left failure) -> ": " <> take 300 (show failure)
        _ -> ""

-- | Where in a transaction the node's evaluation failed, in words: the kind of script purpose and its index.
purposeName :: ConwayPlutusPurpose AsIx ConwayEra -> String
purposeName = \case
    ConwayMinting (AsIx index) -> "minting purpose " <> show index
    ConwaySpending (AsIx index) -> "spending purpose " <> show index
    other -> show other

-- | The words of a failure of the evaluation at a purpose: the purpose, then the typed failure as it shows.
renderEvaluationFailure :: ConwayPlutusPurpose AsIx ConwayEra -> TransactionScriptFailure ConwayEra -> String
renderEvaluationFailure purpose failure = purposeName purpose <> ": " <> show failure

-- | Whether a report holds the executed script's refusal at the purpose.
evaluationRefusedAt :: ConwayPlutusPurpose AsIx ConwayEra -> String -> Bool
evaluationRefusedAt purpose = isInfixOf (purposeName purpose <> ": ValidationFailure")
