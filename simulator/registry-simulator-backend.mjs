#!/usr/bin/env node
/*
 * registry-simulator-backend.mjs — session-tree and free-play over the
 * registry core. Importable under plain Node. The @@BACKEND@@ slice is
 * inlined into registry-simulator.html; it uses the inlined core and the
 * embedded SCENARIOS / REGISTRY_LEAN_TRACES_V1 and must not touch the DOM.
 *
 * Stable exports: playStory, playChallenge, offersFor, dryRun, submit,
 * moveSlot, addEvidence, removeEvidence, selectPath, projectJson.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  newSession, addEvidence as sessionAddEvidence, removeEvidence as sessionRemoveEvidence,
  setSlot, attempt, emptyEnv, isNat, step, actionTag, userPostable, inPhase1, rejectable,
  ckTag, statusTag, lookupCkpt, lookupLeaf,
} from './registry-simulator-core.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCENARIOS = readdirSync(join(HERE, 'registry-simulator-scenarios'))
  .filter(f => f.endsWith('.json')).sort()
  .map(f => JSON.parse(readFileSync(join(HERE, 'registry-simulator-scenarios', f), 'utf8')));
const REGISTRY_LEAN_TRACES_V1 = JSON.parse(readFileSync(join(HERE, 'registry-simulator-corpus.json'), 'utf8'));
const addEvidence = sessionAddEvidence;
const removeEvidence = sessionRemoveEvidence;

/* @@BACKEND@@ */
const DEFAULT_PARAMS = { D: 1000, tip: 2, Mc: 4, Mr: 1, process: 10, retract: 10, W: 5, far: 1000000000 };
const DEFAULT_PLUGIN = 7;
const NAMES = { 1: 'Alice', 2: 'Bob', 3: 'Hal', 4: 'Mallory', 5: 'Cora', 6: 'Sam' };
const nameOf = addr => NAMES[addr] || ('address ' + addr);
const CAST = {
  alice: { name: 'Alice', role: 'an owner', addr: 1, aid: 11, blurb: 'She holds the keys of AID 11, current and next. She never touches the registry herself: a request, a fold by anyone, and her checkpoint carries her token.' },
  bob: { name: 'Bob', role: 'an owner', addr: 2, aid: 12, blurb: 'He holds the keys of AID 12. Same as Alice, one AID over.' },
  hal: { name: 'Hal', role: 'a folder', addr: 3, blurb: 'He watches the inbox, builds folds at the current generation, and collects the tip per request. Anyone may fold; he is the one who bothers.' },
  sam: { name: 'Sam', role: 'a reaper', addr: 6, blurb: 'He cleans up: bondless checkpoints after the grace window for their min-ADA, expired requests for the tip. Anyone may; he is the samaritan.' },
  cora: { name: 'Cora', role: 'a convictor', addr: 5, blurb: 'She holds duplicity proofs: two rotations at one key state, both receipted. A live checkpoint she convicts through its own edge; a dormant AID through a request.' },
  mallory: { name: 'Mallory', role: 'a stranger', addr: 4, blurb: 'She has a transaction builder and no scruples: stale folds, plugin swaps, other people’s AIDs, go-requests by hand, other people’s retracts.' },
};
const ACTOR_ORDER = ['alice', 'bob', 'hal', 'sam', 'cora', 'mallory'];
const CHALLENGE_SPECS = {
  register: { title: 'Register Alice’s AID as yours', actor: 'mallory', env: { inception: [11, 12] } },
};
const dataOf = a => { const t = actionTag(a); return t && a && typeof a === 'object' && a[t] && typeof a[t] === 'object' ? a[t] : {}; };
const opWord = op => typeof op === 'string' ? (op === 'goConvicted' ? 'go → convicted' : op) : `go → dormant(${op.goDormant})`;
function describeAction(a) {
  const t = actionTag(a), b = dataOf(a);
  switch (t) {
    case 'contribute': return `request ${opWord(b.op)} for AID ${b.aid} (owner ${nameOf(b.owner)}, submitted at ${b.submittedAt})`;
    case 'fold': return `fold at generation ${b.gen}, plugin ${b.plugin}: ` + (b.batch.length ? b.batch.map(x => `${x.do} #${x.id}`).join(', ') : 'empty batch');
    case 'retract': return `retract request #${b.req}`;
    case 'reap': return `reap the checkpoint of AID ${b.aid}`;
    case 'pause': return `pause the checkpoint of AID ${b.aid} (withdrawing rotation)`;
    case 'resume': return `resume the checkpoint of AID ${b.aid} (depositing rotation)`;
    case 'convictCkpt': return `convict the checkpoint of AID ${b.aid}`;
  }
  return t;
}
function recordWithOk(rec) {
  if (!rec) return rec;
  const result = rec.result;
  const out = { ...rec };
  if (out.ok === undefined) out.ok = !!(result && result.ok);
  if (out.reason === undefined && result && result.reason !== undefined) out.reason = result.reason;
  if (out.field === undefined && result && result.field !== undefined) out.field = result.field;
  return out;
}
function copyTree(tree) {
  return {
    family: tree.family, story: tree.story, challenge: tree.challenge, actor: tree.actor,
    cursor: tree.cursor, punch: tree.punch, trunkLeaf: tree.trunkLeaf,
    nodes: tree.nodes.map(n => ({ ...n, children: n.children.slice(), branch: n.branch ? { ...n.branch } : n.branch })),
  };
}
function originTree(session, say, extra) {
  const node0 = { id: 0, parent: null, children: [], last: null, session, record: null, who: '', say, kind: 'origin', branch: null };
  return { family: 'registry', story: null, challenge: null, actor: 'alice', cursor: 0, punch: null, nodes: [node0], ...extra };
}
function treeAddChild(tree, parentId, entry) {
  const nodes = tree.nodes.map(n => ({ ...n, children: n.children.slice(), branch: n.branch ? { ...n.branch } : n.branch }));
  const parent = nodes[parentId];
  if (!parent) throw new Error('unknown node ' + parentId);
  const id = nodes.length;
  const n = { id, parent: parentId, children: [], last: null, branch: null, ...entry };
  if (n.record) n.record = recordWithOk(n.record);
  nodes.push(n);
  parent.children.push(id);
  parent.last = id;
  return { ...tree, nodes, cursor: id };
}
function sessionAt(tree, nodeId) {
  const id = nodeId === undefined || nodeId === null ? tree.cursor : nodeId;
  const n = tree.nodes[id];
  if (!n || !n.session) throw new Error('unknown node ' + id);
  return n.session;
}
function storyIdOf(sc) { return sc.id !== undefined && sc.id !== null ? sc.id : sc.story; }
function findScenario(storyId) {
  const want = String(storyId);
  return SCENARIOS.find(s => String(storyIdOf(s)) === want) || null;
}
function storyActorId(st) {
  const w = (st.as || '').split(/ — /)[0].trim().toLowerCase();
  return ACTOR_ORDER.find(id => CAST[id].name.toLowerCase() === w) || null;
}
function buildStoryTree(sc) {
  const s0 = newSession(sc.params, isNat(sc.plugin) ? sc.plugin : DEFAULT_PLUGIN, sc.actors || NAMES, sc.env || {}, REGISTRY_LEAN_TRACES_V1);
  let tree = originTree(s0, (sc.narrative || '') + ' Step through the story with › ; ⋔ chips switch branch.',
    { story: storyIdOf(sc), actor: 'alice' });
  const play = (pid, st, extra) => {
    const sess = tree.nodes[pid].session;
    const out = attempt(sess, st.action, st.now);
    const exp = st.expect || { ok: true };
    const rec = recordWithOk(out.record);
    const mismatch = (exp.ok !== false) !== rec.ok || (exp.ok === false && exp.reason && exp.reason !== (rec.result && rec.result.reason));
    tree = treeAddChild(tree, pid, {
      session: out.session, record: rec, who: st.as || st.actor || 'anyone', actorId: storyActorId(st),
      say: describeAction(st.action) + ' at slot ' + st.now + '.' + (st.note ? ' ' + st.note : ''),
      kind: 'story', step: st, expect: exp, mismatch, ...extra,
    });
    return tree.cursor;
  };
  const trunkIds = [0];
  let pid = 0;
  for (const st of sc.steps) {
    if (st.hidden) { trunkIds.push(pid); continue; }
    pid = play(pid, st, {});
    trunkIds.push(pid);
  }
  for (const fk of sc.forks || []) {
    let fid = trunkIds[fk.at];
    if (fk.env) {
      const sess = tree.nodes[fid].session;
      tree = treeAddChild(tree, fid, {
        session: { ...sess, env: { ...emptyEnv(), ...fk.env } }, record: null, who: 'world',
        say: 'Another world: ' + fk.title + '.', kind: 'evidence', evRow: null, world: true,
        branch: { id: fk.id, title: fk.title },
      });
      fid = tree.cursor;
    }
    fk.steps.forEach((st, i) => { fid = play(fid, st, i === 0 && !fk.env ? { branch: { id: fk.id, title: fk.title } } : {}); });
  }
  for (let i = 0; i + 1 < trunkIds.length; i++) if (trunkIds[i] !== trunkIds[i + 1]) tree.nodes[trunkIds[i]].last = trunkIds[i + 1];
  const end = tree.nodes[trunkIds[trunkIds.length - 1]];
  end.trunkEnd = true;
  end.last = null;
  let punch = Number.isInteger(sc.punchline) && trunkIds[sc.punchline + 1] !== undefined ? trunkIds[sc.punchline + 1] : null;
  if (punch === null) for (const id of trunkIds) { const n = tree.nodes[id]; if (n.record && n.record.ok) punch = id; }
  tree.cursor = 0;
  tree.punch = punch;
  tree.trunkLeaf = trunkIds[trunkIds.length - 1];
  tree.storySc = sc;
  return tree;
}
function playLoadedScenario(sc) { return buildStoryTree(sc); }
function playStory(storyId) {
  const sc = findScenario(storyId);
  if (!sc) throw new Error('unknown story ' + storyId);
  return buildStoryTree(sc);
}
function playChallenge(challengeId) {
  const c = CHALLENGE_SPECS[challengeId];
  if (!c) throw new Error('unknown challenge ' + challengeId);
  const sess = newSession(DEFAULT_PARAMS, DEFAULT_PLUGIN, NAMES, c.env, REGISTRY_LEAN_TRACES_V1);
  return originTree(sess, 'An empty registry. ★ ' + c.title + ': every move below is yours to try.',
    { challenge: challengeId, actor: c.actor });
}
function pendingOf(sess, owner) { return sess.state.requests.filter(r => owner === undefined || r.owner === owner).slice().sort((a, b) => a.id - b.id); }
function ckptOf(sess, aid) { return lookupCkpt(sess.state.ckpts, aid); }
function leafKey(sess, aid) { const l = lookupLeaf(sess.state.leaves, aid); return l === null ? 'none' : statusTag(l); }
function kOf(sess, aid) { const c = ckptOf(sess, aid); if (c) return c.k; const l = lookupLeaf(sess.state.leaves, aid); return l && statusTag(l) === 'dormant' ? l.dormant : 0; }
function offersFor(actorId, tree, nodeId) {
  const sess = sessionAt(tree, nodeId);
  const st = sess.state, now = sess.now, gen = st.gen, pl = st.plugin;
  const keri = [], chain = [];
  const ev = (label, row, hint) => keri.push({ label, row, hint });
  const act = (kind, label, action) => chain.push({ kind, label, action });
  const contribute = (aid, owner, op) => ({ contribute: { aid, owner, submittedAt: now, op } });
  const fold = (folder, g, plugin, batch) => ({ fold: { folder, gen: g, plugin, batch } });
  const all = pendingOf(sess);
  const processable = all.filter(r => inPhase1(sess.params, r, now) || !userPostable(r.op));
  const rejectable_ = all.filter(r => rejectable(sess.params, r, now) && userPostable(r.op));
  const owner = (c) => {
    const aid = c.aid, a = c.addr, k = kOf(sess, aid), lk = leafKey(sess, aid), ck = ckptOf(sess, aid);
    ev(`my inception verifies (AID ${aid})`, { inception: [aid] }, 'the plugin verifies the inception over the bytes');
    ev(`kli rotate from key state ${k}: witnesses receipt`, { rotationFrom: [aid, k] }, 'a witnessed rotation from the key state the checkpoint (or the dormant leaf) records');
    ev(`my keys sign at threshold (quorum, AID ${aid})`, { quorum: [aid] }, 'the owner reaps her own parked checkpoint early');
    if (lk === 'none') act('contribute', `post my registration (bond ${sess.params.D} + tip ${sess.params.tip})`, contribute(aid, a, 'register'));
    if (lk === 'dormant') act('contribute', `post my revival (bond ${sess.params.D} + tip)`, contribute(aid, a, 'revive'));
    for (const r of pendingOf(sess, a)) act('retract', `retract my request #${r.id} (${opWord(r.op)})`, { retract: { req: r.id } });
    const mine = all.filter(r => r.owner === a && (inPhase1(sess.params, r, now)));
    if (mine.length) act('fold', 'fold my own request in (I need no folder)', fold(a, gen, pl, mine.map(r => ({ id: r.id, do: 'process' }))));
    if (ck && ckTag(ck.st) === 'live') act('pause', 'pause: my next keys withdraw the bonds', { pause: { aid } });
    if (ck && ckTag(ck.st) === 'parked') act('resume', 'resume: a depositing rotation makes it live again', { resume: { aid } });
    if (ck) act('reap', 'reap my own parked checkpoint (at any time, with my keys)', { reap: { reaper: a, aid } });
  };
  switch (actorId) {
    case 'alice': owner(CAST.alice); break;
    case 'bob': owner(CAST.bob); break;
    case 'hal':
      if (processable.length) act('fold', `fold the inbox at generation ${gen}: process ${processable.length} request${processable.length > 1 ? 's' : ''}`, fold(3, gen, pl, processable.map(r => ({ id: r.id, do: 'process' }))));
      if (rejectable_.length) act('fold', `sweep: reject ${rejectable_.length} expired request${rejectable_.length > 1 ? 's' : ''}`, fold(3, gen, pl, rejectable_.map(r => ({ id: r.id, do: 'reject' }))));
      for (const r of all) act('fold', `fold #${r.id} alone (${opWord(r.op)}, AID ${r.aid})`, fold(3, gen, pl, [{ id: r.id, do: 'process' }]));
      break;
    case 'sam':
      for (const c of st.ckpts.slice().sort((x, y) => x.aid - y.aid)) act('reap', `reap the checkpoint of AID ${c.aid} (${ckTag(c.ckpt.st)})`, { reap: { reaper: 6, aid: c.aid } });
      if (rejectable_.length) act('fold', `sweep the inbox: reject ${rejectable_.length} for the tip`, fold(6, gen, pl, rejectable_.map(r => ({ id: r.id, do: 'reject' }))));
      for (const r of all) act('fold', `reject #${r.id} alone`, fold(6, gen, pl, [{ id: r.id, do: 'reject' }]));
      break;
    case 'cora':
      for (const c of st.ckpts.slice().sort((x, y) => x.aid - y.aid)) { ev(`obtain a duplicity proof against AID ${c.aid} at key state ${c.ckpt.k}`, { duplicity: [c.aid, c.ckpt.k] }, 'two rotations at that key state, both receipted'); act('convictCkpt', `convict the checkpoint of AID ${c.aid} (${ckTag(c.ckpt.st)})`, { convictCkpt: { aid: c.aid } }); }
      for (const l of st.leaves.filter(l => statusTag(l.status) === 'dormant')) { ev(`obtain a duplicity proof against AID ${l.aid} at key state ${l.status.dormant}`, { duplicity: [l.aid, l.status.dormant] }, 'against the key state the dormant leaf records'); act('contribute', `post a conviction request for dormant AID ${l.aid}`, contribute(l.aid, 5, 'convict')); }
      break;
    case 'mallory':
      act('contribute', 'register Alice’s AID myself (owner Mallory)', contribute(11, 4, 'register'));
      act('contribute', 'post a go-request by hand', contribute(11, 4, 'goConvicted'));
      if (all.length) act('fold', `fold at generation ${gen > 0 ? gen - 1 : gen + 1} (stale)`, fold(4, gen > 0 ? gen - 1 : gen + 1, pl, all.slice(0, 1).map(r => ({ id: r.id, do: 'process' }))));
      if (all.length) act('fold', 'fold with plugin 8, a script I control', fold(4, gen, 8, all.slice(0, 1).map(r => ({ id: r.id, do: 'process' }))));
      act('fold', 'an empty fold, to churn the generation', fold(4, gen, pl, []));
      for (const r of all.filter(r => r.owner !== 4)) act('retract', `retract ${nameOf(r.owner)}’s request #${r.id}`, { retract: { req: r.id } });
      for (const r of all.filter(r => !userPostable(r.op))) act('fold', `reject the go-request #${r.id} inside a batch`, fold(4, gen, pl, [{ id: r.id, do: 'reject' }]));
      for (const c of st.ckpts.slice().sort((x, y) => x.aid - y.aid)) act('reap', `reap the checkpoint of AID ${c.aid} as a stranger`, { reap: { reaper: 4, aid: c.aid } });
      break;
  }
  return { keri, chain };
}
function refusalWhy(r) {
  return `${r.reason}${r.field ? ' (' + r.field + ')' : ''}${r.at !== undefined ? ' at batch entry ' + r.at : ''}`;
}
function dryRun(tree, action, nodeId) {
  const sess = sessionAt(tree, nodeId);
  const r = step(sess.params, sess.env, action, sess.now, sess.state);
  return r.ok ? { ok: true, res: r } : { ok: false, res: r, why: 'refused now — ' + refusalWhy(r) };
}
function opResult(tree, ok, extra) {
  return { tree, ok, cursor: tree.cursor, ...extra };
}
function submit(tree, actorId, action, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  t.cursor = at;
  const sess = t.nodes[at].session;
  const out = attempt(sess, action, sess.now);
  const rec = recordWithOk(out.record);
  const who = (CAST[actorId] && CAST[actorId].name) || actorId;
  const next = treeAddChild(t, at, {
    session: out.session, record: rec, who, actorId,
    say: describeAction(action) + ' at slot ' + sess.now + '.', kind: 'free',
  });
  next.actor = actorId || t.actor;
  return opResult(next, !!rec.ok, { record: rec, node: next.nodes[next.cursor] });
}
function moveSlot(tree, targetSlot, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  const sess = t.nodes[at].session;
  const mv = setSlot(sess, targetSlot);
  if (!mv.ok) return opResult(t, false, { reason: mv.reason });
  if (targetSlot === sess.now) return opResult(t, true);
  const next = treeAddChild(t, at, { session: mv.session, record: null, who: 'Time', say: `Slot ${targetSlot}.`, kind: 'time' });
  return opResult(next, true);
}
function treeAddEvidence(tree, evidenceRow, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  const sess = t.nodes[at].session;
  let nextSess;
  try { nextSess = addEvidence(sess, evidenceRow); }
  catch (e) { return opResult(t, false, { reason: 'invalid-evidence' }); }
  const next = treeAddChild(t, at, {
    session: nextSess, record: null, who: 'You',
    say: (nextSess === sess ? 'Evidence added: ' : 'Evidence added: ') + JSON.stringify(evidenceRow) + '.',
    kind: 'evidence', evRow: evidenceRow,
  });
  return opResult(next, true);
}
function treeRemoveEvidence(tree, evidenceRow, nodeId) {
  const t = copyTree(tree);
  const at = nodeId === undefined || nodeId === null ? t.cursor : nodeId;
  if (!t.nodes[at]) throw new Error('unknown node ' + at);
  const sess = t.nodes[at].session;
  let nextSess;
  try { nextSess = removeEvidence(sess, evidenceRow); }
  catch (e) { return opResult(t, false, { reason: 'invalid-evidence' }); }
  const next = treeAddChild(t, at, {
    session: nextSess, record: null, who: 'You',
    say: 'Evidence removed: ' + JSON.stringify(evidenceRow) + '.', kind: 'evidence', evRow: evidenceRow, removed: true,
  });
  return opResult(next, true);
}
function selectPath(tree, forkId, toEnd) {
  const t = copyTree(tree);
  if (forkId !== undefined && forkId !== null && forkId !== '') {
    const start = t.nodes.find(n => n.branch && String(n.branch.id) === String(forkId));
    if (!start) throw new Error('unknown fork ' + forkId);
    let id = start.id;
    if (toEnd) {
      while (t.nodes[id].children.length) {
        const n = t.nodes[id];
        const nx = n.last !== null ? n.last : n.children[0];
        n.last = nx;
        id = nx;
      }
    }
    for (let n = id; t.nodes[n].parent !== null; n = t.nodes[n].parent) t.nodes[t.nodes[n].parent].last = n;
    t.cursor = id;
    return t;
  }
  let id = 0;
  if (toEnd) {
    if (t.trunkLeaf !== undefined && t.trunkLeaf !== null) id = t.trunkLeaf;
    else {
      for (;;) {
        const n = t.nodes[id];
        if (!n.children.length || n.trunkEnd) break;
        const nx = n.last !== null ? n.last : n.children[0];
        if (nx === null || nx === undefined) break;
        id = nx;
      }
    }
  }
  t.cursor = id;
  return t;
}
function selectedFork(tree) {
  for (let id = tree.cursor; id !== null && tree.nodes[id]; id = tree.nodes[id].parent) {
    if (tree.nodes[id].branch && tree.nodes[id].branch.id) return tree.nodes[id].branch.id;
  }
  return null;
}
function branchAt(tree, id) {
  for (let n = id; n !== null && tree.nodes[n]; n = tree.nodes[n].parent) {
    if (tree.nodes[n].branch) return tree.nodes[n].branch;
  }
  return null;
}
function compactLamps(rec) {
  if (!rec || !rec.theorems) return null;
  const out = {};
  for (const id of Object.keys(rec.theorems)) {
    const x = rec.theorems[id];
    if (x && (x.v === 'holds' || x.v === 'fails')) out[id] = { exhibited: true, holds: x.v === 'holds' };
  }
  return Object.keys(out).length ? out : null;
}
function projectJson(tree) {
  const t = copyTree(tree);
  const ids = [];
  for (let n = t.cursor; n !== null && t.nodes[n]; n = t.nodes[n].parent) ids.unshift(n);
  const path = ids.map(id => {
    const n = t.nodes[id], rec = n.record, sess = n.session;
    const result = rec && rec.result;
    return {
      id: n.id, parent: n.parent, kind: n.kind, branch: branchAt(t, n.id), slot: sess ? sess.now : null,
      who: n.who, say: n.say, action: rec ? rec.action : undefined, ok: rec ? rec.ok : null,
      reason: result && result.reason ? result.reason : undefined,
      flow: result && result.flow, state: sess ? sess.state : null, verdict: null,
      lamps: compactLamps(rec),
    };
  });
  return {
    family: t.family, story: t.story, challenge: t.challenge, fork: selectedFork(t),
    cursor: t.cursor, path,
  };
}
/* @@BACKEND:END@@ */

export {
  playStory, playChallenge, offersFor, dryRun, submit, moveSlot,
  treeAddEvidence as addEvidence, treeRemoveEvidence as removeEvidence,
  selectPath, projectJson, playLoadedScenario,
};
