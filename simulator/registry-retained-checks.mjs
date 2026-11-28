#!/usr/bin/env node
/* Focused executable checks for the retained-custody Registry simulator.
 * The full scenario gate additionally binds source clauses and page controls. */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkScenario, stepFn, checkCell, init, attempt, newSession, setEvidence, equal } from './registry-simulator-core.mjs';
import { parseScenarioDsl, scenarioToDsl } from './scenario-dsl.mjs';
import { playStory, selectPath, projectJson, submit, replaceEvidence } from './registry-simulator-backend.mjs';
import { runSimulatorCli } from './registry-simulator-cli.mjs';
const here = dirname(fileURLToPath(import.meta.url));
const files = readdirSync(join(here, 'registry-simulator-scenarios')).filter(f => f.endsWith('.json')).sort();
const retired = JSON.parse(readFileSync(join(here, 'registry-story-migration.json'), 'utf8')).stories.filter(s => s.retired).map(s => s.id);
assert.equal(files.length, 15 - retired.length, 'story census');
assert(files.every(f => !retired.includes(Number(f.slice(0, 2)))), 'a retired story has no scenario');
let cells = 0, controls = 0;
for (const file of files) {
  const sc = JSON.parse(readFileSync(join(here, 'registry-simulator-scenarios', file), 'utf8'));
  const dsl = readFileSync(join(here, 'registry-simulator-scenarios', file.replace('.json', '.dsl')), 'utf8');
  assert.deepEqual(parseScenarioDsl(dsl).scenario, sc, `${file}: DSL identity`);
  assert.equal(scenarioToDsl('registry', sc), dsl, `${file}: canonical DSL`);
  const report = checkScenario(sc);
  assert.deepEqual(report.problems, [], `${file}: full replay`);
  cells += report.timeline.length + Object.values(report.forkTimelines).reduce((n, xs) => n + xs.length, 0);
  const tree = playStory(sc.id);
  for (const branch of [null, ...sc.forks.map(f => f.id)]) {
    let output = '', error = '';
    const args = ['--story', String(sc.id), '--to-end', '--json', ...(branch ? ['--fork', branch] : [])];
    assert.equal(runSimulatorCli(args, s => { output += s; }, s => { error += s; }), 0, error);
    assert(equal(JSON.parse(output), projectJson(selectPath(tree, branch, true))), 'CLI/backend projection');
  }
  const falseResult = structuredClone(sc);
  const accepted = falseResult.steps.find(s => s.expect.result.ok);
  accepted.expect.result.ok.state.gen++;
  assert(checkScenario(falseResult).problems.some(p => p.includes('full result mismatch')), 'fabricated result control'); controls++;
}
assert.equal(cells, 67, 'story and fork cell census');
const sc = JSON.parse(readFileSync(join(here, 'registry-simulator-scenarios', files.find(f => f.startsWith('12-'))), 'utf8'));
const tree = playStory(sc.id), live = tree.nodes.find(n => n.session.state.carriers[0]?.pendingSpend === null);
assert(live, 'reachable live input');
const session = live.session;
const valid = { convictCkpt: { aid: 11 } };
const before = JSON.stringify(session);
const success = attempt(session, valid);
assert(success.record.result.ok, 'positive conviction');
assert.deepEqual(success.session.state.carriers[0].pendingSpend, {reference: {tx:105,index:0}, aid:11, position:{epoch:1,sn:1}}, 'conviction retains pending custody');
assert.equal(JSON.stringify(session), before, 'immutable source session');
assert.equal(success.session.state.carriers[0].token, session.state.carriers[0].token, 'retained token');
assert.deepEqual(success.session.state.trie, session.state.trie, 'retained active key');
// Keep the accepted ledger example and change only the evidence projection.
const registration = sc.steps.find(s => s.action.bookRegistration);
const bookingEnv = registration.env ?? sc.env;
const request = registration.action.bookRegistration.booking.request;
const runBooking = env => stepFn(sc.params, env, registration.action, init(sc.config));
assert(runBooking(bookingEnv).ok);
for (const change of [
  row => {row.identity++;},
  row => {row.assets.mint[0][1] = 2;},
  row => {row.assets.mint[0][0].name++;},
  row => {row.assets.mint[0][0].policy++;},
  row => {row.assets.outputs = [{assets: row.assets.mint}]; row.assets.mint = [];},
]) {
  const env = structuredClone(bookingEnv);
  change(env.bookings.find(r => equal(r.identity, request.reference.tx)));
  assert.equal(runBooking(env).error, 'keri-inception-refused');
  controls++;
}
for (const change of [
  row => {row.observation.transaction.mint.shift();},
  row => {row.observation.transaction.mint.pop();},
  row => {row.observation.transaction.mint[0][1] = -1;},
  row => {row.observation.transaction.spent = [];},
  row => {row.output.tx++;},
]) {
  const env = structuredClone(session.env);
  change(env.convictionTransactions.find(r => equal(r.output, success.session.state.carriers[0].pendingSpend.reference)));
  assert.equal(attempt(setEvidence(session, env), valid).record.result.error, 'keri-conviction-refused');
  controls++;
}
const withoutEvidence = setEvidence(session, { ...session.env, convictions: [] });
assert.equal(attempt(withoutEvidence, valid).record.result.error, 'keri-conviction-refused', 'stored key evidence');
// Independently exercise the signature and the output fields on the paid path.
const badSignature = structuredClone(session.env);
badSignature.convictions[0].comparison.rival.signatures = [];
assert.equal(attempt(setEvidence(session, badSignature), valid).record.result.error, 'keri-conviction-refused');
const differentOutput = structuredClone(session.env);
differentOutput.convictions[0].output.index = 3;
assert.equal(attempt(setEvidence(session, differentOutput), valid).record.result.error, 'keri-conviction-refused');
differentOutput.convictionTransactions[0].output.index = 3;
const changedReceipt = attempt(setEvidence(session, differentOutput), valid);
assert.equal(changedReceipt.session.state.carriers[0].pendingSpend.reference.index, 3);
const oldBooking = sc.steps.find(step => step.action.bookTermination).action;
assert.equal(attempt(changedReceipt.session, oldBooking).record.result.error, 'keri-conviction-required');
controls += 3;
const changed = submit(tree, valid, live.id);
assert.equal(changed.nodes.length, tree.nodes.length + 1, 'free attempt is sibling');
assert.equal(tree.nodes[live.id].children.length + 1, changed.nodes[live.id].children.length, 'original continuation retained');
assert.equal(replaceEvidence(tree, withoutEvidence.env, live.id).nodes.at(-1).kind, 'evidence');
const invalid = [
  ['negative state Nat', x => { x.state.gen = -1; }],
  ['unsafe state Number', x => { x.state.nextToken = 9007199254740992; }],
  ['fractional unused parameter', x => { x.params.tip = 0.5; }],
  ['negative unused evidence', x => { x.env.bookings.push({identity:-1,assets:{mint:[],invoked:[],spent:[],outputs:[]}}); }],
  ['unsafe evidence Number', x => { x.env.convictions[0].comparison.tip.epoch = 9007199254740992; }],
  ['unknown state field', x => { x.state.stranger = 1; }],
  ['negative held datum', x => { x.state.carriers[0].original.datum = -1; }],
  ['small numeric string', x => { x.state.gen = '1'; }],
  ['noncanonical large integer', x => { x.state.gen = '-09007199254740993'; }],
];
for (const [label, mutate] of invalid) {
  const bad = structuredClone(session); mutate(bad);
  assert.throws(() => attempt(bad, valid), /invalid-|noncanonical-/, label);
  assert.throws(() => setEvidence(bad, bad.env), /invalid-|noncanonical-/, `${label}: evidence entry point`);
  controls += 2;
}
assert.throws(() => init({ ...sc.config, root: [256] }), /invalid-wire/, 'root byte domain'); controls++;
assert.throws(() => newSession({ ...sc.params, D: 0 }, sc.config, sc.env), /params.proofs/, 'positive bond'); controls++;
const large = structuredClone(session);
large.env.convictions[0].comparison.tip.epoch = '9007199254740992';
assert.equal(attempt(large, valid).session.state.carriers[0].pendingSpend.position.epoch, '9007199254740992', 'exact key above Number bound');
const fakeCell = { params: session.params, env: session.env, input: session.state, action: valid, result: success.record.result };
const broken = structuredClone(fakeCell); broken.result.ok.state.nextToken = 9007199254740992;
assert.throws(() => checkCell(broken), /invalid-exact-integer/, 'corpus result exact-number validation'); controls++;
assert.equal(stepFn(session.params, session.env, valid, success.session.state).error, 'keri-conviction-refused', 'pending custody is not convicted again');
assert(equal(checkCell(fakeCell).actual, fakeCell.result));
console.log(JSON.stringify({ stories: files.length, replayedCells: cells, negativeControls: controls, cliAndForks: 'pass', exactIntegerKey: 'pass' }));
