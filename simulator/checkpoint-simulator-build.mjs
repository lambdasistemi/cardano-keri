#!/usr/bin/env node
/*
 * checkpoint-simulator-build.mjs — deterministic inliner of the ONE core,
 * the fifteen scenarios and the Lean corpus into the publishable
 * zero-network single-file page, plus the byte-identical docs copy.
 *
 * checkpoint-simulator-core.mjs is the single source of the machine;
 * checkpoint-simulator.html embeds its slices verbatim between paired
 * markers `/* @@CORE:<id>@@ *​/ … /* @@CORE:<id>:END@@ *​/`, the scenario
 * files between `@@SCENARIOS@@` markers and the Lean corpus (with its
 * sha256) between `@@CORPUS@@` markers. This script:
 *
 *   default:   regenerate the page in place and write docs/simulator/index.html
 *              byte-identical to it; report what changed;
 *   --check:   compare without writing; exit 1 listing every stale or forked
 *              slice, stale scenario/corpus embedding, or drifted docs copy.
 *
 * The slice set is discovered from the core; a slice present in one file and
 * missing in the other is an error, so neither side can silently grow a
 * second transcription.
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const argPath = flag => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const HTML = argPath('--html') || join(HERE, 'checkpoint-simulator.html');
const CORE = argPath('--core') || join(HERE, 'checkpoint-simulator-core.mjs');
const SCENARIOS = join(HERE, 'checkpoint-simulator-scenarios');
const CORPUS = join(HERE, 'checkpoint-simulator-corpus.json');
const DOCS = argPath('--docs') || join(HERE, '..', 'docs', 'simulator', 'index.html');
const CHECK = process.argv.includes('--check');
const sha256 = b => createHash('sha256').update(b).digest('hex');

const sliceRe = id => new RegExp(`/\\* @@CORE:${id}@@ \\*/\\n([\\s\\S]*?)/\\* @@CORE:${id}:END@@ \\*/`);
function slicesOf(text, what) {
  const ids = [...text.matchAll(/\/\* @@CORE:([a-z-]+)@@ \*\//g)].map(m => m[1]);
  if (!ids.length) throw new Error(`no @@CORE@@ slice in ${what}`);
  const out = {};
  for (const id of ids) {
    const m = text.match(sliceRe(id));
    if (!m) throw new Error(`slice ${id} has no closing marker in ${what}`);
    out[id] = m[1];
  }
  return out;
}
const blockRe = tag => new RegExp(`/\\* @@${tag}@@ \\*/\\n([\\s\\S]*?)/\\* @@${tag}:END@@ \\*/`);

const core = readFileSync(CORE, 'utf8');
let html = readFileSync(HTML, 'utf8');
const coreSlices = slicesOf(core, 'checkpoint-simulator-core.mjs');
const htmlSlices = slicesOf(html, 'checkpoint-simulator.html');
const coreIds = Object.keys(coreSlices).sort();
const htmlIds = Object.keys(htmlSlices).sort();
const problems = [];
if (JSON.stringify(coreIds) !== JSON.stringify(htmlIds))
  problems.push(`slice sets diverge — core=[${coreIds}] page=[${htmlIds}]`);
const stale = coreIds.filter(id => htmlSlices[id] !== undefined && coreSlices[id] !== htmlSlices[id]);

// scenarios: one JSON per story, embedded as an array sorted by file name
const files = readdirSync(SCENARIOS).filter(f => f.endsWith('.json')).sort();
const scenarios = files.map(f => JSON.parse(readFileSync(join(SCENARIOS, f), 'utf8')));
const scenarioBlock = `const SCENARIOS = ${JSON.stringify(scenarios)};\n`;
const corpusText = readFileSync(CORPUS, 'utf8');
const corpusSha = sha256(corpusText);
const corpusBlock = `const LEAN_CORPUS = ${corpusText.trim()};\nconst LEAN_CORPUS_SHA256 = '${corpusSha}';\n`;

const scM = html.match(blockRe('SCENARIOS'));
const coM = html.match(blockRe('CORPUS'));
if (!scM) problems.push('page has no @@SCENARIOS@@ block');
if (!coM) problems.push('page has no @@CORPUS@@ block');
const scenariosStale = scM && scM[1] !== scenarioBlock;
const corpusStale = coM && coM[1] !== corpusBlock;

if (problems.length) {
  console.error('RED: ' + problems.join('; '));
  process.exit(1);
}

let out = html;
for (const id of stale)
  out = out.replace(sliceRe(id), () => `/* @@CORE:${id}@@ */\n${coreSlices[id]}/* @@CORE:${id}:END@@ */`);
if (scenariosStale) out = out.replace(blockRe('SCENARIOS'), () => `/* @@SCENARIOS@@ */\n${scenarioBlock}/* @@SCENARIOS:END@@ */`);
if (corpusStale) out = out.replace(blockRe('CORPUS'), () => `/* @@CORPUS@@ */\n${corpusBlock}/* @@CORPUS:END@@ */`);

const docsCurrent = existsSync(DOCS) ? readFileSync(DOCS, 'utf8') : null;
const docsStale = docsCurrent !== out;
const changes = [
  ...stale.map(id => `slice ${id}`),
  ...(scenariosStale ? ['scenarios'] : []),
  ...(corpusStale ? ['corpus'] : []),
  ...(docsStale ? ['docs/simulator/index.html'] : []),
];

if (CHECK) {
  if (changes.length) {
    console.error(`RED: generated artifact stale or forked — ${changes.join(', ')}`);
    process.exit(1);
  }
  console.log(`GREEN: ${coreIds.length} core slices, ${scenarios.length} scenarios and the Lean corpus ` +
    `(sha256 ${corpusSha.slice(0, 12)}…) identical between sources, the page and docs/simulator/index.html`);
  process.exit(0);
}
if (!changes.length) { console.log(`already up to date: ${coreIds.length} slices, ${scenarios.length} scenarios, corpus ${corpusSha.slice(0, 12)}…`); process.exit(0); }
if (out !== html) writeFileSync(HTML, out);
mkdirSync(dirname(DOCS), { recursive: true });
writeFileSync(DOCS, out);
console.log(`page regenerated: ${changes.join(', ')}`);
