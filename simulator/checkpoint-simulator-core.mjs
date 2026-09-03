/*
 * checkpoint-simulator-core.mjs — the pure core of the M1 checkpoint
 * simulator: a JavaScript transcription of `stepFn`, `replay` and
 * `consumableStateB` (the decidable mirror of `consumableState`) from
 * lean/CardanoKeri/Checkpoint.lean, and the
 * theorems T1–T16 of lean/CardanoKeri/CheckpointGoals.lean as executable
 * properties over steps and traces.
 *
 * No DOM, no storage, no clock. Evidence (the Lean `Env`) is a table of
 * decisions supplied by the scenario or by the person playing; the core
 * never decides evidence. Every Nat-typed field is a non-negative integer
 * or the action is refused by name.
 *
 * JSON shapes follow Lean's derived `ToJson` exactly, so the corpus the
 * Lean driver emits is compared byte-for-byte after key sorting:
 *   state   'absent' | {present:{l:{sn,epoch,poisoned,bornAt,refundTo,dreg,b,pool}}}
 *           | {convicted:{epoch,sn,convictedAt}} | {closed:{epoch,sn}}
 *   action  {register:{refund,pool0}} | {rotate:{"sn'",op,payee,"refund'"}} | 'poison'
 *           | {freeze:{"sn'",payee}} | {topUp:{x}} | {convict:{payee}} | {close:{"sn'","refund'"}} | {reopen:{"sn'",refund,pool0}}
 *   flow    {dregIn,bIn,poolIn,refund,hunter,convictor}   payment {addr,dreg,b,pool}
 *   env     {rotationTo:[[e,sn,sn']], intentAuthorized:[[e,intent,addr|null]], quorum:[[e]], duplicityAt:[[e,sn]]}
 *
 * The slices between `@@CORE:<id>@@` markers are inlined verbatim into
 * checkpoint-simulator.html by checkpoint-simulator-build.mjs; the page
 * runs this code, not a copy of it.
 */

/* @@CORE:model@@ */
// ---- canonical JSON ---------------------------------------------------------
function canon(x) {
  if (x === null || typeof x !== 'object') return JSON.stringify(x);
  if (Array.isArray(x)) return '[' + x.map(canon).join(',') + ']';
  return '{' + Object.keys(x).sort().map(k => JSON.stringify(k) + ':' + canon(x[k])).join(',') + '}';
}
// A Lean Nat is unbounded; this simulator represents it exactly only up to
// 2^53 − 1 (Number.MAX_SAFE_INTEGER). Anything else is refused by name at
// every boundary, and an arithmetic result beyond the bound is refused too,
// so no value ever loses an increment silently (LEAN-CLARITY: "Nat is bounded here").
const MAX_NAT = Number.MAX_SAFE_INTEGER;
const isNat = v => typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;
// exact addition of two Nats, or null when the sum is not representable
const natAdd = (a, b) => { const s = a + b; return isNat(s) && BigInt(a) + BigInt(b) === BigInt(s) ? s : null; };
const big = v => BigInt(v);
// parse a decimal string as a Nat; null for anything else (signs, fractions, exponents, loss)
function parseNat(str) {
  const s = String(str).trim();
  if (!/^\d{1,16}$/.test(s)) return null;
  const n = Number(s);
  return isNat(n) && BigInt(s) === BigInt(n) ? n : null;
}
// number literals in a JSON text that JSON.parse would not round-trip exactly
// (integers beyond 2^53 − 1, or any literal whose value re-serializes differently)
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
// parse JSON refusing lossy number literals
function parseJsonExact(text) {
  const bad = lossyJsonNumbers(text);
  if (bad.length) throw new Error('lossy number literal(s) in JSON: ' + bad.slice(0, 3).join(', '));
  return JSON.parse(text);
}

// ---- refusal reasons: the conjuncts of stepFn, in the order it states them
// (the Lean returns `none` without a name; the naming is the simulator's)
const REASONS = [
  'invalid-params', 'invalid-nat', 'invalid-action', 'invalid-state', 'invalid-evidence',
  'convicted-terminal', 'closed-needs-reopen', 'reopen-needs-closed', 'absent-needs-register', 'already-present',
  'no-witnessed-rotation', 'sequence-not-later', 'intent-not-authorized', 'bond-over-full',
  'no-quorum', 'already-poisoned', 'poisoned', 'pool-covers-premium', 'freeze-bond-missing',
  'no-duplicity-proof', 'slot-regression', 'aid-already-registered', 'leaf-not-closed',
];
// the consumer's verdicts; the last three are boundary refusals (a consumer
// reading a non-state or under non-params decides nothing)
const VERDICTS = ['consumable', 'not-present', 'dreg-missing', 'b-missing', 'poisoned', 'juvenile', 'invalid-params', 'invalid-nat', 'invalid-state'];

// ---- the Lean guards behind the refusal names ------------------------------
// Each refusal name stands for the hypothesis binder(s) of the `Step`
// constructors it refuses on (Checkpoint.lean), or for the absence of any
// constructor (stepFn's fall-through, made exact by T7). The scenario gate
// reconciles this table with the Lean source: every `h`-binder of every Step
// constructor must be claimed here (or by SPLITS), and every claim must exist
// with its text inside that constructor. The naming is the simulator's; the
// binders are the Lean's.
const ROTATES = ['Step.rotateKeepPaid', 'Step.rotateKeepUnpaid', 'Step.rotateWithdraw', 'Step.rotateDeposit'];
const LEAN_GUARDS = {
  'no-witnessed-rotation': { decls: [...ROTATES, 'Step.freeze', 'Step.close', 'Step.reopen'], hyp: 'hev', text: 'env.rotationTo' },
  'sequence-not-later': { decls: [...ROTATES, 'Step.freeze', 'Step.close', 'Step.reopen'], hyp: 'hsn', text: "< sn'" },
  'intent-not-authorized': { decls: [...ROTATES, 'Step.close'], hyp: 'hauth', text: 'env.intentOk (l.epoch + 1)' },
  'bond-over-full': { decls: ['Step.rotateDeposit'], hyps: [['hd', 'l.dreg ≤ p.D'], ['hb', 'l.b ≤ p.B']] },
  'no-quorum': { decls: ['Step.poison'], hyp: 'hq', text: 'env.quorum l.epoch = true' },
  'already-poisoned': { decls: ['Step.poison'], hyp: 'hclean', text: 'l.poisoned = false' },
  'poisoned': { decls: ['Step.freeze'], hyp: 'hclean', text: 'l.poisoned = false' },
  'pool-covers-premium': { decls: ['Step.freeze'], hyp: 'hpool', text: 'l.pool < p.P' },
  'freeze-bond-missing': { decls: ['Step.freeze'], hyp: 'hb', text: 'l.b = p.B' },
  'no-duplicity-proof': { decls: ['Step.convict'], hyp: 'hdup', text: 'env.duplicityAt l.epoch l.sn = true' },
  'aid-already-registered': { decls: ['SysStep.register'], hyp: 'habs', text: 's.leaves aid = .absent' },
  'leaf-not-closed': { decls: ['SysStep.reopen'], hyp: 'hclosed', text: 's.leaves aid = .closed e sn' },
  'slot-regression': { decls: ['Trace.cons'], hyp: 'hle', text: "t ≤ t'" },
  // no constructor has the (action, state): stepFn's fall-through, the theorem names it
  'convicted-terminal': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T12_convicted_terminal' },
  'closed-needs-reopen': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_closed_only_reopens' },
  'reopen-needs-closed': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_absent_only_registers' },
  'absent-needs-register': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_absent_only_registers' },
  'already-present': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_mint_once' },
  // the two proof fields of Params
  'invalid-params': { decls: ['Params'], hyps: [['hD', '0 < D'], ['hB', '0 < B']] },
  // the simulator's own boundary (a Lean Nat is unbounded; a Lean value has its type)
  'invalid-nat': { decls: [] }, 'invalid-action': { decls: [] }, 'invalid-state': { decls: [] }, 'invalid-evidence': { decls: [] },
};
// guard hypotheses that are not refusals: the paid / unpaid split of a keep rotation
const LEAN_SPLITS = [
  { decl: 'Step.rotateKeepPaid', hyp: 'hpay', text: 'p.P ≤ l.pool' },
  { decl: 'Step.rotateKeepUnpaid', hyp: 'hnopay', text: 'l.pool < p.P' },
];
// the conjunct of consumableState each verdict names
const VERDICT_CONJUNCTS = {
  'not-present': ['| .present l =>', '| _ => False'], 'dreg-missing': ['l.dreg = p.D'], 'b-missing': ['l.b = p.B'],
  poisoned: ['l.poisoned = false'], juvenile: ['l.bornAt + p.W ≤ now'],
};
// the Step constructor an accepted record went through (the paid/unpaid split is
// visible in the flow), or null for a refused / non-transition record
function constructorOf(rec) {
  if (!rec || !rec.ok) return null;
  const d = (rec.action && typeof rec.action === 'object') ? rec.action[rec.kind] : {};
  switch (rec.kind) {
    case 'register': return 'Step.register';
    case 'rotate': return d.op === 'withdraw' ? 'Step.rotateWithdraw' : d.op === 'deposit' ? 'Step.rotateDeposit' : (rec.flow && rec.flow.hunter ? 'Step.rotateKeepPaid' : 'Step.rotateKeepUnpaid');
    case 'poison': return 'Step.poison';
    case 'freeze': return 'Step.freeze';
    case 'topUp': return 'Step.topUp';
    case 'convict': return 'Step.convict';
    case 'close': return 'Step.close';
    case 'reopen': return 'Step.reopen';
  }
  return null;
}

// ---- Params: D B P W with 0 < D and 0 < B (the two proof fields) -----------
let validatingParams = false;   // the T9 trap lets W be read only here
function validateParams(p) {
  validatingParams = true;
  try {
    if (!p || typeof p !== 'object') return 'params missing';
    for (const k of ['D', 'B', 'P', 'W']) if (!isNat(p[k])) return `${k} is not a non-negative integer (at most 2^53 − 1)`;
    if (p.D === 0) return 'D must be positive';
    if (p.B === 0) return 'B must be positive';
    return null;
  } finally { validatingParams = false; }
}

// ---- Actions ---------------------------------------------------------------
const ACTION_KINDS = ['register', 'rotate', 'poison', 'freeze', 'topUp', 'convict', 'close', 'reopen'];
const BOND_OPS = ['keep', 'withdraw', 'deposit'];
// what the new keys sign along with the refund address (D-038): a bond option, or the close
const INTENTS = ['keep', 'withdraw', 'deposit', 'close'];

function actionKind(a) {
  if (a === 'poison') return a;
  if (a && typeof a === 'object' && !Array.isArray(a)) {
    const ks = Object.keys(a);
    if (ks.length === 1 && ACTION_KINDS.includes(ks[0]) && ks[0] !== 'poison') return ks[0];
  }
  return null;
}

// validates the Lean shape and every Nat field; returns the action or a refusal
function normalizeAction(a) {
  const kind = actionKind(a);
  if (!kind) return { ok: false, reason: 'invalid-action', field: 'action' };
  const nat = (v, f) => (isNat(v) ? null : { ok: false, reason: 'invalid-nat', field: f });
  const bad = (...fs) => fs.map(([v, f]) => nat(v, f)).find(Boolean);
  const d = a[kind];
  if (kind !== 'poison' && (!d || typeof d !== 'object' || Array.isArray(d))) return { ok: false, reason: 'invalid-action', field: kind };
  const optAddr = (v, f) => { const r = v === undefined ? null : v; return r !== null && !isNat(r) ? { ok: false, reason: 'invalid-nat', field: f } : { r }; };
  switch (kind) {
    case 'poison': return { ok: true, kind, action: kind };
    case 'register': {
      const e = bad([d.refund, 'refund'], [d.pool0, 'pool0']); if (e) return e;
      return { ok: true, kind, action: { register: { refund: d.refund, pool0: d.pool0 } } };
    }
    case 'rotate': {
      const e = bad([d["sn'"], "sn'"], [d.payee, 'payee']); if (e) return e;
      if (!BOND_OPS.includes(d.op)) return { ok: false, reason: 'invalid-action', field: 'op' };
      const o = optAddr(d["refund'"], "refund'"); if (o.ok === false) return o;
      return { ok: true, kind, action: { rotate: { "sn'": d["sn'"], op: d.op, payee: d.payee, "refund'": o.r } } };
    }
    case 'freeze': {
      const e = bad([d["sn'"], "sn'"], [d.payee, 'payee']); if (e) return e;
      return { ok: true, kind, action: { freeze: { "sn'": d["sn'"], payee: d.payee } } };
    }
    case 'topUp': {
      const e = bad([d.x, 'x']); if (e) return e;
      return { ok: true, kind, action: { topUp: { x: d.x } } };
    }
    case 'convict': {
      const e = bad([d.payee, 'payee']); if (e) return e;
      return { ok: true, kind, action: { convict: { payee: d.payee } } };
    }
    case 'close': {
      const e = bad([d["sn'"], "sn'"]); if (e) return e;
      const o = optAddr(d["refund'"], "refund'"); if (o.ok === false) return o;
      return { ok: true, kind, action: { close: { "sn'": d["sn'"], "refund'": o.r } } };
    }
    case 'reopen': {
      const e = bad([d["sn'"], "sn'"], [d.refund, 'refund'], [d.pool0, 'pool0']); if (e) return e;
      return { ok: true, kind, action: { reopen: { "sn'": d["sn'"], refund: d.refund, pool0: d.pool0 } } };
    }
  }
  return { ok: false, reason: 'invalid-action', field: 'action' };
}

// Action.touchesLeaf: the partition of D-037
const TOUCHES_LEAF = new Set(['register', 'reopen', 'close', 'convict']);
// Action.actor
function actorOf(a) {
  switch (actionKind(a)) {
    case 'register': case 'topUp': return 'anyone';
    case 'rotate': case 'close': return 'nextKeys';
    case 'poison': return 'currentQuorum';
    case 'freeze': case 'convict': case 'reopen': return 'proof';
  }
  return null;
}

// ---- Env: decision tables ----------------------------------------------------
// rotationTo [e, sn, sn'] · intentAuthorized [e, intent, addr | null] · quorum [e] · duplicityAt [e, sn]
const EV_KINDS = ['rotationTo', 'intentAuthorized', 'quorum', 'duplicityAt'];
const EV_ARITY = { rotationTo: 3, intentAuthorized: 3, quorum: 1, duplicityAt: 2 };
// the type of each entry of a row: 'nat', 'intent', 'addr?' (a Nat or null)
const EV_SHAPE = { rotationTo: ['nat', 'nat', 'nat'], intentAuthorized: ['nat', 'intent', 'addr?'], quorum: ['nat'], duplicityAt: ['nat', 'nat'] };
const entryOk = (ty, v) => (ty === 'nat' ? isNat(v) : ty === 'intent' ? INTENTS.includes(v) : (v === null || isNat(v)));
const emptyEnv = () => ({ rotationTo: [], intentAuthorized: [], quorum: [], duplicityAt: [] });
// validateEnv(env) → null | {reason, field, message}: the complete table — exactly
// the four Lean predicates (a missing one is empty), every row of the right
// arity, every entry of its type — checked before any predicate is consulted
function validateEnv(env) {
  const bad = (reason, field, message) => ({ reason, field, message });
  if (!env || typeof env !== 'object' || Array.isArray(env)) return bad('invalid-evidence', 'env', 'the evidence is not a table');
  for (const k of Object.keys(env)) if (!EV_KINDS.includes(k)) return bad('invalid-evidence', k, `${k} is not one of the four evidence predicates`);
  for (const k of EV_KINDS) {
    const rows = env[k];
    if (rows === undefined) continue;
    if (!Array.isArray(rows)) return bad('invalid-evidence', k, `${k} is not a list of rows`);
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      if (!Array.isArray(r) || r.length !== EV_ARITY[k]) return bad('invalid-evidence', `${k}[${i}]`, `${k}[${i}] is not a row of ${EV_ARITY[k]}`);
      for (let j = 0; j < r.length; j++) {
        const ty = EV_SHAPE[k][j];
        if (!entryOk(ty, r[j])) return bad(ty === 'intent' ? 'invalid-evidence' : 'invalid-nat', `${k}[${i}][${j}]`, `${k}[${i}][${j}] is not ${ty === 'nat' ? 'a non-negative integer' : ty === 'intent' ? 'an intent (keep, withdraw, deposit, close)' : 'an address or null'}`);
      }
    }
  }
  return null;
}
const envHas = (env, kind, args) => (env[kind] || []).some(r => canon(r) === canon(args));
const envRotationTo = (env, e, sn, sn2) => envHas(env, 'rotationTo', [e, sn, sn2]);
const envIntentAuthorized = (env, e, intent, r) => envHas(env, 'intentAuthorized', [e, intent, r === undefined ? null : r]);
const envQuorum = (env, e) => envHas(env, 'quorum', [e]);
const envDuplicityAt = (env, e, sn) => envHas(env, 'duplicityAt', [e, sn]);
// Env.intentOk: keep with no new address is the empty message and needs nothing;
// every other intent, and every new address, needs the signed message (D-038)
const intentOk = (env, e, intent, r) => ((intent === 'keep' && (r === null || r === undefined)) ? true : envIntentAuthorized(env, e, intent, r));
// a row is {kind:[args]}; returns the env with the row added / removed
function envAdd(env, row) {
  const [kind] = Object.keys(row); const args = row[kind];
  if (!EV_KINDS.includes(kind) || !Array.isArray(args) || args.length !== EV_ARITY[kind] || !args.every((v, j) => entryOk(EV_SHAPE[kind][j], v))) throw new Error('bad evidence row ' + JSON.stringify(row));
  if (envHas(env, kind, args)) return env;
  return { ...env, [kind]: [...env[kind], args] };
}
function envRemove(env, row) {
  const [kind] = Object.keys(row); const args = row[kind];
  return { ...env, [kind]: (env[kind] || []).filter(r => canon(r) !== canon(args)) };
}
function envUnion(a, b) {
  let out = a;
  for (const k of EV_KINDS) for (const r of b[k] || []) out = envAdd(out, { [k]: r });
  return out;
}

// ---- States, flows ---------------------------------------------------------
const stateKind = s => (s === 'absent') ? s : (s && s.present ? 'present' : (s && s.convicted ? 'convicted' : (s && s.closed ? 'closed' : null)));
const liveOf = s => (s && s.present ? s.present.l : null);
const present = l => ({ present: { l } });
const payment = (addr, dreg, b, pool) => ({ addr, dreg, b, pool });
const flow = f => Object.assign({ dregIn: 0, bIn: 0, poolIn: 0, refund: null, hunter: null, convictor: null }, f);
// State.dregHeld / bHeld / poolHeld
const held = s => { const l = liveOf(s); return l ? { dreg: l.dreg, b: l.b, pool: l.pool } : { dreg: 0, b: 0, pool: 0 }; };
// Payment?.dreg etc.
const paid = q => (q ? { dreg: q.dreg, b: q.b, pool: q.pool } : { dreg: 0, b: 0, pool: 0 });
// State.sn?: the sequence a state records, or null
const snOf = s => { const k = stateKind(s); const l = liveOf(s); return k === 'present' ? (l && typeof l === 'object' ? l.sn : null) : k === 'closed' ? (s.closed && s.closed.sn) : k === 'convicted' ? (s.convicted && s.convicted.sn) : null; };
// State.leaf: the registry leaf a state projects to (D-037)
const leafOf = s => { const k = stateKind(s); return k === 'present' ? 'live' : k === 'closed' ? { closed: { epoch: s.closed.epoch, sn: s.closed.sn } } : k === 'convicted' ? 'convicted' : 'absent'; };
const leafKind = lf => (lf === 'absent' || lf === 'live' || lf === 'convicted') ? lf : (lf && lf.closed ? 'closed' : null);

const LIVE_NATS = ['sn', 'epoch', 'bornAt', 'refundTo', 'dreg', 'b', 'pool'];
const LIVE_FIELDS = [...LIVE_NATS, 'poisoned'];
const STATE_CTORS = ['present', 'convicted', 'closed'];
// validateState(s) → null | {reason, field, message}: the complete state — one
// of the four Lean shapes, exactly one constructor with nothing beside it,
// every Nat field a Nat, the poison bit a boolean, no field the Lean does not
// have — checked before anything reads it
function validateState(s) {
  const bad = (reason, field, message) => ({ reason, field, message });
  if (s === 'absent') return null;
  if (!s || typeof s !== 'object' || Array.isArray(s)) return bad('invalid-state', 'state', 'unknown state shape');
  const keys = Object.keys(s);
  const stranger = keys.find(x => !STATE_CTORS.includes(x));
  if (stranger !== undefined) return bad('invalid-state', stranger, `${stranger} is not a constructor of State`);
  if (keys.length !== 1) return bad('invalid-state', keys.length ? keys[1] : 'state', keys.length ? `${keys[0]} and ${keys[1]} at once: a state is one constructor` : 'unknown state shape');
  const k = keys[0];
  const record = (obj, key, name, fields) => {
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return bad('invalid-state', key, `${name} without its fields`);
    for (const f of fields) if (!isNat(obj[f])) return bad('invalid-nat', f, `${f} is not a non-negative integer`);
    for (const f of Object.keys(obj)) if (!fields.includes(f)) return bad('invalid-state', f, `${f} is not a field of ${name}`);
    return null;
  };
  if (k === 'present') {
    const w = s.present;
    if (!w || typeof w !== 'object' || Array.isArray(w)) return bad('invalid-state', 'present', 'present without a datum');
    for (const f of Object.keys(w)) if (f !== 'l') return bad('invalid-state', 'present.' + f, `present.${f} is not a field of present (only l)`);
    const l = w.l;
    if (!l || typeof l !== 'object' || Array.isArray(l)) return bad('invalid-state', 'l', 'present without a datum');
    for (const f of LIVE_NATS) if (!isNat(l[f])) return bad('invalid-nat', f, `${f} is not a non-negative integer`);
    if (typeof l.poisoned !== 'boolean') return bad('invalid-state', 'poisoned', 'poisoned is not a boolean');
    for (const f of Object.keys(l)) if (!LIVE_FIELDS.includes(f)) return bad('invalid-state', f, `${f} is not a field of the datum`);
    return null;
  }
  if (k === 'convicted') return record(s.convicted, 'convicted', 'the tombstone', ['epoch', 'sn', 'convictedAt']);
  return record(s.closed, 'closed', 'closed', ['epoch', 'sn']);
}

// validateFlow(f) → null | {reason, field, message}: the complete Lean Flow —
// three Nat inflows and three optional payments of four Nats, nothing else
const FLOW_NATS = ['dregIn', 'bIn', 'poolIn'], FLOW_PAYS = ['refund', 'hunter', 'convictor'], PAY_FIELDS = ['addr', 'dreg', 'b', 'pool'];
function validateFlow(f) {
  const bad = (reason, field, message) => ({ reason, field, message });
  if (!f || typeof f !== 'object' || Array.isArray(f)) return bad('invalid-flow', 'flow', 'not a flow');
  for (const k of Object.keys(f)) if (!FLOW_NATS.includes(k) && !FLOW_PAYS.includes(k)) return bad('invalid-flow', k, `${k} is not a field of Flow`);
  for (const k of FLOW_NATS) if (!isNat(f[k])) return bad('invalid-nat', k, `${k} is not a non-negative integer`);
  for (const k of FLOW_PAYS) {
    const q = f[k];
    if (q === null || q === undefined) continue;
    if (typeof q !== 'object' || Array.isArray(q)) return bad('invalid-flow', k, `${k} is not a payment or null`);
    for (const pf of Object.keys(q)) if (!PAY_FIELDS.includes(pf)) return bad('invalid-flow', k + '.' + pf, `${k}.${pf} is not a field of Payment`);
    for (const pf of PAY_FIELDS) if (!isNat(q[pf])) return bad('invalid-nat', k + '.' + pf, `${k}.${pf} is not a non-negative integer`);
  }
  return null;
}

// ---- stepFn ----------------------------------------------------------------
// step(params, env, action, now, state) → {ok:true, kind, flow, state} | {ok:false, reason, field?}
// The boundary, in this order and before anything is evaluated: params, slot,
// action, the complete state, the complete evidence table. Each refuses by
// name (`invalid-params` / `invalid-nat` / `invalid-action` / `invalid-state`
// / `invalid-evidence`) with the offending field.
function step(p, env, action, now, state) {
  const refuse = (reason, field) => (field ? { ok: false, reason, field } : { ok: false, reason });
  const pv = validateParams(p); if (pv) return refuse('invalid-params', pv);
  if (!isNat(now)) return refuse('invalid-nat', 'now');
  const na = normalizeAction(action); if (!na.ok) return refuse(na.reason, na.field);
  const sv = validateState(state); if (sv) return refuse(sv.reason, sv.field);
  const ev = validateEnv(env); if (ev) return refuse(ev.reason, ev.field);
  const a = na.action, kind = na.kind;
  const some = (f, s) => ({ ok: true, kind, flow: flow(f), state: s });
  const sk = stateKind(state);
  if (sk === 'convicted') return refuse('convicted-terminal');
  if (sk === 'closed') {
    if (kind !== 'reopen') return refuse('closed-needs-reopen');
    const { epoch: e, sn } = state.closed;
    const { "sn'": sn2, refund, pool0 } = a.reopen;
    if (!envRotationTo(env, e, sn, sn2)) return refuse('no-witnessed-rotation');
    if (!(sn < sn2)) return refuse('sequence-not-later');
    const epoch2 = natAdd(e, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
    return some({ dregIn: p.D, bIn: p.B, poolIn: pool0 },
      present({ sn: sn2, epoch: epoch2, poisoned: false, bornAt: now, refundTo: refund, dreg: p.D, b: p.B, pool: pool0 }));
  }
  if (sk === 'absent') {
    if (kind !== 'register') return refuse('absent-needs-register');
    const { refund, pool0 } = a.register;
    return some({ dregIn: p.D, bIn: p.B, poolIn: pool0 },
      present({ sn: 0, epoch: 0, poisoned: false, bornAt: now, refundTo: refund, dreg: p.D, b: p.B, pool: pool0 }));
  }
  const l = state.present.l;
  switch (kind) {
    case 'register': return refuse('already-present');
    case 'reopen': return refuse('reopen-needs-closed');
    case 'rotate': {
      const { "sn'": sn2, op, payee, "refund'": r } = a.rotate;
      if (!envRotationTo(env, l.epoch, l.sn, sn2)) return refuse('no-witnessed-rotation');
      if (!(l.sn < sn2)) return refuse('sequence-not-later');
      const epoch2 = natAdd(l.epoch, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
      if (!intentOk(env, epoch2, op, r)) return refuse('intent-not-authorized');
      const r2 = r === null ? l.refundTo : r;
      const next = { ...l, sn: sn2, epoch: epoch2, poisoned: false, refundTo: r2 };
      if (op === 'keep') {
        if (p.P <= l.pool) return some({ hunter: payment(payee, 0, 0, p.P) }, present({ ...next, pool: l.pool - p.P }));
        return some({}, present(next));
      }
      if (op === 'withdraw')
        return some({ refund: payment(r2, l.dreg, l.b, l.pool) }, present({ ...next, dreg: 0, b: 0, pool: 0 }));
      // deposit
      if (!(l.dreg <= p.D && l.b <= p.B)) return refuse('bond-over-full');
      return some({ dregIn: p.D - l.dreg, bIn: p.B - l.b }, present({ ...next, bornAt: now, dreg: p.D, b: p.B }));
    }
    case 'poison':
      if (!envQuorum(env, l.epoch)) return refuse('no-quorum');
      if (l.poisoned) return refuse('already-poisoned');
      return some({}, present({ ...l, poisoned: true }));
    case 'freeze': {
      const { "sn'": sn2, payee } = a.freeze;
      if (!envRotationTo(env, l.epoch, l.sn, sn2)) return refuse('no-witnessed-rotation');
      if (!(l.sn < sn2)) return refuse('sequence-not-later');
      if (!(l.pool < p.P)) return refuse('pool-covers-premium');
      if (l.b !== p.B) return refuse('freeze-bond-missing');
      if (l.poisoned) return refuse('poisoned');
      return some({ hunter: payment(payee, 0, p.B, 0) }, present({ ...l, b: 0 }));
    }
    case 'topUp': {
      const pool2 = natAdd(l.pool, a.topUp.x); if (pool2 === null) return refuse('invalid-nat', 'pool');
      return some({ poolIn: a.topUp.x }, present({ ...l, pool: pool2 }));
    }
    case 'convict': {
      if (!envDuplicityAt(env, l.epoch, l.sn)) return refuse('no-duplicity-proof');
      return some({ refund: payment(l.refundTo, 0, l.b, l.pool), convictor: payment(a.convict.payee, l.dreg, 0, 0) },
        { convicted: { epoch: l.epoch, sn: l.sn, convictedAt: now } });
    }
    case 'close': {
      const { "sn'": sn2, "refund'": r } = a.close;
      if (!envRotationTo(env, l.epoch, l.sn, sn2)) return refuse('no-witnessed-rotation');
      if (!(l.sn < sn2)) return refuse('sequence-not-later');
      const epoch2 = natAdd(l.epoch, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
      if (!intentOk(env, epoch2, 'close', r)) return refuse('intent-not-authorized');
      const r2 = r === null ? l.refundTo : r;
      return some({ refund: payment(r2, l.dreg, l.b, l.pool) }, { closed: { epoch: epoch2, sn: sn2 } });
    }
  }
  return refuse('invalid-action', 'action');
}

// ---- consumableState -------------------------------------------------------
// the state-side conjuncts, in the Lean's order; the first failing one names the verdict
function consumable(p, now, state) {
  // the boundary first: a consumer reading a non-state, or under non-params, decides nothing
  const refused = (verdict, field) => ({ ok: false, verdict, field, failing: [verdict], conjuncts: {} });
  const pv = validateParams(p); if (pv) return refused('invalid-params', pv);
  if (!isNat(now)) return refused('invalid-nat', 'now');
  const sv = validateState(state); if (sv) return refused(sv.reason, sv.field);
  const l = liveOf(state);
  const conjuncts = {
    present: !!l,
    dreg: !!l && l.dreg === p.D,
    b: !!l && l.b === p.B,
    unpoisoned: !!l && l.poisoned === false,
    mature: !!l && big(l.bornAt) + big(p.W) <= big(now),
  };
  const failing = [];
  if (!conjuncts.present) failing.push('not-present');
  else {
    if (!conjuncts.dreg) failing.push('dreg-missing');
    if (!conjuncts.b) failing.push('b-missing');
    if (!conjuncts.unpoisoned) failing.push('poisoned');
    if (!conjuncts.mature) failing.push('juvenile');
  }
  return { ok: !failing.length, verdict: failing.length ? failing[0] : 'consumable', failing, conjuncts };
}
// ∀ t', ¬ consumableState p t' s  ⇔  the three structural conjuncts cannot all hold
const consumableEver = (p, s) => { const l = liveOf(s); return !!l && l.dreg === p.D && l.b === p.B && !l.poisoned; };

// ---- replay ----------------------------------------------------------------
// replay(params, env, t0, state, [[slot, action], …]) mirrors the Lean: refuses a
// decreasing slot or a refused step; returns the final state on success
function replay(p, env, t0, state, list) {
  // the boundary first, even for an empty list: params, origin slot, the complete
  // origin state, the complete evidence table (at: null = before any step)
  const refuse = (at, reason, field) => (field ? { ok: false, at, reason, field } : { ok: false, at, reason });
  const pv = validateParams(p); if (pv) return refuse(null, 'invalid-params', pv);
  if (!isNat(t0)) return refuse(null, 'invalid-nat', 't0');
  const sv = validateState(state); if (sv) return refuse(null, sv.reason, sv.field);
  const ev = validateEnv(env); if (ev) return refuse(null, ev.reason, ev.field);
  if (!Array.isArray(list)) return refuse(null, 'invalid-action', 'list');
  let t = t0, s = state;
  for (let i = 0; i < list.length; i++) {
    const e = list[i];
    if (!Array.isArray(e) || e.length !== 2) return refuse(i, 'invalid-action', `list[${i}]`);
    const [t2, a] = e;
    if (!isNat(t2)) return refuse(i, 'invalid-nat', 'slot');
    if (!(t <= t2)) return refuse(i, 'slot-regression');
    const r = step(p, env, a, t2, s);
    if (!r.ok) return refuse(i, r.reason, r.field);
    t = t2; s = r.state;
  }
  return { ok: true, state: s };
}

// poisonAfter / poisonSinceLastRotation: register, rotate and reopen open an
// epoch (clear), poison marks it, everything else keeps it
function poisonAfter(b, list) {
  for (const [, a] of list) {
    const k = actionKind(a);
    if (k === 'poison') b = true;
    else if (k === 'rotate' || k === 'register' || k === 'reopen') b = false;
  }
  return b;
}
const poisonSinceLastRotation = list => poisonAfter(false, list);
/* @@CORE:model:END@@ */

/* @@CORE:session@@ */
// ---- a session: params, evidence, slot, state, the registry leaves, history ----
// Sessions are immutable values; every operation returns a new one, so a page
// can keep them for time travel.
// The session is the Lean `Sys` for one deployment: the registry as a map from
// AID to a leaf (`leaves`: absent when missing) and each AID's state
// (`others`), plus the AID the page plays (`aid`, whose state is `state`).
// `corpus` is the embedded Lean corpus the T7 checker consults; without it T7
// is never exhibited.
function newSession(params, opts) {
  const aid = (opts && opts.aid) || 1;
  return { params, env: emptyEnv(), envAll: emptyEnv(), now: 0, state: 'absent', aid, others: {},
    leaves: {}, history: [], origin: 'absent', originSlot: 0, records: [], corpus: (opts && opts.corpus) || null };
}
const stateOfAid = (s, aid) => (aid === s.aid ? s.state : (s.others[aid] !== undefined ? s.others[aid] : 'absent'));
const leafOfAid = (s, aid) => (s.leaves[aid] !== undefined ? s.leaves[aid] : 'absent');
const allAids = s => [...new Set([s.aid, ...Object.keys(s.others).map(Number), ...Object.keys(s.leaves).map(Number)])];
// seed another AID's state (a system-level fixture); its leaf follows the state
function seedOther(s, aid, state) {
  const bad = validateState(state); if (bad) throw new Error('seedOther: ' + bad.reason + ' ' + bad.message);
  if (aid === s.aid) return seed(s, state);
  return { ...s, others: { ...s.others, [aid]: state }, leaves: { ...s.leaves, [aid]: leafOf(state) } };
}
const withParams = (s, params) => ({ ...s, params });
const addEvidence = (s, row) => ({ ...s, env: envAdd(s.env, row), envAll: envAdd(s.envAll, row) });
const removeEvidence = (s, row) => ({ ...s, env: envRemove(s.env, row) });
// a seeded state starts a new origin for the fold theorems; the leaf follows it
function seed(s, state) {
  const bad = validateState(state); if (bad) throw new Error('seed: ' + bad.reason + ' ' + bad.message);
  return { ...s, state, origin: state, originSlot: s.now, history: [], leaves: { ...s.leaves, [s.aid]: leafOf(state) } };
}
function setSlot(s, slot) {
  if (!isNat(slot)) return { ok: false, reason: 'invalid-nat' };
  if (slot < s.now) return { ok: false, reason: 'slot-regression' };
  return { ok: true, session: { ...s, now: slot } };
}
// attempt(session, action, slot, aid?) → {session, record}: one SysStep for
// `aid` (default: the played AID). Registration needs the AID's leaf absent
// (SysStep.register's habs), a reopen needs it closed (SysStep.reopen's
// hclosed); for a consistent system the state guard refuses first, so those
// two reasons only fire on leaves that disagree with the state. The leaf
// follows the state after every accepted step (Sys.set).
function attempt(s, action, slot, aid) {
  if (aid === undefined) aid = s.aid;
  const kind = actionKind(action);
  const pre = stateOfAid(s, aid);
  const record = { slot, action, kind, actor: actorOf(action), pre, now: s.now, aid };
  let res;
  if (!isNat(slot)) res = { ok: false, reason: 'invalid-nat', field: 'slot' };
  else if (slot < s.now) res = { ok: false, reason: 'slot-regression' };
  else {
    res = step(s.params, s.env, action, slot, pre);
    if (res.ok && kind === 'register' && leafOfAid(s, aid) !== 'absent') res = { ok: false, reason: 'aid-already-registered' };
    if (res.ok && kind === 'reopen' && leafKind(leafOfAid(s, aid)) !== 'closed') res = { ok: false, reason: 'leaf-not-closed' };
  }
  record.ok = res.ok;
  if (res.ok) { record.flow = res.flow; record.state = res.state; }
  else { record.reason = res.reason; if (res.field) record.field = res.field; record.state = pre; }
  record.stepped = res.reason !== 'slot-regression' && res.reason !== 'aid-already-registered' && res.reason !== 'leaf-not-closed' && !(res.reason === 'invalid-nat' && res.field === 'slot');
  const now = record.stepped ? Math.max(s.now, slot) : s.now;
  const mine = aid === s.aid;
  const history = res.ok && mine ? [...s.history, [slot, action]] : s.history;
  const leaves = res.ok ? { ...s.leaves, [aid]: leafOf(record.state) } : s.leaves;
  const next = { ...s, now, history, leaves,
    state: mine ? record.state : s.state,
    others: mine ? s.others : { ...s.others, [aid]: record.state } };
  record.theorems = theoremReport(s, next, record);
  next.records = [...s.records, record];
  return { session: next, record };
}
// per theorem: how many records exhibited it and how many of those held
function heldSoFar(s) {
  const out = {};
  for (const t of THEOREMS) out[t.id] = { exhibited: 0, held: 0, broken: 0 };
  for (const r of s.records) for (const id of Object.keys(r.theorems)) {
    const x = r.theorems[id];
    if (x.exhibited) { out[id].exhibited++; if (x.holds) out[id].held++; }
    if (!x.holds) out[id].broken++;
  }
  return out;
}
/* @@CORE:session:END@@ */

/* @@CORE:words@@ */
// ---- the story vocabulary --------------------------------------------------
const CAST = {
  alice: { name: 'Alice', role: 'the owner', addr: 1, aid: 1, blurb: 'She has a KERI identity with three witnesses. She rotates her keys with kli and never touches Cardano except to put money in.' },
  hal: { name: 'Hal', role: 'a hunter', addr: 2, blurb: 'He watches Alice’s witnesses and lands her rotations on Cardano for a fee. When she does not pay, he freezes her instead.' },
  treasury: { name: 'The treasury', role: 'a consumer', addr: 5, blurb: 'A Cardano validator that authorizes payments against Alice’s current keys by reading her checkpoint as a reference input.' },
  cora: { name: 'Cora', role: 'a convictor', addr: 3, blurb: 'She holds two of Alice’s rotations at the same sequence, both receipted by Alice’s witnesses.' },
  mallory: { name: 'Mallory', role: 'a thief', addr: 4, blurb: 'Sometimes she has Alice’s current keys; sometimes the next ones too.' },
  anyone: { name: 'A sponsor', role: 'pays for her presence', addr: 6, blurb: 'Someone who wants Alice served on Cardano — a service, a friend, a DAO. Registers her public inception, reopens it after a close, tops up her pool; the machine asks no signature of him. If he names his own refund address, his bonds go back to Alice at her first rotation: a stale registration is a donation.' },
};
const whoAddr = addr => Object.values(CAST).find(c => c.addr === addr) || { name: 'address ' + addr };
const STATE_WORDS = {
  absent: 'Absent', live: 'Live', poisoned: 'Poisoned', paused: 'Paused', frozen: 'Frozen', convicted: 'Convicted', closed: 'Closed',
};
// the story's state table, read off the datum; closed is the tombstone (not terminal)
function stateWord(p, s) {
  const k = stateKind(s);
  if (k !== 'present') return k;
  const l = liveOf(s);
  if (l.dreg !== p.D) return 'paused';
  if (l.b !== p.B) return 'frozen';
  if (l.poisoned) return 'poisoned';
  return 'live';
}
const INTENT_WORDS = { keep: 'keep the bonds', withdraw: 'withdraw (pause)', deposit: 'deposit (come back)', close: 'close' };
const VERDICT_WORDS = {
  consumable: 'Consumable: both bonds full, not poisoned, past the juvenility window.',
  'not-present': 'Not consumable: there is no live checkpoint to read (absent, closed or convicted).',
  'dreg-missing': 'Not consumable: the conviction bond is missing (paused).',
  'b-missing': 'Not consumable: the freeze bond is missing (frozen).',
  poisoned: 'Not consumable: the current keys are declared poisoned.',
  juvenile: 'Not consumable yet: juvenile, born too recently.',
  'invalid-params': 'Nothing to read: the deployment parameters are not a valid Params (both bonds positive, whole numbers).',
  'invalid-nat': 'Nothing to read: a field that must be a non-negative whole number at most 2^53 − 1 is not.',
  'invalid-state': 'Nothing to read: this is not a checkpoint state.',
};
// every refusal in the story's words, with the numbers that decided it
function explain(rec, s) {
  const p = s.params, a = rec.action;
  const l = liveOf(rec.pre) || { epoch: '?', sn: '?', pool: '?', b: '?', dreg: '?' };
  const k = actionKind(a);
  const d = (a && typeof a === 'object') ? a[k] : {};
  const c = rec.pre && rec.pre.closed ? rec.pre.closed : null;
  switch (rec.reason) {
    case 'invalid-params': return 'The deployment parameters are refused: both bonds must be positive, or "bond missing" could not be told from "bond full".';
    case 'invalid-nat': return (rec.field === 'pool' || rec.field === 'epoch')
      ? `The resulting ${rec.field} would exceed 2^53 − 1, the largest whole number this simulator represents exactly; the Lean's Nat is unbounded, so the step is refused rather than rounded.`
      : `"${rec.field}" must be a non-negative whole number at most 2^53 − 1: lovelace, slots and sequence numbers do not go negative, fractional or beyond what is represented exactly.`;
    case 'aid-already-registered': return 'This AID has a registry leaf already: a registration needs the absence proof, and the leaf never goes back to absent.';
    case 'leaf-not-closed': return 'This AID’s registry leaf is not a closed tombstone: a reopen needs the presence proof of a closed leaf.';
    case 'invalid-action': return 'The validator does not know this redeemer; only register, rotate, poison, freeze, top-up, convict, close and reopen exist.';
    case 'invalid-state': return `"${rec.field}" is not part of a checkpoint state: a state is Absent, Present with its eight datum fields, Convicted with its tombstone, or Closed with its epoch and sequence. Nothing is evaluated on a non-state.`;
    case 'invalid-evidence': return `"${rec.field}" is not part of an evidence table: the four predicates (witnessed rotation, signed intent, quorum, duplicity) as rows of 3, 3, 1 and 2 entries. Nothing is evaluated under a non-table.`;
    case 'convicted-terminal': return 'Convicted is terminal: no rotation, no poison, no close, no reopen, ever. No KERI event un-duplicates an identifier.';
    case 'closed-needs-reopen': return `Closed at epoch ${c ? c.epoch : '?'}, sequence ${c ? c.sn : '?'}: the UTxO is burned. Only a reopen — a witnessed rotation later than sequence ${c ? c.sn : '?'}, bringing both bonds — brings this AID back.`;
    case 'reopen-needs-closed': return 'A reopen needs a closed tombstone; this checkpoint is live on chain.';
    case 'absent-needs-register': return 'Nothing is on chain for this AID. The only thing that can happen first is a registration.';
    case 'already-present': return 'This AID already has its checkpoint. The token is minted once, ever.';
    case 'no-witnessed-rotation': return c
      ? `No witnessed rotation path from the closed tombstone (epoch ${c.epoch}, sequence ${c.sn}) to sequence ${d["sn'"]} was presented.`
      : `No witnessed rotation from epoch ${l.epoch} at sequence ${l.sn} to sequence ${d["sn'"]} was presented: signatures at the current threshold, revealed keys matching the pre-committed digests, receipts from the witnesses.`;
    case 'sequence-not-later': return c
      ? `The presented rotation is at sequence ${d["sn'"]}, not later than the tombstone’s ${c.sn}: a reopen cannot resurrect a stale sequence.`
      : `The presented rotation is at sequence ${d["sn'"]}, not later than the checkpoint’s ${l.sn}: the checkpoint cannot roll back.`;
    case 'intent-not-authorized': return `The keys of epoch ${l.epoch + 1} — the ones this rotation reveals — did not sign the intent «${INTENT_WORDS[k === 'close' ? 'close' : d.op] || d.op}${d["refund'"] !== null && d["refund'"] !== undefined ? ', refund → ' + d["refund'"] : ''}». Public data lands a rotation that keeps the bonds; parking, re-bonding, closing and moving the refund address are the owner’s, signed at the rotation (D-038).`;
    case 'bond-over-full': return `The datum claims more than a full bond (conviction ${l.dreg} of ${p.D}, freeze ${l.b} of ${p.B}); a depositing rotation refuses it. No chain state reaches this.`;
    case 'no-quorum': return `The current keys of epoch ${l.epoch} did not sign at their threshold. Keys of a retired epoch count for nothing.`;
    case 'already-poisoned': return 'This epoch is already poisoned; the poison is declared once per epoch and only a rotation clears it.';
    case 'poisoned': return 'A poisoned checkpoint cannot be frozen: it is already unconsumable, there is nothing to freeze.';
    case 'pool-covers-premium': return `The pool (${l.pool}) covers the premium (${p.P}): there is nothing to freeze. Land the rotation and be paid instead.`;
    case 'freeze-bond-missing': return `The freeze bond is not there to take (held ${l.b}, full is ${p.B}); the checkpoint is already frozen or paused.`;
    case 'no-duplicity-proof': return `No second rotation at sequence ${l.sn} revealing the keys of epoch ${l.epoch}, signed at the current threshold and receipted by the tip’s witnesses, was presented.`;
    case 'slot-regression': return `Slot ${rec.slot} is before the last accepted slot ${rec.now}: the chain does not go backwards.`;
  }
  return 'Refused: ' + rec.reason;
}
/* @@CORE:words:END@@ */

/* @@CORE:theorems@@ */
// ---- the theorems as executable properties ---------------------------------
// theoremReport(before, after, record) → {T1: {exhibited, holds, notes}, …}
// `exhibited`: the theorem's antecedent held on this step, so the play shows
// it. `holds`: its consequent held (vacuously true when not exhibited).
const THEOREMS = [
  { id: 'T1', title: 'The checkpoint cannot roll back',
    lean: ['T1_sn_monotone', 'T1_rotate_strict', 'T1_sn_monotone_all', 'T1_reopen_strict', 'T1_trace_sn_monotone'],
    plain: 'No step decreases the sequence a state records — between live states, into the closed tombstone, and out of it: a reopen is strictly later than the tombstone (no stale resurrection); every rotation strictly increases it; along any trace the sequence never goes down.' },
  { id: 'T2', title: 'Keys change only by rotation',
    lean: ['T2_epoch_only_by_rotation', 'T2_close_and_reopen_open_epochs'],
    plain: 'The key epoch changes only under a rotation, authorized by the next keys, and then by exactly one; a close records the epoch it opened, a reopen opens the one after the tombstone’s.' },
  { id: 'T3', title: 'Poison is local to one epoch',
    lean: ['T3_rotation_clears', 'T3_only_rotation_clears', 'T3_only_poison_sets', 'T3_epoch_local'],
    plain: 'A rotation always yields an unpoisoned state; only a rotation clears the poison; only the poison sets it, from a clean state, changing nothing else and moving no value; along any play the checkpoint is poisoned exactly when the last epoch-relevant action was a poison.' },
  { id: 'T4', title: 'Poisoned keys can only be rotated',
    lean: ['T4_poisoned_blocks_quorum_and_freeze', 'T4_poisoned_nonrotation_inert', 'T4_current_quorum_only_poisons'],
    plain: 'From a poisoned state the current quorum can do nothing and no proof can freeze it; nothing but the next keys yields a consumable state. The current keys’ only Cardano power is the poison: a close is a rotation by the next keys.' },
  { id: 'T5', title: 'Every ruled transition is enabled when its evidence is',
    lean: ['T5_every_bond_option', 'T5_poison_enabled', 'T5_freeze_enabled', 'T5_convict_enabled', 'T5_close_enabled', 'T5_reopen_enabled'],
    plain: 'Given a witnessed rotation and the new keys’ signature on the option, every bond option is enabled whatever the pool holds (payment is never a gate); given the quorum an unpoisoned state can be poisoned; given a later rotation, a short pool, a full freeze bond and no poison the freeze is enabled; given a duplicity proof conviction is enabled from every live state; given the rotation and the signed close intent the close is enabled, poisoned or not; given a later rotation the reopen is enabled from every closed state.' },
  { id: 'T6', title: 'Three value components that never mix; every intent signed by the new keys',
    lean: ['T6_component_conservation', 'T6_dreg_never_a_fee', 'T6_dreg_increases_only_by_deposit', 'T6_refund_change_requires_new_keys', 'T6_bonds_move_only_by_rotation_or_freeze', 'T6_intent_requires_new_keys', 'T6_relayer_cannot_park_age_or_close'],
    plain: 'For each of the conviction bond, the freeze bond and the pool: held plus in equals held after plus out. The conviction bond is never a fee. The refund address changes only under a rotation whose new keys signed it. A withdrawal, a deposit, a close and a new address each carry the new keys’ signature on that intent (D-038): a relayer with public data alone lands a keep and nothing else.' },
  { id: 'T7', title: 'The state is the fold of the accepted actions',
    lean: ['T7_step_iff_stepFn', 'T7_trace_iff_replay'],
    plain: 'The transition relation and the functional step agree exactly, and a trace is exactly a successful replay: replaying every accepted action from the origin reproduces the current state.' },
  { id: 'T8', title: 'One incarnation per AID: the registry leaf',
    lean: ['T8_absent_only_registers', 'T8_closed_only_reopens', 'T8_only_convicted_is_terminal', 'T8_leaf_agrees_with_state', 'T8_edges_leave_the_leaf', 'T8_present_implies_registered', 'T8_closed_leaf_is_the_tombstone', 'T8_leaf_never_absent_again', 'T8_mint_once'],
    plain: 'Registration is the only step from Absent and needs an absent leaf; reopen is the only step from Closed and needs the closed leaf; conviction is the only terminal state. The registry leaf (absent, live, closed, convicted) always agrees with the state, never returns to absent, and rotate, poison, freeze and top-up never touch it.' },
  { id: 'T9', title: 'Juvenility is consumer policy',
    lean: ['consumableStateB_iff', 'T9_juvenility_is_consumer_only'],
    plain: 'No transition depends on the window W: the same action from the same state is accepted or refused identically under any W.' },
  { id: 'T10', title: 'An unbonded or frozen checkpoint is inert to everyone but the next keys',
    lean: ['T10_inert_without_next_keys', 'T10_only_deposit_restores', 'T10_current_quorum_never_restores', 'T10_reopen_is_juvenile'],
    plain: 'If either bond is missing, no step by anyone but the next keys yields a consumable state; only a depositing rotation restores consumability, and it restarts juvenility; the current quorum never produces a consumable state; a reopen brings both bonds back and is juvenile for W slots.' },
  { id: 'T12', title: 'Conviction needs a proof and is exact',
    lean: ['T12_convicted_terminal', 'T12_convict_exact'],
    plain: 'No step leaves Convicted. Only a conviction reaches it, only with a duplicity proof; the tombstone records the tip’s epoch and sequence and the slot; the flow is exactly the conviction bond to the convictor and the rest to the refund address.' },
  { id: 'T14', title: 'The pool moves only by premium, withdrawal or top-up',
    lean: ['T14_pool_decreases_only_by_premium', 'T14_pool_increases_only_by_topup'],
    plain: 'Between live states the pool decreases only by the premium under a paid rotation or to zero under a withdrawing rotation, and increases only by a top-up that changes nothing else.' },
  { id: 'T15', title: 'The freeze bond leaves only by freeze or withdrawal',
    lean: ['T15_b_leaves_only_by_freeze_or_withdraw', 'T15_b_returns_only_by_deposit', 'T15_freeze_makes_inert'],
    plain: 'Between live states the freeze bond leaves only by a freeze (a later rotation presented, pool short, exactly B to the hunter, datum otherwise untouched) or by a withdrawing rotation; it returns only by a depositing rotation, to full; a freeze makes the checkpoint unconsumable.' },
  { id: 'T16', title: 'The closer chooses when, never where',
    lean: ['T16_close_destination', 'T16_close_needs_rotation', 'T16_withdraw_destination', 'T16_payments_are_named'],
    plain: 'A close is a witnessed rotation by the next keys, poisoned or not: it pays everything to the refund address it results in, records the epoch it opened and its sequence, and burns the token; a withdrawing rotation pays everything to the refund address it results in; a hunter is paid only the premium or the freeze bond, a convictor only the conviction bond.' },
];

// ---- the Lean oracle: cells of the embedded corpus, keyed by what stepFn reads
// A step is identified by (params, slot, input state, action) and the values
// of the evidence predicates stepFn consults for it; two Env tables that agree
// on those are the same oracle for that step.
function evidenceBits(env, state, action) {
  const k = actionKind(action); const d = (action && typeof action === 'object') ? action[k] : {};
  const l = liveOf(state);
  if (stateKind(state) === 'closed') return k === 'reopen' ? [envRotationTo(env, state.closed.epoch, state.closed.sn, d["sn'"])] : [];
  if (!l) return [];
  const e1 = natAdd(l.epoch, 1);
  switch (k) {
    case 'rotate': return [envRotationTo(env, l.epoch, l.sn, d["sn'"]), intentOk(env, e1, d.op, d["refund'"])];
    case 'close': return [envRotationTo(env, l.epoch, l.sn, d["sn'"]), intentOk(env, e1, 'close', d["refund'"])];
    case 'freeze': return [envRotationTo(env, l.epoch, l.sn, d["sn'"])];
    case 'poison': return [envQuorum(env, l.epoch)];
    case 'convict': return [envDuplicityAt(env, l.epoch, l.sn)];
  }
  return [];
}
const cellKey = (params, now, input, action, env) => canon([{ D: params.D, B: params.B, P: params.P }, now, input, action, evidenceBits(env, input, action)]);
const corpusIndexes = new WeakMap();
function corpusIndex(corpus) {
  if (!corpus || typeof corpus !== 'object') return null;
  let idx = corpusIndexes.get(corpus);
  if (idx) return idx;
  idx = new Map();
  const put = (params, now, input, action, env, result, where) => idx.set(cellKey(params, now, input, action, env), { result, where });
  const p = corpus.params;
  for (const tr of corpus.traces || []) (tr.steps || []).forEach((st, i) => put(p, st.now, st.input, st.action, tr.env, st.result, 'trace ' + tr.name + ' step ' + i));
  const g = corpus.grid;
  if (g) for (const c of g.cells || []) put(p, g.now, g.states[c.s], g.actions[c.a], g.envs[c.e], c.result, 'grid cell ' + c.s + '/' + c.a + '/' + c.e);
  for (const sc of corpus.stories || []) (sc.steps || []).forEach(st => put(st.params, st.now, st.input, st.action, st.env, st.result, 'story ' + sc.story + ' step ' + st.index));
  corpusIndexes.set(corpus, idx);
  return idx;
}
function leanCell(corpus, params, now, input, action, env) {
  const idx = corpusIndex(corpus); if (!idx) return undefined;
  return idx.get(cellKey(params, now, input, action, env));
}

function theoremReport(before, after, rec) {
  const p = before.params, env = before.env;
  const pre = rec.pre, post = rec.state, ok = rec.ok, kind = rec.kind, actor = rec.actor;
  const lp = liveOf(pre), lq = liveOf(post);
  const preK = stateKind(pre), postK = stateKind(post);
  const pp = preK === 'present' && postK === 'present';
  const a = rec.action, d = (a && typeof a === 'object') ? a[Object.keys(a)[0]] : {};
  const f = rec.flow;
  // the step crossed the boundary: everything it read is a Lean value (the
  // theorems quantify over Lean values only, so a boundary refusal exhibits none)
  const boundaryOk = !validateParams(p) && !validateEnv(env) && !validateState(pre) && isNat(rec.slot) && normalizeAction(a).ok;
  const out = {};
  const put = (id, exhibited, checks) => {
    const notes = exhibited ? checks().filter(c => !c[0]).map(c => c[1]) : [];
    out[id] = { exhibited: !!exhibited, holds: !exhibited || !notes.length, notes };
  };
  const eq = (x, y) => canon(x) === canon(y);
  const e1 = boundaryOk && lp ? natAdd(lp.epoch, 1) : null;
  const closedPre = preK === 'closed' ? pre.closed : null;

  // T1: no step decreases the sequence a state records; rotations and reopens strictly increase it
  const snPre = snOf(pre), snPost = ok ? snOf(post) : null;
  put('T1', ok && snPre !== null && snPost !== null, () => [
    [snPre <= snPost, 'sequence decreased'],
    [kind !== 'rotate' || snPre < snPost, 'rotation did not increase the sequence'],
    [kind !== 'reopen' || snPre < snPost, 'reopen did not pass the tombstone’s sequence (stale resurrection)'],
    [kind !== 'close' || snPre < snPost, 'close did not record a later sequence'],
  ]);
  // T2: epoch changed ⇒ rotation by the next keys, +1; close and reopen open epochs
  put('T2', ok && ((pp && lq.epoch !== lp.epoch) || kind === 'close' || kind === 'reopen'), () => [
    [!pp || actor === 'nextKeys', 'epoch changed without the next keys'],
    [!pp || lq.epoch === lp.epoch + 1, 'epoch did not move by one'],
    [kind !== 'close' || (postK === 'closed' && post.closed.epoch === lp.epoch + 1 && post.closed.sn === d["sn'"]), 'the tombstone does not record the epoch the close opened and its sequence'],
    [kind !== 'reopen' || (lq && lq.epoch === closedPre.epoch + 1 && lq.sn === d["sn'"]), 'the reopen did not open the epoch after the tombstone’s'],
  ]);
  // T3: poison is epoch-local
  const t3ex = ok && postK === 'present' && (kind === 'rotate' || kind === 'poison' || kind === 'reopen' || (lp && lp.poisoned !== lq.poisoned));
  put('T3', t3ex, () => [
    [(kind !== 'rotate' && kind !== 'reopen') || lq.poisoned === false, 'rotation left the poison'],
    [!(lp && lp.poisoned && !lq.poisoned) || actor === 'nextKeys', 'poison cleared by something else than a rotation'],
    [!(lp && !lp.poisoned && lq.poisoned) || (kind === 'poison' && eq(lq, { ...lp, poisoned: true }) && eq(f, flow({}))), 'poison set by something else, or it changed more than the bit'],
    [rec.aid !== after.aid || lq.poisoned === poisonAfter(liveOf(after.origin) ? liveOf(after.origin).poisoned : false, after.history), 'poison bit is not the fold of the actions'],
  ]);
  // T4: from a poisoned state; and the current quorum only poisons
  const quorumOrFreeze = actor === 'currentQuorum' || kind === 'freeze';
  put('T4', boundaryOk && ((!!lp && lp.poisoned && (ok || quorumOrFreeze)) || (ok && actor === 'currentQuorum')), () => [
    [!lp || !lp.poisoned || !ok || !quorumOrFreeze, 'the current quorum acted, or a freeze landed, on a poisoned checkpoint'],
    [!lp || !lp.poisoned || !ok || actor === 'nextKeys' || !consumableEver(p, post), 'a non-rotation made a poisoned checkpoint consumable'],
    [actor !== 'currentQuorum' || !ok || kind === 'poison', 'the current quorum did something other than poison'],
  ]);
  // T5: totality — the evidence antecedent held ⇒ the step is accepted
  let ante = false;
  if (boundaryOk && rec.stepped && preK === 'present') {
    const l = lp;
    if (kind === 'rotate') ante = envRotationTo(env, l.epoch, l.sn, d["sn'"]) && l.sn < d["sn'"] && intentOk(env, e1, d.op, d["refund'"]) &&
      (d.op !== 'deposit' || (l.dreg <= p.D && l.b <= p.B));
    else if (kind === 'poison') ante = envQuorum(env, l.epoch) && !l.poisoned;
    else if (kind === 'freeze') ante = envRotationTo(env, l.epoch, l.sn, d["sn'"]) && l.sn < d["sn'"] && l.pool < p.P && l.b === p.B && !l.poisoned;
    else if (kind === 'convict') ante = envDuplicityAt(env, l.epoch, l.sn);
    else if (kind === 'close') ante = envRotationTo(env, l.epoch, l.sn, d["sn'"]) && l.sn < d["sn'"] && intentOk(env, e1, 'close', d["refund'"]);
    else if (kind === 'topUp') ante = true;
  } else if (boundaryOk && rec.stepped && preK === 'absent' && kind === 'register') ante = true;
  else if (boundaryOk && rec.stepped && preK === 'closed' && kind === 'reopen') ante = envRotationTo(env, closedPre.epoch, closedPre.sn, d["sn'"]) && closedPre.sn < d["sn'"];
  put('T5', ante, () => [[ok, 'evidence held but the step was refused: ' + rec.reason]]);
  // T6: value, and the intent signatures
  if (ok) {
    const hi = held(pre), ho = held(post);
    const pr = paid(f.refund), ph = paid(f.hunter), pc = paid(f.convictor);
    const dregOk = big(hi.dreg) + big(f.dregIn) === big(ho.dreg) + big(pr.dreg) + big(ph.dreg) + big(pc.dreg);
    const bOk = big(hi.b) + big(f.bIn) === big(ho.b) + big(pr.b) + big(ph.b) + big(pc.b);
    const poolOk = big(held(pre).pool) + big(f.poolIn) === big(ho.pool) + big(pr.pool) + big(ph.pool) + big(pc.pool);
    const signed = (intent, r) => envIntentAuthorized(env, e1, intent, r === undefined ? null : r);
    put('T6', true, () => [
      [dregOk, 'conviction bond not conserved'], [bOk, 'freeze bond not conserved'], [poolOk, 'pool not conserved'],
      [ph.dreg === 0, 'a hunter was paid from the conviction bond'],
      [pr.dreg === 0 || (pr.dreg === hi.dreg && ho.dreg === 0), 'the conviction bond left partially to the refund address'],
      [pc.dreg === 0 || (pc.dreg === hi.dreg && postK === 'convicted'), 'the conviction bond went to a convictor without a conviction'],
      [!pp || !(lp.dreg < lq.dreg) || (kind === 'rotate' && d.op === 'deposit' && lq.dreg === p.D && lq.b === p.B && f.dregIn === p.D - lp.dreg && f.bIn === p.B - lp.b && lq.bornAt === rec.slot), 'the conviction bond increased other than by a full deposit'],
      [!pp || lq.refundTo === lp.refundTo || (kind === 'rotate' && d["refund'"] === lq.refundTo && envIntentAuthorized(env, lq.epoch, d.op, lq.refundTo)), 'the refund address moved other than by a rotation naming it, signed by the new keys as that rotation’s own intent (T6_refund_change_requires_new_keys)'],
      [!pp || (lq.dreg === lp.dreg && lq.b === lp.b) || actor === 'nextKeys' || kind === 'freeze', 'a bond moved under poison or top-up'],
      [kind !== 'rotate' || d.op !== 'withdraw' || signed('withdraw', d["refund'"]), 'a withdrawal landed without the new keys’ signature on it (D-038)'],
      [kind !== 'rotate' || d.op !== 'deposit' || signed('deposit', d["refund'"]), 'a deposit landed without the new keys’ signature on it (D-038)'],
      [kind !== 'close' || signed('close', d["refund'"]), 'a close landed without the new keys’ signature on it (D-038)'],
      [kind !== 'rotate' || d.op !== 'keep' || d["refund'"] === null || d["refund'"] === undefined || signed('keep', d["refund'"]), 'a new refund address landed without the new keys’ signature on it (D-038)'],
    ]);
  } else put('T6', false, () => []);
  // T7: parity with the Lean — the step has a cell in the embedded corpus and the
  // core's verdict, flow and post-state equal Lean's (both directions of
  // T7_step_iff_stepFn); plus the fold (T7_trace_iff_replay) on accepted steps
  const cell = rec.stepped && boundaryOk ? leanCell(before.corpus, p, rec.slot, pre, a, env) : undefined;
  if (cell !== undefined) {
    put('T7', true, () => [
      [(cell.result === null) === !ok, 'Lean ' + (cell.result === null ? 'refuses' : 'applies') + ' this step (' + cell.where + '), the core ' + (ok ? 'applied' : 'refused: ' + rec.reason)],
      [!ok || cell.result === null || eq(f, cell.result.flow), 'flow differs from Lean (' + cell.where + ')'],
      [!ok || cell.result === null || eq(post, cell.result.state), 'post-state differs from Lean (' + cell.where + ')'],
      [!ok || rec.aid !== after.aid || (() => { const rp = replay(p, after.envAll, after.originSlot, after.origin, after.history); return rp.ok && eq(rp.state, post); })(), 'replay of the accepted actions does not reproduce the state'],
    ]);
    out.T7.cell = cell.where;
  } else { put('T7', false, () => []); out.T7.cell = null; out.T7.notes = rec.stepped ? ['no Lean cell for this step: T7 not shown'] : []; }
  // T8: the registry leaf on every system transition: it agrees with every state,
  // edges never touch it, it never returns to absent, a convicted leaf stays;
  // terminals and the only-step-from rules; mint-once on the leaf
  const leafPre = leafOfAid(before, rec.aid), leafPost = leafOfAid(after, rec.aid);
  put('T8', ok || preK === 'convicted' || preK === 'closed' || preK === 'absent' || kind === 'register' || kind === 'reopen', () => [
    [preK !== 'convicted' || !ok, 'a step left Convicted'],
    [preK !== 'closed' || !ok || (kind === 'reopen' && lq && lq.dreg === p.D && lq.b === p.B && lq.bornAt === rec.slot && lq.epoch === closedPre.epoch + 1 && lq.sn === d["sn'"]), 'something other than a reopen left Closed, or the reopen did not bring fresh bonds at the next epoch'],
    [preK !== 'absent' || (ok === (kind === 'register' && rec.stepped && leafPre === 'absent' && boundaryOk)), 'from absent, something other than a registration happened, or a registration was refused without cause'],
    [kind !== 'register' || !ok || (preK === 'absent' && leafPre === 'absent'), 'a registration landed on a non-absent state or leaf'],
    [kind !== 'reopen' || !ok || (preK === 'closed' && leafKind(leafPre) === 'closed'), 'a reopen landed on a state or leaf that is not closed'],
    [allAids(after).every(x => eq(leafOfAid(after, x), leafOf(stateOfAid(after, x)))), 'a leaf disagrees with its state (T8_leaf_agrees_with_state)'],
    [!ok || (eq(leafPost, leafPre) === !TOUCHES_LEAF.has(kind)), 'the leaf changed exactly when the action is not a register, reopen, close or conviction — violated (T8_edges_leave_the_leaf)'],
    [leafPre === 'absent' || leafPost !== 'absent', 'a leaf returned to absent (T8_leaf_never_absent_again)'],
    [leafPre !== 'convicted' || leafPost === 'convicted', 'a convicted leaf changed'],
    [allAids(after).filter(x => x !== rec.aid).every(x => eq(leafOfAid(after, x), leafOfAid(before, x))), 'another AID’s leaf changed'],
  ]);
  // T9: the transition never reads W (a trap on the params throws on any read of
  // W outside validation — structural, hence universal over W'), and the same
  // step under sampled W' values gives the same result
  if (rec.stepped) {
    const r0 = step(p, env, a, rec.slot, pre);
    const trap = new Proxy(p, { get(t, k) { if (k === 'W' && !validatingParams) throw new Error('W read'); return t[k]; } });
    let untouched = true, rT = null;
    try { rT = step(trap, env, a, rec.slot, pre); } catch (e) { untouched = false; }
    const samples = [0, 1, 2, 3, 5, 7, 11, 1000, 31536000, MAX_NAT, p.W + 1, p.W > 0 ? p.W - 1 : 4, (rec.slot * 7919 + 13) % 100000];
    const differing = samples.filter(w => !eq(r0, step({ ...p, W: w }, env, a, rec.slot, pre)));
    put('T9', true, () => [
      [untouched && eq(r0, rT), 'the transition read W'],
      [!differing.length, 'the step differs under W = ' + differing.slice(0, 3).join(', ')],
    ]);
  } else put('T9', false, () => []);
  // T10: bonds missing, or the current quorum acted; a reopen is juvenile
  const missing = boundaryOk && !!lp && (lp.dreg !== p.D || lp.b !== p.B);
  put('T10', ok && ((missing) || actor === 'currentQuorum' || kind === 'reopen'), () => [
    [!missing || actor === 'nextKeys' || !consumableEver(p, post), 'someone but the next keys made an unbonded checkpoint consumable'],
    [!missing || !consumableEver(p, post) || (kind === 'rotate' && d.op === 'deposit' && lq && lq.dreg === p.D && lq.b === p.B && lq.bornAt === rec.slot), 'consumability restored other than by a depositing rotation with restarted juvenility'],
    [actor !== 'currentQuorum' || !consumableEver(p, post), 'the current quorum produced a consumable state'],
    [kind !== 'reopen' || (lq && lq.dreg === p.D && lq.b === p.B && lq.bornAt === rec.slot && !consumable(p, rec.slot, post).ok), 'a reopen did not bring full bonds and a fresh juvenility window'],
  ]);
  // T12: conviction
  put('T12', (kind === 'convict' && boundaryOk) || preK === 'convicted', () => [
    [preK !== 'convicted' || !ok, 'a step left Convicted'],
    [kind !== 'convict' || preK !== 'present' || !rec.stepped || !boundaryOk || (ok === envDuplicityAt(env, lp.epoch, lp.sn)), 'conviction accepted without a proof, or refused with one'],
    [kind !== 'convict' || !ok || eq(post, { convicted: { epoch: lp.epoch, sn: lp.sn, convictedAt: rec.slot } }), 'the tombstone does not record the tip and the slot'],
    [kind !== 'convict' || !ok || eq(f, flow({ refund: payment(lp.refundTo, 0, lp.b, lp.pool), convictor: payment(d.payee, lp.dreg, 0, 0) })), 'the conviction flow is not exactly D to the convictor and the rest to the refund address'],
  ]);
  // T14: the pool
  put('T14', ok && pp && (lq.pool !== lp.pool || kind === 'topUp'), () => [
    [!(lq.pool < lp.pool) || (actor === 'nextKeys' && ((big(lq.pool) + big(p.P) === big(lp.pool) && paid(f.hunter).pool === p.P) || (lq.pool === 0 && f.refund !== null))), 'the pool decreased other than by the premium or a withdrawal'],
    [!(lp.pool < lq.pool) || (kind === 'topUp' && eq(f, flow({ poolIn: d.x })) && big(lq.pool) === big(lp.pool) + big(d.x) && eq({ ...lq, pool: 0 }, { ...lp, pool: 0 })), 'the pool increased other than by a top-up that changes nothing else'],
    [kind !== 'topUp' || big(lq.pool) === big(lp.pool) + big(d.x), 'a top-up did not add exactly its amount (precision lost)'],
  ]);
  // T15: the freeze bond
  put('T15', ok && ((pp && lq.b !== lp.b) || kind === 'freeze'), () => [
    [!pp || !(lq.b < lp.b) || (kind === 'freeze' && envRotationTo(env, lp.epoch, lp.sn, d["sn'"]) && lp.pool < p.P && eq(lq, { ...lp, b: 0 }) && eq(f, flow({ hunter: payment(d.payee, 0, p.B, 0) }))) || (kind === 'rotate' && d.op === 'withdraw' && lq.b === 0 && lq.dreg === 0 && lq.pool === 0), 'the freeze bond left other than by an exact freeze or a withdrawal'],
    [!pp || !(lp.b < lq.b) || (kind === 'rotate' && d.op === 'deposit' && lq.b === p.B && lq.dreg === p.D), 'the freeze bond returned other than by a full deposit'],
    [kind !== 'freeze' || !consumableEver(p, post), 'a freeze left the checkpoint consumable'],
  ]);
  // T16: destinations; the close needs the rotation and the signed intent
  put('T16', ok && (postK === 'closed' || (kind === 'rotate' && d.op === 'withdraw') || f.hunter !== null || f.convictor !== null), () => [
    [postK !== 'closed' || (kind === 'close' && lp && eq(f, flow({ refund: payment(d["refund'"] === null ? lp.refundTo : d["refund'"], lp.dreg, lp.b, lp.pool) })) && envRotationTo(env, lp.epoch, lp.sn, d["sn'"]) && lp.sn < d["sn'"] && intentOk(env, e1, 'close', d["refund'"]) && actor === 'nextKeys'), 'Closed reached other than by a close under a witnessed rotation and the signed intent, paying everything to the resulting refund address'],
    [!(kind === 'rotate' && d.op === 'withdraw') || (eq(f, flow({ refund: payment(lq.refundTo, lp.dreg, lp.b, lp.pool) })) && lq.refundTo === (d["refund'"] === null ? lp.refundTo : d["refund'"])), 'the withdrawal did not pay everything to the resulting refund address'],
    [f.hunter === null || eq(paid(f.hunter), { dreg: 0, b: 0, pool: p.P }) || eq(paid(f.hunter), { dreg: 0, b: p.B, pool: 0 }), 'a hunter was paid something other than the premium or the freeze bond'],
    [f.convictor === null || eq(paid(f.convictor), { dreg: held(pre).dreg, b: 0, pool: 0 }), 'a convictor was paid something other than the conviction bond'],
  ]);
  return out;
}
/* @@CORE:theorems:END@@ */

/* @@CORE:suite@@ */
// ---- the executable suite: scenarios and the Lean corpus ---------------------
// Shared by the gates (Node) and the page's ?selftest=1 (browser): one
// implementation of "does this scenario play as written" and "does the
// Lean corpus replay through this core".
function matchesPartial(got, want) {
  if (want === null || typeof want !== 'object' || Array.isArray(want)) return canon(got) === canon(want);
  if (got === null || typeof got !== 'object') return false;
  return Object.keys(want).every(k => matchesPartial(got[k], want[k]));
}
// checkScenario(scenario, label, corpus) → {problems, stepsRun, asserted, exhibited, timeline, forks}
// timeline: one entry per trunk step with the session after it and the record (if
// any); forks: [{id, at, title, timeline}], each replayed from the trunk session
// after step `at` — a scenario is a tree, the trunk and its forks
function checkScenario(sc, label, corpus) {
  const problems = [], asserted = [], exhibited = new Set();
  let stepsRun = 0;
  // one step of a branch: evidence, seed, params override, the action or the
  // slot move, every expectation; returns the session after it and the record
  const applyStep = (session, st, where) => {
    const saved = session.params;
    if (st.params) session = withParams(session, st.params);
    if (st.seed !== undefined) {
      const bad = validateState(st.seed);
      if (bad) { problems.push(where + ': seed refused: ' + bad.reason + ' ' + bad.message); return { session, record: null }; }
      session = seed(session, st.seed);
    }
    if (st.evidence) {
      for (const r of st.evidence.remove || []) session = removeEvidence(session, r);
      for (const r of st.evidence.add || []) session = addEvidence(session, r);
    }
    const ex = st.expect || {};
    let record = null;
    if (st.action === undefined) {
      const mv = setSlot(session, st.slot);
      if (!mv.ok) problems.push(where + ': slot ' + st.slot + ' refused: ' + mv.reason);
      else session = mv.session;
    } else {
      const out = attempt(session, st.action, st.slot);
      session = out.session; record = out.record; stepsRun++;
      if (ex.ok !== undefined && record.ok !== ex.ok)
        problems.push(where + ': expected ok=' + ex.ok + ', got ok=' + record.ok + (record.ok ? '' : ' (' + record.reason + ')'));
      if (ex.reason !== undefined) { asserted.push(ex.reason); if (record.reason !== ex.reason) problems.push(where + ': expected reason «' + ex.reason + '», got «' + record.reason + '»'); }
      if (record.ok && ex.live !== undefined) {
        const l = liveOf(record.state);
        if (!l || !matchesPartial(l, ex.live)) problems.push(where + ': live datum mismatch — expected ⊇ ' + JSON.stringify(ex.live) + ' got ' + JSON.stringify(l));
      }
      if (record.ok && ex.state !== undefined && canon(record.state) !== canon(ex.state)) problems.push(where + ': state mismatch — expected ' + canon(ex.state) + ' got ' + canon(record.state));
      if (record.ok && ex.flow !== undefined && canon(record.flow) !== canon(flow(ex.flow))) problems.push(where + ': flow mismatch — expected ' + canon(flow(ex.flow)) + ' got ' + canon(record.flow));
      const th = record.theorems;
      const failing = Object.keys(th).filter(id => !th[id].holds);
      if (failing.length) problems.push(where + ': theorem VIOLATED: ' + failing.map(id => id + ' (' + th[id].notes.join('; ') + ')').join(' · '));
      const shown = Object.keys(th).filter(id => th[id].exhibited).sort();
      shown.forEach(id => exhibited.add(id));
      if (ex.exhibits !== undefined) {
        const want = ex.exhibits.slice().sort();
        if (JSON.stringify(shown) !== JSON.stringify(want)) problems.push(where + ': exhibits mismatch — expected [' + want + '] got [' + shown + ']');
      }
      if (!record.ok) { const text = explain(record, session); if (typeof text !== 'string' || text.length < 12) problems.push(where + ': refusal «' + record.reason + '» has no explanation'); }
    }
    if (st.params) session = withParams(session, saved);
    if (ex.verdict !== undefined) {
      const v = consumable(session.params, session.now, session.state);
      if (v.verdict !== ex.verdict) problems.push(where + ': verdict mismatch — expected «' + ex.verdict + '» got «' + v.verdict + '»');
    }
    return { session, record };
  };
  const branch = (session, steps, where) => {
    const timeline = [];
    steps.forEach((st, i) => { const r = applyStep(session, st, where(i)); session = r.session; timeline.push({ step: st, session, record: r.record }); });
    return timeline;
  };
  // the trunk, then every fork from the trunk session it departs from
  const origin = newSession(sc.params, { corpus: corpus || null });
  const timeline = branch(origin, sc.steps || [], i => label + ' step ' + i);
  const forks = [];
  (sc.forks || []).forEach((fk, k) => {
    const at = fk.at;
    if (!Number.isInteger(at) || at < 0 || at >= timeline.length) { problems.push(label + ' fork ' + (fk.id || k) + ': departs after trunk step ' + at + ', which does not exist'); return; }
    if (!fk.id || !Array.isArray(fk.steps) || !fk.steps.length) { problems.push(label + ' fork ' + (fk.id || k) + ': needs an id and steps'); return; }
    forks.push({ id: fk.id, at, title: fk.title || fk.id, timeline: branch(timeline[at].session, fk.steps, i => label + ' fork ' + fk.id + ' step ' + i) });
  });
  return { problems, stepsRun, asserted, exhibited: [...exhibited], timeline, forks };
}
// checkCorpus(corpus) → {applied, refused, cons, theoremChecks, reasons}: every
// step of the Lean corpus (applied and refused) must agree with step(); every
// applied step must satisfy every theorem
function checkCorpus(corpus) {
  const reasons = [];
  let applied = 0, refused = 0, theoremChecks = 0, cons = 0;
  const p = corpus.params;
  const pv = validateParams(p); if (pv) reasons.push('corpus params invalid: ' + pv);
  // the boundary first: every state and every evidence table the corpus carries
  // is validated by name before any cell is replayed; a corrupted one is a
  // refusal of the verifier, whatever the Lean said about that cell
  // — inputs and results alike: every state, evidence table, action, slot,
  // flow and result the corpus carries, before any comparison
  const badState = (where, s) => { const b = validateState(s); if (b) reasons.push(where + ': ' + b.reason + ' ' + b.field + ' (' + b.message + ')'); return !!b; };
  const badEnv = (where, e) => { const b = validateEnv(e); if (b) reasons.push(where + ': ' + b.reason + ' ' + b.field + ' (' + b.message + ')'); return !!b; };
  const badFlow = (where, f) => { const b = validateFlow(f); if (b) reasons.push(where + ': ' + b.reason + ' ' + b.field + ' (' + b.message + ')'); return !!b; };
  const badSlot = (where, n) => { if (isNat(n)) return false; reasons.push(where + ': invalid-nat now (not a non-negative integer)'); return true; };
  const badAction = (where, a) => { const n = normalizeAction(a); if (n.ok) return false; reasons.push(where + ': ' + n.reason + ' ' + n.field); return true; };
  const badResult = (where, r) => { if (r === null) return false; if (!r || typeof r !== 'object' || Array.isArray(r) || Object.keys(r).length !== 2 || !('flow' in r) || !('state' in r)) { reasons.push(where + ': invalid-result (a result is null or exactly {flow, state})'); return true; } const f = badFlow(where + ' flow', r.flow); return badState(where + ' state', r.state) || f; };
  for (const tr of corpus.traces || []) {
    badEnv('trace ' + tr.name + ' env', tr.env);
    (tr.steps || []).forEach((st, i) => { const w = 'trace ' + tr.name + ' step ' + i; badSlot(w, st.now); badState(w + ' input', st.input); badAction(w + ' action', st.action); badResult(w + ' result', st.result); });
  }
  if (corpus.grid) {
    const g = corpus.grid;
    badSlot('grid now', g.now);
    (g.states || []).forEach((s, i) => badState('grid state ' + i, s)); (g.envs || []).forEach((e, i) => badEnv('grid env ' + i, e)); (g.actions || []).forEach((a, i) => badAction('grid action ' + i, a));
    (g.cells || []).forEach(c => badResult('grid cell s=' + c.s + ' a=' + c.a + ' e=' + c.e + ' result', c.result));
    (g.consumable || []).forEach(c => badSlot('consumable probe s=' + c.s, c.now));
  }
  for (const sc of corpus.stories || []) for (const st of sc.steps || []) {
    const where = 'story ' + sc.story + ' step ' + st.index;
    const pv2 = validateParams(st.params); if (pv2) reasons.push(where + ': invalid-params ' + pv2);
    badSlot(where, st.now); badState(where + ' input', st.input); badEnv(where + ' env', st.env); badAction(where + ' action', st.action); badResult(where + ' result', st.result);
  }
  if (reasons.length) return { applied, refused, cons, theoremChecks, storyCells: 0, reasons };
  const envOf = env => { let s = newSession(p, { corpus }); for (const k of EV_KINDS) for (const row of env[k] || []) s = addEvidence(s, { [k]: row }); return s; };
  const compare = (where, env, now, input, action, want) => {
    const got = step(p, env, action, now, input);
    if (want === null) { if (got.ok) reasons.push(where + ': Lean refused, the core applied'); else refused++; return null; }
    if (!got.ok) { reasons.push(where + ': Lean applied, the core refused (' + got.reason + ')'); return null; }
    if (canon(got.flow) !== canon(want.flow)) reasons.push(where + ': flow differs — lean=' + canon(want.flow) + ' core=' + canon(got.flow));
    if (canon(got.state) !== canon(want.state)) reasons.push(where + ': post-state differs — lean=' + canon(want.state) + ' core=' + canon(got.state));
    applied++; return got;
  };
  const theorems = (where, session, action, now) => {
    const out = attempt(session, action, now); theoremChecks++;
    const th = out.record.theorems; const failing = Object.keys(th).filter(id => !th[id].holds);
    if (failing.length) reasons.push(where + ': theorem VIOLATED: ' + failing.map(id => id + ' (' + th[id].notes.join('; ') + ')').join(' · '));
    return out.session;
  };
  for (const tr of corpus.traces || []) {
    let session = envOf(tr.env); let s = tr.initial;
    if (canon(s) !== canon('absent')) reasons.push('trace ' + tr.name + ': initial state is not absent');
    (tr.steps || []).forEach((st, i) => {
      const where = 'trace ' + tr.name + ' step ' + i;
      if (canon(st.input) !== canon(s)) reasons.push(where + ': input discontinuous');
      compare(where, session.env, st.now, st.input, st.action, st.result);
      session = theorems(where, session, st.action, st.now);
      s = st.result ? st.result.state : s;
    });
  }
  const g = corpus.grid;
  if (!g || !Array.isArray(g.cells) || !g.cells.length) reasons.push('grid missing or empty');
  else {
    for (const c of g.cells) {
      const input = g.states[c.s], action = g.actions[c.a], env = g.envs[c.e];
      const where = 'grid cell s=' + c.s + ' a=' + c.a + ' e=' + c.e;
      compare(where, env, g.now, input, action, c.result);
      if (c.result) { let session = envOf(env); if (stateKind(input) !== 'absent') session = seed(session, input); theorems(where, session, action, g.now); }
    }
    for (const c of g.consumable || []) { const v = consumable(p, c.now, g.states[c.s]); cons++; if (v.ok !== c.consumable) reasons.push('consumable probe s=' + c.s + ' now=' + c.now + ': lean=' + c.consumable + ' core=' + v.ok); }
  }
  // story cells: Lean's verdict on every story step it could construct
  let storyCells = 0;
  for (const sc of corpus.stories || []) for (const st of sc.steps || []) {
    storyCells++;
    const where = 'story ' + sc.story + ' step ' + st.index;
    const pv2 = validateParams(st.params); if (pv2) { reasons.push(where + ': cell params invalid: ' + pv2); continue; }
    const got = step(st.params, st.env, st.action, st.now, st.input);
    if (st.result === null) { if (got.ok) reasons.push(where + ': Lean refused, the core applied'); else refused++; }
    else if (!got.ok) reasons.push(where + ': Lean applied, the core refused (' + got.reason + ')');
    else { if (canon(got.flow) !== canon(st.result.flow) || canon(got.state) !== canon(st.result.state)) reasons.push(where + ': flow or post-state differs from Lean'); applied++; }
  }
  return { applied, refused, cons, theoremChecks, storyCells, reasons };
}
/* @@CORE:suite:END@@ */

export {
  canon, isNat, REASONS, VERDICTS, LEAN_GUARDS, LEAN_SPLITS, VERDICT_CONJUNCTS, constructorOf,
  validateParams, ACTION_KINDS, BOND_OPS, INTENTS, actionKind, normalizeAction, actorOf,
  EV_KINDS, EV_ARITY, EV_SHAPE, emptyEnv, envHas, envAdd, envRemove, envUnion, validateEnv, intentOk, stateKind, liveOf, present, payment, flow, held, paid, snOf, leafOf, leafKind,
  LIVE_NATS, validateState, validateFlow, step, consumable, consumableEver, replay, poisonAfter, poisonSinceLastRotation,
  newSession, withParams, addEvidence, removeEvidence, seed, seedOther, stateOfAid, leafOfAid, allAids, setSlot, attempt, heldSoFar,
  MAX_NAT, natAdd, parseNat, lossyJsonNumbers, parseJsonExact, evidenceBits, cellKey, leanCell,
  CAST, whoAddr, STATE_WORDS, stateWord, VERDICT_WORDS, INTENT_WORDS, explain, THEOREMS, theoremReport,
  matchesPartial, checkScenario, checkCorpus,
};
