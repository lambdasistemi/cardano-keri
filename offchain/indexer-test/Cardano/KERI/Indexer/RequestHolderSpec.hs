{-# LANGUAGE NumericUnderscores #-}

{- |
Module      : Cardano.KERI.Indexer.RequestHolderSpec
Description : A termination request as the ledger holds it is recognised (#353)

Layer two of the request-shape component. Every output here is built as a
Conway ledger output, serialised as the store holds it, passed through the
store's one observation boundary ('observeOutput') and only then handed to the
production 'requestShape': the same operation layer one drives over the
corpus' observed outputs.

The honest request is the output a booking transaction places: at the
application credential, holding the identifier's active token and the
termination approval once each, with no datum, and the lovelace of the
termination carrier and the tip (the shape @bookTerminationTx@ builds in the
local-chain journeys). The names of its two assets come from the producer
('representativeAsset', 'terminationApproval'), cross-checked against the
approval derivation the application vectors pin; the discriminating controls
change one ledger fact at a time, among them the datum forms the ledger
distinguishes: none, a hash and inline bytes.

A representation check of ledger bytes, not a connected-chain run.
-}
module Cardano.KERI.Indexer.RequestHolderSpec (
    spec,
) where

import Cardano.Crypto.Hash.Class (hashFromBytes)
import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    terminationApprovalName,
 )
import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Consumer (
    Context (..),
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
    representativeAsset,
 )
import Cardano.KERI.AID.Reader (requestShape, terminationApproval)
import Cardano.KERI.AID.Release (
    ReleaseIdentity (..),
    registryIdentityOf,
    releaseContext,
 )
import Cardano.KERI.Indexer.Codecs (
    HoldingRefusal (..),
    Observation (..),
    decodeHoldingOutput,
    observeOutput,
 )
import Cardano.KERI.Indexer.ReleaseFixtures (
    datumOf,
    liveFacts,
    otherRegistry,
    outputWithDatum,
    scriptHashOf,
    testRelease,
    txInAt,
 )
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Api.Scripts.Data (Data (..), Datum (..), dataToBinaryData, hashData)
import Cardano.Ledger.BaseTypes (Network (..))
import Cardano.Ledger.Conway (ConwayEra)
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefNull))
import Cardano.Ledger.Keys (KeyHash (..))
import Cardano.Node.Client.UTxOIndexer.Types qualified as Indexer
import Control.Monad (void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (fromMaybe)
import Test.Hspec (Spec, describe, it, shouldBe)

-- | A raw identifier digest and another.
rawAid, otherRaw :: ByteString
rawAid = BS.replicate 32 0x51
otherRaw = BS.replicate 32 0x52

contextFor :: ReleaseIdentity -> ByteString -> Context
contextFor ri raw = releaseContext ri (qb64Aid raw)

applicationAddr :: ReleaseIdentity -> Addr
applicationAddr ri =
    Addr
        (if riNetwork ri == 0 then Testnet else Mainnet)
        (ScriptHashObj (scriptHashOf (rlApplicationCredential (riRelease ri))))
        StakeRefNull

-- | The lovelace a booking places on a request: the termination carrier and the tip.
requestLovelace :: ReleaseIdentity -> Integer
requestLovelace ri = riTerminationCarrier ri + minimumTip (riApplicationParameters ri)

-- | The two assets of a request of an identity, named by the producer.
requestAssets :: Context -> [(ByteString, ByteString, Integer)]
requestAssets context =
    [ let (p, n) = representativeAsset context in (p, n, 1)
    , let (p, n) = terminationApproval context in (p, n, 1)
    ]

-- | The output a booking transaction places for an identity.
honest :: ReleaseIdentity -> Context -> Indexer.TxOut
honest ri context =
    outputWithDatum (applicationAddr ri) (requestLovelace ri) (requestAssets context) NoDatum

-- | The observed output of a ledger output, through the store's boundary.
observed :: Indexer.TxOut -> ObservedOutput
observed txOut = case observeOutput txOut of
    Right observation -> obsOutput observation
    Left refusal -> error ("the observation refused a built output: " <> show refusal)

recognised :: Context -> Indexer.TxOut -> Bool
recognised context = requestShape context . observed

spec :: Spec
spec = describe "request holder (ledger outputs through the observation boundary)" $ do
    let ri = testRelease
        context = contextFor ri rawAid
        approval = terminationApproval context
        active = representativeAsset context
        build = outputWithDatum (applicationAddr ri) (requestLovelace ri)
        refused name out = it ("refuses " <> name) $ recognised context out `shouldBe` False

    describe "the booked request" $ do
        it "is recognised" $ recognised context (honest ri context) `shouldBe` True
        it "names the approval of the registry and the key, derived by the application vectors' function" $
            approval
                `shouldBe` ( rlApplicationPolicy (riRelease ri)
                           , terminationApprovalName (registryIdentityOf ri) (cxAid context)
                           )
        it "is observed with no datum, at the application script credential" $ do
            let out = observed (honest ri context)
            ooDatum out `shouldBe` DatumAbsent
        it "is not a holding of the checkpoint validator" $
            void (decodeHoldingOutput ri (txInAt 1) (honest ri context))
                `shouldBe` Left NotAtCheckpointValidator
        it "is recognised whatever lovelace it holds" $
            mapM_
                ( \lovelace ->
                    recognised
                        context
                        (outputWithDatum (applicationAddr ri) lovelace (requestAssets context) NoDatum)
                        `shouldBe` True
                )
                [1, requestLovelace ri, 123_456_789_012]
        it "is recognised at the application credential whatever the network of its address" $
            recognised
                context
                ( outputWithDatum
                    (Addr Mainnet (ScriptHashObj (scriptHashOf (rlApplicationCredential (riRelease ri)))) StakeRefNull)
                    (requestLovelace ri)
                    (requestAssets context)
                    NoDatum
                )
                `shouldBe` True

    describe "the datum forms the ledger distinguishes" $ do
        refused "a datum hash" (build (requestAssets context) (DatumHash (hashData (Data (datumOf (liveFacts rawAid)) :: Data ConwayEra))))
        refused
            "an inline datum"
            (build (requestAssets context) (Datum (dataToBinaryData (Data (datumOf (liveFacts rawAid))))))

    describe "the assets" $ do
        let (activePolicy, activeName) = active
            (approvalPolicy, approvalName) = approval
        refused "the approval alone" (build [(approvalPolicy, approvalName, 1)] NoDatum)
        refused "the active token alone" (build [(activePolicy, activeName, 1)] NoDatum)
        refused "no token" (build [] NoDatum)
        refused "an active token of quantity two" (build [(activePolicy, activeName, 2), (approvalPolicy, approvalName, 1)] NoDatum)
        refused "an approval of quantity two" (build [(activePolicy, activeName, 1), (approvalPolicy, approvalName, 2)] NoDatum)
        refused
            "the approval of another key"
            ( build
                [ (activePolicy, activeName, 1)
                , (approvalPolicy, terminationApprovalName (registryIdentityOf ri) (cxAid (contextFor ri otherRaw)), 1)
                ]
                NoDatum
            )
        refused
            "the approval name under the state policy"
            (build [(activePolicy, activeName, 1), (activePolicy, approvalName, 1)] NoDatum)
        refused
            "the approval of another registry"
            ( build
                [ (activePolicy, activeName, 1)
                , let (p, n) = terminationApproval (contextFor otherRegistry rawAid) in (p, n, 1)
                ]
                NoDatum
            )
        refused
            "a third token"
            (build (requestAssets context <> [(BS.replicate 28 0x71, BS.replicate 5 0x01, 1)]) NoDatum)

    describe "the credential" $ do
        refused
            "the checkpoint validator's address"
            ( outputWithDatum
                (Addr Testnet (ScriptHashObj (scriptHashOf (riCheckpointValidator ri))) StakeRefNull)
                (requestLovelace ri)
                (requestAssets context)
                NoDatum
            )
        refused
            "another script address"
            ( outputWithDatum
                (Addr Testnet (ScriptHashObj (scriptHashOf (BS.replicate 28 0x72))) StakeRefNull)
                (requestLovelace ri)
                (requestAssets context)
                NoDatum
            )
        refused
            "a key address with the application credential's bytes"
            ( outputWithDatum
                ( Addr
                    Testnet
                    (KeyHashObj (KeyHash (fromMaybe (error "28 bytes") (hashFromBytes (rlApplicationCredential (riRelease ri))))))
                    StakeRefNull
                )
                (requestLovelace ri)
                (requestAssets context)
                NoDatum
            )

    describe "the identity" $ do
        it "does not recognise the request of another identifier" $
            recognised (contextFor ri otherRaw) (honest ri context) `shouldBe` False
        it "does not recognise the request of another registry" $
            recognised (contextFor otherRegistry rawAid) (honest ri context) `shouldBe` False
        it "recognises each identifier's own request and no other's, over three identifiers" $ do
            let raws = [rawAid, otherRaw, BS.replicate 32 0x53]
            mapM_
                ( \(i, a) ->
                    mapM_
                        ( \(j, b) ->
                            ( i :: Int
                            , j
                            , recognised (contextFor ri a) (honest ri (contextFor ri b))
                            )
                                `shouldBe` (i, j, i == j)
                        )
                        (zip [0 ..] raws)
                )
                (zip [0 ..] raws)
