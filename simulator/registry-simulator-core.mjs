/*
 * registry-simulator-core.mjs — THE machine core of the registry simulator:
 * the single transcription of `CardanoKeri.Registry` (the AID registry as an
 * MPFS instance: `stepFn`, `processOne`, `rejectOne`, `applyBatch`,
 * `reapable`, `replay`, `Action.actor`, the phases), the theorems R1–R14 of
 * `CardanoKeri.RegistryGoals` as executable properties over steps, and the
 * scenario / corpus checkers.
 *
 * The JavaScript core is a TRANSCRIPTION of `stepFn`: same actions, same
 * guards in the same conjunction order, same flows, same results, same
 * refusals. Where `stepFn` returns `none`, this core refuses with a named
 * reason: the first failing conjunct in the Lean's own order. Nothing on the
 * page decides anything the core does not decide.
 *
 * Consumed by BOTH production surfaces, with no second transcription:
 *   - registry-simulator.html embeds these exact slices between
 *     @@CORE:<id>@@ markers; registry-simulator-build.mjs regenerates the
 *     page from this file, and the scenario gate REDs when the embedded copy
 *     is stale or forked (byte compare per slice);
 *   - registry-simulator-scenario-gate.mjs imports this module directly.
 *
 * Pure functional surface: no DOM, no storage, no clock. `now` (chain time,
 * a slot) is always an explicit argument. `Env` is four evidence predicates
 * decided by the scenario or by the person playing — never here.
 *
 * Wire shapes (shared byte-for-byte with the Lean driver's ToJson output,
 * `lean/RegistryTraceDriver.lean`):
 *   params := { D, tip, Mc, Mr, process, retract, W, far }
 *   status := { active: tok } | { dormant: k } | "convicted"
 *   ckpt   := { token, k, st }   st := "live" | { parked: since } | "tomb"
 *   op     := "register" | "revive" | { goDormant: k } | "goConvicted" | "convict"
 *   sys    := { gen, plugin, leaves:[{ aid, status }], ckpts:[{ aid, ckpt }],
 *               requests:[{ id, aid, owner, submittedAt, op }], nextReq, nextToken }
 *   action := { contribute: { aid, owner, submittedAt, op } }
 *           | { fold: { folder, gen, plugin, batch:[{ id, do }] } }   do: "process" | "reject"
 *           | { retract: { req } } | { reap: { reaper, aid } }
 *           | { pause: { aid } } | { resume: { aid } } | { convictCkpt: { aid } }
 *   flow   := { deposited, locked:[{ aid, value }], refunds:[{ addr, value }],
 *               tips: null | { addr, value }, premium: null | { addr, value }, intoRequest }
 *   env    := { inception:[aid], rotationFrom:[[aid, k]], duplicity:[[aid, k]], quorum:[aid] }
 */

/* @@CORE:constants@@ */
const SCHEMA = 'cardano-keri.registry.trace';
const VERSION = 2;

/* Refusal reasons, named after the guard that failed, in the Lean's own
   conjunction order. */
const REASONS = {
  INVALID_PARAMS: 'invalid-params',
  INVALID_NAT: 'invalid-nat',
  INVALID_STATE: 'invalid-state',
  INVALID_ACTION: 'invalid-action',
  INVALID_EVIDENCE: 'invalid-evidence',
  NOT_POSTABLE: 'not-postable',             // contribute of a go-request kind: only a reap creates those
  UNKNOWN_REQUEST: 'unknown-request',       // lookup = none (retract, or a batch entry — including one the same batch consumed)
  NOT_IN_PHASE_2: 'not-in-phase-2',         // retract outside phase 2 (never, for a go-request)
  STALE_GENERATION: 'stale-generation',     // fold names a generation other than the registry's
  PLUGIN_NOT_PINNED: 'plugin-not-pinned',   // fold re-creates the cage with another plugin
  EMPTY_FOLD: 'empty-fold',                 // batch = []
  NOT_IN_PHASE_1: 'not-in-phase-1',         // process outside phase 1
  BAD_INCEPTION: 'bad-inception',           // register: env.inception false
  ALREADY_REGISTERED: 'already-registered', // register: the AID has a leaf — the absence proof fails
  NOT_DORMANT: 'not-dormant',               // revive / convict: the leaf is not dormant
  NO_ROTATION: 'no-rotation',               // revive / pause / resume: env.rotationFrom false
  CKPT_EXISTS: 'checkpoint-exists',         // revive while a checkpoint exists
  NOT_ACTIVE: 'not-active',                 // a go-request on a leaf that is not active
  NO_DUPLICITY_PROOF: 'no-duplicity-proof', // convict (dormant) / convictCkpt: env.duplicity false
  NOT_REJECTABLE: 'not-rejectable',         // reject before phase 3 with an honest timestamp
  GO_NOT_REJECTABLE: 'go-not-rejectable',   // the plugin refuses Rejected on a go-request
  NO_CKPT: 'no-checkpoint',                 // reap / pause / resume / convictCkpt: no checkpoint for the AID
  NOT_REAPABLE: 'not-reapable',             // reap: bonded, or parked inside the grace window without the owner
  NOT_LIVE: 'not-live',                     // pause: the checkpoint is not live
  NOT_PARKED: 'not-parked',                 // resume: the checkpoint is not parked
  ALREADY_TOMB: 'already-tombstone',        // convictCkpt on a tombstone
};

/* Which Lean declaration and binder refuses with each reason. */
const LEAN_GUARDS = {
  'not-postable': { decl: 'stepFn (contribute)', text: 'op.userPostable = true' },
  'unknown-request': { decl: 'stepFn / applyBatch', text: 'lookup … = none' },
  'not-in-phase-2': { decl: 'stepFn (retract)', text: 'inPhase2 p r now' },
  'stale-generation': { decl: 'stepFn (fold)', text: 'g = s.gen' },
  'plugin-not-pinned': { decl: 'stepFn (fold)', text: 'pl = s.plugin' },
  'empty-fold': { decl: 'stepFn (fold)', text: 'batch ≠ []' },
  'not-in-phase-1': { decl: 'processOne', text: 'inPhase1 p r now' },
  'bad-inception': { decl: 'processBody (register)', text: 'env.inception r.aid = true' },
  'already-registered': { decl: 'processBody (register)', text: 'lookup acc.leaves r.aid = none' },
  'not-dormant': { decl: 'processBody (revive / convict)', text: 'some (.dormant k)' },
  'no-rotation': { decl: 'processBody (revive) / stepFn (pause, resume)', text: 'env.rotationFrom aid k = true' },
  'checkpoint-exists': { decl: 'processBody (revive)', text: 'lookup acc.ckpts r.aid = none' },
  'not-active': { decl: 'processBody (goDormant / goConvicted)', text: 'some (.active _)' },
  'no-duplicity-proof': { decl: 'processBody (convict) / stepFn (convictCkpt)', text: 'env.duplicity aid k = true' },
  'not-rejectable': { decl: 'rejectOne', text: 'rejectable p r now' },
  'go-not-rejectable': { decl: 'rejectOne', text: 'r.op.userPostable = true' },
  'no-checkpoint': { decl: 'stepFn (reap / pause / resume / convictCkpt)', text: 'lookup s.ckpts aid = some c' },
  'not-reapable': { decl: 'stepFn (reap)', text: 'reapable p env now aid c' },
  'not-live': { decl: 'stepFn (pause)', text: 'some ⟨tok, k, .live⟩' },
  'not-parked': { decl: 'stepFn (resume)', text: 'some ⟨tok, k, .parked _⟩' },
  'already-tombstone': { decl: 'stepFn (convictCkpt)', text: 'st ≠ .tomb' },
};
/* @@CORE:constants:END@@ */

/* @@CORE:machine@@ */
/* --- exact Nat ----------------------------------------------------------- */
const MAX_NAT = Number.MAX_SAFE_INTEGER;
function isNat(x) { return typeof x === 'number' && Number.isInteger(x) && x >= 0 && x <= MAX_NAT; }
const refuse = (reason, field) => ({ ok: false, reason, field });
/* A Lean Nat is unbounded; the transcription is exact to MAX_NAT. A successor,
   a sum or a product that would leave the bound is refused by the field it
   would have written, never rounded (NatOverflow is caught by `step`). */
class NatOverflow extends Error { constructor(field) { super('invalid-nat/' + field); this.field = field; } }
const add = (a, b, field) => { const r = a + b; if (r > MAX_NAT) throw new NatOverflow(field); return r; };
const succ = (a, field) => add(a, 1, field);
const mul = (a, b, field) => { const r = a * b; if (r > MAX_NAT || !Number.isSafeInteger(r)) throw new NatOverflow(field); return r; };

function validateParams(p) {
  if (!p || typeof p !== 'object') return refuse(REASONS.INVALID_PARAMS, 'params');
  for (const k of ['D', 'tip', 'Mc', 'Mr', 'process', 'retract', 'W', 'far'])
    if (!isNat(p[k])) return refuse(REASONS.INVALID_NAT, k);
  if (!(p.D > 0)) return refuse(REASONS.INVALID_PARAMS, 'D must be positive');
  if (!(p.process > 0)) return refuse(REASONS.INVALID_PARAMS, 'process must be positive');
  if (!(p.retract > 0)) return refuse(REASONS.INVALID_PARAMS, 'retract must be positive');
  if (!(p.Mr + p.tip <= p.Mc)) return refuse(REASONS.INVALID_PARAMS, 'Mr + tip must not exceed Mc');
  return null;
}

/* --- shapes ---------------------------------------------------------------- */
function validateStatus(v, field) {
  if (v === 'convicted') return null;
  if (!v || typeof v !== 'object') return refuse(REASONS.INVALID_STATE, field);
  const ks = Object.keys(v);
  if (ks.length !== 1) return refuse(REASONS.INVALID_STATE, field);
  if (ks[0] === 'active' || ks[0] === 'dormant') return isNat(v[ks[0]]) ? null : refuse(REASONS.INVALID_NAT, `${field}.${ks[0]}`);
  return refuse(REASONS.INVALID_STATE, field);
}
function validateCkState(v, field) {
  if (v === 'live' || v === 'tomb') return null;
  if (!v || typeof v !== 'object' || Object.keys(v).length !== 1 || !('parked' in v)) return refuse(REASONS.INVALID_STATE, field);
  return isNat(v.parked) ? null : refuse(REASONS.INVALID_NAT, `${field}.parked`);
}
function validateOp(v, field) {
  if (v === 'register' || v === 'revive' || v === 'goConvicted' || v === 'convict') return null;
  if (!v || typeof v !== 'object' || Object.keys(v).length !== 1 || !('goDormant' in v)) return refuse(REASONS.INVALID_ACTION, field);
  return isNat(v.goDormant) ? null : refuse(REASONS.INVALID_NAT, `${field}.goDormant`);
}
function validateState(s) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return refuse(REASONS.INVALID_STATE, 'state');
  const keys = ['gen', 'plugin', 'leaves', 'ckpts', 'requests', 'nextReq', 'nextToken'];
  for (const k of Object.keys(s)) if (!keys.includes(k)) return refuse(REASONS.INVALID_STATE, k);
  for (const k of ['gen', 'plugin', 'nextReq', 'nextToken']) if (!isNat(s[k])) return refuse(REASONS.INVALID_NAT, k);
  if (!Array.isArray(s.leaves)) return refuse(REASONS.INVALID_STATE, 'leaves');
  for (let i = 0; i < s.leaves.length; i++) {
    const l = s.leaves[i];
    if (!l || typeof l !== 'object') return refuse(REASONS.INVALID_STATE, `leaves[${i}]`);
    for (const k of Object.keys(l)) if (!['aid', 'status'].includes(k)) return refuse(REASONS.INVALID_STATE, `leaves[${i}].${k}`);
    if (!isNat(l.aid)) return refuse(REASONS.INVALID_NAT, `leaves[${i}].aid`);
    const e = validateStatus(l.status, `leaves[${i}].status`); if (e) return e;
  }
  if (!Array.isArray(s.ckpts)) return refuse(REASONS.INVALID_STATE, 'ckpts');
  for (let i = 0; i < s.ckpts.length; i++) {
    const c = s.ckpts[i];
    if (!c || typeof c !== 'object' || !c.ckpt || typeof c.ckpt !== 'object') return refuse(REASONS.INVALID_STATE, `ckpts[${i}]`);
    for (const k of Object.keys(c)) if (!['aid', 'ckpt'].includes(k)) return refuse(REASONS.INVALID_STATE, `ckpts[${i}].${k}`);
    if (!isNat(c.aid)) return refuse(REASONS.INVALID_NAT, `ckpts[${i}].aid`);
    for (const k of Object.keys(c.ckpt)) if (!['token', 'k', 'st'].includes(k)) return refuse(REASONS.INVALID_STATE, `ckpts[${i}].ckpt.${k}`);
    for (const k of ['token', 'k']) if (!isNat(c.ckpt[k])) return refuse(REASONS.INVALID_NAT, `ckpts[${i}].ckpt.${k}`);
    const e = validateCkState(c.ckpt.st, `ckpts[${i}].ckpt.st`); if (e) return e;
  }
  if (!Array.isArray(s.requests)) return refuse(REASONS.INVALID_STATE, 'requests');
  for (let i = 0; i < s.requests.length; i++) {
    const r = s.requests[i];
    if (!r || typeof r !== 'object') return refuse(REASONS.INVALID_STATE, `requests[${i}]`);
    for (const k of Object.keys(r)) if (!['id', 'aid', 'owner', 'submittedAt', 'op'].includes(k)) return refuse(REASONS.INVALID_STATE, `requests[${i}].${k}`);
    for (const k of ['id', 'aid', 'owner', 'submittedAt']) if (!isNat(r[k])) return refuse(REASONS.INVALID_NAT, `requests[${i}].${k}`);
    const e = validateOp(r.op, `requests[${i}].op`); if (e) return e.reason === REASONS.INVALID_ACTION ? refuse(REASONS.INVALID_STATE, e.field) : e;
  }
  return null;
}
function validateEnv(t) {
  if (!t || typeof t !== 'object' || Array.isArray(t)) return refuse(REASONS.INVALID_EVIDENCE, 'env');
  const shapes = { inception: 1, rotationFrom: 2, duplicity: 2, quorum: 1 };
  for (const k of Object.keys(t)) if (!(k in shapes)) return refuse(REASONS.INVALID_EVIDENCE, k);
  for (const k of Object.keys(shapes)) {
    if (t[k] === undefined) continue;
    if (!Array.isArray(t[k])) return refuse(REASONS.INVALID_EVIDENCE, k);
    for (let i = 0; i < t[k].length; i++) {
      const row = t[k][i];
      if (shapes[k] === 1) { if (!isNat(row)) return refuse(REASONS.INVALID_NAT, `${k}[${i}]`); continue; }
      if (!Array.isArray(row) || row.length !== 2) return refuse(REASONS.INVALID_EVIDENCE, `${k}[${i}]`);
      for (let j = 0; j < 2; j++) if (!isNat(row[j])) return refuse(REASONS.INVALID_NAT, `${k}[${i}][${j}]`);
    }
  }
  return null;
}
function validateAction(a) {
  if (!a || typeof a !== 'object' || Array.isArray(a)) return refuse(REASONS.INVALID_ACTION, 'action');
  const tags = Object.keys(a);
  if (tags.length !== 1) return refuse(REASONS.INVALID_ACTION, 'action');
  const tag = tags[0], b = a[tag];
  if (!b || typeof b !== 'object') return refuse(REASONS.INVALID_ACTION, tag);
  const need = (fields, nats) => {
    for (const k of Object.keys(b)) if (!fields.includes(k)) return refuse(REASONS.INVALID_ACTION, `${tag}.${k}`);
    for (const k of nats) if (!isNat(b[k])) return refuse(REASONS.INVALID_NAT, `${tag}.${k}`);
    return null;
  };
  switch (tag) {
    case 'contribute': { const e = need(['aid', 'owner', 'submittedAt', 'op'], ['aid', 'owner', 'submittedAt']); return e || validateOp(b.op, 'contribute.op'); }
    case 'retract': return need(['req'], ['req']);
    case 'reap': return need(['reaper', 'aid'], ['reaper', 'aid']);
    case 'pause': case 'resume': case 'convictCkpt': return need(['aid'], ['aid']);
    case 'fold': {
      const e = need(['folder', 'gen', 'plugin', 'batch'], ['folder', 'gen', 'plugin']); if (e) return e;
      if (!Array.isArray(b.batch)) return refuse(REASONS.INVALID_ACTION, 'fold.batch');
      for (let i = 0; i < b.batch.length; i++) {
        const x = b.batch[i];
        if (!x || typeof x !== 'object') return refuse(REASONS.INVALID_ACTION, `fold.batch[${i}]`);
        for (const k of Object.keys(x)) if (!['id', 'do'].includes(k)) return refuse(REASONS.INVALID_ACTION, `fold.batch[${i}].${k}`);
        if (!isNat(x.id)) return refuse(REASONS.INVALID_NAT, `fold.batch[${i}].id`);
        if (x.do !== 'process' && x.do !== 'reject') return refuse(REASONS.INVALID_ACTION, `fold.batch[${i}].do`);
      }
      return null;
    }
    default: return refuse(REASONS.INVALID_ACTION, tag);
  }
}

/* --- Env: the four evidence predicates --------------------------------- */
function emptyEnv() { return { inception: [], rotationFrom: [], duplicity: [], quorum: [] }; }
function envFromTables(t) {
  const has1 = (k, a) => Array.isArray(t[k]) && t[k].includes(a);
  const has2 = (k, a, b) => Array.isArray(t[k]) && t[k].some(r => r[0] === a && r[1] === b);
  return {
    inception: aid => has1('inception', aid),
    rotationFrom: (aid, k) => has2('rotationFrom', aid, k),
    duplicity: (aid, k) => has2('duplicity', aid, k),
    quorum: aid => has1('quorum', aid),
  };
}

/* --- Op, Status, Action helpers (Registry.lean) -------------------------- */
function userPostable(op) { return op === 'register' || op === 'revive' || op === 'convict'; }
function opBond(p, op) { return op === 'register' || op === 'revive' ? p.D : p.Mr; }
function opTag(op) { return typeof op === 'string' ? op : Object.keys(op)[0]; }
function statusTag(v) { return typeof v === 'string' ? v : Object.keys(v)[0]; }
function ckTag(st) { return typeof st === 'string' ? st : Object.keys(st)[0]; }
function actionActor(a) {
  if (!a || typeof a !== 'object') return null;
  if ('contribute' in a || 'fold' in a || 'reap' in a) return 'anyone';
  if ('retract' in a) return 'owner';
  if ('pause' in a || 'resume' in a) return 'next-keys';
  if ('convictCkpt' in a) return 'proof';
  return null;
}
function actionTag(a) { return a && typeof a === 'object' ? Object.keys(a)[0] : null; }

/* --- phases ---------------------------------------------------------------- */
const phase1End = (p, r) => add(r.submittedAt, p.process, 'submittedAt+process');
const phase2End = (p, r) => add(phase1End(p, r), p.retract, 'submittedAt+process+retract');
function inPhase1(p, r, now) { return now < phase1End(p, r); }
function inPhase2(p, r, now) { return phase1End(p, r) <= now && now < phase2End(p, r); }
function rejectable(p, r, now) { return phase2End(p, r) <= now || now < r.submittedAt; }
function phaseOf(p, r, now) {
  if (now < r.submittedAt) return 'future';
  if (inPhase1(p, r, now)) return 'phase-1';
  if (inPhase2(p, r, now)) return 'phase-2';
  return 'phase-3';
}

/* --- association lists (lookup, remove, setLeaf) ----------------------- */
function lookupReq(rs, id) { const x = rs.find(r => r.id === id); return x ? x : null; }
function lookupLeaf(ls, aid) { const x = ls.find(l => l.aid === aid); return x ? x.status : null; }
function lookupCkpt(cs, aid) { const x = cs.find(c => c.aid === aid); return x ? x.ckpt : null; }
function removeReq(rs, id) { return rs.filter(r => r.id !== id); }
function removeCkpt(cs, aid) { return cs.filter(c => c.aid !== aid); }
function setLeaf(ls, aid, status) { const i = ls.findIndex(l => l.aid === aid); if (i < 0) return ls.slice(); const out = ls.slice(); out[i] = { aid, status }; return out; }

/* --- processBody: the plugin's body (Registry.lean) ----------------------- */
function processBody(p, env, acc, r) {
  const op = opTag(r.op);
  const leaf = lookupLeaf(acc.leaves, r.aid);
  if (op === 'register') {
    if (env.inception(r.aid) !== true) return { ok: false, reason: REASONS.BAD_INCEPTION };
    if (leaf !== null) return { ok: false, reason: REASONS.ALREADY_REGISTERED };
    return { ok: true, acc: { ...acc, leaves: [{ aid: r.aid, status: { active: acc.nextToken } }, ...acc.leaves],
      ckpts: [{ aid: r.aid, ckpt: { token: acc.nextToken, k: 0, st: 'live' } }, ...acc.ckpts],
      nextToken: succ(acc.nextToken, 'nextToken'), locked: [...acc.locked, { aid: r.aid, value: p.D }] } };
  }
  if (op === 'revive') {
    if (leaf === null || statusTag(leaf) !== 'dormant') return { ok: false, reason: REASONS.NOT_DORMANT };
    const k = leaf.dormant;
    if (env.rotationFrom(r.aid, k) !== true) return { ok: false, reason: REASONS.NO_ROTATION };
    if (lookupCkpt(acc.ckpts, r.aid) !== null) return { ok: false, reason: REASONS.CKPT_EXISTS };
    return { ok: true, acc: { ...acc, leaves: setLeaf(acc.leaves, r.aid, { active: acc.nextToken }),
      ckpts: [{ aid: r.aid, ckpt: { token: acc.nextToken, k: succ(k, 'k'), st: 'live' } }, ...acc.ckpts],
      nextToken: succ(acc.nextToken, 'nextToken'), locked: [...acc.locked, { aid: r.aid, value: p.D }] } };
  }
  if (op === 'goDormant') {
    if (leaf === null || statusTag(leaf) !== 'active') return { ok: false, reason: REASONS.NOT_ACTIVE };
    return { ok: true, acc: { ...acc, leaves: setLeaf(acc.leaves, r.aid, { dormant: r.op.goDormant }),
      refunds: [...acc.refunds, { addr: r.owner, value: p.Mr }] } };
  }
  if (op === 'goConvicted') {
    if (leaf === null || statusTag(leaf) !== 'active') return { ok: false, reason: REASONS.NOT_ACTIVE };
    return { ok: true, acc: { ...acc, leaves: setLeaf(acc.leaves, r.aid, 'convicted'),
      refunds: [...acc.refunds, { addr: r.owner, value: p.Mr }] } };
  }
  /* convict */
  if (leaf === null || statusTag(leaf) !== 'dormant') return { ok: false, reason: REASONS.NOT_DORMANT };
  if (env.duplicity(r.aid, leaf.dormant) !== true) return { ok: false, reason: REASONS.NO_DUPLICITY_PROOF };
  return { ok: true, acc: { ...acc, leaves: setLeaf(acc.leaves, r.aid, 'convicted'),
    refunds: [...acc.refunds, { addr: r.owner, value: p.Mr }] } };
}
function processOne(p, env, now, acc, r) {
  if (!inPhase1(p, r, now)) return { ok: false, reason: REASONS.NOT_IN_PHASE_1 };
  return processBody(p, env, acc, r);
}
function rejectOne(p, now, acc, r) {
  if (!rejectable(p, r, now)) return { ok: false, reason: REASONS.NOT_REJECTABLE };
  if (!userPostable(r.op)) return { ok: false, reason: REASONS.GO_NOT_REJECTABLE };
  return { ok: true, acc: { ...acc, refunds: [...acc.refunds, { addr: r.owner, value: opBond(p, r.op) }] } };
}

/* --- applyBatch ----------------------------------------------------------- */
function applyBatch(p, env, now, acc0, batch) {
  let acc = { leaves: acc0.leaves.slice(), ckpts: acc0.ckpts.slice(), requests: acc0.requests.slice(),
              nextToken: acc0.nextToken, locked: acc0.locked.slice(), refunds: acc0.refunds.slice() };
  for (let i = 0; i < batch.length; i++) {
    const { id, do: fa } = batch[i];
    const r = lookupReq(acc.requests, id);
    if (!r) return { ok: false, reason: REASONS.UNKNOWN_REQUEST, at: i };
    const acc1 = { ...acc, requests: removeReq(acc.requests, id) };
    const res = fa === 'process' ? processOne(p, env, now, acc1, r) : rejectOne(p, now, acc1, r);
    if (!res.ok) return { ok: false, reason: res.reason, at: i };
    acc = res.acc;
  }
  return { ok: true, acc };
}

/* The accumulator trajectory of a batch: element i sees accs[i] (its own
   request already taken out, as applyBatch does), so a property about an
   element reads the accumulator, never the pre-state. Stops after the first
   failure. */
function batchView(p, envTable, now, before, batch) {
  const env = envFromTables(envTable);
  let acc = { leaves: before.leaves.slice(), ckpts: before.ckpts.slice(), requests: before.requests.slice(), nextToken: before.nextToken, locked: [], refunds: [] };
  const view = [];
  for (let i = 0; i < batch.length; i++) {
    const { id, do: fa } = batch[i];
    const r = lookupReq(acc.requests, id);
    if (!r) { view.push({ i, r: null, acc, res: { ok: false, reason: REASONS.UNKNOWN_REQUEST } }); break; }
    const acc1 = { ...acc, requests: removeReq(acc.requests, id) };
    let res;
    try { res = fa === 'process' ? processOne(p, env, now, acc1, r) : rejectOne(p, now, acc1, r); }
    catch (e) { if (e instanceof NatOverflow) res = { ok: false, reason: REASONS.INVALID_NAT, field: e.field }; else throw e; }
    view.push({ i, r, fa, acc: acc1, res });
    if (!res.ok) break;
    acc = res.acc;
  }
  return view;
}

function flow(o) { return { deposited: 0, locked: [], refunds: [], tips: null, premium: null, intoRequest: 0, ...o }; }

/* --- reapable, goOp ---------------------------------------------------- */
function reapableReason(p, env, now, aid, c) {
  const t = ckTag(c.st);
  if (t === 'live') return REASONS.NOT_REAPABLE;
  if (t === 'tomb') return null;
  return (add(c.st.parked, p.W, 'parked+W') <= now || env.quorum(aid) === true) ? null : REASONS.NOT_REAPABLE;
}
function goOp(c) { return ckTag(c.st) === 'tomb' ? 'goConvicted' : { goDormant: c.k }; }

/* --- step: the transcription of `stepFn` --------------------------------- */
function step(params, envTable, action, now, state) {
  try { return stepBody(params, envTable, action, now, state); }
  catch (e) { if (e instanceof NatOverflow) return refuse(REASONS.INVALID_NAT, e.field); throw e; }
}
function stepBody(params, envTable, action, now, state) {
  const ep = validateParams(params); if (ep) return ep;
  if (!isNat(now)) return refuse(REASONS.INVALID_NAT, 'now');
  const ea = validateAction(action); if (ea) return ea;
  const es = validateState(state); if (es) return es;
  const ee = validateEnv(envTable); if (ee) return ee;
  const env = envFromTables(envTable);
  const s = state, p = params, a = action;
  if ('contribute' in a) {
    const { aid, owner, submittedAt, op } = a.contribute;
    if (!userPostable(op)) return refuse(REASONS.NOT_POSTABLE);
    return { ok: true, flow: flow({ deposited: add(opBond(p, op), p.tip, 'deposited') }),
             state: { ...s, requests: [{ id: s.nextReq, aid, owner, submittedAt, op }, ...s.requests], nextReq: succ(s.nextReq, 'nextReq') } };
  }
  if ('retract' in a) {
    const r = lookupReq(s.requests, a.retract.req);
    if (!r) return refuse(REASONS.UNKNOWN_REQUEST);
    if (!inPhase2(p, r, now)) return refuse(REASONS.NOT_IN_PHASE_2);
    return { ok: true, flow: flow({ refunds: [{ addr: r.owner, value: add(opBond(p, r.op), p.tip, 'refunds') }] }),
             state: { ...s, requests: removeReq(s.requests, a.retract.req) } };
  }
  if ('fold' in a) {
    const { folder, gen, plugin, batch } = a.fold;
    if (!(gen === s.gen)) return refuse(REASONS.STALE_GENERATION);
    if (!(plugin === s.plugin)) return refuse(REASONS.PLUGIN_NOT_PINNED);
    if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD);
    const r = applyBatch(p, env, now, { leaves: s.leaves, ckpts: s.ckpts, requests: s.requests, nextToken: s.nextToken, locked: [], refunds: [] }, batch);
    if (!r.ok) return { ok: false, reason: r.reason, at: r.at };
    return { ok: true,
             flow: flow({ locked: r.acc.locked, refunds: r.acc.refunds, tips: { addr: folder, value: mul(batch.length, p.tip, 'tips') } }),
             state: { ...s, gen: succ(s.gen, 'gen'), leaves: r.acc.leaves, ckpts: r.acc.ckpts, requests: r.acc.requests, nextToken: r.acc.nextToken } };
  }
  if ('reap' in a) {
    const { reaper, aid } = a.reap;
    const c = lookupCkpt(s.ckpts, aid);
    if (!c) return refuse(REASONS.NO_CKPT);
    const why = reapableReason(p, env, now, aid, c);
    if (why) return refuse(why);
    return { ok: true,
             flow: flow({ premium: { addr: reaper, value: p.Mc - p.Mr - p.tip }, intoRequest: p.Mr + p.tip }),
             state: { ...s, ckpts: removeCkpt(s.ckpts, aid),
                      requests: [{ id: s.nextReq, aid, owner: reaper, submittedAt: p.far, op: goOp(c) }, ...s.requests],
                      nextReq: succ(s.nextReq, 'nextReq') } };
  }
  if ('pause' in a) {
    const { aid } = a.pause;
    const c = lookupCkpt(s.ckpts, aid);
    if (!c) return refuse(REASONS.NO_CKPT);
    if (ckTag(c.st) !== 'live') return refuse(REASONS.NOT_LIVE);
    if (env.rotationFrom(aid, c.k) !== true) return refuse(REASONS.NO_ROTATION);
    return { ok: true, flow: flow({}),
             state: { ...s, ckpts: [{ aid, ckpt: { token: c.token, k: succ(c.k, 'k'), st: { parked: now } } }, ...removeCkpt(s.ckpts, aid)] } };
  }
  if ('resume' in a) {
    const { aid } = a.resume;
    const c = lookupCkpt(s.ckpts, aid);
    if (!c) return refuse(REASONS.NO_CKPT);
    if (ckTag(c.st) !== 'parked') return refuse(REASONS.NOT_PARKED);
    if (env.rotationFrom(aid, c.k) !== true) return refuse(REASONS.NO_ROTATION);
    return { ok: true, flow: flow({}),
             state: { ...s, ckpts: [{ aid, ckpt: { token: c.token, k: succ(c.k, 'k'), st: 'live' } }, ...removeCkpt(s.ckpts, aid)] } };
  }
  if ('convictCkpt' in a) {
    const { aid } = a.convictCkpt;
    const c = lookupCkpt(s.ckpts, aid);
    if (!c) return refuse(REASONS.NO_CKPT);
    if (ckTag(c.st) === 'tomb') return refuse(REASONS.ALREADY_TOMB);
    if (env.duplicity(aid, c.k) !== true) return refuse(REASONS.NO_DUPLICITY_PROOF);
    return { ok: true, flow: flow({}),
             state: { ...s, ckpts: [{ aid, ckpt: { token: c.token, k: c.k, st: 'tomb' } }, ...removeCkpt(s.ckpts, aid)] } };
  }
  return refuse(REASONS.INVALID_ACTION, 'action');
}

/* --- replay ---------------------------------------------------------------- */
function replay(params, envTable, t0, state, steps) {
  if (!isNat(t0)) return refuse(REASONS.INVALID_NAT, 't0');
  if (!Array.isArray(steps)) return refuse(REASONS.INVALID_ACTION, 'list');
  let t = t0, s = state;
  for (let i = 0; i < steps.length; i++) {
    const e = steps[i];
    if (!Array.isArray(e) || e.length !== 2) return refuse(REASONS.INVALID_ACTION, `list[${i}]`);
    const [t2, action] = e;
    if (!isNat(t2)) return refuse(REASONS.INVALID_NAT, 'slot');
    if (!(t <= t2)) return { ok: false, at: i, reason: 'slot-decreased' };
    const r = step(params, envTable, action, t2, s);
    if (!r.ok) return { ok: false, at: i, reason: r.reason, field: r.field };
    s = r.state; t = t2;
  }
  return { ok: true, state: s };
}

function initSys(plugin) { return { gen: 0, plugin, leaves: [], ckpts: [], requests: [], nextReq: 0, nextToken: 0 }; }
function goPending(s, aid) { return s.requests.some(r => r.aid === aid && !userPostable(r.op)); }
/* @@CORE:machine:END@@ */

/* @@CORE:theorems@@ */
/* --- R1–R14 as executable properties over one step record ---------------- */
const nodup = l => new Set(l).size === l.length;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const foldOf = a => (a && a.fold) || null;
const reqOf = (s, id) => lookupReq(s.requests, id);
const isFoldNow = (f, before) => f && f.gen === before.gen && f.plugin === before.plugin;

const THEOREMS = [
  { id: 'R1', title: 'leaf and checkpoint: a checkpoint implies an active leaf; an active leaf has its checkpoint or a pending go-request; dormant and convicted leaves have none', lean: 'R1_ckpt_implies_active, R1_active_ckpt_or_go, R1_not_active_no_ckpt',
    check: ({ result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state;
      for (const c of s.ckpts) { const l = lookupLeaf(s.leaves, c.aid); if (!l || statusTag(l) !== 'active') return { v: 'fails', why: `checkpoint ${c.aid} without an active leaf` }; }
      for (const l of s.leaves) {
        if (statusTag(l.status) === 'active' && !lookupCkpt(s.ckpts, l.aid) && !goPending(s, l.aid)) return { v: 'fails', why: `active leaf ${l.aid} with neither checkpoint nor go-request` };
        if (statusTag(l.status) !== 'active' && lookupCkpt(s.ckpts, l.aid)) return { v: 'fails', why: `${statusTag(l.status)} leaf ${l.aid} with a checkpoint` };
      }
      return s.leaves.length ? { v: 'holds' } : { v: 'n/a' };
    } },
  { id: 'R1d', title: 'a registered AID cannot be registered again (mint-once, ever) — at any position of a batch', lean: 'R1_registered_refused',
    check: ({ before, action, now, result, params, env }) => {
      const f = foldOf(action); if (!isFoldNow(f, before)) return { v: 'n/a' };
      const hit = batchView(params, env, now, before, f.batch).find(v => v.r && v.fa === 'process' && opTag(v.r.op) === 'register' && lookupLeaf(v.acc.leaves, v.r.aid) !== null);
      if (!hit) return { v: 'n/a' };
      return result.ok ? { v: 'fails', why: 'registered an AID that has a leaf' } : { v: 'holds' };
    } },
  { id: 'R2', title: 'at most one checkpoint, one leaf, one go-request per AID', lean: 'R2_one_ckpt_per_aid, R2_one_leaf_per_aid, R2_one_go_per_aid',
    check: ({ result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state;
      if (!nodup(s.ckpts.map(c => c.aid))) return { v: 'fails', why: 'two checkpoints for one AID' };
      if (!nodup(s.leaves.map(l => l.aid))) return { v: 'fails', why: 'two leaves for one AID' };
      if (!nodup(s.requests.filter(r => !userPostable(r.op)).map(r => r.aid))) return { v: 'fails', why: 'two go-requests for one AID' };
      return s.leaves.length ? { v: 'holds' } : { v: 'n/a' };
    } },
  { id: 'R3', title: 'conviction is permanent: a convicted leaf never changes and the AID is never registered again', lean: 'R3_convicted_permanent, R3_convicted_never_registered',
    check: ({ before, action, now, result, params, env }) => {
      const conv = before.leaves.filter(l => l.status === 'convicted').map(l => l.aid);
      if (result.ok) {
        for (const aid of conv) if (lookupLeaf(result.state.leaves, aid) !== 'convicted') return { v: 'fails', why: `convicted leaf ${aid} changed` };
        return conv.length ? { v: 'holds' } : { v: 'n/a' };
      }
      const f = foldOf(action);
      if (isFoldNow(f, before) && batchView(params, env, now, before, f.batch).some(v => v.r && v.fa === 'process' && opTag(v.r.op) === 'register' && lookupLeaf(v.acc.leaves, v.r.aid) === 'convicted')) return { v: 'holds' };
      return { v: 'n/a' };
    } },
  { id: 'R4', title: 'leaves are permanent: a leaf never leaves the root', lean: 'R4_leaf_permanent',
    check: ({ before, result }) => {
      if (!result.ok) return { v: 'n/a' };
      for (const l of before.leaves) if (lookupLeaf(result.state.leaves, l.aid) === null) return { v: 'fails', why: `leaf ${l.aid} left the root` };
      return before.leaves.length ? { v: 'holds' } : { v: 'n/a' };
    } },
  { id: 'R5', title: 'the plugin is pinned', lean: 'R5_plugin_pinned',
    check: ({ before, action, result }) => {
      if (result.ok) return result.state.plugin === before.plugin ? { v: 'holds' } : { v: 'fails', why: 'plugin changed' };
      const f = foldOf(action);
      if (f && f.gen === before.gen && f.plugin !== before.plugin) return result.reason === REASONS.PLUGIN_NOT_PINNED ? { v: 'holds' } : { v: 'fails', why: `refused for ${result.reason}` };
      return { v: 'n/a' };
    } },
  { id: 'R6', title: 'the generation moves exactly on the fold; contribute, retract, reap, pause, resume and a checkpoint conviction never write the registry', lean: 'R6_gen_step, R6_registry_untouched, R6_fold_advances',
    check: ({ before, action, result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state, tag = actionTag(action);
      if (tag === 'fold') return s.gen === before.gen + 1 ? { v: 'holds' } : { v: 'fails', why: 'fold without a generation step' };
      if (s.gen !== before.gen || s.plugin !== before.plugin || !same(s.leaves, before.leaves)) return { v: 'fails', why: `${tag} wrote the registry` };
      return { v: 'holds' };
    } },
  { id: 'R7', title: 'a stale fold is refused with no state change; one fold per generation', lean: 'R7_stale_fold_refused, R7_one_fold_per_generation',
    check: ({ before, action, result }) => {
      const f = foldOf(action); if (!f || f.gen === before.gen) return { v: 'n/a' };
      return !result.ok && result.reason === REASONS.STALE_GENERATION ? { v: 'holds' } : { v: 'fails', why: result.ok ? 'stale fold applied' : `refused for ${result.reason}` };
    } },
  { id: 'R8', title: 'an empty fold is refused; a fold that re-creates the cage with another plugin is refused', lean: 'R8_empty_fold_refused, R8_plugin_swap_refused',
    check: ({ before, action, result }) => {
      const f = foldOf(action); if (!f || f.gen !== before.gen) return { v: 'n/a' };
      if (f.plugin !== before.plugin) return !result.ok && result.reason === REASONS.PLUGIN_NOT_PINNED ? { v: 'holds' } : { v: 'fails', why: result.ok ? 'plugin swap applied' : `refused for ${result.reason}` };
      if (f.batch.length) return { v: 'n/a' };
      return !result.ok && result.reason === REASONS.EMPTY_FOLD ? { v: 'holds' } : { v: 'fails', why: result.ok ? 'empty fold applied' : `refused for ${result.reason}` };
    } },
  { id: 'R9', title: 'requester exit: a posted request retracts in phase 2 and is rejected when rejectable; a go-request is never retracted and never rejected, so k is never lost', lean: 'R9_retract_enabled, R9_retract_needs_phase2, R9_reject_enabled, R9_reject_needs_rejectable, R9_go_never_retracted, R9_go_never_rejected',
    check: ({ before, action, now, result, params }) => {
      if (action.retract) {
        const r = reqOf(before, action.retract.req); if (!r) return { v: 'n/a' };
        const want = inPhase2(params, r, now) && (userPostable(r.op) || now >= params.far);
        if (!userPostable(r.op) && now < params.far && result.ok) return { v: 'fails', why: 'a go-request was retracted' };
        if (want !== result.ok) return { v: 'fails', why: want ? 'retract refused in phase 2' : 'retract applied outside phase 2' };
        return { v: 'holds' };
      }
      const f = foldOf(action);
      if (isFoldNow(f, before)) {
        const go = f.batch.find(x => x.do === 'reject' && reqOf(before, x.id) && !userPostable(reqOf(before, x.id).op));
        if (go) return !result.ok ? { v: 'holds' } : { v: 'fails', why: 'a go-request was rejected' };
        if (f.batch.length === 1 && f.batch[0].do === 'reject') {
          const r = reqOf(before, f.batch[0].id); if (!r) return { v: 'n/a' };
          const want = rejectable(params, r, now);
          if (want !== result.ok) return { v: 'fails', why: want ? 'reject refused when rejectable' : 'reject applied when not rejectable' };
          return { v: 'holds' };
        }
      }
      return { v: 'n/a' };
    } },
  { id: 'R10', title: 'the phases are exclusive', lean: 'R10_phase1_phase2_exclusive, R10_phase2_reject_exclusive, R10_honest_phase1_reject_exclusive',
    check: ({ before, now, params }) => {
      if (!before.requests.length) return { v: 'n/a' };
      for (const r of before.requests) {
        const p1 = inPhase1(params, r, now), p2 = inPhase2(params, r, now), rj = rejectable(params, r, now);
        if (p1 && p2) return { v: 'fails', why: `request ${r.id} in phases 1 and 2` };
        if (p2 && rj) return { v: 'fails', why: `request ${r.id} in phase 2 and rejectable` };
        if (r.submittedAt <= now && p1 && rj) return { v: 'fails', why: `honest request ${r.id} in phase 1 and rejectable` };
      }
      return { v: 'holds' };
    } },
  { id: 'R11', title: 'value: D locked per registration or revival; bonds refunded to request owners; tips per request; a go-request refunds its min-ADA to the reaper; a reap moves exactly the checkpoint min-ADA', lean: 'R11_go_refunds_reaper, R11_reap_flow, R11_reap_is_samaritan, R11_samaritan_never_loses, R11_contribute_value, R11_retract_value, R11_ckpt_edges_move_no_value',
    check: ({ before, action, now, result, params, env }) => {
      if (!result.ok) return { v: 'n/a' };
      const fl = result.flow, tag = actionTag(action);
      const B = x => BigInt(x);
      if (tag === 'fold') {
        const f = action.fold;
        // the exact flow every position of the batch owes, from the accumulator it saw
        const locked = [], refunds = [];
        for (const v of batchView(params, env, now, before, f.batch)) {
          if (!v.r || !v.res.ok) return { v: 'fails', why: 'an applied fold has a failing position' };
          const op = opTag(v.r.op);
          if (v.fa === 'reject') refunds.push({ addr: v.r.owner, value: opBond(params, v.r.op) });
          else if (op === 'register' || op === 'revive') locked.push({ aid: v.r.aid, value: params.D });
          else refunds.push({ addr: v.r.owner, value: params.Mr });
        }
        if (!same(fl.locked, locked)) return { v: 'fails', why: `locked ${JSON.stringify(fl.locked)}, owed ${JSON.stringify(locked)}` };
        if (!same(fl.refunds, refunds)) return { v: 'fails', why: `refunds ${JSON.stringify(fl.refunds)}, owed ${JSON.stringify(refunds)}` };
        if (!fl.tips || fl.tips.addr !== f.folder || B(fl.tips.value) !== B(f.batch.length) * B(params.tip)) return { v: 'fails', why: 'tips are not tip per request to the folder' };
        if (fl.deposited !== 0 || fl.premium !== null || fl.intoRequest !== 0) return { v: 'fails', why: 'a fold moved value it does not own' };
        return { v: 'holds' };
      }
      if (tag === 'reap') {
        const ok = fl.premium && fl.premium.addr === action.reap.reaper && B(fl.premium.value) === B(params.Mc) - B(params.Mr) - B(params.tip) && B(fl.intoRequest) === B(params.Mr) + B(params.tip) && B(fl.premium.value) + B(fl.intoRequest) === B(params.Mc)
          && fl.deposited === 0 && fl.locked.length === 0 && fl.refunds.length === 0 && fl.tips === null;
        return ok ? { v: 'holds' } : { v: 'fails', why: 'the reap does not split exactly Mc' };
      }
      if (tag === 'retract') {
        const r = reqOf(before, action.retract.req);
        return same(fl, flow({ refunds: [{ addr: r.owner, value: opBond(params, r.op) + params.tip }] })) ? { v: 'holds' } : { v: 'fails', why: 'retract did not return bond + tip' };
      }
      if (tag === 'contribute') return same(fl, flow({ deposited: opBond(params, action.contribute.op) + params.tip })) ? { v: 'holds' } : { v: 'fails', why: 'contribute did not deposit bond + tip' };
      return same(fl, flow({})) ? { v: 'holds' } : { v: 'fails', why: `${tag} moved request value` };
    } },
  { id: 'R12', title: 'a leaf enters and changes only by a fold', lean: 'R12_leaf_enters_only_by_fold, R12_leaf_changes_only_by_fold',
    check: ({ before, action, result }) => {
      if (!result.ok) return { v: 'n/a' };
      const tag = actionTag(action);
      if (!same(result.state.leaves, before.leaves) && tag !== 'fold') return { v: 'fails', why: `leaves changed by ${tag}` };
      return tag === 'fold' && !same(result.state.leaves, before.leaves) ? { v: 'holds' } : { v: 'n/a' };
    } },
  { id: 'R13', title: 'the reap: never a bonded checkpoint; a tombstone at once; a parked checkpoint by a stranger only after the grace window, by the owner at any time', lean: 'R13_live_never_reaped, R13_tomb_reaped, R13_parked_needs_grace, R13_parked_after_grace, R13_owner_reaps_early',
    check: ({ before, action, now, result, params, env }) => {
      if (!action.reap) return { v: 'n/a' };
      const { aid, reaper } = action.reap;
      const c = lookupCkpt(before.ckpts, aid); if (!c) return { v: 'n/a' };
      const t = ckTag(c.st);
      const want = t === 'tomb' || (t === 'parked' && (BigInt(c.st.parked) + BigInt(params.W) <= BigInt(now) || (env && Array.isArray(env.quorum) && env.quorum.includes(aid))));
      if (want !== result.ok) return { v: 'fails', why: want ? `reap refused (${result.reason})` : 'reap applied on a bonded or graced checkpoint' };
      if (result.ok) {
        const s = result.state;
        if (lookupCkpt(s.ckpts, aid) !== null) return { v: 'fails', why: 'the reaped checkpoint is still there' };
        const go = s.requests.find(r => r.aid === aid && !userPostable(r.op));
        if (!go || go.owner !== reaper || go.submittedAt !== params.far || !same(go.op, goOp(c))) return { v: 'fails', why: 'the reap did not post the go-request it owes (owner reaper, dated far, go → ' + JSON.stringify(goOp(c)) + ')' };
        if (!same(s.leaves, before.leaves) || s.gen !== before.gen) return { v: 'fails', why: 'a reap wrote the registry' };
      }
      return { v: 'holds' };
    } },
  { id: 'R14', title: 'every conviction needs a duplicity proof against the recorded key state — a checkpoint, or a dormant AID at any position of a batch', lean: 'R14_convictCkpt_needs_proof, R14_convict_dormant_needs_proof, R14_convict_in_batch_needs_proof',
    check: ({ before, action, now, result, params, env }) => {
      const has = (aid, k) => !!(env && Array.isArray(env.duplicity) && env.duplicity.some(r => r[0] === aid && r[1] === k));
      if (action.convictCkpt) {
        const c = lookupCkpt(before.ckpts, action.convictCkpt.aid); if (!c || ckTag(c.st) === 'tomb') return { v: 'n/a' };
        if (!has(action.convictCkpt.aid, c.k)) return result.ok ? { v: 'fails', why: 'a checkpoint was convicted without a proof' } : { v: 'holds' };
        return { v: 'n/a' };
      }
      const f = foldOf(action); if (!isFoldNow(f, before)) return { v: 'n/a' };
      for (const v of batchView(params, env, now, before, f.batch)) {
        if (!v.r || v.fa !== 'process' || opTag(v.r.op) !== 'convict') continue;
        const leaf = lookupLeaf(v.acc.leaves, v.r.aid); if (!leaf || statusTag(leaf) !== 'dormant') continue;
        if (!has(v.r.aid, leaf.dormant)) return result.ok ? { v: 'fails', why: 'a dormant AID was convicted without a proof' } : { v: 'holds' };
      }
      return { v: 'n/a' };
    } },
];

function checkTheorems(rec) {
  const out = {};
  for (const t of THEOREMS) {
    try { out[t.id] = t.check(rec); } catch (e) { out[t.id] = { v: 'fails', why: `threw: ${e.message}` }; }
  }
  return out;
}
/* @@CORE:theorems:END@@ */

/* @@CORE:verify@@ */
function canonicalJson(x) {
  if (Array.isArray(x)) return '[' + x.map(canonicalJson).join(',') + ']';
  if (x !== null && typeof x === 'object') {
    const ks = Object.keys(x).filter(k => x[k] !== undefined).sort();
    return '{' + ks.map(k => JSON.stringify(k) + ':' + canonicalJson(x[k])).join(',') + '}';
  }
  return JSON.stringify(x);
}
const sameJson = (a, b) => canonicalJson(a) === canonicalJson(b);
function normFlow(f) { return flow(f || {}); }

/* --- the scenario checker --------------------------------------------------- */
/* A scenario is a tree: a trunk and forks, each departing after `at` trunk
   steps (state and slot of the trunk prefix; a fork may bring its own env —
   another world). Every step carries expectations (ok/reason, flow, state,
   exhibits). The corpus, when given, is the Lean oracle per cell: trunk cells
   `steps[i]`, fork cells `forks[id].steps[i]` (label f<id>.<i>). */
function checkScenario(sc, file, corpus) {
  const problems = [], asserted = [], exhibited = [], timeline = [], forkTimelines = {};
  const fail = m => problems.push(`${sc && sc.slug ? sc.slug : file}: ${m}`);
  const done = (extra = {}) => ({ problems, asserted, exhibited, stepsRun: timeline.length + Object.values(forkTimelines).reduce((n, t) => n + t.length, 0), timeline, forkTimelines, ...extra });
  if (!sc || typeof sc.id !== 'number' || !sc.slug || !sc.story) { fail('bad header'); return done(); }
  if (validateParams(sc.params)) { fail('bad params'); return done(); }
  if (!Array.isArray(sc.steps) || !sc.steps.length) { fail('no steps'); return done(); }
  const storyCells = corpus && corpus.stories ? (corpus.stories.find(x => x.id === sc.id) || null) : null;
  const runBranch = (label, steps, s0, t0, env, cells, tl) => {
    let s = s0, t = t0;
    const states = [s0];
    for (let i = 0; i < steps.length; i++) {
      const st = steps[i], tag = `${label}step ${i}`;
      if (!isNat(st.now) || !(t <= st.now)) { fail(`${tag}: slot not non-decreasing`); break; }
      t = st.now;
      if (st.actor !== undefined && actionActor(st.action) !== st.actor) fail(`${tag}: actor «${st.actor}» ≠ ${actionActor(st.action)}`);
      const r = step(sc.params, env, st.action, st.now, s);
      const exp = st.expect || { ok: true };
      const rec = { before: s, action: st.action, now: st.now, result: r, params: sc.params, env };
      const th = (!r.ok && String(r.reason).startsWith('invalid')) ? {} : checkTheorems(rec);
      for (const id of Object.keys(th)) if (th[id].v === 'fails') fail(`${tag}: theorem ${id} fails — ${th[id].why}`);
      for (const id of st.exhibits || []) {
        if (!THEOREMS.some(x => x.id === id)) { fail(`${tag}: unknown theorem ${id}`); continue; }
        if (!th[id] || th[id].v !== 'holds') fail(`${tag}: claims to exhibit ${id} but it is ${th[id] ? th[id].v : 'a boundary refusal'}`);
        else exhibited.push(id);
      }
      if (cells) {
        const c = cells[i];
        if (!c) fail(`${tag}: no Lean cell`);
        else {
          if ((c.result !== null) !== r.ok) fail(`${tag}: Lean ${c.result ? 'applied' : 'refused'}, core ${r.ok ? 'applied' : 'refused'}`);
          else if (r.ok && (!sameJson(normFlow(c.result.flow), normFlow(r.flow)) || !sameJson(c.result.state, r.state))) fail(`${tag}: Lean and core disagree on the result`);
          if (!sameJson(c.input, s) || !sameJson(c.action, st.action) || c.now !== st.now) fail(`${tag}: Lean cell input differs from the story's`);
        }
      }
      tl.push({ i, now: st.now, action: st.action, result: r, theorems: th, branch: label ? label.replace(/\W+$/, '') : 'trunk' });
      if (!r.ok && exp.ok !== false) { fail(`${tag}: refused (${r.reason}${r.field ? '/' + r.field : ''}), expected applied`); break; }
      if (r.ok && exp.ok === false) { fail(`${tag}: applied, expected refusal ${exp.reason || ''}`); break; }
      if (!r.ok) {
        if (exp.reason && exp.reason !== r.reason) { fail(`${tag}: refused ${r.reason}, expected ${exp.reason}`); break; }
        if (exp.reason) asserted.push(exp.reason);
        states.push(s);
        continue;
      }
      if (exp.flow !== undefined && !sameJson(normFlow(exp.flow), normFlow(r.flow))) { fail(`${tag}: flow ${canonicalJson(normFlow(r.flow))} ≠ expected ${canonicalJson(normFlow(exp.flow))}`); break; }
      if (exp.state !== undefined && !sameJson(exp.state, r.state)) { fail(`${tag}: state ${canonicalJson(r.state)} ≠ expected ${canonicalJson(exp.state)}`); break; }
      s = r.state;
      states.push(s);
    }
    return { final: s, states, t };
  };
  const env = { ...emptyEnv(), ...(sc.env || {}) };
  const s0 = sc.initial || initSys(isNat(sc.plugin) ? sc.plugin : 7);
  const trunk = runBranch('', sc.steps, s0, 0, env, storyCells ? storyCells.steps : null, timeline);
  if (!problems.length && sc.expectFinal !== undefined && !sameJson(sc.expectFinal, trunk.final)) fail(`final state ${canonicalJson(trunk.final)} ≠ expected ${canonicalJson(sc.expectFinal)}`);
  const forks = Array.isArray(sc.forks) ? sc.forks : [];
  const ids = new Set();
  for (const fk of forks) {
    if (!fk || typeof fk.id !== 'string' || !fk.id || ids.has(fk.id)) { fail(`fork ${fk && fk.id}: needs a unique string id`); continue; }
    ids.add(fk.id);
    if (!isNat(fk.at) || fk.at > sc.steps.length || fk.at >= trunk.states.length) { fail(`fork ${fk.id}: departs after ${fk.at}, the trunk has ${trunk.states.length - 1} played steps`); continue; }
    if (!Array.isArray(fk.steps) || !fk.steps.length) { fail(`fork ${fk.id}: no steps`); continue; }
    const fenv = fk.env ? { ...emptyEnv(), ...fk.env } : env;
    const t0 = fk.at === 0 ? 0 : sc.steps[fk.at - 1].now;
    const cells = storyCells ? ((storyCells.forks || []).find(x => x.id === fk.id) || {}).steps || null : null;
    if (storyCells && !cells) fail(`fork ${fk.id}: no Lean cells`);
    const tl = forkTimelines[fk.id] = [];
    const fr = runBranch(`f${fk.id}.`, fk.steps, trunk.states[fk.at], t0, fenv, cells, tl);
    if (!problems.length && fk.expectFinal !== undefined && !sameJson(fk.expectFinal, fr.final)) fail(`fork ${fk.id}: final state ${canonicalJson(fr.final)} ≠ expected ${canonicalJson(fk.expectFinal)}`);
  }
  return done({ final: trunk.final });
}

/* --- the corpus checker ------------------------------------------------------- */
function checkCorpus(doc) {
  const reasons = [];
  let cells = 0, applied = 0, refused = 0;
  const one = (label, params, envT, now, input, action, result) => {
    cells++;
    const envTable = { ...emptyEnv(), ...(envT || {}) };
    const r = step(params, envTable, action, now, input);
    if (!r.ok && r.reason && r.reason.startsWith('invalid')) { reasons.push(`${label}: ${r.reason}/${r.field}`); return; }
    if ((result !== null) !== r.ok) { reasons.push(`${label}: Lean ${result ? 'applied' : 'refused'}, core ${r.ok ? 'applied' : 'refused (' + r.reason + ')'}`); return; }
    if (r.ok) {
      applied++;
      if (!sameJson(normFlow(result.flow), normFlow(r.flow))) reasons.push(`${label}: flow mismatch`);
      if (!sameJson(result.state, r.state)) reasons.push(`${label}: post-state mismatch`);
      const th = checkTheorems({ before: input, action, now, result: r, params, env: envTable });
      for (const id of Object.keys(th)) if (th[id].v === 'fails') reasons.push(`${label}: theorem ${id} fails — ${th[id].why}`);
    } else refused++;
  };
  if (!doc || doc.schema !== SCHEMA) reasons.push(`schema: expected ${SCHEMA}`);
  if (!doc || doc.version !== VERSION) reasons.push(`version: expected ${VERSION}`);
  if (!doc || validateParams(doc.params)) reasons.push('params: invalid');
  if (reasons.length) return { ok: false, reasons, cells, applied, refused };
  const P = doc.params;
  if (!Array.isArray(doc.traces) || !doc.traces.length) reasons.push('traces: none');
  for (const tr of doc.traces || []) {
    let prev = tr.initial;
    (tr.steps || []).forEach((st, i) => {
      if (!sameJson(st.input, prev)) reasons.push(`trace ${tr.name} step ${i}: input ≠ previous state`);
      one(`trace ${tr.name} step ${i}`, P, tr.env, st.now, st.input, st.action, st.result);
      prev = st.result ? st.result.state : st.input;
    });
    if (!(tr.steps || []).length) reasons.push(`trace ${tr.name}: no steps`);
  }
  const g = doc.grid;
  if (!g || !Array.isArray(g.cells) || !g.cells.length) reasons.push('grid: none');
  else for (const c of g.cells) one(`grid s${c.s} a${c.a} e${c.e}`, P, g.envs[c.e], g.now, g.states[c.s], g.actions[c.a], c.result);
  if (!Array.isArray(doc.stories) || !doc.stories.length) reasons.push('stories: none');
  for (const sc of doc.stories || []) {
    (sc.steps || []).forEach((st, i) => one(`story ${sc.id} step ${i}`, sc.params || P, sc.env, st.now, st.input, st.action, st.result));
    for (const fk of sc.forks || []) (fk.steps || []).forEach((st, i) => one(`story ${sc.id} f${fk.id}.${i}`, sc.params || P, fk.env || sc.env, st.now, st.input, st.action, st.result));
  }
  return { ok: reasons.length === 0, reasons, cells, applied, refused };
}
/* @@CORE:verify:END@@ */

export { SCHEMA, VERSION, REASONS, LEAN_GUARDS, MAX_NAT, isNat, validateParams, validateState, validateEnv,
         validateAction, emptyEnv, envFromTables, userPostable, opBond, opTag, statusTag, ckTag, actionActor,
         actionTag, inPhase1, inPhase2, rejectable, phaseOf, lookupReq, lookupLeaf, lookupCkpt, removeReq,
         removeCkpt, setLeaf, processBody, processOne, rejectOne, applyBatch, batchView, flow, reapableReason, goOp, step,
         replay, initSys, goPending, THEOREMS, checkTheorems, canonicalJson, sameJson, normFlow, checkScenario,
         checkCorpus };
