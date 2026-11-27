{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryFoldNamed
Description : Fold named booked registrations with public Singular's fold

The folder names the booked requests; everything else is public. The registry's state is
rebuilt from the public history of its state token, the requests are read and authenticated
from their public outputs, the batch, its validity window from the provider's tip and its
balance are public Singular's, and the application is "Cardano.KERI.Deployment.RegistryApplication".
This module only joins them to what the registry commands already do after a transaction is
built: sign it, hand it over once, observe it settle, and say how far it got.
-}
module Cardano.KERI.Deployment.RegistryFoldNamed (
    NamedFoldInput (..),
    FoldedRequest (..),
    NamedFoldDone (..),
    NamedFoldStop (..),
    foldNamed,
) where

import Cardano.KERI.AID.Release (ReleaseIdentity)
import Cardano.KERI.Deployment.KoiosRegistryRuntime (KoiosOpened (..))
import Cardano.KERI.Deployment.Registry (RegistryScripts (..))
import Cardano.KERI.Deployment.RegistryApplication (keriApplication)
import Cardano.KERI.Deployment.RegistryChain (
    Attempt (..),
    Loaded (..),
    Refusal,
    RegistryRuntime,
    SubmitError,
    loadDeployment,
    transactBuilt,
    tryNode,
 )
import Cardano.KERI.Deployment.RegistryFiles (ReferenceRecord)
import Cardano.KERI.Deployment.RegistryReplay (singularIdentity)
import Cardano.KERI.Deployment.RegistryTransactions (RegistryDeployment (..), RegistryReferences (..))
import Cardano.KERI.Deployment.Script (Blueprint)
import Cardano.Ledger.Address (Addr)
import Cardano.Ledger.TxIn (TxIn)
import Cardano.Node.Client.Ledger (ConwayTx)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.IORef (newIORef, readIORef, writeIORef)
import Singular.Registry.TxBuilder.Internal (scriptFromBytes)
import Singular.State.Fold (
    FoldFailure (..),
    FoldResult (..),
    PendingRequest (..),
    Request (..),
    SkippedHolder (..),
    attemptFold,
    requestKey,
 )
import Singular.State.Script (ScriptSource (..), StateScript (..))

-- | What the fold is given: the registry's files, the requests it is told to fold and the paying address.
data NamedFoldInput = NamedFoldInput
    { namedBlueprint :: !Blueprint
    , namedIdentity :: !ReleaseIdentity
    , namedRecord :: !ReferenceRecord
    , namedPending :: ![TxIn]
    -- ^ the booked requests to fold, each named by the output that holds it
    , namedPayer :: !Addr
    }

-- | A request the batch folded, as it was read from the public output.
data FoldedRequest = FoldedRequest
    { foldedRef :: !TxIn
    , foldedKeyBytes :: !ByteString
    , foldedKind :: !String
    }
    deriving stock (Eq, Show)

-- | A fold that settled, with what Singular reports of the batch.
data NamedFoldDone = NamedFoldDone
    { doneTransaction :: !ConwayTx
    , doneFolded :: ![FoldedRequest]
    , doneSkipped :: ![(TxIn, String)]
    -- ^ every holder the fold left unspent, with Singular's reason
    , doneLeft :: !Int
    }

-- | Why the fold stopped, before or after it spent anything.
data NamedFoldStop
    = -- | the registry's files do not name a registry this command can fold into
      NamedFilesRefused !Refusal
    | -- | a read of the provider failed
      NamedReadFailed !String
    | -- | the chain could not be read as one session
      NamedNotAcquired !String
    | -- | Singular's fold refused: its reason, and what it had observed of the other holders and the foldable requests left
      NamedFoldRefused !String !(Maybe ([(TxIn, String)], Int))
    | -- | the transaction was built; this is how far it got
      NamedTransaction !SubmitError !(Maybe Attempt)

{- | Fold the named requests: replay, discover and build through Singular, then sign, hand over once
and observe. The attempt callback is told of every step of the handoff, as the other commands' are.
-}
foldNamed ::
    KoiosOpened ->
    (Attempt -> IO ()) ->
    NamedFoldInput ->
    IO (Either NamedFoldStop NamedFoldDone)
foldNamed opened onAttempt input =
    tryNode (loadDeployment runtime (namedBlueprint input) (namedIdentity input) (namedRecord input)) >>= \case
        Left failure -> pure (Left (NamedReadFailed (show failure)))
        Right (Left refusal) -> pure (Left (NamedFilesRefused refusal))
        Right (Right loaded) -> built loaded
  where
    runtime :: RegistryRuntime
    runtime = openedRuntime opened

    built loaded = do
        let deployment = loadedDeployment loaded
            references = loadedReferences loaded
            stateScript =
                StateScript
                    { ssScript = scriptFromBytes "the registry's state script" (scriptsStateProgram (deploymentScripts deployment))
                    , ssSource = Referenced (fst (referenceState references))
                    }
            registry = singularIdentity (scriptsRegistry (deploymentScripts deployment))
        outcome <-
            tryNode . openedAcquire opened $ \session ->
                attemptFold
                    session
                    stateScript
                    (keriApplication deployment references)
                    registry
                    (namedPending input)
                    (namedPayer input)
                    Nothing
        case outcome of
            Left failure -> pure (Left (NamedReadFailed (show failure)))
            Right (Left failure) -> pure (Left (NamedNotAcquired (show failure)))
            Right (Right (Left refusal)) ->
                pure (Left (NamedFoldRefused (show (foldFailureReason refusal)) (fmap (first (map (\h -> (skippedRef h, show (skippedReason h))))) (foldFailureObserved refusal))))
            Right (Right (Right result)) -> do
                last' <- newIORef Nothing
                settled <- transactBuilt runtime (\attempt -> writeIORef last' (Just attempt) >> onAttempt attempt) (foldTransaction result)
                case settled of
                    Left failure -> Left . NamedTransaction failure <$> readIORef last'
                    Right signed ->
                        pure . Right $
                            NamedFoldDone
                                { doneTransaction = signed
                                , doneFolded = map folded (foldSelected result)
                                , doneSkipped = [(skippedRef h, show (skippedReason h)) | h <- foldSkipped result]
                                , doneLeft = foldLeft result
                                }

-- | A request the batch folded, as the fold reports it.
folded :: PendingRequest -> FoldedRequest
folded pending =
    FoldedRequest
        { foldedRef = pendingRef pending
        , foldedKeyBytes = requestKey (pendingRequest pending)
        , foldedKind = case pendingRequest pending of
            RegistrationRequest{} -> "registration"
            TerminationRequest{} -> "termination"
        }
