# Modules model

| Module | Role | Allowed change |
|---|---|---|
| `onchain/aiken.toml` | Declared Aiken dependency | v2.0.0 → v2.1.0 |
| `onchain/aiken.lock` | Resolved package metadata | coherent v2.1.0 record |
| `offchain/flake.nix` | Hermetic source/cache package | tag, hash, package metadata/layout |
| `onchain/lib/**` | Aiken consumers/tests | focused regression/oracle tests; cage behavior unchanged |
| `offchain/e2e/**/MpfTrie.hs` | Haskell trie/root mirror | only if v2.1.0 semantics require it |
| `offchain/e2e/**/MpfProof.hs` | Haskell proof mirror | non-membership support only if needed for byte-identity proof |
| `offchain/lib/**/Cage/Types.hs` | `ProofStep` wire encoding | no encoding change unless upstream incompatibility is proven |
| `offchain/test`, `offchain/e2e` | Permanent cross-language checks | focused fixtures and assertions |

The ignored root `gate.sh` and `/tmp/keri/m12/t307` evidence are ticket-owner
artifacts, not production deliverables.
