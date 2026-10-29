/* Executable Registry adapter. Every action follows CardanoKeri.Registry.stepFn;
 * imported transaction judgments are in registry-economic-core.mjs. This is a
 * model simulator, with finite evidence tables, not production authorization.
 * Wire v3 carries whole states/transactions and exact integers. */
import * as E from './registry-economic-core.mjs';
import { decodeInput, validateState, validateConfig, validateEnv, validateResult } from './registry-wire.mjs';
export const SCHEMA = 'cardano-keri.registry.trace';
export const VERSION = 3;
export const { canonical, equal } = E;
const require = (condition, reason) => { if (!condition) throw new E.ModelRefusal(reason); };
const containsRef = (inputs, ref) => inputs.some(i => E.equal(i.ref, ref));
const flow = values => ({ deposited: 0n, locked: [], bondReturn: null, premium: null, intoRequest: 0n, bookingFee: 0n, ...values });
const toWorld = s => ({ registry: { config: s.config, trie: s.trie, held: s.carriers.map(c => c.original) }, pending: s.registrations, terminations: s.terminations.map(e => e.booking), treasury: s.treasury });
const carrierAt = (s, aid) => s.carriers.find(c => E.equal(c.aid, aid)) ?? null;
const pendingAt = (s, ref) => s.terminations.find(e => E.equal(e.booking.request.reference, ref)) ?? null;
const bindingAt = (s, aid) => s.bindings.find(([k]) => E.equal(k, aid))?.[1] ?? null;
function observations(s) {
  const aids = [...s.bindings.map(([a]) => a), ...s.carriers.map(c => c.aid), ...s.terminations.map(e => e.payload.aid)]
    .filter((a, i, all) => all.findIndex(b => E.equal(a, b)) === i);
  return aids.map(aid => ({ aid, binding: bindingAt(s, aid), leaf: E.trieGet(s.trie, aid), minAda: carrierAt(s, aid)?.minAda ?? 0n,
    supply: BigInt(s.carriers.filter(c => c.original.key === aid && c.original.kind === 'active').length + s.terminations.flatMap(e => e.booking.request.singularTags).filter(t => E.equal(t, E.singularTag(s.config, aid))).length) }));
}
function execute(p, env, s, action) {
  const [kind] = Object.keys(action), a = action[kind], world = toWorld(s);
  let after = s, moved = flow({});
  if (kind === 'bookRegistration') {
    const b = a.booking;
    require(b.request.carrierAda === p.Mc + p.D && b.request.declaredTip === p.tip, 'keri-registration-value-mismatch');
    const next = E.bookRegistration(world, b);
    after = { ...s, registrations: [b, ...s.registrations] };
    require(E.equal(toWorld(after), next), 'keri-registration-reconstruction-mismatch'); moved = flow({ deposited: b.request.contents.lovelace });
  } else if (['park', 'revive', 'convictCkpt', 'bookTermination'].includes(kind)) {
    const c = carrierAt(s, a.aid); require(c !== null, 'keri-carrier-missing');
    const evidence = (name, second) => env[name].some(([aid, value]) => aid === a.aid && value === second);
    if (kind === 'park') {
      require(c.st === 'live' && evidence('closeAuth', a.recipient), 'keri-close-refused');
      after = { ...s, carriers: s.carriers.map(old => old.aid === a.aid ? { ...old, k: old.k + 1n, st: 'parked' } : old) };
      moved = flow({ bondReturn: [a.recipient, p.D] });
    } else if (kind === 'revive') {
      require(c.st === 'parked' && evidence('rotationFrom', c.k), 'keri-revival-refused');
      after = { ...s, carriers: s.carriers.map(old => old.aid === a.aid ? { ...old, k: old.k + 1n, st: 'live' } : old) };
      moved = flow({ deposited: p.D, locked: [[a.aid, p.D]] });
    } else if (kind === 'convictCkpt') {
      require(c.st !== 'terminationPending' && evidence('duplicity', c.k), 'keri-conviction-refused');
      after = { ...s, carriers: s.carriers.map(old => old.aid === a.aid ? { ...old, st: 'terminationPending' } : old) };
    } else {
      require(c.st === 'terminationPending', 'keri-conviction-required');
      const b = a.booking, r = b.request;
      require(r.key === a.aid && r.destination === c.original.output && E.equal(b.custodyInputs, [c.original]) && c.minAda === p.Mc && r.carrierAda === p.Mr && r.declaredTip === p.tip && r.contents.lovelace === p.Mr + p.tip, 'keri-termination-binding-mismatch');
      const next = E.bookTermination(world, b);
      after = { ...s, carriers: s.carriers.filter(old => old.aid !== a.aid), terminations: [{ booking: b, payload: { aid: a.aid, token: c.token, keyState: c.k, original: c.original, booker: a.booker, bookingFee: a.fee } }, ...s.terminations] };
      require(E.equal(toWorld(after), next), 'keri-termination-reconstruction-mismatch');
      moved = flow({ premium: [a.booker, p.Mc - p.Mr - p.tip], bookingFee: a.fee, intoRequest: p.Mr + p.tip });
    }
  } else if (kind === 'fold') {
    require(a.expectedGen === s.gen, 'keri-generation-mismatch');
    require(a.expectedPlugin === s.config.applicationPolicy, 'keri-plugin-mismatch');
    const members = E.foldMembers(world, a.transaction);
    require(members.every(m => m.kind !== 'registration' || env.inception.includes(m.booking.request.key)), 'keri-inception-refused');
    const next = E.foldAccepted(world, a.unspent, a.transaction);
    for (const { kind, booking: b } of members) {
      if (kind === 'termination') {
        const e = pendingAt(s, b.request.reference); require(e !== null, 'keri-termination-metadata-missing');
        require(E.equal(e.booking, b), 'keri-termination-metadata-mismatch');
      } else {
        require(s.registrations.some(old => E.equal(old, b)), 'keri-registration-metadata-missing');
        const c = { aid: b.request.key, token: after.nextToken, original: { key: b.request.key, kind: 'active', output: b.request.destination, datum: b.request.datum }, k: 0n, st: 'live', minAda: p.Mc };
        after = { ...after, carriers: [c, ...after.carriers], bindings: [[c.aid, c.token], ...after.bindings], nextToken: after.nextToken + 1n };
      }
    }
    after = { ...after, gen: s.gen + 1n, config: next.registry.config, trie: next.registry.trie, treasury: next.treasury,
      registrations: s.registrations.filter(b => !containsRef(a.transaction.transaction.inputs, b.request.reference)), terminations: s.terminations.filter(e => !containsRef(a.transaction.transaction.inputs, e.booking.request.reference)) };
    require(E.equal(toWorld(after), next), 'keri-fold-reconstruction-mismatch');
    moved = flow({ locked: members.filter(m => m.kind === 'registration').map(m => [m.booking.request.key, p.D]) });
  } else {
    const next = kind === 'genericRetraction' ? E.retractionAccepted(world, a.unspent, a.transaction) : E.rejectionAccepted(world, a.unspent, a.transaction);
    after = { ...s, registrations: s.registrations.filter(b => next.pending.some(old => E.equal(old, b))) };
    require(E.equal(toWorld(after), next), 'keri-recovery-reconstruction-mismatch');
  }
  return { ok: { flow: moved, state: after, observations: observations(after) } };
}
// Invalid interchange throws. Semantic refusals alone become {error: reason}.
export function stepFn(params, env, action, state) {
  const [p, e, s, a] = decodeInput(params, env, state, action);
  try { return validateResult(E.toWire(execute(p, e, s, a))); }
  catch (error) { if (!(error instanceof E.ModelRefusal)) throw error; return { error: error.message }; }
}
export function init(config) {
  return E.toWire({ gen: 0n, config: { ...E.toInternal(validateConfig(config)), root: E.rootOf([]) }, trie: [], carriers: [], registrations: [], terminations: [], treasury: 0n, bindings: [], nextToken: 0n });
}
export { validateState };
export function checkCell(cell) {
  validateResult(cell.result);
  const actual = stepFn(cell.params, cell.env, cell.action, cell.input);
  return { name: cell.name, matches: E.equal(actual, cell.result), actual, expected: cell.result };
}

/** Replay every complete result, and require connected trunks and forks.
 * Arbitrary boundary inputs are separate from histories; their results alone
 * do not establish reachability. Fresh-generation equality is the trace gate's
 * separate responsibility. */
export function checkCorpus(doc) {
  const reasons = []; let cells = 0, applied = 0, refused = 0;
  const fail = text => reasons.push(text);
  const inspect = (cell, label) => {
    cells++;
    try {
      const report = checkCell(cell);
      if (!report.matches) fail(`${label}: result mismatch`);
      if (report.actual.ok) applied++; else refused++;
    } catch (error) { fail(`${label}: ${error.message}`); }
  };
  const chain = (entries, start, label) => {
    let current = start;
    for (const [i, cell] of entries.entries()) {
      if (!equal(cell.input, current)) fail(`${label}[${i}]: disconnected input`);
      inspect(cell, `${label}[${i}]`);
      if (cell.result.ok) current = cell.result.ok.state;
    }
    return current;
  };
  try {
    if (doc.schema !== SCHEMA || doc.version !== VERSION) throw Error('schema/version');
    const names = ['retained-output', 'mixed-custody-and-recovery', 'expired-registration', 'registration-retraction', 'seed-437', 'seed-9001'];
    if (!equal(doc.traces.map(t => t.name), names)) throw Error('trace roster');
    for (const trace of doc.traces) {
      if (!trace.cells.length) throw Error(`empty trace ${trace.name}`);
      chain(trace.cells, init(trace.cells[0].input.config), trace.name);
    }
    if (doc.grid.length !== 56 || doc.boundaries.length !== 161) throw Error('boundary census');
    doc.grid.forEach((c, i) => inspect(c, `local[${i}]`));
    doc.boundaries.forEach((c, i) => inspect(c, `economic[${i}]`));
    if (!equal(doc.stories.map(s => s.id), Array.from({ length: 15 }, (_, i) => i + 1))) throw Error('story roster');
    let forks = 0;
    for (const story of doc.stories) {
      if (!story.cells.length) throw Error(`empty story ${story.id}`);
      const start = init(story.cells[0].input.config), final = chain(story.cells, start, `story ${story.id}`);
      if (!equal(final, story.final)) fail(`story ${story.id}: final mismatch`);
      for (const fork of story.forks) {
        forks++;
        if (!Number.isSafeInteger(fork.at) || fork.at < 0 || fork.at > story.cells.length || !fork.cells.length) throw Error('invalid fork');
        const before = story.cells.slice(0, fork.at).reduce((s, c) => c.result.ok?.state ?? s, start);
        const result = chain(fork.cells, before, `story ${story.id}/${fork.id}`);
        if (!equal(result, fork.final)) fail(`story ${story.id}/${fork.id}: final mismatch`);
      }
    }
    if (forks !== 24) throw Error(`fork census ${forks}`);
    if (!applied || !refused) throw Error('missing positive or refusal controls');
  } catch (error) { fail(error.message); }
  return { ok: !reasons.length, cells, applied, refused, reasons };
}

export function replayScenario(scenario) {
  if (scenario.wireVersion !== 3) throw Error('scenario wireVersion');
  const replay = (steps, start, evidence) => {
    let state = start;
    const cells = steps.map(step => {
      const env = step.env ?? evidence;
      const result = stepFn(scenario.params, env, step.action, state);
      const cell = { name: step.note, params: scenario.params, env, input: state, action: step.action, result };
      if (result.ok) state = result.ok.state;
      return cell;
    });
    return { cells, final: state };
  };
  const start = init(scenario.config), trunk = replay(scenario.steps, start, scenario.env);
  const forks = scenario.forks.map(f => {
    if (!Number.isSafeInteger(f.at) || f.at < 0 || f.at > trunk.cells.length) throw Error('invalid fork offset');
    const before = trunk.cells.slice(0, f.at).reduce((s, c) => c.result.ok?.state ?? s, start);
    return { id: f.id, at: f.at, ...replay(f.steps, before, f.env ?? scenario.env) };
  });
  return { id: scenario.id, slug: scenario.slug, ...trunk, forks };
}

export function checkScenario(scenario, name = scenario.slug) {
  const problems = [], timeline = [], forkTimelines = {};
  let replay;
  try {
    replay = replayScenario(scenario);
    const inspect = (steps, cells, into, label) => {
      if (steps.length !== cells.length || !steps.length) throw Error(`${label}: empty or truncated steps`);
      for (const [i, cell] of cells.entries()) {
        const expected = steps[i].expect;
        if (!expected || typeof expected.ok !== 'boolean') problems.push(`${label}[${i}]: missing expectation`);
        else {
          if (expected.ok !== !!cell.result.ok || (!expected.ok && expected.reason !== cell.result.error)) problems.push(`${label}[${i}]: outcome mismatch`);
          if (!expected.result || !equal(expected.result, cell.result)) problems.push(`${label}[${i}]: full result mismatch`);
        }
        into.push({ step: steps[i], record: cell, session: { params: cell.params, env: cell.env, state: cell.result.ok?.state ?? cell.input } });
      }
    };
    inspect(scenario.steps, replay.cells, timeline, name);
    for (const [i, fork] of scenario.forks.entries()) {
      if (Object.hasOwn(forkTimelines, fork.id)) throw Error('duplicate fork id');
      forkTimelines[fork.id] = [];
      inspect(fork.steps, replay.forks[i].cells, forkTimelines[fork.id], `${name}/${fork.id}`);
      if (!equal(fork.expectFinal, replay.forks[i].final)) problems.push(`${name}/${fork.id}: final mismatch`);
    }
    if (!equal(scenario.expectFinal, replay.final)) problems.push(`${name}: final mismatch`);
  } catch (error) { problems.push(`${name}: ${error.message}`); }
  const stepsRun = timeline.length + Object.values(forkTimelines).reduce((n, cells) => n + cells.length, 0);
  return { ok: !problems.length, problems, timeline, forkTimelines, replay, stepsRun };
}

export function newSession(params, config, env) {
  const state = init(config);
  decodeInput(params, env, state, { park: { aid: 0, recipient: 0 } });
  return { params: structuredClone(params), env: validateEnv(env), state };
}
export function attempt(session, action) {
  const result = stepFn(session.params, session.env, action, session.state);
  const record = { params: session.params, env: session.env, input: session.state, action, result };
  return { session: { ...session, state: result.ok?.state ?? session.state }, record };
}
export function setEvidence(session, env) {
  decodeInput(session.params, env, session.state, { park: { aid: 0, recipient: 0 } });
  return { ...session, env: validateEnv(env) };
}
