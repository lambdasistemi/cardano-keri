{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.KoiosSubmissionSpec
Description : a signed transaction handed to Koios is resent only as the same bytes, and the handoff says what came of it

Every case runs the handoff against a loopback stand-in for the service that
logs the body of every request it receives. Expected bytes and ids are obtained
from the ledger at run time (the serialization of the signed transaction, its
id), never typed in. A transaction that goes unanswered is played by a service
that takes the request and stays silent past the transport's timeout. Nothing
here calls Koios, reads a token or touches a network beyond the machine.
-}
module Cardano.KERI.Deployment.KoiosSubmissionSpec (spec) where

import Cardano.Crypto.DSIGN (SignKeyDSIGN, genKeyDSIGN)
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.Deployment.KoiosStandIn (
    Reply (..),
    Seen (..),
    answering,
    cutOff,
    silent,
    withStandIn,
    withStandInAt,
    withStandInClosed,
 )
import Cardano.KERI.Deployment.KoiosSubmission (
    Handoff (..),
    HandoffFailure (..),
    HandoffResult (..),
    newKoiosSubmission,
    renderHandoff,
    submitHandoff,
 )
import Cardano.KERI.Deployment.TransactionRuntime (transactionId)
import Cardano.Ledger.Api.Tx (mkBasicTx)
import Cardano.Ledger.Api.Tx.Body (feeTxBodyL, mkBasicTxBody)
import Cardano.Ledger.Binary (decCBOR, decodeFullAnnotator, serialize')
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Core (eraProtVerHigh)
import Cardano.Ledger.TxIn (TxId)
import Cardano.Node.Client.Ledger (ConwayTx)
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Time (NominalDiffTime, diffUTCTime, getCurrentTime)
import Lens.Micro ((&), (.~))
import Singular.Provider.Koios.Client (
    ClientFailure (..),
    FailureReason (..),
    Koios (..),
    SubmitOutcome (..),
    defaultClientConfig,
    submitTx,
 )
import Singular.Provider.Koios.Http (
    HttpConfig (..),
    defaultHttpConfig,
    newHttpTransport,
 )
import Singular.Provider.Koios.Wire (txIdHex)
import Singular.Registry.Signing (SignedTx, signTx, signedTx)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "the Koios submission handoff" $ do
    controlSpec
    answeredSpec
    unansweredSpec
    wiringSpec
    reportSpec
    laterAnswerSpec
    redirectSpec

-- ---------------------------------------------------------------------
-- Material, obtained from the ledger
-- ---------------------------------------------------------------------

testKey :: SignKeyDSIGN Ed25519DSIGN
testKey = genKeyDSIGN (mkSeedFromBytes (BS.replicate 32 7))

-- | A signed transaction; the fee tells two of them apart.
signedWithFee :: Integer -> SignedTx
signedWithFee fee =
    signTx testKey (mkBasicTx (mkBasicTxBody & feeTxBodyL .~ Coin fee) :: ConwayTx)

-- | The serialization of the signed transaction, as the ledger gives it.
bytesOf :: SignedTx -> ByteString
bytesOf = serialize' (eraProtVerHigh @ConwayEra) . signedTx

idOf :: SignedTx -> TxId
idOf = transactionId . signedTx

-- | The body Koios answers an accepted submission with: the id as a JSON string.
acceptedBody :: TxId -> ByteString
acceptedBody txId = "\"" <> TE.encodeUtf8 (txIdHex txId) <> "\""

firstTx, secondTx :: SignedTx
firstTx = signedWithFee 170_000
secondTx = signedWithFee 180_000

-- | Short bounds, so that a silent service costs a fraction of a second.
boundedBy :: Int -> Text -> HttpConfig
boundedBy attempts url =
    (defaultHttpConfig url)
        { httpTimeout = 0.2
        , httpAttempts = attempts
        , httpBaseDelay = 0.01
        , httpMaxDelay = 0.02
        , httpCallCeiling = 30
        }

clientOf :: HttpConfig -> IO (Koios IO)
clientOf config =
    newHttpTransport config >>= \case
        Right transport -> pure (Koios defaultClientConfig transport)
        Left failure -> fail ("the transport did not start: " <> show failure)

-- | The handoff of a signed transaction under bounds, with what the stand-in saw.
handedOver ::
    Int ->
    (Seen -> Int -> Reply) ->
    SignedTx ->
    IO (Handoff, [Seen])
handedOver attempts script tx =
    withStandIn script $ \url seen -> do
        client <- clientOf (boundedBy attempts url)
        handoff <- submitHandoff client tx
        (,) handoff <$> seen

-- | A service that is silent for its first @n@ requests and then answers.
silentThen :: Int -> Reply -> Seen -> Int -> Reply
silentThen n reply _ earlier
    | earlier < n = silent
    | otherwise = reply

-- ---------------------------------------------------------------------
-- An answer at the first attempt
-- ---------------------------------------------------------------------

answeredSpec :: Spec
answeredSpec = describe "a transaction the service answers at once" $ do
    it "is accepted with its own id after one attempt, sent as its serialization" $ do
        (handoff, seen) <- handedOver 5 (\_ _ -> answering 202 (acceptedBody (idOf firstTx))) firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 1 Accepted
        map seenBody seen `shouldBe` [bytesOf firstTx]
        map seenMethod seen `shouldBe` ["POST"]
        map seenPath seen `shouldBe` ["/submittx"]
        [lookup "content-type" (seenHeaders request) | request <- seen] `shouldBe` [Just "application/cbor"]

    it "sends bytes that decode to the signed transaction it was given" $ do
        (_, seen) <- handedOver 5 (\_ _ -> answering 202 (acceptedBody (idOf firstTx))) firstTx
        fmap (decodeFullAnnotator (eraProtVerHigh @ConwayEra) "signed transaction" decCBOR . BSL.fromStrict . seenBody) seen
            `shouldBe` [Right (signedTx firstTx)]

    it "is accepted when the id comes as bare text" $ do
        let bare = TE.encodeUtf8 (txIdHex (idOf firstTx))
        (handoff, _) <- handedOver 5 (\_ _ -> answering 202 bare) firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 1 Accepted

    it "is refused with the provider's text, in one attempt, and never sent again" $ do
        let text = "BadInputsUTxO: the inputs are not unspent"
        (handoff, seen) <- handedOver 5 (\_ _ -> answering 400 text) firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 1 (Refused (TE.decodeUtf8 text))
        length seen `shouldBe` 1

    it "is not resent after any answer that is not an acceptance" $ do
        forM_
            [ (403, "token rejected", RefusedByServer 403 "token rejected")
            , (500, "internal error", ServerFailing 500 "internal error")
            ]
            $ \(status, body, reason) -> do
                (handoff, seen) <- handedOver 5 (\_ _ -> answering status body) firstTx
                handoff `shouldBe` Handoff (idOf firstTx) 1 (Failed (AnsweredUnusably reason))
                length seen `shouldBe` 1

    it "is not resent after a rate-limit answer" $ do
        (handoff, seen) <- handedOver 5 (\_ _ -> answering 429 "slow down") firstTx
        handoffAttempts handoff `shouldBe` 1
        handoffResult handoff `shouldSatisfy` \case
            Failed (AnsweredUnusably (RateLimited _)) -> True
            _ -> False
        length seen `shouldBe` 1

    it "is a named failure when the service accepts another transaction's id" $ do
        (handoff, _) <- handedOver 5 (\_ _ -> answering 202 (acceptedBody (idOf secondTx))) firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 1 (Failed (AcceptedAnotherTransaction (idOf secondTx)))

    it "is a named failure when the answer is cut off, and is not sent again" $ do
        (handoff, seen) <- handedOver 5 (\_ _ -> cutOff (acceptedBody (idOf firstTx))) firstTx
        handoffAttempts handoff `shouldBe` 1
        handoffResult handoff `shouldSatisfy` \case
            Failed (AnsweredUnusably (IncompletePage _)) -> True
            _ -> False
        length seen `shouldBe` 1

    it "is a named failure when the accepted answer is not an id" $ do
        (handoff, seen) <- handedOver 5 (\_ _ -> answering 202 "\"not an id\"") firstTx
        handoffAttempts handoff `shouldBe` 1
        handoffResult handoff `shouldSatisfy` \case
            Failed (AnsweredUnusably (Undecodable _)) -> True
            _ -> False
        length seen `shouldBe` 1

-- ---------------------------------------------------------------------
-- No answer: the same bytes again, within the bound
-- ---------------------------------------------------------------------

unansweredSpec :: Spec
unansweredSpec = describe "a transaction that gets no answer" $ do
    it "is accepted after the attempts that went unanswered, every attempt the same bytes" $
        forM_ [1, 2] $ \silentFor -> do
            (handoff, seen) <-
                handedOver 5 (silentThen silentFor (answering 202 (acceptedBody (idOf firstTx)))) firstTx
            handoff `shouldBe` Handoff (idOf firstTx) (silentFor + 1) Accepted
            map seenBody seen `shouldBe` replicate (silentFor + 1) (bytesOf firstTx)

    it "is refused after unanswered attempts, and the refusal ends it" $ do
        (handoff, seen) <- handedOver 5 (silentThen 2 (answering 400 "refused")) firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 3 (Refused "refused")
        map seenBody seen `shouldBe` replicate 3 (bytesOf firstTx)

    it "gets no answer after the most attempts the bound allows, all the same bytes" $
        forM_ [1, 3] $ \bound -> do
            (handoff, seen) <- handedOver bound (\_ _ -> silent) firstTx
            handoff `shouldBe` Handoff (idOf firstTx) bound NoAnswer
            map seenBody seen `shouldBe` replicate bound (bytesOf firstTx)

    it "gets no answer after the most attempts when the service cannot be reached" $
        withStandInClosed $ \url -> do
            client <- clientOf (boundedBy 3 url)
            handoff <- submitHandoff client firstTx
            handoff `shouldBe` Handoff (idOf firstTx) 3 NoAnswer

    it "starts no attempt past the time bound of the call, short of the attempt bound" $
        withStandIn (\_ _ -> silent) $ \url seen -> do
            client <- clientOf ((boundedBy 10 url){httpCallCeiling = ceiling'})
            begun <- getCurrentTime
            handoff <- submitHandoff client firstTx
            ended <- getCurrentTime
            requests <- seen
            handoffResult handoff `shouldBe` NoAnswer
            handoffAttempts handoff `shouldSatisfy` (\n -> n >= 2 && n < 10)
            length requests `shouldBe` handoffAttempts handoff
            map seenBody requests `shouldBe` replicate (length requests) (bytesOf firstTx)
            -- no attempt reached the service after the bound was spent
            [diffUTCTime (seenAt request) begun | request <- requests]
                `shouldSatisfy` all (< ceiling')
            diffUTCTime ended begun `shouldSatisfy` (< ceiling' + 0.3)

    it "resends each of two transactions through one client as its own bytes only" $
        sharedHandoff (\url -> submitHandoff <$> clientOf (boundedBy 5 url))

-- | The time bound of a call in the cases that exercise it.
ceiling' :: NominalDiffTime
ceiling' = 0.6

-- ---------------------------------------------------------------------
-- The handoff built from a transport configuration
-- ---------------------------------------------------------------------

wiringSpec :: Spec
wiringSpec = describe "the handoff built on the live transport" $ do
    it "resends each of two transactions through one handoff as its own bytes only" $
        sharedHandoff (\url -> newKoiosSubmission (boundedBy 5 url) >>= either (fail . show) pure)

    it "hands a signed transaction over under the configured bounds" $
        withStandIn (silentThen 2 (answering 202 (acceptedBody (idOf firstTx)))) $ \url seen -> do
            built <- newKoiosSubmission (boundedBy 5 url)
            handoff <- either (fail . show) ($ firstTx) built
            handoff `shouldBe` Handoff (idOf firstTx) 3 Accepted
            requests <- seen
            map seenBody requests `shouldBe` replicate 3 (bytesOf firstTx)

    it "reports no answer after the most attempts of its bound" $
        withStandIn (\_ _ -> silent) $ \url _ -> do
            built <- newKoiosSubmission (boundedBy 2 url)
            handoff <- either (fail . show) ($ firstTx) built
            handoff `shouldBe` Handoff (idOf firstTx) 2 NoAnswer

    it "sends nothing when the token file cannot be read" $
        withSystemTempDirectory "koios-submission" $ \scratch ->
            withStandIn (\_ _ -> answering 202 (acceptedBody (idOf firstTx))) $ \url seen -> do
                let missing = scratch <> "/no-token-here"
                built <- newKoiosSubmission ((boundedBy 5 url){httpTokenFile = Just missing})
                case built of
                    Left (TokenFileUnreadable path _) -> path `shouldBe` missing
                    Left other -> expectationFailure ("another failure: " <> show other)
                    Right _ -> expectationFailure "the handoff was built without its token"
                requests <- seen
                length requests `shouldBe` 0

-- ---------------------------------------------------------------------
-- What is reported
-- ---------------------------------------------------------------------

reportSpec :: Spec
reportSpec = describe "the report of a handoff" $ do
    let txId = txIdHex (idOf firstTx)
    it "names the accepted transaction and the attempts" $
        renderHandoff (Handoff (idOf firstTx) 3 Accepted)
            `shouldBe` "accepted by the provider: " <> txId <> " (3 attempts)"

    it "gives the provider's refusal text with the attempts" $
        renderHandoff (Handoff (idOf firstTx) 1 (Refused "BadInputsUTxO"))
            `shouldBe` "refused by the provider after 1 attempt: transaction " <> txId <> ": BadInputsUTxO"

    it "says that no answer may or may not mean the transaction is lost" $
        renderHandoff (Handoff (idOf firstTx) 5 NoAnswer)
            `shouldBe` "no answer after 5 attempts: may or may not have reached the provider; check it before spending again"

    it "names the id the provider accepted when it is not the submitted one" $
        renderHandoff (Handoff (idOf firstTx) 1 (Failed (AcceptedAnotherTransaction (idOf secondTx))))
            `shouldBe` "the provider accepted "
                <> txIdHex (idOf secondTx)
                <> " where "
                <> txId
                <> " was handed over (1 attempt)"

    it "says a request the provider refused was not handed over, with the status" $ do
        let reported =
                renderHandoff
                    ( Handoff
                        (idOf firstTx)
                        1
                        (Failed (AnsweredUnusably (RefusedByServer 403 "token rejected")))
                    )
        reported
            `shouldBe` "not handed over: the provider refused the request with status 403: token rejected (1 attempt)"
        reported `shouldNotSatisfy` T.isInfixOf "may or may not"

    it "names an answer that is neither an acceptance nor a refusal of the request" $ do
        let reported =
                renderHandoff
                    ( Handoff
                        (idOf firstTx)
                        2
                        (Failed (AnsweredUnusably (ServerFailing 500 "internal error")))
                    )
        reported `shouldSatisfy` T.isInfixOf "500"
        reported `shouldSatisfy` T.isInfixOf "internal error"
        reported `shouldSatisfy` T.isInfixOf "2 attempts"
        reported `shouldNotSatisfy` T.isInfixOf "not handed over"

-- ---------------------------------------------------------------------
-- Controls: the stand-in and the expected values, without the handoff
-- ---------------------------------------------------------------------

{- | Singular's own client submits through the stand-in. These pass whatever the
handoff does: they show the stand-in records the bytes the ledger gives, that
its silence is no answer and that the expected values above are the ones a real
submission produces.
-}
controlSpec :: Spec
controlSpec = describe "the stand-in, driven by Singular's client alone" $ do
    it "records the serialization of the signed transaction and answers with its id" $
        withStandIn (\_ _ -> answering 202 (acceptedBody (idOf firstTx))) $ \url seen -> do
            client <- clientOf (boundedBy 5 url)
            outcome <- submitTx client firstTx
            outcome `shouldBe` Right (SubmitAccepted (idOf firstTx))
            requests <- seen
            map seenBody requests `shouldBe` [bytesOf firstTx]

    it "gets a cut-off answer once, as an incomplete answer, and no second request" $
        withStandIn (\_ _ -> cutOff (acceptedBody (idOf firstTx))) $ \url seen -> do
            client <- clientOf (boundedBy 5 url)
            outcome <- submitTx client firstTx
            fmap failureAttempts (either Just (const Nothing) outcome) `shouldBe` Just 1
            fmap (isIncomplete . failureReason) (either Just (const Nothing) outcome) `shouldBe` Just True
            requests <- seen
            length requests `shouldBe` 1
    it "keeps resending past the time of the call when the bound is not set, so the bound is what stops it" $
        withStandIn (\_ _ -> silent) $ \url seen -> do
            client <- clientOf (boundedBy 5 url)
            begun <- getCurrentTime
            _ <- submitTx client firstTx
            requests <- seen
            [diffUTCTime (seenAt request) begun | request <- requests]
                `shouldSatisfy` any (>= ceiling')

    it "takes the request and gives no answer in time, as often as the bound allows" $
        withStandIn (\_ _ -> silent) $ \url seen -> do
            client <- clientOf (boundedBy 3 url)
            outcome <- submitTx client firstTx
            fmap failureAttempts (either Just (const Nothing) outcome) `shouldBe` Just 3
            fmap failureReason (either Just (const Nothing) outcome) `shouldBe` Just TimedOut
            requests <- seen
            length requests `shouldBe` 3

isIncomplete :: FailureReason -> Bool
isIncomplete = \case
    IncompletePage _ -> True
    _ -> False

-- | A service that is silent at the first request of each transaction and then accepts it.
alternating :: Seen -> Int -> Reply
alternating _ earlier = case earlier of
    0 -> silent
    1 -> answering 202 (acceptedBody (idOf firstTx))
    2 -> silent
    _ -> answering 202 (acceptedBody (idOf secondTx))

{- | One handoff, built once, sends two different transactions in turn. Each is
sent twice and every body is the serialization of the transaction sent, never
the other's.
-}
sharedHandoff :: (Text -> IO (SignedTx -> IO Handoff)) -> IO ()
sharedHandoff built =
    withStandIn alternating $ \url seen -> do
        handOver <- built url
        first <- handOver firstTx
        second <- handOver secondTx
        first `shouldBe` Handoff (idOf firstTx) 2 Accepted
        second `shouldBe` Handoff (idOf secondTx) 2 Accepted
        requests <- seen
        map seenBody requests
            `shouldBe` [bytesOf firstTx, bytesOf firstTx, bytesOf secondTx, bytesOf secondTx]
        bytesOf firstTx `shouldNotBe` bytesOf secondTx

-- ---------------------------------------------------------------------
-- A known limit of the pinned transport: a redirect
-- ---------------------------------------------------------------------

{- | The transport's HTTP client follows a redirect itself, inside one attempt,
so a signed transaction can be sent to the service again after the service
answered, and the reported attempts do not count that request. Only the
service's own log shows it. The first case is the control: with no redirect
the reported attempts equal the requests the stand-in received. The second
states what the pinned transport does today; if a later pin makes it stop, the
second case fails on purpose and is to be rewritten.

The token cases observe what a second service, on another port of the same
host or on another loopback address, receives when the first one redirects the
submission to it. The token is a fixed dummy string in a file the case writes.
The control: with no redirect,
the first service receives the token and the second receives no request.
-}
redirectSpec :: Spec
redirectSpec = describe "a redirect from the service, with the pinned transport" $ do
    it "control: with no redirect the reported attempts equal the requests received" $ do
        (handoff, seen) <- handedOver 5 (silentThen 2 (answering 202 (acceptedBody (idOf firstTx)))) firstTx
        handoffAttempts handoff `shouldBe` 3
        length seen `shouldBe` handoffAttempts handoff

    it "a 307 on the submission is followed: two requests received, one attempt reported" $ do
        let redirecting _ earlier
                | earlier == 0 = Reply 0 307 [("Location", "/api/v1/submittx")] "" False
                | otherwise = answering 202 (acceptedBody (idOf firstTx))
        (handoff, seen) <- handedOver 5 redirecting firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 1 Accepted
        map seenBody seen `shouldBe` replicate 2 (bytesOf firstTx)

    describe "the token, a dummy value in a file this check writes" $ do
        let dummy = "dummy-value-for-the-redirect-check.0123456789"
            bearer = "Bearer " <> TE.decodeUtf8 dummy
            authorizationOf =
                map snd . filter ((== "authorization") . fst) . seenHeaders

        it "control: with no redirect the first service gets the token and the second gets no request" $
            withStandIn acceptsFirstTx $ \_ secondSeen ->
                withTokenFile dummy $ \tokenFile ->
                    handedOverWith
                        tokenFile
                        (\_ _ -> answering 202 (acceptedBody (idOf firstTx)))
                        firstTx
                        $ \handoff firstSeen -> do
                            handoff `shouldBe` Handoff (idOf firstTx) 1 Accepted
                            map authorizationOf firstSeen `shouldBe` [[bearer]]
                            secondSeen >>= (`shouldBe` []) . map seenBody

        forM_
            [ ("another port of the same host", withStandIn)
            , ("another loopback address", withStandInAt (127, 0, 0, 2))
            ]
            $ \(place, second) ->
                it ("a 307 to a second service on " <> place <> ": what it receives of the token") $
                    second acceptsFirstTx $ \secondUrl secondSeen ->
                        withTokenFile dummy $ \tokenFile -> do
                            let redirecting _ earlier
                                    | earlier == 0 =
                                        Reply 0 307 [("Location", secondUrl <> "/submittx")] "" False
                                    | otherwise = answering 500 "the first service is asked again"
                            handedOverWith tokenFile redirecting firstTx $ \handoff firstSeen -> do
                                handoff `shouldBe` Handoff (idOf firstTx) 1 Accepted
                                length firstSeen `shouldBe` 1
                                received <- secondSeen
                                map seenBody received `shouldBe` [bytesOf firstTx]
                                map authorizationOf received `shouldBe` [[bearer]]

-- | The script of a second service: it accepts the first transaction.
acceptsFirstTx :: Seen -> Int -> Reply
acceptsFirstTx _ _ = answering 202 (acceptedBody (idOf firstTx))

-- | A file holding a token, which exists only inside the action.
withTokenFile :: ByteString -> (FilePath -> IO a) -> IO a
withTokenFile token action =
    withSystemTempDirectory "koios-handoff-token" $ \scratch -> do
        let path = scratch <> "/token"
        BS.writeFile path token
        action path

{- | The handoff of a signed transaction with a token file, and what the
first stand-in saw.
-}
handedOverWith ::
    FilePath ->
    (Seen -> Int -> Reply) ->
    SignedTx ->
    (Handoff -> [Seen] -> IO a) ->
    IO a
handedOverWith tokenFile script tx observe =
    withStandIn script $ \url seen -> do
        client <-
            clientOf ((boundedBy 5 url){httpTokenFile = Just tokenFile})
        handoff <- submitHandoff client tx
        seen >>= observe handoff

-- ---------------------------------------------------------------------
-- What is reported when an earlier attempt got no answer
-- ---------------------------------------------------------------------

{- | An attempt that got no answer may have delivered the transaction. Whatever
a later attempt is answered, the report keeps saying so; "not handed over" is
said only when no attempt went unanswered.
-}
laterAnswerSpec :: Spec
laterAnswerSpec = describe "the report after an attempt that got no answer" $ do
    let uncertain =
            "; an earlier attempt got no answer: may or may not have reached the provider; check it before spending again"
        txId = txIdHex (idOf firstTx)
    it "keeps the uncertainty beside a refusal" $
        renderHandoff (Handoff (idOf firstTx) 3 (Refused "BadInputsUTxO"))
            `shouldBe` "refused by the provider after 3 attempts: transaction " <> txId <> ": BadInputsUTxO" <> uncertain

    it "keeps the uncertainty beside a refusal of the request by another status" $
        renderHandoff
            (Handoff (idOf firstTx) 2 (Failed (AnsweredUnusably (RefusedByServer 403 "token rejected"))))
            `shouldBe` "the provider refused the request with status 403: token rejected (2 attempts)" <> uncertain

    it "keeps the uncertainty beside an accepted id that is not the transaction's" $
        renderHandoff (Handoff (idOf firstTx) 2 (Failed (AcceptedAnotherTransaction (idOf secondTx))))
            `shouldBe` "the provider accepted "
                <> txIdHex (idOf secondTx)
                <> " where "
                <> txId
                <> " was handed over (2 attempts)"
                <> uncertain

    it "reports a 403 after a timeout as possibly delivered, from the handoff itself" $ do
        (handoff, _) <- handedOver 5 (silentThen 1 (answering 403 "token rejected")) firstTx
        handoff `shouldBe` Handoff (idOf firstTx) 2 (Failed (AnsweredUnusably (RefusedByServer 403 "token rejected")))
        let reported = renderHandoff handoff
        reported `shouldSatisfy` T.isInfixOf "may or may not have reached the provider; check it before spending again"
        reported `shouldNotSatisfy` T.isInfixOf "not handed over"

    it "reports a 403 alone as not handed over, from the handoff itself" $ do
        (handoff, _) <- handedOver 5 (\_ _ -> answering 403 "token rejected") firstTx
        let reported = renderHandoff handoff
        reported
            `shouldBe` "not handed over: the provider refused the request with status 403: token rejected (1 attempt)"
        reported `shouldNotSatisfy` T.isInfixOf "may or may not"
