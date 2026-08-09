{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.LiveRuntime
Description : N2C query/submission composition (#257: no Koios dependency)

The public deployment commands resolve caller-supplied candidate identities
through LocalStateQuery, build and evaluate with the node's current protocol
parameters, sign in process, and submit through LocalTxSubmission.

No address-wide N2C query is used here. #257 (MOD-257-COMPOSITION) moved
this module's former Koios-calling functions
(@indexedFundingUtxos@\/@transactionSettled@\/@awaitTransaction@) to
"Cardano.KERI.ChainQuery.Koios" and its callers to the chain-query algebra;
'withLiveContext' now takes the transaction-observation capability as a
parameter instead of constructing it from embedded Koios settings, so this
component keeps no concrete-provider dependency (INV-257-BUILDER).
-}
module Cardano.KERI.Deployment.LiveRuntime (
    LiveConfig (..),
    LiveContext (..),
    withLiveContext,
    resolveManifestReferences,
    resolveBoardReference,
    resolveOutput,
    resolveTxIns,
    decodePaymentAddress,
    rewardAccountForScript,
    rewardAccountRegistered,
) where

import Cardano.Crypto.DSIGN.Class (deriveVerKeyDSIGN)
import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.EndpointBoardManifest (
    EndpointBoardInfo (..),
    EndpointBoardManifest (..),
 )
import Cardano.KERI.Deployment.Manifest (
    Manifest (..),
    Reference (..),
    ScriptEntry (..),
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    TransactionRuntime (..),
    signWithPaymentKey,
 )
import Cardano.Ledger.Address (
    AccountAddress (..),
    AccountId (..),
    Addr (..),
    decodeAddr,
 )
import Cardano.Ledger.BaseTypes (
    Network (Mainnet, Testnet),
    TxIx (..),
 )
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (TxOut)
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Hashes (
    ScriptHash (..),
    unsafeMakeSafeHash,
 )
import Cardano.Ledger.Keys (
    VKey (..),
    hashKey,
 )
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Cardano.Node.Client.N2C.Connection (
    newLSQChannel,
    newLTxSChannel,
    runNodeClient,
 )
import Cardano.Node.Client.N2C.Provider (mkN2CProvider)
import Cardano.Node.Client.N2C.Submitter (mkN2CSubmitter)
import Cardano.Node.Client.Provider (Provider (..))
import Cardano.Node.Client.Submitter (Submitter (..))
import Cardano.Tx.Sign.Core (decodePaymentSigningKey)
import Codec.Binary.Bech32 qualified as Bech32
import Control.Concurrent.Async (Async, async, cancel, link)
import Control.Exception (bracket, throwIO)
import Control.Monad (unless, when)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteArray.Encoding (Base (Base16), convertFromBase)
import Data.ByteString qualified as BS
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word16)
import Ouroboros.Network.Magic (NetworkMagic (..))

data LiveConfig = LiveConfig
    { liveNetworkMagic :: !Int
    , liveNodeSocket :: !FilePath
    , liveSigningKeyFile :: !FilePath
    , liveFundingAddressText :: !Text
    , liveTimeoutSeconds :: !Int
    }
    deriving stock (Show)

data LiveContext = LiveContext
    { liveTransactionRuntime :: !(TransactionRuntime IO)
    , liveProvider :: !(Provider IO)
    , liveFundingAddress :: !Addr
    , liveConfig :: !LiveConfig
    }

data LiveResources = LiveResources
    { resourceContext :: !LiveContext
    , resourceClient :: !(Async ())
    }

{- | Open one multiplexed LSQ\/LocalTxSubmission connection for an
operation. @observeTransaction@ is the post-submit settlement capability
(#257 FUN-257-OBSERVE): the caller constructs it (e.g. from
'Cardano.KERI.ChainQuery.Koios' at the composition layer) since this
component owns no concrete-provider dependency.
-}
withLiveContext :: LiveConfig -> (TxId -> IO ()) -> (LiveContext -> IO a) -> IO a
withLiveContext config observeTransaction action = do
    when (liveTimeoutSeconds config <= 0) $
        fail "timeout-seconds must be positive"
    fundingAddress <-
        either fail pure (decodePaymentAddress $ liveFundingAddressText config)
    keyEnvelopeResult <- Aeson.eitherDecodeFileStrict' (liveSigningKeyFile config)
    keyEnvelope <- either fail pure (keyEnvelopeResult :: Either String Value)
    signingKey <- either (fail . show) pure (decodePaymentSigningKey keyEnvelope)
    case fundingAddress of
        Addr _ (KeyHashObj actualKeyHash) _ -> do
            let expectedKeyHash = hashKey (VKey $ deriveVerKeyDSIGN signingKey)
            unless (actualKeyHash == expectedKeyHash) $
                fail "funding address payment key does not match the signing key"
        Addr _ ScriptHashObj{} _ ->
            fail "funding address must use a payment key credential"
        AddrBootstrap{} ->
            fail "funding address must be a Shelley testnet address"
    bracket
        (openResources config fundingAddress keyEnvelope observeTransaction)
        (cancel . resourceClient)
        (action . resourceContext)

openResources :: LiveConfig -> Addr -> Value -> (TxId -> IO ()) -> IO LiveResources
openResources config fundingAddress keyEnvelope observeTransaction = do
    lsq <- newLSQChannel 16
    ltxs <- newLTxSChannel 16
    client <-
        async $ do
            connectionResult <-
                runNodeClient
                    (NetworkMagic $ fromIntegral $ liveNetworkMagic config)
                    (liveNodeSocket config)
                    lsq
                    ltxs
            case connectionResult of
                Left exception -> throwIO exception
                Right () -> fail "node-to-client connection closed unexpectedly"
    link client
    let provider = mkN2CProvider lsq
        submitter = mkN2CSubmitter ltxs
        runtime =
            TransactionRuntime
                { trQueryProtocolParams = queryProtocolParams provider
                , trEvaluate = evaluateTx provider
                , trSign = pure . signWithPaymentKey keyEnvelope
                , trSubmit = submitTx submitter
                , trObserve = observeTransaction
                }
        context =
            LiveContext
                { liveTransactionRuntime = runtime
                , liveProvider = provider
                , liveFundingAddress = fundingAddress
                , liveConfig = config
                }
    pure LiveResources{resourceContext = context, resourceClient = client}

resolveManifestReferences ::
    LiveContext ->
    Manifest ->
    IO [(TxIn, TxOut ConwayEra)]
resolveManifestReferences context manifest =
    resolveTxIns context =<< traverse referenceTxIn references
  where
    references = map scriptReference (manifestScripts manifest)

resolveBoardReference ::
    LiveContext ->
    EndpointBoardManifest ->
    IO [(TxIn, TxOut ConwayEra)]
resolveBoardReference context manifest = do
    txIn <-
        referenceTxIn
            (endpointBoardReference $ endpointBoardManifestInfo manifest)
    resolveTxIns context [txIn]

resolveOutput ::
    LiveContext ->
    Text ->
    Int ->
    IO (TxIn, TxOut ConwayEra)
resolveOutput context txId index = do
    txIn <- either fail pure (mkTxIn txId index)
    rows <- resolveTxIns context [txIn]
    case rows of
        [row] -> pure row
        _ -> fail "exact N2C output resolution returned an impossible cardinality"

resolveTxIns ::
    LiveContext ->
    [TxIn] ->
    IO [(TxIn, TxOut ConwayEra)]
resolveTxIns _ [] = pure []
resolveTxIns context txIns = do
    let requested = Set.fromList txIns
    unless (Set.size requested == length txIns) $
        fail "indexer snapshot contains duplicate output identities"
    resolved <- queryUTxOByTxIn (liveProvider context) requested
    let missing = filter (`Map.notMember` resolved) txIns
    unless (null missing) $
        fail $
            "indexer/N2C snapshot mismatch; outputs are no longer unspent: "
                <> show missing
    pure [(txIn, resolved Map.! txIn) | txIn <- txIns]

referenceTxIn :: Reference -> IO TxIn
referenceTxIn reference =
    either fail pure $
        mkTxIn (referenceTxId reference) (referenceIndex reference)

mkTxIn :: Text -> Int -> Either String TxIn
mkTxIn encodedId index = do
    when (index < 0 || index > fromIntegral (maxBound :: Word16)) $
        Left "transaction output index is outside the ledger range"
    bytes <-
        first
            (const "transaction id is not hexadecimal")
            (convertFromBase Base16 $ TE.encodeUtf8 encodedId)
    unless (BS.length bytes == 32) $
        Left "transaction id is not 32 bytes"
    digest <-
        maybe
            (Left "transaction id is not a ledger hash")
            Right
            (hashFromBytes bytes)
    pure (TxIn (TxId $ unsafeMakeSafeHash digest) (TxIx $ fromIntegral index))

decodePaymentAddress :: Text -> Either String Addr
decodePaymentAddress encoded = do
    (hrp, dataPart) <-
        first
            (("funding address is not Bech32: " <>) . show)
            (Bech32.decodeLenient encoded)
    unless (Bech32.humanReadablePartToText hrp == "addr_test") $
        Left "funding address must use addr_test"
    bytes <-
        maybe
            (Left "funding address data is invalid")
            Right
            (Bech32.dataPartToBytes dataPart)
    address <-
        maybe
            (Left "funding address is not a Shelley address")
            Right
            (decodeAddr bytes :: Maybe Addr)
    case address of
        Addr Testnet _ _ -> Right address
        Addr Mainnet _ _ -> Left "funding address belongs to mainnet"
        AddrBootstrap{} -> Left "funding address is a Byron address"

rewardAccountForScript :: Text -> Manifest -> Either String AccountAddress
rewardAccountForScript name manifest = do
    script <-
        case find ((== name) . scriptName) (manifestScripts manifest) of
            Just found -> Right found
            Nothing -> Left ("manifest script is absent: " <> T.unpack name)
    bytes <-
        first
            (const $ "manifest script hash is not hexadecimal: " <> T.unpack name)
            (convertFromBase Base16 $ TE.encodeUtf8 $ scriptHash script)
    unless (BS.length bytes == 28) $
        Left ("manifest script hash is not 28 bytes: " <> T.unpack name)
    digest <-
        maybe
            (Left $ "manifest script hash is not a ledger hash: " <> T.unpack name)
            Right
            (hashFromBytes bytes)
    pure $
        AccountAddress Testnet (AccountId $ ScriptHashObj $ ScriptHash digest)

rewardAccountRegistered :: LiveContext -> AccountAddress -> IO Bool
rewardAccountRegistered context account =
    Map.member account
        <$> queryRewardAccounts
            (liveProvider context)
            (Set.singleton account)
