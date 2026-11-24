/* Observations of the actual associated system corpus. These contracts
 * require SysReach or SysStep and therefore are not lamps on a bare local Step
 * session. The caller first verifies connected replay from Sys.init against
 * the Lean certificate producer; arbitrary uploaded states carry no premise. */
import {evidenceFor} from './checkpoint-system-core.mjs';
import {equal} from './registry-economic-core.mjs';
import {stateKind,leafOf,hasOutput,actionKind,entitles} from './checkpoint-simulator-core.mjs';
export const SYSTEM_THEOREMS=['T8_leaf_agrees_with_state','T8_edges_leave_the_leaf','T8_present_implies_registered','T8_leaf_states','T8_utxo_iff_active','T8_leaf_never_absent_again','T8_mint_once','T8_sysstep_partition','sys_conviction_consumes_commitment','commitment_closes_in_or_after_window',
  'registration_installs_booked_facts','local_event_uses_own_authorization','sys_step_keeps_deployment','sys_commitment_survives_key_state_step','sys_conviction_refused_for_other_deployment'];
const rowAt=(state,aid)=>state.aids.find(r=>equal(r.aid,aid))??{aid,state:'absent',leaf:'absent',origin:null,pending:null};
export function systemProperties(cell,result=cell.result) {
  const kind=Object.keys(cell.command)[0],command=cell.command[kind],before=cell.input;
  const after=result.ok?.state??before,old=rowAt(before,command.aid),next=rowAt(after,command.aid),accepted=!!result.ok;
  const rows={};
  const row=(name,premise,claim)=>{rows[name]={exhibited:premise,holds:!premise||claim(),by:[name],notes:[]};if(!rows[name].holds)rows[name].notes.push('sampled system conclusion differs');};
  row('T8_leaf_agrees_with_state',true,()=>after.aids.every(r=>r.leaf===leafOf(r.state)));
  const localKind=kind==='register'?'register':kind==='local'?actionKind(command.action):null;
  row('T8_edges_leave_the_leaf',accepted&&localKind!==null,()=>equal(before.aids.map(r=>[r.aid,r.leaf]),after.aids.map(r=>[r.aid,r.leaf]))===(localKind!=='register'));
  row('T8_present_implies_registered',after.aids.some(r=>r.state!=='absent'),()=>after.aids.every(r=>r.state==='absent'||r.leaf!=='absent'));
  row('T8_leaf_states',true,()=>after.aids.every(r=>(r.leaf==='active')===hasOutput(r.state)&&(r.leaf!=='retired'||r.state==='convicted')));
  row('T8_utxo_iff_active',true,()=>after.aids.every(r=>hasOutput(r.state)===(r.leaf==='active')));
  row('T8_leaf_never_absent_again',accepted&&before.aids.some(r=>r.leaf!=='absent'),()=>before.aids.every(r=>{const n=rowAt(after,r.aid);return(r.leaf==='absent'||n.leaf!=='absent')&&(r.leaf!=='retired'||n.leaf==='retired');}));
  row('registration_installs_booked_facts', accepted && kind === 'register', () => {
    const live = next.state.present?.l;
    const booking = command.booking.request;
    const registry = command.context.parameters;
    return !!live && equal(next.origin.registrationRef, booking.reference) && equal(booking.key, command.aid) &&
      equal(live.bornAt, booking.submittedAt) && equal(live.refundTo, booking.refundAddress) &&
      BigInt(registry.D) === BigInt(cell.params.D) + BigInt(cell.params.B) &&
      BigInt(booking.carrierAda) === BigInt(registry.Mc) + BigInt(registry.D) + BigInt(live.pool);
  });
  row('local_event_uses_own_authorization', accepted && kind === 'local', () => {
    const evidence = evidenceFor(cell.env, command.aid);
    const live = old.state.present?.l;
    if (localKind === 'poison') return !!live && evidence.quorum.some(([e]) => e === live.epoch);
    if (localKind !== 'rotate' && localKind !== 'freeze') return true;
    const action = command.action[localKind];
    return !!live && evidence.rotationTo.some(([e, sn, target]) =>
      e === live.epoch && sn === live.sn && target === action["sn'"]) &&
      (action.op !== 'deposit' || evidence.depositAuthorized.some(([e]) => e === live.epoch + 1));
  });
  row('T8_mint_once',accepted&&localKind==='register',()=>old.leaf==='absent');
  // The complete oracle result includes both value flows and every stored
  // origin/association field; success was constructed with the actual event.
  row('T8_sysstep_partition',accepted,()=>['register','local','book','complete','openCommitment','reveal','sweep'].includes(kind)&&equal(result,cell.result));
  // A live output that becomes a pending termination was convicted on an open
  // commitment naming this AID and this deployment, entitling its payee now; the step burnt it.
  const convicted=accepted&&kind==='local'&&stateKind(old.state)==='present'&&stateKind(next.state)==='terminationPending';
  row('sys_conviction_consumes_commitment',convicted,()=>{
    const c=command.action?.convict?.commitment,payee=command.action?.convict?.payee;
    return !!c&&before.commitments.some(o=>equal(o,c))&&equal(c.aid,command.aid)&&c.deployment===before.deployment&&
      !after.commitments.some(o=>o.marker===c.marker)&&
      entitles(evidenceFor(cell.env,command.aid),c,old.state.present.l,payee,command.now);
  });
  // A commitment that closes closes inside its window (a reveal or the conviction
  // that revealed it) or strictly after it (a sweep), never before it is eligible.
  const closed=accepted?before.commitments.filter(o=>!after.commitments.some(n=>n.marker===o.marker)):[];
  row('commitment_closes_in_or_after_window',closed.length>0,()=>closed.every(o=>o.eligibleAfter<=command.now));
  // Every step keeps the system's deployment.
  row('sys_step_keeps_deployment',accepted,()=>after.deployment===before.deployment);
  // A step that replaces a live output by a different one with the same key state (a
  // top-up, a freeze or a poison) opens and burns no commitment, and every open
  // commitment entitles its payee at the new output exactly when it did at the old.
  const live=s=>stateKind(s)==='present'?s.present.l:null,was=live(old.state),now=live(next.state);
  const kept=accepted&&kind==='local'&&!!was&&!!now&&!equal(was,now)&&was.epoch===now.epoch&&was.sn===now.sn&&before.commitments.length>0;
  row('sys_commitment_survives_key_state_step',kept,()=>equal(after.commitments,before.commitments)&&
    before.commitments.every(o=>[o.eligibleAfter,o.expiresAt,command.now].every(t=>
      entitles(evidenceFor(cell.env,command.aid),o,now,o.payee,t)===entitles(evidenceFor(cell.env,command.aid),o,was,o.payee,t))));
  // A conviction revealing a commitment that names another deployment is refused.
  const revealed=kind==='local'&&actionKind(command.action)==='convict'?command.action.convict.commitment:null;
  row('sys_conviction_refused_for_other_deployment',!!revealed&&revealed.deployment!==before.deployment,()=>!accepted);
  return rows;
}
