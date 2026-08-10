{- |
Module      : Cardano.KERI.ChainQuery.Types
Description : Provider-neutral chain-query domain types (#257 DAT-257-*)

The result, locator, watermark, provenance, and consistency types shared by
every 'Cardano.KERI.ChainQuery.Program.ChainQuery' operation and by both
interpreters ("Cardano.KERI.Indexer.ChainQuery" and
"Cardano.KERI.ChainQuery.Koios"). This module owns no HTTP client, no
RocksDB\/store handle, no node runtime, and no executable setting — it is the
nearest stable upstream owner of types that transaction builders and both
interpreters must agree on.
-}
module Cardano.KERI.ChainQuery.Types (
    -- * Errors
    ChainQueryError (..),

    -- * Provenance and consistency
    QuerySource (..),
    SnapshotConsistency (..),

    -- * Watermark
    ChainWatermark (..),
    ColdOr (..),

    -- * Result envelope
    QuerySnapshot (..),

    -- * Locators
    CheckpointLocator (..),
    BoardLocator (..),
    OutputLocator (..),

    -- * Provider-neutral canonical-shape validation (DATA-INV-257-01, NOTE-020)
    validCheckpointLocator,
    validBoardLocator,
    validOutputLocator,
    validPayerAddresses,
    validReferenceHashes,
    validAid,
    isCanonicalScriptHashHex,
    isCanonicalTransactionIdHex,
    isCanonicalBech32Address,

    -- * Promoted domain values
    ChainAsset (..),
    ChainReferenceScript (..),
    ChainAssetUtxo (..),
    ChainReference (..),
    ActiveCheckpoint (..),
    BoardEntry (..),

    -- * Extended-response decode (A-001)
    parseExtendedChainAssetUtxo,
) where

import Cardano.KERI.AID.CESR (Primitive (SelfAddressing), parsePrimitive)
import Cardano.KERI.AID.Checkpoint.Datum (CheckpointDatumV1)
import Codec.Binary.Bech32 qualified as Bech32
import Data.Aeson (
    FromJSON (..),
    Object,
    Value,
    withObject,
    (.:),
    (.:?),
 )
import Data.Aeson.Key (Key)
import Data.Aeson.Types (Parser)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.Foldable (traverse_)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word16, Word64)
import Text.Read (readMaybe)

{- | Named failure of a 'Cardano.KERI.ChainQuery.Program.ChainQuery'
operation. Every variant preserves source identity and never triggers a
fallback to another provider (INV-257-PROVIDER).
-}
data ChainQueryError
    = -- | The selected interpreter has no implementation for this operation.
      UnsupportedOperation !Text
    | -- | The provider itself failed (transport, HTTP status, store error).
      ProviderFailure !Text
    | {- | A response could not be decoded or reconstructed into a ledger
      value (DATA-INV-257-01\/02, Q-001\/A-001 fail-closed reconstruction).
      -}
      DecodingFailure !Text
    | -- | A board or reference-script authentication check failed.
      AuthenticationFailure !Text
    | -- | The watermark was malformed, partial, or internally incoherent.
      IncoherentWatermark !Text
    | -- | More than one candidate matched a single-result operation.
      AmbiguousCurrentState !Text
    | {- | The supplied locator failed validation before interpretation
      (DATA-INV-257-01).
      -}
      InvalidLocator !Text
    deriving stock (Show, Eq)

-- | Which provider actually answered a program (DAT-257-SOURCE).
data QuerySource
    = SourceLocal
    | SourceKoios
    deriving stock (Show, Eq)

{- | Whether a snapshot's rows and watermark share one atomic observation
(DAT-257-CONSISTENCY). The sequential variant is consumer-visible and must
never be rendered or pattern-matched as atomic.
-}
data SnapshotConsistency
    = -- | One local store transaction produced every row and the watermark.
      AtomicLocal
    | {- | Rows and\/or the watermark came from independent sequential
      provider calls; no shared-snapshot claim is made.
      -}
      LegacySequential
    deriving stock (Show, Eq)

-- | The store slot and its corresponding block hash (DAT-257-WATERMARK).
data ChainWatermark = ChainWatermark
    { watermarkSlot :: !Word64
    , watermarkBlockHash :: !Text
    -- ^ Lowercase hex.
    }
    deriving stock (Show, Eq)

-- | A watermark that may be explicitly absent (a cold store or provider).
data ColdOr a
    = Cold
    | Populated !a
    deriving stock (Show, Eq, Functor)

{- | Every successful 'Cardano.KERI.ChainQuery.Program.ChainQuery' program
result (DAT-257-RESULT). For local results, 'snapshotValue' and
'snapshotWatermark' share one store transaction. For Koios,
'snapshotConsistency' prevents an atomic interpretation.
-}
data QuerySnapshot value = QuerySnapshot
    { snapshotValue :: !value
    , snapshotWatermark :: !(ColdOr ChainWatermark)
    , snapshotSource :: !QuerySource
    , snapshotConsistency :: !SnapshotConsistency
    }
    deriving stock (Show, Eq, Functor)

{- | Identifies the checkpoint policy and address needed by both
interpreters (DAT-257-CHECKPOINT-LOCATOR). The AID is supplied separately to
'Cardano.KERI.ChainQuery.Program.currentCheckpoint'.
-}
data CheckpointLocator = CheckpointLocator
    { checkpointLocatorPolicyId :: !Text
    , checkpointLocatorAddress :: !Text
    }
    deriving stock (Show, Eq)

{- | Identifies the endpoint-board policy and marker address
(DAT-257-BOARD-LOCATOR).
-}
data BoardLocator = BoardLocator
    { boardLocatorPolicyId :: !Text
    , boardLocatorAddress :: !Text
    }
    deriving stock (Show, Eq)

{- | #262 DAT-262-OUTPUT-LOCATOR: one live output's exact identity. Carries
nothing but that identity -- no address to scope a search by, no provider
setting, no effect handle -- because an output reference is the whole
selector: the row either exists at this @(txid,index)@ or the operation
fails closed.
-}
data OutputLocator = OutputLocator
    { outputLocatorTxId :: !Text
    -- ^ Canonical lowercase 32-byte transaction-id hex.
    , outputLocatorIndex :: !Int
    -- ^ A ledger-valid, non-negative output index.
    }
    deriving stock (Show, Eq)

{- | DATA-INV-257-01 (NOTE-020): the ONE provider-neutral canonical-shape
check every 'Cardano.KERI.ChainQuery.Program.ChainQuery' smart constructor
runs EAGERLY, the moment an operation is built from a concrete argument --
literal or derived from any real earlier result -- never enumerating
possible continuations. An operation whose argument fails this check never
becomes a 'Cardano.KERI.ChainQuery.Program.ChainQueryF' node, so no
interpreter (local or Koios) is ever given the chance to answer it.
-}
validCheckpointLocator :: CheckpointLocator -> Either ChainQueryError ()
validCheckpointLocator locator
    | T.null (checkpointLocatorPolicyId locator) || T.null (checkpointLocatorAddress locator) =
        Left (InvalidLocator "checkpoint locator policy id and address must be non-empty")
    | not (isCanonicalScriptHashHex (checkpointLocatorPolicyId locator)) =
        Left (InvalidLocator "checkpoint locator policy id is not a canonical 28-byte hex script hash")
    | not (isCanonicalBech32Address (checkpointLocatorAddress locator)) =
        Left (InvalidLocator "checkpoint locator address is not a canonical bech32 address")
    | otherwise = Right ()

validBoardLocator :: BoardLocator -> Either ChainQueryError ()
validBoardLocator locator
    | T.null (boardLocatorPolicyId locator) || T.null (boardLocatorAddress locator) =
        Left (InvalidLocator "board locator policy id and address must be non-empty")
    | not (isCanonicalScriptHashHex (boardLocatorPolicyId locator)) =
        Left (InvalidLocator "board locator policy id is not a canonical 28-byte hex script hash")
    | not (isCanonicalBech32Address (boardLocatorAddress locator)) =
        Left (InvalidLocator "board locator address is not a canonical bech32 address")
    | otherwise = Right ()

{- | #262 DATA-INV-262-01: the exact-output locator's own canonical-shape
check, run EAGERLY by
'Cardano.KERI.ChainQuery.Program.outputAt' the moment the operation is built
from a concrete argument -- literal or derived from an earlier operation's
result -- so an invalid identity never becomes an operation node and no
interpreter is ever given the chance to answer it.

Lower case is required, not merely accepted. Hex decoding is case
insensitive, so a check written only as "decodes to 32 bytes" would admit an
upper-case identity that no interpreter's own lower-case rendering of a
stored row can ever equal: the operation would be dispatched, scan the whole
store, and report a perfectly ordinary absence for a row that is present.
That is a locator error wearing an absence's clothes, and it fails here
instead.
-}
validOutputLocator :: OutputLocator -> Either ChainQueryError ()
validOutputLocator locator
    | T.null (outputLocatorTxId locator) =
        Left (InvalidLocator "output locator transaction id must be non-empty")
    | not (isCanonicalTransactionIdHex (outputLocatorTxId locator)) =
        Left
            ( InvalidLocator
                "output locator transaction id is not canonical lowercase 32-byte hex"
            )
    | outputLocatorIndex locator < 0 =
        Left (InvalidLocator "output locator index must not be negative")
    | outputLocatorIndex locator > maxLedgerOutputIndex =
        Left (InvalidLocator "output locator index is outside the ledger range")
    | otherwise = Right ()

{- | The largest output index a Conway transaction can carry
('Cardano.Ledger.BaseTypes.TxIx' is a 'Data.Word.Word16'). Named here, in the
provider-neutral layer, because both interpreters and every program must
agree on it -- and because
'Cardano.KERI.ChainQuery.LedgerOutput.chainAssetUtxoToLedgerOutput' would
otherwise be the first place a too-large index was noticed, long after the
operation had run.
-}
maxLedgerOutputIndex :: Int
maxLedgerOutputIndex = fromIntegral (maxBound :: Word16)

{- | A lowercase hex string that decodes to exactly a 32-byte transaction id.
Performs no effect.
-}
isCanonicalTransactionIdHex :: Text -> Bool
isCanonicalTransactionIdHex hexRepresentation =
    T.all isLowerHexDigit hexRepresentation
        && case convertFromBase Base16 (TE.encodeUtf8 hexRepresentation) of
            Right bytes -> BS.length (bytes :: BS.ByteString) == 32
            Left (_ :: String) -> False
  where
    isLowerHexDigit c = isDigit c || (c >= 'a' && c <= 'f')

{- | NOTE-020 mandate ruling: an empty payer-address SELECTOR is invalid
(DAT-257-OP requires a non-empty set of ledger addresses) -- distinct from
an empty RESULT, which is legal when a non-empty selector finds no UTxOs.
-}
validPayerAddresses :: [Text] -> Either ChainQueryError ()
validPayerAddresses [] = Left (InvalidLocator "payer address list must not be empty")
validPayerAddresses addresses = traverse_ validPayerAddress addresses

validPayerAddress :: Text -> Either ChainQueryError ()
validPayerAddress address
    | T.null address = Left (InvalidLocator "payer address must be non-empty")
    | not (isCanonicalBech32Address address) =
        Left (InvalidLocator "payer address is not a canonical bech32 address")
    | otherwise = Right ()

{- | NOTE-020 mandate ruling: zero requested reference hashes is a legal
empty result\/no-op shape, not independently forbidden -- but every
SUPPLIED hash must still be non-empty and canonical.
-}
validReferenceHashes :: [Text] -> Either ChainQueryError ()
validReferenceHashes = traverse_ validReferenceHash

validReferenceHash :: Text -> Either ChainQueryError ()
validReferenceHash hashHex
    | T.null hashHex = Left (InvalidLocator "reference script hash must be non-empty")
    | isCanonicalScriptHashHex hashHex = Right ()
    | otherwise = Left (InvalidLocator "reference script hash is not canonical 28-byte hex")

-- | A checkpoint AID must be a well-formed 44-character KERI E-code identifier.
validAid :: Text -> Either ChainQueryError ()
validAid aid = case parsePrimitive (TE.encodeUtf8 aid) of
    Right (SelfAddressing _, rest) | BS.null rest -> Right ()
    _ -> Left (InvalidLocator "AID must be one 44-character KERI E-code identifier")

{- | A hex string that decodes to exactly a 28-byte script hash. Performs
no effect.
-}
isCanonicalScriptHashHex :: Text -> Bool
isCanonicalScriptHashHex hexRepresentation =
    case convertFromBase Base16 (TE.encodeUtf8 hexRepresentation) of
        Right bytes -> BS.length (bytes :: BS.ByteString) == 28
        Left (_ :: String) -> False

-- | An address that decodes as genuine bech32. Performs no effect.
isCanonicalBech32Address :: Text -> Bool
isCanonicalBech32Address addressText =
    case Bech32.decodeLenient addressText of
        Right (_hrp, dataPart) -> isJust (Bech32.dataPartToBytes dataPart)
        Left _ -> False

-- | One native asset quantity on a promoted chain output.
data ChainAsset = ChainAsset
    { chainAssetPolicy :: !Text
    , chainAssetName :: !Text
    , chainAssetQuantity :: !Integer
    }
    deriving stock (Show, Eq)

{- | Reference-script identity and bytes as an extended Koios UTxO view
reports them (A-001's "decode every ... reference-script byte ... needed to
construct the exact builder input").
-}
data ChainReferenceScript = ChainReferenceScript
    { chainReferenceScriptHashField :: !Text
    , chainReferenceScriptType :: !Text
    , chainReferenceScriptBytes :: !Text
    -- ^ Hex-encoded CBOR script bytes.
    }
    deriving stock (Show, Eq)

{- | Promoted shared chain-output view (DAT-257-ASSET-OUTPUT). Provider-only
response fields never enter this type; 'chainAssetReferenceScript' is
present only when the output actually carries a reference script.
-}
data ChainAssetUtxo = ChainAssetUtxo
    { chainAssetTxId :: !Text
    , chainAssetIndex :: !Int
    , chainAssetAddress :: !Text
    , chainAssetLovelace :: !Integer
    , chainAssetList :: ![ChainAsset]
    , chainAssetInlineDatum :: !(Maybe Value)
    , chainAssetReferenceScript :: !(Maybe ChainReferenceScript)
    }
    deriving stock (Show, Eq)

{- | Promoted resolved reference-script output (DAT-257-REFERENCE): the
requested script hash together with enough ledger output data
('chainReferenceOutput') for a transaction builder to validate and use the
reference directly.
-}
data ChainReference = ChainReference
    { chainReferenceScriptHash :: !Text
    , chainReferenceOutput :: !ChainAssetUtxo
    }
    deriving stock (Show, Eq)

{- | Promoted current-checkpoint view already consumed by advance\/status
logic (DAT-257-CHECKPOINT). Identity and decoded datum retain existing
validation and uniqueness rules.
-}
data ActiveCheckpoint = ActiveCheckpoint
    { activeCheckpointAid :: !Text
    , activeCheckpointAssetName :: !Text
    , activeCheckpointTxId :: !Text
    , activeCheckpointIndex :: !Int
    , activeCheckpointAddress :: !Text
    , activeCheckpointLovelace :: !Integer
    , activeCheckpointAssets :: ![ChainAsset]
    , activeCheckpointDatum :: !CheckpointDatumV1
    }
    deriving stock (Show, Eq)

{- | Promoted authenticated endpoint-board record with its output
reference (moved here unchanged from the former
@Cardano.KERI.Deployment.EndpointBoard.BoardEntry@; field names preserved
for every existing consumer). A catalog containing one malformed or
unauthenticated row is rejected wholly by
'Cardano.KERI.Deployment.EndpointBoard.resolveBoardCatalog'.
-}
data BoardEntry = BoardEntry
    { boardWitnessKey :: !ByteString
    , boardAid :: !Text
    , boardScheme :: !Text
    , boardUrl :: !Text
    , boardTxId :: !Text
    , boardIndex :: !Int
    , boardLovelace :: !Integer
    , boardOwnerKeyHash :: !ByteString
    }
    deriving stock (Show, Eq)

{- Extended-response JSON decoding lives here (not in
"Cardano.KERI.ChainQuery.Koios") solely to avoid orphan instances: these
types are owned by this module, and 'FromJSON' is owned by @aeson@, so
Haskell requires the instance to sit with one of the two. The field names
("policy_id", "tx_hash", "reference_script", ...) are still Koios's own
naming convention (A-001) — 'Cardano.KERI.ChainQuery.Koios.decodeExtendedUtxoJson'
is the fail-closed entry point callers should use.
-}

instance FromJSON ChainAsset where
    parseJSON = withObject "ChainAsset" $ \o ->
        ChainAsset
            <$> o .: "policy_id"
            <*> o .: "asset_name"
            <*> integerTextField o "quantity"

instance FromJSON ChainReferenceScript where
    parseJSON = withObject "ChainReferenceScript" $ \o ->
        ChainReferenceScript
            <$> o .: "hash"
            <*> o .: "type"
            <*> o .: "bytes"

instance FromJSON ChainAssetUtxo where
    parseJSON = parseExtendedChainAssetUtxo

{- | Exposed directly (not only via the 'FromJSON' instance) so
"Cardano.KERI.ChainQuery.Koios" can wrap parse failure as a
'ChainQueryError' with 'Data.Aeson.Types.parseEither'.
-}
parseExtendedChainAssetUtxo :: Value -> Parser ChainAssetUtxo
parseExtendedChainAssetUtxo = withObject "ChainAssetUtxo" $ \o -> do
    inline <- o .:? "inline_datum"
    chainAssetInlineDatum <-
        joinMaybe
            <$> traverse
                (withObject "InlineDatum" (.:? "value"))
                inline
    chainAssetReferenceScript <- o .:? "reference_script"
    ChainAssetUtxo
        <$> o .: "tx_hash"
        <*> o .: "tx_index"
        <*> o .: "address"
        <*> integerTextField o "value"
        <*> o .: "asset_list"
        <*> pure chainAssetInlineDatum
        <*> pure chainAssetReferenceScript

integerTextField :: Object -> Key -> Parser Integer
integerTextField objectValue field = do
    spelling <- objectValue .: field
    maybe
        (fail $ "expected decimal integer string in " <> show field)
        pure
        (readMaybe $ T.unpack spelling)

joinMaybe :: Maybe (Maybe a) -> Maybe a
joinMaybe = \case
    Nothing -> Nothing
    Just value -> value
