{- |
Module      : Cardano.KERI.AID.Checkpoint.DatumV2Spec
Description : The version 2 checkpoint datum wire against the Lean vectors

Each accepted row of @lean\/checkpoint-datum-vectors.json@ whose input is spelled
out below must serialise to exactly the datum bytes the Lean declares, and the
bytes must read back into the same value. The expected bytes are the Lean's
(copied from the vectors), never produced by the encoder under test.
-}
module Cardano.KERI.AID.Checkpoint.DatumV2Spec (
    spec,
) where

import Cardano.KERI.AID.CESR (
    aidDigest,
    qb64Aid,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    CheckpointDatumV2 (..),
    DatumError (..),
    KeyMaterial (..),
    canonicalCbor,
    checkpointDatumFromData,
    checkpointDatumToData,
    datumKeyState,
    datumV2WellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString.Char8 qualified as BC
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

fromHex :: ByteString -> ByteString
fromHex h = either error id (convertFromBase Base16 h)

aidText :: ByteString
aidText = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"

refundTo :: ByteString
refundTo =
    fromHex
        "0104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9"

keys :: KeyMaterial
keys =
    KeyMaterial
        { kmCurKeys =
            [ fromHex
                "1f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8"
            ]
        , kmCurThreshold = Unweighted 1
        , kmNextKeys =
            [ fromHex
                "3e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017"
            ]
        , kmNextThreshold = Unweighted 1
        , kmWitnesses = []
        , kmToad = 0
        }

live :: Integer -> Integer -> Bool -> CheckpointDatumV2
live sn epoch frozen = liveOf aidText sn epoch frozen 100 keys

liveOf ::
    ByteString -> Integer -> Integer -> Bool -> Integer -> KeyMaterial -> CheckpointDatumV2
liveOf aid sn epoch frozen bornAt material =
    Live
        { lvAid = aid
        , lvSn = sn
        , lvEpoch = epoch
        , lvPoisoned = False
        , lvFrozen = frozen
        , lvBornAt = bornAt
        , lvRefundTo = refundTo
        , lvKeys = material
        }

pending :: CheckpointDatumV2
pending =
    TerminationPending{tpAid = aidText, tpSn = 4, tpEpoch = 2, tpKeys = keys}

-- | (Lean vector id, value, the datum bytes the Lean declares)
rows :: [(String, CheckpointDatumV2, ByteString)]
rows =
    [ ("registered-funded", live 0 0 False, fromHex "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500000d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff")
    , ("frozen", live 4 2 True, fromHex "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87a80186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff")
    , ("pending-termination", pending, fromHex "d87a9fd87a9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff")
    ]

spec :: Spec
spec = describe "version 2 checkpoint datum" $ do
    describe "wire against the Lean vectors" $ do
        mapM_
            ( \(name, value, bytes) ->
                it ("writes the Lean bytes of " <> name) $
                    canonicalCbor (V2 value) `shouldBe` bytes
            )
            rows
        mapM_
            ( \(name, value, _) ->
                it ("reads back " <> name) $
                    checkpointDatumFromData (checkpointDatumToData (V2 value))
                        `shouldBe` Just (V2 value)
            )
            rows
    describe "write-time validity" $ do
        it "accepts the vector rows" $
            map (\(_, value, _) -> datumV2WellFormed value) rows
                `shouldBe` replicate (length rows) (Right ())
        it "refuses a negative sequence number" $
            datumV2WellFormed (live (-1) 0 False) `shouldBe` Left NegativeSn
        it "refuses a negative epoch" $
            datumV2WellFormed (live 0 (-1) False) `shouldBe` Left NegativeEpoch
        it "refuses a negative birth time" $
            datumV2WellFormed (liveOf aidText 0 0 False (-1) keys)
                `shouldBe` Left NegativeBornAt
        it "refuses key material with a toad beyond its witnesses" $
            datumV2WellFormed (liveOf aidText 0 0 False 100 keys{kmToad = 1})
                `shouldBe` Left ToadRange
    describe "identifier text" $ do
        it "is the E-code text of a 32-byte digest" $
            (qb64Aid <$> aidDigest aidText) `shouldBe` Just aidText
        it "yields the key state a reader sees" $
            fmap cdNativeSn (datumKeyState (V2 (live 4 2 True)))
                `shouldBe` Just 4
        it "reads the epoch as the checkpoint counter" $
            fmap cdSeq (datumKeyState (V2 pending)) `shouldBe` Just 2
        it "refuses a malformed identifier" $
            datumKeyState (V2 (liveOf (BC.pack "not an aid") 0 0 False 100 keys))
                `shouldBe` Nothing
