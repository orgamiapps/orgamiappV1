const {chromium, expect} = require('@playwright/test');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
(async () => {
 const root = path.resolve(__dirname, '../../build/qr-share-preview');
 const out = path.resolve(__dirname, '../../build/qr-share-evidence');
 fs.mkdirSync(out, {recursive:true});
 const types = {'.js':'text/javascript','.html':'text/html','.json':'application/json','.wasm':'application/wasm','.ttf':'font/ttf'};
 const server = http.createServer((req,res) => {
  const pathname = new URL(req.url,'http://localhost').pathname;
  if(pathname === '/') { res.setHeader('Content-Type','text/html'); res.end('<!doctype html><html><head><base href="/"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head><body><script src="flutter_bootstrap.js"></script></body></html>'); return; }
  const file = path.resolve(root,'.'+pathname);
  if(!file.startsWith(root+path.sep)||!fs.existsSync(file)) {res.writeHead(404);res.end();return;}
  res.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');
  if(pathname==='/flutter_bootstrap.js') res.end(fs.readFileSync(file,'utf8').replace('} : {},','} : {canvasKitBaseUrl: "/canvaskit/"},'));
  else fs.createReadStream(file).pipe(res);
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser = await chromium.launch({headless:true});
 const summary=[];
 try {
 for(const [name,viewport] of [['desktop',{width:1440,height:1000}],['phone',{width:390,height:844}]]) {
  const context = await browser.newContext({viewport, permissions:['clipboard-read','clipboard-write']});
  await context.route('https://accounts.google.com/gsi/client',r=>r.fulfill({body:'',contentType:'text/javascript'}));
  const page = await context.newPage();
  const errors=[];page.on('pageerror', e=>errors.push(e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.getByRole('button',{name:'Share event QR',exact:true}).click({timeout:60000});
  const copy = page.getByRole('button',{name:'Copy image',exact:true});
  await expect(copy).toBeEnabled({timeout:30000});
  await page.screenshot({path:path.join(out,`${name}-card.png`)});
  await copy.click();
  await expect(page.getByText('Image copied. Paste it into your message or document.',{exact:true}).first()).toBeAttached();
  const clipboardTypes = await page.evaluate(async ()=>(await navigator.clipboard.read())[0].types);
  assert(clipboardTypes.includes('image/png'));
  for(const [format,label] of [['card',null],['qrOnly','QR only']]) {
   if(label) await page.getByText(label,{exact:true}).click();
   const downloadPromise=page.waitForEvent('download');
   await page.getByRole('button',{name:'Save image',exact:true}).click();
   const download=await downloadPromise;
   assert(download.suggestedFilename().endsWith('.png'));
   await download.saveAs(path.join(out,`${name}-${format}-download.png`));
  }
  await page.getByRole('button',{name:'Copy link',exact:true}).click();
  assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),'https://attendus.app/event/qr-share-fixture');
  // Deterministic browser adapter coverage. These cases do not claim OS delivery.
  await page.evaluate(()=>{Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>false});});
  await page.getByRole('button',{name:'Share image',exact:true}).click();
  await expect(page.getByText(/Image sharing is unavailable in this browser/).first()).toBeAttached();
  const popupPromise=page.waitForEvent('popup');
  await page.getByRole('button',{name:'Open image to save manually',exact:true}).click();
  const popup=await popupPromise;await popup.waitForLoadState();
  assert(popup.url().startsWith('blob:')); await popup.close();
  await page.evaluate(()=>{
   Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});
   Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{window.lastQrShare={name:data.files[0].name,type:data.files[0].type,text:data.text};}});
  });
  await page.getByRole('button',{name:'Share image',exact:true}).click();
  await expect(page.getByText('Finish sharing in your selected app.',{exact:true}).first()).toBeAttached();
  const shared=await page.evaluate(()=>window.lastQrShare);
  assert.equal(shared.type,'image/png'); assert(shared.text.includes('https://attendus.app/event/qr-share-fixture'));
  await page.evaluate(()=>{Object.defineProperty(navigator,'share',{configurable:true,value:async()=>{throw new DOMException('Cancelled','AbortError');}});});
  await page.getByRole('button',{name:'Share image',exact:true}).click();
  await expect(copy).toBeEnabled();
  await expect(page.getByText(/Could not share the image/)).toHaveCount(0);
  await page.evaluate(()=>{Object.defineProperty(navigator.clipboard,'write',{configurable:true,value:async()=>{throw new DOMException('Denied','NotAllowedError');}});});
  await copy.click();
  await expect(page.getByText(/Image copying is unavailable or was blocked/).first()).toBeAttached();
  await page.screenshot({path:path.join(out,`${name}-fallback.png`)});
  await page.getByRole('button',{name:'Close sharing',exact:true}).click();
  await expect(page.getByRole('button',{name:'Share event QR',exact:true})).toBeVisible();
  assert.deepEqual(errors,[]);
  summary.push({viewport:name,clipboard:'real PNG and link verified',downloads:'both PNG formats',share:'adapter success/cancellation/unsupported verified; OS delivery unverified',errors});
  await context.close();
 }
 fs.writeFileSync(path.join(out,'browser-results.json'),JSON.stringify(summary,null,2));
 console.log(JSON.stringify(summary,null,2));
 } finally {await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
