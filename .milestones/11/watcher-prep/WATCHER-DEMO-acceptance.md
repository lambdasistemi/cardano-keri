# WATCHER DEMO — acceptance specification (A-027 verbatim obligations)

The milestone's final proof. Runs after R4 is accepted+merged, against
the accepted R1–R4 head, on a devnet, through the EXISTING e2e path.

MUST SHOW, as a preserved receipt:
1. authenticated KERI events appended through the existing e2e path;
2. the on-chain record growing (before/after record roots or sizes);
3. the whole-record cursor returning the TWO ORTHOGONAL FACTS of A-019
   §4: permanent `ever_duplicitous` AND current `resolution` — including
   their VALID COEXISTENCE after a recovery sequence (i.e., the demo
   script includes a duplicity + recovery scenario, not only the happy
   path);
4. preserved: transaction IDs, event SAIDs, before/after roots/sizes,
   cursor outputs — the acceptance receipt.

MUST NOT: substitute a watcher signature or a Cardano-slot tie-break for
resolution semantics (neither required nor permitted); present a design,
mocked trace, or unit-only output as the demo.

Verification: the desk independently verifies the receipt against the
accepted R1–R4 head before M1.2 reports S2 COMPLETE.

Scenario sketch (for the eventual demo lane's brief): icp → ixn (clean
resolution) → rival ixn at same location (duplicity-detected;
ever_duplicitous=true) → rot superseding (Resolved{Recovered} with
ever_duplicitous still true) → receipt captures every step's txid/SAID/
root/cursor.
