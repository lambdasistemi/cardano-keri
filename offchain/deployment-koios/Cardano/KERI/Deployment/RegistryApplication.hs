{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryApplication
Description : The KERI application, as public Singular's fold drives it

Singular's fold discovers booked requests from the public approvals, rebuilds the
registry's state from the public history, takes the registry transition, the tip-based
window and the confirmation, and asks the application for three things: how a request
is read from public data, what the batch spends and burns, and which outputs carry its
code. This module gives them for a KERI registry. The registrations are the only
requests it reads: a booked termination is not decoded, so the fold leaves it unspent
and reports it as one the application did not accept.
-}
module Cardano.KERI.Deployment.RegistryApplication (
    keriApplication,
) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    RegistrationData (..),
    SpendAction (..),
    configurationTokenName,
    spendActionData,
 )
import Cardano.KERI.Deployment.Registry (RegistryScripts (..), RegistryTerms (..))
import Cardano.KERI.Deployment.RegistryReplay (singularIdentity)
import Cardano.KERI.Deployment.RegistryRequest (registrationOfOutput)
import Cardano.KERI.Deployment.RegistryTransactions (
    RegistryDeployment (..),
    RegistryReferences (..),
    applicationAddress,
    applicationPolicyId,
    ledgerAddressOf,
 )
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, valueTxOutL)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Mary.Value (AssetName (..), MaryValue (..), MultiAsset (..))
import Cardano.Tx.Build qualified as Tx
import Control.Monad (forM_, guard)
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Lens.Micro ((^.))
import PlutusCore.Data (Data (List))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import Singular.State.Fold (
    Application (..),
    Folded (..),
    Registration (..),
    Request (..),
 )

-- | The application of a registry the files name, with the outputs that carry its code and configuration.
keriApplication :: RegistryDeployment -> RegistryReferences -> Application
keriApplication deployment references =
    Application
        { appPolicy = policy
        , appDecode = \_ _ out -> decode out
        , appIsConfiguration = isConfiguration
        , appReferences = [referenceApplication references, referenceConfiguration references]
        , appFold = fold
        }
  where
    policy = applicationPolicyId deployment
    registry = scriptsRegistry (deploymentScripts deployment)

    -- a booked registration, as the booking wrote it, at the application's payment credential (the validators
    -- read the payment credential alone, so a stake reference is the booker's own): nothing else is a request of this application
    decode out = do
        guard (paymentOf (out ^. addrTxOutL) == paymentOf (applicationAddress deployment))
        record <- registrationOfOutput out
        holding <- ledgerAddressOf (deploymentNetwork deployment) (requestHoldingAddress record)
        pure . RegistrationRequest $
            Registration
                { regRegistry = singularIdentity (requestRegistry record)
                , regKey = requestKey record
                , regHolding = holding
                , regDatum = requestInitialDatum record
                , regDeposit = Coin (requestDeposit record)
                , regDeadline = requestProcessDeadline record
                }

    paymentOf = \case
        Addr _ payment _ -> Just payment
        _ -> Nothing

    -- the output that holds the registry's configuration token
    isConfiguration out = case out ^. valueTxOutL of
        MaryValue _ (MultiAsset assets) ->
            (Map.lookup policy assets >>= Map.lookup configurationName) == Just 1
    configurationName = AssetName (SBS.toShort (configurationTokenName registry))

    -- each request is spent with the fold action naming the output that holds its key's token, each approval
    -- is burned, and the application's code and the configuration are read by reference
    fold folded = do
        forM_ folded $ \request ->
            Tx.spendScript
                (foldedRequest request)
                (BuiltinData (spendActionData (FoldRegistration (maybe 0 toInteger (foldedHolding request)))))
        Tx.mint policy (Map.fromListWith (+) [(foldedApproval request, -1) | request <- folded]) (BuiltinData (List []))
        Tx.reference (fst (referenceApplication references))
        Tx.reference (fst (referenceConfiguration references))
        -- the treasury is paid the registration cost of each folded request
        Tx.donateToTreasury (Coin (fromIntegral (length folded) * registrationCost (registryParameters (deploymentTerms deployment))))
