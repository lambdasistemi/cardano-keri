/* Reason-level coverage of the compiled Registry dependency surface.
 * A witness observes a complete stepFn result, not every duplicate source site
 * spelling that reason. Construction exclusions are separately proof-bound. */
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ROOT,sha256} from './registry-corpus.mjs';
import {corpusCells} from './registry-properties.mjs';
const PREFIX='CardanoKeri.Registry.';
const exclusions={
  'keri-registration-reconstruction-mismatch': ['registration_reconstruction', 'Imported registration prepends the same whole booking to the projected pool.'],
  'keri-termination-metadata-missing': ['selected_member_available', 'Selected members come from the same pending lookup; installMember_exists supplies the successful installer.'],
  'keri-termination-metadata-mismatch': ['selected_member_available', 'Selection and metadata lookup return the same whole booking, even without a Reach premise.'],
  'keri-registration-metadata-missing': ['selected_member_available', 'Selected registration members belong to the same registration pool.'],
  'keri-recovery-reconstruction-mismatch': ['recovery_reconstruction', 'Both imported recovery effects filter only registrations; filtering the original pool by membership in that result is exact.'],
  'edge-inadmissible': ['projected_request_admitted', 'foldLegacyRequest constructs only insertActive or updateTerminal.'],
  'no-approval': ['projected_request_admitted', 'The structural adapter supplies the exact configuration policy and approval tuple. Economic authorization remains separately checked.'],
  'approval-mismatch': ['projected_request_admitted', 'The constructed structural approval admitsFor the same configuration and request.'],
  'net-mint-mismatch': ['projected_batch_claim', 'The synthetic structural claims equal their aggregate edge deltas. Actual economic transaction mint is separately observed and checked.'],
};
export function guardCoverage(surface,corpus) {
  const cells=corpusCells(corpus), reasons=[...new Set(surface.decisions.map(d=>d.reason))].sort();
  const factsPath='lean/CardanoKeri/RegistryAdapterFacts.lean';
  const facts=readFileSync(join(ROOT,factsPath),'utf8');
  const rows=reasons.map(reason=>{
    const sites=surface.decisions.filter(d=>d.reason===reason);
    const witnesses=cells.flatMap((cell,index)=>cell.result?.error===reason ? [{index,name:cell.name??null,sha256:sha256(JSON.stringify(cell))}] : []);
    if(witnesses.length)return {reason,sites,evidence:'complete-result-witness',witnesses};
    const exclusion=exclusions[reason];assert(exclusion,'uncovered refusal reason '+reason);
    assert(facts.includes('theorem '+exclusion[0]+' '),'missing exclusion theorem');
    return {reason,sites,evidence:'construction-proof',declaration:PREFIX+exclusion[0],explanation:exclusion[1]};
  });
  return {version:1,extent:'Distinct refusal reasons, with every source occurrence inventoried. A result witness is not per-site branch coverage. Exclusions concern construction by this adapter, not arbitrary direct calls to imported helpers.',
    facts:{path:factsPath,sha256:sha256(facts)},surfaceSha256:sha256(JSON.stringify(surface)),corpusSha256:sha256(JSON.stringify(corpus)),rows};
}
export function checkGuardCoverage(surface,corpus,committed) {
  assert.deepEqual(committed,guardCoverage(surface,corpus),'refusal coverage/source/corpus drift');
  return {refusalReasons:committed.rows.length,witnessedReasons:committed.rows.filter(r=>r.evidence==='complete-result-witness').length,constructionExclusions:committed.rows.filter(r=>r.evidence==='construction-proof').length};
}
