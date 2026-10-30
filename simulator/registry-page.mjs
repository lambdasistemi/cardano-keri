const INTEREST = Object.fromEntries(Object.entries(CAST).map(([id, c]) => [id, c.blurb]));
const addNat = (a, b) => E.toWire(E.toInternal(a) + E.toInternal(b));
const evHas = (env, kind, args) => env[kind].some(x => equal(x, kind === 'inception' ? args[0] : args));
const canonicalJson = canonical;
const treeAddEvidence = (tree, row) => ({ tree: editEvidence(tree, row, true) });
const treeRemoveEvidence = (tree, row) => ({ tree: editEvidence(tree, row, false) });
const ORACLE = oracleIndex(REGISTRY_LEAN_TRACES_V3);
const pendingOf = sess => [...sess.state.registrations.map(b => ({ kind: 'registration', booking: b })), ...sess.state.terminations.map(e => ({ kind: 'termination', booking: e.booking }))];
const leafKey = (sess, aid) => sess.state.trie.find(([k]) => equal(k, aid))?.[1]?.known?.s ?? 'unknown';
const ckptOf = (sess, aid) => sess.state.carriers.find(c => equal(c.aid, aid));
const leafWord = leaf => leaf?.known?.s === 'terminal' ? 'retired' : leaf?.known?.s ?? 'absent';
const SVGNS = 'http://www.w3.org/2000/svg';

// tiny DOM helpers: h(tag, attrs, ...children) and its SVG twin
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'dataset') for (const [dk, dv] of Object.entries(v)) el.dataset[dk] = dv;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'hidden' || k === 'disabled' || k === 'selected' || k === 'open' || k === 'checked') { if (v) el.setAttribute(k, ''); el[k] = !!v; }
    else el.setAttribute(k, String(v));
  }
  for (const c of kids.flat()) if (c !== null && c !== undefined && c !== false) el.append(typeof c === 'string' || typeof c === 'number' ? String(c) : c);
  return el;
}
function s(tag, attrs, ...kids) {
  const el = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'dataset') for (const [dk, dv] of Object.entries(v)) el.setAttribute('data-' + dk, dv);
    else el.setAttribute(k, String(v));
  }
  for (const c of kids.flat()) if (c !== null && c !== undefined && c !== false) el.append(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
  return el;
}
const $ = id => document.getElementById(id);
const clear = el => { el.replaceChildren(); return el; };
const fmt = n => String(n);
const raf = cb => (typeof requestAnimationFrame === 'function' ? requestAnimationFrame(cb) : setTimeout(() => cb(Date.now()), 16));
const nowMs = () => (typeof performance !== 'undefined' && performance.now ? performance.now() : Date.now());
const parseNat = str => { const t = String(str).trim(); if (!/^(0|[1-9][0-9]*)$/.test(t)) return null; return E.toWire(BigInt(t)); };


/* ---- the tree of plays --------------------------------------------------------
   A node is a session (immutable) plus the record that produced it. Children
   are branches; `last` remembers the branch last taken, so › follows it. */
const app = { nodes: [], cursor: 0, story: null, actor: 'alice', pending: null, playing: null, fx: [], punch: null, pastPunch: false, challenge: null, unfold: false, wonShown: false };
let toastTimer = null;
function toast(text, ms) {
  const el = $('toast'); if (!el || !text) return;
  el.textContent = text; el.classList.add('on');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('on'), ms || 2600);
}
// the hit, in one line: who got what, and the registry after
function hitLine(n) {
  if (!n.record?.result.ok) return '';
  return describeFlow(n.record.result.ok.flow) + ' · generation ' + n.session.state.gen;
}
function followScene() {
  try {
    const drawer = $('scene-drawer'), sc = $('scene');
    if (!drawer || !drawer.open || !sc.getBoundingClientRect || !sc.scrollIntoView) return;
    const r = sc.getBoundingClientRect();
    if (r.top < 40 || r.bottom > window.innerHeight) sc.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  } catch (e) { /* the minimal DOM has no viewport */ }
}
function renderHud() {
  const hud = $('hud'), w = $('where'); if (!hud || !w) return;
  clear(hud);
  try { for (const c of w.children) hud.append(c.cloneNode(true)); } catch (e) { /* no cloneNode under the minimal DOM */ }
}
const node = id => app.nodes[id];
const cur = () => node(app.cursor).session;
function newTree(session, say) {
  app.nodes = [{ id: 0, parent: null, children: [], last: null, session, record: null, who: '', say, kind: 'origin', branch: null }];
  app.cursor = 0; app.pending = null; stopPlay();
}
function addChild(parentId, entry) {
  const n = { id: app.nodes.length, parent: parentId, children: [], last: null, branch: null, ...entry };
  app.nodes.push(n);
  const p = node(parentId); p.children.push(n.id); p.last = n.id;
  return n.id;
}
function pathTo(id) { const out = []; for (let n = id; n !== null; n = node(n).parent) out.unshift(n); return out; }
function forwardPath(id) { const out = []; let n = node(id); while (n.children.length) { const c = n.last !== null ? n.last : n.children[0]; out.push(c); n = node(c); } return out; }
const currentPath = () => [...pathTo(app.cursor), ...forwardPath(app.cursor)];
const nextOf = id => { const n = node(id); return n.children.length ? (n.last !== null ? n.last : n.children[0]) : null; };
const leafNodeOf = id => { let n = id; for (;;) { const c = nextOf(n); if (c === null) return n; n = c; } };
function goTo(id, opts) {
  opts = opts || {};
  if (id === app.cursor || !node(id)) return;
  const a = pathTo(app.cursor), b = pathTo(id);
  let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
  const up = a.slice(i).reverse(), down = b.slice(i);
  for (const n of down) { const p = node(n).parent; if (p !== null) node(p).last = n; }
  app.cursor = id; app.pending = null; app.unfold = false;
  render();
  const edges = [...up.map(n => ({ node: n, dir: -1 })), ...down.map(n => ({ node: n, dir: 1 }))];
  if (!opts.silent) playEdges(edges);
  if (!up.length && down.length === 1) { const line = hitLine(node(id)); if (line && /\+/.test(line)) toast(line, 2600); }
}
function pushNode(entry) { const id = addChild(app.cursor, entry); goTo(id); }
function currentTree() {
  return { family: 'registry', story: app.story ? app.story.id : null,
    challenge: app.challenge ? Object.keys(CHALLENGES).find(k => CHALLENGES[k] === app.challenge) || null : null,
    nodes: app.nodes, cursor: app.cursor, actor: app.actor, punch: app.punch };
}
function adoptTree(tree, animate) {
  const dest = tree.cursor, from = app.nodes.length ? app.cursor : 0;
  app.nodes = tree.nodes; app.actor = tree.actor || app.actor || 'alice'; app.punch = tree.punch; app.pending = null;
  if (tree.storySc) app.story = tree.storySc;
  if (animate && dest !== from && app.nodes[from]) { app.cursor = from; goTo(dest); }
  else { app.cursor = dest; stopPlay(); }
}

/* ---- words ----------------------------------------------------------------------- */
function describeFlow(f) {
  const bits = [];
  if (f.deposited) bits.push(f.deposited + ' deposited');
  for (const [aid, value] of f.locked) bits.push(value + ' bond locked for AID ' + aid);
  if (f.bondReturn) bits.push(f.bondReturn[1] + ' → ' + nameOf(f.bondReturn[0]));
  if (f.premium) bits.push(f.premium[1] + ' premium → ' + nameOf(f.premium[0]));
  if (f.intoRequest) bits.push(f.intoRequest + ' retained in the request');
  if (f.bookingFee) bits.push(f.bookingFee + ' external booking fee');
  return bits.length ? bits.join('; ') : 'no application flow recorded';
}
const REASON_WORDS = {
  "keri-conviction-refused": "Conviction needs duplicity at the retained key and a carrier not already pending.",
  "keri-conviction-required": "Only a convicted carrier can be booked for termination; a live carrier stays in custody until it is convicted.",
  "keri-carrier-missing": "This identity has no retained carrier at this point.",
  "keri-generation-mismatch": "This proposal names a registry generation that has already moved.",
  "keri-plugin-mismatch": "The proposed application policy differs from the registry configuration.",
  "keri-inception-refused": "An inception in this batch lacks the required evidence.",
  "empty-fold": "Select at least one pending request to process.",
  "key-exists": "This key is already registered and cannot be registered again.",
  "not-phase1": "The complete transaction interval must fit the registration processing window.",
  "retract-window": "The complete transaction interval must fit the owner retraction window.",
  "retract-owner": "The transaction lacks the refund owner’s signature.",
  "reject-not-expired": "This registration has not reached its expiry boundary.",
  "reject-compatible": "The current registry state is compatible with this registration; mismatch rejection does not apply.",
  "fold-duplicate-input": "A transaction cannot spend the same input twice.",
  "backdated-booking": "The booking interval does not agree with the submitted timestamp."
};
const reasonText = reason => (REASON_WORDS[reason] || reason.replaceAll('-', ' ')) + ' [' + reason + ']';
function needsOf(action) {
  const t = actionTag(action);
  if (t === 'convictCkpt') return { cls: 'public', text: 'duplicity evidence at this key' };
  if (t === 'genericRetraction') return { cls: 'keys', text: 'refund-owner signature and retraction interval' };
  return { cls: 'public', text: t === 'fold' ? 'complete batch, value, token and authorization checks' : 'complete request or transaction observations' };
}

/* ---- free play: offers and dry-run come from the generated backend slice ---- */
const actorOfNode = n => n.actorId || null;

/* ---- the scene ----------------------------------------------------------------
   Every entity is a <g data-obj data-key> placed by `layout`, so the fx layer
   can fly things between them. Regions: KERI (the owners, their witnesses,
   the convictor, the stranger) · the chain (the registry UTxO with its leaves,
   the inbox, the checkpoints, the validator, the tray) · readers & payees
   (the folder, the reaper, the wallets). */
const layout = {
  'actor:alice': { x: 80, y: 110 }, 'actor:bob': { x: 190, y: 110 }, witnesses: { x: 135, y: 200 }, 'actor:cora': { x: 80, y: 330 }, 'actor:mallory': { x: 190, y: 330 }, keri: { x: 135, y: 470 },
  registry: { x: 400, y: 150 }, inbox: { x: 610, y: 150 }, 'ckpt:11': { x: 360, y: 330 }, 'ckpt:12': { x: 480, y: 330 }, 'ckpt:13': { x: 600, y: 330 }, ckpts: { x: 480, y: 330 },
  validator: { x: 500, y: 460 }, tray: { x: 500, y: 545 }, clock: { x: 500, y: 40 },
  'actor:hal': { x: 860, y: 110 }, 'actor:sam': { x: 860, y: 230 }, wallets: { x: 860, y: 360 },
};
const walletPos = i => ({ x: 862, y: 330 + i * 40 });
function hexagon(cx, cy, r) { const pts = []; for (let i = 0; i < 6; i++) { const a = Math.PI / 3 * i - Math.PI / 6; pts.push((cx + r * Math.cos(a)).toFixed(1) + ',' + (cy + r * Math.sin(a)).toFixed(1)); } return pts.join(' '); }
function balancesAlong(nodes) {
  const balances = {};
  const add = (address, component, value) => { const b = balances[address] ||= { refunds: 0n, premium: 0n }; b[component] += E.toInternal(value); };
  for (const n of nodes) if (n.record?.result.ok) {
    const f = n.record.result.ok.flow;
    if (f.bondReturn) add(f.bondReturn[0], 'refunds', f.bondReturn[1]);
    if (f.premium) add(f.premium[0], 'premium', f.premium[1]);
  }
  return E.toWire(balances);
}
function drawScene() {
  const sess = cur(), st = sess.state, svg = clear($('scene'));
  const parts = [];
  for (const [x, width, title] of [[10,250,'KERI · the identities'], [275,450,'Cardano · registry and custody'], [740,250,'folders, bookers & payees']])
    parts.push(s('rect',{class:'region',x,y:10,width,height:580,rx:14}),s('text',{class:'rlbl',x:x+14,y:34},title));
  for (const [id,c] of Object.entries(CAST)) {
    const q=layout['actor:'+id], current=c.aid ? ckptOf(sess,c.aid) : null;
    parts.push(s('g',{class:'actor'+(app.actor===id?' on':''),dataset:{obj:'actor',key:'actor:'+id},transform:'translate('+q.x+','+q.y+')',role:'button',tabindex:0,onclick:()=>{app.actor=id;render();}},
      s('circle',{class:'avatar',r:28}),s('text',{class:'nm',y:4},c.name),s('text',{class:'role',y:42},c.role),s('text',{class:'badge',y:57},current ? current.st+' · key '+current.k : '')));
  }
  const box=(key,x,y,w,title,lines,klass='utxo')=>s('g',{dataset:{obj:key,key}},s('rect',{class:klass,x,y,width:w,height:Math.max(75,37+lines.length*23),rx:10}),s('text',{class:'state-word',x:x+10,y:y+20},title),...lines.map((line,i)=>s('text',{class:'datum-v',x:x+10,y:y+44+i*23},line)));
  parts.push(box('registry',290,65,208,'generation '+st.gen,st.trie.length ? st.trie.slice(0,5).map(([aid,l])=>'AID '+aid+' · '+leafWord(l)) : ['no registered keys']));
  const requests=pendingOf(sess);
  parts.push(box('inbox',510,65,203,'requests · '+requests.length,requests.slice(0,5).map(m=>m.kind+' · '+m.booking.request.key),'tray'));
  const holders=[...st.carriers.map(c=>({aid:c.aid,token:c.token,k:c.k,state:c.st,min:c.minAda})),...st.terminations.map(e=>({aid:e.payload.aid,token:e.payload.token,k:e.payload.keyState,state:'booked termination',min:e.booking.request.contents.lovelace}))];
  holders.slice(0,3).forEach((c,i)=>{const x=288+i*143;layout['ckpt:'+c.aid]={x:x+65,y:330};parts.push(box('ckpt:'+c.aid,x,280,138,'AID '+c.aid,[c.state,'token '+c.token+' · key '+c.k,'retained '+c.min],'ck'));});
  if(!holders.length)parts.push(s('text',{class:'hint',x:305,y:330},'No retained carrier or booked termination'));
  parts.push(box('validator',300,423,400,'Transaction judgment',['admit or refuse these complete observations'],'tray'));
  const rows=Object.entries(sess.env).flatMap(([key,xs])=>xs.map(x=>key+' '+(Array.isArray(x)?x.join('/') : x)));
  parts.push(box('tray',300,505,400,'Evidence table',[rows.slice(0,3).join(' · ')||'none presented'],'tray'));
  const bal=balancesAlong(pathTo(app.cursor).map(node));
  parts.push(box('wallets',750,340,230,'Application payments',Object.entries(bal).flatMap(([a,b])=>[nameOf(a),b.refunds+' returned · '+b.premium+' premium']),'wallet'));
  parts.push(s('g',{dataset:{obj:'clock',key:'clock'}},s('text',{class:'clock-t',x:500,y:45},'proposal slot '+(sess.now??0))));
  parts.push(s('g',{id:'fx'}));svg.append(...parts);
}


/* ---- the fx layer: things that fly between entities ----------------------- */
const fxLayer = () => { const sv = $('scene'); return sv ? sv.querySelector('#fx') : null; };
function cancelFx() { for (const f of app.fx) f.cancel(); app.fx = []; }
function animate(dur, frame, done) {
  let cancelled = false, last = null;
  const start = nowMs();
  const f = { cancel: () => { cancelled = true; } };
  app.fx.push(f);
  const tick = () => {
    if (cancelled) return;
    const now = nowMs();
    const frozen = last !== null && now === last; last = now;
    const u = frozen ? 1 : Math.min(1, Math.max(0, (now - start) / dur));
    frame(u);
    if (u < 1) raf(tick); else { app.fx = app.fx.filter(x => x !== f); if (done) done(); }
  };
  raf(tick);
}
const ease = u => (u < .5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2);
const posOf = key => layout[key] || layout.validator;
function fly(el, fromKey, toKey, opts) {
  opts = opts || {};
  const layer = fxLayer(); if (!layer) return;
  const f = posOf(opts.dir < 0 ? toKey : fromKey), t = posOf(opts.dir < 0 ? fromKey : toKey);
  layer.append(el);
  animate(opts.dur || 700, u => {
    const e = ease(u);
    const x = f.x + (t.x - f.x) * e, y = f.y + (t.y - f.y) * e - (opts.arc === undefined ? 40 : opts.arc) * Math.sin(Math.PI * u);
    el.setAttribute('transform', `translate(${x.toFixed(1)},${y.toFixed(1)})`);
  }, () => { el.remove(); if (opts.done) opts.done(); });
}
function coin(cls, txt, rewind) { return s('g', { class: 'fx-coin' + (rewind ? ' rewind' : '') }, s('ellipse', { class: 'coin ' + cls, rx: 14, ry: 6 }), s('text', { class: 'fx-t', y: -10 }, txt)); }
function card(txt, rewind) {
  const width = Math.max(68, 18 + txt.length * 7);
  return s('g', { class: 'fx-card' + (rewind ? ' rewind' : '') },
    s('rect', { class: 'fx-card', x: -width / 2, y: -12, width, height: 24, rx: 4 }),
    s('text', { class: 'fx-t', y: 4 }, txt));
}
function scroll(txt, rewind) { return s('g', { class: rewind ? 'rewind' : '' }, s('rect', { class: 'fx-scroll', x: -30, y: -10, width: 60, height: 20, rx: 10 }), s('text', { class: 'fx-t', y: 4 }, txt)); }
function pulse(key, bad) {
  const el = $('scene').querySelector(`[data-key="${key}"]`); if (!el) return;
  el.classList.add(bad ? 'pulse-bad' : 'pulse'); setTimeout(() => el.classList.remove(bad ? 'pulse-bad' : 'pulse'), 800);
}
function floatText(key, txt, cls, delay) {
  const layer = fxLayer(); if (!layer) return;
  const q = posOf(key);
  const el = s('text', { class: 'fx-float ' + (cls || ''), x: q.x, y: q.y - 30 });
  el.textContent = txt;
  setTimeout(() => { layer.append(el); animate(1000, u => { el.setAttribute('y', q.y - 30 - 26 * u); el.setAttribute('opacity', String(1 - u * u)); }, () => el.remove()); }, delay || 0);
}
function mark(key, ok, txt, delay) {
  const layer = fxLayer(); if (!layer) return;
  const q = posOf(key);
  setTimeout(() => {
    const el = s('text', { class: 'fx-mark ' + (ok ? 'ok' : 'no'), x: q.x, y: q.y - 36 }, ok ? '✓' : '✗');
    layer.append(el);
    animate(900, u => { el.setAttribute('transform', `translate(0,${(-18 * Math.sin(Math.PI * Math.min(1, u * 1.4))).toFixed(1)})`); el.setAttribute('opacity', String(u > .7 ? (1 - u) / .3 : 1)); }, () => el.remove());
    if (txt) floatText(key, txt, ok ? 'ok' : 'no', 80);
    pulse(key, !ok);
  }, delay || 0);
}
function edgeFx(n, dir, dur) {
  if(n.kind==='time'){pulse('clock');return;}
  if(n.kind==='evidence'){pulse('tray');return;}
  if(!n.record)return;
  const r=n.record,ok=!!r.result.ok,kind=actionTag(r.action),actor='actor:'+(actorOfNode(n)||app.actor||'mallory');
  const label = ({bookRegistration:'Register',bookTermination:'Book termination',convictCkpt:'Convict',genericRetraction:'Retract',genericRejection:'Reject',fold:'Fold'})[kind];
  fly(card(label,dir<0),actor,'validator',{dir,dur:dur*.5,done:()=>mark('validator',ok,ok?'accepted':r.result.error)});
  if(!ok)return;
  const f=r.result.ok.flow;
  for(const pay of [f.bondReturn,f.premium])if(pay)fly(coin('dreg',String(pay[1]),dir<0),'ckpts','wallets',{dir,dur});
  pulse(kind==='fold'?'registry':kind==='bookRegistration'?'inbox':'ckpts');
}

function playEdges(edges) {
  cancelFx();
  if (!edges.length) return;
  const per = edges.length === 1 ? 800 : Math.max(220, Math.floor(1400 / edges.length));
  edges.forEach((e, i) => setTimeout(() => { if (app.cursor !== edges[edges.length - 1].node) return; edgeFx(node(e.node), e.dir, per); }, i * per));
}

/* ---- rendering ---------------------------------------------------------------- */
function render() {
  renderHeader(); renderStoryBar(); renderTree(); renderPlaybar(); renderWhere(); renderPots(); renderNarration(); renderNext(); drawScene(); renderLedger();
  renderEvidence(); renderNumbers(); renderChart(); renderMoney();
}
function renderHeader() {
  const sess=cur(), p=sess.params, c=sess.state.config;
  $('slot-now').textContent=fmt(sess.now??0);$('slot-input').value=fmt(sess.now??0);
  $('slot-plusw').textContent='+process ('+c.processTime+')';
  $('pf-params').textContent='Bond '+p.D+'; retained carrier min-ADA '+p.Mc+'; request min-ADA '+p.Mr+'; tip '+p.tip+'. Processing window '+c.processTime+', retraction window '+c.retractTime+'. The proposal clock chooses transaction intervals; it does not change registry state.';
}
function renderStoryBar() {
  const sel = $('story-picker');
  if (!sel.options.length) {
    sel.append(h('option', { value: '' }, 'free play — pick a story to play its tree'));
    for (const sc of SCENARIOS) sel.append(h('option', { value: String(sc.id) }, sc.id + '. ' + sc.story + (sc.forks && sc.forks.length ? ' ⋔' : '')));
    for (const id of Object.keys(CHALLENGES)) sel.append(h('option', { value: 'c:' + id }, '★ Challenge: ' + CHALLENGES[id].title));
  }
  sel.value = app.story ? String(app.story.id) : (app.challenge ? 'c:' + Object.keys(CHALLENGES).find(k => CHALLENGES[k] === app.challenge) : '');
  $('story-goal').textContent = app.story ? app.story.narrative : 'Free play: every accepted move is a node of the tree below; a second move from the same node opens a branch.';
}
function treeLayout() {
  const col = {}, row = {};
  let rows = 0;
  const place = (id, r) => {
    row[id] = r;
    const n = node(id);
    const kids = n.children.slice();
    const first = n.last !== null ? n.last : kids[0];
    kids.sort((a, b) => (a === first ? -1 : b === first ? 1 : a - b));
    kids.forEach((c, i) => { col[c] = col[id] + 1; if (i === 0) place(c, r); else { rows++; place(c, rows); } });
  };
  col[0] = 0; place(0, 0);
  return { col, row, rows: rows + 1, cols: Math.max(...Object.values(col)) + 1 };
}
const shortWho = w => (w || '').split(/ — | · /)[0].split(' ')[0].slice(0, 8);
function nodeVerb(n) {
  if(n.record)return ({bookRegistration:'register request',bookTermination:'book termination',convictCkpt:'convict',genericRetraction:'retract',genericRejection:'reject'})[actionTag(n.record.action)]||actionTag(n.record.action);
  return n.kind==='time'?'slot '+n.session.now:n.kind==='evidence'?'evidence':'start';
}
function renderTree() {
  const svg = $('tree');
  const { col, row, rows, cols } = treeLayout();
  const dx = 74, dy = 44, x0 = 36, y0 = 22;
  const W = x0 * 2 + (cols - 1) * dx, H = y0 * 2 + (rows - 1) * dy + 22;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`); svg.setAttribute('width', W); svg.setAttribute('height', H);
  const X = id => x0 + col[id] * dx, Y = id => y0 + row[id] * dy;
  const onPath = new Set(currentPath());
  const parts = [];
  for (const n of app.nodes) {
    if (n.parent === null) continue;
    const px = X(n.parent), py = Y(n.parent), x = X(n.id), y = Y(n.id);
    const d = py === y ? `M ${px} ${py} L ${x} ${y}` : `M ${px} ${py} L ${px + dx * .45} ${py} Q ${px + dx * .6} ${py} ${px + dx * .6} ${py + (y - py) * .35} L ${px + dx * .6} ${y - 8} Q ${px + dx * .6} ${y} ${px + dx * .75} ${y} L ${x} ${y}`;
    parts.push(s('path', { class: 'edge' + (onPath.has(n.id) && onPath.has(n.parent) ? ' taken' : ''), d }));
  }
  for (const n of app.nodes) {
    const cls = ['node', n.record ? (n.record.result.ok ? 'ok' : 'no') : n.kind, n.id === app.cursor ? 'here' : ''].join(' ');
    const g = s('g', { class: cls, dataset: { node: n.id, branch: n.branch ? n.branch.id : '' }, transform: `translate(${X(n.id)},${Y(n.id)})`, role: 'button', tabindex: 0, onclick: () => goTo(n.id) });
    g.append(s('title', {}, (n.id === app.punch ? '★ the punchline of this story\n' : '') + (n.who ? n.who + ' — ' + nodeVerb(n) + '\n' : '') + (n.say || '')));
    g.append(s('circle', { r: 8 }));
    g.append(s('text', { y: 3.5 }, n.id === 0 ? '·' : (n.record ? (n.record.result.ok ? '✓' : '✗') : (n.kind === 'time' ? '⏱' : '≡'))));
    g.append(s('text', { class: 'who', y: 20 }, n.id === 0 ? 'start' : shortWho(n.who)));
    if (n.id !== 0) g.append(s('text', { class: 'verb', y: 31 }, nodeVerb(n)));
    if (n.children.length > 1) g.append(s('text', { class: 'fork', x: 12, y: -8 }, '⋔'));
    if (n.id === app.punch) { g.classList.add('punch'); g.append(s('text', { class: 'star', x: -14, y: -8 }, '★')); }
    parts.push(g);
  }
  clear(svg).append(...parts);
}
function renderPlaybar() {
  const path = currentPath();
  const idx = path.indexOf(app.cursor);
  const here = node(app.cursor);
  $('hist-first').disabled = app.cursor === 0;
  $('hist-prev').disabled = here.parent === null;
  $('hist-next').disabled = !here.children.length;
  $('hist-last').disabled = !here.children.length;
  const scrub = $('scrub'); scrub.max = String(path.length - 1); scrub.value = String(idx);
  $('pos').textContent = idx + ' / ' + (path.length - 1);
  $('btn-play').classList.toggle('on', !!app.playing);
  $('btn-play').textContent = app.playing ? '❚❚' : '▶';
  const coda = $('btn-coda'); if (coda) coda.classList.toggle('on', app.punch !== null && app.cursor === app.punch && here.children.length > 0 && !app.playing);
}
function renderWhere() {
  const st=cur().state,w=clear($('where'));
  w.append(h('span',{class:'state'},st.trie.length?st.trie.length+' registered keys':'Empty registry'),h('span',{class:'sum gen'},'generation '+st.gen),h('span',{class:'tiny'},st.trie.filter(([,l])=>l.known?.s==='active').length+' active · '+st.trie.filter(([,l])=>l.known?.s==='terminal').length+' retired'),h('span',{class:'sum dreg'},st.carriers.length+' retained carriers'),h('span',{class:'sum b'},st.registrations.length+' registration requests · '+st.terminations.length+' booked terminations'),h('span',{class:'step'},'step '+(pathTo(app.cursor).length-1)));
  renderHud();renderChallenge();
}
function renderPots() {
  const st=cur().state,svg=clear($('hub'));
  svg.setAttribute('viewBox','0 0 540 100');
  const rooms=[['absent',75],['active',265],['retired',455]];
  for(const [label,x] of rooms)svg.append(s('g',{class:'room'+((label==='absent'&&!st.trie.length)||st.trie.some(([,l])=>leafWord(l)===label)?' on':'')},s('rect',{x:x-70,y:10,width:140,height:60,rx:12}),s('text',{x,y:45,'text-anchor':'middle'},label)));
  svg.append(s('text',{x:170,y:45},'→'),s('text',{x:360,y:45},'→'));
  const dl=clear($('pots-dl')),p=cur().params,c=st.config;
  for(const [term,body] of [
    ['Bond D ('+p.D+')','Locks on registration. There is no owner exit: a carrier is live until it is convicted.'],
    ['Retained min-ADA ('+p.Mc+')','Stays with the carrier until a termination booking moves it into the request.'],
    ['Request min-ADA ('+p.Mr+') and tip ('+p.tip+')','Termination booking retains both in its request; the premium is carrier min-ADA minus these two values. Booking fees use external funding.'],
    ['Active registry key','Covers live and termination-pending custody. Only a consuming termination fold retires it.'],
    ['Pending termination','Conviction retains the token and key. Booking moves whole custody to a request; another request cannot complete it.'],
    ['Retired registry key','Permanent. Its representative token was burned by the consuming fold.'],
    ['Time windows','Registration processing: '+c.processTime+' slots after submission. Owner retraction: the following '+c.retractTime+' slots. Complete transaction bounds are checked.'],
    ['Evidence table','Finite model predicates, not generated signatures or a concrete KERI proof. The local checkpoint simulator separately checks concrete duplicity.']])dl.append(h('dt',{},term),h('dd',{},body));
}

function renderNarration() {
  const n=node(app.cursor),box=clear($('narration'));
  box.append(h('div',{},n.who?h('b',{},n.who+' · '):null,n.say||''));
  if(n.record){const r=n.record.result;box.append(h('div',{class:r.ok?'ok':'no'},r.ok?'✓ accepted · '+describeFlow(r.ok.flow):'✗ '+reasonText(r.error)));}
}
function renderNext() {
  const sess = cur();
  const here = node(app.cursor);
  const br = clear($('branches'));
  const nextId = nextOf(app.cursor);
  for (const cid of here.children) {
    const c = node(cid);
    br.append(h('button', { type: 'button', class: 'branch' + (cid === nextId ? ' on' : ''), dataset: { branch: cid, fork: c.branch ? c.branch.id : '' }, title: 'go there', onclick: () => goTo(cid) },
      h('span', { class: 'go' }, cid === nextId ? '› next' : '⋔'),
      c.branch ? h('span', { class: 'fork-t' }, c.branch.title) : null,
      c.who ? h('span', { class: 'who' }, c.who) : null,
      h('span', { class: 'txt' }, c.say || ''),
      c.record ? h('span', { class: 'res ' + (c.record.result.ok ? 'ok' : 'no') }, c.record.result.ok ? '✓ accepted' : '✗ ' + c.record.result.error) : null));
  }
  if (!here.children.length) br.append(h('div', { class: 'tiny' }, app.story ? 'The story ends here on this branch. Any move below opens a new one.' : 'Nothing has happened after this step yet.'));
  const moves = clear($('next-moves')), refused = clear($('refused-list'));
  let nRefused = 0;
  // story mode: one actor and one move glow — the story's next step; the other cards fold
  const nn = app.story && nextId !== null ? node(nextId) : null;
  const spotActor = nn && (nn.record || nn.evRow) ? actorOfNode(nn) : null;
  const spotKind = nn && nn.record ? actionTag(nn.record.action) : null;
  const spotOp = nn && nn.record && nn.record.action.contribute ? opWord(nn.record.action.contribute.op) : null;
  const spotEv = nn && nn.evRow ? canonicalJson(nn.evRow) : null;
  const refusedRows = [];
  let folded = 0;
  for (const id of ACTOR_ORDER) {
    const c = CAST[id];
    const off = offersFor(id, currentTree());
    const isSpot = spotActor === id;
    const fold = !!spotActor && !isSpot && !app.unfold;
    if (fold) folded++;
    const cardEl = h('div', { class: 'mover' + (isSpot ? ' spot' : '') + (fold ? ' folded' : '') });
    cardEl.append(h('button', { type: 'button', class: 'actor' + (id === app.actor ? ' on' : ''), dataset: { actor: id }, title: c.blurb, onclick: () => { app.actor = id; app.pending = null; render(); } }, c.name + ' · ' + c.role));
    cardEl.append(h('div', { class: 'interest' }, INTEREST[id]));
    const acts = h('div', { class: 'acts' });
    for (const o of off.chain) {
      const attempted = dryRun(currentTree(), o.action); const d = { ok: !!attempted.record.result.ok, why: attempted.record.result.error ? reasonText(attempted.record.result.error) : null };
      const needs = needsOf(o.action);
      const glow = isSpot && d.ok && o.kind === spotKind && (spotOp === null || (o.action.contribute && opWord(o.action.contribute.op) === spotOp));
      const btn = h('button', { type: 'button', class: 'act' + (app.pending && app.pending.offer === o ? ' on' : '') + (glow ? ' glow' : ''), dataset: { kind: o.kind, actor: id }, disabled: !d.ok,
        title: (d.ok ? 'the machine would accept this now' : d.why) + ' · needs: ' + needs.text,
        onclick: () => { app.actor = id; app.pending = { offer: o, action: JSON.parse(JSON.stringify(o.action)) }; renderNext(); } }, o.label, h('span', { class: 'needs ' + needs.cls }, needs.text));
      if (d.ok) { if (!acts.children.length) acts.append(h('span', { class: 'inv-lbl' }, 'moves · each is a transaction')); acts.append(btn); } else { refusedRows.push({ who: c.name, label: o.label, why: d.why }); nRefused++; }
    }
    let invLabelled = false;
    for (const k of off.keri) {
      const kind = Object.keys(k.row)[0];
      if (evHas(sess.env, kind, k.row[kind])) continue;
      if (!invLabelled) { acts.append(h('span', { class: 'inv-lbl' }, 'inventory · off-chain, not a transaction: what ' + c.name + ' can bring')); invLabelled = true; }
      const glowEv = isSpot && spotEv !== null && canonicalJson(k.row) === spotEv;
      acts.append(h('button', { type: 'button', class: 'ev-quick' + (glowEv ? ' glow' : ''), dataset: { actor: id, ev: kind }, title: k.hint,
        onclick: () => { app.actor = id; adoptTree(treeAddEvidence(currentTree(), k.row).tree, true); render(); } }, '+ ' + k.label));
    }
    if (!acts.children.length) acts.append(h('span', { class: 'none' }, 'nothing the machine accepts from here'));
    cardEl.append(acts);
    moves.append(cardEl);
  }
  moves.append(h('div', { class: 'mover' }, h('div', { class: 'lbl' }, 'Time'), h('div', { class: 'acts' },
    h('button', { type: 'button', class: 'act', dataset: { kind: 'time' }, onclick: () => moveSlot(addNat(sess.now ?? 0, 1)) }, '+1 slot'),
    h('button', { type: 'button', class: 'act', dataset: { kind: 'time' }, onclick: () => moveSlot(addNat(sess.now ?? 0, sess.state.config.processTime)) }, `+processing window (${sess.state.config.processTime})`),
    h('button', { type: 'button', class: 'act', dataset: { kind: 'time' }, onclick: () => moveSlot(addNat(sess.now ?? 0, sess.state.config.retractTime)) }, `+retraction window (${sess.state.config.retractTime})`))));
  if (folded) moves.append(h('button', { type: 'button', class: 'ghost', id: 'unfold', onclick: () => { app.unfold = true; renderNext(); } }, folded + ' other ' + (folded > 1 ? 'people' : 'person') + ' could also move · show all'));
  const groups = new Map();
  for (const r of refusedRows) { if (!groups.has(r.why)) groups.set(r.why, []); groups.get(r.why).push(r.who + ': ' + r.label); }
  for (const [why, whos] of groups) refused.append(h('div', { class: 'refused-row' }, h('span', { class: 'why' }, why), h('span', { class: 'who' }, whos.join(' · '))));
  $('refused-summary').textContent = nRefused ? `${nRefused} move${nRefused > 1 ? 's' : ''} the machine refuses now, for ${groups.size} reason${groups.size > 1 ? 's' : ''} — open to read why` : 'nothing is refused now';
  $('refused-moves').hidden = !nRefused;
  renderActForm();
}
const FIELDS={convictCkpt:[['aid','AID']],fold:[['expectedGen','generation'],['expectedPlugin','application policy']]};
function renderActForm() {
  const form=$('act-form');form.hidden=!app.pending;if(!app.pending)return;
  const t=actionTag(app.pending.action),d=dataOf(app.pending.action),fields=clear($('act-fields'));
  for(const [f,label] of FIELDS[t]||[])fields.append(h('label',{},label,h('input',{type:'text',inputmode:'numeric',value:d[f],onchange:e=>{const n=parseNat(e.target.value);if(n===null){$('act-why').textContent='Enter a non-negative whole number.';return;}d[f]=n;renderActForm();}})));
  if(t==='fold') {
    const selected=d.transaction.transaction.inputs.filter(i=>i.ref).map(i=>i.ref),all=pendingOf(cur());
    const box=h('div',{class:'batch'},h('span',{class:'lbl'},'Select complete requests to process. Rejection is a separate transaction.'));
    all.forEach((m,i)=>{const ref=m.booking.request.reference,on=selected.some(r=>equal(r,ref));box.append(h('label',{},m.kind+' for AID '+m.booking.request.key,h('select',{dataset:{batch:i},onchange:e=>{const refs=all.filter((x,j)=>j===i?e.target.value==='process':selected.some(r=>equal(r,x.booking.request.reference))).map(x=>x.booking.request.reference);app.pending.action=B.foldAction(cur().params,cur().state,refs,d.transaction.transaction.validity.lower);renderActForm();}},['leave','process'].map(v=>h('option',{value:v,selected:(v==='process')===on},v)))));});fields.append(box);
  }
  fields.append(h('details',{},h('summary',{},'Complete proposed transaction'),h('textarea',{rows:10,value:JSON.stringify(app.pending.action,null,2),onchange:e=>{try{const a=JSON.parse(e.target.value);dryRun(currentTree(),a);app.pending.action=a;renderActForm();}catch(error){$('act-why').textContent='Invalid transaction input: '+error.message;$('act-submit').disabled=true;}}},JSON.stringify(app.pending.action,null,2))));
  try{const r=dryRun(currentTree(),app.pending.action).record.result;$('act-why').className=r.ok?'ok':'no';$('act-why').textContent=r.ok?'Accepted: '+describeFlow(r.ok.flow):reasonText(r.error);$('act-submit').disabled=false;}
  catch(error){$('act-why').textContent='Invalid input: '+error.message;$('act-submit').disabled=true;}
}
function submitPending(){if(!app.pending)return;const action=app.pending.action;app.pending=null;const tree=submit(currentTree(),action);tree.nodes.at(-1).actorId=app.actor;tree.nodes.at(-1).who=CAST[app.actor].name;adoptTree(tree,true);render();}
const backendMoveSlot=moveSlot;
moveSlot=function(target){try{adoptTree(backendMoveSlot(currentTree(),target),true);$('slot-msg').textContent='';render();}catch(error){$('slot-msg').textContent=error.message;}};
function renderEvidence() {
  const sess=cur(),env=sess.env;
  const aids=[...new Set([11,12,13,...env.inception,...env.duplicity.map(r=>r[0]),...sess.state.carriers.map(c=>c.aid),...(app.extraAids||[])])];
  const tbl=h('table',{class:'evtable'},h('thead',{},h('tr',{},...['AID','inception','duplicity at key'].map(t=>h('th',{},t))))),tb=h('tbody',{});
  const cb=(kind,args,label)=>h('label',{},h('input',{type:'checkbox',dataset:{ev:kind,aid:args[0],k:args[1]??''},checked:evHas(env,kind,args),onchange:e=>{adoptTree(editEvidence(currentTree(),{[kind]:args},e.target.checked),true);render();}}),label);
  for(const aid of aids){const key=ckptOf(sess,aid)?.k??0;const ks=[...new Set([0,1,2,3,key])];tb.append(h('tr',{},h('td',{},aid),h('td',{},cb('inception',[aid],'verifies')),h('td',{},ks.map(k=>cb('duplicity',[aid,k],String(k))))));}
  tbl.append(tb);clear($('evbody')).append(tbl);
}


/* ---- the numbers drawer -------------------------------------------------------- */
function renderNumbers() {
  const st=cur().state,kv=clear($('registry'));
  for(const [name,value] of [['generation',st.gen],['application policy',st.config.applicationPolicy],['next token',st.nextToken],['treasury',st.treasury],['bindings',JSON.stringify(st.bindings)],['registry',JSON.stringify(st.trie)]])kv.append(h('dt',{},name),h('dd',{},String(value)));
  $('ck-count').textContent=st.carriers.length+' retained carriers';clear($('checkpoints')).append(h('pre',{},JSON.stringify(st.carriers,null,2)));
  $('inbox-count').textContent=st.registrations.length+' registrations; '+st.terminations.length+' terminations';clear($('inbox')).append(h('pre',{},JSON.stringify({registrations:st.registrations,terminations:st.terminations},null,2)));
}


/* ---- the chart: three lanes over the current branch --------------------------- */
function heldBy(sess) {
  const st=E.toInternal(sess.state),p=E.toInternal(sess.params);
  return {dreg:BigInt(st.carriers.filter(c=>c.st==='live').length)*p.D,b:st.carriers.reduce((n,c)=>n+c.minAda,0n)+[...st.registrations,...st.terminations.map(e=>e.booking)].reduce((n,b)=>n+b.request.contents.lovelace,0n)};
}
function paidOut(f){return E.toInternal(f.bondReturn?.[1]??0)+E.toInternal(f.premium?.[1]??0);}

function renderChart() {
  const canvas = $('value-chart');
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const dpr = window.devicePixelRatio || 1;
  const W = Math.max(320, canvas.clientWidth || 640), H = 240;
  canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const css = getComputedStyle(document.documentElement);
  const col = v => (css.getPropertyValue(v) || '').trim() || '#888';
  ctx.clearRect(0, 0, W, H);
  const path = currentPath(), tl = path.map(node), n = tl.length, cursorI = path.indexOf(app.cursor);
  const left = 46, right = 10, top = 8, laneGap = 8;
  const laneH = (H - top - 22 - 2 * laneGap) / 3;
  const x = i => left + (n > 1 ? (W - left - right) * i / (n - 1) : (W - left - right) / 2);
  let cum = 0n;
  const paid = tl.map(t => { if (t.record && t.record.result.ok) cum += paidOut(t.record.result.ok.flow); return cum; });
  const lanes = [['dreg', '--dreg', 'D in checkpoints', tl.map(t => heldBy(t.session).dreg)], ['b', '--b', 'inbox + min-ADA', tl.map(t => heldBy(t.session).b)], ['pool', '--pool', 'paid out', paid]];
  ctx.font = '10px ' + col('--mono');
  lanes.forEach(([key, cv, label, vals], li) => {
    const y0 = top + li * (laneH + laneGap), y1 = y0 + laneH;
    const max = vals.reduce((a,b)=>a>b?a:b,1n);
    const y = v => y1 - (laneH - 12) * Number(v * 10000n / max) / 10000;
    ctx.strokeStyle = col('--line-2'); ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(left, y1 + .5); ctx.lineTo(W - right, y1 + .5); ctx.stroke();
    ctx.fillStyle = col('--muted'); ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
    ctx.fillText(String(max), left - 6, y(max)); ctx.fillText('0', left - 6, y1);
    ctx.textAlign = 'left'; ctx.fillStyle = col(cv); ctx.fillText(label, left + 4, y0 + 6);
    const c = col(cv);
    ctx.beginPath(); ctx.moveTo(x(0), y1);
    for (let i = 0; i < n; i++) { ctx.lineTo(x(i), y(vals[i])); if (i + 1 < n) ctx.lineTo(x(i + 1), y(vals[i])); }
    ctx.lineTo(x(n - 1), y1); ctx.closePath();
    ctx.globalAlpha = .18; ctx.fillStyle = c; ctx.fill(); ctx.globalAlpha = 1;
    ctx.beginPath(); ctx.strokeStyle = c; ctx.lineWidth = 2;
    for (let i = 0; i < n; i++) { if (i === 0) ctx.moveTo(x(i), y(vals[i])); else ctx.lineTo(x(i), y(vals[i - 1])); ctx.lineTo(x(i), y(vals[i])); }
    ctx.stroke();
    ctx.strokeStyle = col('--accent'); ctx.lineWidth = 1; ctx.setLineDash([3, 3]);
    ctx.beginPath(); ctx.moveTo(x(cursorI) + .5, y0); ctx.lineTo(x(cursorI) + .5, y1); ctx.stroke(); ctx.setLineDash([]);
  });
  ctx.fillStyle = col('--muted'); ctx.textAlign = 'center'; ctx.textBaseline = 'top';
  const every = Math.max(1, Math.ceil(n / Math.max(4, Math.floor((W - left - right) / 44))));
  for (let i = 0; i < n; i += every) ctx.fillText('s' + tl[i].session.now, x(i), H - 16);
  ctx.textAlign = 'left'; ctx.fillText('step →', left, H - 6);
}

/* ---- the theorem lamps ----------------------------------------------------- */
const LAMPS=[{id:'T7',title:'Complete result agrees with Lean',lean:'RegistryTraceDriver, RegistryBoundaryDriver, RegistryStoryDriver'},...THEOREMS];
function renderLedger() {
  const nodes=pathTo(app.cursor).map(node).filter(n=>n.record),counts=Object.fromEntries(LAMPS.map(t=>[t.id,{shown:0,broken:0}]));
  let last={};
  for(const n of nodes){last=properties(n.record);const oracle=oracleResult(ORACLE,n.record);last.T7={v:oracle.found?(oracle.agrees?'holds':'fails'):'unshown'};for(const [id,r] of Object.entries(last)){if(r.v!=='unshown')counts[id].shown++;if(r.v==='fails')counts[id].broken++;}}
  const led=clear($('ledger'));
  for(const th of LAMPS){const c=counts[th.id];led.append(h('details',{class:'thm'+(last[th.id]?.v==='holds'?' lit':'')+(c.broken?' broken':'')+(c.shown?' seen':''),dataset:{id:th.id}},h('summary',{},h('span',{class:'ttl'},th.title),h('span',{class:'st'},c.broken?'BROKEN':c.shown?c.shown+' shown':'—')),h('div',{class:'body'},th.id==='T7'?'The complete input must occur in the embedded Lean corpus. Then verdict, flow, state and observations must all agree. An unlisted input has no oracle claim.':'This sampled step checks the named theorem conclusion when its executable premise holds. It does not certify an uploaded state as reachable.'),h('div',{class:'lean'},th.lean)));}
  $('found').textContent='discovered in this run: '+Object.values(counts).filter(c=>c.shown).length+' of '+LAMPS.length;
}


/* ---- money ---------------------------------------------------------------- */
function renderMoney() {
  const nodes=pathTo(app.cursor).map(node),balances=balancesAlong(nodes),hd=heldBy(cur());
  clear($('balances')).append(h('p',{},'Live bonds '+hd.dreg+' · request value and retained min-ADA '+hd.b),h('pre',{},JSON.stringify(balances,null,2)),h('p',{class:'tiny'},'Payments above are application Flow fields. Generic refunds, transaction fees, donations and output values are explicit in each complete transaction below; this is not a wallet balance.'));
  const flows=clear($('flows'));
  for(const n of nodes)if(n.record)flows.append(h('details',{},h('summary',{},describeAction(n.record.action)+' · '+(n.record.result.ok?'accepted':'refused')),h('pre',{},JSON.stringify(n.record,null,2))));
}
/* ---- the story player: a scenario becomes a tree ------------------------------ */
function startFresh() {
  const sc=SCENARIOS[0];newTree({...newSession(sc.params,sc.config,{inception:[],duplicity:[]}),now:0},'An empty registry. Bring evidence, book a request, then process it.');
  app.story=null;app.punch=null;app.challenge=null;app.pastPunch=false;
}
const CHALLENGES={sweep:{title:'Sweep a live carrier',actor:'sam',goal:'Alice has a live carrier and nobody holds duplicity against her key. Try to book its termination and collect the booking premium.',won:()=>pathTo(app.cursor).map(node).some(n=>n.record?.action?.bookTermination&&n.record.result.ok),why:'A termination booking requires a convicted carrier: a live carrier cannot be booked (Registry.live_cannot_book). There is no owner exit to collect. Conviction needs duplicity at the carrier’s key; if you add that premise to the model evidence table, the premise has changed.'}};
function playChallenge(id){if(id!=='sweep'){startFresh();render();return;}const tree=Backend.playStory(10);tree.cursor=2;adoptTree(tree);app.story=null;app.challenge=CHALLENGES[id];app.actor='sam';render();}

function renderChallenge() {
  const box = $('challenge'); if (!box) return;
  const c = app.challenge; box.hidden = !c; if (!c) return;
  clear(box);
  const won = c.won();
  box.append(h('div', {}, h('b', {}, '★ ' + c.title + ' — '), c.goal, ' ', h('span', { class: 'tiny' }, 'moves so far: ' + pathTo(app.cursor).filter(id => node(id).record).length)));
  box.append(won ? h('div', { class: 'won' }, 'The model was supplied duplicity evidence and the carrier was convicted first.') : h('div', { class: 'tiny' }, 'not yet'));
  box.append(h('details', { open: won || undefined }, h('summary', {}, won ? 'what it bought you' : 'give up: why conviction comes first'), h('div', {}, c.why)));
  if (won && !app.wonShown) { app.wonShown = true; toast('Only a convicted carrier was booked.', 5000); }
}
const _playStory = playStory;
const _playLoadedScenario = playLoadedScenario;
playStory = function(n) {
  adoptTree(_playStory(n));
  app.story = SCENARIOS.find(x => String(x.id) === String(n)) || app.story;
  app.challenge = null; app.pastPunch = false;
  if ($('pots')) $('pots').open = false;
  render();
};
playLoadedScenario = function(sc) {
  adoptTree(_playLoadedScenario(sc));
  app.story = sc; app.challenge = null; app.pastPunch = false;
  if ($('pots')) $('pots').open = false;
  render();
};
window.playLoadedScenario = playLoadedScenario;
function stopPlay() { if (app.playing) { clearInterval(app.playing); app.playing = null; } }
function togglePlay() {
  if (app.playing) { stopPlay(); renderPlaybar(); return; }
  // ▶ stops on the punchline and holds; from the punchline on, it plays the coda
  app.pastPunch = app.punch === null || pathTo(app.cursor).includes(app.punch);
  const tickPlay = () => {
    const nx = nextOf(app.cursor);
    if (nx === null) { stopPlay(); renderPlaybar(); return; }
    goTo(nx); followScene();
    const atPunch = nx === app.punch && !app.pastPunch;
    if (atPunch || nextOf(nx) === null) { stopPlay(); renderPlaybar(); if (atPunch) toast('★ ' + (hitLine(node(nx)) || node(nx).say), 5000); }
  };
  app.playing = setInterval(tickPlay, 1500);
  tickPlay();
}

/* ---- self-test ---------------------------------------------------------------- */
function runSelftest() {
  const rows=[],row=(what,ok,detail='')=>rows.push({what,ok,detail});
  for(const sc of SCENARIOS){const r=checkScenario(sc);row('story '+sc.id,r.ok,r.problems.join('; '));}
  const c=checkCorpus(REGISTRY_LEAN_TRACES_V3);row('complete Lean corpus',c.ok,c.cells+' cells '+c.reasons.join('; '));
  try{playStory(12);$('hist-next').click();$('hist-next').click();$('hist-next').click();row('conviction control',ckptOf(cur(),11)?.st==='terminationPending');$('hist-prev').click();row('tree rewind',ckptOf(cur(),11)?.st==='live');const fork=app.nodes.find(n=>n.branch);goTo(fork.id);row('fork selection',app.cursor===fork.id);row('drawn tree',document.querySelectorAll('#tree .node').length===app.nodes.length);row('theorem observations',!document.querySelector('#ledger .broken'));row('scene',$('scene').querySelectorAll('[data-obj]').length>=10);toggleTheme();toggleTheme();}catch(error){row('controls',false,error.message);}
  const ok=rows.every(r=>r.ok);document.title=(ok?'PASS':'FAIL')+' — registry simulator selftest';$('selftest-out').hidden=false;$('selftest-out').textContent=rows.map(r=>(r.ok?'PASS ':'FAIL ')+r.what+' '+r.detail).join('\n');window.__selftest={ok,rows};return ok;
}


/* ---- wiring ---------------------------------------------------------------- */
function initTheme() {
  let t = null;
  try { t = localStorage.getItem('registry-sim-theme'); } catch (e) { t = null; }
  if (t === 'dark' || t === 'light') document.documentElement.dataset.theme = t;
}
function toggleTheme() {
  const cur0 = document.documentElement.dataset.theme || (window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const next = cur0 === 'dark' ? 'light' : 'dark';
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem('registry-sim-theme', next); } catch (e) { /* no storage: fine */ }
  renderChart();
}
function dslDiag(ok, msg) {
  const el = $('dsl-diag'); if (!el) return;
  el.textContent = msg || '';
  el.className = 'tiny' + (msg ? (ok ? ' ok' : ' no') : '');
}
function loadScenarioDsl(sourceText, sourceName) {
  const priorNodes = app.nodes, priorCursor = app.cursor, priorStory = app.story, priorPunch = app.punch;
  try {
    assertGrammarVersion('1');
    const doc = parseScenarioDsl(sourceText, sourceName || 'paste');
    if (doc.family !== 'registry') throw new ScenarioDslError(sourceName || 'paste', 1, 1, 'this page plays registry scenarios');
    window.playLoadedScenario(doc.scenario);
    dslDiag(true, 'loaded ' + (sourceName || 'paste'));
  } catch (e) {
    app.nodes = priorNodes; app.cursor = priorCursor; app.story = priorStory; app.punch = priorPunch;
    dslDiag(false, e && e.message ? e.message : String(e));
  }
}
function exportCurrentBranch() {
  const initial=node(0).session,steps=pathTo(app.cursor).map(node).filter(n=>n.record).map(n=>({now:n.session.now??0,actor:'anyone',as:n.who||'You',action:n.record.action,env:n.record.env,expect:{ok:!!n.record.result.ok,...(n.record.result.error?{reason:n.record.result.error}:{}),result:n.record.result},note:n.say||describeAction(n.record.action)}));
  return {wireVersion:3,id:1,slug:'exported-branch',story:'Exported branch',narrative:'A recorded interactive branch; expected results come from this simulator, not a new Lean evaluation.',params:initial.params,config:initial.state.config,plugin:initial.state.config.applicationPolicy,actors:NAMES,env:initial.env,steps,forks:[],expectFinal:cur().state};
}

function exportCurrentBranchDsl() { return scenarioToDsl('registry', exportCurrentBranch()); }
function copyCurrentBranchDsl() {
  const text = exportCurrentBranchDsl();
  if (!navigator.clipboard || typeof navigator.clipboard.writeText !== 'function') {
    dslDiag(false, 'clipboard unavailable');
    throw new Error('clipboard unavailable');
  }
  const p = navigator.clipboard.writeText(text);
  Promise.resolve(p).then(() => dslDiag(true, 'copied branch'), err => dslDiag(false, err && err.message));
  return p;
}
function downloadCurrentBranchDsl() {
  const text = exportCurrentBranchDsl();
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = 'registry-branch.dsl';
  a.click();
  if (typeof URL.revokeObjectURL === 'function') URL.revokeObjectURL(url);
  dslDiag(true, 'downloaded branch');
}
function wireDsl() {
  const loadBtn = $('dsl-load'), paste = $('dsl-paste'), file = $('dsl-file');
  if (loadBtn && paste) loadBtn.addEventListener('click', () => loadScenarioDsl(paste.value, 'paste'));
  if (file) file.addEventListener('change', e => {
    const f = e.target.files && e.target.files[0]; if (!f) return;
    const r = new FileReader();
    r.onload = () => loadScenarioDsl(String(r.result), f.name);
    r.readAsText(f);
  });
  if ($('dsl-copy')) $('dsl-copy').addEventListener('click', () => {
    try { Promise.resolve(copyCurrentBranchDsl()).catch(err => dslDiag(false, err && err.message)); }
    catch (err) { dslDiag(false, err && err.message); }
  });
  if ($('dsl-download')) $('dsl-download').addEventListener('click', () => { try { downloadCurrentBranchDsl(); } catch (err) { dslDiag(false, err.message); } });
}
function wire() {
  $('story-picker').addEventListener('change', e => { const v = e.target.value; if (v === '') { startFresh(); render(); } else if (/^c:/.test(v)) playChallenge(v.slice(2)); else playStory(v); });
  $('hist-first').addEventListener('click', () => goTo(0));
  $('hist-prev').addEventListener('click', () => { const p = node(app.cursor).parent; if (p !== null) goTo(p); });
  $('hist-next').addEventListener('click', () => { const nx = nextOf(app.cursor); if (nx !== null) { goTo(nx); followScene(); } });
  $('btn-coda').addEventListener('click', () => { app.pastPunch = true; if (!app.playing) togglePlay(); });
  try { if (typeof IntersectionObserver !== 'undefined') new IntersectionObserver(es => { for (const e of es) $('hud').classList.toggle('on', !e.isIntersecting && window.scrollY > 120); }).observe($('where')); } catch (e) { /* no observer under the minimal DOM */ }
  $('hist-last').addEventListener('click', () => goTo(leafNodeOf(app.cursor)));
  $('btn-play').addEventListener('click', togglePlay);
  $('scrub').addEventListener('input', e => { const path = currentPath(); const id = path[Number(e.target.value)]; if (id !== undefined) goTo(id); });
  $('scrub').addEventListener('change', e => { const path = currentPath(); const id = path[Number(e.target.value)]; if (id !== undefined) goTo(id); });
  $('btn-reset').addEventListener('click', () => { startFresh(); render(); });
  $('btn-theme').addEventListener('click', toggleTheme);
  $('act-submit').addEventListener('click', submitPending);
  $('act-cancel').addEventListener('click', () => { app.pending = null; renderNext(); });
  $('ev-add').addEventListener('click', () => { const n = parseNat($('ev-aid').value); if (n === null) return; app.extraAids = [...(app.extraAids || []), n]; renderEvidence(); });
  $('slot-input').addEventListener('change', e => { const n = parseNat(e.target.value); if (n === null) { $('slot-msg').textContent = 'the proposal slot must be a non-negative whole number'; $('slot-input').value = fmt(cur().now); return; } moveSlot(n); });
  $('slot-plus1').addEventListener('click', () => moveSlot(addNat(cur().now??0,1)));
  $('slot-plusw').addEventListener('click', () => moveSlot(addNat(cur().now??0,cur().state.config.processTime)));
  $('chart-drawer').addEventListener('toggle', renderChart);
  window.addEventListener('resize', renderChart);
  document.addEventListener('keydown', e => {
    if (e.target && /^(input|select|textarea)$/i.test(e.target.tagName)) return;
    if (e.key === 'ArrowRight') { $('hist-next').click(); e.preventDefault(); }
    else if (e.key === 'ArrowLeft') { $('hist-prev').click(); e.preventDefault(); }
    else if (e.key === ' ') { togglePlay(); e.preventDefault(); }
  });
  wireDsl();
}
window.RS = { stepFn, attempt, newSession, checkScenario, checkCorpus, runSelftest, THEOREMS, SCENARIOS, CHALLENGES, app, node, cur, goTo, playStory, playChallenge, startFresh, render, loadScenarioDsl, exportCurrentBranchDsl, copyCurrentBranchDsl, downloadCurrentBranchDsl, assertGrammarVersion, parseScenarioDsl };
window.__registrySim = { get session() { return cur(); }, get story() { return app.story; }, get app() { return app; } };
initTheme();
startFresh();
wire();
{ const m = /[?&]story=(\d+)/.exec(location.search); if (!/[?&]selftest=1/.test(location.search)) playStory(m ? m[1] : 1); }
render();
if (/[?&]selftest=1/.test(location.search)) runSelftest();
