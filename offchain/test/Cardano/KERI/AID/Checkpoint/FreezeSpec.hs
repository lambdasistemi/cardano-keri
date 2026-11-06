{- |
Module      : Cardano.KERI.AID.Checkpoint.FreezeSpec
Description : The one-step freeze (#345) against the Lean corpus

The Haskell side of the freeze: the datum a freeze writes, what it settles,
and the verdict over the validator's premises. Every amount is arithmetic
over the Lean parameters, never read back from the code under test. The
rotation evidence is the committed @adv_wit_2key@ keripy rotation, the same
the Aiken tests run over, so the two layers judge the same transactions.

The corpus cells are the freeze cells of @simulator/checkpoint-simulator-corpus.json@
(generated into "Cardano.KERI.AID.Checkpoint.FreezeCorpus"): the Haskell
verdict must equal the Lean's on every one, and on the cell the Lean accepts
the verdict must be an acceptance.
-}
module Cardano.KERI.AID.Checkpoint.FreezeSpec (spec) where

import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.Advance (AdvanceEvidence (..))
import Cardano.KERI.AID.Checkpoint.AdvanceSpec (AdvCase (..), advCase)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
    KeyStateView (..),
 )
import Cardano.KERI.AID.Checkpoint.FixtureLoader (loadFixture)
import Cardano.KERI.AID.Checkpoint.Freeze (
    FreezeEvidence (..),
    FreezeInput (..),
    FreezeParams (..),
    FreezeRefusal (..),
    FreezeSettlement (..),
    freezeRotatedView,
    freezeSettlement,
    freezeVerdict,
    frozenLive,
 )
import Cardano.KERI.AID.Checkpoint.FreezeCorpus (
    CorpusCell (..),
    corpusB,
    corpusCells,
    corpusP,
 )
import Cardano.KERI.AID.Checkpoint.Message (SpentCheckpoint (..))
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Data.ByteString qualified as BS
import Data.Either (isRight)
import Test.Hspec (
    Spec,
    beforeAll,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldSatisfy,
 )

-- | One Lean unit, in lovelace.
unit :: Integer
unit = 1_000_000

-- | The Lean parameters as lovelace: @Mc@, @D = 1000@, @B = 5@, @P = 2@.
params :: FreezeParams
params =
    FreezeParams
        { fpMinAda = 2_000_000
        , fpDeposit = 1_000_000_000
        , fpBond = 5 * unit
        , fpPremium = 2 * unit
        }

floorUnfrozen, floorFrozen :: Integer
floorUnfrozen = fpMinAda params + fpDeposit params + fpBond params
floorFrozen = fpMinAda params + fpDeposit params

-- | The spent checkpoint as a live datum, over the fixture's spent key state.
liveOf :: AdvCase -> Bool -> Bool -> Integer -> CheckpointDatumV2
liveOf c poisoned frozen = liveMarked c poisoned frozen False

-- | The spent checkpoint as a live datum with the top-up mark given.
liveMarked :: AdvCase -> Bool -> Bool -> Bool -> Integer -> CheckpointDatumV2
liveMarked c poisoned frozen toppedUp sn =
    Live
        { lvAid = qb64Aid (scCesrAid (acSpent c))
        , lvSn = sn
        , lvEpoch = scSeq (acSpent c)
        , lvPoisoned = poisoned
        , lvFrozen = frozen
        , lvBornAt = 1_800_000_000_000
        , lvRefundTo = BS.cons 0x61 (BS.replicate 28 0x53)
        , lvToppedUp = toppedUp
        , lvKeys =
            KeyMaterial
                { kmCurKeys = acIcpKeys c
                , kmCurThreshold = Unweighted 2
                , kmNextKeys = scNextKeys (acSpent c)
                , kmNextThreshold = scNextThreshold (acSpent c)
                , kmWitnesses = scWitnesses (acSpent c)
                , kmToad = 2
                }
        }

evidenceOf :: AdvCase -> FreezeEvidence
evidenceOf c =
    FreezeEvidence
        { feRotatedKeys =
            KeyMaterial
                { kmCurKeys = cdCurKeys created
                , kmCurThreshold = cdCurThreshold created
                , kmNextKeys = cdNextKeys created
                , kmNextThreshold = cdNextThreshold created
                , kmWitnesses = cdWitnesses created
                , kmToad = cdToad created
                }
        , feRotatedSn = cdNativeSn created
        , feRotation = acEvidence c
        }
  where
    created = acCreated c

unevidenced :: FreezeEvidence -> FreezeEvidence
unevidenced e =
    e
        { feRotation =
            (feRotation e){aeCtrlSigs = [], aeWitReceipts = []}
        }

{- | The honest freeze of an unfrozen, unpoisoned checkpoint holding the given
pool, with the given spent sequence number and evidence.
-}
freezeOf ::
    AdvCase ->
    CheckpointDatumV2 ->
    Integer ->
    FreezeEvidence ->
    FreezeInput
freezeOf c old pool evidence =
    FreezeInput
        { fiPolicy = scPolicyId (acSpent c)
        , fiSpentTxId = scTxid (acSpent c)
        , fiSpentIndex = scIndex (acSpent c)
        , fiSpentDatum = old
        , fiSpentLovelace = floorOf old + pool
        , fiSuccessorDatum = withFrozen True old
        , fiSuccessorLovelace = floorFrozen + pool
        , fiHunterLovelace = fpBond params
        , fiEvidence = evidence
        }
  where
    floorOf d
        | lvFrozen d = floorFrozen
        | otherwise = floorUnfrozen

honest :: AdvCase -> Integer -> FreezeInput
honest c pool =
    freezeOf c (liveOf c False False (scNativeSn (acSpent c))) pool (evidenceOf c)

spec :: Spec
spec = describe "Checkpoint.Freeze (#345, Lean Step.freeze)" $ do
    describe "frozenLive: the same datum with frozen set" $
        beforeAll (loadFixture "advance.json") $ do
            it "sets frozen on a live, unfrozen, unpoisoned datum and nothing else" $ \fx ->
                withCaseIO fx $ \c ->
                    frozenLive (liveOf c False False 0)
                        `shouldBe` Just (liveOf c False True 0)
            it "refuses a frozen datum" $ \fx ->
                withCaseIO fx $ \c ->
                    frozenLive (liveOf c False True 0) `shouldBe` Nothing
            it "refuses a poisoned datum" $ \fx ->
                withCaseIO fx $ \c ->
                    frozenLive (liveOf c True False 0) `shouldBe` Nothing
            it "refuses a pending termination" $ \fx ->
                withCaseIO fx $ \c ->
                    frozenLive (pendingOf (liveOf c False False 0)) `shouldBe` Nothing

    describe "freezeSettlement: the bond leaves, the pool stays" $
        beforeAll (loadFixture "advance.json") $ do
            it "pays the bond and keeps the pool when the pool is below the premium" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeSettlement params (liveOf c False False 0) (floorUnfrozen + unit)
                        `shouldBe` Just
                            FreezeSettlement
                                { fsHunterPaid = 5 * unit
                                , fsSuccessorLovelace = floorFrozen + unit
                                , fsPool = unit
                                }
            it "refuses a pool equal to the premium" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeSettlement params (liveOf c False False 0) (floorUnfrozen + 2 * unit)
                        `shouldBe` Nothing
            it "accepts a pool one lovelace below the premium" $ \fx ->
                withCaseIO fx $ \c ->
                    fmap fsPool (freezeSettlement params (liveOf c False False 0) (floorUnfrozen + 2 * unit - 1))
                        `shouldBe` Just (2 * unit - 1)
            it "refuses an output below its floor" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeSettlement params (liveOf c False False 0) (floorUnfrozen - 1)
                        `shouldBe` Nothing

    describe "freezeRotatedView: the key state the evidence is checked against" $
        beforeAll (loadFixture "advance.json") $
            it "is the fixture's created key state: the old identifier, one more epoch, the rotation's keys" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeRotatedView (liveOf c False False 0) (evidenceOf c)
                        `shouldBe` Just (acCreated c)

    describe "freezeVerdict: the validator's premises, each by name" $
        beforeAll (loadFixture "advance.json") $ do
            it "accepts the honest freeze" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict params (honest c unit) `shouldBe` Right ()
            it "refuses a pool equal to the premium" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict params (honest c (2 * unit))
                        `shouldBe` Left FreezePoolCoversPremium
            it "refuses a frozen checkpoint" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (freezeOf c (liveOf c False True 0) unit (evidenceOf c))
                        `shouldBe` Left FreezeAlreadyFrozen
            it "refuses a poisoned checkpoint" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (freezeOf c (liveOf c True False 0) unit (evidenceOf c))
                        `shouldBe` Left FreezePoisoned
            it "refuses a rotation without signatures or receipts" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict params ((honest c unit){fiEvidence = unevidenced (evidenceOf c)})
                        `shouldSatisfy` isRotationRefused
            it "refuses a rotation that is not later than the spent sequence number" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        ( freezeOf
                            c
                            (liveOf c False False (cdNativeSn (acCreated c)))
                            unit
                            (evidenceOf c)
                        )
                        `shouldSatisfy` isRotationRefused
            it "keeps the top-up mark: accepts the freeze of a topped-up checkpoint" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (freezeOf c (liveMarked c False False True (scNativeSn (acSpent c))) unit (evidenceOf c))
                        `shouldBe` Right ()
            it "keeps the top-up mark: the frozen copy of a topped-up checkpoint is marked" $ \fx ->
                withCaseIO fx $ \c ->
                    frozenLive (liveMarked c False False True 0)
                        `shouldBe` Just (liveMarked c False True True 0)
            it "refuses a freeze whose successor clears the top-up mark" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (freezeOf c (liveMarked c False False True (scNativeSn (acSpent c))) unit (evidenceOf c))
                            { fiSuccessorDatum = liveMarked c False True False (scNativeSn (acSpent c))
                            }
                        `shouldBe` Left FreezeSuccessorNotTheFrozenCopy
            it "refuses a successor that is not the frozen copy" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (honest c unit){fiSuccessorDatum = liveOf c False False 0}
                        `shouldBe` Left FreezeSuccessorNotTheFrozenCopy
            it "refuses a successor holding one lovelace more" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (honest c unit){fiSuccessorLovelace = floorFrozen + unit + 1}
                        `shouldBe` Left FreezeSuccessorValueMismatch
            it "refuses a bond paid one lovelace short" $ \fx ->
                withCaseIO fx $ \c ->
                    freezeVerdict
                        params
                        (honest c unit){fiHunterLovelace = 5 * unit - 1}
                        `shouldBe` Left FreezeBondUnpaid

    describe "the Lean corpus: the Haskell verdict is the Lean's on every freeze cell" $
        beforeAll (loadFixture "advance.json") $ do
            it "covers the grid: both verdicts occur, and the premium and bond are the corpus's" $ \_ -> do
                length corpusCells `shouldBe` 150
                length (filter ccToppedUp corpusCells) `shouldBe` 72
                length (filter ccAccepted corpusCells) `shouldBe` 2
                length (filter (\cell -> ccAccepted cell && ccToppedUp cell) corpusCells)
                    `shouldBe` 1
                (corpusP, corpusB) `shouldBe` (2, 5)
            it "agrees with the Lean on every cell" $ \fx ->
                withCaseIO fx $ \c ->
                    [ ccName cell
                    | cell <- corpusCells
                    , isRight (freezeVerdict params (cellInput c cell)) /= ccAccepted cell
                    ]
                        `shouldBe` []
  where
    withCaseIO fx k = case advCase fx "adv_wit_2key" of
        Left err -> expectationFailure err
        Right c -> k c
    isRotationRefused = \case
        Left (FreezeRotationRefused _) -> True
        _ -> False

-- | The datum with its frozen flag set to the given value (a live datum).
withFrozen :: Bool -> CheckpointDatumV2 -> CheckpointDatumV2
withFrozen frozen = \case
    d@Live{} -> d{lvFrozen = frozen}
    other -> other

-- | The termination pending of a live datum.
pendingOf :: CheckpointDatumV2 -> CheckpointDatumV2
pendingOf = \case
    Live{lvAid, lvSn, lvEpoch} -> TerminationPending lvAid lvSn lvEpoch
    pending -> pending

{- | A corpus cell as a freeze: the flags and pool of the cell, the sequence
number relation re-labelling the spent checkpoint, the oracle deciding whether
the evidence carries signatures.
-}
cellInput :: AdvCase -> CorpusCell -> FreezeInput
cellInput c cell
    | ccPending cell =
        (honest c unit)
            { fiSpentDatum = pending
            , fiSpentLovelace = fpMinAda params
            , fiSuccessorDatum = liveOf c False True 0
            , fiSuccessorLovelace = floorFrozen
            , fiEvidence = evidence
            }
    | otherwise = freezeOf c old (ccPool cell * unit) evidence
  where
    created = cdNativeSn (acCreated c)
    spentSn = case ccSnRelation cell of
        r
            | r > 0 -> scNativeSn (acSpent c)
            | r == 0 -> created
            | otherwise -> created + 1
    old = liveMarked c (ccPoisoned cell) (ccFrozen cell) (ccToppedUp cell) spentSn
    evidence
        | ccRotationEvidenced cell = evidenceOf c
        | otherwise = unevidenced (evidenceOf c)
    pending = pendingOf (liveOf c False False 0)
