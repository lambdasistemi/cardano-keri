#!/usr/bin/env node
// One mutation control per check of the bounded top-up, of the registration
// premium and of the mark's life through a rotation and a freeze.
//
//   nix shell github:NixOS/nixpkgs/<pin>#aiken github:NixOS/nixpkgs/<pin>#nodejs \
//     --command node scripts/check-topup-mutants.mjs
//
// For each premise the Lean's `topUp` step names (the mark is clear, the amount
// is at least P) and for each further fact the validator checks (the successor
// datum, field by field, the successor value, the single checkpoint input and
// output, no mint or burn, the active address), and for the registration's
// first pool, the registration's mark, the rotation's cleared mark and the
// freeze's kept mark, a copy of `onchain/` has exactly that check removed or
// weakened and the top-up tests are run over it. A mutant is KILLED when the
// copy still compiles and a test fails; it SURVIVES when every test passes; a
// copy that does not compile proves nothing and is an error.
//
// The harness is itself controlled: the unmutated copy must pass, an edit that
// changes no behaviour (a comment) must survive, and every edit must change
// exactly one place in the source (it is rejected if its text is absent or
// occurs more than once).
//
// The packaged compiler prints no diagnostics without a terminal, so the runs
// go through `script`, which gives it one: a failed test is then a run that
// names failing tests, a copy that does not compile is a failing run that names
// none, and each kill is named. The runs go in parallel working copies
// (at most four, fewer on a machine with fewer cores; TOPUP_MUTANT_WORKERS overrides).
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { availableParallelism, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const onchain = join(root, 'onchain');

const REGISTER = 'validators/checkpoint_register.ak';

// The datum comparison of the arm, as it stands in the source.
const DATUM_EXACT = '  expect state_output.datum == InlineDatum(datum.write(marked))\n';

// The fields of a live datum the successor must copy from the spent one.
const copied = ['aid', 'sn', 'epoch', 'poisoned', 'frozen', 'born_at', 'refund_to', 'keys'];

// The successor datum with one field taken from the successor itself instead
// of from the spent datum: the check that the field is copied is removed for
// that field alone.
const fieldTakenFromSuccessor = (field) => {
  const order = ['aid', 'sn', 'epoch', 'poisoned', 'frozen', 'born_at', 'refund_to', 'topped_up', 'keys'];
  const rebuilt = order.map((f) => (f === field ? `${f}: successor_${f}` : f === 'topped_up' ? 'topped_up: True' : f)).join(', ');
  return `  expect InlineDatum(successor_data) = state_output.datum\n  expect Live { ${field}: successor_${field}, .. } = datum.read(successor_data)\n  expect successor_data == datum.write(Live { ${rebuilt} })\n`;
};

const VALUE_EXACT = '  state_output.value == (\n    from_lovelace(held) |> merge(from_asset(own_hash, aid_name, 1))\n  )\n}';

// The Lean's premises first, then the facts the validator also checks.
const mutants = [
  { name: 'fresh-only', premise: 'l.toppedUp = false', file: REGISTER, from: '        refund_to,\n        topped_up: False,\n        keys,\n      }\n    = old', to: '        refund_to,\n        topped_up: _,\n        keys,\n      }\n    = old' },
  { name: 'at-least-premium', premise: 'p.P <= x', file: REGISTER, from: '  expect premium <= amount\n', to: '  expect 0 <= amount\n' },
  { name: 'mark-set', premise: 'the successor sets toppedUp := true', file: REGISTER, from: '    topped_up: True,\n    keys,\n  }\n  expect [state_output]', to: '    topped_up: False,\n    keys,\n  }\n  expect [state_output]' },
  { name: 'successor-datum', premise: 'the successor is the spent state, marked', file: REGISTER, from: DATUM_EXACT, to: '' },
  ...copied.map((f) => ({
    name: f === 'born_at' ? 'juvenility-born-at' : `successor-keeps-${f.replace('_', '-')}`,
    premise: f === 'born_at' ? 'the successor keeps the birth time (a changed born_at resets the juvenility)' : `the successor keeps ${f}`,
    file: REGISTER,
    from: DATUM_EXACT,
    to: fieldTakenFromSuccessor(f),
  })),
  { name: 'successor-value-at-least', premise: 'the successor holds exactly the pool and the amount (not more)', file: REGISTER, from: VALUE_EXACT, to: '  lovelace_of(state_output.value) >= held && quantity_of(state_output.value, own_hash, aid_name) == 1\n}' },
  { name: 'successor-value-at-most', premise: 'the successor holds exactly the pool and the amount (not less)', file: REGISTER, from: VALUE_EXACT, to: '  lovelace_of(state_output.value) <= held && quantity_of(state_output.value, own_hash, aid_name) == 1\n}' },
  { name: 'successor-value-no-extra-asset', premise: 'the successor holds nothing but lovelace and the token', file: REGISTER, from: VALUE_EXACT, to: '  lovelace_of(state_output.value) == held && quantity_of(state_output.value, own_hash, aid_name) == 1\n}' },
  { name: 'successor-value-adds-the-amount', premise: 'the pool grows by the redeemer amount', file: REGISTER, from: '    marked,\n    pool + amount,\n  )', to: '    marked,\n    pool + premium,\n  )' },
  { name: 'mints-nothing', premise: 'a top-up mints and burns nothing', file: REGISTER, from: '  expect dict.to_pairs(tokens(mint, own_hash)) == []\n  expect\n    list.length(', to: '  expect\n    list.length(' },
  { name: 'one-checkpoint-input', premise: 'one checkpoint input', file: REGISTER, from: '  expect\n    list.length(\n      list.filter(\n        inputs,\n        fn(input) {\n          input.output.address.payment_credential == Script(own_hash)\n        },\n      ),\n    ) == 1\n  let marked', to: '  let marked' },
  { name: 'one-checkpoint-output', premise: 'one checkpoint successor', file: REGISTER, from: '  expect [state_output] = list.filter(\n    outputs,\n    fn(output) { output.address == from_script(own_hash) },\n  )\n  expect state_output.datum == InlineDatum(datum.write(marked))', to: '  expect [state_output, ..] = list.filter(\n    outputs,\n    fn(output) { output.address == from_script(own_hash) },\n  )\n  expect state_output.datum == InlineDatum(datum.write(marked))' },
  { name: 'active-address', premise: 'the spent output is at the active checkpoint address', file: REGISTER, from: '  expect Script(own_hash) = own_input.output.address.payment_credential\n  expect own_input.output.address == role.address(own_hash, Active)\n  expect InlineDatum(old_data) = own_input.output.datum\n  let old = datum.read(old_data)\n  expect  \n      Live {\n        aid,\n        sn,\n        epoch,\n        poisoned,\n        frozen,\n        born_at,\n        refund_to,\n        topped_up: False,', to: '  expect Script(own_hash) = own_input.output.address.payment_credential\n  expect InlineDatum(old_data) = own_input.output.datum\n  let old = datum.read(old_data)\n  expect  \n      Live {\n        aid,\n        sn,\n        epoch,\n        poisoned,\n        frozen,\n        born_at,\n        refund_to,\n        topped_up: False,' },
  { name: 'register-first-pool', premise: 'p.P <= pool0 (registration)', file: REGISTER, from: '  expect premium <= pool0\n', to: '  expect 0 <= pool0\n' },
  { name: 'register-mark-clear', premise: 'the registered state has toppedUp = false', file: REGISTER, from: '        refund_to,\n        topped_up: False,\n        ..\n      }\n    = datum.read(datum_data)', to: '        refund_to,\n        topped_up: _,\n        ..\n      }\n    = datum.read(datum_data)' },
  { name: 'rotation-clears-mark', premise: 'every rotation sets toppedUp := false', file: REGISTER, from: '        topped_up: False,\n        keys: new_keys,\n        ..', to: '        topped_up: _,\n        keys: new_keys,\n        ..' },
  { name: 'freeze-keeps-mark', premise: 'a freeze leaves toppedUp as it was', file: REGISTER, from: '    refund_to,\n    topped_up,\n    keys,\n  }\n  expect [state_output]', to: '    refund_to,\n    topped_up: False,\n    keys,\n  }\n  expect [state_output]' },
];

// Controls on the harness itself.
const survivorControl = { name: 'comment-only-edit', file: REGISTER, from: 'fn validate_top_up(', to: '// an edit that changes no behaviour\nfn validate_top_up(' };

const modules = ['checkpoint_register_topup_tests', 'checkpoint_register_topup_corpus_tests'];

// Each compiler run over the top-up modules takes a minute or more (the tests
// execute the spend arm and the observers over whole transactions), so the runs
// go in parallel, each in a working copy of its own: the controls and every
// mutant are independent.
const WORKERS = Math.max(1, Number(process.env.TOPUP_MUTANT_WORKERS ?? Math.min(4, availableParallelism())));

// With a terminal the compiler names the tests that fail, so a failed test (a
// name) is told from a copy that does not compile (no name) by the run itself;
// without one `script` is absent and a separate compile-only run tells them apart.
const haveScript = spawnSync('script', ['--version'], { encoding: 'utf8' }).status === 0;

const aiken = (cwd, filter) =>
  new Promise((done) => {
    const [command, args] = haveScript
      ? ['script', ['-qec', `aiken check -m '${filter}'`, '/dev/null']]
      : ['aiken', ['check', '-m', filter]];
    const child = spawn(command, args, { cwd });
    let out = '';
    child.stdout.on('data', (chunk) => { out += chunk; });
    child.on('close', (status) => {
      const text = out.replace(/\x1b\[[0-9;]*[A-Za-z]/g, '');
      done({ status, failing: [...text.matchAll(/FAIL \[[^\]]*\] (\S+)/g)].map((m) => m[1]) });
    });
  });

const compiles = async (cwd) => (await aiken(cwd, 'checkpoint_register_topup_tests.{no_such_test_selects_nothing}')).status === 0;

// The first module whose run fails ends the verdict; a failing run that names no
// test is a copy that does not compile, never a kill.
const topUpTests = async (cwd) => {
  for (const m of modules) {
    const run = await aiken(cwd, `${m}.{..}`);
    if (run.status === 0) continue;
    const built = haveScript ? run.failing.length > 0 : await compiles(cwd);
    return { ok: false, compiles: built, failing: run.failing };
  }
  return { ok: true, compiles: true, failing: [] };
};

// Working copies, one per worker: the dependencies compile in each, and each
// edit is undone before the next. They are removed at the end, whatever happens.
const dirs = Array.from({ length: Math.max(1, WORKERS) }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'topup-mutant-'));
  cpSync(onchain, dir, { recursive: true });
  return dir;
});
process.on('exit', () => dirs.forEach((dir) => rmSync(dir, { recursive: true, force: true })));

const occurrencesIn = (dir, edit) => readFileSync(join(dir, edit.file), 'utf8').split(edit.from).length - 1;

const withEdit = async (dir, edit, body) => {
  if (!edit) return body();
  const path = join(dir, edit.file);
  const text = readFileSync(path, 'utf8');
  const occurrences = text.split(edit.from).length - 1;
  if (occurrences !== 1) throw new Error(`${edit.name}: the edit's text occurs ${occurrences} times in ${edit.file}, expected exactly once`);
  const mutated = text.replace(edit.from, () => edit.to);
  if (mutated === text) throw new Error(`${edit.name}: the edit changed nothing`);
  writeFileSync(path, mutated);
  try {
    return await body();
  } finally {
    writeFileSync(path, text);
  }
};

// Every edit must apply exactly once before any compiler runs.
for (const edit of [survivorControl, ...mutants]) {
  const occurrences = occurrencesIn(dirs[0], edit);
  if (occurrences !== 1) throw new Error(`${edit.name}: the edit's text occurs ${occurrences} times in ${edit.file}, expected exactly once`);
}

// The tasks: the two controls, then every mutant.
const tasks = [
  { kind: 'control-unmutated', name: 'unmutated' },
  { kind: 'control-comment', name: survivorControl.name, edit: survivorControl },
  ...mutants.map((mutant) => ({ kind: 'mutant', name: mutant.name, edit: mutant })),
];
const results = new Array(tasks.length);
let next = 0;
await Promise.all(
  dirs.map(async (dir) => {
    for (;;) {
      const index = next++;
      if (index >= tasks.length) return;
      const task = tasks[index];
      results[index] = await withEdit(dir, task.edit, () => topUpTests(dir));
    }
  }),
);

const failures = [];
const rows = [];

// Control 1: the unmutated copy compiles and the top-up tests pass.
if (!results[0].compiles) throw new Error('control: the unmutated copy does not compile');
if (!results[0].ok) throw new Error('control: the top-up tests fail on the unmutated copy');
rows.push(['unmutated', 'passes']);

// Control 2: an edit that changes no behaviour survives.
if (!results[1].compiles) throw new Error('control: the comment-only copy does not compile');
if (!results[1].ok) throw new Error('control: a comment-only edit made a top-up test fail; the harness cannot tell a kill from a break');
rows.push([survivorControl.name, 'survives, as it must']);

mutants.forEach((mutant, i) => {
  const run = results[2 + i];
  const verdict = !run.compiles ? 'DOES NOT COMPILE' : run.ok ? 'SURVIVED' : 'killed';
  const by = run.failing.length === 0 ? '' : `  by ${run.failing.length} test(s), first: ${run.failing[0]}`;
  rows.push([mutant.name, `${verdict}${by}  (${mutant.premise})`]);
  if (verdict !== 'killed') failures.push(`${mutant.name}: ${verdict}`);
  else if (haveScript && run.failing.length === 0) failures.push(`${mutant.name}: killed, but no failing test could be named`);
});

const width = Math.max(...rows.map(([n]) => n.length));
for (const [name, verdict] of rows) console.log(`${name.padEnd(width)}  ${verdict}`);
if (failures.length > 0) {
  console.error(`\n${failures.length} of ${mutants.length} mutants were not killed:\n  ${failures.join('\n  ')}`);
  process.exit(1);
}
console.log(`\nall ${mutants.length} mutants killed; controls behave (the unmutated copy passes, a comment-only edit survives)`);
