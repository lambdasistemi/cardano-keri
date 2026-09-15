# Modules model

| ID | Component | Changed responsibility | Dependency direction |
|---|---|---|---|
| M-442-LAKE | Lean package definition | Resolve the released Singular library at the frozen release identity. | Cardano KERI Lean depends on Singular Lean. |
| M-442-ROOT | Cardano KERI root library | Expose the dependency binding through the default library build. | Root library depends on the local binding check and released Singular. |
| M-442-CHECK | Dependency binding check | Execute the upstream transition and expose a discriminating result check. | Check depends directly on Singular's public model surface. |
| M-442-DOCS | Lean README | State the dependency and the limited evidence supplied by the check. | Documentation follows the package and check identities. |

No Cardano KERI model module changes responsibility in this ticket.

## Ceiling

This file is limited to 2 KiB and 50 lines.
