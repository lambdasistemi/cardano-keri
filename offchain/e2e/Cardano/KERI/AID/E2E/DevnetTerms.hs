{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.AID.E2E.DevnetTerms
Description : the terms of the registry the devnet journey creates

One definition of the terms: the devnet journey applies them to the scripts of
its registry, and the identities page derives the scripts' hashes and sizes
from the same value.
-}
module Cardano.KERI.AID.E2E.DevnetTerms (
    devnetTerms,
) where

import Cardano.KERI.AID.Application (ApplicationParameters (..))
import Cardano.KERI.Deployment.Registry (RegistryTerms (..))
import Cardano.KERI.Deployment.Script (deployedCheckpointTerms)

-- | The terms of the devnet's registry: the deployed amounts and a short processing window.
devnetTerms :: RegistryTerms
devnetTerms =
    RegistryTerms
        { registryCheckpointTerms = deployedCheckpointTerms
        , registryParameters =
            ApplicationParameters
                { registrationCost = 1_000_000
                , minimumTip = 500_000
                , processTime = 90_000
                , bookingWidth = 5_000
                }
        }
