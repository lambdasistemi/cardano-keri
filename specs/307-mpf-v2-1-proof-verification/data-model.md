# Data model

## Frozen fixtures

### F1 — leaf fork with common prefix

The upstream `phil` proof is an ordered `Proof` containing four `Branch`
steps followed by `Leaf(skip = 1, ...)` and `Leaf(skip = 0, ...)`. Its input
root, inserted key/value, and expected output root are fixed byte arrays copied
from the v2.0.1 upstream regression.

### F2 — terminal fork with non-empty prefix

The upstream `edge_case4` proof is three `Branch(skip = 0, ...)` steps followed
by a terminal `Fork(skip = 1, Neighbor(nibble = 12, prefix = #"", root = ...))`.
Its input root, inserted key/value, and expected output root are fixed byte
arrays copied from the v2.1.0 upstream regression.

## Proof wire format

- `Branch`: constructor 0, integer `skip`, byte-array `neighbors`.
- `Fork`: constructor 1, integer `skip`, `Neighbor` constructor 0 containing
  integer nibble, byte-array prefix, byte-array root.
- `Leaf`: constructor 2, integer `skip`, byte-array key, byte-array value.

Fixture bytes are immutable oracles. The old/new control changes only the MPF
dependency version; input data and assertions must hash identically.
