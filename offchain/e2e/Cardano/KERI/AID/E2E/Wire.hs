{- |
Module      : Cardano.KERI.AID.E2E.Wire
Description : Plutus Data wire types for the hardened #99 cage validator

Hand-written 'ToData' instances that match the Aiken @types.ak@ source
byte-for-byte (constructor indices + field order), for the wire shapes
the e2e builder must produce but that are not already mirrored in
@Cardano.KERI.AID.Cage.Types@:

  * 'OutRef'          — Aiken @cardano/transaction.OutputReference@
  * 'TokenId'         — @lib.TokenId@
  * 'Operation'       — @types.Operation@ (Insert/Delete/Update)
  * 'Request'         — @types.Request@
  * 'CageWireDatum'   — @types.CageDatum@ (RequestDatum/StateDatum)
  * 'MintRedeemer'    — @types.MintRedeemer@ (Minting/Migrating/Burning)
  * 'UpdateRedeemer'  — @types.UpdateRedeemer@ (End/Contribute/Modify/Retract)

The State, OwnerAuth and RequestAction encodings are reused from the
parity-tested 'Cardano.KERI.AID.Cage.Types' ('AIDOnChainTokenState',
'AIDOwnerAuth', 'AIDRequestAction').
-}
module Cardano.KERI.AID.E2E.Wire (
    OutRef (..),
    TokenId (..),
    Operation (..),
    Request (..),
    CageWireDatum (..),
    Mint (..),
    Migration (..),
    MintRedeemer (..),
    UpdateRedeemer (..),

    -- * Re-exports of the parity-tested inner encodings
    AIDOnChainTokenState (..),
    AIDOwnerAuth (..),
    AIDRequestAction (..),
) where

import Cardano.KERI.AID.Cage.Types (
    AIDOnChainTokenState (..),
    AIDOwnerAuth (..),
    AIDRequestAction (..),
 )
import Data.ByteString (ByteString)
import PlutusCore.Data (Data (..))
import PlutusTx.Builtins.Internal (BuiltinData (..))
import PlutusTx.IsData.Class (ToData (..))

mkD :: Data -> BuiltinData
mkD = BuiltinData

unD :: (ToData a) => a -> Data
unD x = let BuiltinData d = toBuiltinData x in d

bsD :: ByteString -> Data
bsD = B

-- | Aiken @OutputReference { transaction_id: ByteArray, output_index: Int }@.
data OutRef = OutRef
    { refTxId :: !ByteString
    , refIdx :: !Integer
    }
    deriving stock (Show, Eq)

instance ToData OutRef where
    toBuiltinData OutRef{..} = mkD $ Constr 0 [bsD refTxId, I refIdx]

-- | Aiken @lib.TokenId { assetName: AssetName }@.
newtype TokenId = TokenId {tokenAssetName :: ByteString}
    deriving stock (Show, Eq)

instance ToData TokenId where
    toBuiltinData (TokenId an) = mkD $ Constr 0 [bsD an]

-- | Aiken @types.Operation@.
data Operation
    = Insert !ByteString
    | Delete !ByteString
    | Update !ByteString !ByteString
    deriving stock (Show, Eq)

instance ToData Operation where
    toBuiltinData (Insert v) = mkD $ Constr 0 [bsD v]
    toBuiltinData (Delete v) = mkD $ Constr 1 [bsD v]
    toBuiltinData (Update o n) = mkD $ Constr 2 [bsD o, bsD n]

-- | Aiken @types.Request@.
data Request = Request
    { requestToken :: !TokenId
    , requestOwner :: !ByteString
    , requestKey :: !ByteString
    , requestValue :: !Operation
    , requestTip :: !Integer
    , requestSubmittedAt :: !Integer
    }
    deriving stock (Show, Eq)

instance ToData Request where
    toBuiltinData Request{..} =
        mkD $
            Constr
                0
                [ unD requestToken
                , bsD requestOwner
                , bsD requestKey
                , unD requestValue
                , I requestTip
                , I requestSubmittedAt
                ]

-- | Aiken @types.CageDatum@ (@RequestDatum(Request)@ / @StateDatum(State)@).
data CageWireDatum
    = RequestDatum !Request
    | StateDatum !AIDOnChainTokenState
    deriving stock (Show, Eq)

instance ToData CageWireDatum where
    toBuiltinData (RequestDatum r) = mkD $ Constr 0 [unD r]
    toBuiltinData (StateDatum s) = mkD $ Constr 1 [unD s]

-- | Aiken @types.Mint { asset: OutputReference }@.
newtype Mint = Mint {mintAsset :: OutRef}
    deriving stock (Show, Eq)

instance ToData Mint where
    toBuiltinData (Mint r) = mkD $ Constr 0 [unD r]

-- | Aiken @types.Migration { tokenId: TokenId }@.
newtype Migration = Migration {migrationTokenId :: TokenId}
    deriving stock (Show, Eq)

instance ToData Migration where
    toBuiltinData (Migration t) = mkD $ Constr 0 [unD t]

-- | Aiken @types.MintRedeemer@.
data MintRedeemer
    = Minting !Mint
    | Migrating !Migration
    | Burning !TokenId
    deriving stock (Show, Eq)

instance ToData MintRedeemer where
    toBuiltinData (Minting m) = mkD $ Constr 0 [unD m]
    toBuiltinData (Migrating m) = mkD $ Constr 1 [unD m]
    toBuiltinData (Burning t) = mkD $ Constr 2 [unD t]

-- | Aiken @types.UpdateRedeemer@.
data UpdateRedeemer
    = End
    | Contribute !OutRef
    | Modify ![AIDRequestAction]
    | Retract !OutRef
    deriving stock (Show, Eq)

instance ToData UpdateRedeemer where
    toBuiltinData End = mkD $ Constr 0 []
    toBuiltinData (Contribute r) = mkD $ Constr 1 [unD r]
    toBuiltinData (Modify actions) =
        mkD $ Constr 2 [List (map unD actions)]
    toBuiltinData (Retract r) = mkD $ Constr 3 [unD r]
