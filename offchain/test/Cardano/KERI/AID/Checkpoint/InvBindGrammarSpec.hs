{- |
Module      : Cardano.KERI.AID.Checkpoint.InvBindGrammarSpec
Description : INV-BIND: the grammar rows of the event object and of its anchor array

The ten structural cases of the gate's grammar table, as the exact bytes the Aiken reader receives
(`inv_bind_grammar.json`, written by `scripts/inv-bind-grammar-rows.mjs`), each signed by the committed
`reg_2key` controllers and observed against the registration binder. An accept row must be bound, a refuse row
must not. Every single-error JSON row has its declared length fixed up, except the size-mismatch row.
-}
module Cardano.KERI.AID.Checkpoint.InvBindGrammarSpec (spec) where

import Cardano.KERI.AID.Checkpoint.FixtureLoader (
    arrayField,
    decodeHex,
    loadFixture,
    textField,
 )
import Cardano.KERI.AID.Checkpoint.InvBindAdversarialSpec (
    IcpBase (..),
    Observation (..),
    Row (..),
    malformed,
    reg2key,
 )
import Control.Monad (forM_)
import Data.Text qualified as T
import Test.Hspec (Spec, describe, it, runIO, shouldBe)

spec :: Spec
spec = describe "INV-BIND grammar rows" $ do
    fixture <- runIO (loadFixture "inv_bind_grammar.json")
    registration <- runIO (loadFixture "registration.json")
    base <- runIO (either fail pure (reg2key registration))
    rows <- runIO (either fail pure (arrayField fixture "rows" >>= traverse decodeRow))
    it "starts from the committed 2-key inception, byte for byte" $
        (decodeHex =<< textField fixture "base_hex") `shouldBe` Right (ibRaw base)
    forM_ rows $ \(variant, expected, raw) -> do
        let observed = rowObservation (malformed variant base raw (ibEvidence base))
            wanted = if expected == "accept" then LegacyAccept else Rejected
        it (T.unpack variant <> " is " <> (if expected == "accept" then "bound" else "refused")) $
            observed `shouldBe` wanted
  where
    decodeRow row = do
        variant <- textField row "variant"
        expected <- textField row "expected"
        raw <- decodeHex =<< textField row "hex"
        pure (variant, expected, raw)
