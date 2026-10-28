/* Model transaction assembly for interactive play. These are complete proposed
 * observations, derived from RegistryScenarioFixtures and the public Singular
 * witness constructors. stepFn judges every proposal. No wallet or ledger data
 * is fetched, and no signature is produced here. */
import { toInternal, toWire, equal, singularTag, applicationName, readyTag, rootOf, known } from './registry-economic-core.mjs';
import { decodeInput } from './registry-wire.mjs';
const emptyEnv = { inception: [], rotationFrom: [], duplicity: [], closeAuth: [] };
const sum = values => values.reduce((a, b) => a + b, 0n);
const sub = (a, b) => a > b ? a - b : 0n;
const nat = value => { const n = toInternal(value); if (typeof n !== 'bigint' || n < 0n) throw Error('invalid-fixture-nat'); return n; };
const prepare = (params, state) => { const [p, , s] = decodeInput(params, emptyEnv, state, { park: { aid: 0, recipient: 0 } }); return [p, s]; };
const requests = s => [...s.registrations.map(b => ({ kind: 'registration', booking: b })), ...s.terminations.map(e => ({ kind: 'termination', booking: e.booking }))];
const fresh = s => sum(requests(s).map(m => m.booking.request.reference.tx)) + 1n;
const ordinary = amount => ({ output: { role: 'owner', datum: 'none', address: 0n, stateTokens: 0n, config: null, commitment: null, assets: [], lovelace: amount, reference: null, datumValue: null, stateToken: null }, contents: { lovelace: amount, applicationTags: [], trieReadyTags: [], otherAssets: [] }, singularTags: [], request: null });
const stateOutput = config => { const o = ordinary(0n); return { ...o, output: { ...o.output, role: 'state', datum: 'inline', config, stateToken: { policy: config.registryId, name: 0n }, stateTokens: 1n, address: null } }; };
const input = ref => ({ role: 'request', datum: 'inline', stateTokens: 0n, approvals: 0n, lovelace: 0n, assets: [], datumValue: null, ref, stateToken: null });
function unspent(s, funding) {
  return [...requests(s).map(({ kind, booking: { request: r } }) => {
    const o = ordinary(r.contents.lovelace);
    return [r.reference, { ...o, output: { ...o.output, role: 'request', datum: 'inline' }, contents: r.contents, singularTags: kind === 'termination' ? r.singularTags : [], request: { [kind]: { request: r } } }];
  }), [{ tx: fresh(s), index: 0n }, stateOutput(s.config)], [{ tx: fresh(s), index: 1n }, ordinary(funding)]];
}
function transaction(s, members, inputs, outputs, validity, fee, donation, signers = []) {
  return { identity: fresh(s) + 1n, outputs,
    transaction: { inputs: inputs.map(input), outputs: outputs.map(o => o.output), mint: [], signers, refunds: [], referenceInputs: [], validity, fee, donation },
    trieReadyMint: members.flatMap(m => m.booking.request.contents.trieReadyTags).map(tag => [tag, -1n]),
    applicationMint: members.flatMap(m => m.booking.request.contents.applicationTags).map(t => [{ policy: t.policy, name: t.assetName }, -1n]),
    stateMint: [], singularMint: [] };
}
export function registrationAction(params, state, aidValue, referenceValue, timeValue = 0) {
  const [p, s] = prepare(params, state), aid = nat(aidValue), reference = nat(referenceValue), time = nat(timeValue);
  const request = { reference: { tx: reference, index: 0n }, registryId: s.config.registryId, key: aid, refundAddress: 42n,
    destination: aid + 100n, submittedAt: time + 1n, registrationCost: s.config.registrationCost ?? 0n, declaredTip: p.tip, carrierAda: p.Mc + p.D, datum: aid + 700n,
    contents: { lovelace: p.Mc + p.D + p.tip + (s.config.registrationCost ?? 0n), applicationTags: [], trieReadyTags: [], otherAssets: [] } };
  const approval = { policy: s.config.applicationPolicy, edge: 'insertActive', key: aid, owner: 42n, destination: request.destination, assetName: applicationName(request), signatures: [] };
  request.contents.applicationTags = [approval]; request.contents.trieReadyTags = [readyTag(s.config, request, 'registration')];
  return toWire({ bookRegistration: { booking: { request, interval: { lower: time, upper: time + 1n }, trieReadyTagsMinted: request.contents.trieReadyTags, applicationTagsMinted: [approval] } } });
}
export function terminationAction(params, state, aidValue, referenceValue, bookerValue = 7, feeValue = 1) {
  const [p, s] = prepare(params, state), aid = nat(aidValue), reference = nat(referenceValue), booker = nat(bookerValue), fee = nat(feeValue);
  const carrier = s.carriers.find(c => c.aid === aid); if (!carrier) throw Error('fixture-carrier-missing');
  const request = { reference: { tx: reference, index: 0n }, registryId: s.config.registryId, key: aid, destination: carrier.original.output,
    declaredTip: p.tip, carrierAda: p.Mr, singularTags: [singularTag(s.config, aid)], refundAddress: null, submittedAt: null,
    contents: { lovelace: p.Mr + p.tip, applicationTags: [], trieReadyTags: [], otherAssets: [] } };
  request.contents.trieReadyTags = [readyTag(s.config, request, 'termination')];
  return toWire({ bookTermination: { aid, booker, fee, booking: { request, custodyInputs: [carrier.original], trieReadyTagsMinted: request.contents.trieReadyTags } } });
}
export function foldAction(params, state, referenceValues, timeValue = 2, fundingValue = 1, feeValue = 1) {
  const [, s] = prepare(params, state), refs = referenceValues.map(ref => ({ tx: nat(ref.tx), index: nat(ref.index) }));
  const time = nat(timeValue), funding = nat(fundingValue), fee = nat(feeValue);
  const members = refs.map(ref => { const m = requests(s).find(m => equal(m.booking.request.reference, ref)); if (!m) throw Error('fixture-request-missing'); return m; });
  let trie = s.trie;
  for (const { kind, booking: { request: r } } of members) trie = [[r.key, known(kind === 'registration' ? 'active' : 'terminal')], ...trie.filter(([key]) => key !== r.key)];
  const carriers = members.filter(m => m.kind === 'registration').map(({ booking: { request: r } }) => {
    const o = ordinary(r.carrierAda); return { ...o, output: { ...o.output, address: r.destination, datum: r.datum === null ? 'none' : 'inline', datumValue: r.datum }, singularTags: [singularTag(s.config, r.key)] };
  });
  const tips = sum(members.map(m => m.booking.request.declaredTip));
  const donation = sum(members.map(({ kind, booking: { request: r } }) => kind === 'registration' ? r.registrationCost : sub(r.contents.lovelace, r.declaredTip)));
  const outputs = [stateOutput({ ...s.config, root: rootOf(trie) }), ...carriers, ordinary(sub(funding + tips, fee))];
  const tx = transaction(s, members, [...refs, { tx: fresh(s), index: 0n }, { tx: fresh(s), index: 1n }], outputs, { lower: time, upper: time + 1n }, fee, donation);
  tx.singularMint = members.flatMap(({ kind, booking: { request: r } }) => kind === 'registration' ? [[singularTag(s.config, r.key), 1n]] : r.singularTags.map(t => [t, -1n]));
  return toWire({ fold: { expectedGen: s.gen, expectedPlugin: s.config.applicationPolicy, unspent: unspent(s, funding), transaction: tx } });
}
export function retractionAction(params, state, reference, lowerValue, upperValue, signers = [42], fundingValue = 1, feeValue = 1) {
  const [, s] = prepare(params, state), ref = { tx: nat(reference.tx), index: nat(reference.index) }, funding = nat(fundingValue), fee = nat(feeValue);
  const member = requests(s).find(m => equal(m.booking.request.reference, ref)); if (!member) throw Error('fixture-request-missing');
  const r = member.booking.request, output = ordinary(r.contents.lovelace + sub(funding, fee)); output.output.address = r.refundAddress;
  const tx = transaction(s, [member], [ref, { tx: fresh(s), index: 1n }], [output], { lower: nat(lowerValue), upper: nat(upperValue) }, fee, 0n, signers.map(nat));
  return toWire({ genericRetraction: { unspent: unspent(s, funding), transaction: tx } });
}
export function rejectionAction(params, state, reference, lowerValue, upperValue, ground = 'expired') {
  const [, s] = prepare(params, state), ref = { tx: nat(reference.tx), index: nat(reference.index) };
  const member = requests(s).find(m => equal(m.booking.request.reference, ref)); if (!member) throw Error('fixture-request-missing');
  const r = member.booking.request, output = ordinary(sub(r.contents.lovelace, r.declaredTip)); output.output.address = r.refundAddress;
  const tx = transaction(s, [member], [ref], [output], { lower: nat(lowerValue), upper: nat(upperValue) }, 0n, 0n);
  tx.transaction.referenceInputs = [input({ tx: fresh(s), index: 0n })];
  return toWire({ genericRejection: { unspent: unspent(s, 0n), transaction: { transaction: tx, stateReference: { tx: fresh(s), index: 0n }, members: [[ref, toInternal(ground)]] } } });
}
