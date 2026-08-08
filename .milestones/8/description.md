Outcome: named security invariants are SMT-checked against the exact compiled Cardano-KERI UPLC, with reproducible evidence and explicit trust limits.

State — Updated: 2026-08-02
Legend: ✅ done · 🟡 active/next · ⏳ queued · ⛔ blocked · ❓ unknown
🟡 #189 active: #192 PR #215 — S1 accepted/pushed → S2 real import/purpose/preparation active → tractability result → #193–#195
                                      └→ ⏳ #190 compiled-contract theorem portfolio → independent acceptance
parallel: ⏳ M8 root-gate lifecycle migration (non-blocking for #192)
Release and claims of full formal verification are separate.

Blaster supplies SMT-valid results without Lean proof reconstruction. Evidence is relative to the pinned extractor, UPLC preparation/semantics, ledger encodings, Blaster translation, Z3, fuel, Aiken compiler, and import boundary; it is not whole-system or compiler verification.
