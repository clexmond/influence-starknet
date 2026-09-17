# Starter mission spikes: findings

17 September 2026. Experimental, test-only code: `src/test/mission_spike.cairo`, included through the existing test-only module. No production mission systems, gameplay changes, declarations, deployments, or mainnet transactions.

## Decisions carried into the plan

- Starter enrollment requires crew ID strictly greater than configured X; existing crews are excluded from this campaign, not future colonization.
- Claims remain attached to crew identity and pay its delegate. The plan uses the current delegate at settlement; snapshotting a different delegate is not implemented.
- Completion creates a durable reward entitlement. Later invalidation blocks further earning but does not revoke completed/unclaimed rewards.
- Evidence needed by subsequent missions belongs in reusable campaign-owned opaque slots.
- Process thresholds and routes are deferred to the user. Colonization requirements and implementation are deferred until starter completion.
- Treat crew IDs at or below X as excluded contamination sources when moving members into newer crews, so a fresh destination ID cannot bypass exclusion. This is an implementation consequence of the exclusion/contamination combination; no eligibility code is implemented.

## Spike A: asynchronous action identity

### Experiments

Tests use existing ExtractResourceStart/Finish and ProcessProductsStart/Finish implementations with repository fixtures. Start a meaningful run, save its finish time, finish through the ordinary function at the earliest permitted timestamp, transfer the relevant gameplay controls in the fixture to another crew, and start a replacement with the same requested product/process/quantity. No mission wrapper mediates that replacement.

Both replacement runs have a strictly later finish time. The tests cover 500,000 units of water extraction and 1,000 recipes of ammonia catalytic cracking. Extraction uses the remaining deposit, so extraction duration itself can change; identity still separates the runs.

A boundary test colocates crew, extractor, deposit and destination and starts a zero-yield extraction. Existing code accepts it with zero duration. Finish and start again at the same block timestamp: the entire serialized Extractor component is identical. This is a concrete counterexample to universal finish-time or snapshot uniqueness, not a demonstrated exploit of a positive-threshold mission.

### Reasoning and recommendation

For a reusable slot, an ordinary replacement cannot start until the previous run has completed. Finish requires `now >= old_finish`. Start uses `crew.busy_until(now)`, which is at least now, plus nonnegative travel/production duration. If every replacement that could match the mission predicate has strictly positive duration, then:

```text
new_finish >= new_start_time + positive_duration > old_finish
```

This suggests a lower-storage binding using the building/slot, finish time, and required process/output/quantity/destination fields (or a commitment to those fields), stored in mission-owned evidence. A bare timestamp does not suffice. Reject zero-duration/nonqualifying candidates and verify the complete binding before invoking finish. The original initiating crew comes from the wrapped start, not from the finishing caller.

Do not add a global run generation counter yet. First finalize approved thresholds/recipes and prove that *every candidate capable of matching saved evidence* has positive duration. Checking positivity only on the original run is not sufficient. Extraction fixed-point rounding, process timing configurations, permitted config changes, and all lifecycle reset paths require that proof. Deconstruction currently requires processor/extractor idle, which helps, but the spike is not an exhaustive proof of all lifecycle paths or administration/upgrades.

If that condition cannot be guaranteed, the monotonic-generation contingency remains available. The spike supports a simpler conditional design, not a universal no-nonce claim.

## Spike B: nested execution and payments

### Experiments

A test-only Forwarder is registered as a normal system. Dispatcher executes it through a library call; it resolves and library-calls a second registered system with the serialized authenticated Context.

- Normal entry preserves Context.caller, timestamp, zero payment fields, immediate caller and Dispatcher execution address across both library calls.
- The existing ChangeName system succeeds through the forwarder and writes into the expected shared component storage.
- The payment-mediated entry preserves the payment sender in Context while the immediate caller remains the authorized payment contract. This confirms why deriving identity from the raw syscall in the wrapper would be wrong for this route.
- An ordinary account is rejected by the payment-mediated entrypoint.
- The real Sway class mints test funds and creates a confirmation receipt for Dispatcher. A nested consumer successfully consumes it; replay fails.
- The real FillSellOrder system is exercised through the forwarder, using its existing marketplace fixture and two real SWAY confirmation receipts (seller and market fee). This tests actual gameplay payment consumption rather than only an echo of Context fields.

The receipt replay failure is surfaced through the current Dispatcher's generic unwrap error. The positive receipt test verifies that the same setup succeeds on the first consumption; the negative test does not assert that nested revert reasons remain preserved in the final error string.

### Practical result

Use the existing ordinary `run_system` path for receipt-based marketplace actions, preserving the Dispatcher as receipt consumer. A separate mission/payment entrypoint is unnecessary. One wrapped gameplay action may consume multiple native receipts; that differs from reusing one payment context for multiple child actions.

The existing `run_system_with_payment` signature can forward its Context through the same wrapper. However, the local Sway source contains no caller implementation that invokes that Dispatcher entrypoint. Its authorization/context tests simulate the already-authorized caller boundary using Cairo testing helpers; they do not prove a deployed end-to-end token callback integration. The Dispatcher uses registry name `SWAY` for that entrypoint, while the active receipt/gameplay path uses `Sway`. Deployment configuration was not inspected and no normalization was applied.

Do not build a new payment callback for starter missions just to use the existing entrypoint. Support the native receipt flows actually used by gameplay, keep the same wrapper compatible with authenticated payment Context, and verify any future callback producer separately before advertising support.

### Scope and limitations

These are Cairo unit/integration-style tests with actual library/token syscalls and existing gameplay code, using test helpers for caller/address/time and fixtures. The outer Dispatcher functions are invoked through their contract-state testing API. There is no account transaction on devnet/mainnet and no production-ready wrapper: the test forwarder intentionally omits assignment validation and action allowlisting.

This spike does not establish complete rollback behavior under real account multicalls, callback/reentrancy safety, event-indexer compatibility, production ABI hardening, or declaration-fee savings. Those remain implementation validation tasks. No broad test suite was run because the changes are isolated experimental tests.

## Proposed capstone without batch tracking

Require the same valid crew to complete an approved *compatible production sequence*:

1. Complete a qualifying upstream process producing product P above its threshold.
2. Subsequently start and complete a qualifying downstream process whose recipe consumes P above its threshold.
3. Complete the selected final-output use or delivery objective.

Optionally bind the upstream destination to the downstream origin inventory for a visible operational connection. It still does not prove that identical material units were used. Purchased or replacement P is explicitly permitted. Existing goods do not qualify by themselves: each required production action must actually complete for the credited crew, in the required order.

Store route/stage progress and only the needed product/inventory/quantity references in campaign-owned packed slots. Fixed route definitions can make many values implicit. This avoids batch IDs, inventory tainting, reserved mission goods, observing unrelated withdrawals, and atomic multi-action handoffs. Finish one action per wrapper invocation.

The remaining work is choosing routes and thresholds, which is deferred. Mission text should describe compatible completed stages rather than promise physical provenance. This retains a stronger objective than owning buildings or holding bought finished goods, while accepting economic substitution between stages.

## Reproduction

```sh
scarb cairo-test -f mission_spike
```

Toolchain: Scarb/Cairo 2.7.0. Test inventory: normal context; authorized payment Context; rejected account payment Context; existing nested gameplay storage; real SWAY receipt; receipt replay rejection; extraction replacement; refinery replacement; zero-yield duplicate snapshot; actual marketplace fill. Final run: **10 passed, 0 failed, 397 filtered out**.
