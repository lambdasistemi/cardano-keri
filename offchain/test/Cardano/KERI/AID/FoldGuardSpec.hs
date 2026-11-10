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
import Data.ByteString (ByteString)
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
spec = describe "a second registration of a registered AID cannot be folded" $ do
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
