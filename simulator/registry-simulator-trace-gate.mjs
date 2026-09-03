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
 *   2. requires valid JSON, the v2 schema, six traces, a nonempty grid and
 *      fifteen stories with their forks;
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
 * post-state that every hash row accepts (committed, embedded, stated sha all
 * agree) so only the replay can catch it, an emptied corpus, forks dropped, a
 * mutated stated sha, and a flipped guard in a scratch copy of the core
 * replaying the real corpus — each RED for its intended reason; then the cold
 * control: a copy of lean/ without .lake fails with the build step removed
 * and is byte-identical with it.
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

/* The modules the driver imports, read off its import lines: a fresh clone has
   no .lake, so the gate builds them before `lake env lean`. */
function driverImports(leanDir) {
  return readFileSync(join(leanDir, DRIVER), 'utf8').split('\n').map(l => l.match(/^import (CardanoKeri\S*)/)).filter(Boolean).map(m => m[1]);
}
function runDriver(leanDir = LEAN_DIR, build = true) {
  if (build) execFileSync('nix', ['shell', 'nixpkgs#lean4', '-c', 'lake', 'build', ...driverImports(leanDir)], { cwd: leanDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
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
    row('schema and version', doc.schema === 'cardano-keri.registry.trace' && doc.version === 2, `${doc.schema} v${doc.version}`);
    const forks = (doc.stories || []).reduce((n, sc) => n + (sc.forks || []).length, 0);
    const forkCells = (doc.stories || []).reduce((n, sc) => n + (sc.forks || []).reduce((m, f) => m + (f.steps || []).length, 0), 0);
    row('six traces, a grid, fifteen stories with their forks', Array.isArray(doc.traces) && doc.traces.length === 6 && doc.grid && doc.grid.cells.length > 0 && Array.isArray(doc.stories) && doc.stories.length === 15 && forks > 0 && forkCells > 0, `${(doc.traces || []).length} traces, ${doc.grid ? doc.grid.cells.length : 0} grid cells, ${(doc.stories || []).length} stories, ${forks} forks (${forkCells} cells)`);
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
  const mutatedText = JSON.stringify(mutated);
  // the mutated post-state is also the committed corpus and the embedded one, with
  // a true sha: every hash row passes and only the replay can catch it
  await control('mutated-post-state-caught-by-replay-alone', mutatedText, d => {
    writeFileSync(join(d, 'registry-simulator-corpus.json'), mutatedText);
    const f = join(d, 'registry-simulator.html'); const t = readFileSync(f, 'utf8'); const e = embedded(t);
    writeFileSync(f, t.replace(e.raw, mutatedText).replace(`REGISTRY_LEAN_TRACES_SHA256 = '${e.sha}'`, `REGISTRY_LEAN_TRACES_SHA256 = '${sha256(mutatedText)}'`));
  }, /replays through the core module.*post-state mismatch/);
  await control('emptied-corpus', JSON.stringify({ ...doc, traces: [], grid: { cells: [] }, stories: [] }), () => {}, /six traces, a grid, fifteen stories/);
  await control('forks-dropped-from-the-corpus', JSON.stringify({ ...doc, stories: doc.stories.map(sc => ({ ...sc, forks: [] })) }), () => {}, /fifteen stories with their forks|fresh output equals the committed/);
  await control('mutated-stated-sha', fresh, d => { const f = join(d, 'registry-simulator.html'); writeFileSync(f, readFileSync(f, 'utf8').replace(/REGISTRY_LEAN_TRACES_SHA256 = '([0-9a-f])/, (m, c) => `REGISTRY_LEAN_TRACES_SHA256 = '${c === '0' ? '1' : '0'}`)); }, /stated sha256/);
  await control('flipped-guard-in-core', fresh, d => { const f = join(d, 'registry-simulator-core.mjs'); const t = readFileSync(f, 'utf8'); const from = 'if (!(gen === s.gen)) return refuse(REASONS.STALE_GENERATION);'; if (!t.includes(from)) throw new Error('control edit target missing'); writeFileSync(f, t.replace(from, '/* mutant: stale fold accepted */')); }, /replays through the core module/);
  // the cold control: a copy of lean/ without .lake (and the scenarios the driver
  // reads relative to it); with the build step removed the driver cannot resolve
  // its imports; with it, the output is byte-identical to the warm run
  const cold = join(tmp, 'repo', 'lean');
  cpSync(LEAN_DIR, cold, { recursive: true, filter: src => !/[\\/]\.lake([\\/]|$)/.test(src) });
  cpSync(join(HERE, 'registry-simulator-scenarios'), join(tmp, 'repo', 'simulator', 'registry-simulator-scenarios'), { recursive: true });
  let coldFail = null;
  try { runDriver(cold, false); } catch (e) { coldFail = String(e.stdout || '') + String(e.stderr || '') + String(e.message || ''); }
  if (coldFail === null) controls.push({ name: 'cold-copy-without-build', red: false, why: 'the driver ran with the build step removed (is .lake absent from the copy?)' });
  else if (!/unknown module prefix|No directory|olean|unknown package/.test(coldFail)) controls.push({ name: 'cold-copy-without-build', red: false, why: 'RED for another reason: ' + coldFail.slice(0, 200) });
  else controls.push({ name: 'cold-copy-without-build', red: true, why: coldFail.split('\n').find(l => /unknown|olean|No directory/.test(l)) || coldFail.slice(0, 120) });
  let coldRaw = null;
  try { coldRaw = runDriver(cold, true); } catch (e) { controls.push({ name: 'cold-copy-with-build', red: false, why: 'the cold build failed: ' + String(e.stderr || e.message).slice(0, 200) }); }
  if (coldRaw !== null) controls.push({ name: 'cold-copy-with-build', red: sha256(coldRaw) === sha256(fresh), why: sha256(coldRaw) === sha256(fresh) ? `lake build ${driverImports(cold).join(' ')} then the driver from a copy with no .lake: sha ${sha256(coldRaw).slice(0, 12)}… identical to the warm run` : 'the cold output differs from the warm run' });
  rmSync(tmp, { recursive: true, force: true });
  for (const c of controls) console.log(`${c.red ? (c.name.startsWith('cold-copy-with') ? 'GREEN (intended)' : 'RED (intended)') : 'CONTROL FAILED'}  ${c.name} — ${c.why}`);
  return controls.every(c => c.red);
}

const main = async () => {
  let fresh;
  try { fresh = runDriver(); }
  catch (e) { console.error(`RED: the Lean driver did not run — from lean/: nix shell nixpkgs#lean4 -c lake build CardanoKeri.Registry && nix shell nixpkgs#lean4 -c lake env lean ${DRIVER}\n${(e.stderr || e.message || '').toString().slice(0, 2000)}`); process.exit(1); }
  if (process.argv.includes('--selftest')) {
    const ok = await selftest(fresh);
    console.log(ok ? 'controls: 5 negative controls red for the intended reason; the cold copy red without the build and byte-identical with it' : 'controls: some did not behave as intended');
    if (!ok) process.exit(1);
  }
  const r = await check({ fresh });
  process.exit(r.ok ? 0 : 1);
};
main().catch(e => { console.error('RED: gate crashed — ' + e.stack); process.exit(1); });
