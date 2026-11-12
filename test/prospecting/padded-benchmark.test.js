import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import net from 'node:net';
import { hash, uint256 } from 'starknet';
import { startDevnet, call } from '../missions/devnet.js';

const sandbox = path.resolve('../mining-prototype');
const dir = path.join(sandbox, 'optimization/fieldwork/padded10');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const requireSandbox = createRequire(path.join(sandbox, 'package.json'));
const garaga = requireSandbox('garaga');
const split = value => { const { low, high } = uint256.bnToUint256(BigInt(value)); return [low, high]; };
const artifact = (directory, suffix) => path.join(directory,
  fs.readdirSync(directory).find(file => file.endsWith(`_${suffix}.contract_class.json`))).replace(/\.contract_class\.json$/, '');
const resources = receipt => ({ transactionHash: receipt.transaction_hash, resources: receipt.execution_resources, actualFee: receipt.actual_fee });

test('specialized versus single padded verifier, including actual Cairo transcript bridge', { timeout: 900000 }, async t => {
  await new Promise((resolve, reject) => {
    const probe = net.connect(5057, '127.0.0.1');
    probe.once('connect', () => { probe.destroy(); reject(new Error('Port 5057 is occupied')); });
    probe.once('error', error => error.code === 'ECONNREFUSED' ? resolve() : reject(error));
  });
  const { accounts: [admin], provider, invoke, reverted } = await startDevnet(t, 5057);
  const declaredClasses = new Set();
  const deploy = async (base, args = []) => {
    const contract = read(`${base}.contract_class.json`), casm = read(`${base}.compiled_contract_class.json`);
    const classHash = hash.computeContractClassHash(contract);
    if (!declaredClasses.has(classHash)) {
      const declared = await admin.declare({ contract, casm }, { tip: 0 });
      await admin.waitForTransaction(declared.transaction_hash, { retryInterval: 100 });
      declaredClasses.add(classHash);
    }
    const deployed = await admin.deployContract({ classHash, constructorCalldata: args.map(String) }, { tip: 0 });
    return { address: deployed.contract_address, receipt: await admin.waitForTransaction(deployed.transaction_hash, { retryInterval: 100 }) };
  };
  await deploy(artifact(path.join(sandbox, 'optimization/ecip/target/dev'), 'UniversalECIP'));
  const verifiers = {};
  for (const n of [1, 3, 5, 10]) verifiers[n] = await deploy(artifact(path.join(sandbox,
    `optimization/fieldwork/volume150/verifier${n}/target/dev`), 'Groth16VerifierBN254'));
  const padded = await deploy(artifact(path.join(dir, 'verifier/target/dev'), 'Groth16VerifierBN254'));
  // Retain the specialized-circuit comparison using the current one-address
  // adapter. Only the historical baseline needs one adapter per specialized key.
  const specializedRouters = {};
  for (const n of [1, 3, 5, 10]) specializedRouters[n] = await deploy(
    'proofs/fieldwork/target/dev/prospecting_verifier_ProspectingVerifier', [verifiers[n].address]);
  const newRouter = await deploy(artifact(path.join(dir, 'router/target/dev'), 'ProspectingVerifier'), [padded.address]);
  await garaga.init();
  const browser = read(path.join(dir, 'artifacts/browser.json'));
  const report = { date: new Date().toISOString(), scope: 'Actual account invoke receipts; verifier and Cairo transcript bridge. Gameplay writes excluded; their inputs and transcript remain unchanged.',
    adapterTopology: 'current one-address adapter for both circuit families',
    paddedRouterDeployment: resources(newRouter.receipt), specializedRouterDeployment: resources(specializedRouters[1].receipt), results: [], checks: [] };
  for (const n of [1, 3, 5, 10]) {
    const base = path.join(sandbox, `optimization/fieldwork/volume150/artifacts/campaign${n}volume150`);
    const input = read(`${base}.input.json`), expected = read(`${base}.expected.json`);
    const c = expected.result;
    const header = 7003n + (BigInt(n) << 14n) + (BigInt(input.quality) << 18n) + (BigInt(input.origin) << 32n)
      + (BigInt(c.lot) << 53n) + (BigInt(c.quantity) << 74n) + (BigInt(c.rate) << 106n);
    const statement = [BigInt(input.context), header, ...input.meta.flatMap((meta, i) => [
      BigInt(meta) + (BigInt(input.randomness[i]) << 81n) + (BigInt(input.blockedApproaches[i]) << 145n), BigInt(input.commitments[i])])];
    const words = statement.flatMap(split);
    const row = { count: n };
    for (const kind of ['specialized', 'padded']) {
      const proof = browser.results.find(row => row.n === n && row.kind === kind);
      assert.deepEqual(proof.publicSignals, expected.publicSignals);
      const vk = read(kind === 'padded' ? path.join(dir, 'artifacts/campaign.vk.json') : `${base}.vk.json`);
      const encoded = garaga.getGroth16CallData(garaga.parseGroth16ProofFromObject(proof.proof, proof.publicSignals),
        garaga.parseGroth16VerifyingKeyFromObject(vk), garaga.CurveId.BN254).map(String);
      assert.equal(Number(encoded[0]), encoded.length - 1);
      const hints = encoded.slice(1);
      const target = kind === 'padded' ? padded : verifiers[n];
      const direct = call(target.address, 'verify_groth16_proof_bn254', [hints.length, ...hints]);
      const router = kind === 'padded' ? newRouter : specializedRouters[n];
      const bridge = call(router.address, 'verify', [n, statement.length, ...words, hints.length, ...hints]);
      assert.equal(BigInt((await provider.callContract(bridge))[0]), 1n);
      row[kind] = { calldataFelts: bridge.calldata.length, hintsFelts: hints.length,
        direct: resources(await invoke(admin, direct)), bridge: resources(await invoke(admin, bridge)) };
      if (kind === 'padded') {
        for (const index of [0, 1, 3]) {
          const changed = [...statement]; changed[index] += 1n;
          await reverted(admin, call(router.address, 'verify', [n, changed.length, ...changed.flatMap(split), hints.length, ...hints]));
          report.checks.push(`count ${n}: altered statement word ${index} rejected`);
        }
        await reverted(admin, call(router.address, 'verify', [n === 10 ? 9 : n + 1, statement.length, ...words, hints.length, ...hints]));
        report.checks.push(`count ${n}: wrong declared length rejected`);
      }
    }
    report.results.push(row);
    fs.writeFileSync(path.join(dir, 'artifacts/gas.json'), JSON.stringify(report, null, 2));
    console.log(n, JSON.stringify({ specialized: row.specialized.bridge.resources, padded: row.padded.bridge.resources,
      felts: [row.specialized.calldataFelts, row.padded.calldataFelts] }));
  }
  console.log('PASS real Groth16 proofs through both Cairo bridges, with count/statement tampering rejected.');
});
