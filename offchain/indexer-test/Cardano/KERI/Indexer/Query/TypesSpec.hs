{- |
Module      : Cardano.KERI.Indexer.Query.TypesSpec
Description : #176 PROVE-LIST 3 — qb64Witness against an independent literal oracle

Every 'Cardano.KERI.Indexer.Query.Types.qb64Witness' call site in
"Cardano.KERI.Indexer.Query.ServerSpec" builds its "expected" JSON by calling
the very function under test, which proves internal consistency, not
correctness of the B-code bit-manipulation itself. This spec instead checks
'qb64Witness' against a byte literal computed independently, by hand,
without calling 'qb64Witness'.
-}
module Cardano.KERI.Indexer.Query.TypesSpec (spec) where

import Cardano.KERI.Indexer.Query.Types (qb64Witness)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
    describe "Cardano.KERI.Indexer.Query.Types.qb64Witness (independent literal oracle)" $
        it "renders 32 zero bytes as the hand-derived B-code qb64 literal" $
            qb64Witness (BS.replicate 32 0) `shouldBe` expected
  where
    {- Hand-derived, not via 'qb64Witness': the qb64 encoding is
    @base64url(0x00 <> key)@ with the leading (always-'A') character
    replaced by the code byte. For a 32-zero-byte key, @0x00 <> key@ is 33
    zero bytes; 33 bytes is exactly 264 bits = 44 base64 sextets, and every
    sextet of an all-zero byte string is 0, which base64url renders as 'A'
    (ASCII 65) — so the un-coded qb64 body is 44 'A' characters. The CESR
    B-code (non-transferable Ed25519 witness key) lead byte 'B' (ASCII 66)
    then replaces only the first of those 44 characters.
    -}
    expected :: ByteString
    expected = BS.cons 66 (BS.replicate 43 65)
