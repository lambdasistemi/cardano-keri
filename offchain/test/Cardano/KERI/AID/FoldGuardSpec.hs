{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.FoldGuardSpec
Description : a second registration of a registered AID cannot be folded

The refusal is the builder's own, before any transaction is built: a request
whose key the registry holds is refused by name, wherever the key sits among
the held keys, and a new key is not refused whatever the registry holds.
-}
module Cardano.KERI.AID.FoldGuardSpec (spec) where

import Cardano.KERI.AID.E2E.FoldGuard (
    BookingRefusal (..),
    FoldRefusal (..),
    bookingRefusal,
    foldRefusal,
 )
import Cardano.KERI.AID.E2E.Rejection (consumedInputAlone)
import Data.ByteString (ByteString)
import Data.List (intercalate)
import Test.Hspec (Spec, describe, it, shouldBe)

alice, bob, carol, dave :: ByteString
alice = "EAliceAid"
bob = "EBobAid"
carol = "ECarolAid"
dave = "EDaveAid"

-- | Three identities already registered.
held :: [ByteString]
held = [alice, bob, carol]

spec :: Spec
spec = do
    specFold
    specTerminal
    specBooking
    specRejection

specFold :: Spec
specFold = describe "a second registration of a registered AID cannot be folded" $ do
    it "refuses a key the registry holds, whichever place it has among the held keys" $
        mapM_
            (\key -> foldRefusal held [] key `shouldBe` Just (KeyAlreadyRegistered key))
            held
    it "refuses the only key of a registry of one" $
        foldRefusal [alice] [] alice `shouldBe` Just (KeyAlreadyRegistered alice)
    it "does not refuse a new key, whatever the registry holds" $ do
        foldRefusal held [] dave `shouldBe` Nothing
        foldRefusal [alice] [] bob `shouldBe` Nothing
    it "does not refuse the first key of an empty registry" $
        foldRefusal [] [] alice `shouldBe` Nothing
    it "names the key it refuses" $
        foldRefusal [bob, alice] [] alice `shouldBe` Just (KeyAlreadyRegistered alice)

-- | Two identities whose registrations were terminated.
gone :: [ByteString]
gone = [erin, frank]

erin, frank :: ByteString
erin = "EErinAid"
frank = "EFrankAid"

specTerminal :: Spec
specTerminal = describe "a registration of a terminal key cannot be folded" $ do
    it "refuses a terminal key, whichever place it has among the terminated keys" $
        mapM_
            (\key -> foldRefusal held gone key `shouldBe` Just (KeyIsTerminal key))
            gone
    it "refuses a terminal key of a registry that holds no active key" $
        foldRefusal [] [erin] erin `shouldBe` Just (KeyIsTerminal erin)
    it "still refuses an active key beside terminated ones, and names it as active" $
        foldRefusal held gone bob `shouldBe` Just (KeyAlreadyRegistered bob)
    it "does not refuse a new key beside terminated ones" $
        foldRefusal held gone dave `shouldBe` Nothing

specBooking :: Spec
specBooking = describe "the termination of a key is booked only from a pending output" $ do
    it "does not refuse a key with a pending output, whichever place it has among the pending keys" $
        mapM_ (\key -> bookingRefusal held key `shouldBe` Nothing) held
    it "refuses a key with no pending output, and names it" $
        bookingRefusal held dave `shouldBe` Just (NoPendingOutput dave)
    it "refuses every key when no checkpoint is pending" $
        mapM_ (\key -> bookingRefusal [] key `shouldBe` Just (NoPendingOutput key)) held
    it "refuses a terminal key, whose active token no pending output holds" $
        mapM_ (\key -> bookingRefusal held key `shouldBe` Just (NoPendingOutput key)) gone

-- | A rejection as the node renders it: the inputs that are gone, then the failures that follow.
rejection :: String -> [String] -> String
rejection inputs others =
    "HardForkApplyTxErrFromEra S (Z (WrapApplyTxErr {unwrapApplyTxErr = ConwayApplyTxError ("
        <> "ConwayUtxowFailure (UtxoFailure (BadInputsUTxO (NonEmptySet (fromList ["
        <> inputs
        <> "])))) :| ["
        <> intercalate ", " others
        <> "])}))"

imbalance, translation, redeemer, validityFailure :: String
imbalance =
    "ConwayUtxowFailure (UtxoFailure (ValueNotConservedUTxO Mismatch (RelEQ) {supplied: A, expected: B}))"
translation = translationOf "state"
redeemer = redeemerAt (2 :: Int)
validityFailure =
    "ConwayUtxowFailure (UtxoFailure (OutsideValidityIntervalUTxO (ValidityInterval {}) (SlotNo 9)))"

translationOf :: String -> String
translationOf input =
    "ConwayUtxowFailure (UtxoFailure (UtxosFailure (CollectErrors (BadTranslation (BabbageContextError (AlonzoContextError (TranslationLogicMissingInput ("
        <> input
        <> "))))) :| [])))"

redeemerAt :: Int -> String
redeemerAt index =
    "ConwayUtxowFailure (ExtraRedeemers (ConwaySpending (AsIx {unAsIx = " <> show index <> "}) :| []))"

-- | What a transaction that spends a consumed input is rejected for, and nothing else.
whole :: [String]
whole = [imbalance, translation, redeemer]

specRejection :: Spec
specRejection = describe "a rejection is read as a whole set" $ do
    it "accepts the consumed input and the failures that follow from it, and nothing else" $
        consumedInputAlone "state" 2 (rejection "state" whole) `shouldBe` True
    it "refuses another input" $
        consumedInputAlone "state" 2 (rejection "proof" whole) `shouldBe` False
    it "refuses two inputs" $
        consumedInputAlone "state" 2 (rejection "state,proof" whole) `shouldBe` False
    it "refuses a further failure of another kind" $
        consumedInputAlone "state" 2 (rejection "state" (whole <> [validityFailure])) `shouldBe` False
    it "refuses a different failure in place of one that follows" $
        consumedInputAlone "state" 2 (rejection "state" [imbalance, translation, validityFailure])
            `shouldBe` False
    it "refuses a missing failure" $
        consumedInputAlone "state" 2 (rejection "state" [imbalance, translation]) `shouldBe` False
    it "refuses a translation failure that names another input" $
        consumedInputAlone "state" 2 (rejection "state" [imbalance, translationOf "proof", redeemer])
            `shouldBe` False
    it "refuses a redeemer of another spend" $
        consumedInputAlone "state" 2 (rejection "state" [imbalance, translation, redeemerAt 1])
            `shouldBe` False
    it "refuses a rejection that does not name a consumed input" $
        consumedInputAlone "state" 2 imbalance `shouldBe` False
