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
    buildModifyTx,

    -- * Settlement helpers
    hasThreadToken,
    isRequestOutput,
    stateRootOf,
    threadTokenName,
) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Sequence.Strict qualified as StrictSeq
import Data.Set qualified as Set
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word32)
import Lens.Micro ((&), (.~), (^.))

import Cardano.Crypto.Hash (hashToBytes)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Allegra.Scripts (ValidityInterval (..))
import Cardano.Ledger.Alonzo.Scripts (AsIx (..))
import Cardano.Ledger.Alonzo.TxBody (
    reqSignerHashesTxBodyL,
    scriptIntegrityHashTxBodyL,
 )
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Tx (mkBasicTx, witsTxL)
import Cardano.Ledger.Api.Tx.Body (
    collateralInputsTxBodyL,
    feeTxBodyL,
    inputsTxBodyL,
    mintTxBodyL,
    mkBasicTxBody,
    outputsTxBodyL,
    vldtTxBodyL,
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
    Inject (..),
    Network (..),
    StrictMaybe (SJust),
    TxIx (..),
 )
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Conway.Scripts (ConwayPlutusPurpose (..))
import Cardano.Ledger.Core (Script, extractHash)
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Hashes (ScriptHash)
import Cardano.Ledger.Keys (KeyHash (..), KeyRole (..), coerceKeyRole)
import Cardano.Ledger.Mary.Value (
    AssetName (..),
    MaryValue (..),
    MultiAsset (..),
    PolicyID (..),
 )
import Cardano.Ledger.Plutus.ExUnits (ExUnits (..))
import Cardano.Ledger.Plutus.Language (Language (PlutusV3))
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))

import Cardano.Node.Client.Balance (
    BalanceResult (..),
    CollateralUtxos (..),
    balanceTx,
    balanceTxWith,
    computeScriptIntegrity,
 )
import Cardano.Node.Client.Ledger (ConwayTx)
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.N2C.Types (LSQChannel, LTxSChannel)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (Submitter (..))

import Cardano.Node.Client.E2E.Setup (
    Ed25519DSIGN,
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    mkSignKey,
    rawSerialiseVerKeyDSIGN,
 )

import PlutusCore.Data qualified as PLC
import PlutusTx.Builtins.Internal (BuiltinByteString (..))

import Cardano.KERI.AID.Cage.Sign (signValueWrite)
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
    insertRootFromEmpty,
 )
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

{- | Fixed fee overestimate for the manually balanced Modify (the ledger
accepts an overpaid fee; validModify's refund invariant uses this exact
value). Generous enough for two Plutus script executions on the devnet.
-}
modifyFee :: Integer
modifyFee = 2_000_000

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
    }

{- | Load the blueprint, apply BOTH validator params, derive the policy id
and script address from the exact applied bytes, and record the script
hash (printed as artifact evidence).
-}
mkCageEnv :: FilePath -> LSQChannel -> LTxSChannel -> IO CageEnv
mkCageEnv bpPath lsq ltxs = do
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
            }

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

{- | Current POSIX time in milliseconds (the devnet's systemStart is patched
to the wall clock, so this tracks chain time closely enough for the
Modify's validity window).
-}
currentPosixMs :: IO Integer
currentPosixMs = round . (* 1000) <$> getPOSIXTime

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
buildSplitTx env ownerAddr = do
    pp <- queryProtocolParams (envProvider env)
    walletUtxos <- queryUTxOs (envProvider env) ownerAddr
    let feeUtxo = case walletUtxos of
            (u : _) -> u
            [] -> error "buildSplitTx: no wallet UTxO"
        splitOut = mkBasicTxOut ownerAddr (inject (Coin 10_000_000))
        -- Three dedicated 10-ada UTxOs + balanceTx change = >=4 wallet UTxOs.
        body =
            mkBasicTxBody
                & outputsTxBodyL .~ StrictSeq.fromList [splitOut, splitOut, splitOut]
        tx = mkBasicTx body
    case balanceTx pp [feeUtxo] [] ownerAddr tx of
        Left err -> error ("buildSplitTx: balance failed: " <> show err)
        Right r -> pure (balancedTx r)

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
buildMintTx env _ownerKh ownerAddr seedUtxo = do
    pp <- queryProtocolParams (envProvider env)
    walletUtxos <- queryUTxOs (envProvider env) ownerAddr
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
        integrity = computeScriptIntegrity PlutusV3 pp redeemers
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
        Right r -> pure (balancedTx r)

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
buildRequestTx env _ownerKh ownerAddr tokenNameBs = do
    pp <- queryProtocolParams (envProvider env)
    walletUtxos <- queryUTxOs (envProvider env) ownerAddr
    -- Real submission timestamp (current POSIX ms); the Modify's phase-1
    -- window is derived to sit before submittedAt + process_time (NOTE-008).
    submittedAt <- currentPosixMs
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
    case balanceTx pp [feeUtxo] [] ownerAddr tx of
        Left err -> error ("buildRequestTx: balance failed: " <> show err)
        Right r -> pure (balancedTx r)

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
buildModifyTx env ownerKh ownerAddr stateUtxo reqUtxos = do
    pp <- queryProtocolParams (envProvider env)
    walletUtxos <- queryUTxOs (envProvider env) ownerAddr
    -- Real chain-time validity derived from the node clock via the pinned
    -- Provider (NOTE-008): a CURRENT interval [lower, upper] that contains
    -- now (so the tx is valid at inclusion) and whose upper bound is well
    -- before submitted_at + process_time, so cage.in_phase1 holds. The lower
    -- bound is derived off a 10s-past timestamp so it is never ahead of the
    -- current slot (which would trip a Phase-1 OutsideValidityInterval).
    now <- currentPosixMs
    lowerSlot <- posixMsCeilSlot (envProvider env) (now - 10_000)
    upperSlot <- posixMsToSlot (envProvider env) (now + 30_000)
    let (stateIn, stateOut) = stateUtxo
        reqIns = map fst reqUtxos
        -- Fee input and collateral must be TWO DISJOINT wallet UTxOs (and both
        -- disjoint from the script inputs): reusing one as the other is a
        -- Phase-1 collateral-structure error.
        walletAvail =
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
        reqLovelace =
            sum [unCoin (o ^. coinTxOutL) | (_, o) <- reqUtxos]
        refundLovelace = reqLovelace - modifyFee - cageTip
        newRoot = insertRootFromEmpty cageRequestKey cageValue
        -- Continuing state output (index 0), token confined.
        newStateDat =
            StateDatum
                AIDOnChainTokenState
                    { aidStateOwner = toBBS (ownerKeyHashBytes ownerAddr)
                    , aidStateRoot = newRoot
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
        -- Refund output (index 1) back to the requester (owner).
        refundOut = mkBasicTxOut ownerAddr (inject (Coin refundLovelace))
        -- Change output (index 2), absorbing the fee UTxO remainder; ignored
        -- by validModify's sumRefunds (only one owner).
        changeLovelace =
            (minAda + reqLovelace + feeUtxoLovelace)
                - minAda -- new state out
                - refundLovelace
                - modifyFee
        changeOut = mkBasicTxOut ownerAddr (inject (Coin changeLovelace))
        allOuts = StrictSeq.fromList [newStateOut, refundOut, changeOut]
        -- Inputs: state + requests + fee/collateral.
        allScriptIns = Set.fromList (stateIn : reqIns)
        allIns = Set.insert feeIn allScriptIns
        -- Redeemers: Modify on the state input, Contribute on each request.
        stateRef = txInToRef stateIn
        -- Owner authorization signature over the request UTxO's output
        -- reference (the ref the on-chain verifyOwnerAuth binds to, for
        -- replay protection): blake2b_256(domain ++ tx_id ++ be2(idx)).
        reqRef = case reqIns of
            (r : _) -> txInToRef r
            [] -> error "buildModifyTx: no request input"
        ownerSig' =
            signValueWrite authSignKey (refTxId reqRef) (refIdx reqRef)
        auth =
            AIDOwnerAuth
                { ownerAid = cageOwnerAid
                , identityProof = [] -- single-leaf trie -> empty proof
                , ownerKey = authOwnerKey
                , ownerSig = ownerSig'
                }
        modifyRedeemer = Modify [AIDUpdateAction{valueProof = [], auth = auth}]
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
        integrity = computeScriptIntegrity PlutusV3 pp redeemers
        witnessKh = coerceKeyRole ownerKh :: KeyHash Guard
        -- A real current window; in_phase1 constrains the upper bound (~30s
        -- ahead of now, well before submitted_at + process_time), and the
        -- lower bound keeps the interval a genuine current interval.
        vldt = ValidityInterval (SJust lowerSlot) (SJust upperSlot)
        body =
            mkBasicTxBody
                & inputsTxBodyL .~ allIns
                & outputsTxBodyL .~ allOuts
                & feeTxBodyL .~ Coin modifyFee
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
            [ ("Modify", modifyExUnits)
            , ("Contribute", contributeExUnits)
            ]
    pure (tx, newRoot, declared)

-- | Wrap raw bytes as the @BuiltinByteString@ the mirrored State datum uses.
toBBS :: ByteString -> BuiltinByteString
toBBS = BuiltinByteString
