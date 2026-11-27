import {readFileSync} from 'node:fs';
const cases=JSON.parse(readFileSync(process.argv[2])).cases;
const rawKey = s => '#"'+Buffer.from('A'+s.slice(1),'base64url').subarray(1).toString('hex')+'"';
console.log('//// Generated from #589 first-seen and rival event bytes.\nuse cardano_keri/checkpoint/rival_evidence.{RivalClaim, open_digest}\nuse cardano_keri/checkpoint/threshold.{Unweighted}\nuse cardano_keri/checkpoint/message.{qb64_aid}');
for (const c of cases.filter(c => ['D09','D10'].includes(c.id))) {
  const first=c.steps.find(s=>s.role==='accepted');
  const decoded=JSON.parse(first.raw);
  for (const step of [first,c.steps.find(s=>s.role==='rival')]) {
    const b=step.raw.startsWith('hex:')?Buffer.from(step.raw.slice(4),'hex'):Buffer.from(step.raw);
    const list=xs=>'['+xs.map(rawKey).join(', ')+']';
    if (decoded.br.length || decoded.ba.length || decoded.bt!=='0') throw Error('unexpected witness fields');
    console.log(`test ${c.id.toLowerCase()}_${step.role}_opens_own_said() {
  let claim = RivalClaim {
    aid: ${rawKey(decoded.i)}, sn: ${parseInt(decoded.s,16)}, prior: "${decoded.p}",
    cur_keys: ${list(decoded.k)}, cur_threshold: Unweighted(${Number(decoded.kt)}),
    next_keys: ${list(decoded.n)}, next_threshold: Unweighted(${Number(decoded.nt)}),
    toad: 0, cuts: [], adds: [],
  }
  when open_digest(claim, #"${b.toString('hex')}") is {
    Some(digest) -> qb64_aid(digest) == "${step.said}"
    None -> False
  }
}`);
  }
}
