{- |
Module      : Cardano.KERI.ChainQuery.ReleaseIdentity
Description : The JSON file of a release identity (#353)

The file a deployer writes and the readers (the follower and the query
service) are configured by. Plain functions on 'Cardano.KERI.AID.Release.ReleaseIdentity',
no orphan instance: the type lives in the core library, which has no JSON
dependency.

The document is one object:

> { "schema_version": 1
> , "network": 0
> , "release": { "application_policy", "application_credential"
>              , "state_program", "state_policy" }        -- 28-byte hashes, hex
> , "seed": { "transaction_id" (32 bytes, hex), "index" }
> , "checkpoint_validator": 28-byte script hash, hex
> , "amounts": { "deposit", "freeze_bond", "premium"
>              , "minimum_ada", "termination_carrier" }
> , "application_parameters": { "registration_cost", "minimum_tip"
>                             , "process_time", "booking_width" } }

Decoding refuses a document unless every field is present and of its type, and
answers one error per kind of problem, naming the field by its dotted path.
-}
module Cardano.KERI.ChainQuery.ReleaseIdentity (
    ReleaseIdentityError (..),
    encodeReleaseIdentity,
    decodeReleaseIdentity,
    readReleaseIdentity,
) where

import Cardano.KERI.AID.Application (
    ApplicationParameters (..),
    OutputReference (..),
 )
import Cardano.KERI.AID.Consumer (Release (..))
import Cardano.KERI.AID.Release (ReleaseIdentity (..))
import Control.Exception (IOException, try)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteArray.Encoding (Base (Base16), convertFromBase, convertToBase)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Scientific (base10Exponent, floatingOrInteger, isInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

-- | Why a document is not a release identity: one constructor per kind of problem.
data ReleaseIdentityError
    = -- | the text is not JSON
      NotJson !String
    | -- | the value at this path (empty for the document) is not an object
      NotAnObject !Text
    | -- | no value at this path
      MissingField !Text
    | -- | the value at this path is not of the type of the field
      WrongType !Text
    | -- | the document's schema version is not the one this reader knows
      UnknownSchemaVersion !Integer
    | -- | the text at this path is not hexadecimal
      NotHex !Text
    | -- | the hash or transaction id at this path has this many bytes where it needs that many
      WrongLength !Text !Int !Int
    | -- | the amount at this path is below zero
      NegativeAmount !Text
    | -- | the network is neither 0 nor 1
      NetworkOutOfRange !Integer
    deriving stock (Eq, Show)

schemaVersion :: Integer
schemaVersion = 1

-- | The document of an identity.
encodeReleaseIdentity :: ReleaseIdentity -> ByteString
encodeReleaseIdentity ReleaseIdentity{..} =
    BL.toStrict . Aeson.encode $
        object
            [ "schema_version" .= schemaVersion
            , "network" .= riNetwork
            , "release"
                .= object
                    [ "application_policy" .= hex (rlApplicationPolicy riRelease)
                    , "application_credential" .= hex (rlApplicationCredential riRelease)
                    , "state_program" .= hex (rlStateProgram riRelease)
                    , "state_policy" .= hex (rlStatePolicy riRelease)
                    ]
            , "seed"
                .= object
                    [ "transaction_id" .= hex (outputTransactionId riSeed)
                    , "index" .= outputIndex riSeed
                    ]
            , "checkpoint_validator" .= hex riCheckpointValidator
            , "amounts"
                .= object
                    [ "deposit" .= riDeposit
                    , "freeze_bond" .= riFreezeBond
                    , "premium" .= riPremium
                    , "minimum_ada" .= riMinimumAda
                    , "termination_carrier" .= riTerminationCarrier
                    ]
            , "application_parameters"
                .= object
                    [ "registration_cost" .= registrationCost riApplicationParameters
                    , "minimum_tip" .= minimumTip riApplicationParameters
                    , "process_time" .= processTime riApplicationParameters
                    , "booking_width" .= bookingWidth riApplicationParameters
                    ]
            ]

hex :: ByteString -> Text
hex = TE.decodeUtf8 . convertToBase Base16

-- | The identity a document names, or why it names none.
decodeReleaseIdentity :: ByteString -> Either ReleaseIdentityError ReleaseIdentity
decodeReleaseIdentity bytes = do
    document <- either (Left . NotJson) Right (Aeson.eitherDecodeStrict bytes)
    root <- object' "" document
    version <- integerAt [] root "schema_version"
    if version /= schemaVersion
        then Left (UnknownSchemaVersion version)
        else do
            riNetwork <- integerAt [] root "network"
            if riNetwork `notElem` [0, 1]
                then Left (NetworkOutOfRange riNetwork)
                else do
                    release <- objectAt [] root "release"
                    riRelease <-
                        Release
                            <$> hashAt ["release"] release "application_policy" 28
                            <*> hashAt ["release"] release "application_credential" 28
                            <*> hashAt ["release"] release "state_program" 28
                            <*> hashAt ["release"] release "state_policy" 28
                    seed <- objectAt [] root "seed"
                    riSeed <-
                        OutputReference
                            <$> hashAt ["seed"] seed "transaction_id" 32
                            <*> amountAt ["seed"] seed "index"
                    riCheckpointValidator <- hashAt [] root "checkpoint_validator" 28
                    amounts <- objectAt [] root "amounts"
                    riDeposit <- amountAt ["amounts"] amounts "deposit"
                    riFreezeBond <- amountAt ["amounts"] amounts "freeze_bond"
                    riPremium <- amountAt ["amounts"] amounts "premium"
                    riMinimumAda <- amountAt ["amounts"] amounts "minimum_ada"
                    riTerminationCarrier <-
                        amountAt ["amounts"] amounts "termination_carrier"
                    parameters <- objectAt [] root "application_parameters"
                    let parameter = amountAt ["application_parameters"] parameters
                    riApplicationParameters <-
                        ApplicationParameters
                            <$> parameter "registration_cost"
                            <*> parameter "minimum_tip"
                            <*> parameter "process_time"
                            <*> parameter "booking_width"
                    pure ReleaseIdentity{..}

type Fields = KeyMap.KeyMap Value

path :: [Text] -> Text -> Text
path parents name = T.intercalate "." (parents <> [name])

object' :: Text -> Value -> Either ReleaseIdentityError Fields
object' _ (Object o) = Right o
object' at' _ = Left (NotAnObject at')

field :: [Text] -> Fields -> Text -> Either ReleaseIdentityError Value
field parents fields name =
    maybe
        (Left (MissingField (path parents name)))
        Right
        (KeyMap.lookup (Key.fromText name) fields)

objectAt :: [Text] -> Fields -> Text -> Either ReleaseIdentityError Fields
objectAt parents fields name =
    field parents fields name >>= object' (path parents name)

integerAt :: [Text] -> Fields -> Text -> Either ReleaseIdentityError Integer
integerAt parents fields name = do
    value <- field parents fields name
    case value of
        Number n
            | isInteger n
            , base10Exponent n < maxExponent
            , Right i <- floatingOrInteger @Double n ->
                Right i
        _ -> Left (WrongType (path parents name))

amountAt :: [Text] -> Fields -> Text -> Either ReleaseIdentityError Integer
amountAt parents fields name = do
    n <- integerAt parents fields name
    if n < 0 then Left (NegativeAmount (path parents name)) else Right n

hashAt ::
    [Text] -> Fields -> Text -> Int -> Either ReleaseIdentityError ByteString
hashAt parents fields name expected = do
    value <- field parents fields name
    text <- case value of
        String t -> Right t
        _ -> Left (WrongType (path parents name))
    bytes <-
        either
            (const (Left (NotHex (path parents name))))
            Right
            (convertFromBase Base16 (TE.encodeUtf8 text))
    if BS.length bytes /= expected
        then Left (WrongLength (path parents name) expected (BS.length bytes))
        else Right bytes

-- | Read and decode the file at a path; an unreadable file is 'NotJson'.
readReleaseIdentity :: FilePath -> IO (Either ReleaseIdentityError ReleaseIdentity)
readReleaseIdentity file = do
    contents <- try @IOException (BS.readFile file)
    pure $ case contents of
        Left err -> Left (NotJson ("cannot read " <> file <> ": " <> show err))
        Right bytes -> decodeReleaseIdentity bytes

{- | The largest power of ten a JSON number may carry and still be read as an
integer: far above any amount or network, so every exact integer a document can
reasonably hold reaches the range, sign and version check of its own field.
-}
maxExponent :: Int
maxExponent = 100_000
