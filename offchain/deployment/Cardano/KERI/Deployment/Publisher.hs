{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.Publisher
Description : Publish applied scripts through the in-process transaction runtime and wait for settlement

#181 Slice 2B: the publisher no longer shells out to an external CLI for
UTxO query, transaction build, signing, transaction-id derivation, or
submission. It composes the shared in-process kernel
('Cardano.KERI.Deployment.TransactionRuntime.runTransactionBuild') over a
caller-supplied 'TransactionRuntime', then settles through an injected
chain-query primitive ('awaitReference'). The reported reference id is the
pure id of the signed transaction, never an echoed submitter value.
-}
module Cardano.KERI.Deployment.Publisher (
    PublishConfig (..),
    PublishError (..),
    publishScripts,
    publishOne,
    awaitReference,
) where

import Cardano.KERI.ChainQuery (ChainAssetUtxo (..), ChainReference (..))
import Cardano.KERI.Deployment.Manifest (Reference (..))
import Cardano.KERI.Deployment.Script (
    ScriptArtifact (..),
    mkCageScript,
    scriptHashText,
 )
import Cardano.KERI.Deployment.TransactionRuntime (
    PayerSelectionError,
    TransactionRuntime (..),
    fundingSpends,
    renderTransactionId,
    runTransactionBuild,
    selectFundingPair,
 )
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.Api.Tx.Body (referenceScriptTxOutL)
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (
    Script,
    TxOut,
    fromStrictMaybeL,
    mkBasicTxOut,
 )
import Cardano.Ledger.Mary.Value (MaryValue (..), MultiAsset (..))
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Tx.Build (
    InterpretIO (..),
    TxBuild,
    defaultBuildOptions,
    output,
    spend,
 )
import Control.Concurrent (threadDelay)
import Data.Functor.Const (Const (..), getConst)
import Data.Functor.Identity (Identity (..), runIdentity)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock (diffUTCTime, getCurrentTime)

{- | Settlement polling cadence in microseconds, matching the pre-migration
publisher's fixed wait between reference-script observations.
-}
publishSettlementPollMicros :: Int
publishSettlementPollMicros = 5_000_000

{- | In-process publish configuration. The caller supplies the transaction
runtime capability, the indexed funding UTxOs, the funding/change address,
the reference output value, the settlement query primitive, and the
observation timeout.
-}
data PublishConfig = PublishConfig
    { publishRuntime :: !(TransactionRuntime IO)
    , publishInputUtxos :: ![(TxIn, TxOut ConwayEra)]
    , publishFundingAddress :: !Addr
    , publishReferenceLovelace :: !Integer
    , publishQueryReferences :: !(Text -> IO [ChainReference])
    , publishTimeoutSeconds :: !Int
    }

-- | Actionable failures of the in-process publish path.
data PublishError
    = -- | Deterministic payer selection rejected the indexed snapshot.
      PublishFundingSelectionFailed !PayerSelectionError
    | -- | The converged build/sign/submit kernel rejected the evolution.
      PublishBuildFailed !Text
    | -- | Settlement was not observed within the timeout.
      TransactionObservationTimeout !Text !Text
    deriving stock (Show)

{- | Publish every artifact in order, returning each settled reference.

Fails the whole run on the first artifact that cannot be published.
-}
publishScripts ::
    PublishConfig ->
    [ScriptArtifact] ->
    IO [(Text, Reference)]
publishScripts config = traverse publishOneOrFail
  where
    publishOneOrFail artifact = do
        result <- publishOne config artifact
        case result of
            Left err ->
                fail $
                    "publish "
                        <> T.unpack (artifactName artifact)
                        <> ": "
                        <> show err
            Right pair -> pure pair

{- | Publish one artifact as a reference script and wait for it to settle.

Selects a deterministic funding input, converges a build\/sign\/submit
evolution through the shared kernel, then observes settlement through the
injected chain-query primitive. Returns the artifact name and the settled
reference, or a typed 'PublishError'.
-}
publishOne ::
    PublishConfig ->
    ScriptArtifact ->
    IO (Either PublishError (Text, Reference))
publishOne config artifact =
    case selectFundingPair isPlainUtxo required (publishInputUtxos config) of
        Left selectionError ->
            pure (Left (PublishFundingSelectionFailed selectionError))
        Right funding -> do
            buildResult <-
                runTransactionBuild
                    defaultBuildOptions
                    (publishRuntime config)
                    publishInterpret
                    (fundingSpends funding)
                    []
                    (publishFundingAddress config)
                    ( publishProgram
                        (map fst $ fundingSpends funding)
                        (referenceTxOut config artifact)
                    )
            case buildResult of
                Left buildError ->
                    pure (Left (PublishBuildFailed (T.pack (show buildError))))
                Right txid -> do
                    let scriptHash = scriptHashText (artifactScriptHash artifact)
                        settledTxId = renderTransactionId txid
                    settlement <-
                        awaitReference
                            (publishQueryReferences config)
                            publishSettlementPollMicros
                            (publishTimeoutSeconds config)
                            scriptHash
                            settledTxId
                    pure $
                        case settlement of
                            Left observationError -> Left observationError
                            Right reference ->
                                Right (artifactName artifact, reference)
  where
    required = Coin (publishReferenceLovelace config)

{- | A funding UTxO is eligible only when it carries no reference script.
'referenceScriptTxOutL' focuses a 'StrictMaybe'; 'fromStrictMaybeL' adapts
it to the plain 'Maybe' this check reasons about.
-}
isPlainUtxo :: TxOut ConwayEra -> Bool
isPlainUtxo txOut =
    isNothing
        (getConst ((referenceScriptTxOutL . fromStrictMaybeL) Const txOut))

{- | The single reference-script output: the artifact at the funding address,
carrying exactly the configured lovelace.
-}
referenceTxOut :: PublishConfig -> ScriptArtifact -> TxOut ConwayEra
referenceTxOut config artifact =
    withReferenceScript
        (mkCageScript (artifactProgram artifact))
        ( mkBasicTxOut
            (publishFundingAddress config)
            (MaryValue (Coin (publishReferenceLovelace config)) (MultiAsset mempty))
        )

-- | Attach a reference script to a transaction output.
withReferenceScript ::
    Script ConwayEra ->
    TxOut ConwayEra ->
    TxOut ConwayEra
withReferenceScript script txOut =
    runIdentity
        ( (referenceScriptTxOutL . fromStrictMaybeL)
            (\_ -> Identity (Just script))
            txOut
        )

{- | The publish program spends the selected funding input and emits the
reference output; balancing produces the single change output. No
collateral is declared for a script-free publish.
-}
publishProgram :: [TxIn] -> TxOut ConwayEra -> TxBuild PublishCtx () ()
publishProgram spendInputs refTxOut = do
    mapM_ spend spendInputs
    _ <- output refTxOut
    pure ()

{- | No domain queries are issued during a publish; the interpreter is
unreachable.
-}
data PublishCtx a

publishInterpret :: InterpretIO PublishCtx
publishInterpret = InterpretIO (\case {})

{- | Poll the injected chain-query primitive until the exact (script hash,
transaction id) pair is observed, or fail closed on timeout. The deadline is
checked only after observing and rejecting a real answer, so the timeout is
reached by iterating the loop, never by skipping the observation.
-}
awaitReference ::
    (Text -> IO [ChainReference]) ->
    Int ->
    Int ->
    Text ->
    Text ->
    IO (Either PublishError Reference)
awaitReference queryReferences pollMicros timeoutSeconds scriptHash txId = do
    started <- getCurrentTime
    let loop = do
            references <- queryReferences scriptHash
            case [ reference
                 | reference <- references
                 , chainReferenceScriptHash reference == scriptHash
                 , chainAssetTxId (chainReferenceOutput reference) == txId
                 ] of
                match : _ ->
                    pure $
                        Right
                            ( Reference
                                (chainAssetTxId (chainReferenceOutput match))
                                (chainAssetIndex (chainReferenceOutput match))
                            )
                [] -> do
                    now <- getCurrentTime
                    if diffUTCTime now started
                        >= fromIntegral timeoutSeconds
                        then
                            pure
                                ( Left
                                    ( TransactionObservationTimeout
                                        scriptHash
                                        txId
                                    )
                                )
                        else threadDelay pollMicros >> loop
    loop
