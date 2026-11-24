{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Cardano.KERI.Deployment.SigningKeyCheck
Description : the signing-key checks made before the node is opened, said by name

The live context refuses a missing or invalid signing-key file and a key that does not
belong to the funding address before it opens the node, with a bare failure. These are the
same refusals, each by name: they happen before any transaction exists, so whoever reads
one can be told nothing was submitted and nothing was spent.
-}
module Cardano.KERI.Deployment.SigningKeyCheck (
    checkSigningKey,
    checkSigningEnvelope,
) where

import Cardano.Crypto.DSIGN.Class (SignKeyDSIGN, deriveVerKeyDSIGN)
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Cardano.Ledger.Address (Addr (..))
import Cardano.Ledger.Credential (Credential (..))
import Cardano.Ledger.Keys (VKey (..), hashKey)
import Cardano.Tx.Sign.Core (decodePaymentSigningKey)
import Control.Exception (IOException, try)
import Data.Aeson (Value, eitherDecodeFileStrict')
import System.Directory (doesFileExist)

{- | The signing key file holds a payment key, and it is the key of the funding address.
Left names the refusal.
-}
checkSigningKey :: FilePath -> Addr -> IO (Either String ())
checkSigningKey path address = do
    present <- doesFileExist path
    if not present
        then pure (Left ("signing-key-file-missing: " <> path <> " is not a file"))
        else
            try @IOException (eitherDecodeFileStrict' path) >>= \case
                Left failure -> pure (Left ("signing-key-file-unreadable: " <> path <> ": " <> show failure))
                Right (Left parseFailure) -> pure (Left ("signing-key-file-invalid: " <> path <> ": " <> parseFailure))
                Right (Right (envelope :: Value)) -> pure $ case decodePaymentSigningKey envelope of
                    Left failure -> Left ("signing-key-file-invalid: " <> path <> ": " <> show failure)
                    Right signingKey -> signingKeyOf signingKey address

{- | The same check of a key already opened: its envelope holds a payment key, and it is the key of
the funding address. Left names the refusal.
-}
checkSigningEnvelope :: Value -> Addr -> Either String ()
checkSigningEnvelope envelope address = case decodePaymentSigningKey envelope of
    Left failure -> Left ("signing-key-invalid: " <> show failure)
    Right signingKey -> signingKeyOf signingKey address

-- | The funding address is the address of the key.
signingKeyOf :: SignKeyDSIGN Ed25519DSIGN -> Addr -> Either String ()
signingKeyOf signingKey = \case
    Addr _ (KeyHashObj actual) _
        | actual == hashKey (VKey (deriveVerKeyDSIGN signingKey)) -> Right ()
        | otherwise -> Left "signing-key-does-not-match-address: the funding address is not the address of the signing key"
    Addr _ ScriptHashObj{} _ -> Left "funding-address-invalid: the funding address must use a payment key credential"
    AddrBootstrap{} -> Left "funding-address-invalid: the funding address must be a Shelley testnet address"
