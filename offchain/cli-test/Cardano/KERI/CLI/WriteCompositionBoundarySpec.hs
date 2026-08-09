{- |
Module      : Cardano.KERI.CLI.WriteCompositionBoundarySpec
Description : RED T240-S1-02 — provider-free write-composition component boundary

INV-240-NOPROVIDER (BLOCKING): the complete write composition boundary has no
Koios\/HTTP\/provider package dependency, import, configuration, callback, or
runtime call. This is enforced by the Cabal component graph
(MOD-240-WRITE-COMPOSITION, @plan.md@ "Dependency direction": "This component
split, not a source convention, enforces INV-240-NOPROVIDER"), not by a
runtime search — so this suite statically inspects the frozen source of
truth for that graph, @cardano-keri.cabal@ itself, plus a positive control
that the check can actually distinguish a real boundary from an absent one
(invariants skill: prove a search's method can find a known positive before
trusting an absence).

RED reason (current tree, pre-migration): no @library write-composition@
stanza exists yet in @cardano-keri.cabal@ — every assertion below fails
closed on a named absent-component reason, not a parse crash or an
unrelated failure.
-}
module Cardano.KERI.CLI.WriteCompositionBoundarySpec (spec) where

import Data.Char (toLower)
import Data.List (isInfixOf, isPrefixOf)
import Data.Maybe (fromMaybe)
import Test.Hspec

-- | The single frozen source of truth for the component graph (@plan.md@).
cabalFilePath :: FilePath
cabalFilePath = "cardano-keri.cabal"

-- | Package-name substrings that make a component provider-reachable
-- (INV-240-NOPROVIDER: "Koios/HTTP/another third-party provider").
forbiddenSubstrings :: [String]
forbiddenSubstrings = ["koios", "http-conduit", "http-client", "http-types", "req"]

{- | One top-level Cabal stanza's raw body: every line after the header line,
up to (excluding) the next line that is neither blank nor indented — this
file's own convention for where one stanza ends and the next begins. Blank
lines and comments *inside* a stanza (this file separates its own fields by
a blank line) are tolerated, never treated as the stanza's end. This is a
deliberately narrow re-implementation sufficient only for this one
repository file, never a general Cabal parser (matching the existing
"no dependency edge just for one enum" precedent set in
"Cardano.KERI.CLI.Backend").
-}
stanzaLines :: String -> [String] -> Maybe [String]
stanzaLines header ls = case dropWhile (not . (header `isPrefixOf`)) ls of
    [] -> Nothing
    (_ : rest) -> Just (takeWhile inStanza rest)
  where
    inStanza "" = True
    inStanza (c : _) = c == ' ' || c == '\t'

{- | One field's value lines within an already-extracted stanza body: every
line after the field-key line, up to (excluding) the first blank line —
this file's fields are blank-line separated from one another.
-}
fieldLines :: String -> [String] -> Maybe [String]
fieldLines key stanza = case dropWhile (not . matches) stanza of
    [] -> Nothing
    (_ : rest) -> Just (takeWhile (not . null) rest)
  where
    matches line = key `isPrefixOf` dropWhile (== ' ') line

-- | Every package token named on a @build-depends:@/continuation line.
dependencyTokens :: [String] -> [String]
dependencyTokens ls =
    [ token
    | line <- ls
    , let stripped = dropWhile (`elem` (" ,\t" :: String)) line
    , not (null stripped)
    , let token = takeWhile (`notElem` (" \t" :: String)) stripped
    , not (null token)
    ]

-- | One named stanza's build-depends tokens, read fresh from disk.
stanzaDependencies :: String -> IO [String]
stanzaDependencies header = do
    ls <- lines <$> readFile cabalFilePath
    pure $ maybe [] dependencyTokens (fieldLines "build-depends:" =<< stanzaLines header ls)

hasForbiddenDependency :: [String] -> Bool
hasForbiddenDependency =
    any (\dep -> any (`isInfixOf` map toLower dep) forbiddenSubstrings)

{- | @write-composition@'s stanza and its dependency tokens, or a named
reason it cannot be found — never a partial/degenerate answer.
-}
writeCompositionStanza :: IO (Either String [String])
writeCompositionStanza = do
    ls <- lines <$> readFile cabalFilePath
    pure $ case stanzaLines "library write-composition" ls of
        Nothing -> Left "no `library write-composition` stanza in cardano-keri.cabal"
        Just body -> case fieldLines "build-depends:" body of
            Nothing -> Left "write-composition stanza has no build-depends field"
            Just deps -> Right (dependencyTokens deps)

spec :: Spec
spec = describe "MOD-240-WRITE-COMPOSITION component boundary (INV-240-NOPROVIDER)" $ do
    it "positive control: the boundary method can see a real forbidden dependency" $ do
        cliDeps <- stanzaDependencies "library cli"
        hasForbiddenDependency cliDeps `shouldBe` True

    it "exists as its own Cabal component, separate from the existing `cli` component" $ do
        stanza <- writeCompositionStanza
        either expectationFailure (const (pure ())) stanza

    it "has no Koios/HTTP/provider dependency edge (EDGE-240-04)" $ do
        stanza <- writeCompositionStanza
        case stanza of
            Left reason -> expectationFailure reason
            Right deps -> hasForbiddenDependency deps `shouldBe` False

    it "receives the existing write command module (Cardano.KERI.Deployment.CLI)" $ do
        ls <- lines <$> readFile cabalFilePath
        case stanzaLines "library write-composition" ls of
            Nothing -> expectationFailure "no `library write-composition` stanza in cardano-keri.cabal"
            Just body -> do
                let exposed = fromMaybe [] (fieldLines "exposed-modules:" body)
                any ("Cardano.KERI.Deployment.CLI" `isInfixOf`) exposed
                    `shouldBe` True

    it "the existing `cli` component depends on write-composition, never the reverse (EDGE-240-02)" $ do
        cliDeps <- stanzaDependencies "library cli"
        any ("write-composition" `isInfixOf`) cliDeps `shouldBe` True
