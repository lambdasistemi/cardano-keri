#!/usr/bin/env node
// One mutation control per clause of the conviction predicate (draft #582,
// Lean `rotationValid` and `CheckpointConviction.accepts`).
//
//   nix shell github:NixOS/nixpkgs/<pin>#aiken github:NixOS/nixpkgs/<pin>#nodejs \
//     --command node scripts/check-rival-mutants.mjs
//
// Each mutant is a copy of `onchain/` with exactly one clause of
// `checkpoint/rival.ak` removed or weakened, and the rival tests are run over
// it. A mutant is KILLED when the copy still compiles and a test fails; it
// SURVIVES when every test passes; a copy that does not compile proves nothing
// and is an error. The harness is controlled: the unmutated copy must pass, an
// edit that changes no behaviour must survive, and every edit must change one
// place (its text must occur exactly once).
//
// Excluded as equivalent, with the reason: `toad <= |witnesses|` (the receipted
// witnesses are a subset of the witnesses, so the receipted bound implies it)
// and `clauses` nonempty in the weighted rule (an empty clause list has width
// zero, which the partition check against the nonempty key list refuses).
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { availableParallelism, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const onchain = join(root, 'onchain');
const RIVAL = 'lib/cardano_keri/checkpoint/rival.ak';

const drop = (line) => ({ from: `${line}\n`, to: '' });
const mutants = [
  { name: 'rotation-kind', clause: 'kind = rotation', ...drop('    rival.is_rotation,') },
  { name: 'structure-verified', clause: 'structureVerified', ...drop('    rival.structure_ok,') },
  { name: 'previous-weights-at-most-one', clause: 'prior.nextThreshold.weightsAtMostOne', ...drop('    weights_at_most_one(previous.next_threshold),') },
  { name: 'rival-weights-at-most-one', clause: 'event.threshold.weightsAtMostOne', ...drop('    weights_at_most_one(rival.threshold),') },
  { name: 'rival-next-weights-at-most-one', clause: 'event.nextThreshold.weightsAtMostOne', ...drop('    weights_at_most_one(rival.next_threshold),') },
  { name: 'rival-next-denominators', clause: 'nextThreshold.positiveDenominators', ...drop('    positive_denominators(rival.next_threshold),') },
  { name: 'same-identifier', clause: 'event.aid = prior.aid', ...drop('    rival.aid == previous.aid,') },
  { name: 'later-sequence', clause: 'prior.sn < event.sn', from: 'previous.sn < rival.sn', to: 'previous.sn <= rival.sn' },
  { name: 'receipts-checked', clause: 'receiptsValid', ...drop('    receipts_valid(previous, rival),') },
  { name: 'signing-checked', clause: 'signingValid', ...drop('    signing_valid(previous, rival),') },
  { name: 'receipt-threshold-met', clause: 'witnessThreshold <= receipted', ...drop('    rival.toad <= list.length(receipted),') },
  { name: 'receipt-threshold-natural', clause: 'witnessThreshold : Nat', ...drop('    rival.toad >= 0,') },
  { name: 'previous-witnesses-distinct', clause: 'distinct prior.witnesses', ...drop('    distinct(previous.witnesses),') },
  { name: 'cuts-distinct', clause: 'distinct event.cuts', ...drop('    distinct(rival.cuts),') },
  { name: 'adds-distinct', clause: 'distinct event.adds', ...drop('    distinct(rival.adds),') },
  { name: 'previous-commitments-distinct', clause: 'distinct prior.nextKeys', ...drop('    distinct(previous.next_keys),') },
  { name: 'rival-keys-distinct', clause: 'distinct event.keys', ...drop('    distinct(rival.keys),') },
  { name: 'previous-commitments-nonempty', clause: '!prior.nextKeys.isEmpty', ...drop('    !list.is_empty(previous.next_keys),') },
  { name: 'rival-keys-nonempty', clause: '!event.keys.isEmpty', ...drop('    !list.is_empty(rival.keys),') },
  { name: 'cuts-removed', clause: 'derivedWitnesses cuts', from: 'fn(w) { !list.has(rival.cuts, w) }', to: 'fn(_) { True }' },
  { name: 'adds-appended', clause: 'derivedWitnesses adds', from: 'list.concat(witnesses, [add])', to: 'witnesses' },
  { name: 'receipts-from-derived-witnesses', clause: 'witnesses.filter receipts', from: 'list.filter(witnesses, fn(w) { list.has(rival.receipts, w) })', to: 'list.filter(previous.witnesses, fn(w) { list.has(rival.receipts, w) })' },
  { name: 'previous-threshold-met', clause: 'prior.nextThreshold.satisfied', from: '      satisfied(\n        previous.next_threshold,', to: '      satisfied(\n        Unweighted(0),' },
  { name: 'own-threshold-met', clause: 'event.threshold.satisfied', from: '    satisfied(\n      rival.threshold,', to: '    satisfied(\n      Unweighted(0),' },
  { name: 'count-is-natural-and-bounded', clause: 'count n: n <= keys.length', from: 'm >= 0 && m <= key_count && evaluate(threshold, key_count, signed)', to: 'evaluate(threshold, key_count, signed)' },
  { name: 'weighted-clauses-partition-keys', clause: 'clauseWidth sum == keys.length', from: ') == key_count && evaluate(threshold, key_count, signed)', to: ') >= 0 && evaluate(threshold, key_count, signed)' },
  { name: 'weighted-denominators-positive', clause: 'Weight.wellFormed', from: '!list.is_empty(clause) && list.all(clause, fn(w) { w.den > 0 })', to: '!list.is_empty(clause)' },
  { name: 'weight-ceiling', clause: 'weightsAtMostOne', from: 'list.all(clause, fn(w) { w.num <= w.den })', to: 'list.all(clause, fn(_) { True })' },
  { name: 'declared-denominators', clause: 'positiveDenominators', from: 'list.all(clauses, fn(clause) { list.all(clause, fn(w) { w.den > 0 }) })', to: 'True' },
  { name: 'never-rotated-refused', clause: 'previous = none', from: '    None -> False', to: '    None -> True' },
  { name: 'rotated-epoch', clause: 'epoch != 0', ...drop('        tip.epoch != 0,') },
  { name: 'tip-identifier', clause: 'tip.aid = rival.aid', ...drop('        tip.aid == rival.aid,') },
  { name: 'tip-position', clause: 'tip.sn = rival.sn', ...drop('        tip.sn == rival.sn,') },
  { name: 'digest-differs', clause: 'writer eventDigest != rival eventDigest', ...drop('        tip.writer_digest != rival.event_digest,') },
  { name: 'rival-valid-against-previous', clause: 'rotationValid previous rival', from: '        rotation_valid(previous, rival),\n      }', to: '        True,\n      }' },
];

const survivorControl = { name: 'comment-only-edit', from: 'pub fn derived_witnesses(', to: '// an edit that changes no behaviour\npub fn derived_witnesses(' };

const WORKERS = Math.max(1, Number(process.env.RIVAL_MUTANT_WORKERS ?? Math.min(4, availableParallelism())));
const haveScript = spawnSync('script', ['--version'], { encoding: 'utf8' }).status === 0;

const aiken = (cwd, filter) => new Promise((done) => {
  const [command, args] = haveScript
    ? ['script', ['-qec', `aiken check -m '${filter}'`, '/dev/null']]
    : ['aiken', ['check', '-m', filter]];
  const child = spawn(command, args, { cwd });
  let out = '';
  child.stdout.on('data', (chunk) => { out += chunk; });
  child.on('close', (status) => {
    const text = out.replace(/\x1b\[[0-9;]*[A-Za-z]/g, '');
    done({ status, failed: [...text.matchAll(/FAIL \[[^\]]*\] (\S+)/g)].map((m) => m[1]), checks: /Summary (\d+) checks/.exec(text)?.[1] });
  });
});

const source = readFileSync(join(onchain, RIVAL), 'utf8');
const occurrences = (text, part) => text.split(part).length - 1;

async function run(edit) {
  if (edit.from !== undefined && occurrences(source, edit.from) !== 1) return { error: `edit text occurs ${occurrences(source, edit.from)} times` };
  const dir = mkdtempSync(join(tmpdir(), 'rival-mutant-'));
  try {
    const copy = join(dir, 'onchain');
    cpSync(onchain, copy, { recursive: true });
    if (edit.from !== undefined) writeFileSync(join(copy, RIVAL), source.replace(edit.from, () => edit.to));
    const compiled = await aiken(copy, 'checkpoint/__no_such_test__');
    if (compiled.status !== 0) return { error: 'does not compile' };
    const tests = await aiken(copy, 'checkpoint/rival');
    return { failed: tests.failed, checks: tests.checks, status: tests.status };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const jobs = [{ name: 'unmutated', control: 'pass', edit: {} }, { name: survivorControl.name, control: 'pass', edit: survivorControl }, ...mutants.map((m) => ({ name: m.name, clause: m.clause, edit: m }))];
const results = new Array(jobs.length);
let next = 0;
await Promise.all(Array.from({ length: WORKERS }, async () => {
  while (next < jobs.length) {
    const i = next++;
    results[i] = await run(jobs[i].edit);
  }
}));

let bad = 0;
jobs.forEach((job, i) => {
  const r = results[i];
  let verdict;
  if (r.error) verdict = `ERROR ${r.error}`;
  else if (job.control) verdict = r.status === 0 && r.failed.length === 0 ? 'PASSES (control ok)' : `FAILS (control broken: ${r.failed.join(', ')})`;
  else verdict = r.failed.length > 0 ? `KILLED by ${r.failed.length} (${r.failed[0]})` : (r.status === 0 ? 'SURVIVES' : 'ERROR no test failed but the run did');
  if (r.error || (job.control ? !verdict.startsWith('PASSES') : !verdict.startsWith('KILLED'))) bad++;
  console.log(`${job.name}${job.clause ? ` [${job.clause}]` : ''}: ${verdict}`);
});
console.log(`${jobs.length - 2} mutants, ${bad} not killed or broken`);
process.exit(bad === 0 ? 0 : 1);
