#!/usr/bin/env node
// Mutation controls for the listed clauses of the conviction predicate (draft
// #582, Lean `rotationValid` and `CheckpointConviction.accepts`), over the flat
// decoded domain the rival tests exercise. The list is not an exhaustive
// decomposition of the predicate: a clause with no entry is not claimed.
//
//   nix shell github:NixOS/nixpkgs/<pin>#aiken github:NixOS/nixpkgs/<pin>#nodejs \
//     github:NixOS/nixpkgs/<pin>#util-linux --command node scripts/check-rival-mutants.mjs [predicate|evidence]
//
// `predicate` (the default) edits checkpoint/rival.ak, the flat decoded
// predicate; `evidence` edits checkpoint/rival_evidence.ak, the signed-byte
// opening over real keripy events. Both run every rival test.
//
// Each mutant is a copy of `onchain/` with exactly one listed edit applied to
// `checkpoint/rival.ak` (a clause removed or weakened), and the rival tests are
// run over it. A mutant is KILLED when the copy still compiles and a test fails; it
// SURVIVES when every test passes; a copy that does not compile proves nothing
// and is an error. The harness is controlled: the unmutated copy must pass, an
// edit that changes no behaviour must survive, and every edit must change one
// place (its text must occur exactly once).
//
// Excluded as equivalent, with the reason: `toad <= |witnesses|` (the receipted
// witnesses are a subset of the witnesses, so the receipted bound implies it)
// and `clauses` nonempty in the weighted rule (an empty clause list has width
// zero, which the partition check against the nonempty key list refuses).
// Equivalent since the corrected rule (#595, #596, #598) and no longer listed: the
// nonempty checks of the previous commitments and of the rival keys (a count of
// zero is never satisfied and a weighted rule must partition the keys), and the
// repeated-addition guard of the witness derivation (an addition of a present
// witness is refused before the derivation).
// Also equivalent since #595: the positive-denominator check of the declared next
// rule (a zero denominator makes the clause total's denominator zero, so the rule
// does not fit its next keys; the model keeps both checks, the flat domain needs one).
//
// The compiler prints no diagnostics without a terminal, so the harness needs
// `script` (util-linux) to name the failed tests, and stops without it rather
// than degrade. Every run must also select exactly the tests written in
// rival_tests.ak, rival_vectors.ak and rival_evidence_tests.ak; a different count is an error.
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { availableParallelism, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const onchain = join(root, 'onchain');
const SET = process.argv[2] ?? 'predicate';
if (!['predicate', 'evidence'].includes(SET)) { console.error('set is predicate or evidence'); process.exit(2); }
const RIVAL = SET === 'evidence' ? 'lib/cardano_keri/checkpoint/rival_evidence.ak' : 'lib/cardano_keri/checkpoint/rival.ak';

const drop = (line) => ({ from: `${line}\n`, to: '' });
const predicateMutants = [
  { name: 'rotation-kind', clause: 'kind = rotation', ...drop('    rival.is_rotation,') },
  { name: 'structure-verified', clause: 'structureVerified', ...drop('    rival.structure_ok,') },
  { name: 'previous-weights-at-most-one', clause: 'prior.nextThreshold.weightsAtMostOne', ...drop('    weights_at_most_one(previous.next_threshold),') },
  { name: 'rival-weights-at-most-one', clause: 'event.threshold.weightsAtMostOne', ...drop('    weights_at_most_one(rival.threshold),') },
  { name: 'rival-next-weights-at-most-one', clause: 'event.nextThreshold.weightsAtMostOne', ...drop('    weights_at_most_one(rival.next_threshold),') },
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
  { name: 'cuts-removed', clause: 'derivedWitnesses cuts', from: 'fn(w) { !list.has(rival.cuts, w) }', to: 'fn(_) { True }' },
  { name: 'adds-appended', clause: 'derivedWitnesses adds', from: 'list.concat(witnesses, [add])', to: 'witnesses' },
  { name: 'receipts-from-derived-witnesses', clause: 'witnesses.filter receipts', from: 'list.filter(witnesses, fn(w) { list.has(rival.receipts, w) })', to: 'list.filter(previous.witnesses, fn(w) { list.has(rival.receipts, w) })' },
  { name: 'previous-quorum-from-signers-not-revealed-keys', clause: 'signers.filter exposed.contains', from: 'list.filter(rival.keys, fn(key) { list.has(rival.signers, key) }),\n        next_key_digest,', to: 'rival.keys,\n        next_key_digest,' },
  { name: 'previous-threshold-met', clause: 'prior.nextThreshold.satisfied', from: '      satisfied(\n        previous.next_threshold,', to: '      satisfied(\n        Unweighted(0),' },
  { name: 'own-threshold-met', clause: 'event.threshold.satisfied', from: '    satisfied(\n      rival.threshold,', to: '    satisfied(\n      Unweighted(0),' },
  { name: 'count-is-natural-and-bounded', clause: 'count n: n <= keys.length', from: 'm >= 1 && m <= key_count && evaluate(threshold, key_count, signed)', to: 'evaluate(threshold, key_count, signed)' },
  { name: 'count-evaluates-signers', clause: 'a count is met by that many distinct signing positions', from: 'm >= 1 && m <= key_count && evaluate(threshold, key_count, signed)', to: 'm >= 1 && m <= key_count' },
  { name: 'zero-count-never-satisfied', clause: 'count 0 is never satisfied (#596)', from: 'm >= 1 && m <= key_count && evaluate(threshold, key_count, signed)', to: 'm >= 0 && m <= key_count && evaluate(threshold, key_count, signed)' },
  { name: 'next-rule-fits-checked', clause: 'fitsNextKeys (#595)', ...drop('    fits_next_keys(rival.next_threshold, rival.next_key_count),') },
  { name: 'next-count-fits-keys', clause: 'fitsNextKeys count width (#595)', from: 'Unweighted(m) -> m >= 0 && m <= key_count', to: 'Unweighted(m) -> m >= 0' },
  { name: 'next-weighted-width-fits-keys', clause: 'fitsNextKeys weighted width (#595)', from: ' <= key_count && !list.is_empty(', to: ' >= 0 && !list.is_empty(' },
  { name: 'next-weighted-clauses-total-one', clause: 'fitsNextKeys clause totals (#595)', from: ') && list.all(clauses, clause_total_at_least_one)', to: ') && True' },
  { name: 'cuts-are-members', clause: 'cuts are prior witnesses (#598)', ...drop('    list.all(rival.cuts, fn(w) { list.has(previous.witnesses, w) }),') },
  { name: 'adds-are-new', clause: 'adds are not prior witnesses (#598)', ...drop('    list.all(rival.adds, fn(w) { !list.has(previous.witnesses, w) }),') },
  { name: 'nonempty-set-needs-threshold', clause: 'nonempty resulting set has positive receipt threshold (#598)', ...drop('    list.is_empty(witnesses) || rival.toad > 0,') },
  { name: 'weighted-clauses-partition-keys', clause: 'clauseWidth sum == keys.length', from: ') == key_count && evaluate(threshold, key_count, signed)', to: ') >= 0 && evaluate(threshold, key_count, signed)' },
  { name: 'weighted-denominators-positive', clause: 'Weight.wellFormed', from: '!list.is_empty(clause) && list.all(clause, fn(w) { w.den > 0 })', to: '!list.is_empty(clause)' },
  { name: 'weight-ceiling', clause: 'weightsAtMostOne', from: 'list.all(clause, fn(w) { w.num <= w.den })', to: 'list.all(clause, fn(_) { True })' },
  { name: 'never-rotated-refused', clause: 'previous = none', from: '    None -> False', to: '    None -> True' },
  { name: 'rotated-epoch', clause: 'epoch != 0', ...drop('        tip.epoch != 0,') },
  { name: 'tip-identifier', clause: 'tip.aid = rival.aid', ...drop('        tip.aid == rival.aid,') },
  { name: 'tip-position', clause: 'tip.sn = rival.sn', ...drop('        tip.sn == rival.sn,') },
  { name: 'digest-differs', clause: 'writer eventDigest != rival eventDigest', ...drop('        tip.writer_digest != rival.event_digest,') },
  { name: 'rival-valid-against-previous', clause: 'rotationValid previous rival', from: '        rotation_valid(previous, rival),\n      }', to: '        True,\n      }' },
];

const evidenceMutants = [
  { name: 'hash-limit', clause: 'bytes over 1024 are not hashed', from: 'size > hash_limit || ', to: '' },
  { name: 'prior-qualified', clause: 'p is a qualified digest', from: 'aid_digest(claim.prior) != None,', to: 'True,' },
  { name: 'structure-prefix', clause: 'every claimed value sits in its canonical top-level field', from: 'bytearray.take(dress(event_bytes, d_off), prefix) == expected,', to: 'True,' },
  { name: 'anchors-open', clause: 'the anchors are a list', from: 'bytearray.at(event_bytes, prefix) == 91,', to: 'True,' },
  { name: 'anchors-close', clause: 'the anchors close the event', from: 'bytearray.drop(event_bytes, size - 2) == "]}",', to: 'True,' },
  { name: 'structure-checked-at-the-opener', clause: 'the structure is established where the digest is opened', from: 'if canonical_structure(claim, event_bytes) {', to: 'if True {' },
  { name: 'said-dressing', clause: 'the d value is dressed before hashing', from: '|> bytearray.concat(dummy_span)', to: '|> bytearray.concat("")' },
  { name: 'declared-digest-refused', clause: 'the carried d is the recomputed digest', from: 'if slice_matches(event_bytes, d_off, qb64_aid(digest)) {', to: 'if True {' },
  { name: 'signatures-verified', clause: 'controller signatures verified over the bytes', from: 'verified_indices(claim.cur_keys, event_bytes, ctrl_sigs)', to: 'list.range(0, list.length(claim.cur_keys) - 1)' },
  { name: 'receipts-verified', clause: 'witness receipts verified over the bytes', from: 'verified_indices(witnesses, event_bytes, wit_receipts)', to: 'list.range(0, list.length(witnesses) - 1)' },
  { name: 'receipts-against-derived-witnesses', clause: 'receipts index the derived witness set', from: 'let witnesses = derived_witnesses(previous, skeleton)', to: 'let witnesses = previous.witnesses' },
  { name: 'own-digest-carried', clause: 'the rival carries its own digest', from: 'event_digest: digest,', to: 'event_digest: claim.aid,' },
];
const mutants = SET === 'evidence' ? evidenceMutants : predicateMutants;

const survivorControl = SET === 'evidence'
  ? { name: 'comment-only-edit', from: 'pub fn open_digest(', to: '// an edit that changes no behaviour\npub fn open_digest(' }
  : { name: 'comment-only-edit', from: 'pub fn derived_witnesses(', to: '// an edit that changes no behaviour\npub fn derived_witnesses(' };

const WORKERS = Math.max(1, Number(process.env.RIVAL_MUTANT_WORKERS ?? Math.min(4, availableParallelism())));
if (spawnSync('script', ['--version'], { encoding: 'utf8' }).status !== 0) {
  console.error('script (util-linux) is required: without a terminal the pinned compiler names no failed test');
  process.exit(2);
}
const countTests = (file) => (readFileSync(join(onchain, file), 'utf8').match(/^test /gm) ?? []).length;
const expectedChecks = ['rival_tests', 'rival_vectors', 'rival_evidence_tests'].map((m) => countTests(`lib/cardano_keri/checkpoint/${m}.ak`)).reduce((a, b) => a + b, 0);

const aiken = (cwd, filter) => new Promise((done) => {
  const child = spawn('script', ['-qec', `aiken check -m '${filter}'`, '/dev/null'], { cwd });
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
    if (Number(tests.checks) !== expectedChecks) return { error: `selected ${tests.checks} tests, expected ${expectedChecks}` };
    if (tests.status !== 0 && tests.failed.length === 0) return { error: 'the run failed and names no failed test' };
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
console.log(`${jobs.length - 2} listed edits over ${expectedChecks} selected tests, ${bad} not killed or broken`);
process.exit(bad === 0 ? 0 : 1);
