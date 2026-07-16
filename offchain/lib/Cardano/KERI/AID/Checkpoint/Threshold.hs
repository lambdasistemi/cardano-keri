{- |
Module      : Cardano.KERI.AID.Checkpoint.Threshold
Description : Frozen KERI @kt@\/@nt@ threshold wire codec (F18), #68

The KERI current\/next signing threshold as a frozen wire type with a
canonical Plutus 'Data' encoding, the F18 well-formedness predicate, and a
deterministic 'evaluate'. This is a validator-free schema-support layer: no
transaction context, no datum, no message types (those are later slices).

The constructor indices and field order are protocol surface (spec #68) and
are mirrored byte-for-byte by the Aiken encoder; they change only by minting
a new version tag.

@
Threshold                       -- PlutusData sum:
  = Unweighted Integer          --   Constr 0, fields [I m]
  | Weighted   [[Weight]]       --   Constr 1, fields [List of clauses]
Weight = Weight Integer Integer --   Constr 0, fields [I num, I den]
@

'toData'\/'fromData' use the deterministic Plutus 'Data' encoding (Constr
tags, 'I', definite lists). Order is positional and security-significant:
reordering weights within a clause or reordering clauses changes the bytes,
hence the commitment and the authority. 'fromData' rejects a non-canonical
(e.g. unreduced) 'Weight' rather than normalizing it (F18 rule 10).
-}
module Cardano.KERI.AID.Checkpoint.Threshold (
    -- * Types
    Threshold (..),
    Weight (..),
    ThresholdError (..),

    -- * Frozen V1 constant
    maxWeightDenom,

    -- * F18 well-formedness and evaluation
    wellFormed,
    evaluate,
) where

import Control.Monad (
    unless,
    when,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet (
    IntSet,
 )
import Data.IntSet qualified as IntSet
import Data.List (
    nub,
 )
import Data.Ratio (
    (%),
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
 )

-- ---------------------------------------------------------
-- Types
-- ---------------------------------------------------------

{- | A KERI signing threshold (@kt@\/@nt@): either an integer @m@-of-@n@ or a
fractionally weighted multi-clause threshold. Clauses partition the key list
positionally and are logically ANDed.
-}
data Threshold
    = -- | Integer @m@-of-@n@ (Constr 0). All keys carry implicit weight 1.
      Unweighted !Integer
    | -- | Fractionally weighted; clauses partition @cur_keys@ (Constr 1).
      Weighted ![[Weight]]
    deriving stock (Show, Eq)

{- | An exact rational weight @num\/den@ in reduced canonical form
(@den > 0@, @num >= 0@, @num <= den@, @gcd num den == 1@). Zero weights are
legal KERI (the reserve\/custodial-rotation pattern); the gcd rule makes
@0\/1@ the unique canonical zero spelling.
-}
data Weight = Weight !Integer !Integer
    deriving stock (Show, Eq)

-- | A specific F18 well-formedness rejection reason.
data ThresholdError
    = -- | Rule 1: empty key set.
      EmptyKeys
    | -- | Rule 2: duplicate 'KeyDigest'.
      DuplicateKey
    | -- | Rule 3: a key digest is not exactly 32 bytes.
      KeyWidth
    | -- | Rule 4: @Unweighted m@ with @m < 1@ or @m > n@.
      UnweightedRange
    | -- | Rule 5: empty clause set or an empty clause.
      EmptyClause
    | -- | Rule 6: clause lengths do not partition the key list.
      PartitionMismatch
    | -- | Rule 7: a weight has @den <= 0@.
      NonPositiveDen
    | -- | Rule 8: a weight has @num < 0@ (negative weight).
      NegativeNum
    | -- | Rule 9: a weight has @num > den@ (over unity).
      OverUnityWeight
    | -- | Rule 10: a weight is unreduced (@gcd num den /= 1@).
      UnreducedWeight
    | -- | Rule 11: a weight's denominator exceeds 'maxWeightDenom'.
      WeightOutOfBound
    | -- | Rule 12: a clause's weights sum to @< 1@ (unsatisfiable).
      UnsatisfiableClause
    deriving stock (Show, Eq)

{- | Frozen V1 upper bound on a 'Weight' denominator: @2^32 = 4294967296@
(F18 rule 11). Changing it requires a new version tag.
-}
maxWeightDenom :: Integer
maxWeightDenom = 4294967296

-- ---------------------------------------------------------
-- PlutusData codec
-- ---------------------------------------------------------

-- | @Weight num den@ -> @Constr 0 [I num, I den]@.
instance ToData Weight where
    toBuiltinData (Weight num den) =
        BuiltinData (Constr 0 [I num, I den])

-- | Rejects a non-canonical (e.g. unreduced) weight (F18 rules 7-10).
instance FromData Weight where
    fromBuiltinData (BuiltinData (Constr 0 [I num, I den]))
        | canonicalWeight num den = Just (Weight num den)
    fromBuiltinData _ = Nothing

-- | @Unweighted m@ -> @Constr 0 [I m]@; @Weighted@ -> @Constr 1 [List ...]@.
instance ToData Threshold where
    toBuiltinData (Unweighted m) =
        BuiltinData (Constr 0 [I m])
    toBuiltinData (Weighted clauses) =
        BuiltinData (Constr 1 [List (map clauseToData clauses)])
      where
        clauseToData c = List (map (unBuiltin . toBuiltinData) c)

instance FromData Threshold where
    fromBuiltinData (BuiltinData d) = case d of
        Constr 0 [I m] -> Just (Unweighted m)
        Constr 1 [List clauses] ->
            Weighted <$> traverse clauseFromData clauses
        _ -> Nothing
      where
        clauseFromData (List ws) =
            traverse (fromBuiltinData . BuiltinData) ws
        clauseFromData _ = Nothing

-- | Is @num\/den@ a reduced weight in @[0, 1]@ (F18 rules 7-10)?
canonicalWeight :: Integer -> Integer -> Bool
canonicalWeight num den =
    den > 0 && num >= 0 && num <= den && gcd num den == 1

unBuiltin :: BuiltinData -> Data
unBuiltin (BuiltinData d) = d

-- ---------------------------------------------------------
-- F18 well-formedness (rules 1-13)
-- ---------------------------------------------------------

{- | The F18 well-formedness predicate over a positional
@(cur_keys, threshold)@ pair. Total and deterministic; each rejection maps to
a specific 'ThresholdError'. Rule 13 (no nested weighted list) is enforced
structurally by the 'Weight' type and needs no runtime check.
-}
wellFormed :: [ByteString] -> Threshold -> Either ThresholdError ()
wellFormed keys th = do
    -- Rule 1: non-empty key set.
    when (null keys) (Left EmptyKeys)
    -- Rule 3: every key digest is exactly 32 bytes.
    unless (all ((== 32) . BS.length) keys) (Left KeyWidth)
    -- Rule 2: no duplicate key.
    when (length (nub keys) /= length keys) (Left DuplicateKey)
    case th of
        Unweighted m ->
            -- Rule 4: 1 <= m <= n.
            unless (1 <= m && m <= n) (Left UnweightedRange)
        Weighted clauses -> do
            -- Rule 5: clauses non-empty; each clause non-empty.
            when (null clauses || any null clauses) (Left EmptyClause)
            -- Rule 6: clause lengths partition the keys exactly once.
            unless
                (sum (map length clauses) == length keys)
                (Left PartitionMismatch)
            -- Rules 7-11: each weight is canonical and bounded.
            mapM_ checkWeight (concat clauses)
            -- Rule 12: each clause is satisfiable (sum of weights >= 1).
            mapM_ checkClauseSum clauses
  where
    n = fromIntegral (length keys) :: Integer

    checkWeight (Weight num den) = do
        when (den <= 0) (Left NonPositiveDen)
        when (num < 0) (Left NegativeNum)
        when (num > den) (Left OverUnityWeight)
        unless (gcd num den == 1) (Left UnreducedWeight)
        unless (den <= maxWeightDenom) (Left WeightOutOfBound)

    checkClauseSum c =
        unless
            (sum [num % den | Weight num den <- c] >= 1)
            (Left UnsatisfiableClause)

-- ---------------------------------------------------------
-- Evaluation
-- ---------------------------------------------------------

{- | Evaluate a threshold against @n@ (the key count) and the set of
positions whose signature verified. 'Unweighted' is satisfied when at least
@m@ valid positions signed; 'Weighted' is the AND over clauses, each clause
satisfied when the exact rational sum of its signed weights is @>= 1@.
Deterministic and order-independent within a clause.
-}
evaluate :: Threshold -> Int -> IntSet -> Bool
evaluate th n signers0 =
    case th of
        Unweighted m ->
            fromIntegral (IntSet.size signers) >= m
        Weighted clauses ->
            go 0 clauses
  where
    signers = IntSet.filter (\i -> i >= 0 && i < n) signers0

    go _ [] = True
    go off (c : cs) =
        clauseTotal >= 1 && go (off + length c) cs
      where
        clauseTotal =
            sum
                [ num % den
                | (p, Weight num den) <- zip [off ..] c
                , p `IntSet.member` signers
                ]
