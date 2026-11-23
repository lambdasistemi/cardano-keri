{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryReturnCommandSpec
Description : @ckeri registry return@ over a chain that keeps its outputs

The command is run whole, over the chain of "Cardano.KERI.Deployment.RegistryBookingChain",
in a directory of its own: what it prints before it pays, what it prints as it settles,
what it refuses and at which boundary, what it leaves alone. The words a refusal is made of
are spelled here, and the refund address is spelled as the bech32 text of the address the
booking's wallet holds.
-}
module Cardano.KERI.Deployment.RegistryReturnCommandSpec (spec) where

import Cardano.Crypto.Hash (hashFromBytes)
import Cardano.KERI.AID.Application (HeldDatum (..), RegistrationData (..), heldDatumData)
import Cardano.KERI.AID.E2E.Datum (mkInlineDatum)
import Cardano.KERI.Deployment.LiveRuntime (decodePaymentAddress)
import Cardano.KERI.Deployment.NodeSocketRuntime (NodeAccess (..), RegistryOpener)
import Cardano.KERI.Deployment.RegistryBookingChain
import Cardano.KERI.Deployment.RegistryBookingCommand
import Cardano.KERI.Deployment.RegistryChain (RegistryRuntime (..), feeOf)
import Cardano.KERI.Deployment.RegistryCommandSpec (capturing, capturingLive)
import Cardano.KERI.Deployment.RegistryDeploy (Deployed (..))
import Cardano.KERI.Deployment.RegistryDeploySpec (Faults (..), noFaults, walletAddress)
import Cardano.KERI.Deployment.RegistryFiles (writeDeploymentFiles)
import Cardano.KERI.Deployment.RegistryTransactions (plutusAddressOf)
import Cardano.KERI.Deployment.TransactionRuntime (TransactionRuntime (..), renderTransactionId, transactionId)
import Cardano.Ledger.Address (Addr (..), serialiseAddr)
import Cardano.Ledger.Api.Tx (bodyTxL)
import Cardano.Ledger.Api.Tx.Body (outputsTxBodyL)
import Cardano.Ledger.Api.Tx.Out (addrTxOutL, coinTxOutL, datumTxOutL)
import Cardano.Ledger.BaseTypes (Network (..), TxIx (..))
import Cardano.Ledger.Coin (Coin (..))
import Cardano.Ledger.Credential (Credential (KeyHashObj, ScriptHashObj), StakeReference (StakeRefBase))
import Cardano.Ledger.Hashes (KeyHash (..), ScriptHash (..), unsafeMakeSafeHash)
import Cardano.Ledger.TxIn (TxId (..), TxIn (..))
import Codec.Binary.Bech32 qualified as Bech32
import Control.Exception (try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Either (fromLeft)
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf, stripPrefix)
import Data.Maybe (fromJust)
import Data.Text qualified as T
import Lens.Micro ((.~), (^.))
import System.Directory (createDirectory, listDirectory, withCurrentDirectory)
import System.Environment (getEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr, stdout)
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

-- | A registry with a request booked for the single export, the tip at the first slot the chain shows at the deadline.
returnable :: Bool -> IO (World, TxIn, RegistrationData)
returnable atDeadline = do
    world <- newWorld 1_000
    export <- loadExport "kli-export-single.cesr"
    (request, record) <- bookDirectly world export
    setTip world (if atDeadline then 10_095 else 10_094)
    pure (world, request, record)

-- | The directory of the two deployment files, and the settings that name them and the request.
withSetup :: World -> TxIn -> (FilePath -> RegistryReturnSettings -> IO a) -> IO a
withSetup world request action = withSystemTempDirectory "registry-return-command" $ \scratch -> do
    blueprint <- getEnv "KERI_CHECKPOINT_BLUEPRINT"
    let work = scratch </> "work"
        identityFile = scratch </> "release-identity.json"
        recordFile = scratch </> "reference-outputs.json"
    createDirectory work
    written <-
        writeDeploymentFiles
            identityFile
            recordFile
            (deployedIdentity (worldDeployed world))
            (deployedRecord (worldDeployed world))
    either (fail . show) pure written
    action
        work
        RegistryReturnSettings
            { rnNetworkMagic = 42
            , rnBlueprint = blueprint
            , rnNodeSocket = "no-node.socket"
            , rnFundingAddress = "addr_test1unused"
            , rnSigningKeyFile = "no-key.skey"
            , rnTimeoutSeconds = 5
            , rnReleaseIdentity = identityFile
            , rnReferenceRecord = recordFile
            , rnRequest = T.pack (requestText request)
            }

-- | The opener over a world, with the payer the command is given and a note of how it was reached.
openerOver :: Faults -> World -> Addr -> IO (RegistryOpener, IO [NodeAccess])
openerOver faults world payer = do
    reached <- newIORef []
    pure
        ( \access use -> do
            modifyIORef' reached (access :)
            use (runtimeOf faults world, payer)
        , reverse <$> readIORef reached
        )

runCaptured :: IO () -> IO (ExitCode, String, String)
runCaptured action = do
    ((outcome, out), err) <- capturing stderr (capturing stdout (try @ExitCode action))
    pure (fromLeft ExitSuccess outcome, out, err)

requestText :: TxIn -> String
requestText (TxIn txId (TxIx ix)) = T.unpack (renderTransactionId txId) <> "#" <> show ix

-- | An address as the bech32 text of its bytes, with the testnet's human-readable part.
bech32Of :: Addr -> String
bech32Of address = case Bech32.humanReadablePartFromText "addr_test" of
    Right hrp -> either (error . show) T.unpack (Bech32.encode hrp (Bech32.dataPartFromBytes (serialiseAddr address)))
    Left failure -> error (show failure)

zeroLine :: String
zeroLine = "nothing was submitted; nothing was spent"

spec :: Spec
spec = describe "#351 ckeri registry return" $ around_ withinOneMinute $ do
    describe "a return that settles" $ do
        it "prints the request, the refund address, the amounts and the interval before it pays, then the transaction, the refund output and the fee as it settles" $ do
            (world, request, record) <- returnable True
            withSetup world request $ \directory settings -> do
                (opener, reachedBy) <- openerOver noFaults world folderAddress
                (code, out, err) <- withCurrentDirectory directory (runCaptured (runRegistryReturnWith opener settings))
                code `shouldBe` ExitSuccess
                transactions <- accepted world
                let returnTx = last transactions
                    txText = T.unpack (renderTransactionId (transactionId returnTx))
                    linesOut = lines out
                    position needle = length (takeWhile (not . (needle `isInfixOf`)) linesOut)
                    wanted =
                        [ "return-request: " <> requestText request
                        , "refund-address: " <> bech32Of walletAddress
                        , "refund-lovelace: 1010000000"
                        , "tip-lovelace: 500000"
                        , "validity-interval-slots: 10095..10100"
                        , "validity-interval-ms: 1800010095000..1800010100000"
                        , "deadline-ms: " <> show (requestProcessDeadline record)
                        , "return-transaction: " <> txText
                        , "refund-output: " <> txText <> "#0"
                        , "return-fee: " <> show (feeOf returnTx)
                        ]
                mapM_ (\line -> (line, line `elem` linesOut) `shouldBe` (line, True)) wanted
                -- the refund goes to the booking's wallet, which is not the wallet that pays
                out `shouldSatisfy` (not . (bech32Of folderAddress `isInfixOf`))
                requestProcessDeadline record `shouldBe` 1_800_010_095_000
                -- in the order they happen: what will be paid, then the handoff, then what settled
                (position "refund-address" < position "handing return") `shouldBe` True
                (position "refund-lovelace" < position "handing return") `shouldBe` True
                (position "tip-lovelace" < position "handing return") `shouldBe` True
                (position "handing return " < position "return-transaction") `shouldBe` True
                (position "return-transaction" < position "refund-output") `shouldBe` True
                err `shouldSatisfy` ("ckeri: not for mainnet" `isInfixOf`)
                reachedBy >>= (`shouldBe` [NodeAccess 42 "no-node.socket" "addr_test1unused" "no-key.skey" 5])
                listDirectory directory >>= (`shouldBe` [])
        it "flushes what it will pay before the return is submitted, so whoever pipes it has it first" $ do
            (world, request, _) <- returnable True
            withSetup world request $ \directory settings -> do
                (opener, _) <- openerOver noFaults world folderAddress
                (liveAtSubmission, _) <-
                    capturingLive stdout $ \readLive -> do
                        seen <- newIORef ""
                        let probed access use =
                                opener access $ \(runtime, payer) ->
                                    use
                                        ( runtime
                                            { rtTransactions =
                                                (rtTransactions runtime)
                                                    { trSubmit = \tx -> do
                                                        readLive >>= writeIORef seen
                                                        trSubmit (rtTransactions runtime) tx
                                                    }
                                            }
                                        , payer
                                        )
                        _ <- withCurrentDirectory directory (try @ExitCode (runRegistryReturnWith probed settings))
                        readIORef seen
                liveAtSubmission `shouldSatisfy` (("refund-address: " <> bech32Of walletAddress) `isInfixOf`)
                liveAtSubmission `shouldSatisfy` ("refund-lovelace: 1010000000" `isInfixOf`)
                liveAtSubmission `shouldSatisfy` ("tip-lovelace: 500000" `isInfixOf`)
                liveAtSubmission `shouldSatisfy` (not . ("return-transaction" `isInfixOf`))
        it "returns a request whose refund address has a stake part, as the address of an ordinary wallet does: the whole address is printed, and the refund is paid to it"
            $ forM_
                [ Addr Testnet (KeyHashObj (KeyHash (hashOf 0x11))) (StakeRefBase (KeyHashObj (KeyHash (hashOf 0x22))))
                , Addr Testnet (ScriptHashObj (ScriptHash (hashOf 0x33))) (StakeRefBase (ScriptHashObj (ScriptHash (hashOf 0x44))))
                ]
            $ \named -> do
                (world, request, record) <- returnable True
                reshape world request $
                    datumTxOutL .~ mkInlineDatum (heldDatumData (Registration record{requestRefundAddress = plutusAddressOf named}))
                withSetup world request $ \directory settings -> do
                    (opener, _) <- openerOver noFaults world folderAddress
                    (code, out, _) <- withCurrentDirectory directory (runCaptured (runRegistryReturnWith opener settings))
                    code `shouldBe` ExitSuccess
                    -- the address printed is the whole address: it decodes back to the one the request names
                    [text | line <- lines out, Just text <- [stripPrefix "refund-address: " line]] `shouldSatisfy` \printed ->
                        map (decodePaymentAddress . T.pack) printed == [Right named]
                    transactions <- accepted world
                    case toList (last transactions ^. bodyTxL . outputsTxBodyL) of
                        refund : _ -> do
                            refund ^. addrTxOutL `shouldBe` named
                            refund ^. coinTxOutL `shouldBe` Coin 1_010_000_000
                        [] -> expectationFailure "the return has no output"
    describe "a return it refuses by name before any transaction, as the command's refusal" $ do
        let refuses label prepare needles = it label $ do
                (world, request, record) <- returnable False
                target <- prepare world request record
                sent0 <- submissionsMade world
                withSetup world target $ \directory settings -> do
                    (opener, _) <- openerOver noFaults world folderAddress
                    (code, out, err) <- withCurrentDirectory directory (runCaptured (runRegistryReturnWith opener settings))
                    code `shouldBe` ExitFailure 1
                    err `shouldSatisfy` ("refused by the command, before any transaction" `isInfixOf`)
                    err `shouldSatisfy` (zeroLine `isInfixOf`)
                    mapM_ (\needle -> (needle, needle `isInfixOf` err) `shouldBe` (needle, True)) needles
                    out `shouldSatisfy` (not . ("handing return" `isInfixOf`))
                    submissionsMade world >>= (`shouldBe` sent0)
                    listDirectory directory >>= (`shouldBe` [])
        refuses
            "before the deadline: the chain's tip slot starts before it and so does the clock"
            (\_ request _ -> pure request)
            [ "deadline-not-reached"
            , "1800010094000"
            , "1800010094100"
            , "1800010095000"
            , "can be returned from 1800010095000 ms"
            ]
        refuses
            "when the clock reads the deadline as reached and the chain does not: the conflict is named with the three readings, and left undetermined"
            (\world request _ -> advanceClock world 1_000 >> pure request)
            [ "time-evidence-conflicts"
            , "1800010094000"
            , "1800010095100"
            , "1800010095000"
            , "undetermined"
            ]
        refuses
            "an output that holds the datum of a request and not the approval the booking minted"
            (\world request _ -> setTip world 10_095 >> stripApproval world request)
            ["request-has-no-approval"]
        refuses
            "an output the node does not hold"
            (\world _ _ -> setTip world 10_095 >> pure (TxIn (unsafeTxId 0x99) (TxIx 0)))
            ["request-unavailable"]
        it "a request reference that is not one, before the node is reached" $ do
            (world, request, _) <- returnable True
            withSetup world request $ \directory settings -> do
                (opener, reachedBy) <- openerOver noFaults world folderAddress
                (code, _, err) <- withCurrentDirectory directory (runCaptured (runRegistryReturnWith opener settings{rnRequest = "not-a-reference"}))
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("request-reference-invalid" `isInfixOf`)
                err `shouldSatisfy` (zeroLine `isInfixOf`)
                reachedBy >>= (`shouldBe` [])
    describe "a return that stops" $
        it "says how far its transaction got when the node refused it, and that it is not retried" $ do
            (world, request, _) <- returnable True
            calls <- newIORef (0 :: Int)
            sent0 <- submissionsMade world
            withSetup world request $ \directory settings -> do
                (opener0, _) <- openerOver noFaults{rejectSubmissionAt = Just sent0} world folderAddress
                let opener access use = opener0 access (\(runtime, payer) -> use (countHandoffsInto calls runtime, payer))
                (code, _, err) <- withCurrentDirectory directory (runCaptured (runRegistryReturnWith opener settings))
                code `shouldBe` ExitFailure 1
                err `shouldSatisfy` ("was refused by the node: the node refuses this transaction; it is not on chain" `isInfixOf`)
                err `shouldSatisfy` ("not retried" `isInfixOf`)
                err `shouldSatisfy` (not . (zeroLine `isInfixOf`))
                -- the command called for one handoff, and not for a second
                readIORef calls >>= (`shouldBe` 1)
  where
    unsafeTxId n = TxId (unsafeMakeSafeHash (fromJust (hashFromBytes (BS.replicate 32 n))))
    hashOf n = fromJust (hashFromBytes (BS.replicate 28 n))
