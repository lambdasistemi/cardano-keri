// Conformance artifact generator; consumes JSON emitted by the existing Lean driver.
// It never implements a transition: accepted state and flow come from Lean verbatim.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const source = JSON.parse(readFileSync(process.argv[2], 'utf8'));
assert.equal(source.schema, 'cardano-keri.checkpoint-trace');
assert.equal(source.version, 1);
const { grid, params } = source;
const actionName = a => typeof a === 'string' ? a : Object.keys(a)[0];
const has = (rows, wanted) => rows.some(row => JSON.stringify(row) === JSON.stringify(wanted));

function state(s) {
  if (typeof s === 'string') return { state: s };
  if (s.present) return { state: 'present', ...s.present.l };
  assert.ok(s.parked);
  return { state: 'parked', ...s.parked.h };
}

function action(a) {
  const name = actionName(a), p = a[name];
  switch (name) {
    case 'register': return { action: name, ...p };
    case 'rotate': return { action: name, sn: p["sn'"], bond: p.op, payee: p.payee, refund: p["refund'"] };
    case 'poison': return { action: name };
    case 'freeze': return { action: name, sn: p["sn'"], payee: p.payee };
    case 'topUp': return { action: name, amount: p.x };
    case 'convict': return { action: name, ...p };
    case 'close': return { action: name, sn: p["sn'"], payee: p.payee, refund: p["refund'"] };
    case 'reopen': return { action: name, sn: p["sn'"], refund: p.refund, pool0: p.pool0 };
    default: throw Error(`Unmapped action ${name}`);
  }
}

function failures(a, s, env) {
  const name = actionName(a), p = a[name], live = s.present?.l, parked = s.parked?.h;
  const matches = name === 'register' ? s === 'absent'
    : name === 'reopen' ? !!parked
    : name === 'convict' ? !!live || !!parked : !!live;
  if (!matches) return ['checkpoint-state-mismatch'];
  const failed = [];
  const guard = (holds, refusal) => { if (!holds) failed.push(refusal); };
  const key = live ?? parked;
  if (['rotate', 'freeze', 'close', 'reopen'].includes(name)) {
    guard(has(env.rotationTo, [key.epoch, key.sn, p["sn'"]]), 'rotation-evidence-invalid');
    guard(key.sn < p["sn'"], 'sequence-not-later');
  }
  if (name === 'rotate' || name === 'close') {
    const intent = name === 'rotate' ? p.op : { close: { payee: p.payee } };
    const empty = intent === 'keep' && p["refund'"] === null;
    guard(empty || has(env.intentAuthorized, [key.epoch + 1, intent, p["refund'"]]), 'intent-unauthorized');
  }
  if (name === 'poison') {
    guard(has(env.quorum, [key.epoch]), 'quorum-missing');
    guard(!live.poisoned, 'already-poisoned');
  }
  if (name === 'freeze') {
    guard(live.pool < params.P, 'freeze-pool-covers-premium');
    guard(!live.frozen, 'already-frozen');
    guard(!live.poisoned, 'freeze-poisoned');
  }
  if (name === 'convict') guard(has(env.duplicityAt, [key.epoch, key.sn]), 'duplicity-evidence-invalid');
  return failed.sort();
}

const coverage = new Map();
const cells = grid.cells.map(c => {
  const refused = failures(grid.actions[c.a], grid.states[c.s], grid.envs[c.e]);
  assert.equal(refused.length === 0, c.result !== null, `Lean refusal mismatch at ${JSON.stringify(c)}`);
  for (const name of refused) coverage.set(name, (coverage.get(name) ?? 0) + 1);
  return { s: c.s, a: c.a, e: c.e, result: c.result === null
    ? { status: 'refused', refusals: refused }
    : { status: 'accepted', flow: c.result.flow, state: state(c.result.state) } };
});
const registry = JSON.parse(readFileSync(new URL('./refusals.json', import.meta.url), 'utf8'));
assert.deepEqual([...coverage.keys()].sort(), registry.refusals.filter(r => r.layer === 'stepFn').map(r => r.name).sort());
assert.equal(new Set(grid.actions.map(actionName)).size, 8);
assert.equal(cells.length, 1380);

const envs = grid.envs.map(e => ({
  rotations: e.rotationTo.map(([epoch, from, to]) => ({ epoch, from, to })),
  intents: e.intentAuthorized.map(([epoch, intent, refund]) => ({ epoch, intent: typeof intent === 'string'
    ? { kind: intent } : { kind: 'close', payee: intent.close.payee }, refund })),
  quorums: e.quorum.map(([epoch]) => ({ epoch })),
  duplicities: e.duplicityAt.map(([epoch, sn]) => ({ epoch, sn })),
}));
console.error(JSON.stringify({ cells: cells.length, accepted: cells.filter(c => c.result.status === 'accepted').length,
  refused: cells.filter(c => c.result.status === 'refused').length, guardCoverage: Object.fromEntries([...coverage].sort()) }));
console.log(JSON.stringify({ profile: 'checkpoint-model-v1', params, now: grid.now,
  states: grid.states.map(state), actions: grid.actions.map(action), envs, cells }));
