/*
 * checkpoint-simulator-minidom.mjs — a minimal DOM for the page smoke.
 *
 * Just enough browser for checkpoint-simulator.html to load and be driven
 * by the gates with real semantics for what they assert: an HTML parser
 * for the static markup, elements with attributes / classList / dataset /
 * value / disabled / hidden, a selector engine (tag, #id, .class, [attr],
 * [attr="v"], descendant and child combinators, comma lists), bubbling
 * events with listeners, a select whose value tracks its options, a canvas
 * whose 2d context records every call, and a window with location,
 * localStorage, matchMedia and requestAnimationFrame. Scripts run in a vm
 * context whose global is the window. Exceptions thrown by scripts or by
 * listeners are recorded in window.__errors — never swallowed silently.
 *
 * This is not jsdom. Anything the page uses that is not here throws, which
 * is the point: the smoke fails loudly instead of passing on a stub.
 */

import vm from 'node:vm';

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'source', 'track', 'wbr']);
const RAW = new Set(['script', 'style']);

class Event {
  constructor(type, init = {}) {
    this.type = type; this.bubbles = init.bubbles !== false; this.target = null;
    this.currentTarget = null; this.defaultPrevented = false; this._stop = false;
    Object.assign(this, init.detail ? { detail: init.detail } : {});
    if (init.key) this.key = init.key;
  }
  preventDefault() { this.defaultPrevented = true; }
  stopPropagation() { this._stop = true; }
  stopImmediatePropagation() { this._stop = true; }
}

class Node {
  constructor(doc) { this.ownerDocument = doc; this.parentNode = null; this._listeners = new Map(); }
  get parentElement() { return this.parentNode instanceof Element ? this.parentNode : null; }
  addEventListener(t, fn) { if (!this._listeners.has(t)) this._listeners.set(t, []); this._listeners.get(t).push(fn); }
  removeEventListener(t, fn) { const l = this._listeners.get(t); if (l) this._listeners.set(t, l.filter(f => f !== fn)); }
  dispatchEvent(ev) {
    ev.target = ev.target || this;
    let n = this;
    while (n && !ev._stop) {
      ev.currentTarget = n;
      const l = (n._listeners.get(ev.type) || []).slice();
      for (const fn of l) {
        try { fn.call(n, ev); } catch (e) { this.ownerDocument.defaultView.__errors.push(e); }
        if (ev._stop) break;
      }
      const onprop = n['on' + ev.type];
      if (typeof onprop === 'function') { try { onprop.call(n, ev); } catch (e) { this.ownerDocument.defaultView.__errors.push(e); } }
      if (!ev.bubbles) break;
      n = n.parentNode || (n === this.ownerDocument.documentElement ? this.ownerDocument : null)
        || (n === this.ownerDocument ? this.ownerDocument.defaultView : null);
      if (n === this.ownerDocument.defaultView) { // window listeners
        ev.currentTarget = n;
        for (const fn of (n._listeners.get(ev.type) || []).slice()) {
          try { fn.call(n, ev); } catch (e) { n.__errors.push(e); }
        }
        break;
      }
    }
    return !ev.defaultPrevented;
  }
  remove() { if (this.parentNode) this.parentNode.removeChild(this); }
}

class Text extends Node {
  constructor(doc, data) { super(doc); this.nodeType = 3; this.data = String(data); }
  get textContent() { return this.data; }
  set textContent(v) { this.data = String(v); }
  get nodeValue() { return this.data; }
}

class ClassList {
  constructor(el) { this.el = el; }
  _get() { return (this.el.getAttribute('class') || '').split(/\s+/).filter(Boolean); }
  _set(l) { this.el.setAttribute('class', l.join(' ')); }
  add(...cs) { const l = this._get(); for (const c of cs) if (!l.includes(c)) l.push(c); this._set(l); }
  remove(...cs) { this._set(this._get().filter(c => !cs.includes(c))); }
  toggle(c, force) {
    const has = this.contains(c);
    const want = force === undefined ? !has : !!force;
    if (want && !has) this.add(c); if (!want && has) this.remove(c);
    return want;
  }
  contains(c) { return this._get().includes(c); }
  get length() { return this._get().length; }
}

class CanvasContext {
  constructor() { this.calls = 0; }
}
function makeContext() {
  const ctx = new CanvasContext();
  return new Proxy(ctx, {
    get(t, p) {
      if (p in t) return t[p];
      if (p === 'measureText') return s => ({ width: String(s).length * 6 });
      if (p === 'createLinearGradient' || p === 'createRadialGradient') return () => ({ addColorStop() {} });
      if (p === 'getImageData') return () => ({ data: new Uint8ClampedArray(4) });
      if (typeof p === 'string') return (...a) => { t.calls++; return undefined; };
      return undefined;
    },
    set(t, p, v) { t[p] = v; return true; },
  });
}

class Element extends Node {
  constructor(doc, tag) {
    super(doc);
    this.nodeType = 1; this.tagName = tag.toUpperCase(); this.localName = tag.toLowerCase();
    this.attributes = new Map(); this.childNodes = []; this.style = {};
    this._value = undefined; this._checked = false;
    this.classList = new ClassList(this);
    const self = this;
    this.dataset = new Proxy({}, {
      get(_, k) { return self.getAttribute('data-' + kebab(k)) ?? undefined; },
      set(_, k, v) { self.setAttribute('data-' + kebab(k), String(v)); return true; },
      deleteProperty(_, k) { self.removeAttribute('data-' + kebab(k)); return true; },
      has(_, k) { return self.hasAttribute('data-' + kebab(k)); },
      ownKeys() { return [...self.attributes.keys()].filter(a => a.startsWith('data-')).map(a => camel(a.slice(5))); },
      getOwnPropertyDescriptor(_, k) { return self.hasAttribute('data-' + kebab(k)) ? { enumerable: true, configurable: true, value: self.getAttribute('data-' + kebab(k)) } : undefined; },
    });
  }
  // attributes
  getAttribute(n) { return this.attributes.has(n) ? this.attributes.get(n) : null; }
  setAttribute(n, v) { this.attributes.set(n, String(v)); }
  removeAttribute(n) { this.attributes.delete(n); }
  hasAttribute(n) { return this.attributes.has(n); }
  get id() { return this.getAttribute('id') || ''; }
  set id(v) { this.setAttribute('id', v); }
  get className() { return this.getAttribute('class') || ''; }
  set className(v) { this.setAttribute('class', v); }
  get title() { return this.getAttribute('title') || ''; }
  set title(v) { this.setAttribute('title', v); }
  get hidden() { return this.hasAttribute('hidden'); }
  set hidden(v) { if (v) this.setAttribute('hidden', ''); else this.removeAttribute('hidden'); }
  get disabled() { return this.hasAttribute('disabled'); }
  set disabled(v) { if (v) this.setAttribute('disabled', ''); else this.removeAttribute('disabled'); }
  get type() { return this.getAttribute('type') || (this.localName === 'button' ? 'submit' : ''); }
  set type(v) { this.setAttribute('type', v); }
  get name() { return this.getAttribute('name') || ''; }
  get checked() { return this._checked; }
  set checked(v) { this._checked = !!v; }
  get htmlFor() { return this.getAttribute('for') || ''; }
  // value semantics
  get options() { return this.localName === 'select' ? this.querySelectorAll('option') : []; }
  get selectedIndex() {
    if (this.localName !== 'select') return -1;
    const o = this.options; const v = this.value;
    return o.findIndex(x => x.value === v);
  }
  set selectedIndex(i) { const o = this.options; if (o[i]) this.value = o[i].value; }
  get value() {
    if (this.localName === 'option') return this.hasAttribute('value') ? this.getAttribute('value') : this.textContent;
    if (this.localName === 'select') {
      const o = this.options;
      if (this._value !== undefined && o.some(x => x.value === this._value)) return this._value;
      const sel = o.find(x => x.hasAttribute('selected'));
      return sel ? sel.value : (o[0] ? o[0].value : '');
    }
    if (this._value !== undefined) return this._value;
    return this.getAttribute('value') || '';
  }
  set value(v) {
    this._value = String(v);
    if (this.localName === 'select') {
      const o = this.options;
      if (!o.some(x => x.value === this._value)) this._value = '';
    }
  }
  get valueAsNumber() { return Number(this.value); }
  // tree
  get children() { return this.childNodes.filter(n => n instanceof Element); }
  get firstChild() { return this.childNodes[0] || null; }
  get lastChild() { return this.childNodes[this.childNodes.length - 1] || null; }
  get firstElementChild() { return this.children[0] || null; }
  get nextSibling() { const p = this.parentNode; if (!p) return null; const i = p.childNodes.indexOf(this); return p.childNodes[i + 1] || null; }
  get nextElementSibling() { let n = this.nextSibling; while (n && !(n instanceof Element)) n = n.nextSibling; return n; }
  contains(n) { while (n) { if (n === this) return true; n = n.parentNode; } return false; }
  _adopt(n) {
    if (typeof n === 'string' || typeof n === 'number') n = new Text(this.ownerDocument, n);
    if (n instanceof Fragment) { const kids = n.childNodes.slice(); n.childNodes = []; return kids; }
    if (n.parentNode) n.parentNode.removeChild(n);
    return [n];
  }
  appendChild(n) { for (const k of this._adopt(n)) { k.parentNode = this; this.childNodes.push(k); } return n; }
  append(...ns) { for (const n of ns) this.appendChild(n); }
  prepend(...ns) { const kids = ns.flatMap(n => this._adopt(n)); for (const k of kids) k.parentNode = this; this.childNodes.unshift(...kids); }
  insertBefore(n, ref) {
    const kids = this._adopt(n);
    const i = ref ? this.childNodes.indexOf(ref) : this.childNodes.length;
    for (const k of kids) k.parentNode = this;
    this.childNodes.splice(i < 0 ? this.childNodes.length : i, 0, ...kids);
    return n;
  }
  removeChild(n) { const i = this.childNodes.indexOf(n); if (i >= 0) { this.childNodes.splice(i, 1); n.parentNode = null; } return n; }
  replaceChildren(...ns) { for (const c of this.childNodes) c.parentNode = null; this.childNodes = []; this.append(...ns); }
  replaceWith(...ns) { const p = this.parentNode; if (!p) return; const i = p.childNodes.indexOf(this); p.removeChild(this); const kids = ns.flatMap(n => p._adopt(n)); for (const k of kids) k.parentNode = p; p.childNodes.splice(i, 0, ...kids); }
  get textContent() {
    if (RAW.has(this.localName)) return this.childNodes.map(c => c.textContent).join('');
    return this.childNodes.map(c => c.textContent).join('');
  }
  set textContent(v) { this.replaceChildren(); if (v !== '' && v !== null && v !== undefined) this.appendChild(new Text(this.ownerDocument, v)); }
  get innerText() { return this.textContent; }
  set innerText(v) { this.textContent = v; }
  get innerHTML() { return this.childNodes.map(serialize).join(''); }
  set innerHTML(v) { this.replaceChildren(); parseInto(this, String(v), this.ownerDocument); }
  get outerHTML() { return serialize(this); }
  // selectors
  matches(sel) { return parseSelectorList(sel).some(chain => matchChain(this, chain)); }
  closest(sel) { let n = this; while (n instanceof Element) { if (n.matches(sel)) return n; n = n.parentNode; } return null; }
  querySelectorAll(sel) {
    const out = [];
    const walk = n => { for (const c of n.childNodes) if (c instanceof Element) { if (c.matches(sel)) out.push(c); walk(c); } };
    walk(this);
    return out;
  }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  getElementsByTagName(t) { return this.querySelectorAll(t); }
  // layout stubs
  getBoundingClientRect() { return { x: 0, y: 0, top: 0, left: 0, width: 640, height: 240, right: 640, bottom: 240 }; }
  get clientWidth() { return 640; }
  get clientHeight() { return 240; }
  get offsetWidth() { return 640; }
  get offsetHeight() { return 240; }
  get scrollWidth() { return 640; }
  focus() {} blur() {} scrollIntoView() {} click() { this.dispatchEvent(new Event('click')); }
  // canvas
  getContext(kind) {
    if (this.localName !== 'canvas') return null;
    if (!this.__ctx) this.__ctx = makeContext();
    return this.__ctx;
  }
  get width() { return Number(this.getAttribute('width') || 640); }
  set width(v) { this.setAttribute('width', String(v)); }
  get height() { return Number(this.getAttribute('height') || 240); }
  set height(v) { this.setAttribute('height', String(v)); }
}

class Fragment extends Element { constructor(doc) { super(doc, '#fragment'); this.nodeType = 11; } }

const kebab = k => k.replace(/[A-Z]/g, m => '-' + m.toLowerCase());
const camel = k => k.replace(/-([a-z])/g, (_, c) => c.toUpperCase());

function escapeHtml(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function serialize(n) {
  if (n instanceof Text) return escapeHtml(n.data);
  const attrs = [...n.attributes].map(([k, v]) => ` ${k}="${v.replace(/"/g, '&quot;')}"`).join('');
  if (VOID.has(n.localName)) return `<${n.localName}${attrs}>`;
  const inner = RAW.has(n.localName) ? n.childNodes.map(c => c.data).join('') : n.childNodes.map(serialize).join('');
  return `<${n.localName}${attrs}>${inner}</${n.localName}>`;
}

/* --- selectors ---------------------------------------------------------- */

function parseSelectorList(sel) {
  return sel.split(',').map(s => s.trim()).filter(Boolean).map(parseChain);
}
function parseChain(s) {
  // tokens separated by combinators ' ' or '>'
  const parts = [];
  let cur = '', comb = ' ';
  const toks = s.replace(/\s*>\s*/g, ' > ').split(/\s+/).filter(Boolean);
  for (const t of toks) {
    if (t === '>') { comb = '>'; continue; }
    parts.push({ comb, compound: parseCompound(t) });
    comb = ' ';
  }
  return parts;
}
function parseCompound(t) {
  const out = { tag: null, id: null, classes: [], attrs: [], not: [] };
  const re = /(\*|[a-zA-Z][\w-]*)|#([\w-]+)|\.([\w-]+)|\[([\w-]+)(?:=(?:"([^"]*)"|'([^']*)'|([^\]]*)))?\]|:not\(([^)]*)\)/g;
  let m;
  while ((m = re.exec(t))) {
    if (m[1]) out.tag = m[1] === '*' ? null : m[1].toLowerCase();
    else if (m[2]) out.id = m[2];
    else if (m[3]) out.classes.push(m[3]);
    else if (m[4]) out.attrs.push({ name: m[4], value: m[5] ?? m[6] ?? m[7] ?? null });
    else if (m[8]) out.not.push(parseCompound(m[8]));
  }
  return out;
}
function matchCompound(el, c) {
  if (c.tag && el.localName !== c.tag) return false;
  if (c.id && el.id !== c.id) return false;
  if (c.classes.some(k => !el.classList.contains(k))) return false;
  for (const a of c.attrs) {
    if (!el.hasAttribute(a.name)) return false;
    if (a.value !== null && el.getAttribute(a.name) !== a.value) return false;
  }
  if (c.not.some(n => matchCompound(el, n))) return false;
  return true;
}
function matchChain(el, chain) {
  let i = chain.length - 1;
  if (!matchCompound(el, chain[i].compound)) return false;
  let n = el;
  while (i > 0) {
    const comb = chain[i].comb;
    i--;
    if (comb === '>') {
      n = n.parentNode;
      if (!(n instanceof Element) || !matchCompound(n, chain[i].compound)) return false;
    } else {
      n = n.parentNode;
      while (n instanceof Element && !matchCompound(n, chain[i].compound)) n = n.parentNode;
      if (!(n instanceof Element)) return false;
    }
  }
  return true;
}

/* --- parser ------------------------------------------------------------- */

function decode(s) {
  return s.replace(/&(amp|lt|gt|quot|#39|nbsp|#(\d+)|#x([0-9a-f]+));/gi, (m, k, d, x) => {
    if (k === 'amp') return '&'; if (k === 'lt') return '<'; if (k === 'gt') return '>';
    if (k === 'quot') return '"'; if (k === '#39') return "'"; if (k === 'nbsp') return ' ';
    if (d) return String.fromCodePoint(Number(d)); if (x) return String.fromCodePoint(parseInt(x, 16));
    return m;
  });
}

function parseInto(root, html, doc) {
  let i = 0; const n = html.length; let cur = root;
  const text = s => { if (s) cur.appendChild(new Text(doc, decode(s))); };
  while (i < n) {
    const lt = html.indexOf('<', i);
    if (lt < 0) { text(html.slice(i)); break; }
    text(html.slice(i, lt));
    if (html.startsWith('<!--', lt)) { const e = html.indexOf('-->', lt); i = e < 0 ? n : e + 3; continue; }
    if (html.startsWith('<!', lt)) { const e = html.indexOf('>', lt); i = e < 0 ? n : e + 1; continue; }
    if (html[lt + 1] === '/') {
      const e = html.indexOf('>', lt); const name = html.slice(lt + 2, e).trim().toLowerCase();
      let p = cur; while (p && p !== root && p.localName !== name) p = p.parentNode;
      if (p && p !== root) cur = p.parentNode;
      else if (p === root && root.localName === name) cur = root.parentNode || root;
      i = e + 1; continue;
    }
    // open tag
    let j = lt + 1; while (j < n && /[\w-]/.test(html[j])) j++;
    const name = html.slice(lt + 1, j).toLowerCase();
    const el = new Element(doc, name);
    // attributes
    while (j < n) {
      while (j < n && /\s/.test(html[j])) j++;
      if (html[j] === '>' || html.startsWith('/>', j)) break;
      let k = j; while (k < n && !/[\s=>\/]/.test(html[k])) k++;
      const an = html.slice(j, k); j = k;
      while (j < n && /\s/.test(html[j])) j++;
      let av = '';
      if (html[j] === '=') {
        j++; while (j < n && /\s/.test(html[j])) j++;
        const q = html[j];
        if (q === '"' || q === "'") { const e = html.indexOf(q, j + 1); av = html.slice(j + 1, e); j = e + 1; }
        else { let e = j; while (e < n && !/[\s>]/.test(html[e])) e++; av = html.slice(j, e); j = e; }
      }
      if (an) el.setAttribute(an, decode(av));
    }
    const selfClose = html.startsWith('/>', j);
    j = html.indexOf('>', j) + 1;
    cur.appendChild(el);
    if (RAW.has(name)) {
      const close = html.toLowerCase().indexOf('</' + name, j);
      el.appendChild(new Text(doc, html.slice(j, close < 0 ? n : close)));
      i = close < 0 ? n : html.indexOf('>', close) + 1;
      continue;
    }
    if (!selfClose && !VOID.has(name)) cur = el;
    i = j;
  }
}

/* --- document and window ------------------------------------------------ */

class Document extends Node {
  constructor(win) {
    super(null); this.ownerDocument = this; this.defaultView = win; this.nodeType = 9;
    this.documentElement = new Element(this, 'html'); this.documentElement.parentNode = null;
    this.readyState = 'loading';
  }
  createElement(t) { return new Element(this, t); }
  createElementNS(ns, t) { return new Element(this, t); }
  createTextNode(s) { return new Text(this, s); }
  createDocumentFragment() { return new Fragment(this); }
  getElementById(id) { return this.documentElement.querySelector('#' + id); }
  querySelector(s) { return this.documentElement.matches(s) ? this.documentElement : this.documentElement.querySelector(s); }
  querySelectorAll(s) { return this.documentElement.querySelectorAll(s); }
  get head() { return this.documentElement.querySelector('head'); }
  get body() { return this.documentElement.querySelector('body'); }
  get title() { const t = this.documentElement.querySelector('title'); return t ? t.textContent : ''; }
  set title(v) { let t = this.documentElement.querySelector('title'); if (!t) { t = this.createElement('title'); (this.head || this.documentElement).appendChild(t); } t.textContent = v; }
  get activeElement() { return this.body; }
}

export function createWindow(html, opts = {}) {
  const win = { __errors: [], _listeners: new Map() };
  const doc = new Document(win);
  parseInto(doc.documentElement, html, doc);
  // a page written without <html>/<head>/<body>: wrap what came out
  if (!doc.body) {
    const body = doc.createElement('body');
    const kids = doc.documentElement.childNodes.slice();
    for (const k of kids) if (!(k instanceof Element && ['head', 'title', 'style', 'meta', 'link'].includes(k.localName))) body.appendChild(k);
    doc.documentElement.appendChild(body);
  }
  if (!doc.head) doc.documentElement.prepend(doc.createElement('head'));
  const store = new Map();
  Object.assign(win, {
    document: doc,
    location: { search: opts.search || '', hash: '', href: 'file:///checkpoint-simulator.html' + (opts.search || ''), pathname: '/checkpoint-simulator.html', protocol: 'file:' },
    navigator: { userAgent: 'minidom', language: 'en' },
    localStorage: {
      getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)),
      removeItem: k => store.delete(k), clear: () => store.clear(),
    },
    matchMedia: q => ({ matches: false, media: q, addEventListener() {}, removeEventListener() {}, addListener() {} }),
    requestAnimationFrame: cb => { try { cb(0); } catch (e) { win.__errors.push(e); } return 1; },
    cancelAnimationFrame() {},
    setTimeout: (cb) => { try { cb(); } catch (e) { win.__errors.push(e); } return 1; },
    clearTimeout() {}, setInterval: () => 1, clearInterval() {},
    devicePixelRatio: 1, innerWidth: 1280, innerHeight: 800,
    performance: { now: () => 0 },
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
    scrollTo() {},
    addEventListener(t, fn) { if (!win._listeners.has(t)) win._listeners.set(t, []); win._listeners.get(t).push(fn); },
    removeEventListener(t, fn) { const l = win._listeners.get(t); if (l) win._listeners.set(t, l.filter(f => f !== fn)); },
    dispatchEvent(ev) { ev.target = ev.target || win; for (const fn of (win._listeners.get(ev.type) || []).slice()) { try { fn.call(win, ev); } catch (e) { win.__errors.push(e); } } return true; },
    Event, CustomEvent: Event, KeyboardEvent: Event, MouseEvent: Event,
    makeEvent: (t, init) => new Event(t, init),
    console, URLSearchParams, JSON, Math, Date, Number, String, Array, Object, Map, Set, Promise, Error, TypeError,
    RangeError, parseInt, parseFloat, isFinite, isNaN, Symbol, Reflect, Proxy, structuredClone,
    Uint8ClampedArray, Uint8Array, Float64Array, Intl, encodeURIComponent, decodeURIComponent,
  });
  win.window = win; win.self = win; win.globalThis = win;
  vm.createContext(win);
  for (const s of doc.querySelectorAll('script')) {
    if (s.hasAttribute('src')) throw new Error('external script: ' + s.getAttribute('src'));
    try { vm.runInContext(s.textContent, win, { filename: 'checkpoint-simulator.html#script' }); }
    catch (e) { win.__errors.push(e); }
  }
  doc.readyState = 'complete';
  doc.dispatchEvent(new Event('DOMContentLoaded', { bubbles: false }));
  win.dispatchEvent(new Event('load', { bubbles: false }));
  return win;
}
