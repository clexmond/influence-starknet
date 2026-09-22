import { Entity, Building, Ship } from '@influenceth/sdk';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';
import { Account, RpcProvider, shortString, hash, config } from 'starknet';

// Fresh deployments: these tests do not depend on the legacy seeded devnet dump.
test('starter mission transactions preserve attribution and roll back failed actions and payouts', { timeout: 600000 }, async (t) => {
  config.set('logLevel', 'FATAL');
  const port = 5051;
  const node = spawn(process.env.STARKNET_DEVNET_BIN || 'starknet-devnet', [
    '--port', String(port), '--seed', '12345', '--initial-balance', '10000000000000000000000000'
  ]);
  let logs = '';
  node.stdout.on('data', (data) => { logs += data; });
  node.stderr.on('data', (data) => { logs += data; });
  t.after(() => node.kill());
  const url = `http://127.0.0.1:${port}`;
  let accounts;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    if (node.exitCode !== null) throw new Error(`Devnet stopped: ${logs}`);
    try {
      const response = await fetch(`${url}/rpc`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'devnet_getPredeployedAccounts', params: {} })
      });
      const body = await response.json();
      if (response.ok && body.result) { accounts = body.result; break; }
    } catch { /* Wait for the local test server to bind. */ }
    await delay(250);
  }
  assert.ok(accounts, `Devnet did not start: ${logs}`);
  const provider = new RpcProvider({ nodeUrl: `${url}/rpc`, transactionRetryIntervalFallback: 100 });
  const admin = new Account({ provider, address: accounts[0].address, signer: accounts[0].private_key });
  const player = new Account({ provider, address: accounts[1].address, signer: accounts[1].private_key });
  const recipient = accounts[2].address;
  const felt = shortString.encodeShortString;

  const artifact = (name, suffix) => JSON.parse(fs.readFileSync(`target/dev/contract_${name}.${suffix}.json`, 'utf8'));

  const declare = async (name) => {
    const sierra = artifact(name, 'contract_class');
    const classHash = hash.computeContractClassHash(sierra);
    const tx = await admin.declare({ contract: sierra, casm: artifact(name, 'compiled_contract_class') }, { tip: 0 });
    await admin.waitForTransaction(tx.transaction_hash, { retryInterval: 100 });
    return classHash;
  };

  const deploy = async (name, calldata) => {
    const classHash = await declare(name);
    const result = await admin.deployContract({ classHash, constructorCalldata: calldata }, { tip: 0 });
    await admin.waitForTransaction(result.transaction_hash, { retryInterval: 100 });
    return result.contract_address;
  };
  const dispatcher = await deploy('Dispatcher', [admin.address]);
  const token = await deploy('Sway', [felt('SWAY'), felt('SWAY'), 6, admin.address]);

  const call = (contractAddress, entrypoint, calldata) => ({ contractAddress, entrypoint, calldata: calldata.map(String) });

  const invoke = async (account, invocation) => {
    const tx = await account.execute(invocation, { tip: 0 });
    return account.waitForTransaction(tx.transaction_hash, { retryInterval: 100 });
  };

  const system = (name, data) => call(dispatcher, 'run_system', [felt(name), data.length, ...data]);
  for (const name of ['WriteComponent', 'ReadComponent', 'RegisterMissionCampaign', 'ConfigureStarterMissions',
    'AcceptMission', 'MissionAction', 'MissionValidate', 'ReadMissionState', 'ClaimMissionReward', 'ConstructionPlan']) {
    await invoke(admin, call(dispatcher, 'register_system', [felt(name), await declare(name)]));
  }
  const template = await declare('StarterMissionCampaign');
  const campaign = felt('StarterRuntime');
  await invoke(admin, system('RegisterMissionCampaign', [campaign, template, 8]));
  const activation = await invoke(admin, system('ConfigureStarterMissions', [campaign, 100]));
  const constants = activation.events.filter((event) =>
    BigInt(event.from_address) === BigInt(dispatcher)
      && BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName('ConstantRegistered')));
  assert.deepEqual(constants.map((event) => event.keys.map(BigInt)), [
    [BigInt(hash.getSelectorFromName('ConstantRegistered'))],
    [BigInt(hash.getSelectorFromName('ConstantRegistered'))]
  ]);
  assert.deepEqual(constants.map((event) => event.data.map(BigInt)), [
    [BigInt(felt('STARTER_MISSION_CUTOFF')), 100n],
    [BigInt(felt('STARTER_MISSION_CAMPAIGN')), BigInt(campaign)]
  ]);
  for (const event of constants) {
    const stored = await provider.callContract(call(dispatcher, 'constant', [event.data[0]]));
    assert.equal(BigInt(stored[0]), BigInt(event.data[1]));
  }
  await invoke(admin, call(dispatcher, 'register_contract', [felt('Sway'), token]));
  const packedCrew = BigInt(Entity.packEntity({ label: Entity.IDS.CREW, id: 101 }));
  const packedAsteroid = BigInt(Entity.packEntity({ label: Entity.IDS.ASTEROID, id: 1 }));
  const lotId = (1n << 32n) + 1n;

  const write = async (name, path, data) => invoke(admin, system('WriteComponent', [felt(name), path.length, ...path, data.length, ...data]));

  const crewData = (delegate) => [delegate, 1, 101, 0, 0, 0, 0, 0, 0, 0, 0];
  await write('Crew', [packedCrew], crewData(player.address));
  await write('Location', [packedCrew], [Entity.IDS.LOT, lotId]);
  await write('Ship', [packedCrew], [Ship.IDS.ESCAPE_MODULE, Ship.STATUSES.DISABLED, 0, Ship.VARIANTS.STANDARD, 0, 0, 0, 0, 0, 0, 0]);
  await write('Control', [packedAsteroid], [Entity.IDS.CREW, 101]);
  const warehouse = Building.TYPES[Building.IDS.WAREHOUSE];
  await write('BuildingType', [warehouse.i], [warehouse.processType, warehouse.siteSlot, warehouse.siteType]);
  const assignment = [campaign, Entity.IDS.CREW, 101, 0];
  const missionEvents = (receipt, name) => receipt.events
    .filter((event) => BigInt(event.from_address) === BigInt(dispatcher)
      && BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName(name)))
    .map((event) => event.data.map(BigInt));

  const accepted = await invoke(player, system('AcceptMission', assignment));
  assert.deepEqual(missionEvents(accepted, 'MissionAccepted'), [assignment.map(BigInt)]);
  assert.deepEqual(missionEvents(accepted, 'MissionCompleted'), []);

  const read = async () => {
    const values = await provider.callContract(system('ReadMissionState', [...assignment, 0]));
    return values.slice(1).map(BigInt); // Dispatcher returns a Span.
  };
  assert.deepEqual(await read(), [1n, 0n, 0n, 0n]);

  const plan = (kind) => system('MissionAction', [...assignment, felt('ConstructionPlan'), 3, kind, Entity.IDS.LOT, lotId]);
  const bounds = {
    l1_gas: { max_amount: 100000n, max_price_per_unit: 10n ** 15n },
    l1_data_gas: { max_amount: 100000n, max_price_per_unit: 10n ** 15n },
    l2_gas: { max_amount: 1000000000n, max_price_per_unit: 10n ** 12n }
  };

  const reverted = async (account, invocation) => {
    // Supply bounds so this is a submitted, reverted transaction, not only a failed estimate.
    const tx = await account.execute(invocation, { resourceBounds: bounds, tip: 0 });
    try { await account.waitForTransaction(tx.transaction_hash, { retryInterval: 100 }); } catch { /* Inspect the actual receipt below. */ }
    const receipt = await provider.getTransactionReceipt(tx.transaction_hash);
    assert.equal(receipt.execution_status, 'REVERTED');
    for (const name of ['MissionAccepted', 'MissionCompleted', 'MissionRewardClaimed', 'ConstantRegistered']) {
      assert.deepEqual(missionEvents(receipt, name), []);
    }
    // The existing Dispatcher uses Result.unwrap and masks nested panic text.
    // Assert persisted state and successful recovery below instead.
    return receipt;
  };
  await reverted(player, system('ConfigureStarterMissions', [campaign, 0]));
  await reverted(admin, system('ConfigureStarterMissions', [campaign, 0]));
  const cutoff = await provider.callContract(call(dispatcher, 'constant', [felt('STARTER_MISSION_CUTOFF')]));
  assert.equal(BigInt(cutoff[0]), 100n);
  // Missing refinery configuration fails after native gameplay has written the building and lot-use records.
  await reverted(player, plan(Building.IDS.REFINERY));
  assert.deepEqual(await read(), [1n, 0n, 0n, 0n]);
  // Same lot succeeds, proving gameplay writes and the execution lock rolled back.
  const completed = await invoke(player, plan(Building.IDS.WAREHOUSE));
  assert.deepEqual(missionEvents(completed, 'MissionCompleted'), [assignment.map(BigInt)]);
  assert.deepEqual(missionEvents(completed, 'MissionAccepted'), []);
  assert.ok(completed.events.some((event) =>
    BigInt(event.from_address) === BigInt(dispatcher)
      && BigInt(event.keys[0]) === BigInt(hash.getSelectorFromName('ConstructionPlanned'))));
  const validated = await invoke(player, system('MissionValidate', [...assignment, 0]));
  assert.deepEqual(missionEvents(validated, 'MissionCompleted'), []);
  await reverted(player, system('AcceptMission', assignment));
  assert.deepEqual(await read(), [1n, 1n, 0n, 1n]);
  await reverted(player, system('ClaimMissionReward', assignment)); // Treasury is empty.
  assert.deepEqual(await read(), [1n, 1n, 0n, 1n]);
  await write('Crew', [packedCrew], crewData(recipient));
  await invoke(admin, call(token, 'add_grant', [admin.address, 2]));
  await invoke(admin, call(token, 'mint', [dispatcher, 5000000000n, 0]));
  const claimed = await invoke(player, system('ClaimMissionReward', assignment));
  assert.deepEqual(missionEvents(claimed, 'MissionRewardClaimed'), [
    [...assignment.map(BigInt), BigInt(recipient), 5000000000n]
  ]);
  assert.deepEqual(missionEvents(claimed, 'MissionCompleted'), []);
  assert.deepEqual(await read(), [1n, 1n, 1n, 1n]);
  const balance = await provider.callContract(call(token, 'balance_of', [recipient]));
  assert.equal(BigInt(balance[0]), 5000000000n);
  await reverted(player, system('ClaimMissionReward', assignment));
  assert.deepEqual(await read(), [1n, 1n, 1n, 1n]);
});
