// Finite claim names and policy parameters from CardanoKeri.Attestation.Fixtures.
import {equal, toWire} from './registry-economic-core.mjs';

function spendName(kind, input) {
  const tag = {advance: 1n, freeze: 2n, convict: 4n}[kind];
  return ((BigInt(input.tx) * 256n + BigInt(input.index)) * 256n + 111n) * 8n + tag;
}

function bookingAsset(app, request) {
  const name = ((BigInt(request.datum) * 256n + BigInt(request.carrierAda)) * 256n +
    BigInt(app)) * 256n + BigInt(request.reference.index);
  return {policy: 51n, name};
}

function issued(tx, asset) {
  return tx.mint.reduce((sum, [id, qty]) => equal(asset, id) ? sum + BigInt(qty) : sum, 0n) === 1n;
}

export function bookingAttested(rows, app, request) {
  const tx = rows.find(row => equal(row.identity, request.reference.tx));
  return !!tx && request.datum !== null && issued(tx.assets, bookingAsset(app, request));
}

export function spendAttested(observation, kind) {
  if (!observation) return false;
  const {input, transaction} = observation;
  if (!transaction.spent.some(ref => equal(ref, input))) return false;
  const name = spendName(kind, input);
  const policies = kind === 'convict' ? [52n, 53n] : [54n];
  return policies.every(policy => issued(transaction, {policy, name}));
}

export function convictionAttested(rows, output) {
  return spendAttested(rows.find(row => equal(row.output, output))?.observation, 'convict');
}

export function sampleBooking(app, request) {
  return toWire({identity: request.reference.tx, assets: {spent: [], outputs: [],
    mint: [[bookingAsset(app, request), 1]], invoked: [51]}});
}

function sampleSpend(kind, input) {
  const policies = kind === 'convict' ? [52, 53] : [54];
  const name = spendName(kind, input);
  return toWire({input, transaction: {spent: [input], outputs: [], invoked: policies,
    mint: policies.map(policy => [{policy, name}, 1])}});
}

export function sampleConviction(output, aid) {
  const offset = BigInt(aid) > 11n ? BigInt(aid) - 11n : 0n;
  return {output, observation: sampleSpend('convict', {tx: 103n + offset, index: 0})};
}

export function sampleAdvances([epoch, sn, next]) {
  const e = BigInt(epoch);
  const input = e === 0n ? {tx: 102, index: 1} : {tx: 102n + e, index: 0};
  return ['advance', 'freeze'].map(kind => ({kind, epoch, sn, next, observation: sampleSpend(kind, input)}));
}
