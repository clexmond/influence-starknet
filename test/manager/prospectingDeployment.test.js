import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createProofDeploymentPlan, deployProspectingProof } from '../../bin/lib/prospectingDeployment.js';
import config from '../../influence.config.js';

const manifest = () => ({ version: 2, contracts: { ProspectingVerifier: { classHash: '0x123' } },
  proof: { circuit: 'fieldwork-r7-volume150-p10-v1', maxSamples: 10, developmentOnly: true,
    verifier: { classHash: '0x456' }, ecip: { classHash: '0x789' } } });

test('plans one verifier and a one-address adapter with deterministic key-specific addresses', () => {
  const plan = createProofDeploymentPlan(manifest());
  assert.deepEqual(plan.bridge.constructorCalldata, [plan.verifier.address]);
  assert.equal(plan.ecip.address, undefined);
  assert.deepEqual(createProofDeploymentPlan(manifest()), plan);
  const changed = manifest(); changed.proof.verifier.classHash = '0x999';
  const next = createProofDeploymentPlan(changed);
  assert.notEqual(next.verifier.address, plan.verifier.address);
  assert.notEqual(next.bridge.address, plan.bridge.address);
  assert.throws(() => createProofDeploymentPlan({ ...manifest(), version: 1 }), /single padded/);
});

test('offline planning performs no RPC or transaction calls', async () => {
  const account = new Proxy({}, { get() { throw new Error('Account was used'); } });
  const plan = createProofDeploymentPlan(manifest());
  assert.deepEqual(await deployProspectingProof({ account, bundle: { plan }, options: { dryRun: true } }),
    { status: 'planned', ...plan });
});

test('game deployment configuration includes the new sampling, read and baseline systems', () => {
  for (const network of ['devnet', 'sepolia', 'mainnet']) for (const name of [
    'ConfigureProspecting', 'ProspectingStart', 'ProspectingSample', 'ProspectingFinalize', 'ProspectingAbandon',
    'ReadProspectingCampaign', 'ReadProspectingSample', 'ReadProspectingRandomness', 'ReadProspectingOrigin',
    'PreviewProspectingSample', 'BaselineExtractResourceStart', 'Abundance', 'TypeComponent'
  ]) assert.equal(config[network][name].isSystem, true, `${network}/${name}`);
});
