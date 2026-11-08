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
use cardano/assets.{add, from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, OutputReference, Transaction, placeholder,
}
use cardano_keri/application/action.{Action, CreateConfiguration}
use cardano_keri/application/configuration_vectors as vectors
use cardano_keri/application/held.{ApplicationParameters, Configuration}
use keri_application
use keri_application_fixture.{
  Deployment, application_address, change_byte, creation, foreign_registry,
  genesis, keri, key_address, mint_of, other_application, parameters, record,
  record_of, seed_input, token,
}
use singular_state/preimage.{
  RegistryIdentity, configuration_token_name, state_token_name,
}

const template: ByteArray = vectors.state_template

/// Run the mint handler of the application as `deployment.application`.
fn mint(
  template: ByteArray,
  deployment: Deployment,
  action: Action,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.mint(
    template,
    action,
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
  template: ByteArray,
  datum: Option<Data>,
  redeemer: Data,
  input: OutputReference,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.spend(template, datum, redeemer, input, tx)
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
  let registry = RegistryIdentity {
    ..keri().registry,
    name: vectors.foreign_configuration_name,
  }
  let deployment = Deployment {
    ..keri(),
    registry,
    configuration_name: configuration_token_name(registry),
  }
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
  let tx = Transaction {
    ..genesis(keri()),
    outputs: [
      record(
        application_address(keri().application),
        InlineDatum(Configuration { parameters: parameters() }),
        token(keri().application, keri().configuration_name, 2),
      ),
    ],
    mint: mint_of(
      [
        (keri().registry.policy, keri().registry.name, 1),
        (keri().application, keri().configuration_name, 2),
      ],
    ),
  }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_holding_another_asset() {
  let output = record(
    application_address(keri().application),
    InlineDatum(Configuration { parameters: parameters() }),
    token(keri().application, keri().configuration_name, 1)
      |> add("other", "token", 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_outside_the_application_address() {
  let output = record(
    key_address(),
    InlineDatum(Configuration { parameters: parameters() }),
    token(keri().application, keri().configuration_name, 1),
  )
  let tx = Transaction { ..genesis(keri()), outputs: [output] }
  !mint(template, keri(), creation(keri(), 0), tx)
}

test refuses_a_record_at_another_application_address() {
  let output = record(
    application_address(vectors.foreign_application_policy),
    InlineDatum(Configuration { parameters: parameters() }),
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
    InlineDatum(Configuration { parameters: parameters() }),
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

test refuses_the_application_policy_as_the_state_policy() {
  let registry = RegistryIdentity {
    ..keri().registry,
    policy: vectors.application_policy,
  }
  let deployment = Deployment { ..keri(), registry }
  !mint(template, deployment, creation(deployment, 0), genesis(deployment))
}

test refuses_the_state_policy_of_another_application_for_a_whole_registry() {
  // The state token and the configuration token of the other registry, a
  // perfect genesis for it, presented to KERI's application.
  let deployment = foreign_registry()
  let tx = genesis(deployment)
  !mint(template, keri(), creation(deployment, 0), tx)
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

test refuses_a_creation_that_mints_no_configuration_token() {
  // The record is there, the state token is minted, and the application
  // policy mints nothing: not a creation.
  let tx = Transaction {
    ..genesis(keri()),
    mint: mint_of([(keri().registry.policy, keri().registry.name, 1)]),
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
    Some(to_data(Configuration { parameters: parameters() })),
    Void,
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
  !spend(template, None, Void, record_reference(), tx)
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
    Some(to_data(Configuration { parameters: parameters() })),
    creation(keri(), 0),
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
