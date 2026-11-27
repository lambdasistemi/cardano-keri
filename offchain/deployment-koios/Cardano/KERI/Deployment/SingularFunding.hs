{- |
Module      : Cardano.KERI.Deployment.SingularFunding
Description : Singular's own choice of the output a transaction is funded and collateralised from, for the builders that may not depend on Singular

The registry transaction builders of "Cardano.KERI.Deployment.RegistryTransactions" take the choice of the seed, the
funding and the collateral as an argument, because the write composition may reach no edge to Singular's package.
This module is where the choice is Singular's: its 'adaOnlyOut' and its 'selectFunding', imported and not copied.
-}
module Cardano.KERI.Deployment.SingularFunding (singularFundingRules) where

import Cardano.KERI.Deployment.RegistryTransactions (FundingRules (..))
import Singular.Registry.TxBuilder.Publication (adaOnlyOut, selectFunding)

-- | The funding rules of public Singular.
singularFundingRules :: FundingRules
singularFundingRules = FundingRules{ruleAdaOnly = adaOnlyOut, ruleSelect = selectFunding}
