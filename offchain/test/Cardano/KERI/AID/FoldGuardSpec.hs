{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.AID.FoldGuardSpec
Description : a second registration of a registered AID cannot be folded

The refusal is the builder's own, before any transaction is built: a request
whose key the registry holds is refused by name, wherever the key sits among
the held keys, and a new key is not refused whatever the registry holds.
-}
module Cardano.KERI.AID.FoldGuardSpec (spec) where

import Cardano.KERI.AID.E2E.FoldGuard (FoldRefusal (..), foldRefusal)
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
    specRejection

specFold :: Spec
specFold = describe "a second registration of a registered AID cannot be folded" $ do
    it "refuses a key the registry holds, whichever place it has among the held keys" $
        mapM_
            (\key -> foldRefusal held key `shouldBe` Just (KeyAlreadyRegistered key))
            held
    it "refuses the only key of a registry of one" $
        foldRefusal [alice] alice `shouldBe` Just (KeyAlreadyRegistered alice)
    it "does not refuse a new key, whatever the registry holds" $ do
        foldRefusal held dave `shouldBe` Nothing
        foldRefusal [alice] bob `shouldBe` Nothing
    it "does not refuse the first key of an empty registry" $
        foldRefusal [] alice `shouldBe` Nothing
    it "names the key it refuses" $
        foldRefusal [bob, alice] alice `shouldBe` Just (KeyAlreadyRegistered alice)

-- | A rejection as the node renders it: the consumed input, then the imbalance.
rejection :: String -> [String] -> String
rejection inputs others =
    "HardForkApplyTxErrFromEra S (Z (WrapApplyTxErr {unwrapApplyTxErr = ConwayApplyTxError ("
        <> "ConwayUtxowFailure (UtxoFailure (BadInputsUTxO (NonEmptySet (fromList ["
        <> inputs
        <> "])))) :| ["
        <> intercalate ", " others
        <> "])}))"

imbalance, validityFailure :: String
imbalance =
    "ConwayUtxowFailure (UtxoFailure (ValueNotConservedUTxO Mismatch (RelEQ) {supplied: A, expected: B}))"
validityFailure =
    "ConwayUtxowFailure (UtxoFailure (OutsideValidityIntervalUTxO (ValidityInterval {}) (SlotNo 9)))"

specRejection :: Spec
specRejection = describe "a rejection is read as a whole set" $ do
    it "accepts the consumed input and the imbalance that follows, and nothing else" $
        consumedInputAlone "state" (rejection "state" [imbalance]) `shouldBe` True
    it "refuses another input" $
        consumedInputAlone "state" (rejection "proof" [imbalance]) `shouldBe` False
    it "refuses two inputs" $
        consumedInputAlone "state" (rejection "state,proof" [imbalance]) `shouldBe` False
    it "refuses a further failure of another kind" $
        consumedInputAlone "state" (rejection "state" [imbalance, validityFailure]) `shouldBe` False
    it "refuses a different second failure" $
        consumedInputAlone "state" (rejection "state" [validityFailure]) `shouldBe` False
    it "refuses a rejection that does not name a consumed input" $
        consumedInputAlone "state" imbalance `shouldBe` False
