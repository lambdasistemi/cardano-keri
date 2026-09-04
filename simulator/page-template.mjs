#!/usr/bin/env node
/*
 * page-template.mjs — the page template of this skill is derived from a
 * reference instance, never written by hand, so the next simulator starts
 * from exactly the page the last one shipped: the same CSS, the same
 * element ids, the same panels in the same order, the same tree, play bar,
 * where-strip, glossary, next-moves panel, scene, lamps and drawers.
 *
 *   node page-template.mjs extract <instance.html> <assets-dir>
 *       writes <assets-dir>/page-template.html   the page with its data blocks emptied
 *              <assets-dir>/page.css             the <style> block, verbatim
 *              <assets-dir>/page-skeleton.html   the <body> markup before the <script>: the element contract
 *              <assets-dir>/page-ids.txt         every id= in the skeleton, one per line
 *   node page-template.mjs check <instance.html> <assets-dir>
 *       exit 1 when the instance's CSS, skeleton or template differ from the
 *       stored ones (prints a line per drifted file and the first differing line)
 *   node page-template.mjs start <assets-dir> <new-instance.html>
 *       copies the template to a new page; the data blocks are empty markers
 *       the instance's build script fills (@@CORE:<id>@@, @@SCENARIOS@@, @@CORPUS@@)
 *
 * The data blocks are the machine: the core slices the build inlines, the
 * scenarios and the corpus. Everything else in the template is page — the
 * part a new machine ports (see references/page.md, "Porting the template").
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const [mode, a, b] = process.argv.slice(2);
const usage = () => { console.error('usage: page-template.mjs extract|check <instance.html> <assets-dir> | start <assets-dir> <new.html>'); process.exit(2); };
if (!mode || !a || !b) usage();

const between = (text, open, close, what) => {
  const i = text.indexOf(open), j = text.indexOf(close, i + open.length);
  if (i < 0 || j < 0) throw new Error(`no ${what} block (${open} … ${close})`);
  return text.slice(i + open.length, j);
};
// empty every data block to its markers
function templateOf(page) {
  let out = page;
  const empties = [];
  for (const m of page.matchAll(/\/\* @@CORE:([a-z-]+)@@ \*\//g)) empties.push(m[1]);
  for (const id of empties) {
    const re = new RegExp(`/\\* @@CORE:${id}@@ \\*/\\n[\\s\\S]*?/\\* @@CORE:${id}:END@@ \\*/`);
    if (!re.test(out)) throw new Error(`slice ${id} has no closing marker`);
    out = out.replace(re, () => `/* @@CORE:${id}@@ */\n/* @@CORE:${id}:END@@ */`);
  }
  for (const blk of ['SCENARIOS', 'CORPUS']) {
    const re = new RegExp(`/\\* @@${blk}@@ \\*/\\n[\\s\\S]*?/\\* @@${blk}:END@@ \\*/`);
    if (!re.test(out)) throw new Error(`no @@${blk}@@ block`);
    out = out.replace(re, () => `/* @@${blk}@@ */\n/* @@${blk}:END@@ */`);
  }
  return out;
}
function derive(page) {
  const css = between(page, '<style>\n', '</style>', 'style');
  const skeleton = between(page, '<body>\n', '<script>', 'body');
  const ids = [...skeleton.matchAll(/\sid="([^"]+)"/g)].map(m => m[1]);
  return { 'page-template.html': templateOf(page), 'page.css': css, 'page-skeleton.html': skeleton, 'page-ids.txt': ids.join('\n') + '\n' };
}
const firstDiff = (x, y) => { const xs = x.split('\n'), ys = y.split('\n'); for (let i = 0; i < Math.max(xs.length, ys.length); i++) if (xs[i] !== ys[i]) return `line ${i + 1}: ${JSON.stringify((xs[i] || '').slice(0, 80))} vs ${JSON.stringify((ys[i] || '').slice(0, 80))}`; return ''; };

if (mode === 'extract') {
  const files = derive(readFileSync(a, 'utf8'));
  mkdirSync(b, { recursive: true });
  for (const [n, t] of Object.entries(files)) writeFileSync(join(b, n), t);
  console.log(`extracted ${Object.keys(files).join(', ')} from ${a} into ${b}`);
} else if (mode === 'check') {
  const files = derive(readFileSync(a, 'utf8'));
  let drift = 0;
  for (const [n, t] of Object.entries(files)) {
    const p = join(b, n);
    if (!existsSync(p)) { console.log(`MISSING ${p}`); drift++; continue; }
    const stored = readFileSync(p, 'utf8');
    if (stored !== t) { console.log(`DRIFT ${n}: ${firstDiff(stored, t)}`); drift++; }
  }
  console.log(drift ? `RED: ${drift} template file(s) differ from ${a}` : `GREEN: ${a} matches the template in ${b}`);
  process.exit(drift ? 1 : 0);
} else if (mode === 'start') {
  const t = readFileSync(join(a, 'page-template.html'), 'utf8');
  if (existsSync(b)) { console.error(`${b} exists; refusing to overwrite`); process.exit(1); }
  writeFileSync(b, t);
  console.log(`${b} started from the template; fill the data blocks with the build script and port the page-level functions listed in references/page.md`);
} else usage();
