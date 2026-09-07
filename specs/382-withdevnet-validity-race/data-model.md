# Issue 382 data model

Artifact ceiling: 2,500 bytes / 70 lines.

| ID | Shape | Fields and invariants |
|---|---|---|
| D382-01 | validity policy | ordinary window = 20 slots; pinned forecast = 30 slots; forecast headroom = 10 slots; forced delay = 25 slots; one expiry retry maximum |
| D382-02 | submission rejection | `ValidityExpired rawDiagnostic` or `DomainRejected rawDiagnostic`; only the exact validity-expiry constructor grants recovery |
| D382-03 | submission attempt | scenario label, attempt number (1 or 2), freshly built transaction identity, validity bounds, node result; attempt 2 exists only after attempt 1 expired |
| D382-04 | timing verdict | scenario label, expired attempt, fresh-rebuild marker, final recovered/failed result; stable and visibly distinct from D382-05 |
| D382-05 | domain verdict | scenario label, first-attempt terminal result, raw diagnostic; no rebuild/retry marker |
| D382-06 | control receipt | injected delay slots, observed expiry marker, submission count, rebuild count, final result; non-empty and bound to the executed live run |

The raw diagnostic remains available for debugging, but it is not the only way
to distinguish timing from domain behavior.
