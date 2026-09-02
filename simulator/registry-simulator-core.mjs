/*
 * registry-simulator-core.mjs — THE machine core of the registry simulator:
 * the single transcription of `CardanoKeri.Registry` (the AID registry as an
 * MPFS instance: `stepFn`, `applyBatch`, `replay`, `Action.actor`, the
 * phases), the theorems R1–R12 of `CardanoKeri.RegistryGoals` as executable
 * properties over steps, and the scenario / corpus checkers.
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
 * a slot) is always an explicit argument. `Env` is three evidence
 * predicates decided by the scenario or by the person playing — never here.
 *
 * Wire shapes (shared byte-for-byte with the Lean driver's ToJson output,
 * `lean/RegistryTraceDriver.lean`):
 *   params := { D, tip, process, retract }
 *   sys    := { gen, plugin, root:[aid], live:[aid], tomb:[aid],
 *               requests:[{ id, aid, owner, submittedAt }], nextReq }
 *   action := { contribute: { aid, owner, submittedAt } }
 *           | { fold: { folder, gen, plugin, batch:[{ id, do }] } }   do: "process" | "reject"
 *           | { retract: { req } } | { close: { aid } } | { convict: { aid } }
 *   flow   := { deposited, locked:[{ aid, value }], refunds:[{ addr, value }],
 *               tips: null | { addr, value } }
 *   env    := { inception:[aid], quorum:[aid], duplicity:[aid] }   (a table; absent = false)
 */

/* @@CORE:constants@@ */
const SCHEMA = 'cardano-keri.registry.trace';
const VERSION = 1;

/* Refusal reasons, named after the guard that failed, in the Lean's own
   conjunction order. */
const REASONS = {
  INVALID_PARAMS: 'invalid-params',
  INVALID_NAT: 'invalid-nat',
  INVALID_STATE: 'invalid-state',
  INVALID_ACTION: 'invalid-action',
  INVALID_EVIDENCE: 'invalid-evidence',
  UNKNOWN_REQUEST: 'unknown-request',       // lookup = none (retract, or a batch entry — including one the same batch consumed)
  NOT_IN_PHASE_2: 'not-in-phase-2',         // retract outside phase 2
  STALE_GENERATION: 'stale-generation',     // fold names a generation other than the registry's
  PLUGIN_NOT_PINNED: 'plugin-not-pinned',   // fold re-creates the cage with another plugin
  EMPTY_FOLD: 'empty-fold',                 // batch = []
  NOT_IN_PHASE_1: 'not-in-phase-1',         // process outside phase 1
  BAD_INCEPTION: 'bad-inception',           // env.inception false
  ALREADY_REGISTERED: 'already-registered', // the AID is in the root: the absence proof fails
  NOT_REJECTABLE: 'not-rejectable',         // reject before phase 3 with an honest timestamp
  NO_LIVE_TOKEN: 'no-live-token',           // close / convict without a live token
  NO_QUORUM: 'no-quorum',                   // close without the current quorum
  NO_DUPLICITY_PROOF: 'no-duplicity-proof', // convict without a proof
};

/* Which Lean declaration and binder refuses with each reason. */
const LEAN_GUARDS = {
  'unknown-request': { decl: 'stepFn / applyBatch', text: 'lookup … = none' },
  'not-in-phase-2': { decl: 'stepFn (retract)', text: 'if inPhase2 p r now' },
  'stale-generation': { decl: 'stepFn (fold)', text: 'g = s.gen' },
  'plugin-not-pinned': { decl: 'stepFn (fold)', text: 'pl = s.plugin' },
  'empty-fold': { decl: 'stepFn (fold)', text: 'batch ≠ []' },
  'not-in-phase-1': { decl: 'applyBatch (process)', text: 'inPhase1 p r now' },
  'bad-inception': { decl: 'applyBatch (process)', text: 'env.inception r.aid = true' },
  'already-registered': { decl: 'applyBatch (process)', text: 'r.aid ∉ acc.root' },
  'not-rejectable': { decl: 'applyBatch (reject)', text: 'rejectable p r now' },
  'no-live-token': { decl: 'stepFn (close / convict)', text: 'aid ∈ s.live' },
  'no-quorum': { decl: 'stepFn (close)', text: 'env.quorum aid = true' },
  'no-duplicity-proof': { decl: 'stepFn (convict)', text: 'env.duplicity aid = true' },
};
/* @@CORE:constants:END@@ */

/* @@CORE:machine@@ */
/* --- exact Nat -----------------------------------------------------------
   A Lean `Nat` is unbounded; this core represents it exactly up to 2^53 − 1
   and refuses by name anything else, before evaluating anything. */
const MAX_NAT = Number.MAX_SAFE_INTEGER;
function isNat(x) { return typeof x === 'number' && Number.isInteger(x) && x >= 0 && x <= MAX_NAT; }
const refuse = (reason, field) => ({ ok: false, reason, field });

function validateParams(p) {
  if (!p || typeof p !== 'object') return refuse(REASONS.INVALID_PARAMS, 'params');
  for (const k of ['D', 'tip', 'process', 'retract'])
    if (!isNat(p[k])) return refuse(REASONS.INVALID_NAT, k);
  if (!(p.D > 0)) return refuse(REASONS.INVALID_PARAMS, 'D must be positive');
  if (!(p.process > 0)) return refuse(REASONS.INVALID_PARAMS, 'process must be positive');
  if (!(p.retract > 0)) return refuse(REASONS.INVALID_PARAMS, 'retract must be positive');
  return null;
}

function validateNatList(l, field) {
  if (!Array.isArray(l)) return refuse(REASONS.INVALID_STATE, field);
  for (let i = 0; i < l.length; i++) if (!isNat(l[i])) return refuse(REASONS.INVALID_NAT, `${field}[${i}]`);
  return null;
}

/* A state is exactly the seven fields of `Sys`; each request exactly four. */
function validateState(s) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return refuse(REASONS.INVALID_STATE, 'state');
  const keys = ['gen', 'plugin', 'root', 'live', 'tomb', 'requests', 'nextReq'];
  for (const k of Object.keys(s)) if (!keys.includes(k)) return refuse(REASONS.INVALID_STATE, k);
  for (const k of ['gen', 'plugin', 'nextReq']) if (!isNat(s[k])) return refuse(REASONS.INVALID_NAT, k);
  for (const k of ['root', 'live', 'tomb']) { const e = validateNatList(s[k], k); if (e) return e; }
  if (!Array.isArray(s.requests)) return refuse(REASONS.INVALID_STATE, 'requests');
  for (let i = 0; i < s.requests.length; i++) {
    const r = s.requests[i];
    if (!r || typeof r !== 'object') return refuse(REASONS.INVALID_STATE, `requests[${i}]`);
    for (const k of Object.keys(r)) if (!['id', 'aid', 'owner', 'submittedAt'].includes(k)) return refuse(REASONS.INVALID_STATE, `requests[${i}].${k}`);
    for (const k of ['id', 'aid', 'owner', 'submittedAt']) if (!isNat(r[k])) return refuse(REASONS.INVALID_NAT, `requests[${i}].${k}`);
  }
  return null;
}

/* An evidence table is exactly the three predicates, each a list of AIDs. */
function validateEnv(t) {
  if (!t || typeof t !== 'object' || Array.isArray(t)) return refuse(REASONS.INVALID_EVIDENCE, 'env');
  for (const k of Object.keys(t)) if (!['inception', 'quorum', 'duplicity'].includes(k)) return refuse(REASONS.INVALID_EVIDENCE, k);
  for (const k of ['inception', 'quorum', 'duplicity']) {
    if (t[k] === undefined) continue;
    if (!Array.isArray(t[k])) return refuse(REASONS.INVALID_EVIDENCE, k);
    for (let i = 0; i < t[k].length; i++) if (!isNat(t[k][i])) return refuse(REASONS.INVALID_NAT, `${k}[${i}]`);
  }
  return null;
}

function validateAction(a) {
  if (!a || typeof a !== 'object' || Array.isArray(a)) return refuse(REASONS.INVALID_ACTION, 'action');
  const tags = Object.keys(a);
  if (tags.length !== 1) return refuse(REASONS.INVALID_ACTION, 'action');
  const tag = tags[0], b = a[tag];
  if (!b || typeof b !== 'object') return refuse(REASONS.INVALID_ACTION, tag);
  const need = (fields) => {
    for (const k of Object.keys(b)) if (!fields.includes(k)) return refuse(REASONS.INVALID_ACTION, `${tag}.${k}`);
    for (const k of fields) if (k !== 'batch' && !isNat(b[k])) return refuse(REASONS.INVALID_NAT, `${tag}.${k}`);
    return null;
  };
  switch (tag) {
    case 'contribute': return need(['aid', 'owner', 'submittedAt']);
    case 'retract': return need(['req']);
    case 'close': case 'convict': return need(['aid']);
    case 'fold': {
      const e = need(['folder', 'gen', 'plugin', 'batch']); if (e) return e;
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

/* --- Env: the three evidence predicates ---------------------------------- */
function emptyEnv() { return { inception: [], quorum: [], duplicity: [] }; }
function envFromTables(t) {
  const has = (k, aid) => Array.isArray(t[k]) && t[k].includes(aid);
  return {
    inception: aid => has('inception', aid),
    quorum: aid => has('quorum', aid),
    duplicity: aid => has('duplicity', aid),
  };
}

/* --- Action.actor (Registry.lean) ---------------------------------------- */
function actionActor(a) {
  if (!a || typeof a !== 'object') return null;
  if ('contribute' in a || 'fold' in a) return 'anyone';
  if ('retract' in a) return 'owner';
  if ('close' in a) return 'current-quorum';
  if ('convict' in a) return 'proof';
  return null;
}
function actionTag(a) { return a && typeof a === 'object' ? Object.keys(a)[0] : null; }

/* --- phases (Registry.lean: inPhase1, inPhase2, rejectable) --------------- */
function inPhase1(p, r, now) { return now < r.submittedAt + p.process; }
function inPhase2(p, r, now) { return r.submittedAt + p.process <= now && now < r.submittedAt + p.process + p.retract; }
function rejectable(p, r, now) { return r.submittedAt + p.process + p.retract <= now || now < r.submittedAt; }
function phaseOf(p, r, now) {
  if (now < r.submittedAt) return 'future';
  if (inPhase1(p, r, now)) return 'phase-1';
  if (inPhase2(p, r, now)) return 'phase-2';
  return 'phase-3';
}

/* --- the inbox (lookup, remove) ------------------------------------------ */
function lookup(rs, id) { const x = rs.find(r => r.id === id); return x ? x : null; }
function remove(rs, id) { return rs.filter(r => r.id !== id); }

/* --- applyBatch: the transcription of `applyBatch` -----------------------
   Threads root, live, requests, locked, refunds through the batch in order;
   returns { ok:false, reason, at } naming the entry that refused. */
function applyBatch(p, env, now, acc0, batch) {
  let acc = { root: acc0.root.slice(), live: acc0.live.slice(), requests: acc0.requests.slice(),
              locked: acc0.locked.slice(), refunds: acc0.refunds.slice() };
  for (let i = 0; i < batch.length; i++) {
    const { id, do: fa } = batch[i];
    const r = lookup(acc.requests, id);
    if (!r) return { ok: false, reason: REASONS.UNKNOWN_REQUEST, at: i };
    if (fa === 'process') {
      if (!inPhase1(p, r, now)) return { ok: false, reason: REASONS.NOT_IN_PHASE_1, at: i };
      if (env.inception(r.aid) !== true) return { ok: false, reason: REASONS.BAD_INCEPTION, at: i };
      if (acc.root.includes(r.aid)) return { ok: false, reason: REASONS.ALREADY_REGISTERED, at: i };
      acc = { root: [r.aid, ...acc.root], live: [r.aid, ...acc.live], requests: remove(acc.requests, id),
              locked: [...acc.locked, { aid: r.aid, value: p.D }], refunds: acc.refunds };
    } else {
      if (!rejectable(p, r, now)) return { ok: false, reason: REASONS.NOT_REJECTABLE, at: i };
      acc = { ...acc, requests: remove(acc.requests, id), refunds: [...acc.refunds, { addr: r.owner, value: p.D }] };
    }
  }
  return { ok: true, acc };
}

function flow(o) { return { deposited: 0, locked: [], refunds: [], tips: null, ...o }; }

/* --- step: the transcription of `stepFn` --------------------------------- */
function step(params, envTable, action, now, state) {
  const ep = validateParams(params); if (ep) return ep;
  if (!isNat(now)) return refuse(REASONS.INVALID_NAT, 'now');
  const ea = validateAction(action); if (ea) return ea;
  const es = validateState(state); if (es) return es;
  const ee = validateEnv(envTable); if (ee) return ee;
  const env = envFromTables(envTable);
  const s = state, p = params, a = action;
  if ('contribute' in a) {
    const { aid, owner, submittedAt } = a.contribute;
    return { ok: true, flow: flow({ deposited: p.D + p.tip }),
             state: { ...s, requests: [{ id: s.nextReq, aid, owner, submittedAt }, ...s.requests], nextReq: s.nextReq + 1 } };
  }
  if ('retract' in a) {
    const r = lookup(s.requests, a.retract.req);
    if (!r) return refuse(REASONS.UNKNOWN_REQUEST);
    if (!inPhase2(p, r, now)) return refuse(REASONS.NOT_IN_PHASE_2);
    return { ok: true, flow: flow({ refunds: [{ addr: r.owner, value: p.D + p.tip }] }),
             state: { ...s, requests: remove(s.requests, a.retract.req) } };
  }
  if ('fold' in a) {
    const { folder, gen, plugin, batch } = a.fold;
    if (!(gen === s.gen)) return refuse(REASONS.STALE_GENERATION);
    if (!(plugin === s.plugin)) return refuse(REASONS.PLUGIN_NOT_PINNED);
    if (!(batch.length > 0)) return refuse(REASONS.EMPTY_FOLD);
    const r = applyBatch(p, env, now, { root: s.root, live: s.live, requests: s.requests, locked: [], refunds: [] }, batch);
    if (!r.ok) return { ok: false, reason: r.reason, at: r.at };
    return { ok: true,
             flow: flow({ locked: r.acc.locked, refunds: r.acc.refunds, tips: { addr: folder, value: batch.length * p.tip } }),
             state: { ...s, gen: s.gen + 1, root: r.acc.root, live: r.acc.live, requests: r.acc.requests } };
  }
  if ('close' in a) {
    const { aid } = a.close;
    if (!s.live.includes(aid)) return refuse(REASONS.NO_LIVE_TOKEN);
    if (env.quorum(aid) !== true) return refuse(REASONS.NO_QUORUM);
    return { ok: true, flow: flow({}),
             state: { ...s, gen: s.gen + 1, root: eraseFirst(s.root, aid), live: eraseFirst(s.live, aid) } };
  }
  if ('convict' in a) {
    const { aid } = a.convict;
    if (!s.live.includes(aid)) return refuse(REASONS.NO_LIVE_TOKEN);
    if (env.duplicity(aid) !== true) return refuse(REASONS.NO_DUPLICITY_PROOF);
    return { ok: true, flow: flow({}),
             state: { ...s, live: eraseFirst(s.live, aid), tomb: [aid, ...s.tomb] } };
  }
  return refuse(REASONS.INVALID_ACTION, 'action');
}
/* List.erase: the first occurrence. */
function eraseFirst(l, x) { const i = l.indexOf(x); return i < 0 ? l.slice() : [...l.slice(0, i), ...l.slice(i + 1)]; }

/* --- replay: the transcription of `replay` ------------------------------- */
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

/* --- initial system (Sys.init) ------------------------------------------- */
function initSys(plugin) { return { gen: 0, plugin, root: [], live: [], tomb: [], requests: [], nextReq: 0 }; }
/* @@CORE:machine:END@@ */

/* @@CORE:theorems@@ */
/* --- R1–R12 as executable properties over one step record ----------------
   A record is { before, action, now, result } where result is the value of
   `step`. Each property returns 'holds' (antecedent held and the claim was
   verified), 'n/a' (antecedent did not hold), or 'fails' with a message. */
const nodup = l => new Set(l).size === l.length;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const foldOf = a => (a && a.fold) || null;
const reqOf = (s, id) => lookup(s.requests, id);

const THEOREMS = [
  { id: 'R1', title: 'row if and only if token', lean: 'R1_row_iff_token',
    check: ({ result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state;
      for (const aid of s.root) if (!s.live.includes(aid) && !s.tomb.includes(aid)) return { v: 'fails', why: `row ${aid} without a token` };
      for (const aid of [...s.live, ...s.tomb]) if (!s.root.includes(aid)) return { v: 'fails', why: `token ${aid} without a row` };
      return { v: 'holds' };
    } },
  { id: 'R1c', title: 'a registered AID cannot be processed again (mint-once)', lean: 'R1_registered_refused',
    check: ({ before, action, result }) => {
      const f = foldOf(action); if (!f || f.gen !== before.gen || f.plugin !== before.plugin) return { v: 'n/a' };
      const hit = f.batch.find(x => x.do === 'process' && reqOf(before, x.id) && before.root.includes(reqOf(before, x.id).aid));
      if (!hit) return { v: 'n/a' };
      return result.ok ? { v: 'fails', why: `processed a registered AID` } : { v: 'holds' };
    } },
  { id: 'R2', title: 'at most one live checkpoint per AID; a tombstone is never live', lean: 'R2_one_live_checkpoint, R2_tomb_not_live',
    check: ({ result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state;
      if (!nodup(s.live)) return { v: 'fails', why: 'two live checkpoints for one AID' };
      for (const aid of s.tomb) if (s.live.includes(aid)) return { v: 'fails', why: `AID ${aid} both live and convicted` };
      return { v: 'holds' };
    } },
  { id: 'R3', title: 'conviction is permanent', lean: 'R3_tomb_permanent, R3_convicted_never_processed, R3_convicted_not_closable',
    check: ({ before, action, result }) => {
      if (result.ok) {
        for (const aid of before.tomb) if (!result.state.tomb.includes(aid)) return { v: 'fails', why: `tombstone ${aid} removed` };
        return before.tomb.length ? { v: 'holds' } : { v: 'n/a' };
      }
      if (action.close && before.tomb.includes(action.close.aid)) return { v: 'holds' };
      const f = foldOf(action);
      if (f && f.gen === before.gen && f.plugin === before.plugin &&
          f.batch.some(x => x.do === 'process' && reqOf(before, x.id) && before.tomb.includes(reqOf(before, x.id).aid))) return { v: 'holds' };
      return { v: 'n/a' };
    } },
  { id: 'R4', title: 'close deletes the row; a closed AID may return', lean: 'R4_close_deletes_row, R4_reregistrable',
    check: ({ before, action, result }) => {
      if (action.close && result.ok) {
        const aid = action.close.aid;
        if (result.state.root.includes(aid) || result.state.live.includes(aid)) return { v: 'fails', why: 'row or token survived the close' };
        return { v: 'holds' };
      }
      const f = foldOf(action);
      if (f && result.ok && f.batch.some(x => x.do === 'process' && reqOf(before, x.id) && !before.root.includes(reqOf(before, x.id).aid)))
        return { v: 'holds' };
      return { v: 'n/a' };
    } },
  { id: 'R5', title: 'the plugin is pinned', lean: 'R5_plugin_pinned',
    check: ({ before, action, result }) => {
      if (result.ok) return result.state.plugin === before.plugin ? { v: 'holds' } : { v: 'fails', why: 'plugin changed' };
      const f = foldOf(action);
      if (f && f.gen === before.gen && f.plugin !== before.plugin) return result.reason === REASONS.PLUGIN_NOT_PINNED ? { v: 'holds' } : { v: 'fails', why: `refused for ${result.reason}` };
      return { v: 'n/a' };
    } },
  { id: 'R6', title: 'the generation moves exactly on registry spends; requests never contend', lean: 'R6_gen_step, R6_requests_never_contend, R6_spend_is_fold_or_close, R6_fold_advances',
    check: ({ before, action, result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state, tag = actionTag(action);
      if (tag === 'fold' || tag === 'close') return s.gen === before.gen + 1 ? { v: 'holds' } : { v: 'fails', why: 'registry spend without a generation step' };
      if (s.gen !== before.gen) return { v: 'fails', why: `${tag} moved the generation` };
      if (tag === 'contribute' || tag === 'retract')
        if (!same(s.root, before.root) || !same(s.live, before.live) || !same(s.tomb, before.tomb)) return { v: 'fails', why: `${tag} touched the registry` };
      return { v: 'holds' };
    } },
  { id: 'R7', title: 'a stale fold is refused with no state change; one fold per generation', lean: 'R7_stale_fold_refused, R7_one_fold_per_generation',
    check: ({ before, action, result }) => {
      const f = foldOf(action); if (!f || f.gen === before.gen) return { v: 'n/a' };
      return !result.ok && result.reason === REASONS.STALE_GENERATION ? { v: 'holds' } : { v: 'fails', why: result.ok ? 'stale fold applied' : `refused for ${result.reason}` };
    } },
  { id: 'R8', title: 'an empty fold is refused', lean: 'R8_empty_fold_refused, R8_plugin_swap_refused',
    check: ({ before, action, result }) => {
      const f = foldOf(action); if (!f || f.gen !== before.gen || f.plugin !== before.plugin || f.batch.length) return { v: 'n/a' };
      return !result.ok && result.reason === REASONS.EMPTY_FOLD ? { v: 'holds' } : { v: 'fails', why: result.ok ? 'empty fold applied' : `refused for ${result.reason}` };
    } },
  { id: 'R9', title: 'requester exit: retract in phase 2, rejection by anyone when rejectable, neither elsewhere', lean: 'R9_retract_enabled, R9_retract_needs_phase2, R9_reject_enabled, R9_reject_needs_rejectable, R9_process_needs_phase1',
    check: ({ before, action, now, result, params }) => {
      if (action.retract) {
        const r = reqOf(before, action.retract.req); if (!r) return { v: 'n/a' };
        const want = inPhase2(params, r, now);
        if (want !== result.ok) return { v: 'fails', why: want ? 'retract refused in phase 2' : 'retract applied outside phase 2' };
        if (!want && result.reason !== REASONS.NOT_IN_PHASE_2) return { v: 'fails', why: `refused for ${result.reason}` };
        return { v: 'holds' };
      }
      const f = foldOf(action);
      if (f && f.gen === before.gen && f.plugin === before.plugin && f.batch.length === 1) {
        const x = f.batch[0], r = reqOf(before, x.id); if (!r) return { v: 'n/a' };
        if (x.do === 'reject') {
          const want = rejectable(params, r, now);
          if (want !== result.ok) return { v: 'fails', why: want ? 'reject refused when rejectable' : 'reject applied when not rejectable' };
          if (!want && result.reason !== REASONS.NOT_REJECTABLE) return { v: 'fails', why: `refused for ${result.reason}` };
          return { v: 'holds' };
        }
        if (!inPhase1(params, r, now)) return !result.ok && result.reason === REASONS.NOT_IN_PHASE_1 ? { v: 'holds' } : { v: 'fails', why: 'process outside phase 1' };
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
  { id: 'R11', title: 'value: bonds lock or refund exactly, tips are tip per request, refunds go to request owners', lean: 'R11_fold_value, R11_retract_value, R11_contribute_value, R11_token_edges_move_no_value',
    check: ({ before, action, result, params }) => {
      if (!result.ok) return { v: 'n/a' };
      const fl = result.flow, tag = actionTag(action);
      if (tag === 'fold') {
        const f = action.fold;
        if (fl.locked.some(x => x.value !== params.D)) return { v: 'fails', why: 'a lock is not D' };
        for (const x of fl.refunds) {
          if (x.value !== params.D) return { v: 'fails', why: 'a refund is not D' };
          if (!before.requests.some(r => r.owner === x.addr)) return { v: 'fails', why: `refund to ${x.addr}, not a request owner` };
        }
        if (!fl.tips || fl.tips.addr !== f.folder || fl.tips.value !== f.batch.length * params.tip) return { v: 'fails', why: 'tips are not tip per request to the folder' };
        if (fl.locked.length + fl.refunds.length !== f.batch.length) return { v: 'fails', why: 'a request unaccounted for' };
        if (fl.deposited !== 0) return { v: 'fails', why: 'a fold deposited' };
        return { v: 'holds' };
      }
      if (tag === 'retract') {
        const r = reqOf(before, action.retract.req);
        return same(fl, flow({ refunds: [{ addr: r.owner, value: params.D + params.tip }] })) ? { v: 'holds' } : { v: 'fails', why: 'retract did not return D + tip to the owner' };
      }
      if (tag === 'contribute') return same(fl, flow({ deposited: params.D + params.tip })) ? { v: 'holds' } : { v: 'fails', why: 'contribute did not deposit D + tip' };
      return same(fl, flow({})) ? { v: 'holds' } : { v: 'fails', why: `${tag} moved request value` };
    } },
  { id: 'R12', title: 'a row leaves the root only by close, enters only by fold', lean: 'R12_row_leaves_only_by_close, R12_row_enters_only_by_fold',
    check: ({ before, action, result }) => {
      if (!result.ok) return { v: 'n/a' };
      const s = result.state, tag = actionTag(action);
      for (const aid of before.root) if (!s.root.includes(aid) && !(tag === 'close' && action.close.aid === aid)) return { v: 'fails', why: `row ${aid} left by ${tag}` };
      for (const aid of s.root) if (!before.root.includes(aid) && tag !== 'fold') return { v: 'fails', why: `row ${aid} entered by ${tag}` };
      return same(s.root, before.root) ? { v: 'n/a' } : { v: 'holds' };
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
/* --- canonical JSON ------------------------------------------------------ */
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

/* --- the scenario checker (shared by the gate and the page's ?selftest) --
   A scenario is declarative data: params, plugin, evidence table, actors,
   steps { now, action, expect: { ok, reason?, flow?, state? }, exhibits? },
   expectFinal. `corpus` (optional) supplies the Lean's own verdict for every
   story step: parity is checked when a cell exists. */
function checkScenario(sc, file, corpus) {
  const problems = [], asserted = [], exhibited = [], timeline = [];
  const fail = m => problems.push(`${sc && sc.slug ? sc.slug : file}: ${m}`);
  if (!sc || typeof sc.id !== 'number' || !sc.slug || !sc.story) { fail('bad header'); return { problems, asserted, exhibited, stepsRun: 0, timeline }; }
  if (validateParams(sc.params)) { fail('bad params'); return { problems, asserted, exhibited, stepsRun: 0, timeline }; }
  if (!Array.isArray(sc.steps) || !sc.steps.length) { fail('no steps'); return { problems, asserted, exhibited, stepsRun: 0, timeline }; }
  const env = sc.env || emptyEnv();
  let s = sc.initial || initSys(isNat(sc.plugin) ? sc.plugin : 7);
  let t = 0;
  const cells = corpus && corpus.stories ? (corpus.stories.find(x => x.id === sc.id) || {}).steps : null;
  for (let i = 0; i < sc.steps.length; i++) {
    const st = sc.steps[i];
    if (!isNat(st.now) || !(t <= st.now)) { fail(`step ${i}: slot not non-decreasing`); break; }
    t = st.now;
    if (st.actor !== undefined && actionActor(st.action) !== st.actor) fail(`step ${i}: actor «${st.actor}» ≠ ${actionActor(st.action)}`);
    const r = step(sc.params, env, st.action, st.now, s);
    const exp = st.expect || { ok: true };
    const rec = { before: s, action: st.action, now: st.now, result: r, params: sc.params };
    const th = checkTheorems(rec);
    for (const id of Object.keys(th)) if (th[id].v === 'fails') fail(`step ${i}: theorem ${id} fails — ${th[id].why}`);
    for (const id of st.exhibits || []) {
      if (!THEOREMS.some(x => x.id === id)) { fail(`step ${i}: unknown theorem ${id}`); continue; }
      if (th[id].v !== 'holds') fail(`step ${i}: claims to exhibit ${id} but it is ${th[id].v}`);
      else exhibited.push(id);
    }
    if (cells) {
      const c = cells[i];
      if (!c) fail(`step ${i}: no Lean cell`);
      else {
        if ((c.result !== null) !== r.ok) fail(`step ${i}: Lean ${c.result ? 'applied' : 'refused'}, core ${r.ok ? 'applied' : 'refused'}`);
        else if (r.ok && (!sameJson(normFlow(c.result.flow), normFlow(r.flow)) || !sameJson(c.result.state, r.state))) fail(`step ${i}: Lean and core disagree on the result`);
        if (!sameJson(c.input, s) || !sameJson(c.action, st.action) || c.now !== st.now) fail(`step ${i}: Lean cell input differs from the story's`);
      }
    }
    timeline.push({ i, now: st.now, action: st.action, result: r, theorems: th });
    if (!r.ok && exp.ok !== false) { fail(`step ${i}: refused (${r.reason}${r.field ? '/' + r.field : ''}), expected applied`); break; }
    if (r.ok && exp.ok === false) { fail(`step ${i}: applied, expected refusal ${exp.reason || ''}`); break; }
    if (!r.ok) {
      if (exp.reason && exp.reason !== r.reason) { fail(`step ${i}: refused ${r.reason}, expected ${exp.reason}`); break; }
      if (exp.reason) asserted.push(exp.reason);
      continue;
    }
    if (exp.flow !== undefined && !sameJson(normFlow(exp.flow), normFlow(r.flow))) { fail(`step ${i}: flow ${canonicalJson(normFlow(r.flow))} ≠ expected ${canonicalJson(normFlow(exp.flow))}`); break; }
    if (exp.state !== undefined && !sameJson(exp.state, r.state)) { fail(`step ${i}: state ${canonicalJson(r.state)} ≠ expected ${canonicalJson(exp.state)}`); break; }
    s = r.state;
  }
  if (!problems.length && sc.expectFinal !== undefined && !sameJson(sc.expectFinal, s)) fail(`final state ${canonicalJson(s)} ≠ expected ${canonicalJson(sc.expectFinal)}`);
  return { problems, asserted, exhibited, stepsRun: timeline.length, timeline, final: s };
}

/* --- the corpus checker ----------------------------------------------------
   The Lean driver emits { schema, version, params, traces:[{name, plugin,
   env, initial, steps:[{now, input, action, result}]}], grid:{now, plugin,
   states, actions, envs, cells:[{s,a,e,result}]}, stories:[{id, steps:[…]}]
   }. Every cell is replayed through `step`; applied cells must match flow
   and post-state, refused cells must be refused; theorems are checked on
   every applied cell. */
function checkCorpus(doc) {
  const reasons = [];
  let cells = 0, applied = 0, refused = 0;
  const one = (label, params, envT, now, input, action, result) => {
    cells++;
    const r = step(params, envT, action, now, input);
    if (!r.ok && r.reason && r.reason.startsWith('invalid')) { reasons.push(`${label}: ${r.reason}/${r.field}`); return; }
    if ((result !== null) !== r.ok) { reasons.push(`${label}: Lean ${result ? 'applied' : 'refused'}, core ${r.ok ? 'applied' : 'refused (' + r.reason + ')'}`); return; }
    if (r.ok) {
      applied++;
      if (!sameJson(normFlow(result.flow), normFlow(r.flow))) reasons.push(`${label}: flow mismatch`);
      if (!sameJson(result.state, r.state)) reasons.push(`${label}: post-state mismatch`);
      const th = checkTheorems({ before: input, action, now, result: r, params });
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
  for (const sc of doc.stories || []) (sc.steps || []).forEach((st, i) => one(`story ${sc.id} step ${i}`, sc.params || P, st.env || sc.env, st.now, st.input, st.action, st.result));
  return { ok: reasons.length === 0, reasons, cells, applied, refused };
}
/* @@CORE:verify:END@@ */

export { SCHEMA, VERSION, REASONS, LEAN_GUARDS, MAX_NAT, isNat, validateParams, validateState, validateEnv,
         validateAction, emptyEnv, envFromTables, actionActor, actionTag, inPhase1, inPhase2, rejectable,
         phaseOf, lookup, remove, applyBatch, flow, step, replay, initSys, THEOREMS, checkTheorems,
         canonicalJson, sameJson, normFlow, checkScenario, checkCorpus };
