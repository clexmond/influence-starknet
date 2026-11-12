# Single prospecting proof

`fieldwork-r7-volume150-p10-v1` uses one ten-slot circuit and one Groth16 key for
campaigns of 1–10 real samples. The count is bound into the existing claim header.
Unused inputs must be zero and disabled steps preserve the state. The prefix sponge
returns the real transcript's digest, so padding adds no calldata or on-chain hashing.
Record schemas, game rules and claim quantities/rates are unchanged.

## Build

Use Node 22 and install pinned dependencies with `npm --prefix proofs/fieldwork ci`.
Set `SCARB_2_16_BIN` to Scarb 2.16.1; the main game continues to use Scarb 2.7.0.

The initial **disposable development setup** additionally requires Garaga CLI 1.1.0
(`GARAGA_BIN`) and a development powers-of-tau file (`PROSPECTING_PTAU`):

```sh
npm run setup-prospecting-proof
```

This explicitly replaces the local development key, regenerates the Groth16 Cairo
constants and builds ECIP, Groth16 and the transcript adapter. It is not a production
ceremony. Once keys exist, rebuild without replacing them:

```sh
npm run build-prospecting-proof
node proofs/fieldwork/build.mjs --output ../influence-client/public/prospecting-proofs
npm run export-prospecting
```

The normal build checks that R1CS and existing keys match. Publication copies one
WASM, proving key, verification key and snarkjs library with SHA-256 descriptors;
obsolete files listed by the prior manifest are removed. All large artifacts live
under ignored `target` directories. The SDK exporter consumes the root manifest
and validates the compiled verifier and asset hashes before exporting bindings.

From the SDK checkout, `npm run export-prospecting -- /path/to/influence-starknet`
refreshes all game/proof bindings. `src/scripts/generateProspectingFixtures.mjs`
can explicitly refresh proof fixtures after replacing a development key.

## Verification and deployment

The SDK pads the private witness; it computes the expected public digest from the
real samples first. The browser worker rejects old circuit IDs/manifests and checks
asset hashes before proving. The Cairo adapter constructor accepts one nonzero
Groth16 verifier address. It verifies the actual count, statement shape and digest.

The root runtime harness proves all ten lengths through that same adapter, followed
by crew/drill consumption, claim finalization, mission observation, extraction and
replacement. Separate browser and witness tests cover the public worker and padding
constraints. See `docs/prospecting-contracts.md` for commands and activation order.

`manager deployProspectingProof --dryRun` prints an offline plan. Actual deployment
is explicit and never activates gameplay. Production setup/key selection remains
deferred; replacing a key requires refreshing assets, SDK bindings and deployed
verifier/adapter together.
