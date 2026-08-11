# Blaster tractability boundary

This slice establishes a reproducible input boundary for later Blaster
properties. It does not add a solver theorem or a kernel proof.

## Historical pre-#219 baseline (retained, not P0 evidence)

Historical evidence identity: `PlutusV3 / pre-Conway / defaultFunSemanticsVariantC`.

The identities in this section are the retired pre-#219 measurement. They are
retained as evidence of a different configuration and cannot satisfy a P0
claim. In particular, they are not the post-Conway E baseline frozen below.

The historical runner accepted no blueprint path, selected exactly one
validator titled `checkpoint.checkpoint.spend`, required non-empty
`compiledCode`, and rejected missing, renamed, malformed, or duplicate matches.

The current audited identities are:

- blueprint SHA-256:
  `896d2c4642740a26248dc46cdeecbce18730061785e78cfbedc2a13a5c9c577c`
- selected program SHA-256:
  `713c747bc83226c71fdcf6b6c174832fd4f69d738439842990d68e163ac26a9a`
- validator title and cardinality: `checkpoint.checkpoint.spend`, exactly one

`nix build ./offchain#blaster` builds the runnable package and its
Lean/artifact closure; building the package does not execute its shell audit.
`nix run ./offchain#blaster` and `just blaster` execute the app. `nix build
./offchain#checks.x86_64-linux.blaster` executes that exact app through the
flake's `runCommand` check. The closure also compiles the minimal
`KeriBlaster` root importing Blaster, PlutusCore UPLC, and Cardano Ledger API
V3.

## Frozen post-Conway baseline

The current baseline is rebuilt from the tracked Aiken source by the ordinary
input-addressed `plutus-blueprint` derivation. Its identity is
`4e840934deeb55aa9fd45a34fc516bb4c635bf81 + Aiken 1.1.23 +
defaultFunSemanticsVariantE`, with ledger language `PlutusV3` and era
`post-Conway`. The program-version-derived value remains separately named as
`defaultFunSemanticsVariantC`; it is historical selection information and
cannot stand in for the explicit E evaluation identity.

The flake-owned runner computes and publishes the complete manifest rather
than duplicating its values in this document: 23 title rows, their parameter
counts and program SHA-256 values, eight distinct program hashes, and the
blueprint SHA-256. The standing identity checker recomputes those values from
the source-built blueprint and reconciles every carried record, verification
receipts included.

## Pinned trust base

The checked lock file records immutable revisions and NAR hashes for the full
remote closure. The principal identities audited at runtime are:

| Component | Version or revision | Source identity |
| --- | --- | --- |
| Lean | `v4.24.0` | `leanprover/lean4:v4.24.0` |
| Lean-Blaster | `62d2d59abda37e90097e655b40e27545bba16f3c` | `sha256-c3+XHSj1KJ3P0O7Mp23vXhXdgrkeP/DSc9qfCoQXyOM=` |
| PlutusCoreBlaster | `7cf5a78c54b9694ef093bf49edb5d3799b2a49c9` | `sha256-Nq6wG/XMeWubb1PXPhuD62jhmQe8Dy61ZFNZfeFYgTg=` |
| CardanoLedgerApiBlaster | `577e3eb03b5be09354cfdb1c0d0c12e9e16541a0` | `sha256-EORoTM/YbdjV7sc+7e1VTl7IuP2IyIgBvT0Oe9HhxSk=` |
| lean4-nix | `faebfa2e0d7093fea3ffaa493b316bf3449c1dbf` | `sha256-D3PN4o8RtyHEjlAtsLa6M9xRjIwtMUk4pIkfsNSMAvQ=` |
| Lean nixpkgs | `1306659b587dc277866c7b69eb97e5f07864d8c4` | `sha256-KJ2wa/BLSrTqDjbfyNx70ov/HdgNBCBBSQP3BIzKnv4=` |
| Z3 | `4.15.2` (`z3-4.15.2`) | `sha256-hUGZdr0VPxZ0mEUpcck1AC0MpyZMjiMw/kK8WX7t0xU=` |
| Aiken | `1.1.23` | nixpkgs `753cc8a3a87467296ddd1fa93f0cc3e81120ee46`, `sha256-KesHgItiZPgGX740axSiQLcIQ8D24MDqNpkKYWIek8k=` |

Warnings emitted while compiling this pinned upstream graph remain visible.
In particular, the current PlutusCore dependency emits an upstream `sorry`
warning; the local `KeriBlaster` root is separately rejected if it contains
`sorry` or `axiom`. A future successful SMT query must be labelled exactly
`SMT-VALID (no proof term)`, never `KERNEL-PROVED`.

## Bump ownership

The Cardano-KERI maintainer changing the Blaster boundary owns the coordinated
revision bump, lock refresh, warning review, and re-audit. First edit the exact
revision URLs for the three principal inputs in `offchain/flake.nix`. Update
the coordinated Lean toolchain and Z3 version/source hash pins too when the
selected dependency graph requires it. Then refresh those lock entries:

```console
cd offchain
nix flake update leanBlaster plutusCoreBlaster cardanoLedgerApiBlaster
```

Review every transitive lock change, then verify from the same directory:

```console
cd offchain
nix build .#checks.x86_64-linux.blaster
```

A green build is required before the new identities replace this table.
