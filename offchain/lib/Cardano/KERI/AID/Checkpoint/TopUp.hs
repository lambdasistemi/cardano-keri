{- |
Module      : Cardano.KERI.AID.Checkpoint.TopUp
Description : The bounded top-up of a live checkpoint (#522, Lean @Step.topUp@)

Anyone may add at least one premium to the pool of a live checkpoint, once per
key state. The successor is the spent datum with the top-up mark set and holds
exactly the amount more; nothing is signed and no rotation evidence is read.
Every rotation clears the mark, so a checkpoint is topped up at most once
between two rotations. The registration needs a first pool of at least one
premium (Lean @Step.register@, @p.P ≤ pool0@).

The refusal names are the Lean simulator's: @pool-below-premium@,
@already-topped-up@ and @top-up-below-premium@.
-}
module Cardano.KERI.AID.Checkpoint.TopUp (
    TopUpParams (..),
    TopUpInput (..),
    TopUpRefusal (..),
    TopUpSettlement (..),
    markedLive,
    topUpSettlement,
    topUpVerdict,
    topUpRefusalName,
    registrationPool,
    registrationVerdict,
    RegistrationRefusal (..),
    registrationRefusalName,
) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..))
import Cardano.KERI.AID.Checkpoint.Value (heldValue, withValue)
import Control.Monad (guard, unless)

-- | The deployment amounts, in lovelace.
data TopUpParams = TopUpParams
    { tuMinAda :: !Integer
    , tuDeposit :: !Integer
    , tuBond :: !Integer
    , tuPremium :: !Integer
    }
    deriving stock (Show, Eq)

-- | A top-up as the validator sees it.
data TopUpInput = TopUpInput
    { tiSpentDatum :: !CheckpointDatumV2
    , tiSpentLovelace :: !Integer
    , tiAmount :: !Integer
    -- ^ the redeemer's amount
    , tiSuccessorDatum :: !CheckpointDatumV2
    , tiSuccessorLovelace :: !Integer
    }
    deriving stock (Show, Eq)

-- | What a top-up settles.
data TopUpSettlement = TopUpSettlement
    { tsSuccessorLovelace :: !Integer
    -- ^ what the marked successor holds, exactly
    , tsPool :: !Integer
    -- ^ the pool the successor holds
    }
    deriving stock (Show, Eq)

-- | Why a top-up is refused.
data TopUpRefusal
    = TopUpNotLive
    | TopUpAlreadyToppedUp
    | TopUpBelowPremium
    | TopUpBelowFloor
    | TopUpSuccessorNotTheMarkedCopy
    | TopUpSuccessorValueMismatch
    deriving stock (Show, Eq)

{- | The Lean simulator's refusal name of a top-up refusal, for the premises
the Lean states; the others are the validator's.
-}
topUpRefusalName :: TopUpRefusal -> String
topUpRefusalName = \case
    TopUpNotLive -> "not-live"
    TopUpAlreadyToppedUp -> "already-topped-up"
    TopUpBelowPremium -> "top-up-below-premium"
    TopUpBelowFloor -> "below-floor"
    TopUpSuccessorNotTheMarkedCopy -> "successor-not-the-marked-copy"
    TopUpSuccessorValueMismatch -> "successor-value-mismatch"

{- | The datum a top-up writes: the live datum with the top-up mark set.
'Nothing' for a datum that is not live or is already topped up.
-}
markedLive :: CheckpointDatumV2 -> Maybe CheckpointDatumV2
markedLive = \case
    d@Live{lvToppedUp = False} -> Just d{lvToppedUp = True}
    _ -> Nothing

{- | What a top-up of this amount settles for an output holding this lovelace.
'Nothing' when the datum cannot be marked, the amount is below the premium,
or the output is below its floor.
-}
topUpSettlement ::
    TopUpParams -> CheckpointDatumV2 -> Integer -> Integer -> Maybe TopUpSettlement
topUpSettlement TopUpParams{..} facts lovelace amount = do
    successor <- markedLive facts
    guard (tuPremium <= amount)
    pool <- withValue tuMinAda tuDeposit tuBond facts lovelace
    pure
        TopUpSettlement
            { tsSuccessorLovelace =
                heldValue tuMinAda tuDeposit tuBond successor (pool + amount)
            , tsPool = pool + amount
            }

{- | The Haskell verdict of a top-up: the validator's premises, in order. The
refusal that names a premise of the Lean is the first that fails.
-}
topUpVerdict :: TopUpParams -> TopUpInput -> Either TopUpRefusal ()
topUpVerdict params@TopUpParams{..} TopUpInput{..} = do
    case tiSpentDatum of
        TerminationPending{} -> Left TopUpNotLive
        Live{lvToppedUp = True} -> Left TopUpAlreadyToppedUp
        Live{} -> Right ()
    unless (tuPremium <= tiAmount) $ Left TopUpBelowPremium
    _ <-
        maybe
            (Left TopUpBelowFloor)
            Right
            ( withValue
                tuMinAda
                tuDeposit
                tuBond
                tiSpentDatum
                tiSpentLovelace
            )
    settlement <-
        maybe
            (Left TopUpNotLive)
            Right
            (topUpSettlement params tiSpentDatum tiSpentLovelace tiAmount)
    unless (Just tiSuccessorDatum == markedLive tiSpentDatum) $
        Left TopUpSuccessorNotTheMarkedCopy
    unless (tiSuccessorLovelace == tsSuccessorLovelace settlement) $
        Left TopUpSuccessorValueMismatch

{- | The first pool of a registration: what the carrier holds above the minimum
ADA, the deposit and the bond. 'Nothing' below that floor.
-}
registrationPool :: Integer -> Integer -> Integer -> Integer -> Maybe Integer
registrationPool mc d b carrier = do
    let floor' = mc + d + b
    guard (floor' <= carrier)
    pure (carrier - floor')

-- | Why a registration is refused for its pool.
data RegistrationRefusal
    = RegistrationBelowFloor
    | RegistrationPoolBelowPremium
    deriving stock (Show, Eq)

-- | The Lean simulator's refusal name.
registrationRefusalName :: RegistrationRefusal -> String
registrationRefusalName = \case
    RegistrationBelowFloor -> "below-floor"
    RegistrationPoolBelowPremium -> "pool-below-premium"

-- | The registration's pool premise (Lean @Step.register@: @p.P ≤ pool0@).
registrationVerdict ::
    TopUpParams -> Integer -> Either RegistrationRefusal Integer
registrationVerdict TopUpParams{..} carrier = do
    pool <-
        maybe
            (Left RegistrationBelowFloor)
            Right
            (registrationPool tuMinAda tuDeposit tuBond carrier)
    unless (tuPremium <= pool) $ Left RegistrationPoolBelowPremium
    pure pool
