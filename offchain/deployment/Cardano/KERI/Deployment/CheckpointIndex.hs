{- |
Module      : Cardano.KERI.Deployment.CheckpointIndex
Description : Exact-asset Koios discovery and fail-closed V1 status rendering
-}
module Cardano.KERI.Deployment.CheckpointIndex (
    ActiveCheckpoint (..),
    checkpointAssetName,
    queryActiveCheckpoint,
    resolveActiveCheckpoint,
    renderCheckpointStatus,
    renderResolvedCheckpointStatus,
    resolveClosedCheckpoint,
    queryCheckpointStatus,
    queryCheckpointStatusWithBoard,
    renderCheckpointStatusWithBoard,
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
    ChainAssetHistory (..),
    ChainAssetUtxo (..),
    ChainMintingTransaction (..),
    ChainScriptRedeemer (..),
    ChainScriptRedeemers (..),
    ChainTransactionPart (..),
    ChainTransactionUtxos (..),
    KoiosToken,
    queryAssetHistory,
    queryAssetUtxos,
    queryScriptRedeemers,
    queryTransactionUtxos,
 )
import Cardano.KERI.Deployment.EndpointBoard (
    BoardEntry,
    queryBoardCatalog,
    renderWatchability,
 )
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
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
import Data.List (maximumBy)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import PlutusCore.Data (Data (..))

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
queryCheckpointStatus baseUrl token manifest aid =
    queryCheckpointStatusUsing
        baseUrl
        token
        manifest
        aid
        ( \assetName utxos ->
            either fail pure $
                renderCheckpointStatus manifest aid assetName utxos
        )

queryCheckpointStatusWithBoard ::
    Text ->
    Maybe KoiosToken ->
    Manifest ->
    EndpointBoardManifest ->
    Text ->
    IO Text
queryCheckpointStatusWithBoard baseUrl token manifest boardManifest aid =
    queryCheckpointStatusUsing
        baseUrl
        token
        manifest
        aid
        renderActive
  where
    info = endpointBoardManifestInfo boardManifest
    renderActive assetName [] =
        either fail pure $
            renderCheckpointStatusWithBoard
                manifest
                aid
                assetName
                []
                []
    renderActive assetName utxos = do
        catalog <-
            queryBoardCatalog
                baseUrl
                token
                (endpointBoardPolicyId info)
                (endpointBoardAddress info)
        either fail pure $
            renderCheckpointStatusWithBoard
                manifest
                aid
                assetName
                utxos
                catalog

queryCheckpointStatusUsing ::
    Text ->
    Maybe KoiosToken ->
    Manifest ->
    Text ->
    (Text -> [ChainAssetUtxo] -> IO Text) ->
    IO Text
queryCheckpointStatusUsing baseUrl token manifest aid renderActive = do
    assetName <- either fail pure (checkpointAssetName aid)
    let policy = checkpointPolicyId $ manifestCheckpoint manifest
    history <- queryAssetHistory baseUrl token policy assetName
    latest <- either fail pure (latestMintingTransaction policy assetName history)
    case latest of
        Just minting
            | chainMintingQuantity minting == -1 -> do
                redeemers <- queryScriptRedeemers baseUrl token policy
                transaction <-
                    queryTransactionUtxos
                        baseUrl
                        token
                        [chainMintingTxId minting]
                closed <-
                    either fail pure $
                        resolveClosedCheckpoint
                            policy
                            assetName
                            history
                            redeemers
                            transaction
                case closed of
                    Just txId ->
                        pure $
                            "state NOT REGISTERED (closed at "
                                <> txId
                                <> ") aid "
                                <> aid
                    Nothing -> renderActive assetName []
        _ -> do
            utxos <- queryAssetUtxos baseUrl token policy assetName
            renderActive assetName utxos

renderResolvedCheckpointStatus ::
    Manifest ->
    Text ->
    Text ->
    [ChainAssetUtxo] ->
    Maybe Text ->
    Either String Text
renderResolvedCheckpointStatus manifest aid assetName utxos closed =
    case closed of
        Just txId ->
            Right $
                "state NOT REGISTERED (closed at "
                    <> txId
                    <> ") aid "
                    <> aid
        Nothing ->
            renderCheckpointStatus manifest aid assetName utxos

queryActiveCheckpoint ::
    Text ->
    Maybe KoiosToken ->
    Manifest ->
    Text ->
    IO ActiveCheckpoint
queryActiveCheckpoint baseUrl token manifest aid = do
    assetName <- either fail pure (checkpointAssetName aid)
    utxos <-
        queryAssetUtxos
            baseUrl
            token
            (checkpointPolicyId $ manifestCheckpoint manifest)
            assetName
    either fail pure (resolveActiveCheckpoint manifest aid assetName utxos)

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

renderCheckpointStatusWithBoard ::
    Manifest ->
    Text ->
    Text ->
    [ChainAssetUtxo] ->
    [BoardEntry] ->
    Either String Text
renderCheckpointStatusWithBoard manifest aid assetName matches catalog = do
    status <- renderCheckpointStatus manifest aid assetName matches
    case matches of
        [] -> pure status
        _ -> do
            active <-
                resolveActiveCheckpoint manifest aid assetName matches
            pure $
                status
                    <> " "
                    <> renderWatchability
                        (cdWitnesses $ activeCheckpointDatum active)
                        catalog

resolveClosedCheckpoint ::
    Text ->
    Text ->
    [ChainAssetHistory] ->
    [ChainScriptRedeemers] ->
    [ChainTransactionUtxos] ->
    Either String (Maybe Text)
resolveClosedCheckpoint policy assetName histories redeemerSets transactions = do
    latest <- latestMintingTransaction policy assetName histories
    case latest of
        Nothing -> pure Nothing
        Just minting
            | chainMintingQuantity minting /= -1 ->
                pure Nothing
            | otherwise ->
                pure $
                    if provesClose minting
                        then Just (chainMintingTxId minting)
                        else Nothing
  where
    provesClose minting =
        case ( matchingRedeemers
             , filter
                ( (== chainMintingTxId minting)
                    . chainTransactionTxId
                )
                transactions
             ) of
            ([redeemers], [transaction]) ->
                case checkpointInputs transaction of
                    [checkpointInput] ->
                        hasCloseBurn minting checkpointInput redeemers
                            && hasCloseSpend minting redeemers
                            && hasExactRefund checkpointInput transaction
                    _ -> False
            _ -> False
    matchingRedeemers =
        filter ((== policy) . chainRedeemerScriptHash) redeemerSets
    checkpointInputs transaction =
        filter
            ( \input ->
                case chainTransactionPartAssets input of
                    [asset] ->
                        chainAssetPolicy asset == policy
                            && chainAssetName asset == assetName
                            && chainAssetQuantity asset == 1
                    _ -> False
            )
            (chainTransactionInputs transaction)
    hasCloseBurn minting input redeemers =
        any
            ( \redeemer ->
                chainRedeemerPurpose redeemer == "mint"
                    && chainRedeemerTxId redeemer == chainMintingTxId minting
                    && case plutusDataFromJson (chainRedeemerData redeemer) of
                        Right
                            ( Constr
                                    1
                                    [Constr 0 [B spentTxId, I spentIndex]]
                                ) ->
                                hexText spentTxId == chainTransactionPartTxId input
                                    && spentIndex
                                        == fromIntegral
                                            (chainTransactionPartIndex input)
                        _ -> False
            )
            (chainScriptRedeemers redeemers)
    hasCloseSpend minting redeemers =
        any
            ( \redeemer ->
                chainRedeemerPurpose redeemer == "spend"
                    && chainRedeemerTxId redeemer == chainMintingTxId minting
                    && case plutusDataFromJson (chainRedeemerData redeemer) of
                        Right (Constr 0 [_closeEvidence]) -> True
                        _ -> False
            )
            (chainScriptRedeemers redeemers)
    hasExactRefund input transaction =
        any
            ( \output ->
                chainTransactionPartLovelace output
                    == chainTransactionPartLovelace input
                    && chainTransactionPartAddress output
                        /= chainTransactionPartAddress input
                    && null (chainTransactionPartAssets output)
            )
            (chainTransactionOutputs transaction)

latestMintingTransaction ::
    Text ->
    Text ->
    [ChainAssetHistory] ->
    Either String (Maybe ChainMintingTransaction)
latestMintingTransaction policy assetName histories =
    case filter
        ( \history ->
            chainHistoryPolicy history == policy
                && chainHistoryAssetName history == assetName
        )
        histories of
        [] -> Right Nothing
        [history] ->
            Right $
                case chainMintingTransactions history of
                    [] -> Nothing
                    transactions ->
                        Just $
                            maximumBy
                                ( comparing
                                    ( \transaction ->
                                        ( chainMintingBlockTime transaction
                                        , chainMintingTxId transaction
                                        )
                                    )
                                )
                                transactions
        _ -> Left "Koios returned ambiguous checkpoint asset history"

hexText :: BS.ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

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
