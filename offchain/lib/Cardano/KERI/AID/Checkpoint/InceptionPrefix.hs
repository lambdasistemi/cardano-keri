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

import Cardano.KERI.AID.Checkpoint.EventDecoder (DecodedEstablishmentEvent)
import Data.ByteString (ByteString)

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

-- | Placeholder.
classifyIdentifier :: ByteString -> Maybe PrefixKind
classifyIdentifier _ = Nothing

-- | Placeholder.
verifyPrefixBinding
    :: DecodedEstablishmentEvent -> Either PrefixRefusal PrefixKind
verifyPrefixBinding _ = Left UnknownDerivationCode
