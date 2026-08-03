# Blaster tractability boundary

This slice establishes a reproducible input boundary for later Blaster
properties. It does not add a solver theorem or a kernel proof.

## Production UPLC source

The only production input is the `plutus-blueprint` derivation wired by
`offchain/flake.nix`. The `blaster` app accepts no blueprint path and does not
search the current directory, environment variables, or ambient files. It
selects exactly one validator titled `checkpoint.checkpoint.spend`, requires a
non-empty string `compiledCode`, and rejects missing, renamed, malformed, or
duplicate matches.

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

## Pinned trust base

The checked lock file records immutable revisions and NAR hashes for the full
remote closure. The principal identities audited at runtime are:

| Component | Version or revision | Source identity |
| --- | --- | --- |
| Lean | `v4.24.0` | `leanprover/lean4:v4.24.0` |
| Lean-Blaster | `d57a9079a164ca25e58f119112162efea617b5e6` | `sha256-pXH5QpO7bJEmmtfOTkSdU31lF6tVZROjRLea+i+Hya0=` |
| PlutusCoreBlaster | `17cee18a2058790bca36282d82c19146587fb2d1` | `sha256-tzdKOl9R9f/N1uQ2Algk6zTbbb119uBGByejNQOOe1U=` |
| CardanoLedgerApiBlaster | `577e3eb03b5be09354cfdb1c0d0c12e9e16541a0` | `sha256-EORoTM/YbdjV7sc+7e1VTl7IuP2IyIgBvT0Oe9HhxSk=` |
| lean4-nix | `faebfa2e0d7093fea3ffaa493b316bf3449c1dbf` | `sha256-D3PN4o8RtyHEjlAtsLa6M9xRjIwtMUk4pIkfsNSMAvQ=` |
| Lean nixpkgs | `1306659b587dc277866c7b69eb97e5f07864d8c4` | `sha256-KJ2wa/BLSrTqDjbfyNx70ov/HdgNBCBBSQP3BIzKnv4=` |
| Z3 | `4.15.2` (`z3-4.15.2`) | `sha256-hUGZdr0VPxZ0mEUpcck1AC0MpyZMjiMw/kK8WX7t0xU=` |
| Aiken | `1.1.21` | nixpkgs `13043924aaa7375ce482ebe2494338e058282925`, `sha256-nwASzrRDD1JBEu/o8ekKYEXm/oJW6EMCzCRdrwcLe90=` |

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
