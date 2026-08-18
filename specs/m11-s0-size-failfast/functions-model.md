# S0 functions model

Artifact ceiling: 6,000 bytes / 140 lines.

Names may be adjusted to Aiken conventions, but argument/result responsibilities
and reachability from the measured programs are fixed.

| ID | Function | Signature-level contract |
|---|---|---|
| S0-F01 | `bind_parsed_event` | `(raw_event: ByteArray, claimed: ParsedEvent) -> Option<ParsedEvent>`; total and bytes-anchored |
| S0-F02 | `apply_record_append` | `(old: RecordState, event: ParsedEvent, proof: HistoricalProof) -> Option<RecordState>`; returns a derived changed state |
| S0-F03 | `derive_cursor` | `(old: CursorState, event: ParsedEvent, proof: HistoricalProof, now: Int) -> Option<CursorState>`; derives every cursor field |
| S0-F04 | `validate_lineage_transition` | `(old: Option<LineageState>, action: LineageAction, tx: Transaction) -> Bool`; exercises genesis, predecessor presence/juvenility, or marker close surface |
| S0-F05 | `validate_escrow_transition` | `(old: EscrowState, action: EscrowAction, grade: EvidenceGrade, tx: Transaction) -> Bool`; exercises service and notice-close surface |
| S0-F06 | `validate_staging_token` | `(raw_event: ByteArray, claimed: ParsedEvent, policy_id: PolicyId, tx: Transaction) -> Bool`; requires successful binding and token identity/output checks |
| S0-F07 | `cursor_policy_allows` | `(policy: CursorPolicy, cursor: CursorState, now: Int) -> Bool`; result depends on keys, state, grade, and freshness |
| S0-F08 | `validate_reference_consumer` | `(policy: CursorPolicy, expected_lineage: PolicyId, tx: Transaction) -> Bool`; obtains cursor-like reference data and delegates to S0-F07 |
| S0-F09 | `measure_blueprint` | `(blueprint_path: Path, source_commit: Hash, compiler: EvidenceIdentity) -> List<MeasurementRow>`; exactly seven deterministic rows |
| S0-F10 | `check_skeleton_obligations` | `(source_root: Path, obligation_manifest: Path) -> ExitStatus`; non-zero for missing/unreachable role obligations |

## Effects and constraints

- S0-F01 through S0-F08 are reachable from one of the seven measured programs.
- S0-F09 is read-only apart from its declared report/evidence outputs.
- S0-F10 does not mutate source and is run on both the real family and hollow
  negative-control fixture.
- No function above is evidence of S2-complete semantics.

