#!/usr/bin/env node
// Generates, from lean/application-vectors.json and the compiled public
// `singular_state` script, the vectors of KERI's application beyond the
// configuration record:
//
//   onchain/lib/cardano_keri/application/row_vectors.ak
//       the scenario's constants and requests, and the names the Lean fixes
//   onchain/validators/keri_application_rows_tests.ak
//       one test per Lean row (bookings, folds, returns, the delivered
//       checkpoint, the pending termination) and per approval row, against the
//       real validator
//
//   node scripts/application-vectors.mjs            # write both modules
//   node scripts/application-vectors.mjs --check    # exit 1 when either drifts
//
// Needs `aiken` (the pinned compiler) and the staged Singular package
// (`bash onchain/stage-dependencies.sh`).
//
// The mapping of the Lean values onto Aiken values is written here, once, and
// restated in the header of each generated module:
//   application policy A_keri         -> the Lean stand-in script hash as the policy the
//                                        validator runs as
//   Lean abstract state policy        -> the real state(A_keri), as the configuration
//                                        vectors compute it; the foreign registry is the
//                                        registry of singular_state applied to another
//                                        application policy
//   credential                        -> a Plutus address: the script or key credential of
//                                        the Lean address, no stake credential
//   request datum (Lean: a hash)      -> the initial checkpoint datum itself; the approval
//                                        commits its BLAKE2b-256
//   controller 0                      -> 28 zero bytes (no row reads it)
//   lifecycle observer                -> a stand-in script hash (the Lean has no such input;
//                                        a parameter of the validator)
//   minimum deposit                   -> minimum ADA plus deposit of the Lean scenario
//                                        (read from the booking-short-deposit note)
// Every Lean row is also checked field by field against the scenario this script
// builds for it (validity, donation, reference inputs, input and output lovelace and
// address roles, verdict); a row that changes shape stops the generator.
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { SUFFIX_HEAD, SUFFIX_TAIL, aiken, blake2b, compileState, concat, hex, isHex, root, unhex } from './application-support.mjs';

const inPath = resolve(root, 'lean/application-vectors.json');
const rowsPath = resolve(root, 'onchain/lib/cardano_keri/application/row_vectors.ak');
const testsPath = resolve(root, 'onchain/validators/keri_application_rows_tests.ak');
const releaseTestsPath = resolve(root, 'onchain/validators/checkpoint_register_release_rows_tests.ak');

// --- Plutus Data of the Singular preimages --------------------------------------
const bstr = (b) => {
  if (b.length < 24) return concat(Uint8Array.of(0x40 + b.length), b);
  if (b.length < 256) return concat(Uint8Array.of(0x58, b.length), b);
  throw new Error('byte string too long for this encoder');
};
const uint = (n) => {
  if (!Number.isSafeInteger(n) || n < 0) throw new Error(`not a natural: ${n}`);
  if (n < 24) return Uint8Array.of(n);
  if (n < 256) return Uint8Array.of(0x18, n);
  if (n < 65536) return Uint8Array.of(0x19, n >> 8, n & 255);
  throw new Error('integer too large for this encoder');
};
const registryCbor = (r) => concat(unhex('d8799f'), bstr(r.policy), bstr(r.name), unhex('ff'));
// RegistrationApproval is constructor 3, Active constructor 1, TerminationApproval constructor 4.
const registrationPreimage = (r, key, holdingHex, datumHash, deposit) =>
  concat(unhex('d87c9f'), registryCbor(r), bstr(key), unhex(holdingHex), bstr(datumHash), uint(deposit), unhex('ff'));
const activePreimage = (r, key) => concat(unhex('d87a9f'), registryCbor(r), bstr(key), unhex('ff'));
const terminationPreimage = (r, key) => concat(unhex('d87d9f'), registryCbor(r), bstr(key), unhex('ff'));
const hash256 = (b) => blake2b(b, 32);

const scriptHash = (n) => Uint8Array.from({ length: 28 }, (_, i) => (n * 37 + i * 5 + 3) % 256);

const generate = () => {
  const data = JSON.parse(readFileSync(inPath, 'utf8'));
  const cfg = data.configuration;
  const byId = (list) => list.reduce((acc, x) => ({ ...acc, [x.id]: x }), {});
  const rowsById = byId(data.rows);
  const row = (id) => {
    const r = rowsById[id];
    if (!r) throw new Error(`the Lean vectors have no row ${id}`);
    return r;
  };
  const p = cfg.parameters;
  const appPolicy = cfg.token.policy;
  const addressRe = /^d8799fd8799f581c([0-9a-f]{56})ffd87a80ff$/;
  const scriptRe = /^d8799fd87a9f581c([0-9a-f]{56})ffd87a80ff$/;
  const appAddr = `d8799fd87a9f581c${appPolicy}ffd87a80ff`;
  const checkpointAddr = cfg.checkpointCredential;
  if (!scriptRe.test(checkpointAddr)) throw new Error('the checkpoint credential is not a script address without a stake credential');
  const refundAddr = row('return-at-deadline').outputs[0].address;
  const spenderAddr = row('return-at-deadline').outputs[1].address;
  const otherAddr = row('return-refund-redirected').outputs[0].address;
  for (const a of [refundAddr, spenderAddr, otherAddr]) if (!addressRe.test(a)) throw new Error('a payee is not a key address without a stake credential');
  if (new Set([appAddr, checkpointAddr, refundAddr, spenderAddr, otherAddr]).size !== 5) throw new Error('the five addresses of the scenario are not distinct');
  const roles = { app: appAddr, checkpoint: checkpointAddr, refund: refundAddr, spender: spenderAddr, other: otherAddr };

  // --- the scenario's numbers, read from the Lean rows ---------------------------
  const approvals = byId(data.approvals);
  const a0 = approvals.approval;
  const a2 = approvals['approval-other-aid'];
  const deposit = a0.input.deposit;
  const booking = row('booking');
  const bookedAt = booking.validity.upper;
  const deadline = bookedAt + p.processTime;
  if (booking.outputs[0].lovelace !== deposit + p.registrationCost + p.minimumTip) throw new Error('the booking row does not hold deposit + cost + tip');
  const shortNote = /minimum ADA (\d+) plus the deposit (\d+)/.exec(row('booking-short-deposit').note);
  if (!shortNote) throw new Error('the short-deposit note no longer names the minimum ADA and the deposit');
  const minimumDeposit = Number(shortNote[1]) + Number(shortNote[2]);
  const cpj = data.checkpoint;
  if (!cpj || cpj.Mc !== Number(shortNote[1])) throw new Error('the checkpoint parameters changed shape');
  // The registry deposit is the checkpoint deposit plus the freeze bond (the vectors satisfy it; the Lean does not require it).
  if (cpj.D + cpj.B !== Number(shortNote[2])) throw new Error('the registry deposit is not the checkpoint deposit plus the freeze bond');
  // The registry's minimum ADA (the pending output of a conviction holds exactly it) and the carrier of a
  // termination request (Mr): applied parameters of the validator, as the Lean's model parameters. The booking
  // rows are read against them below.
  const checkpointMinimumAda = cpj.Mc;
  const terminationCarrier = data.Mr;
  if (!Number.isSafeInteger(terminationCarrier) || terminationCarrier + p.minimumTip > checkpointMinimumAda) throw new Error('Mr plus the tip exceeds the minimum ADA');
  const termBooking = row('termination-booking');
  if (termBooking.inputs[0].lovelace !== checkpointMinimumAda || termBooking.outputs[0].lovelace !== terminationCarrier + p.minimumTip) throw new Error('the termination booking row does not hold Mc and Mr plus the tip');
  // What a fold's holding must hold: Mc + D + B + P, the floor below which the pool is under one premium.
  const initialFloor = cpj.Mc + cpj.D + cpj.B + cpj.P;
  if (deposit !== initialFloor) throw new Error('the default deposit is not the initial floor (a pool of one premium)');
  const shortDeposit = Number(/deposit of (\d+)/.exec(row('booking-short-deposit').note)[1]);
  if (shortDeposit !== minimumDeposit - 1 || row('booking-short-deposit').outputs[0].lovelace !== shortDeposit + p.registrationCost + p.minimumTip) throw new Error('the short-deposit row is not one lovelace short');
  if (row('fold-at-deadline').validity.upper !== deadline || row('return-at-deadline').validity.lower !== deadline) throw new Error('the deadline row bounds changed');
  if (p.retractTime !== 0) throw new Error('retraction window');

  // --- the real registry names ---------------------------------------------------
  const seed = a0.input.seed;
  const applications = [unhex(appPolicy), scriptHash(9), scriptHash(2)];
  const { applied } = compileState(applications);
  const states = applied.map((a, k) => {
    const script = concat(Uint8Array.of(3), a.code);
    if (hex(blake2b(script, 28)) !== a.hash) throw new Error(`application ${k}: the hash of the applied script differs from the blueprint`);
    return unhex(a.hash);
  });
  void SUFFIX_HEAD; void SUFFIX_TAIL;
  const registryName = unhex(cfg.registryName);
  const keri = { policy: states[0], name: registryName };
  const foreign = { policy: states[1], name: registryName };
  const keyE = unhex(a0.key);
  const keyE2 = unhex(a2.key);
  const datumE = a0.input.initialDatum;
  const datumE2 = a2.input.initialDatum;
  // The test network: the refund address is recorded as 0x60 (key) + hash, header low nibble 0.
  const refundHash = addressRe.exec(refundAddr)[1];
  const otherHash = addressRe.exec(otherAddr)[1];
  if (!datumE.includes(`581d60${refundHash}`) || !datumE2.includes(`581d60${refundHash}`)) throw new Error('the initial datum does not record the refund address as ledger bytes on the test network');
  if (!datumE.includes('0a581d')) throw new Error('the initial datum is not born at the booking bound 10');
  for (const [a, d] of [[a0, datumE], [a2, datumE2]]) {
    if (hex(hash256(unhex(d))) !== a.initialDatumHash) throw new Error('the initial datum hash is not the BLAKE2b-256 of the datum');
    if (!d.includes(a.key)) throw new Error('the initial datum does not carry the AID text of the key');
  }
  if (!scriptRe.test(a0.input.holdingAddress) || a0.input.holdingAddress !== checkpointAddr) throw new Error('the approval does not commit the checkpoint validator');

  // The Lean approvals, independently: abstract state policy, bytes for bytes.
  const leanRegistry = { policy: unhex(a0.input.statePolicy), name: registryName };
  const leanApprovals = data.approvals.map((a) => {
    const preimage = registrationPreimage(leanRegistry, unhex(a.key), a.input.holdingAddress, unhex(a.initialDatumHash), a.input.deposit);
    if (hex(preimage) !== a.approvalPreimage) throw new Error(`approval ${a.id}: the preimage is not reproduced`);
    if (hex(hash256(preimage)) !== a.approval.name) throw new Error(`approval ${a.id}: the name is not reproduced`);
    return { a, preimage };
  });

  // The termination approvals, independently: the same abstract policies, bytes for bytes.
  const termApprovals = data.terminationApprovals.map((t) => {
    const preimage = terminationPreimage(leanRegistry, unhex(t.key));
    if (hex(preimage) !== t.preimage) throw new Error(`termination approval ${t.id}: the preimage is not reproduced`);
    if (hex(hash256(preimage)) !== t.approval.name) throw new Error(`termination approval ${t.id}: the name is not reproduced`);
    if (t.approval.policy !== a0.approval.policy || t.registryName !== a0.registryName) throw new Error(`termination approval ${t.id}: another policy or registry`);
    return t;
  });
  // The release verdicts: the datum is the checkpoint datum the pending output carries, the mint is
  // read as (policy, name, quantity); the approval named is the first termination approval.
  const releases = data.releases.map((r) => {
    if (r.verdict !== 'released' && r.verdict !== 'kept') throw new Error(`release ${r.id}: verdict ${r.verdict}`);
    if (!isHex(r.datum)) throw new Error(`release ${r.id}: datum`);
    for (const m of r.mint) if (m.policy !== a0.approval.policy) throw new Error(`release ${r.id}: a mint under another policy`);
    return r;
  });
  if (termApprovals.length !== 2 || releases.length !== 5) throw new Error('the termination sections changed shape');

  // --- the requests the rows decode ----------------------------------------------
  // datum: 'e' the AID's initial datum; a number n the n-th variant of it (see `variant` in the module); 'e2' the other AID's.
  const requests = [
    { raw: 9001, registry: keri, holding: checkpointAddr, deposit, deadline },
    { raw: 9002, registry: foreign, holding: checkpointAddr, deposit, deadline },
    { raw: 9003, registry: keri, holding: checkpointAddr, deposit: shortDeposit, deadline },
    { raw: 9004, registry: keri, holding: otherAddr, deposit, deadline },
    { raw: 9005, registry: keri, holding: checkpointAddr, deposit, deadline: deadline + 1 },
    { raw: 9006, registry: keri, holding: appAddr, deposit, deadline },
    { raw: 9007, registry: keri, holding: checkpointAddr, deposit: deposit - 1, deadline },
    { raw: 9008, registry: keri, holding: checkpointAddr, deposit, deadline, refund: 'pointer' },
    ...[1, 2, 3, 4, 5, 6, 7, 8].map((k) => ({ raw: 9010 + k, registry: keri, holding: checkpointAddr, deposit, deadline, datum: k })),
    { raw: 9019, registry: keri, holding: checkpointAddr, deposit, deadline, datum: 'e2' },
  ];
  for (const r of requests) {
    if (r.datum === undefined) {
      const preimage = registrationPreimage(r.registry, keyE, r.holding, hash256(unhex(datumE)), r.deposit);
      r.name = hex(hash256(preimage));
    }
  }
  const namedRequests = requests.filter((r) => r.name !== undefined);
  const activeName = hex(hash256(activePreimage(keri, keyE)));
  const terminationName = hex(hash256(terminationPreimage(keri, keyE)));

  // --- the rows: Lean shape, scenario call, expected verdict -----------------------
  const B = 'Booking { ..requests.booking(), ';
  const F = 'Fold { ..requests.fold(), ';
  const spec = [];
  const add = (id, kind, call, shape) => spec.push({ id, kind, call, shape });
  const bookShape = (lov, extra = {}) => ({ validity: [9, 10], referenced: 1, donation: 0, inputs: [], outputs: [[lov, 'app']], ...extra });
  add('booking', 'booking', 'requests.booking()', bookShape(18));
  add('booking-foreign-registry', 'booking', `${B}data: rows.request_data(9002) }`, bookShape(18));
  add('booking-short-deposit', 'booking', `${B}data: rows.request_data(9003), lovelace: 16 }`, bookShape(16));
  add('booking-one-lovelace-more', 'booking', `${B}lovelace: 19 }`, bookShape(19));
  add('booking-one-lovelace-less', 'booking', `${B}lovelace: 17 }`, bookShape(17));
  add('booking-other-holding-address', 'booking', `${B}data: rows.request_data(9004) }`, bookShape(18));
  add('booking-application-holding', 'booking', `${B}data: rows.request_data(9006) }`, bookShape(18));
  add('booking-checkpoint-is-application', 'booking', `${B}data: rows.request_data(9006), checkpoint: Script(requests.application()) }`, bookShape(18));
  add('booking-wrong-deadline', 'booking', `${B}data: rows.request_data(9005) }`, bookShape(18));
  add('booking-without-configuration', 'booking', `${B}references: False }`, bookShape(18, { referenced: 0 }));
  add('booking-two-approvals', 'booking', `${B}mint: 2 }`, bookShape(18));
  add('booking-one-payload-twice', 'booking', `${B}mint: 2, copies: 2, actions: [BookRegistration { output_index: 0 }, BookRegistration { output_index: 1 }] }`, bookShape(18, { outputs: [[18, 'app'], [18, 'app']] }));
  add('booking-twice', 'booking', `${B}actions: [BookRegistration { output_index: 0 }, BookRegistration { output_index: 0 }] }`, bookShape(18));
  add('approval-without-booking', 'booking', `${B}actions: [] }`, bookShape(18));
  const foldShape = (out, extra = {}) => ({ validity: [12, 15], referenced: 1, donation: 2, inputs: [[18, 'app']], outputs: [out], ...extra });
  const foldVariant = (id, raw, k) => add(id, 'fold', `${F}data: rows.request_data(${raw}), holding_datum: rows.variant(${k}) }`, foldShape([15, 'checkpoint']));
  add('fold-at-deadline', 'fold', 'requests.fold()', foldShape([15, 'checkpoint']));
  add('fold-donating-more', 'fold', `${F}donation: 3 }`, foldShape([15, 'checkpoint'], { donation: 3 }));
  add('fold-after-deadline', 'fold', `${F}upper: 16 }`, foldShape([15, 'checkpoint'], { validity: [12, 16] }));
  add('fold-holding-one-more', 'fold', `${F}holding_lovelace: 16 }`, foldShape([16, 'checkpoint']));
  add('fold-holding-one-less', 'fold', `${F}holding_lovelace: 14 }`, foldShape([14, 'checkpoint']));
  add('fold-donation-short', 'fold', `${F}donation: 1 }`, foldShape([15, 'checkpoint'], { donation: 1 }));
  add('fold-other-datum', 'fold', `${F}holding_datum: rows.variant(9) }`, foldShape([15, 'checkpoint']));
  add('fold-approval-kept', 'fold', `${F}burn: 0 }`, foldShape([15, 'checkpoint']));
  add('fold-one-payload-twice', 'fold', `${F}second: Some((rows.request_data(9001), Some(FoldRegistration { holding_index: 0 }))), donation: 4 }`, foldShape([15, 'checkpoint'], { inputs: [[18, 'app'], [18, 'app']], donation: 4 }));
  add('fold-at-application-address', 'fold', `${F}holding_address: requests.app_address() }`, foldShape([15, 'app']));
  add('fold-at-committed-other-address', 'fold', `${F}data: rows.request_data(9004), holding_address: rows.other_address }`, foldShape([15, 'other']));
  add('fold-other-commitment-to-checkpoint', 'fold', `${F}data: rows.request_data(9004) }`, foldShape([15, 'checkpoint']));
  foldVariant('fold-advanced-sequence', 9011, 1);
  foldVariant('fold-advanced-epoch', 9012, 2);
  foldVariant('fold-poisoned', 9013, 3);
  foldVariant('fold-frozen', 9014, 4);
  foldVariant('fold-topped-up', 9015, 5);
  foldVariant('fold-born-later', 9016, 6);
  foldVariant('fold-other-refund', 9017, 7);
  foldVariant('fold-pending-termination', 9018, 8);
  add('fold-other-aid', 'fold', `${F}data: rows.request_data(9019), holding_datum: rows.initial_datum(1) }`, foldShape([15, 'checkpoint']));
  add('fold-pool-below-premium', 'fold', `${F}data: rows.request_data(9007), request_lovelace: 17, holding_lovelace: 14 }`, foldShape([14, 'checkpoint'], { inputs: [[17, 'app']] }));
  add('fold-unrecorded-refund', 'fold', `${F}data: rows.request_data(9008) }`, foldShape([15, 'checkpoint']));
  add('checkpoint-spent-at-checkpoint-validator', 'checkpoint', 'requests.checkpoint_spend(requests.checkpoint_address())',
    { validity: [16, 17], referenced: 0, donation: 0, inputs: [[15, 'checkpoint']], outputs: [[15, 'checkpoint']] });
  add('checkpoint-spent-at-application-address', 'checkpoint', 'requests.checkpoint_spend(requests.app_address())',
    { validity: [16, 17], referenced: 0, donation: 0, inputs: [[15, 'app']], outputs: [[15, 'app']] });
  const R = 'Return { ..requests.returned(), ';
  const retShape = (outs, extra = {}) => ({ validity: [15, 20], referenced: 1, donation: 0, inputs: [[18, 'app']], outputs: outs, ...extra });
  add('return-at-deadline', 'return', 'requests.returned()', retShape([[17, 'refund'], [1, 'spender']]));
  add('return-straddling-deadline', 'return', `${R}lower: 14 }`, retShape([[17, 'refund'], [1, 'spender']], { validity: [14, 20] }));
  add('return-refund-reduced', 'return', `${R}pays: [(rows.refund_address, 16), (rows.spender_address, 2)] }`, retShape([[16, 'refund'], [2, 'spender']]));
  add('return-refund-redirected', 'return', `${R}pays: [(rows.other_address, 17), (rows.spender_address, 1)] }`, retShape([[17, 'other'], [1, 'spender']]));
  const T = 'Termination { ..requests.termination(), ';
  const termShape = (extra = {}) => ({ validity: [12, 15], referenced: 1, donation: 2, inputs: [[3, 'app']], outputs: [], ...extra });
  add('termination-fold', 'termination', 'requests.termination()', termShape());
  add('termination-fold-donation-short', 'termination', `${T}donation: 1 }`, termShape({ donation: 1 }));
  add('termination-fold-without-configuration', 'termination', `${T}references: False }`, termShape({ referenced: 0 }));
  add('termination-approval-minted', 'minted', 'requests.termination_minted()', { validity: [12, 15], referenced: 0, donation: 0, inputs: [], outputs: [[3, 'app']] });
  add('termination-fold-active-kept', 'termination', `${T}active_burn: 0 }`, termShape());
  add('fold-with-unnamed-request', 'fold', `${F}second: Some((rows.request_data(9001), None)) }`, foldShape([15, 'checkpoint'], { inputs: [[18, 'app'], [18, 'app']] }));
  add('termination-return', 'termination', `${T}redeemer: ReturnRegistration, donation: 0 }`, termShape({ donation: 0 }));
  const TB = 'TerminationBooking { ..requests.termination_booking(), ';
  const bookTermination = (index, registry = 'requests.registry()', key = 'rows.key_e') =>
    `BookTermination { pending: requests.pending_reference(), output_index: ${index}, registry: ${registry}, key: ${key} }`;
  const tbShape = (extra = {}) => ({ validity: [12, 15], referenced: 1, donation: 0, inputs: [[4, 'checkpoint']], outputs: [[3, 'app'], [1, 'spender']], ...extra });
  add('termination-booking', 'termination-booking', 'requests.termination_booking()', tbShape());
  add('termination-booking-live-checkpoint', 'termination-booking', `${TB}pending_datum: rows.initial_datum(0) }`, tbShape());
  add('termination-booking-other-aid', 'termination-booking', `${TB}pending_datum: requests.pending_datum_of(rows.key_e2) }`, tbShape());
  add('termination-booking-other-key', 'termination-booking', `${TB}key: rows.key_e2, actions: [${bookTermination(0, 'requests.registry()', 'rows.key_e2')}] }`, tbShape());
  add('termination-booking-at-other-address', 'termination-booking', `${TB}pending_address: rows.other_address }`, tbShape({ inputs: [[4, 'other']] }));
  add('termination-booking-pending-one-more', 'termination-booking', `${TB}pending_lovelace: 5 }`, tbShape({ inputs: [[5, 'checkpoint']] }));
  add('termination-booking-without-active-token', 'termination-booking', `${TB}pending_holds_active: False }`, tbShape());
  add('termination-booking-request-one-more', 'termination-booking', `${TB}request_lovelace: 4 }`, tbShape({ outputs: [[4, 'app'], [1, 'spender']] }));
  add('termination-booking-request-one-less', 'termination-booking', `${TB}request_lovelace: 2 }`, tbShape({ outputs: [[2, 'app'], [1, 'spender']] }));
  add('termination-booking-request-datum', 'termination-booking', `${TB}request_datum: InlineDatum(rows.initial_datum(0)) }`, tbShape());
  add('termination-booking-without-configuration', 'termination-booking', `${TB}references: False }`, tbShape({ referenced: 0 }));
  add('termination-booking-foreign-registry', 'termination-booking', `${TB}registry: requests.foreign_registry(), actions: [${bookTermination(0, 'requests.foreign_registry()')}] }`, tbShape());
  add('termination-booking-two-approvals', 'termination-booking', `${TB}mint: 2 }`, tbShape());
  add('termination-booked-twice', 'termination-booking', `${TB}copies: 2, booker_lovelace: 0, mint: 2, actions: [${bookTermination(0)}, ${bookTermination(1)}] }`, tbShape({ outputs: [[3, 'app'], [3, 'app']] }));
  const configurationIds = ['configuration-created', 'configuration-with-retraction', 'configuration-foreign-registry'];
  if (spec.length + configurationIds.length !== data.rows.length) throw new Error(`the Lean vectors have ${data.rows.length} rows, this script knows ${spec.length + configurationIds.length}`);

  for (const s of spec) {
    const r = row(s.id);
    if (r.kind !== (s.kind === 'minted' ? 'termination' : s.kind)) throw new Error(`row ${s.id}: kind ${r.kind}`);
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    if (!same([r.validity.lower, r.validity.upper], s.shape.validity)) throw new Error(`row ${s.id}: validity`);
    if (r.referenced !== s.shape.referenced || r.donation !== s.shape.donation) throw new Error(`row ${s.id}: references or donation`);
    const shapeOf = (list) => list.map((x) => [x.lovelace, Object.keys(roles).find((k) => roles[k] === x.address) ?? x.address]);
    if (!same(shapeOf(r.inputs), s.shape.inputs)) throw new Error(`row ${s.id}: inputs ${JSON.stringify(shapeOf(r.inputs))}`);
    if (!same(shapeOf(r.outputs), s.shape.outputs)) throw new Error(`row ${s.id}: outputs ${JSON.stringify(shapeOf(r.outputs))}`);
    if (r.verdict !== 'accepted' && r.verdict !== 'refused') throw new Error(`row ${s.id}: verdict`);
  }

  // --- the lib module -------------------------------------------------------------
  const flag = (b) => (b ? 'True' : 'False');
  const keyAddr = (a) => `Address { payment_credential: VerificationKey(#"${addressRe.exec(a)[1]}"), stake_credential: None }`;
  const reqCase = (r) => {
    const registry = r.registry === keri ? 'keri_registry()' : 'foreign_registry()';
    const holding = r.holding === checkpointAddr ? 'held.address_of(cfg.checkpoint_credential)'
      : r.holding === otherAddr ? 'other_address'
        : `held.address_of(Script(cfg.application_policy))`;
    return `    ${r.raw} ->
      RegistrationData {
        registry: ${registry},
        key: key_e,
        controller: #"${'00'.repeat(28)}",
        refund_address: ${r.refund === 'pointer' ? 'pointer_refund_address' : 'refund_address'},
        holding_address: ${holding},
        initial_datum: ${r.datum === undefined ? 'initial_datum(0)' : r.datum === 'e2' ? 'initial_datum(1)' : `variant(${r.datum})`},
        deposit: ${r.deposit},
        booked_at: ${bookedAt},
        process_deadline: ${r.deadline},
        reclaim_end: ${r.deadline},
      }`;
  };
  const lib = `//// Generated by scripts/application-vectors.mjs from lean/application-vectors.json
//// and the public \`singular_state\` script. Do not edit.
////
//// The scenario of the Lean rows on the real registry: the requests the rows
//// decode (the fixture numbers 9001 to 9006 of the Lean, as requests of the
//// real registry), the initial checkpoint datums, the addresses of the five
//// parties, and the names the Lean fixes, recomputed here independently of
//// the Aiken code.
////
//// Mapping of the Lean values: an address is the Plutus address of the
//// credential the Lean names, without a stake credential; the Lean request's
//// \`initialDatum\` (a hash) is the datum itself, whose BLAKE2b-256 the approval
//// commits; the controller is 28 zero bytes; the Lean's abstract state policy is
//// \`state(A_keri)\`; the foreign registry is the registry of \`singular_state\`
//// applied to another application.

use aiken/cbor
use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address, Pointer, Script, VerificationKey}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/checkpoint/datum.{KeyMaterial, Live, TerminationPending}
use singular_state/preimage.{RegistryIdentity}

/// The script hash standing for the lifecycle observer (a parameter of the
/// validator; the Lean model has no such input).
pub const observer_hash: ByteArray = #"${hex(scriptHash(11))}"

/// What a fold's holding must hold: the registry's minimum ADA, the checkpoint
/// deposit, the freeze bond and one premium (Lean Mc + D + B + P). The pool is
/// what the deposit leaves above the first three and must cover the premium.
pub const initial_floor: Int = ${initialFloor}

/// The network refund addresses are recorded for: the test network.
pub const network_id: Int = 0

/// An address no checkpoint datum can record as a refund: a pointer stake part.
pub const pointer_refund_address: Address =
  Address {
    payment_credential: VerificationKey(#"${refundHash}"),
    stake_credential: Some(Pointer { slot_number: 1, transaction_index: 2, certificate_index: 3 }),
  }

/// The registry's minimum ADA (Lean \`Mc\`): a convicted checkpoint's pending output
/// holds exactly it.
pub const checkpoint_minimum_ada: Int = ${checkpointMinimumAda}

/// The carrier of a termination request (Lean \`Mr\`): the request holds it and the
/// registry's minimum tip.
pub const termination_carrier: Int = ${terminationCarrier}

/// The registry's minimum ADA plus its deposit, the least deposit a booking
/// commits (Lean \`Mc + D\`).
pub const minimum_deposit: Int = ${minimumDeposit}

pub const refund_address: Address = ${keyAddr(refundAddr)}

pub const spender_address: Address = ${keyAddr(spenderAddr)}

pub const other_address: Address = ${keyAddr(otherAddr)}

/// The key of the AID \`aidE\` of the Lean (its CESR text) and of \`aidE2\`.
pub const key_e: ByteArray = #"${a0.key}"

pub const key_e2: ByteArray = #"${a2.key}"

const datum_e: ByteArray = #"${datumE}"

const datum_e2: ByteArray = #"${datumE2}"

/// The version 2 checkpoint datum of the AID \`aidE\` (0) or \`aidE2\` (1), as the
/// Lean writes it.
pub fn initial_datum(which: Int) -> Data {
  let bytes = if which == 0 {
    datum_e
  } else {
    datum_e2
  }
  expect Some(datum) = cbor.deserialise(bytes)
  datum
}

fn live_of(
  sn: Int,
  epoch: Int,
  poisoned: Bool,
  frozen: Bool,
  born_at: Int,
  refund_to: ByteArray,
  topped_up: Bool,
  keys: KeyMaterial,
) -> Data {
  expect Live { aid, .. } = datum.read(initial_datum(0))
  datum.write(
    Live { aid, sn, epoch, poisoned, frozen, born_at, refund_to, topped_up, keys },
  )
}

/// The checkpoint datum of \`aidE\` in another state than the initial one, one
/// field at a time: 1 sequence number 7, 2 epoch 3, 3 poisoned, 4 frozen,
/// 5 topped up, 6 born one slot after the booking bound, 7 refunding to the other
/// address, 8 a pending termination, 9 the initial state with other key material.
pub fn variant(which: Int) -> Data {
  expect Live { aid, sn, epoch, poisoned, frozen, born_at, refund_to, topped_up, keys } =
    datum.read(initial_datum(0))
  when which is {
    1 -> live_of(7, epoch, poisoned, frozen, born_at, refund_to, topped_up, keys)
    2 -> live_of(sn, 3, poisoned, frozen, born_at, refund_to, topped_up, keys)
    3 -> live_of(sn, epoch, True, frozen, born_at, refund_to, topped_up, keys)
    4 -> live_of(sn, epoch, poisoned, True, born_at, refund_to, topped_up, keys)
    5 -> live_of(sn, epoch, poisoned, frozen, born_at, refund_to, True, keys)
    6 -> live_of(sn, epoch, poisoned, frozen, born_at + 1, refund_to, topped_up, keys)
    7 ->
      live_of(
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        bytearray.push(#"${otherHash}", 96),
        topped_up,
        keys,
      )
    8 -> datum.write(TerminationPending { aid, sn: 0, epoch: 0 })
    9 ->
      live_of(
        sn,
        epoch,
        poisoned,
        frozen,
        born_at,
        refund_to,
        topped_up,
        KeyMaterial { ..keys, cur_keys: list.concat(keys.cur_keys, [#"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"]) },
      )
    _ -> fail @"no such variant"
  }
}

/// Whether the datums built here serialise back to the Lean's bytes.
pub fn datums_read_back() -> Bool {
  cbor.serialise(initial_datum(0)) == datum_e && cbor.serialise(initial_datum(1)) == datum_e2
}

pub fn keri_registry() -> RegistryIdentity {
  RegistryIdentity { policy: cfg.state_policy, name: cfg.registry_name }
}

pub fn foreign_registry() -> RegistryIdentity {
  RegistryIdentity { policy: cfg.foreign_state_policy, name: cfg.registry_name }
}

/// The request the Lean fixture number \`raw\` decodes to.
pub fn request_data(raw: Int) -> RegistrationData {
  when raw is {
${requests.map(reqCase).join('\n')}
    _ -> fail @"no such request"
  }
}

/// The approval name of each request, recomputed independently.
pub const approval_names: List<(Int, ByteArray)> =
  [
${namedRequests.map((r) => `    (${r.raw}, #"${r.name}")`).join(',\n')},
  ]

/// The name of the active token of the AID \`aidE\` in the real registry, and of
/// its termination approval.
pub const active_name: ByteArray = #"${activeName}"

pub const termination_approval_name: ByteArray = #"${terminationName}"

pub type LeanApproval {
  registry_policy: ByteArray,
  key: ByteArray,
  initial_datum_hash: ByteArray,
  datum: Int,
  deposit: Int,
  preimage: ByteArray,
  name: ByteArray,
}

/// The three approval rows of the Lean, with the Lean's own abstract state
/// policy and application policy.
pub const lean_approvals: List<LeanApproval> =
  [
${leanApprovals.map(({ a, preimage }) => `    LeanApproval {
      registry_policy: #"${a.input.statePolicy}",
      key: #"${a.key}",
      initial_datum_hash: #"${a.initialDatumHash}",
      datum: ${a.input.initialDatum === datumE ? 0 : 1},
      deposit: ${a.input.deposit},
      preimage: #"${hex(preimage)}",
      name: #"${a.approval.name}",
    }`).join(',\n')},
  ]

/// The termination approvals of the Lean, with its abstract state policy.
pub type LeanTerminationApproval {
  key: ByteArray,
  preimage: ByteArray,
  name: ByteArray,
}

pub const lean_termination_approvals: List<LeanTerminationApproval> =
  [
${termApprovals.map((t) => `    LeanTerminationApproval {
      key: #"${t.key}",
      preimage: #"${t.preimage}",
      name: #"${t.approval.name}",
    }`).join(',\n')},
  ]

/// The state policy the Lean names the registry of its release rows by.
pub const lean_state_policy: ByteArray = #"${a0.input.statePolicy}"

/// A pending output's datum offered to the checkpoint validator, with the
/// mint of the transaction as (policy, name, quantity), and the Lean verdict.
pub type LeanRelease {
  datum: ByteArray,
  mint: List<(ByteArray, ByteArray, Int)>,
  released: Bool,
}

pub const lean_releases: List<LeanRelease> =
  [
${releases.map((r) => `    LeanRelease {
      datum: #"${r.datum}",
      mint: [${r.mint.map((m) => `(#"${m.policy}", #"${m.name}", ${m.quantity})`).join(', ')}],
      released: ${r.verdict === 'released' ? 'True' : 'False'},
    }`).join(',\n')},
  ]

/// The application policy the Lean approvals are named under.
pub const lean_application_policy: ByteArray = #"${a0.approval.policy}"

/// The Lean registry name.
pub const lean_registry_name: ByteArray = #"${a0.registryName}"
`;

  // --- the row tests -------------------------------------------------------------
  const runner = {
    booking: (call) => `accepts(requests.booking_tx(${call}))`,
    fold: (call) => `accepts(requests.fold_tx(${call}))`,
    return: (call) => `accepts(requests.return_tx(${call}))`,
    termination: (call) => `accepts(requests.termination_tx(${call}))`,
    'termination-booking': (call) => `accepts(requests.termination_booking_tx(${call}))`,
    minted: (call) => `accepts(${call})`,
    checkpoint: (call) => `accepts(${call})`,
  };
  const tests = spec.map((s) => `/// Lean row \`${s.id}\`: ${row(s.id).note}.
test row_${s.id.replace(/-/g, '_')}() {
  ${runner[s.kind](s.call)} == ${flag(row(s.id).verdict === 'accepted')}
}
`);
  const approvalTests = leanApprovals.map(({ a }, k) => {
    const id = a.id.replace(/-/g, '_');
    return `/// Lean approval \`${a.id}\`: ${a.note}. The preimage and the name are the Lean's, byte for byte.
test ${id}_has_the_lean_preimage_and_name() {
  let lean = when list.at(rows.lean_approvals, ${k}) is {
    Some(lean) -> lean
    None -> fail
  }
  let data = lean_request(lean)
  and {
    registration_preimage(
      data.key,
      data.registry,
      data.holding_address,
      initial_datum_hash(data.initial_datum),
      data.deposit,
    ) == lean.preimage,
    initial_datum_hash(data.initial_datum) == lean.initial_datum_hash,
    registration_approval(data) == lean.name,
    approval_name(lean.preimage) == lean.name,
  }
}
`;
  });
  const terminationApprovalTests = termApprovals.map((t, k) => `/// Lean termination approval \`${t.id}\`: ${t.note}. The preimage and the name are the Lean's, byte for byte.
test ${t.id.replace(/-/g, '_')}_has_the_lean_preimage_and_name() {
  let lean = when list.at(rows.lean_termination_approvals, ${k}) is {
    Some(lean) -> lean
    None -> fail
  }
  let registry =
    RegistryIdentity {
      policy: rows.lean_state_policy,
      name: rows.lean_registry_name,
    }
  and {
    termination_preimage(lean.key, registry) == lean.preimage,
    approval_name(termination_preimage(lean.key, registry)) == lean.name,
    approval_name(lean.preimage) == lean.name,
  }
}
`);
  const releaseTestsText = `//// Generated by scripts/application-vectors.mjs from lean/application-vectors.json. Do not edit.
////
//// The five release verdicts of the Lean: a pending output offered to the checkpoint
//// validator's \`Release\` spend, with the mint of the transaction, run against the real
//// validator applied to the Lean's own registry and application policy. The redeemer is
//// constructor 5 with no fields.

use aiken/builtin
use aiken/cbor
use aiken/collection/list
use cardano/address.{from_script}
use cardano/assets.{Value, add, from_lovelace}
use cardano/transaction.{InlineDatum, Input, Output, Transaction, placeholder}
use cardano_keri/application/row_vectors as rows
use checkpoint_register
use freeze_fixture.{
  advance_hash, d_reg, enforcement_hash, entitlement_hash, freeze_bond,
  network_id, policy, premium, spent_ref,
}

fn release_redeemer() -> Data {
  builtin.constr_data(5, [])
}

fn minted(items: List<(ByteArray, ByteArray, Int)>) -> Value {
  list.foldl(
    items,
    from_lovelace(0),
    fn((policy_id, name, quantity), acc) { add(acc, policy_id, name, quantity) },
  )
}

/// The verdict of the checkpoint validator on the Lean release row \`k\`.
fn released(k: Int) -> Bool {
  expect Some(lean) = list.at(rows.lean_releases, k)
  expect Some(datum) = cbor.deserialise(lean.datum)
  let pending =
    Output {
      address: from_script(policy),
      value: from_lovelace(4),
      datum: InlineDatum(datum),
      reference_script: None,
    }
  let tx =
    Transaction {
      ..placeholder,
      inputs: [Input { output_reference: spent_ref(), output: pending }],
      mint: minted(lean.mint),
    }
  checkpoint_register.checkpoint_register.spend(
    rows.lean_state_policy,
    rows.lean_registry_name,
    advance_hash,
    enforcement_hash,
    entitlement_hash,
    network_id,
    d_reg,
    freeze_bond,
    premium,
    rows.lean_application_policy,
    None,
    release_redeemer(),
    spent_ref(),
    tx,
  ) == lean.released
}

${releases.map((r, k) => `/// Lean release \`${r.id}\`: ${r.note}.
test release_${r.id.replace(/-/g, '_').replace(/^release_/, '')}() {
  released(${k})
}`).join('\n\n')}
`;
  const testsText = `//// Generated by scripts/application-vectors.mjs from lean/application-vectors.json
//// and the public \`singular_state\` script. Do not edit.
////
//// Every Lean row of KERI's application beyond the configuration record, run
//// against the real validator: bookings, folds, returns, the delivered
//// checkpoint's own spend, the pending termination, and the three approval
//// rows. The scenario is built by \`keri_application_requests\` from the constants of
//// \`application/row_vectors\`; the verdict of each test is the row's.
////
//// The transactions are the Lean fixtures' with the mapping of
//// \`application/row_vectors\`. The row \`checkpoint-spent-at-checkpoint-validator\`
//// is accepted because the application does not run in it: no input of the
//// transaction is at its address and its policy is neither minted nor burned.

use aiken/collection/list
use cardano/address.{Script}
use cardano/transaction.{InlineDatum, OutputReference, Transaction}
use cardano_keri/application/action.{
  Action, BookRegistration, BookTermination, FoldRegistration,
  ReturnRegistration, SpendAction,
}
use cardano_keri/application/configuration_vectors as cfg
use cardano_keri/application/held.{RegistrationData}
use cardano_keri/application/registration.{registration_approval}
use cardano_keri/application/row_vectors as rows
use keri_application
use keri_application_requests as requests
use keri_application_requests.{
  Booking, Fold, Return, Termination, TerminationBooking,
}
use singular_state/preimage.{
  RegistryIdentity, approval_name, initial_datum_hash, registration_preimage,
  termination_preimage,
}

fn accepts(tx: Transaction) -> Bool {
  requests.accepts(run_mint, run_spend, tx)
}

fn run_mint(actions: List<Action>, tx: Transaction) -> Bool {
  keri_application.keri_application.mint(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    rows.checkpoint_minimum_ada,
    rows.termination_carrier,
    actions,
    requests.application(),
    tx,
  )
}

fn run_spend(
  action: SpendAction,
  reference: OutputReference,
  tx: Transaction,
) -> Bool {
  keri_application.keri_application.spend(
    cfg.state_template_hash,
    rows.observer_hash,
    rows.minimum_deposit,
    rows.initial_floor,
    rows.network_id,
    rows.checkpoint_minimum_ada,
    rows.termination_carrier,
    None,
    action,
    reference,
    tx,
  )
}

/// The request of a Lean approval row, with the Lean's own abstract policies.
fn lean_request(lean: rows.LeanApproval) -> RegistrationData {
  RegistrationData {
    registry: RegistryIdentity {
      policy: lean.registry_policy,
      name: rows.lean_registry_name,
    },
    key: lean.key,
    controller: #"",
    refund_address: rows.refund_address,
    holding_address: held.address_of(cfg.checkpoint_credential),
    initial_datum: rows.initial_datum(lean.datum),
    deposit: lean.deposit,
    booked_at: 0,
    process_deadline: 0,
    reclaim_end: 0,
  }
}

${tests.join('\n')}
${approvalTests.join('\n')}
${terminationApprovalTests.join('\n')}
`;
  return { lib, testsText, releaseTestsText };
};

const format = (name, text) => {
  const work = mkdtempSync(join(tmpdir(), 'application-fmt-'));
  try {
    writeFileSync(join(work, name), text);
    aiken(work, 'fmt', name);
    return readFileSync(join(work, name), 'utf8');
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
};

const { lib, testsText, releaseTestsText } = generate();
const outputs = [
  [rowsPath, format('row_vectors.ak', lib)],
  [testsPath, format('keri_application_rows_tests.ak', testsText)],
  [releaseTestsPath, format('checkpoint_register_release_rows_tests.ak', releaseTestsText)],
];
if (process.argv.includes('--check')) {
  let drift = false;
  for (const [path, text] of outputs) {
    const committed = existsSync(path) ? readFileSync(path, 'utf8') : '';
    if (committed !== text) {
      console.error(`${path} drifts from lean/application-vectors.json and the public singular_state script`);
      drift = true;
    }
  }
  if (drift) process.exit(1);
  console.log('application vectors: no drift');
} else {
  for (const [path, text] of outputs) writeFileSync(path, text);
  console.log(`wrote ${outputs.map(([path]) => path).join(', ')}`);
}
void isHex;
