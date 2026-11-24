{- |
Module      : Cardano.KERI.Deployment.KoiosSubmission
Description : A signed transaction handed to Koios, and what the handoff learned

A signed transaction is handed to Koios, and the handoff ends there: it learns
one of three things and says how many attempts it took.

* the provider accepted it, naming this transaction's id;
* the provider refused it, with its text;
* the provider did not answer in the transport's bound, so the transaction
  may or may not have reached it.

A submission that got no answer (the service unreachable, or silent past the
timeout) is sent again by the transport as the identical signed bytes, within
its bound: the most attempts and the longest time one call may take, both of
the 'HttpConfig'. A refusal is never sent again, and neither is any other
answer. Nothing here builds, signs or changes a transaction: the entry points
take a 'SignedTx' and send its serialization.

It does not settle, confirm, look for the transaction on chain or decide what
comes next; those belong to whatever calls it.

== What the attempt count is, and what it is not

The transport follows up to 10 redirects inside one attempt, and this handoff
does not detect them. Each hop continues the request as it stands: a 302 or
303 turns it into a GET with no body from then on, and any other 3xx keeps its
method and body. So the signed bytes are sent again to each place a 301, 307
or 308 names before any 302 or 303 in the chain. Every hop carries the
request's headers, except that a 302 or 303 also drops the content type. The
attempt count is the transport's count of attempts, not of requests sent. Read
from the transport's source, not reproduced: the count can include an attempt
started with no time left, which sent nothing.
Upstream: <https://github.com/lambdasistemi/singular/issues/819> .
-}
module Cardano.KERI.Deployment.KoiosSubmission (
    -- * The handoff
    Handoff (..),
    HandoffResult (..),
    HandoffFailure (..),
    submitHandoff,
    newKoiosSubmission,

    -- * The report
    renderHandoff,
) where

import Cardano.KERI.Deployment.TransactionRuntime (renderTransactionId, transactionId)
import Cardano.Ledger.TxIn (TxId)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Singular.Provider.Koios.Client (
    ClientFailure (..),
    Exchange (..),
    FailureReason (..),
    Koios (..),
    SubmitOutcome (..),
    Transport (..),
    defaultClientConfig,
    submitTx,
 )
import Singular.Provider.Koios.Http (HttpConfig, newHttpTransport)
import Singular.Registry.Signing (SignedTx, signedTx)

-- | What the handoff of one signed transaction came to.
data Handoff = Handoff
    { handoffTransaction :: !TxId
    -- ^ the transaction that was handed over
    , handoffAttempts :: !Int
    -- ^ the attempts made, the one that was answered included
    , handoffResult :: !HandoffResult
    }
    deriving stock (Eq, Show)

-- | The outcome of a handoff.
data HandoffResult
    = -- | the provider accepted it and named this transaction's id
      Accepted
    | -- | the provider refused it, with its text
      Refused !Text
    | -- | no answer in the bound: the provider may or may not have received it
      NoAnswer
    | -- | the provider answered, and the answer is not an acceptance or a refusal
      Failed !HandoffFailure
    deriving stock (Eq, Show)

-- | An answer that is neither an acceptance nor a refusal of this transaction.
data HandoffFailure
    = -- | the provider accepted a transaction with this other id
      AcceptedAnotherTransaction !TxId
    | -- | the provider answered and the answer cannot be used, in the client's terms
      AnsweredUnusably !FailureReason
    deriving stock (Eq, Show)

{- | Hand a signed transaction to the provider through a client. The transport
of the client resends it when no answer came, within its bound, and the
handoff reports the attempts it made.
-}
submitHandoff :: Koios IO -> SignedTx -> IO Handoff
submitHandoff given signed = do
    made <- newIORef 0
    let counting =
            Transport $ \raw -> do
                exchanged <- exchange (koiosTransport given) raw
                writeIORef made (exchangeAttempts exchanged)
                pure exchanged
    outcome <- submitTx given{koiosTransport = counting} signed
    attempts <- readIORef made
    pure Handoff{handoffTransaction = submitted, handoffAttempts = attempts, handoffResult = resultOf outcome}
  where
    submitted = transactionId (signedTx signed)
    resultOf = \case
        Right (SubmitAccepted returned)
            | returned == submitted -> Accepted
            | otherwise -> Failed (AcceptedAnotherTransaction returned)
        Right (SubmitRefused text) -> Refused text
        Left ClientFailure{failureReason = reason} -> case reason of
            Unreachable _ -> NoAnswer
            TimedOut -> NoAnswer
            _ -> Failed (AnsweredUnusably reason)

{- | The handoff over the live transport of a configuration: its base URL, its
token file (read once, before anything is sent), its timeout and its bound on
attempts and on time. A token file that cannot be read stops it before any
request.
-}
newKoiosSubmission :: HttpConfig -> IO (Either FailureReason (SignedTx -> IO Handoff))
newKoiosSubmission config =
    fmap (submitHandoff . Koios defaultClientConfig) <$> newHttpTransport config

{- | The report of a handoff, in a sentence. A transaction that got no answer to
an attempt may have been delivered by it, so once an attempt went unanswered
the report says so whatever answer a later attempt got; "not handed over" is
said only of a request refused when no attempt went unanswered.
-}
renderHandoff :: Handoff -> Text
renderHandoff Handoff{..} = case handoffResult of
    Accepted -> "accepted by the provider: " <> txId <> " (" <> attempts <> ")"
    Refused text -> "refused by the provider after " <> attempts <> ": " <> text <> earlier
    NoAnswer ->
        "no answer after "
            <> attempts
            <> ": may or may not have reached the provider; check it before spending again"
    Failed (AcceptedAnotherTransaction returned) ->
        "the provider accepted "
            <> renderTransactionId returned
            <> " where "
            <> txId
            <> " was handed over ("
            <> attempts
            <> ")"
            <> earlier
    Failed (AnsweredUnusably (RefusedByServer status text)) ->
        (if unanswered then "" else "not handed over: ")
            <> "the provider refused the request with status "
            <> T.pack (show status)
            <> ": "
            <> text
            <> " ("
            <> attempts
            <> ")"
            <> earlier
    Failed (AnsweredUnusably reason) ->
        "the provider's answer could not be used after "
            <> attempts
            <> ": "
            <> T.pack (show reason)
            <> earlier
  where
    txId = renderTransactionId handoffTransaction
    attempts = T.pack (show handoffAttempts) <> if handoffAttempts == 1 then " attempt" else " attempts"
    -- the transport sends again only when an attempt got no answer, so a second attempt means a first without one
    unanswered = handoffAttempts > 1
    earlier
        | unanswered =
            "; an earlier attempt got no answer: may or may not have reached the provider; check it before spending again"
        | otherwise = ""
