#!/usr/bin/env node
/*
 * scenario-dsl.mjs — the ONE grammar for checkpoint and registry
 * simulator stories. Parser, validator, JSON conversion and canonical
 * serialization live here. No DOM, filesystem or process dependency.
 *
 * The block between @@DSL@@ markers is inlined into both simulator
 * pages; Node consumers import this module and assert GRAMMAR_VERSION.
 */

/* @@DSL@@ */
const ScenarioDslAPI = (() => {
const GRAMMAR_VERSION = '1';
const MAX_NAT = Number.MAX_SAFE_INTEGER;
const isNat = v => typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;
const FAMILIES = new Set(['checkpoint', 'registry']);
const REPEAT = { step: 'steps', fork: 'forks' };
const REPEAT_INV = { steps: 'step', forks: 'fork' };
const BARE_KEY = /^[A-Za-z0-9_'.-]+$/;
const BARE_STR = /^[A-Za-z_][A-Za-z0-9_.-]*$/;
const CK_TOP = ['story', 'title', 'goal', 'params', 'atoms', 'steps', 'forks'];
const CK_TOP_SET = new Set(CK_TOP);
const CK_STEP = ['slot', 'who', 'say', 'hidden', 'params', 'evidence', 'action', 'expect'];
const CK_STEP_SET = new Set(CK_STEP);
const CK_FORK = ['id', 'at', 'title', 'steps'];
const CK_FORK_SET = new Set(CK_FORK);
const RG_TOP = ['id', 'slug', 'story', 'narrative', 'params', 'plugin', 'actors', 'env', 'steps', 'forks', 'expectFinal'];
const RG_TOP_SET = new Set(RG_TOP);
const RG_STEP = ['now', 'actor', 'as', 'action', 'expect', 'exhibits', 'note'];
const RG_STEP_SET = new Set(RG_STEP);
const RG_FORK = ['id', 'at', 'title', 'env', 'expectFinal', 'steps'];
const RG_FORK_SET = new Set(RG_FORK);
const CK_NEED = ['story', 'title', 'goal', 'params', 'atoms', 'steps'];
const RG_NEED = ['id', 'slug', 'story', 'narrative', 'params', 'plugin', 'actors', 'steps'];

class ScenarioDslError extends Error {
  constructor(sourceName, line, column, message) {
    const col = column && column > 0 ? column : 1;
    super(`${sourceName}:${line}: ${message}`);
    this.name = 'ScenarioDslError';
    this.sourceName = sourceName;
    this.line = line;
    this.column = col;
    this.diagnostic = { sourceName, line, column: col, message };
  }
}

function assertGrammarVersion(expectedVersion) {
  if (expectedVersion !== GRAMMAR_VERSION) {
    throw new Error(
      `grammar version mismatch: consumer expected ${JSON.stringify(expectedVersion)}, module exports ${JSON.stringify(GRAMMAR_VERSION)}`,
    );
  }
}

function lossyJsonNumbers(text) {
  const bad = [];
  let i = 0, inStr = false;
  while (i < text.length) {
    const ch = text[i];
    if (inStr) { if (ch === '\\') i++; else if (ch === '"') inStr = false; i++; continue; }
    if (ch === '"') { inStr = true; i++; continue; }
    if (/[-0-9]/.test(ch)) {
      let j = i; while (j < text.length && /[-+0-9.eE]/.test(text[j])) j++;
      const tok = text.slice(i, j);
      if (/^-?\d/.test(tok)) {
        const n = Number(tok);
        const intTok = /^-?\d+$/.test(tok);
        if (!Number.isFinite(n) || (intTok && (BigInt(tok) !== BigInt(Math.trunc(n)) || Math.abs(n) > MAX_NAT))) bad.push(tok);
      }
      i = j; continue;
    }
    i++;
  }
  return bad;
}

function parseJsonExact(text, sourceName, line) {
  const bad = lossyJsonNumbers(text);
  if (bad.length) throw new ScenarioDslError(sourceName, line, 1, 'lossy or unsafe number literal: ' + bad[0]);
  try { return JSON.parse(text); }
  catch (e) { throw new ScenarioDslError(sourceName, line, 1, 'invalid JSON value: ' + e.message); }
}

function stripComment(raw) {
  let inStr = false, out = '';
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if (inStr) {
      out += ch;
      if (ch === '\\' && i + 1 < raw.length) { out += raw[++i]; continue; }
      if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') { inStr = true; out += ch; continue; }
    if (ch === '#') break;
    out += ch;
  }
  return out.replace(/\s+$/, '');
}

function logicalLines(text, sourceName) {
  const raw = text.split(/\n/);
  const out = [];
  for (let n = 0; n < raw.length; n++) {
    const lineNo = n + 1;
    const phys = raw[n].replace(/\r$/, '');
    if (phys.includes('\t')) throw new ScenarioDslError(sourceName, lineNo, phys.indexOf('\t') + 1, 'tabs are not allowed; use spaces');
    let i = 0; while (i < phys.length && phys[i] === ' ') i++;
    const stripped = stripComment(phys.slice(i));
    if (!stripped) continue;
    out.push({ line: lineNo, indent: i, text: stripped, column: i + 1 });
  }
  return out;
}

function parseQuoted(s, sourceName, line, col0) {
  if (s[0] !== '"') return null;
  let i = 1, out = '';
  while (i < s.length) {
    const ch = s[i];
    if (ch === '"') return { value: out, rest: s.slice(i + 1) };
    if (ch === '\\') {
      const n = s[i + 1];
      if (n === undefined) throw new ScenarioDslError(sourceName, line, col0 + i, 'unterminated escape');
      if (n === 'n') out += '\n';
      else if (n === 't') out += '\t';
      else if (n === '"' || n === '\\') out += n;
      else if (n === 'u') {
        const hex = s.slice(i + 2, i + 6);
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) throw new ScenarioDslError(sourceName, line, col0 + i, 'invalid unicode escape');
        out += String.fromCharCode(parseInt(hex, 16));
        i += 4;
      } else throw new ScenarioDslError(sourceName, line, col0 + i, 'invalid escape');
      i += 2; continue;
    }
    out += ch; i++;
  }
  throw new ScenarioDslError(sourceName, line, col0, 'unterminated string');
}

function parseNumberToken(t, sourceName, line, col) {
  if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(t)) return null;
  if (t.replace(/^-/, '').split('.')[0].length > 16) throw new ScenarioDslError(sourceName, line, col, 'integer exceeds a safe JSON number');
  const n = Number(t);
  if (!Number.isFinite(n)) throw new ScenarioDslError(sourceName, line, col, 'number is not finite');
  if (Number.isInteger(n) && !Number.isSafeInteger(n)) throw new ScenarioDslError(sourceName, line, col, 'integer is not a safe JSON integer');
  if (String(n) !== t && !(t.includes('.') && n === Number(t))) {
    /* 2.50 → 2.5 is still the same value; reject exponent-like drift */
    if (Number(t) !== n) throw new ScenarioDslError(sourceName, line, col, 'number does not round-trip');
  }
  return n;
}

function parseScalar(s, sourceName, line, col) {
  const t = s.trim();
  if (t === '') throw new ScenarioDslError(sourceName, line, col, 'missing value');
  if (t === 'true') return true;
  if (t === 'false') return false;
  if (t === 'null') return null;
  const num = parseNumberToken(t, sourceName, line, col);
  if (num !== null) return num;
  if (t[0] === '"') {
    const q = parseQuoted(t, sourceName, line, col);
    if (q.rest.trim()) throw new ScenarioDslError(sourceName, line, col, 'trailing junk after string');
    return q.value;
  }
  if (t[0] === '{' || t[0] === '[') return parseJsonExact(t, sourceName, line);
  if (/^-/.test(t) || (/[.eE]/.test(t) && /^\d/.test(t))) throw new ScenarioDslError(sourceName, line, col, 'unsupported number syntax');
  if (/\s/.test(t)) throw new ScenarioDslError(sourceName, line, col, 'unquoted string contains whitespace; quote it');
  return t;
}

function splitInlineList(inner, sourceName, line) {
  const items = [];
  let cur = '', depth = 0, inStr = false;
  for (let i = 0; i < inner.length; i++) {
    const ch = inner[i];
    if (inStr) {
      cur += ch;
      if (ch === '\\' && i + 1 < inner.length) { cur += inner[++i]; continue; }
      if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') { inStr = true; cur += ch; continue; }
    if (ch === '{' || ch === '[') { depth++; cur += ch; continue; }
    if (ch === '}' || ch === ']') { depth--; cur += ch; continue; }
    if (ch === ',' && depth === 0) { items.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (inStr) throw new ScenarioDslError(sourceName, line, 1, 'unterminated string in list');
  if (cur.trim() !== '' || inner.trim() === '') items.push(cur.trim());
  return items.filter((x, i, a) => !(x === '' && a.length === 1 && inner.trim() === ''));
}

function parseInlineList(s, sourceName, line, col) {
  const t = s.trim();
  if (t[0] !== '[') return null;
  if (t[t.length - 1] !== ']') {
    try { return parseJsonExact(t, sourceName, line); }
    catch (e) { throw new ScenarioDslError(sourceName, line, col, 'unterminated inline list'); }
  }
  try { return parseJsonExact(t, sourceName, line); }
  catch (e) {
    const inner = t.slice(1, -1);
    if (!inner.trim()) return [];
    return splitInlineList(inner, sourceName, line).map(x => parseScalar(x, sourceName, line, col));
  }
}

function parseKey(s, sourceName, line, col) {
  const t = s.trim();
  if (t[0] === '"') {
    const q = parseQuoted(t, sourceName, line, col);
    if (!q.rest.startsWith(':') && !/^\s*:/.test(q.rest)) throw new ScenarioDslError(sourceName, line, col, 'expected ":" after key');
    const rest = q.rest.replace(/^\s*:/, '').replace(/^\s*/, '');
    return { key: q.value, rest };
  }
  const m = t.match(/^([A-Za-z0-9_'.-]+)\s*:(.*)$/);
  if (!m) throw new ScenarioDslError(sourceName, line, col, 'expected key:');
  if (!BARE_KEY.test(m[1])) throw new ScenarioDslError(sourceName, line, col, 'invalid key');
  return { key: m[1], rest: m[2].replace(/^\s*/, '') };
}

function parseBlock(lines, i, parentIndent, sourceName, locations, path) {
  if (i >= lines.length || lines[i].indent <= parentIndent) throw new ScenarioDslError(sourceName, lines[i - 1] ? lines[i - 1].line : 1, 1, 'expected indented block');
  const indent = lines[i].indent;
  if (indent <= parentIndent) throw new ScenarioDslError(sourceName, lines[i].line, 1, 'expected indented block');
  if (lines[i].text.startsWith('- ') || lines[i].text === '-') return parseList(lines, i, indent, sourceName, locations, path);
  return parseMapping(lines, i, indent, sourceName, locations, path);
}

function parseList(lines, i, indent, sourceName, locations, path) {
  const arr = [];
  while (i < lines.length && lines[i].indent === indent && (lines[i].text.startsWith('- ') || lines[i].text === '-')) {
    const L = lines[i];
    const rest = L.text === '-' ? '' : L.text.slice(2).replace(/^\s*/, '');
    const here = path + '[' + arr.length + ']';
    locations[here] = L.line;
    if (!rest) {
      const [val, ni] = parseBlock(lines, i + 1, indent, sourceName, locations, here);
      arr.push(val); i = ni; continue;
    }
    if (/^[A-Za-z0-9_'.-]+\s*:/.test(rest) || rest.startsWith('"')) {
      const fake = [{ ...L, text: rest, indent: indent + 2 }];
      let j = i + 1;
      while (j < lines.length && lines[j].indent > indent) {
        fake.push(lines[j]); j++;
      }
      const [val] = parseMapping(fake, 0, indent + 2, sourceName, locations, here);
      arr.push(val); i = j; continue;
    }
    arr.push(parseLineValue(rest, sourceName, L.line, L.column + 2));
    i++;
  }
  return [arr, i];
}

function parseLineValue(rest, sourceName, line, col) {
  if (rest === '|') throw new ScenarioDslError(sourceName, line, col, 'multiline "|" must be the whole value');
  const t = rest.trim();
  if (t[0] === '[') {
    const list = parseInlineList(t, sourceName, line, col);
    if (list !== null) return list;
  }
  return parseScalar(t, sourceName, line, col);
}

function parseMapping(lines, i, indent, sourceName, locations, path) {
  const obj = {};
  while (i < lines.length && lines[i].indent === indent) {
    const L = lines[i];
    if (L.text.startsWith('- ')) throw new ScenarioDslError(sourceName, L.line, L.column, 'list item in a mapping');
    const { key, rest } = parseKey(L.text, sourceName, L.line, L.column);
    const field = REPEAT[key] || key;
    const here = path ? path + '.' + field : field;
    if (REPEAT[key]) {
      if (!Array.isArray(obj[field])) obj[field] = [];
      const idx = obj[field].length;
      const itemPath = here + '[' + idx + ']';
      locations[itemPath] = L.line;
      let val, ni;
      if (!rest) {
        [val, ni] = parseBlock(lines, i + 1, indent, sourceName, locations, itemPath);
      } else {
        val = parseLineValue(rest, sourceName, L.line, L.column);
        ni = i + 1;
      }
      obj[field].push(val);
      i = ni;
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(obj, key)) throw new ScenarioDslError(sourceName, L.line, L.column, 'duplicate field ' + key);
    locations[here] = L.line;
    if (rest === '|') {
      const parts = [];
      let j = i + 1;
      while (j < lines.length && lines[j].indent > indent) {
        const raw = lines[j];
        parts.push(' '.repeat(raw.indent - indent - 2) + raw.text);
        j++;
      }
      obj[key] = parts.join('\n');
      i = j;
      continue;
    }
    if (!rest) {
      const [val, ni] = parseBlock(lines, i + 1, indent, sourceName, locations, here);
      obj[key] = val; i = ni; continue;
    }
    obj[key] = parseLineValue(rest, sourceName, L.line, L.column);
    i++;
  }
  return [obj, i];
}

function walkNats(x, sourceName, line, path, err) {
  if (typeof x === 'number') {
    if (!Number.isFinite(x) || (Number.isInteger(x) && !Number.isSafeInteger(x))) {
      err(sourceName, line, 1, `${path || 'value'} is not a finite safe JSON number`);
    }
    return;
  }
  if (Array.isArray(x)) { x.forEach((v, i) => walkNats(v, sourceName, line, path + '[' + i + ']', err)); return; }
  if (x && typeof x === 'object') {
    for (const [k, v] of Object.entries(x)) walkNats(v, sourceName, line, path ? path + '.' + k : k, err);
  }
}

function unknownKeys(obj, allowed, sourceName, locations, path, err) {
  for (const k of Object.keys(obj)) {
    if (!allowed.has(k)) err(sourceName, locations[path ? path + '.' + k : k] || 1, 1, `unknown field ${k}`);
  }
}

function needKeys(obj, names, sourceName, locations, path, err) {
  for (const k of names) {
    if (!Object.prototype.hasOwnProperty.call(obj, k)) err(sourceName, locations[path] || 1, 1, `missing required field ${k}`);
  }
}

function validateScenario(family, sc, sourceName, locations) {
  const err = (src, line, col, msg) => { throw new ScenarioDslError(src, line, col, msg); };
  if (!sc || typeof sc !== 'object' || Array.isArray(sc)) err(sourceName, 1, 1, 'scenario must be a mapping');
  walkNats(sc, sourceName, locations[''] || 1, '', err);
  if (family === 'checkpoint') {
    unknownKeys(sc, CK_TOP_SET, sourceName, locations, '', err);
    needKeys(sc, CK_NEED, sourceName, locations, '', err);
    if (!Array.isArray(sc.steps) || !sc.steps.length) err(sourceName, locations.steps || 1, 1, 'checkpoint scenario needs steps');
    if (!Array.isArray(sc.atoms)) err(sourceName, locations.atoms || 1, 1, 'atoms must be a list');
    if (sc.forks !== undefined && !Array.isArray(sc.forks)) err(sourceName, locations.forks || 1, 1, 'forks must be a list');
    sc.steps.forEach((st, i) => {
      if (!st || typeof st !== 'object') err(sourceName, locations[`steps[${i}]`] || 1, 1, 'step must be a mapping');
      unknownKeys(st, CK_STEP_SET, sourceName, locations, `steps[${i}]`, err);
      if (!isNat(st.slot)) err(sourceName, locations[`steps[${i}].slot`] || 1, 1, 'step slot must be a non-negative safe integer');
    });
    (sc.forks || []).forEach((fk, i) => {
      if (!fk || typeof fk !== 'object') err(sourceName, locations[`forks[${i}]`] || 1, 1, 'fork must be a mapping');
      unknownKeys(fk, CK_FORK_SET, sourceName, locations, `forks[${i}]`, err);
      if (typeof fk.id !== 'string' || !fk.id) err(sourceName, locations[`forks[${i}].id`] || 1, 1, 'fork id must be a non-empty string');
      if (!isNat(fk.at)) err(sourceName, locations[`forks[${i}].at`] || 1, 1, 'fork at must be a non-negative safe integer');
      if (!Array.isArray(fk.steps) || !fk.steps.length) err(sourceName, locations[`forks[${i}].steps`] || 1, 1, 'fork needs steps');
      fk.steps.forEach((st, j) => {
        if (!st || typeof st !== 'object') err(sourceName, locations[`forks[${i}].steps[${j}]`] || 1, 1, 'step must be a mapping');
        unknownKeys(st, CK_STEP_SET, sourceName, locations, `forks[${i}].steps[${j}]`, err);
      });
    });
  } else if (family === 'registry') {
    unknownKeys(sc, RG_TOP_SET, sourceName, locations, '', err);
    needKeys(sc, RG_NEED, sourceName, locations, '', err);
    if (!Array.isArray(sc.steps) || !sc.steps.length) err(sourceName, locations.steps || 1, 1, 'registry scenario needs steps');
    if (sc.forks !== undefined && !Array.isArray(sc.forks)) err(sourceName, locations.forks || 1, 1, 'forks must be a list');
    sc.steps.forEach((st, i) => {
      if (!st || typeof st !== 'object') err(sourceName, locations[`steps[${i}]`] || 1, 1, 'step must be a mapping');
      unknownKeys(st, RG_STEP_SET, sourceName, locations, `steps[${i}]`, err);
      if (!isNat(st.now)) err(sourceName, locations[`steps[${i}].now`] || 1, 1, 'step now must be a non-negative safe integer');
      if (st.action === undefined) err(sourceName, locations[`steps[${i}]`] || 1, 1, 'registry step needs an action');
    });
    (sc.forks || []).forEach((fk, i) => {
      if (!fk || typeof fk !== 'object') err(sourceName, locations[`forks[${i}]`] || 1, 1, 'fork must be a mapping');
      unknownKeys(fk, RG_FORK_SET, sourceName, locations, `forks[${i}]`, err);
      if (typeof fk.id !== 'string' || !fk.id) err(sourceName, locations[`forks[${i}].id`] || 1, 1, 'fork id must be a non-empty string');
      if (!isNat(fk.at)) err(sourceName, locations[`forks[${i}].at`] || 1, 1, 'fork at must be a non-negative safe integer');
      if (!Array.isArray(fk.steps) || !fk.steps.length) err(sourceName, locations[`forks[${i}].steps`] || 1, 1, 'fork needs steps');
      fk.steps.forEach((st, j) => {
        if (!st || typeof st !== 'object') err(sourceName, locations[`forks[${i}].steps[${j}]`] || 1, 1, 'step must be a mapping');
        unknownKeys(st, RG_STEP_SET, sourceName, locations, `forks[${i}].steps[${j}]`, err);
      });
    });
  } else err(sourceName, locations.family || 1, 1, 'family must be checkpoint or registry');
}

function parseScenarioDsl(sourceText, sourceName) {
  const name = sourceName || 'input';
  if (typeof sourceText !== 'string') throw new ScenarioDslError(name, 1, 1, 'source text must be a string');
  const lines = logicalLines(sourceText, name);
  if (!lines.length) throw new ScenarioDslError(name, 1, 1, 'empty document');
  const locations = {};
  const [doc, ni] = parseMapping(lines, 0, 0, name, locations, '');
  if (ni !== lines.length) throw new ScenarioDslError(name, lines[ni].line, lines[ni].column, 'unexpected content');
  if (!Object.prototype.hasOwnProperty.call(doc, 'grammar')) throw new ScenarioDslError(name, 1, 1, 'missing grammar version');
  if (String(doc.grammar) !== GRAMMAR_VERSION) throw new ScenarioDslError(name, locations.grammar || 1, 1, `document grammar ${JSON.stringify(doc.grammar)} does not match module ${JSON.stringify(GRAMMAR_VERSION)}`);
  if (!FAMILIES.has(doc.family)) throw new ScenarioDslError(name, locations.family || 1, 1, 'family must be checkpoint or registry');
  const scenario = {};
  for (const [k, v] of Object.entries(doc)) {
    if (k === 'grammar' || k === 'family') continue;
    scenario[k] = v;
  }
  validateScenario(doc.family, scenario, name, locations);
  return { grammarVersion: GRAMMAR_VERSION, family: doc.family, scenario, sourceName: name, locations };
}

function quoteStr(s) {
  return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"';
}
function emitKey(k) { return BARE_KEY.test(k) && !/:$/.test(k) ? k : quoteStr(k); }
function isScalar(x) { return x === null || typeof x === 'boolean' || typeof x === 'number' || typeof x === 'string'; }
function emitScalar(x) {
  if (x === null) return 'null';
  if (typeof x === 'boolean') return x ? 'true' : 'false';
  if (typeof x === 'number') return String(x);
  if (BARE_STR.test(x) && x !== 'true' && x !== 'false' && x !== 'null') return x;
  return quoteStr(x);
}
function awkward(x) {
  if (!Array.isArray(x)) return false;
  return x.some(v => v && typeof v === 'object' && !Array.isArray(v));
}

function emitLines(x, indent, keyOrder, asRepeat) {
  const pad = ' '.repeat(indent);
  const lines = [];
  if (isScalar(x)) { lines.push(pad + emitScalar(x)); return lines; }
  if (Array.isArray(x)) {
    if (!x.length) { lines.push(pad + '[]'); return lines; }
    if (x.every(isScalar) && !x.some(v => typeof v === 'string' && /\s/.test(v)) && x.length <= 24) {
      lines.push(pad + '[' + x.map(emitScalar).join(', ') + ']');
      return lines;
    }
    if (awkward(x)) { lines.push(pad + JSON.stringify(x)); return lines; }
    for (const item of x) {
      if (isScalar(item)) lines.push(pad + '- ' + emitScalar(item));
      else if (Array.isArray(item) && item.every(isScalar)) lines.push(pad + '- ' + '[' + item.map(emitScalar).join(', ') + ']');
      else if (item && typeof item === 'object' && !Array.isArray(item)) {
        const nested = emitLines(item, indent + 2, null, false);
        if (!nested.length) { lines.push(pad + '- {}'); continue; }
        const first = nested[0].replace(/^\s+/, '');
        lines.push(pad + '- ' + first);
        for (let i = 1; i < nested.length; i++) lines.push(nested[i]);
      } else lines.push(pad + '- ' + JSON.stringify(item));
    }
    return lines;
  }
  const keys = keyOrder ? keyOrder.filter(k => Object.prototype.hasOwnProperty.call(x, k)).concat(Object.keys(x).filter(k => !keyOrder.includes(k))) : Object.keys(x);
  for (const k of keys) {
    const v = x[k];
    if (v === undefined) continue;
    if (asRepeat && REPEAT_INV[k] && Array.isArray(v)) {
      const itemOrder = k === 'steps' ? (x.now !== undefined || (v[0] && 'now' in (v[0] || {})) ? RG_STEP : CK_STEP) : (Object.prototype.hasOwnProperty.call(v[0] || {}, 'env') || Object.prototype.hasOwnProperty.call(v[0] || {}, 'expectFinal') ? RG_FORK : CK_FORK);
      for (const item of v) {
        const nested = emitLines(item, indent + 2, itemOrder, true);
        lines.push(pad + REPEAT_INV[k] + ':');
        if (!nested.length) continue;
        for (const n of nested) lines.push(n);
      }
      continue;
    }
    if (isScalar(v)) { lines.push(pad + emitKey(k) + ': ' + emitScalar(v)); continue; }
    if (Array.isArray(v) && !v.length) { lines.push(pad + emitKey(k) + ': []'); continue; }
    if (v && typeof v === 'object' && !Array.isArray(v) && !Object.keys(v).length) {
      lines.push(pad + emitKey(k) + ': {}');
      continue;
    }
    if (Array.isArray(v) && v.every(isScalar)) {
      lines.push(pad + emitKey(k) + ': [' + v.map(emitScalar).join(', ') + ']');
      continue;
    }
    if (awkward(v)) { lines.push(pad + emitKey(k) + ': ' + JSON.stringify(v)); continue; }
    lines.push(pad + emitKey(k) + ':');
    const nested = emitLines(v, indent + 2, null, false);
    if (!nested.length) { lines[lines.length - 1] += ' {}'; continue; }
    for (const n of nested) lines.push(n);
  }
  return lines;
}

function scenarioToDsl(family, scenario) {
  if (!FAMILIES.has(family)) throw new ScenarioDslError('scenario', 1, 1, 'family must be checkpoint or registry');
  const sc = scenario;
  validateScenario(family, sc, 'scenario', {});
  const order = family === 'checkpoint' ? CK_TOP : RG_TOP;
  const body = emitLines(sc, 0, order, true);
  return ['grammar: ' + GRAMMAR_VERSION, 'family: ' + family, ''].concat(body).join('\n') + '\n';
}

function scenarioFromDsl(sourceText, sourceName) {
  return parseScenarioDsl(sourceText, sourceName).scenario;
}

function dropUndef(obj) {
  if (Array.isArray(obj)) return obj.map(dropUndef);
  if (obj && typeof obj === 'object') {
    const o = {};
    for (const [k, v] of Object.entries(obj)) if (v !== undefined) o[k] = dropUndef(v);
    return o;
  }
  return obj;
}

function branchToScenario(family, branch) {
  if (!FAMILIES.has(family)) throw new ScenarioDslError('branch', 1, 1, 'family must be checkpoint or registry');
  if (!branch || typeof branch !== 'object') throw new ScenarioDslError('branch', 1, 1, 'branch must be a mapping');
  const nodes = Array.isArray(branch.nodes) ? branch.nodes : [];
  if (family === 'checkpoint') {
    const steps = [];
    for (const n of nodes) {
      const st = { slot: isNat(n.slot) ? n.slot : 0, who: n.who || 'you', say: n.say || '' };
      if (n.hidden) st.hidden = true;
      if (n.params) st.params = n.params;
      if (n.evidence) st.evidence = n.evidence;
      if (n.action !== undefined) st.action = n.action;
      if (n.expect) st.expect = n.expect;
      steps.push(st);
    }
    if (!steps.length) throw new ScenarioDslError('branch', 1, 1, 'exported branch has no steps');
    return dropUndef({
      story: isNat(branch.story) ? branch.story : 0,
      title: branch.title || 'exported branch',
      goal: branch.goal || 'Replay of the current free-play branch.',
      params: branch.params,
      atoms: Array.isArray(branch.atoms) ? branch.atoms : [],
      steps,
      forks: [],
    });
  }
  const steps = [];
  const env = branch.env && typeof branch.env === 'object' ? branch.env : {};
  for (const n of nodes) {
    if (n.kind === 'evidence' || n.kind === 'time') continue;
    if (n.action === undefined) continue;
    const st = {
      now: isNat(n.now) ? n.now : (isNat(n.slot) ? n.slot : 0),
      actor: n.actor || 'anyone',
      as: n.as || n.who || 'anyone',
      action: n.action,
    };
    if (n.expect) st.expect = n.expect;
    if (n.exhibits) st.exhibits = n.exhibits;
    if (n.note || n.say) st.note = n.note || n.say;
    steps.push(st);
  }
  if (!steps.length) throw new ScenarioDslError('branch', 1, 1, 'exported branch has no steps');
  return dropUndef({
    id: isNat(branch.id) ? branch.id : 0,
    slug: branch.slug || 'exported-branch',
    story: branch.title || branch.story || 'exported branch',
    narrative: branch.narrative || 'Replay of the current free-play branch.',
    params: branch.params,
    plugin: isNat(branch.plugin) ? branch.plugin : 7,
    actors: branch.actors || {},
    env,
    steps,
    forks: [],
    expectFinal: branch.expectFinal,
  });
}
return { GRAMMAR_VERSION, ScenarioDslError, assertGrammarVersion, parseScenarioDsl, scenarioToDsl, scenarioFromDsl, branchToScenario };
})();
const GRAMMAR_VERSION = ScenarioDslAPI.GRAMMAR_VERSION;
const ScenarioDslError = ScenarioDslAPI.ScenarioDslError;
const assertGrammarVersion = ScenarioDslAPI.assertGrammarVersion;
const parseScenarioDsl = ScenarioDslAPI.parseScenarioDsl;
const scenarioToDsl = ScenarioDslAPI.scenarioToDsl;
const scenarioFromDsl = ScenarioDslAPI.scenarioFromDsl;
const branchToScenario = ScenarioDslAPI.branchToScenario;
/* @@DSL:END@@ */

export {
  GRAMMAR_VERSION,
  ScenarioDslError,
  assertGrammarVersion,
  parseScenarioDsl,
  scenarioToDsl,
  scenarioFromDsl,
  branchToScenario,
};
