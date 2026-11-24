{- |
Module      : Cardano.KERI.AID.Reader
Description : What a reader recognises on one observed output (#353)

The words of the Lean model @CardanoKeri.ReaderStatus@ over one observed
output and a configured identity, as a library operation:

* 'registryAsset' is @registryAsset@: the state policy of the release and the
  name of the state token the seed names;
* 'terminationApproval' is the termination approval of the registry and the
  identifier's key, under the release's application policy;
* 'requestShape' is @requestShape@, which is the public registry's
  @SingularApplicationHeld.terminationShape@ at the pinned revision: the output
  is at the application credential, has no datum, and holds exactly the
  identifier's active token and its termination approval, once each.

Nothing is read of the network, the lovelace, the chain point or any history:
those belong to the authenticated context and to the classifier that calls
this. The operation is pure and trusts nothing it is not given.

An output is at a /script/ credential: the application credential of a release
is a script hash, so a key credential with the same bytes is not the
application (a representation of the Lean's opaque credential number).

The status of an identifier is the Lean @classify@ over three values a producer
has already established from raw evidence, held together as 'Determined': the
custody of the holders, whether the history admits a holder, and the leaf the
history establishes. 'readerStatus' is the outer authentication guard of
@classify@ and the table @verdict@, nothing else: it reads no checkpoint,
chooses no custody, asserts no canonical history and runs no replay. Whoever
supplies a 'Determined' answers for its being what the evidence establishes.
-}
module Cardano.KERI.AID.Reader (
    registryAsset,
    terminationApproval,
    requestShape,

    -- * The status of an identifier
    Status (..),
    Custody (..),
    RegistryLeaf (..),
    Determined (..),
    readerStatus,
) where

import Cardano.KERI.AID.Application (
    Credential (..),
    RegistryIdentity (..),
    stateTokenName,
    terminationApprovalName,
 )
import Cardano.KERI.AID.Consumer (
    Context (..),
    Environment,
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
    authenticated,
    representativeAsset,
 )
import Data.ByteString (ByteString)
import Data.List (nub)

-- | The registry's own asset: its state policy and the name its seed gives the state token.
registryAsset :: Context -> (ByteString, ByteString)
registryAsset Context{cxRelease, cxSeed} =
    (rlStatePolicy cxRelease, stateTokenName cxSeed)

{- | The approval of the termination of the identifier's key in the context's
registry: the release's application policy and the name the registry derives
from the registry identity and the key.
-}
terminationApproval :: Context -> (ByteString, ByteString)
terminationApproval cx@Context{cxRelease, cxAid} =
    ( rlApplicationPolicy cxRelease
    , terminationApprovalName (uncurry RegistryIdentity (registryAsset cx)) cxAid
    )

{- | The output is the termination request of the identifier's key: at the
application credential, with no datum, holding exactly the identifier's active
token once and its termination approval once, and nothing else.
-}
requestShape :: Context -> ObservedOutput -> Bool
requestShape cx@Context{cxRelease} out =
    ooCredential out == ScriptCredential (rlApplicationCredential cxRelease)
        && ooDatum out == DatumAbsent
        && exactAssets
            (ooAssets out)
            [(representativeAsset cx, 1), (terminationApproval cx, 1)]

{- | The summed quantity of every asset the output names or the expectation
names equals the summed expected quantity: the Lean @exactAssets@. An asset
may be listed more than once; quantities add.
-}
exactAssets ::
    [(ByteString, ByteString, Integer)] ->
    [((ByteString, ByteString), Integer)] ->
    Bool
exactAssets held expected =
    all matches (nub (map fst expected <> [(p, n) | (p, n, _) <- held]))
  where
    matches asset =
        sum [q | (p, n, q) <- held, (p, n) == asset]
            == sum [q | (a, q) <- expected, a == asset]

-- | The five outcomes of a read: the Lean @Status@.
data Status
    = Active
    | PendingTermination
    | Terminal
    | NeverRegistered
    | Unavailable
    deriving stock (Eq, Show, Enum, Bounded)

{- | What a holding observation establishes about custody: the Lean @Custody@,
without the facts a live or a convicted checkpoint carries, which the table
does not read.
-}
data Custody
    = -- | No holding observation for the asked point and the identifier's asset.
      CustodyNotEstablished
    | -- | The observation shows no holder.
      CustodyAbsent
    | -- | One holder, a live checkpoint of the identifier.
      CustodyLive
    | -- | One holder, the convicted checkpoint of the identifier.
      CustodyConvicted
    | -- | One holder, the termination request of the identifier's key.
      CustodyRequest
    | -- | Two or more holders, or one the reader does not recognise.
      CustodyInconsistent
    deriving stock (Eq, Show, Enum, Bounded)

{- | A leaf of the registry the history can establish for the identifier's
key: the Lean @Singular.Leaf@. A leaf that is not established is 'Nothing'
where it is carried, never one of these.
-}
data RegistryLeaf
    = LeafUnknown
    | LeafActive
    | LeafTerminal
    deriving stock (Eq, Show, Enum, Bounded)

{- | What a producer has established from raw evidence and the status is
decided from: the Lean arguments of @verdict@.
-}
data Determined = Determined
    { dtCustody :: !Custody
    -- ^ the Lean @holdingCustody@
    , dtHistoryAdmitsHolder :: !Bool
    -- ^ the Lean @historyAdmitsHolder@: 'False' is a history that refuses a holder
    , dtEstablishedLeaf :: !(Maybe RegistryLeaf)
    -- ^ the Lean @establishedLeaf@: 'Nothing' is no leaf established
    }
    deriving stock (Eq, Show)

{- | The reader's answer: the Lean @classify@ over a 'Determined'. An
environment that does not authenticate the context answers 'Unavailable'
whatever else is established.
-}
readerStatus :: Environment -> Context -> Determined -> Status
readerStatus environment context determined
    | authenticated environment context = verdict determined
    | otherwise = Unavailable

{- | The table: the Lean @verdict@, clause for clause and in its order. A
holder the history admits decides alone, whatever leaf was established; with no
holder the established leaf decides, whatever the history says; everything else,
a refused holder included, is 'Unavailable'.
-}
verdict :: Determined -> Status
verdict Determined{dtCustody, dtHistoryAdmitsHolder, dtEstablishedLeaf} =
    case (dtCustody, dtHistoryAdmitsHolder, dtEstablishedLeaf) of
        (CustodyLive, True, _) -> Active
        (CustodyConvicted, True, _) -> PendingTermination
        (CustodyRequest, True, _) -> PendingTermination
        (CustodyNotEstablished, _, Just LeafTerminal) -> Terminal
        (CustodyAbsent, _, Just LeafTerminal) -> Terminal
        (CustodyNotEstablished, _, Just LeafUnknown) -> NeverRegistered
        (CustodyAbsent, _, Just LeafUnknown) -> NeverRegistered
        _ -> Unavailable
