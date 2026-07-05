module Cardano.AID.Ed25519
    ( verifyEd25519
    ) where

import Cardano.Crypto.DSIGN
    ( SigDSIGN
    , VerKeyDSIGN
    , rawDeserialiseSigDSIGN
    , rawDeserialiseVerKeyDSIGN
    , verifyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519 (Ed25519DSIGN)
import Data.ByteString (ByteString)

verifyEd25519 :: ByteString -> ByteString -> ByteString -> Bool
verifyEd25519 pubKeyBs msg sigBs =
    case
        ( rawDeserialiseVerKeyDSIGN pubKeyBs :: Maybe (VerKeyDSIGN Ed25519DSIGN)
        , rawDeserialiseSigDSIGN sigBs :: Maybe (SigDSIGN Ed25519DSIGN)
        )
    of
        (Just pk, Just sig) ->
            case verifyDSIGN () pk msg sig of
                Right () -> True
                Left _ -> False
        _ -> False
