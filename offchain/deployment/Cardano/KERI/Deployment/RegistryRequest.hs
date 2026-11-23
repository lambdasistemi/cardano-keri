{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryRequest
Description : Read a booked registration request back from its output

A booking writes the record of a request as the inline datum of an output at the
application's address. A fold is given only that output's reference, so it reads
the record back: the registry it names, the key, the refund address, the
committed deposit and the deadline.
-}
module Cardano.KERI.Deployment.RegistryRequest (
    registrationOfDatum,
    registrationOfOutput,
) where

import Cardano.KERI.AID.Application (
    Credential (..),
    PlutusAddress (..),
    RegistrationData (..),
    RegistryIdentity (..),
 )
import Cardano.KERI.AID.E2E.Datum (rawInlineData)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Conway (ConwayEra)
import PlutusCore.Data (Data (..))

{- | The record a datum is, when it is the datum of a booked request: the shape
'Cardano.KERI.AID.Application.heldDatumData' writes for a registration.
-}
registrationOfDatum :: Data -> Maybe RegistrationData
registrationOfDatum = \case
    Constr 1 [Constr 0 [registry, B key, B controller, refund, holding, initial, I deposit, I booked, I deadline, I reclaim]] ->
        RegistrationData
            <$> identityOf registry
            <*> pure key
            <*> pure controller
            <*> addressOf refund
            <*> addressOf holding
            <*> pure initial
            <*> pure deposit
            <*> pure booked
            <*> pure deadline
            <*> pure reclaim
    _ -> Nothing
  where
    identityOf = \case
        Constr 0 [B policy, B name] -> Just (RegistryIdentity policy name)
        _ -> Nothing
    addressOf = \case
        Constr 0 [payment, stake] -> PlutusAddress <$> credentialOf payment <*> stakeOf stake
        _ -> Nothing
    credentialOf = \case
        Constr 0 [B hash] -> Just (KeyCredential hash)
        Constr 1 [B hash] -> Just (ScriptCredential hash)
        _ -> Nothing
    stakeOf = \case
        Constr 1 [] -> Just Nothing
        Constr 0 [Constr 0 [credential]] -> Just <$> credentialOf credential
        _ -> Nothing

-- | The record an output holds as its inline datum.
registrationOfOutput :: TxOut ConwayEra -> Maybe RegistrationData
registrationOfOutput out = rawInlineData out >>= registrationOfDatum
