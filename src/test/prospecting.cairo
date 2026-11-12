use array::{ArrayTrait, SpanTrait};
use cubit::{f64::{FixedTrait, ONE}, f128};
use influence::{components, config, contracts};
use influence::common::{
    abundance, extraction, extractor_slots, inventory, mining_rate, prospecting, random
};
use influence::components::{
    Celestial, CelestialTrait, Claim, Control, ControlTrait, Crew, Deposit, Extractor,
    ExtractorSlots, Inventory, InventoryTrait, Location, LocationTrait, ProspectingCampaign,
    ProspectingCore, ProspectingOrigin, PublicPolicy, Unique
};
use influence::components::modifier_type::types as modifiers;
use influence::components::product_type::types as products;
use influence::components::prospecting_campaign::statuses;
use influence::config::{entities, permissions};
use influence::systems::policies::helpers::policy_path;
use influence::test::{helpers, mocks};
use influence::types::{Entity, EntityTrait, InventoryContentsTrait, InventoryItemTrait};
use starknet::{SyscallResultTrait, storage_access::Store};

// This test double binds every supplied transcript word. Real Groth16 verification
// is exercised by the devnet integration suite, with the separate Garaga package.
#[starknet::contract]
mod TranscriptTestVerifier {
    use array::{ArrayTrait, SpanTrait};
    use serde::Serde;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn rules(self: @ContractState) -> felt252 {
        'fieldwork-r7-volume150-v1'
    }
    #[external(v0)]
    fn verify(
        self: @ContractState, samples: u32, statement: Span<u256>, proof: Span<felt252>
    ) -> bool {
        let mut words = array![];
        Serde::<Span<u256>>::serialize(@statement, ref words);
        assert(statement.len() == 2 + samples * 2, 'test statement length');
        proof.len() == 1 && *proof.at(0) == poseidon::poseidon_hash_span(words.span())
    }
}

#[derive(Copy, Drop)]
struct Fixture {
    asteroid: Entity,
    crew: Entity,
    origin: Entity,
    warehouse: Entity,
    extractor: Entity
}

fn setup() -> Fixture {
    starknet::testing::set_contract_address(starknet::contract_address_const::<'DISPATCHER'>());
    starknet::testing::set_block_timestamp(100);
    starknet::testing::set_block_number(100);
    helpers::init();
    mocks::constants();
    helpers::deploy_system(
        'Abundance', influence::systems::deposits::abundance::Abundance::TEST_CLASS_HASH
    );
    config::set('PROSPECTING_ENABLED', 1);
    for modifier in array![
        modifiers::CORE_SAMPLE_TIME,
        modifiers::CORE_SAMPLE_QUALITY,
        modifiers::EXTRACTION_TIME,
        modifiers::HOPPER_TRANSPORT_TIME,
        modifiers::FREE_TRANSPORT_DISTANCE,
        modifiers::INVENTORY_MASS_CAPACITY,
        modifiers::INVENTORY_VOLUME_CAPACITY
    ] {
        mocks::modifier_type(modifier);
    };
    for product in array![
        products::CORE_DRILL, products::WATER, products::HYDROGEN
    ] {
        mocks::product_type(product);
    };
    let asteroid = EntityTrait::new(entities::ASTEROID, 250000);
    let mut celestial = CelestialTrait::new(
        1, f128::FixedTrait::new_unscaled(1000000, false), FixedTrait::new(4396773074, false)
    );
    celestial.scan_status = 4;
    celestial.abundances = 500 + 49 * 1024;
    components::set::<Celestial>(asteroid.path(), celestial);
    let crew = mocks::delegated_crew(1, 'PLAYER');
    mocks::delegated_crew(2, 'OTHER');
    let origin = EntityTrait::from_position(asteroid.id, 1);
    let station = mocks::public_habitat(crew, 1);
    let warehouse = mocks::public_warehouse(crew, 3);
    let extractor = mocks::public_extractor(crew, 4);
    for building in array![
        station, warehouse, extractor
    ] {
        components::set::<Location>(building.path(), LocationTrait::new(origin));
    };
    components::set::<Location>(crew.path(), LocationTrait::new(station));
    components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
    components::set::<
        Unique
    >(array!['LotUse', origin.into()].span(), Unique { unique: extractor.into() });
    let path = array![warehouse.into(), 2].span();
    let mut stock = components::get::<Inventory>(path).unwrap();
    inventory::add_unchecked(
        ref stock, array![InventoryItemTrait::new(products::CORE_DRILL, 20)].span()
    );
    components::set::<Inventory>(path, stock);
    let (verifier, _) = starknet::syscalls::deploy_syscall(
        TranscriptTestVerifier::TEST_CLASS_HASH.try_into().unwrap(), 0, array![].span(), false
    )
        .unwrap_syscall();
    contracts::set('ProspectingVerifier', verifier);
    Fixture { asteroid, crew, origin, warehouse, extractor }
}
fn create(f: Fixture) -> u64 {
    let (id, _, _) = prospecting::create(
        f.origin, products::WATER, f.crew, mocks::context('PLAYER')
    );
    id
}
fn sample(f: Fixture, id: u64, target: Entity, index: u64) -> ProspectingCore {
    let (_, sample, _) = prospecting::commit(
        id, target, index, 123 + index.into(), f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
    sample
}
fn mature(f: Fixture, id: u64) {
    let c = prospecting::campaign(id);
    let pending = prospecting::sample_at(id, c.count);
    let crew = components::get::<Crew>(f.crew.path()).unwrap();
    starknet::testing::set_block_timestamp(cmp::max(pending.ready_at, crew.ready_at));
    starknet::testing::set_block_number(pending.target_block + 10);
    starknet::testing::set_block_hash(pending.target_block, 987654321);
}
fn proof(id: u64, lot: Entity, quantity: u64, rate: u64) -> Span<felt252> {
    let c = prospecting::resolve(id, prospecting::campaign(id), starknet::get_block_timestamp());
    prospecting::save(id, c);
    let (_, lot) = lot.to_position();
    let values = prospecting::statement(id, c, lot, quantity, rate);
    let mut words = array![];
    serde::Serde::<Span<u256>>::serialize(@values, ref words);
    array![poseidon::poseidon_hash_span(words.span())].span()
}
fn balance(f: Fixture) -> u64 {
    components::get::<Inventory>(array![f.warehouse.into(), 2].span())
        .unwrap()
        .amount_of(products::CORE_DRILL)
}
fn legacy_claim(f: Fixture, resource: u64) -> Entity {
    let deposit = mocks::controlled_deposit(f.crew, 99, resource);
    components::set::<Location>(deposit.path(), LocationTrait::new(f.origin));
    components::set::<
        Deposit
    >(
        deposit.path(),
        Deposit {
            status: 2,
            resource,
            initial_yield: 2000000,
            remaining_yield: 2000000,
            finish_time: 0,
            yield_eff: FixedTrait::ONE()
        }
    );
    deposit
}
fn revoke_origin(f: Fixture) {
    components::set::<
        Control
    >(f.asteroid.path(), ControlTrait::new(EntityTrait::new(entities::CREW, 2)));
}

#[test]
#[available_gas(60000000)]
fn prospecting_commit_consumes_one_drill_and_binds_timing_and_index() {
    let f = setup();
    let id = create(f);
    let s = sample(f, id, f.origin, 0);
    let c = prospecting::campaign(id);
    assert(c.pending && c.count == 0, 'sample not pending');
    assert(s.ready_at > 100 && s.target_block == 102, 'incorrect schedule');
    assert(c.replaceable_at == s.ready_at + 86400, 'incorrect restart deadline');
    assert(balance(f) == 19, 'drill not consumed once');
    mature(f, id);
    let first = prospecting::randomness(id, 0, starknet::get_block_timestamp());
    starknet::testing::set_block_number(1000);
    starknet::testing::set_block_timestamp(10000);
    assert(first == prospecting::randomness(id, 0, 10000), 'randomness changed by waiting');
    sample(f, id, EntityTrait::from_position(f.asteroid.id, 2), 1);
    assert(
        prospecting::campaign(id).count == 1 && balance(f) == 18, 'previous sample not resolved'
    );
}

#[test]
#[available_gas(60000000)]
fn prospecting_finalization_after_revocation_uses_one_balance_and_releases_origin() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    mature(f, id);
    let proof = proof(id, f.origin, 1500000, 12000);
    revoke_origin(f);
    let claim = prospecting::finalize(
        id, f.origin, 1500000, 12000, proof, f.crew, mocks::context('PLAYER')
    );
    let data = components::get::<Deposit>(claim.path()).unwrap();
    let metadata = components::get::<Claim>(claim.path()).unwrap();
    assert(
        data.initial_yield == 1500000 && data.remaining_yield == 1500000, 'claim balance changed'
    );
    assert(metadata.campaign_id == id && metadata.rate_bps == 12000, 'wrong claim metadata');
    assert(
        components::get::<Control>(claim.path()).unwrap().controller == f.crew, 'wrong claim owner'
    );
    assert(
        prospecting::active_id(f.origin) == 0
            && prospecting::campaign(id).status == statuses::FINALIZED,
        'origin still locked'
    );
}

#[test]
#[available_gas(60000000)]
fn prospecting_timeout_is_replaceability_not_expiration() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    mature(f, id);
    let proof = proof(id, f.origin, 1000000, 9000);
    starknet::testing::set_block_timestamp(prospecting::campaign(id).replaceable_at + 100);
    prospecting::finalize(id, f.origin, 1000000, 9000, proof, f.crew, mocks::context('PLAYER'));
}

#[test]
#[available_gas(40000000)]
fn prospecting_replacement_closes_old_campaign_across_resources() {
    let f = setup();
    let old = create(f);
    starknet::testing::set_block_timestamp(prospecting::campaign(old).replaceable_at);
    let (new_id, _, replaced) = prospecting::create(
        f.origin, products::HYDROGEN, f.crew, mocks::context('PLAYER')
    );
    assert(replaced == old && old != new_id, 'old campaign not replaced');
    assert(prospecting::campaign(old).status == statuses::REPLACED, 'old proof still active');
    assert(prospecting::active_id(f.origin) == new_id, 'wrong active origin');
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('origin campaign cooldown',))]
fn prospecting_resource_change_cannot_bypass_origin_lock() {
    let f = setup();
    create(f);
    prospecting::create(f.origin, products::HYDROGEN, f.crew, mocks::context('PLAYER'));
}

#[test]
#[available_gas(45000000)]
#[should_panic(expected: ('sample index changed',))]
fn prospecting_stale_tab_cannot_append_another_sample() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    sample(f, id, f.origin, 0);
}

#[test]
#[available_gas(45000000)]
#[should_panic(expected: ('sample not ready',))]
fn prospecting_cannot_resolve_before_drilling_finishes() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    prospecting::randomness(id, 0, starknet::get_block_timestamp());
}

#[test]
#[available_gas(45000000)]
#[should_panic(expected: ('future hash not ready',))]
fn prospecting_cannot_resolve_before_hash_availability() {
    let f = setup();
    let id = create(f);
    let s = sample(f, id, f.origin, 0);
    starknet::testing::set_block_timestamp(s.ready_at);
    prospecting::randomness(id, 0, s.ready_at);
}

#[test]
#[available_gas(45000000)]
#[should_panic(expected: ('origin permission required',))]
fn prospecting_revocation_blocks_paid_continuation() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    mature(f, id);
    revoke_origin(f);
    sample(f, id, f.origin, 1);
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('target lot extracting',))]
fn prospecting_any_running_slot_blocks_even_finished_jobs() {
    let f = setup();
    let id = create(f);
    components::set::<ExtractorSlots>(f.extractor.path(), ExtractorSlots { count: 2 });
    let mut slot = components::get::<Extractor>(array![f.extractor.into(), 1].span()).unwrap();
    slot.status = 1;
    slot.finish_time = 1;
    components::set::<Extractor>(array![f.extractor.into(), 2].span(), slot);
    sample(f, id, f.origin, 0);
}

#[test]
#[available_gas(50000000)]
fn prospecting_cancellation_preserves_spending_and_restart_deadline() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    let before = prospecting::campaign(id);
    let after = prospecting::abandon(id, f.crew, mocks::context('PLAYER'));
    assert(
        after.status == statuses::CANCELLED && after.replaceable_at == before.replaceable_at,
        'cancellation changed cooldown'
    );
    assert(
        prospecting::active_id(f.origin) == id && balance(f) == 19, 'cancellation changed spending'
    );
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('invalid prospecting proof',))]
fn prospecting_rejects_changed_quantity_after_proof_generation() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    mature(f, id);
    let proof = proof(id, f.origin, 1000000, 9000);
    prospecting::finalize(id, f.origin, 1000001, 9000, proof, f.crew, mocks::context('PLAYER'));
}

#[test]
#[available_gas(70000000)]
fn prospecting_baseline_uses_no_deposit_and_collection_releases_exact_reservation() {
    let f = setup();
    let before = influence::entities::current_id(entities::DEPOSIT.into());
    let result = extraction::start(
        EntityTrait::new(0, 0),
        products::WATER,
        true,
        100000,
        f.extractor,
        1,
        f.warehouse,
        2,
        f.crew,
        mocks::context('PLAYER')
    );
    assert(result.rate_bps == 2500, 'wrong baseline rate');
    assert(
        influence::entities::current_id(entities::DEPOSIT.into()) == before,
        'baseline created deposit'
    );
    let stock = components::get::<Inventory>(array![f.warehouse.into(), 2].span()).unwrap();
    let reserved = stock.reserved_mass;
    assert(reserved > 0, 'output not reserved');
    starknet::testing::set_block_timestamp(result.finish_time);
    let mut finish =
        influence::systems::production::extract_resource_finish::ExtractResourceFinish::contract_state_for_testing();
    influence::systems::production::extract_resource_finish::ExtractResourceFinish::run(
        ref finish, f.extractor, 1, f.crew, mocks::context('PLAYER')
    );
    let stock = components::get::<Inventory>(array![f.warehouse.into(), 2].span()).unwrap();
    assert(
        stock.reserved_mass == 0 && stock.contents.amount_of(products::WATER) == 100000,
        'wrong output or reservation'
    );
    extractor_slots::assert_idle(f.origin);
}

#[test]
#[available_gas(50000000)]
#[should_panic(expected: ('resource requires claim',))]
fn prospecting_baseline_blocks_trace_materials() {
    let f = setup();
    extraction::start(
        EntityTrait::new(0, 0),
        products::HYDROGEN,
        true,
        1000,
        f.extractor,
        1,
        f.warehouse,
        2,
        f.crew,
        mocks::context('PLAYER')
    );
}

#[test]
#[available_gas(95000000)]
fn prospecting_legacy_trace_claim_keeps_id_balance_and_constant_rate() {
    let f = setup();
    let deposit = legacy_claim(f, products::HYDROGEN);
    let first = extraction::start(
        deposit, 0, false, 100000, f.extractor, 1, f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
    let data = components::get::<Deposit>(deposit.path()).unwrap();
    assert(
        first.rate_bps == 12000 && data.remaining_yield == 1900000 && data.initial_yield == 2000000,
        'legacy claim changed'
    );
    assert(components::get::<Claim>(deposit.path()).is_none(), 'legacy metadata invented');
    assert(
        components::get::<Control>(deposit.path()).unwrap().controller == f.crew,
        'legacy owner changed'
    );
    starknet::testing::set_block_timestamp(first.finish_time);
    let mut finish =
        influence::systems::production::extract_resource_finish::ExtractResourceFinish::contract_state_for_testing();
    influence::systems::production::extract_resource_finish::ExtractResourceFinish::run(
        ref finish, f.extractor, 1, f.crew, mocks::context('PLAYER')
    );
    let second = extraction::start(
        deposit, 0, false, 100000, f.extractor, 1, f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
    assert(
        first.rate_bps == second.rate_bps
            && first.reference_abundance_ppm == second.reference_abundance_ppm,
        'depletion affected rate'
    );
    assert(
        components::get::<Deposit>(deposit.path()).unwrap().remaining_yield == 1800000,
        'second debit incorrect'
    );
}

#[test]
#[available_gas(65000000)]
fn prospecting_extraction_started_before_activation_finishes_unchanged() {
    let f = setup();
    let deposit = legacy_claim(f, products::WATER);
    config::set('PROSPECTING_ENABLED', 0);
    let result = extraction::start(
        deposit, 0, false, 100000, f.extractor, 1, f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
    let before = components::get::<Extractor>(array![f.extractor.into(), 1].span()).unwrap();
    config::set('PROSPECTING_ENABLED', 1);
    assert(before.finish_time == result.finish_time && before.yield == 100000, 'old job changed');
    starknet::testing::set_block_timestamp(before.finish_time);
    let mut finish =
        influence::systems::production::extract_resource_finish::ExtractResourceFinish::contract_state_for_testing();
    influence::systems::production::extract_resource_finish::ExtractResourceFinish::run(
        ref finish, f.extractor, 1, f.crew, mocks::context('PLAYER')
    );
    assert(
        components::get::<Deposit>(deposit.path()).unwrap().remaining_yield == 1900000,
        'collection debited again'
    );
}

#[test]
#[available_gas(85000000)]
fn prospecting_legacy_pending_sample_finishes_with_identical_randomness_and_quantity() {
    let f = setup();
    config::set('PROSPECTING_ENABLED', 0);
    let mut start =
        influence::systems::deposits::sample_start::SampleDepositStart::contract_state_for_testing();
    influence::systems::deposits::sample_start::SampleDepositStart::run(
        ref start, f.origin, products::WATER, f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
    let deposit = EntityTrait::new(
        entities::DEPOSIT, influence::entities::current_id(entities::DEPOSIT.into())
    );
    let pending = components::get::<Deposit>(deposit.path()).unwrap();
    starknet::testing::set_block_timestamp(pending.finish_time + 10000);
    random::entropy::generate();
    let mut finish =
        influence::systems::deposits::sample_finish::SampleDepositFinish::contract_state_for_testing();
    influence::systems::deposits::sample_finish::SampleDepositFinish::run(
        ref finish, deposit, f.crew, mocks::context('PLAYER')
    );
    let control = components::get::<Deposit>(deposit.path()).unwrap();
    components::set::<Deposit>(deposit.path(), pending);
    config::set('PROSPECTING_ENABLED', 1);
    influence::systems::deposits::sample_finish::SampleDepositFinish::run(
        ref finish, deposit, f.crew, mocks::context('PLAYER')
    );
    let migrated = components::get::<Deposit>(deposit.path()).unwrap();
    assert(
        migrated.initial_yield == control.initial_yield
            && migrated.remaining_yield == control.remaining_yield,
        'pending yield changed'
    );
    assert(
        migrated.status == 2 && components::get::<Claim>(deposit.path()).is_none(),
        'legacy finish not default claim'
    );
}

#[test]
#[available_gas(2000000)]
fn prospecting_global_threshold_is_exact_and_claim_rate_matches_sdk() {
    assert(
        abundance::global_ppm(50, 1) == 50000 && abundance::global_ppm(49, 1) == 49000,
        'global threshold rounded'
    );
    assert(mining_rate::intrinsic_rate_nano(500000, 12000) == 251688670, 'SDK rate parity changed');
}

#[test]
#[available_gas(3000000)]
fn prospecting_packed_core_roundtrips_maximum_fields() {
    let base = starknet::storage_base_address_from_felt252(91);
    let value = ProspectingCore {
        commitment: prospecting::FR - 1,
        meta: 2417851639229258349412351,
        blocked_approaches: 1023,
        randomness: 18446744073709551615,
        target_block: 18446744073709551615,
        ready_at: 18446744073709551615
    };
    Store::<ProspectingCore>::write(0, base, value).unwrap_syscall();
    let saved = Store::<ProspectingCore>::read(0, base).unwrap_syscall();
    assert(saved.commitment == value.commitment && saved.meta == value.meta, 'core data changed');
    assert(
        saved.randomness == value.randomness
            && saved.blocked_approaches == value.blocked_approaches,
        'core entropy changed'
    );
    assert(
        saved.ready_at == value.ready_at && saved.target_block == value.target_block,
        'core schedule changed'
    );
}

#[test]
#[available_gas(85000000)]
fn prospecting_lateral_sampling_requires_only_origin_permission() {
    let f = setup();
    revoke_origin(f);
    components::set::<
        PublicPolicy
    >(policy_path(f.origin, permissions::USE_LOT), PublicPolicy { public: true });
    let target = EntityTrait::from_position(f.asteroid.id, 2);
    assert(
        !influence::common::lot_access::lot_access(f.crew, target).allowed,
        'fixture target is permissioned'
    );
    let id = create(f);
    sample(f, id, f.origin, 0);
    mature(f, id);
    let result = sample(f, id, target, 1);
    assert(result.meta % 2097152 == 2 && balance(f) == 18, 'lateral sample failed');
}

#[test]
#[available_gas(65000000)]
#[should_panic(expected: ('inactive prospecting campaign',))]
fn prospecting_replacement_invalidates_an_already_generated_proof() {
    let f = setup();
    let id = create(f);
    sample(f, id, f.origin, 0);
    mature(f, id);
    let proof = proof(id, f.origin, 1000000, 9000);
    starknet::testing::set_block_timestamp(prospecting::campaign(id).replaceable_at);
    create(f);
    prospecting::finalize(id, f.origin, 1000000, 9000, proof, f.crew, mocks::context('PLAYER'));
}

#[test]
#[available_gas(40000000)]
fn prospecting_starter_allowance_replaces_one_drill_without_double_charging() {
    let f = setup();
    let id = create(f);
    components::set::<
        components::StarterPack
    >(
        f.crew.path(),
        components::StarterPack {
            product_id: 1,
            restricted_until: 10000,
            valid: true,
            invalidated_at: 0,
            building_allowances: array![].span(),
            lot_allowance: 0,
            food_reload_allowance: 0,
            core_sample_allowance: 2
        }
    );
    prospecting::commit(
        id, f.origin, 0, 123, EntityTrait::new(0, 0), 0, f.crew, mocks::context('PLAYER')
    );
    assert(balance(f) == 20, 'starter sample also took drill');
    assert(
        components::get::<components::StarterPack>(f.crew.path())
            .unwrap()
            .core_sample_allowance == 1,
        'allowance not charged once'
    );
}

#[test]
#[available_gas(300000000)]
#[should_panic(expected: ('invalid sample commitment',))]
fn prospecting_rejects_an_eleventh_accepted_sample() {
    let f = setup();
    let id = create(f);
    let mut i = 0;
    loop {
        if i == 10 {
            break;
        }
        sample(f, id, f.origin, i);
        mature(f, id);
        i += 1;
    };
    sample(f, id, f.origin, 10);
}

#[test]
#[available_gas(30000000)]
#[should_panic(expected: ('legacy sampling disabled',))]
fn prospecting_activation_disables_old_improvement_start() {
    let f = setup();
    let deposit = legacy_claim(f, products::WATER);
    let mut state =
        influence::systems::deposits::sample_improve::SampleDepositImprove::contract_state_for_testing();
    influence::systems::deposits::sample_improve::SampleDepositImprove::run(
        ref state, deposit, f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
}

#[test]
#[available_gas(85000000)]
fn prospecting_pending_legacy_improvement_preserves_its_exact_result() {
    let f = setup();
    let deposit = legacy_claim(f, products::WATER);
    config::set('PROSPECTING_ENABLED', 0);
    let mut improve =
        influence::systems::deposits::sample_improve::SampleDepositImprove::contract_state_for_testing();
    influence::systems::deposits::sample_improve::SampleDepositImprove::run(
        ref improve, deposit, f.warehouse, 2, f.crew, mocks::context('PLAYER')
    );
    let pending = components::get::<Deposit>(deposit.path()).unwrap();
    starknet::testing::set_block_timestamp(pending.finish_time + 10000);
    random::entropy::generate();
    let mut finish =
        influence::systems::deposits::sample_finish::SampleDepositFinish::contract_state_for_testing();
    influence::systems::deposits::sample_finish::SampleDepositFinish::run(
        ref finish, deposit, f.crew, mocks::context('PLAYER')
    );
    let control = components::get::<Deposit>(deposit.path()).unwrap();
    components::set::<Deposit>(deposit.path(), pending);
    config::set('PROSPECTING_ENABLED', 1);
    influence::systems::deposits::sample_finish::SampleDepositFinish::run(
        ref finish, deposit, f.crew, mocks::context('PLAYER')
    );
    let migrated = components::get::<Deposit>(deposit.path()).unwrap();
    assert(
        migrated.initial_yield == control.initial_yield
            && migrated.remaining_yield == control.remaining_yield,
        'legacy improvement changed'
    );
    assert(components::get::<Claim>(deposit.path()).is_none(), 'legacy reward was upgraded');
}

#[test]
#[available_gas(35000000)]
#[should_panic(expected: ('processor not ready',))]
fn prospecting_cannot_clear_running_second_slot_by_tearing_down_extractor() {
    let f = setup();
    components::set::<ExtractorSlots>(f.extractor.path(), ExtractorSlots { count: 2 });
    let mut slot = components::get::<Extractor>(array![f.extractor.into(), 1].span()).unwrap();
    slot.status = 1;
    components::set::<Extractor>(array![f.extractor.into(), 2].span(), slot);
    let mut deconstruct =
        influence::systems::construction::construction_deconstruct::ConstructionDeconstruct::contract_state_for_testing();
    influence::systems::construction::construction_deconstruct::ConstructionDeconstruct::run(
        ref deconstruct, f.extractor, f.crew, mocks::context('PLAYER')
    );
}
