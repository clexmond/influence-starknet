import fs from 'node:fs';

export const fixtures = JSON.parse(fs.readFileSync(new URL('./fixtures.json', import.meta.url), 'utf8'));

export function createFixtureRecord(Prospecting, n) {
  const { input } = fixtures.find(fixture => fixture.n === n);
  return { ...Prospecting.createRecord({ mode: 'local-simulation', context: input.context,
    identity: { chainId: '0x1', game: '0x2', owner: '0x3', asteroidId: 1, originIndex: Number(input.origin), resource: 1 } }),
  claimIndex: Number(input.selected), actions: input.methods.map((method, i) => ({
    action: { method: Number(method), target: Number(input.targets[i]), source: Number(input.sources[i]),
      depth: Number(input.depths[i]), salt: String(input.salts[i]) },
    meta: String(input.meta[i]), mask: String(input.blockedApproaches[i]), randomness: String(input.randomness[i]) })) };
}
