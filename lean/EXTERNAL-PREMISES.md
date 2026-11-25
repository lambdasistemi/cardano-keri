# Who supplies the evidence?

A theorem about an accepted transaction can depend on evidence that Lean treats as an input. The following discharges apply to the modeled operations. A reader can check a ledger observation independently. A fixture table describes one set of observations and has no authority over the ledger.

| Model input | Who uses it and where |
| --- | --- |
| Booking attestation in the application and registry | The controller presents the inception event with signatures and receipts in the registration booking. The booking evidence policy checks these in the controller’s booking transaction. The application mint requires its +1 asset for the request index, initial datum and committed deposit before issuing the approval. The Singular folder reads that approval and the public holding instructions. |
| `Application.Interpretation.hash`, `code`, `keyOf` | Genesis derives the registry identity from the deployer's seed. The application mint derives approval names during booking and their burns during processing or return. Each policy computes its names over the transaction's preimages. |
| `decode`, `decodeConfiguration`, `decodeCheckpoint`, `refundTo` | The controller's booking mint decodes the request, referenced configuration and initial datum, including the refund address. At termination booking the booker spends the pending holding and the policy reads its key. The folder and returner spend public requests and the application verifies their outputs. |
| `Registry.Params` and `Checkpoint.Params` | The deployer fixes the amounts in the published scripts. Registration checks both positive checkpoint bonds, the carrier, the chosen pool and the minimum tip. Termination booking checks the smaller request carrier and its funding. A relay or freeze spends the checkpoint under the premium and bond schedule. The relying party's consuming transaction checks the waiting period against its validity time. Positivity and funding bounds restrict the modeled deployment. |
| `SystemEnv`, local `rotationTo` | The party submitting a keep or deposit rotation, or a hunter submitting a freeze, supplies the later witnessed rotation for the identifier of the input. The advance policy checks the event, controller signatures and witness receipts in that spend. Keep and deposit require the same advance-kind asset for the spent output. Freeze requires the freeze kind under the same policy. Public witnesses are a source the submitting party may consult itself. |
| `depositAuthorized`, `Observed`, `ReadsDeposit`, `Verify` | The scoped lifecycle lookup is a Boolean. Its concrete correspondence is a hypothesis of `ReadsDeposit`. At the deposit spend the successor keys sign the deposit intent. The checkpoint spending script verifies these signatures separately from the advance policy. A valid advance token alone cannot authorize a deposit. The checkpoint spending script derives the identifier, spent reference, network, policy, sequence, epoch and amount from the transaction and validates the indexed signatures. The transfer-refusal theorem requires an actual contributing signature and its stated threshold assumptions. |
| `quorum` for poison | The scoped lifecycle lookup is a Boolean. In the modeled poison spend the controller presents the current-key quorum for the spent identifier. The current validator has no poison spend. |
| Conviction enforcement and entitlement | The convictor supplies the signed rival and the mature commitment in the transaction spending the checkpoint. The enforcement policy verifies the rival and the entitlement policy verifies the reservation. The checkpoint requires +1 under each distinct policy, with the conviction kind, its relying script and the spent input reference. The custody history binds the decoded read for the indexed pending output to the actual spend's input, script and mint. |
| Commitment opening and reveal | The opener submits the marker, bounded opening interval, deposit and commitment. The commitment program checks the opening. The revealer supplies the opening data and nonce, signs and presents the commitment input, and the conviction transaction checks the applicable window and bindings. An expired commitment is spent by the sweeper. |
| Application deployment and public transaction views | The deployer publishes the release, seed and configuration. The controller, folder or returner submits its own funding and transaction. The ledger supplies spent and referenced outputs, validity bounds, mint, fee, donation and signatures to the validators. For the fold income result, the folder's ordinary input and output destinations must actually satisfy the named routing hypotheses. |
| Consumer context, interpretation and environment | At a consuming transaction the relying contract fixes the network, release, registry seed, AID and checkpoint credential, derives the asset and checks the reference output and decoded datum. For an independent read there is no transaction. The reader must authenticate the expected deployment, resolve its chain view and apply its own freshness requirement. |
| Finite encoding, hash collision freedom, approval-preimage uniqueness, signature binding | The approval, conviction and consumer calculations check concrete names and signatures. No transaction establishes the cryptographic assumptions over all inputs in a theorem's domain. Faithful key, datum and registry mappings are obligations of the interpretation used by the proof. |
| Realized checkpoint inputs and public history | The termination booker consumes the pending carrier. A theorem about what preceded it requires the reader to establish that the input belongs to the proved history. Receipt replay checks the supplied prefix and actual model steps. It cannot establish the completeness or freshness of a provider's ledger view. |
| Seal walk, TEL digest, delegation event digest and credential policy | In the statements models the presenter supplies the event and receipts for the consuming seal walk. A delegation certificate minter supplies the child event and the approval walk. At credential admission the presenter supplies the chain and seal walks, and the verifier supplies its root, schemas, link predicates, depth, witness floor and freshness policy. A relying-party read has no transaction and the reader establishes this context independently. |

The booking evidence policy reads the signed inception and initial witness list from
the same admitted datum. `Env.inceptionWriter aid datum` models that joint read
(the original registration predicate is in `checkpoint/observer.ak` 65–111 and `checkpoint/registration.ak` 310–352, 363–410). At an advance, `Env.rotationWriter` reads the proposed signed event
for the spent identifier and position (`checkpoint/observer.ak` 121–158,
214–231). The system computes the preceding keys and witnesses from the installed
history. Signature verification, opening key digests, binding witness data to
the bytes and verifying the prior digest remain interpretation obligations of
the decoded model. The chain-to-bytes correspondence has no proof here.

The decoded writer datum carries the current writer, its established witnesses
and one previous commitment set. A rotation copies the current next keys,
threshold and witnesses into the successor. An inception carries no previous
set. The proof history may grow while this datum retains only one predecessor.
Comparing complete event content requires an authenticated opening of the event
that wrote the spent checkpoint, including seals and witness changes. The
binding of that opening to the spent input and the concrete representation of
the additional datum fields belong to the datum and validator correspondence.

The decoded conviction tip uses the complete KERI threshold type for the
current keys and next commitments, including nested weighted groups. It can
present every writer with symbolic key identities. For concrete bytes the
verification-key and commitment encoders must round trip through their
respective reads. The existing V2 datum codec covers counts and flat weights.
The writer must be available in public chain data to the convictor. An inline
opening can include it directly. A digest requires public event bytes and an
authenticated injective opening, including seals. The convictor binds this
opening to the spent input in the conviction transaction. A faithful production
wire representation remains open. `MeasureCheckpointWriter.lean` measures an
illustrative inline layout with the model's Plutus Data serializer. The
one-key live examples occupy 220 bytes at inception and 313 after either of
two rotations. The grouped example with 64 seal bytes occupies 412. List
lengths are variable. Transaction size and validator budgets remain unmeasured.

## Mint observations

`Attestation.NetMintField` names the ledger premise that each asset has one net
quantity. The public Singular transaction view represents the field as a list.
`Assets.mintQty` sums the entries for the exact policy and name. The relying
script requires the sum to be +1, so a canceled mint and burn cannot serve.
`Attestation.InvokesMintPolicies` records that a nonzero net quantity invokes
that policy in the same transaction. Holding an asset in an input, in a
continuing output or in change supplies no mint. Burning a token later requires
no new signature or receipt evidence. A cleanup that only spends ordinary
holdings and creates ordinary change retains every checkpoint UTxO.

The application booking reads its own ordered outputs and mint directly.
The economic registry instead asks `bookingTx` for the mint indexed by the
request's creating transaction. At booking the controller's application mint
must read that ledger transaction and its actual request at the stated index.
The registry's booking, reachability and fold-admission results inherit this
projection. In the connected example the indexed mint equals transaction
100's mint and the request is its output zero.

At a local checkpoint step the relayer (rotation), hunter (freeze) or
convictor supplies the transaction consuming the live checkpoint.
`Step`, `LocalEvent` and their system-history consequences use a decoded
environment. Reading one of these as a ledger fact requires matching the
selected input, its script and the observed mint to the executing spend. At
conviction the selected pending output must also be the indexed output that
spend creates. The registry's economic conviction read requires the same
correspondence. `AdvanceAt` takes the matching named input and advance
correspondence as hypotheses. `CarrierHistory.spend` additionally relates a
ledger transition and its created output to the executed step. The connected
examples establish these matches for the rotation in 103 and conviction in
105. A free-standing local trace alone supplies only the projected read.

A transaction whose entire mint field is negative supplies no fresh claim.
A top-up checks the pool contribution and the existing top-up flag regardless
of evidence reads. Releasing a pending checkpoint still requires the
termination approval. Burns under a distinct policy leave that check intact.
A cleanup preserves the outputs of a checkpoint script when it consumes and
creates none there. Burns may also accompany changes to checkpoints.

Each relying script is parameterized by its published attestation policy.
The booking claim binds the application policy, output index in this
transaction, initial datum and committed lovelace. The advance, freeze and
conviction claims bind their kind, the relying checkpoint script and the
reference of the input actually consumed. The pending output index selects the
conviction transaction's observation. Including the creating transaction's
own hash in a booking claim is unnecessary. The claim digest and the distinct
policy identifiers belong to the deployment. `FaithfulNames` states the
collision assumption for the particular two preimages being distinguished.

`Policy.authorizes` takes the evidence verification for this transaction and
claim as an input. For booking the controller supplies inception signatures and
receipts to the booking policy. For advance the relayer, or the hunter for a
freeze, supplies the witnessed rotation to the advance policy. For deposit the
checkpoint additionally verifies the deposit intent signed by the successor
keys. The convictor supplies the rival and the commitment to the separate
enforcement and entitlement policies. A positive mint requires a verified
claim, a nonempty name and exactly +1. The burn branch permits only negative
entries of its policy without evidence. The earlier hash proof in a booking
has its own lifetime.

In the connected custody example, transaction 105 consumes 103#0 and creates
the pending checkpoint at 105#0. Its mint contains both conviction attestations
and both appear in ordinary change. This is a checked ledger observation inside
Lean. Production policy execution, faithful bytes, the deployed scripts and a
settled local-chain conviction remain implementation obligations. The
never-rotated refusal is proved in Lean; on-chain validator evidence remains
outstanding.

For the custody proof, the ledger supplies the spending inputs, transaction
identity, output indices and UTxO changes at every observed step. A reader
must establish the completeness of that history. The checkpoint spend reads
its old holding and writes the new datum and active token
(`validators/checkpoint_register.ak` 508–538). The termination booker spends
the named pending input and places the approval at the request output
(`application/termination.ak` 76–92 and 107–144). Public registry history
and the assumed finite encoding and collision freedom supply the one-token
bound. Under these premises, `Custody.approval_spends_conviction_output`
identifies the minted approval's input and the exact checkpoint edge that
created it. A bare economic registry replay records its decoded observations. A reader
establishes the carrier history by following the active token through the ledger.

The termination booker supplies the pending reference and the request index in
the mint transaction. The ledger identifies the transaction that created each
output. `Transaction.bookingSpend` reads the request at that index, matches its
reference and lovelace, and uses the configured checkpoint credential and the
named input to recover its native position. With the public registry history
and the observed carrier history, `booking_receipt_provenance` identifies both
the producing conviction and its authenticated live writer. The economic entry stores the input reference, identifier, epoch and sequence.

At the checkpoint spend, the conviction mint reads the rival and the carried predecessor.
The ledger assigns the transaction and index of its pending output.
`Env.convictionSpend` represents these reads together. The system retains
the record as history, and the carrier path checks the index and creating
transaction against its actual output. The booking certificate compares that
record with the economic history of the same spend. The termination mint
reads the pending input, and the Singular folder processes the admitted
request under its existing custody rule. See
`Custody.booked_carrier_shares_observation` for the joined history.


For a recorded termination, `ReceiptMatches` identifies the stored association,
the pending entry immediately before the fold and its actual consumed input.
The folder submits the public fold. The ledger supplies its inputs and outputs.
The system proof follows the association through intervening events to its
booking and the earlier conviction. A reader must supply a faithful path from
deployment. Acceptance of the earlier spent-tip comparison is the conclusion
about evidence that the recorded leaf supports.
