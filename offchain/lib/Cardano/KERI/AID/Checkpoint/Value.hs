{- |
Module      : Cardano.KERI.AID.Checkpoint.Value
Description : The lovelace a version 2 checkpoint output holds

The datum carries the facts of a checkpoint; the deposit, the freeze bond and
the premium pool are held in the output's value (Lean @State.valueFloor@,
@State.heldValue@, @State.withValue@). Every function takes the amounts as
arguments: @mc@ the registry's minimum ADA, @d@ the checkpoint deposit, @b@
the freeze bond.
-}
module Cardano.KERI.AID.Checkpoint.Value (
    checkpointMinAda,
    valueFloor,
    heldValue,
    withValue,
    rotationSettlement,
    RotationSettlement (..),
) where

import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV2 (..))

-- | The registry's minimum ADA of a checkpoint output (Lean @Mc@).
checkpointMinAda :: Integer
checkpointMinAda = 2_000_000

{- | The amount below which an output with these facts cannot hold the deposit
and freeze bond its state says it holds.
-}
valueFloor :: Integer -> Integer -> Integer -> CheckpointDatumV2 -> Integer
valueFloor mc d b = \case
    Live{lvFrozen}
        | lvFrozen -> mc + d
        | otherwise -> mc + d + b
    TerminationPending{} -> mc

{- | The lovelace an output with these facts and this pool holds. A pending
termination holds the minimum ADA whatever pool is given.
-}
heldValue ::
    Integer -> Integer -> Integer -> CheckpointDatumV2 -> Integer -> Integer
heldValue mc d b facts pool = case facts of
    Live{} -> valueFloor mc d b facts + pool
    TerminationPending{} -> mc

{- | The pool the facts and the lovelace determine: what a live output holds
above its floor. 'Nothing' below the floor (live) or away from the minimum
ADA (pending).
-}
withValue ::
    Integer ->
    Integer ->
    Integer ->
    CheckpointDatumV2 ->
    Integer ->
    Maybe Integer
withValue mc d b facts lovelace = case facts of
    Live{}
        | floor' <= lovelace -> Just (lovelace - floor')
        | otherwise -> Nothing
      where
        floor' = valueFloor mc d b facts
    TerminationPending{}
        | lovelace == mc -> Just 0
        | otherwise -> Nothing

{- | What a rotation settles: the premium paid out of the pool (zero when the
pool does not cover it) and the pool the successor keeps.
-}
data RotationSettlement = RotationSettlement
    { settlementPaid :: !Integer
    -- ^ lovelace paid to the payee output (the premium, or nothing)
    , settlementPoolAfter :: !Integer
    -- ^ the successor's pool
    }
    deriving stock (Show, Eq)

{- | The settlement of a rotation of an output holding this lovelace: the
premium is paid when the pool covers it. 'Nothing' for an input that is not a
live output at or above its floor.
-}
rotationSettlement ::
    Integer ->
    Integer ->
    Integer ->
    Integer ->
    CheckpointDatumV2 ->
    Integer ->
    Maybe RotationSettlement
rotationSettlement mc d b premium facts lovelace = case facts of
    TerminationPending{} -> Nothing
    Live{} -> do
        pool <- withValue mc d b facts lovelace
        pure $
            if premium <= pool
                then
                    RotationSettlement
                        { settlementPaid = premium
                        , settlementPoolAfter = pool - premium
                        }
                else
                    RotationSettlement
                        { settlementPaid = 0
                        , settlementPoolAfter = pool
                        }
