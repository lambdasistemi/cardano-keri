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

    -- * Lifecycle: the conviction-record datum
    TombstoneV1 (..),

    -- * Output-shape layer
    AddressRole (..),
    OutputDatum (..),
    ContinuingOutput (..),
    ConvictOutputError (..),
    convictOutputPredicate,
    FreezeOutputError (..),
    freezeOutputPredicate,
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
    | {- | The evidence agrees with the tip on @n@\/@nt@\/@bt@ (the whole
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
  4. witnessed anti-fork gate — at least @toad@ witness receipts verify over
     'eeEventBytes' against the tip's witnesses (vacuous when @toad == 0@);
  5. conflict — the event diverges from the tip on at least one of
     @(next_keys, next_threshold, toad)@ (@n@\/@nt@\/@bt@; the witness set is
     NOT a conflict axis) — agreement everywhere is not a conflict and is
     rejected.
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
    -- 4. witnessed anti-fork gate: the conflicting event must carry at least
    --    @toad@ verifying witness receipts (only a real published duplicity can
    --    convict). @toad == 0@ is the vacuous witnessless tier. Mirrors the
    --    freeze predicate's witness check.
    let receipts =
            length
                [ ()
                | (idx, sig) <- eeWitSigs e
                , Just w <- [cdWitnesses d `atMay` idx]
                , verifyEd25519 w (eeEventBytes e) sig
                ]
    unless (fromIntegral receipts >= cdToad d) (Left CvInsufficientReceipts)
    -- 5. conflict: any single forward mismatch on @n@\/@nt@\/@bt@; agreement
    --    everywhere = reject. The witness set is NOT a conflict axis — a KERI
    --    rotation restates no @b@ (only the @br@\/@ba@ delta), so @eeWitnesses@
    --    is always @[]@ and comparing it to a witnessed tip would phantom-convict
    --    the AID's own honest rotation.
    let agrees =
            eeNextKeys e == cdNextKeys d
                && eeNextThreshold e == cdNextThreshold d
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

-- ---------------------------------------------------------
-- Lifecycle: the conviction-record datum (TombstoneV1)
-- ---------------------------------------------------------

{- | The conviction record a @Convict@ spend writes to the tombstone output
(a NEW frozen wire type; @Constr 0@, three fields in order). It records the
convicted AID, the native sn the double-sign occurred at, and the raw
(E-code-stripped) SAID of the conflicting event.
-}
data TombstoneV1 = TombstoneV1
    { tvCesrAid :: !CesrAid
    -- ^ the convicted AID (KERI @i@, raw)
    , tvConvictedAtNativeSn :: !Integer
    -- ^ the native sn the conflicting reveal occurred at
    , tvEvidenceSaid :: !ByteString
    -- ^ the conflicting event's SAID (KERI @d@, raw)
    }
    deriving stock (Show, Eq)

-- | @Constr 0 [B cesr_aid, I convicted_at_native_sn, B evidence_said]@.
instance ToData TombstoneV1 where
    toBuiltinData TombstoneV1{..} =
        BuiltinData $
            Constr
                0
                [ B tvCesrAid
                , I tvConvictedAtNativeSn
                , B tvEvidenceSaid
                ]

instance FromData TombstoneV1 where
    fromBuiltinData (BuiltinData (Constr 0 [B cesr, I sn, B said])) =
        Just (TombstoneV1 cesr sn said)
    fromBuiltinData _ = Nothing

-- ---------------------------------------------------------
-- Output-shape layer (spec Convict 6 / Freeze 4)
-- ---------------------------------------------------------

-- | The role of a continuing-output's script address in the #106 lifecycle.
data AddressRole = Active | Frozen | Tombstone
    deriving stock (Show, Eq)

{- | The datum carried by a continuing output: either the ongoing checkpoint
state or the terminal conviction record.
-}
data OutputDatum
    = CheckpointOutput CheckpointDatumV1
    | TombstoneOutput TombstoneV1
    deriving stock (Show, Eq)

{- | An abstract continuing-output descriptor — the schema-layer projection of a
transaction output (role, whether it carries the identity token, and its
datum), NOT the ledger's @TxOut@. The output-shape predicates operate on this.
-}
data ContinuingOutput = ContinuingOutput
    { coRole :: !AddressRole
    , coHasToken :: !Bool
    , coDatum :: !OutputDatum
    }
    deriving stock (Show, Eq)

-- | A conviction output-shape rejection reason (one constructor per check).
data ConvictOutputError
    = -- | The continuing output is not at the tombstone role.
      CoNotTombstone
    | -- | The continuing output does not carry the identity token.
      CoMissingToken
    | -- | The datum is not the exact expected 'TombstoneV1' conviction record.
      CoWrongRecord
    deriving stock (Show, Eq)

{- | Convict output shape (spec Convict 6): the continuing output must sit at the
tombstone role, carry the token, and hold exactly
@TombstoneV1 tip.cesr_aid tip.native_sn evidence.said@.
-}
convictOutputPredicate ::
    CheckpointDatumV1 ->
    EventEvidence ->
    ContinuingOutput ->
    Either ConvictOutputError ()
convictOutputPredicate tip e out = do
    unless (coRole out == Tombstone) (Left CoNotTombstone)
    unless (coHasToken out) (Left CoMissingToken)
    let expected =
            TombstoneOutput
                ( TombstoneV1
                    (cdCesrAid tip)
                    (cdNativeSn tip)
                    (eeSaid e)
                )
    unless (coDatum out == expected) (Left CoWrongRecord)

-- | A freeze output-shape rejection reason (one constructor per check).
data FreezeOutputError
    = -- | The continuing output is not at the frozen role.
      FoNotFrozen
    | -- | The continuing output does not carry the identity token.
      FoMissingToken
    | -- | The datum is not byte-identical to the tip checkpoint datum.
      FoDatumChanged
    deriving stock (Show, Eq)

{- | Freeze output shape (spec Freeze 4): the continuing output must sit at the
frozen role, carry the token, and hold the tip checkpoint datum unchanged.
-}
freezeOutputPredicate ::
    CheckpointDatumV1 ->
    ContinuingOutput ->
    Either FreezeOutputError ()
freezeOutputPredicate tip out = do
    unless (coRole out == Frozen) (Left FoNotFrozen)
    unless (coHasToken out) (Left FoMissingToken)
    unless (coDatum out == CheckpointOutput tip) (Left FoDatumChanged)
