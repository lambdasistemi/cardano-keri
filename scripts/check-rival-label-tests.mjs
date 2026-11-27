#!/usr/bin/env node
// Drift check of the rival label regression tests (D09 and D10 of the keripy
// comparison): the retained rows under specs/573-conviction/rival-label must
// be the pinned ones, and each generated test's expected SAID must be the own
// SAID the rows carry for that case and role.
//
//   node scripts/check-rival-label-tests.mjs
//
// The generator (specs/573-conviction/rival-label/generate.mjs) reads the raw
// event bytes of the comparison corpus, which is not retained here; the test
// module is therefore carried as generated, formatted by aiken fmt, and this
// check binds what it can: the rows and the expected digests.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const rowsPath = resolve(root, 'specs/573-conviction/rival-label/rows.json');
const testsPath = resolve(root, 'onchain/lib/cardano_keri/checkpoint/rival_label_tests.ak');
const pinned = '100819c9ac523cf0d1e4';

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
if (bad) process.exit(1);
console.log(`rows ${digest.slice(0, 16)}, ${names.length} tests bound to their rows`);
