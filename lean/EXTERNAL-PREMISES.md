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
| Conviction inputs | In the spent-tip comparison the convictor supplies a rival from public KERI history. The enforcement observer takes the first record and both verification key lists from the named active input, decodes the rival and verifies its signatures and receipts. In the off-chain two-event comparison a history reader authenticates a predecessor and the first-seen event. A registry fold processes a public termination request. |
| Commitment opening and reveal | The opener submits the marker, bounded opening interval, deposit and commitment. The commitment program checks the opening. The revealer supplies the opening data and nonce, signs and presents the commitment input, and the entitlement observer checks the applicable window and bindings. An expired commitment is spent by the sweeper. |
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

At enforcement the checkpoint observer reads the spent tip and rival
(`checkpoint/enforcement_observer.ak` 68–94). The agreement of the decoded
tip and signed content with those bytes belongs to `ComparisonReads`.
`InceptionRefusal` and `RotatedRivalValidity` state open conformance
obligations. Authentication of the stored writer alone discharges neither.

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

At the checkpoint spend, the observer reads the rival and the spent keys.
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
