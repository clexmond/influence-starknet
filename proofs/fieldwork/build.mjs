import { createHash, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as snarkjs from 'snarkjs';

const root = dirname(fileURLToPath(import.meta.url));
const directory = resolve(root, 'target/proof');
const base = resolve(directory, 'campaign');
const setup = process.argv.includes('--setup-development');
const outputIndex = process.argv.indexOf('--output');
const output = outputIndex < 0 ? null : resolve(process.argv[outputIndex + 1]);
const scarb = process.env.SCARB_2_16_BIN || 'scarb';
const run = (program, args, cwd = root) => execFileSync(program, args, { cwd, stdio: 'inherit' });
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const json = async file => JSON.parse(await readFile(file, 'utf8'));
const writeJSON = (file, value) => writeFile(file, JSON.stringify(value, null, 2) + '\n');

if (!execFileSync(scarb, ['--version'], { encoding: 'utf8' }).startsWith('scarb 2.16.1')) {
  throw new Error('Set SCARB_2_16_BIN to Scarb 2.16.1; the game uses a separate compiler.');
}
await mkdir(directory, { recursive: true });
run(resolve(root, 'node_modules/.bin/circom2'), [
  'circuits/campaign.circom', '--r1cs', '--wasm', '--O2', '-o', directory
]);
const r1csSha256 = sha256(await readFile(`${base}.r1cs`));
if (setup) {
  if (!process.env.PROSPECTING_PTAU) throw new Error('Set PROSPECTING_PTAU to the development powers-of-tau file.');
  await snarkjs.zKey.newZKey(`${base}.r1cs`, resolve(process.env.PROSPECTING_PTAU), `${base}.initial.zkey`);
  await snarkjs.zKey.contribute(`${base}.initial.zkey`, `${base}.zkey`,
    'INFLUENCE DEVELOPMENT ONLY', randomBytes(32).toString('hex'));
  await rm(`${base}.initial.zkey`);
  await writeJSON(`${base}.vk.json`, await snarkjs.zKey.exportVerificationKey(`${base}.zkey`));
  run(process.env.GARAGA_BIN || 'garaga', [
    'gen', '--system', 'groth16', '--vk', `${base}.vk.json`,
    '--project-name', 'groth16', '--no-include-test-sample'
  ]);
  const manifest = resolve(root, 'groth16/Scarb.toml');
  await writeFile(manifest, (await readFile(manifest, 'utf8')).replace(/\[dev-dependencies\][\s\S]*?(?=\[)/, ''));
  await writeJSON(resolve(directory, 'key.json'), { r1csSha256 });
} else {
  const previous = await json(resolve(directory, 'key.json'));
  if (previous.r1csSha256 !== r1csSha256) {
    throw new Error('The circuit changed. Run setup:development explicitly to replace development keys.');
  }
  const vk = await snarkjs.zKey.exportVerificationKey(`${base}.zkey`);
  if (JSON.stringify(vk) !== JSON.stringify(await json(`${base}.vk.json`))) throw new Error('Proving and verification keys differ.');
}
for (const manifest of ['ecip/Scarb.toml', 'groth16/Scarb.toml', 'Scarb.toml']) {
  run(scarb, ['--manifest-path', resolve(root, manifest), 'build']);
}
const manifest = {
  circuit: 'fieldwork-r7-volume150-p10-v1', developmentOnly: true, maxSamples: 10,
  padding: 'zero', r1csSha256
};
for (const [name, source, file] of [
  ['library', resolve(root, 'node_modules/snarkjs/build/snarkjs.min.js'), 'snarkjs.min.js'],
  ['wasm', `${base}_js/campaign.wasm`, 'campaign-padded10.wasm'],
  ['zkey', `${base}.zkey`, 'campaign-padded10.zkey'],
  ['vk', `${base}.vk.json`, 'campaign-padded10.vk.json']
]) {
  const bytes = await readFile(source);
  manifest[name] = { file, bytes: bytes.length, sha256: sha256(bytes) };
  await copyFile(source, resolve(directory, file));
}
await writeJSON(resolve(directory, 'manifest.json'), manifest);
if (output) {
  await mkdir(output, { recursive: true });
  let previous;
  try { previous = await json(resolve(output, 'manifest.json')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  for (const name of ['library', 'wasm', 'zkey', 'vk']) {
    await copyFile(resolve(directory, manifest[name].file), resolve(output, manifest[name].file));
  }
  await writeJSON(resolve(output, 'manifest.json'), manifest);
  const keep = new Set(['library', 'wasm', 'zkey', 'vk'].map(name => manifest[name].file));
  const oldAssets = previous?.samples ? Object.values(previous.samples) : [previous];
  for (const old of oldAssets.filter(Boolean)) for (const name of ['wasm', 'zkey', 'vk']) {
    const file = old[name]?.file;
    if (file && /^[\w.-]+$/.test(file) && !keep.has(file)) await rm(resolve(output, file), { force: true });
  }
}
console.log(`Built one padded circuit and verifier for 1–${manifest.maxSamples} samples.`);
process.exit(0);
