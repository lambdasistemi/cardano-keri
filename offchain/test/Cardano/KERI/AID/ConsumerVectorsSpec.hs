{- |
Module      : Cardano.KERI.AID.ConsumerVectorsSpec
Description : The consumer predicate against the Lean vectors (#353)

The library's representative asset and consumer verdict, checked against the
rows the Lean model publishes: @lean\/consumer-identity-vectors.json@ (the
representative asset of every relying-contract input) and
@lean\/checkpoint-datum-vectors.json@ (the consumer's reading and verdict of
every accepted and refused datum).

The expected values below are copied from those files, never produced by the
code under test. The tables are mechanical copies: the identity table lists
@vectors[].id, input, stateName, asset.name, asset.policy@, the datum table
lists @accepted[]@ then @refused[]@ with @id, input.aid, datum, consumer,
decoded@ (a refused row has no AID of its own and is read for the first
registry AID). The nix source of the unit tests holds only @offchain\/@, so the
JSON files themselves are not read here; a changed vector is caught by the
@lean@ job, not by this suite.
-}
module Cardano.KERI.AID.ConsumerVectorsSpec (
    spec,

    -- * Shared with the clause specification
    IdentityRow (..),
    DatumRow (..),
    DecodedRow (..),
    StateRow (..),
    identityRows,
    datumRows,
    unhex,
    identityOf,
    liveDatumOf,
    pendingDatumOf,
    contextOf,
    environmentOf,
    holdingOf,
    checkpointCredential,
    maturityWindow,
) where

import Cardano.KERI.AID.Application (
    Credential (..),
    OutputReference (..),
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    canonicalCbor,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Consumer (
    Clause (..),
    Context (..),
    DecodedCheckpoint (..),
    Environment (..),
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
    consumableHolding,
    consumableHoldingB,
    decodeCheckpoint,
    representativeAsset,
 )
import Data.Bifunctor (second)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (nub)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
    shouldNotBe,
 )

-- | One row of the identity vectors.
data IdentityRow = IdentityRow
    { irId :: String
    , irStatePolicy :: String
    , irSeedTransaction :: String
    , irSeedIndex :: Integer
    , irAid :: String
    , irStateName :: String
    , irActiveName :: String
    , irAssetPolicy :: String
    }

-- | What the consumer's decoder returns for a datum.
data DecodedRow = DecodedRow String StateRow
    deriving stock (Eq, Show)

data StateRow
    = LiveRow Integer Integer Bool Bool Integer
    | PendingRow Integer Integer
    deriving stock (Eq, Show)

-- | One row of the datum vectors: the datum bytes, the reading and the verdict.
data DatumRow = DatumRow
    { drId :: String
    , drAid :: String
    , drDatum :: String
    , drNow :: Integer
    , drAccepted :: Bool
    , drDecoded :: Maybe DecodedRow
    }

-- | Bytes from lowercase hexadecimal text, the vectors' notation.
unhex :: String -> ByteString
unhex h = either error id (convertFromBase Base16 (BC.pack h))

-- | The window of the datum vectors (@params.W@).
maturityWindow :: Integer
maturityWindow = 10

-- | The script credential the relying contract resolved for the checkpoint validator.
checkpointCredential :: Credential
checkpointCredential = ScriptCredential (BS.replicate 28 0xcc)

-- | The identity row of an AID text (the three AIDs of the base registry).
identityOf :: String -> IdentityRow
identityOf aid = case [r | r <- identityRows, irAid r == aid, irSeedIndex r == 0, irSeedTransaction r == baseSeed, irStatePolicy r == basePolicy] of
    (r : _) -> r
    [] -> error ("no identity row for " <> aid)
  where
    baseSeed = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    basePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"

-- | The relying context of an identity row.
contextOf :: IdentityRow -> Context
contextOf r =
    Context
        { cxNetwork = 0
        , cxRelease =
            Release
                { rlApplicationPolicy = BS.replicate 28 0xa1
                , rlApplicationCredential = BS.replicate 28 0xa2
                , rlStateProgram = BS.replicate 28 0xa3
                , rlStatePolicy = unhex (irStatePolicy r)
                }
        , cxSeed = OutputReference (unhex (irSeedTransaction r)) (irSeedIndex r)
        , cxAid = BC.pack (irAid r)
        , cxCheckpointCredential = checkpointCredential
        }

keyMaterial :: KeyMaterial
keyMaterial =
    KeyMaterial
        { kmCurKeys = [BS.replicate 32 0x11]
        , kmCurThreshold = Unweighted 1
        , kmNextKeys = [BS.replicate 32 0x22]
        , kmNextThreshold = Unweighted 1
        , kmWitnesses = []
        , kmToad = 0
        }

-- | The datum of a live checkpoint of an AID, written by the library's encoder.
liveDatumOf :: ByteString -> Bool -> Bool -> Integer -> ByteString
liveDatumOf aid poisoned frozen bornAt =
    canonicalCbor . V2 $
        Live
            { lvAid = aid
            , lvSn = 0
            , lvEpoch = 0
            , lvPoisoned = poisoned
            , lvFrozen = frozen
            , lvBornAt = bornAt
            , lvRefundTo = BS.replicate 57 0x01
            , lvToppedUp = False
            , lvKeys = keyMaterial
            }

-- | The datum of a checkpoint pending termination, written by the library's encoder.
pendingDatumOf :: ByteString -> ByteString
pendingDatumOf aid =
    canonicalCbor . V2 $
        TerminationPending{tpAid = aid, tpSn = 4, tpEpoch = 2}

-- | What the trusted integration resolves for a context.
environmentOf :: Context -> Environment
environmentOf cx =
    Environment
        { envNetwork = cxNetwork cx
        , envRelease = Just (cxRelease cx)
        , envCheckpointCredential = Just (cxCheckpointCredential cx)
        }

{- | A genuine holding of the row's representative asset, with the bytes of the
Lean vector for its name, at the checkpoint credential, carrying a datum.
-}
holdingOf :: IdentityRow -> ByteString -> ObservedOutput
holdingOf r datum =
    ObservedOutput
        { ooCredential = checkpointCredential
        , ooAssets = [(unhex (irAssetPolicy r), unhex (irActiveName r), 1)]
        , ooDatum = DatumInline datum
        }

spec :: Spec
spec = describe "Consumer predicate against the Lean vectors" $ do
    describe "representative asset (consumer-identity-vectors.json)" $ do
        mapM_ identityCase identityRows
        mapM_ identityVerdictCase identityRows
        it "gives every vector another asset" $
            length (nub [representativeAsset (contextOf r) | r <- identityRows])
                `shouldBe` length identityRows
        it "has an asset that changes with every input of the context" $ do
            let base = identityOf "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
                cx = contextOf base
                asset = representativeAsset cx
                rel = cxRelease cx
                OutputReference txId ix = cxSeed cx
                changed =
                    [ cx{cxRelease = rel{rlStatePolicy = BS.replicate 28 0x01}}
                    , cx{cxSeed = OutputReference (BS.replicate 32 0x02) ix}
                    , cx{cxSeed = OutputReference txId (ix + 1)}
                    , cx{cxAid = BC.pack "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"}
                    ]
            mapM_ (\c -> representativeAsset c `shouldNotBe` asset) changed
    describe "checkpoint datum (checkpoint-datum-vectors.json)" $
        mapM_ datumCase datumRows

identityVerdictCase :: IdentityRow -> Spec
identityVerdictCase r =
    describe ("the holding predicate on " <> irId r) $ do
        let cx = contextOf r
            asset = (unhex (irAssetPolicy r), unhex (irActiveName r))
            holdingFor c (policy, name) =
                ObservedOutput
                    { ooCredential = checkpointCredential
                    , ooAssets = [(policy, name, 1)]
                    , ooDatum = DatumInline (liveDatumOf (cxAid c) False False 100)
                    }
            refusals c =
                consumableHolding maturityWindow 110 (environmentOf c) c
            verdict c =
                consumableHoldingB maturityWindow 110 (environmentOf c) c
            OutputReference txId ix = cxSeed cx
            rel = cxRelease cx
            flipLast b = BS.snoc (BS.init b) (BS.last b + 1)
            otherAid = BC.pack (init (irAid r) <> [if last (irAid r) == 'A' then 'B' else 'A'])
            mutants =
                [ ("state policy", cx{cxRelease = rel{rlStatePolicy = flipLast (rlStatePolicy rel)}})
                , ("seed transaction", cx{cxSeed = OutputReference (flipLast txId) ix})
                , ("seed index", cx{cxSeed = OutputReference txId (ix + 1)})
                , ("AID", cx{cxAid = otherAid})
                ]
        it "accepts the committed asset under the row's own context" $
            refusals cx (holdingFor cx asset) `shouldBe` []
        it "has the Boolean verdict: accepted for the committed asset, refused for each change" $ do
            verdict cx (holdingFor cx asset) `shouldBe` True
            verdict cx (holdingFor cx (second flipLast asset)) `shouldBe` False
            mapM_ (\(_, c) -> verdict c (holdingFor c asset) `shouldBe` False) mutants
        it "refuses the committed name changed" $
            refusals cx (holdingFor cx (second flipLast asset))
                `shouldBe` [RepresentativeQuantityNotOne]
        mapM_
            ( \(what, c) ->
                it ("refuses the committed asset once the " <> what <> " is another") $
                    refusals c (holdingFor c asset)
                        `shouldBe` [RepresentativeQuantityNotOne]
            )
            mutants

identityCase :: IdentityRow -> Spec
identityCase r =
    it ("names " <> irId r <> " as the Lean vector does") $
        representativeAsset (contextOf r)
            `shouldBe` (unhex (irAssetPolicy r), unhex (irActiveName r))

-- | The clauses the vectors' refusals name, by row.
expectedClauses :: DatumRow -> [Clause]
expectedClauses r
    | drAccepted r = []
    | otherwise = case (drId r, drDecoded r) of
        (_, Nothing) -> [DatumNotDecodedForAid]
        ("registered-juvenile", _) -> [CheckpointJuvenile]
        ("poisoned", _) -> [CheckpointPoisoned]
        ("frozen", _) -> [CheckpointFrozen]
        ("pending-termination", _) -> [CheckpointTerminationPending]
        (other, _) -> error ("no expected clause for the vector " <> other)

datumCase :: DatumRow -> Spec
datumCase r = describe (drId r) $ do
    let identity = identityOf (drAid r)
        cx = contextOf identity
        datum = unhex (drDatum r)
        holding = holdingOf identity datum
        refusals =
            consumableHolding maturityWindow (drNow r) (environmentOf cx) cx holding
    it "is read as the vector says" $
        fmap renderDecoded (decodeCheckpoint datum) `shouldBe` drDecoded r
    it "has the consumer verdict of the vector" $
        consumableHoldingB maturityWindow (drNow r) (environmentOf cx) cx holding
            `shouldBe` drAccepted r
    it "names the failed clauses" $
        refusals `shouldBe` expectedClauses r

renderDecoded :: DecodedCheckpoint -> DecodedRow
renderDecoded = \case
    DecodedLive{..} ->
        DecodedRow
            (hexOf dcAid)
            (LiveRow dcSn dcEpoch dcPoisoned dcFrozen dcBornAt)
    DecodedPending{..} -> DecodedRow (hexOf dcAid) (PendingRow dcSn dcEpoch)

hexOf :: ByteString -> String
hexOf = concatMap byte . BS.unpack
  where
    byte w = [digit (w `div` 16), digit (w `mod` 16)]
    digit n = "0123456789abcdef" !! fromIntegral n

identityRows :: [IdentityRow]
identityRows =
    [ IdentityRow
        { irId = "transferable-aid"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 0
        , irAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , irStateName = "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , irActiveName = "866d8e0d3205af393ae4f5e03038e60e6206b1efbfd88ab34d13b6c9cb9cfde8"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    , IdentityRow
        { irId = "other-aid-same-registry"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 0
        , irAid = "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
        , irStateName = "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , irActiveName = "07758b6c783532bf93bb2dbeeef28a8287716447662dd60a13b3357799e53110"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    , IdentityRow
        { irId = "non-transferable-aid"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 0
        , irAid = "BPbeCTEUzPz5UEX4J9Mk8JST2bZV3phvCQ8hWs0diM14"
        , irStateName = "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , irActiveName = "fda241c4049323fa652a76f3d500e7828b49acdd1eca2a112adfa5265653fc80"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    , IdentityRow
        { irId = "rival-seed-output-index"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 1
        , irAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , irStateName = "137d838233aa11f5c452b27faba772d541440f2a8aabb0357f565d5fe182002c"
        , irActiveName = "2f55cee243abd69ae7276f2478fffb5dbac67bd0146e90bfa8432b59cc04be15"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    , IdentityRow
        { irId = "rival-seed-transaction"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1e"
        , irSeedIndex = 0
        , irAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , irStateName = "187d076638ea18d91c192c59092396bb7bf9c0f302ead97cf65751af0e878bcc"
        , irActiveName = "d934a32be44496f7452cbae58775ce251138a942e121dbcc80e1f2883a9969a9"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    , IdentityRow
        { irId = "other-state-policy"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f6"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 0
        , irAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , irStateName = "f89522d53ec5d471859825a00c59836263130e8cc4a59015a944371049139daf"
        , irActiveName = "66b57382eb1f585288faa37a7a7ee4591ede1f8a2cc0d289be96140e19e73ce9"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f6"
        }
    , IdentityRow
        { irId = "seed-output-index-24"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 24
        , irAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , irStateName = "9d417daf68fb27a72855350afe1b3720d6f1fe33a72f470a3c6d422e84d2230d"
        , irActiveName = "5f5c9b01bac42f5f47a57e27f2d3b11bde6e741926d034b8b380cbcf35f6bbc5"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    , IdentityRow
        { irId = "seed-output-index-256"
        , irStatePolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        , irSeedTransaction = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        , irSeedIndex = 256
        , irAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , irStateName = "dc4d6b04df49082c68c31bee1f1c79f1d50bd845678b3db5c311da83a45a38f0"
        , irActiveName = "1917168024281cff5941cd308be5d1b9b2bd35c54937153fe3dbc884759270b2"
        , irAssetPolicy = "70757a7f84898e93989da2a7acb1b6bbc0c5cacfd4d9dee3e8edf2f7"
        }
    ]

datumRows :: [DatumRow]
datumRows =
    [ DatumRow
        { drId = "registered-funded"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500000d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 110
        , drAccepted = True
        , drDecoded = Just (DecodedRow "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550" (LiveRow 0 0 False False 100))
        }
    , DatumRow
        { drId = "registered-juvenile"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500000d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 109
        , drAccepted = False
        , drDecoded = Just (DecodedRow "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550" (LiveRow 0 0 False False 100))
        }
    , DatumRow
        { drId = "rotated"
        , drAid = "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
        , drDatum = "d87a9fd8799f582c4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f0703d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58205d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f0f7fe050c131a21282f3658207c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080f161d242b323940474e5558209ba2a9b0b7bec5ccd3dae1e8eff6fd040b121920272e353c434a51585f666d74ffd87a9f9f9fd8799f0102ffd8799f0102ffff9fd8799f0101ffffffff9f5820bac1c8cfd6dde4ebf2f900070e151c232a31383f464d545b626970777e858c935820d9e0e7eef5fc030a11181f262d343b424950575e656c737a81888f969da4abb2ffd8799f02ff9f5820f8ff060d141b222930373e454c535a61686f767d848b9299a0a7aeb5bcc3cad15820171e252c333a41484f565d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f05820363d444b525960676e757c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080fff02ffffff"
        , drNow = 200
        , drAccepted = True
        , drDecoded = Just (DecodedRow "4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f" (LiveRow 7 3 False False 100))
        }
    , DatumRow
        { drId = "topped-up"
        , drAid = "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
        , drDatum = "d87a9fd8799f582c4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f0703d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87a80d8799f9f58205d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f0f7fe050c131a21282f3658207c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080f161d242b323940474e5558209ba2a9b0b7bec5ccd3dae1e8eff6fd040b121920272e353c434a51585f666d74ffd87a9f9f9fd8799f0102ffd8799f0102ffff9fd8799f0101ffffffff9f5820bac1c8cfd6dde4ebf2f900070e151c232a31383f464d545b626970777e858c935820d9e0e7eef5fc030a11181f262d343b424950575e656c737a81888f969da4abb2ffd8799f02ff9f5820f8ff060d141b222930373e454c535a61686f767d848b9299a0a7aeb5bcc3cad15820171e252c333a41484f565d646b727980878e959ca3aab1b8bfc6cdd4dbe2e9f05820363d444b525960676e757c838a91989fa6adb4bbc2c9d0d7dee5ecf3fa01080fff02ffffff"
        , drNow = 200
        , drAccepted = True
        , drDecoded = Just (DecodedRow "4545426a795463564847555a4872523178337775784f7862727a48305f63476641594a4a51484d453350776f" (LiveRow 7 3 False False 100))
        }
    , DatumRow
        { drId = "poisoned"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87a80d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Just (DecodedRow "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550" (LiveRow 4 2 True False 100))
        }
    , DatumRow
        { drId = "frozen"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87a80186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Just (DecodedRow "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550" (LiveRow 4 2 False True 100))
        }
    , DatumRow
        { drId = "pending-termination"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd87a9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Just (DecodedRow "454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c4768723550" (PendingRow 4 2))
        }
    , DatumRow
        { drId = "large-numbers"
        , drAid = "BPbeCTEUzPz5UEX4J9Mk8JST2bZV3phvCQ8hWs0diM14"
        , drDatum = "d87a9fd8799f582c42506265435445557a507a35554558344a394d6b384a535432625a56337068764351386857733064694d3134c249010000000000000005c249400000000000000000d87980d8798018645f58400104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9acafb2b5b8bbbe46c1c4c7cacdd0ffd87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = True
        , drDecoded = Just (DecodedRow "42506265435445557a507a35554558344a394d6b384a535432625a56337068764351386857733064694d3134" (LiveRow 18446744073709551621 1180591620717411303424 False False 100))
        }
    , DatumRow
        { drId = "version-1"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d8799fd8799f582000070e151c232a31383f464d545b626970777e858c939aa1a8afb6bdc4cbd2d99f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff80000304ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "version-3"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87b9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "version-no-field"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a80"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "version-two-fields"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "unknown-form"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd87b9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "live-eight-fields"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "live-without-topped-up"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "live-ten-fields"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ff00ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "pending-with-keys"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd87a9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "pending-negative-epoch"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd87a9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500421ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "aid-integer"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f050402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "sn-negative"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235502002d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "epoch-bytes"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500440d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "poisoned-not-boolean"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87b80d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "poisoned-boolean-with-field"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87a9f00ffd87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "frozen-integer"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d8798001186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "born-at-negative"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980386358390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "refund-integer"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186407d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "topped-up-integer"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a900d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "topped-up-not-boolean"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87b80d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "keys-list"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d879809f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "keys-five-fields"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff80ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "key-integer"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f01ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "threshold-unknown-form"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd87b9f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "weight-one-field"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd87a9f9f9fd8799f01ffffffff8000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "witnesses-map"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ffa000ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "toad-bytes"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8040ffffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "not-a-constructor"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "9f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "trailing-byte"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffffff00"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "truncated"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "d87a9fd8799f582c454d4d6351746f714f6b41434c767973774a54465855516d52625a68577434414c6a6a68587a4c47687235500402d87980d87980186458390104070a0d101316191c1f2225282b2e3134373a3d404346494c4f5255585b5e6164676a6d707376797c7f8285888b8e9194979a9da0a3a6a9d87980d8799f9f58201f262d343b424950575e656c737a81888f969da4abb2b9c0c7ced5dce3eaf1f8ffd8799f01ff9f58203e454c535a61686f767d848b9299a0a7aeb5bcc3cad1d8dfe6edf4fb02091017ffd8799f01ff8000ffff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "empty"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = ""
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    , DatumRow
        { drId = "break-byte"
        , drAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , drDatum = "ff"
        , drNow = 200
        , drAccepted = False
        , drDecoded = Nothing
        }
    ]
