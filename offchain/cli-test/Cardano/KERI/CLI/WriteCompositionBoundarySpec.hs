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
import Data.List (isInfixOf, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Distribution.Fields.ParseResult (runParseResult)
import Distribution.PackageDescription.Parsec (parseGenericPackageDescription)
import Distribution.Pretty (prettyShow)
import Distribution.Types.BuildInfo (targetBuildDepends)
import Distribution.Types.Dependency (Dependency, depLibraries, depPkgName)
import Distribution.Types.GenericPackageDescription (
    GenericPackageDescription (condLibrary, condSubLibraries),
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

-- | The module the registry commands of the new design are exposed by.
registryCommandModule :: String
registryCommandModule = "Cardano.KERI.Deployment.RegistryCommand"

-- | The component exposing a module, with its aggregated data.
libraryExposing :: String -> GenericPackageDescription -> Either String (String, Library)
libraryExposing moduleName gpd =
    case [ (unUnqualComponentName name, lib)
         | (name, tree) <- condSubLibraries gpd
         , let lib = fold tree
         , moduleName `elem` exposedModuleNames lib
         ] of
        [one] -> Right one
        found -> Left (moduleName <> " is exposed by " <> show (length found) <> " components")

{- | One dependency edge of a library: a package, the sublibraries it
names, and whether it names the package's main library.
-}
data Edge = Edge
    { edgePackage :: String
    , edgeSubLibraries :: [String]
    , edgeMain :: Bool
    }

-- | A library: its exposed modules and its dependency edges.
data Node = Node
    { nodeModules :: [String]
    , nodeEdges :: [Edge]
    }

-- | The libraries of this package by name; the main library carries the package name.
type Graph = Map String Node

packageName :: String
packageName = "cardano-keri"

internalSub :: String -> Edge
internalSub name = Edge packageName [name] False

nodeOf :: Library -> Node
nodeOf lib =
    Node
        (exposedModuleNames lib)
        (map toEdge (targetBuildDepends (libBuildInfo lib)))
  where
    toEdge dep =
        Edge
            (prettyShow (depPkgName dep))
            [unUnqualComponentName n | LSubLibName n <- toList (depLibraries dep)]
            (LMainLibName `elem` depLibraries dep)

libraryGraph :: GenericPackageDescription -> Either String Graph
libraryGraph gpd = do
    mainTree <-
        maybe (Left ("no main library in " <> cabalFilePath)) Right (condLibrary gpd)
    pure . Map.fromList $
        (packageName, nodeOf (fold mainTree))
            : [ (unUnqualComponentName name, nodeOf (fold tree))
              | (name, tree) <- condSubLibraries gpd
              ]

-- | The libraries of this package an edge names.
internalTargets :: Edge -> [String]
internalTargets edge
    | edgePackage edge /= packageName = []
    | otherwise = [packageName | edgeMain edge] <> edgeSubLibraries edge

{- | Every library of the package a library can import from: itself and
everything reached through internal edges. A write module imports only the
exposed modules of its direct dependencies, and each of those brings its own
dependencies, so the whole reach has to be free of a provider.
-}
reachableFrom :: Graph -> String -> [String]
reachableFrom graph root = go [] [root]
  where
    go seen [] = sort seen
    go seen (lib : rest)
        | lib `elem` seen = go seen rest
        | otherwise =
            go
                (lib : seen)
                (rest <> concatMap internalTargets (maybe [] nodeEdges (Map.lookup lib graph)))

{- | Package and sublibrary names that bring a provider client. The list of
the direct check above stays as it is; this one leaves out @http-types@,
which the query server of @indexer@ uses as HTTP vocabulary and which is not
a provider client.
-}
providerClientSubstrings :: [String]
providerClientSubstrings = ["koios", "http-conduit", "http-client", "req"]

{- | Why a library in the reach of the root is a provider: it exposes a
Koios module, depends on a provider client, or has any edge to Singular's
package. Singular's main library holds the Koios client and its other
sublibraries can wrap a call that reaches it behind a neutral name, so the
edge itself is refused, whatever the sublibrary is called. The one library
let through is 'singularAllowlist', and only while its exposed modules are
pinned.
-}
providerReach :: Graph -> String -> [String]
providerReach graph root =
    concat
        [ [lib <> " exposes " <> m | m <- nodeModules node, "koios" `isInfixOf` map toLower m]
            <> [lib <> " depends on " <> edgeName edge | edge <- nodeEdges node, providerEdge edge]
            <> [ lib <> " depends on " <> edgeName edge
               | edge <- nodeEdges node
               , edgePackage edge == singularPackage
               , not (singularAllowed graph lib)
               ]
        | lib <- reachableFrom graph root
        , let node = fromMaybe (Node [] []) (Map.lookup lib graph)
        ]
  where
    edgeName edge = edgePackage edge <> concatMap (':' :) (edgeSubLibraries edge)

providerEdge :: Edge -> Bool
providerEdge edge =
    any
        (\token -> any (`isInfixOf` map toLower token) providerClientSubstrings)
        (edgePackage edge : edgeSubLibraries edge)

singularPackage :: String
singularPackage = "singular-registry"

{- | The closed allowlist of libraries that may depend on Singular's package:
@key-source@ (#553). It depends on @registry-cli@ to open a wallet vault and
for nothing else, and it exposes the one key-opening module; a second
exposed module there is a new route into Singular's command line and is
refused. It is also kept out of the reach of write-composition (see the
example on the registry commands), so the allowlist is a second wall.
-}
singularAllowlist :: [(String, [String])]
singularAllowlist = [("key-source", ["Cardano.KERI.Deployment.RegistryKeySource"])]

singularAllowed :: Graph -> String -> Bool
singularAllowed graph lib =
    case lookup lib singularAllowlist of
        Nothing -> False
        Just pinned -> maybe False ((== pinned) . nodeModules) (Map.lookup lib graph)

plantEdge :: String -> Edge -> Graph -> Graph
plantEdge lib edge = Map.adjust (\n -> n{nodeEdges = edge : nodeEdges n}) lib

plantModule :: String -> String -> Graph -> Graph
plantModule lib m = Map.adjust (\n -> n{nodeModules = m : nodeModules n}) lib

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

    it "#553 holds Singular's command-line library in the key-source library alone: the write component names no edge to it, so none of its modules can be imported by a write module" $ do
        gpd <- parseCabalFile >>= either fail pure
        keySource <- either fail pure (namedLibrary "key-source" gpd)
        writeLib <- either fail pure (namedLibrary "write-composition" gpd)
        -- positive control: the method sees the edge where it is
        any ("registry-cli" `isInfixOf`) (dependencyTokens keySource) `shouldBe` True
        any ("registry-cli" `isInfixOf`) (dependencyTokens writeLib) `shouldBe` False
        -- the key source is held by the component that exposes the registry
        -- commands, and that component is not one write-composition reaches
        graph <- either fail pure (libraryGraph gpd)
        (home, homeLib) <- either fail pure (libraryExposing registryCommandModule gpd)
        any ("key-source" `isInfixOf`) (dependencyTokens homeLib) `shouldBe` True
        home `shouldNotBe` "write-composition"
        reachableFrom graph "write-composition" `shouldNotContain` [home]
        reachableFrom graph "write-composition" `shouldNotContain` ["key-source"]

    it "no library write-composition can reach exposes a provider module or depends on a provider package" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        providerReach graph "write-composition" `shouldBe` []

    it "the reach of write-composition is the internal graph it can import, not an empty or truncated one" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        let reach = reachableFrom graph "write-composition"
        mapM_
            (\lib -> reach `shouldContain` [lib])
            ["write-composition", "deployment", "chain-query", "indexer", "cardano-keri"]

    it "positive control: the reach check refuses `cli`, whose reach holds the Koios interpreter" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        providerReach graph "cli" `shouldNotBe` []

    it "positive control: the reach check refuses a Koios library planted on write-composition" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        providerReach
            (plantEdge "write-composition" (internalSub "chain-query-koios") graph)
            "write-composition"
            `shouldNotBe` []

    it "positive control: the reach check refuses Singular's main library planted on write-composition" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        providerReach
            (plantEdge "write-composition" (Edge "singular-registry" [] True) graph)
            "write-composition"
            `shouldNotBe` []

    it "positive control: the reach check refuses a Koios module planted in a library write-composition reaches" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        providerReach
            (plantModule "indexer" "Cardano.KERI.Indexer.KoiosRuntime" graph)
            "write-composition"
            `shouldNotBe` []

    it "positive control: the reach check refuses Singular's command-line library planted on a library write-composition reaches" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        providerReach
            (plantEdge "deployment" (Edge "singular-registry" ["registry-cli"] False) graph)
            "write-composition"
            `shouldNotBe` []

    it "the key-source library, the only one allowed to depend on Singular, exposes the one key-opening module; a second module there is refused" $ do
        gpd <- parseCabalFile >>= either fail pure
        graph <- either fail pure (libraryGraph gpd)
        let reaching = plantEdge "write-composition" (internalSub "key-source")
        -- the allowed library passes while pinned, and is refused once it grows
        providerReach (reaching graph) "write-composition" `shouldBe` []
        providerReach
            (plantModule "key-source" "Cardano.KERI.Deployment.RegistryKeySourceMore" (reaching graph))
            "write-composition"
            `shouldNotBe` []
        fmap nodeModules (Map.lookup "key-source" graph)
            `shouldBe` Just ["Cardano.KERI.Deployment.RegistryKeySource"]

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

    it "positive control: the store-route method can see a real store dependency (the `indexer` component genuinely has one)" $ do
        gpd <- parseCabalFile >>= either fail pure
        indexerLib <- either fail pure (namedLibrary "indexer" gpd)
        hasStoreDependency (dependencyTokens indexerLib) `shouldBe` True

    it "#262 INV-262-SOLE-ROUTE: has no store-transaction dependency edge at all, so no direct local acquisition route is even nameable (EDGE-262-05)" $ do
        gpd <- parseCabalFile >>= either fail pure
        case namedLibrary "write-composition" gpd of
            Left reason -> expectationFailure reason
            Right lib -> hasStoreDependency (dependencyTokens lib) `shouldBe` False

{- | Package\/sublibrary tokens that make a component able to open, compose,
or name a local store transaction.

\#262 (INV-262-SOLE-ROUTE): once every build-phase read routes through the
local interpreter, write composition needs neither of these, and the Cabal
graph is what makes that a guarantee rather than a habit. A source scan can
say "this module contains no direct route today"; this says a direct route
cannot be WRITTEN, because the types it would need are not in scope for the
component at all. That is the same argument MOD-240-WRITE-COMPOSITION makes
for the provider boundary above, applied to the store.

@-Wunused-packages@ is the reason this is cheap to keep honest: the component
cannot carry either dependency without using it, so the graph and the source
cannot drift apart in the harmless direction either.
-}
storeDependencySubstrings :: [String]
storeDependencySubstrings = ["rocksdb", "kv-transactions", "utxo-indexer"]

hasStoreDependency :: [String] -> Bool
hasStoreDependency =
    any (\dep -> any (`isInfixOf` map toLower dep) storeDependencySubstrings)
