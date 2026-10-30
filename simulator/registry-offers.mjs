/* Stakeholders organize proposed moves; they grant no authority. Evidence and
 * transaction inputs are judged by the same core for every card. The display
 * clock selects proposal intervals and is not a Registry state transition. */
import * as B from './registry-fixtures.mjs';
import { decodeInput } from './registry-wire.mjs';
import { toInternal, toWire, equal } from './registry-economic-core.mjs';
export const NAMES = { 42: 'Alice (refund address)', 6: 'authorized bond recipient', 7: 'Sam (booker)' };
export const nameOf = address => NAMES[address] ?? `address ${address}`;
export const CAST = {
  alice: { name: 'Alice', role: 'identity owner', aid: 11, blurb: 'Holds the keys of AID 11; wants a usable checkpoint, kept alive until it is convicted.' },
  bob: { name: 'Bob', role: 'identity owner', aid: 12, blurb: 'Holds the keys of AID 12; wants the other identity to leave his custody unchanged.' },
  hal: { name: 'Hal', role: 'folder', blurb: 'Holds a view of the requests and funds a fee; wants to process a valid batch.' },
  sam: { name: 'Sam', role: 'booker', blurb: 'Can book a convicted carrier and receive the exact booking premium; cannot sweep a live carrier.' },
  cora: { name: 'Cora', role: 'convictor', blurb: 'Brings duplicity evidence against a retained key; wants its termination to reach the consuming fold.' },
  mallory: { name: 'Mallory', role: 'challenger', blurb: 'Tries a stale generation, duplicate input or different policy.' },
};
export const ACTOR_ORDER = Object.keys(CAST);
export const actionTag = action => action && typeof action === 'object' && Object.keys(action).length === 1 ? Object.keys(action)[0] : null;
export const dataOf = action => action?.[actionTag(action)] ?? {};
export function describeAction(action) {
  const a = dataOf(action);
  switch (actionTag(action)) {
    case 'bookRegistration': return `book registration of AID ${a.booking.request.key}`;
    case 'convictCkpt': return `convict AID ${a.aid}; retain pending custody`;
    case 'bookTermination': return `book termination of AID ${a.aid}`;
    case 'fold': return `process a batch at generation ${a.expectedGen}`;
    case 'genericRetraction': return 'reclaim a registration with its owner signature';
    case 'genericRejection': return 'reject a registration using the current state read';
    default: return 'unknown action';
  }
}
export function offersFor(actorId, tree, nodeId = tree.cursor) {
  const session = tree.nodes[nodeId].session, { params, state } = session;
  decodeInput(params, session.env, state, { convictCkpt: { aid: 0 } });
  const exact = toInternal(state), time = toInternal(session.now ?? 0);
  const pending = [...exact.registrations, ...exact.terminations.map(e => e.booking)];
  const fresh = pending.reduce((n, b) => n + b.request.reference.tx, 100n) + exact.gen;
  const chain = [], keri = [];
  const offer = (label, action) => chain.push({ kind: actionTag(action), label, action });
  const aid = CAST[actorId]?.aid;
  if (aid) {
    offer('book a registration request', B.registrationAction(params, state, aid, toWire(fresh), toWire(time)));
    keri.push({ label: 'inception verifies', row: { inception: [aid] } });
    for (const b of exact.registrations.filter(b => b.request.key === BigInt(aid))) {
      offer(`reclaim request ${b.request.reference.tx}`, B.retractionAction(params, state, toWire(b.request.reference), toWire(time), toWire(time + 1n), [toWire(b.request.refundAddress)]));
    }
  }
  if (actorId === 'hal' || actorId === 'mallory') {
    const afterSubmission = pending.reduce((t, b) => b.request.submittedAt !== null && b.request.submittedAt > t ? b.request.submittedAt : t, time);
    const action = B.foldAction(params, state, toWire(pending.map(b => b.request.reference)), toWire(afterSubmission));
    offer('process the current batch', action);
    if (actorId === 'mallory') {
      offer('try another application policy', { fold: { ...action.fold, expectedPlugin: toWire(exact.config.applicationPolicy + 1n) } });
      offer('try another generation', { fold: { ...action.fold, expectedGen: toWire(exact.gen === 0n ? 1n : exact.gen - 1n) } });
      if (pending.length) {
        const duplicate = structuredClone(action); duplicate.fold.transaction.transaction.inputs.push(structuredClone(duplicate.fold.transaction.transaction.inputs[0]));
        offer('try spending a request twice', duplicate);
      }
    }
  }
  if (actorId === 'sam') {
    for (const c of state.carriers) offer(`book termination of AID ${c.aid}`, B.terminationAction(params, state, c.aid, toWire(fresh)));
    for (const b of exact.registrations) {
      offer(`reject expired request ${b.request.reference.tx}`, B.rejectionAction(params, state, toWire(b.request.reference), toWire(time), toWire(time + 1n)));
      const leaf = exact.trie.find(([key]) => key === b.request.key)?.[1] ?? 'unknown';
      offer(`check lifecycle mismatch for ${b.request.key}`, B.rejectionAction(params, state, toWire(b.request.reference), toWire(time), toWire(time + 1n), toWire({ mismatch: { leaf } })));
    }
  }
  if (actorId === 'cora') for (const c of state.carriers) {
    offer(`convict AID ${c.aid}`, { convictCkpt: { aid: c.aid } });
    keri.push({ label: `duplicity at AID ${c.aid}, key ${c.k}`, row: { duplicity: [c.aid, c.k] } });
  }
  return { chain, keri };
}
