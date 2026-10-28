/* Executable transcription of the pinned Singular economic judgments used by
 * Registry. Source ownership is recorded in registry-model-bindings.json.
 * Arithmetic is BigInt; wire integers outside the exact Number range are
 * canonical decimal strings. No cryptographic or ledger conformance is claimed.
 */
export const toInternal = x => {
  if (typeof x === 'number') {
    if (!Number.isSafeInteger(x)) throw Error('invalid-exact-integer');
    return BigInt(x);
  }
  if (typeof x === 'string' && /^-?(0|[1-9][0-9]*)$/.test(x)) {
    const n = BigInt(x);
    if (n.toString() !== x || (n >= -9007199254740991n && n <= 9007199254740991n)) throw Error('noncanonical-exact-integer');
    return n;
  }
  if (Array.isArray(x)) return x.map(toInternal);
  if (x && typeof x === 'object') return Object.fromEntries(Object.entries(x).map(([k, v]) => [k, toInternal(v)]));
  return x;
};
export const toWire = x => {
  if (typeof x === 'bigint') return x >= -9007199254740991n && x <= 9007199254740991n ? Number(x) : x.toString();
  if (Array.isArray(x)) return x.map(toWire);
  if (x && typeof x === 'object') return Object.fromEntries(Object.entries(x).map(([k, v]) => [k, toWire(v)]));
  return x;
};
export const canonical = x => JSON.stringify(toWire(x), (_, value) => value && typeof value === 'object' && !Array.isArray(value)
  ? Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b))) : value);
export const equal = (a, b) => canonical(a) === canonical(b);
const sum = xs => xs.reduce((a, b) => a + b, 0n);
const sub = (a, b) => a > b ? a - b : 0n;
const has = (xs, x) => xs.some(y => equal(x, y));
const unique = xs => xs.every((x, i) => !has(xs.slice(0, i), x));
const sameQuantities = (left, right) => [...left, ...right].every(([tag]) =>
  sum(left.filter(([t]) => equal(t, tag)).map(([, n]) => n)) === sum(right.filter(([t]) => equal(t, tag)).map(([, n]) => n)));
const permutation = (a, b) => sameQuantities(a.map(t => [t, 1n]), b.map(t => [t, 1n]));
export class ModelRefusal extends Error {}
const fail = reason => { throw new ModelRefusal(reason); };
const require = (condition, reason) => { if (!condition) fail(reason); };
export const known = s => ({ known: { s } });
export const trieGet = (trie, key) => trie.find(([k]) => k === key)?.[1] ?? 'unknown';
const trieSet = (trie, key, leaf) => [[key, leaf], ...trie.filter(([k]) => k !== key)];
export function fnv1a(bytes) {
  return bytes.reduce((h, byte) => BigInt.asUintN(64, (h ^ BigInt(byte)) * 16777619n), 14695981039346656037n);
}
const u64bytes = n => [56n, 48n, 40n, 32n, 24n, 16n, 8n, 0n].map(shift => (n >> shift) & 255n);
export function rootOf(trie) {
  const bytes = [...trie].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).flatMap(([key, leaf]) =>
    [...u64bytes(fnv1a([key & 255n])), key & 255n, leaf === 'unknown' ? 255n : { absent: 0n, active: 1n, terminal: 2n }[leaf.known.s]]);
  return u64bytes(fnv1a(bytes));
}
// The model hashes the complete compact JSON array of decimal naturals.
const commitment = (domain, fields) => fnv1a(new TextEncoder().encode(`[${[domain, ...fields].map(String).join(',')}]`));
export const applicationName = r => commitment(0n, [1n, r.key, r.refundAddress, r.destination, r.nonce ?? 0n]);
export const readyTag = (c, r, kind) => ({ policy: c.registryId, name: commitment(1n,
  kind === 'registration' ? [0n, r.key, r.refundAddress, r.destination, r.registrationCost, r.declaredTip, r.carrierAda, r.nonce ?? 0n]
    : [1n, r.key, r.destination, r.nonce ?? 0n]) + 1n });
export const singularTag = (c, key) => ({ registryId: c.registryId, token: { policy: c.activePolicy, name: key } });
const stateToken = c => ({ policy: c.registryId, name: 0n });
const appIdentity = tag => ({ policy: tag.policy, name: tag.assetName });
const containsRef = (inputs, ref) => inputs.some(i => equal(i.ref, ref));
const lookup = (u, ref) => u.find(([r]) => equal(r, ref))?.[1] ?? null;
const spentEntries = (u, tx) => u.filter(([ref]) => containsRef(tx.transaction.inputs, ref));
const spent = (u, tx) => spentEntries(u, tx).map(([, o]) => o);
export const ordinary = o => o.output.stateTokens === 0n && !o.contents.trieReadyTags.length && !o.contents.applicationTags.length && !o.singularTags.length;
const ordinaryValue = outputs => sum(outputs.filter(ordinary).map(o => o.output.lovelace));
const bare = o => !o.output.assets.length && !o.contents.otherAssets.length;
const memberAt = (w, ref) => {
  const registration = w.pending.find(b => equal(b.request.reference, ref));
  if (registration) return { kind: 'registration', booking: registration };
  const termination = w.terminations.find(b => equal(b.request.reference, ref));
  return termination ? { kind: 'termination', booking: termination } : null;
};
export const foldMembers = (w, tx) => tx.transaction.inputs.flatMap(i => i.ref === null ? [] : [memberAt(w, i.ref)].filter(Boolean));
const presentInputs = (u, tx) => {
  require(tx.inputs.every(i => i.ref !== null && lookup(u, i.ref) !== null), 'spent-input-missing');
  require(tx.referenceInputs.every(i => i.ref !== null && lookup(u, i.ref) !== null), 'reference-input-missing');
};
const disjoint = tx => tx.referenceInputs.every(i => i.ref === null || !containsRef(tx.inputs, i.ref));
function observations(w, u, tx) {
  require(unique(u.map(([ref]) => ref)), 'unspent-reference-duplicate');
  require(u.every(([ref]) => ref.tx !== tx.identity), 'transaction-identity-not-fresh');
  function observes(b, kind) {
    const r = b.request, o = lookup(u, r.reference);
    return o !== null && equal(o.request, { [kind]: { request: r } }) && equal(o.contents, r.contents) &&
      equal(o.singularTags, kind === 'registration' ? [] : r.singularTags) && o.output.role === 'request' &&
      o.output.datum === 'inline' && o.output.lovelace === r.contents.lovelace && o.output.stateTokens === 0n && !o.output.assets.length;
  }
  require(w.pending.every(b => observes(b, 'registration')) && w.terminations.every(b => observes(b, 'termination')), 'request-observation-mismatch');
  require(equal(tx.outputs.map(o => o.output), tx.transaction.outputs) && tx.outputs.every(o => o.output.lovelace === o.contents.lovelace), 'output-observation-mismatch');
}
const exactBurns = (held, mint) => sameQuantities(mint, held.map(t => [t, -1n]));
const tagsBurned = (u, tx) => exactBurns(spent(u, tx).flatMap(o => o.contents.trieReadyTags), tx.trieReadyMint) &&
  exactBurns(spent(u, tx).flatMap(o => o.contents.applicationTags).map(appIdentity), tx.applicationMint) &&
  tx.outputs.every(o => !o.contents.trieReadyTags.length && !o.contents.applicationTags.length);
export function balanced(u, tx) {
  const inputs = spent(u, tx).map(o => o.output), outputs = tx.transaction.outputs;
  return sum(inputs.map(o => o.lovelace)) === sum(outputs.map(o => o.lovelace)) + tx.transaction.donation + tx.transaction.fee &&
    sameQuantities([...inputs.flatMap(o => o.assets), ...tx.transaction.mint], outputs.flatMap(o => o.assets)) &&
    [...inputs, ...outputs].every(({ stateToken: token }) =>
      sum(inputs.filter(o => equal(o.stateToken, token)).map(o => o.stateTokens)) === sum(outputs.filter(o => equal(o.stateToken, token)).map(o => o.stateTokens)));
}
export function bookRegistration(w, b) {
  const c = w.registry.config, r = b.request, tags = r.contents.applicationTags;
  const shape = r.registryId === c.registryId && r.registrationCost === (c.registrationCost ?? 0n) && c.maxFee <= r.declaredTip && !r.contents.otherAssets.length &&
    tags.length === 1 && tags.every(t => t.policy === c.applicationPolicy && t.edge === 'insertActive' && t.key === r.key && t.owner === r.refundAddress && t.destination === r.destination && t.assetName === applicationName(r));
  const amount = r.registrationCost + r.declaredTip + r.carrierAda;
  require(shape && r.contents.lovelace >= amount, 'dirty-request');
  require(r.contents.lovelace <= amount, 'hidden-surplus');
  require(equal(r.contents.trieReadyTags, [readyTag(c, r, 'registration')]) && equal(b.trieReadyTagsMinted, r.contents.trieReadyTags), 'forged-trie-ready-tag');
  require(equal(b.applicationTagsMinted, tags), 'dirty-request');
  require(b.interval.lower < b.interval.upper, 'invalid-booking-interval');
  require(r.submittedAt === b.interval.upper, 'backdated-booking');
  require(sub(b.interval.upper, b.interval.lower) <= (c.bookingWidth ?? 0n), 'booking-too-wide');
  require(![...w.pending, ...w.terminations].some(p => equal(p.request.reference, r.reference)), 'request-already-pending');
  return { ...w, pending: [b, ...w.pending] };
}
export function bookTermination(w, b) {
  const c = w.registry.config, r = b.request, amount = r.declaredTip + r.carrierAda;
  require(c.maxFee <= r.declaredTip && !r.contents.otherAssets.length && r.refundAddress === null && r.submittedAt === null && !r.contents.applicationTags.length && r.contents.lovelace >= amount, 'dirty-request');
  require(r.contents.lovelace <= amount, 'hidden-surplus');
  require(r.registryId === c.registryId && equal(r.singularTags, [singularTag(c, r.key)]), 'forged-singular-tag');
  require(equal(r.contents.trieReadyTags, [readyTag(c, r, 'termination')]) && equal(b.trieReadyTagsMinted, r.contents.trieReadyTags), 'forged-trie-ready-tag');
  const custody = w.registry.held.filter(h => h.key === r.key && h.kind === 'active');
  require(equal(trieGet(w.registry.trie, r.key), known('active')) && custody.length > 0, 'singular-tag-not-in-custody');
  require(equal(b.custodyInputs, custody) && b.custodyInputs.length === 1, 'forged-singular-tag');
  require(![...w.pending, ...w.terminations].some(p => equal(p.request.reference, r.reference)), 'request-already-pending');
  return { ...w, registry: { ...w.registry, held: w.registry.held.filter(h => !(h.key === r.key && h.kind === 'active')) }, terminations: [b, ...w.terminations] };
}
function structuralFold(w, members) {
  let state = { ...w.registry, held: [...w.registry.held, ...w.terminations.flatMap(b => b.custodyInputs)] };
  const created = [];
  for (const { kind, booking: { request: r } } of members) {
    const leaf = trieGet(state.trie, r.key), active = state.held.some(h => h.key === r.key && h.kind === 'active');
    if (kind === 'registration') require(leaf === 'unknown', 'key-exists');
    else if (equal(leaf, known('active'))) require(active, 'token-missing');
    else fail(leaf === 'unknown' ? 'key-unknown' : leaf.known.s === 'absent' ? 'not-booked' : 'terminal-immutable');
    const trie = trieSet(state.trie, r.key, known(kind === 'registration' ? 'active' : 'terminal'));
    state = { ...state, trie, config: { ...state.config, root: rootOf(trie) }, held: kind === 'registration'
      ? [{ key: r.key, kind: 'active', output: r.destination, datum: r.datum }, ...state.held]
      : state.held.filter(h => !(h.key === r.key && h.kind === 'active')) };
  }
  for (const { kind, booking: { request: r } } of members) {
    if (kind === 'termination') require(!created.includes(r.key), 'token-missing');
    else created.push(r.key);
  }
  return state;
}
const stateShape = (c, o) => o.output.stateTokens === 1n && equal(o.output.stateToken, stateToken(c)) && o.output.datum === 'inline' && equal(o.output.config, c) &&
  o.request === null && !o.singularTags.length && !o.contents.trieReadyTags.length && !o.contents.applicationTags.length && bare(o);
export function foldAccepted(w, u, tx) {
  const t = tx.transaction, c = w.registry.config;
  require(unique(t.inputs.map(i => i.ref)), 'fold-duplicate-input');
  require(disjoint(t), 'fold-input-overlap');
  presentInputs(u, t); observations(w, u, tx);
  const members = foldMembers(w, tx);
  require(members.length > 0, 'empty-fold');
  require(t.validity !== null, 'fold-interval-missing');
  require(t.validity.lower < t.validity.upper, 'fold-interval-empty');
  for (const { kind, booking: { request: r } } of members) if (kind === 'registration')
    require(t.validity.lower >= r.submittedAt && r.submittedAt <= t.validity.upper && t.validity.upper <= r.submittedAt + c.processTime, 'not-phase1');
  require(u.every(([ref, o]) => !containsRef(t.inputs, ref) || memberAt(w, ref) !== null || o.output.stateTokens > 0n || ordinary(o)), 'fold-unrecognized-input');
  const result = structuralFold(w, members), inputs = spent(u, tx), states = inputs.filter(o => o.output.stateTokens > 0n);
  require(states.length === 1, 'fold-state-missing');
  require(stateShape(c, states[0]) && equal(c.root, rootOf(w.registry.trie)), 'fold-state-mismatch');
  const continued = tx.outputs.filter(o => o.output.stateTokens > 0n);
  require(continued.length === 1 && stateShape(result.config, continued[0]), 'fold-state-mismatch');
  require(continued[0].output.lovelace === states[0].output.lovelace, 'fold-state-value-mismatch');
  require(tagsBurned(u, tx), 'fold-tag-not-burned');
  for (const { kind, booking: { request: r } } of members) if (kind === 'registration') {
    const outputs = tx.outputs.filter(o => has(o.singularTags, singularTag(c, r.key)));
    require(outputs.length === 1, 'fold-destination-mismatch');
    const o = outputs[0];
    require(o.output.address === r.destination && equal(o.output.datumValue, r.datum) && o.output.datum === (r.datum === null ? 'none' : 'inline'), 'fold-destination-mismatch');
    require(o.output.lovelace === r.carrierAda, 'destination-carrier-mismatch');
    require(equal(o.singularTags, [singularTag(c, r.key)]) && o.output.stateTokens === 0n && o.request === null && !o.contents.trieReadyTags.length && !o.contents.applicationTags.length && bare(o), 'fold-destination-mismatch');
  }
  const mint = members.flatMap(({ kind, booking: { request: r } }) => kind === 'registration' ? [[singularTag(c, r.key), 1n]] : r.singularTags.map(tag => [tag, -1n]));
  const carriers = members.filter(m => m.kind === 'registration').map(m => singularTag(c, m.booking.request.key));
  require(sameQuantities(tx.singularMint, mint) && permutation(tx.outputs.flatMap(o => o.singularTags), carriers), 'fold-singular-mismatch');
  require(!tx.stateMint.length && !t.mint.length && tx.outputs.every(bare) && inputs.every(bare), 'fold-foreign-asset');
  const donation = sum(members.map(({ kind, booking: { request: r } }) => kind === 'registration' ? r.registrationCost : sub(r.contents.lovelace, r.declaredTip)));
  require(t.donation === donation, 'fold-donation-mismatch');
  require(ordinaryValue(inputs) >= t.fee, 'fold-fee-funding-short');
  require(balanced(u, tx), 'fold-unbalanced');
  const terminations = w.terminations.filter(b => !containsRef(t.inputs, b.request.reference));
  return { registry: { ...result, held: result.held.filter(h => !(h.kind === 'active' && terminations.some(b => b.request.key === h.key))) },
    pending: w.pending.filter(b => !containsRef(t.inputs, b.request.reference)), terminations, treasury: w.treasury + t.donation };
}
const supplyUnchanged = (u, tx) => !tx.transaction.mint.length && !tx.stateMint.length && !tx.singularMint.length && [...spent(u, tx), ...tx.outputs].every(o => o.output.stateTokens === 0n && !o.output.assets.length && !o.singularTags.length && !o.contents.otherAssets.length);
function refunds(tx, requests, retraction, reason) {
  for (const address of requests.map(r => r.refundAddress)) {
    const owed = sum(requests.filter(r => r.refundAddress === address).map(r => retraction ? r.contents.lovelace : sub(r.contents.lovelace, r.declaredTip)));
    require(sum(tx.outputs.filter(o => o.output.address === address).map(o => o.output.lovelace)) >= owed, reason);
  }
}
export function retractionAccepted(w, u, tx) {
  const t = tx.transaction, inputs = spent(u, tx);
  require(!inputs.some(o => o.output.stateTokens > 0n || o.output.role === 'state'), 'retract-state-spent');
  require(!u.some(([ref, o]) => containsRef(t.referenceInputs, ref) && (o.output.stateTokens > 0n || o.output.role === 'state')), 'retract-state-read');
  require(unique(t.inputs.map(i => i.ref)), 'retract-duplicate-input'); require(disjoint(t), 'retract-input-overlap');
  presentInputs(u, t); observations(w, u, tx);
  require(!w.terminations.some(b => containsRef(t.inputs, b.request.reference)), 'retract-registration-only');
  const selected = w.pending.filter(b => containsRef(t.inputs, b.request.reference));
  require(selected.length > 0, 'retract-request-not-pending'); require(selected.length === 1, 'retract-single-request');
  const r = selected[0].request, funding = spentEntries(u, tx).filter(([ref]) => !equal(ref, r.reference)).map(([, o]) => o);
  for (const o of funding) {
    require(o.output.stateTokens === 0n && o.output.role !== 'state', 'retract-state-spent');
    require(!o.contents.trieReadyTags.length, 'retract-funding-trie-ready-tag');
    require(!o.contents.applicationTags.length, 'retract-funding-application-tag');
    require(!o.singularTags.length, 'retract-funding-singular-tag');
    require(o.output.role !== 'request', 'retract-funding-request-address'); require(o.request === null, 'retract-funding-request');
  }
  require(t.signers.includes(r.refundAddress), 'retract-owner');
  require(t.validity !== null, 'retract-interval-missing'); require(t.validity.lower < t.validity.upper, 'retract-interval-empty');
  require(t.validity.lower >= r.submittedAt + w.registry.config.processTime && t.validity.upper <= r.submittedAt + w.registry.config.processTime + w.registry.config.retractTime, 'retract-window');
  require(tagsBurned(u, tx), 'retract-tag-not-burned'); require(tx.outputs.every(bare) && inputs.every(bare), 'retract-foreign-asset');
  require(supplyUnchanged(u, tx), 'retract-registry-supply'); refunds(tx, [r], true, 'retract-refund-short');
  require(t.donation === 0n, 'retract-donation'); require(ordinaryValue(funding) >= t.fee, 'retract-fee-funding-short'); require(balanced(u, tx), 'retract-unbalanced');
  return { ...w, pending: w.pending.filter(b => !containsRef(t.inputs, b.request.reference)) };
}
export function rejectionAccepted(w, u, rejection) {
  const tx = rejection.transaction, t = tx.transaction, ref = rejection.stateReference, members = rejection.members;
  require(!(containsRef(t.inputs, ref) && containsRef(t.referenceInputs, ref)), 'reject-state-overlap');
  require(!spent(u, tx).some(o => o.output.stateTokens > 0n || o.output.role === 'state'), 'reject-state-spent');
  require(unique(t.inputs.map(i => i.ref)) && unique(members.map(([r]) => r)), 'reject-duplicate-input');
  require(disjoint(t), 'reject-input-overlap'); presentInputs(u, t);
  require(containsRef(t.referenceInputs, ref), 'reject-state-reference-missing');
  const state = lookup(u, ref); require(state !== null, 'reference-input-missing');
  require(state.output.stateTokens === 1n && state.output.role === 'state' && state.output.stateToken !== null, 'reject-state-token-missing');
  require(state.output.stateToken.policy === w.registry.config.registryId, 'reject-foreign-state');
  require(state.output.stateToken.name === 0n, 'reject-state-token-name');
  require(state.output.datum === 'inline' && state.output.config !== null, 'reject-state-datum');
  require(equal(state.output.config.root, rootOf(w.registry.trie)), 'reject-stale-state');
  require(equal(state.output.config, w.registry.config), 'reject-state-configuration'); observations(w, u, tx);
  require(t.validity !== null, 'reject-interval-missing'); require(t.validity.lower < t.validity.upper, 'reject-interval-empty');
  require(members.length > 0, 'reject-empty-batch'); require(permutation(t.inputs.map(i => i.ref), members.map(([r]) => r)), 'reject-input-members');
  const requests = [];
  for (const [ref, ground] of members) {
    const member = memberAt(w, ref); require(member !== null, 'reject-request-not-pending');
    const r = member.booking.request, leaf = trieGet(w.registry.trie, r.key);
    if (ground === 'expired') {
      require(member.kind === 'registration', 'reject-termination-no-expiry');
      require(t.validity.lower >= r.submittedAt + w.registry.config.processTime + w.registry.config.retractTime, 'reject-not-expired');
    } else {
      require(equal(ground.mismatch.leaf, leaf), 'reject-evidence-mismatch');
      require(member.kind === 'registration' ? leaf !== 'unknown' : !equal(leaf, known('active')), 'reject-compatible');
    }
    require(member.kind === 'registration', 'reject-termination'); requests.push(r);
  }
  require(tagsBurned(u, tx), 'reject-tag-not-burned'); require(supplyUnchanged(u, tx), 'reject-registry-supply');
  refunds(tx, requests, false, 'reject-refund-short');
  return { ...w, pending: w.pending.filter(b => !members.some(([ref]) => equal(ref, b.request.reference))) };
}
