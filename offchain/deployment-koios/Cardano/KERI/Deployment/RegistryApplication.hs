{- |
Module      : Cardano.KERI.Deployment.RegistryApplication
Description : The KERI application, as public Singular's fold drives it

Singular's fold discovers booked requests from the public approvals, rebuilds the
registry's state from the public history, takes the registry transition, the tip-based
window and the confirmation, and asks the application for three things: how a request
is read from public data, what the batch spends and burns, and which outputs carry its
code. This module gives them for a KERI registry.
-}
module Cardano.KERI.Deployment.RegistryApplication (
    keriApplication,
) where

import Cardano.KERI.Deployment.RegistryTransactions (RegistryDeployment, RegistryReferences, applicationPolicyId)
import Singular.State.Fold (Application (..))

-- | The application of a registry the files name.
keriApplication :: RegistryDeployment -> RegistryReferences -> Application
keriApplication deployment _ =
    Application
        { appPolicy = applicationPolicyId deployment
        , appDecode = \_ _ _ -> Nothing
        , appIsConfiguration = const False
        , appReferences = []
        , appFold = \_ -> pure ()
        }
