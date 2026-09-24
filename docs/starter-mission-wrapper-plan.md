# Accepted missions and reusable campaigns: implementation plan

Updated 17 September 2026. The user subsequently authorized starter implementation and technical validation. See [implementation and integration notes](starter-missions-implementation.md) for the implemented interfaces, storage, supported payment paths, and tests. Colonization and player-created mission publishing remain deferred; no live-network deployment is authorized by this implementation task.

## 1. Chosen architecture

Players explicitly accept missions. Each subsequent mission action identifies its accepted assignment. A registered `MissionAction` system validates that assignment, library-calls an existing gameplay system, and verifies the result atomically. It uses the existing Dispatcher entrypoints: no mission-discovery scan and no new mission/payment entrypoint combinations.

Campaigns group missions and prerequisites. Starter, colonization, and future configured contracts use the same lifecycle and interfaces. Their rules live in their implementations, not branches inside the framework. The starter-specific cross-cutting exception is contamination enforcement in ordinary crew membership paths.

Design constraints:

- Explicit acceptance and assignment selection, with no automatic broadcast to all missions.
- Reusable campaigns with generic subjects, contributor policies and beneficiary policies.
- Existing `run_system` and `run_system_with_payment` signatures.
- Approved versioned implementations; players configure templates, never supply arbitrary Cairo.
- Packed lifecycle state and implementation-owned indexed felts. No shared temporary attribution cache or onchain event history.
- Reuse gameplay classes and typed helpers; avoid redeclaring gameplay systems for each mission.
- Preserve historical crew attribution rather than replace it with current ownership checks.

## 2. Generic concepts

| Concept | Responsibility |
| --- | --- |
| Mission template | Approved implementation/version and parameter schema; defines eligibility, action variants, completion checks and custom storage layout. |
| Mission definition | Immutable configured instance of a template, including reward terms. Shared by its assignments. |
| Campaign definition | Versioned collection of mission definitions, prerequisites and campaign policy implementation. Standalone missions do not need artificial campaigns. |
| Subject | Identity to which progress belongs: a tagged crew, asteroid, account or other supported identity. |
| Campaign participation | Subject-bound campaign state and pinned terms/version, created when its first mission is accepted. |
| Assignment | Acceptance of a mission by/for a subject, with lifecycle and claim protection. |
| Contributor | Actor permitted to perform work; need not equal subject or beneficiary. |
| Beneficiary | Recipient determined by the accepted reward policy, independently of who submits completion. |

The framework resolves accepted definitions and versions, namespaces storage, orchestrates execution, and enforces lifecycle/payment replay protection. Implementations determine gameplay predicates, contributor authorization, beneficiary rules and evidence encoding. Reward amounts and funding references are bound to accepted terms, not supplied freely by the caller.

No core enum or conditional should mean “starter campaign” or “colonization campaign.” Both must use identical interfaces. New mechanics may require a new reviewed implementation, not a new core campaign type.

### Reusable campaigns and acceptance

1. `AcceptMission(definition_ref, subject, acceptance_arguments)` validates authority, eligibility and prerequisites through pinned implementations.
2. Acceptance of the first campaign mission creates campaign participation atomically. Subsequent assignments reuse it.
3. Pin definition/template/campaign versions and terms. Reacceptance cannot reset progress, revive invalidity or create another reward entitlement.
4. Prerequisites are a bounded graph supporting linear progression, independent branches and capstones. Shared definitions hold the graph; do not copy it per participant.
5. An accepted mission may retain narrowly scoped campaign evidence for later steps. This does not automatically accept or pay later missions or update unrelated campaigns.
6. Acceptance of the next mission can be batched with completion/claim when its prerequisites permit. There is no required global single-active-mission restriction: each action explicitly selects an assignment.

Campaign membership does not force one actor policy. Crew campaigns can require one crew throughout; asteroid campaigns can allow any contributor with one beneficiary. Evidence access between missions goes through the campaign implementation’s helpers, not ad hoc cross-component reads.

If colonization requires first-scan provenance, accept its first assignment before that scan, potentially in the same account multicall. The wrapped scan captures the qualifying scanner identity. Past scans cannot acquire trusted attribution retroactively from client-provided events. This is a template rule, not an implicit global scanner hook.

## 3. Registered systems and execution

Conceptual interfaces, not final Cairo ABI:

```text
AcceptMission(definition_ref, subject, acceptance_arguments, Context)
MissionAction(assignment_ref, action_kind, action_arguments, Context)
MissionValidate(assignment_ref, evidence_arguments, Context)
ClaimMissionReward(assignment_ref, Context)
```

An assignment reference can be a canonical tuple of definition/campaign instance, subject and mission index. A separate global assignment ID is optional. Repetition, if a future template permits it, requires an explicit occurrence identity and funded entitlement. Version changes must not reset claim identity.

```text
Account
  -> Dispatcher.run_system("MissionAction", payload)
     -> library call MissionAction.run(payload, authenticated Context)
        -> pinned mission.prepare(...)
        -> library call systems::get(approved_action).run(canonical arguments, same Context)
        -> pinned mission.finalize(..., in-memory preparation data, gameplay return data)
        -> commit evidence/lifecycle changes
```

The same wrapper can be the target of `run_system_with_payment` when invoked through its authenticated payment route. An ordinary account cannot directly invoke that entrypoint with fabricated payment data under current authorization.

### Trust and atomicity

- The outer Dispatcher creates Context and generates entropy. The wrapper forwards that Context once to its child; it does not reconstruct identity from transaction origin or nested client arguments.
- Do not externally call Dispatcher.run_system again. A contract self-call changes the direct caller to Dispatcher. Nested library execution preserves shared storage and caller context.
- Resolve mission code from approved registries and accepted versions, never a user-selected class hash or selector.
- Typed action variants validate crew/target relationships and construct canonical gameplay calldata. Reject trailing calldata, unsupported variants, arbitrary system dispatch and recursive MissionAction calls.
- Initially execute one gameplay action per invocation. Preparation data stays in memory; pending evidence between transactions lives only in implementation-owned slots.
- Finalize only after successful gameplay. Failed postconditions revert gameplay, progress and same-transaction payments/allowances together.
- Prepare/finalize are not registered public gameplay systems. Library classes are privileged code in Dispatcher storage, not sandboxed plugins. Namespacing does not provide isolation from malicious code.
- Audit external callbacks and recursive execution. A wrapper guard alone does not block all ordinary Dispatcher reentry; postconditions and payout ordering still matter.
- MissionValidate checks existing state and trusted saved evidence. Supplied entity IDs locate candidates; they are not proof by themselves.

Ordinary unwrapped gameplay remains available. It may miss credit where evidence disappears, but cannot create false credit. A different caller may finalize an action while credit remains with the recorded initiating crew, subject to that crew’s continued validity and a secure run binding.

## 4. Payments and rewards

Use one MissionAction ABI under the two existing Dispatcher entrypoints. Do not introduce mission-specific payment entrypoints.

Two mechanisms must be verified separately:

1. **Payment Context:** Dispatcher restricts the payment-mediated caller and appends authenticated sender, destination and amount.
2. **SWAY confirmation receipts:** existing marketplace systems consume particular receipts through `confirm_receipt`. Context.payment_amount is not a substitute for those receipts.

The inspected SWAY code exposes receipts; this review has not established an end-to-end producer for the Dispatcher payment-callback route. The spike must verify the actual supported route and registry naming. Do not add unauthenticated forwarding as a workaround. If the callback route is unused/unavailable, preserve the existing interface and report which native payment flows are actually supported.

For every supported action adapter:

- Declare permitted payment modes and validate nonzero Context against the canonical action.
- Forward Context exactly once to one gameplay action; do not fan out or reuse one payment for multiple children.
- Preserve native sender/recipient/amount/memo/consumer and receipt-consumption checks.
- Reject unsupported modes before execution.
- Test rollback of transfers/receipt consumption inside the same transaction. A payment made in an earlier transaction cannot be undone by a later failure.
- Never treat incoming gameplay payment as mission escrow or reward funding.

Completion and payout are separate facts. Baseline: gameplay records entitlement and `ClaimMissionReward` verifies policy and pays. The client may batch completion and claim when desired. This avoids making each gameplay finish depend on an immediate reward transfer. Optional immediate settlement must use the same claim protection and revert on failed transfer; no silent “paid” marker.

Claim protection is set before external payment with success asserted. Reacceptance, version changes and subject transfers cannot reset it. Starter claims remain bound to the crew and pay its delegate (use the current delegate at settlement unless a different snapshot rule is explicitly selected). A completed entitlement survives later crew invalidation: check eligibility while earning completion, not again to erase an earned claim. Other templates may define their own beneficiary rules through the same interface.

## 5. Minimal storage and implementation-owned layouts

These are logical records, not a requirement for a distinct component/slot for every row. Physical packing follows measurement in the spike.

| Generic storage | Purpose/minimization |
| --- | --- |
| Definition/registry | Approved implementations and immutable terms, shared across participants. |
| Lifecycle state | Packed acceptance/completion/paid bits, plus version/definition references where not implicit in the key. Fixed campaigns can pack many assignments into word-sized pages; standalone missions can use a lifecycle word. |
| Opaque state slots | `State[scope, instance_ref, slot_index] -> felt252`. Scope separates assignment and campaign evidence. Implementations own layouts and typed accessors. |
| Starter eligibility exception | Permanent crew nullifier and participation information, reusing campaign progress where practical. Not a field imposed on all assignments. |

The framework owns lifecycle and claim accessors. Each implementation owns requirement bits, counters, IDs, quantities and all custom provenance encoding. Do not add dedicated Warehouse/Refinery/Colony components, a generic provenance struct, a mandatory objective record, or universal completion timestamps.

An implementation uses zero, one or several custom slots. Indexed slots avoid a stored dynamic-array length and whole-array updates for fixed layouts. Range-check every packed field; do not assume arbitrary 252-bit concatenations fit in a felt. Stable instance namespaces and pinned versions prevent accidental reinterpretation; explicit migration must preserve permanent claim identity.

Examples:

- Current-state predicate: lifecycle bit only once complete.
- Build-and-use: building ID until paired use is proven; read type/location/status from ordinary components.
- Sampling: bounded IDs or a safely deduplicated counter, not copies of sampling events.
- Production: minimal pending run binding, collapsed into completion bits when no longer needed.
- Colonization: original scanner beneficiary and compact building/use associations in custom campaign slots.
- Future delivery contract: delivery binding and remaining quantity only if the template permits partial fulfillment.

Campaign-owned evidence can be reused by later accepted missions without copying it. Keep only information required by the agreed predicates. Quantity credits must be consumed/accounted for where multiple uses would create false fulfillment. Rich history and player explanations stay in events/indexing.

Stop writes after requirements complete; saturate counters and combine updates to the same packed word. Do not assume clearing storage refunds prior fees. Measure slot writes and execution/class costs rather than promise a fixed slot count for every mission.

## 6. Starter contamination: the cross-cutting exception

The generic framework invokes eligibility policy. The starter implementation reads a permanent crew nullifier, independently of purchased StarterPack allowances. Non-pack crews use the same mission eligibility rules.

**Acceptance alone does not burn eligibility.** Two unused valid crews may exchange members without setting nullifiers. Record participation no later than the first credited qualifying action or pending evidence, before rewards are claimed. If acceptance itself validates historical work and credits it, participation begins then.

After participation, preserve roster continuity: membership exchange invalidates the participating crew. A member leaving an already invalid crew, or one invalidated by that same exchange, contaminates the destination. Completed campaigns remain participation-marked. Reordering and fresh Adalian recruitment remain allowed; adding an Arvadian follows the existing exclusion rule.

| Change | Result |
| --- | --- |
| Unused valid A moves member to unused valid B | Neither invalid solely because of the move |
| Participating A exports a member | A invalid; recipient contaminated |
| Invalid A exports a member | Recipient contaminated; A remains invalid |
| Participating B receives an exchanged member | B invalid under roster continuity; resolve reciprocal outgoing contamination too |
| Fresh recruitment/reordering | Preserve valid status; never clear invalid status |
| Empty/refill, NFT transfer, reacceptance | Never resets progress/nullifier/claims |

Compute from both old/new rosters and participation/nullifier states. Resolve propagation within a reciprocal exchange before writes so loop order cannot affect eligibility. A fresh member entering an invalid crew contaminates later recipients too: intentional conservative behavior.

Enforce this in ordinary ExchangeCrew and other membership-invalidating paths, not optional mission calls. Audit recruitment, initialization, offchain grants, NFT sales/transfers/recalls and bridges. Crew-only contamination is sufficient only while every previously participating member remains associated with its source crew until reassignment. Fix any path that loses that association before relying on the model.

Agreed starter admission boundary: crew ID must be strictly greater than configured cutoff X. Existing crews at or below X are excluded; they remain candidates for future colonization missions. Apply that exclusion as an effective invalid source in contamination checks, so moving a member from an excluded old crew into a new crew cannot bypass the cutoff. A destination ID above X is necessary but still subject to contamination. Freeze X for the campaign launch; its exact value is set during rollout. Scope this rule to starter eligibility, not unrelated campaigns. Audit pre-activation moves when selecting the cutoff and activation sequence; the ID rule alone does not reconstruct earlier member movements.

## 7. Starter implementation and deferred colonization example

Colonization requirements and implementation are deferred until starter missions are complete. The example below documents the generic interface fit only; do not finalize scan/ownership/reward rules or build colonization now.

| Policy | Starter campaign | Colonization campaign |
| --- | --- | --- |
| Subject | Accepted crew | Accepted asteroid |
| Contributors | Same crew for qualifying work | Any crew permitted by gameplay |
| Beneficiary | Claims bound to crew; pay delegate | Account attributed to first qualifying scan, still owning asteroid at claim |
| Eligibility | Nullifier and established new-crew rules | Qualifying first scan and ownership/provenance rules |
| Evidence | Packed construction/use/run evidence | Scanner beneficiary and compact construction/use evidence |
| Lifecycle/payment/storage API | Generic | Identical generic API |

No automatic asteroid subscription or campaign-specific core hook. Accept before the qualifying scan and capture its initiating account through the wrapper. Other contributors explicitly select that asteroid assignment. Permission to contribute is distinct from accepting on behalf of a subject, changing terms or claiming rewards.

Agreed starter sequence and thresholds (supersedes the earlier order and reward split):

| Mission | Requirement | SWAY | Cumulative |
| --- | --- | ---: | ---: |
| Make Landfall | Plan a Warehouse on a permitted lot. | 5,000 | 5,000 |
| Prospect the Surface | Complete 3 distinct core samples, each with initial yield ≥500,000 kg. | 20,000 | 25,000 |
| Begin Extraction | Complete an Extractor and finish one extraction of ≥100,000 kg of any raw resource from a sampled deposit. | 30,000 | 55,000 |
| Establish Storage | Complete the campaign Warehouse and receive/store ≥100,000 kg of goods in it. | 20,000 | 75,000 |
| Refine the Yield | Complete a Refinery and finish ≥1 full recipe-equivalent of an approved refinery process. | 50,000 | 125,000 |
| Cultivate Life | Complete a Bioreactor and finish ≥1 full batch of an approved biological process. | 35,000 | 160,000 |
| Manufacture Goods | Complete a Factory and finish ≥1 full recipe-equivalent of an approved manufacturing process. | 40,000 | 200,000 |
| Close the Production Loop | Complete an approved linked production route of ≥2 transformations and use or deliver the final product. | 25,000 | 225,000 |

Evidence and interpretation constraints:

- Preserve the Warehouse ID from Make Landfall in campaign state. Establish Storage refers to that building, not an arbitrary currently controlled Warehouse.
- Record distinct initial sampling actions by the crew. Each of the three counted samples must individually meet the ≥500,000 kg initial-yield threshold. The criterion refers to the initial sampling result, not remaining yield at claim or a later improvement. Samples below the threshold do not count toward the three qualifying samples. Repeated improvements do not count as distinct core samples. Preserve the qualifying result before mutable deposit state can obscure it.
- Attribute construction and production starts to the campaign crew, verify successful completion, and retain only the evidence required by subsequent checks. Current control alone does not prove construction.
- Extraction precedes the storage reward, but the Warehouse can be built/used earlier. If qualifying extraction output arrives in it, preserve that receipt in campaign evidence so Establish Storage can recognize it upon acceptance. Do not require a second shipment solely because the storage reward comes later.
- Purchased inputs remain allowed. The extraction rule does not currently specify that its deposit must be one of the three prospecting samples or that its destination must be the campaign Warehouse; do not silently introduce either restriction.
- Quantities in this table are kilograms, not raw inventory units. ProductType.mass and Inventory.mass are grams: 100,000 kg is 100,000,000 g. Calculate goods/extraction mass using canonical product units and verify deposit yield conversion against the resource configuration. Reserved inventory is not received/stored goods.
- A full biological batch must represent the required actual recipe quantity, not merely a fractional input run whose scheduling rounds up to one batch. Recipe-equivalent/batch checks use the process definitions and successful run data.
- Agreed storage interpretation: at least 100,000 kg actually present after a qualifying receipt, allowing mixed products and multiple receipts without a lifetime throughput counter. Do not accumulate repeated round trips of the same goods as new throughput. Mixed goods, purchased goods and extraction output count after actual receipt. Preserve crew-linked use and do not count reservations. The crew must control each building at its qualifying use; earlier buildings need not remain operational through later missions or the capstone.
- Same-crew, valid-at-completion, delegate payout and durable-earned-reward rules remain unchanged. Necessary evidence survives between accepted missions through campaign-owned slots.

Approved process policy: all processes supported by the relevant Refinery, Bioreactor or Factory qualify when they meet the full recipe/batch requirement and positive-duration validation. No curated allowlist for these individual milestones.

The capstone accepts any one of the five process pairs below. Verified against the installed SDK process definitions and Cairo process IDs (local configuration, not a live-chain config audit):

| Route | Stage 1 | Intermediate | Stage 2 | Building types |
| --- | --- | --- | --- | --- |
| 1 | Water Vacuum-evaporation Desalination (24) | Deionized Water (24) | Water Electrolysis (23) | Refinery → Refinery |
| 2 | Calcite Calcination (29) | Quicklime (32) | Salty Cement Mixing (38) | Refinery → Refinery |
| 3 | Bitumen Hydro-cracking (27) | Naphtha (27) | Naphtha Steam-cracking (40) | Refinery → Refinery |
| 4 | Silica Fusing (35) | Fused Quartz (41) | Quartz Filament Drawing and Wrapping (56) | Factory → Factory |
| 5 | Soybean Growing (89) | Soybeans (91) | Basic Food Cooking and Packaging (33) | Bioreactor → Factory |

All five intermediate products appear in stage 1 outputs and stage 2 inputs. Soybean Growing outputs 26,000 units of Soybeans per configured recipe/batch; the stage-2 food recipe consumes 160 units alongside other inputs. Silica Fusing is already a Factory process, so route 4 does not require a Refinery. Other inputs may be purchased. Require actual qualifying intermediate output, accounting for selected output/secondary-yield behavior, rather than merely matching a recipe name.

Agreed capstone completion rules:

- Complete any one of the five approved routes in order, using the same valid campaign crew.
- Each stage must complete at least one full recipe-equivalent, or at least one full biological batch where applicable.
- Both stages may use the same building when supported. Distinct buildings are not required; this supersedes earlier multi-building wording.
- After stage 2 completes, put its final product to economic use: consume it in a gameplay action or complete an outgoing delivery to a different entity. Holding inventory, listing goods, and sales through either order mechanism do not qualify.
- Purchased replacement inputs are permitted; no literal batch provenance is required. Validate compatible product identities, qualifying quantities, ordering, crew attribution and successful actions through campaign evidence.

The starter mission requirement decisions are complete. Crew cutoff X remains a launch-time configuration value; implementation must still validate mass conversions, positive-duration run identity and the supported economic-use action paths.

Confirm the run-identity positivity proof against the approved process domain before implementation. No literal batch tracing is required.

## 8. Integrity checks that remain open

### Asynchronous identity

The authorized spike is complete: see [spike findings](starter-mission-spike-findings.md). Ten focused tests passed. Ordinary positive extraction/processing replacements had later finish times; zero-yield extraction repeated the entire snapshot. Prefer evaluating a mission-owned finish-time/state binding before adding global counters, contingent on proving positive duration for every matching candidate once thresholds are set.

A player can finish through an ordinary system, restart the same processor and present stale mission evidence. Prove a reliable run identity before implementing production completion. Recipe/finish-time/snapshot hashes are not assumed unique merely because they are hashed.

If existing state is insufficient, evaluate a monotonic generation per processor/extractor slot advanced by every start, wrapped or ordinary. It stores no shared crew attribution, but adds persistent state/writes and one-time gameplay changes. Preserve generation across resets or recreation of the same identity. This is a measured contingency, not an already approved implementation or a guarantee of zero gameplay changes.

### Proposed capstone: compatible production stages, not batch provenance

Proposal for user review: the same valid crew completes an approved ordered sequence of compatible production stages. An upstream completed stage outputs product P; a later stage consumes P in its verified recipe inputs. Both meet their separately specified quantity thresholds, and the final output is used or delivered through an observed qualifying action. Purchased inputs and replacement units of P are allowed. The rule proves compatible processes executed in sequence, not that the identical produced units were consumed.

Optionally require the upstream destination and downstream origin to be the same registered inventory for a clearer gameplay connection. This is an inventory relationship check, not provenance. There is no reservation, inventory withdrawal tracking, atomic handoff or multi-action wrapper requirement. Ordinary one-action wrappers remain sufficient, subject to action-identity checks.

Campaign-owned packed evidence can retain the selected route/stage and necessary product/inventory IDs or qualifying quantities; fixed route definitions may make some values implicit. Counters/credits must not accidentally satisfy repeated obligations. Reuse earlier qualifying campaign evidence when its ordering and predicates meet the route. Do not claim merely owning all buildings satisfies this objective.

The five allowed routes and agreed per-stage quantities, same-building policy and terminal economic-use actions are specified in section 7. These are settled requirements; implementation evidence and tests are described in the implementation notes.

## 9. Future player-created missions: template instances only

Not implementation scope now. Players will configure a set of approved missions, for example:

```text
Template: DeliverGoods v1
Parameters: quantity X, product Y, source inventory A,
            destination inventory B, deadline D, escrowed reward R
```

The template validates parameter bounds, compatible product/inventories and issuer authority. Publication/acceptance pins terms and secures funding; the issuer cannot alter obligations or withdraw committed rewards afterward. Instances contain data, not user-supplied class hashes, callbacks or executable predicates.

A commercial delivery template must define source authorization, transport versus procurement, transferred ownership/rights, designated/open fulfiller, partial delivery rules, expiry/cancellation and settlement. Receiving goods for a tutorial is not automatically sufficient commercial fulfillment. Prevent duplicate use of exclusive delivery credit; intentional multiple sponsorship must be explicit.

Future work includes escrow, publishing, acceptance limits, expiry, refunds and fulfillment/claim UX. Build none of it now. Preserve definition/assignment/funding identities and the approved-template boundary so those features can reuse the framework later. If player-created campaigns are offered later, they compose approved templates through the same bounded prerequisite model.

## 10. Future implementation sequence and verification

1. Use the agreed cutoff-X admission, delegate payout and durable completed-entitlement rules. Use the selected mission thresholds; use all supported processes and the five selected capstone routes; apply the agreed capstone quantity/building/disposition rules; defer colonization until starter missions are complete. Starter implementation and tests are now authorized.
2. Run a registered-wrapper integration spike against existing gameplay, including both actual supported payment mechanisms. Prove caller/storage identity, canonical serialization, event/return-data compatibility, entropy behavior and rollback. Negative-test external self-calls and fabricated payment Context.
3. Prove contamination and asynchronous identity before building completion checks on them. Measure any required gameplay-state additions.
4. Implement abstract acceptance/lifecycle/registry/state access and the one-action wrapper. Test crew- and asteroid-bound implementations using identical interfaces without named campaign branches; this does not authorize production colonization implementation.
5. Build Warehouse and one processing mission end to end; starter allowances and manually acquired inputs must yield identical reward eligibility.
6. Complete remaining starter missions after evidence checks pass; enable capstone only after its separate integrity gate.
7. Use a shared SDK transaction builder to attach accepted assignments to relevant actions. UI chooses acceptance/assignment, not completion truth. Avoid separate custom routing in every action screen.
8. Activate only after mandatory crew/action invariants, launch eligibility and funding are ready. New configured definitions require no new Cairo; new template logic requires reviewed declarations.

Required tests when implementation is requested:

- Acceptance authority, prerequisites, immutable terms, repetition/reacceptance, concurrent assignments, cross-mission campaign evidence, pinned versions and claim replay across upgrades.
- Generic subject/contributor/beneficiary combinations, with no starter or colonization assumptions in core interfaces.
- Contamination through unused/participating/invalid/completed crews, reciprocal swaps, splits, new recipients, reorder, recruitment, initialization, empty/refill and NFT/bridge paths.
- Wrong assignment/crew/target, stale run evidence, unwrapped completion/restart, duplicate deposit/delivery counting and incorrect construction provenance.
- Arbitrary classes/selectors, malformed/trailing calldata, unsupported actions, recursion, callbacks and unauthorized registration.
- Context and receipt payments separately: wrong sender/recipient/amount/memo/consumer, reuse, unsupported modes, atomic rollback and reward-transfer failure.
- Packing bounds/round trips, distinct campaign/assignment namespaces, and measured first-write/update/no-op/completion/claim costs.

No fee savings or fixed storage footprint is asserted until compiled class sizes and representative transaction resources are measured.

## Spike findings

[Action identity and payment forwarding findings](starter-mission-spike-findings.md): 10 focused tests passed, including native marketplace receipt consumption through nested execution. At the spike stage only test code was added; production implementation followed after authorization and is described in the implementation notes. The paid Context boundary was tested with an authorized caller fixture; no end-to-end token callback producer was found in the local Sway implementation.

## Source basis

- `src/contracts/dispatcher.cairo`: existing entrypoints, authenticated Context, payment caller restriction and library execution.
- `src/systems.cairo`: registered class lookup in shared storage.
- `src/common/types/context.cairo`: caller/time/payment fields.
- `src/contracts/sway.cairo` and order fill systems: confirmation receipt creation/consumption.
- Crew exchange/recruitment/initialization, offchain grants and Crew/Crewmate NFT transfer implementations.
- Construction/deposit/delivery/production systems and components: persistent versus reset evidence.
- Library-call semantics: https://www.starknet.io/cairo-book/ch102-03-executing-code-from-another-class.html
