/* ConsumerIdentity / ConsumerWire at the public Singular pin. Explicit finite
 * tables model the selected codec/hash/key map/decoder. This simulator is not
 * a Cardano decoder, network resolver, or implementation conformance layer. */
import {toInternal, toWire, equal, canonical} from './registry-economic-core.mjs';
import {newSystem,attemptSystem} from './checkpoint-system-core.mjs';
import {consumable, validateState, validateParams} from './checkpoint-simulator-core.mjs';

const unique = xs => new Set(xs.map(canonical)).size === xs.length;
const lookup = (entries, key) => entries.find(([k]) => equal(k, key))?.[1];
const nat = x => typeof x === 'bigint' && x >= 0n;
const record = (x, fields) => x && !Array.isArray(x) && typeof x === 'object' &&
  Object.keys(x).length === fields.length && fields.every(f => Object.hasOwn(x, f));
const releaseValid = r => record(r, ['applicationPolicy', 'applicationCredential', 'stateProgram', 'statePolicy']) && Object.values(r).every(nat);
const refValid = r => record(r, ['tx', 'index']) && nat(r.tx) && nat(r.index);
const assetValid = a => record(a, ['policy', 'name']) && nat(a.policy) && nat(a.name);
const pairs = (xs, f, g) => Array.isArray(xs) && xs.every(p => Array.isArray(p) && p.length === 2 && f(p[0]) && g(p[1]));
const bytesValid = xs => Array.isArray(xs) && xs.every(nat); // model naturals, not bytes
function preimageValid(p) {
  if (!p || typeof p !== 'object' || Object.keys(p).length !== 1) return false;
  if (p.state) return record(p.state, ['seed']) && refValid(p.state.seed);
  if (p.active) return record(p.active, ['registry', 'key']) && assetValid(p.active.registry) && nat(p.active.key);
  if (p.applicationConfiguration) return record(p.applicationConfiguration, ['registry']) && assetValid(p.applicationConfiguration.registry);
  if (p.registrationApproval) {
    const r=p.registrationApproval;
    return record(r,['registry','key','holdingAddress','initialDatum','deposit']) && assetValid(r.registry) && ['key','holdingAddress','initialDatum','deposit'].every(k=>nat(r[k]));
  }
  if (p.terminationApproval) return record(p.terminationApproval,['registry','key']) && assetValid(p.terminationApproval.registry) && nat(p.terminationApproval.key);
  return false;
}
function datumValid(d) {
  if(d==='empty')return true;
  if(!d||typeof d!=='object'||Object.keys(d).length!==1)return false;
  if(d.application)return record(d.application,['data'])&&nat(d.application.data);
  if(d.root)return record(d.root,['commitment'])&&nat(d.root.commitment);
  if(d.configuration){const p=d.configuration.parameters;return record(d.configuration,['parameters'])&&record(p,['registrationCost','minimumTip','processTime','retractTime','bookingWidth'])&&Object.values(p).every(nat);}
  return false;
}
function validate(q) {
  if(!record(q,['tables','context','environment','params','now','holding']))throw Error('invalid-query');
  const {tables:t,context:c,environment:e,holding:o}=q;
  if(!record(c,['aid','network','release','seed'])||!nat(c.aid)||!nat(c.network)||!releaseValid(c.release)||!refValid(c.seed))throw Error('invalid-context');
  if(!record(e,['network','release'])||!nat(e.network)||(e.release!==null&&!releaseValid(e.release)))throw Error('invalid-environment');
  if(!nat(q.now)||validateParams(toWire(q.params)))throw Error('invalid-params-or-time');
  if(!record(o,['reference','credential','lovelace','datum','assets'])||!refValid(o.reference)||!nat(o.credential)||!nat(o.lovelace)||!datumValid(o.datum)||!pairs(o.assets,assetValid,nat))throw Error('invalid-holding');
  if(!record(t,['keys','codes','hashes','datums'])||!pairs(t.keys,nat,nat)||!pairs(t.codes,preimageValid,bytesValid)||!pairs(t.hashes,bytesValid,nat)||
    !pairs(t.datums,releaseValid,v=>Array.isArray(v)&&v.length===2&&nat(v[0])&&record(v[1],['aid','state'])&&nat(v[1].aid)&&!validateState(toWire(v[1].state))))throw Error('invalid-interpretation');
}
export function consumerVerdict(input) {
  try {
    const q=toInternal(input);validate(q);
    const {tables:t,context:c,environment:e,holding:o}=q;
    const key=lookup(t.keys,c.aid),statePreimage={state:{seed:c.seed}},stateCode=lookup(t.codes,statePreimage);
    const stateName=stateCode===undefined?undefined:lookup(t.hashes,stateCode);
    const registry=stateName===undefined?undefined:{policy:c.release.statePolicy,name:stateName};
    const activePreimage=registry&&key!==undefined?{active:{registry,key}}:undefined;
    const activeCode=activePreimage?lookup(t.codes,activePreimage):undefined;
    const name=activeCode===undefined?undefined:lookup(t.hashes,activeCode);
    if(!t.keys.length||!t.codes.length||!t.hashes.length||!unique(t.keys.map(p=>p[0]))||!unique(t.codes.map(p=>p[0]))||!unique(t.hashes.map(p=>p[0]))||!unique(t.datums.map(([r,[raw]])=>[r,raw]))||name===undefined)
      return {error:'incomplete-or-ambiguous-interpretation'};
    const expectedAsset={policy:registry.policy,name};
    const quantity=o.assets.filter(([a])=>equal(a,expectedAsset)).reduce((n,[,v])=>n+v,0n);
    const decoded=o.datum?.application?t.datums.find(([r,[raw]])=>equal(r,c.release)&&raw===o.datum.application.data)?.[1][1]:undefined;
    const clauses={network:e.network===c.network,release:equal(e.release,c.release),credential:o.credential===c.release.applicationCredential,
      quantity:quantity===1n,datum:decoded!==undefined,aid:decoded?.aid===c.aid};
    const lifecycle=decoded?consumable(toWire(q.params),toWire(q.now),toWire(decoded.state)):null;
    const failure=Object.entries(clauses).find(([,ok])=>!ok)?.[0];
    const ok=!failure&&lifecycle.ok;
    return {ok,verdict:failure??lifecycle?.verdict??'datum',clauses,expectedAsset:toWire(expectedAsset),quantity:toWire(quantity),lifecycle};
  } catch(e) {return {error:e.message};}
}
export function executeConsumer(query) {const r=consumerVerdict(query);return r.error?{error:r.error}:{ok:r.ok};}

export function checkConsumerCorpus(corpus) {
  if(corpus.schema!=='cardano-keri.consumer.identity'||corpus.version!==1||!corpus.fields?.length||!corpus.journey?.length||!corpus.checks?.length)throw Error('consumer-corpus-schema');
  // Fixed approved fixture census: reject truncation even when all remaining cells pass.
  if(corpus.fields.length!==32||corpus.journey.length!==17||corpus.checks.length!==46||corpus.events?.length!==18)throw Error('consumer-corpus-roster');
  if(!unique(corpus.checks.map(c=>c[0]))||!unique(corpus.events.map(c=>c.name)))throw Error('consumer-duplicate-control');
  const cells=[...corpus.fields,...corpus.journey.map(frame=>frame.consumer)];
  if(!unique(corpus.fields.map(c=>c.name))||!unique(corpus.journey.map(c=>c.name)))throw Error('consumer-duplicate-case');
  let accepted=0,refused=0,errors=0;
  for(const c of cells){const actual=executeConsumer(c.query);if(!equal(actual,c.result))throw Error('consumer-result-mismatch:'+c.name+':'+JSON.stringify(actual));if(actual.error)errors++;else if(actual.ok)accepted++;else refused++;}
  if(!accepted||!refused||!errors)throw Error('consumer-missing-verdict-class');
  for(const [name,passed]of corpus.checks)if(passed!==true)throw Error('consumer-control-failed:'+name);
  if(!corpus.events?.length)throw Error('consumer-missing-connected-events');
  let session=newSystem(corpus.events[0].params,corpus.events[0].env);
  let systemAccepted=0,systemRefused=0;
  const snapshots=new Map([[canonical(session.state),session]]);
  for(const cell of corpus.events){
    if(!equal(session.state,cell.input))throw Error('consumer-disconnected:'+cell.name);
    const next=attemptSystem(session,cell.command);
    if(!equal(next.record.result,cell.result))throw Error('consumer-system-result:'+cell.name);
    session=next.session;snapshots.set(canonical(session.state),session);if(cell.result.ok)systemAccepted++;else systemRefused++;
  }
  if(!equal(session.state,corpus.journey.at(-1).system))throw Error('consumer-final-system');
  if(corpus.associationEvents?.length!==2)throw Error('consumer-association-roster');
  for(const cell of corpus.associationEvents){
    const start=snapshots.get(canonical(cell.input));if(!start)throw Error('consumer-association-disconnected');
    const next=attemptSystem(start,cell.command);if(!equal(next.record.result,cell.result))throw Error('consumer-association-result:'+cell.name);
  }
  return {systemAccepted,systemRefused,queries:cells.length,accepted,refused,errors,controls:corpus.checks.length};
}
