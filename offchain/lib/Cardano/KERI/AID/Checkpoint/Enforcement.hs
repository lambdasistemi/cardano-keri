{- |
Module      : Cardano.KERI.AID.Checkpoint.Enforcement
Description : Convict divergence-enforcement predicate, #106

Validator-free schema-support layer: the 'EnforcementEvidence' wire binder
checks EE0-EE9 before constructing decoded 'EventEvidence', then the pure
predicates consume that decoded evidence plus the tip 'KeyStateView'. O1
is resolved — all controller and witness signatures verify over
'eeEventBytes' (the full event serialization, @serder.raw@), never the SAID.

The conviction predicate gates on the establishment event (@rot@, same AID, the
tip's own sequence number) and proves a __double-sign__ (same reveal at the
same sn, diverging forward commitment).
-}
module Cardano.KERI.AID.Checkpoint.Enforcement (
    -- * Signed wire evidence and EE0-EE9 binding
    EnforcementEvidence (..),
    EnforcementBindingError (..),
    bindEnforcementEvidence,

    -- * Decoded event evidence
    EventEvidence (..),

    -- * Convict (fork -> conviction)
    ConvictError (..),
    convictPredicate,
) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CesrAid,
    KeyDigest,
    KeyStateView (..),
    Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Registration (
    respellHex,
    respellThreshold,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold,
    evaluate,
 )
import Cardano.KERI.AID.Ed25519 (
    verifyEd25519,
 )
import Control.Monad (
    unless,
    when,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.IntSet qualified as IntSet
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins.Internal (
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    ToData (..),
 )

-- ---------------------------------------------------------
-- Signed wire evidence and EE0-EE9 binding
-- ---------------------------------------------------------

{- | The ratified V1 enforcement wire surface. Offsets locate exact KERI @rot@
field spellings inside 'eneEventBytes'; all content is independently carried
in decoded form and must bind before an 'EventEvidence' is created. There is
deliberately no @said_blank@ and no SAID recomputation.
-}
data EnforcementEvidence = EnforcementEvidence
    { eneEventBytes :: !ByteString
    , eneOffT :: !Int
    , eneOffI :: !Int
    , eneOffS :: !Int
    , eneOffD :: !Int
    , eneOffK :: ![Int]
    , eneOffKt :: !Int
    , eneOffN :: ![Int]
    , eneOffNt :: !Int
    , eneOffBt :: !Int
    , eneNativeSn :: !Integer
    , eneSaid :: !ByteString
    , eneRevealedKeys :: ![Verkey]
    , eneNextKeys :: ![KeyDigest]
    , eneCurThreshold :: !Threshold
    , eneNextThreshold :: !Threshold
    , eneToad :: !Integer
    , eneCtrlSigs :: ![(Int, ByteString)]
    , eneWitSigs :: ![(Int, ByteString)]
    }
    deriving stock (Show, Eq)

{- | The Aiken @EnforcementEvidence@ record: @Constr 0@ of 19 fields.

The encoder lives here, beside the type whose wire shape it is, because #254
S254-E made it load-bearing beyond transaction building: the canonical
enforcement evidence digest is @blake2b_256@ over exactly these bytes, and a
second copy of the field order would be a second thing to keep in step.
"Cardano.KERI.AID.Checkpoint.Wire" still exposes it as
@enforcementEvidenceData@ for the observer envelopes.
-}
instance ToData EnforcementEvidence where
    toBuiltinData EnforcementEvidence{..} =
        BuiltinData $
            Constr
                0
                [ B eneEventBytes
                , I (fromIntegral eneOffT)
                , I (fromIntegral eneOffI)
                , I (fromIntegral eneOffS)
                , I (fromIntegral eneOffD)
                , evidenceIntList eneOffK
                , I (fromIntegral eneOffKt)
                , evidenceIntList eneOffN
                , I (fromIntegral eneOffNt)
                , I (fromIntegral eneOffBt)
                , I eneNativeSn
                , B eneSaid
                , List (map B eneRevealedKeys)
                , List (map B eneNextKeys)
                , evidenceData eneCurThreshold
                , evidenceData eneNextThreshold
                , I eneToad
                , evidenceSignatureList eneCtrlSigs
                , evidenceSignatureList eneWitSigs
                ]

evidenceData :: (ToData a) => a -> Data
evidenceData value = let BuiltinData dat = toBuiltinData value in dat

evidenceIntList :: (Integral a) => [a] -> Data
evidenceIntList = List . map (I . fromIntegral)

-- | Aiken tuples are Data lists, not record-shaped constructors.
evidenceSignatureList :: [(Int, ByteString)] -> Data
evidenceSignatureList =
    List
        . map
            (\(index, signature) -> List [I (fromIntegral index), B signature])

-- | Structured rejection from the ordered EE0-EE9 wire binder.
data EnforcementBindingError
    = EE0EventBytesLength
    | EE1EventTypeMismatch
    | EE2AidMismatch
    | EE3SequenceMismatch
    | EE4SaidMismatch
    | EE5RevealedKeysMismatch
    | EE6CurThresholdMismatch
    | EE7NextKeysMismatch
    | EE8NextThresholdMismatch
    | EE9ToadMismatch
    deriving stock (Show, Eq)

{- | Bind a wire event to the tip/evidence AID, then construct decoded rotation
evidence. Checks are deliberately linear and ordered EE0 through EE9. The raw
event bytes and signature pairs are carried through byte-for-byte; rotations
have no V1 witness-restatement field, so decoded @b@ remains empty.
-}
bindEnforcementEvidence ::
    CesrAid ->
    EnforcementEvidence ->
    Either EnforcementBindingError EventEvidence
bindEnforcementEvidence aid e = do
    let raw = eneEventBytes e
        n = BS.length raw
        slice = sliceMatches raw
        slices offs expected =
            length offs == length expected
                && and (zipWith slice offs expected)
    unless (n >= 1 && n <= 1024) (Left EE0EventBytesLength)
    unless (slice (eneOffT e) "rot") (Left EE1EventTypeMismatch)
    unless (slice (eneOffI e) (qb64Aid aid)) (Left EE2AidMismatch)
    unless
        (slice (eneOffS e) (respellHex (eneNativeSn e)))
        (Left EE3SequenceMismatch)
    unless
        ( BS.length (eneSaid e) == 32
            && slice (eneOffD e) (qb64Aid (eneSaid e))
        )
        (Left EE4SaidMismatch)
    unless
        (slices (eneOffK e) (map qb64Verkey (eneRevealedKeys e)))
        (Left EE5RevealedKeysMismatch)
    unless
        (slice (eneOffKt e) (respellThreshold (eneCurThreshold e)))
        (Left EE6CurThresholdMismatch)
    unless
        (slices (eneOffN e) (map qb64Aid (eneNextKeys e)))
        (Left EE7NextKeysMismatch)
    unless
        (slice (eneOffNt e) (respellThreshold (eneNextThreshold e)))
        (Left EE8NextThresholdMismatch)
    unless
        (slice (eneOffBt e) (respellHex (eneToad e)))
        (Left EE9ToadMismatch)
    pure
        EventEvidence
            { eeEventBytes = raw
            , eeType = "rot"
            , eeNativeSn = eneNativeSn e
            , eeCesrAid = aid
            , eeSaid = eneSaid e
            , eeRevealedKeys = eneRevealedKeys e
            , eeNextKeys = eneNextKeys e
            , eeCurThreshold = eneCurThreshold e
            , eeNextThreshold = eneNextThreshold e
            , eeWitnesses = []
            , eeToad = eneToad e
            , eeCtrlSigs = eneCtrlSigs e
            , eeWitSigs = eneWitSigs e
            }

-- | Bounds-checked exact byte slice comparison.
sliceMatches :: ByteString -> Int -> ByteString -> Bool
sliceMatches raw off expected =
    off >= 0
        && BS.length expected <= BS.length raw
        && off <= BS.length raw - BS.length expected
        && BS.take (BS.length expected) (BS.drop off raw) == expected

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
    , eeSaid :: !ByteString
    -- ^ KERI @d@ (the event SAID), raw (E-code stripped)
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
    | {- | The conflicting event's witness receipts number fewer than the tip's
      @toad@ (an unwitnessed event cannot frame a witnessed identity).
      -}
      CvInsufficientReceipts
    | {- | The evidence agrees with the tip on @kt@\/@n@\/@nt@\/@bt@ (the whole
      conflict commitment) — not a conflict.
      -}
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
  4. witnessed anti-fork gate — at least @toad@ distinct witness indices have
     receipts verifying over 'eeEventBytes' (vacuous when @toad == 0@);
  5. conflict — the event diverges from the tip on at least one of
     @(cur_threshold, next_keys, next_threshold, toad)@
     (@kt@\/@n@\/@nt@\/@bt@; the witness set is NOT a conflict axis) —
     agreement everywhere is not a conflict and is rejected.
-}
convictPredicate ::
    KeyStateView -> EventEvidence -> Either ConvictError ()
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
    -- 4. witnessed anti-fork gate: the conflicting event must carry at least
    --    @toad@ verifying witness receipts (only a real published duplicity can
    --    convict). @toad == 0@ is the vacuous witnessless tier.
    let receiptIndices =
            IntSet.fromList
                [ idx
                | (idx, sig) <- eeWitSigs e
                , Just w <- [cdWitnesses d `atMay` idx]
                , verifyEd25519 w (eeEventBytes e) sig
                ]
    unless
        (fromIntegral (IntSet.size receiptIndices) >= cdToad d)
        (Left CvInsufficientReceipts)
    -- 5. conflict: any single forward mismatch on @kt@\/@n@\/@nt@\/@bt@; agreement
    --    everywhere = reject. The witness set is NOT a conflict axis — a KERI
    --    rotation restates no @b@ (only the @br@\/@ba@ delta), so @eeWitnesses@
    --    is always @[]@ and comparing it to a witnessed tip would phantom-convict
    --    the AID's own honest rotation.
    let agrees =
            eeCurThreshold e == cdCurThreshold d
                && eeNextKeys e == cdNextKeys d
                && eeNextThreshold e == cdNextThreshold d
                && eeToad e == cdToad d
    when agrees (Left CvNoConflict)

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
