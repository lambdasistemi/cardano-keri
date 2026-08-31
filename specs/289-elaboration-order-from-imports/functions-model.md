# functions model — #289

Shell functions. Signature-level contract only: names, argument names, what is
produced, and the effects that are part of the contract. Bodies, algorithms and
internal helpers belong to the commit owner.

## `offchain/blaster/elaborate-ilean-root.sh`

### New — `declared_local_imports staged_root relative`

| | |
|---|---|
| `staged_root` | absolute path of the staging directory holding the byte-identical copies |
| `relative` | tracked relative path of one module, e.g. `KeriBlaster/S2Cek.lean` |
| stdout | zero or more tracked relative paths, one per line: the modules this module declares an import of, restricted to the tracked `KeriBlaster` namespace |
| exit | zero; an unresolvable name is not this function's decision |

Reads the staged copy, not the original source, so the relation is derived from
the exact bytes that will be compiled.

### New — `derive_compile_order staged_root relative...`

| | |
|---|---|
| `staged_root` | as above |
| `relative...` | the tracked non-root relative paths, in arbitrary order |
| stdout | the same paths, one per line, in a topological order of the declared-import relation |
| exit | non-zero via the script's existing failure path on V1 or V2 |
| effects | performs V1 and V2; must complete before any elaboration occurs |

Output is a permutation of the input: same multiset, reordered. The aggregate
root is not passed to it and is not returned by it.

### Changed — `fail message...`

Unchanged signature. Its single hardcoded discovery line becomes
class-dependent, so that the existing build-root-provenance class and the two
new classes are distinguishable by their `layer=` token in captured stderr. The
exact token spellings are the commit owner's, subject to being asserted by the
controls.

### Changed — compile driver

The sequence fed to `compile_source` comes from `derive_compile_order` instead
of `sort`. `compile_source` itself is unchanged, as is the separate
aggregate-root-last invocation.

## `offchain/blaster/test-elaboration-order.sh` (new)

Positional arguments, following the convention of the sibling harnesses:

| Position | Name | Meaning |
|---|---|---|
| 1 | `elaborator` | executable under test |
| 2 | `build_root` | pinned dependency root |
| 3 | `source_root` | tracked source root |
| 4 | `artifact_root` | S2 artifact root |

| | |
|---|---|
| stdout | one evidence line per control, in the established `RED-PROOF invariant=<ID> mutation=<name> outcome=REFUTED` shape, plus a final `PASS:` line |
| exit | zero only when every control both applied and produced its required outcome |

A control that could not be applied is a failure, never a skip.
