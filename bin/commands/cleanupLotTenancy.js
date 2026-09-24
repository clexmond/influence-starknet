import fs from 'node:fs/promises';
import ibis from '@influenceth/ibis';
import { applyStaleLotCleanup, assertTenancyPaused, planStaleLotCleanup } from '../lib/staleLotTenancy.js';

const cleanupLotTenancy = async ({ network, account, input, fromBlock, output, apply = false, maxFee, tip }) => {
  const { provider, contracts } = ibis(network);
  const dispatcher = contracts.deployed('Dispatcher');
  let transactions;
  if (input) {
    transactions = JSON.parse(await fs.readFile(input, 'utf8'));
    if (!Array.isArray(transactions) || !transactions.every((tx) => typeof tx === 'string' && /^0x[0-9a-f]+$/i.test(tx))) {
      throw new Error('Input must be a JSON array of planning transaction hashes');
    }
  }
  if (apply) await assertTenancyPaused(provider, dispatcher.address);
  const plan = await planStaleLotCleanup({ provider, address: dispatcher.address, transactions, fromBlock });
  const report = JSON.stringify({ network, ...plan }, null, 2);
  if (output) await fs.writeFile(output, `${report}\n`);
  else console.log(report);
  console.log(`${apply ? 'Cleanup' : 'Dry run'}: ${plan.rows.filter((row) => row.status === 'clear').length} stale records; ${plan.rows.filter((row) => row.status === 'skip').length} skipped`);
  if (apply) {
    const options = {};
    if (maxFee != null) options.maxFee = BigInt(maxFee);
    if (tip != null) options.tip = BigInt(tip);
    await applyStaleLotCleanup({ provider, dispatcher, account, plan, options });
  }
  return plan;
};

export default cleanupLotTenancy;
