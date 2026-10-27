#!/usr/bin/env node
// Replay the frozen probes with concrete example pairs. Historical sources,
// expected results and manifests are read-only; only scratch copies change.
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url)), root = resolve(here, '../../..');
const work = mkdtempSync(join(tmpdir(), 'keri-concrete-replay-'));
const lake = args => execFileSync('nix', ['shell', '--no-write-lock-file', '.#lean', '--command', 'lake', ...args],
  { cwd: join(root, 'lean'), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
const hash = data => createHash('sha256').update(data).digest('hex');
function replaceOnce(source, before, after) {
  if (source.split(before).length !== 2) throw new Error('adapter requires exactly one match: ' + before);
  return source.replace(before, after);
}
try {
  lake(['build', 'CardanoKeri.DuplicityExamples', 'CardanoKeri.Checkpoint']);
  for (const [file, receipt, target] of [
    ['EscapeProbe.lean', 'escape-probes.jsonl', [1, 1]],
    ['GistProbe.lean', 'gist-probes.jsonl', [2, 8]],
  ]) {
    const original = readFileSync(join(here, file), 'utf8');
    let source = replaceOnce(original, 'import CardanoKeri.Checkpoint',
      'import CardanoKeri.Checkpoint\nimport CardanoKeri.DuplicityExamples');
    source = replaceOnce(source, 'duplicityAt := fun _ _ => false',
      'convictionContext := fun _ _ => none\n  convictionRival := fun _ _ => none');
    const fields = (e, sn) => `convictionContext := (fun epoch sn => if epoch == ${e} && sn == ${sn} then some (CardanoKeri.Duplicity.fixture epoch sn).1 else none), convictionRival := (fun epoch sn => if epoch == ${e} && sn == ${sn} then some (CardanoKeri.Duplicity.fixture epoch sn).2 else none)`;
    source = replaceOnce(source, 'duplicityAt := fun epoch sn => epoch == 1 && sn == 7', fields(1, 7));
    source = replaceOnce(source, file === 'EscapeProbe.lean' ?
      'duplicityAt := fun epoch sn => epoch == 1 && sn == 1' :
      'duplicityAt := fun e sn => e == 2 && sn == 8', fields(...target));
    const path = join(work, file); writeFileSync(path, source);
    const result = lake(['env', 'lean', '--run', path]);
    const expected = readFileSync(join(here, receipt), 'utf8');
    if (result.trim() !== expected.trim()) throw new Error(file + ': historical outcomes changed');
    const rows = result.trim().split('\n').map(JSON.parse);
    if (rows.some(r => r.pass !== true)) throw new Error(file + ': failed case');
    console.log(JSON.stringify({ probe: file, cases: rows.length, sourceSha256: hash(original),
      adaptedSha256: hash(source), resultSha256: hash(result), sameHistoricalOutcomes: true }));
  }
} finally { rmSync(work, { recursive: true, force: true }); }
