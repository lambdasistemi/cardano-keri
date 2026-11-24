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
-}
module Cardano.KERI.AID.Reader (
    registryAsset,
    terminationApproval,
    requestShape,
) where

import Cardano.KERI.AID.Application (
    Credential (..),
    RegistryIdentity (..),
    stateTokenName,
    terminationApprovalName,
 )
import Cardano.KERI.AID.Consumer (
    Context (..),
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
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
