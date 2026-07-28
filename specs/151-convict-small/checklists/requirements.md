# Requirements quality checklist: convict-small (#151)

- [x] ACTIVE, ARMED, and FROZEN are three independent proof rows.
- [x] Each source row states exact input reserve and exact payouts.
- [x] ARMED protects the recorded hunter's exact `B` at a distinct index.
- [x] FROZEN explicitly excludes the already-paid `B`.
- [x] Ratified burn semantics replace the older surviving TOMBSTONE UTxO.
- [x] The transaction/redeemers/evidence are defined as the tombstone record.
- [x] Token burn and token absence are independently observable.
- [x] Unwitnessed and no-conflict/insufficient evidence are distinct rejects.
- [x] The witnessed conflict is tied to the pinned keripy generator.
- [x] Only Convict, ConvictBurn, and observer action 4 are opened.
- [x] Existing mint, spend, and observer wire indices are frozen.
- [x] The near-limit Advance observer is explicitly unchanged.
- [x] Stock-PV11 live txids, payouts, costs, and rejection evidence are named.
- [x] Re-registration after conviction is explained without a global barrier.
- [x] The story PR's navigable conviction page is an acceptance criterion.
- [x] RED and GREEN-plus-live each require complete navigator approval.
