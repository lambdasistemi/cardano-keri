{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.Registration
Description : Build and settle V1 registration through the in-process runtime

#181 Slice 2C replaces the external transaction command path with the shared
'Cardano.KERI.Deployment.TransactionRuntime.runTransactionBuild' kernel. The
premint and register phases consume caller-resolved funding and reference
UTxOs, validate reference-script hashes against the immutable plan, build and
sign in process, derive the signed transaction id purely, submit exactly that
signed value, and observe settlement through the injected runtime.
-}
module Cardano.KERI.Deployment.Registration (
    RegistrationPlan (..),
    RegisterConfig (..),
    RegistrationCheckError (..),
    RegistrationError (..),
    AssetObservationTimeout (..),
    mkRegistrationPlan,
    premintOne,
    registerOne,
    awaitAsset,
    plutusDataJson,
    plutusDataFromJson,
) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Checkpoint.Datum (
    CheckpointDatum (..),
    CheckpointDatumV1 (..),
 )
import Cardano.KERI.AID.Checkpoint.Message (deriveAidAssetName)
import Cardano.KERI.AID.Checkpoint.Registration (
    RegistrationEvidence (..),
    proofTokenName,
 )
import Cardano.KERI.AID.Checkpoint.Wire (
    asPlcData,
    registerObserverRedeemerData,
 )
import Cardano.KERI.Deployment.ChainIndex (
    ChainAsset (..),
    ChainAssetUtxo (..),
 )
import Cardano.KERI.Deployment.KEL (InceptionExport (..))
import Cardano.KERI.Deployment.Manifest (
    CheckpointInfo (..),
    DeploymentParameters (..),
    Manifest (..),
    NetworkInfo (..),
    Reference (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    AggregateExUnitsError,
    FundingPair (..),
    PayerSelectionError,
    TransactionBuildError,
    TransactionRuntime (..),
    checkAggregateExUnits,
    fundingSpends,
    runTransactionBuild,
    selectFundingPair,
 )
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    decodeAddr,
    serialiseAccountAddress,
 )
import Cardano.Ledger.Api.Tx.Out (referenceScriptTxOutL)
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    StrictMaybe (SJust, SNothing),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.TxCert (
    ConwayDelegCert (ConwayRegCert),
    ConwayTxCert (ConwayTxCertDeleg),
 )
import Cardano.Ledger.Core (
    PParams,
    TxOut,
    hashScript,
    mkBasicTxOut,
    ppKeyDepositL,
    valueTxOutL,
 )
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Hashes (
    ScriptHash (..),
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Tx.Balance (CollateralUtxos (..))
import Cardano.Tx.Build (
    BuildOptions (..),
    CertWitness (ScriptCert),
    Check (..),
    InterpretIO (..),
    TxBuild,
    certify,
    collateral,
    defaultBuildOptions,
    mint,
    output,
    payTo',
    reference,
    spend,
    valid,
    withdrawScript,
 )
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Data.Aeson (Value, object, withObject, (.:), (.:?), (.=))
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (
    Base (Base16),
    convertFromBase,
    convertToBase,
 )
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Lens.Micro ((^.))
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))
import Text.Read (readMaybe)

data RegistrationPlan = RegistrationPlan
    { planAid :: !Text
    , planProofPolicy :: !Text
    , planProofName :: !Text
    , planProofReference :: !Text
    , planCheckpointPolicy :: !Text
    , planCheckpointName :: !Text
    , planCheckpointReference :: !Text
    , planCheckpointAddress :: !Text
    , planLifecycleReference :: !Text
    , planLifecycleRewardAddress :: !Text
    , planEscrowLovelace :: !Integer
    , planPremintRedeemer :: !Value
    , planCheckpointRedeemer :: !Value
    , planProofBurnRedeemer :: !Value
    , planObserverRedeemer :: !Value
    , planLifecycleCertificateRedeemer :: !Value
    , planCheckpointDatum :: !Value
    }
    deriving stock (Show, Eq)

{- | Caller-owned capabilities and already-resolved ledger rows for one
registration evolution. Reference outputs are deliberately supplied as full
'TxOut's: their script bytes affect both fees and script-integrity language
selection, so a mere @TxIn@ is not enough input to the build kernel.
-}
data RegisterConfig = RegisterConfig
    { registerRuntime :: !(TransactionRuntime IO)
    , registerReferenceUtxos :: ![(TxIn, TxOut ConwayEra)]
    , registerFundingAddress :: !Addr
    , registerLifecycleRewardAccount :: !AccountAddress
    , registerQueryAsset :: !(Text -> Text -> IO [ChainAssetUtxo])
    , registerTimeoutSeconds :: !Int
    , registerPollDelayMicros :: !Int
    }

-- | Domain-specific checks performed after the build converges.
newtype RegistrationCheckError
    = RegistrationAggregateExUnitsExceeded AggregateExUnitsError
    deriving stock (Eq, Show)

-- | Typed, phase-preserving failures of either registration transaction.
data RegistrationError
    = RegistrationFundingSelectionFailed !PayerSelectionError
    | RegistrationPlanRejected !String
    | RegistrationBuildFailed !(TransactionBuildError RegistrationCheckError)
    deriving stock (Eq, Show)

-- | The exact asset identity that was not observed before the deadline.
data AssetObservationTimeout = AssetObservationTimeout !Text !Text !Text !Text
    deriving stock (Eq, Show)

-- | Preserve already-encoded Plutus data at the typed builder boundary.
newtype RawData = RawData Data

instance ToData RawData where
    toBuiltinData (RawData datum) = BuiltinData datum

mkRegistrationPlan ::
    Manifest ->
    Integer ->
    InceptionExport ->
    Either String RegistrationPlan
mkRegistrationPlan manifest escrow inception = do
    unless
        ( networkName (manifestNetwork manifest) == "preprod"
            && networkMagic (manifestNetwork manifest) == 1
        )
        (Left "registration manifest is not preprod network magic 1")
    when (escrow <= 0) $
        Left "escrow-lovelace must be positive"
    let expectedEscrow =
            2_000_000
                + parameterRegistrationBond (manifestParameters manifest)
                + parameterFreezeBond (manifestParameters manifest)
    when
        ( parameterRegistrationBond (manifestParameters manifest)
            /= 1_000_000_000
        )
        (Left "manifest registration bond is not the frozen M1 V1 value")
    when
        (parameterFreezeBond (manifestParameters manifest) /= 5_000_000)
        (Left "manifest freeze bond is not the frozen M1 V1 value")
    when (escrow > expectedEscrow) $
        Left "escrow-lovelace exceeds the frozen M1 V1 escrow"
    proof <- scriptNamed "hash-proof" manifest
    checkpoint <- scriptNamed "checkpoint-register" manifest
    lifecycle <- scriptNamed "observer-lifecycle" manifest
    let datum = inceptionDatum inception
        evidence = inceptionEvidence inception
        proofName =
            proofTokenName
                (reEventBytes evidence)
                (cdCesrAid datum)
        checkpointName = deriveAidAssetName (cdCesrAid datum)
        checkpointPolicy =
            checkpointPolicyId (manifestCheckpoint manifest)
    unless (scriptHash checkpoint == checkpointPolicy) $
        Left "manifest checkpoint policy does not match its script entry"
    lifecycleHash <- decodeHex28 "observer-lifecycle script hash" (scriptHash lifecycle)
    lifecycleRewardAddress <- rewardAddress lifecycleHash
    pure
        RegistrationPlan
            { planAid = inceptionAid inception
            , planProofPolicy = scriptHash proof
            , planProofName = hexText proofName
            , planProofReference = renderReference (scriptReference proof)
            , planCheckpointPolicy = checkpointPolicy
            , planCheckpointName = hexText checkpointName
            , planCheckpointReference =
                renderReference (scriptReference checkpoint)
            , planCheckpointAddress =
                checkpointAddressBech32 (manifestCheckpoint manifest)
            , planLifecycleReference =
                renderReference (scriptReference lifecycle)
            , planLifecycleRewardAddress = lifecycleRewardAddress
            , planEscrowLovelace = escrow
            , planPremintRedeemer =
                plutusDataJson $
                    Constr
                        0
                        [ B (reEventBytes evidence)
                        , B (cdCesrAid datum)
                        , I (fromIntegral $ reOffI evidence)
                        , I (fromIntegral $ inceptionDigestOffset inception)
                        ]
            , planCheckpointRedeemer = plutusDataJson (Constr 0 [])
            , planProofBurnRedeemer =
                plutusDataJson (Constr 0 [B "", B "", I 0, I 0])
            , planObserverRedeemer =
                plutusDataJson $
                    registerObserverRedeemerData
                        (decodeHexUnsafe checkpointPolicy)
                        evidence
            , planLifecycleCertificateRedeemer = plutusDataJson (I 0)
            , planCheckpointDatum = plutusDataJson (asPlcData $ V1 datum)
            }

{- | Build, sign, submit, and observe the hash-proof premint transaction.

The optional lifecycle certificate is emitted from the same protocol-parameter
snapshot used by balancing and the aggregate execution-unit check.
-}
premintOne ::
    RegisterConfig ->
    RegistrationPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    Bool ->
    IO (Either RegistrationError TxId)
premintOne config plan inputs registerLifecycle =
    case premintInputs config plan inputs registerLifecycle of
        Left err -> pure (Left err)
        Right PremintInputs{..} ->
            runRegistrationBuild
                config
                premintFunding
                []
                premintReferences
                ( \pparams ->
                    premintProgram
                        pparams
                        config
                        registerLifecycle
                        premintFunding
                        premintReferences
                        premintProofPolicy
                        premintProofName
                        premintProofRedeemer
                        premintLifecycleRedeemer
                )

{- | Build, sign, submit, and observe the checkpoint registration transaction.

The proof input is caller-resolved from the premint settlement query. It must
carry exactly one token under the plan's proof asset identity.
-}
registerOne ::
    RegisterConfig ->
    RegistrationPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    IO (Either RegistrationError TxId)
registerOne config plan inputs proofInput =
    case registerInputs config plan inputs proofInput of
        Left err -> pure (Left err)
        Right RegisterInputs{..} ->
            runRegistrationBuild
                config
                registerFunding
                [proofInput]
                registerReferences
                ( \pparams ->
                    registerProgram
                        pparams
                        config
                        registerFunding
                        registerReferences
                        proofInput
                        registerCheckpointAddress
                        (planEscrowLovelace plan)
                        registerCheckpointPolicy
                        registerCheckpointName
                        registerProofPolicy
                        registerProofName
                        registerCheckpointRedeemer
                        registerProofRedeemer
                        registerObserverRedeemer
                        registerDatum
                )

data PremintInputs = PremintInputs
    { premintFunding :: !FundingPair
    , premintReferences :: ![(TxIn, TxOut ConwayEra)]
    , premintProofPolicy :: !PolicyID
    , premintProofName :: !AssetName
    , premintProofRedeemer :: !RawData
    , premintLifecycleRedeemer :: !RawData
    }

data RegisterInputs = RegisterInputs
    { registerFunding :: !FundingPair
    , registerReferences :: ![(TxIn, TxOut ConwayEra)]
    , registerCheckpointAddress :: !Addr
    , registerCheckpointPolicy :: !PolicyID
    , registerCheckpointName :: !AssetName
    , registerProofPolicy :: !PolicyID
    , registerProofName :: !AssetName
    , registerCheckpointRedeemer :: !RawData
    , registerProofRedeemer :: !RawData
    , registerObserverRedeemer :: !RawData
    , registerDatum :: !RawData
    }

premintInputs ::
    RegisterConfig ->
    RegistrationPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    Bool ->
    Either RegistrationError PremintInputs
premintInputs config plan inputs registerLifecycle = do
    proofHash <- planScriptHash "proof policy" (planProofPolicy plan)
    proofName <- planAssetName "proof asset name" (planProofName plan)
    proofReference <-
        resolveReference
            "proof reference script hash"
            proofHash
            (planProofReference plan)
            (registerReferenceUtxos config)
    lifecycleReferences <-
        if registerLifecycle
            then do
                lifecycleHash <- lifecycleScriptHash config plan
                pure
                    <$> resolveReference
                        "lifecycle reference script hash"
                        lifecycleHash
                        (planLifecycleReference plan)
                        (registerReferenceUtxos config)
            else pure []
    proofRedeemer <- rawPlanData "premint redeemer" (planPremintRedeemer plan)
    lifecycleRedeemer <-
        rawPlanData
            "lifecycle certificate redeemer"
            (planLifecycleCertificateRedeemer plan)
    fundingPair <-
        first RegistrationFundingSelectionFailed $
            selectFundingPair isPlainUtxo (Coin 8_000_000) inputs
    pure
        PremintInputs
            { premintFunding = fundingPair
            , premintReferences = proofReference : lifecycleReferences
            , premintProofPolicy = PolicyID proofHash
            , premintProofName = proofName
            , premintProofRedeemer = proofRedeemer
            , premintLifecycleRedeemer = lifecycleRedeemer
            }

registerInputs ::
    RegisterConfig ->
    RegistrationPlan ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Either RegistrationError RegisterInputs
registerInputs config plan inputs proofInput = do
    proofHash <- planScriptHash "proof policy" (planProofPolicy plan)
    checkpointHash <-
        planScriptHash "checkpoint policy" (planCheckpointPolicy plan)
    proofName <- planAssetName "proof asset name" (planProofName plan)
    checkpointName <-
        planAssetName "checkpoint asset name" (planCheckpointName plan)
    checkpointAddress <- planAddress (planCheckpointAddress plan)
    lifecycleHash <- lifecycleScriptHash config plan
    proofReference <-
        resolveReference
            "proof reference script hash"
            proofHash
            (planProofReference plan)
            (registerReferenceUtxos config)
    checkpointReference <-
        resolveReference
            "checkpoint reference script hash"
            checkpointHash
            (planCheckpointReference plan)
            (registerReferenceUtxos config)
    lifecycleReference <-
        resolveReference
            "lifecycle reference script hash"
            lifecycleHash
            (planLifecycleReference plan)
            (registerReferenceUtxos config)
    requireProofAsset (PolicyID proofHash) proofName proofInput
    checkpointRedeemer <-
        rawPlanData "checkpoint redeemer" (planCheckpointRedeemer plan)
    proofRedeemer <-
        rawPlanData "proof burn redeemer" (planProofBurnRedeemer plan)
    observerRedeemer <-
        rawPlanData "observer redeemer" (planObserverRedeemer plan)
    datum <- rawPlanData "checkpoint datum" (planCheckpointDatum plan)
    fundingPair <-
        first RegistrationFundingSelectionFailed $
            selectFundingPair
                isPlainUtxo
                (Coin $ planEscrowLovelace plan + 5_000_000)
                inputs
    pure
        RegisterInputs
            { registerFunding = fundingPair
            , registerReferences =
                [proofReference, checkpointReference, lifecycleReference]
            , registerCheckpointAddress = checkpointAddress
            , registerCheckpointPolicy = PolicyID checkpointHash
            , registerCheckpointName = checkpointName
            , registerProofPolicy = PolicyID proofHash
            , registerProofName = proofName
            , registerCheckpointRedeemer = checkpointRedeemer
            , registerProofRedeemer = proofRedeemer
            , registerObserverRedeemer = observerRedeemer
            , registerDatum = datum
            }

premintProgram ::
    PParams ConwayEra ->
    RegisterConfig ->
    Bool ->
    FundingPair ->
    [(TxIn, TxOut ConwayEra)] ->
    PolicyID ->
    AssetName ->
    RawData ->
    RawData ->
    TxBuild RegisterCtx RegistrationCheckError ()
premintProgram
    pparams
    config
    registerLifecycle
    funding
    references
    proofPolicy
    proofName
    proofRedeemer
    lifecycleRedeemer = do
        mapM_ (spend . fst) (fundingSpends funding)
        collateral (fst $ fundingCollateral funding)
        _ <-
            output $
                mkBasicTxOut
                    (registerFundingAddress config)
                    ( assetValue
                        (Coin 5_000_000)
                        proofPolicy
                        proofName
                        1
                    )
        mint proofPolicy (Map.singleton proofName 1) proofRedeemer
        mapM_ (reference . fst) references
        when registerLifecycle $ do
            let lifecycleCredential =
                    case registerLifecycleRewardAccount config of
                        AccountAddress _ (AccountId credential) -> credential
                certificate =
                    ConwayTxCertDeleg $
                        ConwayRegCert
                            lifecycleCredential
                            (SJust $ pparams ^. ppKeyDepositL)
            _ <- certify certificate (ScriptCert lifecycleRedeemer)
            pure ()
        valid (registrationCheck pparams)
registerProgram ::
    PParams ConwayEra ->
    RegisterConfig ->
    FundingPair ->
    [(TxIn, TxOut ConwayEra)] ->
    (TxIn, TxOut ConwayEra) ->
    Addr ->
    Integer ->
    PolicyID ->
    AssetName ->
    PolicyID ->
    AssetName ->
    RawData ->
    RawData ->
    RawData ->
    RawData ->
    TxBuild RegisterCtx RegistrationCheckError ()
registerProgram
    pparams
    config
    funding
    references
    proofInput
    checkpointAddress
    escrowLovelace
    checkpointPolicy
    checkpointName
    proofPolicy
    proofName
    checkpointRedeemer
    proofRedeemer
    observerRedeemer
    checkpointDatum = do
        mapM_ (spend . fst) (fundingSpends funding)
        _ <- spend (fst proofInput)
        collateral (fst $ fundingCollateral funding)
        _ <-
            payTo'
                checkpointAddress
                ( assetValue
                    (Coin escrowLovelace)
                    checkpointPolicy
                    checkpointName
                    1
                )
                checkpointDatum
        mint
            checkpointPolicy
            (Map.singleton checkpointName 1)
            checkpointRedeemer
        mint proofPolicy (Map.singleton proofName (-1)) proofRedeemer
        mapM_ (reference . fst) references
        withdrawScript
            (registerLifecycleRewardAccount config)
            (Coin 0)
            observerRedeemer
        valid (registrationCheck pparams)
runRegistrationBuild ::
    RegisterConfig ->
    FundingPair ->
    [(TxIn, TxOut ConwayEra)] ->
    [(TxIn, TxOut ConwayEra)] ->
    (PParams ConwayEra -> TxBuild RegisterCtx RegistrationCheckError ()) ->
    IO (Either RegistrationError TxId)
runRegistrationBuild
    config
    funding
    extraInputs
    references
    mkProgram = do
        let runtime = registerRuntime config
        pparams <- trQueryProtocolParams runtime
        let frozenRuntime = runtime{trQueryProtocolParams = pure pparams}
            options =
                defaultBuildOptions
                    { boCollateralUtxos =
                        CollateralUtxos [fundingCollateral funding]
                    }
        first RegistrationBuildFailed
            <$> runTransactionBuild
                options
                frozenRuntime
                registerInterpret
                (fundingSpends funding <> extraInputs)
                references
                (registerFundingAddress config)
                (mkProgram pparams)

data RegisterCtx a

registerInterpret :: InterpretIO RegisterCtx
registerInterpret = InterpretIO (\case {})

plutusDataJson :: Data -> Value
plutusDataJson = \case
    Constr constructor fields ->
        object
            [ "constructor" .= constructor
            , "fields" .= map plutusDataJson fields
            ]
    Map pairs ->
        object
            [ "map"
                .= [ object
                        [ "k" .= plutusDataJson key
                        , "v" .= plutusDataJson value
                        ]
                   | (key, value) <- pairs
                   ]
            ]
    List values -> object ["list" .= map plutusDataJson values]
    I value -> object ["int" .= value]
    B bytes -> object ["bytes" .= hexText bytes]

plutusDataFromJson :: Value -> Either String Data
plutusDataFromJson = parseEither parsePlutusData

parsePlutusData :: Value -> Parser Data
parsePlutusData = withObject "detailed Plutus data" $ \o -> do
    constructor <- o .:? "constructor"
    fields <- o .:? "fields"
    mapValues <- o .:? "map"
    listValues <- o .:? "list"
    integer <- o .:? "int"
    bytes <- o .:? "bytes"
    case ( constructor
         , fields
         , mapValues
         , listValues
         , integer
         , bytes
         ) of
        (Just tag, Just values, Nothing, Nothing, Nothing, Nothing) ->
            Constr tag <$> traverse parsePlutusData values
        (Nothing, Nothing, Just pairs, Nothing, Nothing, Nothing) ->
            Map <$> traverse parsePair pairs
        (Nothing, Nothing, Nothing, Just values, Nothing, Nothing) ->
            List <$> traverse parsePlutusData values
        (Nothing, Nothing, Nothing, Nothing, Just value, Nothing) ->
            pure (I value)
        (Nothing, Nothing, Nothing, Nothing, Nothing, Just encoded) ->
            B <$> parseHexBytes encoded
        _ -> fail "detailed Plutus data has an invalid or ambiguous shape"
  where
    parsePair = withObject "Plutus map pair" $ \pair ->
        (,)
            <$> (pair .: "k" >>= parsePlutusData)
            <*> (pair .: "v" >>= parsePlutusData)
    parseHexBytes encoded =
        either
            (const $ fail "Plutus bytes are not hexadecimal")
            pure
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)

{- | Poll for one exact asset-bearing output. A zero-second timeout still
performs one real query before returning the typed timeout.
-}
awaitAsset ::
    (Text -> Text -> IO [ChainAssetUtxo]) ->
    Int ->
    Int ->
    Text ->
    Text ->
    Text ->
    Text ->
    IO (Either AssetObservationTimeout ChainAssetUtxo)
awaitAsset queryAsset pollMicros timeoutSeconds policyId assetName txId address = do
    started <- getCurrentTime
    let loop = do
            queried <- try (queryAsset policyId assetName)
            case queried of
                Right utxos ->
                    case filter matches utxos of
                        match : _ -> pure (Right match)
                        [] -> retry started
                Left (_ :: SomeException) -> retry started
        matches utxo =
            chainAssetTxId utxo == txId
                && chainAssetAddress utxo == address
                && any matchesAsset (chainAssetList utxo)
        matchesAsset asset =
            chainAssetPolicy asset == policyId
                && chainAssetName asset == assetName
                && chainAssetQuantity asset == 1
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt >= fromIntegral timeoutSeconds
                then
                    pure
                        ( Left
                            (AssetObservationTimeout policyId assetName txId address)
                        )
                else threadDelay pollMicros >> loop
    loop

registrationCheck ::
    PParams ConwayEra ->
    ConwayTx ->
    Check RegistrationCheckError
registrationCheck pparams tx =
    case checkAggregateExUnits pparams tx of
        Pass -> Pass
        LedgerFail failure -> LedgerFail failure
        CustomFail failure ->
            CustomFail (RegistrationAggregateExUnitsExceeded failure)

isPlainUtxo :: TxOut ConwayEra -> Bool
isPlainUtxo txOut =
    case (txOut ^. referenceScriptTxOutL, txOut ^. valueTxOutL) of
        (SNothing, MaryValue _ (MultiAsset assets)) -> Map.null assets
        _ -> False

assetValue :: Coin -> PolicyID -> AssetName -> Integer -> MaryValue
assetValue coin policy assetName quantity =
    MaryValue
        coin
        (MultiAsset $ Map.singleton policy (Map.singleton assetName quantity))

rawPlanData :: String -> Value -> Either RegistrationError RawData
rawPlanData label =
    first (RegistrationPlanRejected . ((label <> ": ") <>))
        . fmap RawData
        . plutusDataFromJson

planScriptHash :: String -> Text -> Either RegistrationError ScriptHash
planScriptHash label encoded = do
    bytes <- first RegistrationPlanRejected (decodeHex28 label encoded)
    maybe
        (Left $ RegistrationPlanRejected $ label <> " is not a ledger hash")
        (Right . ScriptHash)
        (hashFromBytes bytes)

planAssetName :: String -> Text -> Either RegistrationError AssetName
planAssetName label encoded = do
    bytes <- planHex label encoded
    if BS.length bytes <= 32
        then Right (AssetName $ SBS.toShort bytes)
        else Left (RegistrationPlanRejected $ label <> " exceeds 32 bytes")

planHex :: String -> Text -> Either RegistrationError ByteString
planHex label encoded =
    first
        (const $ RegistrationPlanRejected $ label <> " is not hexadecimal")
        (convertFromBase Base16 $ TE.encodeUtf8 encoded)

planTxIn :: Text -> Either RegistrationError TxIn
planTxIn rendered =
    case T.splitOn "#" rendered of
        [encodedId, renderedIx] -> do
            rawId <- planHex "reference transaction id" encodedId
            unless (BS.length rawId == 32) $
                Left
                    ( RegistrationPlanRejected
                        "reference transaction id is not 32 bytes"
                    )
            digest <-
                maybe
                    ( Left $
                        RegistrationPlanRejected
                            "reference transaction id is not a ledger hash"
                    )
                    Right
                    (hashFromBytes rawId)
            txIx <-
                maybe
                    ( Left $
                        RegistrationPlanRejected
                            "reference transaction index is invalid"
                    )
                    Right
                    (readMaybe $ T.unpack renderedIx)
            pure (TxIn (TxId $ unsafeMakeSafeHash digest) (TxIx txIx))
        _ -> Left (RegistrationPlanRejected "reference must have txid#index form")

planAddress :: Text -> Either RegistrationError Addr
planAddress encoded = do
    (hrp, dataPart) <-
        first
            (RegistrationPlanRejected . ("checkpoint address is not Bech32: " <>) . show)
            (Bech32.decodeLenient encoded)
    unless (Bech32.humanReadablePartToText hrp == "addr_test") $
        Left (RegistrationPlanRejected "checkpoint address must use addr_test")
    bytes <-
        maybe
            (Left $ RegistrationPlanRejected "checkpoint address data is invalid")
            Right
            (Bech32.dataPartToBytes dataPart)
    address <-
        maybe
            ( Left $
                RegistrationPlanRejected
                    "checkpoint address is not a Shelley address"
            )
            Right
            (decodeAddr bytes :: Maybe Addr)
    case address of
        Addr Testnet _ _ -> Right address
        Addr Mainnet _ _ ->
            Left (RegistrationPlanRejected "checkpoint address belongs to mainnet")
        AddrBootstrap{} ->
            Left (RegistrationPlanRejected "checkpoint address is a Byron address")

lifecycleScriptHash ::
    RegisterConfig ->
    RegistrationPlan ->
    Either RegistrationError ScriptHash
lifecycleScriptHash config plan = do
    let account = registerLifecycleRewardAccount config
    unless (renderRewardAccount account == planLifecycleRewardAddress plan) $
        Left
            ( RegistrationPlanRejected
                "lifecycle reward account disagrees with the plan"
            )
    case account of
        AccountAddress _ (AccountId (ScriptHashObj hash)) -> Right hash
        AccountAddress _ (AccountId KeyHashObj{}) ->
            Left
                ( RegistrationPlanRejected
                    "lifecycle reward account is not script-backed"
                )

renderRewardAccount :: AccountAddress -> Text
renderRewardAccount account@(AccountAddress network _) =
    Bech32.encodeLenient
        ( either
            (error . show)
            id
            ( Bech32.humanReadablePartFromText $
                case network of
                    Testnet -> "stake_test"
                    Mainnet -> "stake"
            )
        )
        (Bech32.dataPartFromBytes $ serialiseAccountAddress account)

resolveReference ::
    String ->
    ScriptHash ->
    Text ->
    [(TxIn, TxOut ConwayEra)] ->
    Either RegistrationError (TxIn, TxOut ConwayEra)
resolveReference label expected rendered rows = do
    txIn <- planTxIn rendered
    row@(_, txOut) <-
        maybe
            (Left $ RegistrationPlanRejected $ label <> " UTxO is unresolved")
            Right
            (find ((== txIn) . fst) rows)
    case txOut ^. referenceScriptTxOutL of
        SNothing ->
            Left $ RegistrationPlanRejected $ label <> " UTxO has no script"
        SJust script
            | hashScript script == expected -> Right row
            | otherwise ->
                Left $ RegistrationPlanRejected $ label <> " disagrees with the plan"

requireProofAsset ::
    PolicyID ->
    AssetName ->
    (TxIn, TxOut ConwayEra) ->
    Either RegistrationError ()
requireProofAsset policy assetName (_, txOut) =
    case txOut ^. valueTxOutL of
        MaryValue _ (MultiAsset assets)
            | assets
                == Map.singleton policy (Map.singleton assetName 1) ->
                Right ()
            | otherwise ->
                Left
                    ( RegistrationPlanRejected
                        "proof input does not carry exactly the planned proof token"
                    )

scriptNamed :: Text -> Manifest -> Either String ScriptEntry
scriptNamed name manifest =
    case filter ((== name) . scriptName) (manifestScripts manifest) of
        [script] -> Right script
        _ -> Left ("manifest script is not unique: " <> T.unpack name)

renderReference :: Reference -> Text
renderReference scriptReference =
    referenceTxId scriptReference
        <> "#"
        <> T.pack (show $ referenceIndex scriptReference)

hexText :: ByteString -> Text
hexText = TE.decodeUtf8 . convertToBase Base16

decodeHex28 :: String -> Text -> Either String ByteString
decodeHex28 label encoded = do
    bytes <-
        either
            (const $ Left $ label <> " is not hexadecimal")
            Right
            (convertFromBase Base16 $ TE.encodeUtf8 encoded)
    unless (BS.length bytes == 28) $
        Left (label <> " is not 28 bytes")
    pure bytes

decodeHexUnsafe :: Text -> ByteString
decodeHexUnsafe encoded =
    either
        (error . ("mkRegistrationPlan: impossible manifest hex: " <>))
        id
        (convertFromBase Base16 $ TE.encodeUtf8 encoded)

rewardAddress :: ByteString -> Either String Text
rewardAddress raw = do
    hash <-
        maybe
            (Left "observer-lifecycle script hash is not a ledger hash")
            (Right . ScriptHash)
            (hashFromBytes raw)
    hrp <-
        either
            (Left . show)
            Right
            (Bech32.humanReadablePartFromText "stake_test")
    pure $
        Bech32.encodeLenient
            hrp
            ( Bech32.dataPartFromBytes $
                serialiseAccountAddress $
                    AccountAddress
                        Testnet
                        (AccountId $ ScriptHashObj hash)
            )
