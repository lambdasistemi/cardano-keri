# Story 227: release artifacts cannot complete advance/close signing

**Created**: 2026-08-03
**Status**: Draft
**Input**: ckeri 0.2.0 funded-lifecycle experiment on preprod (feedback F2).

## Outcome

An operator who installs ckeri from release artifacts (AppImage/deb/rpm)
can complete the two-phase `advance` and `close` flows without discovering
helper scripts that live only in the source tree.

Phase 1 of both verbs emits a binary signing package
(`advance-message.cbor` / `close-message.cbor` plus `package.json`). Phase 2
consumes `--controller-signatures` — bare indexed CESR signatures over the
package preimage. Producing those signatures today requires
`scripts/kli-sign-advance.py` and `scripts/kli-sign-close.py` run inside a
keripy/kli environment.

## Root cause (verified in 0.2.0 sources)

- The signing helpers exist only at `scripts/kli-sign-advance.py` and
  `scripts/kli-sign-close.py` in the repository.
- Nothing in `.github/workflows/release.yml` or `scripts/release/` packages
  or uploads them; the release asset list is the binaries, packages, and the
  transcript log only.
- No `--help` text for `advance`/`close` phase 1 points at the helpers or
  documents the signing contract.

The signing contract itself is clean and offline/HSM-friendly (schema-tagged
`package.json`, CBOR preimage, printed sha256 — see Story 161's signing
boundary). The gap is purely distribution and documentation.

## Acceptance scenarios

1. **Given** a release download on a clean machine, **When** the operator
   finishes phase 1 of `advance`, **Then** the output tells them exactly
   what to sign, with what keys, in what output format, and where to find a
   reference signer shipped with the release.
2. **Given** only the release notes and artifacts, **When** a third party
   implements their own signer, **Then** the documented contract (preimage =
   the exact package cbor bytes; signatures = bare indexed CESR over it with
   the current controller keys) is sufficient to produce an accepted
   `--controller-signatures` file.

## Suggested directions

1. Ship the two helper scripts as release assets and reference them in
   phase-1 output and `--help`.
2. Document the signing contract in the repo (spec or README section) so
   non-keripy tooling can interoperate.
3. Longer term: an optional `--kli-command` style integration so ckeri can
   drive signing directly (separate decision).

## Out of scope

- Changing the package schema or signature format (frozen protocol surface).
