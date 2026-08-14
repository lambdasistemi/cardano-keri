# Data model

Signatures and constraints only; no implementation bodies.

## Settings

`RelayerSettings`

- `rsFollower :: FollowerSettings`
- `rsOobiList :: Maybe FilePath`
- `rsPollInterval :: NominalDiffTime` — positive, default 5 seconds
- `rsFetchTimeout :: NominalDiffTime` — positive, default 15 seconds
- `rsSettlementTimeout :: NominalDiffTime` — positive, default 600 seconds
- `rsMaxResponseBytes :: Natural` — positive, default 8 MiB

## Discovery

`DiscoverySnapshot`

- `dsWatermark :: ChainPoint`
- `dsLiveCheckpoints :: Map Aid ActiveCheckpoint`
- `dsBoardCatalog :: BoardCatalog`
- invariant: catalog authentication and all three fields derive from one local
  engine transaction.

`WitnessEndpoint`

- `weAid :: WitnessAid`
- `weScheme :: HttpScheme` — HTTP or HTTPS only
- `weBaseUrl :: BaseUrl`
- `weSource :: EndpointSource`
- `weIdentity :: EndpointIdentity`

`EndpointSource = ChainBoard | StaticFallback`

Static fallback is operator-trusted and valid only for a missing witness match
in an otherwise successfully queried, coherent authenticated board catalog.

## Candidate

`AdvanceCandidate`

- `acAid :: Aid`
- `acPredecessor :: CheckpointDatumV1`
- `acRotation :: RotationExport`
- `acCandidateDatum :: CheckpointDatumV1`
- `acEndpointIdentity :: EndpointIdentity`
- invariant: sequence is exactly predecessor sequence + 1; AID, commitments,
  thresholds, witness delta, receipts, and SAID are verified.

`FinalSubmissionSnapshot`

- `fssWatermark :: ChainPoint`
- `fssCurrentCheckpoint :: ActiveCheckpoint`
- `fssEndpointIdentity :: EndpointIdentity`
- `fssActiveOutput :: ChainOutput`
- `fssReferenceScripts :: ReferenceScripts`
- `fssPayerUtxos :: PayerUtxos`
- invariant: all fields derive from one engine transaction and current datum
  and endpoint identity equal the candidate predecessor/selection.

## Outcomes

`RelayerResult`

- `Advanced Aid Sequence Sequence TxId EndpointSource`
- `AlreadyCurrent Aid Sequence Sequence TxId EndpointSource`
- `Skipped Aid SkipReason`
- `Failed Aid RelayerFailure`

`CurrentComparison = CandidateWon TxId | LaterWon TxId | SameCandidate TxId | Conflict | StillPredecessor`

`SameCandidate` requires byte/semantic equality of the complete candidate
datum, not merely equal sequence. `LaterWon` requires current sequence greater
than candidate sequence.

## Failure taxonomy

`RelayerFailure`

- readiness disconnected/stale
- board query/authentication/conflict
- endpoint absent with no usable fallback
- HTTP status/redirect/media/timeout/size
- KEL parse/AID/sequence/commitment/signature/receipt/SAID
- final snapshot changed or incomplete
- build/submission/settlement
- equal-sequence datum conflict

Failures contain no secret-bearing headers or credential values.
