# Prospecting and unified mining contracts

Implementation checkpoint: 2026-11-12. No deployment or activation has been performed.

## Scope and dependencies

The game remains on Cairo/Scarb 2.7.0. `proofs/fieldwork` is a separate Cairo 2.16.1
package using Garaga 1.1.0. One padded Groth16 circuit supports every campaign
length from 1–10. Its immutable transcript adapter takes one verifier address,
checks the real-length Poseidon2 digest, and delegates to that shared verifier.
The game pins the adapter address when a prospecting campaign starts. Production trusted setup and key
selection remain deferred; the local tests use disposable sandbox keys.

The existing registered `Abundance` class supplies canonical local abundance via
its new `ppm` entry point. This keeps the noise implementation out of the larger
sampling/extraction classes. The implementation originally linked those functions
directly and devnet rejected the resulting sampling class as too large. Legacy
sampling finish still links the same original abundance algorithm directly, so a
later change to the registered lookup cannot change its completion arithmetic.

## Rules implemented

- A campaign belongs to a crew and occupies one starting lot, independently of
  resource and account. The crew's current delegate authorizes actions. Creation
  binds the creating account, crew, chain, Dispatcher, ID, origin, resource, rules,
  quality and verifier into an opaque native-Poseidon context.
- Creation and every new sample require effective `USE_LOT` access to the origin,
  including the existing lot tenancy rules. Lateral targets do not require surface
  access. Finalization and cancellation require crew delegation but no origin access.
- Every target must be a real lot on the same resource-scanned asteroid within
  3.5 km of the origin. A public mask records which previous sample lots are more
  than 1.5 km away. The circuit enforces private source, depth and collapsed-route
  legality. Five schematic depth bands remain 100–500 m. The current v7 circuit
  permits an initial Follow at any private depth on the origin; the current client
  initially exposes only the first band. Depth does not itself multiply yield/rate.
- There are 1–10 accepted samples. The expected index is checked before advancing
  or charging, preventing an old tab from appending a different action accidentally.
  Method, depth and salt remain private and are bound through the BN254 commitment.
- Every accepted sample consumes one `CORE_DRILL`, or one existing starter-pack
  core-sample entitlement when the inventory origin is empty. Accidents and misses
  still cost a sample. Reverts restore material, crew, campaign and event changes.
  New Explorer / Strategist / Industrialist grants provide 10 / 15 / 20 uses.
  Previously granted balances are unchanged; this is not a retroactive top-up.
- Any `RUNNING` extractor slot on the target lot blocks sampling, including finished
  jobs awaiting collection. There is no campaign lock on lateral lots and no
  historical recheck at finalization. Extraction can start after an accepted sample.
  Extractor deconstruction also checks every configured slot before proceeding.
- Sampling is performed from the origin surface lot. Crew and supplies travel to
  that origin, including when the investigated segment lies beneath another lot.
  Existing sample-time, hopper, distance and acceleration bonuses apply. Crew
  readiness includes the return trip; the sample's result time does not.
- Sampling quality is fixed at **10,000 BPS**, as confirmed for this integration.
  How crew prospecting skill affects grade/measurement probabilities is deferred;
  this release does not turn it into an extra quantity multiplier.
- A sample's target block is commitment block +2. Resolution requires both the
  scheduled drilling result time and current block >= target +10. Its fixed block
  hash is native-Poseidon hashed with `[7004, chain_id, Dispatcher, campaign_id,
  sample_index, block_hash]`; the low 64 bits provide the circuit entropy.
- The next commitment or finalization resolves the previous pending draw. Read-only
  randomness queries expose the same draw without a separate resolution transaction.
- Replacement is allowed at the latest scheduled result time +86,400 real seconds,
  or creation +86,400 before the first sample. Expiry alone does not invalidate an
  unreplaced campaign. Cancellation preserves this deadline and spends no refunds.
  Replacement atomically retires the previous ID, including any pre-generated proof.
- One final proof selects one productive portion and creates one claim on its lot.
  The game reconstructs the entire ordered statement from stored inputs. Quantity
  already includes the circuit's +50% reward; it is never boosted again on-chain.

## Components and identity

`Deposit` packing and IDs are unchanged. `Claim` is companion metadata:
`rules_version`, `rate_bps`, `reference_abundance_ppm`, `campaign_id`. Its packed
representation is one felt (16/16/20/64 bits). The sole spendable balance remains
`Deposit.remaining_yield`. Existing control, location, sale and permission paths
continue to use that same deposit entity.

| Component | Path | Purpose |
| --- | --- | --- |
| `ProspectingCampaign` | `[campaign_id]` | Crew, creator, origin, resource, context, pinned quality/router, resolved count, pending bit, status, replacement deadline and resulting deposit |
| `ProspectingCore` | `[campaign_id, index]` | Commitment, authenticated metadata/mask, resolved entropy and scheduling; four storage slots |
| `ProspectingOrigin` | `[packed_lot_entity]` | Current occupying campaign, including cancelled campaigns still in cooldown |
| `Claim` | Existing deposit path | Proven intrinsic parameters; absence means the pinned legacy default |
| `ExtractorSlots` | Existing building path | Contiguous configured slots, starting at 1; existing buildings without this component have their historical single slot |

Campaign statuses are `ACTIVE=1`, `CANCELLED=2`, `REPLACED=3`, `FINALIZED=4`.
`count` is resolved samples; accepted samples are `count + pending`. Claims survive
later campaigns because they are independent deposit entities. Creating a new
campaign does not overwrite a finalized claim.

The campaign is marked closed before calling the pinned verifier. A reverting or
false verification restores the previous state. Replacement cannot run against
that in-flight finalized state, and claim creation/origin release occur only after
successful verification.

Metadata caching uses `Unique` at `['ProspectingMeta', packed_origin, packed_target,
resource, packed_abundances, radius_magnitude]`. It contains public geography and
abundance, not private observations. Core metadata packs lot/offset-x/offset-z/local
PPM into 21/20/20/20 bits. Approach masks use ten bits, and entropy uses 64 bits.

## Systems and events

Arguments below precede the normal `caller_crew, Context` fields for gameplay
writes. The Dispatcher appends Context; callers do not supply an authoritative one.

| System | Arguments | Result/event |
| --- | --- | --- |
| `ProspectingStart` | `origin, resource` | ID; `ProspectingCampaignStarted`, including replaced ID |
| `ProspectingSample` | `campaign_id, lot, expected_index, commitment, inventory_origin, origin_slot` | `ProspectingSampleCommitted`, including metadata, mask, block/time targets and crew readiness |
| `ProspectingFinalize` | `campaign_id, lot, quantity, rate_bps, proof_span` | Deposit; `ProspectingCampaignFinalized` |
| `ProspectingAbandon` | `campaign_id` | `ProspectingCampaignAbandoned` |
| `ReadProspectingCampaign` | `campaign_id` | Raw campaign |
| `ReadProspectingSample` | `campaign_id, index` | Raw core |
| `ReadProspectingRandomness` | `campaign_id` | Mature pending draw |
| `ReadProspectingOrigin` | `origin` | Occupying ID or zero |
| `PreviewProspectingSample` | `campaign_id, lot` | Canonical metadata and approach mask |
| `BaselineExtractResourceStart` | `resource, quantity, extractor, slot, destination, destination_slot` | `ResourceExtractionStartedV1`, mode 0 |
| `ExtractResourceStart` | Existing signature | V1 event, mode 1 after activation; historical event before activation |
| `ConfigureProspecting` | `verifier` plus admin Context | Registry/activation events |

Read systems take only their listed arguments plus the usual appended Context.
The verifier accepts a Span of **u256** statement words and a Span of felt proof
arguments. Garaga's leading Span length is supplied exactly once by ABI encoding.
New gameplay ABIs differ from the SDK's earlier standalone sandbox contract adapter;
SDK bindings and server handlers must adopt the exported gameplay ABIs before use.
The shared SDK model/proof packet remains applicable, as exercised in runtime tests.
Private-record integration must scope records by chain, Dispatcher and campaign ID,
and retain finalized records independently of the next campaign on the same origin.
The existing encrypted local-save/remote-backup flow can then preserve each claim's
private observations without overwriting an earlier campaign.

Public events expose sample footprints, commitments, time targets and public claim
outputs. They do not include private depths, salts, observations or method choices.
`ComponentUpdated` also exposes raw campaign/core records. Server indexing must
recognize campaign-scoped paths rather than interpret every path as an entity UUID.

## Mining and legacy completion

All activated claim extraction uses a constant intrinsic rate, followed by ordinary
crew/asteroid bonuses. Missing Claim metadata means rule 1, **120%** of the selected
lot/resource reference rate. Explicit metadata pins its reference PPM and proven
rate. Depletion changes remaining quantity, not intrinsic speed. The existing
10,000,000 kg per-run quantity limit is enforced; the one-year reference duration
is not a hard extraction-time cap.

Baseline requires exact packed global abundance >= **50,000 PPM** and runs at
**25%** reference rate, using local abundance. It has no deposit or finite balance.
Trace materials remain accessible through claims. Claim and baseline modes share
inventory capacity/reservation, operational facility, extractor slot, crew/ship
readiness, travel, output transport and duration-sensitive permissions.

`ResourceExtractionStartedV1` includes mode, deposit (empty for baseline), resource,
quantity, extractor/slot, destination/slot, finish time, rate BPS, reference PPM,
crew and caller. Existing extraction finish is unchanged: it collects the stored
job, releases the exact reservation and never recalculates its duration or debits
a deposit again. Old running jobs therefore retain their output and timing.

Old sample/improvement starts reject after activation, including compositions that
reach those registered systems. Old finish remains available with its original
committed randomness and yield arithmetic; results become default-rate claims
without changing their quantity or creating a new entity. Historical improvements
cannot be applied to a new explicit Claim, even while prospecting is disabled.

Starter mission 1 retains its ID and reward. An observed `ProspectingFinalize` that
creates a claim of at least **1,000,000 kg (1,000 tonnes)** earns its requirement.
The observer binds the created entity and originating campaign, not client-reported
results. Legacy sample finishes no longer earn that requirement after activation.
Completed flags remain intact; partial historical sample counters do not satisfy
it. Baseline starts can participate in the normal extraction mission observation.

## Local build, tests and artifacts

Main game: `scarb build`, `scarb test`, and `npm run test-prospecting` (Scarb 2.7.0).
The proof package owns pinned Circom 2.2.0/snarkjs 0.7.6 dependencies and separate
Scarb 2.16.1 packages for ECIP, Groth16 and the adapter. Install its npm dependencies
with `npm --prefix proofs/fieldwork ci`. See `proofs/fieldwork/README.md` for compiler
selection, explicit disposable setup and asset publication. The normal build reuses
existing keys and refuses a changed R1CS. `generate-poseidon2.py` retains the pinned
Garaga 1.1.0 permutation generator.

`npm run build-prospecting-fixtures` compiles isolated admin-only runtime fixtures
beneath `temp/prospecting/runtime`; these are excluded from the production game.
`npm run test-prospecting-runtime` owns a fresh local chain on port 5056, refuses an
occupied port and stops its child on completion. Set `STARKNET_DEVNET_BIN` to the
local executable. It now uses this repository's proof assets and fixed regression
transcripts, rather than the old ten-key sandbox artifacts. SDK 2.9.0-rc.2 must be
installed in the client, or set `PROSPECTING_SDK_ROOT` to a built SDK checkout.
`PROSPECTING_BRIDGE_COUNTS=5` narrows the proof bridge checks; the default proves all
ten lengths through the same verifier before the complete gameplay workflow.

Set `PROSPECTING_CLIENT_CONTROLLER=1` to exercise the actual client controller and
server ABI decoders. `PROSPECTING_CLIENT_ROOT` and `PROSPECTING_SERVER_ROOT` override
the sibling repositories. `node --test test/prospecting/browser.test.js` checks the
actual public worker and hash-verified published assets in Chrome at 1/5/10 samples.
`node --test test/prospecting/circuit.test.js` checks every transcript and rejects
invalid count, padding, commitment and claim-selection witnesses.

After both builds, `npm run export-prospecting` writes ABI files, class hashes,
artifact hashes and integration constants to `target/prospecting`. This manifest
records an undeployed implementation; it does not claim a production key ceremony
or deployment readiness. It is the handoff for the next SDK/server integration.

The full Cairo regression suite passes: **717 tests, zero failures**.
Validation includes 27 focused Cairo tests for the campaign lifecycle, old pending
completions, baseline/claim extraction, slot conflicts and the starter mission.
The verifier bridge has accepted actual Groth16 proofs at all ten sample counts.
The complete devnet workflow passes with a freshly generated five-sample proof,
including altered-proof rejection, finalization after permission revocation,
mission credit, claim balance debiting, baseline/claim collection, every-slot
extraction blocking, cancellation cooldown and stale-proof rejection after replacement.

## Client/server integration checkpoint

The client now supports an explicit `App.prospectingMode=chain`, normal wallet and
mission-observed transactions, fixed future-block reconciliation, per-campaign
encrypted archives, and claim/baseline extraction through the regular dialog.
Local simulation remains the default. Legacy sampling starts are unavailable in
chain mode. Pending legacy samples and improvements use timed completion entries
in the same prospecting sidebar; old action/activity links redirect there instead
of opening legacy dialogs. Their original finish transaction needs neither private
campaign data nor a proof. Completion submits the sample owner's crew even when
another crew on the account is selected.

The server indexes the five new components, normalizes V1 extraction starts to the
existing activity family, and serves public campaign history. Its separate libp2p
worker retains authenticated ciphertext with durable acknowledgments and revision
checks. See the client's `src/game/prospecting/README.md` and the server's
`docs/prospecting.md` for mode selection, database preparation and peer configuration.

Local tests do not verify interactive wallet prompts, deployed indexing or public
WSS connectivity. Existing deployment configuration still needs explicit new-system
registration and the matching single verifier/adapter; ordinary `updateAll` alone
is not a complete prospecting deployment. The game configuration now includes the
new systems, and `deployProspectingProof` handles the separate proof package. No network configuration has been activated.

## Activation order

1. Build, test and review the game and verifier packages. Choose the appropriate
   development or production proving-key assets and their matching single verifier.
2. Declare the required Garaga ECIP operations class, deploy one Groth16 verifier,
   and deploy the immutable adapter with that one address.
3. Register the new/updated gameplay systems, Abundance, construction systems,
   component readers and mission observer listed in the manifest. Also update
   `GrantOffchainStarterPack` for the new 10 / 15 / 20 allowances alongside the
   matching server product catalog. Existing legacy finish/collection systems
   remain registered.
4. Update SDK/client transactions and server schemas/events together. Keep the
   activation constant zero until these consumers understand the new events.
5. Call `ConfigureProspecting` as admin. It verifies the router protocol, checks the
   updated legacy-start/extraction/abundance interfaces, checks required new systems,
   emits the verifier registry update, then activates the shared boundary atomically.

No Sepolia deployment, registry update or activation has been performed. SDK
2.9.0-rc.2 is published and installed in both client and server manifests/lockfiles.
Both installed bundles match the tested release, compiled contract manifest, shared
verification key and browser asset hashes. Local simulation remains the client
default until the Sepolia integration is deployed and explicitly activated.

## Proof deployment command

After building/exporting, review an offline plan:

```sh
npm run manager -- deployProspectingProof --network sepolia --dryRun --output temp/prospecting/sepolia-proof-plan.json
```

Without `--dryRun`, that command declares ECIP and deploys the single verifier and
adapter using deterministic, key-specific addresses. It verifies artifacts against
the exported manifest and reuses existing matching deployments. It never registers
systems or activates prospecting. Configure the normal deployment account and use
`--output` to retain the result when deployment is authorized. The command currently
targets devnet/Sepolia development keys; production setup remains a separate decision.
