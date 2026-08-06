{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.LiveRuntime
Description : Production Koios discovery plus N2C query/submission composition

The public deployment commands enumerate payer outputs through the configured
indexer, resolve only those exact inputs through LocalStateQuery, build and
evaluate with the node's current protocol parameters, sign in process, submit
through LocalTxSubmission, and wait for independent indexer settlement.

No address-wide N2C query is used here.  That boundary is deliberate: an
indexer snapshot selects the candidate identities while N2C supplies the full
ledger outputs needed by balancing.
-}
module Cardano.KERI.Deployment.LiveRuntime (
    LiveConfig (..),
    LiveContext (..),
    withLiveContext,
    indexedFundingUtxos,
    resolveManifestReferences,
    resolveBoardReference,
    resolveOutput,
    decodePaymentAddress,
    rewardAccountForScript,
    rewardAccountRegistered,
    transactionSettled,
) where

import Cardano.Crypto.DSIGN.Class (deriveVerKeyDSIGN)
import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.ChainIndex (
    ChainAssetUtxo (..),
    ChainTransactionInfo (..),
    KoiosToken,
    queryAddressUtxos,
    queryTransactionInfo,
 )
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
    renderTransactionId,
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
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (Async, async, cancel, link)
import Control.Exception (SomeException, bracket, throwIO, try)
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
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Data.Word (Word16)
import Ouroboros.Network.Magic (NetworkMagic (..))

data LiveConfig = LiveConfig
    { liveNetworkMagic :: !Int
    , liveNodeSocket :: !FilePath
    , liveSigningKeyFile :: !FilePath
    , liveFundingAddressText :: !Text
    , liveKoiosUrl :: !Text
    , liveKoiosToken :: !(Maybe KoiosToken)
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

-- | Open one multiplexed LSQ/LocalTxSubmission connection for an operation.
withLiveContext :: LiveConfig -> (LiveContext -> IO a) -> IO a
withLiveContext config action = do
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
        (openResources config fundingAddress keyEnvelope)
        (cancel . resourceClient)
        (action . resourceContext)

openResources :: LiveConfig -> Addr -> Value -> IO LiveResources
openResources config fundingAddress keyEnvelope = do
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
                , trObserve = awaitTransaction config
                }
        context =
            LiveContext
                { liveTransactionRuntime = runtime
                , liveProvider = provider
                , liveFundingAddress = fundingAddress
                , liveConfig = config
                }
    pure LiveResources{resourceContext = context, resourceClient = client}

-- | Enumerate through Koios, then resolve those exact identities through N2C.
indexedFundingUtxos :: LiveContext -> IO [(TxIn, TxOut ConwayEra)]
indexedFundingUtxos context = do
    let config = liveConfig context
        address = liveFundingAddressText config
    indexed <-
        queryAddressUtxos
            (liveKoiosUrl config)
            (liveKoiosToken config)
            address
    unless (all ((== address) . chainAssetAddress) indexed) $
        fail "indexer returned a payer output at a different address"
    txIns <- traverse indexedTxIn indexed
    resolveTxIns context txIns

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

indexedTxIn :: ChainAssetUtxo -> IO TxIn
indexedTxIn output =
    either fail pure $
        mkTxIn (chainAssetTxId output) (chainAssetIndex output)

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

transactionSettled :: LiveConfig -> TxId -> IO Bool
transactionSettled config txId = do
    transactions <-
        queryTransactionInfo
            (liveKoiosUrl config)
            (liveKoiosToken config)
            [renderTransactionId txId]
    pure $
        any
            ((== renderTransactionId txId) . txInfoTxHash)
            transactions

awaitTransaction :: LiveConfig -> TxId -> IO ()
awaitTransaction config txId = do
    started <- getCurrentTime
    let loop = do
            observed <- try (transactionSettled config txId)
            case observed of
                Right True -> pure ()
                Right False -> retry started
                Left (_ :: SomeException) -> retry started
        retry startedAt = do
            now <- getCurrentTime
            if diffUTCTime now startedAt
                >= fromIntegral (liveTimeoutSeconds config)
                then
                    fail $
                        "transaction settlement timed out: "
                            <> T.unpack (renderTransactionId txId)
                else threadDelay 2_000_000 >> loop
    loop
