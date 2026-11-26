{- |
Module      : Main
Description : the owner-auth vectors on standard output, and the attestation corpus regenerated for both consumers

@cabal run gen-vectors@, from @offchain/@, prints the owner-auth vectors on
standard output as it always has, and regenerates the booking attestation corpus
(the Aiken module @onchain/lib/cardano_keri/application/attestation_vectors.ak@ and the
fixture @offchain/test/keri-fixtures/fixtures/attestation-vectors.json@) by running
@scripts/attestation-vectors.mjs@. That generator holds the independent oracle (its own
Plutus Data writer and BLAKE2b-256), which this program deliberately does not
replace with the encoders it would be checking; the hosted drift step and
@just check-attestation-vectors@ run the same generator with @--check@.
-}
module Main (main) where

import Cardano.Crypto.DSIGN (
    SignKeyDSIGN,
    deriveVerKeyDSIGN,
    genKeyDSIGN,
    rawSerialiseSigDSIGN,
    rawSerialiseVerKeyDSIGN,
    signDSIGN,
 )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Crypto.Hash.Blake2b (Blake2b_256)
import Cardano.Crypto.Hash.Class (digest)
import Cardano.Crypto.Seed (mkSeedFromBytes)
import Cardano.KERI.AID.Cage.Sign (valueWriteMessage)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Proxy (Proxy (..))
import Data.Word (Word8)
import Numeric (showHex)
import System.Directory (doesFileExist)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc, waitForProcess)

blake :: ByteString -> ByteString
blake = digest (Proxy @Blake2b_256)

-- Aiken MPF combine: blake2b_256(a ++ b)
combine :: ByteString -> ByteString -> ByteString
combine a b = blake (a <> b)

-- Aiken MPF suffix(path, cursor=0): [0xff] ++ path  (cursor even, push prepends)
suffix0 :: ByteString -> ByteString
suffix0 = BS.cons 0xff

-- Identity trie root for a single-element trie:
-- root = combine(suffix(blake2b_256(owner_aid), 0), blake2b_256(blake2b_256(owner_key)))
identityRoot :: ByteString -> ByteString -> ByteString
identityRoot ownerAid ownerKey =
    combine (suffix0 (blake ownerAid)) (blake (blake ownerKey))

toHex :: ByteString -> String
toHex bs = concatMap showByte (BS.unpack bs)
  where
    showByte :: Word8 -> String
    showByte w =
        let s = showHex w ""
         in if length s == 1 then '0' : s else s

main :: IO ()
main = do
    let seed = BS.replicate 32 0x42
        sk :: SignKeyDSIGN Ed25519DSIGN
        sk = genKeyDSIGN (mkSeedFromBytes seed)
        vk = deriveVerKeyDSIGN sk
        ownerKey = rawSerialiseVerKeyDSIGN vk
        ownerAid = "test-aid" :: ByteString
        txId = BS.replicate 32 0xde
        outputIndex = 0 :: Integer
        msg = valueWriteMessage txId outputIndex
        ownerSig = rawSerialiseSigDSIGN $ signDSIGN () msg sk
        idRoot = identityRoot ownerAid ownerKey

    putStrLn "// Aiken test vectors for verifyOwnerAuth"
    putStrLn $ "let owner_key = #\"" <> toHex ownerKey <> "\""
    putStrLn $ "let owner_aid = #\"" <> toHex ownerAid <> "\""
    putStrLn $ "let owner_sig = #\"" <> toHex ownerSig <> "\""
    putStrLn $ "let identity_root = #\"" <> toHex idRoot <> "\""
    putStrLn $ "let tx_id = #\"" <> toHex txId <> "\""
    putStrLn "let output_index = 0"
    putStrLn "let identity_proof: Proof = []  // single-element trie"

    regenerateAttestationCorpus

-- | The tools the generator needs, from the same pinned nixpkgs as every other generator step.
generatorCommand :: [String]
generatorCommand =
    [ "shell"
    , "github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#aiken"
    , "github:NixOS/nixpkgs/753cc8a3a87467296ddd1fa93f0cc3e81120ee46#nodejs"
    , "--command"
    , "node"
    , "../scripts/attestation-vectors.mjs"
    ]

{- | Run the independent attestation generator from @offchain/@; its output goes to
standard error so that standard output stays the owner-auth vectors.
-}
regenerateAttestationCorpus :: IO ()
regenerateAttestationCorpus = do
    present <- doesFileExist "../scripts/attestation-vectors.mjs"
    if present
        then pure ()
        else do
            hPutStrLn stderr "gen-vectors: run it from offchain/ (../scripts/attestation-vectors.mjs not found)"
            exitWith (ExitFailure 2)
    (_, _, _, handle) <-
        createProcess (proc "nix" generatorCommand){std_out = UseHandle stderr}
    code <- waitForProcess handle
    case code of
        ExitSuccess -> pure ()
        ExitFailure n -> do
            hPutStrLn stderr "gen-vectors: the attestation generator failed"
            exitWith (ExitFailure n)
