'use strict';
// Read-only live-provider diagnostic. Never persist tokens, headers, bodies, or user data.
const {chromium} = require('@playwright/test');
(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    const report = {origin: 'https://attendus-staging.web.app', exchanges: [], calls: [], failures: [], appCheckErrors: []};
    page.on('response', async r => {
      const u = new URL(r.url());
      if (u.hostname.endsWith('firebaseappcheck.googleapis.com')) { const entry={path:u.pathname,status:r.status()}; report.exchanges.push(entry); if(r.status()>=400) {try {const body=await r.json(); entry.error={status:body.error?.status,message:body.error?.message};} catch {} } }
      if (u.hostname === 'us-central1-attendus-staging.cloudfunctions.net') report.calls.push({path: u.pathname, status: r.status()});
      if (u.hostname === 'www.google.com' && u.pathname.startsWith('/recaptcha/')) console.log(JSON.stringify({providerPath: u.pathname, status: r.status()}));
    });
    page.on('requestfailed', r => {
      const u = new URL(r.url());
      if (/recaptcha|firebaseappcheck/.test(u.hostname + u.pathname)) report.failures.push({host:u.hostname,path:u.pathname,error:r.failure()?.errorText});
    });
    page.on('console', m => { const match=m.text().match(/appCheck\/[a-z-]+/); if(match) report.appCheckErrors.push(match[0]); });
    await page.goto(report.origin + '/app/discover', {waitUntil:'domcontentloaded'});
    await page.waitForTimeout(65000);
    report.frames = page.frames().map(f => {try {return new URL(f.url()).hostname;} catch {return 'blank';}});
    console.log(JSON.stringify(report, null, 2));
    if (!report.exchanges.some(e=>e.status === 200)) process.exitCode=1;
  } finally { await browser.close(); }
})().catch(e=>{console.error(e.name);process.exitCode=1;});
