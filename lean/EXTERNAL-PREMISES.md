# Who supplies the evidence?

A theorem about an accepted transaction can depend on evidence that Lean treats as an input. The following discharges apply to the modeled operations. A reader can check a ledger observation independently. A fixture table describes one set of observations and has no authority over the ledger.

| Model input | Who uses it and where |
| --- | --- |
| `Application.Env.inception` and `Registry.Env.inception` | The controller presents the inception event with signatures and receipts in the registration booking. The application mint admits the initial datum before issuing its approval. The Singular folder reads that approval and the public holding instructions. |
| `Application.Interpretation.hash`, `code`, `keyOf` | Genesis derives the registry identity from the deployer's seed. The application mint derives approval names during booking and their burns during processing or return. Each policy computes its names over the transaction's preimages. |
| `decode`, `decodeConfiguration`, `decodeCheckpoint`, `refundTo` | The controller's booking mint decodes the request, referenced configuration and initial datum, including the refund address. At termination booking the booker spends the pending holding and the policy reads its key. The folder and returner spend public requests and the application verifies their outputs. |
| `Registry.Params` and `Checkpoint.Params` | The deployer fixes the amounts in the published scripts. Registration checks both positive checkpoint bonds, the carrier, the chosen pool and the minimum tip. Termination booking checks the smaller request carrier and its funding. A relay or freeze spends the checkpoint under the premium and bond schedule. The relying party's consuming transaction checks the waiting period against its validity time. Positivity and funding bounds restrict the modeled deployment. |
| `SystemEnv`, local `rotationTo` | The party submitting a keep or deposit rotation, or a hunter submitting a freeze, supplies the later witnessed rotation for the identifier of the input. The checkpoint observer checks its event, controller signatures and witness receipts. Public witnesses are a source the submitting party may consult itself. |
| `depositAuthorized`, `Observed`, `ReadsDeposit`, `Verify` | The scoped lifecycle lookup is a Boolean. Its concrete correspondence is a hypothesis of `ReadsDeposit`. At the deposit spend the successor keys sign the deposit intent. The observer derives the identifier, spent reference, network, policy, sequence, epoch and amount from the transaction and validates the indexed signatures. The transfer-refusal theorem requires an actual contributing signature and its stated threshold assumptions. |
| `quorum` for poison | The scoped lifecycle lookup is a Boolean. In the modeled poison spend the controller presents the current-key quorum for the spent identifier. The current validator has no poison spend. |
| Conviction inputs and `attestationMinted` | The convictor presents one signed rival and mints the conviction attestation in the transaction spending the checkpoint. The checkpoint policy requires the mint for the conviction kind, its script and the specific output and claim of this spend (#576). The ledger supplies the mint observation. The two environments select that observation by its transaction and output index. The signature results, key-digest openings, binding to complete event bytes and authentication of the spent writer are technical inputs. The predicate checks the rival’s own signing and receipt rules against the previous commitments carried in the spent datum. |
| Commitment opening and reveal | The opener submits the marker, bounded opening interval, deposit and commitment. The commitment program checks the opening. The revealer supplies the opening data and nonce, signs and presents the commitment input, and the conviction transaction checks the applicable window and bindings. An expired commitment is spent by the sweeper. |
| Application deployment and public transaction views | The deployer publishes the release, seed and configuration. The controller, folder or returner submits its own funding and transaction. The ledger supplies spent and referenced outputs, validity bounds, mint, fee, donation and signatures to the validators. For the fold income result, the folder's ordinary input and output destinations must actually satisfy the named routing hypotheses. |
| Consumer context, interpretation and environment | At a consuming transaction the relying contract fixes the network, release, registry seed, AID and checkpoint credential, derives the asset and checks the reference output and decoded datum. For an independent read there is no transaction. The reader must authenticate the expected deployment, resolve its chain view and apply its own freshness requirement. |
| Finite encoding, hash collision freedom, approval-preimage uniqueness, signature binding | The approval, conviction and consumer calculations check concrete names and signatures. No transaction establishes the cryptographic assumptions over all inputs in a theorem's domain. Faithful key, datum and registry mappings are obligations of the interpretation used by the proof. |
| Realized checkpoint inputs and public history | The termination booker consumes the pending carrier. A theorem about what preceded it requires the reader to establish that the input belongs to the proved history. Receipt replay checks the supplied prefix and actual model steps. It cannot establish the completeness or freshness of a provider's ledger view. |
| Seal walk, TEL digest, delegation event digest and credential policy | In the statements models the presenter supplies the event and receipts for the consuming seal walk. A delegation certificate minter supplies the child event and the approval walk. At credential admission the presenter supplies the chain and seal walks, and the verifier supplies its root, schemas, link predicates, depth, witness floor and freshness policy. A relying-party read has no transaction and the reader establishes this context independently. |

The registration observer reads the signed inception and initial witness list from
the same admitted datum. `Env.inceptionWriter aid datum` models that joint read
(`checkpoint/observer.ak` 65–111 and `checkpoint/registration.ak` 310–352,
363–410). At an advance, `Env.rotationWriter` reads the proposed signed event
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

At conviction, `Env.convictionSpend` requires the attestation minted for the
observed output and comparison. A prior holding supplies no mint at use.
In the connected example, transaction 105 has an empty mint field and the
checkpoint environment supplies the abstract attestation for every claim.
Binding that predicate to the ledger mint field remains open under #576.
`rotated_conviction_is_duplicity` concludes duplicity for the actual rival.
`inception_conviction_refused` establishes refusal for a reachable inception in
Lean. Validator evidence at a never-rotated checkpoint is still outstanding.

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
