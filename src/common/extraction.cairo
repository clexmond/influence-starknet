use array::{Array, ArrayTrait};
use option::OptionTrait;
use starknet::ContractAddress;
use traits::{Into, TryInto};

use cubit::f64::{FixedTrait, ONE};

use influence::{components, config};
use influence::common::{
    mining_rate, extractor_slots, crew::CrewDetailsTrait, inventory, math::RoundedDivTrait, position
};
use influence::components::{
    Celestial, CelestialTrait, Claim, Crew, CrewTrait, Building, BuildingTrait, Inventory,
    InventoryTrait, Location, Ship, ShipTrait, modifier_type::types as modifier_types,
    deposit::{statuses as deposit_statuses, Deposit, DepositTrait}, extractor,
    extractor::{statuses as extractor_statuses, Extractor, ExtractorTrait}
};
use influence::config::{actions, entities, errors, permissions};
use influence::types::{Context, Entity, EntityTrait, InventoryItem, InventoryItemTrait};

#[derive(Copy, Drop)]
struct ExtractionResult {
    resource: u64,
    finish_time: u64,
    rate_bps: u64,
    reference_abundance_ppm: u64
}

#[derive(Copy, Drop, starknet::Event)]
struct ResourceExtractionStartedV1 {
    mode: u64,
    deposit: Entity,
    resource: u64,
    yield: u64,
    extractor: Entity,
    extractor_slot: u64,
    destination: Entity,
    destination_slot: u64,
    finish_time: u64,
    rate_bps: u64,
    reference_abundance_ppm: u64,
    caller_crew: Entity,
    caller: ContractAddress
}

fn start(
    deposit: Entity,
    resource: u64,
    baseline: bool,
    yield: u64,
    extractor: Entity,
    extractor_slot: u64,
    destination: Entity,
    destination_slot: u64,
    caller_crew: Entity,
    context: Context
) -> ExtractionResult {
    // Check that crew is delegated, and ready
    let mut crew_details = CrewDetailsTrait::new(caller_crew);
    crew_details.assert_all_ready_within(context.caller, context.now);
    let mut crew_data = crew_details.component;

    // Permissions checks
    if !baseline {
        caller_crew.assert_can(deposit, permissions::USE_DEPOSIT);
    }

    // Check that the extraction slot is ready
    components::get::<Building>(extractor.path())
        .expect(errors::BUILDING_NOT_FOUND)
        .assert_operational();
    let mut extractor_path: Array<felt252> = Default::default();
    extractor_path.append(extractor.into());
    extractor_path.append(extractor_slot.into());
    let mut extractor_data = components::get::<Extractor>(extractor_path.span())
        .expect(errors::EXTRACTOR_NOT_FOUND);

    extractor_data.assert_ready();
    assert(
        extractor_slot > 0 && extractor_slot <= extractor_slots::count(extractor),
        'unknown extractor slot'
    );

    let deposit_data = if baseline {
        assert(mining_rate::enabled(), 'prospecting not activated');
        Option::None
    } else {
        let data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        data.assert_extractable();
        assert(data.remaining_yield >= yield, errors::INSUFFICIENT_YIELD);
        Option::Some(data)
    };
    let resource = match deposit_data {
        Option::Some(data) => data.resource,
        Option::None(_) => resource
    };
    let (ext_ast, ext_lot) = extractor.to_position();
    let (deposit_ast, deposit_lot) = if baseline {
        (ext_ast, ext_lot)
    } else {
        deposit.to_position()
    };
    assert(ext_ast == deposit_ast, errors::DIFFERENT_ASTEROIDS);
    assert(ext_lot == deposit_lot && ext_lot != 0, errors::DIFFERENT_LOTS);

    let (dest_ast, dest_lot) = destination.to_position();
    assert(
        (dest_ast == deposit_ast) && (crew_details.asteroid_id() == deposit_ast),
        errors::DIFFERENT_ASTEROIDS
    );
    assert((dest_lot != 0) && (crew_details.lot_id() != 0), errors::IN_ORBIT);

    // Check that the destination exists and is ready to receive
    if destination.label == entities::BUILDING {
        components::get::<Building>(destination.path())
            .expect(errors::BUILDING_NOT_FOUND)
            .assert_operational();
    } else if destination.label == entities::SHIP {
        components::get::<Ship>(destination.path())
            .expect(errors::SHIP_NOT_FOUND)
            .assert_stationary();
        let location = components::get::<Location>(destination.path())
            .expect(errors::LOCATION_NOT_FOUND);

        match components::get::<Building>(location.location.path()) {
            Option::Some(building_data) => building_data.assert_operational(),
            Option::None(_) => ()
        };
    }

    let mut destination_path: Array<felt252> = Default::default();
    destination_path.append(destination.into());
    destination_path.append(destination_slot.into());
    let mut destination_data = components::get::<Inventory>(destination_path.span())
        .expect(errors::INVENTORY_NOT_FOUND);

    let asteroid = EntityTrait::new(entities::ASTEROID, dest_ast);
    let celestial_data = components::get::<Celestial>(asteroid.path())
        .expect(errors::CELESTIAL_NOT_FOUND);
    let resource_bonus = celestial_data.bonus_by_resource(resource);
    let extract_eff = crew_details.bonus(modifier_types::EXTRACTION_TIME, context.now)
        * resource_bonus;
    let accel: u64 = config::get('TIME_ACCELERATION').try_into().unwrap();
    let (extract_time, rate_bps, reference_abundance_ppm) = if mining_rate::enabled()
        || components::get::<Claim>(deposit.path()).is_some() {
        celestial_data.assert_resource_scanned();
        let (abundance, rate) = if baseline {
            mining_rate::baseline_parameters(ext_ast, ext_lot, resource, celestial_data)
        } else {
            mining_rate::parameters(deposit, ext_ast, ext_lot, resource)
        };
        (mining_rate::extraction_time(yield, abundance, rate, extract_eff, accel), rate, abundance)
    } else {
        let data = deposit_data.unwrap();
        let max_yield = FixedTrait::new(extractor::MAX_YIELD_PER_RUN, false);
        let start_ratio = FixedTrait::new_unscaled(data.remaining_yield.into(), false) / max_yield;
        let end_ratio = FixedTrait::new_unscaled(data.remaining_yield.into() - yield.into(), false)
            / max_yield;
        let raw = (start_ratio.sqrt() - end_ratio.sqrt())
            * FixedTrait::new(extractor::MAX_EXTRACTION_TIME * ONE / accel, false);
        ((raw / extract_eff).mag.div_ceil(ONE), 0, 0)
    };

    // Calculate the crew and hopper transfer times
    let hopper_eff = crew_details.bonus(modifier_types::HOPPER_TRANSPORT_TIME, context.now);
    let dist_eff = crew_details.bonus(modifier_types::FREE_TRANSPORT_DISTANCE, context.now);
    let dep_to_dest = position::hopper_travel_time(
        deposit_lot, dest_lot, celestial_data.radius, hopper_eff, dist_eff
    );

    let crew_to_lot = position::hopper_travel_time(
        crew_details.lot_id(), deposit_lot, celestial_data.radius, hopper_eff, dist_eff
    );

    // Reserve space in destination inventory
    let mut reserved_items: Array<InventoryItem> = Default::default();
    reserved_items.append(InventoryItemTrait::new(resource, yield));
    let mass_eff = crew_details.bonus(modifier_types::INVENTORY_MASS_CAPACITY, context.now);
    let volume_eff = crew_details.bonus(modifier_types::INVENTORY_VOLUME_CAPACITY, context.now);
    inventory::reserve(ref destination_data, reserved_items.span(), mass_eff, volume_eff);
    components::set::<Inventory>(destination_path.span(), destination_data);

    // Update the deposit
    if let Option::Some(mut data) = deposit_data {
        data.remaining_yield -= yield;
        data.status = deposit_statuses::USED;
        components::set::<Deposit>(deposit.path(), data);
    }

    // Update the extractor
    let finish_time = crew_data.busy_until(context.now) + crew_to_lot + extract_time + dep_to_dest;
    assert(yield == 0 || finish_time > context.now, 'extraction duration is zero');
    extractor_data.status = extractor_statuses::RUNNING;
    extractor_data.output_product = resource;
    extractor_data.yield = yield;
    extractor_data.destination = destination;
    extractor_data.destination_slot = destination_slot;
    extractor_data.finish_time = finish_time;
    components::set::<Extractor>(extractor_path.span(), extractor_data);

    // Check that the crew has the necessary permissions given the processing time
    caller_crew.assert_can_until(extractor, permissions::EXTRACT_RESOURCES, finish_time);
    caller_crew.assert_can_until(destination, permissions::ADD_PRODUCTS, finish_time);

    // Update the crew & ship (there + processing time + back)
    let crew_time = extract_time.div_ceil(8);
    crew_data.add_busy(context.now, crew_to_lot + crew_time + crew_to_lot);
    crew_data.set_action(actions::EXTRACT_RESOURCE_STARTED, extractor, crew_time, context.now);
    components::set::<Crew>(caller_crew.path(), crew_data);

    let (station_ship, mut station_ship_data) = crew_details.ship();
    if caller_crew != station_ship {
        station_ship_data.extend_ready(crew_data.ready_at);
        components::set::<Ship>(station_ship.path(), station_ship_data);
    }

    ExtractionResult { resource, finish_time, rate_bps, reference_abundance_ppm }
}
