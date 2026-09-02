#!/usr/bin/env node
/*
 * checkpoint-simulator-trace-gate.mjs — reproducibility and conformance
 * verifier for the Lean trace corpus embedded in checkpoint-simulator.html.
 *
 * Fresh on every run it:
 *   1. runs the committed lean/CheckpointTraceDriver.lean in the repository's
 *      Lean environment (the durable producer; its JSON is disposable);
 *   2. requires valid JSON with the expected schema, nonempty traces and a
 *      nonempty grid;
 *   3. extracts the embedded LEAN_CORPUS fixture and its stated sha256 from
 *      the committed page, and compares fresh Lean output against both by
 *      hash and by structure (first structural difference reported);
 *   4. replays EVERY step of the fresh corpus — applied and refused — through
 *      the JavaScript core: seeded traces step by step, every grid cell from
 *      its seeded state, and the consumability probes; a refusal the core
 *      accepts, an acceptance it refuses, or a different flow / post-state
 *      is RED, so refusal parity with the Lean is a gate and not a reading;
 *   5. checks every theorem property T1–T16 on every applied step;
 *   6. executes the page's ACTUAL production script in the minimal DOM and
 *      replays the fresh corpus through the page's own inlined core
 *      (window.CK.replayCorpus) — never a copied transition implementation;
 *   7. prints counts and the fresh sha, GREEN only if everything agrees.
 *
 * Usage:
 *   node simulator/checkpoint-simulator-trace-gate.mjs
 *   node simulator/checkpoint-simulator-trace-gate.mjs --selftest
 *
 * --selftest proves the gate can fail: a mutated post-state in a scratch copy
 * of the embedded corpus, an emptied embedded corpus, a mutated stated sha,
 * and a core with a guard flipped (freeze without a short pool) — each RED
 * for its intended reason — then production GREEN.
 */

import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createWindow } from './checkpoint-simulator-minidom.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const LEAN = join(HERE, '..', 'lean');
const HTML = join(HERE, 'checkpoint-simulator.html');
const CORE = join(HERE, 'checkpoint-simulator-core.mjs');
const sha256 = b => createHash('sha256').update(b).digest('hex');
const SCHEMA = 'cardano-keri.checkpoint-trace';

function runDriver() {
  return execFileSync('nix', ['shell', 'nixpkgs#lean4', '-c', 'lake', 'env', 'lean', 'CheckpointTraceDriver.lean'],
    { cwd: LEAN, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
}

function extractEmbedded(doc) {
  const fm = doc.match(/const LEAN_CORPUS = (\{.*?\});\nconst LEAN_CORPUS_SHA256 = '([0-9a-f]{64})';\n/s);
  if (!fm) throw new Error('LEAN_CORPUS / LEAN_CORPUS_SHA256 not found in the page');
  return { fixtureText: fm[1], statedSha: fm[2] };
}

/* --- replay: the core's own checker (shared with the page's selftest) ----- */

const replayCorpus = (core, corpus) => core.checkCorpus(corpus);

/* --- one full gate evaluation --------------------------------------------- */

async function runGate(opts) {
  const html = opts.html || HTML;
  const reasons = [];
  let doc;
  try { doc = readFileSync(html, 'utf8'); } catch (e) { return { ok: false, reasons: ['page unreadable: ' + e.message] }; }
  let freshRaw = opts.freshRaw;
  if (!freshRaw) {
    try { freshRaw = runDriver(); }
    catch (e) { return { ok: false, reasons: ['the committed Lean driver fails: ' + (String(e.stdout || '') + String(e.stderr || '')).slice(-600)] }; }
  }
  const freshSha = sha256(freshRaw);
  let fresh;
  try { fresh = JSON.parse(freshRaw); } catch (e) { return { ok: false, reasons: ['driver output is not valid JSON'] }; }
  if (fresh.schema !== SCHEMA || fresh.version !== 1) reasons.push('driver output has the wrong schema/version');
  if (!Array.isArray(fresh.traces) || !fresh.traces.length || fresh.traces.some(t => !t.steps || !t.steps.length))
    reasons.push('fresh corpus has no traces or a trace without steps');
  // embedded fixture and stated sha
  let emb;
  try { emb = extractEmbedded(doc); } catch (e) { return { ok: false, reasons: [...reasons, e.message] }; }
  if (emb.statedSha !== freshSha)
    reasons.push(`stated sha ≠ fresh driver output — stated=${emb.statedSha.slice(0, 12)}… fresh=${freshSha.slice(0, 12)}…`);
  let fixture;
  try { fixture = JSON.parse(emb.fixtureText); } catch (e) { reasons.push('embedded corpus is not valid JSON'); }
  if (fixture) {
    if (!Array.isArray(fixture.traces) || !fixture.traces.length || !fixture.grid || !fixture.grid.cells || !fixture.grid.cells.length)
      reasons.push('embedded corpus empty or without traces / grid');
    else {
      const a = fresh, b = fixture;
      outer: {
        if (a.traces.length !== b.traces.length) { reasons.push(`traces: ${a.traces.length} fresh vs ${b.traces.length} embedded`); break outer; }
        for (let t = 0; t < a.traces.length; t++) {
          if (a.traces[t].steps.length !== b.traces[t].steps.length) { reasons.push(`trace ${a.traces[t].name}: ${a.traces[t].steps.length} fresh steps vs ${b.traces[t].steps.length} embedded`); break outer; }
          for (let i = 0; i < a.traces[t].steps.length; i++)
            if (JSON.stringify(a.traces[t].steps[i]) !== JSON.stringify(b.traces[t].steps[i])) {
              reasons.push(`trace ${a.traces[t].name} step ${i}: first structural difference — fresh=` +
                JSON.stringify(a.traces[t].steps[i]).slice(0, 160) + '… embedded=' + JSON.stringify(b.traces[t].steps[i]).slice(0, 160) + '…');
              break outer;
            }
        }
        if (JSON.stringify(a.grid) !== JSON.stringify(b.grid)) { reasons.push('grid: fresh and embedded differ'); break outer; }
      }
    }
  }
  // replay through the core module
  const core = await import(pathToFileURL(opts.core || CORE).href + '?t=' + Date.now());
  const rp = replayCorpus(core, fresh);
  reasons.push(...rp.reasons.slice(0, 40));
  if (rp.reasons.length > 40) reasons.push(`… and ${rp.reasons.length - 40} more`);
  // replay through the page's own inlined core
  let pageSteps = 0;
  try {
    const win = createWindow(doc, { search: '' });
    if (win.__errors.length) reasons.push('page raised on load: ' + win.__errors.map(String).join(' | '));
    if (!win.CK || typeof win.CK.replayCorpus !== 'function') reasons.push('the page does not expose CK.replayCorpus: page execution not proved');
    else {
      const r = win.CK.replayCorpus(fresh);
      pageSteps = r.applied + r.refused;
      if (r.reasons.length) reasons.push('page replay RED: ' + r.reasons.slice(0, 5).join(' | '));
      if (!(r.applied > 0 && r.refused > 0)) reasons.push('page replay covered no applied or no refused steps');
    }
  } catch (e) { reasons.push('page execution failed: ' + (e && e.stack || e)); }
  if (reasons.length) return { ok: false, reasons };
  return { ok: true, freshSha, traces: fresh.traces.length, applied: rp.applied, refused: rp.refused,
    theoremChecks: rp.theoremChecks, cons: rp.cons, pageSteps, cells: fresh.grid.cells.length };
}

function report(r, prefix) {
  console.log((prefix || '') + `GREEN: Lean regeneration identical (sha ${r.freshSha.slice(0, 12)}…); ${r.traces} traces + ${r.cells} grid cells replayed through the core: ` +
    `${r.applied} applied, ${r.refused} refused, ${r.theoremChecks} theorem reports all holding, ${r.cons} consumability probes agree; ` +
    `${r.pageSteps} steps replayed through the page's inlined core`);
}

/* --- selftest --------------------------------------------------------------- */

async function selftest(work) {
  const doc = readFileSync(HTML, 'utf8');
  const coreText = readFileSync(CORE, 'utf8');
  const freshRaw = runDriver();
  const emb = extractEmbedded(doc);
  const controls = [
    { name: 'post-state mutated in the embedded corpus', expect: /structural difference|stated sha|grid: fresh and embedded differ/,
      make: () => ({ html: writeTmp('m1.html', doc.replace(emb.fixtureText, emb.fixtureText.replace('"pool":8', '"pool":9'))), freshRaw }) },
    { name: 'embedded corpus emptied', expect: /empty|not found|stated sha/,
      make: () => ({ html: writeTmp('m2.html', doc.replace(/const LEAN_CORPUS = \{.*?\};\n/s, 'const LEAN_CORPUS = {};\n')), freshRaw }) },
    { name: 'stated sha mutated', expect: /stated sha ≠/,
      make: () => ({ html: writeTmp('m3.html', doc.replace(emb.statedSha, (emb.statedSha[0] === '0' ? '1' : '0') + emb.statedSha.slice(1))), freshRaw }) },
    { name: 'core guard flipped: freeze without a short pool', expect: /Lean refused, the core applied|theorem VIOLATED/,
      make: () => {
        const needle = "if (!(l.pool < p.P)) return refuse('pool-covers-premium');";
        if (!coreText.includes(needle)) throw new Error('selftest: freeze needle not found');
        return { core: writeTmp('core-m.mjs', coreText.replace(needle, '')), freshRaw };
      } },
  ];
  const writeTmp = (n, t) => { const p = join(work, n); writeFileSync(p, t); return p; };
  for (const c of controls) {
    const r = await runGate(c.make());
    if (r.ok) { console.error(`SELFTEST RED: control «${c.name}» ACCEPTED by the gate`); return 1; }
    const text = r.reasons.join('\n');
    if (!c.expect.test(text)) { console.error(`SELFTEST RED: «${c.name}» failed for the wrong reason:\n${text.slice(0, 600)}`); return 1; }
    console.log(`negative control «${c.name}»: RED as expected — ${text.split('\n')[0].slice(0, 140)}`);
  }
  const green = await runGate({ freshRaw });
  if (!green.ok) { console.error('SELFTEST RED: production does not return GREEN:\n' + green.reasons.join('\n')); return 1; }
  report(green, 'selftest GREEN: 4 negative controls RED for the expected reason; ');
  return 0;
}

const work = mkdtempSync(join(tmpdir(), 'ck-trace-gate-'));
let code = 1;
try {
  if (process.argv.includes('--selftest')) code = await selftest(work);
  else {
    const r = await runGate({});
    if (r.ok) { report(r); code = 0; }
    else { console.error(`RED: ${r.reasons.length} problems`); r.reasons.forEach(x => console.error(' - ' + x)); code = 1; }
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
process.exit(code);
