import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { hash } from 'starknet';

const output = path.resolve('target/prospecting');
fs.mkdirSync(output, { recursive: true });
const systems = ['ConfigureProspecting', 'ProspectingStart', 'ProspectingSample', 'ProspectingFinalize',
  'ProspectingAbandon', 'ReadProspectingCampaign', 'ReadProspectingSample', 'ReadProspectingRandomness',
  'ReadProspectingOrigin', 'PreviewProspectingSample', 'BaselineExtractResourceStart', 'ExtractResourceStart',
  'ExtractResourceFinish', 'SampleDepositStart', 'SampleDepositImprove', 'SampleDepositFinish',
  'Abundance', 'ConstructionFinish', 'ConstructionDeconstruct', 'TypeComponent', 'ReadComponent',
  'WriteComponent', 'MissionObserver', 'StarterMissionCampaign'];
const contracts = {};
const describeArtifact = (name, file) => {
  const artifact = JSON.parse(fs.readFileSync(file, 'utf8'));
  const abi = `${name}.abi.json`;
  fs.writeFileSync(path.join(output, abi), JSON.stringify(artifact.abi, null, 2) + '\n');
  return { abi, artifact: file, classHash: hash.computeContractClassHash(artifact),
    artifactSha256: createHash('sha256').update(fs.readFileSync(file)).digest('hex') };
};
const exportABI = (name, file) => { contracts[name] = describeArtifact(name, file); };
for (const name of systems) exportABI(name, `target/dev/contract_${name}.contract_class.json`);
exportABI('ProspectingVerifier', 'proofs/fieldwork/target/dev/prospecting_verifier_ProspectingVerifier.contract_class.json');
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify({
  version: 2, deployment: 'undeployed', rules: 'fieldwork-r7-volume150-v1',
  gameCompiler: '2.7.0', verifierCompiler: '2.16.1',
  activation: 'ConfigureProspecting', activationConstant: 'PROSPECTING_ENABLED',
  verifierRegistry: 'ProspectingVerifier', trustedSetup: 'deferred; no production keys selected',
  sampleLimit: 10, replacementSeconds: 86400, quantityMultiplierBps: 15000,
  samplingQualityBps: 10000, baselineThresholdPpm: 50000, baselineRateBps: 2500,
  legacyRateBps: 12000, missionMinimumQuantityKg: 1000000, contracts,
  proof: {
    ...JSON.parse(fs.readFileSync('proofs/fieldwork/target/proof/manifest.json', 'utf8')),
    verifier: describeArtifact('Groth16Verifier', 'proofs/fieldwork/groth16/target/dev/groth16_Groth16VerifierBN254.contract_class.json'),
    ecip: describeArtifact('UniversalECIP', 'proofs/fieldwork/ecip/target/dev/universal_ecip_UniversalECIP.contract_class.json')
  }
}, null, 2) + '\n');
fs.copyFileSync('docs/prospecting-contracts.md', path.join(output, 'README.md'));
console.log(`Wrote gameplay ABI and class-hash manifest to ${output}`);
