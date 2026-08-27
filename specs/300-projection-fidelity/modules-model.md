# Modules model: #300 — projection-fidelity requirements record

Artifact ceiling: 100 lines / 7,000 bytes.

MOD-300-SPEC
owns:         `specs/300-projection-fidelity/` — the durable statement of the
              four future S2 requirements (event-derived MPF key; sufficient
              event leaf and key-state snapshot; whole-record cursor
              derivation; pinned keripy parity with proven abstention), their
              order, their acceptance meaning, and their explicit decision
              debt.
does_not_own: any product implementation — onchain Aiken modules, offchain
              Haskell modules, tests, fixtures, or dependency manifests.
              No production module changes are authorized by #300.
notes:        each future implementation slice (R300-1 through R300-4)
              defines its own module ownership and boundaries beneath its
              individual A-019 mandate skeleton before any product write;
              nothing here pre-commits a module layout.
