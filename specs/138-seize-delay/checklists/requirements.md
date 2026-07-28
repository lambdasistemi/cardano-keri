# Requirements quality checklist: seize-delay (#138)

- [x] Exact `B` payout and retained `min + D_reg` reserve are explicit.
- [x] Thaw re-posts exactly `B` and returns the real next KERI state.
- [x] Wrong-hunter and early-claim rejections are independently testable.
- [x] Only the `ClaimFreeze` spend constructor is opened.
- [x] Existing constructor and observer action indices are frozen.
- [x] The near-limit Advance observer is explicitly unchanged.
- [x] The live stock-PV11 sequence and settlement evidence are named.
- [x] The story PR's navigable user documentation is an acceptance criterion.
- [x] Register, Close, Advance, Freeze, and response regressions are preserved.
