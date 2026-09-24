import { hash, shortString } from 'starknet';

const felt = (name) => BigInt(shortString.encodeShortString(name));
const hex = (value) => `0x${BigInt(value).toString(16)}`;
const same = (a, b) => BigInt(a) === BigInt(b);
const entity = (label, id) => BigInt(label) + (BigInt(id) << 16n);
const field = (word, offset, width) => (word >> BigInt(offset)) & ((1n << BigInt(width)) - 1n);
const componentEvent = BigInt(hash.getSelectorFromName('ComponentUpdated'));
const plannedEvent = BigInt(hash.getSelectorFromName('ConstructionPlanned'));
const useLot = felt('UseLot');
const lotUse = felt('LotUse');
const prepaidOffsets = [0n, 64n, 92n, 128n, 164n, 200n];
const trackedComponents = new Map([
  'Unique', 'Control', 'Crew', 'PrepaidAgreement', 'PublicPolicy', 'WhitelistAgreement', 'ContractAgreement'
].map((name) => [felt(name), name]));

// WriteComponent has no compare-and-set. These entrypoints must remain disabled
// throughout execution so a player cannot acquire a lease between check and write.
export const TENANCY_SYSTEMS = [
  'ConstructionPlan', 'ConstructionAbandon', 'RepossessBuilding', 'AcceptPrepaidAgreement',
  'AcceptPrepaidMerkleAgreement', 'ExtendPrepaidAgreement', 'TransferPrepaidAgreement',
  'CancelPrepaidAgreement', 'AcceptContractAgreement', 'Whitelist', 'WhitelistAccount',
  'AssignPublicPolicy', 'DelegateCrew'
];

export const componentKey = (name, path) => hex(
  BigInt(hash.computePoseidonHashOnElements([
    felt('component'), felt(name), hash.computePoseidonHashOnElements(path)
  ])) % ((1n << 251n) - 256n)
);

// Only the first storage word is needed. Crew's first word is its delegate;
// the other tracked components each occupy a single word.
export const componentUpdate = (event) => {
  if (!same(event.keys[0], componentEvent)) return null;
  const name = trackedComponents.get(BigInt(event.keys[1]));
  if (!name) return null;
  const version = BigInt(event.keys[2] || 0);
  if (version !== 0n && !(name === 'Crew' && version === 1n)) {
    throw new Error(`Unsupported ${name} component version ${version}`);
  }
  const data = event.data.map(BigInt);
  const length = Number(data[0]);
  if (!Number.isSafeInteger(length) || length < 1 || length >= data.length) throw new Error('Invalid component path');
  const path = data.slice(1, length + 1);
  const values = data.slice(length + 1);
  let word;
  if (name === 'Control') {
    if (values.length !== 2) throw new Error('Invalid Control update');
    word = entity(...values);
  } else if (name === 'PrepaidAgreement') {
    if (values.length !== 6) throw new Error('Invalid PrepaidAgreement update');
    word = values.reduce((packed, value, i) => packed + (value << prepaidOffsets[i]), 0n);
  } else {
    if (name !== 'Crew' && values.length !== 1) throw new Error(`Invalid ${name} update`);
    word = values[0];
  }
  return { name, path, word, key: componentKey(name, path) };
};

const stateAt = (provider, address, blockHash, overrides = new Map()) => {
  const cache = new Map();
  return async (name, path) => {
    const key = componentKey(name, path);
    if (overrides.has(key)) return overrides.get(key);
    if (!cache.has(key)) cache.set(key, BigInt(await provider.getStorageAt(address, key, blockHash)));
    return cache.get(key);
  };
};

async function* events(provider, address, from, to, keys) {
  let continuation;
  do {
    const page = await provider.getEvents({
      address, from_block: { block_number: from }, to_block: { block_number: to },
      keys, chunk_size: 500, ...(continuation ? { continuation_token: continuation } : {})
    });
    for (const event of page.events) yield event;
    if (page.continuation_token && page.continuation_token === continuation) throw new Error('Repeated event pagination token');
    continuation = page.continuation_token;
  } while (continuation);
}

const sameController = async (read, first, second) => {
  if (!first || !second) return false;
  if (first === second) return true;
  const a = await read('Crew', [first]);
  const b = await read('Crew', [second]);
  return a !== 0n && a === b;
};

const permissionBlocker = async (read, lot, tenant, timestamp) => {
  if (!tenant || (tenant & 65535n) !== 1n) return 'missing or non-crew tenant';
  const agreement = await read('PrepaidAgreement', [lot, 1n, tenant]);
  const end = field(agreement, 164, 36);
  if (!end) return 'no prepaid agreement';
  const noticeEnd = field(agreement, 200, 36) + field(agreement, 92, 28);
  if (BigInt(timestamp) <= end || BigInt(timestamp) <= noticeEnd) return 'lease or notice period is still active';
  const delegate = await read('Crew', [tenant]);
  if (!delegate) return 'tenant crew is missing';
  if (await sameController(read, tenant, await read('Control', [lot]))) return 'tenant controls the lot';
  if (await read('PublicPolicy', [lot, 1n])) return 'public lot-use permission';
  if (await read('WhitelistAgreement', [lot, 1n, tenant])) return 'crew whitelist permission';
  if (await read('WhitelistAgreement', [lot, 1n, delegate])) return 'account whitelist permission';
  if (await read('ContractAgreement', [lot, 1n, tenant])) return 'contract permission requires manual review';
  return null;
};

const confirmed = (block) => {
  if (!block.block_hash || !Number.isSafeInteger(block.block_number)) throw new Error('A confirmed block is required');
  return block;
};

export const planStaleLotCleanup = async ({ provider, address, transactions, fromBlock }) => {
  const snapshot = confirmed(await provider.getBlockWithTxHashes('latest'));
  const hashes = new Set(transactions?.map(hex));
  if (fromBlock !== undefined) {
    if (!Number.isSafeInteger(fromBlock) || fromBlock < 0 || fromBlock > snapshot.block_number) {
      throw new Error('fromBlock must be between zero and the latest confirmed block');
    }
    for await (const event of events(provider, address, fromBlock, snapshot.block_number, [[hex(plannedEvent)]])) {
      hashes.add(hex(event.transaction_hash));
    }
  }
  const blocks = new Map();
  for (const tx of hashes) {
    const receipt = await provider.getTransactionReceipt(tx);
    if (receipt.execution_status !== 'SUCCEEDED' || !receipt.block_hash || !Number.isSafeInteger(receipt.block_number)) {
      throw new Error(`Planning transaction ${tx} is not confirmed and successful`);
    }
    if (receipt.block_number > snapshot.block_number) throw new Error(`Transaction ${tx} is newer than the snapshot`);
    if (blocks.has(receipt.block_number) && !same(blocks.get(receipt.block_number), receipt.block_hash)) {
      throw new Error('Planning block was reorganized');
    }
    blocks.set(receipt.block_number, receipt.block_hash);
  }

  const rows = [];
  const found = new Set();
  for (const [number, expectedHash] of blocks) {
    const block = confirmed(await provider.getBlockWithReceipts(number));
    if (!same(block.block_hash, expectedHash)) throw new Error('Planning block was reorganized');
    const overrides = new Map();
    const read = stateAt(provider, address, block.parent_hash, overrides);
    const blockRows = [];
    for (const { receipt } of block.transactions) {
      for (const event of receipt.events) {
        if (!same(event.from_address, address)) continue;
        const update = componentUpdate(event);
        if (update) {
          overrides.set(update.key, update.word);
          if (update.name === 'Unique' && update.path.length === 2 && update.path[0] === useLot) {
            for (const row of blockRows) {
              if (same(row.lot, update.path[1])) row.reason = 'tenancy was written again after planning';
            }
          }
        }
        if (!same(event.keys[0], plannedEvent) || !hashes.has(hex(receipt.transaction_hash))) continue;
        found.add(hex(receipt.transaction_hash));
        const d = event.data.map(BigInt);
        if (d.length !== 11 || d[0] !== 5n || d[3] !== 3n || d[5] !== 4n || d[8] !== 1n) {
          throw new Error('Unsupported ConstructionPlanned event');
        }
        const building = entity(d[0], d[1]);
        const asteroid = entity(d[3], d[4]);
        const lot = entity(d[5], d[6]);
        const planner = entity(d[8], d[9]);
        const tenant = await read('Unique', [useLot, lot]);
        const asteroidController = await read('Control', [asteroid]);
        const row = {
          lot: hex(lot), building: hex(building), tenant: hex(tenant),
          lotId: d[6].toString(), buildingId: d[1].toString(), tenantCrewId: (tenant >> 16n).toString(),
          planner: hex(planner), asteroid: hex(asteroid), asteroidControllerAtPlanning: hex(asteroidController),
          transactionHash: hex(receipt.transaction_hash), blockNumber: block.block_number,
          blockHash: block.block_hash, plannedAt: block.timestamp, reason: null
        };
        if (!tenant) row.reason = 'no tenant record at planning';
        else if (tenant === planner) row.reason = 'tenant planned their own building';
        else if (!await sameController(read, planner, asteroidController)) {
          row.reason = 'planner was not the asteroid controller';
        } else if (await read('Unique', [lotUse, lot]) !== building) {
          row.reason = 'planning occupancy does not match';
        } else {
          row.reason = await permissionBlocker(read, lot, tenant, block.timestamp);
          row.agreement = hex(await read('PrepaidAgreement', [lot, 1n, tenant]));
        }
        blockRows.push(row);
        rows.push(row);
      }
    }
  }
  for (const tx of hashes) {
    if (!found.has(tx)) throw new Error(`No ConstructionPlanned event for this Dispatcher in ${tx}`);
  }

  // Even writing the same tenant again is a new tenancy. Never erase it on the
  // strength of an older planning event.
  const candidates = rows.filter((row) => !row.reason);
  if (candidates.length) {
    const byLot = new Map();
    for (const row of candidates) {
      if (!byLot.has(row.lot)) byLot.set(row.lot, []);
      byLot.get(row.lot).push(row);
    }
    const firstBlock = Math.min(...candidates.map((row) => row.blockNumber)) + 1;
    if (firstBlock <= snapshot.block_number) {
      for await (const event of events(provider, address, firstBlock, snapshot.block_number, [[hex(componentEvent)], [hex(felt('Unique'))]])) {
        const update = componentUpdate(event);
        if (update.path.length !== 2 || update.path[0] !== useLot) continue;
        for (const row of byLot.get(hex(update.path[1])) || []) {
          if (event.block_number > row.blockNumber) {
            row.reason = 'tenancy was written again after planning';
          }
        }
      }
    }
  }
  const read = stateAt(provider, address, snapshot.block_hash);
  const seen = new Set();
  for (const row of rows) {
    if (!row.reason) row.reason = await currentBlocker(read, row, snapshot.timestamp);
    if (!row.reason && seen.has(row.lot)) row.reason = 'duplicate lot';
    if (!row.reason) seen.add(row.lot);
    row.status = row.reason ? 'skip' : 'clear';
  }
  return { address, chainId: await provider.getChainId(), snapshot: {
    blockNumber: snapshot.block_number, blockHash: snapshot.block_hash
  }, rows };
};

const currentBlocker = async (read, row, timestamp) => {
  const lot = BigInt(row.lot);
  const tenant = BigInt(row.tenant);
  const currentTenant = await read('Unique', [useLot, lot]);
  if (!currentTenant) return 'already cleared';
  if (currentTenant !== tenant) return 'tenant changed';
  if (await read('Unique', [lotUse, lot]) !== BigInt(row.building)) return 'building changed or was abandoned';
  if (await read('PrepaidAgreement', [lot, 1n, tenant]) !== BigInt(row.agreement)) return 'agreement changed';
  return permissionBlocker(read, lot, tenant, timestamp);
};

export const assertTenancyPaused = async (provider, address) => {
  const block = confirmed(await provider.getBlockWithTxHashes('latest'));
  const results = await Promise.all(TENANCY_SYSTEMS.map((name) => provider.callContract({
    contractAddress: address, entrypoint: 'system', calldata: [hex(felt(name))]
  }, block.block_hash)));
  const active = TENANCY_SYSTEMS.filter((_, i) => results[i].length !== 1 || BigInt(results[i][0]) !== 0n);
  if (active.length) throw new Error(`Cleanup requires maintenance: unregister these systems first (class hash 0): ${active.join(', ')}`);
};

export const applyStaleLotCleanup = async ({ provider, dispatcher, account, plan, options = {}, log = console.log }) => {
  if (!same(dispatcher.address, plan.address) || !same(await provider.getChainId(), plan.chainId)) throw new Error('Cleanup network mismatch');
  const canonical = await provider.getBlockWithTxHashes(plan.snapshot.blockNumber);
  if (!same(canonical.block_hash, plan.snapshot.blockHash)) throw new Error('Cleanup snapshot was reorganized');
  await assertTenancyPaused(provider, dispatcher.address);
  dispatcher.connect(account);
  for (const row of plan.rows.filter((item) => item.status === 'clear')) {
    await assertTenancyPaused(provider, dispatcher.address);
    const block = confirmed(await provider.getBlockWithTxHashes('latest'));
    // The command builds its plan after maintenance starts. Refuse to apply a
    // saved/outdated plan without checking every intervening tenancy write.
    if (block.block_number > plan.snapshot.blockNumber) {
      for await (const event of events(provider, dispatcher.address, plan.snapshot.blockNumber + 1, block.block_number,
        [[hex(componentEvent)], [hex(felt('Unique'))]])) {
        const update = componentUpdate(event);
        if (update.path.length === 2 && update.path[0] === useLot && same(update.path[1], row.lot)) {
          throw new Error(`Tenancy changed since planning cleanup for ${row.lot}; rerun the dry run`);
        }
      }
    }
    const reason = await currentBlocker(stateAt(provider, dispatcher.address, block.block_hash), row, block.timestamp);
    if (reason === 'already cleared') { log(`Skipping ${row.lot}: already cleared`); continue; }
    if (reason) throw new Error(`Refusing cleanup for ${row.lot}: ${reason}`);
    const result = await dispatcher.compileAndInvoke('run_system', {
      name: 'WriteComponent', calldata: ['Unique', 2n, 'UseLot', BigInt(row.lot), 1n, 0n]
    }, options);
    log(`Clearing ${row.lot}: ${result.transaction_hash}`);
    const receipt = await account.waitForTransaction(result.transaction_hash);
    if (receipt.execution_status !== 'SUCCEEDED') throw new Error(`Cleanup transaction did not succeed: ${result.transaction_hash}`);
    const remaining = await provider.getStorageAt(dispatcher.address, componentKey('Unique', [useLot, BigInt(row.lot)]), 'latest');
    if (BigInt(remaining) !== 0n) throw new Error(`Cleanup not reflected on chain for ${row.lot}`);
  }
};
