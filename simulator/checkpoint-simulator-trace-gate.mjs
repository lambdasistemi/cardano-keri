#!/usr/bin/env node
/*
 * checkpoint-simulator-trace-gate.mjs — reproducibility and conformance
 * verifier for the Lean trace corpus embedded in checkpoint-simulator.html.
 *
 * Fresh on every run it:
 *   1. builds the committed model and runs the committed Lean producer,
 *      lean/CheckpointTraceDriver.lean, in this repository's lake
 *      environment (`nix shell nixpkgs#lean4 -c`): six seeded traces folded
 *      through the authoritative `stepFn` and serialized with ToJson —
 *      the durable artifact; its JSON output is disposable;
 *   2. requires valid JSON, the v1 schema, a nonempty corpus and nonempty
 *      steps (the six seeded traces must all be there);
 *   3. extracts the embedded CHECKPOINT_LEAN_TRACES_V1 fixture and its
 *      stated sha256 from the committed HTML (sha over the trimmed raw
 *      output; the trailing newline is a lake artifact);
 *   4. compares fresh Lean output against the embedded fixture by hash and
 *      by structure, reporting the first structural difference;
 *   5. executes the HTML's ACTUAL production JavaScript — the whole
 *      embedded script evaluated in a vm with inert browser shims — and
 *      replays BOTH corpora through the page's own `verifyTracesDoc`
 *      (the one transcription of `stepFn`); never a copied transition
 *      implementation;
 *   6. fails on any refusal, flow mismatch, post-state difference,
 *      continuity break, or missing/empty envelope;
 *   7. prints counts, the fresh sha, and GREEN only after BOTH Lean
 *      regeneration equivalence and production-JS replay succeed.
 *
 * Usage from any working directory:
 *   node /path/to/repo/simulator/checkpoint-simulator-trace-gate.mjs
 *   node /path/to/repo/simulator/checkpoint-simulator-trace-gate.mjs --selftest
 *
 * --selftest proves the gate can fail: a mutated post-state in a scratch
 * copy of the embedded envelope, an emptied embedded corpus, and a mutated
 * stated sha — each RED for its intended reason — then production GREEN.
 * Temporary artifacts live in a fresh mkdtemp directory; the repo stays
 * clean.
 */

import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import vm from 'node:vm';

const REPO = dirname(fileURLToPath(import.meta.url));
const HTML = join(REPO, 'checkpoint-simulator.html');
const LEAN_DIR = join(REPO, '..', 'lean');
const DRIVER = 'CheckpointTraceDriver.lean';
const N_TRACES = 6;
const sha256 = b => createHash('sha256').update(b).digest('hex');

/* --- fresh Lean regeneration (reusable across selftest controls) ----------- */

function runDriver() {
  execFileSync('nix', ['shell', 'nixpkgs#lean4', '-c', 'lake', 'build', 'CardanoKeri.Checkpoint'],
    { cwd: LEAN_DIR, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return execFileSync('nix',
    ['shell', 'nixpkgs#lean4', '-c', 'lake', 'env', 'lean', DRIVER],
    { cwd: LEAN_DIR, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

/* --- embedded fixture + stated sha extraction ------------------------------ */

function extractEmbedded(doc) {
  const fm = doc.match(/const CHECKPOINT_LEAN_TRACES_V1 = (\{.*?\});\n/s);
  if (!fm) throw new Error('CHECKPOINT_LEAN_TRACES_V1 not found in the page');
  const sm = doc.match(/Raw output sha256:\n   ([0-9a-f]{64}) \*\//);
  if (!sm) throw new Error('stated sha of the corpus not found in the page');
  return { fixtureText: fm[1], statedSha: sm[1] };
}

/* --- execute the page's ACTUAL production script in an inert vm ------------ */

function loadProduction(htmlPath) {
  const doc = readFileSync(htmlPath, 'utf8');
  const sm = doc.match(/<script>\n([\s\S]*?)\n<\/script>/);
  if (!sm) throw new Error('production script not found in the page');
  const src = sm[1];
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
  if (!ctx.window.CK || typeof ctx.window.CK.verifyTracesDoc !== 'function')
    throw new Error('the production script does not expose CK.verifyTracesDoc: execution not proven');
  return { CK: ctx.window.CK, scriptSha: sha256(src) };
}

/* --- one full gate evaluation ---------------------------------------------- */

function structuralDiff(fresh, fixture) {
  const freshNames = Object.keys(fresh.traces || {});
  const fixNames = Object.keys((fixture || {}).traces || {});
  if (JSON.stringify(freshNames.slice().sort()) !== JSON.stringify(fixNames.slice().sort()))
    return `diverging envelopes — fresh=[${freshNames}] embedded=[${fixNames}]`;
  for (const n of freshNames) {
    const a = fresh.traces[n], b = fixture.traces[n];
    if (!Array.isArray(b.steps) || a.steps.length !== b.steps.length)
      return `trace ${n}: ${a.steps.length} fresh steps vs ${b.steps ? b.steps.length : 0} embedded`;
    for (let i = 0; i < a.steps.length; i++)
      if (JSON.stringify(a.steps[i]) !== JSON.stringify(b.steps[i]))
        return `trace ${n} step ${i}: first structural difference — fresh=` +
          JSON.stringify(a.steps[i]).slice(0, 160) + '… embedded=' +
          JSON.stringify(b.steps[i]).slice(0, 160) + '…';
    if (JSON.stringify(a.initial) !== JSON.stringify(b.initial))
      return `trace ${n}: diverging initial state`;
    if (JSON.stringify(a.params) !== JSON.stringify(b.params))
      return `trace ${n}: diverging params`;
    if (JSON.stringify(a.env) !== JSON.stringify(b.env))
      return `trace ${n}: diverging evidence tables`;
  }
  return null;
}

function runGate(opts) {
  const html = opts.html || HTML;
  const reasons = [];
  let doc;
  try { doc = readFileSync(html, 'utf8'); }
  catch (e) { return { ok: false, reasons: ['HTML unreadable: ' + e.message] }; }

  let freshRaw = opts.freshRaw;
  if (!freshRaw) {
    try { freshRaw = runDriver(); }
    catch (e) {
      return { ok: false, reasons: ['the committed Lean driver fails: ' +
        (String(e.stdout || '') + String(e.stderr || '')).slice(-400)] };
    }
  }
  const freshSha = sha256(freshRaw.trim());
  let fresh;
  try { fresh = JSON.parse(freshRaw); }
  catch (e) { return { ok: false, reasons: ['driver output is not valid JSON'] }; }
  if (fresh.schema !== 'cardano-keri.checkpoint.trace' || fresh.version !== 1)
    reasons.push('driver output is not a v1 cardano-keri.checkpoint.trace corpus');
  const freshNames = Object.keys(fresh.traces || {});
  if (!freshNames.length || freshNames.length < N_TRACES)
    reasons.push(`fresh corpus has ${freshNames.length} envelopes, expected ${N_TRACES}`);
  if (freshNames.some(n => !Array.isArray(fresh.traces[n].steps) || !fresh.traces[n].steps.length))
    return { ok: false, reasons: ['fresh corpus empty or with envelopes without steps'] };

  let emb;
  try { emb = extractEmbedded(doc); }
  catch (e) { return { ok: false, reasons: [e.message] }; }
  if (emb.statedSha !== freshSha)
    reasons.push(`stated sha ≠ fresh driver output — stated=${emb.statedSha.slice(0, 12)}… fresh=${freshSha.slice(0, 12)}…`);
  let fixture;
  try { fixture = JSON.parse(emb.fixtureText); }
  catch (e) { reasons.push('embedded fixture is not valid JSON'); }
  if (fixture) {
    if (!Object.keys(fixture.traces || {}).length ||
        Object.values(fixture.traces).some(t => !Array.isArray(t.steps) || !t.steps.length))
      reasons.push('embedded corpus empty or with envelopes without steps');
    else {
      const diff = structuralDiff(fresh, fixture);
      if (diff) reasons.push(diff);
    }
  }

  // execute the production JavaScript and replay through ITS verifier
  let prod;
  try { prod = loadProduction(html); }
  catch (e) { return { ok: false, reasons: [...reasons, 'production execution failed: ' + e.message] }; }
  let embSteps = 0;
  try {
    const tc = prod.CK.verifyTracesDoc(prod.CK.LEAN_TRACES);
    embSteps = tc.steps;
    if (!tc.ok) reasons.push('production replay of the embedded corpus RED: ' + tc.errors[0]);
    else if (!Number.isInteger(embSteps) || embSteps <= 0)
      reasons.push('production verifyTracesDoc replayed no steps');
  } catch (e) {
    reasons.push('production replay of the embedded corpus threw: ' + e.message);
  }
  let freshSteps = 0;
  try {
    const r = prod.CK.verifyTracesDoc(fresh);
    freshSteps = r.steps;
    if (!r.ok) reasons.push('production replay of the fresh corpus RED: ' + r.errors[0]);
  } catch (e) {
    reasons.push('production replay of the fresh corpus threw: ' + e.message);
  }

  if (reasons.length) return { ok: false, reasons };
  return { ok: true, envelopes: freshNames.length, embSteps, freshSteps, freshSha,
    scriptSha: prod.scriptSha };
}

/* --- selftest: three negative axes, then production GREEN ------------------ */

function selftest(work) {
  const doc = readFileSync(HTML, 'utf8');
  const freshRaw = runDriver();          // one fresh Lean run, reused by every control
  const emb = extractEmbedded(doc);
  const controls = [
    {
      name: 'mutated post-state in the embedded fixture',
      expect: /structural difference|after mismatch|flow mismatch/,
      make: () => doc.replace(emb.fixtureText,
        emb.fixtureText.replace('"pool":7}}', '"pool":8}}')),
    },
    {
      name: 'embedded corpus emptied',
      expect: /embedded corpus empty|no steps|without steps/,
      make: () => doc.replace(/const CHECKPOINT_LEAN_TRACES_V1 = \{.*?\};\n/s,
        'const CHECKPOINT_LEAN_TRACES_V1 = {"schema":"cardano-keri.checkpoint.trace","version":1,"traces":{}};\n'),
    },
    {
      name: 'stated sha mutated',
      expect: /stated sha ≠/,
      make: () => doc.replace(emb.statedSha,
        (emb.statedSha[0] === '0' ? '1' : '0') + emb.statedSha.slice(1)),
    },
  ];
  for (const c of controls) {
    const p = join(work, 'scratch.html');
    const mutated = c.make();
    if (mutated === doc) {
      console.error(`SELFTEST RED: control «${c.name}» did not apply — the mutation is vacuous`);
      return 1;
    }
    writeFileSync(p, mutated);
    const r = runGate({ html: p, freshRaw });
    if (r.ok) {
      console.error(`SELFTEST RED: control «${c.name}» ACCEPTED by the gate`);
      return 1;
    }
    const text = r.reasons.join('\n');
    if (!c.expect.test(text)) {
      console.error(`SELFTEST RED: «${c.name}» failed for the wrong reason:\n${text.slice(0, 400)}`);
      return 1;
    }
    console.log(`negative control «${c.name}»: RED as expected — ${text.split('\n')[0].slice(0, 120)}`);
  }
  const green = runGate({ freshRaw });
  if (!green.ok) {
    console.error('SELFTEST RED: the production gate does not return GREEN:\n' + green.reasons.join('\n'));
    return 1;
  }
  report(green, 'selftest GREEN: 3 negative controls RED for the right reason; ');
  return 0;
}

function report(r, prefix) {
  console.log((prefix || '') +
    `GREEN: ${r.envelopes} envelopes; Lean regeneration identical (sha ${r.freshSha.slice(0, 12)}…); ` +
    `production replay: ${r.embSteps} steps on the embedded corpus + ${r.freshSteps} on the fresh corpus ` +
    `(script executed, sha ${r.scriptSha.slice(0, 12)}…)`);
}

/* --- CLI ------------------------------------------------------------------- */

const work = mkdtempSync(join(tmpdir(), 'ck-trace-gate-'));
let code = 1;
try {
  if (process.argv.includes('--selftest')) {
    code = selftest(work);
  } else {
    const r = runGate({});
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
