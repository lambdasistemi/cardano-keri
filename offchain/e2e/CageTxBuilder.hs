{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : CageTxBuilder
Description : Build hardened #99 cage Mint/Request/Modify txs for withDevnet

Adapts the read-only @CageTxBuilder@ precedent to the hardened #99 wire:
the parameterized @mpfCage(version, predecessorPolicy)@ validator, the
6-field @State@ with @identity_root@, and @Modify(List<RequestAction>)@
with per-request owner authorization.

The builder wallet-prep-splits the single genesis UTxO into disjoint
UTxOs, then mints a cage thread token, opens a value-write request, and
builds a @Modify@ whose owner authorization is a real
'Cardano.KERI.AID.Cage.Sign.signValueWrite' Ed25519 signature over the
request UTxO's output reference, so the on-chain @verifyOwnerAuth@ passes
and the Modify settles on the devnet.
-}
module CageTxBuilder (
    -- * Environment
    CageEnv (..),
    SignKey,
    ConwayTx,
    mkCageEnv,

    -- * Builders
    buildSplitTx,
    buildMintTx,
    buildRequestTx,
    buildRequestsTx,
    buildModifyTx,
    valueProofDepths,

    -- * Settlement helpers
    hasThreadToken,
    isRequestOutput,
    stateRootOf,
    threadTokenName,

    -- * Real Conway Phase-1 guard (pinned @Cardano.Tx.Validate@)
    Phase1Input (..),
    Phase1RewardState (..),
    Phase1Verdict (..),
    Phase1Sentinels (..),
    Pv11GuardParams (..),
    loadPv11GuardParams,
    pv11FixturePath,
    pv11FixtureDigest,
    runPhase1,
    phase1Accepted,
    phase1Structural,
    renderPhase1,
    newPhase1Sentinels,
    readPhase1Sentinels,
    countEvaluation,
    countSigning,
    countSubmission,

    -- * Offline guard candidates (RED only; never submitted)
    offlineUtxos,
    offlineOwnerAddr,
    offlineOwnerKeyHash,
    aggregateMem,
    aggregateSteps,
    overLimitRegisterTx,
    mutatedIntegrityTx,
    zeroFeeTx,
    withdrawalTx,
    overLimitWithdrawalTx,
    witnessOnlyTx,
    signedAdmissibleTx,
    genesisResolvedUtxos,
    seededObserverAccount,
    oversizedCageModifyTx,

    -- * Offline dependency-injected provider seam (RED only)
    offlineProvider,
    offlineProviderWith,
    OfflineSeams (..),
    defaultOfflineSeams,
    offlineCageEnv,
    offlineModifyFixtures,
    offlineWalletOf,
    offlinePhase1Snapshot,

    -- * Downstream-owned bounded synthetic coordinate (fixture only)
    SyntheticDevnetCoordinate (..),
    syntheticDevnetCoordinate,
    syntheticDevnetGlobalsFixture,
    syntheticSlotStartMs,
    syntheticFloorSlot,
    syntheticCeilSlot,
    syntheticHorizonSlot,
    syntheticCoordinateProvider,
    globalsFloorSlot,
    globalsCeilSlot,
) where

import Control.Exception (
    SomeException,
    displayException,
    throwIO,
    try,
 )
import Control.Monad (unless, when, (>=>))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Foldable (toList)
import Data.IORef (
    IORef,
    modifyIORef',
    newIORef,
    readIORef,
 )
import Data.List (isInfixOf, maximumBy, partition, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Data.Word (Word32, Word8)
import Lens.Micro ((&), (.~), (^.))
import Numeric.Natural (Natural)
import System.Environment (lookupEnv)

import Cardano.Crypto.Hash (
    Blake2b_224,
    Blake2b_256,
    Hash,
    hashFromBytes,
    hashToBytes,
    hashToStringAsHex,
    hashWith,
 )
import Cardano.Crypto.Hash.SHA256 (SHA256)
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    Withdrawals (..),
 )
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.PParams (
    ppCollateralPercentageL,
    ppCostModelsL,
    ppMaxBlockExUnitsL,
    ppMaxCollateralInputsL,
    ppMaxTxExUnitsL,
    ppMaxValSizeL,
    ppPricesL,
 )
import Cardano.Ledger.Alonzo.Scripts (
    AsIx (..),
    Prices (..),
    mkCostModel,
    mkCostModels,
 )
import Cardano.Ledger.Alonzo.TxBody (
    reqSignerHashesTxBodyL,
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Alonzo.TxWits (
    Redeemers (..),
    TxDats (..),
 )
import Cardano.Ledger.Api.PParams (CoinPerByte (..), ppCoinsPerUTxOByteL)
import Cardano.Ledger.Api.Scripts.Data qualified as LedgerData
import Cardano.Ledger.Api.Tx (mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    referenceInputsTxBodyL,
    vldtTxBodyL,
    withdrawalsTxBodyL,
 )
import Cardano.Ledger.Api.Tx.Out (
    TxOut,
    addrTxOutL,
    coinTxOutL,
    datumTxOutL,
    mkBasicTxOut,
    valueTxOutL,
 )
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL, scriptTxWitsL)
import Cardano.Ledger.BaseTypes (
    EpochNo (..),
    Globals (..),
    Inject (..),
    Network (..),
    NonNegativeInterval,
    ProtVer (..),
    StrictMaybe (SJust),
    TxIx (..),
    Version,
    boundRational,
    mkVersion,
 )
import Cardano.Ledger.Coin (Coin (..), compactCoinOrError)
import Cardano.Ledger.Conway (ApplyTxError (..), ConwayEra)
import Cardano.Ledger.Conway.PParams (ppMinFeeRefScriptCostPerByteL)
import Cardano.Ledger.Conway.Rules (ConwayLedgerPredFailure)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (
    PParams,
    Script,
    bodyTxL,
    emptyPParams,
    extractHash,
    ppKeyDepositL,
    ppMaxBBSizeL,
    ppMaxBHSizeL,
    ppMaxTxSizeL,
    ppPoolDepositL,
    ppProtocolVersionL,
    ppTxFeeFixedL,
    ppTxFeePerByteL,
 )
import Cardano.Ledger.Credential (Credential (..), StakeReference (..))
import Cardano.Ledger.Hashes (ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..), coerceKeyRole)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..), exUnitsMem, exUnitsSteps)
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.Shelley.Genesis (mkShelleyGlobals)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Slotting.EpochInfo.API (EpochInfo (..))
import Cardano.Slotting.Slot (EpochSize (..))
import Cardano.Slotting.Time (
    RelativeTime (..),
    SlotLength,
    SystemStart (..),
    getSlotLength,
    mkSlotLength,
 )

import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.N2C.Provider (
    mkN2CProvider,
    withAcquiredN2CProviderAndGlobals,
 )
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Cardano.Node.Client.Provider (
    EvaluateTxResult,
    LedgerSnapshot (..),
    Provider (..),
    SlotNo (..),
 )
import Cardano.Node.Client.Submitter (Submitter (..))
import Cardano.Node.Client.Validity (ValidityChoice (AutoLongest))
import Cardano.Tx.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
 )
import Cardano.Tx.Build (PParamsBound, mkPParamsBound, unPParamsBound)
import Ouroboros.Network.Block (genesisPoint)

import Cardano.Node.Client.E2E.Setup (
    Ed25519DSIGN,
    SignKeyDSIGN,
    addKeyWitness,
    deriveVerKeyDSIGN,
    genesisAddr,
    genesisSignKey,
    mkSignKey,
    rawSerialiseVerKeyDSIGN,
 )

import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinByteString (..))

import Cardano.Tx.Validate (
    isWitnessCompletenessFailure,
    validatePhase1WithGlobals,
    validatePhase1WithGlobalsAndRewardAccounts,
 )

import Cardano.KERI.AID.Cage.Sign (signValueWrite)
import Cardano.KERI.AID.Cage.Types (ProofStep)
import Cardano.KERI.AID.E2E.AssetName (computeAssetName)
import Cardano.KERI.AID.E2E.Datum (
    mkInlineDatum,
    rawInlineData,
    toLedgerData,
    toPlcData,
 )
import Cardano.KERI.AID.E2E.Mpf (
    blake2b256,
    emptyRoot,
    identityRoot,
 )
import Cardano.KERI.AID.E2E.MpfProof (prove)
import Cardano.KERI.AID.E2E.MpfTrie (Trie, build, rootOf)
import Cardano.KERI.AID.E2E.Script (
    applyParams,
    cagePolicyId,
    cageScriptAddr,
    computeScriptHash,
    extractCompiledCode,
    loadBlueprint,
    mkCageScript,
 )
import Cardano.KERI.AID.E2E.Wire

-- | Ed25519 signing key alias used across the e2e harness.
type SignKey = SignKeyDSIGN Ed25519DSIGN

-- ---------------------------------------------------------------------------
-- Fixed harness parameters
-- ---------------------------------------------------------------------------

-- | @mpfCage@ version parameter for the smoke.
cageVersion :: Integer
cageVersion = 0

{- | Pinned predecessor policy. Genesis cages have no predecessor and are
created via @Minting@; a 28-byte all-zero policy id is a well-formed pin
that the @Migrating@ path (unused here) would check against.
-}
predecessorPolicy :: ByteString
predecessorPolicy = BS.replicate 28 0

-- | The AID identifier registered in the identity trie.
cageOwnerAid :: ByteString
cageOwnerAid = "keri-aid-0001"

{- | Deterministic auth keypair whose public key is registered at
@cageOwnerAid@ in the identity trie. Separate from the genesis payment key.
The seed is padded/truncated to exactly the 32 bytes Ed25519 requires.
-}
authSignKey :: SignKey
authSignKey =
    mkSignKey (BS.take 32 ("keri-aid-owner-auth-key-seed" <> BS.replicate 32 0x2a))

authOwnerKey :: ByteString
authOwnerKey = rawSerialiseVerKeyDSIGN (deriveVerKeyDSIGN authSignKey)

{- | Snapshot of the single-leaf identity registry root (owner_aid ->
blake2b_256(owner_key)); its inclusion proof is the empty proof.
-}
cageIdentityRoot :: ByteString
cageIdentityRoot = identityRoot cageOwnerAid authOwnerKey

{- | The mutated value-trie key: the owner cell is exactly
@blake2b_256(owner_aid)@ (32 bytes) per FR6.
-}
cageRequestKey :: ByteString
cageRequestKey = blake2b256 cageOwnerAid

-- | The value inserted by the smoke's Modify.
cageValue :: ByteString
cageValue = "keri-value-0001"

cageTip :: Integer
cageTip = 0

{- | Generous processing window (10 min) so the Modify's short current
validity window is comfortably within submitted_at + process_time.
-}
cageProcessTime :: Integer
cageProcessTime = 600_000

cageRetractTime :: Integer
cageRetractTime = 600_000

{- | Fixed declared execution units. Client-side @evaluateTx@ measurement
(which runs scripts unbounded) hangs on this devnet, so we declare
generous fixed budgets and let the NODE validate Phase-2 (budget-capped).
These stay well under the mainnet per-tx max (14,000,000 / 10,000,000,000)
so the aggregate passes Phase-1, and small enough that the Modify's fixed
fee covers the execution cost.
-}
mintExUnits :: ExUnits
mintExUnits = ExUnits 5_000_000 2_000_000_000

{- | Modify redeemer budget — covers @verifyOwnerAuth@ (the identity MPF
no-op update + the Ed25519 signature check) and the value-trie MPF insert.
-}
modifyExUnits :: ExUnits
modifyExUnits = ExUnits 8_000_000 4_000_000_000

-- | Contribute (request-validation) redeemer budget — cheap phase/token check.
contributeExUnits :: ExUnits
contributeExUnits = ExUnits 3_000_000 1_500_000_000

-- | State-output / request-output lovelace.
minAda :: Integer
minAda = 2_000_000

requestAda :: Integer
requestAda = 5_000_000

{- | Base fee overestimate for the manually balanced Modify (the ledger
accepts an overpaid fee; validModify's refund invariant uses the exact fee
value the tx carries). Generous enough for the Modify script execution plus
the base tx on the devnet; the per-request component is added on top.
-}
modifyFee :: Integer
modifyFee = 2_000_000

{- | Per-request fee increment. A larger batch carries more redeemers, proof
data, and inputs/outputs, so the min fee grows with @n@ (the declared
ex-unit cost of each extra Contribute redeemer dominates). This keeps the
fixed-fee overestimate above the ledger min fee across the batch sweep, so a
rejection reflects the ex-unit / size limits rather than a too-small fee.
-}
modifyFeePerReq :: Integer
modifyFeePerReq = 700_000

-- ---------------------------------------------------------------------------
-- Batch (S9b) parameters
-- ---------------------------------------------------------------------------

{- | The i-th value-write key for a batch: a NAMESPACED child of the owner
cell — @blake2b_256(owner_aid) ++ be2(i)@ (length 34). Its first 32 bytes
equal @blake2b_256(owner_aid)@ so FR6 accepts it; distinct @i@ give
distinct keys (and distinct @blake2b_256(key)@ trie paths).
-}
namespacedKey :: Int -> ByteString
namespacedKey i =
    cageRequestKey <> BS.pack [fromIntegral (i `div` 256), fromIntegral (i `mod` 256)]

-- | The i-th value inserted by a batch @Modify@.
namespacedValue :: Int -> ByteString
namespacedValue i =
    "keri-value-" <> BS.pack [fromIntegral (i `div` 256), fromIntegral (i `mod` 256)]

{- | Extract @(requestKey, insertValue)@ from a spent request UTxO's inline
@RequestDatum@ (@Insert@ operations only), matching the Aiken wire:
@Constr 0 [Constr 0 [_token, _owner, B key, Constr 0 [B value], _tip, _at]]@.
-}
parseRequestKV :: PLC.Data -> Maybe (ByteString, ByteString)
parseRequestKV d = case d of
    PLC.Constr 0 [PLC.Constr 0 [_tok, _own, PLC.B key, PLC.Constr 0 [PLC.B value], _tip, _at]] ->
        Just (key, value)
    _ -> Nothing

-- | Extract the request submission time used by the phase-1 deadline.
parseRequestSubmittedAt :: PLC.Data -> Maybe Integer
parseRequestSubmittedAt d = case d of
    PLC.Constr 0 [PLC.Constr 0 [_tok, _own, _key, _value, _tip, PLC.I submittedAt]] ->
        Just submittedAt
    _ -> Nothing

{- | Value-trie inclusion-proof generator per insert: the real non-zero-depth
MPF proof for @key@ in @trie@ (@Cardano.KERI.AID.E2E.MpfProof.prove@,
producing Branch/Fork/Leaf steps). For the i-th insert the proof is
generated against @T_i@ (the trie with the first @i@ keys), so the on-chain
@mpf.insert@ recomputes @excluding(k_i, proof) == T_{i-1}.root@ then
@including(k_i, v_i, proof) == T_i.root@ and the batch @Modify@ settles. For
a single-leaf trie this is the empty proof (the S9a zero-depth case).
-}
valueProofGen :: Trie -> ByteString -> [ProofStep]
valueProofGen = prove

{- | The ACTUAL proof-depth profile of an @n@-request batch inserted into an
EMPTY value trie: the number of proof steps carried by the i-th insert
(i = 1..n), each generated against the trie holding the first @i@ namespaced
keys — the exact proofs 'buildModifyTx' places in the @Modify@ (the request
UTxOs are spent in namespaced-index order). The 1st insert is @0@ (an empty
proof into the empty trie, the S9a zero-depth case); the 2nd+ inserts are
@> 0@ (genuine non-zero-depth Branch/Fork/Leaf proofs).
-}
valueProofDepths :: Int -> [Int]
valueProofDepths n =
    [ length (valueProofGen (build (take i kvs)) (fst (kvs !! (i - 1))))
    | i <- [1 .. n]
    ]
  where
    kvs = [(namespacedKey j, namespacedValue j) | j <- [0 .. n - 1]]

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

data CageEnv = CageEnv
    { envScript :: Script ConwayEra
    , envScriptHash :: ScriptHash
    , envPolicyId :: PolicyID
    , envScriptAddr :: Addr
    , envProvider :: Provider IO
    , envSubmitter :: Submitter IO
    , envGuard :: Pv11GuardParams
    , envWithPhase1Snapshot ::
        forall a. (Globals -> Provider IO -> IO a) -> IO a
    {- ^ The ONE acquisition/ownership boundary (A-065). Everything the
    candidate's provenance depends on — resolve, balance, build, evaluate
    and the ledger-native Phase-1 guard — happens inside this callback
    against the SAME provider and the SAME 'Globals'. Neither value is
    cached, returned, or reconstructed; submission and settlement polling
    stay outside it so a long wait never holds the acquisition.
    -}
    }

{- | Load the blueprint, apply BOTH validator params, derive the policy id
and script address from the exact applied bytes, and record the script
hash (printed as artifact evidence).
-}
mkCageEnv :: FilePath -> LSQChannel -> LTxSChannel -> IO CageEnv
mkCageEnv bpPath lsq ltxs = do
    guardParams <- loadPv11GuardParams
    bp <- loadBlueprint bpPath >>= either fail pure
    let cageCode =
            fromMaybe
                (error "cage compiled code not found in blueprint")
                (extractCompiledCode "cage." bp)
        applied = applyParams cageVersion predecessorPolicy cageCode
        scr = mkCageScript applied
        sHash = computeScriptHash applied
        policyId = cagePolicyId applied
        scriptAddr = cageScriptAddr applied Testnet
    putStrLn $ "cage script hash: " <> show sHash
    pure
        CageEnv
            { envScript = scr
            , envScriptHash = sHash
            , envPolicyId = policyId
            , envScriptAddr = scriptAddr
            , envProvider = mkN2CProvider lsq
            , envSubmitter = mkN2CSubmitter ltxs
            , envGuard = guardParams
            , envWithPhase1Snapshot = withAcquiredN2CProviderAndGlobals lsq
            }

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

{- | "Now" in POSIX milliseconds, read from the ACQUIRED LEDGER COORDINATE
rather than from the client's wall clock (A-069 69A points 3 and 5).

It is the POSIX start of the snapshot provider's own tip slot, translated
through the callback 'Globals'. On a live node that is chain time — which is
what the Modify's validity window actually needs — and it is the same
coordinate the guard and the script context use, so the builder's business
deadlines and the ledger's validity interval can no longer disagree. The old
'getPOSIXTime' reading was a second, unrelated time source.
-}
snapshotNowPosixMs :: Globals -> Provider IO -> IO Integer
snapshotNowPosixMs globals provider = do
    snapshot <- queryLedgerSnapshot provider
    slotStartPosixMsOf globals (ledgerTipSlot snapshot)

{- | POSIX milliseconds at a slot's start, from an acquired 'Globals'. A slot
outside the coordinate's horizon fails loudly; nothing is extrapolated.
-}
slotStartPosixMsOf :: Globals -> SlotNo -> IO Integer
slotStartPosixMsOf globals slot =
    case epochInfoSlotToRelativeTime_ (epochInfo globals) slot of
        Right (RelativeTime seconds) ->
            pure (systemStartMs + round (seconds * 1000))
        Left err ->
            fail
                ( "slotStartPosixMsOf: the acquired coordinate refused slot "
                    <> show (unSlotNo slot)
                    <> ": "
                    <> T.unpack err
                )
  where
    systemStartMs =
        round
            ( 1000
                * utcTimeToPOSIXSeconds
                    (getSystemStart (systemStart globals))
            )

ownerKeyHashBytes :: Addr -> ByteString
ownerKeyHashBytes addr = case addr of
    Addr _ (KeyHashObj (KeyHash h)) _ -> hashToBytes h
    _ -> error "ownerKeyHashBytes: not a key-hash address"

txInToRef :: TxIn -> OutRef
txInToRef (TxIn (TxId h) (TxIx ix)) =
    OutRef
        { refTxId = hashToBytes (extractHash h)
        , refIdx = fromIntegral ix
        }

spendingIndex :: TxIn -> Set.Set TxIn -> Word32
spendingIndex needle ins = go 0 (Set.toAscList ins)
  where
    go _ [] = error "spendingIndex: TxIn not in set"
    go n (x : xs)
        | x == needle = n
        | otherwise = go (n + 1) xs

-- | True when the output carries a token under the cage policy.
hasThreadToken :: CageEnv -> TxOut ConwayEra -> Bool
hasThreadToken env o =
    case o ^. valueTxOutL of
        MaryValue _ (MultiAsset ma) ->
            maybe False (not . Map.null) (Map.lookup (envPolicyId env) ma)

-- | The asset name of the cage token held by an output, if any.
threadTokenName :: CageEnv -> TxOut ConwayEra -> Maybe ByteString
threadTokenName env o =
    case o ^. valueTxOutL of
        MaryValue _ (MultiAsset ma) -> do
            assets <- Map.lookup (envPolicyId env) ma
            case Map.keys assets of
                (AssetName an : _) -> Just (SBS.fromShort an)
                _ -> Nothing

{- | True when the output sits at the cage script address and carries no
cage token (the request output; a request tx's change goes to the
genesis address).
-}
isRequestOutput :: CageEnv -> TxOut ConwayEra -> Bool
isRequestOutput env o =
    atScript && not (hasThreadToken env o)
  where
    atScript = o ^. addrTxOutL == envScriptAddr env

{- | The value-trie root recorded in an output's StateDatum, if it is one.
Structurally: @Constr 1 [Constr 0 [_owner, B root, ...]]@.
-}
stateRootOf :: CageEnv -> TxOut ConwayEra -> Maybe ByteString
stateRootOf _ o = case rawInlineData o of
    Just (PLC.Constr 1 [PLC.Constr 0 (_ : PLC.B root : _)]) -> Just root
    _ -> Nothing

-- ---------------------------------------------------------------------------
-- Setup: split the single genesis UTxO into several
-- ---------------------------------------------------------------------------

{- | The genesis wallet starts with ONE UTxO, but the script txs need a seed
input, a fee/balance input and a DISJOINT collateral UTxO. This setup tx
fans the genesis UTxO out into several ada-only wallet UTxOs (plus change),
so later builders can pick disjoint inputs/collateral.
-}
buildSplitTx :: CageEnv -> Addr -> IO ConwayTx
buildSplitTx env ownerAddr = envWithPhase1Snapshot env $ \globals provider -> do
    pp <- queryProtocolParams provider
    walletUtxos <- queryUTxOs provider ownerAddr
    let feeUtxo = case walletUtxos of
            (u : _) -> u
            [] -> error "buildSplitTx: no wallet UTxO"
        splitOut = mkBasicTxOut ownerAddr (inject (Coin 10_000_000))
        -- Three dedicated 10-ada UTxOs + balanceTx change = >=4 wallet UTxOs.
        body =
            mkBasicTxBody
                & outputsTxBodyL .~ StrictSeq.fromList [splitOut, splitOut, splitOut]
        tx = mkBasicTx body
    balanced <-
        case balanceTx pp [feeUtxo] [] ownerAddr tx of
            Left err -> error ("buildSplitTx: balance failed: " <> show err)
            Right r -> pure (balancedTx r)
    guardCandidateIn globals provider env "buildSplitTx" balanced
    pure balanced

-- ---------------------------------------------------------------------------
-- Mint
-- ---------------------------------------------------------------------------

{- | Build a mint transaction that creates a fresh cage state UTxO holding
the thread token, with the identity registry snapshot in its datum.
-}
buildMintTx ::
    CageEnv ->
    KeyHash Payment ->
    Addr ->
    (TxIn, TxOut ConwayEra) ->
    IO ConwayTx
buildMintTx env _ownerKh ownerAddr seedUtxo =
    envWithPhase1Snapshot env $ \globals provider -> do
        pp <- queryProtocolParams provider
        walletUtxos <- queryUTxOs provider ownerAddr
        let (seedIn, _) = seedUtxo
            -- Collateral must be a wallet UTxO DISJOINT from the regular inputs
            -- (the seed funds balance/fee): reusing an input as collateral is a
            -- Phase-1 structure error. The seed alone covers the outputs + fee.
            collateralUtxo = case filter (\(tin, _) -> tin /= seedIn) walletUtxos of
                (u : _) -> u
                [] -> error "buildMintTx: no disjoint collateral UTxO"
            collateralIn = fst collateralUtxo
            assetNameBs = computeAssetName seedIn
            anLedger = AssetName (SBS.toShort assetNameBs)
            policyId = envPolicyId env
            stateDat =
                StateDatum
                    AIDOnChainTokenState
                        { aidStateOwner = toBBS (ownerKeyHashBytes ownerAddr)
                        , aidStateRoot = emptyRoot
                        , aidIdentityRoot = cageIdentityRoot
                        , aidStateTip = cageTip
                        , aidStateProcessTime = cageProcessTime
                        , aidStateRetractTime = cageRetractTime
                        }
            mintMA =
                MultiAsset $ Map.singleton policyId (Map.singleton anLedger 1)
            stateOut =
                mkBasicTxOut
                    (envScriptAddr env)
                    (MaryValue (Coin minAda) mintMA)
                    & datumTxOutL .~ mkInlineDatum (toPlcData stateDat)
            mintRedeemer = Minting (Mint (txInToRef seedIn))
            redeemers =
                Redeemers $
                    Map.singleton
                        (ConwayMinting (AsIx 0))
                        (toLedgerData mintRedeemer, mintExUnits)
            integrity =
                computeScriptIntegrity
                    (Set.singleton PlutusV3)
                    pp
                    redeemers
                    (TxDats mempty)
            body =
                mkBasicTxBody
                    & inputsTxBodyL .~ Set.singleton seedIn
                    & outputsTxBodyL .~ StrictSeq.singleton stateOut
                    & mintTxBodyL .~ mintMA
                    & collateralInputsTxBodyL .~ Set.singleton collateralIn
                    & scriptIntegrityHashTxBodyL .~ integrity
            tx =
                mkBasicTx body
                    & witsTxL . scriptTxWitsL
                        .~ Map.singleton (envScriptHash env) (envScript env)
                    & witsTxL . rdmrsTxWitsL .~ redeemers
        -- No client-side evaluateTx (its unbounded script measurement hangs on
        -- this devnet); declare fixed exunits and let the node validate on
        -- submit. balanceTxWith sets the fee from the seed and resolves the
        -- DISJOINT collateral UTxO's value for total_collateral/collateral_return
        -- (it is NOT added to the regular inputs).
        case balanceTxWith
            pp
            [seedUtxo]
            (CollateralUtxos [collateralUtxo])
            []
            ownerAddr
            Nothing
            tx of
            Left err -> error ("buildMintTx: balance failed: " <> show err)
            Right r -> do
                let balanced = balancedTx r
                guardCandidateIn globals provider env "buildMintTx" balanced
                pure balanced

-- ---------------------------------------------------------------------------
-- Request (plain payment to the script address; no script execution)
-- ---------------------------------------------------------------------------

{- | Open a value-write request at the cage script for the given thread
token: an ada output carrying a @RequestDatum@ with @Insert@ of the
smoke value, keyed by @blake2b_256(owner_aid)@.
-}
buildRequestTx ::
    CageEnv ->
    KeyHash Payment ->
    Addr ->
    ByteString ->
    IO ConwayTx
buildRequestTx env _ownerKh ownerAddr tokenNameBs =
    envWithPhase1Snapshot env $ \globals provider -> do
        pp <- queryProtocolParams provider
        walletUtxos <- queryUTxOs provider ownerAddr
        -- Real submission timestamp (current POSIX ms); the Modify's phase-1
        -- window is derived to sit before submittedAt + process_time (NOTE-008).
        submittedAt <- snapshotNowPosixMs globals provider
        let feeUtxo = case walletUtxos of
                (u : _) -> u
                [] -> error "buildRequestTx: no wallet UTxO"
            reqDat =
                RequestDatum
                    Request
                        { requestToken = TokenId tokenNameBs
                        , requestOwner = ownerKeyHashBytes ownerAddr
                        , requestKey = cageRequestKey
                        , requestValue = Insert cageValue
                        , requestTip = cageTip
                        , requestSubmittedAt = submittedAt
                        }
            reqOut =
                mkBasicTxOut
                    (envScriptAddr env)
                    (inject (Coin requestAda))
                    & datumTxOutL .~ mkInlineDatum (toPlcData reqDat)
            body = mkBasicTxBody & outputsTxBodyL .~ StrictSeq.singleton reqOut
            tx = mkBasicTx body
        -- No scripts run when CREATING a request output, so a plain balance
        -- (fee + change) suffices — no evaluateTx needed.
        balanced <-
            case balanceTx pp [feeUtxo] [] ownerAddr tx of
                Left err -> error ("buildRequestTx: balance failed: " <> show err)
                Right r -> pure (balancedTx r)
        guardCandidateIn globals provider env "buildRequestTx" balanced
        pure balanced

{- | Open a BATCH of @count@ distinct value-write requests in one tx (S9b):
each output carries a @RequestDatum@ with a distinct namespaced key
('namespacedKey') and value ('namespacedValue') under the same owner cell,
so a subsequent @Modify@ inserts them all into the value trie and the
2nd+ inserts require non-zero-depth proofs.
-}
buildRequestsTx ::
    CageEnv ->
    KeyHash Payment ->
    Addr ->
    ByteString ->
    Int ->
    IO ConwayTx
buildRequestsTx env _ownerKh ownerAddr tokenNameBs count =
    envWithPhase1Snapshot env $ \globals provider -> do
        pp <- queryProtocolParams provider
        walletUtxos <- queryUTxOs provider ownerAddr
        submittedAt <- snapshotNowPosixMs globals provider
        let feeUtxo = case walletUtxos of
                [] -> error "buildRequestsTx: no wallet UTxO"
                us -> maximumBy (comparing (unCoin . (^. coinTxOutL) . snd)) us
            mkReqOut i =
                mkBasicTxOut (envScriptAddr env) (inject (Coin requestAda))
                    & datumTxOutL
                        .~ mkInlineDatum
                            ( toPlcData
                                ( RequestDatum
                                    Request
                                        { requestToken = TokenId tokenNameBs
                                        , requestOwner = ownerKeyHashBytes ownerAddr
                                        , requestKey = namespacedKey i
                                        , requestValue = Insert (namespacedValue i)
                                        , requestTip = cageTip
                                        , requestSubmittedAt = submittedAt
                                        }
                                )
                            )
            body =
                mkBasicTxBody
                    & outputsTxBodyL .~ StrictSeq.fromList [mkReqOut i | i <- [0 .. count - 1]]
            tx = mkBasicTx body
        balanced <-
            case balanceTx pp [feeUtxo] [] ownerAddr tx of
                Left err -> error ("buildRequestsTx: balance failed: " <> show err)
                Right r -> pure (balancedTx r)
        guardCandidateIn globals provider env "buildRequestsTx" balanced
        pure balanced

-- ---------------------------------------------------------------------------
-- Modify
-- ---------------------------------------------------------------------------

{- | Build a hardened Modify transaction that spends the state UTxO
(@Modify@) and the request UTxO (@Contribute@), inserts the request's
value into the trie, refunds the requester, and continues the state
carrying the advanced root.

The Modify carries a real owner-authorization Ed25519 signature over the
request UTxO's output reference, so @verifyOwnerAuth@ passes and the tx
settles. Returns the built tx, the expected continuing-state root, and the
declared per-redeemer execution units.
-}
buildModifyTx ::
    CageEnv ->
    KeyHash Payment ->
    Addr ->
    (TxIn, TxOut ConwayEra) ->
    [(TxIn, TxOut ConwayEra)] ->
    IO (ConwayTx, ByteString, [(String, ExUnits)])
buildModifyTx env ownerKh ownerAddr stateUtxo reqUtxos =
    envWithPhase1Snapshot env $ \globals provider -> do
        pp <- queryProtocolParams provider
        walletUtxos <- queryUTxOs provider ownerAddr
        snapshot <- queryLedgerSnapshot provider
        let sortedReqs = sortOn fst reqUtxos
            reqIns = map fst sortedReqs
        submittedAts <-
            traverse
                ( maybe
                    (fail "buildModifyTx: unparseable request submission time")
                    pure
                    . (rawInlineData . snd >=> parseRequestSubmittedAt)
                )
                sortedReqs
        when (null submittedAts) $
            fail "buildModifyTx: no request validity deadline"
        -- Real chain-time validity derived from the node clock via the pinned
        -- Provider (NOTE-008): a CURRENT interval [lower, upper] that contains
        -- now and whose upper bound is capped by both the provider horizon and
        -- submitted_at + process_time, so cage.in_phase1 holds.
        now <- snapshotNowPosixMs globals provider
        let currentSlot = ledgerTipSlot snapshot
            businessDeadline = minimum submittedAts + cageProcessTime
        unless (now < businessDeadline) $
            fail "buildModifyTx: request processing deadline has elapsed"
        lowerCandidate <- posixMsCeilSlot provider (now - 10_000)
        horizon <-
            queryUpperBoundSlot provider AutoLongest
                >>= either
                    (fail . ("buildModifyTx: no translatable upper horizon: " <>) . show)
                    pure
        businessUpperResult <-
            try (posixMsToSlot provider (businessDeadline - 1)) ::
                IO (Either SomeException SlotNo)
        businessUpper <- case businessUpperResult of
            Right slot -> pure slot
            Left err
                | "PastHorizon" `isInfixOf` displayException err ->
                    pure horizon
                | otherwise -> throwIO err
        let lowerSlot = min lowerCandidate currentSlot
            upperSlot = min businessUpper horizon
        unless (lowerSlot <= currentSlot && currentSlot < upperSlot) $
            fail $
                "buildModifyTx: no current interval before request deadline/horizon: "
                    <> show (lowerSlot, currentSlot, upperSlot)
        let (stateIn, stateOut) = stateUtxo
            -- (requestKey, insertValue) for each request, in fold order.
            kvs =
                [ fromMaybe (error "buildModifyTx: unparseable request datum") $
                    rawInlineData o >>= parseRequestKV
                | (_, o) <- sortedReqs
                ]
            -- Incremental value tries: T_i = build (first i inserts). The i-th
            -- insert's proof is generated against T_i (empty in RED, real
            -- non-zero-depth in GREEN via valueProofGen). The continuing-state
            -- root is the root of the full trie.
            tries = [build (take i kvs) | i <- [1 .. length kvs]]
            finalRoot = case reverse tries of
                (t : _) -> rootOf t
                [] -> emptyRoot
            valueProofs = zipWith (\t (k, _) -> valueProofGen t k) tries kvs
            -- Fee input and collateral: the TWO LARGEST disjoint wallet UTxOs (both
            -- disjoint from the script inputs; reusing one is a Phase-1 structure
            -- error). Largest-first so both cover the batch-scaled fee and the
            -- collateral floor (150% of the fee) as the batch size grows.
            walletAvail =
                sortOn (negate . unCoin . (^. coinTxOutL) . snd) $
                    filter (\(t, _) -> t /= stateIn && t `notElem` reqIns) walletUtxos
            (feeUtxo, collateralUtxo) = case walletAvail of
                (f : c : _) -> (f, c)
                _ ->
                    error
                        "buildModifyTx: need >=2 wallet UTxOs (fee + disjoint collateral)"
            (feeIn, feeOut) = feeUtxo
            collateralIn = fst collateralUtxo
            Coin feeUtxoLovelace = feeOut ^. coinTxOutL
            tokenNameBs =
                fromMaybe (error "buildModifyTx: state has no token") $
                    threadTokenName env stateOut
            anLedger = AssetName (SBS.toShort tokenNameBs)
            policyId = envPolicyId env
            n = length sortedReqs
            -- Fee scales with the batch size (more redeemers/proof data/inputs);
            -- kept above the ledger min fee so a rejection reflects ex-unit/size
            -- limits, not a too-small fee.
            modFee = modifyFee + fromIntegral n * modifyFeePerReq
            totalReqLovelace = sum [unCoin (o ^. coinTxOutL) | (_, o) <- sortedReqs]
            -- Refund accounting: N outputs to the requester summing to
            -- totalReqLovelace - fee - N*tip (the on-chain sumRefunds invariant).
            totalRefund = totalReqLovelace - modFee - fromIntegral n * cageTip
            perRefund = if n > 0 then totalRefund `div` fromIntegral n else 0
            refundRemainder = if n > 0 then totalRefund `mod` fromIntegral n else 0
            refundOuts =
                [ mkBasicTxOut
                    ownerAddr
                    (inject (Coin (perRefund + if i == 0 then refundRemainder else 0)))
                | i <- [0 .. n - 1]
                ]
            -- Continuing state output (index 0): advanced root, token confined.
            newStateDat =
                StateDatum
                    AIDOnChainTokenState
                        { aidStateOwner = toBBS (ownerKeyHashBytes ownerAddr)
                        , aidStateRoot = finalRoot
                        , aidIdentityRoot = cageIdentityRoot
                        , aidStateTip = cageTip
                        , aidStateProcessTime = cageProcessTime
                        , aidStateRetractTime = cageRetractTime
                        }
            stateValue =
                MaryValue
                    (Coin minAda)
                    (MultiAsset (Map.singleton policyId (Map.singleton anLedger 1)))
            newStateOut =
                mkBasicTxOut (envScriptAddr env) stateValue
                    & datumTxOutL .~ mkInlineDatum (toPlcData newStateDat)
            -- Change output (last) absorbs the fee UTxO remainder; ignored by
            -- validModify's sumRefunds (which consumes exactly N refund outputs).
            changeLovelace =
                (minAda + totalReqLovelace + feeUtxoLovelace)
                    - minAda -- new state out
                    - totalRefund
                    - modFee
            changeOut = mkBasicTxOut ownerAddr (inject (Coin changeLovelace))
            allOuts = StrictSeq.fromList (newStateOut : refundOuts ++ [changeOut])
            -- Inputs: state + requests + fee/collateral.
            allScriptIns = Set.fromList (stateIn : reqIns)
            allIns = Set.insert feeIn allScriptIns
            -- Redeemers: Modify on the state input, Contribute on each request.
            stateRef = txInToRef stateIn
            -- Per-request UpdateAction: its value proof + an owner-authorization
            -- signature over THAT request UTxO's output reference (replay binding).
            mkAuth rIn =
                let rr = txInToRef rIn
                 in AIDOwnerAuth
                        { ownerAid = cageOwnerAid
                        , identityProof = [] -- single-leaf identity trie -> empty
                        , ownerKey = authOwnerKey
                        , ownerSig = signValueWrite authSignKey (refTxId rr) (refIdx rr)
                        }
            actions =
                [ AIDUpdateAction{valueProof = pf, auth = mkAuth rIn}
                | (rIn, pf) <- zip reqIns valueProofs
                ]
            modifyRedeemer = Modify actions
            stateIx = spendingIndex stateIn allIns
            contributeEntries =
                [ ( ConwaySpending (AsIx (spendingIndex rIn allIns))
                  , (toLedgerData (Contribute stateRef), contributeExUnits)
                  )
                | rIn <- reqIns
                ]
            redeemers =
                Redeemers $
                    Map.fromList $
                        ( ConwaySpending (AsIx stateIx)
                        , (toLedgerData modifyRedeemer, modifyExUnits)
                        )
                            : contributeEntries
            integrity =
                computeScriptIntegrity
                    (Set.singleton PlutusV3)
                    pp
                    redeemers
                    (TxDats mempty)
            witnessKh = coerceKeyRole ownerKh :: KeyHash Guard
            -- A real current window. in_phase1 constrains the upper bound before
            -- submitted_at + process_time, while the provider horizon keeps the
            -- interval translatable and the lower bound cannot lead the tip.
            vldt = ValidityInterval (SJust lowerSlot) (SJust upperSlot)
            body =
                mkBasicTxBody
                    & inputsTxBodyL .~ allIns
                    & outputsTxBodyL .~ allOuts
                    & feeTxBodyL .~ Coin modFee
                    & collateralInputsTxBodyL .~ Set.singleton collateralIn
                    & reqSignerHashesTxBodyL .~ Set.singleton witnessKh
                    & vldtTxBodyL .~ vldt
                    & scriptIntegrityHashTxBodyL .~ integrity
            tx =
                mkBasicTx body
                    & witsTxL . scriptTxWitsL
                        .~ Map.singleton (envScriptHash env) (envScript env)
                    & witsTxL . rdmrsTxWitsL .~ redeemers
        -- No client-side evaluateTx (its script measurement hangs on this
        -- devnet); the fixed declared exunits keep the aggregate under the
        -- protocol max (Phase-1 OK) and cover the full Modify execution
        -- (@verifyOwnerAuth@ + the value-trie MPF insert), so the node's
        -- budget-capped Phase-2 accepts the owner-authorized Modify and it
        -- settles. The declared budgets are reported as the exunits record.
        let declared =
                ("Modify", modifyExUnits)
                    : [("Contribute", contributeExUnits) | _ <- [1 .. n]]
        -- Real Conway Phase-1 guard on the exact candidate this seam returns,
        -- before any evaluation, signing, or submission continuation. Structural
        -- failures reject here with the ledger's own constructors rather than
        -- being rediscovered by a live submission.
        guardCandidateIn globals provider env "buildModifyTx" tx
        pure (tx, finalRoot, declared)

-- | Wrap raw bytes as the @BuiltinByteString@ the mirrored State datum uses.
toBBS :: ByteString -> BuiltinByteString
toBBS = BuiltinByteString

-- ---------------------------------------------------------------------------
-- Real Conway Phase-1 guard
-- ---------------------------------------------------------------------------

{- | Everything the pinned real Conway Phase-1 rule needs about one candidate.

Builder-specific code owns the resolved inputs and the call placement; this
record is the generic seam both the Cage and Checkpoint builders hand to
'runPhase1'.
-}
data Phase1Input = Phase1Input
    { p1Globals :: Globals
    {- ^ The REAL acquired ledger coordinate the candidate was built under,
    never a network-shaped synthesis. Live it comes from the node inside
    'envWithPhase1Snapshot'; offline it is the one bounded
    'syntheticDevnetGlobalsFixture'.
    -}
    , p1Slot :: SlotNo
    , p1Params :: Pv11GuardParams
    , p1ResolvedInputs :: [(TxIn, TxOut ConwayEra)]
    }

{- | Reward-account state supplied to the guard.

'NoRewardState' is the default and uses plain 'validatePhase1'. Bodies that
carry withdrawals use 'SeededRewardAccounts' with EXACTLY the body's own
withdrawal accounts at their known balances, and only after the registration
settlement proof has succeeded. Never seed an account the body does not
withdraw from, and never seed to mute a failure.
-}
data Phase1RewardState
    = NoRewardState
    | SeededRewardAccounts (Map.Map AccountAddress Coin)

{- | The guard's verdict, preserving the ledger's own ordered failures.

The witness partition is exactly what the pinned exported
'isWitnessCompletenessFailure' recognises; everything else is structural and
rejects.
-}
data Phase1Verdict
    = Phase1Accepted
    | Phase1Rejected
        { p1WitnessFailures :: [ConwayLedgerPredFailure ConwayEra]
        , p1StructuralFailures :: [ConwayLedgerPredFailure ConwayEra]
        }

{- | Run the pinned real Conway Phase-1 rule on the exact candidate.

No admissibility predicate is hand-rolled and no failure is translated into a
weaker form: the carried ordered failures are flattened and partitioned only by
the pinned exported witness-completeness recogniser.
-}
runPhase1 :: Phase1Input -> Phase1RewardState -> ConwayTx -> Phase1Verdict
runPhase1 input rewardState tx =
    case validated of
        Right () -> Phase1Accepted
        Left (ConwayApplyTxError failures) ->
            let carried = toList failures
                (witness, structural) =
                    partition isWitnessCompletenessFailure carried
             in Phase1Rejected
                    { p1WitnessFailures = witness
                    , p1StructuralFailures = structural
                    }
  where
    bound = pv11PParamsBound (p1Params input)
    validated = case rewardState of
        NoRewardState ->
            validatePhase1WithGlobals
                (p1Globals input)
                bound
                (p1ResolvedInputs input)
                (p1Slot input)
                tx
        SeededRewardAccounts accounts ->
            validatePhase1WithGlobalsAndRewardAccounts
                (p1Globals input)
                bound
                (p1ResolvedInputs input)
                accounts
                (p1Slot input)
                tx

{- | A candidate passes the guard when the real rule accepted it outright, or
when every carried failure is witness-completeness noise. Any remaining
structural failure rejects.
-}
phase1Accepted :: Phase1Verdict -> Bool
phase1Accepted = null . phase1Structural

-- | The structural partition; empty exactly when the candidate is admissible.
phase1Structural :: Phase1Verdict -> [ConwayLedgerPredFailure ConwayEra]
phase1Structural Phase1Accepted = []
phase1Structural Phase1Rejected{p1StructuralFailures} = p1StructuralFailures

-- | Render a verdict's exact ledger failures for diagnostics and evidence.
renderPhase1 :: Phase1Verdict -> String
renderPhase1 Phase1Accepted = "Phase1Accepted"
renderPhase1 Phase1Rejected{p1WitnessFailures, p1StructuralFailures} =
    "Phase1Rejected witness="
        <> show p1WitnessFailures
        <> " structural="
        <> show p1StructuralFailures

-- ---------------------------------------------------------------------------
-- Downstream sentinels (dependency-injected seam)
-- ---------------------------------------------------------------------------

{- | Counters proving what the guard did NOT reach.

A structural rejection must short-circuit before evaluation, signing, and
submission; these counters make "the guard stopped it" demonstrable rather than
assumed. They are pure local counters, never a provider evaluator.
-}
data Phase1Sentinels = Phase1Sentinels
    { sentinelEvaluations :: IORef Int
    , sentinelSignings :: IORef Int
    , sentinelSubmissions :: IORef Int
    }

newPhase1Sentinels :: IO Phase1Sentinels
newPhase1Sentinels =
    Phase1Sentinels <$> newIORef 0 <*> newIORef 0 <*> newIORef 0

-- | @(evaluations, signings, submissions)@ observed so far.
readPhase1Sentinels :: Phase1Sentinels -> IO (Int, Int, Int)
readPhase1Sentinels sentinels =
    (,,)
        <$> readIORef (sentinelEvaluations sentinels)
        <*> readIORef (sentinelSignings sentinels)
        <*> readIORef (sentinelSubmissions sentinels)

countEvaluation :: Phase1Sentinels -> IO ()
countEvaluation sentinels = modifyIORef' (sentinelEvaluations sentinels) (+ 1)

countSigning :: Phase1Sentinels -> IO ()
countSigning sentinels = modifyIORef' (sentinelSignings sentinels) (+ 1)

countSubmission :: Phase1Sentinels -> IO ()
countSubmission sentinels = modifyIORef' (sentinelSubmissions sentinels) (+ 1)

-- ---------------------------------------------------------------------------
-- PV11 guard parameters (A-048 ruling 48A)
-- ---------------------------------------------------------------------------

{- | The composed offline guard parameter set, with explicit provenance.

Per A-048 (48A) this value is composed from COMMITTED, PINNED sources only:

* the three real-mainnet PV11 values below come from the committed
  @cardano-node-clients@ fixture @e2e-test/fixtures/pparams-pv11-mainnet.json@
  ('pv11ProtocolMajor', 'pv11V3CostModelEntries', 'pv11MaxTxExUnits'); and
* every other Phase-1 field comes from the SAME pinned node-clients revision's
  devnet genesis under @E2E_GENESIS_DIR@.

Nothing is invented. Any assertion decided by a genesis-sourced field —
@MaxTxSizeUTxO@, @FeeTooSmallUTxO@, min-UTxO, collateral — rests on the pinned
DEVNET GENESIS value and must not be reported as mainnet-authoritative. Only
the three fields above are real mainnet PV11 parameters.
-}
data Pv11GuardParams = Pv11GuardParams
    { pv11FixtureFile :: FilePath
    , pv11FixtureSha256 :: String
    , pv11GenesisDir :: FilePath
    , pv11ProtocolMajor :: Integer
    , pv11V3CostModelEntries :: Int
    , pv11MaxTxExUnits :: ExUnits
    , pv11ProtocolMinor :: Integer
    , pv11ComposedParams :: PParams ConwayEra
    , pv11PParamsBound :: PParamsBound
    , pv11GenesisSourced :: [String]
    , pv11FixtureSourced :: [String]
    }

{- | Resolve the committed PV11 fixture as the genesis directory's sibling,
falling back to the pinned-source working directory. Both candidates are
checked and the resolved absolute path is evidence.
-}
pv11FixturePath :: IO FilePath
pv11FixturePath = do
    genesisDir <- pv11GenesisDirPath
    let sibling = takeDirectoryPath genesisDir <> "/fixtures/" <> fixtureName
        cwdFallback = "e2e-test/fixtures/" <> fixtureName
    siblingExists <- readableFile sibling
    if siblingExists
        then pure sibling
        else do
            fallbackExists <- readableFile cwdFallback
            if fallbackExists
                then pure cwdFallback
                else
                    fail $
                        "PV11 fixture not found at "
                            <> sibling
                            <> " nor at "
                            <> cwdFallback

fixtureName :: FilePath
fixtureName = "pparams-pv11-mainnet.json"

pv11GenesisDirPath :: IO FilePath
pv11GenesisDirPath =
    lookupEnv "E2E_GENESIS_DIR"
        >>= maybe (fail "E2E_GENESIS_DIR not set") pure

-- | SHA-256 of the resolved fixture bytes, as lowercase hex evidence.
pv11FixtureDigest :: FilePath -> IO String
pv11FixtureDigest path = do
    bytes <- BS.readFile path
    pure (hashToStringAsHex (hashWith id bytes :: Hash SHA256 ByteString))

readableFile :: FilePath -> IO Bool
readableFile path =
    try (BS.readFile path) >>= \case
        Right _ -> pure True
        Left (_ :: SomeException) -> pure False

-- | Strip the final path segment (no @filepath@ dependency in this component).
takeDirectoryPath :: FilePath -> FilePath
takeDirectoryPath path =
    case break (== '/') (reverse path) of
        (_, '/' : rest) -> reverse rest
        _ -> "."

{- | Load the composed guard parameters: pinned devnet genesis as the base,
the committed real-PV11 fixture overlaid for exactly protocol major, the
PlutusV3 cost model, and the maximum transaction execution units.
-}
loadPv11GuardParams :: IO Pv11GuardParams
loadPv11GuardParams = do
    genesisDir <- pv11GenesisDirPath
    fixturePath <- pv11FixturePath
    digest <- pv11FixtureDigest fixturePath
    fixture <- decodeJsonFile fixturePath
    shelley <- decodeJsonFile (genesisDir <> "/shelley-genesis.json")
    alonzo <- decodeJsonFile (genesisDir <> "/alonzo-genesis.json")
    conway <- decodeJsonFile (genesisDir <> "/conway-genesis.json")

    -- FIXTURE-sourced: the three real mainnet PV11 values.
    protocolMajor <- jsonInteger fixture ["protocolVersion", "major"]
    exMem <- jsonInteger fixture ["maxTxExecutionUnits", "memory"]
    exSteps <- jsonInteger fixture ["maxTxExecutionUnits", "steps"]
    v3Entries <- jsonIntegerArray fixture ["costModels", "PlutusV3"]
    let maxTxExUnits =
            ExUnits (fromInteger exMem) (fromInteger exSteps)
    v3CostModel <-
        either
            (\err -> fail ("PV11 fixture PlutusV3 cost model rejected: " <> show err))
            pure
            (mkCostModel PlutusV3 (map fromInteger v3Entries))

    -- GENESIS-sourced: every remaining Phase-1 field.
    -- A-048 48A: the fixture wins for EXACTLY three values (major, the 350-entry
    -- V3 cost model, max tx exunits). Protocol MINOR is a genesis-sourced field.
    protocolMinor <- jsonInteger shelley ["protocolParams", "protocolVersion", "minor"]
    minFeeA <- jsonInteger shelley ["protocolParams", "minFeeA"]
    minFeeB <- jsonInteger shelley ["protocolParams", "minFeeB"]
    maxTxSize <- jsonInteger shelley ["protocolParams", "maxTxSize"]
    maxBBSize <- jsonInteger shelley ["protocolParams", "maxBlockBodySize"]
    maxBHSize <- jsonInteger shelley ["protocolParams", "maxBlockHeaderSize"]
    keyDeposit <- jsonInteger shelley ["protocolParams", "keyDeposit"]
    poolDeposit <- jsonInteger shelley ["protocolParams", "poolDeposit"]
    collateralPercent <- jsonInteger alonzo ["collateralPercentage"]
    maxCollateral <- jsonInteger alonzo ["maxCollateralInputs"]
    maxValue <- jsonInteger alonzo ["maxValueSize"]
    perUTxOWord <- jsonInteger alonzo ["lovelacePerUTxOWord"]
    priceMem <- jsonRational alonzo ["executionPrices", "priceMemory"]
    priceSteps <- jsonRational alonzo ["executionPrices", "priceSteps"]
    blockExMem <- jsonInteger alonzo ["maxBlockExUnits", "memory"]
    blockExSteps <- jsonInteger alonzo ["maxBlockExUnits", "steps"]
    refScriptCost <- jsonRational conway ["minFeeRefScriptCostPerByte"]

    prices <-
        Prices
            <$> requireBounded "executionPrices.priceMemory" priceMem
            <*> requireBounded "executionPrices.priceSteps" priceSteps
    refScriptCoeff <-
        requireBounded "minFeeRefScriptCostPerByte" refScriptCost

    let params =
            (emptyPParams :: PParams ConwayEra)
                -- FIXTURE (real mainnet PV11)
                & ppProtocolVersionL
                    .~ ProtVer (mkVersionOrDie protocolMajor) (fromInteger protocolMinor)
                & ppMaxTxExUnitsL .~ maxTxExUnits
                & ppCostModelsL
                    .~ mkCostModels (Map.singleton PlutusV3 v3CostModel)
                -- PINNED DEVNET GENESIS (everything else)
                & ppTxFeePerByteL .~ CoinPerByte (compactCoinOrError (Coin minFeeA))
                & ppTxFeeFixedL .~ Coin minFeeB
                & ppMaxTxSizeL .~ fromInteger maxTxSize
                & ppMaxBBSizeL .~ fromInteger maxBBSize
                & ppMaxBHSizeL .~ fromInteger maxBHSize
                & ppKeyDepositL .~ Coin keyDeposit
                & ppPoolDepositL .~ Coin poolDeposit
                & ppPricesL .~ prices
                & ppMaxBlockExUnitsL
                    .~ ExUnits (fromInteger blockExMem) (fromInteger blockExSteps)
                & ppMaxValSizeL .~ fromInteger maxValue
                & ppCollateralPercentageL .~ fromInteger collateralPercent
                & ppMaxCollateralInputsL .~ fromInteger maxCollateral
                -- Babbage replaced lovelacePerUTxOWord with a per-byte coin;
                -- the ledger's own upgrade rule is word/8, applied here to the
                -- pinned genesis value rather than choosing a new constant.
                & ppCoinsPerUTxOByteL .~ CoinPerByte (compactCoinOrError (Coin (perUTxOWord `div` 8)))
                & ppMinFeeRefScriptCostPerByteL .~ refScriptCoeff
    pure
        Pv11GuardParams
            { pv11FixtureFile = fixturePath
            , pv11FixtureSha256 = digest
            , pv11GenesisDir = genesisDir
            , pv11ProtocolMajor = protocolMajor
            , pv11V3CostModelEntries = length v3Entries
            , pv11MaxTxExUnits = maxTxExUnits
            , pv11ProtocolMinor = protocolMinor
            , pv11ComposedParams = params
            , pv11PParamsBound = mkPParamsBound params
            , pv11FixtureSourced =
                [ "ppProtocolVersion.major"
                , "ppMaxTxExUnits"
                , "ppCostModels[PlutusV3]"
                ]
            , pv11GenesisSourced =
                [ "ppProtocolVersion.minor"
                , "ppTxFeePerByte"
                , "ppTxFeeFixed"
                , "ppMaxTxSize"
                , "ppMaxBBSize"
                , "ppMaxBHSize"
                , "ppKeyDeposit"
                , "ppPoolDeposit"
                , "ppPrices"
                , "ppMaxBlockExUnits"
                , "ppMaxValSize"
                , "ppCollateralPercentage"
                , "ppMaxCollateralInputs"
                , "ppCoinsPerUTxOByte"
                , "ppMinFeeRefScriptCostPerByte"
                ]
            }

mkVersionOrDie :: Integer -> Version
mkVersionOrDie major =
    case mkVersion major of
        Just version -> version
        Nothing -> error ("PV11 fixture protocol major is invalid: " <> show major)

requireBounded :: String -> Rational -> IO NonNegativeInterval
requireBounded label value =
    maybe
        (fail (label <> ": not a valid non-negative interval: " <> show value))
        pure
        (boundRational value)

decodeJsonFile :: FilePath -> IO Aeson.Value
decodeJsonFile path =
    Aeson.eitherDecodeFileStrict path
        >>= either (\err -> fail (path <> ": " <> err)) pure

{- | Explicitly synthetic, test-only devnet coordinate owned by this
repository.

It is a FIXTURE. It is never handed to a live builder or guard, never
exported from the library, never reconstructed from a wall clock, and is
NOT real devnet or mainnet provenance. It is authoritative only for the
bounded slot interval it names.
-}
data SyntheticDevnetCoordinate = SyntheticDevnetCoordinate
    { syntheticSystemStart :: SystemStart
    , syntheticSlotLength :: SlotLength
    , syntheticEpochLength :: EpochSize
    , syntheticConwayStart :: EpochNo
    , syntheticHorizon :: SlotNo
    }

{- | The frozen synthetic values: deterministic non-POSIX-epoch-zero start
@2030-01-01T00:00:00Z@, 0.1-second slots, 100-slot epochs, Conway at epoch
zero, and an exercised horizon of slots @0..199@ with failure at @200@.
-}
syntheticDevnetCoordinate :: SyntheticDevnetCoordinate
syntheticDevnetCoordinate =
    SyntheticDevnetCoordinate
        { syntheticSystemStart =
            systemStartFromText "2030-01-01T00:00:00Z"
        , syntheticSlotLength = mkSlotLength 0.1
        , syntheticEpochLength = EpochSize 100
        , syntheticConwayStart = EpochNo 0
        , syntheticHorizon = SlotNo 199
        }

-- | The first slot past the bounded horizon: @200@.
syntheticHorizonSlot :: SlotNo
syntheticHorizonSlot =
    SlotNo (unSlotNo (syntheticHorizon syntheticDevnetCoordinate) + 1)

{- | Decode an ISO-8601 instant through Aeson, so the fixture obtains a typed
'SystemStart' from the same decoder the genesis file uses.
-}
systemStartFromText :: Text -> SystemStart
systemStartFromText text =
    case Aeson.eitherDecodeStrict (encodeUtf8 ("\"" <> text <> "\"")) of
        Right value -> SystemStart value
        Left err -> error ("systemStartFromText: " <> err)

{- | The one downstream-owned bounded synthetic 'Globals'.

It decodes the SAME pinned devnet @shelley-genesis.json@ that
'loadPv11GuardParams' already resolves through @E2E_GENESIS_DIR@, replaces
ONLY the @systemStart@ field with the deterministic synthetic start, and
applies the canonical ledger constructor 'mkShelleyGlobals'. Every other
scalar therefore comes from the pinned genesis, and the epoch coordinate
comes from 'syntheticDevnetCoordinate' rather than from constants at a call
site.
-}
syntheticDevnetGlobalsFixture :: IO Globals
syntheticDevnetGlobalsFixture = do
    genesisDir <- pv11GenesisDirPath
    raw <- BS.readFile (genesisDir <> "/shelley-genesis.json")
    let patched =
            encodeUtf8
                ( T.replace
                    "PLACEHOLDER"
                    "2030-01-01T00:00:00Z"
                    (decodeUtf8 raw)
                )
    case Aeson.eitherDecodeStrict patched of
        Right genesis ->
            pure
                ( mkShelleyGlobals
                    genesis
                    (syntheticEpochInfo syntheticDevnetCoordinate)
                )
        Left err ->
            fail ("syntheticDevnetGlobalsFixture: " <> err)

{- | Bounded 'EpochInfo' derived from the synthetic source record. A slot past
the named horizon fails; nothing is extrapolated and no safe zone is
extended.
-}
syntheticEpochInfo ::
    SyntheticDevnetCoordinate ->
    EpochInfo (Either Text)
syntheticEpochInfo coordinate =
    EpochInfo
        { epochInfoSize_ = \epoch ->
            withinEpoch epoch (syntheticEpochLength coordinate)
        , epochInfoFirst_ = \epoch ->
            withinEpoch epoch (SlotNo (unEpochNo epoch * epochLength))
        , epochInfoEpoch_ = \slot ->
            withinHorizon slot (EpochNo (unSlotNo slot `div` epochLength))
        , epochInfoSlotToRelativeTime_ = \slot ->
            withinHorizon
                slot
                (RelativeTime (fromIntegral (unSlotNo slot) * slotSeconds))
        , epochInfoSlotLength_ = \slot ->
            withinHorizon slot (syntheticSlotLength coordinate)
        }
  where
    epochLength = unEpochSize (syntheticEpochLength coordinate)
    slotSeconds = getSlotLength (syntheticSlotLength coordinate)
    horizon = unSlotNo (syntheticHorizon coordinate)
    withinHorizon :: forall a. SlotNo -> a -> Either Text a
    withinHorizon slot value
        | unSlotNo slot <= horizon = Right value
        | otherwise =
            Left
                ( "synthetic devnet fixture: slot "
                    <> T.pack (show (unSlotNo slot))
                    <> " is past the bounded horizon"
                )
    withinEpoch :: forall a. EpochNo -> a -> Either Text a
    withinEpoch epoch value
        | unEpochNo epoch * epochLength <= horizon = Right value
        | otherwise =
            Left
                ( "synthetic devnet fixture: epoch "
                    <> T.pack (show (unEpochNo epoch))
                    <> " is past the bounded horizon"
                )

-- | POSIX milliseconds of a slot's start, from the synthetic source record.
syntheticSlotStartMs :: SlotNo -> Integer
syntheticSlotStartMs slot =
    syntheticStartMs
        + toInteger (unSlotNo slot) * syntheticSlotMs

-- | POSIX milliseconds of the synthetic system start.
syntheticStartMs :: Integer
syntheticStartMs =
    round
        ( 1000
            * utcTimeToPOSIXSeconds
                (getSystemStart (syntheticSystemStart syntheticDevnetCoordinate))
        )

-- | The synthetic slot length in whole milliseconds.
syntheticSlotMs :: Integer
syntheticSlotMs =
    round (1000 * getSlotLength (syntheticSlotLength syntheticDevnetCoordinate))

{- | Floor POSIX milliseconds to a slot using only the synthetic source
record. Past the bounded horizon this is a named failure, never a clamp.
-}
syntheticFloorSlot :: Integer -> Either Text SlotNo
syntheticFloorSlot ms
    | candidate > unSlotNo (syntheticHorizon syntheticDevnetCoordinate) =
        Left
            ( "synthetic devnet fixture: slot "
                <> T.pack (show candidate)
                <> " is past the bounded horizon"
            )
    | otherwise = Right (SlotNo candidate)
  where
    candidate =
        fromInteger (max 0 ((ms - syntheticStartMs) `div` syntheticSlotMs))

-- | Ceiling POSIX milliseconds to a slot, same bounded contract.
syntheticCeilSlot :: Integer -> Either Text SlotNo
syntheticCeilSlot ms
    | (ms - syntheticStartMs) `mod` syntheticSlotMs == 0 =
        syntheticFloorSlot ms
    | otherwise =
        syntheticFloorSlot ms
            >>= \slot -> syntheticFloorSlot (syntheticSlotStartMs slot + syntheticSlotMs)

{- | A provider whose POSIX/slot translation is derived from the synthetic
source record's own arithmetic.

This is the "provider side" of the coordinate-identity proof. It is a
separate code path from the fixture 'Globals' 'EpochInfo' (which
'globalsFloorSlot' / 'globalsCeilSlot' interrogate), so agreement between the
two is real evidence rather than a tautology. Every operation outside the
bounded time contract fails loudly rather than fabricating ledger data.
-}
syntheticCoordinateProvider :: Provider IO
syntheticCoordinateProvider =
    Provider
        { withAcquired = \_ -> unusedSynthetic "withAcquired"
        , queryUTxOs = \_ -> unusedSynthetic "queryUTxOs"
        , queryUTxOByTxIn = \_ -> unusedSynthetic "queryUTxOByTxIn"
        , queryProtocolParams = unusedSynthetic "queryProtocolParams"
        , queryLedgerSnapshot = unusedSynthetic "queryLedgerSnapshot"
        , queryStakeRewards = \_ -> unusedSynthetic "queryStakeRewards"
        , queryRewardAccounts = \_ -> unusedSynthetic "queryRewardAccounts"
        , queryVoteDelegatees = \_ -> unusedSynthetic "queryVoteDelegatees"
        , queryTreasury = unusedSynthetic "queryTreasury"
        , queryGovernanceState = unusedSynthetic "queryGovernanceState"
        , evaluateTx = \_ -> unusedSynthetic "evaluateTx"
        , posixMsToSlot = eitherToIO . syntheticFloorSlot
        , posixMsCeilSlot = eitherToIO . syntheticCeilSlot
        , queryUpperBoundSlot = \_ -> unusedSynthetic "queryUpperBoundSlot"
        }
  where
    eitherToIO = either (throwIO . userError . T.unpack) pure
    unusedSynthetic :: forall a. String -> IO a
    unusedSynthetic name =
        throwIO
            ( userError
                ( "synthetic coordinate provider: "
                    <> name
                    <> " is not part of the bounded fixture contract"
                )
            )

{- | Floor POSIX milliseconds to a slot using ONLY the fixture 'Globals'
'EpochInfo', by searching the bounded interval. Independent of the provider
arithmetic above.
-}
globalsFloorSlot :: Globals -> Integer -> Either Text SlotNo
globalsFloorSlot globals ms
    | ms >= syntheticSlotStartMs syntheticHorizonSlot =
        -- Refuse rather than clamp: a POSIX value at or past the first slot
        -- beyond the bounded horizon has no coordinate in this fixture.
        Left
            ( "synthetic devnet fixture: "
                <> T.pack (show ms)
                <> " ms is past the bounded horizon"
            )
    | otherwise = do
        starts <- traverse relativeStart boundedSlots
        case [slot | (slot, start) <- starts, start <= target] of
            [] -> Left "globalsFloorSlot: before the fixture origin"
            below -> Right (maximum below)
  where
    boundedSlots =
        SlotNo <$> [0 .. unSlotNo (syntheticHorizon syntheticDevnetCoordinate)]
    relativeStart slot =
        (,) slot . getRelativeTime
            <$> epochInfoSlotToRelativeTime_ (epochInfo globals) slot
    target = fromInteger (ms - syntheticStartMs) / 1000

{- | Ceiling POSIX milliseconds to a slot using ONLY the fixture 'Globals'
'EpochInfo'.
-}
globalsCeilSlot :: Globals -> Integer -> Either Text SlotNo
globalsCeilSlot globals ms = do
    slot <- globalsFloorSlot globals ms
    start <-
        getRelativeTime
            <$> epochInfoSlotToRelativeTime_ (epochInfo globals) slot
    if start == target
        then Right slot
        else globalsFloorSlot globals (syntheticSlotStartMs slot + syntheticSlotMs)
  where
    target = fromInteger (ms - syntheticStartMs) / 1000

jsonAt :: Aeson.Value -> [Text] -> Either String Aeson.Value
jsonAt = foldl step . Right
  where
    step acc key = do
        value <- acc
        case value of
            Aeson.Object fields ->
                maybe
                    (Left (T.unpack key <> " missing"))
                    Right
                    (KeyMap.lookup (Key.fromText key) fields)
            _ -> Left (T.unpack key <> ": parent is not an object")

jsonInteger :: Aeson.Value -> [Text] -> IO Integer
jsonInteger value path =
    case jsonAt value path of
        Right (Aeson.Number number) -> pure (truncate number)
        Right _ -> fail (show path <> ": not a number")
        Left err -> fail (show path <> ": " <> err)

jsonRational :: Aeson.Value -> [Text] -> IO Rational
jsonRational value path =
    case jsonAt value path of
        Right (Aeson.Number number) -> pure (toRational number)
        Right _ -> fail (show path <> ": not a number")
        Left err -> fail (show path <> ": " <> err)

jsonIntegerArray :: Aeson.Value -> [Text] -> IO [Integer]
jsonIntegerArray value path =
    case jsonAt value path of
        Right (Aeson.Array items) -> traverse asInteger (toList items)
        Right _ -> fail (show path <> ": not an array")
        Left err -> fail (show path <> ": " <> err)
  where
    asInteger (Aeson.Number number) = pure (truncate number)
    asInteger _ = fail (show path <> ": non-numeric cost-model entry")

-- ---------------------------------------------------------------------------
-- Offline guard candidates (RED only)
-- ---------------------------------------------------------------------------

-- These are real Conway transactions handed to the real pinned ledger rule.
-- They are never signed and never submitted; they exist so the guard's exact
-- failure constructors can be proved without spending a live run.

offlineOwnerAddr :: Addr
offlineOwnerAddr =
    Addr
        Testnet
        (KeyHashObj (KeyHash (offlineHash28 0x11)))
        StakeRefNull

offlineObserverHash :: ScriptHash
offlineObserverHash = ScriptHash (offlineHash28 0x22)

offlineHash28 :: Word8 -> Hash Blake2b_224 a
offlineHash28 byte =
    fromMaybe
        (error "offlineHash28: expected a 28-byte hash")
        (hashFromBytes (BS.replicate 28 byte))

offlineTxIn :: Word8 -> TxIn
offlineTxIn byte =
    TxIn
        (TxId (unsafeMakeSafeHash (offlineHash32 byte)))
        (TxIx 0)

offlineHash32 :: Word8 -> Hash Blake2b_256 a
offlineHash32 byte =
    fromMaybe
        (error "offlineHash32: expected a 32-byte hash")
        (hashFromBytes (BS.replicate 32 byte))

{- | The resolved input set every offline candidate spends. The mempool rule
short-circuits when it cannot resolve an input, so these must exist.
-}
offlineUtxos :: [(TxIn, TxOut ConwayEra)]
offlineUtxos =
    [ (offlineTxIn 0xaa, mkBasicTxOut offlineOwnerAddr (inject (Coin 1_000_000_000)))
    , (offlineTxIn 0xbb, mkBasicTxOut offlineOwnerAddr (inject (Coin 1_000_000_000)))
    ]

offlineInputs :: Set.Set TxIn
offlineInputs = Set.singleton (offlineTxIn 0xaa)

offlineCollateral :: Set.Set TxIn
offlineCollateral = Set.singleton (offlineTxIn 0xbb)

-- | The exact declared per-purpose budgets the positive Register carried.
registerCheckpointMint, registerHashProofBurn, registerLifecycle :: ExUnits
registerCheckpointMint = ExUnits 12_000_000 7_000_000_000
registerHashProofBurn = ExUnits 500_000 500_000_000
registerLifecycle = ExUnits 12_000_000 7_000_000_000

-- | Declared aggregate of the three Register purposes: 24,500,000.
aggregateMem :: Natural
aggregateMem =
    exUnitsMem registerCheckpointMint
        + exUnitsMem registerHashProofBurn
        + exUnitsMem registerLifecycle

-- | Declared aggregate of the three Register purposes: 14,500,000,000.
aggregateSteps :: Natural
aggregateSteps =
    exUnitsSteps registerCheckpointMint
        + exUnitsSteps registerHashProofBurn
        + exUnitsSteps registerLifecycle

registerRedeemers :: Redeemers ConwayEra
registerRedeemers =
    Redeemers $
        Map.fromList
            [ (ConwayMinting (AsIx 0), (rawLedgerData unitData, registerCheckpointMint))
            , (ConwayMinting (AsIx 1), (rawLedgerData unitData, registerHashProofBurn))
            , (ConwayRewarding (AsIx 0), (rawLedgerData unitData, registerLifecycle))
            ]

unitData :: PLC.Data
unitData = PLC.Constr 0 []

-- | Wrap raw Plutus data as ledger redeemer data (no ToData round-trip).
rawLedgerData :: PLC.Data -> LedgerData.Data ConwayEra
rawLedgerData = LedgerData.Data

offlineBaseTx :: ConwayTx
offlineBaseTx =
    mkBasicTx $
        mkBasicTxBody
            & inputsTxBodyL .~ offlineInputs
            & collateralInputsTxBodyL .~ offlineCollateral
            & outputsTxBodyL
                .~ StrictSeq.singleton
                    (mkBasicTxOut offlineOwnerAddr (inject (Coin 900_000_000)))
            & feeTxBodyL .~ Coin 10_000_000

{- | The exact three-purpose Register aggregate that is inadmissible at PV11:
24,500,000 / 14,500,000,000 against a 16,500,000 / 10,000,000,000 maximum.
-}
overLimitRegisterTx :: ConwayTx
overLimitRegisterTx =
    offlineBaseTx & witsTxL . rdmrsTxWitsL .~ registerRedeemers

-- | A candidate whose script-integrity hash does not match its redeemers.
mutatedIntegrityTx :: ConwayTx
mutatedIntegrityTx =
    offlineBaseTx
        & bodyTxL . scriptIntegrityHashTxBodyL .~ SJust wrongIntegrity
        & witsTxL . rdmrsTxWitsL .~ singleCheapRedeemer
  where
    wrongIntegrity = unsafeMakeSafeHash (offlineHash32 0xcd)

-- | A candidate declaring a zero fee against the pinned genesis fee schedule.
zeroFeeTx :: ConwayTx
zeroFeeTx =
    offlineBaseTx
        & bodyTxL . feeTxBodyL .~ Coin 0
        & witsTxL . rdmrsTxWitsL .~ singleCheapRedeemer

singleCheapRedeemer :: Redeemers ConwayEra
singleCheapRedeemer =
    Redeemers $
        Map.singleton
            (ConwayRewarding (AsIx 0))
            (rawLedgerData unitData, ExUnits 1_000 1_000_000)

offlineWithdrawals :: Withdrawals
offlineWithdrawals =
    Withdrawals $
        Map.singleton
            (AccountAddress Testnet (AccountId (ScriptHashObj offlineObserverHash)))
            (Coin 0)

{- | The zero-withdrawal observer body: genuinely valid on a chain where the
observer registration has settled, but reported as
@WithdrawalsNotInRewardsCERTS@ by an empty default reward state.
-}
withdrawalTx :: ConwayTx
withdrawalTx =
    offlineBaseTx
        & bodyTxL . withdrawalsTxBodyL .~ offlineWithdrawals
        & witsTxL . rdmrsTxWitsL .~ singleCheapRedeemer

{- | The same withdrawal body carrying the inadmissible Register aggregate, so
a genuine structural failure can be proved to survive state seeding.
-}
overLimitWithdrawalTx :: ConwayTx
overLimitWithdrawalTx =
    offlineBaseTx
        & bodyTxL . withdrawalsTxBodyL .~ offlineWithdrawals
        & witsTxL . rdmrsTxWitsL .~ registerRedeemers

{- | EXACTLY the accounts the body withdraws from, at their known balances,
and nothing else. Seeding any further account would be a convenient fiction.
-}
seededObserverAccount :: Phase1RewardState
seededObserverAccount =
    SeededRewardAccounts $
        Map.singleton
            (AccountAddress Testnet (AccountId (ScriptHashObj offlineObserverHash)))
            (Coin 0)

{- | An @n@-request Cage @Modify@-shaped candidate carrying the builder's REAL
declared budgets — @modifyExUnits@ plus @n@ times @contributeExUnits@ — and a
per-request redeemer payload standing in for the real MPF proof and owner
authorization. The declared aggregate is the same arithmetic the live sweep
submitted, so the real ledger rule reaches the same ex-unit verdict offline.
-}
oversizedCageModifyTx :: Int -> ConwayTx
oversizedCageModifyTx n =
    mkBasicTx body & witsTxL . rdmrsTxWitsL .~ redeemers
  where
    requestIns = [offlineTxIn (fromIntegral (0x40 + i)) | i <- [0 .. n - 1]]
    allIns = Set.union offlineInputs (Set.fromList requestIns)
    refundOuts =
        [ mkBasicTxOut offlineOwnerAddr (inject (Coin 4_000_000))
        | _ <- [1 .. n]
        ]
    body =
        mkBasicTxBody
            & inputsTxBodyL .~ allIns
            & collateralInputsTxBodyL .~ offlineCollateral
            & outputsTxBodyL .~ StrictSeq.fromList refundOuts
            & feeTxBodyL .~ Coin (2_000_000 + fromIntegral n * 700_000)
    perRequestPayload =
        PLC.Constr
            0
            [ PLC.B (BS.replicate 320 0x5a)
            , PLC.B (BS.replicate 64 0x6b)
            , PLC.B (BS.replicate 32 0x7c)
            ]
    redeemers =
        Redeemers $
            Map.fromList $
                (ConwaySpending (AsIx 0), (rawLedgerData perRequestPayload, modifyExUnits))
                    : [ ( ConwaySpending (AsIx (fromIntegral i))
                        , (rawLedgerData perRequestPayload, contributeExUnits)
                        )
                      | i <- [1 .. n]
                      ]

{- | A structurally valid, exactly balanced, script-free candidate. Unsigned,
so the ONLY failure the real rule can raise is witness completeness — which is
exactly the partition the guard is allowed to accept.
-}
witnessOnlyTx :: ConwayTx
witnessOnlyTx =
    mkBasicTx $
        mkBasicTxBody
            & inputsTxBodyL .~ offlineInputs
            & outputsTxBodyL
                .~ StrictSeq.singleton
                    (mkBasicTxOut offlineOwnerAddr (inject (Coin 999_800_000)))
            & feeTxBodyL .~ Coin 200_000

-- ---------------------------------------------------------------------------
-- Offline dependency-injected provider seam
-- ---------------------------------------------------------------------------

{- | A pure in-memory 'Provider'. It answers exactly the queries the builders
make, from the composed PV11 guard parameters and a caller-supplied wallet.
It opens no socket, starts no node, and reaches no network; every field the
builders do not use is left as an explicit offline error.
-}

{- | Harness knobs for the offline provider. They only decide what the pure
seam answers; they add no production behaviour.
-}
data OfflineSeams = OfflineSeams
    { seamEvaluate :: ConwayTx -> IO (EvaluateTxResult ConwayEra)
    , seamResolve :: Set.Set TxIn -> IO (Map.Map TxIn (TxOut ConwayEra))
    }

-- | Evaluation is unavailable and nothing settles, unless a spec says otherwise.
defaultOfflineSeams :: OfflineSeams
defaultOfflineSeams =
    OfflineSeams
        { seamEvaluate = \_ -> offlineUnsupported "evaluateTx"
        , seamResolve = \_ -> pure Map.empty
        }

offlineProvider ::
    Pv11GuardParams -> [(TxIn, TxOut ConwayEra)] -> Provider IO
offlineProvider = offlineProviderWith defaultOfflineSeams

offlineProviderWith ::
    OfflineSeams ->
    Pv11GuardParams ->
    [(TxIn, TxOut ConwayEra)] ->
    Provider IO
offlineProviderWith seams guardParams wallet =
    Provider
        { withAcquired = \_ -> offlineUnsupported "withAcquired"
        , queryUTxOs = \_ -> pure wallet
        , queryUTxOByTxIn = \wanted -> do
            settled <- seamResolve seams wanted
            pure (Map.union settled (Map.restrictKeys (Map.fromList wallet) wanted))
        , queryProtocolParams = pure (unPParamsBound (pv11PParamsBound guardParams))
        , queryLedgerSnapshot =
            pure
                LedgerSnapshot
                    { ledgerCurrentEra = "Conway"
                    , ledgerChainPoint = genesisPoint
                    , ledgerTipSlot = offlineTipSlot
                    , ledgerEpoch = EpochNo 0
                    }
        , queryStakeRewards = \_ -> offlineUnsupported "queryStakeRewards"
        , queryRewardAccounts = \_ -> offlineUnsupported "queryRewardAccounts"
        , queryVoteDelegatees = \_ -> offlineUnsupported "queryVoteDelegatees"
        , queryTreasury = offlineUnsupported "queryTreasury"
        , queryGovernanceState = offlineUnsupported "queryGovernanceState"
        , evaluateTx = seamEvaluate seams
        , -- A-069 69A point 3: the offline provider's POSIX/slot translation
          -- IS the canonical downstream coordinate, not a second one-second
          -- convention. The provider and the callback 'Globals' therefore
          -- agree by construction, which is what Standard #12 requires, and a
          -- slot past the named horizon fails here exactly as it fails in the
          -- fixture's own 'EpochInfo'.
          posixMsToSlot = eitherToOfflineIO . syntheticFloorSlot
        , posixMsCeilSlot = eitherToOfflineIO . syntheticCeilSlot
        , queryUpperBoundSlot = \_ ->
            pure (Right (syntheticHorizon syntheticDevnetCoordinate))
        }
  where
    -- The bounded coordinate's refusal is reported in the SAME vocabulary a
    -- node uses for an unforecastable slot, so the builders' existing
    -- past-horizon handling (cap at the queried horizon) applies to it
    -- unchanged instead of treating it as an unknown error.
    eitherToOfflineIO =
        either (fail . ("PastHorizon: " <>) . T.unpack) pure

{- | The offline installation of the A-065 acquisition boundary.

It hands the callback the caller's own offline 'Provider' together with the
ONE downstream-owned 'syntheticDevnetGlobalsFixture'. There is no node to
acquire, so the boundary is degenerate — but the OWNERSHIP contract is the
same one the live path obeys: the callback receives both values, neither is
cached across calls, and neither is reconstructed from a wall clock or an
inferred timestamp.
-}
offlinePhase1Snapshot ::
    Provider IO -> (Globals -> Provider IO -> IO a) -> IO a
offlinePhase1Snapshot provider callback = do
    globals <- syntheticDevnetGlobalsFixture
    callback globals provider

{- | The offline provider's acquired ledger tip, INSIDE the one canonical
downstream coordinate (A-069 69A point 3).

Slot one million was legacy fixture bookkeeping, never semantics: it named no
observable, and it is the only reason the bounded fixture and the offline
seam could not both stand. The tip sits far enough below the named horizon
that every derived endpoint an offline action exercises — an Arm upper at
@tip + 6@, a Claim/Advance window, the guard's own slot — stays inside
@0..199@ and remains translatable, while slot @200@ keeps failing exactly as
the frozen RED requires.
-}
offlineTipSlot :: SlotNo
offlineTipSlot = SlotNo 100

offlineUnsupported :: String -> IO a
offlineUnsupported name =
    fail ("offlineProvider: " <> name <> " is not available offline")

{- | A 'CageEnv' bound to the offline provider. The script is the REAL applied
cage validator from the flake-provided blueprint; only the node seam is
replaced. Submission is wired to an explicit failure so any accidental submit
is loud rather than silent.
-}
offlineCageEnv :: FilePath -> Pv11GuardParams -> [(TxIn, TxOut ConwayEra)] -> IO CageEnv
offlineCageEnv blueprintPath guardParams wallet = do
    blueprint <- loadBlueprint blueprintPath >>= either fail pure
    let cageCode =
            fromMaybe
                (error "offlineCageEnv: cage compiled code not found")
                (extractCompiledCode "cage." blueprint)
        applied = applyParams cageVersion predecessorPolicy cageCode
    pure
        CageEnv
            { envScript = mkCageScript applied
            , envScriptHash = computeScriptHash applied
            , envPolicyId = cagePolicyId applied
            , envScriptAddr = cageScriptAddr applied Testnet
            , envProvider = provider
            , envSubmitter =
                Submitter
                    { submitTx = \_ ->
                        fail "offlineCageEnv: submission attempted offline"
                    }
            , envGuard = guardParams
            , envWithPhase1Snapshot = offlinePhase1Snapshot provider
            }
  where
    provider = offlineProvider guardParams wallet

{- | State plus @n@ request UTxOs shaped exactly as the real builder expects,
so @buildModifyTx@ can run with no node. Returns
@(wallet, stateUtxo, requestUtxos)@.
-}
offlineModifyFixtures ::
    CageEnv ->
    Int ->
    Integer ->
    ([(TxIn, TxOut ConwayEra)], (TxIn, TxOut ConwayEra), [(TxIn, TxOut ConwayEra)])
offlineModifyFixtures env n submittedAt =
    (wallet, stateUtxo, requestUtxos)
  where
    ownerAddr = offlineOwnerAddr
    tokenName = "offline-cage-token"
    anLedger = AssetName (SBS.toShort tokenName)
    stateValue =
        MaryValue
            (Coin minAda)
            ( MultiAsset
                (Map.singleton (envPolicyId env) (Map.singleton anLedger 1))
            )
    stateDat =
        StateDatum
            AIDOnChainTokenState
                { aidStateOwner = toBBS (ownerKeyHashBytes ownerAddr)
                , aidStateRoot = emptyRoot
                , aidIdentityRoot = cageIdentityRoot
                , aidStateTip = cageTip
                , aidStateProcessTime = cageProcessTime
                , aidStateRetractTime = cageRetractTime
                }
    stateUtxo =
        ( offlineTxIn 0x90
        , mkBasicTxOut (envScriptAddr env) stateValue
            & datumTxOutL .~ mkInlineDatum (toPlcData stateDat)
        )
    mkRequest i =
        ( offlineTxIn (fromIntegral (0x40 + i))
        , mkBasicTxOut (envScriptAddr env) (inject (Coin requestAda))
            & datumTxOutL
                .~ mkInlineDatum
                    ( toPlcData
                        ( RequestDatum
                            Request
                                { requestToken = TokenId tokenName
                                , requestOwner = ownerKeyHashBytes ownerAddr
                                , requestKey = namespacedKey i
                                , requestValue = Insert (namespacedValue i)
                                , requestTip = cageTip
                                , requestSubmittedAt = submittedAt
                                }
                        )
                    )
        )
    requestUtxos = [mkRequest i | i <- [0 .. n - 1]]
    wallet =
        [ (offlineTxIn 0xaa, mkBasicTxOut ownerAddr (inject (Coin 5_000_000_000)))
        , (offlineTxIn 0xbb, mkBasicTxOut ownerAddr (inject (Coin 5_000_000_000)))
        ]

-- | The payment key hash matching 'offlineOwnerAddr'.
offlineOwnerKeyHash :: KeyHash Payment
offlineOwnerKeyHash = KeyHash (offlineHash28 0x11)

{- | An offline wallet built from @(seed byte, lovelace)@ pairs, so a spec can
drive a builder to a specific structural boundary with legitimate inputs.
-}
offlineWalletOf :: [(Int, Integer)] -> [(TxIn, TxOut ConwayEra)]
offlineWalletOf entries =
    [ ( offlineTxIn (fromIntegral seedByte)
      , mkBasicTxOut offlineOwnerAddr (inject (Coin lovelace))
      )
    | (seedByte, lovelace) <- entries
    ]

{- | The resolved input set for the genuinely signed admissible candidate: a
single genesis-owned UTxO, so the real rule has everything it needs.
-}
genesisResolvedUtxos :: [(TxIn, TxOut ConwayEra)]
genesisResolvedUtxos =
    [(offlineTxIn 0xef, mkBasicTxOut genesisAddr (inject (Coin 1_000_000_000)))]

{- | A structurally valid, exactly balanced, script-free candidate that is
GENUINELY SIGNED by the genesis key. With no witness gap and no structural
defect the real rule must return @Right ()@.
-}
signedAdmissibleTx :: ConwayTx
signedAdmissibleTx =
    addKeyWitness genesisSignKey $
        mkBasicTx $
            mkBasicTxBody
                & inputsTxBodyL .~ Set.singleton (offlineTxIn 0xef)
                & outputsTxBodyL
                    .~ StrictSeq.singleton
                        (mkBasicTxOut genesisAddr (inject (Coin 999_800_000)))
                & feeTxBodyL .~ Coin 200_000

{- | Run the real Conway Phase-1 guard on the exact candidate a builder seam is
about to return, resolving its complete normal-plus-collateral input set
through the provider. Structural failures reject here, before any evaluation,
signing, or submission continuation, carrying the ledger's own constructors.
-}

{- | The guard always runs INSIDE the acquisition, so the snapshot 'Globals'
and snapshot 'Provider' are passed explicitly: the resolution and the guard
use exactly the coordinate the candidate was built under, and nothing
re-acquires inside an open callback.
-}
guardCandidateIn ::
    Globals -> Provider IO -> CageEnv -> String -> ConwayTx -> IO ()
guardCandidateIn globals provider env label tx = do
    resolved <- queryUTxOByTxIn provider (candidateSpentInputs tx)
    snapshot <- queryLedgerSnapshot provider
    let verdict =
            runPhase1
                Phase1Input
                    { p1Globals = globals
                    , p1Slot = ledgerTipSlot snapshot
                    , p1Params = envGuard env
                    , p1ResolvedInputs = Map.toList resolved
                    }
                NoRewardState
                tx
    unless (phase1Accepted verdict) $
        fail
            ( label
                <> ": Phase-1 guard rejected the candidate: "
                <> renderPhase1 verdict
            )

-- | Every normal and collateral input a candidate spends.
candidateSpentInputs :: ConwayTx -> Set.Set TxIn
candidateSpentInputs tx =
    Set.unions
        [ tx ^. bodyTxL . inputsTxBodyL
        , tx ^. bodyTxL . collateralInputsTxBodyL
        , tx ^. bodyTxL . referenceInputsTxBodyL
        ]
