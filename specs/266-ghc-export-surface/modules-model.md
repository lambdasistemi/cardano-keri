# Modules model — #266 GHC-derived public export surface

Artifact ceiling: 4,000 bytes and 110 lines.

## Changed responsibilities

### MOD-266-COMPILER-SURFACE — reusable test-support boundary

- Owns one configured GHC session and resolves the public value exports and
  types for requested package modules.
- Preserves both the public route module and GHC's defining-name identity.
- Fails closed when GHC cannot resolve a requested module or value type.
- Has no chain-query qualification or zero-effect knowledge.

### MOD-266-CABAL-SEED — exposed-module discovery

- Continues to parse Cabal metadata with Cabal's parser and folds every
  conditional library component.
- Supplies exposed module routes to **MOD-266-COMPILER-SURFACE**.
- Does not locate or read Haskell source files for export enumeration.

### MOD-266-PUBLIC-GUARD — #262 property consumer

- Consumes compiler-reported public values and applies the existing
  rejectable-input, effect, store-reaching, capability, and proof-coverage
  rules.
- Keeps `(route module, export)` membership and executable zero-effect coverage.
- Owns compiled regression fixtures only as proof inputs, not as an alternate
  export parser.

## Dependency direction

- **EDGE-266-01:** public guard → Cabal seed → compiler-surface boundary.
- **EDGE-266-02:** public guard → #262 proof actions and existing qualification
  rules.
- **EDGE-266-03:** compiler-surface boundary has no dependency on chain-query
  domain code.
- **EDGE-266-04:** no export enumeration depends on source bytes, paths,
  comments, strings, layout, or locally reconstructed export syntax.

## Promotion decision

- **PROMOTE-266-01:** isolate compiler introspection at the nearest reusable
  test-support boundary, while retaining it inside this package for #266.
- **PROMOTE-266-02:** retain Cabal as module-set authority and GHC as
  export/type authority; neither duplicates the other's role.
