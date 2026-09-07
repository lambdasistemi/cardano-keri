const fs = require('fs'), cp = require('child_process'), path = require('path'), crypto = require('crypto');
const evidence = __dirname, root = path.resolve(evidence, '../../..');
const digest = path.basename(evidence);
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const git = (...a) => cp.execFileSync('git', a, {cwd: root}).toString();
const requireThat = (ok, why) => { if (!ok) throw Error(why); };
const sections = ['Mode and frozen inputs','Decision coverage','Inversion coverage','Theorem outcomes','Mutation adequacy','Correspondence','Honest limits'];
function reportCheck(report) {
  requireThat((report.match(/^Terminal verdict: /gm)||[]).length === 1, 'verdict singularity');
  requireThat(report.includes('Terminal verdict: AUDIT-FINDINGS\n'), 'findings must not be promoted to pass');
  requireThat(JSON.stringify([...report.matchAll(/^## (.+)$/gm)].map(x=>x[1])) === JSON.stringify(sections), 'seven report sections');
  requireThat(report.includes(digest), 'report input digest');
}
function axiomCheck(log, names) {
  const records = [...log.matchAll(/^'([^']+)' (does not depend on any axioms|depends on axioms: \[([^\]]*)\])/gm)];
  requireThat(names.length > 0 && new Set(names).size === names.length, 'nonempty unique inventory');
  requireThat(JSON.stringify(records.map(m=>m[1]).sort()) === JSON.stringify([...names].sort()), 'exact axiom receipt names');
  for (const row of records) for (const a of (row[3]||'').split(',').map(x=>x.trim()).filter(Boolean)) requireThat(['propext','Quot.sound'].includes(a), 'unapproved axiom');
}
function inputCheck(actual, expected) { requireThat(actual === expected, 'input bytes differ'); }
const report = fs.readFileSync(root+'/lean/AUDIT-REPORT.md','utf8');
const names = fs.readFileSync(evidence+'/theorem-names.txt','utf8').trim().split('\n');
const axioms = fs.readFileSync(evidence+'/axioms.log','utf8');
if (process.argv.includes('--self-test')) {
  let rejected = 0;
  for (const [label, f] of [
    ['duplicate verdict',()=>reportCheck(report+'\nTerminal verdict: AUDIT-FINDINGS\n')],
    ['pass promotion',()=>reportCheck(report.replace('Terminal verdict: AUDIT-FINDINGS','Terminal verdict: AUDIT-PASS'))],
    ['missing section',()=>reportCheck(report.replace('## Honest limits','Honest limits'))],
    ['wrong report digest',()=>reportCheck(report.replaceAll(digest,'0'.repeat(64)))],
    ['changed input',()=>inputCheck('changed','frozen')],
    ['empty theorem inventory',()=>axiomCheck('',[])],
    ['truncated axiom receipt',()=>axiomCheck('',names)],
    ['escape axiom',()=>axiomCheck("'Control' depends on axioms: [sorryAx]\n",['Control'])]
  ]) { let failed=false; try { f(); } catch { failed=true; } requireThat(failed,'control survived: '+label); console.log('REJECTED '+label); rejected++; }
  reportCheck(report); axiomCheck(axioms,names); console.log(`mechanical controls ${rejected}/${rejected}; positive report/axiom cases pass; no semantic mutant claim`); process.exit(0);
}
reportCheck(report); axiomCheck(axioms,names);
const frozen = fs.readFileSync(evidence+'/inputs.git-manifest','utf8');
requireThat(sha(frozen) === digest, 'manifest directory identity');
const actual = git('ls-tree','-r','HEAD','--','lean/').split('\n').filter(l=>l && !l.endsWith('\tlean/AUDIT-REPORT.md') && !l.includes('\tlean/audit-evidence/')).join('\n')+'\n';
inputCheck(actual, frozen);
for (const line of frozen.trim().split('\n')) {
  const [meta,p] = line.split('\t'); const [mode,,blob] = meta.split(' ');
  const bytes=fs.readFileSync(root+'/'+p);
  const actualBlob=crypto.createHash('sha1').update(Buffer.from('blob '+bytes.length+'\0')).update(bytes).digest('hex');
  requireThat(actualBlob===blob,'working input drift '+p);
  requireThat(((fs.statSync(root+'/'+p).mode & 0o111)!==0)===(mode==='100755'),'mode drift '+p);
}
git('merge-base','--is-ancestor','a67e3ed16d4f406fa99dd8b746a65e0c2c0b8359','HEAD');
const owned = p => p==='lean/AUDIT-REPORT.md' || p.startsWith('lean/audit-evidence/'+digest+'/') || /^specs\/368-lean-audit-report\/(spec|plan|tasks|data-model|functions-model|modules-model)\.md$/.test(p);
for(const p of git('diff','--name-only','a67e3ed16d4f406fa99dd8b746a65e0c2c0b8359').trim().split('\n').filter(Boolean)) requireThat(owned(p),'forbidden delta '+p);
for(const p of git('ls-files','--others','--exclude-standard').trim().split('\n').filter(Boolean)) requireThat(owned(p),'unexpected untracked '+p);
for(const name of ['build','inventory','axioms','traceability']) requireThat(fs.readFileSync(evidence+'/'+name+'.exit','utf8').trim()==='0',name+' exit');
for(const name of ['Lifecycle','Goals','Invariants']) {
  requireThat(fs.readFileSync(evidence+'/retired-'+name+'.exit','utf8').trim()==='1','retired exit');
  requireThat(fs.readFileSync(evidence+'/retired-'+name+'.log','utf8').includes('CardanoKeri/'+name+'.olean'),'retired module diagnostic');
}
for(const line of fs.readFileSync(evidence+'/MANIFEST.sha256','utf8').trim().split('\n')) {
  const [h,p]=line.split('  '); requireThat(sha(fs.readFileSync(evidence+'/'+p))===h,'evidence hash '+p);
}
git('diff','--check');
console.log('REPORT-GATE PASS: frozen inputs unchanged; one findings verdict; seven sections; 749 axiom receipts; evidence hashes; allowed scope. This is not AUDIT-PASS.');
