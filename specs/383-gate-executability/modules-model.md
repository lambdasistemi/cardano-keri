# Issue 383 modules model

Artifact ceiling: 2,500 bytes / 70 lines.

| ID | Component | Responsibility | Dependency direction |
|---|---|---|---|
| M383-01 | campaign subject manifest | Bind the complete #365 campaign subject to exact Git blobs at `127f2e8` | Authority input; depends only on Git object identity |
| M383-02 | gate-v6 | Execute the unchanged v5 acceptance program after the one-byte line-23 repair | Depends on M383-01 and the existing runner; never on hand-written verdicts |
| M383-03 | control ledger | Demonstrate every M383-02 predicate can fail for its intended reason, including runner reachability | Depends on frozen M383-02 and disposable inputs only |
| M383-04 | supersession record | Preserve v5/v6 hashes, exact diff, authority, F-365-001 lineage, and retained campaign identity | Depends on M383-01 through M383-03; contains no acceptance by itself |
| M383-05 | v6 execution evidence | Full raw output, campaign tables, axiom account, pre/post identity and compact receipt from the sole authorized run | Emitted by M383-02 invoking the existing runner |
| M383-06 | independent audit packet | Bind exact candidate, gate, controls, historical and new execution evidence, budget, and report paths | Depends on all prior components; read-only to the auditor |

The Lean model, atom ledger, mutant specifications, runner, sensors, witnesses,
and generated receipts are frozen subjects. They do not depend on ticket #383
artifacts.
