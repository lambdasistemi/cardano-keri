# Functions model

## Upstream verifier surface

- `mpf.insert(trie, key, value, proof)` first reconstructs the excluded root,
  then includes the new leaf. Both frozen regressions enter `excluding()`.
- Leaf-fork reconstruction selects the neighboring nibble after the skipped
  common prefix.
- Terminal-fork reconstruction prepends the skipped path nibbles before the
  neighbor prefix when `skip > 0`.
- `mpf.miss(trie, key, proof)` succeeds exactly when reconstructed exclusion
  equals the trie root.

## Repository mirror surface

- `MpfTrie.build/rootOf` constructs relative-prefix trie roots.
- `MpfProof.prove` currently walks inclusion paths and errors on an empty child.
  Extend it only if a repository acceptance test needs explicit non-membership.
- `ToData`/`FromData`/`UnsafeFromData ProofStep` preserve upstream constructor
  indices and field order.

## Gate behavior

For each fixture the gate creates two isolated Aiken projects with byte-identical
test source. It expects v2.0.0 `aiken check` to compile and fail its assertion,
and v2.1.0 to compile and pass. Resolution, import, or compiler errors are gate
failures, never accepted negative controls.
