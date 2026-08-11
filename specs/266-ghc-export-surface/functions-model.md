# Functions model — #266 GHC-derived public export surface

Artifact ceiling: 3,500 bytes and 100 lines.

Only new or changed signatures are modeled. Responsibilities are in
`modules-model.md`; values and invariants are in `data-model.md`.

## Compiler surface

- **FUN-266-SESSION:** `withCompilerExportSession action -> IO result`
- **FUN-266-MODULE:** `publicValuesOf session routeModule -> IO [PublicValue]`
- **FUN-266-SURFACE:** `publicValuesOfModules session routeModules -> IO [PublicValue]`

Constraints:

- one session serves the complete enumeration;
- result membership is derived from GHC module information;
- only callable value-level names carry an exported type;
- any unresolved requested module or value type returns a named terminal
  failure rather than a partial result.

## Guard integration

- **FUN-266-EXPORTED:** `exportedSignaturesOf routeModule -> IO [(exportedName, exportedType)]`

Constraints:

- preserves the consumer-visible route module independently of defining
  identity;
- delegates export membership and types to **FUN-266-MODULE**;
- retains the existing downstream qualification and coverage semantics;
- has no Haskell-source input.

Exact internal GHC types may replace these domain-neutral spellings if required
by the pinned API; the argument/result relationships and failure effects are
fixed.
