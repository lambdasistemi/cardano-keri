#!/usr/bin/env node
/* Focused executable checks for the retained-output Registry simulator.
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
assert.equal(files.length, 15, 'story census');
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
assert.equal(cells, 84, 'story and fork cell census');
const sc = JSON.parse(readFileSync(join(here, 'registry-simulator-scenarios', files[8]), 'utf8'));
const tree = playStory(sc.id), parked = tree.nodes.find(n => n.session.state.carriers[0]?.st === 'parked');
assert(parked, 'reachable parked input');
const session = parked.session;
const valid = { revive: { aid: 11 } };
const before = JSON.stringify(session);
const success = attempt(session, valid);
assert(success.record.result.ok, 'positive revival');
assert.equal(JSON.stringify(session), before, 'immutable source session');
assert.equal(success.session.state.carriers[0].token, session.state.carriers[0].token, 'retained token');
assert.deepEqual(success.session.state.trie, session.state.trie, 'retained active key');
const withoutEvidence = setEvidence(session, { ...session.env, rotationFrom: [] });
assert.equal(attempt(withoutEvidence, valid).record.result.error, 'keri-revival-refused', 'stored key evidence');
const changed = submit(tree, valid, parked.id);
assert.equal(changed.nodes.length, tree.nodes.length + 1, 'free attempt is sibling');
assert.equal(tree.nodes[parked.id].children.length + 1, changed.nodes[parked.id].children.length, 'original continuation retained');
assert.equal(replaceEvidence(tree, withoutEvidence.env, parked.id).nodes.at(-1).kind, 'evidence');
const invalid = [
  ['negative state Nat', x => { x.state.gen = -1; }],
  ['unsafe state Number', x => { x.state.nextToken = 9007199254740992; }],
  ['fractional unused parameter', x => { x.params.tip = 0.5; }],
  ['negative unused evidence', x => { x.env.inception.push(-1); }],
  ['unsafe evidence Number', x => { x.env.duplicity.push([11, 9007199254740992]); }],
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
large.state.carriers[0].k = '9007199254740992';
large.env.rotationFrom = [[11, '9007199254740992']];
assert.equal(attempt(large, valid).session.state.carriers[0].k, '9007199254740993', 'exact successor above Number bound');
const fakeCell = { params: session.params, env: session.env, input: session.state, action: valid, result: success.record.result };
const broken = structuredClone(fakeCell); broken.result.ok.state.nextToken = 9007199254740992;
assert.throws(() => checkCell(broken), /invalid-exact-integer/, 'corpus result exact-number validation'); controls++;
const parent = structuredClone(session); parent.env.closeAuth = [];
assert.equal(stepFn(parent.params, parent.env, { park: { aid: 11, recipient: 6 } }, success.session.state).error, 'keri-close-refused');
assert(equal(checkCell(fakeCell).actual, fakeCell.result));
console.log(JSON.stringify({ stories: files.length, replayedCells: cells, negativeControls: controls, cliAndForks: 'pass', exactIntegerSuccessor: 'pass' }));
