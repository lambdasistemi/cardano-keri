{- |
Module      : Cardano.KERI.Deployment.CheckpointIndex
Description : Exact-asset Koios discovery and fail-closed V1 status rendering
-}
module Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    checkpointAssetName,
    resolveActiveCheckpoint,
    renderCheckpointStatus,
    queryCheckpointStatus,
) where

import Cardano.KERI.AID.CESR (
    Primitive (..),
    parsePrimitive,
 )
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
    checkpointDatumFromData,
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Threshold (Threshold (..))
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
    KoiosToken,
    queryAssetUtxos,
 )
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
 )
import Cardano.KERI.Deployment.Registration (plutusDataFromJson)
import Control.Monad (unless)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

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

checkpointAssetName :: Text -> Either String Text
checkpointAssetName aid =
    case parsePrimitive (TE.encodeUtf8 aid) of
        Right (SelfAddressing raw, rest)
            | BS.null rest ->
                Right $
                    TE.decodeUtf8 $
                        convertToBase Base16 $
                            deriveAidAssetName raw
        _ -> Left "AID must be one 44-character KERI E-code identifier"

queryCheckpointStatus ::
    Text ->
    Maybe KoiosToken ->
    Manifest ->
    Text ->
    IO Text
queryCheckpointStatus baseUrl token manifest aid = do
    assetName <- either fail pure (checkpointAssetName aid)
    utxos <-
        queryAssetUtxos
            baseUrl
            token
            (checkpointPolicyId $ manifestCheckpoint manifest)
            assetName
    either fail pure (renderCheckpointStatus manifest aid assetName utxos)

renderCheckpointStatus ::
    Manifest ->
    Text ->
    Text ->
    [ChainAssetUtxo] ->
    Either String Text
renderCheckpointStatus _ aid _ [] =
    Right ("state NOT REGISTERED aid " <> aid)
renderCheckpointStatus manifest aid assetName matches = do
    active <- resolveActiveCheckpoint manifest aid assetName matches
    let datum = activeCheckpointDatum active
    pure $
        T.unwords
            [ "state ACTIVE"
            , "seq"
            , T.pack (show $ cdSeq datum)
            , "native"
            , T.pack (show $ cdNativeSn datum)
            , "keys"
            , renderThreshold (cdCurThreshold datum) (length $ cdCurKeys datum)
            , "witnesses"
            , T.pack (show $ length $ cdWitnesses datum)
            , "(toad"
            , T.pack (show $ cdToad datum) <> ")"
            , "bond intact"
            , "tx"
            , activeCheckpointTxId active
                <> "#"
                <> T.pack (show $ activeCheckpointIndex active)
            ]

resolveActiveCheckpoint ::
    Manifest ->
    Text ->
    Text ->
    [ChainAssetUtxo] ->
    Either String ActiveCheckpoint
resolveActiveCheckpoint _ _ _ [] =
    Left "checkpoint is not registered"
resolveActiveCheckpoint manifest aid assetName [utxo] = do
    unless
        (chainAssetAddress utxo == checkpointAddressBech32 (manifestCheckpoint manifest))
        (Left "checkpoint asset is not at the known V1 ACTIVE role address")
    unless
        ( assetQuantity
            (checkpointPolicyId $ manifestCheckpoint manifest)
            assetName
            (chainAssetList utxo)
            == 1
        )
        (Left "checkpoint output does not hold exactly one queried token")
    inline <-
        maybe
            (Left "checkpoint output has no inline datum")
            Right
            (chainAssetInlineDatum utxo)
    dat <-
        plutusDataFromJson inline
    checkpoint <-
        maybe
            (Left "checkpoint inline datum is not the frozen V1 schema")
            Right
            (checkpointDatumFromData dat)
    datum <-
        case checkpoint of
            V1 value -> Right value
    expectedAid <-
        case parsePrimitive (TE.encodeUtf8 aid) of
            Right (SelfAddressing raw, rest)
                | BS.null rest -> Right raw
            _ -> Left "AID must be one 44-character KERI E-code identifier"
    unless (cdCesrAid datum == expectedAid) $
        Left "checkpoint inline datum AID does not match the queried asset"
    let minimumEscrow =
            2_000_000
                + parameterRegistrationBond (manifestParameters manifest)
                + parameterFreezeBond (manifestParameters manifest)
    unless (chainAssetLovelace utxo >= minimumEscrow) $
        Left "checkpoint escrow is below min ADA + registration bond + freeze bond"
    pure
        ActiveCheckpoint
            { activeCheckpointAid = aid
            , activeCheckpointAssetName = assetName
            , activeCheckpointTxId = chainAssetTxId utxo
            , activeCheckpointIndex = chainAssetIndex utxo
            , activeCheckpointAddress = chainAssetAddress utxo
            , activeCheckpointLovelace = chainAssetLovelace utxo
            , activeCheckpointAssets = chainAssetList utxo
            , activeCheckpointDatum = datum
            }
resolveActiveCheckpoint _ _ _ matches =
    Left $
        "checkpoint lookup is ambiguous: "
            <> show (length matches)
            <> " live outputs"

assetQuantity :: Text -> Text -> [ChainAsset] -> Integer
assetQuantity policyId assetName =
    sum
        . map chainAssetQuantity
        . filter
            ( \asset ->
                chainAssetPolicy asset == policyId
                    && chainAssetName asset == assetName
            )

renderThreshold :: Threshold -> Int -> Text
renderThreshold threshold keyCount =
    case threshold of
        Unweighted required ->
            T.pack (show required <> "-of-" <> show keyCount)
        Weighted _ ->
            "weighted-" <> T.pack (show keyCount)
