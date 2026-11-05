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
    CheckpointDatumV2 (..),
    DatumError (..),
    KeyMaterial (..),
    KeyStateView (..),
    canonicalCbor,
    checkpointDatumFromData,
    checkpointDatumToData,
    datumKeyState,
    datumV2WellFormed,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import PlutusCore.Data (Data (..))
import Test.Hspec (
    Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

lastMay :: [a] -> Maybe a
lastMay [] = Nothing
lastMay xs = Just (last xs)

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
        , lvToppedUp = False
        , lvKeys = material
        }

{- | The Lean's row `topped-up`: the mark set, weighted current threshold,
three witnesses.
-}
toppedUp :: CheckpointDatumV2
toppedUp =
    Live
        { lvAid = "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
        , lvSn = 7
        , lvEpoch = 3
        , lvPoisoned = False
        , lvFrozen = False
        , lvBornAt = 100
        , lvRefundTo = refundTo
        , lvToppedUp = True
        , lvKeys =
            KeyMaterial
                { kmCurKeys =
                    [ fromHex "5d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f0f7fe050c131a21282f36"
                    , fromHex "7c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080f161d242b323940474e55"
                    , fromHex "9ba2a9b0b7bec5ccd3dae1e8eff6fd040b121920272e353c434a51585f666d74"
                    ]
                , kmCurThreshold = Weighted [[Weight 1 2, Weight 1 2], [Weight 1 1]]
                , kmNextKeys =
                    [ fromHex "bac1c8cfd6dde4ebf2f900070e151c232a31383f464d545b626970777e858c93"
                    , fromHex "d9e0e7eef5fc030a11181f262d343b424950575e656c737a81888f969da4abb2"
                    ]
                , kmNextThreshold = Unweighted 2
                , kmWitnesses =
                    [ fromHex "f8ff060d141b222930373e454c535a61686f767d848b9299a0a7aeb5bcc3cad1"
                    , fromHex "171e252c333a41484f565d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f0"
                    , fromHex "363d444b525960676e757c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080f"
                    ]
                , kmToad = 2
                }
        }

pending :: CheckpointDatumV2
pending =
    TerminationPending{tpAid = aidText, tpSn = 4, tpEpoch = 2}

-- | (Lean vector id, value, the datum bytes the Lean declares)
rows :: [(String, CheckpointDatumV2, ByteString)]
rows =
    [ ("registered-funded", live 0 0 False, fromHex "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500000d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff")
    , ("frozen", live 4 2 True, fromHex "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87a80186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff")
    , ("topped-up", toppedUp, fromHex "d87a9fd8799f582c4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f0703d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87a80d8799f9f58205d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f0f7fe050c131a21282f3658207c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080f161d242b323940474e5558209ba2a9b0b7bec5ccd3dae1e8eff6fd040b121920272e353c434a51585f666d74ffd87a9f9f9fd8799f0102ffd8799f0102ffff9fd8799f0101ffffffff9f5820bac1c8cfd6dde4ebf2f900070e151c232a31383f464d545b626970777e858c935820d9e0e7eef5fc030a11181f262d343b424950575e656c737a81888f969da4abb2ffd8799f02ff9f5820f8ff060d141b222930373e454c535a61686f767d848b9299a0a7aeb5bcc3cad15820171e252c333a41484f565d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f05820363d444b525960676e757c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080fff02ffffff")
    , ("pending-termination", pending, fromHex "d87a9fd87a9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402ffff")
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
    describe "outer constructor 0 is refused" $ do
        it "refuses the nine-field record under constructor 0" $
            checkpointDatumFromData
                ( Constr
                    0
                    [ Constr
                        0
                        [ B (BS.replicate 32 0xaa)
                        , List [B (BS.replicate 32 0x01)]
                        , Constr 0 [I 1]
                        , List [B (BS.replicate 32 0x0a)]
                        , Constr 0 [I 1]
                        , List []
                        , I 0
                        , I 0
                        , I 0
                        ]
                    ]
                )
                `shouldBe` Nothing
        it "refuses a version 2 body under constructor 0" $
            case checkpointDatumToData (V2 (live 4 2 False)) of
                Constr 1 body ->
                    checkpointDatumFromData (Constr 0 body)
                        `shouldBe` Nothing
                other -> expectationFailure ("not a version 2 datum: " <> show other)
    describe "identifier text" $ do
        it "is the E-code text of a 32-byte digest" $
            (qb64Aid <$> aidDigest aidText) `shouldBe` Just aidText
        it "yields the key state a reader sees" $
            fmap cdNativeSn (datumKeyState (V2 (live 4 2 True)))
                `shouldBe` Just 4
        it "reads the epoch as the checkpoint counter" $
            fmap cdSeq (datumKeyState (V2 (live 4 2 False))) `shouldBe` Just 2
        it "has no key state for a pending termination: it is no active checkpoint" $
            datumKeyState (V2 pending) `shouldBe` Nothing
        it "refuses the earlier four-field pending layout (Lean pending-with-keys)" $
            case checkpointDatumToData (V2 (live 4 2 False)) of
                Constr 1 [Constr 0 fields]
                    | Just withKeys <- lastMay fields ->
                        checkpointDatumFromData
                            ( Constr
                                1
                                [Constr 1 [B aidText, I 4, I 2, withKeys]]
                            )
                            `shouldBe` Nothing
                other -> expectationFailure ("not a live version 2 datum: " <> show other)
        it "writes a pending termination within the Lean size bound" $
            BS.length (canonicalCbor (V2 pending)) `shouldSatisfy` (<= 72)
        it "refuses a malformed identifier" $
            datumKeyState (V2 (liveOf (BC.pack "not an aid") 0 0 False 100 keys))
                `shouldBe` Nothing
