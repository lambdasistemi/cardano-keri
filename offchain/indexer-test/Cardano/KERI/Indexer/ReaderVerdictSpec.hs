{- |
Module      : Cardano.KERI.Indexer.ReaderVerdictSpec
Description : The status a booked termination request is read to be (#353)

Layer two of the status component. A request is built as the Conway ledger
output a booking places, serialised as the store holds it, observed through the
store's one observation boundary ('observeOutput'), recognised by the
production 'requestShape', and the custody that recognition gives is handed to
the production 'readerStatus' with the environment the release resolves
('releaseEnvironment') and the release's own context ('releaseContext').

__What executes__: the ledger serialisation, the observation, 'requestShape',
the release's resolution of the environment and 'readerStatus' with its
authentication guard.

__What this test supplies__, and does not establish:

* that the observed output is the only holder of the identifier's asset: a
  single holder is the whole holding observation here, so no holder lookup runs;
* the custody of an output 'requestShape' refuses: the adapter below gives it
  the inconsistent custody the Lean gives a single holder that is neither a
  checkpoint nor a request. No checkpoint custody is chosen, so a live or a
  convicted holder is not exercised here;
* whether the history admits the holder, and the leaf it establishes. No
  history is replayed: the agreement is a supplied Boolean.

It is a representation check of ledger bytes through the production boundaries
that exist on main, not a connected-chain run and not an end-to-end classifier.

The shape controls below (a missing or another identifier's token, a datum
form, another credential) test the refusal of the request shape under the
adapter's supplied custody: the refused output is read as the inconsistent
custody, which the table never decides. A history agreement paired with an
unknown or terminal leaf is a synthetic pair of the table (an agreeing history
that establishes a leaf establishes the active one, @leaf_allows_holder_iff@);
it is exercised as such and named so.
-}
module Cardano.KERI.Indexer.ReaderVerdictSpec (
    spec,
) where

import Cardano.KERI.AID.Application (terminationApprovalName)
import Cardano.KERI.AID.Consumer (
    Context (..),
    Environment (..),
    ObservedOutput,
    Release (..),
    representativeAsset,
 )
import Cardano.KERI.AID.Reader (
    Custody (..),
    Determined (..),
    RegistryLeaf (..),
    Status (..),
    readerStatus,
    requestShape,
    terminationApproval,
 )
import Cardano.KERI.AID.Release (
    ReleaseIdentity (..),
    registryIdentityOf,
    releaseEnvironment,
 )
import Cardano.KERI.Indexer.ReleaseFixtures (
    applicationAddr,
    bookedRequest,
    contextFor,
    datumOf,
    liveFacts,
    observedOutput,
    otherRegistry,
    outputWithDatum,
    requestAssets,
    requestLovelace,
    scriptHashOf,
    testRelease,
 )
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), dataToBinaryData, hashData)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (Credential (ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Test.Hspec (Spec, describe, it, shouldBe)

-- | A raw identifier digest and another.
rawAid, otherRaw :: ByteString
rawAid = BS.replicate 32 0x81
otherRaw = BS.replicate 32 0x82

{- | The custody of a single observed holder that is not a checkpoint, as the
Lean @custodyOf@ reads it: the request when the request shape holds, otherwise
the inconsistent custody. Supplied by this test; it chooses nothing about a
checkpoint.
-}
custodyOfHolder :: Context -> ObservedOutput -> Custody
custodyOfHolder context out
    | requestShape context out = CustodyRequest
    | otherwise = CustodyInconsistent

{- | The status of a ledger output as the sole holder of an identifier's asset,
under an environment, with a supplied history agreement and established leaf.
-}
statusOf ::
    Environment ->
    Context ->
    Bool ->
    Maybe RegistryLeaf ->
    Indexer.TxOut ->
    Status
statusOf environment context admits leaf txOut =
    readerStatus
        environment
        context
        Determined
            { dtCustody = custodyOfHolder context (observedOutput txOut)
            , dtHistoryAdmitsHolder = admits
            , dtEstablishedLeaf = leaf
            }

spec :: Spec
spec = describe "reader status of a booked request (ledger outputs through the observation boundary)" $ do
    let ri = testRelease
        context = contextFor ri rawAid
        environment = releaseEnvironment ri
        booked = bookedRequest ri context
        build = outputWithDatum (applicationAddr ri) (requestLovelace ri)
        status = statusOf environment context
        (activePolicy, activeName) = representativeAsset context
        (approvalPolicy, approvalName) = terminationApproval context

    describe "the booked request" $ do
        it "is read as pending termination when the history agrees with the holder, or none is held" $
            status True Nothing booked `shouldBe` PendingTermination
        it "is read as pending termination with the active leaf an agreeing history establishes" $
            status True (Just LeafActive) booked `shouldBe` PendingTermination
        it "is read as pending termination with an unknown or terminal leaf (synthetic pairs: the table does not read the leaf of a holder)" $
            mapM_
                (\leaf -> (leaf, status True (Just leaf) booked) `shouldBe` (leaf, PendingTermination))
                [LeafUnknown, LeafTerminal]
        it "is read as unavailable when the history contradicts the holder, with no leaf, an unknown or a terminal one" $
            mapM_
                (\leaf -> (leaf, status False leaf booked) `shouldBe` (leaf, Unavailable))
                [Nothing, Just LeafUnknown, Just LeafTerminal]
        it "is read as unavailable for a contradicting history paired with the active leaf (synthetic pair)" $
            status False (Just LeafActive) booked `shouldBe` Unavailable

    describe "the same output with one ledger fact changed is not read as a request (custody as the adapter supplies it)" $ do
        let unavailable name out =
                it ("is unavailable with " <> name) $
                    mapM_
                        (\leaf -> (leaf, status True leaf out) `shouldBe` (leaf, Unavailable))
                        (Nothing : map Just [minBound .. maxBound])
        unavailable
            "a datum hash"
            (build (requestAssets context) (DatumHash (hashData (Data (datumOf (liveFacts rawAid)) :: Data ConwayEra))))
        unavailable
            "an inline datum"
            (build (requestAssets context) (Datum (dataToBinaryData (Data (datumOf (liveFacts rawAid))))))
        unavailable "no approval" (build [(activePolicy, activeName, 1)] NoDatum)
        unavailable "no active token" (build [(approvalPolicy, approvalName, 1)] NoDatum)
        unavailable
            "an approval of quantity two"
            (build [(activePolicy, activeName, 1), (approvalPolicy, approvalName, 2)] NoDatum)
        unavailable
            "a third token"
            (build (requestAssets context <> [(BS.replicate 28 0x71, BS.replicate 5 0x01, 1)]) NoDatum)
        unavailable
            "the approval of another key"
            ( build
                [ (activePolicy, activeName, 1)
                , (approvalPolicy, terminationApprovalName (registryIdentityOf ri) (cxAid (contextFor ri otherRaw)), 1)
                ]
                NoDatum
            )
        unavailable
            "the checkpoint validator's address"
            ( outputWithDatum
                (Addr Testnet (ScriptHashObj (scriptHashOf (riCheckpointValidator ri))) StakeRefNull)
                (requestLovelace ri)
                (requestAssets context)
                NoDatum
            )
        unavailable "the request of another identifier" (bookedRequest ri (contextFor ri otherRaw))
        unavailable "the request of another registry" (bookedRequest otherRegistry (contextFor otherRegistry rawAid))

    describe "an environment that does not authenticate the context" $ do
        let refused name changed =
                it ("reads the booked request as unavailable under " <> name) $
                    statusOf changed context True Nothing booked `shouldBe` Unavailable
        refused "another network" environment{envNetwork = envNetwork environment + 1}
        refused "an unresolved release" environment{envRelease = Nothing}
        refused
            "another release"
            environment{envRelease = Just (riRelease ri){rlApplicationPolicy = BS.replicate 28 0x0d}}
        refused "an unresolved checkpoint credential" environment{envCheckpointCredential = Nothing}
        it "reads the booked request as unavailable for a context of another network" $
            statusOf environment context{cxNetwork = cxNetwork context + 1} True Nothing booked `shouldBe` Unavailable
