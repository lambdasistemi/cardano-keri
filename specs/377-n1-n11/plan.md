# Promotion plan

One coherent authoring slice adds all eleven stories, narrative sections,
clauses, regenerated Lean-produced corpus and pages, and extent consumers.
No machine behavior changes. Existing core/checker/backend/DSL grammar remain
read-only dependencies. New stories use their existing APIs and fields.

Preparation is authorized before predecessors land. Clause probes use scratch
--clauses documents. Acceptance waits for #390 and #418; take each rebase through
the git workflow, preserve successor-owned regions, and rerun all seven gates.
A red attributable to #379 is a stop/question, not a repair in this branch.

Owner topology: visible alternate-provider commit owner, draft=NONE. Gate
review precedes implementation; independent anti-cheat review follows candidate
freeze. Maximum two candidate submissions. No worker push or remote contact.
Ticket owner owns planning, immutable runtime gate, acceptance and PR metadata.

Named commands: node simulator/{checkpoint,registry}-simulator-scenario-gate.mjs;
node simulator/{checkpoint,registry}-simulator-trace-gate.mjs;
node simulator/scenario-dsl-gate.mjs;
node simulator/{checkpoint,registry}-simulator-build.mjs --check.
These seven commands are the authorized verification scope; Haskell CI is not
part of this simulator-only ticket. Baseline on 8739b9e: six passes, checkpoint
scenario 25 items/104 steps/42 known problems. Baseline is diagnostic only.

Planning ceilings: each artifact <= 100 lines/8 KiB; compiled brief <= 140 lines/
12 KiB. Authoring ceiling 60 files/1 MiB excluding regenerated corpus/pages;
no author launch until the contract/gate has been reviewed. Review launches:
one pre-work gate seat, one anti-cheat seat, one delta seat if needed (three total).
Each review <= 45 minutes, with two complete seven-command bundles maximum.
Owner <= 90 minutes before durable handback, no unattended child processes.
