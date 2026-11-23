{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryRequestSpec
Description : the record of a booked request is read back from its datum, and only a request's datum reads back

The library writes the datum of a request; a fold reads it back. What it reads
is judged against records spelled here, and against datums that are not one.
-}
module Cardano.KERI.Deployment.RegistryRequestSpec (spec) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    Credential (..),
    HeldDatum (..),
    PlutusAddress (..),
    RegistrationData (..),
    RegistryIdentity (..),
    heldDatumData,
 )
import Cardano.KERI.Deployment.RegistryRequest
import Data.ByteString qualified as BS
import PlutusCore.Data (Data (..))
import Test.Hspec

record :: Int -> PlutusAddress -> PlutusAddress -> RegistrationData
record n refund holding =
    RegistrationData
        { requestRegistry = RegistryIdentity (BS.replicate 28 0x41) (BS.replicate 32 0x42)
        , requestKey = BS.replicate 32 (fromIntegral n)
        , requestController = BS.replicate 28 0x43
        , requestRefundAddress = refund
        , requestHoldingAddress = holding
        , requestInitialDatum = Constr 2 [B (BS.replicate 3 0x44), I (toInteger n * 7)]
        , requestDeposit = 1_009_000_000 + toInteger n
        , requestBookedAt = 1_800_000_010_000 + toInteger n
        , requestProcessDeadline = 1_800_000_100_000 + toInteger n
        , requestReclaimEnd = 1_800_000_100_000 + toInteger n
        }

keyAddress, scriptAddress, stakedAddress :: PlutusAddress
keyAddress = PlutusAddress (KeyCredential (BS.replicate 28 0x11)) Nothing
scriptAddress = PlutusAddress (ScriptCredential (BS.replicate 28 0x12)) Nothing
stakedAddress = PlutusAddress (KeyCredential (BS.replicate 28 0x13)) (Just (ScriptCredential (BS.replicate 28 0x14)))

spec :: Spec
spec = describe "#351 reading a booked request back" $ do
    it "reads the record a booking wrote, for several records, refund addresses and holding addresses" $
        mapM_
            ( \(n, refund, holding) ->
                let r = record n refund holding
                 in registrationOfDatum (heldDatumData (Registration r)) `shouldBe` Just r
            )
            [(1, keyAddress, scriptAddress), (2, stakedAddress, scriptAddress), (3, scriptAddress, keyAddress), (200, keyAddress, stakedAddress)]
    it "reads the datum of the configuration record as no request" $
        registrationOfDatum
            (heldDatumData (Configuration (ApplicationParameters 1_000_000 500_000 90_000 5_000) (ScriptCredential (BS.replicate 28 0x15))))
            `shouldBe` Nothing
    it "reads what is not a request's datum as none" $
        mapM_
            (\datum -> registrationOfDatum datum `shouldBe` Nothing)
            [ I 0
            , B "registration"
            , Constr 1 []
            , Constr 1 [Constr 0 [I 1]]
            , Constr 1 [Constr 0 (replicate 10 (I 0))]
            , Constr 3 [Constr 0 (replicate 10 (I 0))]
            ]
    it "reads a record with one field of another shape as none" $ do
        case heldDatumData (Registration (record 5 keyAddress scriptAddress)) of
            Constr 1 [Constr 0 fields] ->
                mapM_
                    ( \index ->
                        registrationOfDatum (Constr 1 [Constr 0 [if i == index then B "not what belongs here" else f | (i, f) <- zip [0 :: Int ..] fields]])
                            `shouldBe` Nothing
                    )
                    [0, 3, 4, 6, 7, 8, 9]
            other -> expectationFailure ("the datum of a request has another shape: " <> show other)
