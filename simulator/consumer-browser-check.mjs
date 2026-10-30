#!/usr/bin/env node
/* Supply a matched Playwright module and browser installation in the runner.
 * The shipped page is exercised through DOM controls, not a second UI model. */
import fs from 'node:fs';import path from 'node:path';import http from 'node:http';import assert from 'node:assert/strict';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE||'playwright');
const root=path.resolve(import.meta.dirname,'..'),out=process.argv[2];if(!out)throw Error('screenshot directory required');fs.mkdirSync(out,{recursive:true});
const server=http.createServer((req,res)=>{try{const file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));if(!file.startsWith(root+'/'))throw Error('path');res.setHeader('Content-Type',file.endsWith('.html')?'text/html':file.endsWith('.js')?'text/javascript':'application/octet-stream');res.end(fs.readFileSync(file));}catch{res.statusCode=404;res.end('missing');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:"chromium",headless:true,args:['--no-sandbox'],...(process.env.CHROMIUM_EXECUTABLE?{executablePath:process.env.CHROMIUM_EXECUTABLE}:{})});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(`http://127.0.0.1:${server.address().port}/simulator/checkpoint-simulator.html?story=11`);await page.waitForFunction(()=>window.CKC);
 assert.equal(await page.locator('#consumer-player').getAttribute('open'),'');
 const replay=await page.evaluate(()=>CKC.checkCorpus(CKC.corpus));assert.equal(replay.queries,51);
 for(let i=0;i<19;i++){
  const observed=await page.evaluate(()=>CKC.snapshot());assert.equal(observed.cursor,i);assert.deepEqual(observed.result,await page.evaluate(i=>CKC.corpus.journey[i].consumer.result,i));
  if(i<18)await page.locator('#consumer-next').click();
 }
 assert.match(await page.locator('#consumer-story').textContent(),/burns the active asset/);
 await page.locator('#consumer-prev').click();assert.equal((await page.evaluate(()=>CKC.snapshot())).cursor,17);
 for(const name of await page.locator('#consumer-case option').evaluateAll(xs=>xs.map(x=>x.value).filter(Boolean))){
  await page.locator('#consumer-case').selectOption(name);
  const s=await page.evaluate(()=>CKC.snapshot());assert.equal(s.field,name);assert.deepEqual(s.result,await page.evaluate(n=>CKC.corpus.fields.find(c=>c.name===n).result,name));
 }
 await page.locator('#consumer-case').selectOption('positive-anchor');
 const context=await page.locator('#consumer-context').textContent();
 await page.locator('#consumer-holding').evaluate(el=>{el.closest('details').open=true;});
 const q=await page.evaluate(()=>CKC.snapshot().query);q.holding.assets[0][1]=2;
 await page.locator('#consumer-holding').fill(JSON.stringify(q.holding));await page.locator('#consumer-try').click();
 assert.match(await page.locator('#consumer-result').textContent(),/refuses: quantity/);assert.equal(await page.locator('#consumer-context').textContent(),context);
 await page.locator('#consumer-holding').evaluate(el=>{el.closest('details').open=false;});
 await page.locator('#consumer-reset').click();await page.locator('#consumer-next').click();
 for(const [size,width,height]of [['desktop',1440,1000],['phone',390,844]]){
  await page.setViewportSize({width,height});
  for(const theme of ['light','dark']){
   await page.evaluate(t=>document.documentElement.setAttribute('data-theme',t),theme);
   await page.evaluate(()=>window.scrollTo(0,0));
   if(size==='phone')await page.screenshot({path:path.join(out,`${size}-${theme}.png`)});
   else await page.locator('#consumer-player').screenshot({path:path.join(out,`${size}-${theme}.png`)});
   const overflow=await page.locator('#consumer-player').evaluate(e=>e.scrollWidth>e.clientWidth+2);assert.equal(overflow,false,`${size} panel overflow`);
  }
 }
 assert.equal(await page.locator('#consumer-properties').evaluate(e=>e.textContent.split('\n').length),26);assert.deepEqual(errors,[]);
 console.log(JSON.stringify({pageReplay:replay,journeyControls:19,candidateControls:32,editedHolding:true,fixedContext:true,themes:2,viewports:2,pageErrors:errors}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
