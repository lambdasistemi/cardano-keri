/* Observations of the actual associated system corpus. These eight contracts
 * require SysReach or SysStep and therefore are not lamps on a bare local Step
 * session. The caller first verifies connected replay from Sys.init against
 * the Lean certificate producer; arbitrary uploaded states carry no premise. */
import {equal} from './registry-economic-core.mjs';
import {stateKind,leafOf,hasOutput,actionKind} from './checkpoint-simulator-core.mjs';
export const SYSTEM_THEOREMS=['T8_leaf_agrees_with_state','T8_edges_leave_the_leaf','T8_present_implies_registered','T8_leaf_states','T8_utxo_iff_active','T8_leaf_never_absent_again','T8_mint_once','T8_sysstep_partition'];
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
  row('T8_mint_once',accepted&&['register','reopen'].includes(localKind),()=>localKind==='register'?old.leaf==='absent':stateKind(old.state)==='parked'&&old.leaf==='active');
  // The complete oracle result includes both value flows and every stored
  // origin/association field; success was constructed with the actual event.
  row('T8_sysstep_partition',accepted,()=>['register','local','book','complete'].includes(kind)&&equal(result,cell.result));
  return rows;
}
