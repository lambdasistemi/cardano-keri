#!/usr/bin/env node
// One mutation control per premise of the one-step freeze.
//
//   nix shell github:NixOS/nixpkgs/<pin>#aiken github:NixOS/nixpkgs/<pin>#nodejs \
//     --command node scripts/check-freeze-mutants.mjs
//
// For each premise the Lean's `freeze` step names (a witnessed rotation, a later
// sequence number, a pool below the premium, not frozen, not poisoned) and for
// each further fact the validator checks (the successor datum, the successor
// value, the hunter's bond, the hunter output not being the successor, no mint),
// a copy of `onchain/` has exactly that check removed and the freeze tests are
// run over it. A mutant is KILLED when the copy still compiles and a freeze test
// fails; it SURVIVES when every test passes; a copy that does not compile proves
// nothing and is an error.
//
// The harness is itself controlled: the unmutated copy must pass, an edit that
// changes no behaviour (a comment) must survive, and every edit must change
// exactly one place in the source (it is rejected if its text is absent or
// occurs more than once).
//
// Only exit codes are read: the packaged compiler prints no diagnostics
// without a terminal, so a compile error and a failed test are told apart by
// running the same copy once with a filter that selects no test (compile
// only) and once with the freeze tests.
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const onchain = join(root, 'onchain');

const REGISTER = 'validators/checkpoint_register.ak';
const OBSERVER = 'lib/cardano_keri/checkpoint/observer.ak';
const MESSAGE = 'lib/cardano_keri/checkpoint/message.ak';

// The Lean's premises first, then the facts the validator also checks.
const mutants = [
  { name: 'rotation-evidence', premise: 'rotationTo: the rotation is witnessed', file: OBSERVER, from: 'advance_predicate(spent, new, evidence.rotation) == AdvancePredicateValid\n}', to: 'advance_predicate(spent, new, evidence.rotation) == AdvancePredicateValid || True\n}' },
  { name: 'later-sequence-number', premise: "l.sn < sn'", file: MESSAGE, from: 'new.native_sn > spent.native_sn', to: 'new.native_sn >= spent.native_sn' },
  { name: 'short-pool', premise: 'l.pool < P', file: REGISTER, from: '  expect pool < premium\n', to: '  expect pool >= 0\n' },
  { name: 'unfrozen', premise: 'l.frozen = false', file: REGISTER, from: '        poisoned: False,\n        frozen: False,\n        born_at,\n        refund_to,\n        keys,\n      }\n    = old', to: '        poisoned: False,\n        frozen: _,\n        born_at,\n        refund_to,\n        keys,\n      }\n    = old' },
  { name: 'unpoisoned', premise: 'l.poisoned = false', file: REGISTER, from: '        poisoned: False,\n        frozen: False,\n        born_at,\n        refund_to,\n        keys,\n      }\n    = old', to: '        poisoned: _,\n        frozen: False,\n        born_at,\n        refund_to,\n        keys,\n      }\n    = old' },
  { name: 'successor-datum', premise: 'the successor is the same live state frozen', file: REGISTER, from: '  expect state_output.datum == InlineDatum(datum.write(frozen))\n', to: '' },
  { name: 'successor-value', premise: 'the successor holds Mc + D + pool', file: REGISTER, from: 'held_value(checkpoint_min_ada, d_reg, freeze_bond, frozen, pool)', to: 'held_value(checkpoint_min_ada, d_reg, freeze_bond, old, pool)' },
  { name: 'hunter-bond', premise: 'the hunter receives B', file: REGISTER, from: '  ) >= freeze_bond\n}\n\n/// Convict', to: '  ) >= 0\n}\n\n/// Convict' },
  { name: 'hunter-is-not-the-successor', premise: 'the hunter output holds no token', file: REGISTER, from: 'quantity_of(hunter.value, own_hash, aid_name) == 0 && lovelace_of(', to: 'True && lovelace_of(' },
  { name: 'binding-action-tag', premise: 'the observation is tagged as a freeze', file: REGISTER, from: 'claim.action == action && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(\n                own_ref,\n              )\n            } else {', to: 'claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(\n                own_ref,\n              )\n            } else {' },
  { name: 'binding-policy', premise: 'the observation names this checkpoint policy', file: REGISTER, from: 'claim.action == action && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(\n                own_ref,\n              )\n            } else {', to: 'claim.action == action && claim.own_ref == Some(\n                own_ref,\n              )\n            } else {' },
  { name: 'binding-spent-output', premise: 'the observation names the spent output', file: REGISTER, from: 'claim.action == action && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(\n                own_ref,\n              )\n            } else {', to: 'claim.action == action && claim.checkpoint_policy == checkpoint_policy\n            } else {' },
  { name: 'binding-zero-withdrawal', premise: 'the observer ran as a zero-lovelace withdrawal', file: REGISTER, from: 'let credential: Credential = Script(advance_hash)\n  expect\n    list.any(\n      tx.withdrawals,\n      fn(Pair(withdrawal_credential, lovelace)) {\n        withdrawal_credential == credential && lovelace == 0', to: 'let credential: Credential = Script(advance_hash)\n  expect\n    list.any(\n      tx.withdrawals,\n      fn(Pair(withdrawal_credential, lovelace)) {\n        withdrawal_credential == credential' },
  { name: 'mints-nothing', premise: 'a freeze mints and burns nothing', file: REGISTER, from: '  expect dict.to_pairs(tokens(mint, own_hash)) == []\n  let frozen = Live {', to: '  let frozen = Live {' },
];

// Controls on the harness itself.
const survivorControl = { name: 'comment-only-edit', file: REGISTER, from: 'fn validate_freeze(', to: '// an edit that changes no behaviour\nfn validate_freeze(' };

const modules = ['checkpoint_register_freeze_tests', 'checkpoint_register_freeze_corpus_tests'];

const aiken = (cwd, filter) => spawnSync('aiken', ['check', '-m', filter], { cwd, encoding: 'utf8' }).status;

const compiles = (cwd) => aiken(cwd, 'checkpoint_register_freeze_tests.{no_such_test_selects_nothing}') === 0;
const freezeTestsPass = (cwd) => modules.every((m) => aiken(cwd, `${m}.{..}`) === 0);

// One working copy for every run: the dependencies compile once, and each edit
// is undone before the next. The copy is removed at the end, whatever happens.
const dir = mkdtempSync(join(tmpdir(), 'freeze-mutant-'));
process.on('exit', () => rmSync(dir, { recursive: true, force: true }));
cpSync(onchain, dir, { recursive: true });

const withEdit = (edit, body) => {
  if (!edit) return body();
  const path = join(dir, edit.file);
  const text = readFileSync(path, 'utf8');
  const occurrences = text.split(edit.from).length - 1;
  if (occurrences !== 1) throw new Error(`${edit.name}: the edit's text occurs ${occurrences} times in ${edit.file}, expected exactly once`);
  const mutated = text.replace(edit.from, () => edit.to);
  if (mutated === text) throw new Error(`${edit.name}: the edit changed nothing`);
  writeFileSync(path, mutated);
  try {
    return body();
  } finally {
    writeFileSync(path, text);
  }
};

const failures = [];
const rows = [];

// Control 1: the unmutated copy compiles and the freeze tests pass.
if (!compiles(dir)) throw new Error('control: the unmutated copy does not compile');
if (!freezeTestsPass(dir)) throw new Error('control: the freeze tests fail on the unmutated copy');
rows.push(['unmutated', 'passes']);

// Control 2: an edit that changes no behaviour survives.
withEdit(survivorControl, () => {
  if (!compiles(dir)) throw new Error('control: the comment-only copy does not compile');
  if (!freezeTestsPass(dir)) throw new Error('control: a comment-only edit made a freeze test fail; the harness cannot tell a kill from a break');
});
rows.push([survivorControl.name, 'survives, as it must']);

for (const mutant of mutants) {
  const verdict = withEdit(mutant, () => {
    if (!compiles(dir)) return 'DOES NOT COMPILE';
    return freezeTestsPass(dir) ? 'SURVIVED' : 'killed';
  });
  rows.push([mutant.name, `${verdict}  (${mutant.premise})`]);
  if (verdict !== 'killed') failures.push(`${mutant.name}: ${verdict}`);
}

const width = Math.max(...rows.map(([n]) => n.length));
for (const [name, verdict] of rows) console.log(`${name.padEnd(width)}  ${verdict}`);
if (failures.length > 0) {
  console.error(`\n${failures.length} of ${mutants.length} mutants were not killed:\n  ${failures.join('\n  ')}`);
  process.exit(1);
}
console.log(`\nall ${mutants.length} mutants killed; controls behave (the unmutated copy passes, a comment-only edit survives)`);
