# Function model

Proposed signatures and obligations only; no bodies, imports, or pseudocode.

## Entry and lifecycle

`relayerParser :: Parser RelayerSettings`

- Uses existing opt-env-conf conventions; exposes documented defaults.

`runRelayer :: RelayerSettings -> IO ()`

- Runs all live AIDs, advances at most one event per AID/cycle, owns no durable
  state, emits stable structured result lines.

`withFollowerQueryHandle :: FollowerSettings -> (forall cf op. Manifest -> QueryHandle cf op -> IO a) -> IO a`

- One RocksDB runner and follower lifecycle; callback shares the handle; linked
  failure propagation; no second store open.

## Readiness and snapshots

`sampleReadiness :: QueryHandle cf op -> IO ReadinessStatus`

- Exact shared query-server semantics for connected and fresh; fail closed.

`discoveryProgram :: ChainQuery DiscoverySnapshot`

- Live checkpoints, authenticated board catalog, and watermark in one engine
  transaction.

`finalSubmissionProgram :: AdvanceCandidate -> ChainQuery FinalSubmissionSnapshot`

- Reacquires endpoint identity, predecessor, active output, references, payer
  inputs, and watermark in one transaction; mismatches are explicit failures.

## Discovery and network

`selectEndpoint :: Maybe StaticOobiCatalog -> DiscoverySnapshot -> ActiveCheckpoint -> Either RelayerFailure WitnessEndpoint`

- Chain board first. Static fallback only for absent matching board witness,
  never for board/readiness/authentication failure.

`witnessKelRequest :: WitnessEndpoint -> Aid -> Sequence -> Request`

- `GET /query?typ=kel&pre=<aid>&sn=<next>`; encoded parameters; no credential
  header; HTTP/HTTPS only; redirects disabled.

`fetchWitnessedKel :: FetchPolicy -> WitnessEndpoint -> Aid -> Sequence -> IO (Either RelayerFailure ByteString)`

- Enforces timeout, 8 MiB default limit, 200 status, and
  `application/json+cesr` before returning bytes.

## Verification and submission

`parseNextRotationExport :: Text -> CheckpointDatumV1 -> ByteString -> Either String RotationExport`

- Exactly one immediate next `rot`; binds AID/sequence, prior next-key
  commitments, thresholds, witness delta/receipts, and SAID; preserves native
  controller signatures; rejects trailing ambiguity.

`candidateFromRotation :: ActiveCheckpoint -> RotationExport -> Either RelayerFailure AdvanceCandidate`

- Produces the exact candidate datum accepted by the existing validator path.

`submitLiveAdvance :: SettlementPolicy -> FinalSubmissionSnapshot -> AdvanceCandidate -> IO (Either AdvanceFailure TxId)`

- Reuses in-process build/submit/await services; attaches KEL-native signatures;
  never consumes an external controller/Cardano-domain signature file.

`compareCurrentCandidate :: ActiveCheckpoint -> AdvanceCandidate -> CurrentComparison`

- Later sequence or exact same candidate may classify a competing success;
  equal sequence/different datum is conflict.

`reconcileAdvance :: QueryHandle cf op -> AdvanceCandidate -> IO (Either RelayerFailure RelayerResult)`

- Reacquires current state after submit, settlement, or input-race outcome and
  reports the actual checkpoint output transaction id.

## Observability

`renderRelayerResult :: RelayerResult -> Text`

- Stable keys: `result`, `aid`, `old_seq`, `new_seq`, `txid`; adds
  `discovery=static-fallback` only when used; deterministic and secret-free.
