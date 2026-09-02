/*
 * checkpoint-simulator-core.mjs — THE machine core of the checkpoint
 * simulator: the single transcription of `CardanoKeri.Checkpoint` (the M1
 * return machine: `stepFn`, `replay`, `consumableState`, `Action.actor`),
 * plus the frozen trace-envelope and scenario verifiers.
 *
 * The JavaScript core is a TRANSCRIPTION of `stepFn`: same actions, same
 * guards (in the same conjunction order), same flows, same results, same
 * refusals. Where `stepFn` returns `none`, this core refuses with a named
 * reason. Nothing on the page decides anything the core does not decide.
 *
 * Consumed by BOTH production surfaces, with no second transcription:
 *   - checkpoint-simulator.html embeds these exact slices between
 *     @@CORE:<id>@@ markers; checkpoint-simulator-build.mjs regenerates the
 *     page from this file, and the scenario gate REDs when the embedded
 *     copy is stale or forked (byte compare per slice);
 *   - checkpoint-simulator-scenario-gate.mjs imports this module directly.
 *
 * The boundary is a pure functional surface (state in → result out): no
 * DOM, no storage, no clock. `now` (chain time, a slot) is always an
 * explicit argument. `Env` is the set of four evidence predicates; in the
 * simulator they are decided by the scenario or by the person playing —
 * never invented here.
 *
 * Wire shapes (shared byte-for-byte with the Lean driver's ToJson output,
 * `lean/CheckpointTraceDriver.lean`):
 *   state  := "absent" | "gone"                (nullary constructors, as strings)
 *           | { present:   { sn, epoch, poisoned, bornAt, refundTo,
 *                            dreg, b, pool } }
 *           | { convicted: { epoch, sn, convictedAt } }
 *   action := { register: { refund, pool0 } }
 *           | { rotate:   { sn, op, payee, refund } }   (refund: null | addr)
 *           | { freeze:   { sn, payee } }
 *           | { topUp:    { x } }
 *           | { convict:  { payee } }
 *           | { poison: {} } | { close: {} }
 *   flow   := { dregIn, bIn, poolIn, refund, hunter, convictor }
 *   payment:= { addr, dreg, b, pool }
 *   params := { D, B, P, W }
 *   env    := decision tables (see `envFromTables`)
 */

/* @@CORE:constants@@ */
const SCHEMA = 'cardano-keri.checkpoint.trace';
const VERSION = 1;

/* Refusal reasons, named after the guard that failed. `stepFn` returns
   `none`; the simulator always says WHY, naming the first failing conjunct
   in the constructor's own order. */
const REASONS = {
  INVALID_PARAMS: 'invalid-params',         // 0 < D and 0 < B are structural in Lean
  NOT_ABSENT: 'not-absent',                 // register on a non-absent state
  NOT_PRESENT: 'not-present',               // any action on absent/convicted/gone
  NO_WITNESSED_ROTATION: 'no-witnessed-rotation',   // rotationTo false
  SEQUENCE_NOT_GREATER: 'sequence-not-greater',     // sn' ≤ sn
  REFUND_NOT_AUTHORIZED: 'refund-not-authorized',   // new keys did not sign the address
  BONDS_OVERFULL: 'bonds-overfull',         // deposit guard dreg ≤ D ∧ b ≤ B
  NO_QUORUM: 'no-quorum',                   // quorum false (poison, close)
  ALREADY_POISONED: 'already-poisoned',     // poison twice in one epoch
  POOL_COVERS_PREMIUM: 'pool-covers-premium',       // freeze needs pool < P
  FREEZE_BOND_MISSING: 'freeze-bond-missing',       // freeze needs b = B
  POISONED: 'poisoned',                     // freeze/close from a poisoned state
  NO_DUPLICITY_PROOF: 'no-duplicity-proof', // convict without duplicityAt
};
/* @@CORE:constants:END@@ */

/* @@CORE:machine@@ */
/* --- Params -------------------------------------------------------------
   Deployment parameters. In Lean, `Params` carries proofs `0 < D`, `0 < B`
   — invalid params are unrepresentable there. Here they are refused by
   name, and `validParams` lets the page gate input before calling. */
function validParams(p) {
  return !!p && Number.isInteger(p.D) && p.D > 0
    && Number.isInteger(p.B) && p.B > 0
    && Number.isInteger(p.P) && Number.isInteger(p.W);
}

/* --- Env: the four evidence predicates ----------------------------------
   In the model each predicate stands for a cryptographic check over data
   the transaction presents (Checkpoint.lean, `Env`). The simulator never
   decides them: `envFromTables` builds the predicates from explicit
   decision tables (a row not listed is false), so a scenario — or a person
   at the evidence panel — decides the evidence, never the core. */
function envFromTables(t) {
  const key = a => a.join('|');
  const rot = new Map((t.rotationTo || []).map(r => [key(r.slice(0, 3)), r[3] === true]));
  const ref = new Map((t.refundAuthorized || []).map(r => [key(r.slice(0, 2)), r[2] === true]));
  const quo = new Map((t.quorum || []).map(r => [String(r[0]), r[1] === true]));
  const dup = new Map((t.duplicityAt || []).map(r => [key(r.slice(0, 2)), r[2] === true]));
  return {
    rotationTo: (e, sn, sn2) => rot.get(key([e, sn, sn2])) === true,
    refundAuthorized: (e, a) => ref.get(key([e, a])) === true,
    quorum: e => quo.get(String(e)) === true,
    duplicityAt: (e, sn) => dup.get(key([e, sn])) === true,
  };
}

/* --- Action.actor (Checkpoint.lean) -------------------------------------- */
function actionActor(a) {
  if (!a || typeof a !== 'object') return null;
  if ('register' in a) return 'anyone';
  if ('rotate' in a) return 'next-keys';
  if ('freeze' in a) return 'proof';
  if ('topUp' in a) return 'anyone';
  if ('convict' in a) return 'proof';
  if ('poison' in a || 'close' in a) return 'current-quorum';
  return null;
}

/* Which action tags the state's shape can carry at all (T8d: registration
   is the only step from `absent`; terminal states have no edges). The page
   uses this to offer only structurally possible controls. */
function stateAllows(state, tag) {
  if (tag === 'register') return typeof state === 'string' && state === 'absent';
  return typeof state === 'object' && state !== null && 'present' in state;
}

/* --- Flow/payment constructors with the Lean defaults -------------------- */
function payment(addr, dreg, b, pool) { return { addr, dreg: dreg || 0, b: b || 0, pool: pool || 0 }; }
function flow(o) {
  return { dregIn: 0, bIn: 0, poolIn: 0, refund: null, hunter: null, convictor: null, ...o };
}
function presentOf(state, reason) {
  if (typeof state === 'object' && state !== null && 'present' in state) return state.present;
  throw new Error(reason);
}

/* --- step: the transcription of `stepFn` ---------------------------------
   Guard conjunctions are tested in the constructor's own order, so the
   named reason is the FIRST failing conjunct, exactly as the Lean `if … ∧ …
   ∧ … then some … else none` refuses. */
function step(params, env, action, now, state) {
  if (!validParams(params)) return { ok: false, reason: REASONS.INVALID_PARAMS };
  const a = action;
  if (a === null || typeof a !== 'object') return { ok: false, reason: REASONS.NOT_PRESENT };
  if ('poison' in a) {
    if (!stateAllows(state, 'poison')) return { ok: false, reason: REASONS.NOT_PRESENT };
    const l = presentOf(state, REASONS.NOT_PRESENT);
    if (env.quorum(l.epoch) !== true) return { ok: false, reason: REASONS.NO_QUORUM };
    if (l.poisoned !== false) return { ok: false, reason: REASONS.ALREADY_POISONED };
    return { ok: true, flow: flow({}), state: { present: { ...l, poisoned: true } } };
  }
  if ('close' in a) {
    if (!stateAllows(state, 'close')) return { ok: false, reason: REASONS.NOT_PRESENT };
    const l = presentOf(state, REASONS.NOT_PRESENT);
    if (env.quorum(l.epoch) !== true) return { ok: false, reason: REASONS.NO_QUORUM };
    if (l.poisoned !== false) return { ok: false, reason: REASONS.POISONED };
    return {
      ok: true,
      flow: flow({ refund: payment(l.refundTo, l.dreg, l.b, l.pool) }),
      state: 'gone',
    };
  }
  if ('register' in a) {
    const { refund, pool0 } = a.register;
    if (!stateAllows(state, 'register')) return { ok: false, reason: REASONS.NOT_ABSENT };
    return {
      ok: true,
      flow: flow({ dregIn: params.D, bIn: params.B, poolIn: pool0 }),
      state: { present: { sn: 0, epoch: 0, poisoned: false, bornAt: now,
                          refundTo: refund, dreg: params.D, b: params.B, pool: pool0 } },
    };
  }
  if ('rotate' in a) {
    if (!stateAllows(state, 'rotate')) return { ok: false, reason: REASONS.NOT_PRESENT };
    const l = presentOf(state, REASONS.NOT_PRESENT);
    const { sn, op, payee, refund } = a.rotate;
    /* env.rotationTo l.epoch l.sn sn' = true ∧ l.sn < sn' ∧ refund'.all … */
    if (env.rotationTo(l.epoch, l.sn, sn) !== true)
      return { ok: false, reason: REASONS.NO_WITNESSED_ROTATION };
    if (!(l.sn < sn)) return { ok: false, reason: REASONS.SEQUENCE_NOT_GREATER };
    if (!(refund === null || refund === undefined
          ? true
          : env.refundAuthorized(l.epoch + 1, refund) === true))
      return { ok: false, reason: REASONS.REFUND_NOT_AUTHORIZED };
    const r2 = (refund === null || refund === undefined) ? l.refundTo : refund;
    if (op === 'keep') {
      if (params.P <= l.pool)
        return { ok: true,
                 flow: flow({ hunter: payment(payee, 0, 0, params.P) }),
                 state: { present: { ...l, sn, epoch: l.epoch + 1, poisoned: false,
                                     refundTo: r2, pool: l.pool - params.P } } };
      /* payment is never a gate (T14): the rotation lands, nothing is paid */
      return { ok: true,
               flow: flow({}),
               state: { present: { ...l, sn, epoch: l.epoch + 1, poisoned: false,
                                   refundTo: r2 } } };
    }
    if (op === 'withdraw') {
      return { ok: true,
               flow: flow({ refund: payment(r2, l.dreg, l.b, l.pool) }),
               state: { present: { ...l, sn, epoch: l.epoch + 1, poisoned: false,
                                   refundTo: r2, dreg: 0, b: 0, pool: 0 } } };
    }
    if (op === 'deposit') {
      if (!(l.dreg <= params.D && l.b <= params.B))
        return { ok: false, reason: REASONS.BONDS_OVERFULL };
      return { ok: true,
               flow: flow({ dregIn: params.D - l.dreg, bIn: params.B - l.b }),
               state: { present: { ...l, sn, epoch: l.epoch + 1, poisoned: false,
                                   bornAt: now, refundTo: r2,
                                   dreg: params.D, b: params.B } } };
    }
    return { ok: false, reason: REASONS.NOT_PRESENT };
  }
  if ('freeze' in a) {
    if (!stateAllows(state, 'freeze')) return { ok: false, reason: REASONS.NOT_PRESENT };
    const l = presentOf(state, REASONS.NOT_PRESENT);
    const { sn, payee } = a.freeze;
    /* rotationTo ∧ sn' > sn ∧ pool < P ∧ b = B ∧ poisoned = false.
       The last conjunct is a modelling assumption of D-034: a freeze is not
       enabled from a poisoned state. */
    if (env.rotationTo(l.epoch, l.sn, sn) !== true)
      return { ok: false, reason: REASONS.NO_WITNESSED_ROTATION };
    if (!(l.sn < sn)) return { ok: false, reason: REASONS.SEQUENCE_NOT_GREATER };
    if (!(l.pool < params.P)) return { ok: false, reason: REASONS.POOL_COVERS_PREMIUM };
    if (!(l.b === params.B)) return { ok: false, reason: REASONS.FREEZE_BOND_MISSING };
    if (l.poisoned !== false) return { ok: false, reason: REASONS.POISONED };
    return { ok: true,
             flow: flow({ hunter: payment(payee, 0, params.B, 0) }),
             state: { present: { ...l, b: 0 } } };
  }
  if ('topUp' in a) {
    if (!stateAllows(state, 'topUp')) return { ok: false, reason: REASONS.NOT_PRESENT };
    const l = presentOf(state, REASONS.NOT_PRESENT);
    return { ok: true,
             flow: flow({ poolIn: a.topUp.x }),
             state: { present: { ...l, pool: l.pool + a.topUp.x } } };
  }
  if ('convict' in a) {
    if (!stateAllows(state, 'convict')) return { ok: false, reason: REASONS.NOT_PRESENT };
    const l = presentOf(state, REASONS.NOT_PRESENT);
    if (env.duplicityAt(l.epoch, l.sn) !== true)
      return { ok: false, reason: REASONS.NO_DUPLICITY_PROOF };
    return { ok: true,
             flow: flow({ refund: payment(l.refundTo, 0, l.b, l.pool),
                          convictor: payment(a.convict.payee, l.dreg, 0, 0) }),
             state: { convicted: { epoch: l.epoch, sn: l.sn, convictedAt: now } } };
  }
  return { ok: false, reason: REASONS.NOT_PRESENT };
}

/* --- replay: the transcription of `replay` --------------------------------
   Timestamped actions at non-decreasing slots; the first refusal (or a
   decreasing slot) fails the whole trace. */
function replay(params, env, now, state, steps) {
  let t = now, s = state;
  for (let i = 0; i < steps.length; i++) {
    const { now: t2, action } = steps[i];
    if (!(t <= t2)) return { ok: false, at: i, reason: 'slot-decreased' };
    const r = step(params, env, action, t2, s);
    if (!r.ok) return { ok: false, at: i, reason: r.reason };
    s = r.state;
    t = t2;
  }
  return { ok: true, state: s };
}

/* --- consumableState ------------------------------------------------------
   The state-side conjuncts of what a consumer accepts (the treasury). The
   consumer's own threshold check, and validity once A11 ships, are outside
   this machine. Failures are named, in the conjuncts' order. */
function consumableState(params, now, state) {
  const failures = [];
  if (!(typeof state === 'object' && state !== null && 'present' in state))
    return { consumable: false, failures: ['not-present'] };
  const l = state.present;
  if (!(l.dreg === params.D)) failures.push('conviction-bond-not-full');
  if (!(l.b === params.B)) failures.push('freeze-bond-missing');
  if (!(l.poisoned === false)) failures.push('poisoned');
  if (!(l.bornAt + params.W <= now)) failures.push('juvenile');
  return { consumable: failures.length === 0, failures };
}
/* @@CORE:machine:END@@ */

/* @@CORE:verify@@ */
/* --- canonical JSON: structural equality that ignores key order ---------- */
function canonicalJson(x) {
  if (Array.isArray(x)) return '[' + x.map(canonicalJson).join(',') + ']';
  if (x !== null && typeof x === 'object') {
    const ks = Object.keys(x).filter(k => x[k] !== undefined).sort();
    return '{' + ks.map(k => JSON.stringify(k) + ':' + canonicalJson(x[k])).join(',') + '}';
  }
  return JSON.stringify(x);
}

/* Fill the Lean defaults so terse expectations compare equal to full wire
   shapes: Flow's missing payments are `null`, a Payment's missing
   components are 0, a state's missing `present` fields do not exist. */
function normPayment(p) {
  if (p === null || p === undefined) return null;
  return { addr: p.addr, dreg: p.dreg || 0, b: p.b || 0, pool: p.pool || 0 };
}
function normFlow(f) {
  const g = f || {};
  return { dregIn: g.dregIn || 0, bIn: g.bIn || 0, poolIn: g.poolIn || 0,
           refund: normPayment(g.refund), hunter: normPayment(g.hunter),
           convictor: normPayment(g.convictor) };
}
const sameJson = (a, b) => canonicalJson(a) === canonicalJson(b);

/* --- trace-envelope verifier ----------------------------------------------
   The committed Lean driver (`lean/CheckpointTraceDriver.lean`) emits
   {schema, version, traces: {name: {params, env, initial, steps}}} where
   every step carries {now, action, before, flow, after}. This verifier
   checks envelope shape, continuity, slot monotonicity, and that THIS
   core's `step` reproduces every flow and post-state from the envelope's
   own params and evidence tables — Lean output replayed through the page's
   one transcription. */
function verifyTracesDoc(doc) {
  const errors = [];
  if (!doc || doc.schema !== SCHEMA) errors.push(`schema: expected ${SCHEMA}`);
  if (!doc || doc.version !== VERSION) errors.push(`version: expected ${VERSION}`);
  const names = doc && doc.traces && typeof doc.traces === 'object'
    ? Object.keys(doc.traces) : [];
  if (!names.length) errors.push('traces: none');
  let steps = 0;
  for (const name of names) {
    const env0 = doc.traces[name];
    const label = `trace ${name}`;
    if (!env0.params || !validParams(env0.params)) { errors.push(`${label}: bad params`); continue; }
    if (!Array.isArray(env0.steps) || !env0.steps.length) { errors.push(`${label}: no steps`); continue; }
    const env = envFromTables(env0.env || {});
    let prev = env0.initial;
    for (let i = 0; i < env0.steps.length; i++) {
      const st = env0.steps[i];
      steps++;
      if (prev !== undefined && !sameJson(st.before, prev)) {
        errors.push(`${label} step ${i}: before ≠ previous after`);
        break;
      }
      if (i > 0 && !(env0.steps[i - 1].now <= st.now)) {
        errors.push(`${label} step ${i}: slot decreased`);
        break;
      }
      const r = step(env0.params, env, st.action, st.now, st.before);
      if (!r.ok) { errors.push(`${label} step ${i}: refused (${r.reason})`); break; }
      if (!sameJson(normFlow(r.flow), normFlow(st.flow))) {
        errors.push(`${label} step ${i}: flow mismatch — core=${canonicalJson(normFlow(r.flow)).slice(0, 160)} driver=${canonicalJson(normFlow(st.flow)).slice(0, 160)}`);
        break;
      }
      if (!sameJson(r.state, st.after)) {
        errors.push(`${label} step ${i}: after mismatch — core=${canonicalJson(r.state).slice(0, 160)} driver=${canonicalJson(st.after).slice(0, 160)}`);
        break;
      }
      prev = st.after;
    }
  }
  return { ok: errors.length === 0, traces: names.length, steps, errors };
}

/* --- scenario verifier -----------------------------------------------------
   A scenario is declarative data: initial params, evidence tables, an
   action list with slots and actors, expected per-step results (refusals
   carry their named reason), an expected final state, and consumer checks.
   Used by the scenario gate AND by the page's ?selftest — one
   implementation, no second transcription of the expectations. */
function verifyScenario(sc) {
  const lines = [];
  const fail = m => { lines.push(m); return { ok: false, lines }; };
  if (!sc || typeof sc.id !== 'number' || !sc.slug || !sc.story) return fail('scenario: bad header');
  if (!validParams(sc.params)) return fail(`${sc.slug}: bad params`);
  if (!Array.isArray(sc.steps) || !sc.steps.length) return fail(`${sc.slug}: no steps`);
  const env = envFromTables(sc.env || {});
  let s = sc.initial === undefined ? 'absent' : sc.initial;
  let t = -Infinity;
  let accepted = 0, refused = 0;
  for (let i = 0; i < sc.steps.length; i++) {
    const st = sc.steps[i];
    if (typeof st.now !== 'number' || !(t <= st.now)) return fail(`${sc.slug} step ${i}: slot not non-decreasing`);
    t = st.now;
    if (actionActor(st.action) !== st.actor)
      lines.push(`${sc.slug} step ${i}: actor «${st.actor}» ≠ ${actionActor(st.action)} (display only)`);
    const r = step(sc.params, env, st.action, st.now, s);
    const exp = st.expect || { ok: true };
    if (!r.ok && !(exp.ok === false)) return fail(`${sc.slug} step ${i}: refused (${r.reason}), expected applied`);
    if (r.ok && exp.ok === false) return fail(`${sc.slug} step ${i}: applied, expected refusal`);
    if (!r.ok && exp.ok === false) {
      if (exp.reason && r.reason !== exp.reason)
        return fail(`${sc.slug} step ${i}: refused ${r.reason}, expected ${exp.reason}`);
      refused++;
      lines.push(`${sc.slug} step ${i}: refused (${r.reason}) as expected`);
      continue;
    }
    if (exp.flow !== undefined && !sameJson(normFlow(r.flow), normFlow(exp.flow)))
      return fail(`${sc.slug} step ${i}: flow ${canonicalJson(normFlow(r.flow))} ≠ expected ${canonicalJson(normFlow(exp.flow))}`);
    accepted++;
    lines.push(`${sc.slug} step ${i}: applied`);
    s = r.state;
  }
  if (sc.expectFinal !== undefined && !sameJson(s, sc.expectFinal))
    return fail(`${sc.slug}: final state ${canonicalJson(s)} ≠ expected ${canonicalJson(sc.expectFinal)}`);
  for (const c of sc.checks || []) {
    if (c.kind !== 'consumable') return fail(`${sc.slug}: unknown check kind ${c.kind}`);
    const v = consumableState(sc.params, c.now, s);
    if (v.consumable !== c.expect)
      return fail(`${sc.slug}: consumable@${c.now} = ${v.consumable}, expected ${c.expect}`);
    if (Array.isArray(c.failing) && canonicalJson(v.failures) !== canonicalJson(c.failing))
      return fail(`${sc.slug}: failures@${c.now} = ${canonicalJson(v.failures)} ≠ expected ${canonicalJson(c.failing)}`);
    lines.push(`${sc.slug}: consumable@${c.now} = ${v.consumable}` +
      (v.failures.length ? ` (${v.failures.join(', ')})` : ''));
  }
  if (!accepted && !refused) return fail(`${sc.slug}: no steps ran`);
  return { ok: true, lines, accepted, refused };
}

function verifyScenariosAll(scenarios) {
  const results = (scenarios || []).map(sc => ({ sc, r: verifyScenario(sc) }));
  return { ok: results.every(x => x.r.ok), results };
}
/* @@CORE:verify:END@@ */

export { SCHEMA, VERSION, REASONS, validParams, envFromTables, actionActor,
         stateAllows, step, replay, consumableState, canonicalJson, normFlow,
         verifyTracesDoc, verifyScenario, verifyScenariosAll };
