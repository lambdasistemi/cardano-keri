#!/usr/bin/env node
// D-04 to D-06: asserted projections of the shipped Lean-derived simulators.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const fast = process.argv.includes('--fast');
const pauseMs = fast ? 0 : Number(process.env.DEMO_PAUSE_MS ?? 3500);
assert(Number.isFinite(pauseMs) && pauseMs >= 0 && pauseMs <= 10000);
function play(which, story) {
  return JSON.parse(execFileSync('node', [`simulator/${which}-simulator-cli.mjs`,
    '--story', String(story), '--to-end', '--json'], { encoding: 'utf8' }));
}
const reg = play('registry', 4);
const advance = play('checkpoint', 2);
const freeze = play('checkpoint', 3);
const unpaid = play('checkpoint', 4);
assert.equal(reg.family, 'registry');
assert.equal(reg.path[2].ok, true);
assert.deepEqual(reg.path[2].state.leaves, [{ aid: 11, status: { active: 0 } }]);
assert.equal(reg.path[4].ok, false);
assert.equal(reg.path[4].reason, 'already-registered');
assert.deepEqual(reg.path[4].state.leaves, reg.path[2].state.leaves);
assert.equal(advance.path[3].ok, true);
assert.equal(advance.path[3].state.present.l.sn, 1);
assert.equal(advance.path[3].state.present.l.pool, 8);
assert.equal(freeze.path[3].ok, true);
assert.equal(freeze.path[3].state.present.l.frozen, true);
assert.equal(freeze.path[3].state.present.l.pool, 1);
assert.equal(unpaid.path[4].ok, true);
assert.equal(unpaid.path[4].state.present.l.sn, 1);
assert.equal(unpaid.path[4].state.present.l.pool, 1);
const c = { reset:'\x1b[0m', cyan:'\x1b[1;36m', dim:'\x1b[0;90m',
  green:'\x1b[1;32m', yellow:'\x1b[1;33m', red:'\x1b[0;31m' };
function line(color, s) { console.log(`${c[color]}${s}${c.reset}`); }
async function frame(title, comments, command, output) {
  process.stdout.write('\x1b[H\x1b[2J\x1b[3J'); line('cyan',title); console.log();
  comments.forEach(x => line('dim', `# ${x}`));
  console.log(); line('green', `$ ${command}`); console.log();
  output(); if (pauseMs) await sleep(pauseMs);
}
await frame('D-04 to D-06 | identity model rehearsals', [
  'Alice AID 11 and numeric tokens are simulator fixtures.',
  'No actual inception bytes, policy ID or Cardano tx is shown.',
], 'node demo/identity-model-rehearsal.mjs', () =>
  line('yellow', 'Sources: registry story 4; checkpoint stories 2, 3, 4.'));
await frame('D-04 | registration and duplicate refusal', [
  'The registry simulator folds Alice\'s first request.',
  'A second registration for the same live AID refuses.',
], 'node simulator/registry-simulator-cli.mjs --story 4 --to-end --json', () => {
  line('yellow', 'MODEL ACCEPTED: AID 11 active; token 0; checkpoint live.');
  line('red', `EXPECTED REFUSAL: ${reg.path[4].reason}`);
});
await frame('D-05 | witnessed advance in checkpoint model', [
  'The checkpoint simulator registers, then lands a rotation.',
  'Its pool changes from 10 to 8 model units.',
], 'node simulator/checkpoint-simulator-cli.mjs --story 2 --to-end --json', () => {
  line('yellow', `MODEL ACCEPTED: sn=${advance.path[3].state.present.l.sn}`);
  line('yellow', `pool=${advance.path[3].state.present.l.pool}`);
});
await frame('D-06 | short pool freezes', [
  'The model takes a freeze branch with pool 1.',
  'A short pool is not a blanket refusal.',
], 'node simulator/checkpoint-simulator-cli.mjs --story 3 --to-end --json', () => {
  line('yellow', `MODEL ACCEPTED: frozen=${freeze.path[3].state.present.l.frozen}`);
  line('yellow', `pool=${freeze.path[3].state.present.l.pool}`);
});
await frame('D-06 | unpaid keep from frozen', [
  'The next story reaches an unpaid advance.',
  'Sequence rises while the short pool remains at 1.',
], 'node simulator/checkpoint-simulator-cli.mjs --story 4 --to-end --json', () => {
  line('yellow', `MODEL ACCEPTED: sn=${unpaid.path[4].state.present.l.sn}`);
  line('yellow', `pool=${unpaid.path[4].state.present.l.pool}`);
});
await frame('Candidate model play complete | ledger target open', [
  'These are simulator observations from the shipped corpus.',
  'They do not prove CK to Singular mapping or devnet behavior.',
], 'review the dated pages', () =>
  line('yellow', 'Connected scripts and node receipts remain required.'));
