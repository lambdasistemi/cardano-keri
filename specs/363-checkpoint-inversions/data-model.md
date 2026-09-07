# Data model — #363 Checkpoint constructor inversions

Artifact ceiling: 4,000 bytes and 90 lines.

This ticket adds no runtime or on-chain data. These are proof-surface records.

## DAT-363-CONSTRUCTOR-ROW

One row derived from one compiled `Checkpoint.Step` constructor:

- fully qualified constructor identity;
- explicit non-proof parameters in constructor order;
- proof premises in constructor order;
- exact `Step` result indices: action, slot, source, flow, successor;
- the one bound public inversion declaration.

The live row set is non-empty and derived after importing `CardanoKeri`.

## DAT-363-INVERSION-TYPE

The canonical public proposition for a constructor row universally binds its
non-proof parameters, places the exact `Step` result at the left of `Iff`, and
places every constructor proof premise exactly once and in order at the right.
The right side is `True` for a constructor with no proof premise. Definitional
equality is permitted; weakening, duplication, substitution, reordering, or a
different constructor result is not.

## DAT-363-COVERAGE-RECEIPT

The compiled check reports denominator, numerator, constructor identities,
bound inversion identities, and exact-type verdict. A zero denominator,
unresolved declaration, duplicate binding, or non-exact type is failure.

## DAT-363-MUTATION-RECEIPT

Each required failure-class row records base/candidate identity, mutation
class, exact edit count, setup/model compile result when applicable, gate exit,
failure marker, evidence path/hash, and restored-tree result. Only intended
checker failures count.

