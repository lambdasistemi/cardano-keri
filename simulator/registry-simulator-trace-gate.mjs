#!/usr/bin/env node
/*
 * registry-simulator-trace-gate.mjs — reproducibility and conformance
 * verifier for the Lean corpus embedded in registry-simulator.html.
 *
 * Fresh on every run it:
 *   1. builds the driver's imports (`lake build CardanoKeri.Registry`) and
 *      runs the committed Lean producer, lean/RegistryTraceDriver.lean, in
 *      this repository's lake environment (`nix shell nixpkgs#lean4 -c`):
 *      six seeded traces, the boundary grid and the fifteen story cells,
 *      folded through the authoritative `stepFn` and serialized with ToJson;
 *   2. requires valid JSON, the v1 schema, six traces, a nonempty grid and
 *      fifteen stories;
 *   3. compares the fresh output with registry-simulator-corpus.json and
 *      with the corpus embedded in the page, by sha256 and by structure;
 *   4. replays every cell (applied and refused) through the core module and
 *      through the page's ACTUAL production script (evaluated in the
 *      minimal DOM), checking every theorem on every applied cell;
 *   5. prints counts, the fresh sha, and GREEN only after both regeneration
 *      equivalence and production replay succeed.
 *
 * Usage:
 *   node registry-simulator-trace-gate.mjs
 *   node registry-simulator-trace-gate.mjs --selftest
 *
 * --selftest proves the gate can fail on scratch copies: a mutated
 * post-state, an emptied corpus, a mutated stated sha, and a flipped guard
 * in a scratch copy of the core replaying the real corpus — each RED for
 * its intended reason.
 */

import { readFileSync, writeFileSync, mkdtempSync, rmSync, cpSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createWindow } from './checkpoint-simulator-minidom.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const HTML = join(HERE, 'registry-simulator.html');
const CORE = join(HERE, 'registry-simulator-core.mjs');
const CORPUS = join(HERE, 'registry-simulator-corpus.json');
const LEAN_DIR = join(HERE, '..', 'lean');
const DRIVER = 'RegistryTraceDriver.lean';
const sha256 = b => createHash('sha256').update(b).digest('hex');

function runDriver(leanDir = LEAN_DIR) {
  execFileSync('nix', ['shell', 'nixpkgs#lean4', '-c', 'lake', 'build', 'CardanoKeri.Registry'], { cwd: leanDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return execFileSync('nix', ['shell', 'nixpkgs#lean4', '-c', 'lake', 'env', 'lean', DRIVER], { cwd: leanDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 }).trim();
}

function embedded(html) {
  const m = html.match(/const REGISTRY_LEAN_TRACES_V1 = ([\s\S]*?);\nconst REGISTRY_LEAN_TRACES_SHA256 = '([0-9a-f]*)';/);
  if (!m) throw new Error('no embedded corpus in the page');
  return { raw: m[1], sha: m[2] };
}

async function check({ fresh, corePath = CORE, html = HTML, corpusPath = CORPUS, quiet = false }) {
  const rows = [], problems = [];
  const row = (what, ok, detail) => { rows.push({ what, ok, detail }); if (!ok) problems.push(`${what}: ${detail}`); };
  let doc = null;
  try { doc = JSON.parse(fresh); row('fresh Lean output is JSON', true, `${fresh.length} bytes`); } catch (e) { row('fresh Lean output is JSON', false, e.message); }
  if (doc) {
    row('schema and version', doc.schema === 'cardano-keri.registry.trace' && doc.version === 1, `${doc.schema} v${doc.version}`);
    row('six traces, a grid, fifteen stories', Array.isArray(doc.traces) && doc.traces.length === 6 && doc.grid && doc.grid.cells.length > 0 && Array.isArray(doc.stories) && doc.stories.length === 15, `${(doc.traces || []).length} traces, ${doc.grid ? doc.grid.cells.length : 0} grid cells, ${(doc.stories || []).length} stories`);
    for (const t of doc.traces || []) if (!t.steps || !t.steps.length) row(`trace ${t.name} has steps`, false, 'empty');
  }
  const committed = readFileSync(corpusPath, 'utf8').trim();
  row('fresh output equals the committed corpus file', sha256(fresh) === sha256(committed), `fresh ${sha256(fresh).slice(0, 12)}… committed ${sha256(committed).slice(0, 12)}…`);
  const page = readFileSync(html, 'utf8');
  let emb = null;
  try { emb = embedded(page); } catch (e) { row('page embeds a corpus', false, e.message); }
  if (emb) {
    row('stated sha256 in the page equals the embedded corpus', sha256(emb.raw) === emb.sha, `${emb.sha.slice(0, 12)}…`);
    row('embedded corpus equals the fresh output', sha256(emb.raw) === sha256(fresh), `embedded ${sha256(emb.raw).slice(0, 12)}…`);
  }
  const core = await import(pathToFileURL(corePath).href + '?t=' + Date.now());
  if (doc) {
    const c = core.checkCorpus(doc);
    row('every cell replays through the core module', c.ok, c.ok ? `${c.cells} cells, ${c.applied} applied, ${c.refused} refused` : c.reasons.slice(0, 3).join(' | '));
  }
  if (emb) {
    try {
      const w = createWindow(page, {});
      const docE = JSON.parse(emb.raw);
      const c = w.checkCorpus(docE);
      row('every embedded cell replays through the page’s inlined core', c.ok && !w.__errors.length, c.ok ? `${c.cells} cells` : c.reasons.slice(0, 3).join(' | '));
    } catch (e) { row('every embedded cell replays through the page’s inlined core', false, e.message); }
  }
  if (!quiet) {
    for (const r of rows) console.log(`${r.ok ? 'ok ' : 'RED'}  ${r.what}${r.detail ? ' — ' + r.detail : ''}`);
    console.log(problems.length ? `RED: ${problems.length} problem(s)` : `GREEN: fresh Lean sha256 ${sha256(fresh)}`);
  }
  return { ok: problems.length === 0, problems };
}

async function selftest(fresh) {
  const tmp = mkdtempSync(join(tmpdir(), 'registry-trace-gate-'));
  const controls = [];
  const setup = name => { const d = join(tmp, name); mkdirSync(d); for (const f of ['registry-simulator-core.mjs', 'registry-simulator.html', 'registry-simulator-corpus.json', 'checkpoint-simulator-minidom.mjs']) cpSync(join(HERE, f), join(d, f)); return d; };
  const control = async (name, freshText, mutate, expectRe) => {
    const d = setup(name); mutate(d);
    const r = await check({ fresh: freshText, corePath: join(d, 'registry-simulator-core.mjs'), html: join(d, 'registry-simulator.html'), corpusPath: join(d, 'registry-simulator-corpus.json'), quiet: true });
    const red = !r.ok && r.problems.some(p => expectRe.test(p));
    controls.push({ name, red, why: red ? r.problems.find(p => expectRe.test(p)) : (r.ok ? 'stayed GREEN' : 'RED for another reason: ' + r.problems[0]) });
  };
  const doc = JSON.parse(fresh);
  const mutated = structuredClone(doc); { const st = mutated.traces[0].steps.find(s => s.result); st.result.state.gen += 1; }
  await control('mutated-post-state', JSON.stringify(mutated), () => {}, /replays through the core module.*post-state mismatch|fresh output equals the committed/);
  await control('emptied-corpus', JSON.stringify({ ...doc, traces: [], grid: { cells: [] }, stories: [] }), () => {}, /six traces, a grid, fifteen stories/);
  await control('mutated-stated-sha', fresh, d => { const f = join(d, 'registry-simulator.html'); writeFileSync(f, readFileSync(f, 'utf8').replace(/REGISTRY_LEAN_TRACES_SHA256 = '([0-9a-f])/, (m, c) => `REGISTRY_LEAN_TRACES_SHA256 = '${c === '0' ? '1' : '0'}`)); }, /stated sha256/);
  await control('flipped-guard-in-core', fresh, d => { const f = join(d, 'registry-simulator-core.mjs'); const t = readFileSync(f, 'utf8'); const from = 'if (!(gen === s.gen)) return refuse(REASONS.STALE_GENERATION);'; if (!t.includes(from)) throw new Error('control edit target missing'); writeFileSync(f, t.replace(from, '/* mutant: stale fold accepted */')); }, /replays through the core module/);
  rmSync(tmp, { recursive: true, force: true });
  for (const c of controls) console.log(`${c.red ? 'RED (intended)' : 'CONTROL FAILED'}  ${c.name} — ${c.why}`);
  return controls.every(c => c.red);
}

const main = async () => {
  let fresh;
  try { fresh = runDriver(); }
  catch (e) { console.error(`RED: the Lean driver did not run — from lean/: nix shell nixpkgs#lean4 -c lake build CardanoKeri.Registry && nix shell nixpkgs#lean4 -c lake env lean ${DRIVER}\n${(e.stderr || e.message || '').toString().slice(0, 2000)}`); process.exit(1); }
  if (process.argv.includes('--selftest')) {
    const ok = await selftest(fresh);
    console.log(ok ? 'controls: 4/4 red for the intended reason' : 'controls: some did not go red');
    if (!ok) process.exit(1);
  }
  const r = await check({ fresh });
  process.exit(r.ok ? 0 : 1);
};
main().catch(e => { console.error('RED: gate crashed — ' + e.stack); process.exit(1); });
