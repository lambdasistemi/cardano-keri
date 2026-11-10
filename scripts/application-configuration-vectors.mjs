#!/usr/bin/env node
// Generates onchain/lib/cardano_keri/application/configuration_vectors.ak from
// lean/application-vectors.json (the configuration record and the rows
// `configuration-created`, `configuration-with-retraction` and
// `configuration-foreign-registry` of KERI's application on the public
// Singular registry) and from the compiled public `singular_state` script.
//
//   node scripts/application-configuration-vectors.mjs            # write the module
//   node scripts/application-configuration-vectors.mjs --check    # exit 1 when the module drifts
//
// Needs `aiken` (the pinned compiler) and the staged Singular package
// (`bash onchain/stage-dependencies.sh`).
//
// The mapping of the Lean values onto Aiken values is written here, once, and
// restated in the header of the generated module:
//   application policy A_keri        -> `configuration.token.policy`
//   Lean abstract state policy       -> replaced by the real state(A_keri): the
//                                       script hash of `singular_state` applied
//                                       to A_keri, as `aiken blueprint apply`
//                                       produces it; the token names that depend
//                                       on it are recomputed here with BLAKE2b
//                                       over the Lean preimage layout
//   foreign registry                 -> the registry of `singular_state` applied
//                                       to another application policy
//   checkpoint credential            -> the script credential of the Lean address
//   row `configuration-with-retraction` -> the configuration parameters with
//                                       retractTime = 1 (checked against the
//                                       row's note)
// The BLAKE2b (scripts/application-support.mjs) is independent of the Aiken
// `blake2b_*` builtins, is checked against the known digests of the empty string and
// against the Lean vector's own configuration token name.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { SUFFIX_HEAD, SUFFIX_TAIL, aiken, blake2b, compileState, concat, hex, isHex, root, unhex } from './application-support.mjs';

const inPath = resolve(root, 'lean/application-vectors.json');
const outPath = resolve(root, 'onchain/lib/cardano_keri/application/configuration_vectors.ak');

// --- the Plutus Data layouts of the Singular preimages ----------------------
// `ApplicationConfiguration { registry }` is constructor 2 (tag 0xd87b) of the
// preimage sum; `RegistryIdentity { policy, name }` is constructor 0.
const configurationPreimage = (policy, name) => concat(
  unhex('d87b9fd8799f581c'), policy, unhex('5820'), name, unhex('ffff'));
const configurationName = (policy, name) => blake2b(configurationPreimage(policy, name), 32);

const generate = () => {
  const data = JSON.parse(readFileSync(inPath, 'utf8'));
  const cfg = data.configuration;
  if (!cfg || !isHex(cfg.token.policy, 28) || !isHex(cfg.token.name, 32) || !isHex(cfg.registryName, 32)) throw new Error('configuration record changed shape');
  const rowsById = Object.fromEntries(data.rows.map((r) => [r.id, r]));
  const rowIds = ['configuration-created', 'configuration-with-retraction', 'configuration-foreign-registry'];
  const verdicts = { 'configuration-created': 'accepted', 'configuration-with-retraction': 'refused', 'configuration-foreign-registry': 'refused' };
  const applicationAddress = `d8799fd87a9f581c${cfg.token.policy}ffd87a80ff`;
  for (const id of rowIds) {
    const row = rowsById[id];
    if (!row || row.kind !== 'configuration' || row.verdict !== verdicts[id]) throw new Error(`row ${id} changed`);
    if (row.outputs.length !== 1 || row.outputs[0].address !== applicationAddress || row.outputs[0].lovelace !== 2) throw new Error(`row ${id}: the record is not 2 lovelace at the application address`);
    if (row.inputs.length !== 0 || row.referenced !== 0 || row.donation !== 0) throw new Error(`row ${id}: unexpected inputs`);
  }
  if (!/retractTime = 1/.test(rowsById['configuration-with-retraction'].note)) throw new Error('the retraction row no longer sets retractTime = 1');
  const checkpointMatch = /^d8799fd87a9f581c([0-9a-f]{56})ffd87a80ff$/.exec(cfg.checkpointCredential);
  if (!checkpointMatch) throw new Error('the checkpoint credential is not a script address without a stake credential');
  const checkpointHash = checkpointMatch[1];
  if (checkpointHash === cfg.token.policy) throw new Error('the checkpoint credential is the application');
  const p = cfg.parameters;
  for (const f of ['retractTime', 'registrationCost', 'processTime', 'minimumTip', 'bookingWidth']) if (!Number.isSafeInteger(p[f]) || p[f] < 0) throw new Error(`parameter ${f}`);
  if (p.retractTime !== 0) throw new Error('the scenario configuration has a retraction window');

  // The Lean seed: the state name of the vector must be the hash of the seed's preimage.
  const approval = data.approvals[0];
  if (approval.registryName !== cfg.registryName) throw new Error('the approval vector names another registry');
  const seed = approval.input.seed;
  if (!isHex(seed.transactionId, 32) || !Number.isInteger(seed.outputIndex) || seed.outputIndex < 0 || seed.outputIndex > 23) throw new Error('seed');
  // State { seed } is constructor 0 of the preimage sum: OutputReference is constructor 0 of (tx id, index).
  const statePreimage = concat(unhex('d8799fd8799f5820'), unhex(seed.transactionId), Uint8Array.of(seed.outputIndex), unhex('ffff'));
  if (hex(blake2b(statePreimage, 32)) !== cfg.registryName) throw new Error('the registry name is not the hash of the state preimage of the seed');

  // The Lean abstract state policy, kept only to check the BLAKE2b layout.
  const abstractPolicy = approval.input.statePolicy;
  if (hex(configurationName(unhex(abstractPolicy), unhex(cfg.registryName))) !== cfg.token.name) throw new Error('the configuration token name of the Lean vector is not reproduced');

  // Three application policies: A_keri, and two others (the foreign registries).
  const scriptHash = (seedNumber) => Uint8Array.from({ length: 28 }, (_, i) => (seedNumber * 37 + i * 5 + 3) % 256);
  const applications = [unhex(cfg.token.policy), scriptHash(9), scriptHash(2)];
  const { applied } = compileState(applications);
  const tails = applications.map((a) => concat(SUFFIX_HEAD, a, SUFFIX_TAIL));
  const prefix = applied[0].code.subarray(0, applied[0].code.length - tails[0].length);
  const states = applied.map((a, k) => {
    const expectedCode = concat(prefix, tails[k]);
    if (hex(expectedCode) !== hex(a.code)) throw new Error(`application ${k}: the applied script is not prefix and parameter`);
    const script = concat(Uint8Array.of(3), a.code);
    if (hex(blake2b(script, 28)) !== a.hash) throw new Error(`application ${k}: hash of the applied script differs from the blueprint`);
    return unhex(a.hash);
  });

  const name = unhex(cfg.registryName);
  const names = states.map((s) => configurationName(s, name));
  const flag = (b) => (b ? 'True' : 'False');
  const out = [];
  out.push(`//// Generated by scripts/application-configuration-vectors.mjs from
//// lean/application-vectors.json and the public \`singular_state\` script. Do not edit.
////
//// The configuration record of a registry of KERI's application: the Lean
//// rows \`configuration-created\`, \`configuration-with-retraction\` and
//// \`configuration-foreign-registry\`, with the real state policy.
////
//// The Lean vectors name an abstract state policy; here it is replaced by the
//// script hash of \`singular_state\` applied to the application policy, as
//// \`aiken blueprint apply\` computes it, and every token name that depends on it
//// is recomputed over the Lean preimage layout. The foreign registry is the
//// registry of \`singular_state\` applied to another application policy. The
//// retraction row is the scenario parameters with a retraction time of 1.

use cardano/address.{Credential, Script}
use cardano/transaction.{OutputReference}

/// The unapplied-prefix of the script of \`singular_state\` applied to a policy:
/// everything before the parameter. The script is this prefix, then
/// \`1e581c\`, the 28 policy bytes and \`0001\`.
pub const state_template: ByteArray = #"${hex(prefix)}"

/// The BLAKE2b-256 of the template: the parameter of the application, which
/// commits its hash to the template without carrying it. The template itself is
/// published in the inline datum of an output a genesis transaction references.
pub const state_template_hash: ByteArray = #"${hex(blake2b(prefix, 32))}"

/// The application policy of the scenario: the hash of the KERI application.
pub const application_policy: ByteArray = #"${cfg.token.policy}"

/// \`state(application_policy)\`, from the blueprint.
pub const state_policy: ByteArray = #"${hex(states[0])}"

/// Another application policy, and the state policy of its registry.
pub const foreign_application_policy: ByteArray = #"${hex(applications[1])}"

pub const foreign_state_policy: ByteArray = #"${hex(states[1])}"

/// A third application policy and its state policy, for the template checks.
pub const other_application_policy: ByteArray = #"${hex(applications[2])}"

pub const other_state_policy: ByteArray = #"${hex(states[2])}"

/// The seed the registry is created from.
pub const seed: OutputReference =
  OutputReference {
    transaction_id: #"${seed.transactionId}",
    output_index: ${seed.outputIndex},
  }

/// The name of the registry's state token (hash of the seed's preimage).
pub const registry_name: ByteArray = #"${cfg.registryName}"

/// The name of the configuration token of the registry under \`state_policy\`.
pub const configuration_name: ByteArray = #"${hex(names[0])}"

/// The name of the configuration token of the foreign registry.
pub const foreign_configuration_name: ByteArray = #"${hex(names[1])}"

/// The configuration parameters of the scenario registry.
pub const registration_cost: Int = ${p.registrationCost}

pub const minimum_tip: Int = ${p.minimumTip}

pub const process_time: Int = ${p.processTime}

pub const booking_width: Int = ${p.bookingWidth}

/// The lovelace of the record's output in every row.
pub const record_lovelace: Int = ${rowsById['configuration-created'].outputs[0].lovelace}

/// The credential of the checkpoint validator the scenario's configuration
/// record names: the Lean checkpointCredential, a script address without a
/// stake credential, as its payment credential.
pub const checkpoint_credential: Credential = Script(#"${checkpointHash}")
`);
  for (const id of rowIds) {
    const fn = id.replace(/-/g, '_');
    out.push(`/// Row \`${id}\`: ${rowsById[id].note}. Accepted: ${flag(verdicts[id] === 'accepted')}.
pub const ${fn}: Bool = ${flag(verdicts[id] === 'accepted')}
`);
  }
  const text = out.join('\n');
  // `aiken fmt` canonicalises the module, so that the committed module and the format check agree.
  const work = mkdtempSync(join(tmpdir(), 'application-fmt-'));
  try {
    writeFileSync(join(work, 'configuration_vectors.ak'), text);
    aiken(work, 'fmt', 'configuration_vectors.ak');
    return readFileSync(join(work, 'configuration_vectors.ak'), 'utf8');
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
};

const generated = generate();
if (process.argv.includes('--check')) {
  const committed = existsSync(outPath) ? readFileSync(outPath, 'utf8') : '';
  if (committed !== generated) {
    console.error(`${outPath} drifts from lean/application-vectors.json and the public singular_state script`);
    process.exit(1);
  }
  console.log('application configuration vectors: no drift');
} else {
  writeFileSync(outPath, generated);
  console.log(`wrote ${outPath}`);
}
