{- |
Module      : Cardano.KERI.AID.RequestShapeSpec
Description : The reader recognises a booked termination request (#353)

Layer one of the request-shape component. It consumes the frozen reader corpus
@lean\/reader-status-vectors.json@ (a byte copy under the fixtures, checked
against the Lean file whenever the repository is present) and drives the
production 'requestShape' over the holder of every row whose holding
observation is established for the asked point and the identifier's
representative asset: the component must agree with the corpus' own custody
answer, which the Lean @custodyOf@ derives from the same predicate
(@ReaderStatus.requestShape@, over the pinned @terminationShape@).

Nothing here types the bytes of a request: the holder is the corpus' output,
the assets the component must find in it come from the producer
('representativeAsset', 'terminationApproval'), and each boundary control is a
mutation of the corpus' own positive holder.
-}
module Cardano.KERI.AID.RequestShapeSpec (
    spec,
) where

import Cardano.KERI.AID.Application (Credential (..), OutputReference (..))
import Cardano.KERI.AID.Consumer (
    Context (..),
    ObservedOutput (..),
    OutputDatum (..),
    Release (..),
    representativeAsset,
 )
import Cardano.KERI.AID.Reader (
    registryAsset,
    requestShape,
    terminationApproval,
 )
import Cardano.KERI.AID.ReaderCorpus (
    Corpus (..),
    Holding (..),
    Row (..),
    fixtureName,
    loadCorpus,
    rowNamed,
 )
import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (nub, sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Paths_cardano_keri (getDataFileName)
import System.Directory (doesFileExist)
import Test.Hspec (
    Spec,
    describe,
    it,
    runIO,
    shouldBe,
    shouldSatisfy,
 )

-- ---------------------------------------------------------
-- The selection the component is driven over
-- ---------------------------------------------------------

{- | The holder of a row the way @ReaderStatus.holdingCustody@ reads it: the
holding observation is established for the asked point and the identifier's
representative asset, and names one output.
-}
establishedHolder :: Context -> Row -> Maybe ObservedOutput
establishedHolder context row = case rowHolding row of
    Just holding
        | hoPoint holding == rowPoint row
        , hoAsset holding == representativeAsset context
        , [holder] <- hoHolders holding ->
            Just holder
    _ -> Nothing

-- | The five rows of the story, no history, and what they are.
namedRows :: [Text]
namedRows =
    [ "pending-requested"
    , "request-with-another-approval"
    , "request-without-approval"
    , "request-with-datum"
    , "request-at-another-credential"
    ]

-- ---------------------------------------------------------
-- Controls on the corpus' own positive holder
-- ---------------------------------------------------------

setQuantity :: (ByteString, ByteString) -> Integer -> ObservedOutput -> ObservedOutput
setQuantity (policy, name) quantity out =
    out
        { ooAssets =
            [ if (p, n) == (policy, name) then (p, n, quantity) else entry
            | entry@(p, n, _) <- ooAssets out
            ]
        }

without :: (ByteString, ByteString) -> ObservedOutput -> ObservedOutput
without (policy, name) out =
    out{ooAssets = [e | e@(p, n, _) <- ooAssets out, (p, n) /= (policy, name)]}

withEntry :: (ByteString, ByteString, Integer) -> ObservedOutput -> ObservedOutput
withEntry entry out = out{ooAssets = ooAssets out <> [entry]}

-- | The request the producer builds for an identity: its two assets, at the application credential, no datum.
requestOf :: Context -> ObservedOutput
requestOf context =
    ObservedOutput
        { ooCredential = ScriptCredential (rlApplicationCredential (cxRelease context))
        , ooAssets =
            [ let (p, n) = representativeAsset context in (p, n, 1)
            , let (p, n) = terminationApproval context in (p, n, 1)
            ]
        , ooDatum = DatumAbsent
        }

-- ---------------------------------------------------------

spec :: Spec
spec = describe "request shape (reader-status-vectors.json)" $ do
    corpus <- runIO loadCorpus
    let context = cpContext corpus
        rows = cpRows corpus
        positive =
            fromMaybe (error "pending-requested holds no established holder") $
                establishedHolder context (rowNamed corpus "pending-requested")

    describe "the corpus" $ do
        it "is the frozen reader corpus: 72 rows with distinct names" $ do
            length rows `shouldBe` 72
            length (nub (map rowId rows)) `shouldBe` 72
        it "holds the five rows of the story, each once" $
            mapM_ (\i -> length [() | r <- rows, rowId r == i] `shouldBe` 1) namedRows
        it "is the Lean file byte for byte, where the repository is present" $ do
            let leanPath = "../lean/reader-status-vectors.json"
            present <- doesFileExist leanPath
            when present $ do
                here <- getDataFileName fixtureName >>= BS.readFile
                there <- BS.readFile leanPath
                here `shouldBe` there

    describe "the assets the producer derives" $ do
        it "the identifier's key is the corpus' own: the text of the identifier" $
            cxAid context `shouldBe` cpDerivedKey corpus
        it "the representative asset is the corpus' own" $
            representativeAsset context `shouldBe` cpDerivedRepresentative corpus
        it "the registry asset is the corpus' own" $
            registryAsset context `shouldBe` cpDerivedRegistry corpus
        it "the termination approval is the corpus' own, under the application policy" $ do
            terminationApproval context `shouldBe` cpDerivedApproval corpus
            fst (terminationApproval context)
                `shouldBe` rlApplicationPolicy (cxRelease context)

    describe "the five rows without history" $
        mapM_
            ( \identifier -> it (T.unpack identifier) $ do
                let row = rowNamed corpus identifier
                    holder = establishedHolder context row
                holder `shouldSatisfy` (/= Nothing)
                fmap (requestShape context) holder
                    `shouldBe` Just (rowCustody row == "request")
            )
            namedRows

    describe "the positive row" $ do
        it "is a request in the corpus' own answer" $
            rowCustody (rowNamed corpus "pending-requested") `shouldBe` "request"
        it "is recognised" $ requestShape context positive `shouldBe` True

    describe "every row whose holder is established" $ do
        let established = [(r, h) | r <- rows, Just h <- [establishedHolder context r]]
        it "reads custody request exactly where the corpus does" $
            mapM_
                (\(r, h) -> (rowId r, requestShape context h) `shouldBe` (rowId r, rowCustody r == "request"))
                established
        it "covers both answers, several rows each" $ do
            length [() | (r, _) <- established, rowCustody r == "request"] `shouldSatisfy` (>= 3)
            length [() | (r, _) <- established, rowCustody r /= "request"] `shouldSatisfy` (>= 10)
        it "meets more than one custody word" $
            length (nub (sort [rowCustody r | (r, _) <- established])) `shouldSatisfy` (>= 3)

    describe "boundary controls on the positive holder" $ do
        let active = representativeAsset context
            approval = terminationApproval context
            refused name out = it ("refuses " <> name) $ requestShape context out `shouldBe` False
            accepted name out = it ("keeps recognising " <> name) $ requestShape context out `shouldBe` True
        refused "no active token" (without active positive)
        refused "an active token of quantity zero" (setQuantity active 0 positive)
        refused "an active token of quantity two" (setQuantity active 2 positive)
        refused "no approval" (without approval positive)
        refused "an approval of quantity zero" (setQuantity approval 0 positive)
        refused "an approval of quantity two" (setQuantity approval 2 positive)
        refused "the active token listed twice" (withEntry (fst active, snd active, 1) positive)
        refused "an unrelated token beside the two" (withEntry (BS.replicate 28 0x09, BS.replicate 4 0x01, 1) positive)
        refused
            "the approval name under the state policy"
            (withEntry (fst active, snd approval, 1) (without approval positive))
        refused "a datum of inline bytes" positive{ooDatum = DatumInline BS.empty}
        refused "a datum hash" positive{ooDatum = DatumByHash (BS.replicate 32 0x07)}
        refused "the checkpoint credential" positive{ooCredential = cxCheckpointCredential context}
        refused
            "a key credential with the application credential's bytes"
            positive{ooCredential = KeyCredential (rlApplicationCredential (cxRelease context))}
        refused
            "another script credential"
            positive{ooCredential = ScriptCredential (BS.replicate 28 0x0a)}
        accepted "the lines in the other order" positive{ooAssets = reverse (ooAssets positive)}
        accepted
            "an active token split into two lines of one and zero"
            (withEntry (fst active, snd active, 0) positive)
        accepted
            "an unrelated token of quantity zero"
            (withEntry (BS.replicate 28 0x09, BS.replicate 4 0x01, 0) positive)
        it "refuses another identifier's request" $
            requestShape context{cxAid = BC.pack "EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo"} positive
                `shouldBe` False
        it "refuses the request of another registry" $
            requestShape
                context{cxSeed = OutputReference (BS.replicate 32 0x0b) 0}
                positive
                `shouldBe` False

    describe "requests built from the producer's assets, over several identities" $ do
        let aids = map BC.pack ["EEBjyTcVHGUZHrR1x3wuxOxbrzH0_cGfAYJJQHME3Pwo", "EMMcQtoqOkACLvyswJTFXUQmRbZhWt4ALjjhXzLGhr5P", "EJy0N3PMSxlZ0cCRR3HGCl2SF53FmTSw_ftRMfqpPQ6a"]
            contexts = [context{cxAid = a} | a <- aids]
        it "each identity recognises its own request and no other's" $
            mapM_
                ( \(i, c) ->
                    mapM_
                        ( \(j, d) ->
                            (i, j, requestShape c (requestOf d)) `shouldBe` (i, j, i == j)
                        )
                        (zip [0 :: Int ..] contexts)
                )
                (zip [0 :: Int ..] contexts)
