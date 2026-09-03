#!/usr/bin/env node
/*
 * registry-simulator-scenario-gate.mjs — executable scenario suite over the
 * ONE machine core (registry-simulator-core.mjs), the drift gate for the
 * generated page, and a page smoke under the minimal DOM.
 *
 * Fresh on every run the gate:
 *
 *   1. imports the core MODULE directly and replays every story in
 *      registry-simulator-scenarios/ through `checkScenario`, with the
 *      embedded Lean corpus as the parity oracle: an applied step expected
 *      to be refused (or the wrong refusal reason), a flow or state
 *      mismatch, a theorem failing on any step, a claimed exhibit that does
 *      not hold, or a disagreement with the Lean's verdict is RED;
 *   2. requires exactly the fifteen stories, every theorem exhibited by some
 *      story, every refusal reason asserted by some story;
 *   3. probes exact-Nat and shape refusals at every entry point;
 *   4. runs registry-simulator-build.mjs --check (a stale or forked inlined
 *      copy, story block, corpus block or published copy is RED);
 *   5. executes the page's ACTUAL script under the minimal DOM: the
 *      self-test mode must PASS; the picker must play every story with no
 *      mismatch; free play must accept a request and a fold and refuse a
 *      stale fold; evidence, slot, history and theme controls must work
 *      without a thrown error;
 *   6. prints a table and GREEN only if everything above is green.
 *
 * Usage:
 *   node registry-simulator-scenario-gate.mjs             # production
 *   node registry-simulator-scenario-gate.mjs --selftest  # negative controls
 *
 * --selftest proves the gate can fail, each control RED for its intended
 * reason, on scratch copies (the committed tree is never touched): a flipped
 * story expectation, a forked embedded slice, a flipped core guard (the
 * absence proof removed), a lying theorem property, a broken page control.
 */

import { readFileSync, readdirSync, mkdtempSync, rmSync, writeFileSync, cpSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { createWindow } from './checkpoint-simulator-minidom.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const argPath = flag => { const i = process.argv.indexOf(flag); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : null; };
const CORE = argPath('--core') || join(HERE, 'registry-simulator-core.mjs');
const HTML = argPath('--html') || join(HERE, 'registry-simulator.html');
const SCEN_DIR = argPath('--scenarios') || join(HERE, 'registry-simulator-scenarios');
const CORPUS = argPath('--corpus') || join(HERE, 'registry-simulator-corpus.json');
const BUILD = join(HERE, 'registry-simulator-build.mjs');
const DOCS = argPath('--docs') || join(HERE, '..', 'docs', 'simulator', 'registry', 'index.html');
const CLAUSES = argPath('--clauses') || join(HERE, 'registry-simulator-clauses.json');
const STORIES_MD = argPath('--stories') || join(HERE, 'REGISTRY-STORIES.md');
const LEAN_ROOT = argPath('--lean-root') || join(HERE, '..');
const N_STORIES = 15;

/* --- the Lean source, by declaration span and arm --------------------------- */

// leanSpans(files) → Map name → {file, from, to, text, lines}: every top-level
// declaration runs from its line to the line before the next column-0
// declaration, doc comment, section or `end`. Doc comments are not part of a
// span: an anchor must be code.
const TOP = /^(theorem|def|inductive|structure|abbrev|instance)\s+([^\s(:{]+)/;
const TOP_END = /^(theorem|def|inductive|structure|abbrev|instance|namespace|end|open|section|\/-|#)/;
function leanSpans(files) {
  const spans = new Map();
  for (const [file, text] of Object.entries(files)) {
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(TOP);
      if (!m) continue;
      let j = i + 1;
      while (j < lines.length && !TOP_END.test(lines[j])) j++;
      spans.set(m[2], { file, from: i + 1, to: j, text: lines.slice(i, j).join('\n'), lines: lines.slice(i, j) });
      i = j - 1;
    }
  }
  return spans;
}
const squash = x => String(x).replace(/\s+/g, ' ').trim();
const within = (hay, needle) => squash(hay).includes(squash(needle));
const where = span => `${span.file}:${span.from}-${span.to}`;
const indentOf = l => l.match(/^\s*/)[0].length;
// the arms of a declaration that matches on the action or the op: the `| .name`
// lines at the least indentation; an arm runs to the next arm or the end
function armsOf(span) {
  const arms = [];
  let min = Infinity;
  // the least-indented `| ` lines of the declaration; they are arms only when they match on a constructor (`| .name`)
  span.lines.forEach(l => { const m = l.match(/^(\s*)\| /); if (m && m[1].length < min) min = m[1].length; });
  span.lines.forEach((l, i) => { const m = l.match(/^(\s*)\| \.([A-Za-z]+)/); if (m && m[1].length === min) arms.push({ name: '.' + m[2], at: i }); });
  return arms.map((a, k) => ({ name: a.name, from: a.at, to: k + 1 < arms.length ? arms[k + 1].at - 1 : span.lines.length - 1, lines: span.lines.slice(a.at, (k + 1 < arms.length ? arms[k + 1].at : span.lines.length)) }));
}
function armSpan(span, arm) { if (!arm) return { lines: span.lines, text: span.text, name: null }; const a = armsOf(span).find(x => x.name === arm); return a ? { ...a, text: a.lines.join('\n') } : null; }
// the parts of an arm: the conditions (every if-conjunct and every accepting
// match pattern) and the result (from the accepting `some` to the end)
function splitConjuncts(cond) { const out = []; let depth = 0, cur = ''; for (const ch of cond) { if ('([{⟨'.includes(ch)) depth++; if (')]}⟩'.includes(ch)) depth--; if (ch === '∧' && depth === 0) { out.push(cur); cur = ''; } else cur += ch; } out.push(cur); return out.map(squash).filter(Boolean); }
function partsOf(lines) {
  const cond = [], patterns = [], result = [];
  for (const l of lines) {
    const ifm = l.match(/\bif (.*) then\b/); if (ifm) cond.push(...splitConjuncts(ifm[1]));
    const pm = l.match(/^\s*\| (.*?) =>\s*(.*)$/);
    if (pm && !/^none\s*$/.test(pm[2])) patterns.push(pm[1]);
    if ((/\bsome\b/.test(l) || /\blet\b.*:= \{/.test(l)) && !/=>\s*none/.test(l) && !/^\s*\| /.test(l)) result.push(l);
    else if (result.length && !/^\s*\| /.test(l) && !/\bif .* then\b/.test(l) && !/^\s*else/.test(l) && !/\bmatch\b/.test(l)) result.push(l);
  }
  return { cond, patterns, result: result.join('\n') };
}
// every decision site of a declaration on the path from stepFn: an if-conjunct
// (by arm) or the accepting pattern of a match with a `=> none` arm
function decisionSites(name, span) {
  const arms = armsOf(span);
  const sites = [];
  const scan = (lines, arm) => {
    lines.forEach((l, i) => {
      const ifm = l.match(/\bif (.*) then\b/); if (ifm) for (const c of splitConjuncts(ifm[1])) sites.push({ decl: name, arm, text: c, kind: 'if' });
      const nm = l.match(/^(\s*)\| (.*?) =>\s*none\s*$/);
      if (nm) {
        const ind = nm[1].length; const sib = [];
        for (let j = i - 1; j >= 0; j--) { const t = lines[j]; if (indentOf(t) < ind && /\bmatch\b/.test(t)) break; const pm = t.match(/^(\s*)\| (.*?) =>/); if (pm && pm[1].length === ind && !/=>\s*none\s*$/.test(t)) sib.unshift(pm[2]); if (pm && pm[1].length === ind && /=>\s*none\s*$/.test(t)) break; }
        for (let j = i + 1; j < lines.length; j++) { const t = lines[j]; if (indentOf(t) < ind) break; const pm = t.match(/^(\s*)\| (.*?) =>/); if (pm && pm[1].length === ind) { if (!/=>\s*none\s*$/.test(t)) sib.push(pm[2]); else break; } }
        for (const p of sib) sites.push({ decl: name, arm, text: squash(p), kind: 'match' });
      }
    });
  };
  if (arms.length) for (const a of arms) scan(a.lines, a.name); else scan(span.lines, null);
  return sites;
}
const PATH = ['stepFn', 'applyBatch', 'processOne', 'processBody', 'rejectOne', 'replay'];
const siteKey = x => `${x.decl}${x.arm ? ' ' + x.arm : ''} «${squash(x.text)}»`;

// the guard table both ways: every claimed site exists with its text in its
// declaration and arm; every decision site of the Lean is claimed by exactly
// one reason, or shared (declared), or a pass-through (declared)
function checkGuardTable(core, spans) {
  const problems = [];
  const claimed = new Map();
  const claim = (x, by) => { const k = siteKey(x); if (!claimed.has(k)) claimed.set(k, []); claimed.get(k).push(by); };
  for (const reason of Object.values(core.REASONS)) {
    const g = core.LEAN_GUARDS[reason];
    if (!g) { problems.push(`guard table: refusal ${reason} has no entry (which Lean guard is it?)`); continue; }
    for (const x of g.sites || []) {
      const span = spans.get(x.decl);
      if (!span) { problems.push(`guard table: ${reason} names ${x.decl}, which is not a declaration of the Lean`); continue; }
      const a = armSpan(span, x.arm);
      if (!a) { problems.push(`guard table: ${reason} names ${x.decl} ${x.arm}, which is not an arm of it (${where(span)})`); continue; }
      if (!within(a.text, x.text)) { problems.push(`guard table: «${x.text}» is not inside ${x.decl}${x.arm ? ' ' + x.arm : ''} (${where(span)}) (${reason})`); continue; }
      if (g.decider && !within(x.text, g.decider.replace(/^Op\./, ''))) problems.push(`guard table: ${reason}'s site «${x.text}» does not call its decider ${g.decider}`);
      claim(x, reason);
    }
    for (const [decl, hyp, text] of g.hyps || []) {
      const span = spans.get(decl);
      if (!span) { problems.push(`guard table: ${reason} names ${decl}, not a declaration`); continue; }
      const f = span.lines.find(l => l.startsWith('  ' + hyp + ' :'));
      if (!f) problems.push(`guard table: ${decl} has no field ${hyp} (${reason})`);
      else if (!within(f, text)) problems.push(`guard table: ${decl}.${hyp} is «${squash(f)}», not «${text}» (${reason})`);
      claim({ decl, arm: null, text: hyp }, reason);
    }
    if (g.decider && !spans.has(g.decider) && g.decider !== 'lookup') problems.push(`guard table: ${reason} names decider ${g.decider}, not a declaration`);
  }
  for (const reason of Object.keys(core.LEAN_GUARDS)) if (!Object.values(core.REASONS).includes(reason)) problems.push(`guard table: ${reason} is not a refusal the core can produce`);
  const shared = new Map(core.LEAN_SHARED_SITES.map(x => [siteKey(x), x.by]));
  const pass = new Set(core.LEAN_PASSTHROUGH.map(siteKey));
  let n = 0;
  for (const name of PATH) {
    const span = spans.get(name);
    if (!span) { problems.push(`guard table: ${name} is not a declaration of the Lean`); continue; }
    for (const x of decisionSites(name, span)) {
      n++;
      const k = siteKey(x), by = claimed.get(k) || [];
      if (pass.has(k)) { if (by.length) problems.push(`guard table: ${k} is a pass-through and is also claimed by ${by.join(', ')}`); continue; }
      if (!by.length) problems.push(`guard table: ${k} (${where(span)}) is a decision site of the Lean no refusal name claims`);
      else if (by.length > 1 && !(shared.has(k) && shared.get(k).slice().sort().join() === by.slice().sort().join())) problems.push(`guard table: ${k} is claimed by ${by.join(' and ')} and not declared shared`);
    }
  }
  for (const [k] of shared) if (!(claimed.get(k) || []).length) problems.push(`guard table: shared site ${k} does not exist`);
  for (const k of pass) { const decl = k.split(' ')[0]; const span = spans.get(decl); if (!span || !decisionSites(decl, span).some(x => siteKey(x) === k)) problems.push(`guard table: pass-through ${k} is not a decision site of the Lean`); }
  const paramsSpan = spans.get('Params');
  if (paramsSpan) for (const l of paramsSpan.lines) { const f = l.match(/^  (h[A-Za-z]*)\s*:/); if (f && !claimed.has(siteKey({ decl: 'Params', arm: null, text: f[1] }))) problems.push(`guard table: Params.${f[1]} is a proof field no refusal name claims`); }
  if (!n) problems.push('guard table: no decision site found on the path from stepFn (parser broken?)');
  return { problems, sites: n, claimed };
}

/* --- story reconciliation ---------------------------------------------- */
const LABELS = ['The chain checks', 'Money', 'Refused'];
function extractStoryClauses(md) {
  const out = {};
  let story = null;
  for (const raw of md.split('\n')) {
    const h = raw.match(/^## (\d+)\. /);
    if (h) { story = Number(h[1]); out[story] = []; continue; }
    if (/^## /.test(raw)) { story = null; continue; }
    if (story === null) continue;
    const m = raw.match(/^- \*\*([^*]+)\*\*:\s*(.*)$/);
    if (m && LABELS.includes(m[1])) out[story].push({ label: m[1], text: m[2].replace(/\s+/g, ' ').trim() });
  }
  return out;
}
function opsOfStep(core, rec) {
  const f = rec.action.fold; if (!f) return { process: [], reject: [] };
  const v = core.batchView(rec.params, rec.env, rec.now, rec.before, f.batch);
  return { process: v.filter(x => x.r && x.fa === 'process').map(x => '.' + core.opTag(x.r.op)), reject: v.filter(x => x.r && x.fa === 'reject').map(() => 'reject') };
}
function findStep(m, timelines) {
  const tl = m.branch ? (timelines.forkTimelines || {})[m.branch] : timelines.timeline;
  if (!tl) return null;
  return tl[m.step] || null;
}
function checkClauses(core, clausesDoc, storiesMd, scenarioTimelines, leanRoot) {
  const problems = [];
  const clauses = clausesDoc.clauses || [];
  const files = {};
  for (const f of ['lean/CardanoKeri/Registry.lean', 'lean/CardanoKeri/RegistryGoals.lean']) {
    try { files[f] = readFileSync(join(leanRoot, f), 'utf8'); } catch (e) { problems.push(`cannot read ${f}: ${e.message}`); }
  }
  const spans = leanSpans(files);
  const gt = checkGuardTable(core, spans);
  problems.push(...gt.problems);
  const theoremGroup = decl => core.THEOREMS.find(t => t.lean.split(/,\s*/).includes(decl));
  const KINDS = ['guard', 'refusal', 'payment', 'post-state', 'no-guard', 'verdict'];
  let anchored = 0;
  for (const c of clauses) {
    const tag = `story ${c.story} clause «${c.clause}»`;
    if (!['guard', 'omission', 'overrule'].includes(c.class)) { problems.push(`${tag}: unknown class ${c.class}`); continue; }
    if (c.class === 'omission') { if (!c.note) problems.push(`${tag}: an omission needs a note`); if (c.decl || c.reason || c.match) problems.push(`${tag}: an omission anchors nothing`); continue; }
    if (!c.decl || !c.text || !c.kind) { problems.push(`${tag}: a ${c.class} row names a Lean declaration (decl), its kind and the exact text (text)`); continue; }
    if (!KINDS.includes(c.kind)) { problems.push(`${tag}: unknown kind ${c.kind}`); continue; }
    const span = spans.get(c.decl);
    if (!span) { problems.push(`${tag}: ${c.decl} is not a declaration of the Lean`); continue; }
    const isTheorem = /^theorem /.test(span.lines[0]);
    if ((c.kind === 'verdict') !== isTheorem) { problems.push(`${tag}: kind verdict is for a theorem, ${c.decl} is ${isTheorem ? 'one' : 'not one'}`); continue; }
    const a = armSpan(span, c.arm);
    if (!a) { problems.push(`${tag}: ${c.decl} has no arm ${c.arm} (${where(span)})`); continue; }
    if (c.arm === undefined && armsOf(span).length && !isTheorem && PATH.includes(c.decl)) { problems.push(`${tag}: ${c.decl} matches on arms; name the arm`); continue; }
    if (!within(a.text, c.text)) { problems.push(`${tag}: «${c.text}» is not inside ${c.decl}${c.arm ? ' ' + c.arm : ''} (${where(span)})`); continue; }
    if (PATH.includes(c.decl)) {
      const parts = partsOf(a.lines);
      if (c.kind === 'guard' || c.kind === 'refusal') { if (!parts.cond.some(x => x === squash(c.text)) && !parts.patterns.some(x => within(x, c.text))) { problems.push(`${tag}: «${c.text}» is not a condition of ${c.decl}${c.arm ? ' ' + c.arm : ''} (conditions: ${[...parts.cond, ...parts.patterns].join(' / ')})`); continue; } }
      else if (c.kind === 'payment' || c.kind === 'post-state') { if (!within(parts.result, c.text)) { problems.push(`${tag}: «${c.text}» is not in the result of ${c.decl}${c.arm ? ' ' + c.arm : ''}`); continue; } }
      else if (c.kind === 'no-guard') { if (!a.lines[0] || !within(a.lines[0], c.text) || /\bif\b/.test(a.lines[0])) { problems.push(`${tag}: a no-guard row names the arm's pattern line`); continue; } }
    }
    if (c.kind === 'post-state' && c.updates) {
      const sets = [...squash(partsOf(a.lines).result).matchAll(/\b([A-Za-z]+) :=/g)].map(x => x[1]).filter(k => !['deposited', 'refunds', 'tips', 'premium', 'intoRequest', 'locked'].includes(k));
      const want = [...new Set(sets)].sort().join(','), have = c.updates.slice().sort().join(',');
      if (want !== have) { problems.push(`${tag}: updates ${have} but the arm's with sets ${want}`); continue; }
    }
    const ties = ['reason', 'match'].filter(k => c[k] !== undefined);
    if (ties.length !== 1) { problems.push(`${tag}: a ${c.class} row carries exactly one tie (reason or match), has ${ties.length ? ties.join('+') : 'none'}`); continue; }
    if (c.reason !== undefined) {
      const g = core.LEAN_GUARDS[c.reason];
      if (!g) { problems.push(`${tag}: unknown reason ${c.reason}`); continue; }
      const hit = (g.sites || []).find(x => x.decl === c.decl && (x.arm || null) === (c.arm || null) && squash(x.text) === squash(c.text));
      const viaDecider = g.decider === c.decl && within(span.text, c.text);
      if (!hit && !viaDecider) { problems.push(`${tag}: ${c.reason} is decided at ${(g.sites || []).map(siteKey).join(' / ') || 'the simulator, not the Lean'}${g.decider ? ' via ' + g.decider : ''}, not by «${c.text}» in ${c.decl}${c.arm ? ' ' + c.arm : ''}`); continue; }
    } else {
      const tls = scenarioTimelines[c.story];
      const rec = tls ? findStep(c.match, tls) : null;
      if (!rec) { problems.push(`${tag}: story ${c.story} has no step ${JSON.stringify(c.match)}`); continue; }
      if (c.match.ok !== undefined && rec.result.ok !== c.match.ok) { problems.push(`${tag}: step ${JSON.stringify(c.match)} is ${rec.result.ok ? 'applied' : 'refused'}`); continue; }
      const kind = core.actionTag(rec.action);
      if (isTheorem) {
        const grp = theoremGroup(c.decl);
        if (!grp) { problems.push(`${tag}: ${c.decl} is in no executable property's list`); continue; }
        const th = rec.theorems[grp.id];
        if (!th || th.v !== 'holds') { problems.push(`${tag}: step ${JSON.stringify(c.match)} does not exhibit ${grp.id} (${c.decl})`); continue; }
      } else if (c.decl === 'stepFn') {
        if ('.' + kind !== c.arm) { problems.push(`${tag}: step ${JSON.stringify(c.match)} goes through .${kind}, not ${c.arm}`); continue; }
      } else if (c.decl === 'processBody') {
        if (kind !== 'fold' || !opsOfStep(core, rec).process.includes(c.arm)) { problems.push(`${tag}: step ${JSON.stringify(c.match)} does not process a ${c.arm} request`); continue; }
      } else if (c.decl === 'processOne') {
        if (kind !== 'fold' || !opsOfStep(core, rec).process.length) { problems.push(`${tag}: step ${JSON.stringify(c.match)} processes nothing`); continue; }
      } else if (c.decl === 'rejectOne' || c.decl === 'rejectable') {
        if (kind !== 'fold' || !opsOfStep(core, rec).reject.length) { problems.push(`${tag}: step ${JSON.stringify(c.match)} rejects nothing`); continue; }
      } else if (c.decl === 'applyBatch') {
        if (kind !== 'fold') { problems.push(`${tag}: step ${JSON.stringify(c.match)} is not a fold`); continue; }
      } else if (c.decl === 'reapable') {
        if (kind !== 'reap') { problems.push(`${tag}: step ${JSON.stringify(c.match)} is not a reap`); continue; }
      } else if (c.decl === 'inPhase2') {
        if (kind !== 'retract') { problems.push(`${tag}: step ${JSON.stringify(c.match)} is not a retract`); continue; }
      } else { problems.push(`${tag}: a match tie needs an arm of the step, a fold body, a decider or a theorem, not ${c.decl}`); continue; }
      if (c.kind === 'post-state' && c.updates && rec.result.ok) {
        const changed = Object.keys(rec.before).filter(k => JSON.stringify(rec.before[k]) !== JSON.stringify(rec.result.state[k])).sort().join(',');
        if (changed !== c.updates.slice().sort().join(',')) { problems.push(`${tag}: the step changed ${changed || 'nothing'}, the row says ${c.updates.join(',')}`); continue; }
      }
      if (c.kind === 'payment' && rec.result.ok) {
        const fl = rec.result.flow, field = (c.text.match(/^(deposited|locked|refunds|tips|premium|intoRequest)\b/) || [])[1];
        const paid = field === 'deposited' || field === 'intoRequest' ? fl[field] > 0 : field === 'tips' || field === 'premium' ? fl[field] !== null : field ? fl[field].length > 0 : false;
        if (!paid) { problems.push(`${tag}: step ${JSON.stringify(c.match)} pays nothing through ${field || 'that field'}`); continue; }
      }
    }
    anchored++;
  }
  const extracted = extractStoryClauses(storiesMd);
  const byStory = {};
  for (const c of clauses) (byStory[c.story] = byStory[c.story] || []).push(c);
  let fragments = 0;
  const seen = new Set();
  for (let n = 1; n <= N_STORIES; n++) {
    const bs = extracted[n] || [];
    if (!bs.length) { problems.push(`story ${n}: no labelled bullet (${LABELS.join(' / ')}) found in REGISTRY-STORIES.md`); continue; }
    const cs = [...new Set((byStory[n] || []).map(c => c.clause))].sort((a, b) => b.length - a.length);
    for (const b of bs) {
      let rest = b.text;
      for (const cl of cs) { let i; while ((i = rest.indexOf(cl)) >= 0) { rest = rest.slice(0, i) + ' ' + rest.slice(i + cl.length); fragments++; seen.add(n + ' ' + cl); } }
      const leftover = rest.replace(/[\s;:.,()—]/g, '');
      if (leftover.length) problems.push(`story ${n}: unclassified fragment in «${b.label}»: «${rest.trim().replace(/\s+/g, ' ').slice(0, 120)}»`);
    }
    if (!cs.length) problems.push(`story ${n}: no clauses in the reconciliation table`);
  }
  for (const c of clauses) if (!seen.has(c.story + ' ' + c.clause)) problems.push(`story ${c.story} clause «${c.clause}» does not occur in the story's labelled bullets`);
  return { problems, clauses: clauses.length, anchored, fragments, sites: gt.sites, omissions: clauses.filter(c => c.class === 'omission').length };
}
function clausesMarkdown(clausesDoc) {
  const lines = ['| story | clause | class | kind | Lean | text | tie | note |', '|---|---|---|---|---|---|---|---|'];
  const esc = x => String(x === undefined ? '' : x).replace(/\|/g, '\\|');
  for (const c of clausesDoc.clauses) {
    const tie = c.reason ? 'reason ' + c.reason : c.match ? 'step ' + JSON.stringify(c.match) : '';
    lines.push(`| ${c.story} | ${esc(c.clause)} | ${c.class} | ${esc(c.kind)} | ${c.decl ? esc(c.decl + (c.arm ? ' ' + c.arm : '')) : ''} | ${c.text ? '\`' + esc(c.text) + '\`' : ''} | ${esc(tie)} | ${esc(c.note)} |`);
  }
  return lines.join('\n');
}

async function run({ core: corePath = CORE, html = HTML, scenDir = SCEN_DIR, corpusPath = CORPUS, docs = DOCS, clausesPath = CLAUSES, storiesMd = STORIES_MD, leanRoot = LEAN_ROOT, quiet = false } = {}) {
  const core = await import(pathToFileURL(corePath).href + '?t=' + Date.now());
  const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));
  const rows = [], problems = [];
  const row = (what, ok, detail) => { rows.push({ what, ok, detail }); if (!ok) problems.push(`${what}: ${detail}`); };

  // 1–2. the stories through the core, with the Lean corpus as oracle
  const files = readdirSync(scenDir).filter(f => f.endsWith('.json')).sort();
  const exhibited = new Set(), asserted = new Set(); let steps = 0, forks = 0, forkSteps = 0;
  const ids = [], timelines = {};
  for (const f of files) {
    const sc = JSON.parse(readFileSync(join(scenDir, f), 'utf8'));
    ids.push(sc.id);
    const r = core.checkScenario(sc, f, corpus);
    timelines[sc.id] = r;
    steps += r.stepsRun; r.exhibited.forEach(x => exhibited.add(x)); r.asserted.forEach(x => asserted.add(x));
    const nf = Object.keys(r.forkTimelines || {}).length; forks += nf; forkSteps += Object.values(r.forkTimelines || {}).reduce((n, t) => n + t.length, 0);
    row(`story ${sc.id} ${sc.slug}`, r.problems.length === 0, r.problems.length ? r.problems.join(' | ') : `${r.stepsRun} steps${nf ? `, ${nf} branch${nf > 1 ? 'es' : ''}` : ''}`);
  }
  row('the stories are trees: refused attempts and what-ifs are branches the driver folds', forks > 0 && forkSteps > 0, `${forks} forks, ${forkSteps} fork steps`);
  row('exactly the fifteen stories', ids.length === N_STORIES && [...Array(N_STORIES).keys()].every(i => ids.includes(i + 1)), `ids ${ids.join(',')}`);
  const missingT = core.THEOREMS.map(t => t.id).filter(id => !exhibited.has(id));
  row('every theorem exhibited by some story', missingT.length === 0, missingT.length ? 'missing ' + missingT.join(', ') : `${core.THEOREMS.length} theorems`);
  // Two guards are defence in depth: the invariant makes them unreachable
  // from genesis (a go-request exists only while its leaf is active; a
  // dormant leaf never has a checkpoint). No story can assert them.
  const UNREACHABLE = ['checkpoint-exists', 'not-active'];
  const REPLAY_ONLY = ['slot-decreased']; // a refusal of replay, not of step: no story step can assert it
  const missingR = Object.values(core.REASONS).filter(r => !r.startsWith('invalid') && !UNREACHABLE.includes(r) && !REPLAY_ONLY.includes(r) && !asserted.has(r));
  row('every reachable refusal reason asserted by some story', missingR.length === 0, missingR.length ? 'missing ' + missingR.join(', ') : `${asserted.size} reasons; ${UNREACHABLE.join(', ')} unreachable by Inv`);
  const corpusForks = (corpus.stories || []).reduce((n, sc) => n + (sc.forks || []).length, 0);
  row('the corpus is the fifteen stories with their forks, six traces and the grid', Array.isArray(corpus.stories) && corpus.stories.length === N_STORIES && corpusForks === forks && corpus.traces.length === 6 && corpus.grid.cells.length > 0, `${(corpus.stories || []).length} stories, ${corpusForks} forks, ${(corpus.traces || []).length} traces, ${corpus.grid ? corpus.grid.cells.length : 0} grid cells`);
  const cc = core.checkCorpus(corpus);
  row('the Lean corpus replays through the core', cc.ok, cc.ok ? `${cc.cells} cells, ${cc.applied} applied, ${cc.refused} refused` : cc.reasons.slice(0, 3).join(' | '));

  // 3. exact Nat and shapes at every entry point
  {
    const P = { D: 10, tip: 1, Mc: 4, Mr: 1, process: 5, retract: 5, W: 3, far: 1000 };
    const S0 = core.initSys(7);
    const bads = [2 ** 53, -1, 1.5, '5', NaN, Infinity, null, undefined, true];
    const errs = [];
    for (const v of bads) {
      const tagv = typeof v === 'string' ? JSON.stringify(v) : String(v);
      if (core.isNat(v)) errs.push(`isNat accepts ${tagv}`);
      for (const k of ['D', 'tip', 'Mc', 'Mr', 'process', 'retract', 'W', 'far']) if (core.validateParams({ ...P, [k]: v }) === null) errs.push(`params accept ${k}=${tagv}`);
      const REG = { contribute: { aid: 1, owner: 1, submittedAt: 0, op: 'register' } };
      for (const k of ['gen', 'plugin', 'nextReq', 'nextToken']) { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, [k]: v }); if (r.ok || r.reason !== 'invalid-nat' || r.field !== k) errs.push(`state ${k}=${tagv} not refused invalid-nat/${k}`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, leaves: [{ aid: v, status: 'convicted' }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`leaf aid=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, leaves: [{ aid: 1, status: { active: v } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`leaf token=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, ckpts: [{ aid: 1, ckpt: { token: 0, k: v, st: 'live' } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`ckpt k=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, ckpts: [{ aid: 1, ckpt: { token: 0, k: 0, st: { parked: v } } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`ckpt parked=${tagv} not refused`); }
      { const r = core.step(P, core.emptyEnv(), REG, 0, { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: { goDormant: v } }] }); if (r.ok || r.reason !== 'invalid-nat') errs.push(`request goDormant=${tagv} not refused`); }
      const r1 = core.step(P, core.emptyEnv(), { contribute: { aid: v, owner: 1, submittedAt: 0, op: 'register' } }, 0, S0); if (r1.ok || r1.reason !== 'invalid-nat') errs.push(`action aid=${tagv} not refused`);
      const r2 = core.step(P, core.emptyEnv(), REG, v, S0); if (r2.ok || r2.reason !== 'invalid-nat' || r2.field !== 'now') errs.push(`now=${tagv} not refused`);
      const r3 = core.step(P, { ...core.emptyEnv(), inception: [v] }, REG, 0, S0); if (r3.ok || r3.reason !== 'invalid-nat') errs.push(`evidence inception=[${tagv}] not refused`);
      { const r = core.step(P, { ...core.emptyEnv(), rotationFrom: [[1, v]] }, REG, 0, S0); if (r.ok || r.reason !== 'invalid-nat') errs.push(`evidence rotationFrom=[[1,${tagv}]] not refused`); }
      const r4 = core.step(P, core.emptyEnv(), { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: v, do: 'process' }] } }, 0, S0); if (r4.ok || r4.reason !== 'invalid-nat') errs.push(`batch id=${tagv} not refused`);
      const r5 = core.replay(P, core.emptyEnv(), v, S0, []); if (r5.ok || r5.reason !== 'invalid-nat') errs.push(`replay t0=${tagv} not refused`);
    }
    const REG0 = { contribute: { aid: 1, owner: 1, submittedAt: 0, op: 'register' } };
    const shapes = [[{ bogus: 1 }, 'invalid-state'], [null, 'invalid-state'], [{ ...S0, extra: 1 }, 'invalid-state'], [{ ...S0, requests: [{ id: 0, aid: 1, owner: 1 }] }, 'invalid-nat'],
      [{ ...S0, leaves: [{ aid: 1, status: 'gone' }] }, 'invalid-state'], [{ ...S0, ckpts: [{ aid: 1, ckpt: { token: 0, k: 0, st: 'frozen' } }] }, 'invalid-state'], [{ ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: 'close' }] }, 'invalid-state']];
    for (const [st, want] of shapes) { const r = core.step(P, core.emptyEnv(), REG0, 0, st); if (r.ok || r.reason !== want) errs.push(`shape ${JSON.stringify(st)} gave ${r.reason}, expected ${want}`); }
    for (const [a, want] of [[null, 'invalid-action'], [{ contribute: { aid: 1 } }, 'invalid-nat'], [{ contribute: { aid: 1, owner: 1, submittedAt: 0, op: 'close' } }, 'invalid-action'], [{ fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'burn' }] } }, 'invalid-action'], [{ rotate: {} }, 'invalid-action'], [{ pause: { aid: 1 }, resume: { aid: 1 } }, 'invalid-action']]) {
      const r = core.step(P, core.emptyEnv(), a, 0, S0); if (r.ok || r.reason !== want) errs.push(`action ${JSON.stringify(a)} gave ${r.reason}, expected ${want}`);
    }
    for (const [e, want] of [[null, 'invalid-evidence'], [{ inception: 'x' }, 'invalid-evidence'], [{ ...core.emptyEnv(), bogus: [] }, 'invalid-evidence'], [{ ...core.emptyEnv(), rotationFrom: [[1]] }, 'invalid-evidence']]) {
      const r = core.step(P, e, REG0, 0, S0); if (r.ok || r.reason !== want) errs.push(`evidence ${JSON.stringify(e)} gave ${r.reason}, expected ${want}`);
    }
    // a counter at the bound is a Nat whose successor is not: every successor, sum and product refuses by the field it would write
    {
      const M = core.MAX_NAT, E = core.emptyEnv();
      const want = (label, r, field) => { if (r.ok || r.reason !== 'invalid-nat' || r.field !== field) errs.push(`${label}: got ${r.ok ? 'applied' : r.reason + '/' + r.field}, expected invalid-nat/${field}`); };
      want('nextReq at the bound, contribute', core.step(P, E, REG0, 0, { ...S0, nextReq: M }), 'nextReq');
      const withReq = { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: 'register' }], nextReq: 1 };
      want('nextToken at the bound, a register folds', core.step(P, { ...E, inception: [1] }, { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, 0, { ...withReq, nextToken: M }), 'nextToken');
      want('gen at the bound, a fold', core.step(P, { ...E, inception: [1] }, { fold: { folder: 3, gen: M, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, 0, { ...withReq, gen: M }), 'gen');
      const lateReq = { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: M, op: 'register' }], nextReq: 1 };
      want('submittedAt at the bound, retract', core.step(P, E, { retract: { req: 0 } }, M, lateReq), 'submittedAt+process');
      want('submittedAt at the bound, process', core.step(P, { ...E, inception: [1] }, { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, M, lateReq), 'submittedAt+process');
      const withCk = { ...S0, leaves: [{ aid: 1, status: { active: 0 } }], ckpts: [{ aid: 1, ckpt: { token: 0, k: M, st: 'live' } }], nextToken: 1 };
      want('k at the bound, pause', core.step(P, { ...E, rotationFrom: [[1, M]] }, { pause: { aid: 1 } }, 0, withCk), 'k');
      const parked = { ...withCk, ckpts: [{ aid: 1, ckpt: { token: 0, k: 0, st: { parked: M } } }] };
      want('parked at the bound, reap', core.step(P, E, { reap: { reaper: 6, aid: 1 } }, M, parked), 'parked+W');
      const Q = { D: 2, tip: M - 1, Mc: M, Mr: 1, process: 1, retract: 1, W: 1, far: M };
      if (core.validateParams(Q)) errs.push('params at the bound refused: ' + JSON.stringify(core.validateParams(Q)));
      else {
        want('bond + tip past the bound, contribute', core.step(Q, E, REG0, 0, S0), 'deposited');
        const two = { ...S0, requests: [{ id: 0, aid: 1, owner: 1, submittedAt: 0, op: 'register' }, { id: 1, aid: 2, owner: 2, submittedAt: 0, op: 'register' }], nextReq: 2 };
        want('n × tip past the bound, a fold of two rejects', core.step(Q, E, { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'reject' }, { id: 1, do: 'reject' }] } }, 5, two), 'tips');
      }
      // a boundary refusal exhibits no theorem
      const sc = { id: 99, slug: 'boundary', story: 'boundary', params: P, plugin: 7, steps: [{ now: 0, action: REG0, expect: { ok: false, reason: 'invalid-nat' }, exhibits: ['R6'] }], initial: { ...S0, nextReq: M } };
      const r = core.checkScenario(sc, 'boundary', null);
      if (!r.problems.some(p => /claims to exhibit R6 but it is a boundary refusal/.test(p))) errs.push('a boundary refusal was allowed to exhibit a theorem');
    }
    if (core.validateParams({ ...P, D: 0 }) === null || core.validateParams({ ...P, D: 0 }).reason !== 'invalid-params') errs.push('zero bond accepted');
    if (core.validateParams({ ...P, Mc: 1 }) === null || core.validateParams({ ...P, Mc: 1 }).reason !== 'invalid-params') errs.push('a checkpoint that cannot fund its go-request accepted');
    row('exact Nat and shapes refused by name at every entry point, and every successor, sum and product at the bound', errs.length === 0, errs.length ? errs.slice(0, 4).join(' | ') : `${bads.length} bad numbers × every field; 9 results at the bound`);
  }

  // 3b. every executable property reds on a fabricated violation (a lamp that
  // cannot go red is not a check)
  {
    const P = { D: 1000, tip: 2, Mc: 4, Mr: 1, process: 10, retract: 10, W: 5, far: 1000000000 };
    const E = core.emptyEnv();
    const S = (o = {}) => ({ ...core.initSys(7), ...o });
    const leaf = (aid, status) => ({ aid, status });
    const ck = (aid, token, k, st) => ({ aid, ckpt: { token, k, st } });
    const req = (id, aid, owner, submittedAt, op) => ({ id, aid, owner, submittedAt, op });
    const okr = (state, fl = {}) => ({ ok: true, flow: core.flow(fl), state });
    const registered = S({ gen: 1, leaves: [leaf(11, { active: 0 })], ckpts: [ck(11, 0, 0, 'live')], nextReq: 1, nextToken: 1 });
    const fold1 = { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } };
    const V = {
      R1: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, leaves: [leaf(11, { active: 1 })] }) },
      R1d: { before: { ...registered, requests: [req(1, 11, 4, 5, 'register')], nextReq: 2 }, action: { fold: { folder: 3, gen: 1, plugin: 7, batch: [{ id: 1, do: 'process' }] } }, now: 6, result: okr(registered, { locked: [{ aid: 11, value: 1000 }], tips: { addr: 3, value: 2 } }) },
      R2: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, leaves: [leaf(11, { active: 0 }), leaf(11, { active: 0 })] }) },
      R3: { before: S({ leaves: [leaf(11, 'convicted')] }), action: { pause: { aid: 11 } }, now: 5, result: okr(S({ leaves: [leaf(11, { active: 0 })] })) },
      R4: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, leaves: [] }) },
      R5: { before: registered, action: { pause: { aid: 11 } }, now: 5, result: okr({ ...registered, plugin: 8 }) },
      R6: { before: registered, action: { contribute: { aid: 12, owner: 2, submittedAt: 5, op: 'register' } }, now: 5, result: okr({ ...registered, gen: 2 }, { deposited: 1002 }) },
      R7: { before: registered, action: { fold: { folder: 3, gen: 0, plugin: 7, batch: [{ id: 0, do: 'process' }] } }, now: 5, result: okr(registered) },
      R8: { before: registered, action: { fold: { folder: 3, gen: 1, plugin: 7, batch: [] } }, now: 5, result: okr({ ...registered, gen: 2 }) },
      R9: { before: S({ requests: [req(0, 11, 1, 0, 'register')], nextReq: 1 }), action: { retract: { req: 0 } }, now: 3, result: okr(S({ nextReq: 1 }), { refunds: [{ addr: 1, value: 1002 }] }) },
      R11: { before: S({ requests: [req(0, 11, 1, 0, 'register')], nextReq: 1 }), action: fold1, now: 1, result: okr(registered, { refunds: [{ addr: 1, value: 1000 }], tips: { addr: 3, value: 2 } }) },
      R12: { before: registered, action: { contribute: { aid: 12, owner: 2, submittedAt: 5, op: 'register' } }, now: 5, result: okr({ ...registered, leaves: [leaf(11, { active: 0 }), leaf(12, { active: 1 })] }, { deposited: 1002 }) },
      R13: { before: { ...registered, ckpts: [ck(11, 0, 1, { parked: 5 })] }, action: { reap: { reaper: 6, aid: 11 } }, now: 20, result: okr({ ...registered, ckpts: [ck(11, 0, 1, { parked: 5 })] }, { premium: { addr: 6, value: 1 }, intoRequest: 3 }) },
      R14: { before: registered, action: { convictCkpt: { aid: 11 } }, now: 5, result: okr({ ...registered, ckpts: [ck(11, 0, 0, 'tomb')] }) },
    };
    const errs = [], noControl = [];
    for (const t of core.THEOREMS) {
      const v = V[t.id];
      if (!v) { noControl.push(t.id); continue; }
      const rec = { params: P, env: E, ...v };
      let out; try { out = t.check(rec); } catch (e) { out = { v: 'threw', why: e.message }; }
      if (!out || out.v !== 'fails') errs.push(`${t.id} says ${out ? out.v : 'nothing'} on a fabricated violation`);
    }
    // R10 is structural (the phase functions are exclusive on every request of the
    // record): no record can lie to it; the phases-overlap mutant of --selftest reds it.
    const allowed = ['R10'];
    for (const id of noControl) if (!allowed.includes(id)) errs.push(`no fabricated violation for ${id}`);
    row('every executable property reds on a fabricated violation', errs.length === 0, errs.length ? errs.join(' | ') : `${Object.keys(V).length} fabricated records, each refused by its lamp; R10 by the phases-overlap mutant`);
  }

  // 3c. the stories' clauses against the Lean, and the guard table both ways
  {
    let cl = null;
    try { cl = checkClauses(core, JSON.parse(readFileSync(clausesPath, 'utf8')), readFileSync(storiesMd, 'utf8'), timelines, leanRoot); }
    catch (e) { row('every clause of every story reconciled with the Lean', false, 'checker crashed: ' + e.stack.split('\n').slice(0, 3).join(' « ')); }
    if (cl) row('every clause of every story reconciled with the Lean; every decision site of the Lean claimed by a refusal name', cl.problems.length === 0, cl.problems.length ? cl.problems.slice(0, 14).join(' | ') : `${cl.clauses} clauses (${cl.anchored} anchored, ${cl.omissions} omissions), ${cl.fragments} fragments, ${cl.sites} decision sites on the path from stepFn`);
  }

  // 4. build drift
  let buildOut = '';
  try { buildOut = execFileSync(process.execPath, [BUILD, '--check', '--html', html, '--core', corePath, '--scenarios', scenDir, '--corpus', corpusPath, '--docs', docs], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim(); row('generated page and published copy are current', true, buildOut); }
  catch (e) { row('generated page and published copy are current', false, (e.stderr || e.stdout || String(e)).trim()); }

  // 5. the page under the minimal DOM
  {
    const doc = readFileSync(html, 'utf8');
    const errs = [];
    try {
      const w = createWindow(doc, { search: '?selftest=1' });
      if (w.__errors.length) errs.push('selftest threw: ' + w.__errors.map(e => e.message).join(' | '));
      if (!w.__selftest || !w.__selftest.ok) errs.push('page selftest FAIL: ' + (w.__selftest ? w.__selftest.rows.filter(r => !r.ok).map(r => r.what + ' — ' + r.detail).join(' | ') : 'no result'));
    } catch (e) { errs.push('selftest mode: ' + e.message); }
    try {
      const w = createWindow(doc, {});
      const d = w.document, $ = id => d.getElementById(id);
      if (w.__errors.length) errs.push('init threw: ' + w.__errors.map(e => e.message).join(' | '));
      const opts = [...$('sc-pick').options].slice(1);
      if (opts.length !== N_STORIES) errs.push(`picker has ${opts.length} stories`);
      let mismatches = 0, applied = 0;
      for (const o of opts) {
        $('sc-pick').value = o.value; $('sc-pick').dispatchEvent(new w.Event('change'));
        $('sc-step').click(); $('sc-all').click();
        const s = w.__registrySim.session;
        mismatches += s.history.filter(h => h.mismatch).length; applied += s.history.filter(h => h.result.ok).length;
        if (!$('sc-step').disabled) errs.push(`story ${o.value}: play all did not finish`);
        $('sc-reset').click();
        if (w.__registrySim.session.history.length) errs.push(`story ${o.value}: restart kept history`);
      }
      if (mismatches) errs.push(`${mismatches} story steps disagreed with the page`);
      if (!applied) errs.push('no story step applied');
      // the tree of the play: a branch taken from a continuation, a node of the trunk taken back
      {
        const sc13 = JSON.parse(readFileSync(join(scenDir, '13-convict-dormant.json'), 'utf8'));
        $('sc-pick').value = '13'; $('sc-pick').dispatchEvent(new w.Event('change'));
        if ($('play').hidden) errs.push('tree: #play hidden inside a story');
        const fk = sc13.forks.find(f => f.id === 'convict-without-proof');
        for (let k = 0; k < fk.at; k++) $('sc-step').click();
        const btn = d.querySelector(`#branches .branch[data-branch="${fk.id}"]`);
        if (!btn) errs.push('tree: no continuation button for the fork departing here');
        else {
          btn.click();
          const st = w.__registrySim.story, ses = w.__registrySim.session;
          if (!st || st.branch !== fk.id) errs.push('tree: the continuation did not switch to the fork');
          $('sc-all').click();
          const last = w.__registrySim.session.history[w.__registrySim.session.history.length - 1];
          if (!last || last.result.ok || last.result.reason !== fk.steps[fk.steps.length - 1].expect.reason) errs.push('tree: the fork did not play to its refusal');
          if (w.__registrySim.session.history.some(h => h.mismatch)) errs.push('tree: a fork step disagreed with the page');
          if (!d.querySelector(`#tree .node[data-branch="${fk.id}"].bad`)) errs.push('tree: the refused fork step is not drawn ✗');
          const node = d.querySelector('#tree .node[data-branch=""][data-i="2"]');
          if (!node) errs.push('tree: no trunk node'); else { node.click(); const s2 = w.__registrySim; if (s2.story.branch !== null || s2.session.history.length !== 3) errs.push('tree: clicking a trunk node did not go there'); }
          if (!d.querySelector('#branches .branch.on')) errs.push('tree: no default continuation marked');
        }
        $('sc-exit').click();
        if (!$('play').hidden) errs.push('tree: #play shown outside a story');
      }
      $('sc-pick').value = '1'; $('sc-pick').dispatchEvent(new w.Event('change')); $('sc-exit').click();
      if (!$('storybox').hidden) errs.push('leave story did not hide the story box');
      // free play: evidence, request, fold, stale fold, slot, history, theme
      $('ev-aid').value = '11'; $('ev-add').click();
      const cb = d.querySelector('input[data-ev="inception"][data-aid="11"]'); if (!cb) errs.push('no evidence row for AID 11'); else if (!cb.checked) { cb.checked = true; cb.dispatchEvent(new w.Event('change')); }
      $('a-c-op').value = 'register'; $('a-c-aid').value = '11'; $('a-c-owner').value = '1'; $('a-c-t').value = '0';
      d.querySelector('button[data-go="contribute"]').click();
      let s = w.__registrySim.session;
      if (s.state.requests.length !== 1) errs.push('free play: request not posted');
      const sel = d.querySelector('select[data-batch="0"]'); if (!sel) errs.push('free play: no batch selector'); else sel.value = 'process';
      d.querySelector('button[data-go="fold"]').click();
      s = w.__registrySim.session;
      const last = s.history[s.history.length - 1];
      if (!last.result.ok) errs.push(`free play: fold refused (${last.result.reason})`);
      if (core.lookupLeaf(s.state.leaves, 11) === null || core.lookupCkpt(s.state.ckpts, 11) === null) errs.push('free play: AID 11 not registered after the fold');
      const rot = d.querySelector('input[data-ev="rotationFrom"][data-aid="11"][data-k="0"]'); if (!rot) errs.push('free play: no rotation evidence control'); else { rot.checked = true; rot.dispatchEvent(new w.Event('change')); }
      $('a-p-aid').value = '11'; d.querySelector('button[data-go="pause"]').click();
      s = w.__registrySim.session;
      if (!s.history[s.history.length - 1].result.ok) errs.push(`free play: pause refused (${s.history[s.history.length - 1].result.reason})`);
      $('slot-10').click(); $('a-rp-aid').value = '11'; d.querySelector('button[data-go="reap"]').click();
      s = w.__registrySim.session;
      const rp = s.history[s.history.length - 1].result;
      if (!rp.ok || !rp.flow.premium) errs.push(`free play: reap refused after the grace window (${rp.reason})`);
      if (!s.state.requests.some(r => !core.userPostable(r.op))) errs.push('free play: no go-request after the reap');
      $('a-f-gen').value = '0'; d.querySelector('button[data-go="fold"]').click();
      s = w.__registrySim.session;
      const st = s.history[s.history.length - 1];
      if (st.result.ok || st.result.reason !== 'stale-generation') errs.push(`free play: stale fold not refused (${st.result.ok ? 'applied' : st.result.reason})`);
      if ($('whyline').hidden || !/stale-generation/.test($('whyline').textContent)) errs.push('free play: refusal not shown');
      if (Number($('slot').textContent) !== 10) errs.push('slot control');
      $('h-first').click(); if (w.__registrySim.session.cursor !== 0) errs.push('history first');
      $('h-next').click(); $('h-last').click(); $('h-prev').click(); $('h-clear').click();
      if (w.__registrySim.session.history.length) errs.push('clear history');
      const before = d.documentElement.getAttribute('data-theme'); $('btn-theme').click();
      if (d.documentElement.getAttribute('data-theme') === before) errs.push('theme toggle');
      if (!/R1/.test($('ledger').innerHTML)) errs.push('ledger not rendered');
      if (w.__errors.length) errs.push('page threw: ' + w.__errors.map(e => e.message).join(' | '));
    } catch (e) { errs.push('page smoke: ' + e.message); }
    row('the page plays every story, switches a branch through the tree, self-tests, and free play works under the minimal DOM', errs.length === 0, errs.length ? errs.slice(0, 5).join(' | ') : 'selftest PASS, 15 stories, a fork taken and a trunk node taken back, free play (register, pause, reap), evidence, slot, history, theme');
  }

  if (!quiet) {
    for (const r of rows) console.log(`${r.ok ? 'ok ' : 'RED'}  ${r.what}${r.detail ? ' — ' + r.detail : ''}`);
    console.log(problems.length ? `RED: ${problems.length} problem(s)` : `GREEN: ${rows.length} checks, ${steps} story steps`);
  }
  return { ok: problems.length === 0, problems, rows };
}

async function selftest() {
  const tmp = mkdtempSync(join(tmpdir(), 'registry-sim-gate-'));
  const controls = [];
  const control = async (name, mutate, expectRe) => {
    const dir = join(tmp, name); mkdirSync(dir);
    for (const f of ['registry-simulator-core.mjs', 'registry-simulator.html', 'registry-simulator-corpus.json', 'checkpoint-simulator-minidom.mjs', 'registry-simulator-build.mjs', 'registry-simulator-clauses.json', 'REGISTRY-STORIES.md']) cpSync(join(HERE, f), join(dir, f));
    cpSync(SCEN_DIR, join(dir, 'scenarios'), { recursive: true });
    cpSync(DOCS, join(dir, 'index.html'));
    mkdirSync(join(dir, 'lean', 'CardanoKeri'), { recursive: true });
    for (const f of ['Registry.lean', 'RegistryGoals.lean']) cpSync(join(LEAN_ROOT, 'lean', 'CardanoKeri', f), join(dir, 'lean', 'CardanoKeri', f));
    mutate(dir);
    const r = await run({ core: join(dir, 'registry-simulator-core.mjs'), html: join(dir, 'registry-simulator.html'), scenDir: join(dir, 'scenarios'), corpusPath: join(dir, 'registry-simulator-corpus.json'), docs: join(dir, 'index.html'), clausesPath: join(dir, 'registry-simulator-clauses.json'), storiesMd: join(dir, 'REGISTRY-STORIES.md'), leanRoot: dir, quiet: true });
    const red = !r.ok && r.problems.some(p => expectRe.test(p));
    controls.push({ name, red, why: red ? r.problems.find(p => expectRe.test(p)) : (r.ok ? 'stayed GREEN' : 'RED for another reason: ' + r.problems[0]) });
  };
  const edit = (f, from, to) => { const t = readFileSync(f, 'utf8'); if (!t.includes(from)) throw new Error(`control edit: ${from} not found in ${f}`); writeFileSync(f, t.replace(from, to)); };
  await control('flipped-expectation', dir => edit(join(dir, 'scenarios', '04-duplicate-registration.json'), '"reason":"already-registered"', '"reason":"not-in-phase-1"'), /story 4 .*refused already-registered, expected not-in-phase-1/);
  await control('forked-embedded-slice', dir => edit(join(dir, 'registry-simulator.html'), "if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD);", "if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD); /* forked */"), /stale or forked/);
  await control('flipped-guard-absence-proof', dir => { edit(join(dir, 'registry-simulator-core.mjs'), 'if (leaf !== null) return { ok: false, reason: REASONS.ALREADY_REGISTERED };', '/* mutant: absence proof removed */'); }, /story 4 .*|story 12 .*|Lean corpus replays/);
  await control('lying-theorem-never-fires', dir => edit(join(dir, 'registry-simulator-core.mjs'), "const f = foldOf(action); if (!f || f.gen === before.gen) return { v: 'n/a' };", "const f = foldOf(action); return { v: 'n/a' };"), /claims to exhibit R7 but it is n\/a/);
  await control('fork-expectation-flipped', dir => edit(join(dir, 'scenarios', '13-convict-dormant.json'), '"reason":"no-duplicity-proof"', '"reason":"not-dormant"'), /story 13 .*fconvict-without-proof\.step 1: refused no-duplicity-proof, expected not-dormant/);
  await control('overflow-unchecked', dir => edit(join(dir, 'registry-simulator-core.mjs'), 'const r = a + b; if (r > MAX_NAT) throw new NatOverflow(field); return r;', 'return a + b;'), /nextReq at the bound, contribute: got applied/);
  await control('lamp-that-cannot-go-red', dir => edit(join(dir, 'registry-simulator-core.mjs'), "      if (result.ok) {\n        const s = result.state;\n        if (lookupCkpt(s.ckpts, aid) !== null)", "      if (false) {\n        const s = result.state;\n        if (lookupCkpt(s.ckpts, aid) !== null)"), /R13 says holds on a fabricated violation/);
  await control('phases-overlap', dir => edit(join(dir, 'registry-simulator-core.mjs'), 'function inPhase2(p, r, now) { return phase1End(p, r) <= now && now < phase2End(p, r); }', 'function inPhase2(p, r, now) { return now < phase2End(p, r); }'), /theorem R10 fails/);
  // the three survivors of the checkpoint audit, then the story and the Lean side
  await control('clause-re-anchored-to-an-unrelated-declaration', dir => edit(join(dir, 'registry-simulator-clauses.json'), '"clause":"a witnessed rotation from the recorded key state","class":"guard","kind":"guard","decl":"processBody","arm":".revive","text":"env.rotationFrom r.aid k = true"', '"clause":"a witnessed rotation from the recorded key state","class":"guard","kind":"guard","decl":"stepFn","arm":".pause","text":"env.rotationFrom aid k = true"'), /goes through \.fold, not \.pause/);
  await control('clause-same-text-on-another-arm', dir => edit(join(dir, 'registry-simulator-clauses.json'), '"clause":"a revive needs a dormant leaf","class":"guard","kind":"guard","decl":"processBody","arm":".revive"', '"clause":"a revive needs a dormant leaf","class":"guard","kind":"guard","decl":"processBody","arm":".convict"'), /does not process a \.convict request/);
  await control('clause-wrong-but-existing-text', dir => edit(join(dir, 'registry-simulator-clauses.json'), '"clause":"a registration whose inception does not verify is refused","class":"guard","kind":"refusal","decl":"processBody","arm":".register","text":"env.inception r.aid = true"', '"clause":"a registration whose inception does not verify is refused","class":"guard","kind":"refusal","decl":"processBody","arm":".register","text":"lookup acc.leaves r.aid = none"'), /bad-inception is decided at .* not by «lookup acc.leaves r.aid = none»/);
  await control('clause-missing-from-the-story', dir => edit(join(dir, 'REGISTRY-STORIES.md'), 'the plugin is pinned; the request is in phase 1;', 'the request is in phase 1;'), /clause «the plugin is pinned» does not occur/);
  await control('story-fragment-unclassified', dir => edit(join(dir, 'REGISTRY-STORIES.md'), '- **Money**: the bond is locked into the checkpoint;', '- **Money**: the bond is locked into the checkpoint; the fee is paid by the folder;'), /unclassified fragment/);
  await control('lean-conjunct-edited', dir => edit(join(dir, 'lean', 'CardanoKeri', 'Registry.lean'), 'if g = s.gen ∧ pl = s.plugin ∧ batch ≠ [] then', 'if g = s.gen ∧ pl = s.plugin ∧ batch.length ≠ 0 then'), /«batch ≠ \[\]» is not inside stepFn \.fold|decision site of the Lean no refusal name claims/);
  await control('lean-guard-unclaimed', dir => edit(join(dir, 'registry-simulator-core.mjs'), "'already-tombstone': { sites: [site('stepFn', '.convictCkpt', 'st ≠ .tomb')] },", "'already-tombstone': { sites: [] },"), /stepFn \.convictCkpt «st ≠ \.tomb».*no refusal name claims/);
  await control('dead-branch-button', dir => edit(join(dir, 'registry-simulator.html'), "b.addEventListener('click', () => goTo(it.branch, it.to));", "b.addEventListener('click', () => {});"), /tree: the continuation did not switch to the fork/);
  await control('broken-page-control', dir => edit(join(dir, 'registry-simulator.html'), "$('sc-all').addEventListener('click', () => { while (storyStep()) {} });", "$('sc-all').addEventListener('click', () => {});"), /play all did not finish/);
  rmSync(tmp, { recursive: true, force: true });
  for (const c of controls) console.log(`${c.red ? 'RED (intended)' : 'CONTROL FAILED'}  ${c.name} — ${c.why}`);
  const all = controls.every(c => c.red);
  console.log(all ? `controls: ${controls.length}/${controls.length} red for the intended reason` : 'controls: some did not go red');
  return all;
}

const main = async () => {
  if (process.argv.includes('--clauses-md')) { console.log(clausesMarkdown(JSON.parse(readFileSync(CLAUSES, 'utf8')))); process.exit(0); }
  if (process.argv.includes('--selftest')) {
    const ok = await selftest();
    if (!ok) process.exit(1);
    const r = await run();
    process.exit(r.ok ? 0 : 1);
  }
  const r = await run();
  process.exit(r.ok ? 0 : 1);
};
main().catch(e => { console.error('RED: gate crashed — ' + e.stack); process.exit(1); });
