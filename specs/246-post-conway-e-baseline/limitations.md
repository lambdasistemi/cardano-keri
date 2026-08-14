# Rebased Variant-E baseline limitations

This baseline establishes the producer identity, current compiled denominator,
explicit post-Conway Variant E, and reconciliation to the accepted prior
inventory. It does not close the three shell-level parser and isolation classes
split out of rejected Slice C. Those follow-ups are filed here so readers do not
mistake a deliberately reduced result for universal bundle hardening.

## LIM-246-DUPLICATE-KEY: duplicate-key closure is not established

The published-bytes check rejects the duplicate scalar identity-key shapes
exercised by this ticket, including escaped spellings. It does not establish a
general duplicate-key-rejecting JSON decode independent of spelling and value
type. A future object- or array-valued duplicate remains outside this baseline's
claim.

- Owner: ticket owner (#246)
- Follow-up ID: `T246-F9`

## LIM-246-CLAIM-RECORD: closed claim-record parsing is not established

The evidence bundle's claim checks do not establish that every downstream
claim is parsed as a closed record containing exactly one `id`, `variant`, and
`outcome`. General rejection of duplicate, ambiguous, blank, unknown, and
`COULD-NOT-EVALUATE` claim fields remains outside this baseline's claim.

- Owner: ticket owner (#246)
- Follow-up ID: `T246-F10`

## LIM-246-FILESYSTEM-NAMESPACE: subtree isolation is not established

The fresh-checkout evidence does not establish complete filesystem-namespace
isolation from a forbidden subtree. In particular, root-inode comparison does
not reconcile descendant bind mounts, file binds, and every surviving file
descriptor to that subtree.

- Owner: ticket owner (#246)
- Follow-up ID: `T246-F11`

Scheduling these follow-ups belongs to the parent epic. They cannot expand
ticket #246 again.
