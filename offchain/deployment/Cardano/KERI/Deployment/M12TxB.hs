{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}

module Cardano.KERI.Deployment.M12TxB (
    TxBWitnessMode (..),
    TxBRole (..),
    TxBScript (..),
    TxBSemanticPlan (..),
    TxBInputs (..),
    TxBSigningContext (..),
    TxBCreationEnvelope (..),
    TxBFit (..),
    TxBFitVerdict (..),
    TxBManifest (..),
    TxBProtocol (..),
    TxBScriptRow (..),
    TxBSurfaceB (..),
    TxBResidual (..),
    TxBBuildError (..),
    txBWitnessMode,
    buildTxB,
    buildTxBWithMode,
    inspectTxB,
    txBReferenceScriptFee,
    txBCreationEnvelope,
    txBManifest,
    familyRoles,
    isFamilyRole,
    roleName,
) where

-- \|
-- Module      : Cardano.KERI.Deployment.M12TxB
-- Description : Pure M12 TxB construction and witness-mode inspection
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : Apache-2.0
--
-- Owns the semantic TxB plan, explicit REFERENCE/INLINE witness carriage,
-- fail-closed script/reference validation, and the provenance manifest.
-- No CLI or live-provider edge.

import Cardano.KERI.Deployment.Script (computeScriptHash, mkCageScript)
import Cardano.Ledger.Alonzo.TxWits (Redeemers)
import Cardano.Ledger.Api.PParams (emptyPParams)
import Cardano.Ledger.Api.Tx (bodyTxL, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    ValidityInterval,
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    reqSignerHashesTxBodyL,
    vldtTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (TxOut, referenceScriptTxOutL)
import Cardano.Ledger.Api.Tx.Wits (addrTxWitsL, rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (StrictMaybe (SJust), unNonZero, unboundRational)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.PParams (
    ppMaxRefScriptSizePerTxG,
    ppMinFeeRefScriptCostPerByteL,
    ppRefScriptCostMultiplierG,
    ppRefScriptCostStrideG,
 )
import Cardano.Ledger.Conway.Tx (tierRefScriptFee)
import Cardano.Ledger.Core (PParams, mkBasicTx, ppMaxTxSizeL, sizeTxF)
import Cardano.Ledger.Hashes (KeyHash, ScriptHash)
import Cardano.Ledger.Keys (KeyRole (Guard))
import Cardano.Ledger.Mary.Value (MultiAsset)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (unless, when)
import Crypto.Hash (Digest, SHA256 (..), hash)
import Data.ByteString.Short (ShortByteString)
import Data.ByteString.Short qualified as SBS
import Data.Foldable (for_)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Lens.Micro ((&), (.~), (^.))

-- | Closed production/control witness choice.
data TxBWitnessMode
    = -- | Family scripts arrive through reference inputs.
      Reference
    | -- | Family scripts are carried as witnesses.
      Inline
    deriving stock (Eq, Show)

-- | Exact TxB family roles plus the labelled escrow extension.
data TxBRole
    = RoleAppend
    | RoleCursor
    | RoleStagingProofToken
    | RoleMaintenanceEscrow
    deriving stock (Eq, Ord, Show)

-- | One measured family script and its optional reference UTxO.
data TxBScript = TxBScript
    { txbScriptRole :: TxBRole
    , txbScriptHash :: ScriptHash
    , txbScriptBytes :: ShortByteString
    , txbScriptMeasuredBytes :: Int
    , txbScriptReference :: Maybe TxIn
    }
    deriving stock (Eq, Show)

-- | Carriage-free semantic plan shared by both witness modes.
data TxBSemanticPlan = TxBSemanticPlan
    { txbPlanConsumed :: Set TxIn
    , txbPlanProduced :: [TxOut ConwayEra]
    , txbPlanMint :: MultiAsset
    , txbPlanRedeemers :: Redeemers ConwayEra
    , txbPlanRequiredSigners :: Set (KeyHash Guard)
    , txbPlanValidity :: ValidityInterval
    , txbPlanCollateral :: Set TxIn
    , txbPlanRoles :: [TxBRole]
    }
    deriving stock (Eq, Show)

-- | Semantic plan plus the scripts that implement the named roles.
data TxBInputs = TxBInputs
    { txbInputsPlan :: TxBSemanticPlan
    , txbInputsScripts :: [TxBScript]
    }
    deriving stock (Eq, Show)

{- | Everything needed to construct and sign one reference-script creation
transaction.  The signing operation is supplied explicitly so this pure module
does not acquire a key-file, environment, or live-provider edge.
-}
data TxBSigningContext = TxBSigningContext
    { txbCreationInput :: TxIn
    , txbCreationOutput :: TxOut ConwayEra
    , txbSignCreation :: ConwayTx -> Either Text ConwayTx
    }

-- | One measured signed reference-script creation transaction.
data TxBCreationEnvelope = TxBCreationEnvelope
    { txbEnvelopeRole :: TxBRole
    , txbEnvelopeProgramBytes :: Int
    , txbEnvelopeCreationTxBytes :: Int
    , txbEnvelopeSigned :: Bool
    , txbEnvelopeVerdict :: TxBFitVerdict
    }
    deriving stock (Eq, Show)

-- | Signed headroom / limit comparison.
data TxBFitVerdict
    = Fits
    | Exceeds
    deriving stock (Eq, Show)

-- | Derived serialized and reference-script fit of one built TxB.
data TxBFit = TxBFit
    { txbFitMode :: TxBWitnessMode
    , txbFitTxBytes :: Int
    , txbFitMaxTxBytes :: Int
    , txbFitRefScriptBytes :: Int
    , txbFitMaxRefScriptBytes :: Int
    , txbFitBasePrice :: Rational
    , txbFitStride :: Int
    , txbFitMultiplier :: Rational
    , txbFitRefFee :: Coin
    , txbFitTxHeadroom :: Int
    , txbFitRefHeadroom :: Int
    , txbFitTxVerdict :: TxBFitVerdict
    , txbFitRefVerdict :: TxBFitVerdict
    }
    deriving stock (Eq, Show)

-- | Pinned protocol identities carried in the manifest.
data TxBProtocol = TxBProtocol
    { txbProtocolPackage :: Text
    , txbProtocolPackageSha :: Text
    , txbProtocolSnapshot :: Text
    , txbProtocolMaxRefScriptBytes :: Int
    , txbProtocolStride :: Int
    , txbProtocolMultiplier :: Double
    , txbProtocolMinFeePerByte :: Int
    }
    deriving stock (Eq, Show)

-- | One manifest script row.
data TxBScriptRow = TxBScriptRow
    { txbRowRole :: Text
    , txbRowHash :: Text
    , txbRowBytes :: Int
    }
    deriving stock (Eq, Show)

-- | The only permitted Surface-B representation: archived RED evidence.
data TxBSurfaceB = TxBSurfaceB
    { txbSurfaceBStatus :: Text
    , txbSurfaceBEvidenceSha256 :: Text
    }
    deriving stock (Eq, Show)

-- | One explicitly visible residual carried by the determination.
data TxBResidual = TxBResidual
    { txbResidualId :: Text
    , txbResidualStatus :: Text
    , txbResidualDetail :: Text
    }
    deriving stock (Eq, Show)

-- | Provenance-bound deterministic manifest value.
data TxBManifest = TxBManifest
    { txbManifestSchema :: Int
    , txbManifestMode :: TxBWitnessMode
    , txbManifestPlanDigest :: Text
    , txbManifestSurfaceB :: TxBSurfaceB
    , txbManifestAikenDigest :: Text
    , txbManifestProtocol :: TxBProtocol
    , txbManifestScripts :: [TxBScriptRow]
    , txbManifestAggregateBytes :: Int
    , txbManifestFit :: TxBFit
    , txbManifestFeeBoundary :: Map Text Integer
    , txbManifestResiduals :: [TxBResidual]
    , txbManifestCaveats :: [Text]
    }
    deriving stock (Eq, Show)

-- | Typed fail-closed construction and report errors.
data TxBBuildError
    = MissingScript TxBRole
    | DuplicateScript TxBRole
    | MismatchedScriptHash TxBRole
    | MismatchedScriptSize TxBRole
    | MissingReference TxBRole
    | UnexpectedReference TxBRole
    | MissingWitness TxBRole
    | UnexpectedWitness TxBRole
    | AggregateLimitBreached Int Int
    | ModeCarriageDisagreement TxBWitnessMode
    | CreationSigningFailed Text
    | UnsignedCreationTransaction TxBRole
    | CreationBodyChanged TxBRole
    | ProtocolValueMismatch Text Text Text
    | UnavailableAncestry Text
    | BinaryDigestMismatch Text Text
    | ManifestInconsistency Text
    deriving stock (Eq, Show)

-- | Production witness choice: reference inputs.
txBWitnessMode :: TxBWitnessMode
txBWitnessMode = Reference

-- | Build the production/reference transaction.
buildTxB ::
    PParams ConwayEra ->
    TxBInputs ->
    Either TxBBuildError ConwayTx
buildTxB = buildTxBWithMode txBWitnessMode

-- | Build either carriage branch from the same semantic inputs.
buildTxBWithMode ::
    TxBWitnessMode ->
    PParams ConwayEra ->
    TxBInputs ->
    Either TxBBuildError ConwayTx
buildTxBWithMode mode pparams inputs = do
    requireMinFeeSnapshot pparams
    validateInputs mode inputs
    let plan = txbInputsPlan inputs
        scripts = familyScripts inputs
        referenceBytes = case mode of
            Reference -> sum (map txbScriptMeasuredBytes scripts)
            Inline -> 0
        referenceInputs = case mode of
            Reference -> familyReferenceSet scripts
            Inline -> Set.empty
        scriptWitnesses = case mode of
            Reference -> Map.empty
            Inline ->
                Map.fromList
                    [ (txbScriptHash script, mkCageScript (txbScriptBytes script))
                    | script <- scripts
                    ]
    unless (referenceBytes <= ledgerMaxRefScriptBytes) $
        Left (AggregateLimitBreached referenceBytes ledgerMaxRefScriptBytes)
    let body =
            mkBasicTxBody
                & inputsTxBodyL .~ txbPlanConsumed plan
                & outputsTxBodyL .~ StrictSeq.fromList (txbPlanProduced plan)
                & mintTxBodyL .~ txbPlanMint plan
                & reqSignerHashesTxBodyL .~ txbPlanRequiredSigners plan
                & vldtTxBodyL .~ txbPlanValidity plan
                & collateralInputsTxBodyL .~ txbPlanCollateral plan
                & referenceInputsTxBodyL .~ referenceInputs
                & feeTxBodyL .~ Coin 1_000_000
    pure $
        mkBasicTx body
            & witsTxL . rdmrsTxWitsL .~ txbPlanRedeemers plan
            & witsTxL . scriptTxWitsL .~ scriptWitnesses

-- | Derive serialized and reference-script fit from a built transaction.
inspectTxB ::
    PParams ConwayEra ->
    TxBWitnessMode ->
    TxBInputs ->
    ConwayTx ->
    Either TxBBuildError TxBFit
inspectTxB pparams mode inputs tx = do
    requireMinFeeSnapshot pparams
    validateInputs mode inputs
    validateBuiltCarriage mode inputs tx
    referenceFee <- txBReferenceScriptFee pparams referenceBytes
    let txBytes = fromIntegral (tx ^. sizeTxF)
        maxTxBytes = fromIntegral (pparams ^. ppMaxTxSizeL)
        txHeadroom = maxTxBytes - txBytes
        refHeadroom = ledgerMaxRefScriptBytes - referenceBytes
    pure
        TxBFit
            { txbFitMode = mode
            , txbFitTxBytes = txBytes
            , txbFitMaxTxBytes = maxTxBytes
            , txbFitRefScriptBytes = referenceBytes
            , txbFitMaxRefScriptBytes = ledgerMaxRefScriptBytes
            , txbFitBasePrice =
                unboundRational (pparams ^. ppMinFeeRefScriptCostPerByteL)
            , txbFitStride = ledgerRefScriptStride
            , txbFitMultiplier = ledgerRefScriptMultiplier
            , txbFitRefFee = referenceFee
            , txbFitTxHeadroom = txHeadroom
            , txbFitRefHeadroom = refHeadroom
            , txbFitTxVerdict = verdict txHeadroom
            , txbFitRefVerdict = verdict refHeadroom
            }
  where
    referenceBytes = case mode of
        Reference -> sum (map txbScriptMeasuredBytes (familyScripts inputs))
        Inline -> 0

-- | Pinned ledger tier fee for a non-negative aggregate byte count.
txBReferenceScriptFee ::
    PParams ConwayEra ->
    Int ->
    Either TxBBuildError Coin
txBReferenceScriptFee pparams scriptBytes = do
    requireMinFeeSnapshot pparams
    unless (scriptBytes >= 0) $
        Left $
            ProtocolValueMismatch
                "refScriptBytes"
                "non-negative"
                (T.pack (show scriptBytes))
    pure $
        tierRefScriptFee
            ledgerRefScriptMultiplier
            ledgerRefScriptStride
            (unboundRational (pparams ^. ppMinFeeRefScriptCostPerByteL))
            scriptBytes

-- | Build and measure one signed reference-script creation transaction.
txBCreationEnvelope ::
    PParams ConwayEra ->
    TxBSigningContext ->
    TxBScript ->
    Either TxBBuildError TxBCreationEnvelope
txBCreationEnvelope pparams context script = do
    validateScript script
    let output =
            txbCreationOutput context
                & referenceScriptTxOutL .~ SJust (mkCageScript (txbScriptBytes script))
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton (txbCreationInput context)
                & outputsTxBodyL .~ StrictSeq.fromList [output]
                & feeTxBodyL .~ Coin 1_000_000
        unsigned = mkBasicTx body
    signed <-
        case txbSignCreation context unsigned of
            Left detail -> Left (CreationSigningFailed detail)
            Right tx -> Right tx
    unless (signed ^. bodyTxL == unsigned ^. bodyTxL) $
        Left (CreationBodyChanged (txbScriptRole script))
    when (Set.null (signed ^. witsTxL . addrTxWitsL)) $
        Left (UnsignedCreationTransaction (txbScriptRole script))
    let creationBytes = fromIntegral (signed ^. sizeTxF)
        maximumBytes = fromIntegral (pparams ^. ppMaxTxSizeL)
    pure
        TxBCreationEnvelope
            { txbEnvelopeRole = txbScriptRole script
            , txbEnvelopeProgramBytes = txbScriptMeasuredBytes script
            , txbEnvelopeCreationTxBytes = creationBytes
            , txbEnvelopeSigned = True
            , txbEnvelopeVerdict = verdict (maximumBytes - creationBytes)
            }

-- | Provenance-bound deterministic manifest value.
txBManifest ::
    PParams ConwayEra ->
    TxBInputs ->
    ConwayTx ->
    Either TxBBuildError TxBManifest
txBManifest pparams inputs tx = do
    fit <- inspectTxB pparams txBWitnessMode inputs tx
    feeBoundary <- Map.fromList <$> traverse feeRow feeProbeSizes
    let scripts = familyScripts inputs
        rows =
            [ TxBScriptRow
                { txbRowRole = roleName (txbScriptRole script)
                , txbRowHash = T.pack (show (txbScriptHash script))
                , txbRowBytes = txbScriptMeasuredBytes script
                }
            | script <- scripts
            ]
    pure
        TxBManifest
            { txbManifestSchema = 1
            , txbManifestMode = txBWitnessMode
            , txbManifestPlanDigest = planDigest (txbInputsPlan inputs)
            , txbManifestSurfaceB =
                TxBSurfaceB "ARCHIVED_RED" archivedRedEvidenceSha256
            , txbManifestAikenDigest = s0AikenDigest
            , txbManifestProtocol =
                TxBProtocol
                    { txbProtocolPackage = ledgerPackage
                    , txbProtocolPackageSha = ledgerPackageSha256
                    , txbProtocolSnapshot = ledgerSnapshot
                    , txbProtocolMaxRefScriptBytes = ledgerMaxRefScriptBytes
                    , txbProtocolStride = ledgerRefScriptStride
                    , txbProtocolMultiplier =
                        fromRational ledgerRefScriptMultiplier
                    , txbProtocolMinFeePerByte = 44
                    }
            , txbManifestScripts = rows
            , txbManifestAggregateBytes = sum (map txbRowBytes rows)
            , txbManifestFit = fit
            , txbManifestFeeBoundary = feeBoundary
            , txbManifestResiduals = requiredResiduals
            , txbManifestCaveats = [sizeOnlyCaveat]
            }
  where
    feeRow bytes = do
        Coin fee <- txBReferenceScriptFee pparams bytes
        pure (T.pack (show bytes), fee)

-- | The three required TxB family roles, in order.
familyRoles :: [TxBRole]
familyRoles =
    [RoleAppend, RoleCursor, RoleStagingProofToken]

-- | True for the three required family roles.
isFamilyRole :: TxBRole -> Bool
isFamilyRole RoleMaintenanceEscrow = False
isFamilyRole _ = True

-- | Stable role name used in the manifest and report.
roleName :: TxBRole -> Text
roleName = \case
    RoleAppend -> "append"
    RoleCursor -> "cursor"
    RoleStagingProofToken -> "staging_proof_token"
    RoleMaintenanceEscrow -> "maintenance_escrow"

ledgerPParams :: PParams ConwayEra
ledgerPParams = emptyPParams

ledgerMaxRefScriptBytes :: Int
ledgerMaxRefScriptBytes =
    fromIntegral (ledgerPParams ^. ppMaxRefScriptSizePerTxG)

ledgerRefScriptStride :: Int
ledgerRefScriptStride =
    fromIntegral (unNonZero (ledgerPParams ^. ppRefScriptCostStrideG))

ledgerRefScriptMultiplier :: Rational
ledgerRefScriptMultiplier =
    unboundRational (ledgerPParams ^. ppRefScriptCostMultiplierG)

ledgerPackage :: Text
ledgerPackage = "cardano-ledger-conway-1.21.0.0"

ledgerPackageSha256 :: Text
ledgerPackageSha256 =
    "c31a38424d578a7a6a2c51769e81296e731c84c5e69e1879645b044e2e6cf1e6"

ledgerSnapshot :: Text
ledgerSnapshot =
    "cardano-node-clients-a10cdb73317a2b6d5375b216f72f40b71736e648"

archivedRedEvidenceSha256 :: Text
archivedRedEvidenceSha256 =
    "bd569a319a9c3bcee73012854759f67acb4f68c6be191b6421b912f63dd44da1"

s0AikenDigest :: Text
s0AikenDigest =
    "c248f991a51176fe9e7b1c08b47939a1c55be3c1aebe3ca544d546640360e689"

sizeOnlyCaveat :: Text
sizeOnlyCaveat = "size-only; transaction-fit unproven"

feeProbeSizes :: [Int]
feeProbeSizes = [25_599, 25_600, 25_601, 25_617, 26_448]

requiredResiduals :: [TxBResidual]
requiredResiduals =
    [ TxBResidual
        { txbResidualId = "A3-F1"
        , txbResidualStatus = "ADVISORY"
        , txbResidualDetail =
            "the shipped harness does not observe the AIKEN_EXPECTED_VERSION seam"
        }
    , TxBResidual
        { txbResidualId = "F1-ERROR-CLASSIFICATION"
        , txbResidualStatus = "OPEN"
        , txbResidualDetail =
            "fail-closed safety held; error classification diverged"
        }
    ]

requireMinFeeSnapshot ::
    PParams ConwayEra ->
    Either TxBBuildError ()
requireMinFeeSnapshot pparams =
    let actual = unboundRational (pparams ^. ppMinFeeRefScriptCostPerByteL)
     in unless (actual == 44) $
            Left $
                ProtocolValueMismatch
                    "minFeeRefScriptCostPerByte"
                    "44"
                    (T.pack (show actual))

validateInputs ::
    TxBWitnessMode ->
    TxBInputs ->
    Either TxBBuildError ()
validateInputs mode inputs = do
    let grouped =
            Map.fromListWith
                (++)
                [ (txbScriptRole script, [script])
                | script <- txbInputsScripts inputs
                ]
    for_ familyRoles $ \role ->
        case Map.findWithDefault [] role grouped of
            [] -> Left (MissingScript role)
            [_] -> pure ()
            _ -> Left (DuplicateScript role)
    for_ (txbInputsScripts inputs) $ \script -> do
        validateScript script
        case (mode, isFamilyRole (txbScriptRole script), txbScriptReference script) of
            (Reference, True, Nothing) ->
                Left (MissingReference (txbScriptRole script))
            (Inline, True, Just _) ->
                Left (UnexpectedReference (txbScriptRole script))
            _ -> pure ()

validateScript :: TxBScript -> Either TxBBuildError ()
validateScript script = do
    unless
        (txbScriptMeasuredBytes script == SBS.length (txbScriptBytes script))
        $ Left (MismatchedScriptSize (txbScriptRole script))
    unless
        (txbScriptHash script == computeScriptHash (txbScriptBytes script))
        $ Left (MismatchedScriptHash (txbScriptRole script))

validateBuiltCarriage ::
    TxBWitnessMode ->
    TxBInputs ->
    ConwayTx ->
    Either TxBBuildError ()
validateBuiltCarriage mode inputs tx =
    let scripts = familyScripts inputs
        hashes = Set.fromList (map txbScriptHash scripts)
        expectedReferences = familyReferenceSet scripts
        actualReferences = tx ^. bodyTxL . referenceInputsTxBodyL
        actualWitnesses = Map.keysSet (tx ^. witsTxL . scriptTxWitsL)
     in case mode of
            Reference -> do
                unless (actualReferences == expectedReferences) $
                    Left (ModeCarriageDisagreement Reference)
                unless (Set.null (hashes `Set.intersection` actualWitnesses)) $
                    Left (UnexpectedWitness RoleAppend)
            Inline -> do
                unless (Set.null actualReferences) $
                    Left (ModeCarriageDisagreement Inline)
                unless (actualWitnesses == hashes) $
                    Left (MissingWitness RoleAppend)

familyScripts :: TxBInputs -> [TxBScript]
familyScripts =
    filter (isFamilyRole . txbScriptRole) . txbInputsScripts

familyReferenceSet :: [TxBScript] -> Set TxIn
familyReferenceSet scripts =
    Set.fromList
        [ reference
        | script <- scripts
        , Just reference <- [txbScriptReference script]
        ]

verdict :: Int -> TxBFitVerdict
verdict headroom
    | headroom >= 0 = Fits
    | otherwise = Exceeds

planDigest :: TxBSemanticPlan -> Text
planDigest plan =
    T.pack (show (hash payload :: Digest SHA256))
  where
    payload =
        TE.encodeUtf8 $
            T.intercalate
                "\n"
                [ T.pack (show (Set.toAscList (txbPlanConsumed plan)))
                , T.pack (show (length (txbPlanProduced plan)))
                , T.pack (show (txbPlanMint plan))
                , T.pack (show (txbPlanRedeemers plan))
                , T.pack (show (txbPlanRequiredSigners plan))
                , T.pack (show (txbPlanValidity plan))
                , T.pack (show (txbPlanCollateral plan))
                , T.pack (show (txbPlanRoles plan))
                ]
