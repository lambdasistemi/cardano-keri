import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { attemptSystem, newSystem } from './checkpoint-system-core.mjs';
import { acceptsComparison, convictionFixture } from './checkpoint-conviction.mjs';
import { concreteDuplicityAt, rotationValid, thresholdSatisfied } from './checkpoint-simulator-core.mjs';
import { validateEnv } from './registry-wire.mjs';

const rows = JSON.parse(readFileSync(new URL('../lean/checkpoint-rival-validity-vectors.json', import.meta.url)));
const fresh = execFileSync(process.env.LAKE_BIN || 'lake', ['env', 'lean', '--run', 'CheckpointRivalValidityVectors.lean'],
  {cwd: new URL('../lean/', import.meta.url), encoding: 'utf8'});
assert.deepEqual(rows, JSON.parse(fresh), 'fresh Lean comparison corpus');
assert.equal(rows.length, 17);
for (const {name, input, rotationValid: valid, convictionAccepted} of rows) {
  validateEnv({bookings: [], convictionTransactions: [], convictions: [{output: {tx: 105, index: 0}, comparison: input}]});
  assert.equal(input.tip.previous && rotationValid(input.tip.previous, input.rival), valid, name);
  assert.equal(acceptsComparison(input), convictionAccepted, name);
}
const {rotations: admissionCases, thresholds} = JSON.parse(execFileSync(process.env.LAKE_BIN || 'lake',
  ['env', 'lean', '--run', 'RotationAdmissionChecks.lean'],
  {cwd: new URL('../lean/', import.meta.url), encoding: 'utf8'}));
for (const {name, prior, rotation, context, expected} of admissionCases) {
  assert.equal(rotationValid(prior, rotation), expected, name);
  assert.equal(concreteDuplicityAt(1, 1, context, rotation), expected, 'rival: ' + name);
}
for (const {name, keyCount, threshold, expectedMasks} of thresholds) {
  const keys = Array.from({length: keyCount}, (_, index) => index);
  const accepted = [];
  for (let mask = 0; mask < 2 ** keyCount; mask++) {
    const signers = keys.filter(k => mask & (1 << k));
    if (thresholdSatisfied({count: {required: threshold}}, keys, signers)) accepted.push(mask);
  }
  assert.deepEqual(accepted, expectedMasks, name);
}
console.log(`All ${admissionCases.length} rotation admission examples agree with Lean.`);
const spelling = rows.find(row => row.name === 'signed-weight-1-versus-1/1').input;
const inconsistent = structuredClone(spelling);
inconsistent.tip.writer.eventDigest = inconsistent.rival.event.eventDigest;
inconsistent.tip.writer.extension = [99];
assert.equal(acceptsComparison(inconsistent), false, 'one SAID cannot be two events');
console.log('All 17 comparison scenarios agree with both Lean verdicts.');

// Exercise registration through the booking receipt and rotations through both
// the public rotation judgment and the conviction comparison that consumes it.
const corpus = JSON.parse(readFileSync(new URL('./checkpoint-system-corpus.json', import.meta.url)));
const trace = corpus.traces[0], first = trace.cells[0];
function changeBody(signed, changes) {
  Object.assign(signed.event, changes);
  for (const signature of [...signed.signatures, ...signed.receipts]) {
    signature.event = structuredClone(signed.event);
  }
}
function register(changes, structureVerified = true, code = "D") {
  const env = structuredClone(first.env);
  const signed = env[0][1].writers.inceptions[0].signed;
  changeBody(signed, changes);
  signed.structureVerified = structureVerified;
  const aid = signed.event.aid;
  env[0][1].writers.prefixes = {codes: [[aid, code]], digests: [[structuredClone(signed.event), aid]]};
  return attemptSystem(newSystem(first.params, env, trace.deployment), first.command).record.result;
}
function checkRegistration(changes, allowed, label, verified = true, code = "D") {
  const result = register(changes, verified, code);
  if (allowed) assert.ok(result.ok, label);
  else assert.equal(result.error, 'checkpoint-inception-writer-mismatch', label);
}
for (const changes of [{priorDigest: 7}, {cuts: [20]}, {adds: [21]}]) {
  checkRegistration(changes, false, JSON.stringify(changes));
}
checkRegistration({}, false, 'decoded invalid structure', false);
checkRegistration({nextKeys: [], nextThreshold: {count: {required: 1}}}, false, 'missing next digest');
checkRegistration({nextThreshold: {count: {required: 2}}}, false, 'next threshold exceeds commitments');
checkRegistration({threshold: {count: {required: 0}}}, false, 'zero signing threshold', true, "E");
checkRegistration({nextKeys: [], nextThreshold: {count: {required: 0}}, extension: [7]}, false, 'signed anchors', true, "B");
const ratio = (numerator, denominator) => ({numerator, denominator});
const one = ratio(1, 1);
const positions = {
  flat: weight => ({key: {weight}}),
  outer: weight => ({group: {weight, members: [one]}}),
  member: weight => ({group: {weight: one, members: [weight]}}),
};
// The signed D inceptions in the keripy reference differ only in the declared next rule.
const commitments = [21, 22];
for (const [label, weight, allowed] of [
  ['D next below one', ratio(1, 3), false],
  ['D next unreduced', ratio(2, 4), true],
]) {
  const term = positions.flat(weight);
  checkRegistration({nextKeys: commitments, nextThreshold: {weighted: {clauses: [[term, term]]}}}, allowed, label);
}
for (const [position, term] of Object.entries(positions)) {
  for (const [name, fraction, allowed] of [
    ['unreduced', ratio(2, 2), true], ['above-one', ratio(2, 1), false],
    ['zero-denominator', ratio(1, 0), false],
  ]) {
    const rule = {weighted: {clauses: [[term(fraction)]]}};
    for (const field of ['threshold', 'nextThreshold']) {
      const changes = {[field]: rule}, label = [position, name, field].join('/');
      checkRegistration(changes, allowed, label, true, "E");
      checkRegistration(changes, field === "nextThreshold" && allowed, "basic " + label);
      const {comparison} = convictionFixture(11, 1, 1);
      changeBody(comparison.rival, changes);
      assert.equal(rotationValid(comparison.tip.previous, comparison.rival), allowed, 'advance ' + label);
      assert.equal(acceptsComparison(comparison), allowed, 'rival ' + label);
    }
    const {comparison} = convictionFixture(11, 1, 1);
    comparison.tip.previous.nextThreshold = rule;
    assert.equal(acceptsComparison(comparison), allowed, 'predecessor ' + name + '/' + position);
  }
}
const decimalDigest = convictionFixture(11, 1, 1).comparison;
decimalDigest.tip.writer.eventDigest = '01';
changeBody(decimalDigest.rival, {eventDigest: '1'});
assert.equal(acceptsComparison(decimalDigest), true, 'opaque digest spellings survive arithmetic conversion');
console.log('Registration, rotation and rival agree across flat, outer and member weight controls.');
