#!/usr/bin/env node
// One mutation control per premise of the deposit option of Advance.
//
//   nix shell github:NixOS/nixpkgs/<pin>#aiken github:NixOS/nixpkgs/<pin>#nodejs \
//     --command node scripts/check-deposit-mutants.mjs
//
// For each premise the Lean's deposit rotation names (the keys of the rotation
// signed the intent, the successor is unfrozen, the premium is paid exactly when
// the pool covers it, the frame is kept, nothing is minted, the rotation is
// witnessed and later) and for each fact the validator reads into the intent
// (the network, the policy, the spent output, the identifier, the sequence
// number, the epoch, the amount), a copy of `onchain/` has exactly that check
// changed and the tests named for it are run over it. A mutant is KILLED when
// the copy still compiles and one of its named tests fails; it SURVIVES when all
// of them pass; a copy that does not compile proves nothing and is an error.
//
// The named tests are the point of the table: the refusal tests (`fail` tests)
// pass when the validator refuses, so they say nothing until a mutant makes the
// validator accept; and an accepted deposit says nothing about a fact the intent
// binds until the fact is wrong. Running only the named tests keeps the control
// inside the time a hosted step may take; the whole deposit suite runs in the
// `aiken check` step.
//
// The harness is itself controlled: every named test must exist in its module
// (a filter that selects nothing exits 0 and would prove nothing), the unmutated
// copy must pass every named test, an edit that changes no behaviour (a comment)
// must survive, and every edit must change exactly one place in the source (it is
// rejected if its text is absent or occurs more than once).
//
// Two single edits are equivalent mutants and are not asserted: removing the
// deduplication of positions in only one of the two places that perform it (the
// verified positions and the threshold), and removing the range filter of the
// threshold (a position outside the key list has no key and never verifies). The
// two-place edit is asserted.
//
// Only exit codes are read: the packaged compiler prints no diagnostics without
// a terminal, so a compile error and a failed test are told apart by running the
// same copy once with a filter that selects no test (compile only) and once with
// the named tests.
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const onchain = join(root, 'onchain');

const REGISTER = 'validators/checkpoint_register.ak';
const OBSERVER = 'lib/cardano_keri/checkpoint/observer.ak';
const DEPOSIT = 'lib/cardano_keri/checkpoint/deposit.ak';
const ADVANCE = 'lib/cardano_keri/checkpoint/advance.ak';
const THRESHOLD = 'lib/cardano_keri/checkpoint/threshold.ak';

const CONNECTED = 'checkpoint_register_deposit_tests';
const VECTORS = 'checkpoint_register_deposit_vector_tests';

const t = (module, ...names) => names.map((name) => ({ module, name }));

const accepts = t(CONNECTED, 'deposit_restores_the_bond_of_a_frozen_checkpoint');
const acceptsUnfrozen = t(CONNECTED, 'deposit_on_an_unfrozen_checkpoint_names_zero_and_is_accepted');

const mutants = [
  {
    name: 'keep-preserves-the-frozen-flag',
    premise: 'the keep option leaves the frozen flag as it was',
    edits: [{ file: REGISTER, from: 'Keep -> new_frozen == frozen', to: 'Keep -> True' }],
    killers: t(CONNECTED, 'keep_of_a_frozen_checkpoint_cannot_unfreeze_it', 'keep_of_an_unfrozen_checkpoint_cannot_freeze_it'),
  },
  {
    name: 'deposit-unfreezes',
    premise: 'the successor of a deposit is not frozen',
    edits: [{ file: REGISTER, from: '!new_frozen && deposit_authorized(', to: 'deposit_authorized(' }],
    killers: t(CONNECTED, 'deposit_that_leaves_the_checkpoint_frozen_is_refused'),
  },
  {
    name: 'deposit-is-authorized',
    premise: 'the new keys signed the deposit intent',
    edits: [{ file: REGISTER, from: '!new_frozen && deposit_authorized(', to: '!new_frozen && True || deposit_authorized(' }],
    killers: t(CONNECTED, 'deposit_without_signatures_is_refused', 'deposit_naming_zero_on_a_frozen_checkpoint_is_refused'),
  },
  {
    name: 'intent-network',
    premise: 'the intent names the network the validator is applied to',
    edits: [{ file: REGISTER, from: 'required_intent(\n            network_id,', to: 'required_intent(\n            0,' }],
    killers: [...accepts, ...t(CONNECTED, 'deposit_signed_for_another_network_is_refused')],
  },
  {
    name: 'intent-policy',
    premise: 'the intent names the checkpoint policy',
    edits: [{ file: REGISTER, from: '            own_hash,\n            own_ref,\n            aid,', to: '            #"00",\n            own_ref,\n            aid,' }],
    killers: accepts,
  },
  {
    name: 'intent-spent-transaction',
    premise: 'the intent names the transaction of the spent output',
    edits: [{ file: REGISTER, from: '            own_ref,\n            aid,\n            new_sn,', to: '            OutputReference {\n              transaction_id: #"00",\n              output_index: own_ref.output_index,\n            },\n            aid,\n            new_sn,' }],
    killers: accepts,
  },
  {
    name: 'intent-spent-index',
    premise: 'the intent names the index of the spent output',
    edits: [{ file: REGISTER, from: '            own_ref,\n            aid,\n            new_sn,', to: '            OutputReference {\n              transaction_id: own_ref.transaction_id,\n              output_index: 0,\n            },\n            aid,\n            new_sn,' }],
    killers: t(VECTORS, 'requirement_frozen_required'),
  },
  {
    name: 'intent-identifier',
    premise: 'the intent names the identifier',
    edits: [{ file: REGISTER, from: '            aid,\n            new_sn,', to: '            #"00",\n            new_sn,' }],
    killers: accepts,
  },
  {
    name: 'intent-sequence-number',
    premise: 'the intent names the new sequence number',
    edits: [{ file: REGISTER, from: '            new_sn,\n            new_epoch,', to: '            0,\n            new_epoch,' }],
    killers: accepts,
  },
  {
    name: 'intent-epoch',
    premise: 'the intent names the epoch the rotation opens',
    edits: [{ file: REGISTER, from: '            new_epoch,\n            if frozen {', to: '            0,\n            if frozen {' }],
    killers: accepts,
  },
  {
    name: 'intent-amount-is-always-the-bond',
    premise: 'the intent names B - bHeld: nothing when the spent state is not frozen',
    edits: [{ file: REGISTER, from: 'if frozen {\n              freeze_bond\n            } else {\n              0\n            },', to: 'freeze_bond,' }],
    killers: [...acceptsUnfrozen, ...t(CONNECTED, 'deposit_naming_the_bond_on_an_unfrozen_checkpoint_is_refused')],
  },
  {
    name: 'intent-amount-is-always-zero',
    premise: 'the intent names B - bHeld: the bond when the spent state is frozen',
    edits: [{ file: REGISTER, from: 'if frozen {\n              freeze_bond\n            } else {\n              0\n            },', to: '0,' }],
    killers: [...accepts, ...t(CONNECTED, 'deposit_naming_zero_on_a_frozen_checkpoint_is_refused')],
  },
  {
    name: 'signers-are-the-new-keys',
    premise: 'the signers are the current keys of the rotation, not those of the spent state',
    edits: [
      { file: REGISTER, from: 'expect Live { aid, frozen, born_at, refund_to, .. } = old', to: 'expect Live { aid, frozen, born_at, refund_to, keys: old_keys, .. } = old' },
      { file: REGISTER, from: '          new_keys.cur_keys,\n', to: '          old_keys.cur_keys,\n' },
    ],
    killers: [...accepts, ...t(CONNECTED, 'deposit_signed_by_the_keys_of_the_spent_state_is_refused')],
  },
  {
    name: 'signers-meet-the-threshold',
    premise: 'the distinct verified positions satisfy the rotation\'s threshold',
    edits: [
      { file: REGISTER, from: 'use cardano_keri/checkpoint/deposit.{deposit_authorized, required_intent}', to: 'use cardano_keri/checkpoint/deposit.{deposit_authorized, required_intent}\nuse cardano_keri/checkpoint/threshold.{Unweighted}' },
      { file: REGISTER, from: '          new_keys.cur_threshold,\n', to: '          Unweighted(1),\n' },
    ],
    killers: t(CONNECTED, 'deposit_signed_by_one_of_two_new_keys_is_refused'),
  },
  {
    name: 'signatures-are-verified',
    premise: 'a signature that does not verify never counts',
    edits: [{ file: ADVANCE, from: 'if verify_ed25519_signature(k, msg, sig) {', to: 'if True {' }],
    killers: t(CONNECTED, 'deposit_with_a_damaged_signature_is_refused'),
  },
  {
    name: 'repeated-position-counts-once',
    premise: 'a repeated position counts once (the two places that deduplicate)',
    edits: [
      { file: ADVANCE, from: '  list.unique(\n    list.filter_map(\n      sigs,', to: '  list.reverse(\n    list.filter_map(\n      sigs,' },
      { file: THRESHOLD, from: 'let valid = list.filter(list.unique(signers), fn(p) { p >= 0 && p < n })', to: 'let valid = list.filter(signers, fn(p) { p >= 0 && p < n })' },
    ],
    killers: t(CONNECTED, 'deposit_counting_one_position_twice_is_refused'),
  },
  {
    name: 'domain-tag',
    premise: 'the intent carries the frozen domain tag',
    edits: [{ file: DEPOSIT, from: '"cardano-keri/checkpoint/deposit/v1"', to: '"cardano-keri/checkpoint/deposit/v2"' }],
    killers: [...accepts, ...t(VECTORS, 'requirement_frozen_required_required_is_the_lean_bytes')],
  },
  {
    name: 'field-order',
    premise: 'the intent is the Lean record, field by field',
    edits: [
      { file: DEPOSIT, from: '  new_sn: Int,\n  new_epoch: Int,\n  deposit: Int,\n}', to: '  new_epoch: Int,\n  new_sn: Int,\n  deposit: Int,\n}' },
      { file: DEPOSIT, from: '    new_sn,\n    new_epoch,\n    deposit,\n  }', to: '    new_epoch: new_epoch,\n    new_sn: new_sn,\n    deposit,\n  }' },
    ],
    killers: t(VECTORS, 'intent_frozen_is_the_lean_bytes', 'intent_large_numbers_is_the_lean_bytes'),
  },
  {
    name: 'successor-holds-the-bond',
    premise: 'the successor holds the minimum ADA, the deposit, the bond and the pool',
    edits: [{ file: REGISTER, from: 'held_value(checkpoint_min_ada, d_reg, freeze_bond, new, pool_after)', to: 'held_value(checkpoint_min_ada, d_reg, freeze_bond, old, pool_after)' }],
    killers: [...accepts, ...t(CONNECTED, 'deposit_unfrozen_without_the_bond_in_its_value_is_refused')],
  },
  {
    name: 'premium-reduces-the-pool',
    premise: 'the pool is reduced by the premium when it covers it',
    edits: [{ file: REGISTER, from: '    pool - premium\n  } else {', to: '    pool\n  } else {' }],
    killers: t(CONNECTED, 'deposit_restores_the_bond_and_pays_the_premium_when_the_pool_covers_it', 'deposit_that_does_not_reduce_the_pool_by_the_premium_is_refused'),
  },
  {
    name: 'premium-is-paid',
    premise: 'the payee receives at least the premium',
    edits: [{ file: REGISTER, from: ') >= premium\n  } else {', to: ') >= 0\n  } else {' }],
    killers: t(CONNECTED, 'deposit_paying_the_premium_short_by_one_lovelace_is_refused'),
  },
  {
    name: 'premium-payee-holds-no-token',
    premise: 'the premium payee output holds no checkpoint token',
    edits: [{ file: REGISTER, from: 'quantity_of(payee.value, registry.policy, aid_name) == 0 && lovelace_of(', to: 'True && lovelace_of(' }],
    killers: t(CONNECTED, 'deposit_paying_the_premium_to_an_output_with_the_token_is_refused'),
  },
  {
    name: 'frame-refund-address',
    premise: 'the refund address is kept',
    edits: [{ file: REGISTER, from: '      new_refund_to == refund_to,\n', to: '      True,\n' }],
    killers: t(CONNECTED, 'deposit_that_changes_the_refund_address_is_refused'),
  },
  {
    name: 'frame-birth-slot',
    premise: 'the birth slot is kept',
    edits: [{ file: REGISTER, from: '      new_born_at == born_at,\n', to: '      True,\n' }],
    killers: t(CONNECTED, 'deposit_that_changes_the_birth_slot_is_refused'),
  },
  {
    name: 'frame-identifier',
    premise: 'the identifier is kept',
    edits: [{ file: OBSERVER, from: '  expect new_aid == aid\n', to: '' }],
    killers: t(CONNECTED, 'deposit_that_changes_the_identifier_is_refused'),
  },
  {
    name: 'mints-nothing',
    premise: 'a deposit mints and burns nothing under the checkpoint policy',
    edits: [{ file: REGISTER, from: '  expect quantity_of(mint, registry.policy, aid_name) == 0\n  expect Some(pool) = with_value(\n    checkpoint_min_ada,\n    d_reg,\n    freeze_bond,\n    old,\n    lovelace_of(own_input.output.value),\n  )\n  let paid', to: '  expect Some(pool) = with_value(\n    checkpoint_min_ada,\n    d_reg,\n    freeze_bond,\n    old,\n    lovelace_of(own_input.output.value),\n  )\n  let paid' }],
    killers: t(CONNECTED, 'deposit_that_mints_under_the_checkpoint_policy_is_refused'),
  },
  {
    name: 'rotation-evidence',
    premise: 'the rotation is witnessed and later (the unchanged advance predicate)',
    edits: [{ file: OBSERVER, from: 'advance_predicate(spent, new, evidence) == AdvancePredicateValid\n}', to: 'advance_predicate(spent, new, evidence) == AdvancePredicateValid || True\n}' }],
    killers: t(CONNECTED, 'deposit_with_a_rotation_signed_by_too_few_keys_is_refused', 'deposit_with_an_unevidenced_rotation_is_refused'),
  },
  {
    name: 'observation-names-the-spent-output',
    premise: 'the observation names the spent output',
    edits: [{ file: REGISTER, from: 'claim.action == action && claim.checkpoint_policy == checkpoint_policy && claim.own_ref == Some(\n                own_ref,\n              )\n            } else {', to: 'claim.action == action && claim.checkpoint_policy == checkpoint_policy\n            } else {' }],
    killers: t(CONNECTED, 'deposit_spend_arm_alone_accepts_the_honest_claim', 'deposit_claiming_another_output_for_the_observer_is_refused'),
  },
];

// Controls on the harness itself.
const survivorControl = {
  name: 'comment-only-edit',
  edits: [{ file: REGISTER, from: 'fn validate_advance(', to: '// an edit that changes no behaviour\nfn validate_advance(' }],
};

const aiken = (cwd, filters) => spawnSync('aiken', ['check', ...filters.flatMap((f) => ['-m', f])], { cwd, encoding: 'utf8' }).status;
const filterOf = ({ module, name }) => `${module}.{${name}}`;
const compiles = (cwd) => aiken(cwd, [`${CONNECTED}.{no_such_test_selects_nothing}`]) === 0;
const passes = (cwd, tests) => aiken(cwd, tests.map(filterOf)) === 0;

// One working copy for every run: the dependencies compile once, and each edit
// is undone before the next. The copy is removed at the end, whatever happens.
const dir = mkdtempSync(join(tmpdir(), 'deposit-mutant-'));
process.on('exit', () => rmSync(dir, { recursive: true, force: true }));
cpSync(onchain, dir, { recursive: true });

const withEdits = (edits, body) => {
  const saved = new Map();
  try {
    for (const edit of edits) {
      const path = join(dir, edit.file);
      const text = readFileSync(path, 'utf8');
      if (!saved.has(path)) saved.set(path, text);
      const occurrences = text.split(edit.from).length - 1;
      if (occurrences !== 1) throw new Error(`the edit's text occurs ${occurrences} times in ${edit.file}, expected exactly once: ${JSON.stringify(edit.from.slice(0, 60))}`);
      const mutated = text.replace(edit.from, () => edit.to);
      if (mutated === text) throw new Error(`the edit changed nothing in ${edit.file}`);
      writeFileSync(path, mutated);
    }
    return body();
  } finally {
    for (const [path, text] of saved) writeFileSync(path, text);
  }
};

// Control 0: every named test exists, once, as a test of its module.
const named = new Map();
for (const mutant of mutants) for (const test of mutant.killers) named.set(filterOf(test), test);
for (const { module, name } of named.values()) {
  const source = readFileSync(join(dir, 'validators', `${module}.ak`), 'utf8');
  const count = source.split(new RegExp(`^test ${name}\\(\\)`, 'm')).length - 1;
  if (count !== 1) throw new Error(`control: ${module} has ${count} tests named ${name}, expected exactly one`);
}

const failures = [];
const rows = [];

// Control 1: the unmutated copy compiles and passes every named test.
if (!compiles(dir)) throw new Error('control: the unmutated copy does not compile');
if (!passes(dir, [...named.values()])) throw new Error('control: a named test fails on the unmutated copy');
rows.push(['unmutated', `passes the ${named.size} named tests`]);

// Control 2: an edit that changes no behaviour survives.
withEdits(survivorControl.edits, () => {
  if (!compiles(dir)) throw new Error('control: the comment-only copy does not compile');
  if (!passes(dir, [...named.values()])) throw new Error('control: a comment-only edit made a named test fail; the harness cannot tell a kill from a break');
});
rows.push([survivorControl.name, 'survives, as it must']);

for (const mutant of mutants) {
  const verdict = withEdits(mutant.edits, () => {
    if (!compiles(dir)) return 'DOES NOT COMPILE';
    return passes(dir, mutant.killers) ? 'SURVIVED' : 'killed';
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
console.log(`\nall ${mutants.length} mutants killed; controls behave (every named test exists and passes on the unmutated copy, a comment-only edit survives)`);
