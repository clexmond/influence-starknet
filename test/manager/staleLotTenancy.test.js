import assert from 'node:assert/strict';
import { test } from 'node:test';
import { hash, shortString } from 'starknet';
import {
  applyStaleLotCleanup, componentKey, componentUpdate, planStaleLotCleanup
} from '../../bin/lib/staleLotTenancy.js';

const felt = (name) => BigInt(shortString.encodeShortString(name));
const entity = (label, id) => BigInt(label) + (BigInt(id) << 16n);
const address = '0x123';
const owner = entity(1, 1);
const tenant = entity(1, 2);
const stranger = entity(1, 3);
const asteroid = entity(3, 1);
const lot = entity(4, 1n + (1001n << 32n));
const building = entity(5, 42);
const lease = 3600n + (100n << 64n) + (20n << 92n) + (100n << 128n) + (200n << 164n);
const usePath = [felt('UseLot'), lot];
const agreementPath = [lot, 1n, tenant];
const update = (name, path, values, version = 0) => ({
  from_address: address,
  keys: [hash.getSelectorFromName('ComponentUpdated'), `0x${felt(name).toString(16)}`, ...(version ? [String(version)] : [])],
  data: [path.length, ...path, ...values].map(String)
});

const fixture = () => {
  const before = new Map();
  const current = new Map();
  const put = (map, name, path, value) => map.set(componentKey(name, path), value);
  put(before, 'Unique', usePath, tenant);
  put(before, 'PrepaidAgreement', agreementPath, lease);
  put(before, 'Control', [asteroid], owner);
  put(before, 'Crew', [owner], 111n);
  put(before, 'Crew', [tenant], 222n);
  put(before, 'Crew', [stranger], 333n);
  for (const [key, value] of before) current.set(key, value);
  put(current, 'Unique', [felt('LotUse'), lot], building);
  const planned = {
    from_address: address, keys: [hash.getSelectorFromName('ConstructionPlanned')],
    data: [5, 42, 1, 3, 1, 4, lot >> 16n, 173100, 1, 1, 111].map(String)
  };
  const planningReceipt = {
    transaction_hash: '0xaabb', block_number: 10, block_hash: '0x10', execution_status: 'SUCCEEDED',
    events: [update('Unique', [felt('LotUse'), lot], [building]), update('Control', [building], [1, 1]), planned]
  };
  const block = { block_number: 10, block_hash: '0x10', parent_hash: '0x9', timestamp: 300,
    transactions: [{ receipt: planningReceipt }] };
  const snapshot = { block_number: 20, block_hash: '0x20', timestamp: 500 };
  const later = [];
  const submissions = [];
  const f = {
    before, current, put, block, snapshot, planned, later, planningReceipt, submissions, paused: true,
    provider: {
      getChainId: async () => '0x534e5f5345504f4c4941',
      getBlockWithTxHashes: async () => snapshot,
      getTransactionReceipt: async () => planningReceipt,
      getBlockWithReceipts: async () => block,
      getStorageAt: async (_address, key, blockHash) => (blockHash === '0x9' ? before : current).get(key) || 0n,
      getEvents: async ({ keys, from_block, to_block }) => ({
        events: BigInt(keys[0][0]) === BigInt(planned.keys[0])
          ? [{ ...planned, block_number: 10, transaction_hash: '0xaabb' }]
          : later.filter((event) => event.block_number >= from_block.block_number && event.block_number <= to_block.block_number)
      }),
      callContract: async () => [f.paused ? '0x0' : '0x1']
    },
    dispatcher: {
      address, connect: () => {},
      compileAndInvoke: async (...args) => {
        submissions.push(args);
        put(current, 'Unique', usePath, 0n);
        return { transaction_hash: '0xcccc' };
      }
    },
    account: { waitForTransaction: async () => ({ execution_status: 'SUCCEEDED' }) }
  };
  f.plan = () => planStaleLotCleanup({ provider: f.provider, address, transactions: ['0xaabb'] });
  f.apply = (plan) => applyStaleLotCleanup({ provider: f.provider, dispatcher: f.dispatcher, account: f.account, plan, log: () => {} });
  return f;
};

test('storage keys match the vectors asserted against Cairo components::resolve', () => {
  assert.equal(componentKey('Unique', usePath), '0x6db83780c4781b5cd7df5a6a395df96d0b89e034e1c3f92db4764b714e76278');
  assert.equal(componentKey('PrepaidAgreement', agreementPath), '0x265f758e03d26d386c92d3717f24c5fe8edac4ee5af096115b02104a76acd4f');
});

test('decodes Cairo component event layouts, including Crew version 1', () => {
  assert.equal(componentUpdate(update('PrepaidAgreement', agreementPath, [3600, 100, 20, 100, 200, 0])).word, lease);
  assert.equal(componentUpdate(update('Control', [asteroid], [1, 2])).word, tenant);
  assert.equal(componentUpdate(update('Crew', [owner], [111, 0, 0, 0, 0, 0, 0, 0, 0, 0], 1)).word, 111n);
  assert.throws(() => componentUpdate(update('Unique', usePath, [tenant], 9)), /Unsupported/);
  assert.throws(() => componentUpdate(update('PrepaidAgreement', agreementPath, [3600])), /Invalid/);
});

test('dry run proves stale tenancy without writes', async () => {
  const f = fixture();
  const plan = await f.plan();
  assert.equal(plan.rows[0].status, 'clear');
  assert.equal(BigInt(plan.rows[0].tenant), tenant);
  assert.equal(f.submissions.length, 0);
});

test('can discover planning transactions from a block range', async () => {
  const f = fixture();
  const plan = await planStaleLotCleanup({ provider: f.provider, address, fromBlock: 8 });
  assert.equal(plan.rows[0].status, 'clear');
  await assert.rejects(planStaleLotCleanup({ provider: f.provider, address, fromBlock: -1 }), /fromBlock/);
});

test('uses historical ownership even after the asteroid changes hands', async () => {
  const f = fixture();
  f.put(f.current, 'Control', [asteroid], stranger);
  assert.equal((await f.plan()).rows[0].status, 'clear');
});

test('does not clear a legitimate tenant who later acquires the asteroid', async () => {
  const f = fixture();
  f.planned.data[9] = '2';
  f.put(f.current, 'Control', [asteroid], tenant);
  assert.match((await f.plan()).rows[0].reason, /own building/);
});

test('current ownership does not substitute for ownership at planning', async () => {
  const f = fixture();
  f.put(f.before, 'Control', [asteroid], stranger);
  assert.match((await f.plan()).rows[0].reason, /not the asteroid controller/);
});

test('recognizes another owner crew by its historical delegate', async () => {
  const f = fixture();
  f.planned.data[9] = '3';
  f.put(f.before, 'Crew', [stranger], 111n);
  assert.equal((await f.plan()).rows[0].status, 'clear');
});

for (const [name, word] of [
  ['lease active at planning', lease + (200n << 164n)],
  ['exact expiry boundary', lease + (100n << 164n)],
  ['notice active at planning', lease + (300n << 200n)]
]) {
  test(`preserves ${name}`, async () => {
    const f = fixture();
    f.put(f.before, 'PrepaidAgreement', agreementPath, word);
    assert.match((await f.plan()).rows[0].reason, /still active/);
  });
}

test('replays changes earlier in the same transaction before classifying the plan', async () => {
  const f = fixture();
  f.planningReceipt.events.unshift(update('PrepaidAgreement', agreementPath, [3600, 100, 20, 100, 400, 0]));
  assert.match((await f.plan()).rows[0].reason, /still active/);
});

test('replays ownership changes in earlier transactions in the same block', async () => {
  const f = fixture();
  f.block.transactions.unshift({ receipt: { transaction_hash: '0x1234', events: [update('Control', [asteroid], [1, 3])] } });
  assert.match((await f.plan()).rows[0].reason, /not the asteroid controller/);
});

for (const withinBlock of [true, false]) {
  test(`preserves same-tenant renewals ${withinBlock ? 'later in the same block' : 'in later blocks'}`, async () => {
    const f = fixture();
    const event = update('Unique', usePath, [tenant]);
    if (withinBlock) f.planningReceipt.events.push(event);
    else f.later.push({ ...event, block_number: 15 });
    assert.match((await f.plan()).rows[0].reason, /written again/);
  });
}

for (const [name, path, value, reason] of [
  ['Unique', usePath, 0n, /already cleared/],
  ['Unique', usePath, stranger, /tenant changed/],
  ['Unique', [felt('LotUse'), lot], 0n, /abandoned/],
  ['Unique', [felt('LotUse'), lot], entity(5, 43), /building changed/],
  ['PrepaidAgreement', agreementPath, lease + 1n, /agreement changed/],
  ['WhitelistAgreement', agreementPath, 1n, /crew whitelist/],
  ['WhitelistAgreement', [lot, 1n, 222n], 1n, /account whitelist/],
  ['PublicPolicy', [lot, 1n], 1n, /public/],
  ['ContractAgreement', agreementPath, 777n, /manual review/],
  ['Crew', [tenant], 0n, /crew is missing/]
]) {
  test(`skips changed current state: ${name} ${reason}`, async () => {
    const f = fixture();
    f.put(f.current, name, path, value);
    assert.match((await f.plan()).rows[0].reason, reason);
  });
}

test('handles paginated renewal events', async () => {
  const f = fixture();
  f.provider.getEvents = async ({ continuation_token }) => continuation_token
    ? { events: [{ ...update('Unique', usePath, [tenant]), block_number: 15 }] }
    : { events: [], continuation_token: 'next' };
  assert.match((await f.plan()).rows[0].reason, /written again/);
});

test('stops rather than guessing when archival RPC reads fail', async () => {
  const f = fixture();
  f.provider.getStorageAt = async () => { throw new Error('archive unavailable'); };
  await assert.rejects(f.plan(), /archive unavailable/);
  assert.equal(f.submissions.length, 0);
});

test('rejects a planning block reorganization', async () => {
  const f = fixture();
  f.planningReceipt.block_hash = '0xdead';
  await assert.rejects(f.plan(), /reorganized/);
});

test('apply only zeros UseLot and verifies the transaction', async () => {
  const f = fixture();
  await f.apply(await f.plan());
  assert.deepEqual(f.submissions, [['run_system', {
    name: 'WriteComponent', calldata: ['Unique', 2n, 'UseLot', lot, 1n, 0n]
  }, {}]]);
  assert.equal(f.current.get(componentKey('PrepaidAgreement', agreementPath)), lease);
  assert.equal(f.current.get(componentKey('Unique', [felt('LotUse'), lot])), building);
});

test('refuses writes while gameplay tenancy systems remain registered', async () => {
  const f = fixture();
  const plan = await f.plan();
  f.paused = false;
  await assert.rejects(f.apply(plan), /maintenance/);
  assert.equal(f.submissions.length, 0);
});

test('revalidates current state before each write', async () => {
  const f = fixture();
  const plan = await f.plan();
  f.put(f.current, 'Unique', usePath, stranger);
  await assert.rejects(f.apply(plan), /tenant changed/);
  assert.equal(f.submissions.length, 0);
});

test('rejects same-tenant writes after the dry-run snapshot', async () => {
  const f = fixture();
  const plan = await f.plan();
  f.snapshot.block_number = 21;
  f.later.push({ ...update('Unique', usePath, [tenant]), block_number: 21 });
  await assert.rejects(f.apply(plan), /Tenancy changed since/);
  assert.equal(f.submissions.length, 0);
});

test('already-cleared records are idempotent', async () => {
  const f = fixture();
  const plan = await f.plan();
  await f.apply(plan);
  await f.apply(plan);
  assert.equal(f.submissions.length, 1);
  assert.match((await f.plan()).rows[0].reason, /already cleared/);
});

test('never resubmits an uncertain cleanup transaction', async () => {
  const f = fixture();
  f.account.waitForTransaction = async () => { throw new Error('timeout'); };
  await assert.rejects(f.apply(await f.plan()), /timeout/);
  assert.equal(f.submissions.length, 1);
});

test('stops on a reverted cleanup transaction', async () => {
  const f = fixture();
  f.account.waitForTransaction = async () => ({ execution_status: 'REVERTED' });
  await assert.rejects(f.apply(await f.plan()), /0xcccc/);
  assert.equal(f.submissions.length, 1);
});

test('rejects a cleanup snapshot reorganization and a different chain', async () => {
  const f = fixture();
  const plan = await f.plan();
  f.snapshot.block_hash = '0xdead';
  await assert.rejects(f.apply(plan), /reorganized/);
  f.provider.getChainId = async () => '0x1';
  await assert.rejects(f.apply(plan), /network mismatch/);
  assert.equal(f.submissions.length, 0);
});
