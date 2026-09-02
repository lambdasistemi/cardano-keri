#!/usr/bin/env node
/*
 * checkpoint-simulator-build.mjs — deterministic inliner of the ONE machine
 * core into the publishable zero-external-request single-file page.
 *
 * simulator/checkpoint-simulator-core.mjs is the single source of the
 * machine core; simulator/checkpoint-simulator.html embeds its slices
 * verbatim between paired markers `/* @@CORE:<id>@@ *​/ …
 * `/* @@CORE:<id>:END@@ *​/`, and the fifteen stories between
 * `/* @@SCENARIOS@@ *​/ … `/* @@SCENARIOS:END@@ *​/`. This script:
 *
 *   default:  regenerate the page in place from the core and the scenarios
 *             directory (splice every slice; report what changed);
 *   --check:  compare without writing; exit 1 listing every stale or forked
 *             slice (used by checkpoint-simulator-scenario-gate.mjs to RED
 *             on a stale generated artifact or a forked copy).
 *
 * The slice set is discovered from the core file; a slice present in one
 * file and missing in the other is an error, so neither side can silently
 * grow a second transcription. The SCENARIOS block is generated from
 * simulator/checkpoint-simulator-scenarios/ (sorted by story id); a story
 * file the page has not embedded is drift, and drift is red.
 *
 * --html/--core/--scenarios overrides exist for negative controls
 * (checking scratch copies); production callers use the defaults.
 */

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = dirname(fileURLToPath(import.meta.url));
const argPath = flag => {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null;
};
const HTML = argPath('--html') || join(REPO, 'checkpoint-simulator.html');
const CORE = argPath('--core') || join(REPO, 'checkpoint-simulator-core.mjs');
const SCEN_DIR = argPath('--scenarios') || join(REPO, 'checkpoint-simulator-scenarios');

const sliceRe = id => new RegExp(
  `/\\* @@CORE:${id}@@ \\*/\\n([\\s\\S]*?)/\\* @@CORE:${id}:END@@ \\*/`);
const scenRe = () => /\/\* @@SCENARIOS@@ \*\/([\s\S]*?)\/\* @@SCENARIOS:END@@ \*\//;

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

function scenariosJson(dir) {
  const files = readdirSync(dir).filter(f => f.endsWith('.json')).sort();
  if (!files.length) throw new Error(`no scenario JSON in ${dir}`);
  const scenarios = files.map(f => JSON.parse(readFileSync(join(dir, f), 'utf8')));
  scenarios.sort((a, b) => a.id - b.id);
  const ids = scenarios.map(s => s.id);
  for (let i = 1; i <= scenarios.length; i++)
    if (!ids.includes(i)) throw new Error(`story ${i} missing from ${dir}`);
  return JSON.stringify(scenarios, null, 1).replace(/\n/g, '\n');
}

const core = readFileSync(CORE, 'utf8');
const html = readFileSync(HTML, 'utf8');
const coreSlices = slicesOf(core, 'checkpoint-simulator-core.mjs');
const htmlSlices = slicesOf(html, 'checkpoint-simulator.html');

const coreIds = Object.keys(coreSlices).sort();
const htmlIds = Object.keys(htmlSlices).sort();
if (JSON.stringify(coreIds) !== JSON.stringify(htmlIds)) {
  console.error('RED: diverging slice sets — core=[' + coreIds +
    '] page=[' + htmlIds + ']');
  process.exit(1);
}

const stale = coreIds.filter(id => coreSlices[id] !== htmlSlices[id]);

const wantScen = scenariosJson(SCEN_DIR);
const scenBlock = html.match(scenRe());
if (!scenBlock) {
  console.error('RED: no @@SCENARIOS@@ block in the page');
  process.exit(1);
}
const scenStale = scenBlock[1] !== '\n' + wantScen + '\n';

if (process.argv.includes('--check')) {
  if (stale.length || scenStale) {
    const why = [];
    if (stale.length) why.push(`${stale.length} core slice(s) stale or forked: ${stale.join(', ')}`);
    if (scenStale) why.push('the embedded stories have drifted from checkpoint-simulator-scenarios/');
    console.error('RED: generated artifact stale or forked — ' + why.join('; '));
    process.exit(1);
  }
  console.log(`GREEN: ${coreIds.length} core slices identical byte-per-byte and ` +
    `${scenBlock[1].split('"id"').length - 1} embedded stories match the scenarios directory`);
  process.exit(0);
}

if (!stale.length && !scenStale) {
  console.log(`page already up to date: ${coreIds.length} slices identical, stories embedded`);
  process.exit(0);
}
let out = html;
for (const id of stale)
  out = out.replace(sliceRe(id),
    `/* @@CORE:${id}@@ */\n${coreSlices[id]}/* @@CORE:${id}:END@@ */`);
if (scenStale)
  out = out.replace(scenRe(), `/* @@SCENARIOS@@ */\n${wantScen}\n/* @@SCENARIOS:END@@ */`);
writeFileSync(HTML, out);
const changed = [];
if (stale.length) changed.push(`core slices: ${stale.join(', ')}`);
if (scenStale) changed.push('stories');
console.log(`page regenerated from the core: updated ${changed.join(' and ')}`);
