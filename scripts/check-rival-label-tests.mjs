#!/usr/bin/env node
// Drift check of the rival label regression tests (D09 and D10 of the keripy
// comparison): the retained rows under specs/573-conviction/rival-label must
// be the pinned ones, and each generated test's expected SAID must be the own
// SAID the rows carry for that case and role.
//
//   node scripts/check-rival-label-tests.mjs
//
// The generator (specs/573-conviction/rival-label/generate.mjs) reads the raw
// event bytes of the comparison corpus. Only the two cases it needs (D09, D10)
// are retained, in d09-d10.json, with the corpus commit and digest they come
// from; the check regenerates the tests from them and requires the committed
// module to be the same tokens (aiken fmt only reorders imports and wraps).
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const rowsPath = resolve(root, 'specs/573-conviction/rival-label/rows.json');
const testsPath = resolve(root, 'onchain/lib/cardano_keri/checkpoint/label_regression_tests.ak');
const pinned = '100819c9ac523cf0d1e4';
const subsetPath = resolve(root, 'specs/573-conviction/rival-label/d09-d10.json');
const subsetPinned = 'a13e764bc8be2646d723';
const generator = resolve(root, 'specs/573-conviction/rival-label/generate.mjs');

const raw = readFileSync(rowsPath);
const digest = createHash('sha256').update(raw).digest('hex');
if (!digest.startsWith(pinned)) { console.error(`rows digest ${digest.slice(0, 20)} is not the pinned ${pinned}`); process.exit(1); }
const rows = JSON.parse(raw.toString('utf8')).rows;
const source = readFileSync(testsPath, 'utf8');

let bad = 0;
const names = [...source.matchAll(/^test (d\d+)_(accepted|rival)_opens_own_said\(\)/gm)];
if (names.length !== 4) { console.error(`expected 4 tests, found ${names.length}`); bad++; }
for (const [, id, role] of names) {
  const row = rows.find((r) => r.case === id.toUpperCase() && r.role === role);
  if (!row) { console.error(`no row for ${id} ${role}`); bad++; continue; }
  const block = source.slice(source.indexOf(`test ${id}_${role}_opens_own_said()`));
  const expected = /qb64_aid\(digest\) == "([^"]+)"/.exec(block)?.[1];
  if (expected !== row.signed.event.eventDigest) { console.error(`${id} ${role}: test expects ${expected}, rows carry ${row.signed.event.eventDigest}`); bad++; }
}
const subset = readFileSync(subsetPath);
const subsetDigest = createHash('sha256').update(subset).digest('hex');
if (!subsetDigest.startsWith(subsetPinned)) { console.error(`d09-d10 digest ${subsetDigest.slice(0, 20)} is not the pinned ${subsetPinned}`); bad++; }
const generated = spawnSync(process.execPath, [generator, subsetPath], { encoding: 'utf8' });
if (generated.status !== 0) { console.error(`generator failed: ${generated.stderr}`); bad++; }
const tokens = (text) => text.replace(/[ ,\n]/g, '').replace(/use/g, '\nuse').replace(/test/g, '\ntest').split('\n').sort().join('\n');
if (tokens(generated.stdout) !== tokens(source)) { console.error('the committed tests are not what the retained rows generate'); bad++; }
if (bad) process.exit(1);
console.log(`rows ${digest.slice(0, 16)}, ${names.length} tests bound to their rows`);
