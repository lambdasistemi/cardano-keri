import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { acceptsComparison } from './checkpoint-conviction.mjs';
import { rotationValid } from './checkpoint-simulator-core.mjs';
import { validateEnv } from './registry-wire.mjs';

const rows = JSON.parse(readFileSync(new URL('../lean/checkpoint-rival-validity-vectors.json', import.meta.url)));
const fresh = execFileSync(process.env.LAKE_BIN || 'lake', ['env', 'lean', '--run', 'CheckpointRivalValidityVectors.lean'],
  {cwd: new URL('../lean/', import.meta.url), encoding: 'utf8'});
assert.deepEqual(rows, JSON.parse(fresh), 'fresh Lean comparison corpus');
assert.equal(rows.length, 16);
for (const {name, input, rotationValid: valid, convictionAccepted} of rows) {
  validateEnv({bookings: [], convictionTransactions: [], convictions: [{output: {tx: 105, index: 0}, comparison: input}]});
  assert.equal(input.tip.previous && rotationValid(input.tip.previous, input.rival), valid, name);
  assert.equal(acceptsComparison(input), convictionAccepted, name);
}
console.log('All 16 comparison scenarios agree with both Lean verdicts.');
