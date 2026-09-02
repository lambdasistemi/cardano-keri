/*
 * checkpoint-simulator-core.mjs — the pure core of the M1 checkpoint
 * simulator: a JavaScript transcription of `stepFn`, `replay` and
 * `consumableState` from lean/CardanoKeri/Checkpoint.lean, and the
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
 *           | {convicted:{epoch,sn,convictedAt}} | 'gone'
 *   action  {register:{refund,pool0}} | {rotate:{"sn'",op,payee,"refund'"}} | 'poison'
 *           | {freeze:{"sn'",payee}} | {topUp:{x}} | {convict:{payee}} | 'close'
 *   flow    {dregIn,bIn,poolIn,refund,hunter,convictor}   payment {addr,dreg,b,pool}
 *   env     {rotationTo:[[e,sn,sn']], refundAuthorized:[[e,a]], quorum:[[e]], duplicityAt:[[e,sn]]}
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
  'invalid-params', 'invalid-nat', 'invalid-action',
  'gone-terminal', 'convicted-terminal', 'absent-needs-register', 'already-present',
  'no-witnessed-rotation', 'sequence-not-later', 'refund-not-authorized', 'bond-over-full',
  'no-quorum', 'already-poisoned', 'poisoned', 'pool-covers-premium', 'freeze-bond-missing',
  'no-duplicity-proof', 'slot-regression', 'aid-already-registered',
];
const VERDICTS = ['consumable', 'not-present', 'dreg-missing', 'b-missing', 'poisoned', 'juvenile'];

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
const ACTION_KINDS = ['register', 'rotate', 'poison', 'freeze', 'topUp', 'convict', 'close'];
const BOND_OPS = ['keep', 'withdraw', 'deposit'];

function actionKind(a) {
  if (a === 'poison' || a === 'close') return a;
  if (a && typeof a === 'object' && !Array.isArray(a)) {
    const ks = Object.keys(a);
    if (ks.length === 1 && ACTION_KINDS.includes(ks[0])) return ks[0];
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
  switch (kind) {
    case 'poison': case 'close': return { ok: true, kind, action: kind };
    case 'register': {
      const e = bad([d.refund, 'refund'], [d.pool0, 'pool0']); if (e) return e;
      return { ok: true, kind, action: { register: { refund: d.refund, pool0: d.pool0 } } };
    }
    case 'rotate': {
      const e = bad([d["sn'"], "sn'"], [d.payee, 'payee']); if (e) return e;
      if (!BOND_OPS.includes(d.op)) return { ok: false, reason: 'invalid-action', field: 'op' };
      const r = d["refund'"] === undefined ? null : d["refund'"];
      if (r !== null && !isNat(r)) return { ok: false, reason: 'invalid-nat', field: "refund'" };
      return { ok: true, kind, action: { rotate: { "sn'": d["sn'"], op: d.op, payee: d.payee, "refund'": r } } };
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
  }
  return { ok: false, reason: 'invalid-action', field: 'action' };
}

// Action.actor
function actorOf(a) {
  switch (actionKind(a)) {
    case 'register': case 'topUp': return 'anyone';
    case 'rotate': return 'nextKeys';
    case 'poison': case 'close': return 'currentQuorum';
    case 'freeze': case 'convict': return 'proof';
  }
  return null;
}

// ---- Env: decision tables ----------------------------------------------------
const EV_KINDS = ['rotationTo', 'refundAuthorized', 'quorum', 'duplicityAt'];
const emptyEnv = () => ({ rotationTo: [], refundAuthorized: [], quorum: [], duplicityAt: [] });
const envHas = (env, kind, args) => (env[kind] || []).some(r => canon(r) === canon(args));
const envRotationTo = (env, e, sn, sn2) => envHas(env, 'rotationTo', [e, sn, sn2]);
const envRefundAuthorized = (env, e, a) => envHas(env, 'refundAuthorized', [e, a]);
const envQuorum = (env, e) => envHas(env, 'quorum', [e]);
const envDuplicityAt = (env, e, sn) => envHas(env, 'duplicityAt', [e, sn]);
// a row is {kind:[args]}; returns the env with the row added / removed
function envAdd(env, row) {
  const [kind] = Object.keys(row); const args = row[kind];
  if (!EV_KINDS.includes(kind) || !Array.isArray(args) || !args.every(isNat)) throw new Error('bad evidence row ' + JSON.stringify(row));
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
const stateKind = s => (s === 'absent' || s === 'gone') ? s : (s && s.present ? 'present' : (s && s.convicted ? 'convicted' : null));
const liveOf = s => (s && s.present ? s.present.l : null);
const present = l => ({ present: { l } });
const payment = (addr, dreg, b, pool) => ({ addr, dreg, b, pool });
const flow = f => Object.assign({ dregIn: 0, bIn: 0, poolIn: 0, refund: null, hunter: null, convictor: null }, f);
// State.dregHeld / bHeld / poolHeld
const held = s => { const l = liveOf(s); return l ? { dreg: l.dreg, b: l.b, pool: l.pool } : { dreg: 0, b: 0, pool: 0 }; };
// Payment?.dreg etc.
const paid = q => (q ? { dreg: q.dreg, b: q.b, pool: q.pool } : { dreg: 0, b: 0, pool: 0 });

function validateState(s) {
  const k = stateKind(s);
  if (!k) return 'unknown state shape';
  if (k === 'present') {
    const l = s.present.l;
    for (const f of ['sn', 'epoch', 'bornAt', 'refundTo', 'dreg', 'b', 'pool']) if (!isNat(l[f])) return `${f} is not a non-negative integer`;
    if (typeof l.poisoned !== 'boolean') return 'poisoned is not a boolean';
  }
  if (k === 'convicted') for (const f of ['epoch', 'sn', 'convictedAt']) if (!isNat(s.convicted[f])) return `${f} is not a non-negative integer`;
  return null;
}

// ---- stepFn ----------------------------------------------------------------
// step(params, env, action, now, state) → {ok:true, kind, flow, state} | {ok:false, reason, field?}
function step(p, env, action, now, state) {
  const refuse = (reason, field) => (field ? { ok: false, reason, field } : { ok: false, reason });
  const pv = validateParams(p); if (pv) return refuse('invalid-params', pv);
  if (!isNat(now)) return refuse('invalid-nat', 'now');
  const na = normalizeAction(action); if (!na.ok) return refuse(na.reason, na.field);
  const a = na.action, kind = na.kind;
  const some = (f, s) => ({ ok: true, kind, flow: flow(f), state: s });
  const sk = stateKind(state);
  if (sk === 'gone') return refuse('gone-terminal');
  if (sk === 'convicted') return refuse('convicted-terminal');
  if (sk === 'absent') {
    if (kind !== 'register') return refuse('absent-needs-register');
    const { refund, pool0 } = a.register;
    return some({ dregIn: p.D, bIn: p.B, poolIn: pool0 },
      present({ sn: 0, epoch: 0, poisoned: false, bornAt: now, refundTo: refund, dreg: p.D, b: p.B, pool: pool0 }));
  }
  const l = state.present.l;
  switch (kind) {
    case 'register': return refuse('already-present');
    case 'rotate': {
      const { "sn'": sn2, op, payee, "refund'": r } = a.rotate;
      if (!envRotationTo(env, l.epoch, l.sn, sn2)) return refuse('no-witnessed-rotation');
      if (!(l.sn < sn2)) return refuse('sequence-not-later');
      if (r !== null && !envRefundAuthorized(env, natAdd(l.epoch, 1), r)) return refuse('refund-not-authorized');
      const r2 = r === null ? l.refundTo : r;
      const epoch2 = natAdd(l.epoch, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
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
    case 'close':
      if (!envQuorum(env, l.epoch)) return refuse('no-quorum');
      if (state.present.l.poisoned) return refuse('poisoned');
      return some({ refund: payment(l.refundTo, l.dreg, l.b, l.pool) }, 'gone');
  }
  return refuse('invalid-action', 'action');
}

// ---- consumableState -------------------------------------------------------
// the state-side conjuncts, in the Lean's order; the first failing one names the verdict
function consumable(p, now, state) {
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
  let t = t0, s = state;
  for (let i = 0; i < list.length; i++) {
    const [t2, a] = list[i];
    if (!(t <= t2)) return { ok: false, at: i, reason: 'slot-regression' };
    const r = step(p, env, a, t2, s);
    if (!r.ok) return { ok: false, at: i, reason: r.reason };
    t = t2; s = r.state;
  }
  return { ok: true, state: s };
}

// poisonAfter / poisonSinceLastRotation
function poisonAfter(b, list) {
  for (const [, a] of list) {
    const k = actionKind(a);
    if (k === 'poison') b = true;
    else if (k === 'rotate' || k === 'register') b = false;
  }
  return b;
}
const poisonSinceLastRotation = list => poisonAfter(false, list);
/* @@CORE:model:END@@ */

/* @@CORE:session@@ */
// ---- a session: params, evidence, slot, state, registry, history --------------
// Sessions are immutable values; every operation returns a new one, so a page
// can keep them for time travel.
// The session is the Lean `Sys` for one deployment: a registry of every AID
// ever registered and each AID's state (`others`), plus the AID the page
// plays (`aid`, whose state is `state`). `corpus` is the embedded Lean corpus
// the T7 checker consults; without it T7 is never exhibited.
function newSession(params, opts) {
  const aid = (opts && opts.aid) || 1;
  return { params, env: emptyEnv(), envAll: emptyEnv(), now: 0, state: 'absent', aid, others: {},
    registry: [], history: [], origin: 'absent', originSlot: 0, records: [], corpus: (opts && opts.corpus) || null };
}
const stateOfAid = (s, aid) => (aid === s.aid ? s.state : (s.others[aid] !== undefined ? s.others[aid] : 'absent'));
const allAids = s => [...new Set([s.aid, ...Object.keys(s.others).map(Number), ...s.registry])];
// seed another AID's state (a system-level fixture); registers it if not absent
function seedOther(s, aid, state) {
  const bad = validateState(state); if (bad) throw new Error('seedOther: ' + bad);
  if (aid === s.aid) return seed(s, state);
  const registry = stateKind(state) !== 'absent' && !s.registry.includes(aid) ? [...s.registry, aid] : s.registry;
  return { ...s, others: { ...s.others, [aid]: state }, registry };
}
const withParams = (s, params) => ({ ...s, params });
const addEvidence = (s, row) => ({ ...s, env: envAdd(s.env, row), envAll: envAdd(s.envAll, row) });
const removeEvidence = (s, row) => ({ ...s, env: envRemove(s.env, row) });
// a seeded state starts a new origin for the fold theorems
function seed(s, state) {
  const bad = validateState(state); if (bad) throw new Error('seed: ' + bad);
  const registry = stateKind(state) !== 'absent' && !s.registry.includes(s.aid) ? [...s.registry, s.aid] : s.registry;
  return { ...s, state, origin: state, originSlot: s.now, history: [], registry };
}
function setSlot(s, slot) {
  if (!isNat(slot)) return { ok: false, reason: 'invalid-nat' };
  if (slot < s.now) return { ok: false, reason: 'slot-regression' };
  return { ok: true, session: { ...s, now: slot } };
}
// attempt(session, action, slot) → {session, record}; the record carries the
// theorem report computed against the session it was attempted in
// attempt(session, action, slot, aid?) → {session, record}: one SysStep for
// `aid` (default: the played AID). Registration needs the AID absent from the
// registry (mint-once, SysStep.register's habs) and the state-level step.
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
    // SysStep.register also needs the AID absent from the registry (habs); for a
    // consistent system the state guard refuses first, so this only fires on a
    // registry that lists an absent AID
    if (res.ok && kind === 'register' && s.registry.includes(aid)) res = { ok: false, reason: 'aid-already-registered' };
  }
  record.ok = res.ok;
  if (res.ok) { record.flow = res.flow; record.state = res.state; }
  else { record.reason = res.reason; if (res.field) record.field = res.field; record.state = pre; }
  record.stepped = res.reason !== 'slot-regression' && res.reason !== 'aid-already-registered' && !(res.reason === 'invalid-nat' && res.field === 'slot');
  const now = record.stepped ? Math.max(s.now, slot) : s.now;
  const mine = aid === s.aid;
  const history = res.ok && mine ? [...s.history, [slot, action]] : s.history;
  const registry = res.ok && kind === 'register' ? [...s.registry, aid] : s.registry;
  const next = { ...s, now, history, registry,
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
  anyone: { name: 'Anyone', role: 'a relayer, a friend, a stranger', addr: 6, blurb: 'Whoever relays a public event, tops up a pool, or registers a public inception.' },
};
const whoAddr = addr => Object.values(CAST).find(c => c.addr === addr) || { name: 'address ' + addr };
const STATE_WORDS = {
  absent: 'Absent', live: 'Live', poisoned: 'Poisoned', paused: 'Paused', frozen: 'Frozen', convicted: 'Convicted', gone: 'Gone',
};
// the story's state table, read off the datum
function stateWord(p, s) {
  const k = stateKind(s);
  if (k !== 'present') return k;
  const l = liveOf(s);
  if (l.dreg !== p.D) return 'paused';
  if (l.b !== p.B) return 'frozen';
  if (l.poisoned) return 'poisoned';
  return 'live';
}
const VERDICT_WORDS = {
  consumable: 'Consumable: both bonds full, not poisoned, past the juvenility window.',
  'not-present': 'Not consumable: there is no live checkpoint to read.',
  'dreg-missing': 'Not consumable: the conviction bond is missing (paused).',
  'b-missing': 'Not consumable: the freeze bond is missing (frozen).',
  poisoned: 'Not consumable: the current keys are declared poisoned.',
  juvenile: 'Not consumable yet: juvenile, born too recently.',
};
// every refusal in the story's words, with the numbers that decided it
function explain(rec, s) {
  const p = s.params, a = rec.action;
  const l = liveOf(rec.pre) || { epoch: '?', sn: '?', pool: '?', b: '?', dreg: '?' };
  const d = (a && typeof a === 'object') ? a[Object.keys(a)[0]] : {};
  switch (rec.reason) {
    case 'invalid-params': return 'The deployment parameters are refused: both bonds must be positive, or "bond missing" could not be told from "bond full".';
    case 'invalid-nat': return (rec.field === 'pool' || rec.field === 'epoch')
      ? `The resulting ${rec.field} would exceed 2^53 − 1, the largest whole number this simulator represents exactly; the Lean's Nat is unbounded, so the step is refused rather than rounded.`
      : `"${rec.field}" must be a non-negative whole number at most 2^53 − 1: lovelace, slots and sequence numbers do not go negative, fractional or beyond what is represented exactly.`;
    case 'aid-already-registered': return 'This AID is in the registry already: the token is minted once, ever, whatever its state.';
    case 'invalid-action': return 'The validator does not know this redeemer; only register, rotate, poison, freeze, top-up, convict and close exist.';
    case 'gone-terminal': return 'Gone is terminal: the token was burned and the registry row stays, so this AID can never be registered on Cardano again.';
    case 'convicted-terminal': return 'Convicted is terminal: no rotation, no poison, no close, ever. No KERI event un-duplicates an identifier.';
    case 'absent-needs-register': return 'Nothing is on chain for this AID. The only thing that can happen first is a registration.';
    case 'already-present': return 'This AID already has its checkpoint. The token is minted once, ever.';
    case 'no-witnessed-rotation': return `No witnessed rotation from epoch ${l.epoch} at sequence ${l.sn} to sequence ${d["sn'"]} was presented: signatures at the current threshold, revealed keys matching the pre-committed digests, receipts from the witnesses.`;
    case 'sequence-not-later': return `The presented rotation is at sequence ${d["sn'"]}, not later than the checkpoint’s ${l.sn}: the checkpoint cannot roll back.`;
    case 'refund-not-authorized': return `The new keys (epoch ${l.epoch + 1}) did not sign refund address ${d["refund'"]}. A relayer cannot move where the money goes.`;
    case 'bond-over-full': return `The datum claims more than a full bond (conviction ${l.dreg} of ${p.D}, freeze ${l.b} of ${p.B}); a depositing rotation refuses it. No chain state reaches this.`;
    case 'no-quorum': return `The current keys of epoch ${l.epoch} did not sign at their threshold. Keys of a retired epoch count for nothing.`;
    case 'already-poisoned': return 'This epoch is already poisoned; the poison is declared once per epoch and only a rotation clears it.';
    case 'poisoned': return rec.kind === 'freeze'
      ? 'A poisoned checkpoint cannot be frozen: it is already unconsumable, there is nothing to freeze.'
      : 'Close is disabled while poisoned: whoever holds the current keys cannot take the bonds. The only way out is a rotation.';
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
    lean: ['T1_sn_monotone', 'T1_rotate_strict', 'T1_trace_sn_monotone'],
    plain: 'No step between live states decreases the sequence number, and every rotation strictly increases it; along any trace the sequence never goes down.' },
  { id: 'T2', title: 'Keys change only by rotation',
    lean: ['T2_epoch_only_by_rotation'],
    plain: 'The key epoch changes only under a rotation, authorized by the next keys, and then by exactly one.' },
  { id: 'T3', title: 'Poison is local to one epoch',
    lean: ['T3_rotation_clears', 'T3_only_rotation_clears', 'T3_only_poison_sets', 'T3_epoch_local'],
    plain: 'A rotation always yields an unpoisoned state; only a rotation clears the poison; only the poison sets it, from a clean state, changing nothing else and moving no value; along any play the checkpoint is poisoned exactly when the last epoch-relevant action was a poison.' },
  { id: 'T4', title: 'Poisoned keys can only be rotated',
    lean: ['T4_poisoned_blocks_quorum_and_freeze', 'T4_poisoned_nonrotation_inert'],
    plain: 'From a poisoned state the current quorum can do nothing (no close, no second poison) and no proof can freeze it; nothing but a rotation yields a consumable state.' },
  { id: 'T5', title: 'Every ruled transition is enabled when its evidence is',
    lean: ['T5_every_bond_option', 'T5_poison_enabled', 'T5_freeze_enabled', 'T5_convict_enabled', 'T5_close_enabled'],
    plain: 'Given a valid witnessed rotation every bond option is enabled whatever the pool holds (payment is never a gate); given the quorum an unpoisoned state can be poisoned or closed; given a later rotation, a short pool, a full freeze bond and no poison the freeze is enabled; given a duplicity proof conviction is enabled from every live state.' },
  { id: 'T6', title: 'Three value components that never mix',
    lean: ['T6_component_conservation', 'T6_dreg_never_a_fee', 'T6_dreg_increases_only_by_deposit', 'T6_refund_change_requires_new_keys', 'T6_bonds_move_only_by_rotation_or_freeze'],
    plain: 'For each of the conviction bond, the freeze bond and the pool: held plus in equals held after plus out. The conviction bond is never a fee: no hunter payment carries it and it leaves only whole, to the refund address or to the convictor; it re-enters only by a depositing rotation. The refund address changes only under a rotation whose new keys authorized it. Poison and top-up move no bond.' },
  { id: 'T7', title: 'The state is the fold of the accepted actions',
    lean: ['T7_step_iff_stepFn', 'T7_trace_iff_replay'],
    plain: 'The transition relation and the functional step agree exactly, and a trace is exactly a successful replay: replaying every accepted action from the origin reproduces the current state.' },
  { id: 'T8', title: 'One incarnation per AID, ever',
    lean: ['T8_gone_terminal', 'T8_absent_only_registers', 'T8_registry_nodup', 'T8_registry_monotone', 'T8_present_implies_registered'],
    plain: 'No step leaves Gone; registration is the only step from Absent; the registry never holds an AID twice and only grows; every AID with a state other than Absent is in the registry.' },
  { id: 'T9', title: 'Juvenility is consumer policy',
    lean: ['T9_juvenility_is_consumer_only'],
    plain: 'No transition depends on the window W: the same action from the same state is accepted or refused identically under any W.' },
  { id: 'T10', title: 'An unbonded or frozen checkpoint is inert to everyone but the next keys',
    lean: ['T10_inert_without_next_keys', 'T10_only_deposit_restores', 'T10_current_quorum_never_restores'],
    plain: 'If either bond is missing, no step by anyone but the next keys yields a consumable state; only a depositing rotation restores consumability, and it restarts juvenility; the current quorum never produces a consumable state.' },
  { id: 'T12', title: 'Conviction needs a proof and is exact',
    lean: ['T12_convicted_terminal', 'T12_convict_exact'],
    plain: 'No step leaves Convicted. Only a conviction reaches it, only with a duplicity proof; the tombstone records the tip’s epoch and sequence and the slot; the flow is exactly the conviction bond to the convictor and the rest to the refund address.' },
  { id: 'T14', title: 'The pool moves only by premium, withdrawal or top-up',
    lean: ['T14_pool_decreases_only_by_premium', 'T14_pool_increases_only_by_topup'],
    plain: 'The pool decreases only by the premium under a paid rotation or to zero under a withdrawing rotation, and increases only by a top-up that changes nothing else.' },
  { id: 'T15', title: 'The freeze bond leaves only by freeze or withdrawal',
    lean: ['T15_b_leaves_only_by_freeze_or_withdraw', 'T15_b_returns_only_by_deposit', 'T15_freeze_makes_inert'],
    plain: 'The freeze bond leaves a live state only by a freeze (a later rotation presented, pool short, exactly B to the hunter, datum otherwise untouched) or by a withdrawing rotation; it returns only by a depositing rotation, to full; a freeze makes the checkpoint unconsumable.' },
  { id: 'T16', title: 'The closer chooses when, never where',
    lean: ['T16_close_destination', 'T16_withdraw_destination', 'T16_payments_are_named'],
    plain: 'Close pays everything to the refund address in the datum, only from an unpoisoned state under the quorum; a withdrawing rotation pays everything to the refund address it results in; a hunter is paid only the premium or the freeze bond, a convictor only the conviction bond.' },
];

// ---- the Lean oracle: cells of the embedded corpus, keyed by what stepFn reads
// A step is identified by (params, slot, input state, action) and the values
// of the evidence predicates stepFn consults for it; two Env tables that agree
// on those are the same oracle for that step.
function evidenceBits(env, state, action) {
  const l = liveOf(state); if (!l) return [];
  const k = actionKind(action); const d = (action && typeof action === 'object') ? action[k] : {};
  switch (k) {
    case 'rotate': return [envRotationTo(env, l.epoch, l.sn, d["sn'"]), d["refund'"] === null || d["refund'"] === undefined ? null : envRefundAuthorized(env, natAdd(l.epoch, 1), d["refund'"])];
    case 'freeze': return [envRotationTo(env, l.epoch, l.sn, d["sn'"])];
    case 'poison': case 'close': return [envQuorum(env, l.epoch)];
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
  const pp = stateKind(pre) === 'present' && stateKind(post) === 'present';
  const a = rec.action, d = (a && typeof a === 'object') ? a[Object.keys(a)[0]] : {};
  const f = rec.flow;
  const out = {};
  const put = (id, exhibited, checks) => {
    const notes = exhibited ? checks().filter(c => !c[0]).map(c => c[1]) : [];
    out[id] = { exhibited: !!exhibited, holds: !exhibited || !notes.length, notes };
  };
  const eq = (x, y) => canon(x) === canon(y);

  // T1: present→present steps keep sn; rotations increase it strictly
  put('T1', ok && pp, () => [
    [lp && lq && lp.sn <= lq.sn, 'sequence decreased'],
    [kind !== 'rotate' || (lp.sn < lq.sn), 'rotation did not increase the sequence'],
  ]);
  // T2: epoch changed ⇒ rotation by the next keys, +1
  put('T2', ok && pp && lq.epoch !== lp.epoch, () => [
    [actor === 'nextKeys', 'epoch changed without the next keys'],
    [lq.epoch === lp.epoch + 1, 'epoch did not move by one'],
  ]);
  // T3: poison is epoch-local
  const t3ex = ok && stateKind(post) === 'present' && (kind === 'rotate' || kind === 'poison' || (lp && lp.poisoned !== lq.poisoned));
  put('T3', t3ex, () => [
    [kind !== 'rotate' || lq.poisoned === false, 'rotation left the poison'],
    [!(lp && lp.poisoned && !lq.poisoned) || actor === 'nextKeys', 'poison cleared by something else than a rotation'],
    [!(lp && !lp.poisoned && lq.poisoned) || (kind === 'poison' && eq(lq, { ...lp, poisoned: true }) && eq(f, flow({}))), 'poison set by something else, or it changed more than the bit'],
    [rec.aid !== after.aid || lq.poisoned === poisonAfter(liveOf(after.origin) ? liveOf(after.origin).poisoned : false, after.history), 'poison bit is not the fold of the actions'],
  ]);
  // T4: from a poisoned state
  const quorumOrFreeze = actor === 'currentQuorum' || kind === 'freeze';
  put('T4', !!lp && lp.poisoned && (ok || quorumOrFreeze), () => [
    [!ok || !quorumOrFreeze, 'the current quorum acted, or a freeze landed, on a poisoned checkpoint'],
    [!ok || actor === 'nextKeys' || !consumableEver(p, post), 'a non-rotation made a poisoned checkpoint consumable'],
  ]);
  // T5: totality — the evidence antecedent held ⇒ the step is accepted
  let ante = false;
  if (rec.stepped && stateKind(pre) === 'present') {
    const l = lp;
    if (kind === 'rotate') ante = envRotationTo(env, l.epoch, l.sn, d["sn'"]) && l.sn < d["sn'"] &&
      (d["refund'"] === null || d["refund'"] === undefined || envRefundAuthorized(env, l.epoch + 1, d["refund'"])) &&
      (d.op !== 'deposit' || (l.dreg <= p.D && l.b <= p.B));
    else if (kind === 'poison') ante = envQuorum(env, l.epoch) && !l.poisoned;
    else if (kind === 'freeze') ante = envRotationTo(env, l.epoch, l.sn, d["sn'"]) && l.sn < d["sn'"] && l.pool < p.P && l.b === p.B && !l.poisoned;
    else if (kind === 'convict') ante = envDuplicityAt(env, l.epoch, l.sn);
    else if (kind === 'close') ante = envQuorum(env, l.epoch) && !l.poisoned;
    else if (kind === 'topUp') ante = true;
    if (ante && validateParams(p)) ante = false;
    if (ante && !normalizeAction(a).ok) ante = false;
  } else if (rec.stepped && stateKind(pre) === 'absent' && kind === 'register' && !validateParams(p) && normalizeAction(a).ok) ante = true;
  put('T5', ante, () => [[ok, 'evidence held but the step was refused: ' + rec.reason]]);
  // T6: value
  if (ok) {
    const hi = held(pre), ho = held(post);
    const pr = paid(f.refund), ph = paid(f.hunter), pc = paid(f.convictor);
    const dregOk = big(hi.dreg) + big(f.dregIn) === big(ho.dreg) + big(pr.dreg) + big(ph.dreg) + big(pc.dreg);
    const bOk = big(hi.b) + big(f.bIn) === big(ho.b) + big(pr.b) + big(ph.b) + big(pc.b);
    const poolOk = big(held(pre).pool) + big(f.poolIn) === big(ho.pool) + big(pr.pool) + big(ph.pool) + big(pc.pool);
    put('T6', true, () => [
      [dregOk, 'conviction bond not conserved'], [bOk, 'freeze bond not conserved'], [poolOk, 'pool not conserved'],
      [ph.dreg === 0, 'a hunter was paid from the conviction bond'],
      [pr.dreg === 0 || (pr.dreg === hi.dreg && ho.dreg === 0), 'the conviction bond left partially to the refund address'],
      [pc.dreg === 0 || (pc.dreg === hi.dreg && stateKind(post) === 'convicted'), 'the conviction bond went to a convictor without a conviction'],
      [!pp || !(lp.dreg < lq.dreg) || (kind === 'rotate' && d.op === 'deposit' && lq.dreg === p.D && lq.b === p.B && f.dregIn === p.D - lp.dreg && f.bIn === p.B - lp.b && lq.bornAt === rec.slot), 'the conviction bond increased other than by a full deposit'],
      [!pp || lq.refundTo === lp.refundTo || (actor === 'nextKeys' && envRefundAuthorized(env, lq.epoch, lq.refundTo)), 'the refund address moved without the new keys’ authorization'],
      [!pp || (lq.dreg === lp.dreg && lq.b === lp.b) || actor === 'nextKeys' || kind === 'freeze', 'a bond moved under poison or top-up'],
    ]);
  } else put('T6', false, () => []);
  // T7: parity with the Lean — the step has a cell in the embedded corpus and the
  // core's verdict, flow and post-state equal Lean's (both directions of
  // T7_step_iff_stepFn); plus the fold (T7_trace_iff_replay) on accepted steps
  const cell = rec.stepped ? leanCell(before.corpus, p, rec.slot, pre, a, env) : undefined;
  if (cell !== undefined) {
    put('T7', true, () => [
      [(cell.result === null) === !ok, 'Lean ' + (cell.result === null ? 'refuses' : 'applies') + ' this step (' + cell.where + '), the core ' + (ok ? 'applied' : 'refused: ' + rec.reason)],
      [!ok || cell.result === null || eq(f, cell.result.flow), 'flow differs from Lean (' + cell.where + ')'],
      [!ok || cell.result === null || eq(post, cell.result.state), 'post-state differs from Lean (' + cell.where + ')'],
      [!ok || rec.aid !== after.aid || (() => { const rp = replay(p, after.envAll, after.originSlot, after.origin, after.history); return rp.ok && eq(rp.state, post); })(), 'replay of the accepted actions does not reproduce the state'],
    ]);
    out.T7.cell = cell.where;
  } else { put('T7', false, () => []); out.T7.cell = null; out.T7.notes = rec.stepped ? ['no Lean cell for this step: T7 not shown'] : []; }
  // T8: terminals, absent-only-registers, registry
  const preK = stateKind(pre);
  // T8: the registry on every system transition (monotone, no duplicates, every
  // non-absent AID registered), terminals, absent-only-registers, mint-once
  put('T8', ok || preK === 'gone' || preK === 'convicted' || preK === 'absent' || kind === 'register', () => [
    [!(preK === 'gone' || preK === 'convicted') || !ok, 'a step left a terminal state'],
    [preK !== 'absent' || (ok === (kind === 'register' && rec.stepped && !before.registry.includes(rec.aid) && !validateParams(p) && normalizeAction(a).ok)), 'from absent, something other than a registration happened, or a registration was refused without cause'],
    [kind !== 'register' || !ok || (preK === 'absent' && !before.registry.includes(rec.aid)), 'a registration landed on a non-absent or already registered AID'],
    [before.registry.every(x => after.registry.includes(x)), 'the registry lost an AID (T8_registry_monotone)'],
    [new Set(after.registry).size === after.registry.length, 'registry holds a duplicate (T8_registry_nodup)'],
    [allAids(after).every(x => stateKind(stateOfAid(after, x)) === 'absent' || after.registry.includes(x)), 'a non-absent AID is not in the registry (T8_present_implies_registered)'],
    [after.registry.length === before.registry.length + (ok && kind === 'register' ? 1 : 0), 'the registry changed other than by this registration'],
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
  // T10: bonds missing, or the current quorum acted
  const missing = !!lp && (lp.dreg !== p.D || lp.b !== p.B);
  put('T10', ok && ((missing) || actor === 'currentQuorum'), () => [
    [!missing || actor === 'nextKeys' || !consumableEver(p, post), 'someone but the next keys made an unbonded checkpoint consumable'],
    [!missing || !consumableEver(p, post) || (kind === 'rotate' && d.op === 'deposit' && lq && lq.dreg === p.D && lq.b === p.B && lq.bornAt === rec.slot), 'consumability restored other than by a depositing rotation with restarted juvenility'],
    [actor !== 'currentQuorum' || !consumableEver(p, post), 'the current quorum produced a consumable state'],
  ]);
  // T12: conviction
  put('T12', kind === 'convict' || preK === 'convicted', () => [
    [preK !== 'convicted' || !ok, 'a step left Convicted'],
    [kind !== 'convict' || preK !== 'present' || !rec.stepped || (ok === envDuplicityAt(env, lp.epoch, lp.sn)), 'conviction accepted without a proof, or refused with one'],
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
  // T16: destinations
  put('T16', ok && (stateKind(post) === 'gone' || (kind === 'rotate' && d.op === 'withdraw') || f.hunter !== null || f.convictor !== null), () => [
    [stateKind(post) !== 'gone' || (kind === 'close' && eq(f, flow({ refund: payment(lp.refundTo, lp.dreg, lp.b, lp.pool) })) && !lp.poisoned && envQuorum(env, lp.epoch)), 'Gone reached other than by a close paying everything to the datum’s refund address from an unpoisoned state under the quorum'],
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
// checkScenario(scenario, label) → {problems, stepsRun, asserted, exhibited, timeline}
// timeline: one entry per scenario step with the session after it and the record (if any)
function checkScenario(sc, label, corpus) {
  const problems = [], asserted = [], exhibited = new Set(), timeline = [];
  let session = newSession(sc.params, { corpus: corpus || null }), stepsRun = 0;
  (sc.steps || []).forEach((st, i) => {
    const where = label + ' step ' + i;
    const saved = session.params;
    if (st.params) session = withParams(session, st.params);
    if (st.seed !== undefined) session = seed(session, st.seed);
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
    timeline.push({ step: st, session, record });
  });
  return { problems, stepsRun, asserted, exhibited: [...exhibited], timeline };
}
// checkCorpus(corpus) → {applied, refused, cons, theoremChecks, reasons}: every
// step of the Lean corpus (applied and refused) must agree with step(); every
// applied step must satisfy every theorem
function checkCorpus(corpus) {
  const reasons = [];
  let applied = 0, refused = 0, theoremChecks = 0, cons = 0;
  const p = corpus.params;
  const pv = validateParams(p); if (pv) reasons.push('corpus params invalid: ' + pv);
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
  canon, isNat, REASONS, VERDICTS, validateParams, ACTION_KINDS, BOND_OPS, actionKind, normalizeAction, actorOf,
  EV_KINDS, emptyEnv, envHas, envAdd, envRemove, envUnion, stateKind, liveOf, present, payment, flow, held, paid,
  validateState, step, consumable, consumableEver, replay, poisonAfter, poisonSinceLastRotation,
  newSession, withParams, addEvidence, removeEvidence, seed, seedOther, stateOfAid, allAids, setSlot, attempt, heldSoFar,
  MAX_NAT, natAdd, parseNat, lossyJsonNumbers, parseJsonExact, evidenceBits, cellKey, leanCell,
  CAST, whoAddr, STATE_WORDS, stateWord, VERDICT_WORDS, explain, THEOREMS, theoremReport,
  matchesPartial, checkScenario, checkCorpus,
};
