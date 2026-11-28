/* Version 3 interchange validation. This is the simulator's input boundary,
 * separate from the model's semantic refusals. Nat/Int are exact and complete
 * records are required; optional default-zero fields use the Lean encoding. */
import { toInternal, toWire } from './registry-economic-core.mjs';
const error = path => { throw Error(`invalid-wire:${path}`); };
const integer = (x, p) => typeof x === 'bigint' ? x : error(p);
const nat = (x, p) => integer(x, p) >= 0n ? x : error(p);
const byte = (x, p) => nat(x, p) < 256n ? x : error(p);
const enumeration = values => (x, p) => values.includes(x) ? x : error(p);
const list = f => (x, p) => Array.isArray(x) ? x.map((v, i) => f(v, `${p}[${i}]`)) : error(p);
const option = f => (x, p) => x === null ? null : f(x, p);
const pair = (f, g) => (x, p) => Array.isArray(x) && x.length === 2 ? [f(x[0], `${p}[0]`), g(x[1], `${p}[1]`)] : error(p);
const record = (fields, optional = {}) => (x, p) => {
  if (!x || typeof x !== 'object' || Array.isArray(x) || Object.keys(x).some(k => !Object.hasOwn(fields, k) && !Object.hasOwn(optional, k))) error(p);
  const out = Object.fromEntries(Object.entries(fields).map(([k, f]) => [k, f(x[k], `${p}.${k}`)]));
  for (const [k, f] of Object.entries(optional)) if (Object.hasOwn(x, k)) out[k] = f(x[k], `${p}.${k}`);
  return out;
};
const variant = (variants, atoms = []) => (x, p) => {
  if (atoms.includes(x)) return x;
  if (!x || typeof x !== 'object' || Array.isArray(x) || Object.keys(x).length !== 1) error(p);
  const [k] = Object.keys(x); if (!Object.hasOwn(variants, k)) error(p);
  return { [k]: variants[k](x[k], `${p}.${k}`) };
};
const zeroOmitted = f => (x, p) => Object.fromEntries(Object.entries(f(x, p)).filter(([k, v]) => !['nonce', 'registrationCost', 'bookingWidth'].includes(k) || v !== 0n));
const fields = names => Object.fromEntries(names.split(' ').map(n => [n, nat]));
const token = record(fields('policy name'));
const ref = record(fields('tx index'));
const interval = record(fields('lower upper'));
const leaf = variant({ known: record({ s: enumeration(['absent', 'active', 'terminal']) }) }, ['unknown']);
const config = zeroOmitted(record({ ...fields('registryId maxFee processTime retractTime applicationPolicy activePolicy'), root: list(byte) }, fields('registrationCost bookingWidth')));
const holding = record({ ...fields('key output'), kind: enumeration(['active']), datum: option(nat) });
const singular = record({ registryId: nat, token });
const approval = record({ signatures: list(list(nat)), ...fields('policy key owner destination assetName'), edge: enumeration(['insertAbsent', 'insertActive', 'updateActive', 'updateTerminal', 'deleteAbsent', 'deleteActive', 'witnessTerminal']) });
const contents = record({ lovelace: nat, applicationTags: list(approval), trieReadyTags: list(token), otherAssets: list(pair(token, nat)) });
const registration = record({ ...fields('registryId key refundAddress destination submittedAt registrationCost declaredTip carrierAda'), reference: ref, contents, datum: option(nat) }, { nonce: nat });
const termination = record({ ...fields('registryId key destination declaredTip carrierAda'), reference: ref, contents, singularTags: list(singular), refundAddress: option(nat), submittedAt: option(nat) }, { nonce: nat });
const nonceOmitted = f => (x, p) => { const out = f(x, p); if (out.nonce === 0n) delete out.nonce; return out; };
const regRequest = nonceOmitted(registration), termRequest = nonceOmitted(termination);
const regBooking = record({ request: regRequest, interval, trieReadyTagsMinted: list(token), applicationTagsMinted: list(approval) });
const termFields = { request: termRequest, custodyInputs: list(holding), trieReadyTagsMinted: list(token) };
const termBooking = record(termFields);
const position = record(fields('epoch sn'));
const localBooking = record({ ...termFields, pendingReference: ref, position });
const spend = record({ reference: ref, aid: nat, position });
const request = variant({ registration: record({ request: regRequest }), termination: record({ request: termRequest }) });
// The historical transaction asset vocabulary is retained exactly.
const asset = pair(enumeration(['active']), nat);
const role = enumeration(['state', 'request', 'destination', 'witness', 'owner']);
const datum = enumeration(['inline', 'hashed', 'none']);
const input = record({ role, datum, ...fields('stateTokens approvals lovelace'), assets: list(pair(asset, integer)), datumValue: option(nat), ref: option(ref), stateToken: option(token) });
const output = record({ role, datum, address: option(nat), stateTokens: nat, config: option(config), commitment: option(nat), assets: list(pair(asset, integer)), lovelace: nat, reference: option(nat), datumValue: option(nat), stateToken: option(token) });
const tx = record({ inputs: list(input), outputs: list(output), mint: list(pair(asset, integer)), signers: list(nat), refunds: list(pair(nat, nat)), referenceInputs: list(input), validity: option(interval), fee: nat, donation: nat });
const economicOutput = record({ output, contents, singularTags: list(singular), request: option(request) });
const economicTx = record({ transaction: tx, identity: nat, outputs: list(economicOutput), trieReadyMint: list(pair(token, integer)), applicationMint: list(pair(token, integer)), stateMint: list(pair(token, integer)), singularMint: list(pair(singular, integer)) });
const utxo = list(pair(ref, economicOutput));
const rejection = record({ transaction: economicTx, stateReference: ref, members: list(pair(ref, variant({ mismatch: record({ leaf }) }, ['expired']))) });
const carrier = record({ ...fields('aid token minAda'), original: holding, pendingSpend: option(spend) });
const payload = record({ ...fields('aid token booker bookingFee'), original: holding, spend });
const sys = record({ ...fields('gen treasury nextToken'), config, trie: list(pair(nat, leaf)), carriers: list(carrier), registrations: list(regBooking), terminations: list(record({ booking: termBooking, payload })), bindings: list(pair(nat, nat)) });
const params = record(fields('D tip Mc Mr'));
const flag = (x, p) => typeof x === 'boolean' ? x : error(p);
const fraction = record(fields('numerator denominator'));
const weight = variant({key: record({weight: fraction}), group: record({weight: fraction, members: list(fraction)})});
const threshold = variant({count: record({required: nat}), weighted: record({clauses: list(list(weight))})});
const keys = list(list(nat));
const keyMaterial = record({curKeys: keys, curThreshold: threshold, nextKeys: keys, nextThreshold: threshold,
  witnesses: keys, toad: integer});
const content = record({...fields('aid sn priorDigest witnessThreshold'),
  kind: enumeration(['inception', 'rotation', 'interaction', 'delegatedInception', 'delegatedRotation']),
  keys: list(nat), threshold, nextKeys: list(nat), nextThreshold: threshold,
  cuts: list(nat), adds: list(nat), extension: list(nat)});
const predecessor = record({...fields('aid sn'), delegated: flag, nextKeys: list(nat),
  nextThreshold: threshold, witnesses: list(nat)});
const signature = record({signer: nat, event: content, verified: flag});
const tip = record({...fields('aid epoch sn'), keys: keyMaterial, previous: option(predecessor), writer: content});
const rival = record({event: content, structureVerified: flag, signatures: list(signature), receipts: list(signature)});
const conviction = record({output: ref, comparison: record({tip, rival})});
const assetView = record({spent: list(ref), outputs: list(record({assets: list(pair(token, nat))})),
  mint: list(pair(token, integer)), invoked: list(nat)});
const observedSpend = record({input: ref, transaction: assetView});
const production = record({output: ref, observation: observedSpend});
const env = record({bookings: list(record({identity: nat, assets: assetView})),
  convictionTransactions: list(production), convictions: list(conviction)});
const advance = record({kind: enumeration(['advance','freeze','convict']), ...fields('epoch sn next'),
  observation: observedSpend});
const mints = record({advances: list(advance), convictions: list(production)});
export const validateMints = value => toWire(mints(toInternal(value), 'mintTransactions'));
const action = variant({
  bookRegistration: record({ booking: regBooking }), convictCkpt: record(fields('aid')),
  bookTermination: record({ ...fields('aid booker fee'), booking: localBooking }),
  fold: record({ ...fields('expectedGen expectedPlugin'), unspent: utxo, transaction: economicTx }),
  returnRequests: record({ unspent: utxo, transaction: rejection }),
});
export function decodeInput(p, e, s, a) {
  const result = [params(toInternal(p), 'params'), env(toInternal(e), 'env'), sys(toInternal(s), 'state'), action(toInternal(a), 'action')];
  if (result[0].D === 0n || result[0].Mr + result[0].tip > result[0].Mc) error('params.proofs');
  return result;
}
export const validateState = state => toWire(sys(toInternal(state), 'state'));
export const validateConfig = value => toWire(config(toInternal(value), 'config'));
export const validateEnv = value => toWire(env(toInternal(value), 'env'));
export const validateParams = value => {
  const p=params(toInternal(value),'params');
  if(p.D===0n||p.Mr+p.tip>p.Mc)error('params.proofs');
  return toWire(p);
};
export const validateRival = value => toWire(rival(toInternal(value), 'rival'));
export const validateAction = value => toWire(action(toInternal(value),'action'));
export const validateRegistrationBooking = value => toWire(regBooking(toInternal(value),'registration'));
export const validateTerminationBooking = value => toWire(localBooking(toInternal(value),'termination'));
export const validateEconomicTransaction = value => toWire(economicTx(toInternal(value),'transaction'));
export const validateUtxo = value => toWire(utxo(toInternal(value),'unspent'));
const flow = record({ ...fields('deposited intoRequest bookingFee'), locked: list(pair(nat, nat)), bondReturn: option(pair(nat, nat)), premium: option(pair(nat, nat)) });
const observation = record({ ...fields('aid minAda supply'), binding: option(nat), leaf });
const result = variant({ error: (x, p) => typeof x === 'string' ? x : error(p), ok: record({ flow, state: sys, observations: list(observation) }) });
export const validateResult = value => toWire(result(toInternal(value), 'result'));
