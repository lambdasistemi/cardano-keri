// Specification checks only; no transaction construction or KERI networking.
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';

const root = dirname(fileURLToPath(import.meta.url));
const corpus = JSON.parse(readFileSync(join(root, 'checkpoint-conformance.json'), 'utf8'));
const registry = JSON.parse(readFileSync(join(root, 'refusals.json'), 'utf8'));
const expected = registry.refusals.filter(r => r.layer === 'stepFn').map(r => r.name).sort();
const singleton = new Set();
for (const c of corpus.cells) {
  assert.ok(c.s < corpus.states.length && c.a < corpus.actions.length && c.e < corpus.envs.length);
  if (c.result.status !== 'refused') continue;
  const r = c.result.refusals;
  assert.deepEqual(r, [...new Set(r)].sort());
  if (r.length === 1) singleton.add(r[0]);
}
assert.deepEqual([...singleton].sort(), expected, 'every guard needs a case where it alone refuses');
if (process.argv[2]) {
  const generated = spawnSync(process.execPath, [join(root, 'extract-checkpoint.mjs'), process.argv[2]], { encoding: 'utf8' });
  assert.equal(generated.status, 0, generated.stderr);
  assert.deepEqual(JSON.parse(generated.stdout), corpus, 'corpus differs from fresh Lean output');
}

const scratch = mkdtempSync(join(tmpdir(), 'keri-api-shapes-'));
const controls = JSON.parse(readFileSync(join(root, 'shape-controls.json'), 'utf8'));
controls.push({ name: 'large-natural', valid: true,
  cborHex: 'a266616374696f6e65746f70557066616d6f756e74c24b0100000000000000000000' });
let count = 0;
function validate(path, valid, name) {
  const r = spawnSync('cddl', [join(root, 'checkpoint-model.cddl'), 'validate', path], { encoding: 'utf8' });
  assert.equal(r.error, undefined, `${name}: ${r.error}`);
  assert.equal(r.status, valid ? 0 : 1, `${name}: ${r.stderr}`);
  if (!valid) assert.match(r.stderr, /CDDL validation failure/, `${name}: wrong failure reason`);
  count++;
}
try {
  validate(join(root, 'checkpoint-conformance.json'), true, 'model-corpus');
  for (const c of controls) {
    const file = join(scratch, c.name + (c.cborHex ? '.cbor' : '.json'));
    writeFileSync(file, c.cborHex ? Buffer.from(c.cborHex, 'hex') : JSON.stringify(c.value));
    validate(file, c.valid, c.name);
  }
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
console.log(JSON.stringify({ cells: corpus.cells.length, isolatedRefusals: singleton.size,
  cddlChecks: count, freshLeanParity: Boolean(process.argv[2]) }));
