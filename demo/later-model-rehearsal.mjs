#!/usr/bin/env node
// Assert shipped checkpoint-model observations before printing cast frames.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { parseJsonExact, checkScenario } from '../simulator/checkpoint-simulator-core.mjs';

const page = process.argv[2];
assert(['d07', 'd09'].includes(page), 'usage: node demo/later-model-rehearsal.mjs d07|d09 [--fast]');
const pause = process.argv.includes('--fast') ? 0 : Number(process.env.DEMO_PAUSE_MS ?? 3500);
assert(Number.isFinite(pause) && pause >= 0 && pause <= 10000);
const cli = (story, fork) => JSON.parse(execFileSync('node', [
  'simulator/checkpoint-simulator-cli.mjs', '--story', String(story),
  ...(fork ? ['--fork', fork] : []), '--to-end', '--json'], { encoding: 'utf8' }));
const step = (story, fork, i) => {
  const p = cli(story, fork);
  assert.equal(p.family, 'checkpoint');
  assert.equal(p.story, story);
  return p.path[i];
};
const c = { reset:'\x1b[0m', cyan:'\x1b[1;36m', dim:'\x1b[0;90m',
  green:'\x1b[1;32m', yellow:'\x1b[1;33m', red:'\x1b[0;31m' };
const line = (color, s) => console.log(`${c[color]}${s}${c.reset}`);
async function frame(title, comments, command, output) {
  process.stdout.write('\x1b[H\x1b[2J\x1b[3J'); line('cyan', title); console.log();
  comments.forEach(x => line('dim', `# ${x}`));
  console.log(); line('green', `$ ${command}`); console.log(); await output();
  if (pause) await sleep(pause);
}
if (page === 'd07') {
  const close = step(5, null, 4), returnHome = step(6, null, 4);
  const convict = step(9, null, 3), noProof = step(9, 'noproof', 3);
  const relayer = step(5, 'relayer', 3), stale = step(6, 'replay', 3);
  const terminal = step(9, 'terminal', 4), badClose = step(10, 'current-keys', 3);
  assert.equal(close.ok, true);
  assert.deepEqual(close.state, { parked: { h: { epoch: 1, sn: 1 } } });
  assert.deepEqual(close.flow.refund, { addr: 1, dreg: 1000, b: 5, pool: 8 });
  assert.deepEqual(close.flow.hunter, { addr: 2, dreg: 0, b: 0, pool: 2 });
  assert.equal(returnHome.ok, true);
  assert.equal(returnHome.state.present.l.epoch, 2);
  assert.equal(returnHome.state.present.l.sn, 2);
  assert.equal(convict.ok, true); assert.equal(convict.state, 'convicted');
  assert.deepEqual(convict.flow.convictor, { addr: 3, dreg: 1000, b: 0, pool: 0 });
  assert.deepEqual(convict.flow.refund, { addr: 1, dreg: 0, b: 5, pool: 10 });
  for (const [x, reason] of [[relayer,'intent-not-authorized'], [stale,'no-witnessed-rotation'],
    [noProof,'no-duplicity-proof'], [terminal,'convicted-terminal'],
    [badClose,'no-witnessed-rotation']]) { assert.equal(x.ok, false); assert.equal(x.reason, reason); }
  await frame('D-07 | checkpoint model only', [
    'Stories 5, 6, 9 and 10 are shipped simulator fixtures.',
    'No CK registry transaction or KERI proof bytes are exercised.'
  ], 'node demo/later-model-rehearsal.mjs d07', () =>
    line('yellow', 'Inputs: D=1000, B=5, P=2; addresses 1, 2, 3 are synthetic.'));
  await frame('Close | witnessed rotation and signed intent', [
    'Story 5 registers, adds rotation and close intent, then closes.',
    'This is a model transition from a live checkpoint.'
  ], 'node simulator/checkpoint-simulator-cli.mjs --story 5 --to-end --json', () => {
    line('yellow', 'MODEL: parked epoch=1 sn=1');
    line('yellow', 'Refund addr 1: D=1000 B=5 pool=8');
    line('yellow', 'Hunter addr 2: premium=2');
  });
  await frame('Close refusals | authority and rotation', [
    'A public rotation alone cannot authorize a close.',
    'Current keys cannot substitute for witnessed next keys.'
  ], 'checkpoint CLI: story 5 --fork relayer; story 10 --fork current-keys', () => {
    line('red', `EXPECTED REFUSAL: ${relayer.reason}`);
    line('red', `EXPECTED REFUSAL: ${badClose.reason}`);
  });
  await frame('Return | parked is not terminal', [
    'Story 6 reopens only with a later witnessed rotation.',
    'A replay of the closing rotation fails.'
  ], 'checkpoint CLI: story 6; story 6 --fork replay', () => {
    line('yellow', 'MODEL: reopened epoch=2 sn=2');
    line('red', `EXPECTED REFUSAL: ${stale.reason}`);
  });
  await frame('Conviction | separate model trace', [
    'Story 9 registers, poisons and supplies duplicityAt[0,0].',
    'The predicate is abstract; this is not KERI proof validation.'
  ], 'node simulator/checkpoint-simulator-cli.mjs --story 9 --to-end --json', () => {
    line('yellow', 'MODEL: convicted; Cora addr 3 receives D=1000');
    line('yellow', 'Refund addr 1 receives B=5 pool=10');
  });
  await frame('Conviction refusals | proof and finality', [
    'Without the model duplicity atom, conviction refuses.',
    'A subsequent transition from convicted also refuses.'
  ], 'checkpoint CLI: story 9 --fork noproof; --fork terminal', () => {
    line('red', `EXPECTED REFUSAL: ${noProof.reason}`);
    line('red', `EXPECTED REFUSAL: ${terminal.reason}`);
  });
  await frame('D-07 model play complete | connected target open', [
    'Registry leaf/token, KERI duplicity and real refunds need receipts.'
  ], 'review docs/demos/d07-close-convict.md', () =>
    line('yellow', 'No ledger close or conviction is claimed.'));
} else {
  const dir = 'simulator/checkpoint-simulator-scenarios';
  const files = readdirSync(dir).filter(x => x.endsWith('.json')).sort();
  assert.equal(files.length, 15);
  const corpus = parseJsonExact(readFileSync('simulator/checkpoint-simulator-corpus.json', 'utf8'));
  const rows = files.map(file => {
    const scenario = parseJsonExact(readFileSync(`${dir}/${file}`, 'utf8'));
    const result = checkScenario(scenario, file, corpus);
    assert.deepEqual(result.problems, [], `${file}: ${result.problems.join('; ')}`);
    assert.equal(cli(scenario.story).story, scenario.story);
    return { story: scenario.story, steps: result.stepsRun, forks: result.forks.length };
  });
  assert.deepEqual(rows.map(x => x.story), Array.from({length:15}, (_,i) => i+1));
  assert.equal(rows.reduce((n,x) => n+x.steps,0), 104);
  let gateOutput = '';
  try { gateOutput = execFileSync('node', ['simulator/checkpoint-simulator-scenario-gate.mjs'],
    { encoding: 'utf8', stdio: ['ignore','pipe','pipe'] }); }
  catch (error) { gateOutput = String(error.stdout || ''); }
  const gateSummary = gateOutput.match(/RED: 25 items, 104 story steps replayed, (\d+) problems/);
  assert(gateSummary, 'the full gate status changed; re-evaluate the D-09 cast text');
  assert(gateOutput.includes('FAIL  theorem rows:'));
  assert(gateOutput.includes('FAIL  story reconciliation:'));
  await frame('D-09 | fifteen checkpoint model scenarios', [
    'The shipped core checks each JSON trunk and fork against its',
    'fixture expectations and the parsed Lean corpus.'
  ], 'node demo/later-model-rehearsal.mjs d09', () =>
    line('yellow', 'MODEL: 15 scenario files, 104 action steps.'));
  for (let start=0; start<15; start+=5) await frame(
    `Model stories ${start+1} to ${start+5} | asserted replay`, [
      'Each row includes its fixture forks; no devnet transaction ran.'
    ], 'core.checkScenario(scenario, file, corpus)', async () => {
      for(const x of rows.slice(start,start+5)) {
        line('yellow', `MODEL story ${String(x.story).padStart(2)}: ${x.steps} actions, ${x.forks} forks, assertions pass`);
        if (pause) await sleep(120);
      }
    });
  await frame('D-09 | limits of the model replay', [
    'The full scenario gate is separately RED in this checkout.',
    'Theorem-row/reconciliation checks and devnet receipts remain open.'
  ], 'node simulator/checkpoint-simulator-scenario-gate.mjs', () => {
    line('red', `GATE RED: ${gateSummary[1]} problems in full scenario gate`);
    line('yellow', 'This cast establishes fixture replay only.');
  });
}
