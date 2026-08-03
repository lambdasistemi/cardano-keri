# Specification — #220 hear a rotation (`ckeri verify`)

Compiled 2026-08-03 from issue #220 as updated at 2026-08-03T07:13:07Z,
the ticket brief, A-001, and A-002. Product semantics in this document are
frozen for planning. The mechanical registration of the command against
#216's CLI contract is intentionally deferred until the parent releases the
merged contract.

## Outcome

A person with the installed `ckeri` release can run:

```text
ckeri verify <AID>
```

The command discovers authenticated witness endpoints from Cardano, samples
the identity's key event log (KEL) independently from those witnesses through
pinned keripy, verifies each history, compares the verified key state with the
indexed checkpoint, and returns one of three exit-status outcomes:

| Exit | Meaning |
|---|---|
| `0` | answered affirmative: the checkpoint is current and no sampled history proves duplicity |
| `1` | answered negative: a verified mismatch, stale checkpoint, or duplicity was proved |
| `2` | cannot answer: the available valid witness evidence is insufficient |

The status alone distinguishes affirmative, negative, and unknown. Prose is
never required to interpret the outcome class.

## Roles and trust boundary

- The authenticated endpoint board says where witnesses can be contacted.
- Pinned keripy 1.3.5 performs OOBI resolution, witness protocol exchange, and
  CESR stream acquisition in an isolated subprocess per witness.
- Haskell verifies the acquired KEL histories and receipts, compares histories
  with one another and with Cardano, renders the verdict, and chooses the exit
  status.
- A keripy subprocess result is acquisition evidence, never a verdict. Haskell
  does not trust a subprocess claim that a KEL is valid.
- Witness samples never share a keripy database. A first-seen merge across
  witnesses could erase the disagreement the duplicity detector exists to
  observe.

No user or controller private keys are accepted. Temporary sampler state is
command-scoped, contains only an ephemeral protocol identity and public KEL
material, and is removed on exit. Nothing is cached beside the follower.

## Functional requirements

### FR-1 — command and configuration

`ckeri verify <AID>` accepts one complete 44-character KERI E-code AID. The
new configuration surface uses `opt-env-conf` exclusively, with option,
environment, and YAML precedence matching the landed `ckeri` contract.
`optparse-applicative` is forbidden.

The default bootstrap is `chain`. An explicit `file` bootstrap accepts the
existing `witnesses.json` shape as a fallback. There is no automatic fallback:
a failed chain bootstrap remains a visible cannot-answer result unless the
caller explicitly selected file bootstrap.

The explicit `--require-full-coverage` setting makes complete declared-witness
coverage load-bearing. If full coverage is not achieved under that setting,
the result is UNKNOWN / exit 2 even when currency would otherwise be
answerable at quorum.

### FR-2 — authenticated chain bootstrap

Chain bootstrap reads both:

1. the target AID's indexed checkpoint; and
2. the complete authenticated endpoint-board catalog.

The local-follower path consumes the engine's transactional read surface and
`Cardano.KERI.Indexer.{Reads,Board}` semantics. The installed nodeless path may
reuse the authenticated `ckeri board list` / Koios catalog resolver. It never
uses an N2C `GetUTxOByAddress` address scan. A hosted backend that cannot
enumerate `GET /board` reports unsupported/cannot-answer; it does not pretend
that per-witness lookup is catalog enumeration.

Any undecodable, forged, or malformed board row invalidates the entire chain
catalog. A partial authenticated-looking catalog is forbidden.

File bootstrap validates every fallback record before use, identifies itself
as fallback in output, and never outranks a successfully selected chain
catalog.

### FR-3 — independent witness sampling

The sampler starts with the checkpoint's declared witnesses when a checkpoint
exists, or the complete catalog when it does not. Each witness is resolved and
queried in its own keripy process and private temporary state.

Every verified history may reveal a changed witness set. Sampling expands to
newly declared, board-listed witnesses until no verified history introduces a
new witness or the command deadline is reached. The coverage universe is the
union of witnesses declared by the checkpoint and by every event in every
verified history. This prevents removed or newly added witnesses from becoming
an unexamined place for a fork to hide.

The sampler reports acquisition facts per witness: endpoint identity,
transport outcome, and exact captured CESR bytes. It cannot emit a successful
domain verdict. Timeouts, unreachable endpoints, malformed protocol replies,
and non-zero subprocess exits are distinct sample failures and never become a
negative checkpoint verdict by themselves.

### FR-4 — complete KEL verification

For each captured history, Haskell verifies the target AID and the complete
supported KERI lineage from inception through every returned event. At
minimum the verifier proves:

- KERI framing and complete consumption, with truncation and trailing material
  rejected;
- AID, SAID, prior-event lineage, and native sequence continuity;
- controller signatures and current threshold;
- rotation keys against the prior next-key commitments;
- witness cut/add delta validity;
- distinct witness receipts over the exact event bytes at or above `toad`;
- event-state projection for inception, rotation, and interaction events.

Interaction events advance native lineage but do not by themselves make a
key checkpoint stale. The comparison head is the latest verified key-
establishment state. Unsupported establishment types fail closed.

A sample is `reachable-valid` only when transport succeeded and this complete
verification succeeded. A forged, truncated, wrong-AID, under-signed, or
under-receipted sample is rejected and does not count toward quorum.

### FR-5 — currency quorum

Currency is answerable when at least `toad` distinct currently declared
witnesses are reachable-valid and agree on the verified establishment head.
The comparison uses `>= toad`, never unanimity and never `> toad`.

For the committed three-witness, `toad = 2` identity:

- `3/3` valid can answer;
- `2/3` valid can answer currency;
- `1/3` valid cannot answer and exits 2.

The `2/3` case is a permanent positive boundary control. If the implementation
silently becomes unanimous, this control must go red.

### FR-6 — chain comparison

The verified KEL state is compared with all checkpoint key-state fields:
AID, checkpoint/native sequence, current and next keys and thresholds,
witnesses, and `toad`.

- An exact latest-establishment match is current.
- A checkpoint matching a verified ancestor while the verified establishment
  head is newer is stale and therefore negative / exit 1.
- A checkpoint not represented by the quorum-agreed verified history is a
  proved mismatch and therefore negative / exit 1.
- A quorum-agreed verified history with no Cardano checkpoint is not recorded
  and therefore negative / exit 1.
- Missing or invalid evidence before quorum is UNKNOWN / exit 2, not mismatch.

### FR-7 — duplicity and coverage-qualified absence

The detector compares independently verified histories by AID, native
sequence, and event SAID before any cross-witness merge. Two different valid
events at the same AID and native sequence prove duplicity and return a
negative verdict / exit 1.

Duplicity presence is a positive finding and does not require full witness
coverage. Duplicity absence is an absence claim:

- with full coverage, output may say `duplicity none`;
- below full coverage but at currency quorum, output must say that none was
  found among the reached witnesses and quantify the unreachable remainder;
- with `--require-full-coverage`, the same incomplete coverage is UNKNOWN /
  exit 2.

A committed positive control supplies two valid conflicting histories and
must make the same detector report duplicity. A zero-result claim is not
accepted without that control.

### FR-8 — stable human output

Output names:

- bootstrap source and authenticated board count;
- reached/declared witness coverage and `toad`;
- rejected/unreachable sample counts without treating them as negative proof;
- verified KEL establishment head and receipt count;
- checkpoint state and current/stale/mismatch comparison;
- duplicity result with coverage qualification;
- final verdict and numeric exit status.

The UNKNOWN path is reachable from the production command, not only by calling
a library helper in a unit test.

### FR-9 — installed-release boundary

The `ckeri` Nix wrapper and Linux AppImage/DEB/RPM closure include the pinned
keripy 1.3.5 sampler and Python runtime, CA material, and all helper files
needed by `verify`. The wrapper provides the closure-owned libsodium library
directory through `LD_LIBRARY_PATH` and provides closure-owned `binutils` in
its strict `PATH`; Nix Python disables host `ldconfig`, and pysodium's
`ctypes.util.find_library` therefore requires the `ld` fallback. The command
does not depend on a checkout, Docker, ambient `kli`, ambient Python, ambient
libsodium, ambient binutils, or an ambient PATH installation. Network access
is required for real witness acquisition, but not for locating or initializing
the packaged keripy runtime.

A permanent release-closure check builds the package and invokes its packaged
runtime probe under a cleared environment and an unshared network namespace
with only the Nix store plus ephemeral process/device/temp mounts available.
It asserts—not merely prints—that the closure-owned `kli` reports keripy
library version 1.3.5. Its demonstrated negative control removes the
closure-owned libsodium loader path and must fail with pysodium unable to find
libsodium before the production wiring is accepted.

Acceptance runs the installed/extracted release artifact, not only a Cabal or
worktree executable.

### FR-10 — documentation and evidence

The same PR ships a `docs/user/` page and MkDocs navigation entry covering the
command, bootstrap precedence, exit codes, quorum versus full coverage,
fallback operation, and failure interpretation.

Raw `script(1)` evidence is committed under `deploy/preprod/`, and a repository
checker rejects a hand-edited or incomplete transcript. Machine facts are
captured, never retyped.

## Required captured controls

Using the committed three-witness, `toad = 2` preprod identity:

1. `3/3`: currency current, unqualified `duplicity none`, exit 0.
2. `2/3`: currency current, duplicity absence explicitly qualified, exit 0.
3. `1/3`: below quorum, UNKNOWN, exit 2.
4. `2/3 --require-full-coverage`: UNKNOWN, exit 2.
5. forged or truncated KEL samples: explicit rejection; when valid coverage is
   thereby below quorum, UNKNOWN rather than a negative verdict.
6. planted valid fork: the production comparison method detects duplicity and
   exits 1.
7. genuine stale/mismatch fixture: answered negative and exits 1.
8. chain bootstrap is shown succeeding; file bootstrap is separately shown as
   explicit fallback and never as an implicit recovery.
9. at least one full journey runs from an installed Linux release artifact.

Deterministic loopback fault proxies may make one or two witness endpoints
unreachable or corrupt their responses while forwarding the remaining samples
to the live preprod witnesses. The transcript must identify the proxy and the
upstream live endpoints so the failure is caused rather than awaited.

## Non-goals and fences

- No transaction builders, publisher, register, advance, close, or on-chain
  changes.
- No reasoning about #219 advance authorization.
- No `onchain/` edits.
- No `offchain/indexer/` implementation changes; consume its read surfaces.
- No persistent watcher loop, archive, relayer, hunter, or daemon.
- No hosted `/board` enumeration change; that remains epic #171/#176 work.
- No quiet cache or derived state outside the follower engine transaction.
- No reimplementation of witness protocol acquisition outside pinned keripy.
- No command-registration implementation until the parent releases #216's
  landed CLI contract.
