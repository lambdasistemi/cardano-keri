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
//   row `configuration-with-retraction` -> the configuration parameters with
//                                       retractTime = 1 (checked against the
//                                       row's note)
// The BLAKE2b below is independent of the Aiken `blake2b_*` builtins and is
// checked against the known digests of the empty string and against the Lean
// vector's own configuration token name.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const inPath = resolve(root, 'lean/application-vectors.json');
const outPath = resolve(root, 'onchain/lib/cardano_keri/application/configuration_vectors.ak');
const stagedSingular = resolve(root, 'onchain/build/packages/singular-registry');

const isHex = (s, bytes) => typeof s === 'string' && /^([0-9a-f]{2})*$/.test(s) && (bytes === undefined || s.length === 2 * bytes);
const hex = (b) => Buffer.from(b).toString('hex');
const unhex = (s) => Uint8Array.from(Buffer.from(s, 'hex'));
const concat = (...parts) => Uint8Array.from(parts.flatMap((p) => [...p]));

// --- BLAKE2b -----------------------------------------------------------------
const M = (1n << 64n) - 1n;
const IV = [
  0x6a09e667f3bcc908n, 0xbb67ae8584caa73bn, 0x3c6ef372fe94f82bn, 0xa54ff53a5f1d36f1n,
  0x510e527fade682d1n, 0x9b05688c2b3e6c1fn, 0x1f83d9abfb41bd6bn, 0x5be0cd19137e2179n,
];
const SIGMA = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
];
const rotr = (x, n) => ((x >> BigInt(n)) | (x << BigInt(64 - n))) & M;

const compress = (h, block, t, last) => {
  const m = Array.from({ length: 16 }, (_, i) => {
    let w = 0n;
    for (let k = 7; k >= 0; k--) w = (w << 8n) | BigInt(block[8 * i + k]);
    return w;
  });
  const v = [...h, ...IV];
  v[12] ^= t & M;
  if (last) v[14] ^= M;
  const g = (a, b, c, d, x, y) => {
    v[a] = (v[a] + v[b] + x) & M; v[d] = rotr(v[d] ^ v[a], 32);
    v[c] = (v[c] + v[d]) & M; v[b] = rotr(v[b] ^ v[c], 24);
    v[a] = (v[a] + v[b] + y) & M; v[d] = rotr(v[d] ^ v[a], 16);
    v[c] = (v[c] + v[d]) & M; v[b] = rotr(v[b] ^ v[c], 63);
  };
  for (let r = 0; r < 12; r++) {
    const s = SIGMA[r % 10];
    g(0, 4, 8, 12, m[s[0]], m[s[1]]); g(1, 5, 9, 13, m[s[2]], m[s[3]]);
    g(2, 6, 10, 14, m[s[4]], m[s[5]]); g(3, 7, 11, 15, m[s[6]], m[s[7]]);
    g(0, 5, 10, 15, m[s[8]], m[s[9]]); g(1, 6, 11, 12, m[s[10]], m[s[11]]);
    g(2, 7, 8, 13, m[s[12]], m[s[13]]); g(3, 4, 9, 14, m[s[14]], m[s[15]]);
  }
  return h.map((x, i) => x ^ v[i] ^ v[i + 8]);
};

const blake2b = (bytes, outlen) => {
  let h = [...IV];
  h[0] ^= 0x01010000n ^ BigInt(outlen);
  const total = bytes.length;
  let offset = 0;
  while (total - offset > 128) {
    h = compress(h, bytes.subarray(offset, offset + 128), BigInt(offset + 128), false);
    offset += 128;
  }
  const rest = new Uint8Array(128);
  rest.set(bytes.subarray(offset));
  h = compress(h, rest, BigInt(total), true);
  const out = new Uint8Array(64);
  h.forEach((w, i) => { for (let k = 0; k < 8; k++) out[8 * i + k] = Number((w >> BigInt(8 * k)) & 0xffn); });
  return out.subarray(0, outlen);
};

if (hex(blake2b(new Uint8Array(0), 32)) !== '0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8') throw new Error('blake2b-256 self-check failed');
if (hex(blake2b(new Uint8Array(0), 28)) !== '836cc68931c2e4e3e838602eca1902591d216837bafddfe6f0c8cb07') throw new Error('blake2b-224 self-check failed');

// --- the Plutus Data layouts of the Singular preimages ----------------------
// `ApplicationConfiguration { registry }` is constructor 4 (tag 0xd87b) of the
// preimage sum; `RegistryIdentity { policy, name }` is constructor 0.
const configurationPreimage = (policy, name) => concat(
  unhex('d87b9fd8799f581c'), policy, unhex('5820'), name, unhex('ffff'));
const configurationName = (policy, name) => blake2b(configurationPreimage(policy, name), 32);

// --- the compiled public state script and its application --------------------
const aiken = (cwd, ...args) => execFileSync('aiken', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// The script of `singular_state` applied to a policy: the unapplied script's
// bytes with the first term tag rewritten, a fixed prefix; then the parameter
// as a flat byte string (chunk length 30, the CBOR bytes 0x58 0x1c and the 28
// policy bytes, end of chunks) and the end-of-program filler. The prefix is
// derived from the first application and checked against every other one.
const SUFFIX_HEAD = unhex('1e581c');
const SUFFIX_TAIL = unhex('0001');

const compileState = (policies) => {
  if (!existsSync(join(stagedSingular, 'aiken.toml'))) {
    throw new Error('the Singular package is not staged: run `bash onchain/stage-dependencies.sh` first');
  }
  const work = mkdtempSync(join(tmpdir(), 'application-state-'));
  try {
    // Only the state script and the libraries it uses: the rest of the package
    // is not part of that script's compilation.
    cpSync(join(stagedSingular, 'lib'), join(work, 'lib'), { recursive: true });
    cpSync(join(stagedSingular, 'validators/singular_state.ak'), join(work, 'validators/singular_state.ak'));
    const toml = readFileSync(join(stagedSingular, 'aiken.toml'), 'utf8')
      .replace(/\[\[dependencies\]\]\nname = "aiken-lang\/fuzz"\nversion = "[^"]*"\nsource = "github"\n\n/, '');
    if (/fuzz/.test(toml)) throw new Error('the staged package manifest changed shape');
    writeFileSync(join(work, 'aiken.toml'), toml);
    aiken(work, 'build', '-t', 'silent');
    const blueprint = JSON.parse(readFileSync(join(work, 'plutus.json'), 'utf8'));
    const mint = blueprint.validators.find((v) => v.title === 'singular_state.singular_state.mint');
    if (!mint || mint.parameters.length !== 1) throw new Error('singular_state.mint is not a one-parameter validator');
    const applied = policies.map((policy) => {
      aiken(work, 'blueprint', 'apply', '-i', 'plutus.json', '-o', 'applied.json', '-m', 'singular_state', '-v', 'singular_state', `581c${hex(policy)}`);
      const v = JSON.parse(readFileSync(join(work, 'applied.json'), 'utf8')).validators.find((x) => x.title === 'singular_state.singular_state.mint');
      return { code: unhex(v.compiledCode), hash: v.hash };
    });
    return { unapplied: mint.compiledCode, applied };
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
};

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

use cardano/transaction.{OutputReference}

/// The unapplied-prefix of the script of \`singular_state\` applied to a policy:
/// everything before the parameter. The script is this prefix, then
/// \`1e581c\`, the 28 policy bytes and \`0001\`.
pub const state_template: ByteArray = #"${hex(prefix)}"

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
