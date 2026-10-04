'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('@playwright/test');
const {allowedBrowserRequest} = require('./network-policy.cjs');
const connections = new Map();
const evidence = process.env.ATTENDUS_BROWSER_EVIDENCE;
if (!evidence || process.env.GCLOUD_PROJECT !== 'demo-attendus-admin') throw new Error('An isolated evidence directory and demo project are required.');
fs.mkdirSync(evidence, {recursive: true});
const log = (entry) => fs.appendFileSync(path.join(evidence, 'network-policy.jsonl'), JSON.stringify(entry) + '\n');
const server = http.createServer(async (req, res) => {
  try {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const response = await fetch(`http://127.0.0.1:4445${req.url}`, {
      method: req.method, headers: {'content-type': 'application/json'},
      ...(chunks.length ? {body: Buffer.concat(chunks)} : {}),
    });
    const text = await response.text();
    if (req.method === 'POST' && req.url === '/session' && response.ok) {
      const session = JSON.parse(text).value;
      const address = session?.capabilities?.['goog:chromeOptions']?.debuggerAddress;
      if (!/^localhost:\d+$|^127\.0\.0\.1:\d+$/.test(address || '')) throw new Error('Chrome did not expose a local CDP endpoint; refusing an unisolated browser.');
      const browser = await chromium.connectOverCDP(`http://${address}`);
      const context = browser.contexts()[0];
      if (!context) throw new Error('Missing browser context.');
      const observe = (page) => page.on('console', (message) => {
        const value = message.text();
        if (!/^\d{2}:\d{2} \+\d+/.test(value) && !value.includes('EXCEPTION CAUGHT BY')) return;
        const safe = value.replace(/https?:\/\/[^\s)]+/g, (address) => {
          try {const parsed = new URL(address); return parsed.origin + parsed.pathname;} catch {return '[url]';}
        }).replace(/eyJ[A-Za-z0-9_.-]+/g, '[token]');
        fs.appendFileSync(path.join(evidence, 'test-progress.jsonl'), JSON.stringify({message: safe}) + '\n');
      });
      for (const page of context.pages()) observe(page);
      context.on('page', observe);
      await context.route('**/*', async (route) => {
        const request = route.request();
        const url = new URL(request.url());
        const allowed = allowedBrowserRequest(request.url(), request.method());
        if (!allowed) log({action: 'blocked', method: request.method(), origin: url.origin, path: url.pathname});
        return allowed ? route.continue() : route.abort('blockedbyclient');
      });
      await context.routeWebSocket('**/*', (socket) => {
        if (allowedBrowserRequest(socket.url())) socket.connectToServer();
        else {log({action: 'blocked-websocket', origin: new URL(socket.url()).origin}); socket.close();}
      });
      connections.set(session.sessionId, browser);
      log({action: 'isolation-installed', sessionId: session.sessionId});
    }
    res.writeHead(response.status, {'content-type': 'application/json'});
    res.end(text);
  } catch (error) {
    log({action: 'isolation-error', message: error.message});
    res.writeHead(500, {'content-type': 'application/json'});
    res.end(JSON.stringify({value: {error: 'session not created', message: error.message}}));
  }
});
server.listen(4444, '127.0.0.1');
process.on('SIGTERM', () => server.close(() => process.exit(0)));
