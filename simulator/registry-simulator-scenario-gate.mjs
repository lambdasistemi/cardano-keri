#!/usr/bin/env node
/*
 * registry-simulator-scenario-gate.mjs — executable scenario suite over the
 * ONE machine core (registry-simulator-core.mjs), the drift gate for the
 * generated page, and a page smoke under the minimal DOM.
 *
 * Fresh on every run the gate:
 *
 *   1. imports the core MODULE directly and replays every story in
 *      registry-simulator-scenarios/ through `checkScenario`, with the
 *      embedded Lean corpus as the parity oracle: an applied step expected
 *      to be refused (or the wrong refusal reason), a flow or state
 *      mismatch, a theorem failing on any step, a claimed exhibit that does
 *      not hold, or a disagreement with the Lean's verdict is RED;
 *   2. requires exactly the fifteen stories, every theorem exhibited by some
 *      story, every refusal reason asserted by some story;
 *   3. probes exact-Nat and shape refusals at every entry point;
 *   4. runs registry-simulator-build.mjs --check (a stale or forked inlined
 *      copy, story block, corpus block or published copy is RED);
 *   5. executes the page's ACTUAL script under the minimal DOM: the
 *      self-test mode must PASS; the picker must play every story with no
 *      mismatch; free play must accept a request and a fold and refuse a
 *      stale fold; evidence, slot, history and theme controls must work
 *      without a thrown error;
 *   6. prints a table and GREEN only if everything above is green.
 *
 * Usage:
 *   node registry-simulator-scenario-gate.mjs             # production
 *   node registry-simulator-scenario-gate.mjs --selftest  # negative controls
 *
 * --selftest proves the gate can fail, each control RED for its intended
 * reason, on scratch copies (the committed tree is never touched): a flipped
 * story expectation, a forked embedded slice, a flipped core guard (the
 * absence proof removed), a lying theorem property, a broken page control.
 */

import { readFileSync, readdirSync, mkdtempSync, rmSync, writeFileSync, cpSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createWindow } from './checkpoint-simulator-minidom.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const argPath = flag => { const i = process.argv.indexOf(flag); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null; };
const CORE = argPath('--core') || join(HERE, 'registry-simulator-core.mjs');
const HTML = argPath('--html') || join(HERE, 'registry-simulator.html');
const SCEN_DIR = argPath('--scenarios') || join(HERE, 'registry-simulator-scenarios');
const CORPUS = argPath('--corpus') || join(HERE, 'registry-simulator-corpus.json');
const BUILD = join(HERE, 'registry-simulator-build.mjs');
const DOCS = argPath('--docs') || join(HERE, '..', 'docs', 'simulator', 'registry', 'index.html');
const N_STORIES = 15;

async function run({ core: corePath = CORE, html = HTML, scenDir = SCEN_DIR, corpusPath = CORPUS, docs = DOCS, quiet = false } = {}) {
  const core = await import(pathToFileURL(corePath).href + '?t=' + Date.now());
  const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));
  const rows = [], problems = [];
  const row = (what, ok, detail) => { rows.push({ what, ok, detail }); if (!ok) problems.push(`${what}: ${detail}`); };

  // 1–2. the stories through the core, with the Lean corpus as oracle
  const files = readdirSync(scenDir).filter(f => f.endsWith('.json')).sort();
  const exhibited = new Set(), asserted = new Set(); let steps = 0, forks = 0, forkSteps = 0;
  const ids = [];
  for (const f of files) {
    const sc = JSON.parse(readFileSync(join(scenDir, f), 'utf8'));
    ids.push(sc.id);
    const r = core.checkScenario(sc, f, corpus);
    steps += r.stepsRun; r.exhibited.forEach(x => exhibited.add(x)); r.asserted.forEach(x => asserted.add(x));
    const nf = Object.keys(r.forkTimelines || {}).length; forks += nf; forkSteps += Object.values(r.forkTimelines || {}).reduce((n, t) => n + t.length, 0);
    row(`story ${sc.id} ${sc.slug}`, r.problems.length === 0, r.problems.length ? r.problems.join(' | ') : `${r.stepsRun} steps${nf ? `, ${nf} branch${nf > 1 ? 'es' : ''}` : ''}`);
  }
  row('the stories are trees: refused attempts and what-ifs are branches the driver folds', forks > 0 && forkSteps > 0, `${forks} forks, ${forkSteps} fork steps`);
  row('exactly the fifteen stories', ids.length === N_STORIES && [...Array(N_STORIES).keys()].every(i => ids.includes(i + 1)), `ids ${ids.join(',')}`);
  const missingT = core.THEOREMS.map(t => t.id).filter(id => !exhibited.has(id));
  row('every theorem exhibited by some story', missingT.length === 0, missingT.length ? 'missing ' + missingT.join(', ') : `${core.THEOREMS.length} theorems`);
  // Two guards are defence in depth: the invariant makes them unreachable
  // from genesis (a go-request exists only while its leaf is active; a
  // dormant leaf never has a checkpoint). No story can assert them.
  const UNREACHABLE = ['checkpoint-exists', 'not-active'];
  const missingR = Object.values(core.REASONS).filter(r => !r.startsWith('invalid') && !UNREACHABLE.includes(r) && !asserted.has(r));
  row('every reachable refusal reason asserted by some story', missingR.length === 0, missingR.length ? 'missing ' + missingR.join(', ') : `${asserted.size} reasons; ${UNREACHABLE.join(', ')} unreachable by Inv`);
  const corpusForks = (corpus.stories || []).reduce((n, sc) => n + (sc.forks || []).length, 0);
  row('the corpus is the fifteen stories with their forks, six traces and the grid', Array.isArray(corpus.stories) && corpus.stories.length === N_STORIES && corpusForks === forks && corpus.traces.length === 6 && corpus.grid.cells.length > 0, `${(corpus.stories || []).length} stories, ${corpusForks} forks, ${(corpus.traces || []).length} traces, ${corpus.grid ? corpus.grid.cells.length : 0} grid cells`);
  const cc = core.checkCorpus(corpus);
  row('the Lean corpus replays through the core', cc.ok, cc.ok ? `${cc.cells} cells, ${cc.applied} applied, ${cc.refused} refused` : cc.reasons.slice(0, 3).join(' | '));

  // 3. exact Nat and shapes at every entry point
  {
    const P = { D: 10, tip: 1, Mc: 4, Mr: 1, process: 5, retract: 5, W: 3, far: 1000 };
    const S0 = core.initSys(7);
    const bads = [2 ** 53, -1, 1.5, '5', NaN, Infinity, null, undefined, true];
    const errs = [];
    for (const v of bads) {
      const tagv = typeof v === 'string' ? JSON.stringify(v) : String(v);
      if (core.isNat(v)) errs.push(`isNat accepts ${tagv}`);
      for (const k of ['D', 'tip', 'Mc', 'Mr', 'process', 'retract', 'W', 'far']) if (core.validateParams({ ...P, [k]: v }) === null) errs.push(`params accept ${k}=${tagv}`);
      const REG = { contribute: { aid: 1, owner: 1, submittedAt: 0, op: 'register' } };
      for (const k of ['gen', 'plugin', 'nextReq', 'nextToken']) { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, [k]: v }); if (r.ok || r.reason !== 'invalid-nat' || r.field !== k) errs.push(`state ${k}=${tagv} not refused invalid-nat/${k}`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, leaves: [{ aid: v, status: 'convicted' }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`leaf aid=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, leaves: [{ aid: 1, status: { active: v } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`leaf token=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, ckpts: [{ aid: 1, ckpt: { token: 0, k: v, st: 'live' } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`ckpt k=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, ckpts: [{ aid: 1, ckpt: { token: 0, k: 0, st: { parked: v } } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`ckpt parked=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: { goDormant: v } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`request goDormant=${tagv} not refused`); }
      const r1 = core.step(P, core.emptyEnv(), { contribute: { aid: v, owner: 1, submittedAt: 0, op: 'register' } }, 0, S0); if (r1.ok || r1.reason !== 'invalid-nat') errs.push(`action aid=${tagv} not refused`);
      const r2 = core.step(P, core.emptyEnv(), REG, v, S0); if (r2.ok || r2.reason !== 'invalid-nat' || r2.field !== 'now') errs.push(`now=${tagv} not refused`);
      const r3 = core.step(P, { ...core.emptyEnv(), inception: [v] }, REG, 0, S0); if (r3.ok || r3.reason !== 'invalid-nat') errs.push(`evidence inception=[${tagv}] not refused`);
      { const r = core.step(P, { ...core.emptyEnv(), rotationFrom: [[1, v]] }, REG, 0, S0); if (r.ok || r.reason !== 'invalid-nat') errs.push(`evidence rotationFrom=[[1,${tagv}]] not refused`); }
      const r4 = core.step(P, core.emptyEnv(), { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: v, do: 'process' }] } }, 0, S0); if (r4.ok || r4.reason !== 'invalid-nat') errs.push(`batch id=${tagv} not refused`);
      const r5 = core.replay(P, core.emptyEnv(), v, S0, []); if (r5.ok || r5.reason !== 'invalid-nat') errs.push(`replay t0=${tagv} not refused`);
    }
    const REG0 = { contribute: { aid: 1, owner: 1, submittedAt: 0, op: 'register' } };
    const shapes = [[{ bogus: 1 }, 'invalid-state'], [null, 'invalid-state'], [{ ...S0, extra: 1 }, 'invalid-state'], [{ ...S0, requests: [{ id: 0, aid: 1, owner: 1 }] }, 'invalid-nat'],
      [{ ...S0, leaves: [{ aid: 1, status: 'gone' }] }, 'invalid-state'], [{ ...S0, ckpts: [{ aid: 1, ckpt: { token: 0, k: 0, st: 'frozen' } }] }, 'invalid-state'], [{ ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: 'close' }] }, 'invalid-state']];
    for (const [st, want] of shapes) { const r = core.step(P, core.emptyEnv(), REG0, 0, st); if (r.ok || r.reason !== want) errs.push(`shape ${JSON.stringify(st)} gave ${r.reason}, expected ${want}`); }
    for (const [a, want] of [[null, 'invalid-action'], [{ contribute: { aid: 1 } }, 'invalid-nat'], [{ contribute: { aid: 1, owner: 1, submittedAt: 0, op: 'close' } }, 'invalid-action'], [{ fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'burn' }] } }, 'invalid-action'], [{ rotate: {} }, 'invalid-action'], [{ pause: { aid: 1 }, resume: { aid: 1 } }, 'invalid-action']]) {
      const r = core.step(P, core.emptyEnv(), a, 0, S0); if (r.ok || r.reason !== want) errs.push(`action ${JSON.stringify(a)} gave ${r.reason}, expected ${want}`);
    }
    for (const [e, want] of [[null, 'invalid-evidence'], [{ inception: 'x' }, 'invalid-evidence'], [{ ...core.emptyEnv(), bogus: [] }, 'invalid-evidence'], [{ ...core.emptyEnv(), rotationFrom: [[1]] }, 'invalid-evidence']]) {
      const r = core.step(P, e, REG0, 0, S0); if (r.ok || r.reason !== want) errs.push(`evidence ${JSON.stringify(e)} gave ${r.reason}, expected ${want}`);
    }
    // a counter at the bound is a Nat whose successor is not: every successor, sum and product refuses by the field it would write
    {
      const M = core.MAX_NAT, E = core.emptyEnv();
      const want = (label, r, field) => { if (r.ok || r.reason !== 'invalid-nat' || r.field !== field) errs.push(`${label}: got ${r.ok ? 'applied' : r.reason + '/' + r.field}, expected invalid-nat/${field}`); };
      want('nextReq at the bound, contribute', core.step(P, E, REG0, 0, { ...S0, nextReq: M }), 'nextReq');
      const withReq = { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: 'register' }], nextReq: 1 };
      want('nextToken at the bound, a register folds', core.step(P, { ...E, inception: [1] }, { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, 0, { ...withReq, nextToken: M }), 'nextToken');
      want('gen at the bound, a fold', core.step(P, { ...E, inception: [1] }, { fold: { folder: 3, gen: M, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, 0, { ...withReq, gen: M }), 'gen');
      const lateReq = { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: M, op: 'register' }], nextReq: 1 };
      want('submittedAt at the bound, retract', core.step(P, E, { retract: { req: 0 } }, M, lateReq), 'submittedAt+process');
      want('submittedAt at the bound, process', core.step(P, { ...E, inception: [1] }, { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, M, lateReq), 'submittedAt+process');
      const withCk = { ...S0, leaves: [{ aid: 1, status: { active: 0 } }], ckpts: [{ aid: 1, ckpt: { token: 0, k: M, st: 'live' } }], nextToken: 1 };
      want('k at the bound, pause', core.step(P, { ...E, rotationFrom: [[1, M]] }, { pause: { aid: 1 } }, 0, withCk), 'k');
      const parked = { ...withCk, ckpts: [{ aid: 1, ckpt: { token: 0, k: 0, st: { parked: M } } }] };
      want('parked at the bound, reap', core.step(P, E, { reap: { reaper: 6, aid: 1 } }, M, parked), 'parked+W');
      const Q = { D: 2, tip: M - 1, Mc: M, Mr: 1, process: 1, retract: 1, W: 1, far: M };
      if (core.validateParams(Q)) errs.push('params at the bound refused: ' + JSON.stringify(core.validateParams(Q)));
      else {
        want('bond + tip past the bound, contribute', core.step(Q, E, REG0, 0, S0), 'deposited');
        const two = { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: 'register' }, { id: 1, aid: 2, owner: 2, submittedAt: 0, op: 'register' }], nextReq: 2 };
        want('n × tip past the bound, a fold of two rejects', core.step(Q, E, { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'reject' }, { id: 1, do: 'reject' }] } }, 5, two), 'tips');
      }
      // a boundary refusal exhibits no theorem
      const sc = { id: 99, slug: 'boundary', story: 'boundary', params: P, plugin: 7, steps: [{ now: 0, action: REG0, expect: { ok: false, reason: 'invalid-nat' }, exhibits: ['R6'] }], initial: { ...S0, nextReq: M } };
      const r = core.checkScenario(sc, 'boundary', null);
      if (!r.problems.some(p => /claims to exhibit R6 but it is a boundary refusal/.test(p))) errs.push('a boundary refusal was allowed to exhibit a theorem');
    }
    if (core.validateParams({ ...P, D: 0 }) === null || core.validateParams({ ...P, D: 0 }).reason !== 'invalid-params') errs.push('zero bond accepted');
    if (core.validateParams({ ...P, Mc: 1 }) === null || core.validateParams({ ...P, Mc: 1 }).reason !== 'invalid-params') errs.push('a checkpoint that cannot fund its go-request accepted');
    row('exact Nat and shapes refused by name at every entry point, and every successor, sum and product at the bound', errs.length === 0, errs.length ? errs.slice(0, 4).join(' | ') : `${bads.length} bad numbers × every field; 9 results at the bound`);
  }

  // 3b. every executable property reds on a fabricated violation (a lamp that
  // cannot go red is not a check)
  {
    const P = { D: 1000, tip: 2, Mc: 4, Mr: 1, process: 10, retract: 10, W: 5, far: 1000000000 };
    const E = core.emptyEnv();
    const S = (o = {}) => ({ ...core.initSys(7), ...o });
    const leaf = (aid, status) => ({ aid, status });
    const ck = (aid, token, k, st) => ({ aid, ckpt: { token, k, st } });
    const req = (id, aid, owner, submittedAt, op) => ({ id, aid, owner, submittedAt, op });
    const okr = (state, fl = {}) => ({ ok: true, flow: core.flow(fl), state });
    const registered = S({ gen: 1, leaves: [leaf(11, { active: 0 })], ckpts: [ck(11, 0, 0, 'live')], nextReq: 1, nextToken: 1 });
    const fold1 = { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } };
    const V = {
      R1: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, leaves: [leaf(11, { dormant: 0 })] }) },
      R1d: { before: { ...registered, requests: [req(1, 11, 4, 5, 'register')], nextReq: 2 }, action: { fold: { folder: 3, gen: 1, plugin: 7, batch: [{ id: 1, do: 'process' }] } }, now: 6, result: okr(registered, { locked: [{ aid: 11, value: 1000 }], tips: { addr: 3, value: 2 } }) },
      R2: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, leaves: [leaf(11, { active: 0 }), leaf(11, { active: 0 })] }) },
      R3: { before: S({ leaves: [leaf(11, 'convicted')] }), action: { pause: { aid: 11 } }, now: 5, result: okr(S({ leaves: [leaf(11, { active: 0 })] })) },
      R4: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, leaves: [] }) },
      R5: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, plugin: 8 }) },
      R6: { before: registered, action: { contribute: { aid: 12, owner: 2, submittedAt: 5, op: 'register' } }, now: 5, result: okr({ ...registered, gen: 2 }, { deposited: 1002 }) },
      R7: { before: registered, action: { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, now: 5, result: okr(registered) },
      R8: { before: registered, action: { fold: { folder: 3, gen: 1, plugin: 7, batch: [] } }, now: 5, result: okr({ ...registered, gen: 2 }) },
      R9: { before: S({ requests: [req(0, 11, 1, 0, 'register')], nextReq: 1 }), action: { retract: { req: 0 } }, now: 3, result: okr(S({ nextReq: 1 }), { refunds: [{ addr: 1, value: 1002 }] }) },
      R11: { before: S({ requests: [req(0, 11, 1, 0, 'register')], nextReq: 1 }), action: fold1, now: 1, result: okr(registered, { refunds: [{ addr: 1, value: 1000 }], tips: { addr: 3, value: 2 } }) },
      R12: { before: registered, action: { contribute: { aid: 12, owner: 2, submittedAt: 5, op: 'register' } }, now: 5, result: okr({ ...registered, leaves: [leaf(11, { active: 0 }), leaf(12, { active: 1 })] }, { deposited: 1002 }) },
      R13: { before: { ...registered, ckpts: [ck(11, 0, 1, { parked: 5 })] }, action: { reap: { reaper: 6, aid: 11 } }, now: 20, result: okr({ ...registered, ckpts: [ck(11, 0, 1, { parked: 5 })] }, { premium: { addr: 6, value: 1 }, intoRequest: 3 }) },
      R14: { before: registered, action: { convictCkpt: { aid: 11 } }, now: 5, result: okr({ ...registered, ckpts: [ck(11, 0, 0, 'tomb')] }) },
    };
    const errs = [], noControl = [];
    for (const t of core.THEOREMS) {
      const v = V[t.id];
      if (!v) { noControl.push(t.id); continue; }
      const rec = { params: P, env: E, ...v };
      let out; try { out = t.check(rec); } catch (e) { out = { v: 'threw', why: e.message }; }
      if (!out || out.v !== 'fails') errs.push(`${t.id} says ${out ? out.v : 'nothing'} on a fabricated violation`);
    }
    // R10 is structural (the phase functions are exclusive on every request of the
    // record): no record can lie to it; the phases-overlap mutant of --selftest reds it.
    const allowed = ['R10'];
    for (const id of noControl) if (!allowed.includes(id)) errs.push(`no fabricated violation for ${id}`);
    row('every executable property reds on a fabricated violation', errs.length === 0, errs.length ? errs.join(' | ') : `${Object.keys(V).length} fabricated records, each refused by its lamp; R10 by the phases-overlap mutant`);
  }

  // 4. build drift
  let buildOut = '';
  try { buildOut = execFileSync(process.execPath, [BUILD, '--check', '--html', html, '--core', corePath, '--scenarios', scenDir, '--corpus', corpusPath, '--docs', docs], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim(); row('generated page and published copy are current', true, buildOut); }
  catch (e) { row('generated page and published copy are current', false, (e.stderr || e.stdout || String(e)).trim()); }

  // 5. the page under the minimal DOM
  {
    const doc = readFileSync(html, 'utf8');
    const errs = [];
    try {
      const w = createWindow(doc, { search: '?selftest=1' });
      if (w.__errors.length) errs.push('selftest threw: ' + w.__errors.map(e => e.message).join(' | '));
      if (!w.__selftest || !w.__selftest.ok) errs.push('page selftest FAIL: ' + (w.__selftest ? w.__selftest.rows.filter(r => !r.ok).map(r => r.what + ' — ' + r.detail).join(' | ') : 'no result'));
    } catch (e) { errs.push('selftest mode: ' + e.message); }
    try {
      const w = createWindow(doc, {});
      const d = w.document, $ = id => d.getElementById(id);
      if (w.__errors.length) errs.push('init threw: ' + w.__errors.map(e => e.message).join(' | '));
      const opts = [...$('sc-pick').options].slice(1);
      if (opts.length !== N_STORIES) errs.push(`picker has ${opts.length} stories`);
      let mismatches = 0, applied = 0;
      for (const o of opts) {
        $('sc-pick').value = o.value; $('sc-pick').dispatchEvent(new w.Event('change'));
        $('sc-step').click(); $('sc-all').click();
        const s = w.__registrySim.session;
        mismatches += s.history.filter(h => h.mismatch).length; applied += s.history.filter(h => h.result.ok).length;
        if (!$('sc-step').disabled) errs.push(`story ${o.value}: play all did not finish`);
        $('sc-reset').click();
        if (w.__registrySim.session.history.length) errs.push(`story ${o.value}: restart kept history`);
      }
      if (mismatches) errs.push(`${mismatches} story steps disagreed with the page`);
      if (!applied) errs.push('no story step applied');
      $('sc-exit').click();
      if (!$('storybox').hidden) errs.push('leave story did not hide the story box');
      // free play: evidence, request, fold, stale fold, slot, history, theme
      $('ev-aid').value = '11'; $('ev-add').click();
      const cb = d.querySelector('input[data-ev="inception"][data-aid="11"]'); if (!cb) errs.push('no evidence row for AID 11'); else if (!cb.checked) { cb.checked = true; cb.dispatchEvent(new w.Event('change')); }
      $('a-c-op').value = 'register'; $('a-c-aid').value = '11'; $('a-c-owner').value = '1'; $('a-c-t').value = '0';
      d.querySelector('button[data-go="contribute"]').click();
      let s = w.__registrySim.session;
      if (s.state.requests.length !== 1) errs.push('free play: request not posted');
      const sel = d.querySelector('select[data-batch="0"]'); if (!sel) errs.push('free play: no batch selector'); else sel.value = 'process';
      d.querySelector('button[data-go="fold"]').click();
      s = w.__registrySim.session;
      const last = s.history[s.history.length - 1];
      if (!last.result.ok) errs.push(`free play: fold refused (${last.result.reason})`);
      if (core.lookupLeaf(s.state.leaves, 11) === null || core.lookupCkpt(s.state.ckpts, 11) === null) errs.push('free play: AID 11 not registered after the fold');
      const rot = d.querySelector('input[data-ev="rotationFrom"][data-aid="11"][data-k="0"]'); if (!rot) errs.push('free play: no rotation evidence control'); else { rot.checked = true; rot.dispatchEvent(new w.Event('change')); }
      $('a-p-aid').value = '11'; d.querySelector('button[data-go="pause"]').click();
      s = w.__registrySim.session;
      if (!s.history[s.history.length - 1].result.ok) errs.push(`free play: pause refused (${s.history[s.history.length - 1].result.reason})`);
      $('slot-10').click(); $('a-rp-aid').value = '11'; d.querySelector('button[data-go="reap"]').click();
      s = w.__registrySim.session;
      const rp = s.history[s.history.length - 1].result;
      if (!rp.ok || !rp.flow.premium) errs.push(`free play: reap refused after the grace window (${rp.reason})`);
      if (!s.state.requests.some(r => !core.userPostable(r.op))) errs.push('free play: no go-request after the reap');
      $('a-f-gen').value = '0'; d.querySelector('button[data-go="fold"]').click();
      s = w.__registrySim.session;
      const st = s.history[s.history.length - 1];
      if (st.result.ok || st.result.reason !== 'stale-generation') errs.push(`free play: stale fold not refused (${st.result.ok ? 'applied' : st.result.reason})`);
      if ($('whyline').hidden || !/stale-generation/.test($('whyline').textContent)) errs.push('free play: refusal not shown');
      if (Number($('slot').textContent) !== 10) errs.push('slot control');
      $('h-first').click(); if (w.__registrySim.session.cursor !== 0) errs.push('history first');
      $('h-next').click(); $('h-last').click(); $('h-prev').click(); $('h-clear').click();
      if (w.__registrySim.session.history.length) errs.push('clear history');
      const before = d.documentElement.getAttribute('data-theme'); $('btn-theme').click();
      if (d.documentElement.getAttribute('data-theme') === before) errs.push('theme toggle');
      if (!/R1/.test($('ledger').innerHTML)) errs.push('ledger not rendered');
      if (w.__errors.length) errs.push('page threw: ' + w.__errors.map(e => e.message).join(' | '));
    } catch (e) { errs.push('page smoke: ' + e.message); }
    row('the page plays every story, self-tests, and free play works under the minimal DOM', errs.length === 0, errs.length ? errs.slice(0, 5).join(' | ') : 'selftest PASS, 15 stories, free play (register, pause, reap), evidence, slot, history, theme');
  }

  if (!quiet) {
    for (const r of rows) console.log(`${r.ok ? 'ok ' : 'RED'}  ${r.what}${r.detail ? ' — ' + r.detail : ''}`);
    console.log(problems.length ? `RED: ${problems.length} problem(s)` : `GREEN: ${rows.length} checks, ${steps} story steps`);
  }
  return { ok: problems.length === 0, problems, rows };
}

async function selftest() {
  const tmp = mkdtempSync(join(tmpdir(), 'registry-sim-gate-'));
  const controls = [];
  const control = async (name, mutate, expectRe) => {
    const dir = join(tmp, name); mkdirSync(dir);
    for (const f of ['registry-simulator-core.mjs', 'registry-simulator.html', 'registry-simulator-corpus.json', 'checkpoint-simulator-minidom.mjs', 'registry-simulator-build.mjs']) cpSync(join(HERE, f), join(dir, f));
    cpSync(SCEN_DIR, join(dir, 'scenarios'), { recursive: true });
    cpSync(DOCS, join(dir, 'index.html'));
    mutate(dir);
    const r = await run({ core: join(dir, 'registry-simulator-core.mjs'), html: join(dir, 'registry-simulator.html'), scenDir: join(dir, 'scenarios'), corpusPath: join(dir, 'registry-simulator-corpus.json'), docs: join(dir, 'index.html'), quiet: true });
    const red = !r.ok && r.problems.some(p => expectRe.test(p));
    controls.push({ name, red, why: red ? r.problems.find(p => expectRe.test(p)) : (r.ok ? 'stayed GREEN' : 'RED for another reason: ' + r.problems[0]) });
  };
  const edit = (f, from, to) => { const t = readFileSync(f, 'utf8'); if (!t.includes(from)) throw new Error(`control edit: ${from} not found in ${f}`); writeFileSync(f, t.replace(from, to)); };
  await control('flipped-expectation', dir => edit(join(dir, 'scenarios', '04-duplicate-registration.json'), '"reason":"already-registered"', '"reason":"not-in-phase-1"'), /story 4 .*refused already-registered, expected not-in-phase-1/);
  await control('forked-embedded-slice', dir => edit(join(dir, 'registry-simulator.html'), "if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD);", "if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD); /* forked */"), /stale or forked/);
  await control('flipped-guard-absence-proof', dir => { edit(join(dir, 'registry-simulator-core.mjs'), 'if (leaf !== null) return { ok: false, reason: REASONS.ALREADY_REGISTERED };', '/* mutant: absence proof removed */'); }, /story 4 .*|story 12 .*|Lean corpus replays/);
  await control('lying-theorem-never-fires', dir => edit(join(dir, 'registry-simulator-core.mjs'), "const f = foldOf(action); if (!f || f.gen === before.gen) return { v: 'n/a' };", "const f = foldOf(action); return { v: 'n/a' };"), /claims to exhibit R7 but it is n\/a/);
  await control('fork-expectation-flipped', dir => edit(join(dir, 'scenarios', '13-convict-dormant.json'), '"reason":"no-duplicity-proof"', '"reason":"not-dormant"'), /story 13 .*fconvict-without-proof\.step 1: refused no-duplicity-proof, expected not-dormant/);
  await control('overflow-unchecked', dir => edit(join(dir, 'registry-simulator-core.mjs'), 'const r = a + b; if (r > MAX_NAT) throw new NatOverflow(field); return r;', 'return a + b;'), /nextReq at the bound, contribute: got applied/);
  await control('lamp-that-cannot-go-red', dir => edit(join(dir, 'registry-simulator-core.mjs'), "      if (result.ok) {\n        const s = result.state;\n        if (lookupCkpt(s.ckpts, aid) !== null)", "      if (false) {\n        const s = result.state;\n        if (lookupCkpt(s.ckpts, aid) !== null)"), /R13 says holds on a fabricated violation/);
  await control('phases-overlap', dir => edit(join(dir, 'registry-simulator-core.mjs'), 'function inPhase2(p, r, now) { return phase1End(p, r) <= now && now < phase2End(p, r); }', 'function inPhase2(p, r, now) { return now < phase2End(p, r); }'), /theorem R10 fails/);
  await control('broken-page-control', dir => edit(join(dir, 'registry-simulator.html'), "$('sc-all').addEventListener('click', () => { while (storyStep()) {} });", "$('sc-all').addEventListener('click', () => {});"), /play all did not finish/);
  rmSync(tmp, { recursive: true, force: true });
  for (const c of controls) console.log(`${c.red ? 'RED (intended)' : 'CONTROL FAILED'}  ${c.name} — ${c.why}`);
  const all = controls.every(c => c.red);
  console.log(all ? `controls: ${controls.length}/${controls.length} red for the intended reason` : 'controls: some did not go red');
  return all;
}

const main = async () => {
  if (process.argv.includes('--selftest')) {
    const ok = await selftest();
    if (!ok) process.exit(1);
    const r = await run();
    process.exit(r.ok ? 0 : 1);
  }
  const r = await run();
  process.exit(r.ok ? 0 : 1);
};
main().catch(e => { console.error('RED: gate crashed — ' + e.stack); process.exit(1); });
