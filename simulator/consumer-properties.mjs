/* Finite sampled properties, not substitutes for the Lean proofs or production
 * conformance. Each row has a concrete witness and an executable falsifier. */
import {executeConsumer,consumerVerdict} from './consumer-core.mjs';
import {equal,toInternal} from './registry-economic-core.mjs';
import {consumable} from './checkpoint-simulator-core.mjs';
const cell=(c,n)=>[...c.fields,...c.journey.map(f=>f.consumer)].find(x=>x.name===n);
const frame=(c,n)=>c.journey.find(x=>x.name===n);
const quantity=(o,a)=>toInternal(o.assets).filter(([x])=>equal(x,a)).reduce((n,[,v])=>n+v,0n);
const a=c=>consumerVerdict(cell(c,'positive-anchor').query).expectedAsset;
const refused=(c,n)=>executeConsumer(cell(c,n).query).ok===false;
const accepted=(c,n)=>executeConsumer(cell(c,n).query).ok===true;
const money=c=>{
 const f=c.registrationFold,e=c.registrationEconomic,t=e.transaction;
 return equal(f.assets.spent,t.inputs.map(x=>x.ref))&&t.inputs.every(x=>x.ref!==null)&&
 equal(f.spentOutputs.map(x=>[x.reference,x.lovelace]),c.registrationUnspent.filter(([r])=>t.inputs.some(x=>equal(x.ref,r))).map(([r,o])=>[r,o.output.lovelace]))&&
 equal(f.outputs.map(x=>x.lovelace),e.outputs.map(x=>x.output.lovelace))&&equal(f.interval,t.validity)&&equal(f.fee,t.fee)&&equal(f.donation,t.donation);
};
const genesis=c=>{
 const q=cell(c,'positive-anchor').query,b=c.registrationFold.before;
 return equal(b.seed,q.context.seed)&&equal(c.genesis.spent,[q.context.seed])&&
 equal(c.genesis.mint,[[b.identity,1]])&&equal(c.genesis.invoked,[q.context.release.statePolicy])&&
 c.genesisOutputs.length===1&&equal(c.genesisOutputs[0],b.state)&&b.trie.length===0;
};
const origin=c=>c.journey.every(f=>equal(f.system.aids[0].origin,c.journey[0].system.aids[0].origin));
const registration=c=>{
 const f=c.journey[0],o=f.system.aids[0].origin,q=f.consumer.query;
 return genesis(c)&&money(c)&&equal(f.holding,c.registrationFold.outputs[1])&&
 equal(o.carrierRef,f.holding.reference)&&equal(o.configuration.applicationPolicy,q.context.release.applicationPolicy)&&
 equal(o.configuration.activePolicy,q.context.release.statePolicy)&&equal(c.registrationFold.changes[0].register.key,q.context.aid)&&
 quantity(f.holding,a(c))===1n&&origin(c);
};
const rows=[];
function add(id,theorem,holds,breakWitness){rows.push({id,theorem,holds,breakWitness});}
const flip=(name)=>c=>{const x=cell(c,name);x.query=structuredClone(cell(c,'positive-anchor').query);};
const breakGenesis=c=>{c.genesis.spent=[];};
const breakMoney=c=>{c.registrationFold.fee++;};
const breakOrigin=c=>{c.journey[1].system.aids[0].origin.token++;};
add('CI01','consumableHoldingB_iff',c=>[...c.fields,...c.journey.map(f=>f.consumer)].every(x=>equal(executeConsumer(x.query),x.result)),c=>{cell(c,'positive-anchor').result.ok=false;});
add('CI02','consumableHolding_exact',c=>{const r=consumerVerdict(cell(c,'positive-anchor').query);return r.ok&&Object.values(r.clauses).every(Boolean)&&r.lifecycle.ok;},c=>{cell(c,'positive-anchor').query.holding.credential++;});
add('CI03','existing_eligibility_preserved',c=>c.journey.filter(f=>f.holding).every(f=>equal(executeConsumer(f.consumer.query).ok,consumable(f.consumer.query.params,f.now,f.system.aids[0].state).ok)),c=>{c.journey[1].consumer.query.environment.network++;});
add('CI04','wrong_network_refused',c=>refused(c,'wrong-network'),flip('wrong-network'));
add('CI05','wrong_or_unknown_release_refused',c=>['unknown-release','release-application-policy','release-credential','release-state-program','release-state-policy'].every(n=>refused(c,n)),flip('unknown-release'));
add('CI06','wrong_credential_refused',c=>refused(c,'holding-credential'),flip('holding-credential'));
add('CI07','wrong_quantity_refused',c=>['quantity-zero','quantity-two','duplicate-entries'].every(n=>refused(c,n)),flip('quantity-two'));
add('CI08','wrong_asset_refused',c=>['wrong-policy','wrong-name','other-aid-token'].every(n=>refused(c,n)),flip('wrong-name'));
add('CI09','malformed_datum_refused',c=>['datum-empty','datum-root','datum-malformed'].every(n=>refused(c,n)),flip('datum-empty'));
add('CI10','wrong_datum_aid_refused',c=>refused(c,'datum-other-aid'),flip('datum-other-aid'));
add('CI11','ineligible_state_refused',c=>['maturity-minus-one','frozen','poisoned','absent-datum','terminal-datum'].every(n=>refused(c,n)),flip('frozen'));
add('CI12','retained_custody_refused',c=>['parked','termination-pending','termination-booked'].every(n=>refused(c,n)),flip('parked'));
add('CI13','different_encoded_keys_distinct',c=>!equal(cell(c,'other-aid-token').query.holding.assets[0][0],a(c)),c=>{cell(c,'other-aid-token').query.holding.assets[0][0]=a(c);});
add('CI14','different_registries_distinct',c=>!equal(cell(c,'rival-registry-policy').query.holding.assets[0][0],a(c)),c=>{cell(c,'rival-registry-policy').query.holding.assets[0][0]=a(c);});
add('CI15','different_seeds_distinct',c=>['rival-seed-transaction','rival-seed-index'].every(n=>!equal(cell(c,n).query.holding.assets[0][0],a(c))),c=>{cell(c,'rival-seed-index').query.holding.assets[0][0]=a(c);});
add('CI16','rival_seed_refused',c=>refused(c,'genuine-rival-registry'),flip('genuine-rival-registry'));
add('CI17','local_step_retains_exact_asset',c=>c.journey.filter(f=>f.holding).every(f=>equal(f.logicalAsset,a(c))&&quantity(f.holding,a(c))===1n),c=>{frame(c,'parked').holding.assets=[];});
add('CI18','completion_refuses_consumer',c=>{const f=c.journey.at(-1);return f.holding===null&&f.logicalAsset===null&&f.system.aids[0].state==='convicted'&&refused(c,f.name);},c=>{c.journey.at(-1).holding=c.journey[1].holding;});
add('CI19','system_preserves_identity_binding',origin,breakOrigin);
// CI20 samples the two explicit registry identities and the fixture map rows.
add('CI20','faithful_origin_registry_separation',c=>c.registryMap.length===2&&!equal(c.registryMap[0][0],c.registryMap[1][0])&&!equal(c.registryMap[0][1],c.registryMap[1][1]),c=>{c.registryMap[1][1]=c.registryMap[0][1];});
add('CI21','createRegistry_exact',genesis,breakGenesis);
add('CI22','createRegistry_complete',genesis,breakGenesis);
add('CI23','registerJoint_sound',registration,breakOrigin);
add('CI24','registerJoint_money',money,breakMoney);
add('CI25','registered_consumer_iff',c=>registration(c)&&!accepted(c,'registered-juvenile')&&accepted(c,'registered-mature'),c=>{cell(c,'registered-mature').query.environment.network++;});
add('CI26','registerJoint_complete',registration,breakMoney);
export const CONSUMER_PROPERTIES=rows;
export function checkConsumerProperties(corpus){
 return rows.map(r=>{const holds=!!r.holds(corpus);if(!holds)throw Error('consumer-property:'+r.id+'/'+r.theorem);return {id:r.id,theorem:r.theorem,holds,scope:'finite sampled instance'};});
}
