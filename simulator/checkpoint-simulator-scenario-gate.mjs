#!/usr/bin/env node
/*
 * checkpoint-simulator-scenario-gate.mjs — executable story suite over the
 * checkpoint core, plus the page smoke.
 *
 * Fresh on every run:
 *   1. imports the core module (the same file whose slices the build
 *      script inlines byte-for-byte into the page; step 7 proves that) and
 *      the Lean corpus (parsed refusing lossy number literals);
 *   2. loads every scenario in checkpoint-simulator-scenarios/ — exactly the
 *      fifteen stories, each replayed step by step through the core's
 *      session with the corpus as T7's oracle: refusal reasons, post-states,
 *      flows, the consumer verdict and the set of theorems each step exhibits
 *      are compared with the scenario's expectations, and EVERY theorem
 *      property must hold on every step (exhibited or not);
 *   3. requires every refusal reason the core can produce to be asserted
 *      by a scenario step or by the system generator, and every reason to
 *      have a story-vocabulary explanation;
 *   4. exact Nat: every boundary (params, actions, states, evidence, slots,
 *      JSON, UI parsing) refuses by name anything that is not a safe
 *      non-negative integer, and arithmetic at and beyond 2^53 is refused
 *      rather than rounded — a core that rounds must redden T6/T14;
 *   5. the system level: a seeded generator drives several AIDs through
 *      random actions and evidence; every theorem holds on every transition
 *      and T8 (registry inclusion, no duplicates, state membership) is
 *      exhibited on every accepted transition;
 *   6. the story reconciliation: every "chain checks" clause extracted from
 *      M1-STORIES.md is classified in checkpoint-simulator-clauses.json as a
 *      Lean guard (whose file:line contains its token), an omission, or an
 *      overrule; an unclassified fragment is RED; every distinctive clause
 *      names a scenario step that exercises it (the coverage matrix);
 *   7. runs checkpoint-simulator-build.mjs --check (a stale or forked
 *      inlined copy, or a stale docs/ copy, is RED);
 *   8. loads the page under a minimal DOM with real event/value semantics
 *      (checkpoint-simulator-minidom.mjs) and drives the controls it
 *      asserts, then loads it with ?selftest=1 and requires PASS;
 *   9. prints a table and exits non-zero on anything.
 *
 * Usage:
 *   node simulator/checkpoint-simulator-scenario-gate.mjs               # production
 *   node simulator/checkpoint-simulator-scenario-gate.mjs --matrix      # also print the coverage matrix
 *   node simulator/checkpoint-simulator-scenario-gate.mjs --selftest    # negative controls
 *   node simulator/checkpoint-simulator-scenario-gate.mjs --clauses-md  # print the reconciliation table
 *
 * --selftest proves the gate can fail for the right reason: a scenario
 * with a flipped expectation; a guard flipped in the core (close while
 * poisoned); a lying T6 property; a page without its picker; a core that
 * rounds at 2^53; a wrong top-up transition that T7 must catch against the
 * Lean cell; a registry that drops an unrelated AID (T8); a transition that
 * reads W (T9); a clause dropped from the reconciliation; a guard anchor
 * whose line no longer holds its token; a distinctive scenario step
 * dropped — each RED for its intended reason — then GREEN.
 */

import { readFileSync, writeFileSync, readdirSync, mkdtempSync, mkdirSync, rmSync, cpSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createWindow } from './checkpoint-simulator-minidom.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const argPath = flag => { const i = process.argv.indexOf(flag); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null; };
const CORE = argPath('--core') || join(HERE, 'checkpoint-simulator-core.mjs');
const HTML = argPath('--html') || join(HERE, 'checkpoint-simulator.html');
const SCENARIOS = argPath('--scenarios') || join(HERE, 'checkpoint-simulator-scenarios');
const CLAUSES = argPath('--clauses') || join(HERE, 'checkpoint-simulator-clauses.json');
const CORPUS = join(HERE, 'checkpoint-simulator-corpus.json');
const STORIES = join(HERE, 'M1-STORIES.md');
const LEAN_ROOT = argPath('--lean-root') || join(HERE, '..');
const BUILD = join(HERE, 'checkpoint-simulator-build.mjs');

/* --- one scenario: the core's own checker (shared with the page's selftest) --- */

function runScenario(core, sc, file, corpus) {
  const r = core.checkScenario(sc, file, corpus);
  // the timeline searched for distinctive steps and clause ties spans every branch
  const timeline = [...r.timeline, ...r.forks.flatMap(fk => fk.timeline.map(t => ({ ...t, fork: fk.id })))];
  return { problems: r.problems, asserted: new Set(r.asserted), exhibitedIds: new Set(r.exhibited), stepsRun: r.stepsRun, timeline, forks: r.forks.length };
}

/* --- exact Nat ------------------------------------------------------------ */

function checkExactNat(core, corpus) {
  const problems = [], asserted = new Set();
  const P = { D: 10, B: 5, P: 2, W: 3 };
  const bads = [2 ** 53, 2 ** 53 + 2, 2 ** 60, -1, 1.5, '5', NaN, Infinity, null, undefined, true];
  const live = (over = {}) => ({ present: { l: { sn: 1, epoch: 1, poisoned: false, bornAt: 0, refundTo: 7, dreg: 10, b: 5, pool: 4, ...over } } });
  const LIVE = ['sn', 'epoch', 'bornAt', 'refundTo', 'dreg', 'b', 'pool'];
  const EV_SHAPES = { rotationTo: [1, 1, 2], refundAuthorized: [2, 7], quorum: [1], duplicityAt: [1, 1] };
  // an action that consults each predicate from live(), and one that consults none
  const CONSULTING = { rotationTo: { rotate: { "sn'": 2, op: 'keep', payee: 1, "refund'": null } }, refundAuthorized: { rotate: { "sn'": 2, op: 'keep', payee: 1, "refund'": 7 } }, quorum: 'poison', duplicityAt: { convict: { payee: 1 } } };
  const NOP = { topUp: { x: 0 } };
  const okEnv = core.envAdd(core.envAdd(core.emptyEnv(), { quorum: [1] }), { rotationTo: [1, 1, 2] });
  const got = r => (r.ok ? 'ok' : r.reason + (r.field !== undefined ? '/' + r.field : ''));
  // the entry point must refuse by name, with the offending field, before evaluating anything
  // an entry point that throws on a corrupted input has not refused it by name
  const call = thunk => { try { return thunk(); } catch (e) { return { ok: false, reason: 'THREW', verdict: 'THREW', field: String(e && e.message).slice(0, 80) }; } };
  const refusal = (what, thunk, reason, field) => {
    const r = call(thunk);
    if (r.ok || r.reason !== reason || r.field !== field) problems.push(`${what}: expected ${reason}/${field}, got ${got(r)}`);
    else asserted.add(reason);
  };
  const verdict = (what, thunk, want, field) => {
    const v = call(thunk);
    if (v.ok || v.verdict !== want || v.field !== field) problems.push(`${what}: expected verdict ${want}/${field}, got ${v.ok ? 'consumable' : v.verdict + '/' + v.field}`);
  };
  for (const v of bads) {
    const tag = typeof v === 'string' ? JSON.stringify(v) : String(v);
    if (core.isNat(v)) problems.push(`isNat accepts ${tag}`);
    for (const k of ['D', 'B', 'P', 'W']) if (core.validateParams({ ...P, [k]: v }) === null) problems.push(`params accept ${k}=${tag}`);
    const actions = [{ register: { refund: v, pool0: 1 } }, { register: { refund: 1, pool0: v } }, { rotate: { "sn'": v, op: 'keep', payee: 1, "refund'": null } },
      { rotate: { "sn'": 2, op: 'keep', payee: v, "refund'": null } }, { rotate: { "sn'": 2, op: 'keep', payee: 1, "refund'": v } }, { freeze: { "sn'": v, payee: 1 } },
      { freeze: { "sn'": 2, payee: v } }, { topUp: { x: v } }, { convict: { payee: v } }];
    for (const a of actions) {
      if (a.rotate && a.rotate["sn'"] === 2 && a.rotate.payee === 1 && (v === null || v === undefined)) continue; // refund' null / absent means none
      const n = core.normalizeAction(a);
      if (n.ok || n.reason !== 'invalid-nat') problems.push(`action ${JSON.stringify(a)} not refused invalid-nat (got ${n.ok ? 'ok' : n.reason})`);
      const r = core.step(P, core.emptyEnv(), a, 1, a.register ? 'absent' : live());
      if (r.ok || r.reason !== 'invalid-nat') problems.push(`step ${JSON.stringify(a)} not refused invalid-nat`);
    }
    let threw = false; try { core.envAdd(core.emptyEnv(), { rotationTo: [1, 1, v] }); } catch (e) { threw = true; }
    if (!threw) problems.push(`evidence row accepts ${tag}`);
    const s = core.newSession(P);
    if (core.setSlot(s, v).ok) problems.push(`setSlot accepts ${tag}`);
    refusal(`attempt at slot ${tag}`, () => core.attempt(s, { register: { refund: 1, pool0: 1 } }, v).record, 'invalid-nat', 'slot');
    refusal(`step at now=${tag}`, () => core.step(P, core.emptyEnv(), NOP, v, live()), 'invalid-nat', 'now');
    refusal(`replay from t0=${tag}`, () => core.replay(P, okEnv, v, live(), []), 'invalid-nat', 't0');
    refusal(`replay of a step at slot ${tag}`, () => core.replay(P, okEnv, 0, live(), [[v, NOP]]), 'invalid-nat', 'slot');
    verdict(`consumable at now=${tag}`, () => core.consumable(P, v, live()), 'invalid-nat', 'now');
    // ---- the real boundary: every entry point that takes a state refuses a
    // live datum with one corrupted field, whatever the action would have done
    for (const f of LIVE) {
      const st = live({ [f]: v });
      refusal(`step topUp 0 on a live state with ${f}=${tag}`, () => core.step(P, okEnv, NOP, 1, st), 'invalid-nat', f);
      refusal(`step poison on a live state with ${f}=${tag}`, () => core.step(P, okEnv, 'poison', 1, st), 'invalid-nat', f);
      refusal(`replay from a live state with ${f}=${tag}`, () => core.replay(P, okEnv, 0, st, [[1, NOP]]), 'invalid-nat', f);
      refusal(`replay with no steps from a live state with ${f}=${tag}`, () => core.replay(P, okEnv, 0, st, []), 'invalid-nat', f);
      verdict(`consumable on a live state with ${f}=${tag}`, () => core.consumable(P, 5, st), 'invalid-nat', f);
      // the system step, on the played AID and on another AID
      refusal(`attempt topUp 0 on the played AID with ${f}=${tag}`, () => core.attempt({ ...core.newSession(P), state: st, registry: [1] }, NOP, 0).record, 'invalid-nat', f);
      refusal(`attempt topUp 0 on AID 2 with ${f}=${tag}`, () => core.attempt({ ...core.newSession(P), others: { 2: st }, registry: [2] }, NOP, 0, 2).record, 'invalid-nat', f);
    }
    for (const f of ['epoch', 'sn', 'convictedAt']) {
      const conv = { convicted: { epoch: 1, sn: 1, convictedAt: 1, [f]: v } };
      refusal(`step close on a convicted state with ${f}=${tag} (before convicted-terminal)`, () => core.step(P, okEnv, 'close', 1, conv), 'invalid-nat', f);
      refusal(`replay with no steps from a convicted state with ${f}=${tag}`, () => core.replay(P, okEnv, 0, conv, []), 'invalid-nat', f);
      verdict(`consumable on a convicted state with ${f}=${tag}`, () => core.consumable(P, 5, conv), 'invalid-nat', f);
      refusal(`attempt close on a convicted AID with ${f}=${tag}`, () => core.attempt({ ...core.newSession(P), state: conv, registry: [1] }, 'close', 0).record, 'invalid-nat', f);
    }
    // ---- every entry point that takes an evidence table refuses a corrupted
    // entry of any predicate, whether or not the action consults it
    for (const k of Object.keys(EV_SHAPES)) for (let j = 0; j < EV_SHAPES[k].length; j++) {
      const row = EV_SHAPES[k].slice(); row[j] = v;
      const env = { ...core.emptyEnv(), [k]: [row] };
      const field = `${k}[0][${j}]`;
      refusal(`step topUp 0 (consults nothing) with evidence ${field}=${tag}`, () => core.step(P, env, NOP, 1, live()), 'invalid-nat', field);
      refusal(`step ${core.canon(CONSULTING[k])} (consults ${k}) with evidence ${field}=${tag}`, () => core.step(P, env, CONSULTING[k], 1, live()), 'invalid-nat', field);
      refusal(`register from absent with evidence ${field}=${tag}`, () => core.step(P, env, { register: { refund: 1, pool0: 1 } }, 1, 'absent'), 'invalid-nat', field);
      refusal(`replay with evidence ${field}=${tag}`, () => core.replay(P, env, 0, live(), [[1, NOP]]), 'invalid-nat', field);
      refusal(`replay with no steps with evidence ${field}=${tag}`, () => core.replay(P, env, 0, live(), []), 'invalid-nat', field);
      refusal(`attempt topUp 0 with session evidence ${field}=${tag}`, () => core.attempt({ ...core.newSession(P), state: live(), registry: [1], env }, NOP, 0).record, 'invalid-nat', field);
    }
    // ---- the trace verifier: a corpus carrying a corrupted state or table is refused by name
    if (corpus) {
      const mutate = (edit, what, field) => {
        const c2 = structuredClone(corpus); edit(c2);
        let rs;
        try { rs = core.checkCorpus(c2).reasons; } catch (e) { problems.push(`checkCorpus on a corpus with ${what}=${tag} threw instead of refusing by name: ${e.message}`); return; }
        if (!rs.some(r => r.includes('invalid-nat') && r.includes(field))) problems.push(`checkCorpus on a corpus with ${what}=${tag}: no invalid-nat/${field} reason among ${rs.length} (${rs.slice(0, 2).join(' | ')})`);
      };
      const si = corpus.grid.states.findIndex(s => core.stateKind(s) === 'present');
      mutate(c => { c.grid.states[si].present.l.pool = v; }, `grid state ${si} pool`, 'pool');
      mutate(c => { c.grid.envs[0].duplicityAt = [[1, v]]; }, 'grid env 0 duplicityAt[0][1]', 'duplicityAt[0][1]');
      mutate(c => { c.traces[0].env.quorum = [[v]]; }, 'trace 0 quorum[0][0]', 'quorum[0][0]');
      mutate(c => { const st = c.traces[0].steps.find(s => core.stateKind(s.input) === 'present'); st.input.present.l.sn = v; }, 'trace 0 input sn', 'sn');
      mutate(c => { const st = c.stories[0].steps.find(s => core.stateKind(s.input) === 'present'); st.input.present.l.bornAt = v; }, 'story cell input bornAt', 'bornAt');
      mutate(c => { c.stories[0].steps[0].env.rotationTo = [[0, 0, v]]; }, 'story cell env rotationTo[0][2]', 'rotationTo[0][2]');
      // results, not only inputs: a Lean-side post-state or flow beyond the bound is a refusal, not a parity difference
      const applied = corpus.grid.cells.find(c => c.result && core.stateKind(c.result.state) === 'present');
      mutate(c => { c.grid.cells.find(x => x.s === applied.s && x.a === applied.a && x.e === applied.e).result.state.present.l.pool = v; }, 'grid cell result state pool', 'pool');
      mutate(c => { c.grid.cells.find(x => x.s === applied.s && x.a === applied.a && x.e === applied.e).result.flow.poolIn = v; }, 'grid cell result flow poolIn', 'poolIn');
      mutate(c => { const st = c.traces[0].steps.find(s => s.result && core.stateKind(s.result.state) === 'present'); st.result.state.present.l.b = v; }, 'trace result state b', 'b');
      mutate(c => { const st = c.stories[0].steps.find(s => s.result && core.stateKind(s.result.state) === 'present'); st.result.state.present.l.dreg = v; }, 'story cell result state dreg', 'dreg');
      mutate(c => { c.grid.actions[0] = { topUp: { x: v } }; }, 'grid action x', 'x');
      mutate(c => { c.grid.now = v; }, 'grid now', 'now');
    }
  }
  // ---- shapes that are not a state / not a table are refused by name too
  // exactly one Lean constructor, nothing beside it, nothing extra inside its wrapper
  const shapes = [[{ bogus: 1 }, 'bogus'], [null, 'state'], ['absentt', 'state'], [{}, 'state'], [{ present: { l: null } }, 'l'], [{ present: { l: { ...live().present.l, poisoned: 'no' } } }, 'poisoned'],
    [{ ...live(), extra: true }, 'extra'], [{ ...live(), convicted: { epoch: 1, sn: 1, convictedAt: 1 } }, 'convicted'], [{ present: { l: live().present.l, extra: true } }, 'present.extra'],
    [{ convicted: { epoch: 1, sn: 1, convictedAt: 1 }, present: { l: live().present.l } }, 'present'], [{ present: 'l' }, 'present'], [{ convicted: [1, 1, 1] }, 'convicted'],
    [{ present: { l: { ...live().present.l, extra: 1 } } }, 'extra'], [{ convicted: { epoch: 1, sn: 1, convictedAt: 1, extra: 0 } }, 'extra']];
  for (const [st, field] of shapes) {
    refusal(`step on non-state ${core.canon(st)}`, () => core.step(P, okEnv, NOP, 1, st), 'invalid-state', field);
    refusal(`replay from non-state ${core.canon(st)}`, () => core.replay(P, okEnv, 0, st, []), 'invalid-state', field);
    verdict(`consumable on non-state ${core.canon(st)}`, () => core.consumable(P, 5, st), 'invalid-state', field);
    refusal(`attempt on non-state ${core.canon(st)}`, () => core.attempt({ ...core.newSession(P), state: st, registry: [1] }, NOP, 0).record, 'invalid-state', field);
  }
  const tables = [[null, 'env'], [[], 'env'], [{ ...core.emptyEnv(), bogus: [] }, 'bogus'], [{ ...core.emptyEnv(), quorum: 'x' }, 'quorum'],
    [{ ...core.emptyEnv(), quorum: [[1, 2]] }, 'quorum[0]'], [{ ...core.emptyEnv(), rotationTo: [[1, 1]] }, 'rotationTo[0]'], [{ ...core.emptyEnv(), duplicityAt: [1] }, 'duplicityAt[0]']];
  for (const [env, field] of tables) {
    refusal(`step under non-table ${core.canon(env)}`, () => core.step(P, env, NOP, 1, live()), 'invalid-evidence', field);
    refusal(`register under non-table ${core.canon(env)}`, () => core.step(P, env, { register: { refund: 1, pool0: 1 } }, 1, 'absent'), 'invalid-evidence', field);
    refusal(`replay under non-table ${core.canon(env)}`, () => core.replay(P, env, 0, live(), []), 'invalid-evidence', field);
    refusal(`attempt under non-table ${core.canon(env)}`, () => core.attempt({ ...core.newSession(P), state: live(), registry: [1], env }, NOP, 0).record, 'invalid-evidence', field);
  }
  refusal('replay of a non-list', () => core.replay(P, okEnv, 0, live(), 'x'), 'invalid-action', 'list');
  refusal('replay of a non-pair entry', () => core.replay(P, okEnv, 0, live(), [[1, NOP, 2]]), 'invalid-action', 'list[0]');
  verdict('consumable under a zero bond', () => core.consumable({ ...P, D: 0 }, 5, live()), 'invalid-params', 'D must be positive');
  // a boundary refusal exhibits no theorem: T5 / T8 / T12 must not read a non-state as a refused-with-evidence step
  const brec = core.attempt({ ...core.newSession(P), state: live({ sn: 2 ** 53 }), registry: [1], env: { ...core.emptyEnv(), duplicityAt: [[1, 2 ** 53]] } }, { convict: { payee: 1 } }, 0).record;
  const bviol = Object.keys(brec.theorems).filter(id => !brec.theorems[id].holds);
  if (bviol.length) problems.push('a boundary-refused conviction violates ' + bviol.join(','));
  if (Object.keys(brec.theorems).some(id => id !== 'T9' && brec.theorems[id].exhibited)) problems.push('a boundary-refused step exhibits ' + Object.keys(brec.theorems).filter(id => brec.theorems[id].exhibited).join(','));
  // arithmetic at the bound: refused by name, never rounded
  const M = core.MAX_NAT;
  const hp = { D: 1, B: 1, P: 0, W: 0 };
  const top = core.step(hp, core.emptyEnv(), { topUp: { x: 1 } }, 0, live({ dreg: 1, b: 1, pool: M }));
  if (top.ok || top.reason !== 'invalid-nat' || top.field !== 'pool') problems.push('topUp 1 on a pool of 2^53 − 1 was not refused invalid-nat/pool: ' + JSON.stringify(top));
  const top2 = core.step(hp, core.emptyEnv(), { topUp: { x: 1 } }, 0, live({ dreg: 1, b: 1, pool: M - 1 }));
  if (!top2.ok || top2.state.present.l.pool !== M) problems.push('topUp 1 on a pool of 2^53 − 2 did not give 2^53 − 1 exactly');
  const env = core.envAdd(core.emptyEnv(), { rotationTo: [M, 1, 2] });
  const rot = core.step(hp, env, { rotate: { "sn'": 2, op: 'keep', payee: 1, "refund'": null } }, 0, live({ dreg: 1, b: 1, epoch: M }));
  if (rot.ok || rot.reason !== 'invalid-nat' || rot.field !== 'epoch') problems.push('rotation from epoch 2^53 − 1 was not refused invalid-nat/epoch: ' + JSON.stringify(rot));
  if (core.natAdd(M, 1) !== null || core.natAdd(M - 1, 1) !== M || core.natAdd(2 ** 52, 2 ** 52) !== null) problems.push('natAdd is not exact at the bound');
  // a state beyond the bound forced past validation: the step must refuse, and if a
  // core ever applied it the theorem checkers must see the lost increment
  const huge = 2 ** 53;
  const forced = { ...core.newSession(hp), state: live({ dreg: 1, b: 1, pool: huge }) };
  const fr = core.attempt(forced, { topUp: { x: 1 } }, 0).record;
  if (fr.ok) {
    problems.push(`a pool of 2^53 accepted a top-up (pool after: ${fr.state.present.l.pool})` +
      (fr.theorems.T6.holds && fr.theorems.T14.holds ? ' and T6/T14 did not notice the precision loss' : ' — T6/T14 flagged it: ' + [...fr.theorems.T6.notes, ...fr.theorems.T14.notes].join('; ')));
  } else if (fr.reason !== 'invalid-nat') problems.push('a pool of 2^53 was refused for a reason other than invalid-nat: ' + fr.reason);
  // JSON and UI parsing
  if (!core.lossyJsonNumbers('[9007199254740993, {"a": 18014398509481985}]').length) problems.push('lossyJsonNumbers misses integers beyond 2^53');
  if (core.lossyJsonNumbers('[9007199254740991, -5, 2.5, 0, "x 99999999999999999999"]').length) problems.push('lossyJsonNumbers flags exact literals or strings');
  let thrown = false; try { core.parseJsonExact('{"x": 9007199254740993}'); } catch (e) { thrown = true; }
  if (!thrown) problems.push('parseJsonExact accepted a lossy literal');
  for (const [s, want] of [['9007199254740992', null], ['9007199254740991', M], ['-1', null], ['1e3', null], ['1.0', null], ['', null], ['12', 12], ['007', 7], ['99999999999999999999', null]])
    if (core.parseNat(s) !== want) problems.push(`parseNat(${JSON.stringify(s)}) = ${core.parseNat(s)}, expected ${want}`);
  return { problems, boundaries: bads.length, asserted };
}

/* --- the system level: several AIDs, random actions, every theorem ------ */

function prng(seed) { let x = seed >>> 0 || 1; return () => { x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x / 4294967296; }; }

function checkSystem(core, corpus) {
  const problems = [];
  const P = { D: 1000, B: 5, P: 2, W: 10 };
  const asserted = new Set();
  let accepted = 0, refused = 0, t8Shown = 0, nonRegisterShown = 0, transitions = 0, distinctRegistered = 0;
  for (let run = 0; run < 24; run++) {
    const rnd = prng(0x9e3779b9 + run * 7919);
    const pick = arr => arr[Math.floor(rnd() * arr.length)];
    let s = core.newSession(P, { corpus });
    let slot = 0;
    for (let i = 0; i < 40; i++) {
      const aid = pick([1, 2, 3, 4]);
      const st = core.stateOfAid(s, aid);
      const l = core.liveOf(st);
      const e = l ? l.epoch : 0, sn = l ? l.sn : 0;
      // evidence arrives at random, for this AID's current epoch and sequence
      if (rnd() < 0.5) s = core.addEvidence(s, pick([{ rotationTo: [e, sn, sn + 1] }, { quorum: [e] }, { duplicityAt: [e, sn] }, { refundAuthorized: [e + 1, 1] }, { rotationTo: [e, sn, sn + 2] }]));
      if (rnd() < 0.1) for (const k of core.EV_KINDS) for (const row of s.env[k].slice()) if (rnd() < 0.3) s = core.removeEvidence(s, { [k]: row });
      let action;
      if (core.stateKind(st) === 'absent' && rnd() < 0.7) action = { register: { refund: pick([1, 4, 6]), pool0: Math.floor(rnd() * 12) } };
      else action = pick([
        { rotate: { "sn'": pick([sn + 1, sn, sn + 2]), op: pick(core.BOND_OPS), payee: pick([1, 2, 4]), "refund'": pick([null, null, 1, 9]) } },
        'poison', 'close', { freeze: { "sn'": sn + 1, payee: 2 } }, { topUp: { x: Math.floor(rnd() * 5) } }, { convict: { payee: 3 } },
        { register: { refund: 6, pool0: 1 } },
      ]);
      slot += Math.floor(rnd() * 4);
      const out = core.attempt(s, action, slot, aid);
      s = out.session;
      const rec = out.record;
      transitions++;
      if (rec.ok) accepted++; else { refused++; asserted.add(rec.reason); }
      const th = rec.theorems;
      const failing = Object.keys(th).filter(id => !th[id].holds);
      if (failing.length) problems.push(`system run ${run} step ${i} (aid ${aid}, ${core.canon(action)}): theorem VIOLATED: ` + failing.map(id => id + ' (' + th[id].notes.join('; ') + ')').join(' · '));
      if (rec.ok) {
        if (!th.T8.exhibited) problems.push(`system run ${run} step ${i}: accepted transition does not exhibit T8`);
        else { t8Shown++; if (rec.kind !== 'register') nonRegisterShown++; }
      }
      if (problems.length > 12) return { problems, transitions };
    }
    // the registry equals the set of AIDs ever registered in this run, no duplicates
    const everRegistered = new Set(s.records.filter(r => r.ok && r.kind === 'register').map(r => r.aid));
    if (s.registry.length !== everRegistered.size || ![...everRegistered].every(a => s.registry.includes(a))) problems.push(`system run ${run}: registry ${JSON.stringify(s.registry)} ≠ AIDs registered ${JSON.stringify([...everRegistered])}`);
    distinctRegistered += everRegistered.size;
    // a corrupted registry (an absent AID listed) refuses that AID's registration by name
    const corrupted = { ...s, registry: [...s.registry, 9] };
    const cr = core.attempt(corrupted, { register: { refund: 1, pool0: 1 } }, slot, 9).record;
    if (cr.ok || cr.reason !== 'aid-already-registered') problems.push(`system run ${run}: registration of a listed-but-absent AID not refused aid-already-registered (got ${cr.ok ? 'ok' : cr.reason})`);
    asserted.add('aid-already-registered');
    if (!cr.theorems.T8.exhibited || !cr.theorems.T8.holds) problems.push(`system run ${run}: the refused re-registration does not exhibit T8 holding`);
  }
  if (accepted < 200) problems.push(`system generator accepted only ${accepted} transitions`);
  if (nonRegisterShown < 100) problems.push(`system generator exhibited T8 on only ${nonRegisterShown} non-registration transitions`);
  if (distinctRegistered < 48) problems.push(`system generator registered only ${distinctRegistered} AIDs over the runs`);
  return { problems, transitions, accepted, refused, t8Shown, nonRegisterShown, asserted };
}

/* --- the Lean source, by declaration span ------------------------------- */

// leanSpans(files) → Map name → {file, from, to, text}: every top-level
// declaration (theorem/def/inductive/structure/abbrev/instance) runs from its
// line to the line before the next column-0 declaration, doc comment, section
// or `end`; every constructor of an inductive (`  | name`) is `Inductive.name`
// and runs to the line before the next constructor or its doc comment. Doc
// comments are not part of a span: an anchor must be code.
const TOP = /^(theorem|def|inductive|structure|abbrev|instance)\s+([^\s(:{]+)/;
const TOP_END = /^(theorem|def|inductive|structure|abbrev|instance|namespace|end|open|section|\/-|#)/;
function leanSpans(files) {
  const spans = new Map();
  for (const [file, text] of Object.entries(files)) {
    const lines = text.split('\n');
    const put = (name, from, to) => spans.set(name, { file, from: from + 1, to: to + 1, text: lines.slice(from, to + 1).join('\n') });
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(TOP);
      if (!m) continue;
      let j = i + 1;
      while (j < lines.length && !TOP_END.test(lines[j])) j++;
      put(m[2], i, j - 1);
      if (m[1] === 'inductive') {
        let c = -1, cname = null;
        const close = k => { if (c >= 0) put(m[2] + '.' + cname, c, k); };
        for (let k = i + 1; k <= j - 1; k++) {
          const cm = lines[k].match(/^  \| (\S+)/);
          if (cm) { close(k - 1); c = k; cname = cm[1]; }
          else if (/^  \/--/.test(lines[k])) { close(k - 1); c = -1; }
        }
        close(j - 1);
      }
      i = j - 1;
    }
  }
  return spans;
}
// binders(span) → {name: typeText} for every `(name : type)` binder in a span
function binders(span) {
  const out = {};
  const re = /\(([A-Za-z_][A-Za-z0-9_']*)\s*:\s*/g;
  let m;
  while ((m = re.exec(span.text))) {
    let depth = 1, k = re.lastIndex;
    while (k < span.text.length && depth) { if (span.text[k] === '(') depth++; else if (span.text[k] === ')') depth--; k++; }
    out[m[1]] = span.text.slice(re.lastIndex, k - 1).replace(/\s+/g, ' ').trim();
  }
  // structure fields: `  name : type` lines (Params.hD : 0 < D)
  for (const line of span.text.split('\n')) { const f = line.match(/^  ([A-Za-z_][A-Za-z0-9_']*)\s*:\s*(.+)$/); if (f && out[f[1]] === undefined) out[f[1]] = f[2].trim(); }
  return out;
}
// groups(text) → the balanced groups and words of a Lean expression
function groups(text) {
  const out = []; let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (/\s/.test(ch)) { i++; continue; }
    if ('({⟨'.includes(ch)) {
      let depth = 0, j = i;
      for (; j < text.length; j++) { if ('({⟨'.includes(text[j])) depth++; else if (')}⟩'.includes(text[j])) { depth--; if (!depth) break; } }
      out.push(text.slice(i, j + 1)); i = j + 1;
    } else { let j = i; while (j < text.length && !/\s/.test(text[j]) && !'({⟨'.includes(text[j])) j++; out.push(text.slice(i, j)); i = j; }
  }
  return out;
}
// constructorParts(span) → {action, input, flow, post, postUpdates} for a Step
// constructor (`Step p env (action) now (input) {flow} (post)`), {input, post}
// for a SysStep constructor, null otherwise; postUpdates lists the datum
// fields a `{ l with … }` post-state sets
function constructorParts(span) {
  const m = span.text.match(/^\s*(Step|SysStep) p env /m);
  if (!m) return null;
  const g = groups(span.text.slice(m.index));
  if (m[1] === 'Step') {
    const [, , , action, , input, flow, post] = g;
    const sp = squash(post || '');
    const upd = /^\(\.present \{ l with /.test(sp) ? [...sp.slice(sp.indexOf(' with ') + 6).matchAll(/([A-Za-z_][A-Za-z0-9_']*)\s*:=/g)].map(x => x[1]) : null;
    return { action: action || null, input: input || null, flow: flow && flow.startsWith('{') ? flow : null, post: post || null, postUpdates: upd };
  }
  return { action: null, input: g[3] || null, flow: null, post: g[4] || null, postUpdates: null };
}
const squash = s => String(s).replace(/\s+/g, ' ');
const within = (hay, needle) => squash(hay).includes(squash(needle));
const where = span => `${span.file}:${span.from}-${span.to}`;

/* --- story reconciliation ---------------------------------------------- */

const LABELS = { default: ['The chain checks', 'The predicate', 'Fails closed', 'What limits it'], 13: ['Action'], 14: ['*'], 15: ['Today', 'Direction (D-027, not yet ruled)'] };

function extractStoryClauses(md) {
  const out = {}; // story → [{label, text}]
  let story = null, bullets = [];
  const flush = () => { if (story !== null) out[story] = bullets; };
  for (const raw of md.split('\n')) {
    const h = raw.match(/^## (\d+)\. /);
    if (h) { flush(); story = Number(h[1]); bullets = []; continue; }
    if (/^## /.test(raw) || /^---/.test(raw)) { flush(); story = null; continue; }
    if (story === null) continue;
    if (/^- /.test(raw)) bullets.push(raw.slice(2));
    else if (/^  \S/.test(raw) && bullets.length) bullets[bullets.length - 1] += ' ' + raw.trim();
  }
  flush();
  const res = {};
  for (const [st, bs] of Object.entries(out)) {
    const labels = LABELS[st] || LABELS.default;
    res[st] = [];
    for (const b of bs) {
      const text = b.replace(/\s+/g, ' ').trim();
      if (labels.includes('*')) { res[st].push({ label: '*', text }); continue; }
      const m = text.match(/^\*\*([^*]+)\*\*:?\s*(.*)$/) || text.match(/^(Today|Direction \(D-027, not yet ruled\)):\s*(.*)$/);
      if (m && labels.includes(m[1])) res[st].push({ label: m[1], text: m[2] });
    }
  }
  return res;
}

// does a scenario timeline entry match a clause's `match` (the distinctive vocabulary)?
function recordMatches(core, m, t) {
  const r = t.record; if (!r) return false;
  const params = t.session.params;
  const dd = (r.action && typeof r.action === 'object') ? r.action[r.kind] : {};
  const lp = core.liveOf(r.pre), lq = core.liveOf(r.state);
  const fl = r.flow || core.flow({});
  return [
    m.ok === undefined || r.ok === m.ok,
    m.kind === undefined || r.kind === m.kind,
    m.reason === undefined || r.reason === m.reason,
    m.op === undefined || dd.op === m.op,
    m.preWord === undefined || core.stateWord(params, r.pre) === m.preWord,
    !m.prePoisoned || (lp && lp.poisoned === true),
    !m.refundNull || dd["refund'"] === null,
    !m.refundUnchanged || (lp && lq && lp.refundTo === lq.refundTo),
    !m.refundChanged || (lp && lq && lp.refundTo !== lq.refundTo),
    !m.hunterPool || (r.ok && fl.hunter && fl.hunter.pool > 0),
    !m.noFlow || (r.ok && core.canon(fl) === core.canon(core.flow({}))),
    !m.refundToAlice || (r.ok && fl.refund && fl.refund.addr === 1),
    !m.bornAtUnchanged || (lp && lq && lp.bornAt === lq.bornAt),
  ].every(Boolean);
}
function findStep(core, story, m, scenarioTimelines) {
  for (const [file, tl] of Object.entries(scenarioTimelines)) {
    if (Number(file.match(/^(\d+)/)[1]) !== story) continue;
    for (let i = 0; i < tl.length; i++) if (recordMatches(core, m, tl[i])) return { file, step: i, record: tl[i].record };
  }
  return null;
}

// the refusal names against the Lean: every claim exists with its text inside
// the constructor (and inside the named binder), every `h`-binder of every
// Step constructor is claimed exactly once, every theorem named exists
function checkGuardTable(core, spans) {
  const problems = [];
  const claimed = new Map(); // 'decl/hyp' → reason
  const claim = (decl, hyp, by, text) => {
    const span = spans.get(decl);
    if (!span) { problems.push(`guard table: ${by} names ${decl}, which is not a declaration of the Lean`); return; }
    if (hyp) {
      const b = binders(span)[hyp];
      if (b === undefined) problems.push(`guard table: ${by} names ${decl}/${hyp}, but ${decl} (${where(span)}) has no binder ${hyp}`);
      else if (text && !within(b, text)) problems.push(`guard table: ${decl}/${hyp} is «${b}», not «${text}» (${by})`);
      const key = decl + '/' + hyp;
      if (claimed.has(key) && claimed.get(key) !== by) problems.push(`guard table: ${key} is claimed by both ${claimed.get(key)} and ${by}`);
      claimed.set(key, by);
    } else if (text && !within(span.text, text)) problems.push(`guard table: «${text}» is not inside ${decl} (${where(span)}) (${by})`);
  };
  for (const reason of core.REASONS) {
    const g = core.LEAN_GUARDS[reason];
    if (!g) { problems.push(`guard table: refusal ${reason} has no entry (which Lean guard is it?)`); continue; }
    for (const decl of g.decls) {
      if (g.hyp) claim(decl, g.hyp, reason, g.text);
      else if (g.hyps) for (const [h, t] of g.hyps) claim(decl, h, reason, t);
      else claim(decl, null, reason, g.text);
    }
    if (g.theorem && !spans.has(g.theorem)) problems.push(`guard table: ${reason} names theorem ${g.theorem}, which does not exist`);
  }
  for (const reason of Object.keys(core.LEAN_GUARDS)) if (!core.REASONS.includes(reason)) problems.push(`guard table: ${reason} is not a refusal the core can produce`);
  for (const s of core.LEAN_SPLITS) claim(s.decl, s.hyp, 'split ' + s.hyp, s.text);
  // every guard hypothesis of every Step constructor is claimed
  let hyps = 0;
  for (const [name, span] of spans) {
    if (!name.startsWith('Step.')) continue;
    for (const h of Object.keys(binders(span))) {
      if (!/^h/.test(h)) continue;
      hyps++;
      if (!claimed.has(name + '/' + h)) problems.push(`guard table: ${name}/${h} (${where(span)}) is a guard the refusal names do not claim`);
    }
  }
  if (!hyps) problems.push('guard table: no Step constructor with a guard hypothesis found in the Lean (parser broken?)');
  return { problems, hyps, claimed };
}

function checkClauses(core, clausesDoc, storiesMd, scenarioTimelines, leanRoot) {
  const problems = [];
  const clauses = clausesDoc.clauses || [];
  const files = {};
  for (const f of ['lean/CardanoKeri/Checkpoint.lean', 'lean/CardanoKeri/CheckpointGoals.lean']) {
    try { files[f] = readFileSync(join(leanRoot, f), 'utf8'); } catch (e) { problems.push(`cannot read ${f}: ${e.message}`); }
  }
  const spans = leanSpans(files);
  const gt = checkGuardTable(core, spans);
  problems.push(...gt.problems);
  const byStory = {};
  for (const c of clauses) (byStory[c.story] = byStory[c.story] || []).push(c);
  const theoremGroup = decl => core.THEOREMS.find(t => t.lean.includes(decl));
  // the parts of a constructor: the conclusion `Step p env (action) now (input)
  // {flow} (post)` split into balanced groups; a claim's text must sit in the
  // part its kind names (a guard in a hypothesis binder, a payment in the flow
  // at the field that pays it, a post-state claim in the post-state expression)
  const KINDS = ['guard', 'refusal', 'payment', 'post-state', 'no-guard', 'verdict'];
  const TIES_OF = { guard: ['reason', 'match'], refusal: ['reason'], payment: ['match'], 'post-state': ['match'], 'no-guard': ['match'], verdict: ['verdict'] };
  const FLOW_FIELD = /^(dregIn|bIn|poolIn|refund|hunter|convictor)\s*:=/;
  let anchored = 0;
  for (const c of clauses) {
    const tag = `story ${c.story} clause «${c.clause}»`;
    const fail = msg => problems.push(`${tag}: ${msg}`);
    if (!['guard', 'omission', 'overrule'].includes(c.class)) { fail(`unknown class ${c.class}`); continue; }
    if (c.class === 'omission') { if (!c.note) fail('an omission needs a note'); if (c.decl || c.reason || c.verdict || c.match || c.kind) fail('an omission anchors nothing'); continue; }
    if (c.ref || c.token) fail('file:line anchors are gone; name a declaration (decl) and its text');
    if (!c.decl || !c.text) { fail(`a ${c.class} row names a Lean declaration (decl) and the exact text (text) that entails it`); continue; }
    const span = spans.get(c.decl);
    if (!span) { fail(`${c.decl} is not a declaration of the Lean`); continue; }
    const ties = ['reason', 'verdict', 'match'].filter(k => c[k] !== undefined);
    if (ties.length !== 1) { fail(`a ${c.class} row carries exactly one tie (reason, verdict or match), has ${ties.length ? ties.join('+') : 'none'}`); continue; }
    const tie = ties[0];
    // 0. the declaration decides the clause's tie at all
    if (tie === 'match' && !(c.decl.startsWith('Step.') || c.decl.startsWith('SysStep.') || theoremGroup(c.decl))) { fail(`a match tie needs a Step constructor, a SysStep constructor or a theorem, not ${c.decl}`); continue; }
    if (tie === 'reason') {
      const g = core.LEAN_GUARDS[c.reason];
      if (!g) { fail(`unknown reason ${c.reason}`); continue; }
      if (!g.decls.includes(c.decl)) { fail(`${c.reason} is decided by ${g.decls.join(' / ') || 'the simulator, not the Lean'}, not by ${c.decl}`); continue; }
    }
    if (tie === 'verdict' && c.decl !== 'consumableState') { fail(`a verdict claim lives in consumableState, not ${c.decl}`); continue; }
    if (!KINDS.includes(c.kind)) { fail(`a ${c.class} row names its claim kind (${KINDS.join(' / ')}), has ${c.kind}`); continue; }
    if (!TIES_OF[c.kind].includes(tie)) { fail(`a ${c.kind} claim ties by ${TIES_OF[c.kind].join(' or ')}, not by ${tie}`); continue; }
    const b = binders(span), parts = constructorParts(span);
    // 1. the text sits in the part its kind names
    let flowField = null, ok = true;
    if (c.kind === 'guard' || c.kind === 'refusal') {
      if (!c.hyp) { fail(`a ${c.kind} claim names the hypothesis (hyp) it lives in`); ok = false; }
      else if (b[c.hyp] === undefined) { fail(`${c.decl} (${where(span)}) has no binder ${c.hyp}`); ok = false; }
      else if (!within(b[c.hyp], c.text)) { fail(`«${c.text}» is not inside ${c.decl}/${c.hyp} : «${b[c.hyp]}»`); ok = false; }
    } else if (c.kind === 'payment') {
      if (!parts || parts.flow === null) { fail(`${c.decl} has no flow record for a payment claim`); ok = false; }
      else if (!within(parts.flow, c.text)) { fail(`«${c.text}» is not inside the flow of ${c.decl} : «${squash(parts.flow)}»`); ok = false; }
      else { const m = squash(c.text).match(FLOW_FIELD); if (!m) { fail(`a payment claim's text starts at the flow field that pays it (dregIn / bIn / poolIn / refund / hunter / convictor): «${c.text}»`); ok = false; } else flowField = m[1]; }
    } else if (c.kind === 'post-state') {
      if (!parts || parts.post === null) { fail(`${c.decl} has no post-state for a post-state claim`); ok = false; }
      else if (!within(parts.post, c.text)) { fail(`«${c.text}» is not inside the post-state of ${c.decl} : «${squash(parts.post)}»`); ok = false; }
      else if (c.updates !== undefined) {
        if (!parts.postUpdates) { fail(`the post-state of ${c.decl} is not «{ l with … }», it carries no untouched-except claim`); ok = false; }
        else { const want = [...c.updates].sort().join(','), got = [...parts.postUpdates].sort().join(','); if (want !== got) { fail(`the post-state of ${c.decl} updates ${got || 'nothing'}, the claim says ${want || 'nothing'}`); ok = false; } }
      }
    } else if (c.kind === 'no-guard') {
      const hs = Object.keys(b).filter(h => /^h/.test(h));
      if (hs.length) { fail(`${c.decl} has the guard hypotheses ${hs.join(', ')}; a no-guard claim needs none`); ok = false; }
      else if (!parts || !within(parts.action, c.text)) { fail(`«${c.text}» is not the action of ${c.decl}`); ok = false; }
    } else if (c.kind === 'verdict') {
      if (c.decl !== 'consumableState') { fail(`a verdict claim lives in consumableState, not ${c.decl}`); ok = false; }
      else if (!within(span.text, c.text)) { fail(`«${c.text}» is not inside consumableState`); ok = false; }
    }
    if (!ok) continue;
    // 2. the tie agrees with what decides the clause
    if (tie === 'reason') {
      const g = core.LEAN_GUARDS[c.reason];
      const hyps = g.hyp ? [g.hyp] : (g.hyps || []).map(x => x[0]);
      if (!hyps.includes(c.hyp)) { fail(`${c.reason} is the guard ${hyps.join('/')}, not ${c.hyp}`); continue; }
      if (c.kind === 'refusal' && !findStep(core, c.story, { ok: false, reason: c.reason }, scenarioTimelines)) { fail(`no step of story ${c.story}'s scenario is refused ${c.reason}`); continue; }
    } else if (tie === 'verdict') {
      const conj = core.VERDICT_CONJUNCTS[c.verdict];
      if (!conj) { fail(`${c.verdict} is not a conjunct verdict`); continue; }
      if (!conj.some(x => squash(x) === squash(c.text))) { fail(`«${c.text}» is not the conjunct of ${c.verdict} (${conj.join(' / ')})`); continue; }
    } else {
      const hit = findStep(core, c.story, c.match, scenarioTimelines);
      if (!hit) { fail(`no step of story ${c.story}'s scenario matches ${JSON.stringify(c.match)}`); continue; }
      const rec = hit.record, grp = theoremGroup(c.decl);
      if (c.decl.startsWith('Step.')) {
        const decided = rec.ok ? [core.constructorOf(rec)] : ((core.LEAN_GUARDS[rec.reason] || {}).decls || []);
        if (!decided.includes(c.decl)) { fail(`${hit.file} step ${hit.step} goes through ${decided.join(' / ') || 'no constructor'}, not ${c.decl}`); continue; }
      } else if (c.decl.startsWith('SysStep.')) {
        const sys = rec.ok && rec.kind === 'register' ? 'SysStep.register' : rec.ok ? 'SysStep.other' : null;
        if (sys !== c.decl) { fail(`${hit.file} step ${hit.step} is ${sys || 'no system step'}, not ${c.decl}`); continue; }
      } else {
        const th = rec.theorems[grp.id];
        if (!th || !th.exhibited || !th.holds) { fail(`${hit.file} step ${hit.step} does not exhibit ${grp.id} (${c.decl})`); continue; }
      }
      if (c.kind === 'payment') {
        const v = (rec.flow || {})[flowField]; const paid = typeof v === 'number' ? v > 0 : !!v;
        if (!paid) { fail(`${hit.file} step ${hit.step} pays nothing through ${flowField}`); continue; }
      }
      if (c.kind === 'post-state' && c.updates !== undefined) {
        const lp = core.liveOf(rec.pre), lq = core.liveOf(rec.state);
        if (!lp || !lq) { fail(`${hit.file} step ${hit.step} is not a present → present step; an untouched-except claim needs one`); continue; }
        const outside = [...core.LIVE_NATS, 'poisoned'].filter(k => lp[k] !== lq[k] && !c.updates.includes(k));
        if (outside.length) { fail(`${hit.file} step ${hit.step} changes ${outside.join(', ')}, outside the claimed updates ${c.updates.join(', ')}`); continue; }
      }
    }
    anchored++;
  }
  // every extracted fragment of the stories is covered by the clauses (longest
  // clause first, so "not poisoned" is taken before "poisoned"), and every
  // clause of the table occurs in its story
  const extracted = extractStoryClauses(storiesMd);
  let fragments = 0;
  const seen = new Set();
  for (let n = 1; n <= 15; n++) {
    const bs = extracted[n] || [];
    if (!bs.length) { problems.push(`story ${n}: no "chain checks" bullet found in M1-STORIES.md`); continue; }
    const cs = [...new Set((byStory[n] || []).map(c => c.clause))].sort((a, b) => b.length - a.length);
    for (const b of bs) {
      let rest = b.text;
      for (const cl of cs) { const i = rest.indexOf(cl); if (i >= 0) { rest = rest.slice(0, i) + ' ' + rest.slice(i + cl.length); fragments++; seen.add(n + ' ' + cl); } }
      const leftover = rest.replace(/[\s;:.,()—]/g, '');
      if (leftover.length) problems.push(`story ${n}: unclassified fragment in «${b.label}»: «${rest.trim().replace(/\s+/g, ' ').slice(0, 120)}»`);
    }
    if (!cs.length) problems.push(`story ${n}: no clauses in the reconciliation table`);
  }
  for (const c of clauses) if (!seen.has(c.story + ' ' + c.clause)) problems.push(`story ${c.story} clause «${c.clause}» does not occur in the story's checked bullets`);
  // distinctive clauses: each names a scenario step that exercises it
  const matrix = [];
  for (const d of clausesDoc.distinctive || []) {
    const hit = findStep(core, d.story, d.match || {}, scenarioTimelines);
    matrix.push({ id: d.id, story: d.story, clause: d.clause, hit: hit ? { file: hit.file, step: hit.step } : null });
    if (!hit) problems.push(`distinctive clause «${d.id}» (story ${d.story}: ${d.clause}) is not exercised by any scenario step`);
  }
  return { problems, clauses: clauses.length, anchored, fragments, matrix, hyps: gt.hyps };
}

function clausesMarkdown(clausesDoc) {
  const lines = ['| story | clause | class | kind | Lean declaration | text | tie | note |', '|---|---|---|---|---|---|---|---|'];
  const esc = s => String(s === undefined ? '' : s).replace(/\|/g, '\\|');
  for (const c of clausesDoc.clauses) {
    const tie = c.reason ? 'reason ' + c.reason : c.verdict ? 'verdict ' + c.verdict : c.match ? 'step ' + JSON.stringify(c.match) : '';
    lines.push(`| ${c.story} | ${esc(c.clause)} | ${c.class} | ${esc(c.kind)} | ${c.decl ? esc(c.decl + (c.hyp ? '/' + c.hyp : '')) : ''} | ${c.text ? '`' + esc(c.text) + '`' : ''} | ${esc(tie)} | ${esc(c.note)} |`);
  }
  return lines.join('\n');
}

/* --- page smoke under the minimal DOM ---------------------------------- */

function pageSmoke(core, html) {
  const problems = [];
  let win;
  try { win = createWindow(html, { search: '' }); }
  catch (e) { return { problems: ['page failed to load: ' + (e && e.stack || e)] }; }
  const doc = win.document;
  const $ = sel => doc.querySelector(sel);
  const errs = win.__errors || [];
  if (errs.length) problems.push('page raised on load: ' + errs.map(String).join(' | '));
  const net = html.match(/\b(src|href)\s*=\s*"(https?:)?\/\//g);
  if (net) problems.push('page references the network: ' + net.slice(0, 3).join(', '));
  const picker = $('#story-picker');
  if (!picker) { problems.push('no #story-picker'); return { problems }; }
  const opts = picker.querySelectorAll('option').filter(o => o.value !== '');
  if (opts.length !== 15) problems.push(`picker lists ${opts.length} stories, expected 15`);
  const pick = n => { picker.value = String(n); picker.dispatchEvent(win.makeEvent('change')); };
  pick(3);
  const next = $('#hist-next');
  if (!next) problems.push('no #hist-next control');
  let guard = 0;
  while (next && !next.disabled && guard++ < 50) next.dispatchEvent(win.makeEvent('click'));
  const strip = $('#history-strip');
  const chips = strip ? strip.querySelectorAll('.hist-chip') : [];
  if (chips.length < 3) problems.push(`story 3 played ${chips.length} chips, expected the story's steps`);
  const stateName = ($('#state-name') || {}).textContent || '';
  if (!/frozen/i.test(stateName)) problems.push(`after story 3 the ladder shows «${stateName}», expected Frozen`);
  const verdictText = ($('#verdict') || {}).textContent || '';
  if (!/freeze bond/i.test(verdictText)) problems.push(`after story 3 the verdict says «${verdictText.slice(0, 80)}», expected the freeze bond conjunct`);
  const okChips = doc.querySelectorAll('#history-strip .hist-chip.ok');
  if (!okChips.length) problems.push('no accepted chip in the history strip');
  else okChips[okChips.length - 1].dispatchEvent(win.makeEvent('click'));
  const lit = doc.querySelectorAll('#ledger .thm.lit').map(e => e.dataset.id).sort();
  if (!lit.includes('T15')) problems.push(`ledger on the freeze step lights [${lit}], expected T15 among them`);
  if (!lit.includes('T7')) problems.push(`ledger on the freeze step lights [${lit}], expected T7 (a Lean story cell exists)`);
  if (!/frozen/i.test(($('#state-name') || {}).textContent || '')) problems.push('the last accepted chip does not show Frozen');
  while (next && !next.disabled && guard++ < 50) next.dispatchEvent(win.makeEvent('click'));
  const broken = doc.querySelectorAll('#ledger .thm.broken');
  if (broken.length) problems.push('ledger shows broken rows: ' + broken.map(e => e.dataset.id).join(','));
  const prev = $('#hist-prev'), first = $('#hist-first');
  if (!prev || !first) problems.push('no #hist-prev / #hist-first controls');
  else {
    prev.dispatchEvent(win.makeEvent('click'));
    const back1 = ($('#state-name') || {}).textContent || '';
    if (!/frozen/i.test(back1)) problems.push(`one step back the ladder shows «${back1}», expected Frozen`);
    first.dispatchEvent(win.makeEvent('click'));
    const start = ($('#state-name') || {}).textContent || '';
    if (!/absent/i.test(start)) problems.push(`at the start the ladder shows «${start}», expected Absent`);
  }
  // free play: reset, register, evidence rows, slot control
  const reset = $('#btn-reset');
  if (!reset) problems.push('no #btn-reset'); else reset.dispatchEvent(win.makeEvent('click'));
  const actorBtn = doc.querySelector('.actor[data-actor="anyone"]');
  if (!actorBtn) problems.push('no anyone actor chip'); else actorBtn.dispatchEvent(win.makeEvent('click'));
  const regBtn = doc.querySelector('.act[data-kind="register"]');
  if (!regBtn) problems.push('no register action for anyone');
  else if (regBtn.disabled) problems.push('register is disabled on an absent checkpoint');
  else regBtn.dispatchEvent(win.makeEvent('click'));
  const goBtn = $('#act-submit');
  if (goBtn) goBtn.dispatchEvent(win.makeEvent('click'));
  const v0 = ($('#verdict') || {}).textContent || '';
  if (!/juvenile|young|born/i.test(v0)) problems.push(`after register the verdict says «${v0.slice(0, 80)}», expected juvenile`);
  const slotInput = $('#slot-input');
  if (!slotInput) problems.push('no #slot-input');
  else {
    slotInput.value = '10'; slotInput.dispatchEvent(win.makeEvent('change'));
    const v1 = ($('#verdict') || {}).textContent || '';
    if (!/consumable/i.test(v1) || /not consumable/i.test(v1)) problems.push(`after moving the slot to 10 the verdict says «${v1.slice(0, 80)}», expected consumable`);
    slotInput.value = '3'; slotInput.dispatchEvent(win.makeEvent('change'));
    if (($('#slot-now') || {}).textContent !== '10') problems.push('the slot control went backwards');
    slotInput.value = '9007199254740992'; slotInput.dispatchEvent(win.makeEvent('change'));
    if (($('#slot-now') || {}).textContent !== '10') problems.push('the slot control accepted 2^53');
    slotInput.value = '1e3'; slotInput.dispatchEvent(win.makeEvent('change'));
    if (($('#slot-now') || {}).textContent !== '10') problems.push('the slot control accepted an exponent literal');
  }
  const evKind = $('#ev-kind'), evAdd = $('#ev-add');
  if (!evKind || !evAdd) problems.push('no evidence controls');
  else {
    evKind.value = 'rotationTo'; evKind.dispatchEvent(win.makeEvent('change'));
    $('#ev-a').value = '0'; $('#ev-b').value = '0'; $('#ev-c').value = '9007199254740992';
    evAdd.dispatchEvent(win.makeEvent('click'));
    if (doc.querySelectorAll('#ev-rows .ev-row').length !== 0) problems.push('an evidence row with 2^53 was accepted');
    $('#ev-c').value = '1';
    evAdd.dispatchEvent(win.makeEvent('click'));
    const rows = doc.querySelectorAll('#ev-rows .ev-row');
    if (rows.length !== 1) problems.push(`evidence rows after add: ${rows.length}, expected 1`);
    const hal = doc.querySelector('.actor[data-actor="hal"]');
    if (hal) hal.dispatchEvent(win.makeEvent('click'));
    const rot = doc.querySelector('.act[data-kind="rotate"]');
    if (!rot) problems.push('no rotate action for hal');
    else if (rot.disabled) problems.push('rotate is disabled although the rotation evidence is present: ' + rot.title);
    const rm = doc.querySelector('#ev-rows .ev-rm');
    if (!rm) problems.push('no evidence remove control');
    else {
      rm.dispatchEvent(win.makeEvent('click'));
      if (doc.querySelectorAll('#ev-rows .ev-row').length !== 0) problems.push('evidence row not removed');
      const rot2 = doc.querySelector('.act[data-kind="rotate"]');
      if (rot2 && !rot2.disabled) problems.push('rotate stays enabled after the evidence was removed');
      if (rot2 && !/witness/i.test(rot2.title)) problems.push('disabled rotate does not explain the missing witnessed rotation: ' + rot2.title);
    }
  }
  const theme = $('#btn-theme');
  if (!theme) problems.push('no #btn-theme');
  else {
    const before = doc.documentElement.dataset.theme || '';
    theme.dispatchEvent(win.makeEvent('click'));
    if ((doc.documentElement.dataset.theme || '') === before) problems.push('theme toggle did nothing');
  }
  const canvas = $('#value-chart');
  if (!canvas) problems.push('no #value-chart canvas');
  else if (!canvas.__ctx || canvas.__ctx.calls < 10) problems.push('the value chart drew nothing');
  if (win.__errors && win.__errors.length) problems.push('page raised during play: ' + win.__errors.map(String).join(' | '));
  try {
    const w2 = createWindow(html, { search: '?selftest=1' });
    if (w2.__errors.length) problems.push('selftest page raised: ' + w2.__errors.map(String).join(' | '));
    const title = w2.document.title;
    const pre = (w2.document.querySelector('#selftest-out') || {}).textContent || '';
    if (!/^PASS/.test(title) || /^FAIL/m.test(pre)) problems.push('the page selftest does not PASS: ' + title + ' — ' + pre.split('\n').filter(l => /^FAIL/.test(l)).join(' | '));
    if (!/Lean corpus/.test(pre)) problems.push('the page selftest did not replay the Lean corpus');
  } catch (e) { problems.push('selftest page failed to load: ' + (e && e.message)); }
  return { problems };
}

/* --- the suite ------------------------------------------------------------ */

async function runSuite(opts) {
  opts = { ...opts, leanRoot: opts.leanRoot || LEAN_ROOT };
  const core = await import(pathToFileURL(opts.core || CORE).href + '?t=' + Date.now() + Math.random());
  const rows = [], problems = [];
  let corpus = null;
  try { corpus = core.parseJsonExact(readFileSync(CORPUS, 'utf8')); } catch (e) { problems.push('corpus unreadable or lossy: ' + e.message); }
  const files = readdirSync(opts.scenarios || SCENARIOS).filter(f => f.endsWith('.json')).sort();
  if (files.length !== 15) problems.push(`scenario files: ${files.length}, expected 15`);
  const asserted = new Set(), stories = new Set(), timelines = {};
  let steps = 0;
  for (const f of files) {
    let sc;
    try { sc = core.parseJsonExact(readFileSync(join(opts.scenarios || SCENARIOS, f), 'utf8')); }
    catch (e) { problems.push(`${f}: unreadable or lossy: ${e.message}`); continue; }
    if (!Number.isInteger(sc.story) || stories.has(sc.story)) problems.push(`${f}: story number missing or duplicated`);
    stories.add(sc.story);
    if (!Array.isArray(sc.steps) || !sc.steps.length) { problems.push(`${f}: no steps`); continue; }
    const r = runScenario(core, sc, f, corpus);
    r.asserted.forEach(x => asserted.add(x));
    steps += r.stepsRun; timelines[f] = r.timeline;
    rows.push({ item: `story ${String(sc.story).padStart(2)} ${sc.title}`, steps: r.stepsRun, exhibits: r.exhibitedIds.size, ok: !r.problems.length });
    problems.push(...r.problems);
  }
  for (let n = 1; n <= 15; n++) if (!stories.has(n)) problems.push(`story ${n} has no scenario`);
  // exact Nat
  const nat = checkExactNat(core, corpus);
  nat.asserted.forEach(x => asserted.add(x));
  rows.push({ item: `exact Nat: ${nat.boundaries} non-Nat values refused by name at every real entry point (step, replay, attempt, consumable, checkCorpus); 2^53 arithmetic refused, never rounded`, ok: !nat.problems.length });
  problems.push(...nat.problems);
  // the system level
  const sys = checkSystem(core, corpus);
  (sys.asserted || new Set()).forEach(x => asserted.add(x));
  rows.push({ item: `system: ${sys.transitions} multi-AID transitions (${sys.accepted || 0} accepted, T8 shown on ${sys.t8Shown || 0}, ${sys.nonRegisterShown || 0} non-registration)`, ok: !sys.problems.length });
  problems.push(...sys.problems);
  // reason coverage
  const missing = core.REASONS.filter(r => !asserted.has(r));
  rows.push({ item: `refusal reasons asserted ${asserted.size}/${core.REASONS.length}`, ok: !missing.length });
  if (missing.length) problems.push('refusal reasons never asserted: ' + missing.join(', '));
  const unknown = [...asserted].filter(r => !core.REASONS.includes(r));
  if (unknown.length) problems.push('scenarios assert reasons the core cannot produce: ' + unknown.join(', '));
  const dumb = core.REASONS.filter(r => typeof core.explain({ ok: false, reason: r, action: 'close', pre: 'absent', field: 'x', slot: 0, now: 0 }, core.newSession({ D: 1, B: 1, P: 1, W: 1 })) !== 'string');
  if (dumb.length) problems.push('reasons without explanation: ' + dumb.join(', '));
  const bare = core.THEOREMS.filter(t => !t.plain || !t.lean || !t.lean.length);
  if (bare.length) problems.push('theorems without plain statement or Lean names: ' + bare.map(t => t.id).join(', '));
  rows.push({ item: `theorem groups ${core.THEOREMS.length} (T11, T13 absent from the Lean)`, ok: core.THEOREMS.length === 14 });
  if (core.THEOREMS.length !== 14) problems.push(`theorem groups: ${core.THEOREMS.length}, expected 14`);
  // reconciliation
  let clausesDoc = null;
  try { clausesDoc = core.parseJsonExact(readFileSync(opts.clauses || CLAUSES, 'utf8')); } catch (e) { problems.push('clauses table unreadable: ' + e.message); }
  if (clausesDoc) {
    const cl = checkClauses(core, clausesDoc, readFileSync(STORIES, 'utf8'), timelines, opts.leanRoot || LEAN_ROOT);
    rows.push({ item: `story reconciliation: ${cl.clauses} clauses, ${cl.anchored} atomic claims anchored in the part of a Lean declaration their kind names, with a semantic tie, ${cl.fragments} story fragments classified; ${cl.hyps} Step guard hypotheses all claimed by a refusal name; ${cl.matrix.length} distinctive clauses exercised`, ok: !cl.problems.length });
    problems.push(...cl.problems);
    if (opts.printMatrix) for (const m of cl.matrix) console.log(`  ${m.hit ? '✓' : '✗'}  ${m.id.padEnd(32)} story ${String(m.story).padStart(2)}  ${m.hit ? m.hit.file + ' step ' + m.hit.step : '—'}  ${m.clause}`);
  }
  // build --check
  if (!opts.skipBuild) {
    try {
      execFileSync(process.execPath, [BUILD, '--check', ...(opts.html ? ['--html', opts.html] : []), ...(opts.core ? ['--core', opts.core] : [])], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      rows.push({ item: 'build --check (core slices, scenarios, corpus, docs copy)', ok: true });
    } catch (e) { rows.push({ item: 'build --check', ok: false }); problems.push('build --check RED: ' + String(e.stdout || '').trim() + ' ' + String(e.stderr || '').trim()); }
  }
  // page smoke
  let html;
  try { html = readFileSync(opts.html || HTML, 'utf8'); } catch (e) { problems.push('page unreadable: ' + e.message); }
  if (html) {
    const s = pageSmoke(core, html);
    rows.push({ item: 'page smoke (minimal DOM: picker, play, evidence, slot, ledger, theme, chart, ?selftest=1)', ok: !s.problems.length });
    problems.push(...s.problems);
  }
  return { rows, problems, steps };
}

function printTable(r) {
  const w = Math.max(...r.rows.map(x => x.item.length));
  for (const row of r.rows) console.log(`${row.ok ? 'PASS' : 'FAIL'}  ${row.item.padEnd(w)}` + (row.steps !== undefined ? `  steps=${row.steps} exhibits=${row.exhibits}` : ''));
  console.log(`${r.problems.length ? 'RED' : 'GREEN'}: ${r.rows.length} items, ${r.steps} story steps replayed` + (r.problems.length ? `, ${r.problems.length} problems` : ''));
  r.problems.forEach(p => console.error(' - ' + p));
}

/* --- selftest: negative controls, then GREEN ---------------------------- */

async function selftest(work) {
  const coreText = readFileSync(CORE, 'utf8');
  const htmlText = readFileSync(HTML, 'utf8');
  const mutant = (name, edits) => {
    let t = coreText;
    for (const [needle, repl] of edits) { if (!t.includes(needle)) throw new Error(`selftest ${name}: needle not found: ${needle.slice(0, 60)}`); t = t.replace(needle, repl); }
    const p = join(work, name + '.mjs'); writeFileSync(p, t); return p;
  };
  const scenariosCopy = (edit) => { const d = join(work, 'sc-' + Math.random().toString(36).slice(2)); mkdirSync(d, { recursive: true }); cpSync(SCENARIOS, d, { recursive: true }); edit(d); return d; };
  const topUp = "const pool2 = natAdd(l.pool, a.topUp.x); if (pool2 === null) return refuse('invalid-nat', 'pool');";
  const withClauses = (name, edit) => { const j = JSON.parse(readFileSync(CLAUSES, 'utf8')); edit(j); const p = join(work, name); writeFileSync(p, JSON.stringify(j)); return { clauses: p, skipBuild: true }; };
  const controls = [
    { name: 'scenario with a flipped expectation', expect: /expected ok=false, got ok=true/,
      make: () => ({ scenarios: scenariosCopy(d => { const f = join(d, '02-hal-lands-and-is-paid.json'); const sc = JSON.parse(readFileSync(f, 'utf8')); sc.steps[3].expect.ok = false; sc.steps[3].expect.reason = 'no-quorum'; writeFileSync(f, JSON.stringify(sc)); }), skipBuild: true }) },
    { name: 'core guard flipped: close enabled while poisoned', expect: /expected ok=false, got ok=true|theorem VIOLATED: .*T(16|4|7)/,
      make: () => ({ core: mutant('m-close', [["if (state.present.l.poisoned) return refuse('poisoned');\n      return some({ refund: payment(l.refundTo, l.dreg, l.b, l.pool) }, 'gone');", "return some({ refund: payment(l.refundTo, l.dreg, l.b, l.pool) }, 'gone');"]]), skipBuild: true }) },
    { name: 'theorem property seeded to lie: T6 conservation on the pool', expect: /theorem VIOLATED: .*T6/,
      make: () => ({ core: mutant('m-t6', [['const poolOk = big(held(pre).pool) + big(f.poolIn) ===', 'const poolOk = big(held(pre).pool) + big(f.poolIn) + 1n ===']]), skipBuild: true }) },
    { name: 'page with the story picker removed', expect: /no #story-picker|picker lists|page raised on load/,
      make: () => { const p = join(work, 'page-m1.html'); writeFileSync(p, htmlText.replace('id="story-picker"', 'id="story-pickr"')); return { html: p, skipBuild: true }; } },
    { name: 'core that rounds at 2^53 (isNat relaxed, sum unguarded)', expect: /isNat accepts 9007199254740992|accepted a top-up .* T6\/T14 flagged|precision/,
      make: () => ({ core: mutant('m-nat', [["const isNat = v => typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;", "const isNat = v => typeof v === 'number' && Number.isInteger(v) && v >= 0;"],
        ['const natAdd = (a, b) => { const s = a + b; return isNat(s) && BigInt(a) + BigInt(b) === BigInt(s) ? s : null; };', 'const natAdd = (a, b) => a + b;']]), skipBuild: true }) },
    { name: 'step skips the state and evidence validation (the helper stays; the real boundary is open)', expect: /step topUp 0 on a live state with sn=9007199254740992: expected invalid-nat\/sn, got ok/,
      make: () => ({ core: mutant('m-step-boundary', [["  const sv = validateState(state); if (sv) return refuse(sv.reason, sv.field);\n  const ev = validateEnv(env); if (ev) return refuse(ev.reason, ev.field);\n  const a = na.action, kind = na.kind;", "  const a = na.action, kind = na.kind;"]]), skipBuild: true }) },
    { name: 'replay skips its own boundary (a corrupted origin with no steps passes)', expect: /replay with no steps from a live state with sn=9007199254740992: expected invalid-nat\/sn, got ok/,
      make: () => ({ core: mutant('m-replay-boundary', [["  const sv = validateState(state); if (sv) return refuse(null, sv.reason, sv.field);\n  const ev = validateEnv(env); if (ev) return refuse(null, ev.reason, ev.field);\n", ""]]), skipBuild: true }) },
    { name: 'consumable reads a non-state (verdict on a 2^53 bornAt)', expect: /consumable on a live state with bornAt=9007199254740992: expected verdict invalid-nat\/bornAt, got/,
      make: () => ({ core: mutant('m-consumable-boundary', [["  const sv = validateState(state); if (sv) return refused(sv.reason, sv.field);\n  const l = liveOf(state);", "  const l = liveOf(state);"]]), skipBuild: true }) },
    { name: 'the state boundary accepts two constructors at once and strangers beside one', expect: /step on non-state .*"convicted".*"present".*: expected invalid-state\/convicted, got ok/,
      make: () => ({ core: mutant('m-state-ctor', [["  const stranger = keys.find(x => !STATE_CTORS.includes(x));\n  if (stranger !== undefined) return bad('invalid-state', stranger, `${stranger} is not a constructor of State`);\n  if (keys.length !== 1) return bad('invalid-state', keys.length ? keys[1] : 'state', keys.length ? `${keys[0]} and ${keys[1]} at once: a state is one constructor` : 'unknown state shape');\n  const k = keys[0];", "  const k = keys.find(x => STATE_CTORS.includes(x)) || 'state';"]]), skipBuild: true }) },
    { name: 'the trace verifier validates inputs only, so a Lean-side result beyond the bound is a parity difference', expect: /checkCorpus on a corpus with grid cell result state pool=9007199254740992: no invalid-nat\/pool reason/,
      make: () => ({ core: mutant('m-corpus-results', [["  const badResult = (where, r) => { if (r === null) return false;", "  const badResult = (where, r) => { if (true) return false;"]]), skipBuild: true }) },
    { name: 'the trace verifier replays a corrupted corpus cell without refusing it by name', expect: /checkCorpus on a corpus with grid state \d+ pool=9007199254740992(: no invalid-nat\/pool reason| threw instead of refusing)/,
      make: () => ({ core: mutant('m-corpus-boundary', [["  if (reasons.length) return { applied, refused, cons, theoremChecks, storyCells: 0, reasons };\n", "  reasons.length = 0;\n"]]), skipBuild: true }) },
    { name: 'wrong transition: top-up adds one more (T7 must red against the Lean cell)', expect: /theorem VIOLATED: .*T7 \(.*differs from Lean/,
      make: () => ({ core: mutant('m-t7', [[topUp, "const pool2 = natAdd(l.pool, a.topUp.x + 1); if (pool2 === null) return refuse('invalid-nat', 'pool');"]]), skipBuild: true }) },
    { name: 'registry drops an unrelated AID (T8 must red on the system generator)', expect: /theorem VIOLATED: .*T8 \(.*registry lost an AID|T8 \(.*registry changed/,
      make: () => ({ core: mutant('m-t8', [["const registry = res.ok && kind === 'register' ? [...s.registry, aid] : s.registry;", "const registry = res.ok && kind === 'register' ? [...s.registry, aid] : (res.ok ? [aid] : s.registry);"]]), skipBuild: true }) },
    { name: 'transition that reads W (differs at W = 2; T9 must red)', expect: /theorem VIOLATED: .*T9 \(the transition read W/,
      make: () => ({ core: mutant('m-t9', [[topUp, "const pool2 = natAdd(l.pool, a.topUp.x + (p.W === 2 ? 1 : 0)); if (pool2 === null) return refuse('invalid-nat', 'pool');"]]), skipBuild: true }) },
    { name: 'a story clause dropped from the reconciliation table', expect: /unclassified fragment/,
      make: () => { const j = JSON.parse(readFileSync(CLAUSES, 'utf8')); j.clauses = j.clauses.filter(c => !(c.story === 1 && /inception parses/.test(c.clause))); const p = join(work, 'clauses-m.json'); writeFileSync(p, JSON.stringify(j)); return { clauses: p, skipBuild: true }; } },
    { name: "the auditor's survivor: the inception clause re-anchored to Action.actor, an existing but unrelated declaration", expect: /story 1 clause «the inception parses and self-addresses»: .*not Action\.actor/,
      make: () => withClauses('clauses-survivor.json', j => { const c = j.clauses.find(c => c.story === 1 && /inception parses/.test(c.clause)); Object.assign(c, { class: 'guard', decl: 'Action.actor', text: '| .register .. => .anyone', match: { ok: true, kind: 'register' } }); delete c.note; }) },
    { name: 'a reason row re-anchored to another constructor that carries the same text (hpool → rotateKeepUnpaid/hnopay)', expect: /pool-covers-premium is decided by Step\.freeze, not by Step\.rotateKeepUnpaid/,
      make: () => withClauses('clauses-hnopay.json', j => { const c = j.clauses.find(c => c.story === 3 && /below `P`/.test(c.clause)); c.decl = 'Step.rotateKeepUnpaid'; c.hyp = 'hnopay'; }) },
    { name: 'a text that exists in the file but outside the named hypothesis', expect: /«env\.quorum l\.epoch = true» is not inside Step\.freeze\/hpool/,
      make: () => withClauses('clauses-outside.json', j => { const c = j.clauses.find(c => c.story === 3 && /below `P`/.test(c.clause)); c.text = 'env.quorum l.epoch = true'; }) },
    { name: "the auditor's survivor: story 3's payment claim re-tied to the post-state text inside the same Step.freeze", expect: /story 3 clause «Then it pays `B` to Hal»: «\(\.present \{ l with b := 0 \}\)» is not inside the flow of Step\.freeze/,
      make: () => withClauses('clauses-survivor-2.json', j => { const c = j.clauses.find(c => c.story === 3 && /pays `B` to Hal/.test(c.clause)); c.text = '(.present { l with b := 0 })'; }) },
    { name: 'a payment claim whose text is in the flow but does not start at a paying field', expect: /a payment claim's text starts at the flow field that pays it/,
      make: () => withClauses('clauses-payfield.json', j => { const c = j.clauses.find(c => c.story === 3 && /pays `B` to Hal/.test(c.clause)); c.text = 'b := p.B'; }) },
    { name: 'an untouched-except claim naming the wrong field (story 3: the freeze updates b, the claim says pool)', expect: /the post-state of Step\.freeze updates b, the claim says pool/,
      make: () => withClauses('clauses-updates.json', j => { const c = j.clauses.find(c => c.story === 3 && /leaves the datum untouched/.test(c.clause)); c.updates = ['pool']; }) },
    { name: 'a guard claim moved out of its hypothesis into the flow', expect: /a guard claim names the hypothesis \(hyp\) it lives in/,
      make: () => withClauses('clauses-guard-flow.json', j => { const c = j.clauses.find(c => c.story === 3 && /below `P`/.test(c.clause)); delete c.hyp; c.text = 'hunter := some { addr := payee, b := p.B }'; }) },
    { name: 'a refusal claim whose story never refuses for that reason', expect: /no step of story 3's scenario is refused pool-covers-premium/,
      make: () => withClauses('clauses-refusal.json', j => { const c = j.clauses.find(c => c.story === 3 && /below `P`/.test(c.clause)); c.kind = 'refusal'; }) },
    { name: 'a payment claim tied by a refusal name instead of a step', expect: /a payment claim ties by match, not by reason/,
      make: () => withClauses('clauses-kind-tie.json', j => { const c = j.clauses.find(c => c.story === 3 && /pays `B` to Hal/.test(c.clause)); delete c.match; c.reason = 'freeze-bond-missing'; }) },
    { name: 'a step tie whose scenario step goes through another constructor', expect: /goes through Step\.freeze, not Step\.rotateKeepPaid/,
      make: () => withClauses('clauses-ctor.json', j => { const c = j.clauses.find(c => c.story === 3 && /pays `B` to Hal/.test(c.clause)); c.decl = 'Step.rotateKeepPaid'; c.text = 'hunter := some { addr := payee, pool := p.P }'; }) },
    { name: 'a clause the story does not contain', expect: /clause «that the pool is below `Q`» does not occur in the story/,
      make: () => withClauses('clauses-absent.json', j => { const c = j.clauses.find(c => c.story === 3 && /below `P`/.test(c.clause)); c.clause = 'that the pool is below `Q`'; }) },
    { name: 'a Step guard hypothesis renamed in the Lean (scratch copy: hpool → hpoolx) that no refusal name claims', expect: /Step\.freeze\/hpoolx .* is a guard the refusal names do not claim|Step\.freeze .* has no binder hpool/,
      make: () => { const root = join(work, 'lean-root'); mkdirSync(join(root, 'lean', 'CardanoKeri'), { recursive: true }); for (const f of ['Checkpoint.lean', 'CheckpointGoals.lean']) { let s = readFileSync(join(LEAN_ROOT, 'lean', 'CardanoKeri', f), 'utf8'); if (f === 'Checkpoint.lean') { if (!s.includes('(hpool : l.pool < p.P)')) throw new Error('selftest: hpool binder not found'); s = s.replace('(hpool : l.pool < p.P)', '(hpoolx : l.pool < p.P)'); } writeFileSync(join(root, 'lean', 'CardanoKeri', f), s); } return { leanRoot: root, skipBuild: true }; } },
    { name: 'a distinctive scenario step dropped (conviction from a poisoned state)', expect: /distinctive clause «convict-from-poisoned».*not exercised/,
      make: () => ({ scenarios: scenariosCopy(d => { const f = join(d, '09-cora-convicts.json'); const sc = JSON.parse(readFileSync(f, 'utf8')); sc.steps.splice(1, 1); sc.steps.forEach(s => { delete s.expect.exhibits; delete s.expect.verdict; }); writeFileSync(f, JSON.stringify(sc)); }), skipBuild: true }) },
  ];
  for (const c of controls) {
    const opts = c.make();
    const r = await runSuite(opts);
    if (!r.problems.length) { console.error(`SELFTEST RED: control «${c.name}» ACCEPTED by the gate`); return 1; }
    const text = r.problems.join('\n');
    if (!c.expect.test(text)) { console.error(`SELFTEST RED: «${c.name}» failed for the wrong reason:\n${text.slice(0, 900)}`); return 1; }
    console.log(`negative control «${c.name}»: RED as expected — ${text.split('\n').find(l => c.expect.test(l)).slice(0, 160)}`);
  }
  const green = await runSuite({});
  printTable(green);
  if (green.problems.length) { console.error('SELFTEST RED: production does not return GREEN'); return 1; }
  console.log(`selftest GREEN: ${controls.length} negative controls RED for the expected reason, then production GREEN`);
  return 0;
}

const work = mkdtempSync(join(tmpdir(), 'ck-scenario-gate-'));
let code = 1;
try {
  if (process.argv.includes('--clauses-md')) {
    console.log(clausesMarkdown(JSON.parse(readFileSync(CLAUSES, 'utf8')))); code = 0;
  } else if (process.argv.includes('--selftest')) code = await selftest(work);
  else {
    const r = await runSuite({ core: argPath('--core'), html: argPath('--html'), scenarios: argPath('--scenarios'), clauses: argPath('--clauses'),
      skipBuild: process.argv.includes('--skip-build'), printMatrix: process.argv.includes('--matrix') });
    printTable(r);
    code = r.problems.length ? 1 : 0;
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
process.exit(code);
