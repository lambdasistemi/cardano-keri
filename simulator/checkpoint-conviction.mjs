// Decoded enforcement evidence. The simulator's finite signature table
// verifies exactly the key and message used by the Lean fixture verifier.
import { equal, toInternal, toWire } from './registry-economic-core.mjs';

function verifiedPositions(keys, bytes, signatures) {
  const positions = new Set();
  for (const [index, signature] of signatures) {
    const key = keys[index];
    if (key !== undefined && equal([...key, ...bytes], signature)) positions.add(BigInt(index));
  }
  return positions;
}

function thresholdMet(threshold, positions) {
  if (threshold.unweighted) return BigInt(threshold.unweighted.m) <= BigInt(positions.size);
  let offset = 0n;
  return threshold.weighted.clauses.every(clause => {
    let numerator = 0n, denominator = 1n;
    for (const [n, d] of clause) {
      if (positions.has(offset)) {
        numerator = numerator * BigInt(d) + BigInt(n) * denominator;
        denominator *= BigInt(d);
      }
      offset++;
    }
    return denominator <= numerator;
  });
}

export function acceptsComparison({tip, rival}) {
  const keys = tip.keys;
  return rival.rotation && equal(tip.aid, rival.aid) && equal(tip.sn, rival.sn) &&
    equal(keys.curKeys, rival.revealedKeys) &&
    thresholdMet(keys.curThreshold, verifiedPositions(keys.curKeys, rival.bytes, rival.signatures)) &&
    BigInt(keys.toad) <= BigInt(verifiedPositions(keys.witnesses, rival.bytes, rival.receipts).size) &&
    !equal([keys.curThreshold, keys.nextKeys, keys.nextThreshold, keys.toad],
      [rival.threshold, rival.nextKeys, rival.nextThreshold, rival.toad]);
}

// CheckpointConviction.Fixtures.comparison and Registry.Scenarios.convictionFixture.
export function convictionFixture(identifier, epoch, sequence) {
  const [aid, e, sn] = toInternal([identifier, epoch, sequence]);
  const one = {unweighted: {m: 1n}}, keys = [[aid]], bytes = [aid, e, sn, 1n];
  return toWire({
    output: {tx: 105n + (aid > 11n ? aid - 11n : 0n), index: 0n},
    comparison: {
      tip: {aid, epoch: e, sn, keys: {curKeys: keys, curThreshold: one, nextKeys: keys,
        nextThreshold: one, witnesses: [], toad: 0n}},
      rival: {bytes, rotation: sn !== 0n, aid, sn, revealedKeys: keys, threshold: one,
        nextKeys: [[aid + 1n]], nextThreshold: one, toad: 0n, signatures: [[0n, [aid, ...bytes]]], receipts: []}
    }
  });
}
