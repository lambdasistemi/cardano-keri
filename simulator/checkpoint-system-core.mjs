/* Finite certificate interpreter for Checkpoint's associated system events.
 * The oracle is CheckpointCertificate: successful Lean execution constructs an
 * actual SysStep witness. Public sessions start at Sys.init and accept command
 * histories; an uploaded state cannot manufacture an origin or receipt.
 * Local Checkpoint integers retain that simulator's explicit safe-Number bound.
 * Registry values use exact wire integers. Schema errors are not model refusals. */
import * as C from './checkpoint-simulator-core.mjs';
import * as R from './registry-simulator-core.mjs';
import * as W from './registry-wire.mjs';
import * as E from './registry-economic-core.mjs';
const own=(x,k)=>Object.hasOwn(x,k);
function fields(x,names,path) {
  if(!x||typeof x!=='object'||Array.isArray(x)||Object.keys(x).length!==names.length||names.some(k=>!own(x,k)))throw Error('invalid-system-wire:'+path);
}
const nat=(x,path)=>{if(typeof E.toInternal(x)!=='bigint'||E.toInternal(x)<0n)throw Error('invalid-system-wire:'+path);};
const localNat=(x,path)=>{if(!C.isNat(x))throw Error('unsupported-checkpoint-integer:'+path);};
const require=(ok,reason)=>{if(!ok)throw new E.ModelRefusal(reason);};
function certificate(c) {
  fields(c,['history','unspent','transaction'],'certificate');
  if(!Array.isArray(c.history))throw Error('invalid-system-wire:history');
  c.history.forEach(W.validateAction);W.validateUtxo(c.unspent);W.validateEconomicTransaction(c.transaction);
}
export function validateCommand(command) {
  if(!command||typeof command!=='object'||Array.isArray(command)||Object.keys(command).length!==1)throw Error('invalid-system-wire:command');
  const kind=Object.keys(command)[0],a=command[kind];
  const keys={register:['aid','now','refund','pool','context','certificate','booking','index'],local:['aid','now','action'],book:['aid','booker','fee','history','booking'],complete:['aid','certificate']};
  if(!own(keys,kind))throw Error('invalid-system-wire:command-kind');fields(a,keys[kind],kind);nat(a.aid,'aid');
  if(kind==='register') {
    ['now','refund','pool'].forEach(k=>localNat(a[k],k));localNat(a.index,'index');
    fields(a.context,['parameters','environment','configuration'],'context');
    W.validateParams(a.context.parameters);W.validateEnv(a.context.environment);W.validateConfig(a.context.configuration);
    certificate(a.certificate);W.validateRegistrationBooking(a.booking);
  } else if(kind==='local') {
    localNat(a.now,'now');const action=C.normalizeAction(a.action);if(!action.ok)throw Error('invalid-system-wire:local-action:'+action.reason);
  } else if(kind==='book') {
    nat(a.booker,'booker');nat(a.fee,'fee');W.validateTerminationBooking(a.booking);
    if(!Array.isArray(a.history))throw Error('invalid-system-wire:history');a.history.forEach(W.validateAction);
  } else certificate(a.certificate);
  return command;
}
const contextOf=origin=>({parameters:origin.parameters,environment:origin.environment,configuration:origin.configuration});
function registryStep(context,state,action) {
  const r=R.stepFn(context.parameters,context.environment,action,state);
  if(r.error)throw new E.ModelRefusal(r.error);
  return r.ok;
}
function registryReplay(context,start,history) {
  return history.reduce((state,action)=>registryStep(context,state,action).state,start);
}
function replayFold(context,start,c) {
  const before=registryReplay(context,start,c.history);
  const result=registryStep(context,before,{fold:{expectedGen:before.gen,expectedPlugin:before.config.applicationPolicy,unspent:c.unspent,transaction:c.transaction}});
  return {before,...result,transaction:c.transaction};
}
function localStep(p,env,action,now,state) {
  const result=C.step(p,env,action,now,state);
  if(!result.ok&&['invalid-nat','invalid-params','invalid-state','invalid-action','invalid-evidence'].includes(result.reason))throw Error('unsupported-checkpoint-input:'+result.reason+':'+result.field);
  require(result.ok,'checkpoint-local-refused');return result;
}
const pendingAt=(state,ref)=>state.terminations.find(e=>E.equal(e.booking.request.reference,ref))??null;
const contains=(inputs,ref)=>inputs.some(i=>E.equal(i.ref,ref));
function transition(p,env,state,command) {
  validateCommand(command);
  const kind=Object.keys(command)[0],a=command[kind];
  const row=state.aids.find(x=>E.equal(x.aid,a.aid))??{aid:a.aid,leaf:'absent',state:'absent',origin:null,pending:null};
  let next=row,checkpointFlow=null,registryFlow=null;
  if(kind==='register') {
    require(row.leaf==='absent','checkpoint-registration-leaf');require(row.origin===null,'checkpoint-origin-already-bound');
    const local=localStep(p,env,{register:{refund:a.refund,pool0:a.pool}},a.now,row.state);
    const receipt=replayFold(a.context,R.init(a.context.configuration),a.certificate);
    const binding=receipt.state.bindings.find(([aid])=>E.equal(aid,a.aid));require(!!binding,'checkpoint-registration-alias-missing');
    const output=receipt.transaction.outputs[a.index];require(!!output,'checkpoint-registration-output-missing');
    const before=E.toInternal(receipt.before),tx=E.toInternal(receipt.transaction);
    const world={registry:{config:before.config,trie:before.trie,held:before.carriers.map(c=>c.original)},pending:before.registrations,terminations:before.terminations.map(e=>e.booking),treasury:before.treasury};
    const selected=E.foldMembers(world,tx).some(m=>m.kind==='registration'&&E.equal(m.booking,a.booking));
    require(selected&&E.equal(a.booking.request.key,a.aid)&&E.equal(output.singularTags,[E.singularTag(E.toInternal(receipt.before.config),E.toInternal(a.aid))])&&E.equal(output.output.address,a.booking.request.destination)&&E.equal(output.output.datumValue,a.booking.request.datum)&&E.equal(output.output.lovelace,a.booking.request.carrierAda),'checkpoint-registration-delivery-mismatch');
    const origin={...a.context,registered:receipt.state,token:binding[1],registrationRef:a.booking.request.reference,carrierRef:{tx:receipt.transaction.identity,index:a.index}};
    next={aid:a.aid,leaf:C.leafOf(local.state),state:local.state,origin,pending:null};checkpointFlow=local.flow;registryFlow=receipt.flow;
  } else if(kind==='local') {
    require(C.actionKind(a.action)!=='register','checkpoint-registration-receipt-required');
    const local=localStep(p,env,a.action,a.now,row.state);
    next={...row,state:local.state,leaf:C.leafOf(local.state)};checkpointFlow=local.flow;
  } else if(kind==='book') {
    require(C.stateKind(row.state)==='terminationPending','checkpoint-not-pending');
    require(row.origin!==null,'checkpoint-origin-missing');require(row.pending===null,'checkpoint-already-associated');
    const context=contextOf(row.origin),before=registryReplay(context,row.origin.registered,a.history);
    const result=registryStep(context,before,{bookTermination:{aid:a.aid,booker:a.booker,fee:a.fee,booking:a.booking}});
    const entry=pendingAt(result.state,a.booking.request.reference);require(entry!==null,'checkpoint-booking-entry-missing');
    require(E.equal(entry.booking,a.booking)&&E.equal(entry.payload.aid,a.aid)&&E.equal(entry.payload.token,row.origin.token),'checkpoint-booking-binding');
    next={...row,pending:{origin:row.origin,keyState:row.state.terminationPending.h,reference:a.booking.request.reference,entry,booked:result.state}};registryFlow=result.flow;
  } else {
    const association=row.pending;require(association!==null,'checkpoint-association-missing');
    const receipt=replayFold(contextOf(association.origin),association.booked,a.certificate);
    const entry=pendingAt(receipt.before,association.reference);
    require(E.equal(row.state,{terminationPending:{h:association.keyState}})&&E.equal(receipt.before.config,{...association.origin.registered.config,root:receipt.before.config.root})&&E.equal(entry,association.entry)&&entry!==null&&E.equal(entry.payload.aid,a.aid)&&E.equal(entry.payload.token,association.origin.token)&&contains(receipt.transaction.transaction.inputs,association.reference),'checkpoint-receipt-mismatch');
    next={...row,leaf:'retired',state:'convicted',pending:null};registryFlow=receipt.flow;
  }
  const aids=state.aids.some(x=>E.equal(x.aid,a.aid))?state.aids.map(x=>E.equal(x.aid,a.aid)?next:x):[...state.aids,next];
  return {ok:{state:{aids},checkpointFlow,registryFlow}};
}
const sessions=new WeakSet();
function freeze(value) {if(value&&typeof value==='object'&&!Object.isFrozen(value)){Object.values(value).forEach(freeze);Object.freeze(value);}return value;}
function session(value) {const copy=freeze(structuredClone(value));sessions.add(copy);return copy;}
export function newSystem(params,env) {
  fields(params,['D','B','P','W'],'params');fields(env,['rotationTo','intentAuthorized','quorum','duplicityAt'],'env');
  if(C.validateParams(params)||C.validateEnv(env))throw Error('invalid-system-wire:checkpoint-context');
  return session({params,env,state:{aids:[]},records:[]});
}
export function attemptSystem(current,command) {
  if(!sessions.has(current))throw Error('system-session-must-start-at-init');
  let result;
  try{result=transition(current.params,current.env,current.state,command);}catch(error){if(!(error instanceof E.ModelRefusal))throw error;result={error:error.message};}
  const record={input:current.state,command,result};
  return {record,session:session({...current,state:result.ok?.state??current.state,records:[...current.records,record]})};
}
export function replaySystem(params,env,commands) {return commands.reduce((s,c)=>attemptSystem(s,c).session,newSystem(params,env));}
export function checkSystemCorpus(corpus) {
  if(corpus.schema!=='cardano-keri.checkpoint.system'||corpus.version!==1||corpus.traces.length!==4)throw Error('system-corpus-schema/roster');
  let cells=0,accepted=0,refused=0;
  for(const trace of corpus.traces) {
    if(!trace.cells.length)throw Error('empty-system-trace');
    let current=newSystem(trace.cells[0].params,trace.cells[0].env);
    if(!E.equal(current.state,trace.initial))throw Error('system-initial-mismatch');
    for(const cell of trace.cells) {
      if(!E.equal(current.state,cell.input)||!E.equal(current.params,cell.params)||!E.equal(current.env,cell.env))throw Error('system-disconnected:'+cell.name);
      const got=attemptSystem(current,cell.command);
      if(!E.equal(got.record.result,cell.result))throw Error('system-result-mismatch:'+cell.name+' '+E.canonical(got.record.result));
      current=got.session;cells++;cell.result.ok?accepted++:refused++;
    }
    if(!E.equal(current.state,trace.final))throw Error('system-final-mismatch');
  }
  return {cells,accepted,refused};
}
