#!/usr/bin/env node
/*
 * checkpoint-simulator-scenario-gate.mjs — executable story suite over the
 * checkpoint core, plus the page smoke.
 *
 * Fresh on every run:
 *   1. imports the core module (the same file whose slices the build
 *      script inlines byte-for-byte into the page; step 4 proves that);
 *   2. loads every scenario in checkpoint-simulator-scenarios/ — exactly the
 *      fifteen stories, each replayed step by step through the core's
 *      session: refusal reasons, post-states, flows, the consumer verdict
 *      and the set of theorems each step exhibits are compared with the
 *      scenario's expectations, and EVERY theorem property T1–T16 must hold
 *      on every step (exhibited or not);
 *   3. requires every refusal reason the core can produce to be asserted
 *      by at least one scenario step, and every reason to have a
 *      story-vocabulary explanation;
 *   4. runs checkpoint-simulator-build.mjs --check (a stale or forked
 *      inlined copy, or a stale docs/ copy, is RED);
 *   5. loads the page under a minimal DOM with real event/value semantics
 *      (checkpoint-simulator-minidom.mjs) and drives the controls it
 *      asserts: the page loads without error, the picker lists fifteen
 *      stories, selecting one plays it to the end, evidence rows can be
 *      added and removed, the slot control changes the consumer verdict,
 *      the page's own theorem ledger agrees with the core, and the page
 *      makes no network reference;
 *   6. prints a table and exits non-zero on anything.
 *
 * Usage:
 *   node simulator/checkpoint-simulator-scenario-gate.mjs             # production
 *   node simulator/checkpoint-simulator-scenario-gate.mjs --selftest  # negative controls
 *
 * --selftest proves the gate can fail for the right reason: a scenario
 * with a flipped expectation, a core with a guard flipped (close while
 * poisoned), a core with a theorem property seeded to lie, and a page with
 * the picker removed — each RED for its intended reason — then GREEN.
 */

import { readFileSync, writeFileSync, readdirSync, mkdtempSync, mkdirSync,
  rmSync, cpSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createWindow } from './checkpoint-simulator-minidom.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const argPath = flag => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const CORE = argPath('--core') || join(HERE, 'checkpoint-simulator-core.mjs');
const HTML = argPath('--html') || join(HERE, 'checkpoint-simulator.html');
const SCENARIOS = argPath('--scenarios') || join(HERE, 'checkpoint-simulator-scenarios');
const BUILD = join(HERE, 'checkpoint-simulator-build.mjs');

/* --- one scenario: the core's own checker (shared with the page's selftest) --- */

function runScenario(core, sc, file) {
  const r = core.checkScenario(sc, file);
  return { problems: r.problems, asserted: new Set(r.asserted), exhibitedIds: new Set(r.exhibited), stepsRun: r.stepsRun };
}

/* --- page smoke under the minimal DOM ---------------------------------- */

function pageSmoke(core, html) {
  const problems = [];
  let win;
  try {
    win = createWindow(html, { search: '' });
  } catch (e) {
    return { problems: ['page failed to load: ' + (e && e.stack || e)] };
  }
  const doc = win.document;
  const $ = sel => doc.querySelector(sel);
  const errs = win.__errors || [];
  if (errs.length) problems.push('page raised on load: ' + errs.map(String).join(' | '));

  // no network reference
  const net = html.match(/\b(src|href)\s*=\s*"(https?:)?\/\//g);
  if (net) problems.push('page references the network: ' + net.slice(0, 3).join(', '));

  // picker lists fifteen stories
  const picker = $('#story-picker');
  if (!picker) { problems.push('no #story-picker'); return { problems }; }
  const opts = picker.querySelectorAll('option').filter(o => o.value !== '');
  if (opts.length !== 15) problems.push(`picker lists ${opts.length} stories, expected 15`);

  // selecting one plays it: pick story 3 and step to the end
  const pick = n => {
    picker.value = String(n);
    picker.dispatchEvent(win.makeEvent('change'));
  };
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

  // theorem ledger: on the last accepted step (the freeze) the page's rows light T15
  const okChips = doc.querySelectorAll('#history-strip .hist-chip.ok');
  if (!okChips.length) problems.push('no accepted chip in the history strip');
  else okChips[okChips.length - 1].dispatchEvent(win.makeEvent('click'));
  const lit = doc.querySelectorAll('#ledger .thm.lit').map(e => e.dataset.id).sort();
  if (!lit.includes('T15')) problems.push(`ledger on the freeze step lights [${lit}], expected T15 among them`);
  if (!/frozen/i.test(($('#state-name') || {}).textContent || '')) problems.push('the last accepted chip does not show Frozen');
  while (next && !next.disabled && guard++ < 50) next.dispatchEvent(win.makeEvent('click'));
  const broken = doc.querySelectorAll('#ledger .thm.broken');
  if (broken.length) problems.push('ledger shows broken rows: ' + broken.map(e => e.dataset.id).join(','));

  // the history strip goes back: one step back stays Frozen (the last story step only reads), the start is Absent
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
  if (!actorBtn) problems.push('no anyone actor chip');
  else actorBtn.dispatchEvent(win.makeEvent('click'));
  const regBtn = doc.querySelector('.act[data-kind="register"]');
  if (!regBtn) problems.push('no register action for anyone');
  else if (regBtn.disabled) problems.push('register is disabled on an absent checkpoint');
  else regBtn.dispatchEvent(win.makeEvent('click'));
  const goBtn = $('#act-submit');
  if (goBtn) goBtn.dispatchEvent(win.makeEvent('click'));
  const v0 = ($('#verdict') || {}).textContent || '';
  if (!/juvenile|young|born/i.test(v0)) problems.push(`after register the verdict says «${v0.slice(0, 80)}», expected juvenile`);

  // slot control changes the verdict
  const slotInput = $('#slot-input');
  if (!slotInput) problems.push('no #slot-input');
  else {
    slotInput.value = '10';
    slotInput.dispatchEvent(win.makeEvent('change'));
    const v1 = ($('#verdict') || {}).textContent || '';
    if (!/consumable/i.test(v1) || /not consumable/i.test(v1))
      problems.push(`after moving the slot to 10 the verdict says «${v1.slice(0, 80)}», expected consumable`);
    // moving backwards is refused
    slotInput.value = '3';
    slotInput.dispatchEvent(win.makeEvent('change'));
    if (($('#slot-now') || {}).textContent !== '10') problems.push('the slot control went backwards');
  }

  // evidence rows can be added and removed
  const evKind = $('#ev-kind');
  const evAdd = $('#ev-add');
  if (!evKind || !evAdd) problems.push('no evidence controls');
  else {
    evKind.value = 'rotationTo';
    evKind.dispatchEvent(win.makeEvent('change'));
    $('#ev-a').value = '0'; $('#ev-b').value = '0'; $('#ev-c').value = '1';
    evAdd.dispatchEvent(win.makeEvent('click'));
    const rows = doc.querySelectorAll('#ev-rows .ev-row');
    if (rows.length !== 1) problems.push(`evidence rows after add: ${rows.length}, expected 1`);
    // Hal can now land the rotation
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
  // theme toggle exists and flips
  const theme = $('#btn-theme');
  if (!theme) problems.push('no #btn-theme');
  else {
    const before = doc.documentElement.dataset.theme || '';
    theme.dispatchEvent(win.makeEvent('click'));
    if ((doc.documentElement.dataset.theme || '') === before) problems.push('theme toggle did nothing');
  }
  // the chart drew
  const canvas = $('#value-chart');
  if (!canvas) problems.push('no #value-chart canvas');
  else if (!canvas.__ctx || canvas.__ctx.calls < 10) problems.push('the value chart drew nothing');
  if (win.__errors && win.__errors.length) problems.push('page raised during play: ' + win.__errors.map(String).join(' | '));
  // the page's own ?selftest=1 must run and PASS
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
  const core = await import(pathToFileURL(opts.core || CORE).href + '?t=' + Date.now());
  const rows = [];
  const problems = [];
  const files = readdirSync(opts.scenarios || SCENARIOS).filter(f => f.endsWith('.json')).sort();
  if (files.length !== 15) problems.push(`scenario files: ${files.length}, expected 15`);
  const asserted = new Set();
  const stories = new Set();
  let steps = 0;
  for (const f of files) {
    let sc;
    try { sc = JSON.parse(readFileSync(join(opts.scenarios || SCENARIOS, f), 'utf8')); }
    catch (e) { problems.push(`${f}: unreadable: ${e.message}`); continue; }
    if (!Number.isInteger(sc.story) || stories.has(sc.story)) problems.push(`${f}: story number missing or duplicated`);
    stories.add(sc.story);
    if (!Array.isArray(sc.steps) || !sc.steps.length) { problems.push(`${f}: no steps`); continue; }
    const r = runScenario(core, sc, f);
    r.asserted.forEach(x => asserted.add(x));
    steps += r.stepsRun;
    rows.push({ item: `story ${String(sc.story).padStart(2)} ${sc.title}`, steps: r.stepsRun,
      exhibits: [...r.exhibitedIds].length, ok: !r.problems.length });
    problems.push(...r.problems);
  }
  for (let n = 1; n <= 15; n++) if (!stories.has(n)) problems.push(`story ${n} has no scenario`);
  // reason coverage
  const missing = core.REASONS.filter(r => !asserted.has(r));
  rows.push({ item: `refusal reasons asserted ${asserted.size}/${core.REASONS.length}`, ok: !missing.length });
  if (missing.length) problems.push('refusal reasons never asserted by a scenario: ' + missing.join(', '));
  const unknown = [...asserted].filter(r => !core.REASONS.includes(r));
  if (unknown.length) problems.push('scenarios assert reasons the core cannot produce: ' + unknown.join(', '));
  // every reason explains itself
  const dumb = core.REASONS.filter(r => typeof core.explain({ ok: false, reason: r, action: 'close', pre: 'absent' }, core.newSession({ D: 1, B: 1, P: 1, W: 1 })) !== 'string');
  if (dumb.length) problems.push('reasons without explanation: ' + dumb.join(', '));
  // every theorem in the ledger has a plain statement and lean names
  const bare = core.THEOREMS.filter(t => !t.plain || !t.lean || !t.lean.length);
  if (bare.length) problems.push('theorems without plain statement or Lean names: ' + bare.map(t => t.id).join(', '));
  rows.push({ item: `theorem groups ${core.THEOREMS.length} (T11, T13 absent from the Lean)`, ok: core.THEOREMS.length === 14 });
  if (core.THEOREMS.length !== 14) problems.push(`theorem groups: ${core.THEOREMS.length}, expected 14`);

  // build --check
  if (!opts.skipBuild) {
    try {
      execFileSync(process.execPath, [BUILD, '--check', ...(opts.html ? ['--html', opts.html] : []),
        ...(opts.core ? ['--core', opts.core] : [])], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
      rows.push({ item: 'build --check (core slices, scenarios, corpus, docs copy)', ok: true });
    } catch (e) {
      rows.push({ item: 'build --check', ok: false });
      problems.push('build --check RED: ' + String(e.stdout || '').trim() + ' ' + String(e.stderr || '').trim());
    }
  }
  // page smoke
  let html;
  try { html = readFileSync(opts.html || HTML, 'utf8'); }
  catch (e) { problems.push('page unreadable: ' + e.message); }
  if (html) {
    const s = pageSmoke(core, html);
    rows.push({ item: 'page smoke (minimal DOM: picker, play, evidence, slot, ledger, theme, chart)', ok: !s.problems.length });
    problems.push(...s.problems);
  }
  return { rows, problems, steps };
}

function printTable(r) {
  const w = Math.max(...r.rows.map(x => x.item.length));
  for (const row of r.rows)
    console.log(`${row.ok ? 'PASS' : 'FAIL'}  ${row.item.padEnd(w)}` +
      (row.steps !== undefined ? `  steps=${row.steps} exhibits=${row.exhibits}` : ''));
  console.log(`${r.problems.length ? 'RED' : 'GREEN'}: ${r.rows.length} items, ${r.steps} story steps replayed` +
    (r.problems.length ? `, ${r.problems.length} problems` : ''));
  r.problems.forEach(p => console.error(' - ' + p));
}

/* --- selftest: four negative axes, then GREEN ------------------------------ */

async function selftest(work) {
  const coreText = readFileSync(CORE, 'utf8');
  const htmlText = readFileSync(HTML, 'utf8');
  const controls = [
    {
      name: 'scenario with a flipped expectation',
      expect: /expected ok=false, got ok=true/,
      make: () => {
        const d = join(work, 'sc1'); mkdirSync(d, { recursive: true });
        cpSync(SCENARIOS, d, { recursive: true });
        const f = join(d, '02-hal-lands-and-is-paid.json');
        const sc = JSON.parse(readFileSync(f, 'utf8'));
        sc.steps[3].expect.ok = false; sc.steps[3].expect.reason = 'no-quorum';
        writeFileSync(f, JSON.stringify(sc));
        return { scenarios: d, skipBuild: true };
      },
    },
    {
      name: 'core guard flipped: close enabled while poisoned',
      expect: /expected ok=false, got ok=true|theorem VIOLATED: .*T16|T4/,
      make: () => {
        const p = join(work, 'core-m1.mjs');
        const needle = "if (state.present.l.poisoned) return refuse('poisoned');\n      return some({ refund: payment(l.refundTo, l.dreg, l.b, l.pool) }, 'gone');";
        if (!coreText.includes(needle)) throw new Error('selftest: close guard needle not found in core');
        writeFileSync(p, coreText.replace(needle, "return some({ refund: payment(l.refundTo, l.dreg, l.b, l.pool) }, 'gone');"));
        return { core: p, skipBuild: true };
      },
    },
    {
      name: 'theorem property seeded to lie: T6 conservation on the pool',
      expect: /theorem VIOLATED: .*T6/,
      make: () => {
        const p = join(work, 'core-m2.mjs');
        const needle = 'const poolOk = held(pre).pool + f.poolIn ===';
        if (!coreText.includes(needle)) throw new Error('selftest: T6 needle not found in core');
        writeFileSync(p, coreText.replace(needle, 'const poolOk = held(pre).pool + f.poolIn + 1 ==='));
        return { core: p, skipBuild: true };
      },
    },
    {
      name: 'page with the story picker removed',
      expect: /no #story-picker|picker lists/,
      make: () => {
        const p = join(work, 'page-m1.html');
        writeFileSync(p, htmlText.replace('id="story-picker"', 'id="story-pickr"'));
        return { html: p, skipBuild: true };
      },
    },
  ];
  for (const c of controls) {
    const opts = c.make();
    const r = await runSuite(opts);
    if (!r.problems.length) { console.error(`SELFTEST RED: control «${c.name}» ACCEPTED by the gate`); return 1; }
    const text = r.problems.join('\n');
    if (!c.expect.test(text)) {
      console.error(`SELFTEST RED: «${c.name}» failed for the wrong reason:\n${text.slice(0, 600)}`);
      return 1;
    }
    console.log(`negative control «${c.name}»: RED as expected — ${text.split('\n')[0].slice(0, 140)}`);
  }
  const green = await runSuite({});
  printTable(green);
  if (green.problems.length) { console.error('SELFTEST RED: production does not return GREEN'); return 1; }
  console.log('selftest GREEN: 4 negative controls RED for the expected reason, then production GREEN');
  return 0;
}

const work = mkdtempSync(join(tmpdir(), 'ck-scenario-gate-'));
let code = 1;
try {
  if (process.argv.includes('--selftest')) code = await selftest(work);
  else {
    const r = await runSuite({ core: argPath('--core'), html: argPath('--html'), scenarios: argPath('--scenarios'),
      skipBuild: process.argv.includes('--skip-build') });
    printTable(r);
    code = r.problems.length ? 1 : 0;
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
process.exit(code);
