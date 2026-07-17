{- |
Module      : Cardano.KERI.AID.Checkpoint.Enforcement
Description : Convict\/Freeze divergence-enforcement predicates, #106

Validator-free schema-support layer, the same shape as
"Cardano.KERI.AID.Checkpoint.Message": pure predicates over already-decoded
KERI establishment-event evidence ('EventEvidence') plus the tip
'CheckpointDatumV1', returning @Either <Error> ()@ with one constructor per
check, evaluated in order.

The evidence is __decoded__: offset\/slice extraction over the raw CESR event
is @#24@'s on-chain concern, not this layer's. O1 is resolved — all controller
and witness signatures verify over 'eeEventBytes' (the full event
serialization, @serder.raw@), never the SAID.

The two predicates share the establishment-event gate (@rot@, same AID, a
sequence relation) then diverge: 'convictPredicate' proves a __double-sign__
(same reveal at the same sn, diverging forward commitment); 'freezePredicate'
proves a __committed, witnessed later event__ (the checkpoint is behind).
-}
module Cardano.KERI.AID.Checkpoint.Enforcement (
    -- * Decoded event evidence
    EventEvidence (..),

    -- * Convict (fork -> tombstone)
    ConvictError (..),
    convictPredicate,

    -- * Freeze (lag -> frozen)
    FreezeError (..),
    freezePredicate,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (
    blake3Hash,
 )
import Cardano.KERI.AID.CESR (
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CesrAid,
    CheckpointDatumV1 (..),
    KeyDigest,
    Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold,
    evaluate,
 )
import Cardano.KERI.AID.Ed25519 (
    verifyEd25519,
 )
import Control.Monad (
    forM,
    unless,
    when,
 )
import Data.ByteString (
    ByteString,
 )
import Data.IntSet qualified as IntSet
import Data.List (
    elemIndex,
 )

-- ---------------------------------------------------------
-- Decoded event evidence
-- ---------------------------------------------------------

{- | A decoded KERI establishment event, with the fields the predicates need
lifted out and the raw serialization retained as the signature target (O1:
every signature verifies over 'eeEventBytes'). Signatures are carried as
@(index, raw signature)@ pairs — controller signatures index into
'eeRevealedKeys' (the event's own @k@), witness receipts index into the tip
datum's stored witness set.
-}
data EventEvidence = EventEvidence
    { eeEventBytes :: !ByteString
    -- ^ @serder.raw@ — the full serialization, the signature target (O1)
    , eeType :: !ByteString
    -- ^ KERI @t@ (e.g. @"rot"@)
    , eeNativeSn :: !Integer
    -- ^ KERI native sequence number @s@
    , eeCesrAid :: !CesrAid
    -- ^ KERI @i@, raw (E-code stripped)
    , eeRevealedKeys :: ![Verkey]
    -- ^ KERI @k@, raw verkeys
    , eeNextKeys :: ![KeyDigest]
    -- ^ KERI @n@, raw pre-rotation digests
    , eeCurThreshold :: !Threshold
    -- ^ KERI @kt@
    , eeNextThreshold :: !Threshold
    -- ^ KERI @nt@
    , eeWitnesses :: ![Verkey]
    -- ^ KERI @b@, raw
    , eeToad :: !Integer
    -- ^ KERI @bt@
    , eeCtrlSigs :: ![(Int, ByteString)]
    -- ^ @(index into 'eeRevealedKeys', raw signature)@
    , eeWitSigs :: ![(Int, ByteString)]
    -- ^ @(index into the tip datum's witnesses, raw signature)@
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- Convict (fork -> tombstone)
-- ---------------------------------------------------------

-- | A conviction rejection reason (one constructor per ordered check).
data ConvictError
    = -- | The evidence is not a rotation (@t /= "rot"@).
      CvNotRotation
    | -- | The evidence is for a different AID than the tip.
      CvAidMismatch
    | -- | The evidence sn is not the tip's @native_sn@ (not the same event slot).
      CvSeqMismatch
    | -- | The evidence does not reveal exactly the tip's @cur_keys@.
      CvRevealMismatch
    | -- | The verifying controller signatures do not satisfy @cur_threshold@.
      CvQuorumUnsatisfied
    | -- | The evidence agrees with the tip on the whole forward commitment.
      CvNoConflict
    deriving stock (Show, Eq)

{- | The conviction predicate: a rotation at the tip's own sn revealing the tip's
own @cur_keys@ (a double-sign of one commitment), attributed to the current
quorum, that diverges from the tip on any forward field. Checks in order (spec
"The @Convict@ predicate"):

  1. establishment gate — @rot@, same AID, @native_sn@ equal to the tip's;
  2. same reveal — @k@ equals the tip's @cur_keys@ positionally;
  3. controller attribution — the positions whose signature verifies over
     'eeEventBytes' satisfy the tip's @cur_threshold@;
  4. conflict — the event diverges from the tip on at least one of
     @(next_keys, next_threshold, witnesses, toad)@ (agreement everywhere is
     not a conflict and is rejected).
-}
convictPredicate ::
    CheckpointDatumV1 -> EventEvidence -> Either ConvictError ()
convictPredicate d e = do
    -- 1. establishment gate.
    unless (eeType e == "rot") (Left CvNotRotation)
    unless (eeCesrAid e == cdCesrAid d) (Left CvAidMismatch)
    unless (eeNativeSn e == cdNativeSn d) (Left CvSeqMismatch)
    -- 2. same reveal at the same sn (this is what makes it a double-sign).
    unless (eeRevealedKeys e == cdCurKeys d) (Left CvRevealMismatch)
    -- 3. controller attribution over the tip's current keys.
    let signed =
            IntSet.fromList
                [ idx
                | (idx, sig) <- eeCtrlSigs e
                , Just k <- [cdCurKeys d `atMay` idx]
                , verifyEd25519 k (eeEventBytes e) sig
                ]
    unless
        (evaluate (cdCurThreshold d) (length (cdCurKeys d)) signed)
        (Left CvQuorumUnsatisfied)
    -- 4. conflict: any single forward mismatch; agreement everywhere = reject.
    let agrees =
            eeNextKeys e == cdNextKeys d
                && eeNextThreshold e == cdNextThreshold d
                && eeWitnesses e == cdWitnesses d
                && eeToad e == cdToad d
    when agrees (Left CvNoConflict)

-- ---------------------------------------------------------
-- Freeze (lag -> frozen)
-- ---------------------------------------------------------

-- | A freeze rejection reason (one constructor per ordered check).
data FreezeError
    = -- | The evidence is not a rotation (@t /= "rot"@).
      FzNotRotation
    | -- | The evidence is for a different AID than the tip.
      FzAidMismatch
    | -- | The evidence sn is not strictly ahead of the tip's @native_sn@.
      FzNotAhead
    | -- | A verifying revealed key's digest is not in the tip's @next_keys@.
      FzUncommittedReveal
    | -- | The committed positions do not satisfy the tip's @next_threshold@.
      FzPriorQuorumUnsatisfied
    | -- | Verifying witness receipts number fewer than the tip's @toad@.
      FzInsufficientReceipts
    deriving stock (Show, Eq)

{- | The freeze predicate: a rotation strictly ahead of the tip that provably
spends the tip's own pre-rotation commitment and carries enough witness
receipts. Checks in order (spec "The @Freeze@ predicate"):

  1. establishment gate — @rot@, same AID, @native_sn@ strictly greater;
  2. committed reveal + prior quorum — each verifying revealed key's
     @blake3(qb64(key))@ digest locates a position in the tip's @next_keys@
     (an unlocated one is 'FzUncommittedReveal'), and those positions satisfy
     the tip's @next_threshold@;
  3. witnessed — witness receipts verifying over 'eeEventBytes' against the
     tip's witnesses number at least the tip's @toad@ (vacuous when @toad ==
     0@, the documented weaker witnessless tier).
-}
freezePredicate ::
    CheckpointDatumV1 -> EventEvidence -> Either FreezeError ()
freezePredicate d e = do
    -- 1. establishment gate; the event is strictly ahead of the checkpoint.
    unless (eeType e == "rot") (Left FzNotRotation)
    unless (eeCesrAid e == cdCesrAid d) (Left FzAidMismatch)
    unless (eeNativeSn e > cdNativeSn d) (Left FzNotAhead)
    -- 2. committed reveal: each verifying key must sit in the pre-rotation
    --    commitment (blake3 over its qb64), and the located positions must
    --    satisfy the committed next threshold (KERI pre-rotation gate).
    let verifiedKeys =
            [ k
            | (idx, sig) <- eeCtrlSigs e
            , Just k <- [eeRevealedKeys e `atMay` idx]
            , verifyEd25519 k (eeEventBytes e) sig
            ]
    positions <-
        forM verifiedKeys $ \k ->
            case elemIndex (blake3Hash (qb64Verkey k)) (cdNextKeys d) of
                Just p -> Right p
                Nothing -> Left FzUncommittedReveal
    unless
        ( evaluate
            (cdNextThreshold d)
            (length (cdNextKeys d))
            (IntSet.fromList positions)
        )
        (Left FzPriorQuorumUnsatisfied)
    -- 3. witnessed: receipts over the tip's witnesses meet toad (0 = vacuous).
    let receipts =
            length
                [ ()
                | (idx, sig) <- eeWitSigs e
                , Just w <- [cdWitnesses d `atMay` idx]
                , verifyEd25519 w (eeEventBytes e) sig
                ]
    unless (fromIntegral receipts >= cdToad d) (Left FzInsufficientReceipts)

-- ---------------------------------------------------------
-- Helper
-- ---------------------------------------------------------

-- | Total safe list indexing.
atMay :: [a] -> Int -> Maybe a
atMay xs i
    | i < 0 = Nothing
    | otherwise = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing
