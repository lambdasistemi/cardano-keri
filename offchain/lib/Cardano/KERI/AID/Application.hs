{- |
Module      : Cardano.KERI.AID.Application
Description : Wire records and token names of KERI's application on the public registry

The words of the Lean model @CardanoKeri.Application@ as bytes: the registry
identity, the records an output at the application address carries, the
operations of the application and of the registry's state script, and the
names of the tokens the registry hashes from them.

Every name here is the Plutus Data serialisation of a preimage, hashed with
BLAKE2b-256, exactly as the public registry's own functions compute it, so
a Haskell builder and the validators agree on every asset name. The library
is pure: nothing here talks to a node.
-}
module Cardano.KERI.AID.Application (
    -- * The registry and the credential a Lean address names
    RegistryIdentity (..),
    OutputReference (..),
    Credential (..),
    PlutusAddress (..),
    unstakedAddress,

    -- * Token names
    stateTokenName,
    activeTokenName,
    configurationTokenName,
    registrationApprovalName,
    terminationApprovalName,
    initialDatumHash,

    -- * The records of the application address
    ApplicationParameters (..),
    RegistrationData (..),
    HeldDatum (..),
    heldDatumData,

    -- * The operations of the application
    Action (..),
    SpendAction (..),
    actionData,
    spendActionData,

    -- * The registry's state script
    stateProgram,
    statePolicy,
    stateDatumData,
    StateMint (..),
    stateMintData,
    Change (..),
    stateSpendData,
    activeLeaf,

    -- * Plutus Data shared by the encoders
    addressData,
    registryIdentityData,
    outputReferenceData,
) where

import Cardano.Crypto.Hash.Blake2b (Blake2b_224)
import Cardano.Crypto.Hash.Class (digest)
import Cardano.KERI.AID.Checkpoint.Datum (blake2b_256)
import Cardano.KERI.AID.Migration.Types (canonicalCborData)
import Data.ByteString (ByteString)
import Data.Proxy (Proxy (..))
import PlutusCore.Data (Data (..))

{- | The identity of a registry: the policy of its state script and the name of
its state token.
-}
data RegistryIdentity = RegistryIdentity
    { registryStatePolicy :: !ByteString
    , registryName :: !ByteString
    }
    deriving stock (Eq, Show)

-- | A transaction output reference: the transaction id and the output index.
data OutputReference = OutputReference
    { outputTransactionId :: !ByteString
    , outputIndex :: !Integer
    }
    deriving stock (Eq, Show)

-- | The payment part of an address: a key hash or a script hash.
data Credential
    = KeyCredential !ByteString
    | ScriptCredential !ByteString
    deriving stock (Eq, Show)

-- | A Plutus address: a payment credential and an optional stake credential.
data PlutusAddress = PlutusAddress
    { addressPayment :: !Credential
    , addressStake :: !(Maybe Credential)
    }
    deriving stock (Eq, Show)

{- | The address of a Lean credential: the payment credential alone, with no
stake credential.
-}
unstakedAddress :: Credential -> PlutusAddress
unstakedAddress credential = PlutusAddress credential Nothing

credentialData :: Credential -> Data
credentialData = \case
    KeyCredential hash -> Constr 0 [B hash]
    ScriptCredential hash -> Constr 1 [B hash]

-- | The Plutus Data of an address: the stake credential is an inline one.
addressData :: PlutusAddress -> Data
addressData (PlutusAddress payment stake) =
    Constr
        0
        [ credentialData payment
        , maybe (Constr 1 []) (\c -> Constr 0 [Constr 0 [credentialData c]]) stake
        ]

registryIdentityData :: RegistryIdentity -> Data
registryIdentityData (RegistryIdentity policy name) = Constr 0 [B policy, B name]

outputReferenceData :: OutputReference -> Data
outputReferenceData (OutputReference transactionId index) =
    Constr 0 [B transactionId, I index]

-- ---------------------------------------------------------
-- Token names
-- ---------------------------------------------------------

-- | The role name of a preimage: BLAKE2b-256 of its Data serialisation.
roleName :: Data -> ByteString
roleName = blake2b_256 . canonicalCborData

{- | The name of the state token of the registry created by spending @seed@
(preimage constructor 0).
-}
stateTokenName :: OutputReference -> ByteString
stateTokenName seed = roleName (Constr 0 [outputReferenceData seed])

{- | The name of the token that stands for @key@ in the registry (preimage
constructor 1): the asset the representative asset of the Lean identity is.
-}
activeTokenName :: RegistryIdentity -> ByteString -> ByteString
activeTokenName registry key =
    roleName (Constr 1 [registryIdentityData registry, B key])

-- | The name of the token of the configuration record (preimage constructor 2).
configurationTokenName :: RegistryIdentity -> ByteString
configurationTokenName registry =
    roleName (Constr 2 [registryIdentityData registry])

{- | The hash of a holding's initial datum, as the registration approval commits
it.
-}
initialDatumHash :: Data -> ByteString
initialDatumHash = blake2b_256 . canonicalCborData

{- | The name of the approval of a registration under the application policy
(preimage constructor 3): the registry, the key, the address the holding sits
at, the hash of its initial datum and the deposit it holds.
-}
registrationApprovalName ::
    RegistryIdentity -> ByteString -> PlutusAddress -> Data -> Integer -> ByteString
registrationApprovalName registry key holdingAddress initialDatum deposit =
    roleName
        ( Constr
            3
            [ registryIdentityData registry
            , B key
            , addressData holdingAddress
            , B (initialDatumHash initialDatum)
            , I deposit
            ]
        )

{- | The name of the approval of a termination (preimage constructor 4): the
registry and the key.
-}
terminationApprovalName :: RegistryIdentity -> ByteString -> ByteString
terminationApprovalName registry key =
    roleName (Constr 4 [registryIdentityData registry, B key])

-- ---------------------------------------------------------
-- The records of the application address
-- ---------------------------------------------------------

{- | The five request parameters of a registry, fixed when it is created. A KERI
registry has no retraction window, so there is no such field: it is written
as zero.
-}
data ApplicationParameters = ApplicationParameters
    { registrationCost :: !Integer
    , minimumTip :: !Integer
    , processTime :: !Integer
    , bookingWidth :: !Integer
    }
    deriving stock (Eq, Show)

-- | A booked registration, the datum of a request.
data RegistrationData = RegistrationData
    { requestRegistry :: !RegistryIdentity
    , requestKey :: !ByteString
    , requestController :: !ByteString
    , requestRefundAddress :: !PlutusAddress
    , requestHoldingAddress :: !PlutusAddress
    , requestInitialDatum :: !Data
    , requestDeposit :: !Integer
    , requestBookedAt :: !Integer
    , requestProcessDeadline :: !Integer
    , requestReclaimEnd :: !Integer
    }
    deriving stock (Eq, Show)

-- | The datum of an output at the application address.
data HeldDatum
    = -- | The record of a registry: its parameters and the checkpoint credential.
      Configuration !ApplicationParameters !Credential
    | -- | A booked request.
      Registration !RegistrationData
    deriving stock (Eq, Show)

heldDatumData :: HeldDatum -> Data
heldDatumData = \case
    Configuration parameters checkpoint ->
        Constr
            0
            [ Constr
                0
                [ I (registrationCost parameters)
                , I (minimumTip parameters)
                , I (processTime parameters)
                , I 0
                , I (bookingWidth parameters)
                ]
            , credentialData checkpoint
            ]
    Registration request ->
        Constr
            1
            [ Constr
                0
                [ registryIdentityData (requestRegistry request)
                , B (requestKey request)
                , B (requestController request)
                , addressData (requestRefundAddress request)
                , addressData (requestHoldingAddress request)
                , requestInitialDatum request
                , I (requestDeposit request)
                , I (requestBookedAt request)
                , I (requestProcessDeadline request)
                , I (requestReclaimEnd request)
                ]
            ]

-- ---------------------------------------------------------
-- The operations of the application
-- ---------------------------------------------------------

-- | An operation that brings an output into being: the mint redeemer lists them.
data Action
    = {- | Create the configuration record of the registry in the output at the
      index, in the transaction that spends the seed.
      -}
      CreateConfiguration !RegistryIdentity !OutputReference !Integer
    | -- | Book the registration held by the output at the index.
      BookRegistration !Integer
    deriving stock (Eq, Show)

-- | The operation that spends an input at the application address.
data SpendAction
    = -- | Fold the request: the output at the index is the delivered holding.
      FoldRegistration !Integer
    | -- | Return the request after its deadline.
      ReturnRegistration
    deriving stock (Eq, Show)

actionData :: Action -> Data
actionData = \case
    CreateConfiguration registry seed index ->
        Constr 0 [registryIdentityData registry, outputReferenceData seed, I index]
    BookRegistration index -> Constr 1 [I index]

spendActionData :: SpendAction -> Data
spendActionData = \case
    FoldRegistration index -> Constr 0 [I index]
    ReturnRegistration -> Constr 1 []

-- ---------------------------------------------------------
-- The registry's state script
-- ---------------------------------------------------------

{- | The program of the state script applied to the application policy: the
template, the flat encoding of the parameter and the end of the program.
-}
stateProgram :: ByteString -> ByteString -> ByteString
stateProgram template applicationPolicy =
    template <> "\x1e\x58\x1c" <> applicationPolicy <> "\x00\x01"

{- | The policy of the registry state of an application: the hash of the state
program, which is also the credential of the state address.
-}
statePolicy :: ByteString -> ByteString -> ByteString
statePolicy template applicationPolicy =
    digest (Proxy @Blake2b_224) ("\x03" <> stateProgram template applicationPolicy)

-- | The datum of the state output: the root of the registry's keys.
stateDatumData :: ByteString -> Data
stateDatumData root = Constr 0 [B root]

-- | The redeemer of the state policy.
data StateMint
    = -- | The genesis of the registry named from the seed.
      Genesis !OutputReference
    | -- | A mint that belongs to a fold.
      Folded
    deriving stock (Eq, Show)

stateMintData :: StateMint -> Data
stateMintData = \case
    Genesis seed -> Constr 0 [outputReferenceData seed]
    Folded -> Constr 1 []

-- | The registration a fold folds into the state.
data Change = Register
    { changeRequest :: !OutputReference
    , changeKey :: !ByteString
    , changeHolding :: !Integer
    , changeDeposit :: !Integer
    , changeProof :: ![Data]
    -- ^ the steps of the proof of the key's absence; empty for an empty registry
    }
    deriving stock (Eq, Show)

-- | The redeemer of the state output: the seed that names the registry and the changes.
stateSpendData :: OutputReference -> [Change] -> Data
stateSpendData seed changes =
    Constr 0 [outputReferenceData seed, List (map changeData changes)]
  where
    changeData (Register request key holding deposit proof) =
        Constr
            0
            [ outputReferenceData request
            , B key
            , I holding
            , I deposit
            , List proof
            ]

-- | The leaf the registry binds to a registered key.
activeLeaf :: ByteString
activeLeaf = "\x01"
