#!/usr/bin/env node
/*
 * scenario-dsl-gate.mjs — permanent proof of the scenario DSL seam.
 *
 * Discovers authored .dsl sources (does not list them), compiles them
 * through the one grammar and the documented CLI, requires deep equality
 * with the checked-in JSON, replays through the existing checkers, drives
 * both generated pages for paste/file play and branch export, and proves
 * each guard class can fail on a verified scratch mutation.
 *
 * GREEN prints the 30 / 104 / 115 denominators. Empty or truncated
 * discovery is a refusal, not a smaller success.
 */

import { readFileSync, writeFileSync, readdirSync, mkdtempSync, rmSync, cpSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { createWindow } from './checkpoint-simulator-minidom.mjs';
import * as ckCore from './checkpoint-simulator-core.mjs';
import * as rgCore from './registry-simulator-core.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const GRAMMAR = join(HERE, 'scenario-dsl.mjs');
const CLI = join(HERE, 'scenario-dsl-cli.mjs');
const CK_DIR = join(HERE, 'checkpoint-simulator-scenarios');
const RG_DIR = join(HERE, 'registry-simulator-scenarios');
const CK_HTML = join(HERE, 'checkpoint-simulator.html');
const RG_HTML = join(HERE, 'registry-simulator.html');
const CK_BUILD = join(HERE, 'checkpoint-simulator-build.mjs');
const RG_BUILD = join(HERE, 'registry-simulator-build.mjs');
const CK_CORPUS = join(HERE, 'checkpoint-simulator-corpus.json');
const RG_CORPUS = join(HERE, 'registry-simulator-corpus.json');
const DOCUMENTED = [
  process.execPath,
  'simulator/scenario-dsl-cli.mjs',
  'to-json',
  '--family',
  'checkpoint',
  'simulator/checkpoint-simulator-scenarios/01-alice-appears.dsl',
];
const WANT = { total: 30, checkpointFiles: 15, registryFiles: 15, checkpointSteps: 104, registrySteps: 115 };

const sha256 = b => createHash('sha256').update(b).digest('hex');
const rows = [];
const problems = [];
function row(inv, ok, detail) {
  rows.push({ inv, ok, detail: String(detail || '') });
  if (!ok) problems.push(`${inv}: ${detail}`);
}
function sameJson(a, b) {
  const canon = x => {
    if (Array.isArray(x)) return '[' + x.map(canon).join(',') + ']';
    if (x !== null && typeof x === 'object') {
      return '{' + Object.keys(x).filter(k => x[k] !== undefined).sort()
        .map(k => JSON.stringify(k) + ':' + canon(x[k])).join(',') + '}';
    }
    return JSON.stringify(x);
  };
  return canon(a) === canon(b);
}
function discover(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter(f => f.endsWith('.dsl')).sort().map(f => join(dir, f));
}
function jsonBeside(dslPath) {
  return dslPath.replace(/\.dsl$/, '.json');
}
function scratch() {
  return mkdtempSync(join(tmpdir(), 's375-dsl-'));
}
function mutated(path, from, to) {
  const before = readFileSync(path, 'utf8');
  if (!before.includes(from)) return { ok: false, why: `mutation subject missing ${JSON.stringify(from)}` };
  const after = before.split(from).join(to);
  if (after === before || sha256(after) === sha256(before)) return { ok: false, why: 'mutation did not change the file' };
  if (!after.includes(to)) return { ok: false, why: 'mutation result missing replacement' };
  writeFileSync(path, after);
  return { ok: true, before: sha256(before), after: sha256(readFileSync(path)) };
}
function loadJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}
function stripField(obj, field) {
  const c = structuredClone(obj);
  const walk = x => {
    if (!x || typeof x !== 'object') return;
    if (Array.isArray(x)) { x.forEach(walk); return; }
    delete x[field];
    Object.values(x).forEach(walk);
  };
  walk(c);
  return c;
}

let grammar = null, cliMod = null, ckSteps = 0, rgSteps = 0, nScenarios = 0;

async function loadGrammar() {
  if (!existsSync(GRAMMAR)) return null;
  return import(pathToFileURL(GRAMMAR).href + '?t=' + Date.now());
}
async function loadCli() {
  if (!existsSync(CLI)) return null;
  return import(pathToFileURL(CLI).href + '?t=' + Date.now());
}

function checkComparator() {
  const orig = loadJson(join(CK_DIR, '01-alice-appears.json'));
  if (sameJson(orig, orig) !== true) { row('INV-375-LOSSLESS', false, 'comparator does not accept identity'); return; }
  const noExpect = stripField(orig, 'expect');
  const noFlow = stripField(orig, 'flow');
  const noExhibits = stripField(orig, 'exhibits');
  const e1 = !sameJson(noExpect, orig);
  const e2 = !sameJson(noFlow, orig);
  const e3 = !sameJson(noExhibits, orig);
  row('INV-375-LOSSLESS', e1 && e2 && e3,
    e1 && e2 && e3
      ? 'comparator reds when expect, flow, or exhibits is stripped from a real scenario'
      : `comparator stayed equal after strip expect=${e1} flow=${e2} exhibits=${e3}`);
}

function checkExtentGuards() {
  const empty = scratch();
  mkdirSync(join(empty, 'ck')); mkdirSync(join(empty, 'rg'));
  const emptyCk = discover(join(empty, 'ck'));
  const emptyRg = discover(join(empty, 'rg'));
  const emptyFails = emptyCk.length + emptyRg.length !== WANT.total;
  const short = scratch();
  mkdirSync(join(short, 'ck')); mkdirSync(join(short, 'rg'));
  for (let i = 0; i < 14; i++) writeFileSync(join(short, 'ck', `s${i}.dsl`), 'grammar: 1\n');
  for (let i = 0; i < 15; i++) writeFileSync(join(short, 'rg', `s${i}.dsl`), 'grammar: 1\n');
  const shortCk = discover(join(short, 'ck'));
  const shortRg = discover(join(short, 'rg'));
  const shortFails = !(shortCk.length === WANT.checkpointFiles && shortRg.length === WANT.registryFiles && shortCk.length + shortRg.length === WANT.total);
  rmSync(empty, { recursive: true, force: true });
  rmSync(short, { recursive: true, force: true });
  row('INV-375-EXTENT', emptyFails && shortFails,
    emptyFails && shortFails
      ? 'empty and one-file-short scratch sets fail the extent guard'
      : `emptyFails=${emptyFails} shortFails=${shortFails}`);
}

function checkLosslessCompile() {
  const ckFiles = discover(CK_DIR);
  const rgFiles = discover(RG_DIR);
  nScenarios = ckFiles.length + rgFiles.length;
  if (!grammar) {
    row('INV-375-LOSSLESS', false, 'shared grammar module missing; cannot compile discovered sources');
    row('INV-375-EXTENT', nScenarios === WANT.total && ckFiles.length === WANT.checkpointFiles && rgFiles.length === WANT.registryFiles,
      `discovered ${ckFiles.length}+${rgFiles.length}=${nScenarios}, want ${WANT.checkpointFiles}+${WANT.registryFiles}=${WANT.total}`);
    return;
  }
  let ok = true;
  const details = [];
  const families = [['checkpoint', ckFiles, ckCore, CK_CORPUS], ['registry', rgFiles, rgCore, RG_CORPUS]];
  for (const [family, files, core, corpusPath] of families) {
    let corpus = null;
    try { corpus = JSON.parse(readFileSync(corpusPath, 'utf8')); } catch (e) { ok = false; details.push(`${family} corpus: ${e.message}`); }
    let steps = 0;
    for (const f of files) {
      const jsonPath = jsonBeside(f);
      if (!existsSync(jsonPath)) { ok = false; details.push(`${basename(f)}: no sibling JSON`); continue; }
      const want = loadJson(jsonPath);
      let doc, got, again;
      try { doc = grammar.parseScenarioDsl(readFileSync(f, 'utf8'), basename(f)); }
      catch (e) { ok = false; details.push(`${basename(f)}: parse ${e.message}`); continue; }
      if (doc.family !== family) { ok = false; details.push(`${basename(f)}: family ${doc.family}`); continue; }
      if (doc.scenario == null) { ok = false; details.push(`${basename(f)}: no scenario`); continue; }
      got = grammar.scenarioFromDsl(readFileSync(f, 'utf8'), basename(f));
      if (!sameJson(got, want)) { ok = false; details.push(`${basename(f)}: DSL→JSON ≠ checked-in JSON`); continue; }
      const dsl2 = grammar.scenarioToDsl(family, want);
      again = grammar.scenarioFromDsl(dsl2, basename(f) + '.round');
      if (!sameJson(again, want)) { ok = false; details.push(`${basename(f)}: JSON→DSL→JSON ≠ JSON`); continue; }
      const r = core.checkScenario(got, basename(f), corpus);
      if (r.problems && r.problems.length) { ok = false; details.push(`${basename(f)}: checker ${r.problems.slice(0, 2).join(' | ')}`); }
      steps += r.stepsRun || 0;
    }
    if (family === 'checkpoint') ckSteps = steps; else rgSteps = steps;
  }
  const extentOk = nScenarios === WANT.total
    && ckFiles.length === WANT.checkpointFiles
    && rgFiles.length === WANT.registryFiles
    && ckSteps === WANT.checkpointSteps
    && rgSteps === WANT.registrySteps;
  row('INV-375-LOSSLESS', ok, ok ? `compiled ${nScenarios} sources, JSON round-trip equal` : details.slice(0, 8).join(' | '));
  row('INV-375-EXTENT', extentOk,
    `discovered ${ckFiles.length}+${rgFiles.length}=${nScenarios} (want ${WANT.total}); steps ${ckSteps}/${rgSteps} (want ${WANT.checkpointSteps}/${WANT.registrySteps})`);
}

function checkOne() {
  if (!grammar) { row('INV-375-ONE', false, 'shared grammar module missing'); return; }
  const v = grammar.GRAMMAR_VERSION;
  if (typeof v !== 'string' || !v) { row('INV-375-ONE', false, 'GRAMMAR_VERSION is not a non-empty string'); return; }
  try { grammar.assertGrammarVersion(v); }
  catch (e) { row('INV-375-ONE', false, `matching assert threw: ${e.message}`); return; }
  let mismatch = false;
  try { grammar.assertGrammarVersion(v + '-other'); }
  catch (e) { mismatch = true; if (!/version/i.test(e.message)) mismatch = false; }
  if (!mismatch) { row('INV-375-ONE', false, 'assertGrammarVersion accepted a different expected version'); return; }
  const d = scratch();
  cpSync(GRAMMAR, join(d, 'scenario-dsl.mjs'));
  const mut = mutated(join(d, 'scenario-dsl.mjs'), `const GRAMMAR_VERSION = '${v}'`, `const GRAMMAR_VERSION = '${v}-mut'`);
  if (!mut.ok) { rmSync(d, { recursive: true, force: true }); row('INV-375-ONE', false, mut.why); return; }
  writeFileSync(join(d, 'consumer.mjs'),
    `import { assertGrammarVersion } from './scenario-dsl.mjs';\nassertGrammarVersion(${JSON.stringify(v)});\n`);
  let failed = false, out = '';
  try {
    execFileSync(process.execPath, [join(d, 'consumer.mjs')], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    failed = true;
    out = String(e.stderr || e.stdout || e.message);
  }
  rmSync(d, { recursive: true, force: true });
  row('INV-375-ONE', failed,
    failed ? `scratch version bump with consumer still asserting ${JSON.stringify(v)} failed: ${out.split('\n')[0]}` : 'scratch consumer still succeeded after version bump');
}

function checkRunnable() {
  if (!existsSync(CLI) || !existsSync(join(CK_DIR, '01-alice-appears.dsl'))) {
    row('INV-375-RUNNABLE', false, 'documented CLI or 01-alice-appears.dsl missing');
    return;
  }
  let out, err = '';
  try {
    out = execFileSync(DOCUMENTED[0], DOCUMENTED.slice(1), { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    row('INV-375-RUNNABLE', false, `to-json failed: ${(e.stderr || e.message || '').toString().slice(0, 240)}`);
    return;
  }
  let sc;
  try { sc = JSON.parse(out); } catch (e) { row('INV-375-RUNNABLE', false, 'to-json stdout is not JSON: ' + e.message); return; }
  const want = loadJson(join(CK_DIR, '01-alice-appears.json'));
  if (!sameJson(sc, want)) { row('INV-375-RUNNABLE', false, 'to-json JSON is not deeply equal to the checked-in scenario'); return; }
  const corpus = JSON.parse(readFileSync(CK_CORPUS, 'utf8'));
  const r = ckCore.checkScenario(sc, '01-alice-appears.dsl', corpus);
  if (r.problems.length) { row('INV-375-RUNNABLE', false, 'checker refused to-json output: ' + r.problems[0]); return; }
  let back;
  try {
    back = execFileSync(process.execPath, [
      'simulator/scenario-dsl-cli.mjs', 'from-json', '--family', 'checkpoint',
      'simulator/checkpoint-simulator-scenarios/01-alice-appears.json',
    ], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    row('INV-375-RUNNABLE', false, `from-json failed: ${(e.stderr || e.message || '').toString().slice(0, 240)}`);
    return;
  }
  if (!cliMod || typeof cliMod.runScenarioDslCli !== 'function') {
    row('INV-375-RUNNABLE', false, 'runScenarioDslCli is not exported');
    return;
  }
  const buf = [];
  const code = cliMod.runScenarioDslCli(['to-json', '--family', 'checkpoint', join(CK_DIR, '01-alice-appears.dsl')], null, {
    writeOut: s => buf.push(s),
    writeErr: s => { err += s; },
  });
  if (code !== 0) { row('INV-375-RUNNABLE', false, `runScenarioDslCli exit ${code}: ${err}`); return; }
  row('INV-375-RUNNABLE', true, `documented to-json accepted by checker (${r.stepsRun} steps); from-json emitted ${back.length} bytes`);
}

async function checkAtomic() {
  if (!grammar || !cliMod) { row('INV-375-ATOMIC', false, 'grammar or CLI missing; cannot refuse malformed input'); return; }
  const cases = [
    { name: 'line1', text: 'this is not a scenario\n', wantLine: 1 },
    {
      name: 'after-valid',
      text: [
        'grammar: 1',
        'family: checkpoint',
        'story: 1',
        'title: "x"',
        'goal: "y"',
        'params:',
        '  D: 1000',
        '  B: 5',
        '  P: 2',
        '  W: 10',
        'atoms:',
        '  - a.b',
        'step:',
        '  slot: 0',
        '  who: treasury',
        '  say: "ok"',
        '  expect:',
        '    verdict: not-present',
        'THIS IS JUNK',
        '',
      ].join('\n'),
      wantLine: 19,
    },
  ];
  const errs = [];
  for (const c of cases) {
    let threw = false, err = null;
    try { grammar.parseScenarioDsl(c.text, c.name + '.dsl'); }
    catch (e) { threw = true; err = e; }
    if (!threw) { errs.push(`${c.name}: parser returned a document`); continue; }
    if (err.scenario) errs.push(`${c.name}: refusal carried a scenario`);
    const line = err.line || (err.diagnostic && err.diagnostic.line);
    const src = err.sourceName || (err.diagnostic && err.diagnostic.sourceName);
    if (line !== c.wantLine) errs.push(`${c.name}: line ${line}, want ${c.wantLine}`);
    if (src !== c.name + '.dsl') errs.push(`${c.name}: sourceName ${src}`);
    const diag = String(err.message || '');
    if (!diag.includes(c.name + '.dsl') || !String(line).length) errs.push(`${c.name}: message lacks file:line (${diag.slice(0, 80)})`);
    const d = scratch();
    writeFileSync(join(d, c.name + '.dsl'), c.text);
    let code = 0, stderr = '';
    try {
      code = cliMod.runScenarioDslCli(['to-json', '--family', 'checkpoint', join(d, c.name + '.dsl')], null, {
        writeOut: () => {},
        writeErr: s => { stderr += s; },
      });
    } catch (e) { code = 1; stderr += e.message; }
    rmSync(d, { recursive: true, force: true });
    if (code === 0) errs.push(`${c.name}: CLI exited 0`);
    if (!stderr.includes(c.name + '.dsl')) errs.push(`${c.name}: CLI stderr lacks source file`);
  }
  const unsafeName = 'full-except-D.dsl';
  const unsafeComplete = [
    'grammar: 1',
    'family: checkpoint',
    'story: 1',
    'title: "x"',
    'goal: "y"',
    'params:',
    '  D: 9007199254740992',
    '  B: 5',
    '  P: 2',
    '  W: 10',
    'atoms: [a.b]',
    'step:',
    '  slot: 0',
    '  who: treasury',
    '  say: "ok"',
    '  expect:',
    '    verdict: not-present',
    '',
  ].join('\n');
  const safeComplete = unsafeComplete.replace('9007199254740992', '1000');
  try { grammar.parseScenarioDsl(safeComplete, unsafeName); }
  catch (e) { errs.push('control document (D=1000) refused: ' + e.message); }
  let unsafeErr = null;
  try { grammar.parseScenarioDsl(unsafeComplete, unsafeName); }
  catch (e) { unsafeErr = e; }
  if (!unsafeErr) errs.push('unsafe integer 2^53 was accepted on an otherwise valid document');
  else {
    if (/nat|integer|safe/i.test(unsafeErr.sourceName || '')) errs.push('unsafe-integer sourceName contaminates the reason assertion');
    const reason = (unsafeErr.diagnostic && unsafeErr.diagnostic.message) || '';
    if (!/safe JSON integer/i.test(reason)) errs.push('unsafe-integer reason was «' + reason + '», not a safe-integer refusal');
    if (unsafeErr.line !== 7) errs.push('unsafe-integer line ' + unsafeErr.line + ', want the D field (7)');
  }
  const weakDir = scratch();
  cpSync(GRAMMAR, join(weakDir, 'scenario-dsl.mjs'));
  const weakMut = mutated(join(weakDir, 'scenario-dsl.mjs'), 'Number.isSafeInteger', 'Number.isInteger');
  if (!weakMut.ok) errs.push('unsafe-integer can-fail mutation: ' + weakMut.why);
  else {
    let accepted = false;
    try {
      const weak = await import(pathToFileURL(join(weakDir, 'scenario-dsl.mjs')).href + '?weak=' + Date.now());
      weak.parseScenarioDsl(unsafeComplete, unsafeName);
      accepted = true;
    } catch (e) { accepted = false; }
    if (!accepted) errs.push('weakened isSafeInteger still refused the otherwise-valid 2^53 document (fixture invalid for another reason)');
  }
  rmSync(weakDir, { recursive: true, force: true });
  row('INV-375-ATOMIC', errs.length === 0, errs.length ? errs.join(' | ') : 'line-1 and after-valid refusals locate file:line and yield no scenario; 2^53 refused by reason on an otherwise-valid document');
}

function pageApi(win) {
  return win.CK || win.RS || {};
}

function snapshotPlay(win) {
  const api = pageApi(win);
  const app = api.app;
  const doc = win.document;
  const $ = id => doc.getElementById(id);
  const nodes = app && app.nodes ? app.nodes : [];
  const forks = nodes.filter(n => n.children && n.children.length > 1).length;
  const records = nodes.filter(n => n.record);
  const flows = records.map(n => n.record.flow || (n.record.result && n.record.result.flow)).filter(Boolean);
  const exhibits = [];
  for (const n of records) {
    const th = n.record.theorems || {};
    for (const [id, t] of Object.entries(th)) {
      if (t && (t.exhibited || t.v === 'holds')) exhibits.push(id);
    }
  }
  exhibits.sort();
  const next = $('hist-next');
  let guard = 0;
  while (next && !next.disabled && guard++ < 80) next.click();
  return {
    nodeCount: nodes.length,
    forks,
    refused: nodes.filter(n => n.record && (n.record.ok === false || (n.record.result && n.record.result.ok === false))).length,
    actionRecords: records.length,
    state: (($('state-name') || {}).textContent || '') + '|' + (($('where') || {}).textContent || '').slice(0, 80),
    verdict: (($('verdict') || {}).textContent || '').slice(0, 80),
    lamps: [...doc.querySelectorAll('#ledger .thm.lit')].map(e => e.dataset.id).sort().join(','),
    exhibits: exhibits.join(','),
    flow0: flows[0] ? JSON.stringify(flows[0]) : '',
    cursor: app ? app.cursor : null,
  };
}

function visSteps(steps) { return (steps || []).filter(s => !s.hidden); }

function expectedShape(family, sc) {
  const trunk = visSteps(sc.steps);
  let forkSteps = 0, envNodes = 0, refused = 0;
  const countRef = steps => {
    for (const st of visSteps(steps)) if (st.expect && st.expect.ok === false) refused++;
  };
  countRef(sc.steps);
  for (const fk of sc.forks || []) {
    forkSteps += visSteps(fk.steps).length;
    if (family === 'registry' && fk.env) envNodes++;
    countRef(fk.steps);
  }
  let actions = 0;
  const countAct = steps => {
    for (const st of visSteps(steps)) if (st.action !== undefined) actions++;
  };
  countAct(sc.steps);
  for (const fk of sc.forks || []) countAct(fk.steps);
  return { nodeCount: 1 + trunk.length + forkSteps + envNodes, refused, actions };
}

function loadViaFile(win, text, name) {
  const input = win.document.getElementById('dsl-file');
  if (!input) throw new Error('no #dsl-file');
  if (typeof win.File !== 'function' || typeof win.FileReader !== 'function') throw new Error('minidom File/FileReader missing');
  input.files = [new win.File([text], name, { type: 'text/plain' })];
  input.dispatchEvent(win.makeEvent('change'));
}

function checkPlay() {
  if (!grammar) { row('INV-375-PLAY', false, 'grammar missing; pages cannot share a parser'); return; }
  const ckFiles = discover(CK_DIR);
  const rgFiles = discover(RG_DIR);
  if (!ckFiles.length || !rgFiles.length) { row('INV-375-PLAY', false, 'no DSL sources to play'); return; }
  const ckCorpus = JSON.parse(readFileSync(CK_CORPUS, 'utf8'));
  const rgCorpus = JSON.parse(readFileSync(RG_CORPUS, 'utf8'));
  const errs = [];
  const playFamily = (htmlPath, files, family, apiName, core, corpus) => {
    let win;
    try { win = createWindow(readFileSync(htmlPath, 'utf8'), { search: '' }); }
    catch (e) { errs.push(`${family} page failed to load: ${e.message}`); return; }
    if (win.__errors.length) errs.push(`${family} init: ${win.__errors.map(e => e.message).slice(0, 2).join(' | ')}`);
    const api = win[apiName];
    if (!api || typeof api.loadScenarioDsl !== 'function') { errs.push(`${family}: loadScenarioDsl missing`); return; }
    if (typeof win.playLoadedScenario !== 'function') { errs.push(`${family}: playLoadedScenario is not a window function`); return; }
    for (const f of files) {
      const text = readFileSync(f, 'utf8');
      const json = loadJson(jsonBeside(f));
      const oracle = expectedShape(family, json);
      const checked = core.checkScenario(json, basename(f), corpus);
      if (checked.problems && checked.problems.length) errs.push(`${basename(f)}: independent checker ${checked.problems[0]}`);
      try { loadViaFile(win, text, basename(f)); }
      catch (e) { errs.push(`${basename(f)}: file load ${e.message}`); continue; }
      if (win.__errors.length) { errs.push(`${basename(f)}: ${win.__errors.map(e => e.message)[0]}`); win.__errors.length = 0; }
      const snap = snapshotPlay(win);
      if (snap.nodeCount !== oracle.nodeCount) errs.push(`${basename(f)}: nodeCount page=${snap.nodeCount} json-oracle=${oracle.nodeCount}`);
      if (snap.refused !== oracle.refused) errs.push(`${basename(f)}: refused page=${snap.refused} json-oracle=${oracle.refused}`);
      if (snap.actionRecords !== oracle.actions) errs.push(`${basename(f)}: actionRecords page=${snap.actionRecords} json-oracle=${oracle.actions}`);
      if (!(checked.stepsRun > 0)) errs.push(`${basename(f)}: independent checker reported stepsRun=${checked.stepsRun}`);
      if (oracle.nodeCount <= 1) errs.push(`${basename(f)}: json oracle is degenerate (nodeCount ${oracle.nodeCount})`);
    }
    const priorLen = api.app.nodes.length, priorCursor = api.app.cursor, priorRef = api.app.nodes;
    try { api.loadScenarioDsl('nope', 'bad.dsl'); } catch (e) { /* diagnostic allowed */ }
    if (api.app.nodes.length !== priorLen || api.app.cursor !== priorCursor) errs.push(`${family}: parse-fail load mutated the tree`);
    const diag = win.document.getElementById('dsl-diag');
    if (diag && !diag.textContent) errs.push(`${family}: malformed load left no diagnostic`);

    const valid = readFileSync(files[0], 'utf8');
    const origAdmit = win.playLoadedScenario;
    win.playLoadedScenario = function (sc) { origAdmit(sc); throw new Error('post-admit failure'); };
    api.loadScenarioDsl(valid, 'post-admit.dsl');
    win.playLoadedScenario = origAdmit;
    if (api.app.nodes !== priorRef && (api.app.nodes.length !== priorLen || api.app.cursor !== priorCursor)) {
      errs.push(`${family}: post-admit failure left the tree mutated (rollback missing)`);
    }
    if (api.app.cursor !== priorCursor || api.app.nodes.length !== priorLen) {
      errs.push(`${family}: post-admit rollback did not restore cursor/length`);
    }
    if (!diag || !/post-admit/i.test(diag.textContent)) errs.push(`${family}: post-admit failure left no diagnostic`);

    const w2 = createWindow(readFileSync(htmlPath, 'utf8'), {});
    const api2 = w2[apiName];
    const json0 = loadJson(jsonBeside(files[0]));
    const oracle0 = expectedShape(family, json0);
    w2.playLoadedScenario = function (sc) {
      api2.app.nodes = [{ id: 0, parent: null, children: [], last: null, session: api2.app.nodes[0] && api2.app.nodes[0].session, record: null, who: '', say: 'empty-runner', kind: 'origin', branch: null }];
      api2.app.cursor = 0;
      api2.app.story = sc;
    };
    loadViaFile(w2, readFileSync(files[0], 'utf8'), basename(files[0]));
    const emptySnap = snapshotPlay(w2);
    if (!(oracle0.nodeCount > 1 && emptySnap.nodeCount <= 1)) {
      errs.push(`${family}: empty playLoadedScenario was not distinguished from the json oracle (page=${emptySnap.nodeCount} oracle=${oracle0.nodeCount})`);
    }

    const w3 = createWindow(readFileSync(htmlPath, 'utf8'), {});
    w3.document.getElementById('btn-reset').click();
    const oracle2 = expectedShape(family, loadJson(jsonBeside(files[1])));
    w3.FileReader = class { constructor() { this.result = null; this.onload = null; } readAsText() { /* no-op: never fires onload */ } };
    loadViaFile(w3, readFileSync(files[1], 'utf8'), basename(files[1]));
    const after3 = snapshotPlay(w3);
    if (oracle2.nodeCount > 1 && after3.nodeCount === oracle2.nodeCount) {
      errs.push(`${family}: FileReader no-op still admitted ${basename(files[1])} (file path not used)`);
    }
  };
  playFamily(CK_HTML, ckFiles, 'checkpoint', 'CK', ckCore, ckCorpus);
  playFamily(RG_HTML, rgFiles, 'registry', 'RS', rgCore, rgCorpus);
  row('INV-375-PLAY', errs.length === 0, errs.length ? errs.slice(0, 8).join(' | ') : `file-loaded ${ckFiles.length + rgFiles.length} DSL sources against json+checker oracles; empty runner and FileReader no-op distinguished`);
}

function nodeOf(api, id) { return api.app.nodes[id]; }

function driveCheckpointExport(win) {
  const d = win.document, $ = id => d.getElementById(id), CK = win.CK;
  $('btn-reset').click();
  const originCount = CK.app.nodes.length;
  $('slot-plus1').click();
  const evKind = $('ev-kind');
  if (evKind) { evKind.value = 'quorum'; evKind.dispatchEvent(win.makeEvent('change')); $('ev-a').value = '0'; $('ev-add').click(); }
  const anyone = d.querySelector('.actor[data-actor="anyone"]');
  if (anyone) anyone.click();
  const reg = d.querySelector('.act[data-kind="register"]');
  if (reg) { reg.click(); $('act-submit').click(); }
  const afterReg = CK.app.cursor;
  const top = d.querySelector('.act[data-kind="topUp"]');
  if (top) { top.click(); $('act-submit').click(); }
  const n = nodeOf(CK, afterReg);
  if (n) n.last = n.children[0];
  CK.goTo(afterReg);
  const alice = d.querySelector('.actor[data-actor="alice"]');
  if (alice) alice.click();
  const poison = d.querySelector('.act[data-kind="poison"]');
  if (poison && !poison.disabled) { poison.click(); $('act-submit').click(); }
  const kinds = CK.app.nodes.map(x => x.kind);
  const path = [];
  for (let id = CK.app.cursor; id !== null; id = nodeOf(CK, id).parent) path.unshift(nodeOf(CK, id));
  return { originCount, path, kinds, nodes: CK.app.nodes, cursor: CK.app.cursor };
}

function driveRegistryExport(win) {
  const d = win.document, $ = id => d.getElementById(id), RS = win.RS;
  $('btn-reset').click();
  const ev = d.querySelector('#next-moves .ev-quick[data-actor="alice"][data-ev="inception"]');
  if (ev) ev.click();
  const contrib = [...d.querySelectorAll('#next-moves .act[data-actor="alice"][data-kind="contribute"]')].find(x => /registration|register/i.test(x.textContent));
  if (contrib) { contrib.click(); $('act-submit').click(); }
  const after = RS.app.cursor;
  const fold = [...d.querySelectorAll('#next-moves .act[data-kind="fold"]')].find(x => /fold/i.test(x.textContent));
  if (fold) { fold.click(); $('act-submit').click(); }
  RS.goTo(after);
  $('slot-plus1').click();
  const retract = d.querySelector('#next-moves .act[data-kind="retract"]');
  if (retract && !retract.disabled) { retract.click(); $('act-submit').click(); }
  const path = [];
  for (let id = RS.app.cursor; id !== null; id = nodeOf(RS, id).parent) path.unshift(nodeOf(RS, id));
  return { path, nodes: RS.app.nodes, cursor: RS.app.cursor };
}

function checkExport() {
  const errs = [];
  const one = (htmlPath, apiName, drive, family, core, corpusPath) => {
    let win;
    try { win = createWindow(readFileSync(htmlPath, 'utf8'), {}); }
    catch (e) { errs.push(`${family} load: ${e.message}`); return; }
    const api = win[apiName];
    if (!api || typeof api.exportCurrentBranchDsl !== 'function'
      || typeof api.copyCurrentBranchDsl !== 'function'
      || typeof api.downloadCurrentBranchDsl !== 'function') {
      errs.push(`${family}: export/copy/download missing`);
      return;
    }
    let driven;
    try { driven = drive(win); }
    catch (e) { errs.push(`${family} export play threw: ${e.message}`); return; }
    const path = driven.path || [];
    const hasTime = path.some(n => n.kind === 'time' || (n.say && /slot/i.test(n.say || '')));
    const hasEv = path.some(n => n.kind === 'evidence' || n.evRow);
    const hasAct = path.some(n => n.record && (n.record.ok || (n.record.result && n.record.result.ok)));
    const parentWithKids = driven.nodes.filter(n => n.children && n.children.length > 1);
    if (!hasTime) errs.push(`${family} export play: no time node on the selected branch`);
    if (!hasEv) errs.push(`${family} export play: no evidence node on the selected branch`);
    if (!hasAct) errs.push(`${family} export play: no accepted action on the selected branch`);
    if (!parentWithKids.length) errs.push(`${family} export play: no forked continuation`);
    let dsl;
    try { dsl = api.exportCurrentBranchDsl(); }
    catch (e) { errs.push(`${family} export threw: ${e.message}`); return; }
    if (typeof dsl !== 'string' || !dsl.includes('family:') || !dsl.includes(family)) errs.push(`${family} export is not DSL for ${family}`);
    const copyBtn = win.document.getElementById('dsl-copy');
    const dlBtn = win.document.getElementById('dsl-download');
    if (!copyBtn || !dlBtn) { errs.push(`${family}: copy/download controls missing`); return; }
    if (/window\.__clipboard\s*=/.test(readFileSync(htmlPath, 'utf8'))) errs.push(`${family}: production assigns window.__clipboard`);
    const writes = [];
    const origWT = win.navigator.clipboard && win.navigator.clipboard.writeText;
    if (typeof origWT !== 'function') { errs.push(`${family}: clipboard.writeText missing`); return; }
    win.navigator.clipboard.writeText = async function (s) { writes.push(s); return origWT.call(this, s); };
    win.__clipboard = '';
    copyBtn.click();
    if (writes.length !== 1 || writes[0] !== dsl) errs.push(`${family}: copy did not call clipboard.writeText with the exported DSL (calls=${writes.length})`);
    if (win.__clipboard !== dsl) errs.push(`${family}: clipboard adapter did not receive the exported DSL`);
    win.navigator.clipboard.writeText = async function () { /* no-op adapter */ };
    win.__clipboard = '';
    copyBtn.click();
    if (win.__clipboard === dsl) errs.push(`${family}: copy populated clipboard without writeText producing the text`);
    win.navigator.clipboard = undefined;
    win.__clipboard = 'STALE';
    copyBtn.click();
    const copyDiag = win.document.getElementById('dsl-diag');
    if (win.__clipboard === dsl) errs.push(`${family}: copy succeeded with clipboard API absent`);
    if (!copyDiag || !/unavailable/i.test(copyDiag.textContent)) errs.push(`${family}: absent clipboard left no diagnostic`);
    win.navigator.clipboard = { writeText: origWT };
    dlBtn.click();
    const dl = (win.__downloads || [])[0];
    if (!dl || dl.text !== dsl) errs.push(`${family}: download did not capture the same DSL`);
    if (dl && !/\.dsl$/.test(dl.name || dl.download || '')) errs.push(`${family}: download name is not a .dsl file`);
    if (!grammar) { errs.push(`${family}: cannot recompile export without grammar`); return; }
    let sc;
    try { sc = grammar.scenarioFromDsl(dsl, family + '-export.dsl'); }
    catch (e) { errs.push(`${family} recompile: ${e.message}`); return; }
    const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));
    const r = core.checkScenario(sc, family + '-export', corpus);
    if (r.problems && r.problems.length) errs.push(`${family} export checker: ${r.problems[0]}`);
    const exportedActs = (sc.steps || []).filter(st => st.action !== undefined).length;
    if (!exportedActs) errs.push(`${family} export has no action steps`);
    const pathActs = path.filter(n => n.record).length;
    if (exportedActs !== pathActs) errs.push(`${family}: exported ${exportedActs} actions, selected branch has ${pathActs}`);
    if (Array.isArray(sc.forks) && sc.forks.length) errs.push(`${family}: export included ${sc.forks.length} fork(s); selected branch must be linear`);
  };
  one(CK_HTML, 'CK', driveCheckpointExport, 'checkpoint', ckCore, CK_CORPUS);
  one(RG_HTML, 'RS', driveRegistryExport, 'registry', rgCore, RG_CORPUS);
  row('INV-375-EXPORT', errs.length === 0, errs.length ? errs.slice(0, 8).join(' | ') : 'both pages exported a time+evidence+action+fork branch via copy and download; recompile+checker accepted');
}

function checkScope() {
  const errs = [];
  for (const dir of [CK_DIR, RG_DIR]) {
    for (const f of readdirSync(dir).filter(x => x.endsWith('.json')).sort()) {
      JSON.parse(readFileSync(join(dir, f), 'utf8'));
    }
  }
  if (existsSync(GRAMMAR) && readFileSync(GRAMMAR, 'utf8').length > 40 * 1024) errs.push('grammar module exceeds 40 KiB');
  for (const f of [...discover(CK_DIR), ...discover(RG_DIR)]) {
    if (readFileSync(f).length > 40 * 1024) errs.push(`${basename(f)} exceeds 40 KiB`);
  }
  row('INV-375-SCOPE', errs.length === 0, errs.length ? errs.join(' | ') : 'JSON corpus parseable; size caps hold');
}

function checkBuildSlice() {
  const errs = [];
  for (const [build, html, label] of [[CK_BUILD, CK_HTML, 'checkpoint'], [RG_BUILD, RG_HTML, 'registry']]) {
    try {
      execFileSync(process.execPath, [build, '--check'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) {
      errs.push(`${label} --check: ${((e.stderr || e.stdout || e.message) + '').trim().slice(0, 200)}`);
      continue;
    }
    const page = readFileSync(html, 'utf8');
    if (!/\/\* @@DSL@@ \*\//.test(page) || !/\/\* @@DSL:END@@ \*\//.test(page)) errs.push(`${label} page has no @@DSL@@ slice`);
    if (existsSync(GRAMMAR)) {
      const src = readFileSync(GRAMMAR, 'utf8');
      const m = src.match(/\/\* @@DSL@@ \*\/\n([\s\S]*?)\/\* @@DSL:END@@ \*\//);
      const p = page.match(/\/\* @@DSL@@ \*\/\n([\s\S]*?)\/\* @@DSL:END@@ \*\//);
      if (!m) errs.push('grammar has no @@DSL@@ block');
      else if (!p) errs.push(`${label} page DSL slice missing`);
      else if (p[1] !== m[1]) errs.push(`${label} DSL slice drifted from scenario-dsl.mjs`);
    }
  }
  if (!existsSync(GRAMMAR)) errs.push('shared grammar missing (build cannot inline it)');
  const prev = rows.find(r => r.inv === 'INV-375-ONE');
  if (errs.length) {
    if (prev) {
      prev.ok = false;
      prev.detail = (prev.detail ? prev.detail + ' | ' : '') + errs.join(' | ');
      if (!problems.some(p => p.startsWith('INV-375-ONE:'))) problems.push('INV-375-ONE: ' + prev.detail);
    } else {
      row('INV-375-ONE', false, errs.join(' | '));
    }
  }
}

async function main() {
  grammar = await loadGrammar();
  cliMod = await loadCli();
  checkComparator();
  checkExtentGuards();
  checkLosslessCompile();
  checkOne();
  checkRunnable();
  await checkAtomic();
  checkPlay();
  checkExport();
  checkScope();
  checkBuildSlice();

  const failed = rows.filter(r => !r.ok);
  const w = Math.max(...rows.map(r => r.inv.length));
  for (const r of rows) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.inv.padEnd(w)}  ${r.detail}`);
  if (failed.length) {
    console.log(`RED: ${failed.length} invariant(s) failed; discovered ${nScenarios} scenarios, checkpoint ${ckSteps} steps, registry ${rgSteps} steps`);
    problems.forEach(p => console.error(' - ' + p));
    process.exit(1);
  }
  if (nScenarios !== WANT.total || ckSteps !== WANT.checkpointSteps || rgSteps !== WANT.registrySteps) {
    console.log(`RED: GREEN denominator missing: ${nScenarios} ${ckSteps} ${rgSteps}`);
    process.exit(1);
  }
  console.log(`GREEN: ${nScenarios} scenarios, checkpoint ${ckSteps} story steps, registry ${rgSteps} story steps`);
}

main().catch(e => { console.error('RED: gate crashed: ' + (e && e.stack || e)); process.exit(1); });
