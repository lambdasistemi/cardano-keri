import PlutusCore.UPLC

/-!
Fail-closed reference-discovery seed.

A bare upstream `open` makes later unqualified identifiers depend on a pinned
package without spelling the namespace beside each use.  The tracked collector
deliberately supports selective `open Namespace (member, ...)` declarations,
where every imported member is enumerable.  It must reject this broader form
as `COULD-NOT-EVALUATE` instead of silently publishing a smaller denominator.

This file is consumed only by the collector-narrowing self-test.  It is not
imported by the tracked bridge.
-/

open PlutusCore.UPLC

#check Program
