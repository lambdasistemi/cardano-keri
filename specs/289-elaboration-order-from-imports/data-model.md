# data model — #289

## Tracked module

The unit the elaborator already handles. Fields it already carries, restated
because the ordering relation is defined over them:

| Field | Meaning |
|---|---|
| relative path | path under the source root, e.g. `KeriBlaster/S2Cek.lean` |
| module name | dotted form of the relative path with `.lean` removed, e.g. `KeriBlaster.S2Cek` |
| staged copy | the byte-identical copy the script places in its staging directory |

The relative path and the module name are two spellings of one identity. The
existing `.ilean` identity check already asserts the compiled artifact agrees
with the module name, so nothing here introduces a second source of truth.

## Declared local import

A new derived relation, read from the staged copy of each tracked module.

| Field | Meaning |
|---|---|
| importer | the tracked module the import statement appears in |
| imported module name | the `KeriBlaster.*` module named by the import |

Scope: only imports naming a module inside the tracked `KeriBlaster` namespace.
Imports of pinned upstream packages are supplied by the dependency root, are not
elaborated by this script, and are not part of this relation.

## Validation

- **V1** Every imported module name in the relation resolves to a tracked module
  in the current input set. An unresolved name is R3's abort, not a skip.
- **V2** The relation restricted to the tracked set is acyclic. A cycle is R4's
  abort.
- **V3** The aggregate root `KeriBlaster.lean` is excluded from the relation and
  from the derived order; it is compiled last under the existing rule.

## State invariants

- **S1** At the moment a module is elaborated, every module it declares an
  import of has already been elaborated into the output root. This is the
  property the whole ticket exists to establish.
- **S2** The derived order is total over the tracked non-root set and contains
  each module exactly once. The existing duplicate-source rejection continues to
  guarantee the input set has no repeats.
- **S3** The derived order is a pure function of the input set: same set, same
  order, independent of argument order and of directory enumeration order. Ties
  between mutually independent modules resolve by a stated deterministic rule.
- **S4** Validation completes before the first elaboration, so a V1 or V2
  failure leaves the output root with nothing compiled in it.
