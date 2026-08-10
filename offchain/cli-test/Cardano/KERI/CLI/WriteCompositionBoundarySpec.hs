{- |
Module      : Cardano.KERI.CLI.WriteCompositionBoundarySpec
Description : T240-S1-02 -- provider-free write-composition component boundary (layout-independent, A-011)

INV-240-NOPROVIDER (BLOCKING): the complete write composition boundary has no
Koios\/HTTP\/provider package dependency, import, configuration, callback, or
runtime call. This is enforced by the Cabal component graph
(MOD-240-WRITE-COMPOSITION, @plan.md@ "Dependency direction": "This component
split, not a source convention, enforces INV-240-NOPROVIDER"), not by a
runtime search — so this suite inspects the frozen source of truth for that
graph, @cardano-keri.cabal@ itself.

A-011 repair: this suite previously matched raw lines\/stanza shapes by hand,
which is brittle in both directions a formatter can move a field and the
proof breaks (announces itself), but a provider dependency written in a
layout the hand parser does not recognise would pass undetected (does not
announce itself) — the same defect, only one direction is visible. This
version parses @cardano-keri.cabal@ through Cabal's own package-description
parser ("Distribution.PackageDescription.Parsec") and queries the resulting
typed component graph, so layout — continuation form, inline form, comments,
ordering, any future @cabal-fmt@ canonicalisation — is irrelevant by
construction. Every checked component's dependency\/module set is the union
across ALL conditional branches ('Distribution.Types.Library.Library' and
"Distribution.Types.BuildInfo".'Distribution.Types.BuildInfo.BuildInfo' are
'Monoid's precisely so this fold is the complete, not merely convenient,
answer — no conditional branch is silently ignored). A parse failure or a
missing named component is itself a fail-closed named failure, never a
partial/degenerate answer.
-}
module Cardano.KERI.CLI.WriteCompositionBoundarySpec (spec) where

import Data.ByteString qualified as BS
import Data.Char (toLower)
import Data.Foldable (fold, toList)
import Data.List (isInfixOf)
import Distribution.Fields.ParseResult (runParseResult)
import Distribution.PackageDescription.Parsec (parseGenericPackageDescription)
import Distribution.Pretty (prettyShow)
import Distribution.Types.BuildInfo (targetBuildDepends)
import Distribution.Types.Dependency (Dependency, depLibraries, depPkgName)
import Distribution.Types.GenericPackageDescription (
    GenericPackageDescription (condSubLibraries),
 )
import Distribution.Types.Library (Library (..))
import Distribution.Types.LibraryName (LibraryName (..))
import Distribution.Types.UnqualComponentName (mkUnqualComponentName, unUnqualComponentName)
import Test.Hspec

-- | The single frozen source of truth for the component graph (@plan.md@).
cabalFilePath :: FilePath
cabalFilePath = "cardano-keri.cabal"

{- | Package-name\/sublibrary-name substrings that make a component
provider-reachable (INV-240-NOPROVIDER: "Koios/HTTP/another third-party
provider").
-}
forbiddenSubstrings :: [String]
forbiddenSubstrings = ["koios", "http-conduit", "http-client", "http-types", "req"]

{- | Parse the frozen cabal file through Cabal's own parser. Fails closed
with a named reason on any parse error rather than a partial answer.
-}
parseCabalFile :: IO (Either String GenericPackageDescription)
parseCabalFile = do
    contents <- BS.readFile cabalFilePath
    pure $ case runParseResult (parseGenericPackageDescription contents) of
        (_warnings, Left (_version, errs)) ->
            Left ("failed to parse " <> cabalFilePath <> ": " <> show (toList errs))
        (_warnings, Right gpd) -> Right gpd

{- | One named library component's data, aggregated across EVERY
conditional branch via 'Library''s own 'Monoid' instance -- never just the
unconditional top-level 'Distribution.Types.CondTree.condTreeData'
(A-011: a structured check must not silently ignore conditional
branches). A named reason if the component does not exist at all.
-}
namedLibrary :: String -> GenericPackageDescription -> Either String Library
namedLibrary name gpd =
    case lookup (mkUnqualComponentName name) (condSubLibraries gpd) of
        Nothing -> Left ("no `library " <> name <> "` component in " <> cabalFilePath)
        Just tree -> Right (fold tree)

{- | Every dependency token a 'Library' reaches: each dependency's package
name, plus (for an internal @pkg:sublib@ edge) every qualified sublibrary
name -- so e.g. @cardano-keri:chain-query-koios@ is caught by its
sublibrary name, not only its own (innocuous) package name.
-}
dependencyTokens :: Library -> [String]
dependencyTokens lib =
    concatMap dependencyIdentityTokens (targetBuildDepends (libBuildInfo lib))

dependencyIdentityTokens :: Dependency -> [String]
dependencyIdentityTokens dep =
    prettyShow (depPkgName dep)
        : [unUnqualComponentName subName | LSubLibName subName <- toList (depLibraries dep)]

hasForbiddenDependency :: [String] -> Bool
hasForbiddenDependency =
    any (\dep -> any (`isInfixOf` map toLower dep) forbiddenSubstrings)

exposedModuleNames :: Library -> [String]
exposedModuleNames = map prettyShow . exposedModules

spec :: Spec
spec = describe "MOD-240-WRITE-COMPOSITION component boundary (INV-240-NOPROVIDER)" $ do
    it "positive control: the boundary method can see a real forbidden dependency" $ do
        gpd <- parseCabalFile >>= either fail pure
        cliLib <- either fail pure (namedLibrary "cli" gpd)
        hasForbiddenDependency (dependencyTokens cliLib) `shouldBe` True

    it "exists as its own Cabal component, separate from the existing `cli` component" $ do
        gpd <- parseCabalFile >>= either fail pure
        either expectationFailure (const (pure ())) (namedLibrary "write-composition" gpd)

    it "has no Koios/HTTP/provider dependency edge (EDGE-240-04)" $ do
        gpd <- parseCabalFile >>= either fail pure
        case namedLibrary "write-composition" gpd of
            Left reason -> expectationFailure reason
            Right lib -> hasForbiddenDependency (dependencyTokens lib) `shouldBe` False

    it "receives the existing write command module (Cardano.KERI.Deployment.CLI)" $ do
        gpd <- parseCabalFile >>= either fail pure
        case namedLibrary "write-composition" gpd of
            Left reason -> expectationFailure reason
            Right lib ->
                any ("Cardano.KERI.Deployment.CLI" `isInfixOf`) (exposedModuleNames lib)
                    `shouldBe` True

    it "the existing `cli` component depends on write-composition, never the reverse (EDGE-240-02)" $ do
        gpd <- parseCabalFile >>= either fail pure
        cliLib <- either fail pure (namedLibrary "cli" gpd)
        any ("write-composition" `isInfixOf`) (dependencyTokens cliLib) `shouldBe` True
