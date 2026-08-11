# Implementation plan — #266 GHC-derived public export surface

Artifact ceiling: 5,000 bytes and 130 lines.

## Durable design decision

Use the GHC 9.12.3 API over compiled package modules. Cabal continues to own
the exposed-module seed; GHC `ModuleInfo` owns the resolved export names and
GHC owns their types. HIE files are rejected because this build does not
produce them and doing so would add a second generated-artifact contract.
`ghc-lib-parser` is rejected because syntax parsing alone cannot resolve
imports, module re-exports, generated selectors, or types.

The compiler-facing responsibility is separated from the #262 domain
predicate so it can be extracted later without moving chain-query behavior.
The ticket itself does not publish a new package.

## Strategy

One OWNER slice replaces the source-derived export enumeration, supplies
compiled regression fixtures for every legal spelling/export shape, and
retains the existing zero-effect coverage rule.

1. Introduce a test-support boundary that queries one Cabal-exposed route from
   a configured GHC session and returns compiler-reported value names/types.
2. Seed that boundary from all conditional Cabal library components and fail
   closed when a seeded module has no GHC information.
3. Replace only the export/signature source reader in the #262 guard; retain
   its public-route key and qualification/coverage semantics.
4. Add compiled fixture modules for lexical/layout/re-export controls and
   unavailable-input controls for failure behavior.
5. Demonstrate the qualifying-export seed RED and restored GREEN, retain the
   unchanged #262 behavioral proof results, and remove obsolete scanner code.

## Constraints

- Frozen base is `085367270536afc175ed9628d6992263145ce903`, #262's branch
  head. Rebase onto `main` only after PR #264 merges.
- Base build budget is 10 plus a repair reserve of 4 for audit findings only.
- The free readiness barrier precedes every allocated gate run.
- Expected dependency change is the compiler-bundled `ghc` library in the
  local-write-path test suite. `flake.nix` is not expected to change; if both
  it and Cabal metadata change, `ci-onchain` and #259's no-write-lock guard join
  each submission gate.
- Production modules, #262 behavioral tests, and documentation are outside the
  writable fence.
- No ticket-owner edits to implementation, proof, fixtures, dependencies, or
  generated output.

## Verification

- focused #266 compiler-surface and regression controls;
- qualifying unsafe export RED, restored GREEN, both compiled;
- exact GHC-versus-derived route equality with non-empty controls;
- unchanged #262 local-write-path behavioral proofs;
- `ci-offchain`, format, HLint, diff/path/tree gates, and final root CI within
  the declared budget.
