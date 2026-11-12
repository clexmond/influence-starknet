import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { hash } from 'starknet';
import { declareClass } from './declareClass.js';
import { txOptions } from './dryRun.js';

export function createProofDeploymentPlan(manifest) {
  if (manifest.version !== 2 || manifest.proof?.circuit !== 'fieldwork-r7-volume150-p10-v1'
      || manifest.proof.maxSamples !== 10) throw new Error('Expected the single padded circuit manifest');
  const contract = (name, descriptor, constructorCalldata = []) => {
    const salt = hash.getSelectorFromName(`InfluenceProspecting:${name}`);
    return { name, ...descriptor, salt, constructorCalldata,
      address: hash.calculateContractAddressFromHash(salt, descriptor.classHash, constructorCalldata, 0) };
  };
  const verifier = contract('Groth16Verifier', manifest.proof.verifier);
  const bridge = contract('ProspectingVerifier', manifest.contracts.ProspectingVerifier, [verifier.address]);
  return { circuit: manifest.proof.circuit, developmentOnly: manifest.proof.developmentOnly,
    ecip: { name: 'UniversalECIP', ...manifest.proof.ecip }, verifier, bridge };
}

export function prepareProofDeployment(root = process.cwd()) {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'target/prospecting/manifest.json'), 'utf8'));
  const plan = createProofDeploymentPlan(manifest);
  const artifacts = {};
  for (const descriptor of [plan.ecip, plan.verifier, plan.bridge]) {
    const file = path.join(root, descriptor.artifact);
    const bytes = fs.readFileSync(file), contract = JSON.parse(bytes);
    if (createHash('sha256').update(bytes).digest('hex') !== descriptor.artifactSha256
        || hash.computeContractClassHash(contract) !== descriptor.classHash) {
      throw new Error(`Rebuild/export the proof artifacts: ${descriptor.name} changed`);
    }
    artifacts[descriptor.name] = { contract,
      casm: JSON.parse(fs.readFileSync(file.replace('.contract_class.json', '.compiled_contract_class.json'), 'utf8')) };
  }
  return { plan, artifacts };
}

export async function deployProspectingProof({ account, bundle, options = {} }) {
  const { plan, artifacts } = bundle;
  // Planning is offline. It does not pretend to estimate deployments whose
  // classes may not yet be declared on the selected network.
  if (options.dryRun) return { status: 'planned', ...plan };
  const contracts = {
    sierra: name => artifacts[name].contract,
    casm: name => artifacts[name].casm,
    declare: (name, { account }, details) => account.declare(artifacts[name], details)
  };
  const transactions = [];
  for (const descriptor of [plan.ecip, plan.verifier, plan.bridge]) {
    const declared = await declareClass({ contracts, contractName: descriptor.name, account, options,
      classHash: descriptor.classHash });
    if (declared.transaction_hash) transactions.push(declared.transaction_hash);
    if (descriptor === plan.ecip) continue;
    let exists = false;
    try {
      const actual = await account.getClassHashAt(descriptor.address);
      if (BigInt(actual) !== BigInt(descriptor.classHash)) throw new Error(`Unexpected class at ${descriptor.address}`);
      exists = true;
    } catch (error) {
      if (error.code !== 20 && !error.isType?.('CONTRACT_NOT_FOUND')) throw error;
    }
    if (exists) continue;
    const deployed = await account.deployContract({ classHash: descriptor.classHash,
      constructorCalldata: descriptor.constructorCalldata, salt: descriptor.salt, unique: false }, txOptions(options));
    if (BigInt(deployed.contract_address) !== BigInt(descriptor.address)) throw new Error('Unexpected proof deployment address');
    transactions.push(deployed.transaction_hash);
  }
  return { status: 'deployed', ...plan, transactions };
}
