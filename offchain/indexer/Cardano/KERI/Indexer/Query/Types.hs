{- |
Module      : Cardano.KERI.Indexer.Query.Types
Description : Frozen #176 Slice 1 public JSON response shapes

The exact wire contract from @specs\/176-query-endpoint\/spec.md@ (as
corrected by commit @0c11bf2@: freshness fields sit beside a named
endpoint-specific payload — @checkpoint@, @board@, or @watchability@ — never
inside a generic @data@ envelope). CESR values render in canonical
qualified-base64 form; transaction ids and owner key hashes render as
lowercase hex; thresholds preserve their weighted\/unweighted datum shape.
-}
module Cardano.KERI.Indexer.Query.Types (
    -- * Freshness
    Freshness (..),
    ReadyResponse (..),
    UnavailableResponse (..),

    -- * Checkpoint
    CheckpointResponse (..),
    CheckpointData (..),
    ThresholdJson (..),

    -- * Board
    BoardResponse (..),
    BoardData (..),
    BoardListResponse (..),
    BoardListEntry (..),

    -- * Watchability
    WatchabilityResponse (..),
    WatchabilityData (..),

    -- * Rendering helpers
    qb64Witness,
    hexBytes,
    hexTxId,
) where

import Cardano.KERI.AID.CESR (
    qb64Aid,
    qb64Verkey,
 )
import Cardano.KERI.AID.Checkpoint.Threshold (
    Threshold (..),
    Weight (..),
 )
import Data.Aeson (
    ToJSON (..),
    Value,
    object,
    (.=),
 )
import Data.ByteArray.Encoding (
    Base (Base64URLUnpadded),
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Base16 qualified as Base16
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Word (Word64)

-- | Common freshness pair carried by every response.
data Freshness = Freshness
    { freshAsOfSlot :: !(Maybe Word64)
    , freshTipLagSlots :: !(Maybe Word64)
    }
    deriving stock (Eq, Show)

-- | Exact @GET \/ready@ body. Always HTTP 200.
data ReadyResponse = ReadyResponse
    { readyReady :: !Bool
    , readyFreshness :: !Freshness
    , readyUpstream :: !Text
    , readyReason :: !(Maybe Text)
    }
    deriving stock (Eq, Show)

instance ToJSON ReadyResponse where
    toJSON ReadyResponse{readyReady, readyFreshness, readyUpstream, readyReason} =
        object
            [ "ready" .= readyReady
            , "as_of_slot" .= freshAsOfSlot readyFreshness
            , "tip_lag_slots" .= freshTipLagSlots readyFreshness
            , "upstream" .= readyUpstream
            , "reason" .= readyReason
            ]

{- | Exact HTTP 503 body for a data route when readiness fails closed. Never
carries @checkpoint@\/@board@\/@watchability@ — not even @null@.
-}
data UnavailableResponse = UnavailableResponse
    { unavailableFreshness :: !Freshness
    , unavailableUpstream :: !Text
    , unavailableReason :: !Text
    }
    deriving stock (Eq, Show)

instance ToJSON UnavailableResponse where
    toJSON UnavailableResponse{unavailableFreshness, unavailableUpstream, unavailableReason} =
        object
            [ "ready" .= False
            , "as_of_slot" .= freshAsOfSlot unavailableFreshness
            , "tip_lag_slots" .= freshTipLagSlots unavailableFreshness
            , "upstream" .= unavailableUpstream
            , "reason" .= unavailableReason
            , "error" .= ("service_unavailable" :: Text)
            ]

-- | A KERI @kt@\/@nt@ threshold rendered exactly as spec.md's two shapes.
data ThresholdJson
    = UnweightedJson !Integer
    | WeightedJson ![[(Integer, Integer)]]
    deriving stock (Eq, Show)

instance ToJSON ThresholdJson where
    toJSON (UnweightedJson n) =
        object ["type" .= ("unweighted" :: Text), "value" .= n]
    toJSON (WeightedJson clauses) =
        object
            [ "type" .= ("weighted" :: Text)
            , "clauses" .= map (map weightJson) clauses
            ]
      where
        weightJson (num, den) =
            object ["numerator" .= num, "denominator" .= den]

thresholdToJson :: Threshold -> ThresholdJson
thresholdToJson (Unweighted n) = UnweightedJson n
thresholdToJson (Weighted clauses) =
    WeightedJson (map (map weightPair) clauses)
  where
    weightPair (Weight num den) = (num, den)

{- | The nullable @checkpoint@ payload's fields. Field names are prefixed
@chk@, distinct from 'Cardano.KERI.AID.Checkpoint.Datum.CheckpointDatumV1's
@cd@-prefixed fields (the two types are commonly in scope together in
"Cardano.KERI.Indexer.Query.Server"); this is a pure Haskell-identifier
choice and has no effect on the JSON below, which is unchanged.
-}
data CheckpointData = CheckpointData
    { chkTxId :: !ByteString
    -- ^ Raw 32-byte transaction id.
    , chkOutputIndex :: !Int
    , chkSequence :: !Integer
    , chkNativeSequence :: !Integer
    , chkCurrentKeys :: ![ByteString]
    -- ^ Raw 32-byte transferable verkeys.
    , chkCurrentThreshold :: !Threshold
    , chkNextKeyDigests :: ![ByteString]
    -- ^ Raw 32-byte Blake3-256 digests.
    , chkNextThreshold :: !Threshold
    , chkWitnesses :: ![ByteString]
    -- ^ Raw 32-byte non-transferable witness keys.
    , chkWitnessThreshold :: !Integer
    }
    deriving stock (Eq, Show)

instance ToJSON CheckpointData where
    toJSON CheckpointData{..} =
        object
            [ "tx_id" .= hexTxId chkTxId
            , "output_index" .= chkOutputIndex
            , "sequence" .= chkSequence
            , "native_sequence" .= chkNativeSequence
            , "current_keys" .= map qb64TextVerkey chkCurrentKeys
            , "current_threshold" .= thresholdToJson chkCurrentThreshold
            , "next_key_digests" .= map qb64TextDigest chkNextKeyDigests
            , "next_threshold" .= thresholdToJson chkNextThreshold
            , "witnesses" .= map qb64TextWitness chkWitnesses
            , "witness_threshold" .= chkWitnessThreshold
            ]

-- | Exact @GET \/checkpoint\/{aid}@ HTTP 200 body.
data CheckpointResponse = CheckpointResponse
    { crAid :: !ByteString
    , crFreshness :: !Freshness
    , crCheckpoint :: !(Maybe CheckpointData)
    }
    deriving stock (Eq, Show)

instance ToJSON CheckpointResponse where
    toJSON CheckpointResponse{crAid, crFreshness, crCheckpoint} =
        object
            [ "aid" .= qb64TextAid crAid
            , "as_of_slot" .= freshAsOfSlot crFreshness
            , "tip_lag_slots" .= freshTipLagSlots crFreshness
            , "checkpoint" .= crCheckpoint
            ]

-- | The nullable @board@ payload's fields.
data BoardData = BoardData
    { bdAid :: !Text
    , bdScheme :: !Text
    , bdUrl :: !Text
    , bdTxId :: !Text
    -- ^ Already lowercase hex (sourced from the board catalog record).
    , bdOutputIndex :: !Int
    , bdLovelace :: !Integer
    , bdOwnerKeyHash :: !ByteString
    -- ^ Raw 28-byte owner key hash.
    }
    deriving stock (Eq, Show)

instance ToJSON BoardData where
    toJSON BoardData{..} =
        object
            [ "aid" .= bdAid
            , "scheme" .= bdScheme
            , "url" .= bdUrl
            , "tx_id" .= bdTxId
            , "output_index" .= bdOutputIndex
            , "lovelace" .= bdLovelace
            , "owner_key_hash" .= hexBytes bdOwnerKeyHash
            ]

-- | Exact @GET \/board\/{witness_key}@ HTTP 200 body.
data BoardResponse = BoardResponse
    { brWitnessKey :: !ByteString
    , brFreshness :: !Freshness
    , brBoard :: !(Maybe BoardData)
    }
    deriving stock (Eq, Show)

instance ToJSON BoardResponse where
    toJSON BoardResponse{brWitnessKey, brFreshness, brBoard} =
        object
            [ "witness_key" .= qb64TextWitness brWitnessKey
            , "as_of_slot" .= freshAsOfSlot brFreshness
            , "tip_lag_slots" .= freshTipLagSlots brFreshness
            , "board" .= brBoard
            ]

{- | One authenticated entry in @GET /board@. The wire shape is flat so a
catalog consumer can associate the witness key with its endpoint record
without reconstructing the single-record response envelope.
-}
data BoardListEntry = BoardListEntry
    { bleWitnessKey :: !ByteString
    , bleBoard :: !BoardData
    }
    deriving stock (Eq, Show)

instance ToJSON BoardListEntry where
    toJSON BoardListEntry{bleWitnessKey, bleBoard = BoardData{..}} =
        object
            [ "witness_key" .= qb64TextWitness bleWitnessKey
            , "aid" .= bdAid
            , "scheme" .= bdScheme
            , "url" .= bdUrl
            , "tx_id" .= bdTxId
            , "output_index" .= bdOutputIndex
            , "lovelace" .= bdLovelace
            , "owner_key_hash" .= hexBytes bdOwnerKeyHash
            ]

-- | Exact @GET /board@ HTTP 200 body.
data BoardListResponse = BoardListResponse
    { blrFreshness :: !Freshness
    , blrBoard :: ![BoardListEntry]
    }
    deriving stock (Eq, Show)

instance ToJSON BoardListResponse where
    toJSON BoardListResponse{blrFreshness, blrBoard} =
        object
            [ "as_of_slot" .= freshAsOfSlot blrFreshness
            , "tip_lag_slots" .= freshTipLagSlots blrFreshness
            , "board" .= blrBoard
            ]

-- | The non-nullable @watchability@ payload's fields.
data WatchabilityData = WatchabilityData
    { wdCheckpointPresent :: !Bool
    , wdWitnessesDeclared :: !Int
    , wdWitnessesListed :: !Int
    , wdMissingWitnesses :: ![ByteString]
    }
    deriving stock (Eq, Show)

instance ToJSON WatchabilityData where
    toJSON WatchabilityData{..} =
        object
            [ "checkpoint_present" .= wdCheckpointPresent
            , "witnesses_declared" .= wdWitnessesDeclared
            , "witnesses_listed" .= wdWitnessesListed
            , "missing_witnesses" .= map qb64TextWitness wdMissingWitnesses
            ]

-- | Exact @GET \/watchability\/{aid}@ HTTP 200 body.
data WatchabilityResponse = WatchabilityResponse
    { wrAid :: !ByteString
    , wrFreshness :: !Freshness
    , wrWatchability :: !WatchabilityData
    }
    deriving stock (Eq, Show)

instance ToJSON WatchabilityResponse where
    toJSON WatchabilityResponse{wrAid, wrFreshness, wrWatchability} =
        object
            [ "aid" .= qb64TextAid wrAid
            , "as_of_slot" .= freshAsOfSlot wrFreshness
            , "tip_lag_slots" .= freshTipLagSlots wrFreshness
            , "watchability" .= wrWatchability
            ]

{- | The fully qualified Base64url (qb64) form of a raw 32-byte
non-transferable Ed25519 witness key: code @\'B\'@ followed by
@b64url(0x00 ‖ key)@ with the leading @\'A\'@ character replaced by the code
— 44 ASCII characters. @Cardano.KERI.AID.CESR@ only exposes the D-code
('qb64Verkey') and E-code ('qb64Aid') renderers, so the B-code renderer this
package needs for witness keys is defined here.
-}
qb64Witness :: ByteString -> ByteString
qb64Witness key =
    BS.cons 0x42 (BS.drop 1 b64) -- 'B' replaces the leading 'A'
  where
    b64 = convertToBase Base64URLUnpadded (BS.cons 0x00 key)

qb64TextWitness :: ByteString -> Text
qb64TextWitness = TE.decodeUtf8 . qb64Witness

-- | Lowercase hex rendering of raw bytes.
hexBytes :: ByteString -> Text
hexBytes = TE.decodeUtf8 . Base16.encode

-- | Lowercase hex rendering of a raw transaction id.
hexTxId :: ByteString -> Text
hexTxId = hexBytes

qb64TextVerkey :: ByteString -> Value
qb64TextVerkey key = toJSON (TE.decodeUtf8 (qb64Verkey key))

qb64TextDigest :: ByteString -> Value
qb64TextDigest key = toJSON (TE.decodeUtf8 (qb64Aid key))

qb64TextAid :: ByteString -> Text
qb64TextAid = TE.decodeUtf8 . qb64Aid
