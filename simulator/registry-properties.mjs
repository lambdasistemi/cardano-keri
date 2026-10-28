/* Executable observations of the named Lean contracts. A lamp checks its
 * explicit premise on this step, then its conclusion. These finite checks do
 * not replace Reach proofs or establish implementation conformance. */
import { equal, toInternal, toWire, singularTag } from './registry-economic-core.mjs';
export const THEOREMS = [
  { id: 'retained-park', title: 'Parking retains custody and returns the authorized bond', lean: 'Registry.park_retains' },
  { id: 'retained-revive', title: 'Revival rotates the retained key and adds a fresh bond', lean: 'Registry.revive_retains' },
  { id: 'pending-conviction', title: 'Conviction retains custody pending termination', lean: 'Registry.local_conviction_retains' },
  { id: 'booking-custody', title: 'Booking moves the whole carrier into pending custody', lean: 'Registry.bookTermination_iff, Registry.booking_keeps_active_supply' },
  { id: 'pending-frame', title: 'Unconsumed pending entries remain whole', lean: 'Registry.pending_preserved_unless_consumed' },
  { id: 'local-frame', title: 'Local moves keep the registry and other identities', lean: 'Registry.local_actions_world, Registry.nonfold_frame' },
  { id: 'configuration', title: 'Configuration stays fixed; only folds advance generation', lean: 'Registry.config_and_generation_frame' },
  { id: 'binding-domain', title: 'Every registered key has its permanent token binding', lean: 'Registry.fold_binding_domain, Registry.fold_old_binding' },
  { id: 'terminal', title: 'Retired keys never return or keep custody', lean: 'Registry.retired_preserved, Registry.terminal_no_custody' },
  { id: 'fold-burn', title: 'Selected termination burns its exact token and retires its key', lean: 'Registry.fold_consumes_exact, Registry.booked_fold_token_effects' },
];
const getLeaf = (s, aid) => s.trie.find(([key]) => key === aid)?.[1]?.known?.s ?? 'unknown';
const carrier = (s, aid) => s.carriers.find(c => c.aid === aid);
const entry = (s, ref) => s.terminations.find(e => equal(e.booking.request.reference, ref));
const noRoot = c => Object.fromEntries(Object.entries(c).filter(([key]) => key !== 'root'));
const member = (xs, x) => xs.some(y => equal(x, y));
export function properties(record) {
  const out = Object.fromEntries(THEOREMS.map(t => [t.id, { v: 'unshown' }]));
  if (!record.result.ok) return out;
  const { params: p, input: s, action, result: { ok: { state: n, flow: f } } } = toInternal(record);
  const kind = Object.keys(action)[0], a = action[kind], before = carrier(s, a.aid), after = carrier(n, a.aid);
  const check = (id, premise, conclusion) => { if (premise) out[id] = { v: conclusion() ? 'holds' : 'fails' }; };
  const local = ['park', 'revive', 'convictCkpt'].includes(kind);
  check('retained-park', kind === 'park' && before?.st === 'live', () =>
    equal(after, { ...before, k: before.k + 1n, st: 'parked' }) && equal(f.bondReturn, [a.recipient, p.D]) && getLeaf(n, a.aid) === 'active');
  check('retained-revive', kind === 'revive' && before?.st === 'parked', () =>
    equal(after, { ...before, k: before.k + 1n, st: 'live' }) && f.deposited === p.D && equal(f.locked, [[a.aid, p.D]]) && getLeaf(n, a.aid) === 'active');
  check('pending-conviction', kind === 'convictCkpt' && !!before, () =>
    equal(after, { ...before, st: 'terminationPending' }) && getLeaf(n, a.aid) === 'active');
  check('booking-custody', kind === 'bookTermination' && before?.st === 'terminationPending', () => {
    const e = entry(n, a.booking.request.reference);
    return !after && !!e && equal(e, { booking: a.booking, payload: { aid: a.aid, token: before.token, keyState: before.k, original: before.original, booker: a.booker, bookingFee: a.fee } }) &&
      equal(f.premium, [a.booker, p.Mc - p.Mr - p.tip]) && f.intoRequest === p.Mr + p.tip && f.bookingFee === a.fee && getLeaf(n, a.aid) === 'active';
  });
  const consumed = kind === 'fold' ? a.transaction.transaction.inputs.map(i => i.ref) : [];
  const untouched = s.terminations.filter(e => !member(consumed, e.booking.request.reference));
  check('pending-frame', untouched.length > 0, () => untouched.every(e => member(n.terminations, e)));
  check('local-frame', local, () => equal(s.trie, n.trie) && equal(s.config, n.config) && equal(s.bindings, n.bindings) && s.nextToken === n.nextToken && s.treasury === n.treasury &&
    equal(s.registrations, n.registrations) && equal(s.terminations, n.terminations) && equal(s.carriers.filter(c => c.aid !== a.aid), n.carriers.filter(c => c.aid !== a.aid)));
  check('configuration', true, () => equal(noRoot(s.config), noRoot(n.config)) && n.gen === s.gen + (kind === 'fold' ? 1n : 0n));
  check('binding-domain', true, () => n.trie.every(([key]) => n.bindings.filter(([aid]) => aid === key).length === 1) && n.bindings.every(([aid]) => n.trie.some(([key]) => aid === key)) && s.bindings.every(b => member(n.bindings, b)));
  const retired = s.trie.filter(([, l]) => l.known?.s === 'terminal').map(([key]) => key);
  check('terminal', retired.length > 0, () => retired.every(aid => getLeaf(n, aid) === 'terminal' && !carrier(n, aid) && !n.terminations.some(e => e.payload.aid === aid)));
  const selected = s.terminations.filter(e => member(consumed, e.booking.request.reference));
  check('fold-burn', kind === 'fold' && selected.length > 0, () => selected.every(e => {
    const aid = e.payload.aid, tag = singularTag(s.config, aid);
    const quantity = a.transaction.singularMint.filter(([t]) => equal(t, tag)).reduce((sum, [, q]) => sum + q, 0n);
    return quantity === -1n && getLeaf(n, aid) === 'terminal' && !carrier(n, aid) && !entry(n, e.booking.request.reference);
  }));
  return out;
}
export function corpusCells(doc) {
  return [...doc.traces.flatMap(t => t.cells), ...doc.grid, ...doc.boundaries,
    ...doc.stories.flatMap(s => [...s.cells, ...s.forks.flatMap(f => f.cells)])];
}
export function oracleIndex(doc) {
  const index = new Map();
  for (const cell of corpusCells(doc)) {
    // Canonical key below is order independent, including uploaded DSL objects.
    index.set(canonicalKey(cell), cell.result);
  }
  return index;
}
const canonicalKey = r => JSON.stringify(toWire([r.params, r.env, r.input, r.action]), (_, v) => v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort(([a],[b])=>a.localeCompare(b))) : v);
export function oracleResult(index, record) {
  const expected = index.get(canonicalKey(record));
  return expected === undefined ? { found: false } : { found: true, agrees: equal(expected, record.result) };
}
