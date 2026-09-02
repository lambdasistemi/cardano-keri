#!/usr/bin/env node
/*
 * registry-simulator-build.mjs — deterministic inliner of the ONE machine
 * core, the fifteen stories and the Lean corpus into the publishable
 * zero-external-request single-file page, and its published copy.
 *
 * simulator/registry-simulator-core.mjs is the single source of the machine
 * core; simulator/registry-simulator.html embeds its slices verbatim between
 * paired markers `/* @@CORE:<id>@@ *​/ … /* @@CORE:<id>:END@@ *​/`, the
 * stories between `/* @@SCENARIOS@@ *​/ … /* @@SCENARIOS:END@@ *​/`, and the
 * corpus (with its sha256) between `/* @@CORPUS@@ *​/ … /* @@CORPUS:END@@ *​/`.
 *
 *   default:  regenerate the page in place and write the byte-identical
 *             published copy docs/simulator/registry/index.html;
 *   --check:  compare without writing; exit 1 listing every stale or forked
 *             slice, drifted story block, drifted corpus block or drifted
 *             published copy.
 *
 * The slice set is discovered from the core file; a slice present in one
 * file and missing in the other is an error, so neither side can silently
 * grow a second transcription. --html/--core/--scenarios/--corpus/--docs
 * overrides exist for negative controls; production callers use the defaults.
 */

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const argPath = flag => { const i = process.argv.indexOf(flag); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null; };
const HTML = argPath('--html') || join(HERE, 'registry-simulator.html');
const CORE = argPath('--core') || join(HERE, 'registry-simulator-core.mjs');
const SCEN_DIR = argPath('--scenarios') || join(HERE, 'registry-simulator-scenarios');
const CORPUS = argPath('--corpus') || join(HERE, 'registry-simulator-corpus.json');
const DOCS = argPath('--docs') || join(HERE, '..', 'docs', 'simulator', 'registry', 'index.html');
const N_STORIES = 15;

const sliceRe = id => new RegExp(`/\\* @@CORE:${id}@@ \\*/\\n([\\s\\S]*?)/\\* @@CORE:${id}:END@@ \\*/`);
const scenRe = /\/\* @@SCENARIOS@@ \*\/\n([\s\S]*?)\/\* @@SCENARIOS:END@@ \*\//;
const corpusRe = /\/\* @@CORPUS@@ \*\/\n([\s\S]*?)\/\* @@CORPUS:END@@ \*\//;
const sha256 = b => createHash('sha256').update(b).digest('hex');

function slicesOf(text, what) {
  const ids = [...text.matchAll(/\/\* @@CORE:([a-z0-9-]+)@@ \*\//g)].map(m => m[1]);
  if (!ids.length) throw new Error(`no @@CORE@@ slice in ${what}`);
  const out = {};
  for (const id of ids) {
    const m = text.match(sliceRe(id));
    if (!m) throw new Error(`slice ${id} without a closing marker in ${what}`);
    out[id] = m[1];
  }
  return out;
}

function scenariosBlock(dir) {
  const files = readdirSync(dir).filter(f => f.endsWith('.json')).sort();
  if (!files.length) throw new Error(`no scenario JSON in ${dir}`);
  const scenarios = files.map(f => JSON.parse(readFileSync(join(dir, f), 'utf8')));
  scenarios.sort((a, b) => a.id - b.id);
  const ids = scenarios.map(s => s.id);
  for (let i = 1; i <= N_STORIES; i++) if (!ids.includes(i)) throw new Error(`story ${i} missing from ${dir}`);
  if (scenarios.length !== N_STORIES) throw new Error(`${scenarios.length} stories in ${dir}, expected ${N_STORIES}`);
  return `const SCENARIOS = ${JSON.stringify(scenarios)};\n`;
}

function corpusBlock(path) {
  const raw = readFileSync(path, 'utf8').trim();
  JSON.parse(raw); // must be JSON
  return `const REGISTRY_LEAN_TRACES_V1 = ${raw};\nconst REGISTRY_LEAN_TRACES_SHA256 = '${sha256(raw)}';\n`;
}

const core = readFileSync(CORE, 'utf8');
const html = readFileSync(HTML, 'utf8');
const coreSlices = slicesOf(core, 'registry-simulator-core.mjs');
const htmlSlices = slicesOf(html, 'registry-simulator.html');
const coreIds = Object.keys(coreSlices).sort(), htmlIds = Object.keys(htmlSlices).sort();
if (JSON.stringify(coreIds) !== JSON.stringify(htmlIds)) {
  console.error(`RED: diverging slice sets — core=[${coreIds}] page=[${htmlIds}]`);
  process.exit(1);
}
const stale = coreIds.filter(id => coreSlices[id] !== htmlSlices[id]);
const wantScen = scenariosBlock(SCEN_DIR);
const scenBlock = html.match(scenRe);
if (!scenBlock) { console.error('RED: no @@SCENARIOS@@ block in the page'); process.exit(1); }
const scenStale = scenBlock[1] !== wantScen;
const wantCorpus = corpusBlock(CORPUS);
const corpBlock = html.match(corpusRe);
if (!corpBlock) { console.error('RED: no @@CORPUS@@ block in the page'); process.exit(1); }
const corpusStale = corpBlock[1] !== wantCorpus;

let out = html;
for (const id of stale) out = out.replace(sliceRe(id), `/* @@CORE:${id}@@ */\n${coreSlices[id]}/* @@CORE:${id}:END@@ */`);
if (scenStale) out = out.replace(scenRe, `/* @@SCENARIOS@@ */\n${wantScen}/* @@SCENARIOS:END@@ */`);
if (corpusStale) out = out.replace(corpusRe, `/* @@CORPUS@@ */\n${wantCorpus}/* @@CORPUS:END@@ */`);
const docsStale = !existsSync(DOCS) || readFileSync(DOCS, 'utf8') !== out;

if (process.argv.includes('--check')) {
  const why = [];
  if (stale.length) why.push(`${stale.length} core slice(s) stale or forked: ${stale.join(', ')}`);
  if (scenStale) why.push('the embedded stories have drifted from registry-simulator-scenarios/');
  if (corpusStale) why.push('the embedded corpus has drifted from registry-simulator-corpus.json');
  if (docsStale) why.push('docs/simulator/registry/index.html is not the byte-identical page');
  if (why.length) { console.error('RED: generated artifact stale or forked — ' + why.join('; ')); process.exit(1); }
  console.log(`GREEN: ${coreIds.length} core slices identical byte-per-byte, ${N_STORIES} stories and the corpus (sha256 ${sha256(readFileSync(CORPUS, 'utf8').trim()).slice(0, 12)}…) embedded, published copy identical`);
  process.exit(0);
}

if (stale.length || scenStale || corpusStale) writeFileSync(HTML, out);
if (docsStale) { mkdirSync(dirname(DOCS), { recursive: true }); writeFileSync(DOCS, out); }
const changed = [];
if (stale.length) changed.push(`core slices: ${stale.join(', ')}`);
if (scenStale) changed.push('stories');
if (corpusStale) changed.push('corpus');
if (docsStale) changed.push('published copy');
console.log(changed.length ? `page regenerated: updated ${changed.join(', ')}` : 'page already up to date');
