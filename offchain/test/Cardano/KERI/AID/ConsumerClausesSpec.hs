{- |
Module      : Cardano.KERI.AID.ConsumerClausesSpec
Description : Each clause of the consumer predicate fails distinctly (#353)

Starts from a genuine holding (the Lean vector @registered-funded@ read at its
accepted time) and breaks one aspect at a time, then every combination of the
six independent aspects. A refused holding reports exactly the clauses it
fails, in the order of the Lean @consumableHoldingB@: the authenticated
context, the checkpoint credential, the representative quantity, the datum,
then the state clauses. The Boolean answer is true exactly when none failed.

The datums of the breaks are written with the library's own datum encoder,
which @DatumV2Spec@ pins to the bytes of the Lean vectors.
-}
module Cardano.KERI.AID.ConsumerClausesSpec (
    spec,
) where

import Cardano.KERI.AID.Application (Credential (..))
import Cardano.KERI.AID.Consumer (
    Clause (..),
    Context (..),
    Environment (..),
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
    consumableHolding,
    consumableHoldingB,
    representativeQuantity,
 )
import Cardano.KERI.AID.ConsumerVectorsSpec (
    IdentityRow (..),
    checkpointCredential,
    contextOf,
    environmentOf,
    holdingOf,
    identityOf,
    liveDatumOf,
    maturityWindow,
    pendingDatumOf,
    unhex,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (subsequences)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

aidText :: String
aidText = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"

-- | Another AID of the base registry.
otherAidText :: String
otherAidText = "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"

-- | The hash of the checkpoint validator, as a script and as a key.
checkpointHash :: ByteString
checkpointHash = case checkpointCredential of
    ScriptCredential h -> h
    KeyCredential h -> h

identity :: IdentityRow
identity = identityOf aidText

cx :: Context
cx = contextOf identity

-- | The slot the datum vectors read @registered-funded@ at.
accepting :: Integer
accepting = 110

birth :: Integer
birth = 100

-- | The datum of a live checkpoint of an AID.
liveDatum :: String -> Bool -> Bool -> Integer -> ByteString
liveDatum aid = liveDatumOf (BC.pack aid)

genuine :: ObservedOutput
genuine = holdingOf identity (liveDatum aidText False False birth)

refusalsOf :: Integer -> Environment -> Context -> ObservedOutput -> [Clause]
refusalsOf = consumableHolding maturityWindow

-- | The independent aspects a holding can fail, with the clause each one names.
data Fault
    = WrongNetwork
    | WrongCredential
    | WrongQuantity
    | WrongAid
    | Frozen
    | Poisoned
    | Juvenile
    deriving stock (Eq, Show, Enum, Bounded)

clauseOf :: Fault -> Clause
clauseOf = \case
    WrongNetwork -> ContextNotAuthenticated
    WrongCredential -> OutputNotAtCheckpointCredential
    WrongQuantity -> RepresentativeQuantityNotOne
    WrongAid -> DatumNotDecodedForAid
    Frozen -> CheckpointFrozen
    Poisoned -> CheckpointPoisoned
    Juvenile -> CheckpointJuvenile

-- | A holding and a time carrying exactly the given faults.
withFaults :: [Fault] -> (Environment, ObservedOutput, Integer)
withFaults fs = (env, out, now)
  where
    has f = f `elem` fs
    env =
        (environmentOf cx)
            { envNetwork = if has WrongNetwork then 1 else cxNetwork cx
            }
    out =
        genuine
            { ooCredential =
                if has WrongCredential
                    then ScriptCredential (BS.replicate 28 0xdd)
                    else checkpointCredential
            , ooAssets =
                [ (p, n, if has WrongQuantity then 2 else 1)
                | (p, n, _) <- ooAssets genuine
                ]
            , ooDatum =
                DatumInline
                    ( liveDatum
                        (if has WrongAid then otherAidText else aidText)
                        (has Poisoned)
                        (has Frozen)
                        birth
                    )
            }
    now = if has Juvenile then birth + maturityWindow - 1 else accepting

spec :: Spec
spec = describe "Consumer predicate clauses" $ do
    it "accepts the genuine holding" $ do
        refusalsOf accepting (environmentOf cx) cx genuine `shouldBe` []
        consumableHoldingB maturityWindow accepting (environmentOf cx) cx genuine
            `shouldBe` True
    it "accepts at the last slot of the window and refuses the slot before" $ do
        let at now = refusalsOf now (environmentOf cx) cx genuine
        at (birth + maturityWindow) `shouldBe` []
        at (birth + maturityWindow - 1) `shouldBe` [CheckpointJuvenile]
    describe "the context is authenticated" $ do
        let env = environmentOf cx
            rel = cxRelease cx
            asRefusals e = refusalsOf accepting e cx genuine
        it "refuses another network" $
            asRefusals env{envNetwork = 1} `shouldBe` [ContextNotAuthenticated]
        it "refuses an unresolved release" $
            asRefusals env{envRelease = Nothing} `shouldBe` [ContextNotAuthenticated]
        it "refuses an unresolved checkpoint credential" $
            asRefusals env{envCheckpointCredential = Nothing}
                `shouldBe` [ContextNotAuthenticated]
        it "refuses the checkpoint credential's hash as a key credential" $
            asRefusals env{envCheckpointCredential = Just (KeyCredential checkpointHash)}
                `shouldBe` [ContextNotAuthenticated]
        it "refuses another checkpoint credential" $
            asRefusals env{envCheckpointCredential = Just (ScriptCredential (BS.replicate 28 0xee))}
                `shouldBe` [ContextNotAuthenticated]
        it "refuses a release differing in any field" $
            mapM_
                ( \r ->
                    asRefusals env{envRelease = Just r}
                        `shouldBe` [ContextNotAuthenticated]
                )
                [ rel{rlApplicationPolicy = BS.replicate 28 0x01}
                , rel{rlApplicationCredential = BS.replicate 28 0x01}
                , rel{rlStateProgram = BS.replicate 28 0x01}
                , rel{rlStatePolicy = BS.replicate 28 0x01}
                ]
    describe "the output sits at the checkpoint credential" $ do
        it "refuses an output elsewhere" $
            refusalsOf
                accepting
                (environmentOf cx)
                cx
                genuine{ooCredential = ScriptCredential (BS.replicate 28 0xdd)}
                `shouldBe` [OutputNotAtCheckpointCredential]
        it "refuses a key credential with the hash of the checkpoint validator" $
            refusalsOf
                accepting
                (environmentOf cx)
                cx
                genuine{ooCredential = KeyCredential checkpointHash}
                `shouldBe` [OutputNotAtCheckpointCredential]
    describe "the representative asset is held exactly once" $ do
        let policy = unhex (irAssetPolicy identity)
            name = unhex (irActiveName identity)
            other = (BS.replicate 28 0x09, BS.replicate 32 0x09, 5)
            with assets = refusalsOf accepting (environmentOf cx) cx genuine{ooAssets = assets}
        it "reads the quantity as the sum of the asset's entries" $ do
            let quantityOf assets = representativeQuantity cx genuine{ooAssets = assets}
            quantityOf [] `shouldBe` 0
            quantityOf [other] `shouldBe` 0
            quantityOf [(policy, name, 2)] `shouldBe` 2
            quantityOf [(policy, name, 1), other, (policy, name, 4)] `shouldBe` 5
        it "refuses none" $ with [] `shouldBe` [RepresentativeQuantityNotOne]
        it "refuses only another asset" $
            with [other] `shouldBe` [RepresentativeQuantityNotOne]
        it "refuses two" $ with [(policy, name, 2)] `shouldBe` [RepresentativeQuantityNotOne]
        it "sums the entries of one asset: 1 + 1 is two" $
            with [(policy, name, 1), (policy, name, 1)]
                `shouldBe` [RepresentativeQuantityNotOne]
        it "sums the entries of one asset: 0 + 1 is one" $
            with [(policy, name, 0), (policy, name, 1)] `shouldBe` []
        it "accepts one among other assets" $
            with [other, (policy, name, 1)] `shouldBe` []
        it "refuses the name of another policy or of another AID" $ do
            with [(BS.replicate 28 0x01, name, 1)] `shouldBe` [RepresentativeQuantityNotOne]
            with [(policy, BS.replicate 32 0x01, 1)] `shouldBe` [RepresentativeQuantityNotOne]
    describe "the datum is read and is the AID's" $ do
        let with d = refusalsOf accepting (environmentOf cx) cx genuine{ooDatum = maybe DatumAbsent DatumInline d}
            other = "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"
        it "refuses no datum" $ with Nothing `shouldBe` [DatumNotDecodedForAid]
        it "refuses bytes that are no datum" $
            with (Just (unhex "d8799fff")) `shouldBe` [DatumNotDecodedForAid]
        it "refuses a datum for another AID" $
            with (Just (liveDatum other False False birth))
                `shouldBe` [DatumNotDecodedForAid]
        it "also names the state clauses of a datum decoded for another AID" $ do
            with (Just (liveDatum other False True birth))
                `shouldBe` [DatumNotDecodedForAid, CheckpointFrozen]
            with (Just (liveDatum other True False (accepting - maturityWindow + 1)))
                `shouldBe` [DatumNotDecodedForAid, CheckpointPoisoned, CheckpointJuvenile]
            with (Just (pendingDatumOf (BC.pack other)))
                `shouldBe` [DatumNotDecodedForAid, CheckpointTerminationPending]
    describe "the state is consumable" $ do
        let with d = refusalsOf accepting (environmentOf cx) cx genuine{ooDatum = DatumInline d}
        it "refuses a frozen checkpoint" $
            with (liveDatum aidText False True birth) `shouldBe` [CheckpointFrozen]
        it "refuses a poisoned checkpoint" $
            with (liveDatum aidText True False birth) `shouldBe` [CheckpointPoisoned]
        it "refuses a juvenile checkpoint" $
            with (liveDatum aidText False False (accepting - maturityWindow + 1))
                `shouldBe` [CheckpointJuvenile]
        it "names a poisoned, frozen and juvenile checkpoint by all three" $
            with (liveDatum aidText True True accepting)
                `shouldBe` [CheckpointFrozen, CheckpointPoisoned, CheckpointJuvenile]
    describe "every combination of independent faults" $ do
        let combinations = subsequences [minBound .. maxBound :: Fault]
        it "covers every one of the 128 combinations" $
            length combinations `shouldBe` 128
        mapM_
            ( \fs -> it ("reports exactly " <> show fs) $ do
                let (env, out, now) = withFaults fs
                    expected = [clauseOf f | f <- [minBound .. maxBound], f `elem` fs]
                refusalsOf now env cx out `shouldBe` expected
                consumableHoldingB maturityWindow now env cx out `shouldBe` null fs
            )
            combinations
