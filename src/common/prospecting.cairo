use array::{ArrayTrait, SpanTrait};
use cubit::f64::{Fixed, FixedTrait, Vec3Trait, ONE};
use starknet::{ContractAddress, SyscallResultTrait};
use influence::{components, config, contracts};
use influence::common::{
    abundance, crew::CrewDetailsTrait, extractor_slots, inventory, lot_access,
    math::RoundedDivTrait, position, starter_pack
};
use influence::components::{
    Building, BuildingTrait, Celestial, CelestialTrait, Claim, Control, ControlTrait, Crew,
    CrewTrait, Deposit, Inventory, Location, LocationTrait, ProspectingCampaign, ProspectingCore,
    ProspectingOrigin, Ship, ShipTrait, Unique
};
use influence::components::modifier_type::types as modifiers;
use influence::components::product_type::types as products;
use influence::components::prospecting_campaign::statuses;
use influence::config::{entities, errors, permissions};
use influence::types::{Context, Entity, EntityTrait, InventoryItemTrait};

const RULES: felt252 = 'fieldwork-r7-volume150-v1';
const FR: u256 = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
const REPLACEMENT_DELAY: u64 = 86400;
const MAX_SAMPLES: u64 = 10;
const META_ABUNDANCE_RADIX: u128 = 2305843009213693952;

#[starknet::interface]
trait IProspectingVerifier<T> {
    fn rules(self: @T) -> felt252;
    fn verify(self: @T, samples: u32, statement: Span<u256>, proof: Span<felt252>) -> bool;
}

fn campaign(id: u64) -> ProspectingCampaign {
    components::get::<ProspectingCampaign>(array![id.into()].span())
        .expect('unknown prospecting campaign')
}
fn sample_at(id: u64, index: u64) -> ProspectingCore {
    components::get::<ProspectingCore>(array![id.into(), index.into()].span())
        .expect('unknown prospecting sample')
}
fn active_id(origin: Entity) -> u64 {
    match components::get::<ProspectingOrigin>(origin.path()) {
        Option::Some(active) => active.campaign_id,
        Option::None(_) => 0
    }
}
fn save(id: u64, value: ProspectingCampaign) {
    components::set::<ProspectingCampaign>(array![id.into()].span(), value);
}
fn assert_enabled() {
    assert(influence::common::mining_rate::enabled(), 'prospecting not activated');
}
fn assert_active(id: u64, c: ProspectingCampaign) {
    assert(
        c.status == statuses::ACTIVE && active_id(c.origin) == id, 'inactive prospecting campaign'
    );
}
fn owned(id: u64, caller_crew: Entity, context: Context) -> ProspectingCampaign {
    let c = campaign(id);
    assert_active(id, c);
    assert(caller_crew == c.crew, 'wrong campaign crew');
    components::get::<Crew>(caller_crew.path())
        .expect(errors::CREW_NOT_FOUND)
        .assert_delegated_to(context.caller);
    c
}
fn assert_origin_access(crew: Entity, origin: Entity) {
    assert(lot_access::lot_access(crew, origin).allowed, 'origin permission required');
}
fn celestial(origin: Entity) -> (u64, u64, Celestial) {
    assert(origin.label == entities::LOT, 'origin must be a lot');
    let (asteroid, lot) = origin.to_position();
    position::assert_valid_lot(asteroid, lot);
    let celestial = components::get::<
        Celestial
    >(EntityTrait::new(entities::ASTEROID, asteroid).path())
        .expect(errors::CELESTIAL_NOT_FOUND);
    celestial.assert_resource_scanned();
    (asteroid, lot, celestial)
}
fn distance_dm(origin: u64, target: u64, radius: Fixed) -> u64 {
    if origin == target {
        return 0;
    }
    let distance = position::surface_distance(origin, target, radius)
        * FixedTrait::new_unscaled(10000, false);
    distance.ceil().try_into().unwrap()
}
fn metadata(origin: Entity, target: Entity, resource: u64) -> u128 {
    let (ast, from, celestial) = celestial(origin);
    assert(target.label == entities::LOT, 'target must be a lot');
    let (target_ast, to) = target.to_position();
    assert(ast == target_ast, errors::DIFFERENT_ASTEROIDS);
    position::assert_valid_lot(ast, to);
    assert(from < 2097152 && to < 2097152, 'lot index out of range');
    assert(abundance::global_ppm(celestial.abundances, resource) > 0, 'absent resource');
    assert(distance_dm(from, to, celestial.radius) <= 35000, 'outside origin reach');
    let area = position::surface_area(celestial.radius).floor();
    let n = position::surface_position_norm(from, area);
    let p = position::surface_position_norm(to, area);
    let axis = cubit::f64::Vec3Trait::new(
        FixedTrait::ZERO(), FixedTrait::ONE(), FixedTrait::ZERO()
    );
    let east = axis.cross(n);
    let length = east.norm();
    let east = if length.mag == 0 {
        cubit::f64::Vec3Trait::new(FixedTrait::ONE(), FixedTrait::ZERO(), FixedTrait::ZERO())
    } else {
        east.div(length)
    };
    let north = n.cross(east);
    let factor = FixedTrait::new_unscaled(100000, false);
    let offset = FixedTrait::new_unscaled(500000, false);
    let x: u128 = (p.dot(east) * celestial.radius * factor + offset).floor().try_into().unwrap();
    let z: u128 = (p.dot(north) * celestial.radius * factor + offset).floor().try_into().unwrap();
    let ppm: u128 = abundance::queried_ppm(ast, to, resource).into();
    assert(x < 1048576 && z < 1048576, 'metadata out of range');
    to.into() + x * 2097152 + z * 2199023255552 + ppm * META_ABUNDANCE_RADIX
}
fn cached_metadata(origin: Entity, target: Entity, resource: u64, celestial: Celestial) -> u128 {
    let path = array![
        'ProspectingMeta',
        origin.into(),
        target.into(),
        resource.into(),
        celestial.abundances,
        celestial.radius.mag.into()
    ]
        .span();
    if let Option::Some(cached) = components::get::<Unique>(path) {
        cached.unique.try_into().unwrap()
    } else {
        let meta = metadata(origin, target, resource);
        components::set::<Unique>(path, Unique { unique: meta.into() });
        meta
    }
}
fn approach_mask(id: u64, target: Entity, count: u64, radius: Fixed) -> u16 {
    let (_, to) = target.to_position();
    let mut mask: u16 = 0;
    let mut factor: u16 = 1;
    let mut index = 0;
    loop {
        if index == count {
            break;
        }
        let from: u64 = (sample_at(id, index).meta % 2097152).try_into().unwrap();
        if distance_dm(from, to, radius) > 15000 {
            mask += factor;
        }
        factor *= 2;
        index += 1;
    };
    mask
}
fn randomness_for_hash(id: u64, index: u64, block_hash: felt252) -> u64 {
    let info = starknet::get_tx_info().unbox();
    let hash: u256 = poseidon::poseidon_hash_span(
        array![
            7004,
            info.chain_id,
            starknet::get_contract_address().into(),
            id.into(),
            index.into(),
            block_hash
        ]
            .span()
    )
        .into();
    (hash.low % 18446744073709551616).try_into().unwrap()
}
fn randomness(id: u64, index: u64, now: u64) -> u64 {
    let sample = sample_at(id, index);
    assert(now >= sample.ready_at, 'sample not ready');
    assert(starknet::get_block_number() >= sample.target_block + 10, 'future hash not ready');
    let hash = starknet::syscalls::get_block_hash_syscall(sample.target_block).unwrap_syscall();
    assert(hash != 0, 'missing block hash');
    randomness_for_hash(id, index, hash)
}
fn resolve(id: u64, mut c: ProspectingCampaign, now: u64) -> ProspectingCampaign {
    if c.pending {
        let mut sample = sample_at(id, c.count);
        sample.randomness = randomness(id, c.count, now);
        components::set::<ProspectingCore>(array![id.into(), c.count.into()].span(), sample);
        c.pending = false;
        c.count += 1;
    }
    c
}
fn create(
    origin: Entity, resource: u64, caller_crew: Entity, context: Context
) -> (u64, ProspectingCampaign, u64) {
    assert_enabled();
    assert(caller_crew.label == entities::CREW, 'invalid campaign crew');
    let (asteroid, _lot, celestial) = celestial(origin);
    assert(abundance::global_ppm(celestial.abundances, resource) > 0, 'absent resource');
    assert_origin_access(caller_crew, origin);
    let mut details = CrewDetailsTrait::new(caller_crew);
    details.assert_all_ready_within(context.caller, context.now);
    assert(
        details.asteroid_id() == asteroid && details.lot_id() != 0, 'crew not on asteroid surface'
    );
    let verifier = contracts::get('ProspectingVerifier');
    assert(verifier.into() != 0, 'prospecting verifier missing');
    assert(
        IProspectingVerifierDispatcher { contract_address: verifier }.rules() == RULES,
        'wrong prospecting verifier'
    );
    let previous = active_id(origin);
    if previous != 0 {
        let mut old = campaign(previous);
        assert(
            old.status == statuses::ACTIVE || old.status == statuses::CANCELLED,
            'origin campaign is finalizing'
        );
        assert(context.now >= old.replaceable_at, 'origin campaign cooldown');
        old.status = statuses::REPLACED;
        save(previous, old);
    }
    let id = influence::entities::next_id('ProspectingCampaign');
    let quality_bps: u64 = 10000;
    let hash: u256 = poseidon::poseidon_hash_span(
        array![
            7000,
            starknet::get_tx_info().unbox().chain_id,
            starknet::get_contract_address().into(),
            id.into(),
            caller_crew.into(),
            context.caller.into(),
            origin.into(),
            resource.into(),
            7,
            quality_bps.into(),
            verifier.into()
        ]
            .span()
    )
        .into();
    let c = ProspectingCampaign {
        crew: caller_crew,
        creator: context.caller,
        origin,
        resource,
        context: hash,
        quality_bps,
        verifier,
        count: 0,
        pending: false,
        status: statuses::ACTIVE,
        replaceable_at: context.now + REPLACEMENT_DELAY,
        claim: EntityTrait::new(0, 0)
    };
    save(id, c);
    components::set::<ProspectingOrigin>(origin.path(), ProspectingOrigin { campaign_id: id });
    (id, c, previous)
}
fn consume_drill(origin: Entity, slot: u64, caller_crew: Entity, asteroid: u64) -> u64 {
    if origin.is_empty() {
        starter_pack::consume_core_sample_allowance(caller_crew);
        return 0;
    }
    if origin.label == entities::BUILDING {
        components::get::<Building>(origin.path())
            .expect(errors::BUILDING_NOT_FOUND)
            .assert_operational();
    } else {
        assert(origin.label == entities::SHIP, 'invalid drill inventory');
        components::get::<Ship>(origin.path()).expect(errors::SHIP_NOT_FOUND).assert_stationary();
        let location = components::get::<Location>(origin.path())
            .expect(errors::LOCATION_NOT_FOUND);
        if let Option::Some(building) = components::get::<Building>(location.location.path()) {
            building.assert_operational();
        }
    }
    caller_crew.assert_can(origin, permissions::REMOVE_PRODUCTS);
    let (origin_ast, origin_lot) = origin.to_position();
    assert(origin_ast == asteroid && origin_lot != 0, 'drill inventory off asteroid');
    let path = array![origin.into(), slot.into()].span();
    let mut data = components::get::<Inventory>(path).expect(errors::INVENTORY_NOT_FOUND);
    inventory::remove(ref data, array![InventoryItemTrait::new(products::CORE_DRILL, 1)].span());
    components::set::<Inventory>(path, data);
    origin_lot
}
fn commit(
    id: u64,
    target: Entity,
    expected_index: u64,
    commitment: u256,
    origin: Entity,
    origin_slot: u64,
    caller_crew: Entity,
    context: Context
) -> (ProspectingCampaign, ProspectingCore, u64) {
    assert_enabled();
    let current = owned(id, caller_crew, context);
    let accepted = current.count + if current.pending {
        1
    } else {
        0
    };
    assert(expected_index == accepted, 'sample index changed');
    assert_origin_access(caller_crew, current.origin);
    extractor_slots::assert_idle(target);
    let mut c = resolve(id, current, context.now);
    assert(c.count < MAX_SAMPLES && commitment < FR, 'invalid sample commitment');
    if c.count == 0 {
        assert(target == c.origin, 'first sample off origin');
    }
    let (asteroid, lot, celestial) = celestial(c.origin);
    let meta = cached_metadata(c.origin, target, c.resource, celestial);
    let blocked_approaches = approach_mask(id, target, c.count, celestial.radius);
    let mut details = CrewDetailsTrait::new(caller_crew);
    details.assert_all_ready_within(context.caller, context.now);
    assert(
        details.asteroid_id() == asteroid && details.lot_id() != 0, 'crew not on asteroid surface'
    );
    let hopper = details.bonus(modifiers::HOPPER_TRANSPORT_TIME, context.now);
    let distance = details.bonus(modifiers::FREE_TRANSPORT_DISTANCE, context.now);
    let crew_travel = position::hopper_travel_time(
        details.lot_id(), lot, celestial.radius, hopper, distance
    );
    let supplies_lot = consume_drill(origin, origin_slot, caller_crew, asteroid);
    let supply_travel = if origin.is_empty() {
        0
    } else {
        position::hopper_travel_time(supplies_lot, lot, celestial.radius, hopper, distance)
    };
    let bonus = details.bonus(modifiers::CORE_SAMPLE_TIME, context.now);
    let seconds: u128 = config::get('CORE_SAMPLING_TIME').try_into().unwrap();
    let accel: u128 = config::get('TIME_ACCELERATION').try_into().unwrap();
    assert(seconds > 0 && accel > 0 && !bonus.sign && bonus.mag > 0, 'invalid sampling timing');
    let duration: u64 = (seconds * ONE.into())
        .div_ceil(bonus.mag.into() * accel)
        .try_into()
        .unwrap();
    let mut crew = details.component;
    let ready_at = crew.busy_until(context.now) + cmp::max(crew_travel, supply_travel) + duration;
    crew.ready_at = ready_at + crew_travel;
    components::set::<Crew>(caller_crew.path(), crew);
    let (ship, mut data) = details.ship();
    if ship != caller_crew {
        data.extend_ready(crew.ready_at);
        components::set::<Ship>(ship.path(), data);
    }
    let sample = ProspectingCore {
        commitment,
        meta,
        blocked_approaches,
        randomness: 0,
        target_block: starknet::get_block_number() + 2,
        ready_at
    };
    components::set::<ProspectingCore>(array![id.into(), c.count.into()].span(), sample);
    c.pending = true;
    c.replaceable_at = ready_at + REPLACEMENT_DELAY;
    save(id, c);
    (c, sample, crew.ready_at)
}
fn statement(
    id: u64, c: ProspectingCampaign, lot: u64, quantity: u64, rate_bps: u64
) -> Span<u256> {
    let count: u256 = c.count.into();
    let (_, origin_lot) = c.origin.to_position();
    let origin: u256 = origin_lot.into();
    let quality: u256 = c.quality_bps.into();
    let lot: u256 = lot.into();
    let quantity: u256 = quantity.into();
    let rate: u256 = (rate_bps / 100).into();
    let header = 7003
        + count * 16384
        + quality * 262144
        + origin * 4294967296
        + lot * 9007199254740992
        + quantity * 18889465931478580854784
        + rate * 81129638414606681695789005144064;
    let mut values = array![c.context, header];
    let mut index = 0;
    loop {
        if index == c.count {
            break;
        }
        let sample = sample_at(id, index);
        let meta: u256 = sample.meta.into();
        let random: u256 = sample.randomness.into();
        let blocked: u256 = sample.blocked_approaches.into();
        values
            .append(
                meta
                    + random * 2417851639229258349412352
                    + blocked * 44601490397061246283071436545296723011960832
            );
        values.append(sample.commitment);
        index += 1;
    };
    values.span()
}
fn finalize(
    id: u64,
    lot: Entity,
    quantity: u64,
    rate_bps: u64,
    proof: Span<felt252>,
    caller_crew: Entity,
    context: Context
) -> Entity {
    assert_enabled();
    let current = owned(id, caller_crew, context);
    let mut c = resolve(id, current, context.now);
    assert(c.count > 0 && c.count <= MAX_SAMPLES, 'no resolved campaign samples');
    assert(quantity > 0 && quantity < 4294967296, 'invalid claim quantity');
    assert(rate_bps >= 9000 && rate_bps <= 20000 && rate_bps % 100 == 0, 'invalid claim rate');
    assert(lot.label == entities::LOT, 'claim must be on lot');
    let (asteroid, index) = lot.to_position();
    let (origin_asteroid, _) = c.origin.to_position();
    assert(asteroid == origin_asteroid && index > 0 && index < 2097152, 'invalid claim lot');
    let mut found = false;
    let mut reference_abundance_ppm = 0;
    let mut i = 0;
    loop {
        if i == c.count {
            break;
        }
        let sample = sample_at(id, i);
        if sample.meta % 2097152 == index.into() {
            found = true;
            reference_abundance_ppm = (sample.meta / META_ABUNDANCE_RADIX).try_into().unwrap();
        }
        i += 1;
    };
    assert(found && reference_abundance_ppm > 0, 'claim lot was not sampled');
    let values = statement(id, c, index, quantity, rate_bps);
    // Close before the external verifier call; a revert restores all state.
    c.status = statuses::FINALIZED;
    save(id, c);
    assert(
        IProspectingVerifierDispatcher { contract_address: c.verifier }
            .verify(c.count.try_into().unwrap(), values, proof),
        'invalid prospecting proof'
    );
    let claim = EntityTrait::new(
        entities::DEPOSIT, influence::entities::next_id(entities::DEPOSIT.into())
    );
    components::set::<
        Deposit
    >(
        claim.path(),
        Deposit {
            status: 2,
            resource: c.resource,
            initial_yield: quantity,
            remaining_yield: quantity,
            finish_time: 0,
            yield_eff: FixedTrait::ONE()
        }
    );
    components::set::<
        Claim
    >(claim.path(), Claim { rules_version: 1, rate_bps, reference_abundance_ppm, campaign_id: id });
    components::set::<Control>(claim.path(), ControlTrait::new(c.crew));
    components::set::<Location>(claim.path(), LocationTrait::new(lot));
    c.claim = claim;
    save(id, c);
    components::set::<ProspectingOrigin>(c.origin.path(), ProspectingOrigin { campaign_id: 0 });
    claim
}
fn abandon(id: u64, caller_crew: Entity, context: Context) -> ProspectingCampaign {
    let mut c = owned(id, caller_crew, context);
    c.status = statuses::CANCELLED;
    save(id, c);
    c
}
