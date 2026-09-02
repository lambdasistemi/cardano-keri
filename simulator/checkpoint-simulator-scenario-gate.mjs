#!/usr/bin/env node
/*
 * checkpoint-simulator-scenario-gate.mjs — executable scenario suite over
 * the ONE machine core (checkpoint-simulator-core.mjs), plus the shared-core
 * drift gate for the generated single-file page.
 *
 * A scenario is declarative data — initial params, evidence tables, an
 * action list with slots, expected per-step results (refusals carry their
 * named reason), an expected final state, and consumer checks — never a
 * second machine. Fresh on every run the gate:
 *
 *   1. imports the core MODULE directly (the same file whose slices are
 *      inlined byte-for-byte into the page — step 4 proves that);
 *   2. loads every story in checkpoint-simulator-scenarios/ — anything
 *      other than exactly the fifteen stories, or a failing expectation,
 *      is RED;
 *   3. replays every story through the core's verifyScenario: an applied
 *      step expected to be refused (or the wrong refusal reason), a flow
 *      mismatch, a final-state mismatch, or a consumer-check mismatch
 *      is RED;
 *   4. proves both surfaces consume the SAME core: runs
 *      checkpoint-simulator-build.mjs --check (a stale or forked inlined
 *      copy is RED), executes the page's actual script in a vm, and
 *      compares its step/consumable/replay behavior against the imported
 *      module on a probe battery, its embedded stories against the
 *      directory, and its embedded Lean corpus against the core;
 *   5. prints a table and GREEN only if everything above is green.
 *
 * Usage:
 *   node checkpoint-simulator-scenario-gate.mjs             # production
 *   node checkpoint-simulator-scenario-gate.mjs --selftest  # negative controls
 *
 * --selftest proves the gate can fail, each control RED for its intended
 * reason: a broken scenario expectation, a drifted embedded copy, and a
 * flipped core guard (the M-style mutant, applied to a scratch copy — the
 * committed tree is never touched). Temporary artifacts live in a fresh
 * mkdtemp directory.
 *
 * --html/--core/--scenarios/--build overrides exist for the controls;
 * production callers use the defaults.
 */

import { readFileSync, readdirSync, mkdtempSync, rmSync, writeFileSync, cpSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import vm from 'node:vm';

const REPO = dirname(fileURLToPath(import.meta.url));
const argPath = flag => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const HTML = argPath('--html') || join(REPO, 'checkpoint-simulator.html');
const CORE = argPath('--core') || join(REPO, 'checkpoint-simulator-core.mjs');
const SCEN_DIR = argPath('--scenarios') || join(REPO, 'checkpoint-simulator-scenarios');
const BUILD = argPath('--build') || join(REPO, 'checkpoint-simulator-build.mjs');
const N_STORIES = 15;
const sha256 = b => createHash('sha256').update(b).digest('hex');

const loadScenarios = dir => readdirSync(dir).filter(f => f.endsWith('.json')).sort()
  .map(f => ({ file: f, sc: JSON.parse(readFileSync(join(dir, f), 'utf8')) }));

/* --- execute the page's ACTUAL production script in an inert vm ----------- */

function loadProduction(htmlPath) {
  const doc = readFileSync(htmlPath, 'utf8');
  const sm = doc.match(/<script>\n([\s\S]*?)\n<\/script>/);
  if (!sm) throw new Error('production script not found in the page');
  const src = sm[1];
  // universal inert stub: any property access yields another callable stub,
  // so define-time and render-time DOM traffic is absorbed without a browser
  const stubHandler = {
    get(t, p) {
      if (p === Symbol.toPrimitive) return () => '';
      if (p === Symbol.iterator) return function* () {};
      if (p === 'hidden' || p === 'disabled') return false;
      return STUB;
    },
    set() { return true; },
    apply() { return STUB; },
    construct() { return STUB; },
  };
  const STUB = new Proxy(function () {}, stubHandler);
  const ctx = {
    location: { search: '' },
    document: STUB,
    navigator: STUB,
    URLSearchParams: class { constructor() {} get() { return null; } },
    innerWidth: 1280, innerHeight: 800,
    performance: { now: () => 0 },
    requestAnimationFrame: () => 0,
    setTimeout: () => 0, clearTimeout: () => 0,
    console,
  };
  ctx.window = ctx;
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(src, ctx, { filename: 'checkpoint-simulator.html#script' });
  if (!ctx.window.CK || typeof ctx.window.CK.step !== 'function')
    throw new Error('the production script does not expose window.CK.step: execution not proven');
  return { CK: ctx.window.CK, scriptSha: sha256(src) };
}

/* --- the probe battery: same calls, both surfaces -------------------------- */

function probeBattery(CK) {
  const P = { D: 1000, B: 5, P: 2, W: 10 };
  const env = CK.envFromTables({
    rotationTo: [[0, 0, 1, true], [1, 1, 2, true], [2, 2, 2, true]],
    refundAuthorized: [[1, 1, true]],
    quorum: [[0, true]],
    duplicityAt: [[0, 0, true]],
  });
  const reg = { register: { refund: 1, pool0: 5 } };
  const rot = (sn, op, refund) => ({ rotate: { sn, op, payee: 2, refund: refund === undefined ? null : refund } });
  const present = { present: { sn: 0, epoch: 0, poisoned: false, bornAt: 0, refundTo: 1, dreg: 1000, b: 5, pool: 5 } };
  const frozen = { present: { sn: 0, epoch: 0, poisoned: false, bornAt: 0, refundTo: 1, dreg: 1000, b: 0, pool: 1 } };
  const poisoned = { present: { sn: 0, epoch: 0, poisoned: true, bornAt: 0, refundTo: 1, dreg: 1000, b: 5, pool: 1 } };
  const calls = [
    () => CK.step(P, env, reg, 0, 'absent'),
    () => CK.step(P, env, reg, 0, 'gone'),
    () => CK.step(P, env, reg, 0, present),
    () => CK.step(P, env, rot(1, 'keep'), 5, present),
    () => CK.step(P, env, rot(0, 'keep'), 5, present),
    () => CK.step(P, env, rot(2, 'keep', 4), 5, present),
    () => CK.step(P, env, rot(1, 'withdraw'), 5, present),
    () => CK.step(P, env, rot(1, 'deposit'), 5, frozen),
    () => CK.step(P, env, { poison: {} }, 5, present),
    () => CK.step(P, env, { poison: {} }, 5, poisoned),
    () => CK.step(P, env, { close: {} }, 5, poisoned),
    () => CK.step(P, env, { close: {} }, 5, present),
    () => CK.step(P, env, 'close', 5, present),
    () => CK.step(P, env, { freeze: { sn: 1, payee: 2 } }, 5, present),
    () => CK.step(P, env, { freeze: { sn: 1, payee: 2 } }, 5, frozen),
    () => CK.step(P, env, { freeze: { sn: 1, payee: 2 } }, 5, poisoned),
    () => CK.step(P, env, { convict: { payee: 3 } }, 5, present),
    () => CK.step(P, env, { topUp: { x: 2 } }, 5, present),
    () => CK.step(P, env, { topUp: { x: 2 } }, 5, 'absent'),
    () => CK.replay(P, env, 5, 'absent', [{ now: 3, action: reg }, { now: 2, action: rot(1, 'keep') }]),
    () => CK.replay(P, env, 0, 'absent', [{ now: 3, action: reg }]),
    () => CK.consumableState(P, 9, present),
    () => CK.consumableState(P, 10, present),
    () => CK.consumableState(P, 10, poisoned),
    () => CK.consumableState(P, 10, 'gone'),
    () => CK.actionActor({ rotate: { sn: 1, op: 'keep', payee: 2, refund: null } }),
    () => CK.actionActor({ poison: {} }),
    () => CK.stateAllows('gone', 'register'),
    () => CK.stateAllows('absent', 'topUp'),
    () => CK.verifyScenario({ id: 0, slug: 'x', story: 'x', params: P, env: {}, initial: 'absent',
      steps: [{ now: 0, actor: 'anyone', action: reg, expect: { ok: false, reason: 'not-absent' } }] }),
  ];
  return CK.canonicalJson(calls.map(f => f()));
}

/* --- one full gate evaluation ---------------------------------------------- */

async function runGate(opts) {
  const reasons = [];
  const rows = [];
  const html = opts.html || HTML;
  const corePath = opts.core || CORE;
  const scenDir = opts.scenarios || SCEN_DIR;
  const core = await import(pathToFileURL(corePath).href);

  let scenarios;
  try {
    scenarios = loadScenarios(scenDir);
  } catch (e) {
    return { ok: false, rows, reasons: ['scenarios unreadable: ' + e.message] };
  }
  if (scenarios.length !== N_STORIES) {
    reasons.push(`expected exactly ${N_STORIES} stories, found ${scenarios.length}`);
  } else {
    scenarios.forEach(({ sc }, i) => {
      if (sc.id !== i + 1) reasons.push(`story ${i + 1} has id ${sc.id}`);
    });
  }
  for (const { file, sc } of scenarios) {
    const r = core.verifyScenario(sc);
    rows.push({ id: sc.id, story: sc.story, ok: r.ok,
      detail: r.ok ? `${r.accepted} applied, ${r.refused} refused` : r.lines.filter(l => !/: applied$/.test(l)).join(' | ') });
    if (!r.ok) reasons.push(`${file}: ${rows[rows.length - 1].detail}`);
  }

  // the drift gate: the embedded copy must be fresh
  try {
    const out = execFileSync(process.execPath, [BUILD, '--check', '--html', html,
      '--core', corePath, '--scenarios', scenDir], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    rows.push({ id: '—', story: 'embedded copy is the core (build --check)', ok: true, detail: out.trim() });
  } catch (e) {
    reasons.push('drift gate: ' + String(e.stderr || e.message).trim().split('\n')[0]);
    rows.push({ id: '—', story: 'embedded copy is the core (build --check)', ok: false, detail: 'stale or forked' });
  }

  // the page's own script, executed, must behave like the imported module
  let prod;
  try { prod = loadProduction(html); }
  catch (e) {
    return { ok: false, rows, reasons: [...reasons, 'production execution failed: ' + e.message] };
  }
  let probeMod, probePage;
  try {
    probeMod = probeBattery(core);
    probePage = probeBattery(prod.CK);
  } catch (e) {
    return { ok: false, rows, reasons: [...reasons, 'probe battery threw: ' + e.message] };
  }
  if (probeMod !== probePage) {
    reasons.push('the page\'s embedded core does not behave like the module (probe battery mismatch)');
    rows.push({ id: '—', story: 'page core ≡ module core (probe battery)', ok: false, detail: 'mismatch' });
  } else {
    rows.push({ id: '—', story: 'page core ≡ module core (probe battery)', ok: true, detail: '28 probes identical' });
  }

  // embedded stories must equal the directory
  const embScen = prod.CK.SCENARIOS;
  const dirScen = scenarios.map(x => x.sc);
  if (core.canonicalJson(embScen) !== core.canonicalJson(dirScen)) {
    reasons.push('the page\'s embedded stories differ from the scenarios directory');
    rows.push({ id: '—', story: 'embedded stories ≡ directory', ok: false, detail: 'differ' });
  } else {
    rows.push({ id: '—', story: 'embedded stories ≡ directory', ok: true, detail: `${dirScen.length} stories` });
  }

  // embedded Lean corpus replayed through the page core
  try {
    const r = prod.CK.verifyTracesDoc(prod.CK.LEAN_TRACES);
    if (!r.ok) {
      reasons.push('embedded Lean corpus refused by the page core: ' + r.errors[0]);
      rows.push({ id: '—', story: 'embedded Lean corpus replays', ok: false, detail: r.errors[0] });
    } else {
      rows.push({ id: '—', story: 'embedded Lean corpus replays', ok: true, detail: `${r.traces} envelopes, ${r.steps} steps` });
    }
  } catch (e) {
    reasons.push('embedded Lean corpus replay threw: ' + e.message);
  }

  return { ok: reasons.length === 0, rows, reasons, scriptSha: prod.scriptSha };
}

/* --- selftest: three negative axes, then production GREEN ------------------ */

async function selftest(work) {
  const doc = readFileSync(HTML, 'utf8');

  // axis 1 — a broken scenario expectation
  const brokenDir = join(work, 'scen-broken');
  cpSync(SCEN_DIR, brokenDir, { recursive: true });
  const f02 = join(brokenDir, '02-rotate-keep-paid.json');
  const sc02 = JSON.parse(readFileSync(f02, 'utf8'));
  sc02.expectFinal.present.pool = 4;              // the machine says 3
  writeFileSync(f02, JSON.stringify(sc02, null, 1));
  let r = await runGate({ scenarios: brokenDir });
  if (r.ok || !/pool ≠ expected|final state/.test(r.reasons.join('\n'))) {
    console.error('SELFTEST RED: broken expectation not caught for the right reason:\n' + r.reasons.join('\n'));
    return 1;
  }
  console.log('negative control «broken scenario expectation»: RED as expected — ' + r.reasons[0].slice(0, 120));

  // axis 2 — a drifted embedded copy (one forked byte inside a page slice)
  const drifted = join(work, 'drifted.html');
  const forked = doc.replace('sequence-not-greater', 'sequence-not-greATER');
  if (forked === doc) { console.error('SELFTEST RED: drift mutation did not apply'); return 1; }
  writeFileSync(drifted, forked);
  r = await runGate({ html: drifted });
  if (r.ok || !/drift gate|stale or forked/.test(r.reasons.join('\n'))) {
    console.error('SELFTEST RED: drifted embedded copy not caught for the right reason:\n' + r.reasons.join('\n'));
    return 1;
  }
  console.log('negative control «drifted embedded copy»: RED as expected — ' + r.reasons.find(x => /drift/.test(x)).slice(0, 120));

  // axis 3 — a flipped core guard (the M-class mutant), on scratch copies
  const scratchCore = join(work, 'core-flipped.mjs');
  const scratchHtml = join(work, 'page-flipped.html');
  const orig = readFileSync(CORE, 'utf8');
  const flipped = orig.replace(
    "if (!(l.sn < sn)) return { ok: false, reason: REASONS.SEQUENCE_NOT_GREATER };",
    "");
  if (flipped === orig) { console.error('SELFTEST RED: guard flip did not apply'); return 1; }
  writeFileSync(scratchCore, flipped);
  cpSync(HTML, scratchHtml);
  execFileSync(process.execPath, [BUILD, '--core', scratchCore, '--html', scratchHtml,
    '--scenarios', SCEN_DIR], { stdio: ['ignore', 'pipe', 'pipe'] });
  r = await runGate({ core: scratchCore, html: scratchHtml });
  if (r.ok || !/expected refusal|sequence/.test(r.reasons.join('\n'))) {
    console.error('SELFTEST RED: flipped guard not caught for the right reason:\n' + r.reasons.join('\n'));
    return 1;
  }
  console.log('negative control «flipped core guard»: RED as expected — ' + r.reasons[0].slice(0, 120));

  const green = await runGate({});
  if (!green.ok) {
    console.error('SELFTEST RED: the production gate does not return GREEN:\n' + green.reasons.join('\n'));
    return 1;
  }
  report(green, 'selftest GREEN: 3 negative controls RED for the right reason; ');
  return 0;
}

function report(r, prefix) {
  console.log((prefix || '') + 'per-story results:');
  for (const row of r.rows)
    console.log(`  ${String(row.id).padStart(2)}  ${(row.ok ? 'PASS' : 'FAIL').padEnd(4)}  ${row.story}` +
      (row.detail ? `  — ${row.detail}` : ''));
  console.log(`GREEN: ${r.rows.filter(x => x.story.match(/^story|^[0-9]/) || /^[0-9]/.test(String(x.id))).length} stories, ` +
    `page script executed (sha ${r.scriptSha.slice(0, 12)}…), embedded copy fresh, one core`);
}

/* --- CLI ------------------------------------------------------------------- */

const work = mkdtempSync(join(tmpdir(), 'ck-scenario-gate-'));
let code = 1;
try {
  if (process.argv.includes('--selftest')) {
    code = await selftest(work);
  } else {
    const r = await runGate({});
    if (r.ok) { report(r); code = 0; }
    else {
      console.error(`RED: ${r.reasons.length} problem(s)`);
      r.reasons.forEach(x => console.error(' - ' + x));
      code = 1;
    }
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
process.exit(code);
