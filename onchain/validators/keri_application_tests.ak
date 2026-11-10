//// The application validator: the creation of the configuration record of a
//// registry, and the refusal of everything else at this revision.
////
//// Every refusal is one change to a perfect transaction that the same
//// validator accepts, and returns `False` (it does not crash), so a refusal
//// cannot be an artefact of the fixture.
////
//// ## Layers
//// - hand-built transactions: one mutation per guard of the Lean
////   `createConfiguration` (invariants I1, I2, I3), of the mint accounting (I6)
////   and of the spend refusal (I5);
//// - the generated Lean rows `configuration-created`,
////   `configuration-with-retraction` and `configuration-foreign-registry`,
////   whose verdicts come from the vectors.
////
//// The state policy computed on chain is checked in
//// `cardano_keri/application/state_policy_tests`.

use aiken/collection/list
use aiken/crypto.{blake2b_256}
use aiken/primitive/bytearray
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder,
}
use cardano_keri/application/action.{Action, ReturnRegistration, SpendAction}
use cardano_keri/application/configuration_vectors as vectors
use cardano_keri/application/held.{ApplicationParameters, Configuration}
use cardano_keri/application/row_vectors as rows
use cardano_keri/application/state_policy.{state_policy}
use keri_application
use keri_application_fixture.{
  Deployment, application_address, change_byte, creation, foreign_registry,
  genesis, keri, key_address, mint_of, other_application, parameters, record,
  record_of, registry_deployment, seed_input, template_input, token,
}
use singular_state/preimage.{
  RegistryIdentity, configuration_token_name, state_token_name,
}

const template: ByteArray = vectors.state_template

/// Run the mint handler of the application as `deployment.application`, in a
/// transaction that also references the output publishing `template`.
fn mint(
  template: ByteArray,
  deployment: Deployment,
  action: Action,
  tx: Transaction,
) -> Bool {
  mint_as_is(
    deployment,
    action,
    Transaction {
      ..tx,
      reference_inputs: [template_input(template), ..tx.reference_inputs],
    },
  )
}

/// The same, over the transaction exactly as given.
fn mint_as_is(deployment: Deployment, action: Action, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    vectors.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    [action],
    deployment.application,
    tx,
  )
}

/// Any value as Plutus Data.
fn to_data(value: Data) -> Data {
  value
}

/// Run the spend handler of the application over `input`.
fn spend(
  _template: ByteArray,
  datum: Option<Data>,
  redeemer: SpendAction,
  input: OutputReference,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.spend(
    vectors.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    datum,
    redeemer,
    input,
    tx,
  )
}

// ---- the perfect transactions -------------------------------------------------

/// Lean row `configuration-created`.
test row_configuration_created() {
  mint(template, keri(), creation(keri(), 0), genesis(keri())) == vectors.configuration_created
}

/// The same scenario for another application is accepted under its own
/// state policy: `state(A)` is computed for each application, not fixed.
test another_application_creates_under_its_own_state_policy() {
  mint(
    template,
    other_application(),
    creation(other_application(), 0),
    genesis(other_application()),
  )
}

// ---- I1: created in the registry's genesis -----------------------------------

test refuses_when_the_seed_is_not_spent() {
  let tx = Transaction { ..genesis(keri()), inputs: [] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_when_the_seed_is_spent_twice() {
  let tx = Transaction {
    ..genesis(keri()),
    inputs: [seed_input(keri().seed), seed_input(keri().seed)],
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_when_the_state_token_is_not_minted() {
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of([(keri().application, keri().configuration_name, 1)]),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_when_the_state_token_is_minted_twice() {
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of(
      [
        (keri().registry.policy, keri().registry.name, 2),
        (keri().application, keri().configuration_name, 1),
      ],
    ),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_registry_not_named_from_the_seed() {
  // A perfect genesis for a registry whose name is not the hash of the seed's
  // preimage: the state token and the configuration token carry that name.
  let deployment = registry_deployment(
    RegistryIdentity {
      ..keri().registry,
      name: vectors.foreign_configuration_name,
    },
  )
  !mint(template, deployment, creation(deployment, 0), genesis(deployment))
}

test refuses_when_the_configuration_token_is_not_minted() {
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of([(keri().registry.policy, keri().registry.name, 1)]),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_when_the_configuration_token_is_minted_twice() {
  // The record holds the token once; only the mint says twice.
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of(
      [
        (keri().registry.policy, keri().registry.name, 1),
        (keri().application, keri().configuration_name, 2),
      ],
    ),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_holding_the_configuration_token_twice() {
  // The mint says once; only the record holds the token twice.
  let tx = Transaction {
    ..genesis(keri()),
    outputs: [
      record(
        application_address(keri().application),
        InlineDatum(
          Configuration {
            parameters: parameters(),
            checkpoint_credential: vectors.checkpoint_credential,
          },
        ),
        token(keri().application, keri().configuration_name, 2),
      ),
    ],
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_holding_another_asset() {
  let output = record(
    application_address(keri().application),
    InlineDatum(
      Configuration {
        parameters: parameters(),
        checkpoint_credential: vectors.checkpoint_credential,
      },
    ),
    token(keri().application, keri().configuration_name, 1)
      |> add("other", "token", 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_outside_the_application_address() {
  let output = record(
    key_address(),
    InlineDatum(
      Configuration {
        parameters: parameters(),
        checkpoint_credential: vectors.checkpoint_credential,
      },
    ),
    token(keri().application, keri().configuration_name, 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_at_another_application_address() {
  let output = record(
    application_address(vectors.foreign_application_policy),
    InlineDatum(
      Configuration {
        parameters: parameters(),
        checkpoint_credential: vectors.checkpoint_credential,
      },
    ),
    token(keri().application, keri().configuration_name, 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_without_a_datum() {
  let output = record(
    application_address(keri().application),
    NoDatum,
    token(keri().application, keri().configuration_name, 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_whose_datum_is_not_a_configuration() {
  let output = record(
    application_address(keri().application),
    InlineDatum(42),
    token(keri().application, keri().configuration_name, 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_carrying_another_registrys_token() {
  let output = record(
    application_address(keri().application),
    InlineDatum(
      Configuration {
        parameters: parameters(),
        checkpoint_credential: vectors.checkpoint_credential,
      },
    ),
    token(keri().application, vectors.foreign_configuration_name, 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_when_the_named_output_is_not_the_record() {
  let decoy = record(key_address(), NoDatum, from_lovelace(0))
  let tx = Transaction {
    ..genesis(keri()),
    outputs: [decoy, record_of(keri(), parameters())],
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test accepts_the_record_at_the_index_it_names() {
  let decoy = record(key_address(), NoDatum, from_lovelace(0))
  let tx = Transaction {
    ..genesis(keri()),
    outputs: [decoy, record_of(keri(), parameters())],
  }
  mint(template, keri(), creation(keri(), 1), tx)
}

test refuses_an_index_past_the_outputs() {
  !mint(template, keri(), creation(keri(), 1), genesis(keri()))
}

test refuses_a_negative_index() {
  !mint(template, keri(), creation(keri(), -1), genesis(keri()))
}

// ---- I2: no retraction window -------------------------------------------------

/// Lean row `configuration-with-retraction`: retract time 1.
test row_configuration_with_retraction() {
  let tx = Transaction {
    ..genesis(keri()),
    outputs: [
      record_of(
        keri(),
        ApplicationParameters { ..parameters(), retract_time: 1 },
      ),
    ],
  }
  mint(template, keri(), creation(keri(), 0), tx) == vectors.configuration_with_retraction
}

test refuses_any_other_retract_time() {
  list.all(
    [-1, 2, 5, 1_000_000],
    fn(retract_time) {
      let tx = Transaction {
        ..genesis(keri()),
        outputs: [
          record_of(
            keri(),
            ApplicationParameters { ..parameters(), retract_time },
          ),
        ],
      }
      !mint(template, keri(), creation(keri(), 0), tx)
    },
  )
}

// ---- I7: the parameters are naturals ---------------------------------------------

/// A record that differs from the perfect one by the parameters only.
fn with_parameters(parameters: ApplicationParameters) -> Transaction {
  Transaction { ..genesis(keri()), outputs: [record_of(keri(), parameters)] }
}

test refuses_a_negative_registration_cost() {
  let tx = with_parameters(
    ApplicationParameters { ..parameters(), registration_cost: -1 },
  )
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_negative_minimum_tip() {
  let tx = with_parameters(
    ApplicationParameters { ..parameters(), minimum_tip: -1 },
  )
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_negative_process_time() {
  let tx = with_parameters(
    ApplicationParameters { ..parameters(), process_time: -1 },
  )
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_negative_booking_width() {
  let tx = with_parameters(
    ApplicationParameters { ..parameters(), booking_width: -1 },
  )
  !mint(template, keri(), creation(keri(), 0), tx)
}

/// Zero is a natural: every field at zero (retract time is zero by the Lean rule)
/// is accepted, so the refusals above are about the sign and nothing else.
test accepts_parameters_at_zero() {
  let tx = with_parameters(
    ApplicationParameters {
      registration_cost: 0,
      minimum_tip: 0,
      process_time: 0,
      retract_time: 0,
      booking_width: 0,
    },
  )
  mint(template, keri(), creation(keri(), 0), tx)
}

// ---- I3: no configuration record for a foreign registry ----------------------

/// Lean row `configuration-foreign-registry`: a registry whose state policy is
/// the state policy of another application.
test row_configuration_foreign_registry() {
  mint(
    template,
    foreign_registry(),
    creation(foreign_registry(), 0),
    genesis(foreign_registry()),
  ) == vectors.configuration_foreign_registry
}

test refuses_an_arbitrary_state_policy() {
  // A perfect genesis for a registry under a policy that is the state policy
  // of no application.
  let deployment = registry_deployment(
    RegistryIdentity {
      ..keri().registry,
      policy: #"1111111111111111111111111111111111111111111111111111111111",
    },
  )
  !mint(template, deployment, creation(deployment, 0), genesis(deployment))
}

test refuses_the_state_policy_of_a_third_application() {
  let deployment = registry_deployment(
    RegistryIdentity { ..keri().registry, policy: vectors.other_state_policy },
  )
  !mint(template, deployment, creation(deployment, 0), genesis(deployment))
}

test refuses_a_state_policy_computed_from_another_template() {
  // One byte of the template changed: the state policy the application
  // computes is no longer the registry's policy.
  let changed = change_byte(template, 100)
  !mint(changed, keri(), creation(keri(), 0), genesis(keri()))
}

// ---- I6: nothing else is minted under the application policy ----------------

test refuses_a_second_token_under_the_application_policy() {
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of(
      [
        (keri().registry.policy, keri().registry.name, 1),
        (keri().application, keri().configuration_name, 1),
        (keri().application, "extra", 1),
      ],
    ),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_burn_under_the_application_policy_beside_the_creation() {
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of(
      [
        (keri().registry.policy, keri().registry.name, 1),
        (keri().application, keri().configuration_name, 1),
        (keri().application, "extra", -1),
      ],
    ),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_creation_of_the_configuration_token_of_another_registry() {
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of(
      [
        (keri().registry.policy, keri().registry.name, 1),
        (keri().application, vectors.foreign_configuration_name, 1),
      ],
    ),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

// ---- I5: no input at the application address is spent ------------------------

fn record_reference() -> OutputReference {
  OutputReference { transaction_id: #"aa", output_index: 0 }
}

test refuses_to_spend_a_configuration_record() {
  let spent = Input {
    output_reference: record_reference(),
    output: record_of(keri(), parameters()),
  }
  let tx = Transaction { ..placeholder, inputs: [spent] }
  !spend(
    template,
    Some(
      to_data(
        Configuration {
          parameters: parameters(),
          checkpoint_credential: vectors.checkpoint_credential,
        },
      ),
    ),
    ReturnRegistration,
    record_reference(),
    tx,
  )
}

test refuses_to_spend_an_input_without_a_datum() {
  let spent = Input {
    output_reference: record_reference(),
    output: record(
      application_address(keri().application),
      NoDatum,
      from_lovelace(0),
    ),
  }
  let tx = Transaction { ..placeholder, inputs: [spent] }
  !spend(template, None, ReturnRegistration, record_reference(), tx)
}

test refuses_to_spend_in_the_transaction_that_creates_a_record() {
  let spent = Input {
    output_reference: record_reference(),
    output: record_of(keri(), parameters()),
  }
  let tx = genesis(keri())
  let tx = Transaction { ..tx, inputs: [spent, ..tx.inputs] }
  !spend(
    template,
    Some(
      to_data(
        Configuration {
          parameters: parameters(),
          checkpoint_credential: vectors.checkpoint_credential,
        },
      ),
    ),
    ReturnRegistration,
    record_reference(),
    tx,
  )
}

// ---- the generated constants agree with the public Singular names ------------

test the_registry_name_is_the_public_state_name_of_the_seed() {
  vectors.registry_name == state_token_name(vectors.seed)
}

test the_configuration_name_is_the_public_configuration_name() {
  vectors.configuration_name == configuration_token_name(keri().registry)
}

test the_foreign_configuration_name_is_the_public_configuration_name() {
  vectors.foreign_configuration_name == configuration_token_name(
    foreign_registry().registry,
  )
}

// ---- J14: the state policy is computed from an authenticated template -------------------

/// A genesis of the registry whose state policy is the one the state script
/// built from `template` has under the application: every value derived from it
/// is recomputed.
fn genesis_of_template(template: ByteArray) -> Deployment {
  registry_deployment(
    RegistryIdentity {
      policy: state_policy(template, keri().application),
      name: vectors.registry_name,
    },
  )
}

test the_genesis_references_the_template_it_computes_the_state_policy_from() {
  mint(template, keri(), creation(keri(), 0), genesis(keri())) && !mint_as_is(
    keri(),
    creation(keri(), 0),
    genesis(keri()),
  )
}

test refuses_a_genesis_that_references_no_template() {
  !mint_as_is(keri(), creation(keri(), 0), genesis(keri()))
}

test refuses_a_genesis_whose_state_script_is_another_than_the_pinned_template() {
  // The registry's state policy is that of a state script built from a template
  // one byte different, which the transaction publishes: the application's hash
  // pins the template, whatever the transaction publishes.
  let other = change_byte(template, 100)
  let deployment = genesis_of_template(other)
  !mint(other, deployment, creation(deployment, 0), genesis(deployment))
}

test refuses_a_template_of_one_byte_more_or_less() {
  let longer = bytearray.concat(template, #"00")
  let shorter = bytearray.take(template, bytearray.length(template) - 1)
  list.all(
    [longer, shorter],
    fn(other) {
      let deployment = genesis_of_template(other)
      !mint(other, deployment, creation(deployment, 0), genesis(deployment))
    },
  )
}

test passes_over_reference_inputs_that_are_not_the_template() {
  // Other reference inputs of the transaction, whatever their datums, do not
  // hide the template: the one whose hash is the parameter is the one read.
  let tx = genesis(keri())
  let decoy_bytes = template_input(#"01")
  let decoy_integer = Input {
    ..template_input(#""),
    output: Output { ..template_input(#"").output, datum: InlineDatum(7) },
  }
  let decoy_hashed = Input {
    ..template_input(#""),
    output: Output {
      ..template_input(#"").output,
      datum: DatumHash(
        #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
      ),
    },
  }
  let with_decoys = Transaction {
    ..tx,
    reference_inputs: [
      decoy_bytes,
      decoy_integer,
      decoy_hashed,
      template_input(template),
    ],
  }
  mint_as_is(keri(), creation(keri(), 0), with_decoys) && !mint_as_is(
    keri(),
    creation(keri(), 0),
    Transaction {
      ..tx,
      reference_inputs: [decoy_bytes, decoy_integer, decoy_hashed],
    },
  )
}

test refuses_a_template_spent_instead_of_referenced() {
  let tx = genesis(keri())
  !mint_as_is(
    keri(),
    creation(keri(), 0),
    Transaction { ..tx, inputs: [template_input(template), ..tx.inputs] },
  )
}

test refuses_a_template_published_by_a_datum_hash() {
  let hashed = Input {
    ..template_input(template),
    output: Output {
      ..template_input(template).output,
      datum: DatumHash(
        #"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
      ),
    },
  }
  !mint_as_is(
    keri(),
    creation(keri(), 0),
    Transaction { ..genesis(keri()), reference_inputs: [hashed] },
  )
}

test the_template_hash_parameter_is_the_hash_of_the_template() {
  vectors.state_template_hash == blake2b_256(template)
}
