{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReadbackSpec
Description : The checkpoint of a booked identifier, read back through a ledger provider

The provider here serves the transactions the builders wrote: the booking
that created the request, the fold that consumed it and the checkpoint the fold
delivered. The three identifiers of the December rows (a non-transferable and a
transferable key-derived prefix, and a self-addressing one) are read by the
identifier exactly as signed; the answer carries the stored identifier and keys
as spelled, the references that tie them to the booking, and the inception
digest recomputed from the signed bytes in that booking's evidence. A provider
that cannot show a link returns the stored state marked not linked and names the
link; it never supplies a digest.
-}
module Cardano.KERI.Deployment.RegistryReadbackSpec (
    spec,
    World (..),
    worldOf,
    worldAt,
    honest,
    providerOf,
    shownBy,
    rows,
) where

import Cardano.KERI.AID.Application (RegistrationData (..), activeTokenName)
import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.Deployment.ReferenceInception (Reference (..), loadReferences, pick, respell)
import Cardano.KERI.Deployment.Registry (RegistryScripts (..))
import Cardano.KERI.Deployment.RegistryBookingShapeSpec (
    Scenario (..),
    foldAt,
    scenarioOf,
 )
import Cardano.KERI.Deployment.RegistryChain (exportKey)
import Cardano.KERI.Deployment.RegistryReadback (
    Link (..),
    LinkFailure (..),
    Linked (..),
    Readback (..),
    readCheckpoint,
    signedDigest,
 )
import Cardano.KERI.Deployment.RegistryTransactions (
    applicationPolicyId,
    approval,
    deploymentScripts,
    statePolicyId,
 )
import Cardano.KERI.Deployment.RegistryTransactionsSpec (deposit, load, outputAt, producedBy)
import Cardano.Ledger.Alonzo.TxWits (Redeemers (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..))
import Cardano.Ledger.Api.Tx (txIdTx, witsTxL)
import Cardano.Ledger.Api.Tx.Out (TxOut)
import Cardano.Ledger.Api.Tx.Wits (rdmrsTxWitsL)
import Cardano.Ledger.BaseTypes (TxIx (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Mary.Value (AssetName (..), PolicyID)
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Tracer (nullTracer)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Short qualified as SBS
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import Lens.Micro ((%~), (&))
import PlutusCore.Data qualified as PLC
import Singular.Registry.Evidence (Evidenced (..), NoWitness, SessionBinding (..), SessionId (..))
import Singular.Registry.LedgerProvider (
    HistoricalTransaction (..),
    HistoryBlock (..),
    HistoryFailure (..),
    HistoryStream (..),
    Network (..),
    OutputQuery (..),
    ReadFailure (..),
    Session (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)

-- | One booked and folded identifier, with the transactions the builders wrote for it.
data World = World
    { wScenario :: Scenario
    , wBooking :: HistoricalTransaction
    , wFold :: HistoricalTransaction
    , wHolding :: (TxIn, TxOut ConwayEra)
    , wActive :: (PolicyID, AssetName)
    , wApproval :: (PolicyID, AssetName)
    }

worldOf :: FilePath -> IO World
worldOf name = worldAt [(name, deposit)] 0

{- | The world of the request at an output position of a booking of several requests: the
fold that consumed that position's output, and the approval and active token of its record.
-}
worldAt :: [(FilePath, Integer)] -> Int -> IO World
worldAt shapes position = do
    s <- scenarioOf shapes
    foldTx <- foldAt s position
    let booking = scBooking s
        record = scRecords s !! position
        registry = scRegistry s
        scripts = deploymentScripts registry
    pure
        World
            { wScenario = s
            , wBooking = historical booking []
            , wFold = historical foldTx [outputAt booking position]
            , wHolding = outputAt foldTx 0
            , wActive =
                ( statePolicyId registry
                , AssetName (SBS.toShort (activeTokenName (scriptsRegistry scripts) (requestKey record)))
                )
            , wApproval = (applicationPolicyId registry, AssetName (SBS.toShort (approval record)))
            }

historical :: ConwayTx -> [(TxIn, TxOut ConwayEra)] -> HistoricalTransaction
historical tx spent =
    HistoricalTransaction
        { historicalId = txIdTx tx
        , historicalCbor = mempty
        , historicalTx = tx
        , spentOutputs = spent
        , referenceOutputs = []
        , createdOutputs = producedBy tx
        , scriptValid = True
        }

-- | The provider of a world, with the transactions it shows for each asset.
providerOf ::
    [(TxIn, TxOut ConwayEra)] ->
    ((PolicyID, AssetName) -> Either HistoryFailure [HistoricalTransaction]) ->
    Session NoWitness IO
providerOf holders shown =
    Session
        { sessionNetwork = Network 42
        , sessionId = SessionId "readback-test"
        , sessionBinding = Unbound
        , sessionTracer = nullTracer
        , sessionEvaluated = \_ -> pure ()
        , servedNetwork = unavailable
        , outputs = \case
            HoldingAsset _ -> pure (Right (Evidenced holders Nothing))
            _ -> unavailable
        , protocolParameters = unavailable
        , tipObservation = unavailable
        , networkTime = unavailable
        , scriptRegistered = const unavailable
        , mintRecord = const unavailable
        , history = \asset _ -> pure (stream <$> shown asset)
        , inclusion = const unavailable
        }
  where
    unavailable = pure (Left (BackendReadFailure "not served by this provider"))
    stream = \case
        [] -> HistoryStream (pure (Right Nothing))
        tx : rest -> HistoryStream (pure (Right (Just (HistoryBlock 1 (tx :| []), stream rest))))

-- | The honest provider of a world: every transaction the chain holds for the two tokens.
honest :: World -> Session NoWitness IO
honest w = providerOf [wHolding w] (shownBy w [wFold w] [wBooking w, wFold w])

shownBy ::
    World ->
    [HistoricalTransaction] ->
    [HistoricalTransaction] ->
    (PolicyID, AssetName) ->
    Either HistoryFailure [HistoricalTransaction]
shownBy w active approvals asset
    | asset == wActive w = Right active
    | asset == wApproval w = Right approvals
    | otherwise = Right []

readOf :: World -> Session NoWitness IO -> ByteString -> IO (Either ReadFailure (Maybe Readback))
readOf w = readCheckpoint (scRegistry (wScenario w))

rows :: [(FilePath, ByteString, [ByteString], ByteString)]
rows =
    [
        ( "case:B empty"
        , "BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTw"
        , ["BKCapfR6Z1mAL_lV-NwtKhSlyZ0jvpf4ZBJ_-Tg0VaTw"]
        , "EIgvoqHwq-DpO8FStujY-u5MDe1JjChiQssTtgBG208B"
        )
    ,
        ( "reference:I01"
        , "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
        , ["DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"]
        , "EFdfRKDdnvl3KoYGilKKR8p_ukC4sKLuf8YMJDPT9_8c"
        )
    ,
        ( "reference:I02"
        , "EEnwnQUz696trMrSNOKKH9b2CKz5xTF-fgCquWHuiLgA"
        ,
            [ "DNFWz8AsxHPcZFy7tIswi1cYEG96zmZQVkdz8gQIdzIL"
            , "DCtQH-bOQ4L7ywz_P_uuT_pSKAWce7H6PB_sKuy7b3_R"
            , "DHsjDyW82DiCth5DZhxzn_zJ7PeOPpTFW3zJ-FLXbD09"
            ]
        , "EEnwnQUz696trMrSNOKKH9b2CKz5xTF-fgCquWHuiLgA"
        )
    ]

spec :: Spec
spec = describe "the checkpoint of a booked identifier, read through a ledger provider" $ do
    describe "the stored identifier and keys, and the chain of evidence" $
        mapM_
            ( \(name, aid, keys, said) -> it (show name) $ do
                w <- worldOf name
                let booking = historicalId (wBooking w)
                result <- readOf w (honest w) aid
                case result of
                    Right (Just rb) -> do
                        readbackIdentifier rb `shouldBe` aid
                        readbackKeys rb `shouldBe` keys
                        readbackCheckpoint rb `shouldBe` fst (wHolding w)
                        fmap
                            (\l -> (linkedFold l, linkedPending l, linkedBooking l, linkedIndex l, qb64Aid (linkedDigest l)))
                            (readbackLinks rb)
                            `shouldBe` Right (historicalId (wFold w), TxIn booking (TxIx 0), booking, 0, said)
                    other -> fail ("a checkpoint was expected: " <> show (fmap (fmap readbackIdentifier) other))
            )
            rows
    describe "a weighted future declaration of draft #600 is booked, folded and read back (Q-069)" $
        mapM_
            ( \name -> it name $ do
                w <- worldOf name
                export <- load name
                let aid = exportKey export
                result <- readOf w (honest w) aid
                case result of
                    Right (Just rb) -> do
                        readbackIdentifier rb `shouldBe` aid
                        fmap linkedBooking (readbackLinks rb) `shouldBe` Right (historicalId (wBooking w))
                    other -> fail ("a checkpoint was expected: " <> show (fmap (fmap readbackIdentifier) other))
            )
            ["future:D next unreduced", "future:D next partial coverage"]
    describe "a request that is not at the first output of its booking" $ do
        it "is read at its own output index, with its own evidence among the two the booking issues" $ do
            let shapes = [("case:B empty", deposit), ("reference:I01", deposit + 7_000_000)]
                aid = "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            w <- worldAt shapes 1
            result <- readOf w (honest w) aid
            case result of
                Right (Just rb) -> do
                    readbackIdentifier rb `shouldBe` aid
                    fmap (\l -> (linkedIndex l, linkedPending l, qb64Aid (linkedDigest l))) (readbackLinks rb)
                        `shouldBe` Right (1, TxIn (historicalId (wBooking w)) (TxIx 1), "EFdfRKDdnvl3KoYGilKKR8p_ukC4sKLuf8YMJDPT9_8c")
                other -> fail ("a checkpoint was expected: " <> show (fmap (fmap readbackIdentifier) other))
        it "does not take the evidence of the other request of the booking" $ do
            let shapes = [("case:B empty", deposit), ("reference:I01", deposit + 7_000_000)]
            w <- worldAt shapes 1
            result <- readOf w (honest w) "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            fmap (fmap (fmap (qb64Aid . linkedDigest) . readbackLinks)) result
                `shouldBe` Right (Just (Right "EFdfRKDdnvl3KoYGilKKR8p_ukC4sKLuf8YMJDPT9_8c"))
    describe "a transaction in a later block of the history is found" $
        it "links the booking when the provider streams it after other transactions of the approval" $ do
            w <- worldOf "reference:I01"
            result <-
                readOf
                    w
                    (providerOf [wHolding w] (shownBy w [wFold w] [wFold w, wFold w, wBooking w]))
                    "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            case result of
                Right (Just rb) -> fmap linkedBooking (readbackLinks rb) `shouldBe` Right (historicalId (wBooking w))
                other -> fail ("a checkpoint was expected: " <> show (fmap (fmap readbackIdentifier) other))
    describe "a link the provider cannot show leaves the stored state, marked not linked, and no digest" $ do
        let unlinked name provider expected = it name $ do
                w <- worldOf "reference:I01"
                result <- readOf w (provider w) "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
                case result of
                    Right (Just rb) -> do
                        readbackIdentifier rb `shouldBe` "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
                        readbackKeys rb `shouldBe` ["DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"]
                        expected (readbackLinks rb)
                    other -> fail ("stored state was expected: " <> show (fmap (fmap readbackIdentifier) other))
            failedAt link failure = \case
                Left (l, f) -> (l, f) `shouldBe` (link, failure)
                Right _ -> fail "the links must not be complete"
        unlinked
            "the fold transaction is not among the transactions shown for the active token"
            (\w -> providerOf [wHolding w] (shownBy w [] [wBooking w, wFold w]))
            (failedAt AtFoldTransaction (NotShown AtFoldTransaction))
        unlinked
            "the fold shows no request of the identifier among its spent outputs"
            ( \w ->
                providerOf
                    [wHolding w]
                    (shownBy w [(wFold w){spentOutputs = []}] [wBooking w, wFold w])
            )
            (failedAt AtPendingOutput (NotShown AtPendingOutput))
        unlinked
            "the booking transaction is not among the transactions shown for the approval"
            (\w -> providerOf [wHolding w] (shownBy w [wFold w] [wFold w]))
            (failedAt AtBookingTransaction (NotShown AtBookingTransaction))
        unlinked
            "the booking transaction carries no evidence at the index of the request"
            ( \w ->
                providerOf
                    [wHolding w]
                    (shownBy w [wFold w] [(wBooking w){historicalTx = historicalTx (wFold w)}, wFold w])
            )
            (failedAt AtBookingEvidence (NotShown AtBookingEvidence))
        unlinked
            "the provider refuses the history of the approval"
            ( \w ->
                providerOf [wHolding w] $ \asset ->
                    if asset == wApproval w
                        then Left (HistoryReadFailure (BackendReadFailure "history is not served"))
                        else shownBy w [wFold w] [] asset
            )
            ( \case
                Left (AtBookingTransaction, ProviderRefused AtBookingTransaction _) -> pure ()
                other -> fail ("a refused history of the approval was expected: " <> show other)
            )
    describe "the evidence is not one complete inception" $ do
        it "names the evidence of the booking, not the signed identifier, and supplies no digest" $ do
            w <- worldOf "reference:I01"
            let garbled = (wBooking w){historicalTx = garble (historicalTx (wBooking w))}
            result <-
                readOf
                    w
                    (providerOf [wHolding w] (shownBy w [wFold w] [garbled, wFold w]))
                    "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            case result of
                Right (Just rb) -> readbackLinks rb `shouldBe` Left (AtBookingEvidence, EvidenceUndecodable)
                other -> fail ("stored state was expected: " <> show (fmap (fmap readbackIdentifier) other))
        it "is the same result for bytes that are cut short" $
            signedDigest "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ" "{\"v\":\"KERI10JSON" `shouldBe` Left EvidenceUndecodable
    describe "the evidence is for the identifier that is stored" $
        it "the signed identifier of the evidence differs from the stored one" $ do
            w <- worldOf "reference:I01"
            other <- worldOf "reference:I02"
            let swapped = (wBooking w){historicalTx = historicalTx (wBooking other)}
            result <-
                readOf
                    w
                    (providerOf [wHolding w] (shownBy w [wFold w] [swapped, wFold w]))
                    "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            case result of
                Right (Just rb) -> readbackLinks rb `shouldBe` Left (AtSignedIdentifier, IdentifierDiffers)
                other' -> fail ("stored state was expected: " <> show (fmap (fmap readbackIdentifier) other'))
    describe "the digest of the signed bytes" $ do
        it "is recomputed from them, and the digest they carry must be the one they bind" $ do
            refs <- loadReferences
            let r = pick "I01" refs
                said = TE.encodeUtf8 (refSaid r)
                changed = BS.take 2 said <> (if BS.index said 2 == 0x41 then "B" else "A") <> BS.drop 3 said
            fmap qb64Aid (signedDigest (TE.encodeUtf8 (refIdentifier r)) (refEvent r)) `shouldBe` Right said
            signedDigest (TE.encodeUtf8 (refIdentifier r)) (respell (refEvent r) said changed)
                `shouldBe` Left DigestDoesNotBind
        it "is not supplied when the identifier of the bytes is another" $ do
            refs <- loadReferences
            signedDigest (TE.encodeUtf8 (refIdentifier (pick "I02" refs))) (refEvent (pick "I01" refs))
                `shouldBe` Left IdentifierDiffers
    describe "an identifier nothing holds" $
        it "is read as nothing, not as an error" $ do
            w <- worldOf "reference:I01"
            result <- readOf w (providerOf [] (shownBy w [] [])) "DKx2eNz1Wnq8AkCuLVA5IaAWze0OncYRfoF3LQG5H-PZ"
            fmap (fmap readbackIdentifier) result `shouldBe` Right Nothing

-- | The same transaction with the signed bytes of every Issue entry replaced by bytes that are no event.
garble :: ConwayTx -> ConwayTx
garble tx = tx & witsTxL . rdmrsTxWitsL %~ (\(Redeemers m) -> Redeemers (Map.map (\(Data d, units) -> (Data (issue d), units)) m))
  where
    issue = \case
        PLC.Constr 0 [application, PLC.List entries] -> PLC.Constr 0 [application, PLC.List (map entry entries)]
        other -> other
    entry = \case
        PLC.Constr 0 [index, PLC.Constr 0 (PLC.B _ : rest)] -> PLC.Constr 0 [index, PLC.Constr 0 (PLC.B "not an event" : rest)]
        other -> other
