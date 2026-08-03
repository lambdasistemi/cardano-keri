# Story 231: failures surface as raw GHC exception traces

**Created**: 2026-08-03
**Status**: Draft
**Input**: ckeri 0.2.0 funded-lifecycle experiment on preprod (feedback F5).

## Outcome

Every ckeri failure prints one actionable line on stderr and exits non-zero.
GHC internals stay out of operator-facing output.

## Observed behavior (0.2.0, every failure mode seen)

```
ckeri: Uncaught exception ghc-internal:GHC.Internal.IO.Exception.IOException:

user error (hash-proof premint needs two distinct plain funding UTxOs)

HasCallStack backtrace:
  bracket, called at ./System/IO/Temp.hs:114:3 in temporary-1.3-…
```

The actionable message is inside `user error (...)`; the wrapper and
backtrace are noise for operators and pollute scripted stderr.

## Root cause (verified in sources)

- `offchain/app/Ckeri.hs:7-12` — `main` runs `runInstructions` with no
  exception handler; every `fail` in the deployment/CLI layers escapes as an
  uncaught `IOException`.
- `fail` is used throughout for validation errors (e.g.
  `Registration.hs:655`, `CloseTransaction.hs:234-236`), which is the right
  structure — only the top-level rendering is missing.

## Acceptance scenarios

1. **Given** any validation failure (funding, manifests, signatures,
   guardrails), **When** ckeri exits, **Then** stderr carries the inner
   message on one line prefixed with `ckeri:`, exit code is non-zero, and
   no `ghc-internal`, `HasCallStack`, or package-qualified text appears.
2. **Given** `CKERI_DEBUG=1` (or a `--verbose` switch), **When** the same
   failure occurs, **Then** the current full trace is still available.
3. **Given** cardano-cli subprocess failures, **When** they occur, **Then**
   the relevant part of the subprocess stderr (the script evaluation or
   ledger error) is preserved in the one-line rendering, since it is often
   the actionable content.

## Out of scope

- Changing which conditions fail; only rendering and exit-code hygiene.
