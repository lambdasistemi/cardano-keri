# Feature specification — #266 GHC-derived public export surface

Artifact ceiling: 5,000 bytes and 130 lines.

## Outcome

The forward-looking #262 guard ranges over exactly the value-level exports GHC
reports for every Cabal-exposed library module in scope. Source spelling,
layout, comments, strings, and re-export form cannot remove a public route from
the guard.

## Requirements

- **RQ-266-01 — compiler-owned surface:** module membership remains derived
  from Cabal, while each module's public names and types come from GHC export
  information. No source lexer, export-list parser, per-name allowlist, or
  defining-module guess participates in enumeration.
- **RQ-266-02 — route identity:** a public member is keyed by the exposed
  module through which a consumer imports it and the exported name. A re-export
  is therefore a distinct route even when GHC attributes the name to another
  defining module.
- **RQ-266-03 — complete value coverage:** functions, operators, record field
  selectors, local re-exports, imported re-exports, and module re-exports join
  the derived set when GHC reports them as values with types.
- **RQ-266-04 — closed failure:** an exposed module that GHC cannot resolve or
  describe terminates enumeration with a diagnostic naming that module; an
  empty or missing source is never interpreted as an empty public surface.
- **RQ-266-05 — retained predicate:** the #262 qualifying-type, store-reaching,
  store-capability, and executable zero-effect rules retain their observable
  meaning. Only public-surface enumeration changes.
- **RQ-266-06 — permanent regressions:** controls cover nested block comments
  with fake headers, multiline `Type (..)` fields, nested capabilities,
  `module` in comments/Haddock/strings, imported and local re-exports, record
  fields, operators, defining-module signatures, and unavailable module/source
  inputs.

## Invariants

- **INV-266-DERIVED (BLOCKING):** the enumerated set equals GHC's public export
  information for every Cabal-exposed module in scope. A mutant dropping any
  compiler-reported value route must make the permanent guard RED.
- **INV-266-FALSIFIABLE (BLOCKING):** adding a qualifying public export without
  an executable zero-effect proof makes the compiled guard RED; restoring it
  makes the same guard GREEN, with both receipts retained.
- **INV-266-REGRESSIONS (BLOCKING):** every issue/comment regression shape is a
  permanent control whose positive and negative observations are non-vacuous.
- **INV-266-NO-REGRESSION (BLOCKING):** #262's behavioral proofs remain green
  and untouched; a named proof-removal mutant remains RED.

## Rejection behavior

- Missing GHC module information, missing value type information, or mismatch
  between Cabal-exposed modules and the queried compiler surface fails closed
  with the exposed route named.
- Types, constructors, and classes that are not callable value-level entries
  are classified explicitly rather than silently discarded.

## Non-goals

- Re-proving or changing the production `INV-262-SOLE-ROUTE` behavior.
- Changing production exports, runners, query semantics, or write paths.
- Replacing the source-derived call graph or rejectable-input derivation beyond
  adaptations strictly required to consume GHC-reported types.
- Publishing a general-purpose package in this ticket; the GHC boundary must
  nevertheless remain separable from the domain property.
