{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryProviderSpec
Description : a registry command runs on exactly one provider, and its reports name the other end as it is

The choice is a node socket, or a Koios URL with an optional token file;
anything else is refused by name. The reports of a run on Koios are the node's
reports with the one noun changed, and the handoff report counts the attempts
and says what the count is.
-}
module Cardano.KERI.Deployment.RegistryProviderSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.Deployment.KoiosSubmission (Handoff (..), HandoffResult (..), renderHandoff)
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing)
import Cardano.KERI.Deployment.RegistryProvider
import Cardano.Ledger.Hashes (unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..))
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (isInfixOf, isPrefixOf)
import Data.Maybe (fromJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.IO (stdout)
import Test.Hspec

spec :: Spec
spec = describe "#546 the provider a registry command runs on" $ do
    resolveSpec
    nodeOnlySpec
    namesSpec
    wordingSpec
    handoffReportSpec

socket, koios :: ProviderChoice
socket = ProviderChoice (Just "node.socket") Nothing Nothing Nothing
koios = ProviderChoice Nothing (Just "https://koios.example/api/v1") Nothing Nothing

resolveSpec :: Spec
resolveSpec = describe "the choice of a command that can run on either" $ do
    it "is the node socket when only that is given" $
        resolveProvider socket `shouldBe` Right (OnNode "node.socket")
    it "is the Koios service, without a token file, when only its URL is given" $
        resolveProvider koios `shouldBe` Right (OnKoios "https://koios.example/api/v1" Nothing)
    it "is the Koios service with its token file when both are given" $
        resolveProvider koios{chosenKoiosTokenFile = Just "token"}
            `shouldBe` Right (OnKoios "https://koios.example/api/v1" (Just "token"))
    it "is refused when both a node socket and a Koios URL are given, with or without a token file" $ do
        resolveProvider socket{chosenKoiosUrl = Just "https://koios.example/api/v1"} `shouldBe` Left BothProviders
        resolveProvider socket{chosenKoiosUrl = Just "u", chosenKoiosTokenFile = Just "t"} `shouldBe` Left BothProviders
    it "is refused when neither is given" $ do
        resolveProvider (ProviderChoice Nothing Nothing Nothing Nothing) `shouldBe` Left NoProvider
        resolveProvider (ProviderChoice Nothing Nothing (Just "token") Nothing) `shouldBe` Left NoProvider
    it "is refused when a token file goes with a node socket and no Koios URL" $
        resolveProvider socket{chosenKoiosTokenFile = Just "token"} `shouldBe` Left TokenFileWithoutKoios

nodeOnlySpec :: Spec
nodeOnlySpec = describe "the choice of a command that runs on the node only" $ do
    it "is the node socket" $
        resolveNodeProvider socket `shouldBe` Right "node.socket"
    it "refuses anything that names Koios, whether or not a node socket is also given" $ do
        resolveNodeProvider koios `shouldBe` Left FoldRunsOnTheNodeOnly
        resolveNodeProvider koios{chosenKoiosTokenFile = Just "token"} `shouldBe` Left FoldRunsOnTheNodeOnly
        resolveNodeProvider socket{chosenKoiosUrl = Just "u"} `shouldBe` Left FoldRunsOnTheNodeOnly
        resolveNodeProvider socket{chosenKoiosTokenFile = Just "t"} `shouldBe` Left FoldRunsOnTheNodeOnly
    it "is refused when nothing is given" $
        resolveNodeProvider (ProviderChoice Nothing Nothing Nothing Nothing) `shouldBe` Left NoProvider

namesSpec :: Spec
namesSpec = describe "each refusal" $
    it "begins with its name, then says what to give" $ do
        let named =
                [ (BothProviders, "provider-both-given: ")
                , (NoProvider, "provider-none-given: ")
                , (TokenFileWithoutKoios, "koios-token-file-without-koios-url: ")
                , (FoldRunsOnTheNodeOnly, "fold-runs-on-the-node-only: ")
                ]
        mapM_ (\(refusal, prefix) -> renderProviderRefusal refusal `shouldSatisfy` (prefix `isPrefixOf`)) named
        renderProviderRefusal NoProvider `shouldSatisfy` ("--koios-url" `isInfixOf`)
        renderProviderRefusal NoProvider `shouldSatisfy` ("--node-socket" `isInfixOf`)

wordingSpec :: Spec
wordingSpec = describe "the noun for the other end" $ do
    it "is the node on the node socket and the provider on Koios" $ do
        counterpartOf (OnNode "s") `shouldBe` TheNode
        counterpartOf (OnKoios "u" Nothing) `shouldBe` TheProvider
    it "leaves a node report as it is" $
        forCounterpart TheNode "booking x was refused by the node: y; it is not on chain"
            `shouldBe` "booking x was refused by the node: y; it is not on chain"
    it "names the provider where a report names the node, the local evaluation where it names the node's evaluation, and changes nothing else" $ do
        forCounterpart TheProvider "booking x was refused by the node: y; it is not on chain"
            `shouldBe` "booking x was refused by the provider: y; it is not on chain"
        forCounterpart TheProvider "refused by the node's evaluation of the transaction"
            `shouldBe` "refused by the local evaluation of the transaction"
        forCounterpart TheProvider "ckeri: registry register stopped, refused by the node's evaluation of the transaction: the node's evaluation refused the booking: the application's minting purpose"
            `shouldBe` "ckeri: registry register stopped, refused by the local evaluation of the transaction: the local evaluation refused the booking: the application's minting purpose"
        forCounterpart TheProvider "ckeri: registry register stopped, the node could not be read: z"
            `shouldBe` "ckeri: registry register stopped, the provider could not be read: z"
        forCounterpart TheProvider "handing booking x to the node"
            `shouldBe` "handing booking x to the provider"
        forCounterpart TheProvider "refused by the ledger" `shouldBe` "refused by the provider"
        forCounterpart TheNode "refused by the ledger" `shouldBe` "refused by the ledger"
    it "keeps what was marked whatever characters it holds, the marks themselves included, for either end" $
        forM_ ["\xE001the node rejected", "a\xE000the node", "\xE000\xE001the node\xE001", "the node\xE001\xE001", "", "\xE001"] $ \said -> do
            let line = "was refused by the node: " <> evidence said <> "; the node"
            forCounterpart TheProvider line `shouldBe` "was refused by the provider: " <> said <> "; the provider"
            forCounterpart TheNode line `shouldBe` "was refused by the node: " <> said <> "; the node"
    it "reads the bytes of a refusal as UTF-8 text" $
        reasonText (TE.encodeUtf8 "d\233p\244t refus\233") `shouldBe` "d\233p\244t refus\233"
    it "keeps what the provider said word for word, for either end, and takes its marks off" $ do
        let said = "the node rejected the spending input, refused by the ledger"
            line = "booking x was refused by the node: " <> evidence said <> "; it is not on chain"
        forCounterpart TheProvider line `shouldBe` "booking x was refused by the provider: " <> said <> "; it is not on chain"
        forCounterpart TheNode line `shouldBe` "booking x was refused by the node: " <> said <> "; it is not on chain"

handoffReportSpec :: Spec
handoffReportSpec = describe "the report of a handoff" $ do
    let txId = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 5))))
    it "counts the attempts and says what the count is, with the issue that reports the limit" $ do
        let handoff = Handoff txId 3 Accepted
        ((), out) <- capturing stdout (printHandoffReport handoff)
        let reported = lines out
        case reported of
            [counted, limits] -> do
                counted `shouldBe` "provider-handoff: " <> T.unpack (renderHandoff handoff)
                limits `shouldSatisfy` ("provider-handoff-limits: " `isPrefixOf`)
                limits `shouldSatisfy` ("the attempt count is the transport's" `isInfixOf`)
                limits `shouldSatisfy` ("a redirect the provider answers is followed inside one attempt and is not detected" `isInfixOf`)
                limits `shouldSatisfy` ("https://github.com/lambdasistemi/singular/issues/819" `isInfixOf`)
            other -> expectationFailure ("two lines were wanted: " <> show other)
    it "says the same of a handoff that got no answer" $ do
        let handoff = Handoff txId 5 NoAnswer
        ((), out) <- capturing stdout (printHandoffReport handoff)
        take 1 (lines out) `shouldBe` ["provider-handoff: " <> T.unpack (renderHandoff handoff)]
