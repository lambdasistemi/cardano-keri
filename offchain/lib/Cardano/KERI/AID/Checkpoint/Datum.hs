{- |
Module      : Cardano.KERI.AID.Checkpoint.Datum
Description : Frozen sovereign per-AID @CheckpointDatumV1@ wire codec, #68

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

Constructor indices and field order are protocol surface (spec #68); they
change only by minting a new version tag. The pre-rotation commitment is the
explicit @(next_keys, next_threshold)@ pair — the KERI @n@ digest list plus
@nt@ — so a rotation may reveal any satisfiable subset of the committed
digests (KERI partial\/reserve rotation) and restate its own current
threshold, exactly as the KERI dual-threshold rule allows.
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

    -- * Canonical serialization
    canonicalCbor,
    blake2b_256,

    -- * Datum-level well-formedness (rule 14)
    DatumError (..),
    datumWellFormed,
) where

import Cardano.Crypto.Hash.Blake2b (
    Blake2b_256,
 )
import Cardano.Crypto.Hash.Class (
    digest,
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

-- | A current\/next establishment key digest (@blake2b_256(qb64(verkey))@).
type KeyDigest = ByteString

-- | A raw 32-byte Ed25519 witness verkey.
type Verkey = ByteString

-- | A 32-byte Blake2b-256 output.
type Digest32 = ByteString

-- | The external F-code-stripped 32-byte Blake2b-256 AID digest.
type CesrAid = ByteString

-- ---------------------------------------------------------
-- Types
-- ---------------------------------------------------------

{- | The checkpoint datum version sum. @V1@ is constructor index 0; a
v1-only validator fails closed on an unknown constructor.
-}
newtype CheckpointDatum
    = -- | Constr 0, wrapping the inner v1 record.
      V1 CheckpointDatumV1
    deriving stock (Show, Eq)

{- | The frozen sovereign per-AID checkpoint state (Constr 0). The 9 fields
are positional and security-significant; reordering changes the bytes.
-}
data CheckpointDatumV1 = CheckpointDatumV1
    { cdCesrAid :: !CesrAid
    -- ^ external AID binding (KERI @i@)
    , cdCurKeys :: ![KeyDigest]
    -- ^ current establishment key digests (KERI @k@), positional
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

-- | @V1 v@ -> @Constr 0 [<inner record>]@.
instance ToData CheckpointDatum where
    toBuiltinData (V1 v) = BuiltinData (Constr 0 [asData v])

instance FromData CheckpointDatum where
    fromBuiltinData (BuiltinData (Constr 0 [d])) =
        V1 <$> fromBuiltinData (BuiltinData d)
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
