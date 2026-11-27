{- |
Module      : LegacyRegistration
Description : The nine-offset registration predicate the validators on main still read

The Aiken registration vectors are checked against validators whose evidence
type carries nine offsets. Their expected verdicts, misdirection rows
included, come from this frozen copy of the earlier Haskell predicate. It is
read by the vector generator only; no builder or command uses it. It is
deleted together with the offset-bearing vectors when the offset-free
validators merge.
-}
module LegacyRegistration (
    RegistrationEvidence (..),
    registrationPredicate,
) where

import Cardano.KERI.AID.CESR (qb64Aid, qb64Verkey)
import Cardano.KERI.AID.Checkpoint.Datum (KeyStateView (..))
import Cardano.KERI.AID.Checkpoint.Registration (
    DeploymentContext (..),
    EventType (..),
    RegistrationError (..),
    qb64WitnessVerkey,
    respellHex,
    respellThreshold,
    validRegistrationDeposit,
    validateInceptionDatum,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (evaluate)
import Cardano.KERI.AID.Ed25519 (verifyEd25519)
import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet

-- | The evidence of the earlier layout: the signed bytes, nine positions and the attachments.
data RegistrationEvidence = RegistrationEvidence
    { reEventBytes :: !ByteString
    -- ^ the full keripy @icp@ serialization (@serder.raw@)
    , reOffT :: !Int
    -- ^ offset of the event-type value (@t@)
    , reOffI :: !Int
    -- ^ offset of the 44-char qb64 AID (@i@)
    , reOffS :: !Int
    -- ^ offset of the hex sequence-number value (@s@)
    , reOffK :: ![Int]
    -- ^ offsets of the 44-char qb64 @k@ entries
    , reOffKt :: !Int
    -- ^ offset of the @kt@ JSON value
    , reOffN :: ![Int]
    -- ^ offsets of the 44-char qb64 @n@ entries
    , reOffNt :: !Int
    -- ^ offset of the @nt@ JSON value
    , reOffB :: ![Int]
    -- ^ offsets of the 44-char qb64 @b@ entries
    , reOffBt :: !Int
    -- ^ offset of the @bt@ JSON value
    , reCtrlSigs :: ![(Int, ByteString)]
    -- ^ @(index into cur_keys, signature over event_bytes)@
    , reWitReceipts :: ![(Int, ByteString)]
    -- ^ @(index into witnesses, receipt signature over event_bytes)@
    }
    deriving stock (Show, Eq)

{- | R6 — the E1-E9 event-binding slice set. Every expected value
is computed from the datum (derivation-code-prefixed qb64 or exact
re-spelling); the prover's offsets only locate it. A slice is
checked bounds-first, so a truncated (tail) or negative offset
fails its field's check like any mismatch.
-}
eventBinding ::
    KeyStateView ->
    RegistrationEvidence ->
    Either RegistrationError ()
eventBinding d e = do
    unless (slice (reOffT e) "icp") (Left E1EventTypeMismatch)
    unless
        (slice (reOffI e) (qb64Aid (cdCesrAid d)))
        (Left E2AidMismatch)
    unless (slice (reOffS e) "0") (Left E3SequenceMismatch)
    unless
        (slices (reOffK e) (map qb64Verkey (cdCurKeys d)))
        (Left E4CurKeysMismatch)
    unless
        (slice (reOffKt e) (respellThreshold (cdCurThreshold d)))
        (Left E5CurThresholdMismatch)
    unless
        (slices (reOffN e) (map qb64Aid (cdNextKeys d)))
        (Left E6NextKeysMismatch)
    unless
        (slice (reOffNt e) (respellThreshold (cdNextThreshold d)))
        (Left E7NextThresholdMismatch)
    unless
        (slices (reOffB e) (map qb64WitnessVerkey (cdWitnesses d)))
        (Left E8WitnessesMismatch)
    unless
        (slice (reOffBt e) (respellHex (cdToad d)))
        (Left E9ToadMismatch)
  where
    slice = sliceMatches (reEventBytes e)
    slices offs expected =
        length offs == length expected
            && and (zipWith slice offs expected)

{- | The pure registration predicate: R3, R6 (E1-E9), R4, R7, R8,
in order. R6 precedes R4 because E1's verified @t@ slice is what
derives R4's 'EventType' (after E1 only 'Icp' can reach it);
misdirected offsets that force a duplicate datum key slip past E4
only to fail R4's F18 (rule 2). The @lovelace@ argument is the
state output's value the R8 arithmetic runs over; transaction
shape itself (R1\/R2\/R5) is the S5 validator layer.
-}
registrationPredicate ::
    DeploymentContext ->
    -- | The inline datum @D@ of the genesis state output.
    KeyStateView ->
    -- | The state output's lovelace (R8).
    Integer ->
    RegistrationEvidence ->
    Either RegistrationError ()
registrationPredicate ctx d lovelace e = do
    unless (validRegistrationDeposit (dcDReg ctx)) (Left DRegBelowMinimum)
    -- R3: genesis projection.
    unless (cdSeq d == 0) (Left R3GenesisDatumMismatch)
    -- R6: the event-binding slice set (E1 derives R4's type).
    eventBinding d e
    -- R4: the frozen #68 schema predicate, reused.
    first R4InceptionInvalid (validateInceptionDatum Icp d)
    -- R7: distinct controller positions over exact event bytes.
    let signed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- reCtrlSigs e
                , Just k <- [cdCurKeys d `atMay` idx]
                , verifyEd25519 k (reEventBytes e) sig
                ]
    unless
        (evaluate (cdCurThreshold d) (length (cdCurKeys d)) signed)
        (Left R7QuorumUnsatisfied)
    -- R7: distinct witness receipt positions over those same bytes. A
    -- zero-toad event accepts only a literally empty evidence list.
    let witnessed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- reWitReceipts e
                , Just k <- [cdWitnesses d `atMay` idx]
                , verifyEd25519 k (reEventBytes e) sig
                ]
        receiptsSatisfied
            | cdToad d == 0 = null (reWitReceipts e)
            | otherwise =
                toInteger (IntSet.size witnessed) >= cdToad d
    unless receiptsSatisfied (Left R7WitnessQuorumUnsatisfied)
    -- R8: deposit floor.
    unless
        (lovelace >= dcMinAda ctx + dcDReg ctx)
        (Left R8DepositBelowMinimum)

-- ---------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------

{- | Does the slice of @raw@ at @off@ equal @expected@?
Bounds-checked: an out-of-range span never matches.
-}
sliceMatches :: ByteString -> Int -> ByteString -> Bool
sliceMatches raw off expected =
    off >= 0
        && off + n <= BS.length raw
        && BS.take n (BS.drop off raw) == expected
  where
    n = BS.length expected

-- | Total safe list indexing.
atMay :: [a] -> Int -> Maybe a
atMay xs i
    | i < 0 = Nothing
    | otherwise = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing
