// The decoded rotation judgment is shared by conviction and the two-event reader.
import { equal, toInternal, toWire } from './registry-economic-core.mjs';

const unique = xs => [...new Set(xs)];
const distinct = xs => unique(xs).length === xs.length;
const fractionAdd = (a, b) => [a[0] * b[1] + b[0] * a[1], a[1] * b[1]];
const fraction = w => [BigInt(w.numerator), BigInt(w.denominator)];
const atLeastOne = w => w[1] > 0n && w[0] >= w[1];
export function thresholdSatisfied(threshold, keys, signers) {
  const signed = keys.map(k => signers.includes(k));
  if (threshold.count) return threshold.count.required <= keys.length && threshold.count.required <= signed.filter(Boolean).length;
  const clauses = threshold.weighted.clauses;
  let offset = 0;
  const valid = clauses.length > 0 && clauses.every(clause => {
    let sum = [0n, 1n];
    if (!clause.length) return false;
    for (const w of clause) {
      const term = w.key || w.group;
      if (!term.weight.denominator) return false;
      if (w.key) {
        if (signed[offset]) sum = fractionAdd(sum, fraction(term.weight));
        offset++;
      } else {
        if (!term.members.length || term.members.some(m => !m.denominator)) return false;
        let inner = [0n, 1n];
        for (const member of term.members) {
          if (signed[offset]) inner = fractionAdd(inner, fraction(member));
          offset++;
        }
        if (atLeastOne(inner)) sum = fractionAdd(sum, fraction(term.weight));
      }
    }
    return atLeastOne(sum);
  });
  return valid && offset === keys.length;
}
export function verifiedSigners(event, signatures) {
  return unique(signatures.filter(s => s.verified && equal(s.event, event)).map(s => s.signer));
}
export function derivedWitnesses(prior, event) {
  const witnesses = prior.witnesses.filter(w => !event.cuts.includes(w));
  for (const w of event.adds) if (!witnesses.includes(w)) witnesses.push(w);
  return witnesses;
}
export function signingValid(prior, signed) {
  const event = signed.event, signers = verifiedSigners(event, signed.signatures);
  const exposed = prior.nextKeys.filter(k => event.keys.includes(k));
  return prior.nextKeys.length > 0 && distinct(prior.nextKeys) && distinct(event.keys) && event.keys.length > 0 &&
    thresholdSatisfied(prior.nextThreshold, prior.nextKeys, signers.filter(k => exposed.includes(k))) &&
    thresholdSatisfied(event.threshold, event.keys, signers);
}
export function receiptsValid(prior, signed) {
  const event = signed.event, witnesses = derivedWitnesses(prior, event), receipts = verifiedSigners(event, signed.receipts);
  return distinct(prior.witnesses) && distinct(event.cuts) && distinct(event.adds) && event.witnessThreshold <= witnesses.length &&
    event.witnessThreshold <= witnesses.filter(w => receipts.includes(w)).length;
}
export function rotationValid(prior, signed) {
  return !prior.delegated && signed.event.kind === 'rotation' && signed.structureVerified &&
    signed.event.aid === prior.aid && prior.sn < signed.event.sn && signingValid(prior, signed) && receiptsValid(prior, signed);
}

export function acceptsComparison(comparison) {
  const {tip, rival} = toInternal(comparison);
  return tip.previous !== null && tip.epoch !== 0n &&
    tip.aid === rival.event.aid && tip.sn === rival.event.sn &&
    rotationValid(tip.previous, rival) && !equal(tip.writer, rival.event);
}

// CheckpointConviction.Fixtures.comparison with the symbolic key interpretation.
export function convictionFixture(identifier, epoch, sequence) {
  const [aid, e, sn] = toInternal([identifier, epoch, sequence]);
  const one = {count: {required: 1n}};
  const writer = {aid, sn, kind: e === 0n ? 'inception' : 'rotation', priorDigest: 0n,
    keys: [aid], threshold: one, nextKeys: [aid], nextThreshold: one,
    cuts: [], adds: [], witnessThreshold: 0n, extension: []};
  const previous = e === 0n ? null : {aid, sn: sn > 0n ? sn - 1n : 0n, delegated: false,
    nextKeys: [aid], nextThreshold: one, witnesses: []};
  const keys = {curKeys: [[aid]], curThreshold: one, nextKeys: [[aid]], nextThreshold: one,
    witnesses: [], toad: 0n};
  const event = {...writer, nextKeys: [aid + 1n]};
  return toWire({output: {tx: 105n + (aid > 11n ? aid - 11n : 0n), index: 0n},
    comparison: {tip: {aid, epoch: e, sn, keys, previous, writer},
      rival: {event, structureVerified: true, signatures: [{signer: aid, event, verified: true}], receipts: []}}});
}
