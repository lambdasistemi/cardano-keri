{-# LANGUAGE NamedFieldPuns #-}

{- |
Module      : Cardano.KERI.AID.Checkpoint.Datum
Description : The checkpoint datum wire codec: the frozen version 1 record (#68) and the version 2 datum (#339)

The versioned checkpoint datum as a validator-free schema-support layer: the
'CheckpointDatum' version sum, the 'CheckpointDatumV1' record, and the
canonical Plutus 'Data' / CBOR serialization the Aiken encoder mirrors
byte-for-byte.

@
CheckpointDatum   = V1 CheckpointDatumV1   -- Constr 0, wrapping the inner record
CheckpointDatumV1                          -- Constr 0, 9 fields in frozen order:
  { cesr_aid, cur_keys, cur_threshold, next_keys, next_threshold,
    witnesses, toad, seq, native_sn }
@

Version 2 (@V2@ is constructor 1) carries the facts of a checkpoint state:

@
CheckpointDatumV2
  = Live                -- Constr 0, 8 fields:
      { aid, sn, epoch, poisoned, frozen, born_at, refund_to, keys }
  | TerminationPending  -- Constr 1, 4 fields:
      { aid, sn, epoch, keys }
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
    CheckpointDatumV1 (..),
    CheckpointDatumV2 (..),
    KeyMaterial (..),

    -- * Canonical serialization
    canonicalCbor,
    checkpointDatumFromData,
    checkpointDatumToData,
    blake2b_256,

    -- * Datum-level well-formedness (rule 14)
    DatumError (..),
    datumWellFormed,
    datumV2WellFormed,

    -- * The version 1 key-state view of a version 2 checkpoint
    keyStateView,
    datumKeyState,
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

{- | The checkpoint datum version sum. @V1@ is constructor index 0 and @V2@
index 1; a validator fails closed on a constructor it does not know.
-}
data CheckpointDatum
    = -- | Constr 0, wrapping the inner v1 record.
      V1 CheckpointDatumV1
    | -- | Constr 1, wrapping the version 2 datum.
      V2 CheckpointDatumV2
    deriving stock (Show, Eq)

-- | The key material of a version 2 checkpoint: the version 1 record's key fields.
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
    | -- | A convicted checkpoint awaiting completion (Constr 1, four fields).
      TerminationPending
        { tpAid :: !ByteString
        , tpSn :: !Integer
        , tpEpoch :: !Integer
        , tpKeys :: !KeyMaterial
        }
    deriving stock (Show, Eq)

{- | The frozen sovereign per-AID checkpoint state (Constr 0). The 9 fields
are positional and security-significant; reordering changes the bytes.
-}
data CheckpointDatumV1 = CheckpointDatumV1
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

-- | @V1 v@ -> @Constr 0 [<inner record>]@, @V2 v@ -> @Constr 1 [<datum>]@.
instance ToData CheckpointDatum where
    toBuiltinData (V1 v) = BuiltinData (Constr 0 [asData v])
    toBuiltinData (V2 v) = BuiltinData (Constr 1 [asData v])

instance FromData CheckpointDatum where
    fromBuiltinData (BuiltinData (Constr 0 [d])) =
        V1 <$> fromBuiltinData (BuiltinData d)
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
            Constr 1 [B tpAid, I tpSn, I tpEpoch, asData tpKeys]

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
    fromBuiltinData (BuiltinData (Constr 1 [B aid, I sn, I epoch, keys])) = do
        tpKeys <- fromBuiltinData (BuiltinData keys)
        pure TerminationPending{tpAid = aid, tpSn = sn, tpEpoch = epoch, ..}
    fromBuiltinData _ = Nothing

-- | @CheckpointDatumV1@ -> @Constr 0 [9 fields in frozen order]@.
instance ToData CheckpointDatumV1 where
    toBuiltinData CheckpointDatumV1{..} =
        BuiltinData $
            Constr
                0
                [ B cdCesrAid
                , List (map B cdCurKeys)
                , asData cdCurThreshold
                , List (map B cdNextKeys)
                , asData cdNextThreshold
                , List (map B cdWitnesses)
                , I cdToad
                , I cdSeq
                , I cdNativeSn
                ]

instance FromData CheckpointDatumV1 where
    fromBuiltinData
        ( BuiltinData
                ( Constr
                        0
                        [ B cesr
                            , List keys
                            , thr
                            , List nkeys
                            , nthr
                            , List wits
                            , I toad
                            , I s
                            , I nsn
                            ]
                    )
            ) = do
            cdCurKeys <- traverse unB keys
            cdNextKeys <- traverse unB nkeys
            cdWitnesses <- traverse unB wits
            cdCurThreshold <- fromBuiltinData (BuiltinData thr)
            cdNextThreshold <- fromBuiltinData (BuiltinData nthr)
            pure
                CheckpointDatumV1
                    { cdCesrAid = cesr
                    , cdCurKeys = cdCurKeys
                    , cdCurThreshold = cdCurThreshold
                    , cdNextKeys = cdNextKeys
                    , cdNextThreshold = cdNextThreshold
                    , cdWitnesses = cdWitnesses
                    , cdToad = toad
                    , cdSeq = s
                    , cdNativeSn = nsn
                    }
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
datumWellFormed :: CheckpointDatumV1 -> Either DatumError ()
datumWellFormed CheckpointDatumV1{..} = do
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
non-negative and its key material obeys the version 1 key rules. No rule on
the identifier text or the refund address.
-}
datumV2WellFormed :: CheckpointDatumV2 -> Either DatumError ()
datumV2WellFormed = \case
    Live{lvSn, lvEpoch, lvBornAt, lvKeys} -> do
        unless (lvSn >= 0) (Left NegativeSn)
        unless (lvEpoch >= 0) (Left NegativeEpoch)
        unless (lvBornAt >= 0) (Left NegativeBornAt)
        keysWellFormed lvKeys
    TerminationPending{tpSn, tpEpoch, tpKeys} -> do
        unless (tpSn >= 0) (Left NegativeSn)
        unless (tpEpoch >= 0) (Left NegativeEpoch)
        keysWellFormed tpKeys

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

{- | The version 1 record the shared registration, rotation and enforcement
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
    CheckpointDatumV1
keyStateView rawAid sn epoch KeyMaterial{..} =
    CheckpointDatumV1
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

{- | The key state a checkpoint output declares, in the version 1 record the
shared predicates and the readers use: a live or pending version 2 datum
whose identifier is canonical. A version 1 datum is no longer a checkpoint.
-}
datumKeyState :: CheckpointDatum -> Maybe CheckpointDatumV1
datumKeyState = \case
    V2 Live{lvAid, lvSn, lvEpoch, lvKeys} ->
        (\raw -> keyStateView raw lvSn lvEpoch lvKeys) <$> aidDigest lvAid
    V2 TerminationPending{tpAid, tpSn, tpEpoch, tpKeys} ->
        (\raw -> keyStateView raw tpSn tpEpoch tpKeys) <$> aidDigest tpAid
    V1 _ -> Nothing

{- | The live version 2 datum of a key state: the identifier text of its
digest, the sequence number and epoch from the record, no poison, not frozen.
The birth time and the refund address are the registration's.
-}
liveOfKeyState ::
    -- | the ledger bytes of the refund address
    ByteString ->
    -- | the birth time, POSIX milliseconds
    Integer ->
    CheckpointDatumV1 ->
    CheckpointDatumV2
liveOfKeyState refund bornAt CheckpointDatumV1{..} =
    Live
        { lvAid = qb64Aid cdCesrAid
        , lvSn = cdNativeSn
        , lvEpoch = cdSeq
        , lvPoisoned = False
        , lvFrozen = False
        , lvBornAt = bornAt
        , lvRefundTo = refund
        , lvKeys =
            KeyMaterial
                { kmCurKeys = cdCurKeys
                , kmCurThreshold = cdCurThreshold
                , kmNextKeys = cdNextKeys
                , kmNextThreshold = cdNextThreshold
                , kmWitnesses = cdWitnesses
                , kmToad = cdToad
                }
        }
