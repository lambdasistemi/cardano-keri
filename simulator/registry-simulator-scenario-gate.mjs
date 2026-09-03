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
  const exhibited = new Set(), asserted = new Set(); let steps = 0;
  const ids = [];
  for (const f of files) {
    const sc = JSON.parse(readFileSync(join(scenDir, f), 'utf8'));
    ids.push(sc.id);
    const r = core.checkScenario(sc, f, corpus);
    steps += r.stepsRun; r.exhibited.forEach(x => exhibited.add(x)); r.asserted.forEach(x => asserted.add(x));
    row(`story ${sc.id} ${sc.slug}`, r.problems.length === 0, r.problems.length ? r.problems.join(' | ') : `${r.stepsRun} steps`);
  }
  row('exactly the fifteen stories', ids.length === N_STORIES && [...Array(N_STORIES).keys()].every(i => ids.includes(i + 1)), `ids ${ids.join(',')}`);
  const missingT = core.THEOREMS.map(t => t.id).filter(id => !exhibited.has(id));
  row('every theorem exhibited by some story', missingT.length === 0, missingT.length ? 'missing ' + missingT.join(', ') : `${core.THEOREMS.length} theorems`);
  const missingR = Object.values(core.REASONS).filter(r => !r.startsWith('invalid') && !asserted.has(r));
  row('every refusal reason asserted by some story', missingR.length === 0, missingR.length ? 'missing ' + missingR.join(', ') : `${asserted.size} reasons`);
  row('the corpus is the fifteen stories, six traces and the grid', Array.isArray(corpus.stories) && corpus.stories.length === N_STORIES && corpus.traces.length === 6 && corpus.grid.cells.length > 0, `${(corpus.stories || []).length} stories, ${(corpus.traces || []).length} traces, ${corpus.grid ? corpus.grid.cells.length : 0} grid cells`);
  const cc = core.checkCorpus(corpus);
  row('the Lean corpus replays through the core', cc.ok, cc.ok ? `${cc.cells} cells, ${cc.applied} applied, ${cc.refused} refused` : cc.reasons.slice(0, 3).join(' | '));

  // 3. exact Nat and shapes at every entry point
  {
    const P = { D: 10, tip: 1, process: 5, retract: 5 };
    const S0 = core.initSys(7);
    const bads = [2 ** 53, -1, 1.5, '5', NaN, Infinity, null, undefined, true];
    const errs = [];
    for (const v of bads) {
      const tagv = typeof v === 'string' ? JSON.stringify(v) : String(v);
      if (core.isNat(v)) errs.push(`isNat accepts ${tagv}`);
      for (const k of ['D', 'tip', 'process', 'retract']) if (core.validateParams({ ...P, [k]: v }) === null) errs.push(`params accept ${k}=${tagv}`);
      for (const k of ['gen', 'plugin', 'nextReq']) { const r = core.step(P, core.emptyEnv(), { contribute: { aid: 1, owner: 1, submittedAt: 0 } }, 0, { ...S0, [k]: v }); if (r.ok || r.reason !== 'invalid-nat' || r.field !== k) errs.push(`state ${k}=${tagv} not refused invalid-nat/${k}`); }
      for (const k of ['root', 'live', 'tomb']) { const r = core.step(P, core.emptyEnv(), { contribute: { aid: 1, owner: 1, submittedAt: 0 } }, 0, { ...S0, [k]: [v] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`state ${k}=[${tagv}] not refused`); }
      const r1 = core.step(P, core.emptyEnv(), { contribute: { aid: v, owner: 1, submittedAt: 0 } }, 0, S0); if (r1.ok || r1.reason !== 'invalid-nat') errs.push(`action aid=${tagv} not refused`);
      const r2 = core.step(P, core.emptyEnv(), { contribute: { aid: 1, owner: 1, submittedAt: 0 } }, v, S0); if (r2.ok || r2.reason !== 'invalid-nat' || r2.field !== 'now') errs.push(`now=${tagv} not refused`);
      const r3 = core.step(P, { ...core.emptyEnv(), inception: [v] }, { contribute: { aid: 1, owner: 1, submittedAt: 0 } }, 0, S0); if (r3.ok || r3.reason !== 'invalid-nat') errs.push(`evidence inception=[${tagv}] not refused`);
      const r4 = core.step(P, core.emptyEnv(), { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: v, do: 'process' }] } }, 0, S0); if (r4.ok || r4.reason !== 'invalid-nat') errs.push(`batch id=${tagv} not refused`);
      const r5 = core.replay(P, core.emptyEnv(), v, S0, []); if (r5.ok || r5.reason !== 'invalid-nat') errs.push(`replay t0=${tagv} not refused`);
    }
    const shapes = [[{ bogus: 1 }, 'invalid-state'], [null, 'invalid-state'], [{ ...S0, extra: 1 }, 'invalid-state'], [{ ...S0, requests: [{ id: 0, aid: 1, owner: 1 }] }, 'invalid-nat']];
    for (const [st, want] of shapes) { const r = core.step(P, core.emptyEnv(), { contribute: { aid: 1, owner: 1, submittedAt: 0 } }, 0, st); if (r.ok || r.reason !== want) errs.push(`shape ${JSON.stringify(st)} gave ${r.reason}, expected ${want}`); }
    for (const [a, want] of [[null, 'invalid-action'], [{ contribute: { aid: 1 } }, 'invalid-nat'], [{ fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'burn' }] } }, 'invalid-action'], [{ rotate: {} }, 'invalid-action'], [{ close: { aid: 1 }, convict: { aid: 1 } }, 'invalid-action']]) {
      const r = core.step(P, core.emptyEnv(), a, 0, S0); if (r.ok || r.reason !== want) errs.push(`action ${JSON.stringify(a)} gave ${r.reason}, expected ${want}`);
    }
    for (const [e, want] of [[null, 'invalid-evidence'], [{ inception: 'x' }, 'invalid-evidence'], [{ ...core.emptyEnv(), bogus: [] }, 'invalid-evidence']]) {
      const r = core.step(P, e, { contribute: { aid: 1, owner: 1, submittedAt: 0 } }, 0, S0); if (r.ok || r.reason !== want) errs.push(`evidence ${JSON.stringify(e)} gave ${r.reason}, expected ${want}`);
    }
    if (core.validateParams({ ...P, D: 0 }) === null || core.validateParams({ ...P, D: 0 }).reason !== 'invalid-params') errs.push('zero bond accepted');
    row('exact Nat and shapes refused by name at every entry point', errs.length === 0, errs.length ? errs.slice(0, 4).join(' | ') : `${bads.length} bad numbers × every field`);
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
      $('a-c-aid').value = '11'; $('a-c-owner').value = '1'; $('a-c-t').value = '0';
      d.querySelector('button[data-go="contribute"]').click();
      let s = w.__registrySim.session;
      if (s.state.requests.length !== 1) errs.push('free play: request not posted');
      const sel = d.querySelector('select[data-batch="0"]'); if (!sel) errs.push('free play: no batch selector'); else sel.value = 'process';
      d.querySelector('button[data-go="fold"]').click();
      s = w.__registrySim.session;
      const last = s.history[s.history.length - 1];
      if (!last.result.ok) errs.push(`free play: fold refused (${last.result.reason})`);
      if (!s.state.root.includes(11) || !s.state.live.includes(11)) errs.push('free play: AID 11 not registered after the fold');
      $('a-f-gen').value = '0'; d.querySelector('button[data-go="fold"]').click();
      s = w.__registrySim.session;
      const st = s.history[s.history.length - 1];
      if (st.result.ok || st.result.reason !== 'stale-generation') errs.push(`free play: stale fold not refused (${st.result.ok ? 'applied' : st.result.reason})`);
      if ($('whyline').hidden || !/stale-generation/.test($('whyline').textContent)) errs.push('free play: refusal not shown');
      $('slot-10').click(); if (Number($('slot').textContent) !== 10) errs.push('slot control');
      $('h-first').click(); if (w.__registrySim.session.cursor !== 0) errs.push('history first');
      $('h-next').click(); $('h-last').click(); $('h-prev').click(); $('h-clear').click();
      if (w.__registrySim.session.history.length) errs.push('clear history');
      const before = d.documentElement.getAttribute('data-theme'); $('btn-theme').click();
      if (d.documentElement.getAttribute('data-theme') === before) errs.push('theme toggle');
      if (!/R1/.test($('ledger').innerHTML)) errs.push('ledger not rendered');
      if (w.__errors.length) errs.push('page threw: ' + w.__errors.map(e => e.message).join(' | '));
    } catch (e) { errs.push('page smoke: ' + e.message); }
    row('the page plays every story, self-tests, and free play works under the minimal DOM', errs.length === 0, errs.length ? errs.slice(0, 5).join(' | ') : 'selftest PASS, 15 stories, free play, evidence, slot, history, theme');
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
  await control('flipped-expectation', dir => edit(join(dir, 'scenarios', '04-duplicate-registration.json'), '"reason": "already-registered"', '"reason": "not-in-phase-1"'), /story 4 .*refused already-registered, expected not-in-phase-1/);
  await control('forked-embedded-slice', dir => edit(join(dir, 'registry-simulator.html'), "if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD);", "if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD); /* forked */"), /stale or forked/);
  await control('flipped-guard-absence-proof', dir => { edit(join(dir, 'registry-simulator-core.mjs'), 'if (acc.root.includes(r.aid)) return { ok: false, reason: REASONS.ALREADY_REGISTERED, at: i };', '/* mutant: absence proof removed */'); }, /story 4 .*|story 10 .*|Lean corpus replays/);
  await control('lying-theorem-never-fires', dir => edit(join(dir, 'registry-simulator-core.mjs'), "const f = foldOf(action); if (!f || f.gen === before.gen) return { v: 'n/a' };", "const f = foldOf(action); return { v: 'n/a' };"), /claims to exhibit R7 but it is n\/a/);
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
