use array::ArrayTrait;
use option::OptionTrait;
use traits::Into;
use cubit::f64::FixedTrait;
use influence::{components, config};
use influence::components::{
    BuildingTypeTrait, ProcessType, ProcessTypeTrait, Processor, Extractor, Location
};
use influence::components::building_type::types as buildings;
use influence::components::process_type::types as processes;
use influence::components::product_type::types as products;
use influence::config::entities;
use influence::types::{EntityTrait};
use influence::systems::production::{ProcessProductsStart, ExtractResourceStart};
use influence::systems::construction::ConstructionStart;
use influence::test::{mocks, starter_missions};

// Co-location removes travel time, so these tests exercise the production duration itself.
// A zero/zero ProcessType is already considered unset by the existing component validator.
#[test]
#[available_gas(200000000)]
#[should_panic(expected: ('E1036: process type not found',))]
fn mission_duration_existing_validation_rejects_empty_process() {
    let (a, asteroid, warehouse) = starter_missions::landfall();
    let refinery = starter_missions::construct(a, asteroid, buildings::REFINERY);
    components::set::<
        Location
    >(refinery.path(), components::get::<Location>(warehouse.path()).unwrap());
    let mut cfg = ProcessTypeTrait::by_type(processes::WATER_VACUUM_EVAPORATION_DESALINATION);
    cfg.setup_time = 0;
    cfg.recipe_time = 0;
    components::set::<
        ProcessType
    >(array![processes::WATER_VACUUM_EVAPORATION_DESALINATION.into()].span(), cfg);
    starter_missions::supply(warehouse, 2, cfg.inputs);
    starter_missions::ready(a.subject);
    let mut start = ProcessProductsStart::contract_state_for_testing();
    ProcessProductsStart::run(
        ref start,
        refinery,
        1,
        processes::WATER_VACUUM_EVAPORATION_DESALINATION,
        products::DEIONIZED_WATER,
        FixedTrait::ONE(),
        warehouse,
        2,
        warehouse,
        2,
        a.subject,
        mocks::context('PLAYER')
    );
}

#[test]
#[available_gas(200000000)]
fn mission_duration_fractional_processing_remains_supported() {
    let (a, asteroid, warehouse) = starter_missions::landfall();
    let refinery = starter_missions::construct(a, asteroid, buildings::REFINERY);
    components::set::<
        Location
    >(refinery.path(), components::get::<Location>(warehouse.path()).unwrap());
    starter_missions::ready(a.subject);
    starter_missions::supply(
        warehouse,
        2,
        ProcessTypeTrait::by_type(processes::WATER_VACUUM_EVAPORATION_DESALINATION).inputs
    );
    let mut start = ProcessProductsStart::contract_state_for_testing();
    ProcessProductsStart::run(
        ref start,
        refinery,
        1,
        processes::WATER_VACUUM_EVAPORATION_DESALINATION,
        products::DEIONIZED_WATER,
        FixedTrait::new(2147483648, false),
        warehouse,
        2,
        warehouse,
        2,
        a.subject,
        mocks::context('PLAYER')
    );
    let processor = components::get::<Processor>(array![refinery.into(), 1].span()).unwrap();
    assert(processor.finish_time > starknet::get_block_timestamp(), 'positive setup lost');
}

#[test]
#[available_gas(200000000)]
#[should_panic(expected: ('E1036: process type not found',))]
fn mission_duration_existing_validation_rejects_empty_construction() {
    let (a, asteroid) = starter_missions::setup();
    starter_missions::accept(a, 0);
    let lot = EntityTrait::from_position(asteroid.id, 1758637);
    starter_missions::act(a, 'ConstructionPlan', @(buildings::WAREHOUSE, lot));
    let building = EntityTrait::new(
        entities::BUILDING, influence::entities::current_id(entities::BUILDING.into())
    );
    let kind = BuildingTypeTrait::by_type(buildings::WAREHOUSE);
    let mut cfg = ProcessTypeTrait::by_type(kind.process_type);
    starter_missions::supply(building, kind.site_slot, cfg.inputs);
    cfg.setup_time = 0;
    cfg.recipe_time = 0;
    components::set::<ProcessType>(array![kind.process_type.into()].span(), cfg);
    starter_missions::ready(a.subject);
    let mut start = ConstructionStart::contract_state_for_testing();
    ConstructionStart::run(ref start, building, a.subject, mocks::context('PLAYER'));
}

#[test]
#[available_gas(200000000)]
fn mission_duration_smallest_positive_extraction_remains_supported() {
    let (a, asteroid, warehouse) = starter_missions::landfall();
    let extractor = starter_missions::construct(a, asteroid, buildings::EXTRACTOR);
    let deposit = mocks::controlled_deposit(a.subject, 1, products::WATER);
    let location = components::get::<Location>(warehouse.path()).unwrap();
    components::set::<Location>(extractor.path(), location);
    components::set::<Location>(deposit.path(), location);
    starter_missions::ready(a.subject);
    let mut start = ExtractResourceStart::contract_state_for_testing();
    ExtractResourceStart::run(
        ref start, deposit, 1, extractor, 1, warehouse, 2, a.subject, mocks::context('PLAYER')
    );
    let data = components::get::<Extractor>(array![extractor.into(), 1].span()).unwrap();
    assert(data.finish_time > starknet::get_block_timestamp(), 'positive extraction rounded out');
}

#[test]
#[available_gas(1000000)]
fn mission_duration_rounds_subsecond_processing_up() {
    config::set('TIME_ACCELERATION', 24);
    let (setup, variable) = influence::systems::production::helpers::time(
        1, 1, false, FixedTrait::ONE(), FixedTrait::new_unscaled(100, false)
    );
    assert(setup == 1 && variable == 1, 'subsecond duration rounded down');
}
