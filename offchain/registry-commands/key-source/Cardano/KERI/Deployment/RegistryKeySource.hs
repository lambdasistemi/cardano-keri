{-# LANGUAGE LambdaCase #-}

{- |
Module      : Cardano.KERI.Deployment.RegistryKeySource
Description : Where the registry commands take their signing key from

@ckeri registry deploy|register|fold|return@ sign with one key: the payment
signing-key envelope of a file, or the key of a wallet vault opened with a
passphrase. Exactly one source is given. The vault and the passphrase rules are
those of the @singular@ command line; they are read from its modules, not
restated here.

The key a vault holds is handed on as an envelope and never as a path: nothing is
written, and the envelope shows as a marker wherever it is shown.
-}
module Cardano.KERI.Deployment.RegistryKeySource (
    signingKeyFileSetting,
    vaultSetting,
    passphraseFdSetting,
    KeySourceRefusal,
    renderKeySourceRefusal,
    resolveKeySource,
) where

import Cardano.KERI.Deployment.NodeSocketRuntime (KeySource (..))
import Data.Aeson qualified as Aeson
import OptEnvConf qualified as Opt
import Singular.CLI.Passphrase (
    Confirmation (AskOnce),
    PassphraseRefusal,
    PassphraseSource (..),
    readPassphrase,
    renderPassphraseRefusal,
    sourceFor,
 )
import Singular.CLI.Vault (
    VaultRefusal (..),
    openVault,
    readVaultFile,
    renderVaultRefusal,
    signKeyEnvelope,
 )

-- | @--signing-key-file@: a Cardano payment signing-key envelope, accepted beside the vault.
signingKeyFileSetting :: Opt.Parser (Maybe FilePath)
signingKeyFileSetting =
    Opt.optional $
        Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long "signing-key-file"
            , Opt.env "CKERI_SIGNING_KEY_FILE"
            , Opt.conf "signing-key-file"
            , Opt.metavar "VALUE"
            , Opt.help "Cardano payment signing-key envelope, accepted; give --vault instead, which is the supported way"
            ]

-- | @--vault@: the wallet vault that signs, made by @singular wallet create@.
vaultSetting :: Opt.Parser (Maybe FilePath)
vaultSetting =
    Opt.optional $
        Opt.setting
            [ Opt.reader Opt.str
            , Opt.option
            , Opt.long "vault"
            , Opt.env "CKERI_VAULT"
            , Opt.conf "vault"
            , Opt.metavar "VALUE"
            , Opt.help "The wallet vault that signs, made by `singular wallet create`: the supported way; its passphrase is read from --passphrase-fd"
            ]

-- | @--passphrase-fd@: the descriptor the vault's passphrase is read from, given on the command line alone.
passphraseFdSetting :: Opt.Parser (Maybe Int)
passphraseFdSetting =
    Opt.optional $
        Opt.setting
            [ Opt.reader Opt.auto
            , Opt.option
            , Opt.long "passphrase-fd"
            , Opt.metavar "N"
            , Opt.help "The inherited file descriptor the vault's passphrase is read from, one line; on a development network SINGULAR_PASSPHRASE is read when this is not given"
            ]

-- | Why the commands refuse to take a key, before a transaction exists.
data KeySourceRefusal
    = -- | a key file and a vault were both given
      KeySourceBoth
    | -- | neither was
      KeySourceNeither
    | -- | a vault, and nothing to read its passphrase from
      VaultWithoutPassphrase
    | -- | a passphrase descriptor, and no vault to open
      PassphraseWithoutVault
    | -- | the passphrase could not be taken: Singular's refusal
      PassphraseRefused PassphraseRefusal
    | -- | the vault could not be read or opened: Singular's refusal
      VaultRefused VaultRefusal
    deriving stock (Eq, Show)

{- | The refusal as one line, carrying no secret. What belongs to the vault and to the
passphrase is said as the @singular@ modules say it.
-}
renderKeySourceRefusal :: KeySourceRefusal -> String
renderKeySourceRefusal = \case
    KeySourceBoth ->
        "key-source-both: give --signing-key-file or --vault with --passphrase-fd, not both"
    KeySourceNeither ->
        "key-source-neither: give --vault with --passphrase-fd (the supported way) or --signing-key-file"
    VaultWithoutPassphrase ->
        "vault-without-passphrase: --vault needs --passphrase-fd, or SINGULAR_PASSPHRASE on a development network"
    PassphraseWithoutVault ->
        "passphrase-fd-without-vault: --passphrase-fd opens the vault named by --vault, and none was given"
    PassphraseRefused refusal -> renderPassphraseRefusal refusal
    VaultRefused refusal -> renderVaultRefusal refusal

{- | The key the settings name, or the refusal: given the network magic, the
@--signing-key-file@, the @--vault@ and the @--passphrase-fd@. Nothing is read until the
choice of source is known to be exactly one, and a key file is only named here, never read.
-}
resolveKeySource ::
    Int -> Maybe FilePath -> Maybe FilePath -> Maybe Int -> IO (Either KeySourceRefusal KeySource)
resolveKeySource magic file vault descriptor = case (file, vault, descriptor) of
    (Just _, Just _, _) -> refuse KeySourceBoth
    (Nothing, Nothing, Nothing) -> refuse KeySourceNeither
    (Nothing, Nothing, Just _) -> refuse PassphraseWithoutVault
    (Just _, Nothing, Just _) -> refuse PassphraseWithoutVault
    (Just path, Nothing, Nothing) -> pure (Right (KeyFile path))
    (Nothing, Just vaultPath, _) ->
        sourceFor (fromIntegral magic) descriptor >>= \case
            Left refusal -> refuse (PassphraseRefused refusal)
            Right PassphraseTerminal -> refuse VaultWithoutPassphrase
            Right source -> openVaultWith source vaultPath
  where
    refuse = pure . Left
    openVaultWith source vaultPath =
        readVaultFile vaultPath >>= \case
            Left refusal -> refuse (VaultRefused refusal)
            Right bytes ->
                readPassphrase AskOnce source >>= \case
                    Left refusal -> refuse (PassphraseRefused refusal)
                    Right passphrase -> pure $ case openVault passphrase bytes of
                        Left refusal -> Left (VaultRefused refusal)
                        Right key -> case Aeson.eitherDecodeStrict' (signKeyEnvelope key) of
                            Right envelope -> Right (KeyEnvelope envelope)
                            Left _ -> Left (VaultRefused VaultNotOpened)
