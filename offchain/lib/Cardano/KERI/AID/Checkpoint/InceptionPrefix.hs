{- |
Module      : Cardano.KERI.AID.Checkpoint.InceptionPrefix
Description : The prefix binding of an inception (#590, model draft #600)

Off-chain mirror of @Application.InceptionPrefix@: the identifier's derivation
code decides its kind, and a basic prefix or a self-addressing prefix must be
bound to the signed inception it names.
-}
module Cardano.KERI.AID.Checkpoint.InceptionPrefix (
    PrefixKind (..),
    PrefixRefusal (..),
    classifyIdentifier,
    verifyPrefixBinding,
) where

import Cardano.KERI.AID.Blake3.Checkpoint (blake3Hash)
import Cardano.KERI.AID.CESR (qb64Aid)
import Cardano.KERI.AID.Checkpoint.EventDecoder (
    DecodedEstablishmentEvent (..),
    EventVariant (..),
 )
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8

-- | The kind of an identifier, from its derivation code.
data PrefixKind
    = -- | A key-derived prefix; the flag says whether it is transferable.
      BasicPrefix !Bool
    | -- | A prefix derived from the digest of the signed inception.
      SelfAddressingPrefix
    deriving stock (Show, Eq)

-- | Why a prefix binding is refused.
data PrefixRefusal
    = UnknownDerivationCode
    | NotAnInception
    | KeyIsNotTheIdentifier
    | SigningThresholdIsNotOne
    | NonTransferableHasNextKeys
    | NonTransferableHasWitnesses
    | NonTransferableHasSeals
    | IdentifierIsNotDerived
    | UnsupportedDerivation
    deriving stock (Show, Eq)

{- | The derivation code of a qualified identifier: four characters after
the counter `1AA`, two after a leading `0`, otherwise one.
-}
derivationCode :: ByteString -> ByteString
derivationCode text
    | "1AA" `B8.isPrefixOf` text = BS.take 4 text
    | "0" `B8.isPrefixOf` text = BS.take 2 text
    | otherwise = BS.take 1 text

{- | The kind of an identifier from its derivation code, in the ordinary
basic-key and self-addressing domain of keripy 1.3.5 (non-transferable
basic: B, 1AAA, 1AAC, 1AAI; transferable basic: D, 1AAB, 1AAD, 1AAJ;
self-addressing: E, F, G, H, I, 0D, 0E, 0F, 0G).
-}
classifyIdentifier :: ByteString -> Maybe PrefixKind
classifyIdentifier text
    | code `elem` ["B", "1AAA", "1AAC", "1AAI"] = Just (BasicPrefix False)
    | code `elem` ["D", "1AAB", "1AAD", "1AAJ"] = Just (BasicPrefix True)
    | code `elem` ["E", "F", "G", "H", "I", "0D", "0E", "0F", "0G"] =
        Just SelfAddressingPrefix
    | otherwise = Nothing
  where
    code = derivationCode text

{- | Bind a decoded inception to the kind of its identifier. A basic prefix is
the sole signing key with numeric threshold one, and a non-transferable one
also has no next keys, witnesses or seals; a self-addressing prefix is the
digest of the signed body. The own SAID is a separate value: it is not the
identifier of a basic prefix.
-}
verifyPrefixBinding ::
    DecodedEstablishmentEvent -> Either PrefixRefusal PrefixKind
verifyPrefixBinding event
    | deeVariant event /= VariantIcp = Left NotAnInception
    | otherwise = case classifyIdentifier (deeAid event) of
        Nothing -> Left UnknownDerivationCode
        Just kind@(BasicPrefix transferable) -> do
            unless (deeK event == [deeAid event]) (Left KeyIsNotTheIdentifier)
            unless (deeKt event == "1") (Left SigningThresholdIsNotOne)
            unless (transferable || null (deeN event)) (Left NonTransferableHasNextKeys)
            unless (transferable || null (deeB event)) (Left NonTransferableHasWitnesses)
            unless (transferable || deeAnchors event == "[]") (Left NonTransferableHasSeals)
            Right kind
        Just SelfAddressingPrefix
            | derivationCode (deeAid event) /= "E" -> Left UnsupportedDerivation
            | qb64Aid (blake3Hash (deeSaidPreimage event)) == deeAid event ->
                Right SelfAddressingPrefix
            | otherwise -> Left IdentifierIsNotDerived
