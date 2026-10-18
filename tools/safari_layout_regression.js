'use strict';
// Branded Safari regression with loopback HTML only. No Firebase credentials,
// production requests, or patched WebKit are involved.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const {spawn, execFileSync} = require('node:child_process');
const {htmlResponsiveProbe} = require('./web_release_producers/safari');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  assert.equal(process.platform, 'darwin');
  const server = http.createServer((req, res) => {
    res.setHeader('Content-Type', 'text/html');
    res.end('<!doctype html><html><head><style>body{font:16px Arial;margin:16px}h1{font-size:20px}dialog{width:350px}input,button{font:inherit;max-width:100%;box-sizing:border-box}</style></head><body><h1>Controlled heading</h1><div>Inherited text</div><button id="open">Open dialog</button><script>document.querySelector("#open").onclick=()=>{document.body.insertAdjacentHTML("beforeend",`<dialog><label>Name<input></label><button>Close</button></dialog>`);document.querySelector("dialog").showModal()};</script></body></html>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  execFileSync('sudo', ['-n', '/usr/bin/safaridriver', '--enable']);
  const child = spawn('/usr/bin/safaridriver', ['--port', '4446'], {stdio: 'ignore'});
  let session; const results = {observedAt:new Date().toISOString()};
  async function request(route, data, method = data === undefined ? 'GET' : 'POST') {
    const res = await fetch('http://127.0.0.1:4446'+route, {method,headers:{'Content-Type':'application/json'},...(data===undefined?{}:{body:JSON.stringify(data)}),signal:AbortSignal.timeout(30000)});
    const body=await res.json();assert.equal(res.ok,true,JSON.stringify(body));return body.value;
  }
  const execute = fn => request(`/session/${session}/execute/sync`, {script:`return (${fn.toString()})();`,args:[]});
  try {
    for(let n=0;n<50;n++){try{if((await request('/status')).ready)break;}catch{}await delay(100);}
    const started=await request('/session',{capabilities:{alwaysMatch:{browserName:'safari'}}});session=started.sessionId;results.capabilities=started.capabilities;
    assert.equal(started.capabilities.browserName.toLowerCase(),'safari');
    await request(`/session/${session}/url`,{url:`http://127.0.0.1:${server.address().port}/`});
    results.page=await execute(htmlResponsiveProbe);
    await execute(()=>document.querySelector('#open').click());
    results.dialog=await execute(htmlResponsiveProbe);
    results.repeated=await execute(htmlResponsiveProbe);
    for(const result of [results.page,results.dialog,results.repeated])assert.equal(result.textIs200Percent,true);
    for(const result of [results.dialog,results.repeated]){
      assert.equal(result.samples.find(s=>s.tag==='input').before,16);
      assert.equal(result.samples.find(s=>s.tag==='h1').before,20);
      assert.equal(result.controlsFit,true);
    }
  } finally {
    fs.mkdirSync('build',{recursive:true});fs.writeFileSync('build/safari-layout-regression.json',JSON.stringify(results,null,2));
    if(session)await request(`/session/${session}`,undefined,'DELETE');child.kill('SIGTERM');await new Promise(resolve=>server.close(resolve));
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
