import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fixtures, createFixtureRecord } from './records.js';

const { Prospecting } = createRequire(path.resolve('../influence-client/package.json'))('@influenceth/sdk');
const snarkjs = createRequire(path.resolve('proofs/fieldwork/package.json'))('snarkjs');
const assets = path.resolve('proofs/fieldwork/target/proof');
const manifest = JSON.parse(fs.readFileSync(path.join(assets, 'manifest.json'), 'utf8'));

test('the promoted padded circuit preserves every transcript and constrains count, selection and unused inputs', async () => {
  const file = path.join(assets, 'regression.wtns'), wasm = path.join(assets, manifest.wasm.file);
  for (const fixture of fixtures) {
    const packet = Prospecting.getProofPacket(createFixtureRecord(Prospecting, fixture.n));
    await snarkjs.wtns.calculate(packet.input, wasm, file);
    const witness = await snarkjs.wtns.exportJson(file);
    assert.deepEqual(witness.slice(1, 2).map(String), fixture.publicSignals);
  }
  const { input } = Prospecting.getProofPacket(createFixtureRecord(Prospecting, 5));
  const invalid = [];
  for (const field of ['meta', 'blockedApproaches', 'commitments', 'randomness', 'methods', 'targets', 'sources', 'depths', 'salts']) {
    const modified = structuredClone(input); modified[field][5] = '1'; invalid.push(modified);
  }
  for (const count of ['0', '4', '6', '11']) invalid.push({ ...input, count });
  invalid.push({ ...input, selected: '5' });
  const altered = structuredClone(input); altered.commitments[0] = (BigInt(altered.commitments[0]) + 1n).toString();
  invalid.push(altered);
  for (const modified of invalid) await assert.rejects(snarkjs.wtns.calculate(modified, wasm, file));
});
