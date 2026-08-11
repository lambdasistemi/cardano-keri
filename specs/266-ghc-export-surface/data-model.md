# Data model — #266 GHC-derived public export surface

Artifact ceiling: 3,500 bytes and 100 lines.

## New data

### DAT-266-PUBLIC-VALUE — compiler-reported public route

Fields:

- `routeModule`: the Cabal-exposed module a consumer imports;
- `exportedName`: the occurrence GHC reports on that route;
- `definingIdentity`: GHC's stable identity for the underlying name;
- `exportedType`: the value type supplied by GHC.

The route key is `(routeModule, exportedName)`. Defining identity may coincide
across re-exports but never collapses distinct public routes.

### DAT-266-SURFACE-FAILURE — closed compiler query failure

Fields:

- requested exposed module;
- failed phase: module resolution, module information, or value type;
- compiler diagnostic context.

Failure is terminal for the derived surface. It is never converted to an empty
module or omitted member.

## State invariants

- **DATA-INV-266-01:** every Cabal-exposed module in scope produces GHC module
  information or one named terminal failure.
- **DATA-INV-266-02:** every GHC-reported callable value produces exactly one
  **DAT-266-PUBLIC-VALUE** on that public route.
- **DATA-INV-266-03:** source spelling and source readability are absent from
  successful export membership; compiled GHC information is the sole source.
- **DATA-INV-266-04:** distinct re-export routes remain distinct even when
  `definingIdentity` is equal.
