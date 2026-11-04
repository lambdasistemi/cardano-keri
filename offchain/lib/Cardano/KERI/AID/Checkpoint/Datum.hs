{-# LANGUAGE NamedFieldPuns #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.Datum
Description : The checkpoint datum wire codec: the version 2 datum (#339) and the key state the event predicates run over

The checkpoint datum as a validator-free schema-support layer: the version 2
'CheckpointDatum' and the canonical Plutus 'Data' / CBOR serialization the Aiken
encoder mirrors byte-for-byte. The outer constructor is index 1; every other
index is refused when reading.

@
CheckpointDatum = V2 CheckpointDatumV2  -- Constr 1, wrapping the datum
@

The datum carries the facts of a checkpoint state:

@
CheckpointDatumV2
  = Live                -- Constr 0, 8 fields:
      { aid, sn, epoch, poisoned, frozen, born_at, refund_to, keys }
  | TerminationPending  -- Constr 1, 3 fields, no key material:
      { aid, sn, epoch }
KeyMaterial             -- Constr 0, 6 fields:
  { cur_keys, cur_threshold, next_keys, next_threshold, witnesses, toad }
@

@aid@ is the 44-character CESR text of the identifier, @refund_to@ the ledger
bytes of the address paid on conviction, booleans are Plutus's (@False@ is
constructor 0, @True@ constructor 1). The premium pool and the bond amounts
are held in the output's value, not in the datum.

Constructor indices and field order are protocol surface (spec #68); they
change only by minting a new version tag. The pre-rotation commitment is the
explicit @(next_keys, next_threshold)@ pair — the KERI @n@ digest list plus
@nt@ — so a rotation may reveal any satisfiable subset of the committed
digests (KERI partial\/reserve rotation) and restate its own current
threshold, exactly as the KERI dual-threshold rule allows. The contract is
E-native: @cesr_aid@ and the @next_keys@ entries are Blake3-256 values equal
byte-for-byte to production KERI KEL material, while @cur_keys@ hold raw
verkeys so the authorization hot path never hashes.
-}
module Cardano.KERI.AID.Checkpoint.Datum (
    -- * Fixed-width field aliases
    KeyDigest,
    Verkey,
    Digest32,
    CesrAid,

    -- * The versioned datum
    CheckpointDatum (..),
    KeyStateView (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),

    -- * Canonical serialization
    canonicalCbor,
    checkpointDatumFromData,
    checkpointDatumToData,
    blake2b_256,

    -- * Datum-level well-formedness (rule 14)
    DatumError (..),
    keyStateWellFormed,
    datumV2WellFormed,

    -- * The key-state view of a version 2 checkpoint
    keyStateView,
    datumKeyState,
    datumFacts,
    isTerminationPending,
    keyMaterialOf,
    rotatedLive,
    convictedOf,
    liveOfKeyState,
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_256,
 )
import Cardano.Crypto.Hash.Class (
    digest,
 )
import Cardano.KERI.AID.CESR (
    aidDigest,
    qb64Aid,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold,
    ThresholdError,
    wellFormed,
 )
import Control.Monad (
    unless,
    when,
 )
import Data.Bifunctor (
    first,
 )
import Data.ByteString (
    ByteString,
 )
import Data.ByteString qualified as BS
import Data.List (
    nub,
 )
import Data.Proxy (
    Proxy (..),
 )
import PlutusCore.Data (
    Data (..),
 )
import PlutusTx.Builtins (
    serialiseData,
 )
import PlutusTx.Builtins.Internal (
    BuiltinByteString (..),
    BuiltinData (..),
 )
import PlutusTx.IsData.Class (
    FromData (..),
    ToData (..),
 )

-- ---------------------------------------------------------
-- Fixed-width field aliases (spec "Primitive widths and domains")
-- ---------------------------------------------------------

{- | A pre-rotation next-key digest: @blake3_256(qb64(verkey))@ — the KERI
KEL @n@ entry byte-for-byte (E-code, the production KERI default).
-}
type KeyDigest = ByteString

-- | A raw 32-byte Ed25519 verkey (current keys and witnesses).
type Verkey = ByteString

-- | A 32-byte hash output.
type Digest32 = ByteString

-- | The external E-code-stripped 32-byte Blake3-256 AID digest.
type CesrAid = ByteString

-- ---------------------------------------------------------
-- Types
-- ---------------------------------------------------------

{- | The checkpoint datum: the version 2 datum under outer constructor index 1.
Every other constructor index is refused when reading.
-}
newtype CheckpointDatum
    = -- | Constr 1, wrapping the version 2 datum.
      V2 CheckpointDatumV2
    deriving stock (Show, Eq)

-- | The key material of a version 2 checkpoint: the key fields of 'KeyStateView'.
data KeyMaterial = KeyMaterial
    { kmCurKeys :: ![Verkey]
    -- ^ current establishment raw verkeys (KERI @k@)
    , kmCurThreshold :: !Threshold
    -- ^ current signing threshold (KERI @kt@)
    , kmNextKeys :: ![KeyDigest]
    -- ^ pre-rotation next-key digests (KERI @n@)
    , kmNextThreshold :: !Threshold
    -- ^ pre-rotation next threshold (KERI @nt@)
    , kmWitnesses :: ![Verkey]
    -- ^ current witness verkeys (KERI @b@)
    , kmToad :: !Integer
    -- ^ witness threshold (KERI @bt@)
    }
    deriving stock (Show, Eq)

-- | The version 2 checkpoint datum.
data CheckpointDatumV2
    = -- | A checkpoint that is alive (Constr 0, eight fields).
      Live
        { lvAid :: !ByteString
        -- ^ the qualified CESR text of the identifier
        , lvSn :: !Integer
        -- ^ KERI sequence number of the reflected establishment event
        , lvEpoch :: !Integer
        -- ^ rotations since registration
        , lvPoisoned :: !Bool
        , lvFrozen :: !Bool
        , lvBornAt :: !Integer
        -- ^ upper validity bound of the registration, POSIX milliseconds
        , lvRefundTo :: !ByteString
        -- ^ ledger bytes of the address a conviction refunds
        , lvKeys :: !KeyMaterial
        }
    | {- | A convicted checkpoint awaiting completion (Constr 1, three fields,
      no key material: no step reads the keys of a pending checkpoint).
      -}
      TerminationPending
        { tpAid :: !ByteString
        , tpSn :: !Integer
        , tpEpoch :: !Integer
        }
    deriving stock (Show, Eq)

{- | The key state of a checkpoint as the event predicates read it: the AID
digest, the key material and the two counters. It is built from a live version 2
datum (@cdSeq@ is its epoch, @cdNativeSn@ its sequence number) and has no wire
form.
-}
data KeyStateView = KeyStateView
    { cdCesrAid :: !CesrAid
    -- ^ external AID binding (KERI @i@, E-code)
    , cdCurKeys :: ![Verkey]
    {- ^ current establishment __raw__ verkeys (KERI @k@, decoded), positional —
    raw so authorization signature checks never hash
    -}
    , cdCurThreshold :: !Threshold
    -- ^ current signing threshold (KERI @kt@)
    , cdNextKeys :: ![KeyDigest]
    -- ^ pre-rotation next-key digests (KERI @n@), positional
    , cdNextThreshold :: !Threshold
    -- ^ pre-rotation next threshold (KERI @nt@)
    , cdWitnesses :: ![Verkey]
    -- ^ current witness verkeys (KERI @b@), positional
    , cdToad :: !Integer
    -- ^ witness threshold (KERI @bt@); 0 iff no witnesses, else in [1, len]
    , cdSeq :: !Integer
    -- ^ Cardano checkpoint projection counter; starts 0, +1 per advance
    , cdNativeSn :: !Integer
    -- ^ KERI native sequence number @s@ of the reflected est. event
    }
    deriving stock (Show, Eq)

-- ---------------------------------------------------------
-- PlutusData codec
-- ---------------------------------------------------------

-- | Strip the 'BuiltinData' wrapper of a value's 'Data' tree.
asData :: (ToData a) => a -> Data
asData x = let BuiltinData d = toBuiltinData x in d

-- | @Just@ the bytes of a @B@ node, else @Nothing@.
unB :: Data -> Maybe ByteString
unB (B b) = Just b
unB _ = Nothing

-- | @V2 v@ -> @Constr 1 [<datum>]@.
instance ToData CheckpointDatum where
    toBuiltinData (V2 v) = BuiltinData (Constr 1 [asData v])

instance FromData CheckpointDatum where
    fromBuiltinData (BuiltinData (Constr 1 [d])) =
        V2 <$> fromBuiltinData (BuiltinData d)
    fromBuiltinData _ = Nothing

-- | A plutus boolean: @False@ is constructor 0, @True@ constructor 1.
boolData :: Bool -> Data
boolData b = Constr (if b then 1 else 0) []

unBool :: Data -> Maybe Bool
unBool (Constr 0 []) = Just False
unBool (Constr 1 []) = Just True
unBool _ = Nothing

-- | @KeyMaterial@ -> @Constr 0 [6 fields in frozen order]@.
instance ToData KeyMaterial where
    toBuiltinData KeyMaterial{..} =
        BuiltinData $
            Constr
                0
                [ List (map B kmCurKeys)
                , asData kmCurThreshold
                , List (map B kmNextKeys)
                , asData kmNextThreshold
                , List (map B kmWitnesses)
                , I kmToad
                ]

instance FromData KeyMaterial where
    fromBuiltinData
        ( BuiltinData
                (Constr 0 [List keys, thr, List nkeys, nthr, List wits, I toad])
            ) = do
            kmCurKeys <- traverse unB keys
            kmNextKeys <- traverse unB nkeys
            kmWitnesses <- traverse unB wits
            kmCurThreshold <- fromBuiltinData (BuiltinData thr)
            kmNextThreshold <- fromBuiltinData (BuiltinData nthr)
            pure KeyMaterial{kmToad = toad, ..}
    fromBuiltinData _ = Nothing

instance ToData CheckpointDatumV2 where
    toBuiltinData Live{..} =
        BuiltinData $
            Constr
                0
                [ B lvAid
                , I lvSn
                , I lvEpoch
                , boolData lvPoisoned
                , boolData lvFrozen
                , I lvBornAt
                , B lvRefundTo
                , asData lvKeys
                ]
    toBuiltinData TerminationPending{..} =
        BuiltinData $
            Constr 1 [B tpAid, I tpSn, I tpEpoch]

instance FromData CheckpointDatumV2 where
    fromBuiltinData
        ( BuiltinData
                ( Constr
                        0
                        [B aid, I sn, I epoch, poisoned, frozen, I bornAt, B refund, keys]
                    )
            ) = do
            lvPoisoned <- unBool poisoned
            lvFrozen <- unBool frozen
            lvKeys <- fromBuiltinData (BuiltinData keys)
            pure
                Live
                    { lvAid = aid
                    , lvSn = sn
                    , lvEpoch = epoch
                    , lvBornAt = bornAt
                    , lvRefundTo = refund
                    , ..
                    }
    fromBuiltinData (BuiltinData (Constr 1 [B aid, I sn, I epoch])) =
        Just TerminationPending{tpAid = aid, tpSn = sn, tpEpoch = epoch}
    fromBuiltinData _ = Nothing

-- | The public Plutus 'Data' tree of a checkpoint datum.
checkpointDatumToData :: CheckpointDatum -> Data
checkpointDatumToData = asData

-- | Decode the public Plutus 'Data' tree through the datum wire codec.
checkpointDatumFromData :: Data -> Maybe CheckpointDatum
checkpointDatumFromData = fromBuiltinData . BuiltinData

-- ---------------------------------------------------------
-- Canonical serialization
-- ---------------------------------------------------------

{- | Canonical Plutus 'Data' CBOR bytes of a value — the cross-language,
byte-for-byte contract (the same bytes Aiken @cbor.serialise@ emits).
-}
canonicalCbor :: (ToData a) => a -> ByteString
canonicalCbor x =
    let BuiltinByteString bs = serialiseData (toBuiltinData x) in bs

-- | Blake2b-256, the native Plutus builtin hash (32-byte output).
blake2b_256 :: ByteString -> Digest32
blake2b_256 = digest (Proxy @Blake2b_256)

-- ---------------------------------------------------------
-- Datum-level well-formedness (spec rule 14)
-- ---------------------------------------------------------

-- | A datum-level well-formedness rejection reason.
data DatumError
    = -- | @cesr_aid@ is not exactly 32 bytes.
      CesrAidWidth
    | {- | The current key set\/threshold failed Slice-2 F18 'wellFormed'
      (empty\/duplicate keys, key width, threshold F18 rules 1–13).
      -}
      ThresholdIllFormed ThresholdError
    | {- | The pre-rotation @(next_keys, next_threshold)@ pair failed the
      same F18 'wellFormed' predicate.
      -}
      NextIllFormed ThresholdError
    | -- | A witness verkey is not exactly 32 bytes.
      WitnessWidth
    | -- | The witness set has a duplicate 'Verkey'.
      DuplicateWitness
    | {- | @toad@ violates the KERI @bt@ rule: @toad == 0@ iff @witnesses@
      is empty, else @1 <= toad <= len(witnesses)@ (rule 14).
      -}
      ToadRange
    | -- | A version 2 @sn@ is negative.
      NegativeSn
    | -- | A version 2 @epoch@ is negative.
      NegativeEpoch
    | -- | A version 2 @born_at@ is negative.
      NegativeBornAt
    deriving stock (Show, Eq)

{- | Full datum well-formedness. Delegates the current and next key-set +
threshold F18 checks (empty\/duplicate keys, key width, threshold rules 1–13)
to Slice-2 'wellFormed', and additionally pins the fixed-width primitive
domains (@cesr_aid@, witness verkeys all exactly 32 bytes) and the rule-14
witness\/@toad@ constraints. Nothing malformed can serialize past it.
-}
keyStateWellFormed :: KeyStateView -> Either DatumError ()
keyStateWellFormed KeyStateView{..} = do
    unless (BS.length cdCesrAid == 32) (Left CesrAidWidth)
    -- Delegate cur_keys + cur_threshold to the reused Slice-2 F18 predicate.
    first ThresholdIllFormed (wellFormed cdCurKeys cdCurThreshold)
    -- The committed next pair obeys the same F18 predicate (KERI n + nt).
    first NextIllFormed (wellFormed cdNextKeys cdNextThreshold)
    unless (all ((== 32) . BS.length) cdWitnesses) (Left WitnessWidth)
    when (length (nub cdWitnesses) /= length cdWitnesses) (Left DuplicateWitness)
    unless toadOk (Left ToadRange)
  where
    -- KERI bt rule: 0 iff the witness list is empty, else in [1, len].
    toadOk
        | null cdWitnesses = cdToad == 0
        | otherwise = 1 <= cdToad && cdToad <= fromIntegral (length cdWitnesses)

{- | Write-time validity of a version 2 datum: the numbers it carries are
non-negative and its key material obeys the key-state rules. No rule on
the identifier text or the refund address.
-}
datumV2WellFormed :: CheckpointDatumV2 -> Either DatumError ()
datumV2WellFormed = \case
    Live{lvSn, lvEpoch, lvBornAt, lvKeys} -> do
        unless (lvSn >= 0) (Left NegativeSn)
        unless (lvEpoch >= 0) (Left NegativeEpoch)
        unless (lvBornAt >= 0) (Left NegativeBornAt)
        keysWellFormed lvKeys
    TerminationPending{tpSn, tpEpoch} -> do
        unless (tpSn >= 0) (Left NegativeSn)
        unless (tpEpoch >= 0) (Left NegativeEpoch)

keysWellFormed :: KeyMaterial -> Either DatumError ()
keysWellFormed KeyMaterial{..} = do
    first ThresholdIllFormed (wellFormed kmCurKeys kmCurThreshold)
    first NextIllFormed (wellFormed kmNextKeys kmNextThreshold)
    unless (all ((== 32) . BS.length) kmWitnesses) (Left WitnessWidth)
    when (length (nub kmWitnesses) /= length kmWitnesses) (Left DuplicateWitness)
    unless toadOk (Left ToadRange)
  where
    toadOk
        | null kmWitnesses = kmToad == 0
        | otherwise = 1 <= kmToad && kmToad <= fromIntegral (length kmWitnesses)

{- | The key-state view the shared registration, rotation and enforcement
predicates read, built from the facts of a version 2 checkpoint: the raw
32-byte identifier digest, the key material, the epoch standing for the
checkpoint counter and the sequence number for the native sequence number.
-}
keyStateView ::
    -- | the raw 32-byte identifier digest
    ByteString ->
    -- | the sequence number
    Integer ->
    -- | the epoch
    Integer ->
    KeyMaterial ->
    KeyStateView
keyStateView rawAid sn epoch KeyMaterial{..} =
    KeyStateView
        { cdCesrAid = rawAid
        , cdCurKeys = kmCurKeys
        , cdCurThreshold = kmCurThreshold
        , cdNextKeys = kmNextKeys
        , cdNextThreshold = kmNextThreshold
        , cdWitnesses = kmWitnesses
        , cdToad = kmToad
        , cdSeq = epoch
        , cdNativeSn = sn
        }

{- | The key state of a live checkpoint, in the record the shared predicates and
the readers use: a live version 2 datum whose identifier is canonical. A
pending termination is not an active checkpoint (Lean @terminationPending@: not
present, not consumable).
-}
datumKeyState :: CheckpointDatum -> Maybe KeyStateView
datumKeyState = \case
    V2 Live{lvAid, lvSn, lvEpoch, lvKeys} ->
        (\raw -> keyStateView raw lvSn lvEpoch lvKeys) <$> aidDigest lvAid
    V2 TerminationPending{} -> Nothing

-- | Whether the datum is a convicted checkpoint awaiting completion.
isTerminationPending :: CheckpointDatum -> Bool
isTerminationPending = \case
    V2 TerminationPending{} -> True
    _ -> False

{- | The version 2 datum of a live checkpoint output with its key state, for a
datum whose identifier is canonical.
-}
datumFacts :: CheckpointDatum -> Maybe (CheckpointDatumV2, KeyStateView)
datumFacts = \case
    datum@(V2 facts) -> (,) facts <$> datumKeyState datum

-- | The key material of a key state: its keys, thresholds, witnesses and toad.
keyMaterialOf :: KeyStateView -> KeyMaterial
keyMaterialOf KeyStateView{..} =
    KeyMaterial
        { kmCurKeys = cdCurKeys
        , kmCurThreshold = cdCurThreshold
        , kmNextKeys = cdNextKeys
        , kmNextThreshold = cdNextThreshold
        , kmWitnesses = cdWitnesses
        , kmToad = cdToad
        }

{- | The live datum a rotation to this key state writes (Lean
@rotateKeepPaid@, @rotateKeepUnpaid@): the sequence number of the new
establishment event, one more epoch, no poison and the new keys; the
identifier, the frozen flag, the birth time and the refund address are
unchanged. 'Nothing' for a datum that is not live.
-}
rotatedLive :: CheckpointDatumV2 -> KeyStateView -> Maybe CheckpointDatumV2
rotatedLive old view@KeyStateView{..} = case old of
    Live{} ->
        Just
            old
                { lvSn = cdNativeSn
                , lvEpoch = lvEpoch old + 1
                , lvPoisoned = False
                , lvKeys = keyMaterialOf view
                }
    TerminationPending{} -> Nothing

{- | The datum a conviction writes (Lean @Step.convict@): the identifier, the
sequence number and the epoch of the live datum, as a pending
termination without key material. 'Nothing' for a datum that is not live.
-}
convictedOf :: CheckpointDatumV2 -> Maybe CheckpointDatumV2
convictedOf = \case
    Live{lvAid, lvSn, lvEpoch} ->
        Just
            TerminationPending
                { tpAid = lvAid
                , tpSn = lvSn
                , tpEpoch = lvEpoch
                }
    TerminationPending{} -> Nothing

{- | The live version 2 datum of a key state: the identifier text of its
digest, the sequence number and epoch from the record, no poison, not frozen.
The birth time and the refund address are the registration's.
-}
liveOfKeyState ::
    -- | the ledger bytes of the refund address
    ByteString ->
    -- | the birth time, POSIX milliseconds
    Integer ->
    KeyStateView ->
    CheckpointDatumV2
liveOfKeyState refund bornAt view@KeyStateView{..} =
    Live
        { lvAid = qb64Aid cdCesrAid
        , lvSn = cdNativeSn
        , lvEpoch = cdSeq
        , lvPoisoned = False
        , lvFrozen = False
        , lvBornAt = bornAt
        , lvRefundTo = refund
        , lvKeys = keyMaterialOf view
        }
