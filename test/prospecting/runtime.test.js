import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import net from 'node:net';
import { hash, shortString, uint256 } from 'starknet';
import { startDevnet, call } from '../missions/devnet.js';
import { observeMissionAction } from '../../bin/lib/missionObservation.js';
import { prepareProofDeployment, deployProspectingProof } from '../../bin/lib/prospectingDeployment.js';
import { createFixtureRecord } from './records.js';

const requireClient = createRequire(path.resolve(process.env.PROSPECTING_CLIENT_ROOT || '../influence-client', 'package.json'));
const { Prospecting, Entity, Lot, System } = process.env.PROSPECTING_SDK_ROOT
  ? requireClient(path.resolve(process.env.PROSPECTING_SDK_ROOT, 'build/index.cjs'))
  : requireClient('@influenceth/sdk');
if (!Prospecting.Game) throw new Error('Install SDK 2.9.0-rc.2 in the client or set PROSPECTING_SDK_ROOT to its built SDK repository');
const snarkjs = createRequire(path.resolve('proofs/fieldwork/package.json'))('snarkjs');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const felt = shortString.encodeShortString;
const split = value => { const { low, high } = uint256.bnToUint256(BigInt(value)); return [low, high]; };
const entity = (label, id) => [label, id];
const packEntity = (label, id) => BigInt(label) + (BigInt(id) << 16n);
const directory = 'temp/prospecting/runtime/target/dev';
const assets = path.resolve('proofs/fieldwork/target/proof');
const manifest = read(path.join(assets, 'manifest.json'));
const useClientController = process.env.PROSPECTING_CLIENT_CONTROLLER === '1';
const clientController = useClientController ? (await import(path.resolve(
  process.env.PROSPECTING_CLIENT_ROOT || '../influence-client', 'src/game/prospecting/chainCampaign.js'))).createChainCampaign : null;
const serverDecoder = useClientController ? createRequire(path.resolve(
  process.env.PROSPECTING_SERVER_ROOT || '../influence-server', 'package.json'))(path.resolve(
    process.env.PROSPECTING_SERVER_ROOT || '../influence-server', 'src/common/lib/prospecting.js')) : null;
async function proveRecord(record) {
  const packet = Prospecting.getProofPacket(record);
  const files = manifest;
  assert.equal(packet.circuit, manifest.circuit);
  assert.equal(packet.input.count, String(packet.sampleCount));
  const result = await snarkjs.groth16.fullProve(packet.input, path.join(assets, files.wasm.file),
    path.join(assets, files.zkey.file), undefined, undefined, { singleThread: true });
  assert.deepEqual(result.publicSignals, packet.expectedPublicSignals);
  return result;
}


function statement(record) {
  const state = Prospecting.replayCampaign(record);
  const c = state.finalized;
  const header = 7003n + (BigInt(record.actions.length) << 14n) + (BigInt(record.qualityBps ?? 10000) << 18n)
    + (BigInt(record.identity.originIndex) << 32n) + (BigInt(c.lot) << 53n)
    + (BigInt(c.quantity) << 74n) + (BigInt(c.rate) << 106n);
  return [BigInt(record.context), header, ...state.history.flatMap(h => [
    BigInt(h.meta) + (BigInt(h.randomness) << 81n) + (BigInt(h.mask) << 145n), BigInt(h.commitment)
  ])];
}

test('prospecting game systems, real Groth16 bridge, extraction and replacement on isolated devnet', { timeout: 900000 }, async t => {
  await new Promise((resolve, reject) => {
    const probe = net.connect(5056, '127.0.0.1');
    probe.once('connect', () => { probe.destroy(); reject(new Error('Port 5056 is occupied; refusing to touch another chain')); });
    probe.once('error', error => error.code === 'ECONNREFUSED' ? resolve() : reject(error));
  });
  const { accounts: [admin, player, other], provider, invoke: invokeNative, deploy, declare, reverted, rpc } = await startDevnet(t, 5056);
  const decoded = [];
  const invoke = async (...args) => {
    const receipt = await invokeNative(...args);
    if (serverDecoder) for (const event of receipt.events) {
      if (BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName('ComponentUpdated'))) {
        const name = shortString.decodeShortString(`0x${BigInt(event.keys[1]).toString(16)}`);
        if (serverDecoder.COMPONENTS[name]) decoded.push({ name, data: serverDecoder.decodeComponent(name, event) });
      }
      for (const name of ['ProspectingCampaignStarted', 'ProspectingSampleCommitted',
        'ProspectingCampaignFinalized', 'ProspectingCampaignAbandoned', 'ResourceExtractionStartedV1']) {
        if (BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName(name))) {
          decoded.push({ name, data: serverDecoder.decodeEvent(name, event) });
        }
      }
    }
    return receipt;
  };
  const bundle = prepareProofDeployment();
  const deployedProof = await deployProspectingProof({ account: admin, bundle, options: { tip: 0 } });
  const bridge = deployedProof.bridge.address;
  assert.equal(deployedProof.bridge.constructorCalldata.length, 1);
  const repeated = await deployProspectingProof({ account: admin, bundle, options: { tip: 0 } });
  assert.deepEqual(repeated.transactions, [], 'repeated proof deployment submitted new transactions');
  const bridgeCounts = process.env.PROSPECTING_BRIDGE_COUNTS?.split(',').map(Number) || Array.from({ length: 10 }, (_, i) => i + 1);
  for (const n of bridgeCounts) {
    const record = createFixtureRecord(Prospecting, n);
    const proof = await proveRecord(record);
    const hints = await Prospecting.Proof.getVerifierCalldata({ record, ...proof });
    const words = statement(record).flatMap(split);
    const checked = await provider.callContract(call(bridge, 'verify', [n, words.length / 2, ...words, hints.length, ...hints]));
    assert.equal(BigInt(checked[0]), 1n);
    if (n === 5) {
      const altered = [...words]; altered[0] = String(BigInt(altered[0]) + 1n);
      await reverted(player, call(bridge, 'verify', [n, altered.length / 2, ...altered, hints.length, ...hints]));
    }
    console.log(`PASS real verifier bridge: ${n} samples`);
  }
  const dispatcher = await deploy('Dispatcher', [admin.address], directory);
  const system = (name, args) => call(dispatcher, 'run_system', [felt(name), args.length, ...args]);
  const names = ['WriteComponent', 'ReadComponent', 'ProspectingRuntimeSeed', 'ConfigureProspecting',
    'Abundance', 'SampleDepositStart', 'SampleDepositImprove', 'SampleDepositFinish', 'ProspectingStart', 'ProspectingSample',
    'ProspectingFinalize', 'ProspectingAbandon', 'ReadProspectingCampaign', 'ReadProspectingSample',
    'ReadProspectingRandomness', 'ReadProspectingOrigin', 'PreviewProspectingSample',
    'ExtractResourceStart', 'BaselineExtractResourceStart', 'ExtractResourceFinish', 'MissionObserver', 'ReadMissionState'];
  for (const name of names) await invoke(admin, call(dispatcher, 'register_system', [felt(name), await declare(name, directory)]));
  await invoke(admin, system('ProspectingRuntimeSeed', [player.address, other.address]));
  await invoke(admin, system('ConfigureProspecting', [bridge]));
  const game = Prospecting.Game.createClient({ dispatcher, provider });
  const originId = Lot.toId(250000, 1);
  const origin = entity(Entity.IDS.LOT, originId), crew = entity(Entity.IDS.CREW, 1);
  const warehouse = entity(Entity.IDS.BUILDING, 3), extractor = entity(Entity.IDS.BUILDING, 4);
  const asEntity = ([label, id]) => ({ label, id });
  const start = resource => Prospecting.Game.getStartCall({ dispatcher, origin: asEntity(origin), resource, crew: asEntity(crew) });
  const sampleCall = (id, lot, index, commitment) => Prospecting.Game.getSampleCall({ dispatcher,
    campaignId: id, lot: asEntity(lot), index, commitment, inventoryOrigin: asEntity(warehouse), originSlot: 2, crew: asEntity(crew) });
  const abandon = id => Prospecting.Game.getAbandonCall({ dispatcher, campaignId: id, crew: asEntity(crew) });
  const extractionOptions = { dispatcher, quantity: 1000, extractor: asEntity(extractor),
    destination: asEntity(warehouse), destinationSlot: 2, crew: asEntity(crew) };
  const baseline = (resource, extractorSlot) => Prospecting.Game.getBaselineExtractionCall({ ...extractionOptions, resource, extractorSlot });
  const collect = extractorSlot => Prospecting.Game.getExtractionFinishCall({ ...extractionOptions, extractorSlot });
  const view = async (name, args) => (await provider.callContract(system(name, args))).slice(1);
  const component = async (name, scope) => {
    const values = await view('ReadComponent', [felt(name), scope.length, ...scope]);
    assert.equal(Number(values[0]), values.length - 1, 'component Span framing');
    return values.slice(1);
  };
  const write = (name, scope, data) => invoke(admin, system('WriteComponent', [felt(name), scope.length, ...scope, data.length, ...data]));
  const extKey = packEntity(...extractor);
  const stockKey = [packEntity(...warehouse), 2];
  const stock = () => component('Inventory', stockKey);
  const campaign = async id => {
    const c = await game.campaign(id);
    return { ...c, status: c.chainStatus, replaceable: c.replaceableAt };
  };
  const sample = async (id, i) => {
    const core = await game.core(id, i);
    return { ...core, target: Number(core.target) };
  };
  const moveTime = async time => { await rpc('devnet_setTime', { time, generate_block: true }); };
  const untilSample = async s => {
    await moveTime(s.ready + 1);
    while (await provider.getBlockNumber() < s.target + 10) await rpc('devnet_createBlock', {});
  };
  await reverted(player, system('SampleDepositStart', [...origin, 1, ...warehouse, 2, ...crew]));
  const initialStock = await stock();
  await reverted(player, baseline(2, 1));
  assert.deepEqual(await stock(), initialStock);

  let finalRecord, campaignId, finalController;
  for (let attempt = 0; attempt < 8 && !finalRecord; attempt++) {
    await invoke(player, start(1));
    campaignId = Number((await view('ReadProspectingOrigin', origin))[0]);
    let c = await campaign(campaignId);
    let record = Prospecting.createRecord({ mode: 'chain', campaignId, context: c.context, qualityBps: c.qualityBps,
      identity: { chainId: await provider.getChainId(), game: dispatcher, owner: player.address, asteroidId: 250000, originIndex: 1, resource: 1 } });
    const controller = clientController && clientController({ game, provider, crew: asEntity(crew),
      read: () => record,
      save: async next => { Prospecting.replayCampaign(next); record = JSON.parse(JSON.stringify(next)); },
      recheck: async () => null,
      execute: async (name, input) => {
        const call = System.getRunSystemCall(name, input, dispatcher);
        const calls = name === 'ProspectingFinalize' ? observeMissionAction({ dispatcher, account: player.address,
          system: name, calldata: call.calldata.slice(2), executionCalls: [call],
          candidates: [{ campaign: felt('ProspectingRuntime'), subject: asEntity(crew), mission: 1 }] }) : call;
        const receipt = await invoke(player, calls);
        return { status: 'submitted', txHash: receipt.transaction_hash };
      } });
    assert.equal(BigInt(Prospecting.Game.getCampaignContext({ identity: record.identity,
      campaignId, crew: asEntity(crew), verifier: bridge })), BigInt(c.context), 'SDK/game campaign domain mismatch');
    const lockedStock = await stock();
    await reverted(player, start(2));
    assert.deepEqual(await stock(), lockedStock);
    for (let i = 0; i < 5; i++) {
      const state = Prospecting.replayCampaign(record);
      const known = state.cells.map((cell, index) => ({ cell, index })).filter(({ cell }) => cell[0]);
      const productive = known.find(({ cell }) => cell[3] > 0);
      let method = 0, target = i, source = known.at(-1)?.index || 0, depth = known.length ? Math.min(4, known.at(-1).cell[2] + 1) : 0;
      if (productive && !productive.cell[7]) { method = 1; target = productive.index; depth = productive.cell[2]; }
      else if (productive && !productive.cell[8]) { method = 2; target = productive.index; depth = productive.cell[2]; }
      // Follow under the same surface lot; five depth bands suffice for this workflow fixture.
      const collapsed = method === 0 && state.history.some(h => h.event === 2 &&
        h.sourceLot === 1 && h.sourceDepth === state.cells[source][2] && h.lot === 1 && h.depth === depth);
      const targetLot = collapsed ? entity(Entity.IDS.LOT, Lot.toId(250000, 2)) : origin;
      const { meta, blockedApproaches: mask } = await game.previewSample(campaignId, asEntity(targetLot));
      const action = { method, target, source, depth, salt: Prospecting.generateSalt() };
      if (controller) {
        await controller.sample({ method, target, source, depth }, asEntity(targetLot), { entity: asEntity(warehouse), slot: 2 });
      } else {
        record = Prospecting.prepareSample(record, { action, meta: String(BigInt(meta)), blockedApproaches: String(BigInt(mask)), preparedAt: c.replaceable - 86400 });
      }
      const commit = sampleCall(campaignId, targetLot, i, record.pending.commitment);
      if (!controller) {
        const receipt = await invoke(player, commit);
        record = Prospecting.markSubmitted(record, receipt.transaction_hash);
      }
      const s = await sample(campaignId, i);
      if (!controller) record = Prospecting.acceptSample(record, s);
      const savedStock = await stock();
      await reverted(player, commit);
      assert.deepEqual(await stock(), savedStock, 'stale commit spent inventory');
      if (i === 0) await reverted(player, sampleCall(campaignId, origin, 1, record.pending.commitment));
      await untilSample(s);
      const entropy = await game.randomness(campaignId);
      const targetBlock = await provider.getBlock(s.target);
      assert.equal(Prospecting.Game.getBlockRandomness({ chainId: record.identity.chainId, dispatcher,
        campaignId, sampleIndex: i, blockHash: targetBlock.block_hash }), entropy, 'SDK/game randomness domain mismatch');
      const blockNumber = await provider.getBlockNumber();
      const now = Number((await provider.getBlock('latest')).timestamp);
      if (controller) {
        await controller.synchronize();
        assert.equal(record.pending, null);
        assert.equal(record.actions[i].randomness, entropy);
      } else record = Prospecting.resolveSample(record, String(BigInt(entropy)), { now, blockNumber });
      c = await campaign(campaignId);
    }
    const state = Prospecting.replayCampaign(record);
    const selected = state.cells.findIndex(cell => cell[0] && cell[3] > 0 && cell[1] === 1);
    if (selected >= 0) {
      finalRecord = Prospecting.finalizeRecord(record, selected);
      record = finalRecord;
      finalController = controller;
    } else {
      // Fixture search obeys the game's paid samples and real replacement deadline.
      await invoke(player, abandon(campaignId));
      await moveTime(c.replaceable + 1);
    }
  }
  assert.ok(finalRecord, 'No productive five-sample fixture found');
  const proof = await proveRecord(finalRecord);
  const hints = await Prospecting.Proof.getVerifierCalldata({ record: finalRecord, ...proof });
  const result = Prospecting.replayCampaign(finalRecord).finalized;
  const finalize = quantity => Prospecting.Game.getFinalizeCall({ dispatcher, campaignId, lot: asEntity(origin),
    quantity, rateBps: result.rateBps, proofCalldata: hints, crew: asEntity(crew) });
  const preparedFinalization = await Prospecting.Game.prepareFinalizeCall({ client: game, record: finalRecord, ...proof,
    blockIdentifier: await provider.getBlockNumber() });
  assert.deepEqual(preparedFinalization, finalize(result.quantity), 'SDK finalization drifted from selected proof');
  const preclaim = await campaign(campaignId);
  await reverted(player, finalize(result.quantity + 1));
  assert.deepEqual(await campaign(campaignId), preclaim, 'failed proof changed campaign');
  await invoke(player, baseline(1, 2));
  const baselineJob = await component('Extractor', [extKey, 2]);
  // Revoking the surface permission must not destroy already accepted evidence.
  await write('Control', [packEntity(Entity.IDS.ASTEROID, 250000)], entity(Entity.IDS.CREW, 2));
  const finalizeCall = preparedFinalization;
  const finalized = finalController
    ? await provider.getTransactionReceipt((await finalController.finalize(proof)).txHash)
    : await invoke(player, observeMissionAction({ dispatcher, account: player.address,
      system: 'ProspectingFinalize', calldata: finalizeCall.calldata.slice(2), executionCalls: [finalizeCall],
      candidates: [{ campaign: felt('ProspectingRuntime'), subject: { label: Entity.IDS.CREW, id: 1 }, mission: 1 }] }));
  assert.ok(finalized.events.some(event => BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName('MissionCompleted'))),
    'completed campaign did not earn the prospecting mission');
  const mission = await view('ReadMissionState', [felt('ProspectingRuntime'), ...crew, 1, 0]);
  assert.equal(BigInt(mission[1]), 1n);
  const completed = await campaign(campaignId);
  assert.equal(completed.status, 4);
  assert.equal(BigInt((await view('ReadProspectingOrigin', origin))[0]), 0n);
  const depKey = [packEntity(completed.claim.label, completed.claim.id)];
  const claimData = await component('Claim', depKey);
  const deposit = await component('Deposit', depKey);
  assert.equal(BigInt(deposit[2]), BigInt(result.quantity));
  assert.equal(BigInt(deposit[3]), BigInt(result.quantity));
  assert.equal(BigInt(claimData[1]), BigInt(result.rateBps));
  await reverted(player, finalize(result.quantity));
  assert.deepEqual(await component('Deposit', depKey), deposit, 'duplicate proof changed balance');
  await write('Control', [packEntity(Entity.IDS.ASTEROID, 250000)], crew);
  await invoke(player, Prospecting.Game.getClaimExtractionCall({ ...extractionOptions, deposit: completed.claim, extractorSlot: 1 }));
  const running = await component('Extractor', [extKey, 1]);
  assert.equal(BigInt((await component('Deposit', depKey))[3]), BigInt(result.quantity - 1000));
  await moveTime(Number(running.at(-1)) + 1);
  await invoke(player, start(1));
  const next = Number((await view('ReadProspectingOrigin', origin))[0]);
  const beforeBlocked = await stock();
  await reverted(player, sampleCall(next, origin, 0, 123));
  assert.deepEqual(await stock(), beforeBlocked, 'RUNNING conflict spent a drill');
  await invoke(player, collect(1));
  await reverted(player, sampleCall(next, origin, 0, 123));
  await moveTime(Math.max(Number(running.at(-1)), Number(baselineJob.at(-1))) + 2);
  await invoke(player, collect(2));
  await invoke(player, sampleCall(next, origin, 0, 123));
  const replacement = await campaign(next);
  await invoke(player, abandon(next));
  await reverted(player, start(2));
  await moveTime(replacement.replaceable + 1);
  await invoke(player, start(2));
  assert.equal((await campaign(next)).status, 3);
  await reverted(player, system('ProspectingFinalize', [next, ...origin, result.quantity, result.rateBps, hints.length, ...hints, ...crew]));
  if (serverDecoder) {
    for (const name of Object.keys(serverDecoder.COMPONENTS)) assert.ok(decoded.some(event => event.name === name), `Missing real ${name} event`);
    assert.ok(decoded.some(event => event.name === 'ResourceExtractionStartedV1' && event.data.mode === 0));
    assert.ok(decoded.some(event => event.name === 'ResourceExtractionStartedV1' && event.data.mode === 1));
    console.log(`PASS client controller and server ABI decoding for ${decoded.length} native events`);
  }
  console.log('PASS real campaign proof, private transitions, consumption, revocation, RUNNING conflict and replacement');
});
