import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { createFixtureRecord } from './records.js';

const client = path.resolve(process.env.PROSPECTING_CLIENT_ROOT || '../influence-client');
const requireClient = createRequire(path.join(client, 'package.json'));
const { Prospecting } = requireClient('@influenceth/sdk');
const { chromium } = requireClient('playwright');
const assets = path.join(client, 'public/prospecting-proofs');
const manifest = JSON.parse(fs.readFileSync(path.join(assets, 'manifest.json'), 'utf8'));
const recordFor = n => createFixtureRecord(Prospecting, n);
const packetFor = n => Prospecting.getProofPacket(recordFor(n));

test('the actual client worker proves multiple campaign lengths using one verified asset family', { timeout: 180000 }, async () => {
  assert.equal(Prospecting.CIRCUIT, 'fieldwork-r7-volume150-p10-v1');
  assert.equal(manifest.circuit, Prospecting.CIRCUIT);
  const requestedKeys = new Set();
  const files = new Map(['library', 'wasm', 'zkey', 'vk'].map(name => [`/proofs/${manifest[name].file}`, path.join(assets, manifest[name].file)]));
  files.set('/proofs/manifest.json', path.join(assets, 'manifest.json'));
  files.set('/worker.js', path.join(client, 'public/prospecting-prover.worker.js'));
  const server = createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/') { res.end('<!doctype html><title>Client proof worker integration</title>'); return; }
    const file = files.get(url.pathname);
    if (!file) { res.writeHead(404); res.end(); return; }
    if (file.endsWith('.zkey')) requestedKeys.add(file);
    res.setHeader('content-type', file.endsWith('.js') ? 'text/javascript' : 'application/octet-stream');
    res.end(fs.readFileSync(file));
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(15183, '127.0.0.1', resolve); });
  let browser;
  try {
    browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
    const page = await browser.newPage(); await page.goto('http://127.0.0.1:15183');
    const prove = packet => page.evaluate(packet => new Promise((resolve, reject) => {
      const worker = new Worker('/worker.js');
      worker.onerror = event => { worker.terminate(); reject(new Error(event.message)); };
      worker.onmessage = ({ data }) => {
        if (data.type === 'result' || data.type === 'error') { worker.terminate(); resolve(data); }
      };
      worker.postMessage({ packet, assetRoot: `${location.origin}/proofs/` });
    }), packet);
    const results = [];
    for (const n of [1, 5, 10]) {
      const packet = packetFor(n), result = await prove(packet);
      assert.equal(result.type, 'result', result.message);
      assert.deepEqual(result.publicSignals, packet.expectedPublicSignals);
      const hints = await Prospecting.Proof.getVerifierCalldata({ record: recordFor(n), proof: result.proof, publicSignals: result.publicSignals });
      assert(hints.length < 5000);
      results.push({ samples: n, timings: result.timings, hintsFelts: hints.length });
      console.log(`PASS actual client worker: ${n} samples, ${hints.length} proof felts`);
    }
    const bad = packetFor(1); bad.sampleCount = 2;
    assert.equal((await prove(bad)).type, 'error');
    assert.equal(requestedKeys.size, 1);
    fs.writeFileSync('target/prospecting/browser.json', JSON.stringify({ browser: await browser.version(), results }, null, 2));
  } finally { await browser?.close(); await new Promise(resolve => server.close(resolve)); }
});
