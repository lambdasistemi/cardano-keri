// Execute the same reachable writer and rival against an original Lean definition
// and a one-site mutation. Each #guard requires the two named Boolean outcomes.
// Extraction checks make source drift and compilation failure distinct from a kill.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
const root = resolve(import.meta.dirname, '..');
const output = process.argv[2] || mkdtempSync(join(tmpdir(), 'rival-validity-'));
const read = file => readFileSync(join(root, file), 'utf8');
let source = read('CheckpointRivalValidityControls.lean') + `
namespace MutationChecks
open CardanoKeri Checkpoint CheckpointConviction Duplicity Checkpoint.Examples Checkpoint.RivalControls
def changed := signed {first.event with cuts := [10], adds := [12]} [1] [12]
def staleReceipts := signed changed.event [1] [10]
def shortReceipts := signed changed.event [1] []
def uncommitted := signed {first.event with keys := [3]} [3] [10]
def otherAid := signed {first.event with aid := 12} [1] [10]
def wrongSn := signed {first.event with sn := 2} [1] [10]
def badKind := signed {first.event with kind := .interaction} [1] [10]
def forged := {seals with signatures := first.signatures}
def augmented := signed {first.event with keys := [1,3], threshold := .count 2} [1,3] [10]
def weighted := signed {first.event with keys := [1,3], threshold := .weighted [[.key ⟨1,2⟩, .key ⟨1,2⟩]]} [1] [10]
def badStructure := {seals with structureVerified := false}
def nestedTip := hg.datum.tip KeyEncoding.symbolic 1
def wrongOutput := {obs with output.index := 1}
def selective := {setup 11 with
  presentedSpend := fun _ _ => some obs
  attestationMinted := fun claim => decide (claim = wrongOutput)}
`;
const ids = [];
function decl(file, name) {
  const all = read('CardanoKeri/'+file+'.lean');
  const start = all.indexOf('def '+name+' ');
  assert(start >= 0, name);
  return all.slice(start, all.indexOf('\n\n',start)).replace('def '+name+' ', 'def mutated ');
}
function check(id, file, name, old, replacement, expression, expected) {
  let body = decl(file, name);
  assert.equal(body.split(old).length, 2, id+' must have one mutation site');
  assert(!ids.includes(id));
  ids.push(id);
  const original=expression.replaceAll('SUBJECT',name);
  const changed=expression.replaceAll('SUBJECT','mutated');
  source += `\nnamespace ${id}\n${body.replace(old,replacement)}\ndef honest := ${original}\ndef fault := ${changed}\n#guard honest == ${expected} && fault == ${!expected}\n#eval IO.println s!"${id} baseline={honest} mutant={fault}"\nend ${id}\n`;
}
const predicate=(id,old,next,expr,expected)=>check(id,'CheckpointConviction','accepts',old,next,expr,expected);
predicate('NoPredecessor','none => false','none => true','SUBJECT incClaim.comparison.tip incRival',false);
predicate('WrongEpoch','tip.epoch != 0','true','SUBJECT {tip with epoch := 0} alternative',false);
predicate('WrongTipAid','tip.aid == rival.event.aid','true','SUBJECT {tip with aid := 12} alternative',false);
predicate('WrongPosition','tip.sn == rival.event.sn','true','SUBJECT tip wrongSn',false);
predicate('Identical','decide (tip.writer ≠ rival.event)','true','SUBJECT tip first',false);
predicate('Seals','decide (tip.writer ≠ rival.event)','decide (tip.writer.nextKeys ≠ rival.event.nextKeys)','SUBJECT tip seals',true);
predicate('PartialKeys','Duplicity.rotationValid previous rival','decide (tip.writer.keys = rival.event.keys) && Duplicity.rotationValid previous rival','spendReady alternative && SUBJECT tip alternative',true);
predicate('OwnValidity','Duplicity.rotationValid previous rival','true','spendReady underSigned && SUBJECT tip underSigned',false);
const prior='bookingOrigin.inception.predecessor';
function rotation(id, name, old, next, event, expected) {
  check(id,'Duplicity',name,old,next,`SUBJECT ${prior} ${event}`,expected);
}
rotation('OtherAid','rotationValid','signed.event.aid == prior.aid','true','otherAid',false);
rotation('NotRotation','rotationValid','decide (signed.event.kind = .rotation)','true','badKind',false);
rotation('Structure','rotationValid','signed.structureVerified','true','badStructure',false);
rotation('WrongPriorPosition','rotationValid','prior.sn < signed.event.sn','true','(signed {first.event with sn := 0} [1] [10])',false);
rotation('OwnQuorum','signingValid','signed.event.threshold.satisfied signed.event.keys signers','true','underSigned',false);
rotation('PriorAuthority','signingValid','prior.nextThreshold.satisfied prior.nextKeys (signers.filter exposed.contains)','true','uncommitted',false);
rotation('OwnWitnesses','receiptsValid','derivedWitnesses prior signed.event','prior.witnesses','changed',true);
rotation('RemovedWitness','receiptsValid','derivedWitnesses prior signed.event','prior.witnesses','staleReceipts',false);
rotation('ReceiptQuorum','receiptsValid','signed.event.witnessThreshold <= (witnesses.filter receipts.contains).length','true','shortReceipts',false);
check('SignedContent','Duplicity','verifiedSigners','decide (s.event = event)','true','decide ((SUBJECT forged.event forged.signatures).contains 1)',false);
const data=(id,name,old,next,expr,expected)=>check(id,'CheckpointEventHistory',name,old,next,expr,expected);
data('RegistrationPrior','WriterDatum.inception','witnesses, none','witnesses, some ⟨event.aid, event.sn, false, event.nextKeys, event.nextThreshold, witnesses⟩','(SUBJECT inceptionEvent.event [10]).previous.isNone',true);
data('StalePrior','WriterDatum.advance','some spent.commitments','spent.previous','decide ((SUBJECT h1.datum second.event).previous = some h1.predecessor)',true);
data('OlderInfluence','WriterDatum.advance','some spent.commitments','spent.previous.orElse (fun _ => some spent.commitments)','decide ((SUBJECT h1.datum second.event) = (SUBJECT {h1.datum with previous := none} second.event))',true);
data('WriterUpdate','WriterDatum.advance','⟨event,','⟨spent.writer,','decide ((SUBJECT h1.datum second.event).writer = h2.writer.event)',true);
data('WitnessUpdate','WriterDatum.advance','derivedWitnesses spent.commitments event','spent.witnesses','decide ((SUBJECT h1.datum second.event).commitments = h2.predecessor)',true);
for(const [id,old,next] of [
  ['PriorKeys','datum.writer.nextKeys','datum.writer.keys'],
  ['PriorThreshold','datum.writer.nextThreshold','.count 0'],
  ['PriorWitnesses','datum.witnesses','[]']
])data(id,'WriterDatum.commitments',old,next,'decide (SUBJECT h1.datum = h1.predecessor)',true);
data('OriginAid','inceptionWrites','e.aid == aid','true','SUBJECT 12 inceptionEvent [10]',false);
check('StoredDatum','Checkpoint','updateWriterDatum','old.map (·.advance event.event)','old','decide (SUBJECT (atFirst.writerData 11) (some h2) = atSecond.writerData 11)',true);
data('MatchPrevious','KeyReads.matchesDatum','decide (tip.previous = datum.previous)','true','SUBJECT KeyReads.symbolic 11 1 h1.datum {tip with previous := none}',false);
data('MatchSeals','KeyReads.matchesDatum','decide (tip.writer = event)','true','SUBJECT KeyReads.symbolic 11 1 h1.datum {tip with writer := seals.event}',false);
for(const [id,field] of [['NestedCurrent','curThreshold'],['NestedNext','nextThreshold']]) {
  const old=field==='curThreshold'?'encoding.key, e.threshold':'encoding.commitment,\n      e.nextThreshold';
  const next=old.replace(/e\.(nextThreshold|threshold)$/,'.count 1');
  data(id,'WriterDatum.tip',old,next,'KeyReads.symbolic.matchesDatum 11 1 hg.datum (SUBJECT hg.datum KeyEncoding.symbolic 1)',true);
}
check('MintAtUse','Checkpoint','Env.convictionSpend','.filter env.attestationMinted','','(SUBJECT selective 1 1).isSome',false);
check('PresentedOutput','Checkpoint','Env.convictionSpend','(env.presentedSpend epoch sn)','((env.presentedSpend epoch sn).map (fun o => {o with output.index := 1}))','decide (SUBJECT (env 11) 1 1 = some ⟨⟨105, 0⟩, Fixtures.comparison 11 1 1⟩)',true);
predicate('AugmentedKeys','Duplicity.rotationValid previous rival','decide (rival.event.keys.length = tip.writer.keys.length) && Duplicity.rotationValid previous rival','spendReady augmented && SUBJECT tip augmented',true);
rotation('WeightedQuorum','signingValid','signed.event.threshold.satisfied signed.event.keys signers','true','weighted',false);
check('UnsoundSpend','Checkpoint','stepFn','env.acceptsRival l.epoch l.sn = true','(env.comparison l.epoch l.sn).isSome = true','(SUBJECT p (spendEnv underSigned 11) (.convict 7 (pledge underSigned)) 5 (.present rotatedLive)).isSome',false);
// A bad constructor alone would leave the existential free to choose another
// tip. Restrict the input matcher itself and rule out every possible tip.
data('FlatOnly','KeyReads.matchesDatum','tip.keys.toad == (event.witnessThreshold : Int)',
  'tip.keys.toad == (event.witnessThreshold : Int) && decide (event.threshold ≠ nestedRule)',
  'SUBJECT KeyReads.symbolic 11 1 hg.datum nestedTip',true);
source += `
example (candidate : Tip) :
    FlatOnly.mutated KeyReads.symbolic 11 1 hg.datum candidate = false := by
  simp [FlatOnly.mutated, hg, EventHistory.datum, WriterDatum.advance, grouped, signed]
example : ¬ ∃ t : Tip, (nestedState.writerData 11).any
    (fun d => FlatOnly.mutated KeyReads.symbolic 11 1 d t) = true ∧
    (Comparison.mk t seals).acceptsAt 1 1 = true := by
  rintro ⟨t, matched, _⟩
  change FlatOnly.mutated KeyReads.symbolic 11 1 hg.datum t = true at matched
  simp [FlatOnly.mutated, hg, EventHistory.datum, WriterDatum.advance, grouped, signed] at matched
#guard !duplicityAt 1 1 ⟨1, bookingOrigin.inception.predecessor, first⟩ underSigned
#guard (UnsoundSpend.mutated p (spendEnv underSigned 11) (.convict 7 (pledge underSigned))
  5 (.present rotatedLive)).map Prod.snd == some (.terminationPending rotatedLive.hash)
`;
// Thread the existing one-site no-predecessor mutant through the actual spend
// and edge. The two equivalence checks pin the test harness to the original
// definitions for all environments, sources and successors.
const judgeArg = '(judge : Tip → Rival → Bool)';
const judged = (file, name, replacementName, site, replacement) => {
  const body = decl(file, name);
  assert.equal(body.split(site).length, 2, name + ' judgment site');
  return body.replace('def mutated ', 'def ' + replacementName + ' ' + judgeArg + ' ')
    .replace(site, replacement);
};
source += '\nnamespace InceptionEdge\n';
source += judged('CheckpointConviction', 'Comparison.acceptsAt', 'compareWith',
  'accepts comparison.tip comparison.rival', 'judge comparison.tip comparison.rival') + '\n';
source += judged('Checkpoint', 'Env.acceptsRival', 'acceptsWith',
  'c.acceptsAt epoch sn', 'compareWith judge c epoch sn') + '\n';
source += judged('Checkpoint', 'stepFn', 'stepWith',
  'env.acceptsRival l.epoch l.sn', 'acceptsWith judge env l.epoch l.sn') + '\n';
source += judged('CheckpointSystemHistory', 'ConvictionEdge', 'edgeWith',
  'Step p (env aid) (.convict payee commitment) now (.present live) flow (.terminationPending key)',
  'stepWith judge p (env aid) (.convict payee commitment) now (.present live) = some (flow, .terminationPending key)') + '\n';
source += `
example : stepWith accepts = stepFn := rfl
example (params env aid key before after) :
    edgeWith accepts params env aid key before after ↔ ConvictionEdge params env aid key before after := by
  simp only [edgeWith, ConvictionEdge, show stepWith accepts = stepFn from rfl, T7_step_iff_stepFn]
def payout : Flow := { refund := some {addr := live.refundTo, b := live.bHeld p, pool := live.pool},
                       convictor := some {addr := 7, dreg := p.D} }
#guard (stepWith accepts p (incEnv 11) incAction 5 (.present live)).isNone
#guard stepWith NoPredecessor.mutated p (incEnv 11) incAction 5 (.present live) ==
  some (payout, .terminationPending live.hash)
example : edgeWith NoPredecessor.mutated p incEnv 11 live.hash incOpened incPending :=
  ⟨live, 5, 7, incPledge, payout, rfl, rfl, by decide, ⟨rfl, by decide⟩, rfl⟩
#eval IO.println "InceptionEdge honest=refused mutant=pending target=105#0 commitment=consumed"
end InceptionEdge
`;
source += '\nend MutationChecks\n';
const file=join(resolve(output),'ClauseMutants.lean');
writeFileSync(file,source);
const result=spawnSync(process.env.LAKE_BIN || 'lake',['env','lean',file],{cwd:root,encoding:'utf8'});
process.stdout.write(result.stdout+result.stderr);
if(result.status!==0)throw Error('Lean baseline/mutation check failed; see the named guard');
assert.equal(result.stdout.split('\n').filter(s=>s.includes(' baseline=') && s.includes(' mutant=')).length,ids.length);
console.log(ids.length+' distinct mutations changed their specified observations.');
