/*
 * checkpoint-simulator-core.mjs — the pure core of the M1 checkpoint
 * simulator: a JavaScript transcription of `stepFn`, `replay` and
 * `consumableStateB` (the decidable mirror of `consumableState`) from
 * lean/CardanoKeri/Checkpoint.lean, and the
 * theorems of lean/CardanoKeri/CheckpointGoals.lean as executable properties
 * over steps and traces — one checker row per Lean declaration, keyed by its
 * name, folded into fourteen lamps for the page.
 *
 * Third slice (D-039, D-040): an identity is active (the UTxO: live, poisoned
 * or frozen), parked (no UTxO; the leaf holds the hash of the last checkpoint
 * — its key state) or convicted (the mark). No withdraw, no unbonded state:
 * a present checkpoint always holds the conviction bond; the freeze bond is
 * held unless frozen. The close is the reap: a witnessed rotation whose new
 * keys sign the close intent naming the payee of the premium and the refund
 * address; everything else goes to the refund address, the leaf is parked
 * with the hash. The reopen is the revival from the parked key state.
 *
 * No DOM, no storage, no clock. Evidence (the Lean `Env`) is a table of
 * decisions supplied by the scenario or by the person playing; the core
 * never decides evidence. Every Nat-typed field is a non-negative integer
 * or the action is refused by name.
 *
 * JSON shapes follow Lean's derived `ToJson` exactly, so the corpus the
 * Lean driver emits is compared byte-for-byte after key sorting:
 *   state   'absent' | {present:{l:{sn,epoch,poisoned,frozen,bornAt,refundTo,pool}}}
 *           | {parked:{h:{epoch,sn}}} | 'convicted'
 *   action  {register:{refund,pool0}} | {rotate:{"sn'",op,payee,"refund'"}} | 'poison'
 *           | {freeze:{"sn'",payee}} | {topUp:{x}} | {convict:{payee}} | {close:{"sn'",payee,"refund'"}} | {reopen:{"sn'",refund,pool0}}
 *   intent  'keep' | 'deposit' | {close:{payee}}
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
  'convicted-terminal', 'parked-inert', 'reopen-needs-parked', 'absent-needs-register', 'already-present',
  'no-witnessed-rotation', 'sequence-not-later', 'intent-not-authorized',
  'no-quorum', 'already-poisoned', 'poisoned', 'pool-covers-premium', 'freeze-bond-missing',
  'no-duplicity-proof', 'slot-regression', 'aid-already-registered', 'leaf-not-parked',
];
// the consumer's verdicts; the last three are boundary refusals (a consumer
// reading a non-state or under non-params decides nothing)
const VERDICTS = ['consumable', 'not-present', 'frozen', 'poisoned', 'juvenile', 'invalid-params', 'invalid-nat', 'invalid-state'];

// ---- the Lean guards behind the refusal names ------------------------------
// Each refusal name stands for the hypothesis binder(s) of the `Step`
// constructors it refuses on (Checkpoint.lean), or for the absence of any
// constructor (stepFn's fall-through, made exact by T7). The scenario gate
// reconciles this table with the Lean source: every `h`-binder of every Step
// constructor must be claimed here (or by SPLITS), and every claim must exist
// with its text inside that constructor. The naming is the simulator's; the
// binders are the Lean's.
const ROTATES = ['Step.rotateKeepPaid', 'Step.rotateKeepUnpaid', 'Step.rotateDepositPaid', 'Step.rotateDepositUnpaid'];
const CLOSES = ['Step.closePaid', 'Step.closeUnpaid'];
const LEAN_GUARDS = {
  'no-witnessed-rotation': { decls: [...ROTATES, 'Step.freeze', ...CLOSES, 'Step.reopen'], hyp: 'hev', text: 'env.rotationTo' },
  'sequence-not-later': { decls: [...ROTATES, 'Step.freeze', ...CLOSES, 'Step.reopen'], hyp: 'hsn', text: "< sn'" },
  'intent-not-authorized': { decls: [...ROTATES, ...CLOSES], hyp: 'hauth', text: 'env.intentOk (l.epoch + 1)' },
  'no-quorum': { decls: ['Step.poison'], hyp: 'hq', text: 'env.quorum l.epoch = true' },
  'already-poisoned': { decls: ['Step.poison'], hyp: 'hclean', text: 'l.poisoned = false' },
  'poisoned': { decls: ['Step.freeze'], hyp: 'hclean', text: 'l.poisoned = false' },
  'pool-covers-premium': { decls: ['Step.freeze'], hyp: 'hpool', text: 'l.pool < p.P' },
  'freeze-bond-missing': { decls: ['Step.freeze'], hyp: 'hb', text: 'l.frozen = false' },
  'no-duplicity-proof': { decls: ['Step.convict', 'Step.convictParked'], hyp: 'hdup', text: 'env.duplicityAt' },
  'aid-already-registered': { decls: ['SysStep.register'], hyp: 'habs', text: 's.leaves aid = .absent' },
  'leaf-not-parked': { decls: ['SysStep.reopen'], hyp: 'hparked', text: 's.leaves aid = .parked h' },
  'slot-regression': { decls: ['Trace.cons'], hyp: 'hle', text: "t ≤ t'" },
  // no constructor has the (action, state): stepFn's fall-through, the theorem names it
  'convicted-terminal': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T12_convicted_terminal' },
  'parked-inert': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_parked_only_revives_or_convicts' },
  'reopen-needs-parked': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_absent_only_registers' },
  'absent-needs-register': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_absent_only_registers' },
  'already-present': { decls: ['stepFn'], text: '| _, _ => none', theorem: 'T8_mint_once' },
  // the two proof fields of Params
  'invalid-params': { decls: ['Params'], hyps: [['hD', '0 < D'], ['hB', '0 < B']] },
  // the simulator's own boundary (a Lean Nat is unbounded; a Lean value has its type)
  'invalid-nat': { decls: [] }, 'invalid-action': { decls: [] }, 'invalid-state': { decls: [] }, 'invalid-evidence': { decls: [] },
};
// guard hypotheses that are not refusals: the paid / unpaid split of a keep, a deposit and a close
const LEAN_SPLITS = [
  { decl: 'Step.rotateKeepPaid', hyp: 'hpay', text: 'p.P ≤ l.pool' },
  { decl: 'Step.rotateKeepUnpaid', hyp: 'hnopay', text: 'l.pool < p.P' },
  { decl: 'Step.rotateDepositPaid', hyp: 'hpay', text: 'p.P ≤ l.pool' },
  { decl: 'Step.rotateDepositUnpaid', hyp: 'hnopay', text: 'l.pool < p.P' },
  { decl: 'Step.closePaid', hyp: 'hpay', text: 'p.P ≤ l.pool' },
  { decl: 'Step.closeUnpaid', hyp: 'hnopay', text: 'l.pool < p.P' },
];
// the conjunct of consumableState each verdict names
const VERDICT_CONJUNCTS = {
  'not-present': ['| .present l =>', '| _ => False'], frozen: ['l.frozen = false'],
  poisoned: ['l.poisoned = false'], juvenile: ['l.bornAt + p.W ≤ now'],
};
// the Step constructor an accepted record went through (the paid/unpaid split is
// visible in the flow), or null for a refused / non-transition record
function constructorOf(rec) {
  if (!rec || !rec.ok) return null;
  const d = (rec.action && typeof rec.action === 'object') ? rec.action[rec.kind] : {};
  const paidBy = rec.flow && rec.flow.hunter && rec.flow.hunter.pool > 0;
  switch (rec.kind) {
    case 'register': return 'Step.register';
    case 'rotate': return d.op === 'deposit' ? (paidBy ? 'Step.rotateDepositPaid' : 'Step.rotateDepositUnpaid') : (paidBy ? 'Step.rotateKeepPaid' : 'Step.rotateKeepUnpaid');
    case 'poison': return 'Step.poison';
    case 'freeze': return 'Step.freeze';
    case 'topUp': return 'Step.topUp';
    case 'convict': return stateKind(rec.pre) === 'parked' ? 'Step.convictParked' : 'Step.convict';
    case 'close': return paidBy ? 'Step.closePaid' : 'Step.closeUnpaid';
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
const BOND_OPS = ['keep', 'deposit'];
// what the new keys sign along with the refund address (D-038): a bond option,
// or the close naming its payee (D-039): 'keep' | 'deposit' | {close:{payee}}
const INTENT_KINDS = ['keep', 'deposit', 'close'];
const intentKind = i => (i === 'keep' || i === 'deposit') ? i : (i && typeof i === 'object' && !Array.isArray(i) && Object.keys(i).length === 1 && i.close && typeof i.close === 'object' && !Array.isArray(i.close) && Object.keys(i.close).length === 1 && isNat(i.close.payee)) ? 'close' : null;
const closeIntent = payee => ({ close: { payee } });

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
      const e = bad([d["sn'"], "sn'"], [d.payee, 'payee']); if (e) return e;
      const o = optAddr(d["refund'"], "refund'"); if (o.ok === false) return o;
      return { ok: true, kind, action: { close: { "sn'": d["sn'"], payee: d.payee, "refund'": o.r } } };
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
const entryOk = (ty, v) => (ty === 'nat' ? isNat(v) : ty === 'intent' ? intentKind(v) !== null : (v === null || isNat(v)));
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
        if (!entryOk(ty, r[j])) return bad(ty === 'intent' ? 'invalid-evidence' : 'invalid-nat', `${k}[${i}][${j}]`, `${k}[${i}][${j}] is not ${ty === 'nat' ? 'a non-negative integer' : ty === 'intent' ? 'an intent (keep, deposit, or close with its payee)' : 'an address or null'}`);
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
const stateKind = s => (s === 'absent' || s === 'convicted') ? s : (s && s.present ? 'present' : (s && s.parked ? 'parked' : null));
const liveOf = s => (s && s.present ? s.present.l : null);
// the parked key state (the hash the leaf holds), or null
const hashOf = s => (s && s.parked ? s.parked.h : null);
const present = l => ({ present: { l } });
const parked = h => ({ parked: { h: { epoch: h.epoch, sn: h.sn } } });
const payment = (addr, dreg, b, pool) => ({ addr, dreg, b, pool });
const flow = f => Object.assign({ dregIn: 0, bIn: 0, poolIn: 0, refund: null, hunter: null, convictor: null }, f);
// Live.bHeld: B unless frozen
const bHeldOf = (p, l) => (l.frozen ? 0 : p.B);
// State.dregHeld / bHeld / poolHeld: a present checkpoint holds D always and B
// unless frozen; a parked or convicted state holds nothing (D-040)
const held = (p, s) => { const l = liveOf(s); return l ? { dreg: p.D, b: bHeldOf(p, l), pool: l.pool } : { dreg: 0, b: 0, pool: 0 }; };
// Payment?.dreg etc.
const paid = q => (q ? { dreg: q.dreg, b: q.b, pool: q.pool } : { dreg: 0, b: 0, pool: 0 });
// State.sn?: the sequence a state records, or null
const snOf = s => { const k = stateKind(s); const l = liveOf(s); return k === 'present' ? (l && typeof l === 'object' ? l.sn : null) : k === 'parked' ? (s.parked.h && s.parked.h.sn) : null; };
// Live.hash: the key state a present checkpoint records
const hashOfLive = l => ({ epoch: l.epoch, sn: l.sn });
// Live.rotated: the datum a rotation to sn' leaves before its bond option
const rotated = (p, l, sn2, r) => ({ ...l, sn: sn2, epoch: l.epoch + 1, poisoned: false, refundTo: r === null || r === undefined ? l.refundTo : r, pool: p.P <= l.pool ? l.pool - p.P : l.pool });
// Params.premium: P to the payee when the pool covers it, nothing otherwise
const premium = (p, l, payee) => (p.P <= l.pool ? payment(payee, 0, 0, p.P) : null);
// State.leaf: the registry leaf a state projects to (D-037, D-040): absent | active | {parked:{h}} | convicted
const leafOf = s => { const k = stateKind(s); return k === 'present' ? 'active' : k === 'parked' ? { parked: { h: { epoch: s.parked.h.epoch, sn: s.parked.h.sn } } } : k === 'convicted' ? 'convicted' : 'absent'; };
const leafKind = lf => (lf === 'absent' || lf === 'active' || lf === 'convicted') ? lf : (lf && lf.parked ? 'parked' : null);

const LIVE_NATS = ['sn', 'epoch', 'bornAt', 'refundTo', 'pool'];
const LIVE_BOOLS = ['poisoned', 'frozen'];
const LIVE_FIELDS = [...LIVE_NATS, ...LIVE_BOOLS];
const STATE_CTORS = ['present', 'parked'];
// validateState(s) → null | {reason, field, message}: the complete state — one
// of the four Lean shapes, exactly one constructor with nothing beside it,
// every Nat field a Nat, the two bits booleans, no field the Lean does not
// have — checked before anything reads it
function validateState(s) {
  const bad = (reason, field, message) => ({ reason, field, message });
  if (s === 'absent' || s === 'convicted') return null;
  if (!s || typeof s !== 'object' || Array.isArray(s)) return bad('invalid-state', 'state', 'unknown state shape');
  const keys = Object.keys(s);
  const stranger = keys.find(x => !STATE_CTORS.includes(x));
  if (stranger !== undefined) return bad('invalid-state', stranger, `${stranger} is not a constructor of State`);
  if (keys.length !== 1) return bad('invalid-state', keys.length ? keys[1] : 'state', keys.length ? `${keys[0]} and ${keys[1]} at once: a state is one constructor` : 'unknown state shape');
  const k = keys[0];
  if (k === 'present') {
    const w = s.present;
    if (!w || typeof w !== 'object' || Array.isArray(w)) return bad('invalid-state', 'present', 'present without a datum');
    for (const f of Object.keys(w)) if (f !== 'l') return bad('invalid-state', 'present.' + f, `present.${f} is not a field of present (only l)`);
    const l = w.l;
    if (!l || typeof l !== 'object' || Array.isArray(l)) return bad('invalid-state', 'l', 'present without a datum');
    for (const f of LIVE_NATS) if (!isNat(l[f])) return bad('invalid-nat', f, `${f} is not a non-negative integer`);
    for (const f of LIVE_BOOLS) if (typeof l[f] !== 'boolean') return bad('invalid-state', f, `${f} is not a boolean`);
    for (const f of Object.keys(l)) if (!LIVE_FIELDS.includes(f)) return bad('invalid-state', f, `${f} is not a field of the datum`);
    return null;
  }
  const w = s.parked;
  if (!w || typeof w !== 'object' || Array.isArray(w)) return bad('invalid-state', 'parked', 'parked without its hash');
  for (const f of Object.keys(w)) if (f !== 'h') return bad('invalid-state', 'parked.' + f, `parked.${f} is not a field of parked (only h)`);
  const hh = w.h;
  if (!hh || typeof hh !== 'object' || Array.isArray(hh)) return bad('invalid-state', 'h', 'parked without its hash');
  for (const f of ['epoch', 'sn']) if (!isNat(hh[f])) return bad('invalid-nat', f, `${f} is not a non-negative integer`);
  for (const f of Object.keys(hh)) if (!['epoch', 'sn'].includes(f)) return bad('invalid-state', f, `${f} is not a field of the key state`);
  return null;
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
  if (sk === 'parked') {
    const hh = state.parked.h;
    if (kind === 'convict') {
      if (!envDuplicityAt(env, hh.epoch, hh.sn)) return refuse('no-duplicity-proof');
      return some({}, 'convicted');
    }
    if (kind !== 'reopen') return refuse('parked-inert');
    const { "sn'": sn2, refund, pool0 } = a.reopen;
    if (!envRotationTo(env, hh.epoch, hh.sn, sn2)) return refuse('no-witnessed-rotation');
    if (!(hh.sn < sn2)) return refuse('sequence-not-later');
    const epoch2 = natAdd(hh.epoch, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
    return some({ dregIn: p.D, bIn: p.B, poolIn: pool0 },
      present({ sn: sn2, epoch: epoch2, poisoned: false, frozen: false, bornAt: now, refundTo: refund, pool: pool0 }));
  }
  if (sk === 'absent') {
    if (kind !== 'register') return refuse('absent-needs-register');
    const { refund, pool0 } = a.register;
    return some({ dregIn: p.D, bIn: p.B, poolIn: pool0 },
      present({ sn: 0, epoch: 0, poisoned: false, frozen: false, bornAt: now, refundTo: refund, pool: pool0 }));
  }
  const l = state.present.l;
  switch (kind) {
    case 'register': return refuse('already-present');
    case 'reopen': return refuse('reopen-needs-parked');
    case 'rotate': {
      const { "sn'": sn2, op, payee, "refund'": r } = a.rotate;
      if (!envRotationTo(env, l.epoch, l.sn, sn2)) return refuse('no-witnessed-rotation');
      if (!(l.sn < sn2)) return refuse('sequence-not-later');
      const epoch2 = natAdd(l.epoch, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
      if (!intentOk(env, epoch2, op, r)) return refuse('intent-not-authorized');
      const r2 = r === null ? l.refundTo : r;
      const next = { ...l, sn: sn2, epoch: epoch2, poisoned: false, refundTo: r2 };
      const bIn = op === 'deposit' ? p.B - bHeldOf(p, l) : 0;
      if (op === 'deposit') next.frozen = false;
      if (p.P <= l.pool) return some({ bIn, hunter: payment(payee, 0, 0, p.P) }, present({ ...next, pool: l.pool - p.P }));
      return some({ bIn }, present(next));
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
      if (l.frozen) return refuse('freeze-bond-missing');
      if (l.poisoned) return refuse('poisoned');
      return some({ hunter: payment(payee, 0, p.B, 0) }, present({ ...l, frozen: true }));
    }
    case 'topUp': {
      const pool2 = natAdd(l.pool, a.topUp.x); if (pool2 === null) return refuse('invalid-nat', 'pool');
      return some({ poolIn: a.topUp.x }, present({ ...l, pool: pool2 }));
    }
    case 'convict': {
      if (!envDuplicityAt(env, l.epoch, l.sn)) return refuse('no-duplicity-proof');
      return some({ refund: payment(l.refundTo, 0, bHeldOf(p, l), l.pool), convictor: payment(a.convict.payee, p.D, 0, 0) }, 'convicted');
    }
    case 'close': {
      const { "sn'": sn2, payee, "refund'": r } = a.close;
      if (!envRotationTo(env, l.epoch, l.sn, sn2)) return refuse('no-witnessed-rotation');
      if (!(l.sn < sn2)) return refuse('sequence-not-later');
      const epoch2 = natAdd(l.epoch, 1); if (epoch2 === null) return refuse('invalid-nat', 'epoch');
      if (!intentOk(env, epoch2, closeIntent(payee), r)) return refuse('intent-not-authorized');
      const r2 = r === null ? l.refundTo : r;
      if (p.P <= l.pool) return some({ refund: payment(r2, p.D, bHeldOf(p, l), l.pool - p.P), hunter: payment(payee, 0, 0, p.P) }, parked({ epoch: epoch2, sn: sn2 }));
      return some({ refund: payment(r2, p.D, bHeldOf(p, l), l.pool) }, parked({ epoch: epoch2, sn: sn2 }));
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
    b: !!l && l.frozen === false,
    unpoisoned: !!l && l.poisoned === false,
    mature: !!l && big(l.bornAt) + big(p.W) <= big(now),
  };
  const failing = [];
  if (!conjuncts.present) failing.push('not-present');
  else {
    if (!conjuncts.b) failing.push('frozen');
    if (!conjuncts.unpoisoned) failing.push('poisoned');
    if (!conjuncts.mature) failing.push('juvenile');
  }
  return { ok: !failing.length, verdict: failing.length ? failing[0] : 'consumable', failing, conjuncts };
}
// consumableStateB, transcribed as one Boolean: the mirror the theorem consumableStateB_iff ties to the conjuncts
const consumableB = (p, now, s) => { const l = liveOf(s); return !!l && l.frozen === false && l.poisoned === false && big(l.bornAt) + big(p.W) <= big(now); };
// ∀ t', ¬ consumableState p t' s  ⇔  the two structural conjuncts cannot both hold
const consumableEver = (p, s) => { const l = liveOf(s); return !!l && !l.frozen && !l.poisoned; };

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
// (SysStep.register's habs), a reopen needs it parked (SysStep.reopen's
// hparked); for a consistent system the state guard refuses first, so those
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
    if (res.ok && kind === 'reopen' && leafKind(leafOfAid(s, aid)) !== 'parked') res = { ok: false, reason: 'leaf-not-parked' };
  }
  record.ok = res.ok;
  if (res.ok) { record.flow = res.flow; record.state = res.state; }
  else { record.reason = res.reason; if (res.field) record.field = res.field; record.state = pre; }
  record.stepped = res.reason !== 'slot-regression' && res.reason !== 'aid-already-registered' && res.reason !== 'leaf-not-parked' && !(res.reason === 'invalid-nat' && res.field === 'slot');
  const now = record.stepped ? Math.max(s.now, slot) : s.now;
  const mine = aid === s.aid;
  const history = res.ok && mine ? [...s.history, [slot, action]] : s.history;
  const leaves = res.ok ? { ...s.leaves, [aid]: leafOf(record.state) } : s.leaves;
  const next = { ...s, now, history, leaves,
    state: mine ? record.state : s.state,
    others: mine ? s.others : { ...s.others, [aid]: record.state } };
  record.theorems = theoremReport(s, next, record);
  record.lamps = lampsOf(record.theorems);
  next.records = [...s.records, record];
  return { session: next, record };
}
// per theorem: how many records exhibited it and how many of those held
function heldSoFar(s) {
  const out = {};
  for (const t of THEOREMS) out[t.id] = { exhibited: 0, held: 0, broken: 0 };
  for (const r of s.records) for (const id of Object.keys(r.lamps)) {
    const x = r.lamps[id];
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
  anyone: { name: 'A sponsor', role: 'pays for her presence', addr: 6, blurb: 'Someone who wants Alice served on Cardano — a service, a friend, a DAO. Registers her public inception, revives it from the registry after she left, tops up her pool; the machine asks no signature of him. If he names his own refund address, his bonds go back to Alice at her first rotation: a stale registration is a donation.' },
};
const whoAddr = addr => Object.values(CAST).find(c => c.addr === addr) || { name: 'address ' + addr };
const STATE_WORDS = {
  absent: 'Absent', live: 'Live', poisoned: 'Poisoned', frozen: 'Frozen', parked: 'Parked', convicted: 'Convicted',
};
// the story's state table, read off the datum: the three registry states of
// D-040 (active = live / poisoned / frozen, parked, convicted) and absent
function stateWord(p, s) {
  const k = stateKind(s);
  if (k !== 'present') return k;
  const l = liveOf(s);
  if (l.frozen) return 'frozen';
  if (l.poisoned) return 'poisoned';
  return 'live';
}
// an intent in words: 'keep' | 'deposit' | {close:{payee}}
const INTENT_WORDS = { keep: 'keep the bonds', deposit: 'deposit (unfreeze)', close: 'close (leave)' };
const intentWord = i => { const k = intentKind(i); return k === 'close' ? INTENT_WORDS.close + ', payee → ' + whoAddr(i.close.payee).name : (INTENT_WORDS[k] || String(i)); };
const VERDICT_WORDS = {
  consumable: 'Consumable: bonded, not frozen, not poisoned, past the juvenility window.',
  'not-present': 'Not consumable: there is no checkpoint to read (absent, parked or convicted).',
  frozen: 'Not consumable: the freeze bond is missing (frozen).',
  poisoned: 'Not consumable: the current keys are declared poisoned.',
  juvenile: 'Not consumable yet: juvenile, born too recently.',
  'invalid-params': 'Nothing to read: the deployment parameters are not a valid Params (both bonds positive, whole numbers).',
  'invalid-nat': 'Nothing to read: a field that must be a non-negative whole number at most 2^53 − 1 is not.',
  'invalid-state': 'Nothing to read: this is not a checkpoint state.',
};
// every refusal in the story's words, with the numbers that decided it
function explain(rec, s) {
  const p = s.params, a = rec.action;
  const l = liveOf(rec.pre) || { epoch: '?', sn: '?', pool: '?', frozen: '?' };
  const k = actionKind(a);
  const d = (a && typeof a === 'object' && a[k] && typeof a[k] === 'object') ? a[k] : {};
  const c = hashOf(rec.pre);
  switch (rec.reason) {
    case 'invalid-params': return 'The deployment parameters are refused: both bonds must be positive, or "bond missing" could not be told from "bond full".';
    case 'invalid-nat': return (rec.field === 'pool' || rec.field === 'epoch')
      ? `The resulting ${rec.field} would exceed 2^53 − 1, the largest whole number this simulator represents exactly; the Lean's Nat is unbounded, so the step is refused rather than rounded.`
      : `"${rec.field}" must be a non-negative whole number at most 2^53 − 1: lovelace, slots and sequence numbers do not go negative, fractional or beyond what is represented exactly.`;
    case 'aid-already-registered': return 'This AID has a registry leaf already: a registration needs the absence proof, and the leaf never goes back to absent.';
    case 'leaf-not-parked': return 'This AID’s registry leaf is not parked: a revival needs the presence proof of a parked leaf with its hash.';
    case 'invalid-action': return 'The validator does not know this redeemer; only register, rotate, poison, freeze, top-up, convict, close and reopen exist.';
    case 'invalid-state': return `"${rec.field}" is not part of a checkpoint state: a state is Absent, Present with its seven datum fields, Parked with the hash (its key state), or Convicted. Nothing is evaluated on a non-state.`;
    case 'invalid-evidence': return `"${rec.field}" is not part of an evidence table: the four predicates (witnessed rotation, signed intent, quorum, duplicity) as rows of 3, 3, 1 and 2 entries. Nothing is evaluated under a non-table.`;
    case 'convicted-terminal': return 'Convicted is terminal: no rotation, no poison, no close, no revival, ever. No KERI event un-duplicates an identifier.';
    case 'parked-inert': return `Parked: the UTxO is burned and the registry leaf holds the hash of the last checkpoint (key state: epoch ${c ? c.epoch : '?'}, sequence ${c ? c.sn : '?'}). Nothing is held, so nothing moves it but a revival — a witnessed rotation from exactly that key state, later than sequence ${c ? c.sn : '?'}, bringing fresh bonds — or a duplicity proof against it.`;
    case 'reopen-needs-parked': return 'A revival needs a parked leaf; this checkpoint is on chain.';
    case 'absent-needs-register': return 'Nothing is on chain for this AID. The only thing that can happen first is a registration.';
    case 'already-present': return 'This AID already has its checkpoint. The token is minted once, ever.';
    case 'no-witnessed-rotation': return c
      ? `No witnessed rotation from the parked key state (epoch ${c.epoch}, sequence ${c.sn}) to sequence ${d["sn'"]} was presented. Only the holder of the next keys of that state can produce one.`
      : `No witnessed rotation from epoch ${l.epoch} at sequence ${l.sn} to sequence ${d["sn'"]} was presented: signatures at the current threshold, revealed keys matching the pre-committed digests, receipts from the witnesses.`;
    case 'sequence-not-later': return c
      ? `The presented rotation is at sequence ${d["sn'"]}, not later than the parked ${c.sn}: a revival cannot resurrect a stale sequence — not even the close's own rotation.`
      : `The presented rotation is at sequence ${d["sn'"]}, not later than the checkpoint’s ${l.sn}: the checkpoint cannot roll back.`;
    case 'intent-not-authorized': return `The keys of epoch ${l.epoch + 1} — the ones this rotation reveals — did not sign the intent «${k === 'close' ? intentWord(closeIntent(d.payee)) : (INTENT_WORDS[d.op] || d.op)}${d["refund'"] !== null && d["refund'"] !== undefined ? ', refund → ' + d["refund'"] : ''}». Public data lands a rotation that keeps the bonds; unfreezing, leaving (with its payee) and moving the refund address are the owner’s, signed at the rotation (D-038, D-039). A copied reap with another payee is a message the keys never signed.`;
    case 'no-quorum': return `The current keys of epoch ${l.epoch} did not sign at their threshold. Keys of a retired epoch count for nothing.`;
    case 'already-poisoned': return 'This epoch is already poisoned; the poison is declared once per epoch and only a rotation clears it.';
    case 'poisoned': return 'A poisoned checkpoint cannot be frozen: it is already unconsumable, there is nothing to freeze.';
    case 'pool-covers-premium': return `The pool (${l.pool}) covers the premium (${p.P}): there is nothing to freeze. Land the rotation and be paid instead.`;
    case 'freeze-bond-missing': return `The freeze bond is not there to take: the checkpoint is already frozen (the bond is ${p.B} when held, nothing now).`;
    case 'no-duplicity-proof': return c
      ? `No second rotation at sequence ${c.sn} revealing the keys of epoch ${c.epoch} — the parked key state — was presented.`
      : `No second rotation at sequence ${l.sn} revealing the keys of epoch ${l.epoch}, signed at the current threshold and receipted by the tip’s witnesses, was presented.`;
    case 'slot-regression': return `Slot ${rec.slot} is before the last accepted slot ${rec.now}: the chain does not go backwards.`;
  }
  return 'Refused: ' + rec.reason;
}
/* @@CORE:words:END@@ */

/* @@CORE:theorems@@ */
// ---- the theorems as executable properties ---------------------------------
const THEOREMS = [
  { id: 'T1', title: 'The checkpoint cannot roll back',
    lean: ['T1_sn_monotone', 'T1_rotate_strict', 'T1_sn_monotone_all', 'T1_reopen_strict', 'T1_close_rotation_cannot_revive', 'trace_sn_monotone_all', 'T1_trace_sn_monotone'],
    plain: 'No step decreases the sequence a state records — between live states, into the parked hash, and out of it: a revival is strictly later than the parked key state (no stale resurrection; the close’s own rotation cannot revive); every rotation strictly increases it; along any trace the sequence never goes down.' },
  { id: 'T2', title: 'Keys change only by rotation',
    lean: ['T2_epoch_only_by_rotation', 'T2_close_and_reopen_open_epochs'],
    plain: 'The key epoch changes only under a rotation, authorized by the next keys, and then by exactly one; a close parks the epoch it opened with its sequence, a revival opens the one after the parked epoch.' },
  { id: 'T3', title: 'Poison is local to one epoch',
    lean: ['T3_rotation_clears', 'T3_only_rotation_clears', 'T3_only_poison_sets', 'trace_poison_fold', 'T3_epoch_local'],
    plain: 'A rotation always yields an unpoisoned state; only a rotation clears the poison; only the poison sets it, from a clean state, changing nothing else and moving no value; along any play the checkpoint is poisoned exactly when the last epoch-relevant action was a poison.' },
  { id: 'T4', title: 'Poisoned keys can only be rotated; a thief of the current keys can neither park nor revive',
    lean: ['T4_poisoned_blocks_quorum_and_freeze', 'T4_poisoned_nonrotation_inert', 'T4_current_quorum_only_poisons', 'T4_current_key_thief_cannot_park', 'T4_current_key_thief_cannot_revive'],
    plain: 'From a poisoned state the current quorum can do nothing and no proof can freeze it; nothing but the next keys yields a consumable state. The current keys’ only Cardano power is the poison. When the next keys never signed a rotation, no step parks the checkpoint and nothing but a duplicity proof moves a parked one.' },
  { id: 'T5', title: 'Every ruled transition is enabled when its evidence is',
    lean: ['T5_every_bond_option', 'T5_keep_is_rotated', 'T5_deposit_on_full_is_keep', 'T5_keep_needs_no_intent', 'T5_poison_enabled', 'T5_freeze_enabled', 'T5_convict_enabled', 'T5_convict_parked_enabled', 'T5_close_enabled', 'T5_reopen_enabled'],
    plain: 'Given a witnessed rotation and the new keys’ signature on the option, both bond options are enabled whatever the pool holds (payment is never a gate); a keep is exactly the rotated datum plus the premium, and a deposit on full bonds is a keep; given the quorum an unpoisoned state can be poisoned; given a later rotation, a short pool, the freeze bond held and no poison the freeze is enabled; given a duplicity proof conviction is enabled from every present and every parked state; given the rotation and the signed close intent naming the payee the close is enabled, poisoned or frozen or not; given a later rotation the revival is enabled from every parked state.' },
  { id: 'T6', title: 'Three value components that never mix; every intent signed by the new keys',
    lean: ['T6_component_conservation', 'T6_dreg_never_a_fee', 'T6_dreg_never_moves_between_present_states', 'T6_dreg_enters_only_at_birth', 'T6_refund_change_requires_new_keys', 'T6_frozen_flips_only_by_rotation_or_freeze', 'T6_intent_requires_new_keys', 'T6_relayer_cannot_park_age_or_close'],
    plain: 'For each of the conviction bond, the freeze bond and the pool: held plus in equals held after plus out. The conviction bond is never a fee, never moves between present states, and enters only at a birth. The refund address changes only under a rotation whose new keys signed it. A deposit, a close with its payee, and a new address each carry the new keys’ signature on that intent (D-038, D-039): a relayer with public data alone lands a keep and nothing else.' },
  { id: 'T7', title: 'The state is the fold of the accepted actions',
    lean: ['T7_step_iff_stepFn', 'T7_trace_iff_replay'],
    plain: 'The transition relation and the functional step agree exactly, and a trace is exactly a successful replay: replaying every accepted action from the origin reproduces the current state.' },
  { id: 'T8', title: 'One incarnation per AID: the registry leaf over its three states',
    lean: ['T8_absent_only_registers', 'T8_parked_only_revives_or_convicts', 'T8_parked_returns_only_by_revival', 'T8_only_convicted_is_terminal', 'T8_leaf_agrees_with_state', 'T8_edges_leave_the_leaf', 'T8_present_implies_registered', 'T8_leaf_states', 'T8_utxo_iff_active', 'T8_leaf_never_absent_again', 'T8_mint_once', 'T8_reopen_actor_is_proof', 'T8_sysstep_partition'],
    plain: 'Registration is the only step from Absent and needs an absent leaf; from Parked only a revival or a conviction moves, and only the revival comes back; conviction is the only terminal state. The registry leaf (absent, active, parked with the hash, convicted) always agrees with the state — a UTxO exists exactly when the leaf is active — never returns to absent, and rotate, poison, freeze and top-up never touch it.' },
  { id: 'T9', title: 'Juvenility is consumer policy',
    lean: ['consumableStateB_iff', 'T9_juvenility_is_consumer_only'],
    plain: 'No transition depends on the window W: the same action from the same state is accepted or refused identically under any W. The registry’s grace window is not this machine’s.' },
  { id: 'T10', title: 'A frozen checkpoint is inert to everyone but the next keys; a parked one holds nothing',
    lean: ['T10_inert_without_next_keys', 'T10_only_deposit_restores', 'T10_current_quorum_never_restores', 'T10_reopen_is_juvenile', 'T10_bonds_are_observable', 'T10_parked_holds_nothing'],
    plain: 'If the freeze bond is missing, no step by anyone but the next keys yields a consumable state; only a depositing rotation restores consumability, and it does not restart juvenility; the current quorum never produces a consumable state; a revival brings both bonds and is juvenile for W slots; the bonds are positive, so a frozen checkpoint and a parked identity are observably different in value; a parked identity holds nothing.' },
  { id: 'T12', title: 'Conviction needs a proof and is exact',
    lean: ['T12_convicted_terminal', 'trace_from_convicted', 'T12_convict_exact', 'T12_convict_parked_exact'],
    plain: 'No step leaves Convicted. Only a conviction reaches it, only with a duplicity proof against the checkpoint’s key state; from a present checkpoint the flow is exactly the conviction bond to the convictor and the rest to the refund address; from a parked identity nothing moves.' },
  { id: 'T14', title: 'The pool moves only by premium or top-up',
    lean: ['T14_pool_decreases_only_by_premium', 'T14_pool_increases_only_by_topup'],
    plain: 'Between live states the pool decreases only by the premium under a paid rotation, and increases only by a top-up that changes nothing else.' },
  { id: 'T15', title: 'The freeze bond leaves only by freeze',
    lean: ['T15_b_leaves_only_by_freeze', 'T15_b_returns_only_by_deposit', 'T15_freeze_makes_inert'],
    plain: 'Between live states the freeze bond leaves only by a freeze (a later rotation presented, pool short, exactly B to the hunter, datum otherwise untouched); it returns only by a depositing rotation, in full; a freeze makes the checkpoint unconsumable.' },
  { id: 'T16', title: 'The closer chooses when, never where nor who is paid; the parked hash is the closed checkpoint’s',
    lean: ['T16_close_destination', 'T16_close_needs_rotation', 'T16_parked_hash_is_the_closed_checkpoints', 'T16_copied_reap_refused', 'T16_payments_are_named'],
    plain: 'A close is a witnessed rotation by the next keys, poisoned or frozen or not: it pays the premium to the signed payee when the pool covers it and everything else to the refund address it results in, parks the epoch it opened with its sequence — the hash of the checkpoint the rotation reached — and burns the token; when the keys signed exactly one close message, a copied reap with another payee or address is refused; a hunter is paid only the premium or the freeze bond, a convictor only the conviction bond.' },
];

// ---- the Lean oracle: cells of the embedded corpus, keyed by what stepFn reads
// A step is identified by (params, slot, input state, action) and the values
// of the evidence predicates stepFn consults for it; two Env tables that agree
// on those are the same oracle for that step.
function evidenceBits(env, state, action) {
  const k = actionKind(action); const d = (action && typeof action === 'object' && action[k] && typeof action[k] === 'object') ? action[k] : {};
  const l = liveOf(state), hh = hashOf(state);
  if (hh) return k === 'reopen' ? [envRotationTo(env, hh.epoch, hh.sn, d["sn'"])] : k === 'convict' ? [envDuplicityAt(env, hh.epoch, hh.sn)] : [];
  if (!l) return [];
  const e1 = natAdd(l.epoch, 1);
  switch (k) {
    case 'rotate': return [envRotationTo(env, l.epoch, l.sn, d["sn'"]), intentOk(env, e1, d.op, d["refund'"])];
    case 'close': return [envRotationTo(env, l.epoch, l.sn, d["sn'"]), intentOk(env, e1, closeIntent(d.payee), d["refund'"])];
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

// theoremReport(before, after, record) → one row per Lean declaration of
// CheckpointGoals.lean, keyed by its exact name: {exhibited, holds, notes, by}.
// `exhibited`: the theorem's antecedent held on this step, so the play shows
// it; `holds`: its consequent held (vacuously true when not exhibited); `by`
// names the declaration the row instantiates. The page's lamps are the
// fourteen groups of THEOREMS, folded over the rows by lampsOf.
function theoremReport(before, after, rec) {
  const p = before.params, env = before.env;
  const pre = rec.pre, post = rec.state, ok = rec.ok, kind = rec.kind, actor = rec.actor;
  const lp = liveOf(pre), lq = liveOf(post);
  const preK = stateKind(pre), postK = stateKind(post);
  const pp = preK === 'present' && postK === 'present';
  const a = rec.action, d = (a && typeof a === 'object' && a[Object.keys(a)[0]] && typeof a[Object.keys(a)[0]] === 'object') ? a[Object.keys(a)[0]] : {};
  const f = rec.flow || flow({});
  // the step crossed the boundary: everything it read is a Lean value (the
  // theorems quantify over Lean values only, so a boundary refusal exhibits none)
  const boundaryOk = !validateParams(p) && !validateEnv(env) && !validateState(pre) && isNat(rec.slot) && normalizeAction(a).ok;
  const stepped = boundaryOk && rec.stepped;
  const out = {};
  const row = (name, exhibited, checks) => {
    const notes = exhibited ? checks().filter(c => !c[0]).map(c => c[1]) : [];
    out[name] = { exhibited: !!exhibited, holds: !exhibited || !notes.length, notes, by: [name] };
  };
  const eq = (x, y) => canon(x) === canon(y);
  const e1 = boundaryOk && lp ? natAdd(lp.epoch, 1) : null;
  const hPre = preK === 'parked' ? pre.parked.h : null, hPost = postK === 'parked' ? post.parked.h : null;
  const mine = rec.aid === after.aid;
  const origin = after.origin, lo = liveOf(origin);
  // the first present state of this play and the accepted actions after it: the
  // trace theorems quantify traces from a present state, and a play from absent
  // carries one from its first accepted step that produced a checkpoint
  const accepted = before.records.filter(r => r.ok && r.aid === rec.aid);
  const firstPresent = lo ? { l: lo, es: after.history } : (() => { const k = accepted.findIndex(r => stateKind(r.state) === 'present'); return k < 0 ? null : { l: liveOf(accepted[k].state), es: after.history.slice(k + 1) }; })();
  const snPre = snOf(pre), snPost = ok ? snOf(post) : null;
  const rot = kind === 'rotate', op = rot ? d.op : null, r2 = d["refund'"] === undefined ? null : d["refund'"];
  const rotEv = !!lp && stepped && envRotationTo(env, lp.epoch, lp.sn, d["sn'"]) && lp.sn < d["sn'"];
  const closeMsg = kind === 'close' ? closeIntent(d.payee) : null;
  // what a thief of the current keys can present: no rotation from the key state at all
  const noRotFrom = (e, sn) => boundaryOk && !env.rotationTo.some(rw => rw[0] === e && rw[1] === sn);
  const heldZero = x => x.dreg === 0 && x.b === 0 && x.pool === 0;
  const hi = held(p, pre), ho = held(p, post);
  const pr = paid(f.refund), ph = paid(f.hunter), pc = paid(f.convictor);
  const keepShaped = () => { const bIn0 = f.bIn === 0 && f.dregIn === 0 && f.poolIn === 0; const fl = eq(f, flow({ hunter: premium(p, lp, d.payee) })); const st = eq(post, present(rotated(p, lp, d["sn'"], r2))); return [bIn0, fl, st]; };

  // ---- T1: the checkpoint cannot roll back
  row('T1_sn_monotone', ok && pp, () => [[lp.sn <= lq.sn, 'sequence decreased between live states']]);
  row('T1_rotate_strict', ok && pp && rot, () => [[lp.sn < lq.sn, 'a rotation did not increase the sequence']]);
  row('T1_sn_monotone_all', ok && snPre !== null && snPost !== null, () => [[snPre <= snPost, 'the recorded sequence decreased']]);
  row('T1_reopen_strict', ok && kind === 'reopen' && !!hPre && !!lq, () => [[hPre.sn < lq.sn, 'a revival did not pass the parked sequence (stale resurrection)']]);
  row('T1_close_rotation_cannot_revive', kind === 'reopen' && stepped && !!hPre && d["sn'"] === hPre.sn, () => [[!ok, 'the close’s own rotation (the parked sequence) revived the identity']]);
  const snSeen = mine ? before.records.filter(r => r.ok && r.aid === rec.aid).map(r => snOf(r.state)).filter(x => x !== null) : [];
  row('trace_sn_monotone_all', ok && mine && snPost !== null && (snOf(origin) !== null || snSeen.length > 0), () => [
    [(snOf(origin) === null || snOf(origin) <= snPost) && snSeen.every(x => x <= snPost), 'along this play a recorded sequence was higher than the one now recorded']]);
  row('T1_trace_sn_monotone', ok && mine && !!lq && !!firstPresent && firstPresent.es.length > 0, () => [[firstPresent.l.sn <= lq.sn, 'the sequence is below the first checkpoint of this play']]);
  // ---- T2: keys change only by rotation
  row('T2_epoch_only_by_rotation', ok && pp && lq.epoch !== lp.epoch, () => [
    [actor === 'nextKeys', 'the epoch changed without the next keys'], [lq.epoch === lp.epoch + 1, 'the epoch did not move by one']]);
  row('T2_close_and_reopen_open_epochs', ok && (kind === 'close' || kind === 'reopen'), () => [
    [kind !== 'close' || (!!hPost && hPost.epoch === lp.epoch + 1 && hPost.sn === d["sn'"]), 'the parked hash is not the epoch the close opened with its sequence'],
    [kind !== 'reopen' || (!!lq && !!hPre && lq.epoch === hPre.epoch + 1 && lq.sn === d["sn'"]), 'the revival did not open the epoch after the parked one at its sequence']]);
  // ---- T3: poison is epoch-local
  row('T3_rotation_clears', ok && pp && rot, () => [[lq.poisoned === false, 'a rotation left the poison']]);
  row('T3_only_rotation_clears', ok && pp && lp.poisoned && !lq.poisoned, () => [[actor === 'nextKeys', 'the poison was cleared by something else than a rotation']]);
  row('T3_only_poison_sets', ok && pp && !lp.poisoned && lq.poisoned, () => [
    [kind === 'poison' && eq(lq, { ...lp, poisoned: true }) && eq(f, flow({})), 'the poison was set by something else, or it changed more than the bit']]);
  row('trace_poison_fold', ok && mine && !!lq && !!firstPresent && firstPresent.es.length > 0, () => [[lq.poisoned === poisonAfter(firstPresent.l.poisoned, firstPresent.es), 'the poison bit is not the fold of the actions over the bit this play started with']]);
  row('T3_epoch_local', ok && mine && !!lq && stateKind(origin) === 'absent', () => [[lq.poisoned === poisonAfter(false, after.history), 'poisoned, but the last epoch-relevant action was not a poison (or the reverse)']]);
  // ---- T4: poisoned keys can only be rotated; the current quorum only poisons; the thief
  const quorumOrFreeze = actor === 'currentQuorum' || kind === 'freeze';
  row('T4_poisoned_blocks_quorum_and_freeze', boundaryOk && !!lp && lp.poisoned && (ok || quorumOrFreeze), () => [[!ok || !quorumOrFreeze, 'the current quorum acted, or a freeze landed, on a poisoned checkpoint']]);
  row('T4_poisoned_nonrotation_inert', ok && !!lp && lp.poisoned && actor !== 'nextKeys', () => [[!consumableEver(p, post), 'a non-rotation made a poisoned checkpoint consumable']]);
  row('T4_current_quorum_only_poisons', ok && actor === 'currentQuorum', () => [[kind === 'poison', 'the current quorum did something other than poison']]);
  row('T4_current_key_thief_cannot_park', ok && !!lp && noRotFrom(lp.epoch, lp.sn), () => [
    [actor !== 'nextKeys', 'with no rotation from the key state, a next-keys step landed'], [kind !== 'freeze', 'with no rotation from the key state, a freeze landed'], [postK !== 'parked', 'with no rotation from the key state, the checkpoint was parked']]);
  row('T4_current_key_thief_cannot_revive', ok && !!hPre && noRotFrom(hPre.epoch, hPre.sn), () => [
    [kind === 'convict' && postK === 'convicted', 'with no rotation from the parked key state, something other than a conviction moved it'], [postK !== 'present', 'with no rotation from the parked key state, the identity was revived']]);
  // ---- T5: totality — the evidence antecedent held ⇒ the step is accepted
  const anteRot = rot && rotEv && intentOk(env, e1, op, r2);
  row('T5_every_bond_option', anteRot, () => [[ok, 'the rotation’s evidence and signed intent held but it was refused: ' + rec.reason]]);
  row('T5_keep_is_rotated', ok && rot && op === 'keep', () => { const [, fl, st] = keepShaped(); return [[fl, 'a keep’s flow is not the premium to the payee and nothing else'], [st, 'a keep’s datum is not the rotated datum']]; });
  row('T5_deposit_on_full_is_keep', ok && rot && op === 'deposit' && !!lp && !lp.frozen, () => { const [bIn0, fl, st] = keepShaped(); return [[bIn0, 'a deposit on full bonds brought something'], [fl, 'a deposit on full bonds paid other than a keep'], [st, 'a deposit on full bonds left other than the rotated datum'], [!!lq && lq.bornAt === lp.bornAt, 'a deposit on full bonds reset juvenility']]; });
  row('T5_keep_needs_no_intent', rot && op === 'keep' && r2 === null && rotEv, () => [[ok, 'a keep with no new address was refused although the rotation is witnessed: ' + rec.reason]]);
  row('T5_poison_enabled', kind === 'poison' && stepped && !!lp && envQuorum(env, lp.epoch) && !lp.poisoned, () => [[ok, 'the quorum signed on a clean state but the poison was refused: ' + rec.reason]]);
  row('T5_freeze_enabled', kind === 'freeze' && rotEv && lp.pool < p.P && !lp.frozen && !lp.poisoned, () => [[ok, 'the freeze’s evidence held but it was refused: ' + rec.reason]]);
  row('T5_convict_enabled', kind === 'convict' && stepped && !!lp && envDuplicityAt(env, lp.epoch, lp.sn), () => [[ok, 'a duplicity proof was presented but the conviction was refused: ' + rec.reason]]);
  row('T5_convict_parked_enabled', kind === 'convict' && stepped && !!hPre && envDuplicityAt(env, hPre.epoch, hPre.sn), () => [[ok && postK === 'convicted' && eq(f, flow({})), 'a duplicity proof against the parked key state was presented but the conviction was refused or moved value: ' + (ok ? '' : rec.reason)]]);
  row('T5_close_enabled', kind === 'close' && rotEv && intentOk(env, e1, closeMsg, r2), () => [[ok && !!hPost && hPost.epoch === lp.epoch + 1 && hPost.sn === d["sn'"], 'the close’s rotation and signed intent held but it was refused or parked another hash: ' + (ok ? '' : rec.reason)]]);
  row('T5_reopen_enabled', kind === 'reopen' && stepped && !!hPre && envRotationTo(env, hPre.epoch, hPre.sn, d["sn'"]) && hPre.sn < d["sn'"], () => [[ok, 'a later witnessed rotation was presented but the revival was refused: ' + rec.reason]]);
  // ---- T6: value, and the intent signatures
  row('T6_component_conservation', ok, () => [
    [big(hi.dreg) + big(f.dregIn) === big(ho.dreg) + big(pr.dreg) + big(ph.dreg) + big(pc.dreg), 'conviction bond not conserved'],
    [big(hi.b) + big(f.bIn) === big(ho.b) + big(pr.b) + big(ph.b) + big(pc.b), 'freeze bond not conserved'],
    [big(hi.pool) + big(f.poolIn) === big(ho.pool) + big(pr.pool) + big(ph.pool) + big(pc.pool), 'pool not conserved']]);
  row('T6_dreg_never_a_fee', ok, () => [
    [ph.dreg === 0, 'a hunter was paid from the conviction bond'],
    [pr.dreg === 0 || (pr.dreg === p.D && hi.dreg === p.D && ho.dreg === 0), 'the conviction bond left partially, or not from a checkpoint holding it, to the refund address'],
    [pc.dreg === 0 || (pc.dreg === p.D && hi.dreg === p.D && postK === 'convicted'), 'the conviction bond went to a convictor without a conviction, or partially']]);
  row('T6_dreg_never_moves_between_present_states', ok && pp, () => [[f.dregIn === 0 && pr.dreg === 0 && ph.dreg === 0 && pc.dreg === 0, 'the conviction bond moved between two present states']]);
  row('T6_dreg_enters_only_at_birth', ok && f.dregIn !== 0, () => [
    [(kind === 'register' && preK === 'absent') || (kind === 'reopen' && preK === 'parked'), 'the conviction bond entered other than at a registration or a revival'],
    [f.dregIn === p.D && f.bIn === p.B && !!lq && lq.frozen === false && lq.bornAt === rec.slot, 'a birth did not bring both bonds in full, unfrozen, born now']]);
  row('T6_refund_change_requires_new_keys', ok && pp && lq.refundTo !== lp.refundTo, () => [
    [rot && r2 === lq.refundTo && envIntentAuthorized(env, lq.epoch, op, lq.refundTo), 'the refund address moved other than by a rotation naming it, signed by the new keys as that rotation’s own intent']]);
  row('T6_frozen_flips_only_by_rotation_or_freeze', ok && pp && lq.frozen !== lp.frozen, () => [[actor === 'nextKeys' || kind === 'freeze', 'the freeze bond moved under poison or top-up']]);
  const signed = (intent, r) => envIntentAuthorized(env, e1, intent, r);
  row('T6_intent_requires_new_keys', ok && ((rot && (op !== 'keep' || r2 !== null)) || kind === 'close'), () => [
    [!(rot && op === 'deposit') || signed('deposit', r2), 'a deposit landed without the new keys’ signature on it'],
    [kind !== 'close' || signed(closeMsg, r2), 'a close landed without the new keys’ signature on it, naming its payee'],
    [!(rot && op === 'keep' && r2 !== null) || signed('keep', r2), 'a new refund address landed without the new keys’ signature on it']]);
  const noIntent = boundaryOk && e1 !== null && !env.intentAuthorized.some(rw => rw[0] === e1);
  row('T6_relayer_cannot_park_age_or_close', ok && actor === 'nextKeys' && noIntent, () => [[rot && op === 'keep' && r2 === null, 'with no signed intent at the new epoch, something other than a keep with the address unchanged landed']]);
  // ---- T7: parity with the Lean — the cell in the embedded corpus, and the fold
  const cell = stepped ? leanCell(before.corpus, p, rec.slot, pre, a, env) : undefined;
  row('T7_step_iff_stepFn', cell !== undefined, () => [
    [(cell.result === null) === !ok, 'Lean ' + (cell.result === null ? 'refuses' : 'applies') + ' this step (' + cell.where + '), the core ' + (ok ? 'applied' : 'refused: ' + rec.reason)],
    [!ok || cell.result === null || eq(f, cell.result.flow), 'flow differs from Lean (' + cell.where + ')'],
    [!ok || cell.result === null || eq(post, cell.result.state), 'post-state differs from Lean (' + cell.where + ')']]);
  out.T7_step_iff_stepFn.cell = cell !== undefined ? cell.where : null;
  if (cell === undefined && rec.stepped) out.T7_step_iff_stepFn.notes = ['the Lean was not asked about this exact step: T7 not shown'];
  row('T7_trace_iff_replay', ok && mine && cell !== undefined, () => [
    [(() => { const rp = replay(p, after.envAll, after.originSlot, after.origin, after.history); return rp.ok && eq(rp.state, post); })(), 'replay of the accepted actions does not reproduce the state']]);
  // ---- T8: one incarnation per AID — the registry leaf over its three states
  const leafPre = leafOfAid(before, rec.aid), leafPost = leafOfAid(after, rec.aid);
  row('T8_absent_only_registers', stepped && preK === 'absent', () => [[ok === (kind === 'register' && leafPre === 'absent'), 'from absent, something other than a registration happened, or a registration was refused without cause']]);
  row('T8_parked_only_revives_or_convicts', stepped && preK === 'parked', () => [
    [!ok || (kind === 'reopen' && !!lq && lq.frozen === false && lq.bornAt === rec.slot && lq.epoch === hPre.epoch + 1 && lq.sn === d["sn'"] && hPre.sn < d["sn'"] && lq.poisoned === false && lq.refundTo === d.refund && lq.pool === d.pool0 && eq(f, flow({ dregIn: p.D, bIn: p.B, poolIn: d.pool0 })))
      || (kind === 'convict' && postK === 'convicted' && eq(f, flow({}))), 'something other than a revival or a conviction left Parked, or the revival did not bring fresh bonds, clean, born now, at the next epoch, or the conviction moved value']]);
  row('T8_parked_returns_only_by_revival', ok && preK === 'parked' && postK === 'present', () => [[kind === 'reopen' && envRotationTo(env, hPre.epoch, hPre.sn, d["sn'"]) && hPre.sn < d["sn'"], 'the identity came back other than by a witnessed rotation later than the parked key state']]);
  const enabledFrom = st => { const k = stateKind(st); if (k === 'absent') return step(p, env, { register: { refund: 0, pool0: 0 } }, rec.slot, st).ok; if (k === 'present') return step(p, env, { topUp: { x: 0 } }, rec.slot, st).ok; if (k === 'parked') return step(p, env, { reopen: { "sn'": st.parked.h.sn + 1, refund: 0, pool0: 0 } }, rec.slot, st).ok; return false; };
  row('T8_only_convicted_is_terminal', ok && mine && postK !== 'convicted' && (postK !== 'parked' || envRotationTo(env, hPost.epoch, hPost.sn, hPost.sn + 1)), () => [[enabledFrom(post), 'no step is enabled from a state that is not Convicted']]);
  row('T8_leaf_agrees_with_state', boundaryOk, () => [[allAids(after).every(x => eq(leafOfAid(after, x), leafOf(stateOfAid(after, x)))), 'a leaf disagrees with its state']]);
  row('T8_edges_leave_the_leaf', ok, () => [[eq(leafPost, leafPre) === !TOUCHES_LEAF.has(kind), 'the leaf changed exactly when the action is not a register, reopen, close or conviction — violated']]);
  row('T8_present_implies_registered', boundaryOk, () => [[allAids(after).every(x => stateKind(stateOfAid(after, x)) === 'absent' || leafOfAid(after, x) !== 'absent'), 'an AID with a state has no leaf']]);
  row('T8_leaf_states', boundaryOk, () => [[allAids(after).every(x => { const lf = leafOfAid(after, x), st = stateOfAid(after, x), k = leafKind(lf); return (k !== 'parked' || eq(st, { parked: { h: lf.parked.h } })) && (lf !== 'active' || stateKind(st) === 'present') && (lf !== 'convicted' || st === 'convicted'); }), 'a leaf does not carry what its state holds']]);
  row('T8_utxo_iff_active', boundaryOk, () => [[allAids(after).every(x => (stateKind(stateOfAid(after, x)) === 'present') === (leafOfAid(after, x) === 'active')), 'an AID has a UTxO without an active leaf, or an active leaf without a UTxO']]);
  row('T8_leaf_never_absent_again', boundaryOk && leafPre !== 'absent', () => [
    [leafPre === 'absent' || leafPost !== 'absent', 'a leaf returned to absent'],
    [leafKind(leafPre) !== 'convicted' || leafKind(leafPost) === 'convicted', 'a convicted leaf changed'],
    [allAids(after).filter(x => x !== rec.aid).every(x => eq(leafOfAid(after, x), leafOfAid(before, x))), 'another AID’s leaf changed']]);
  row('T8_mint_once', ok && (kind === 'register' || kind === 'reopen'), () => [
    [kind !== 'register' || (preK === 'absent' && leafPre === 'absent'), 'a registration landed on a non-absent state or leaf'],
    [kind !== 'reopen' || (preK === 'parked' && leafKind(leafPre) === 'parked'), 'a revival landed on a state or leaf that is not parked']]);
  row('T8_reopen_actor_is_proof', boundaryOk && (kind === 'reopen' || kind === 'freeze' || kind === 'convict'), () => [[actorOf(a) === 'proof', 'a proof-bearing action is not classed as one']]);
  row('T8_sysstep_partition', ok && rec.stepped, () => [
    [kind !== 'register' || (leafPre === 'absent' && preK === 'absent'), 'a registration landed under a leaf that is not absent'],
    [kind !== 'reopen' || leafKind(leafPre) === 'parked', 'a revival landed under a leaf that is not parked'],
    [eq(leafPost, leafOf(post)), 'the leaf did not follow the state of the AID that stepped']]);
  // ---- T9: juvenility is consumer policy; the consumer's program is its predicate
  row('consumableStateB_iff', stepped, () => [[consumable(p, rec.slot, post).ok === consumableB(p, rec.slot, post), 'the consumer’s Bool mirror disagrees with the conjuncts']]);
  const r0 = rec.stepped ? step(p, env, a, rec.slot, pre) : null;
  let untouched = true, rT = null, differing = [];
  if (rec.stepped) {
    const trap = new Proxy(p, { get(t, k) { if (k === 'W' && !validatingParams) throw new Error('W read'); return t[k]; } });
    try { rT = step(trap, env, a, rec.slot, pre); } catch (e) { untouched = false; }
    const samples = [0, 1, 2, 3, 5, 7, 11, 1000, 31536000, MAX_NAT, p.W + 1, p.W > 0 ? p.W - 1 : 4, (rec.slot * 7919 + 13) % 100000];
    differing = samples.filter(w => !eq(r0, step({ ...p, W: w }, env, a, rec.slot, pre)));
  }
  row('T9_juvenility_is_consumer_only', rec.stepped, () => [[untouched && eq(r0, rT), 'the transition read W'], [!differing.length, 'the step differs under W = ' + differing.slice(0, 3).join(', ')]]);
  // ---- T10: a frozen checkpoint is inert to everyone but the next keys; a parked one holds nothing
  const frozenPre = boundaryOk && !!lp && lp.frozen;
  row('T10_inert_without_next_keys', ok && frozenPre && actor !== 'nextKeys', () => [[!consumableEver(p, post), 'someone but the next keys made a frozen checkpoint consumable']]);
  row('T10_only_deposit_restores', ok && frozenPre && consumableEver(p, post), () => [[rot && op === 'deposit' && !!lq && lq.frozen === false && lq.bornAt === lp.bornAt && f.bIn === p.B, 'consumability restored other than by a depositing rotation bringing B, juvenility untouched']]);
  row('T10_current_quorum_never_restores', ok && actor === 'currentQuorum', () => [[!consumableEver(p, post), 'the current quorum produced a consumable state']]);
  row('T10_reopen_is_juvenile', ok && kind === 'reopen', () => [[f.dregIn === p.D && f.bIn === p.B && !!lq && lq.frozen === false && lq.bornAt === rec.slot && !consumable(p, rec.slot, post).ok, 'a revival did not bring both bonds and a fresh juvenility window']]);
  row('T10_bonds_are_observable', boundaryOk && !!lp, () => [
    [hi.dreg !== 0, 'a present checkpoint holds no conviction bond: it cannot be told from a parked identity in value'],
    [!lp.frozen || hi.b !== p.B, 'a frozen checkpoint holds the full freeze bond: freezing is not observable in value']]);
  row('T10_parked_holds_nothing', boundaryOk && (preK === 'parked' || preK === 'convicted' || (ok && (postK === 'parked' || postK === 'convicted'))), () => [
    [(preK !== 'parked' && preK !== 'convicted') || heldZero(hi), 'a parked or convicted identity holds value'],
    [!ok || (postK !== 'parked' && postK !== 'convicted') || heldZero(ho), 'a step left value on a parked or convicted identity']]);
  // ---- T12: conviction needs a proof and is exact; convicted is terminal
  row('T12_convicted_terminal', stepped && preK === 'convicted', () => [[!ok, 'a step left Convicted']]);
  const wasConvicted = mine && (stateKind(origin) === 'convicted' || before.records.some(r => r.ok && r.aid === rec.aid && stateKind(r.state) === 'convicted'));
  row('trace_from_convicted', wasConvicted, () => [[stateKind(post) === 'convicted' && eq(post, pre), 'a play that reached Convicted moved on']]);
  row('T12_convict_exact', kind === 'convict' && stepped && preK === 'present', () => [
    [ok === envDuplicityAt(env, lp.epoch, lp.sn), 'conviction accepted without a proof against the checkpoint’s key state, or refused with one'],
    [!ok || post === 'convicted', 'a conviction did not reach Convicted'],
    [!ok || eq(f, flow({ refund: payment(lp.refundTo, 0, bHeldOf(p, lp), lp.pool), convictor: payment(d.payee, p.D, 0, 0) })), 'the conviction flow is not exactly D to the convictor and the rest to the refund address']]);
  row('T12_convict_parked_exact', kind === 'convict' && stepped && preK === 'parked', () => [
    [ok === envDuplicityAt(env, hPre.epoch, hPre.sn), 'conviction of a parked identity accepted without a proof against the parked key state, or refused with one'],
    [!ok || (post === 'convicted' && eq(f, flow({}))), 'a conviction of a parked identity moved value or did not reach Convicted']]);
  // ---- T14: the pool
  row('T14_pool_decreases_only_by_premium', ok && pp && lq.pool < lp.pool, () => [
    [actor === 'nextKeys' && big(lq.pool) + big(p.P) === big(lp.pool) && ph.pool === p.P, 'the pool decreased other than by the premium under a rotation']]);
  row('T14_pool_increases_only_by_topup', ok && pp && (lp.pool < lq.pool || kind === 'topUp'), () => [
    [!(lp.pool < lq.pool) || (kind === 'topUp' && eq(f, flow({ poolIn: d.x })) && big(lq.pool) === big(lp.pool) + big(d.x) && eq({ ...lq, pool: 0 }, { ...lp, pool: 0 })), 'the pool increased other than by a top-up that changes nothing else'],
    [kind !== 'topUp' || big(lq.pool) === big(lp.pool) + big(d.x), 'a top-up did not add exactly its amount (precision lost)']]);
  // ---- T15: the freeze bond
  row('T15_b_leaves_only_by_freeze', ok && pp && !lp.frozen && lq.frozen, () => [
    [kind === 'freeze' && envRotationTo(env, lp.epoch, lp.sn, d["sn'"]) && lp.pool < p.P && eq(lq, { ...lp, frozen: true }) && eq(f, flow({ hunter: payment(d.payee, 0, p.B, 0) })), 'the freeze bond left other than by an exact freeze']]);
  row('T15_b_returns_only_by_deposit', ok && pp && lp.frozen && !lq.frozen, () => [[rot && op === 'deposit' && f.bIn === p.B, 'the freeze bond returned other than by a deposit bringing B']]);
  row('T15_freeze_makes_inert', ok && kind === 'freeze', () => [[!consumableEver(p, post), 'a freeze left the checkpoint consumable']]);
  // ---- T16: the closer chooses when, never where nor who is paid; the parked hash; payments are named
  const closeFlow = () => { const paidP = p.P <= lp.pool; return flow({ refund: payment(r2 === null ? lp.refundTo : r2, p.D, bHeldOf(p, lp), paidP ? lp.pool - p.P : lp.pool), hunter: paidP ? payment(d.payee, 0, 0, p.P) : null }); };
  row('T16_close_destination', ok && postK === 'parked', () => [
    [kind === 'close' && !!lp && eq(f, closeFlow()) && rotEv && intentOk(env, e1, closeMsg, r2) && hPost.epoch === lp.epoch + 1 && hPost.sn === d["sn'"], 'Parked reached other than by a close under a witnessed rotation and the signed intent naming the payee, paying the premium to the payee and everything else to the resulting refund address']]);
  row('T16_close_needs_rotation', kind === 'close' && stepped && preK === 'present', () => [[!ok || (rotEv && actor === 'nextKeys'), 'a close landed without a witnessed later rotation by the next keys']]);
  row('T16_parked_hash_is_the_closed_checkpoints', ok && kind === 'close' && !!lp, () => [
    [!!hPost && eq(hPost, hashOfLive(rotated(p, lp, d["sn'"], r2))) && hPost.epoch === lp.epoch + 1 && hPost.sn === d["sn'"], 'the parked hash is not the key state the closing rotation reached'],
    [pr.dreg === hi.dreg && pr.b === hi.b && big(pr.pool) + big(ph.pool) === big(hi.pool), 'the close did not pay out exactly what the checkpoint held'],
    [heldZero(ho), 'the parked identity holds value']]);
  const closeMsgs = boundaryOk && e1 !== null ? env.intentAuthorized.filter(rw => rw[0] === e1 && intentKind(rw[1]) === 'close') : [];
  row('T16_copied_reap_refused', kind === 'close' && stepped && !!lp && closeMsgs.length === 1, () => [
    [!ok || (d.payee === closeMsgs[0][1].close.payee && eq(r2, closeMsgs[0][2])), 'a close landed naming a payee or an address the keys did not sign (the copied reap)'],
    [!ok || f.hunter === null || f.hunter.addr === closeMsgs[0][1].close.payee, 'the premium went to someone other than the signed payee']]);
  row('T16_payments_are_named', ok && (f.hunter !== null || f.convictor !== null), () => [
    [f.hunter === null || eq(ph, { dreg: 0, b: 0, pool: p.P }) || eq(ph, { dreg: 0, b: p.B, pool: 0 }), 'a hunter was paid something other than the premium or the freeze bond'],
    [f.convictor === null || eq(pc, { dreg: hi.dreg, b: 0, pool: 0 }), 'a convictor was paid something other than the conviction bond held']]);
  return out;
}
// the page's lamps: the fourteen groups of THEOREMS folded over the rows
function lampsOf(rows) {
  const out = {};
  for (const g of THEOREMS) {
    const rs = g.lean.map(n => rows[n]).filter(Boolean);
    const exhibited = rs.some(r => r.exhibited);
    const notes = rs.filter(r => !r.holds).flatMap(r => r.notes.map(n => r.by[0] + ': ' + n));
    out[g.id] = { exhibited, holds: !notes.length, notes, by: rs.filter(r => r.exhibited).map(r => r.by[0]) };
    if (g.id === 'T7') { out.T7.cell = rows.T7_step_iff_stepFn ? rows.T7_step_iff_stepFn.cell : null; if (!exhibited && rows.T7_step_iff_stepFn && rows.T7_step_iff_stepFn.notes.length) out.T7.notes = rows.T7_step_iff_stepFn.notes; }
  }
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
      const th = record.theorems;   // one row per Lean declaration: exhibits are pinned by name
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
  validateParams, ACTION_KINDS, BOND_OPS, INTENT_KINDS, intentKind, closeIntent, actionKind, normalizeAction, actorOf,
  EV_KINDS, EV_ARITY, EV_SHAPE, emptyEnv, envHas, envAdd, envRemove, envUnion, validateEnv, intentOk, stateKind, liveOf, hashOf, present, parked, payment, flow, held, paid, snOf, leafOf, leafKind, rotated, premium, bHeldOf,
  LIVE_NATS, LIVE_BOOLS, validateState, validateFlow, step, consumable, consumableB, consumableEver, replay, poisonAfter, poisonSinceLastRotation,
  newSession, withParams, addEvidence, removeEvidence, seed, seedOther, stateOfAid, leafOfAid, allAids, setSlot, attempt, heldSoFar,
  MAX_NAT, natAdd, parseNat, lossyJsonNumbers, parseJsonExact, evidenceBits, cellKey, leanCell,
  CAST, whoAddr, STATE_WORDS, stateWord, VERDICT_WORDS, INTENT_WORDS, intentWord, explain, THEOREMS, theoremReport, lampsOf,
  matchesPartial, checkScenario, checkCorpus,
};
