{-# LANGUAGE RecordWildCards #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.TopUpSpec
Description : The bounded top-up against the Lean corpus (#346, #522)

The Haskell verdict of a top-up is the Lean's on every top-up cell of the
corpus, and the registration's first pool premise is the Lean's on every
registration cell. The refusals the Lean names are told apart:
@top-up-below-premium@, @already-topped-up@, @pool-below-premium@. Amounts are
arithmetic over the Lean's parameters (one unit is a million lovelace), never
read back from the code under test.
-}
module Cardano.KERI.AID.Checkpoint.TopUpSpec (
    spec,
) where

import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatumV2 (..),
    KeyMaterial (..),
 )
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.AID.Checkpoint.TopUp (
    RegistrationRefusal (..),
    TopUpInput (..),
    TopUpParams (..),
    TopUpRefusal (..),
    TopUpSettlement (..),
    markedLive,
    registrationRefusalName,
    registrationVerdict,
    topUpRefusalName,
    topUpSettlement,
    topUpVerdict,
 )
import Cardano.KERI.AID.Checkpoint.TopUpCorpus (
    CorpusRegister (..),
    CorpusTopUp (..),
    corpusP,
    corpusRegisters,
    corpusTopUps,
 )
import Cardano.KERI.AID.Checkpoint.Value (heldValue, valueFloor)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (isRight)
import Test.Hspec (
    Spec,
    describe,
    it,
    shouldBe,
 )

unit :: Integer
unit = 1_000_000

params :: TopUpParams
params =
    TopUpParams
        { tuMinAda = 2_000_000
        , tuDeposit = 1_000_000_000
        , tuBond = 5_000_000
        , tuPremium = 2 * unit
        }

keys :: KeyMaterial
keys =
    KeyMaterial
        { kmCurKeys = [BS.replicate 32 0x01]
        , kmCurThreshold = Unweighted 1
        , kmNextKeys = [BS.replicate 32 0x02]
        , kmNextThreshold = Unweighted 1
        , kmWitnesses = []
        , kmToad = 0
        }

{- | The fields of a live checkpoint, in a record whose fields can be changed
one at a time.
-}
data Fields = Fields
    { fAid :: ByteString
    , fSn :: Integer
    , fEpoch :: Integer
    , fPoisoned :: Bool
    , fFrozen :: Bool
    , fBornAt :: Integer
    , fRefundTo :: ByteString
    , fToppedUp :: Bool
    , fKeys :: KeyMaterial
    }

baseFields :: Fields
baseFields =
    Fields
        { fAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P"
        , fSn = 4
        , fEpoch = 2
        , fPoisoned = False
        , fFrozen = False
        , fBornAt = 100
        , fRefundTo = BS.replicate 29 0x61
        , fToppedUp = False
        , fKeys = keys
        }

toDatum :: Fields -> CheckpointDatumV2
toDatum Fields{..} =
    Live
        { lvAid = fAid
        , lvSn = fSn
        , lvEpoch = fEpoch
        , lvPoisoned = fPoisoned
        , lvFrozen = fFrozen
        , lvBornAt = fBornAt
        , lvRefundTo = fRefundTo
        , lvToppedUp = fToppedUp
        , lvKeys = fKeys
        }

-- | A live checkpoint with the flags and mark given.
live :: Bool -> Bool -> Bool -> CheckpointDatumV2
live poisoned frozen toppedUp =
    toDatum baseFields{fPoisoned = poisoned, fFrozen = frozen, fToppedUp = toppedUp}

pending :: CheckpointDatumV2
pending = TerminationPending{tpAid = "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P", tpSn = 4, tpEpoch = 2}

floorOf :: CheckpointDatumV2 -> Integer
floorOf = valueFloor (tuMinAda params) (tuDeposit params) (tuBond params)

heldOf :: CheckpointDatumV2 -> Integer -> Integer
heldOf = heldValue (tuMinAda params) (tuDeposit params) (tuBond params)

-- | The honest top-up of a fresh checkpoint with a pool of one unit.
honest :: Integer -> TopUpInput
honest amount =
    TopUpInput
        { tiSpentDatum = live False False False
        , tiSpentLovelace = heldOf (live False False False) unit
        , tiAmount = amount
        , tiSuccessorDatum = live False False True
        , tiSuccessorLovelace = heldOf (live False False True) (unit + amount)
        }

{- | The corpus cell as a top-up: the successor is always the state grown by
the amount with the mark set, so a refused cell is refused by a guard.
-}
cellInput :: CorpusTopUp -> TopUpInput
cellInput cell
    | tuPending cell =
        TopUpInput
            { tiSpentDatum = pending
            , tiSpentLovelace = tuMinAda params
            , tiAmount = amount
            , tiSuccessorDatum = live False False True
            , tiSuccessorLovelace = heldOf (live False False True) amount
            }
    | otherwise =
        TopUpInput
            { tiSpentDatum = old
            , tiSpentLovelace = heldOf old pool
            , tiAmount = amount
            , tiSuccessorDatum = marked
            , tiSuccessorLovelace = heldOf marked (pool + amount)
            }
  where
    amount = tuAmount cell * unit
    pool = tuPool cell * unit
    old = live (tuPoisoned cell) (tuFrozen cell) (tuToppedUp cell)
    marked = live (tuPoisoned cell) (tuFrozen cell) True

carrierOf :: Integer -> Integer
carrierOf pool0Units =
    tuMinAda params + tuDeposit params + tuBond params + pool0Units * unit

refusal :: TopUpInput -> Maybe TopUpRefusal
refusal input = either Just (const Nothing) (topUpVerdict params input)

spec :: Spec
spec = describe "bounded top-up (Lean Step.topUp, Step.register)" $ do
    describe "the Lean corpus: the Haskell verdict is the Lean's on every cell" $ do
        it "covers the grid: 150 top-up cells (48 accepted), 6 registration cells (4 accepted), P = 2" $ do
            length corpusTopUps `shouldBe` 150
            length (filter tuAccepted corpusTopUps) `shouldBe` 48
            length (filter tuToppedUp corpusTopUps) `shouldBe` 72
            length corpusRegisters `shouldBe` 6
            length (filter rgAccepted corpusRegisters) `shouldBe` 4
            corpusP `shouldBe` 2
        it "agrees with the Lean on every top-up cell" $
            [ tuName cell
            | cell <- corpusTopUps
            , isRight (topUpVerdict params (cellInput cell)) /= tuAccepted cell
            ]
                `shouldBe` []
        it "agrees with the Lean on every registration cell" $
            [ rgName cell
            | cell <- corpusRegisters
            , isRight (registrationVerdict params (carrierOf (rgPool0 cell)))
                /= rgAccepted cell
            ]
                `shouldBe` []

    describe "the refusals the Lean names" $ do
        it "refuses an amount one lovelace below the premium: top-up-below-premium" $ do
            refusal (honest (tuPremium params - 1)) `shouldBe` Just TopUpBelowPremium
            fmap topUpRefusalName (refusal (honest (tuPremium params - 1)))
                `shouldBe` Just "top-up-below-premium"
        it "refuses a negative amount" $
            refusal (honest (-1)) `shouldBe` Just TopUpBelowPremium
        it "refuses a second top-up in one key state: already-topped-up" $ do
            let second =
                    (honest (tuPremium params))
                        { tiSpentDatum = live False False True
                        , tiSpentLovelace = heldOf (live False False True) unit
                        }
            refusal second `shouldBe` Just TopUpAlreadyToppedUp
            fmap topUpRefusalName (refusal second) `shouldBe` Just "already-topped-up"
        it "refuses a registration with a first pool one lovelace below the premium: pool-below-premium" $ do
            registrationVerdict params (carrierOf 2 - 1)
                `shouldBe` Left RegistrationPoolBelowPremium
            either registrationRefusalName show (registrationVerdict params (carrierOf 1))
                `shouldBe` "pool-below-premium"
        it "accepts a registration with a first pool of exactly the premium" $
            registrationVerdict params (carrierOf 2) `shouldBe` Right (2 * unit)
        it "refuses a registration below the floor" $
            registrationVerdict params (carrierOf 0 - 1)
                `shouldBe` Left RegistrationBelowFloor

    describe "what a top-up accepts" $ do
        it "accepts exactly the premium and any amount above it" $
            [ amount
            | amount <- [tuPremium params, tuPremium params + 1, 5 * unit]
            , isRight (topUpVerdict params (honest amount))
            ]
                `shouldBe` [tuPremium params, tuPremium params + 1, 5 * unit]
        it "accepts every combination of the poison and frozen flags when fresh" $
            [ (p, f)
            | p <- [False, True]
            , f <- [False, True]
            , let old = live p f False
                  input =
                    TopUpInput
                        { tiSpentDatum = old
                        , tiSpentLovelace = heldOf old unit
                        , tiAmount = tuPremium params
                        , tiSuccessorDatum = live p f True
                        , tiSuccessorLovelace = heldOf (live p f True) (unit + tuPremium params)
                        }
            , isRight (topUpVerdict params input)
            ]
                `shouldBe` [(False, False), (False, True), (True, False), (True, True)]
        it "settles the pool and the lovelace of the marked successor" $
            topUpSettlement
                params
                (live False False False)
                (heldOf (live False False False) unit)
                (tuPremium params)
                `shouldBe` Just
                    TopUpSettlement
                        { tsSuccessorLovelace = floorOf (live False False True) + unit + tuPremium params
                        , tsPool = unit + tuPremium params
                        }
        it "writes the mark and nothing else" $
            markedLive (live True False False) `shouldBe` Just (live True False True)
        it "writes no mark on a pending termination or a marked datum" $ do
            markedLive pending `shouldBe` Nothing
            markedLive (live False False True) `shouldBe` Nothing

    describe "what a top-up refuses in its successor" $ do
        let refused successor = refusal (honest (tuPremium params)){tiSuccessorDatum = successor}
            changed f = refused (toDatum (f baseFields{fToppedUp = True}))
        it "refuses a successor that does not set the mark" $
            refused (live False False False)
                `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that changes the aid" $
            changed (\f -> f{fAid = "other"}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that changes the sequence number" $
            changed (\f -> f{fSn = fSn f + 1}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that changes the epoch" $
            changed (\f -> f{fEpoch = fEpoch f + 1}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that sets the poison" $
            changed (\f -> f{fPoisoned = True}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that sets the frozen flag" $
            changed (\f -> f{fFrozen = True}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that changes the refund address" $
            changed (\f -> f{fRefundTo = BS.replicate 29 0x62}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor that changes the keys" $
            changed (\f -> f{fKeys = (fKeys f){kmCurThreshold = Unweighted 2}})
                `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor with the birth time lowered" $
            changed (\f -> f{fBornAt = fBornAt f - 1}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor with the birth time raised" $
            changed (\f -> f{fBornAt = fBornAt f + 1}) `shouldBe` Just TopUpSuccessorNotTheMarkedCopy
        it "refuses a successor holding one lovelace less" $
            refusal (honest (tuPremium params)){tiSuccessorLovelace = tiSuccessorLovelace (honest (tuPremium params)) - 1}
                `shouldBe` Just TopUpSuccessorValueMismatch
        it "refuses a successor holding one lovelace more" $
            refusal (honest (tuPremium params)){tiSuccessorLovelace = tiSuccessorLovelace (honest (tuPremium params)) + 1}
                `shouldBe` Just TopUpSuccessorValueMismatch
        it "refuses a spent output below its floor" $
            refusal (honest (tuPremium params)){tiSpentLovelace = floorOf (live False False False) - 1}
                `shouldBe` Just TopUpBelowFloor
