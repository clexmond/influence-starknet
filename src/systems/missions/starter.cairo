use influence::components::product_type::types as products;
use influence::components::processor::types as processors;
use influence::components::process_type::types as processes;
use influence::components::building_type::types as buildings;
use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use serde::Serde;
use traits::{Into, TryInto};
use starknet::ContractAddress;
use cubit::f64::{Fixed, FixedTrait};
use influence::{components, config};
use influence::common::{missions, mission_eligibility as eligibility};
use influence::common::missions::Assignment;
use influence::components::{
    Building, BuildingTrait, Crew, CrewTrait, Deposit, Extractor, Processor, Inventory,
    ProductTypeTrait, ProcessTypeTrait, ProcessType, Delivery, BuildingTypeTrait
};
use influence::components::building::statuses as building_status;
use influence::components::delivery::statuses as delivery_status;
use influence::types::{Entity, EntityTrait, InventoryItem, InventoryContentsTrait};
use influence::config::entities;
use influence::types::Context;

// Slot 0: requirement bits 0..7, sample count 8..9, upstream route bits 10..14.
// Slot 1: campaign Warehouse ID. Slots 100+: final-product bitmaps (128 per word).
// Pending actions and construction evidence are keyed by entity/slot.
fn key(kind: felt252, entity: Entity, slot: u64) -> felt252 {
    poseidon::poseidon_hash_span(array![kind, entity.into(), slot.into()].span())
}

fn hash<T, impl S: Serde<T>, impl D: Drop<T>>(value: @T) -> felt252 {
    let mut data = array![];
    Serde::<T>::serialize(value, ref data);
    poseidon::poseidon_hash_span(data.span())
}

fn parse<T, impl S: Serde<T>, impl D: Drop<T>>(mut args: Span<felt252>) -> T {
    let value = Serde::<T>::deserialize(ref args).expect('invalid mission arguments');
    assert(args.is_empty(), 'trailing mission arguments');
    value
}

fn encoded<T, impl S: Serde<T>, impl D: Drop<T>>(value: @T) -> Array<felt252> {
    let mut data = array![];
    Serde::<T>::serialize(value, ref data);
    data
}

fn run<T, impl S: Serde<T>, impl D: Drop<T>>(
    action: felt252, value: @T, crew: Entity, context: Context
) {
    missions::execute(action, encoded(value), crew, context);
}

fn building_fingerprint(building: Entity, data: Building) -> felt252 {
    hash(@(building, data.building_type, data.planned_at, data.finish_time))
}

fn earned(a: Assignment, index: u32) -> bool {
    let word: u128 = missions::state(a, 0).try_into().unwrap();
    word / missions::bit(index) % 2 == 1
}

fn earn(a: Assignment, index: u32) {
    if !earned(a, index) {
        let word: u128 = missions::state(a, 0).try_into().unwrap();
        missions::set_state(a, 0, (word + missions::bit(index)).into());
    }
}

fn record_sample(a: Assignment, initial_yield: u64) {
    if initial_yield >= 500000 && !earned(a, 1) {
        let word: u128 = missions::state(a, 0).try_into().unwrap();
        let count = word / 256 % 4 + 1;
        missions::set_state(a, 0, (word + 256).into());
        if count == 3 {
            earn(a, 1);
        }
    }
}

fn final_product(a: Assignment, product: u64) -> bool {
    let word: u128 = missions::state(a, (100 + product / 128).into()).try_into().unwrap();
    word / missions::bit((product % 128).try_into().unwrap()) % 2 == 1
}

fn record_final_product(a: Assignment, product: u64) {
    if !final_product(a, product) {
        let slot = (100 + product / 128).into();
        let word: u128 = missions::state(a, slot).try_into().unwrap();
        missions::set_state(
            a, slot, (word + missions::bit((product % 128).try_into().unwrap())).into()
        );
    }
}

fn selected(a: Assignment, kind: u64) -> Entity {
    EntityTrait::new(entities::BUILDING, missions::state(a, kind.into()).try_into().unwrap())
}

fn own_building(a: Assignment, building: Entity) -> Building {
    assert(building.label == entities::BUILDING, 'not a building');
    a.subject.assert_controls(building);
    let data = components::get::<Building>(building.path()).expect('building missing');
    data.assert_operational();
    assert(
        missions::state(a, key('Built', building, 0)) == building_fingerprint(building, data),
        'not campaign construction'
    );
    data
}

fn storage_received(a: Assignment, destination: Entity, slot: u64) {
    if destination == selected(a, 1) && slot == 2 && !earned(a, 3) {
        own_building(a, destination);
        let inventory = components::get::<Inventory>(array![destination.into(), slot.into()].span())
            .expect('inventory missing');
        if inventory.mass >= 100000000 {
            earn(a, 3);
        }
    }
}

fn economic(a: Assignment, items: Span<InventoryItem>) {
    let mut items = items;
    loop {
        match items.pop_front() {
            Option::Some(item) => {
                if *item.amount > 0 && final_product(a, *item.product) {
                    earn(a, 7);
                }
            },
            Option::None(_) => { break; }
        }
    };
}

fn new_entity(label: u64, scope: felt252, before: u64) -> Entity {
    let after = influence::entities::current_id(scope);
    assert(after == before + 1, 'unexpected entity creation');
    EntityTrait::new(label, after)
}

fn process_commit(data: Processor) -> felt252 {
    let cfg = ProcessTypeTrait::by_type(data.running_process);
    hash(@(data, cfg))
}

fn routes(index: u32) -> (u64, u64, u64) {
    if index == 0 {
        (
            processes::WATER_VACUUM_EVAPORATION_DESALINATION,
            processes::WATER_ELECTROLYSIS,
            products::DEIONIZED_WATER
        )
    } else if index == 1 {
        (processes::CALCITE_CALCINATION, processes::SALTY_CEMENT_MIXING, products::QUICKLIME)
    } else if index == 2 {
        (processes::BITUMEN_HYDRO_CRACKING, processes::NAPHTHA_STEAM_CRACKING, products::NAPHTHA)
    } else if index == 3 {
        (
            processes::SILICA_FUSING,
            processes::QUARTZ_FILAMENT_DRAWING_AND_WRAPPING,
            products::FUSED_QUARTZ
        )
    } else {
        (
            processes::SOYBEAN_GROWING,
            processes::BASIC_FOOD_COOKING_AND_PACKAGING,
            products::SOYBEANS
        )
    }
}

fn completed_process(a: Assignment, data: Processor, downstream: u128) {
    let cfg = ProcessTypeTrait::by_type(data.running_process);
    let outputs = influence::systems::production::helpers::outputs(
        cfg.outputs, data.output_product, data.recipes, data.secondary_eff
    );
    if data.processor_type == processors::REFINERY {
        earn(a, 4);
    } else if data.processor_type == processors::BIOREACTOR {
        earn(a, 5);
    } else if data.processor_type == processors::FACTORY {
        earn(a, 6);
    }
    let mut i = 0;
    loop {
        if i == 5 {
            break;
        }
        let (first, second, product) = routes(i);
        if data.running_process == first && outputs.amount_of(product) > 0 {
            earn(a, 10 + i);
        }
        if data.running_process == second && downstream / missions::bit(i) % 2 == 1 {
            let mut items = outputs;
            loop {
                match items.pop_front() {
                    Option::Some(item) => {
                        if *item.amount > 0 {
                            record_final_product(a, *item.product);
                        }
                    },
                    Option::None(_) => { break; }
                }
            };
        }
        i += 1;
    };
}

fn check_context(a: Assignment, context: Context) {
    assert(a.campaign == config::get('STARTER_MISSION_CAMPAIGN'), 'wrong starter campaign');
    assert(a.subject.label == entities::CREW && a.mission < 8, 'invalid starter subject');
    assert(
        context.payment_amount == 0 && context.payment_to.is_zero(), 'unsupported payment context'
    );
}

fn authorize(a: Assignment, context: Context) {
    eligibility::assert_valid(a.subject);
    components::get::<Crew>(a.subject.path()).unwrap().assert_delegated_to(context.caller);
}

fn validate(a: Assignment) {
    let mut i = 0_u32;
    loop {
        if i == 8 {
            break;
        }
        let step = Assignment { mission: i, ..a };
        if missions::flag(step, 0)
            && earned(a, i)
            && (i == 0 || missions::flag(Assignment { mission: i - 1, ..a }, 1)) {
            missions::set_flag(step, 1);
        }
        i += 1;
    };
}

fn action(a: Assignment, name: felt252, args: Span<felt252>, context: Context) {
    authorize(a, context);
    eligibility::participate(a.subject);
    if name == 'ConstructionPlan' {
        let (kind, lot) = parse::<(u64, Entity)>(args);
        assert(kind >= buildings::WAREHOUSE && kind <= buildings::FACTORY, 'unsupported building');
        if kind == buildings::WAREHOUSE {
            assert(selected(a, 1).is_empty(), 'warehouse already planned');
        }
        let before = influence::entities::current_id(entities::BUILDING.into());
        run(name, @(kind, lot), a.subject, context);
        let building = new_entity(entities::BUILDING, entities::BUILDING.into(), before);
        if kind == buildings::WAREHOUSE {
            missions::set_state(a, 1, building.id.into());
            earn(a, 0);
        }
    } else if name == 'ConstructionStart' {
        let building = parse::<Entity>(args);
        let old = components::get::<Building>(building.path()).expect('building missing');
        assert(
            old.building_type >= buildings::WAREHOUSE && old.building_type <= buildings::FACTORY,
            'unsupported building'
        );
        if old.building_type == buildings::WAREHOUSE {
            assert(building == selected(a, 1), 'wrong warehouse');
        }
        let cfg = BuildingTypeTrait::by_type(old.building_type);
        let inputs = ProcessTypeTrait::by_type(cfg.process_type).inputs;
        let site = components::get::<
            Inventory
        >(array![building.into(), cfg.site_slot.into()].span())
            .expect('inventory missing');
        let mut supplied = true;
        let mut items = inputs;
        loop {
            match items.pop_front() {
                Option::Some(item) => {
                    if site.contents.amount_of(*item.product) < *item.amount {
                        supplied = false;
                    }
                },
                Option::None(_) => { break; }
            }
        };
        run(name, @building, a.subject, context);
        if supplied {
            economic(a, inputs);
        }
        let data = components::get::<Building>(building.path()).unwrap();
        missions::set_state(a, key('Built', building, 0), building_fingerprint(building, data));
    } else if name == 'ConstructionFinish' {
        let building = parse::<Entity>(args);
        run(name, @building, a.subject, context);
        own_building(a, building);
    } else if name == 'SampleDepositStart' {
        let params = parse::<(Entity, u64, Entity, u64)>(args);
        let before = influence::entities::current_id(entities::DEPOSIT.into());
        run(name, @params, a.subject, context);
        let deposit = new_entity(entities::DEPOSIT, entities::DEPOSIT.into(), before);
        let data = components::get::<Deposit>(deposit.path()).unwrap();
        missions::set_state(a, key('Sample', deposit, 0), hash(@data));
    } else if name == 'SampleDepositFinish' {
        let deposit = parse::<Entity>(args);
        let data = components::get::<Deposit>(deposit.path()).expect('deposit missing');
        assert(missions::state(a, key('Sample', deposit, 0)) == hash(@data), 'unbound sample');
        assert(data.initial_yield == 0, 'not initial sampling');
        run(name, @deposit, a.subject, context);
        missions::set_state(a, key('Sample', deposit, 0), 0);
        let result = components::get::<Deposit>(deposit.path()).unwrap();
        record_sample(a, result.initial_yield);
    } else if name == 'ExtractResourceStart' {
        let (deposit, amount, building, slot, destination, dest_slot) = parse::<
            (Entity, u64, Entity, u64, Entity, u64)
        >(args);
        let data = own_building(a, building);
        assert(data.building_type == buildings::EXTRACTOR, 'not extractor');
        let dep = components::get::<Deposit>(deposit.path()).expect('deposit missing');
        assert(
            dep.resource >= products::WATER && dep.resource <= products::URANINITE,
            'not raw resource'
        );
        let amount_wide: u128 = amount.into();
        let unit_mass: u128 = ProductTypeTrait::by_type(dep.resource).mass.into();
        assert(amount_wide * unit_mass >= 100000000_u128, 'extraction below threshold');
        run(name, @(deposit, amount, building, slot, destination, dest_slot), a.subject, context);
        let extractor = components::get::<Extractor>(array![building.into(), slot.into()].span())
            .unwrap();
        assert(extractor.finish_time > context.now, 'zero duration');
        missions::set_state(a, key('Extraction', building, slot), hash(@extractor));
    } else if name == 'ExtractResourceFinish' {
        let (building, slot) = parse::<(Entity, u64)>(args);
        own_building(a, building);
        let extractor = components::get::<Extractor>(array![building.into(), slot.into()].span())
            .expect('extractor missing');
        assert(
            missions::state(a, key('Extraction', building, slot)) == hash(@extractor),
            'unbound extraction'
        );
        run(name, @(building, slot), a.subject, context);
        missions::set_state(a, key('Extraction', building, slot), 0);
        earn(a, 2);
        storage_received(a, extractor.destination, extractor.destination_slot);
    } else if name == 'ProcessProductsStart' {
        let (
            building, slot, process, output, recipes, origin, origin_slot, destination, dest_slot
        ) =
            parse::<
            (Entity, u64, u64, u64, Fixed, Entity, u64, Entity, u64)
        >(args);
        let data = own_building(a, building);
        assert(
            data.building_type >= buildings::REFINERY && data.building_type <= buildings::FACTORY,
            'unsupported processor'
        );
        assert(recipes >= FixedTrait::ONE(), 'recipe below threshold');
        let cfg = ProcessTypeTrait::by_type(process);
        let inputs = influence::systems::production::helpers::inputs(cfg.inputs, recipes);
        let mut downstream = 0_u128;
        let mut i = 0_u32;
        loop {
            if i == 5 {
                break;
            }
            let (_, second, product) = routes(i);
            if process == second && earned(a, 10 + i) && inputs.amount_of(product) > 0 {
                downstream += missions::bit(i);
            }
            i += 1;
        };
        run(
            name,
            @(
                building,
                slot,
                process,
                output,
                recipes,
                origin,
                origin_slot,
                destination,
                dest_slot
            ),
            a.subject,
            context
        );
        let processor = components::get::<Processor>(array![building.into(), slot.into()].span())
            .unwrap();
        assert(processor.finish_time > context.now, 'zero duration');
        missions::set_state(a, key('Process', building, slot), process_commit(processor));
        missions::set_state(a, key('Downstream', building, slot), downstream.into());
        economic(a, inputs);
    } else if name == 'ProcessProductsFinish' {
        let (building, slot) = parse::<(Entity, u64)>(args);
        own_building(a, building);
        let processor = components::get::<Processor>(array![building.into(), slot.into()].span())
            .expect('processor missing');
        assert(
            missions::state(a, key('Process', building, slot)) == process_commit(processor),
            'unbound process'
        );
        let downstream = missions::state(a, key('Downstream', building, slot)).try_into().unwrap();
        run(name, @(building, slot), a.subject, context);
        missions::set_state(a, key('Process', building, slot), 0);
        missions::set_state(a, key('Downstream', building, slot), 0);
        completed_process(a, processor, downstream);
        storage_received(a, processor.destination, processor.destination_slot);
    } else if name == 'SendDelivery' {
        let (origin, origin_slot, items, destination, dest_slot) = parse::<
            (Entity, u64, Span<InventoryItem>, Entity, u64)
        >(args);
        assert(origin != destination, 'self delivery not economic');
        let before = influence::entities::current_id('Delivery');
        run(name, @(origin, origin_slot, items, destination, dest_slot), a.subject, context);
        let delivery = new_entity(entities::DELIVERY, 'Delivery', before);
        bind_delivery(a, delivery, true);
    } else if name == 'ReceiveDelivery' {
        let delivery = parse::<Entity>(args);
        let bound = missions::state(a, key('Delivery', delivery, 0));
        if bound == 0 {
            // Receiving into our Warehouse is itself attributable to this crew;
            // the sender (including a marketplace seller) need not participate.
            let incoming = components::get::<Delivery>(delivery.path()).expect('delivery missing');
            assert(incoming.dest == selected(a, 1) && incoming.dest_slot == 2, 'unbound delivery');
            own_building(a, incoming.dest);
            bind_delivery(a, delivery, false);
        }
        run(name, @delivery, a.subject, context);
        credit_delivery(a, delivery);
    } else if name == 'ResupplyFood' {
        let (origin, slot, amount) = parse::<(Entity, u64, u64)>(args);
        assert(!origin.is_empty(), 'allowance is not consumption');
        run(name, @(origin, slot, amount), a.subject, context);
        economic(a, array![InventoryItem { product: products::FOOD, amount }].span());
    } else if name == 'FillSellOrder' {
        let (
            seller,
            exchange,
            product,
            amount,
            price,
            storage,
            storage_slot,
            destination,
            dest_slot,
            buyer
        ) =
            parse::<
            (Entity, Entity, u64, u64, u64, Entity, u64, Entity, u64, Entity)
        >(args);
        assert(buyer == a.subject, 'not campaign buyer');
        let before = influence::entities::current_id('Delivery');
        run(
            name,
            @(
                seller,
                exchange,
                product,
                amount,
                price,
                storage,
                storage_slot,
                destination,
                dest_slot
            ),
            buyer,
            context
        );
        let delivery = new_entity(entities::DELIVERY, 'Delivery', before);
        bind_delivery(a, delivery, false);
    } else {
        panic_with_felt252('unsupported mission action');
    }
}

fn bind_delivery(a: Assignment, delivery: Entity, economic_use: bool) {
    let data = components::get::<Delivery>(delivery.path()).unwrap();
    missions::set_state(
        a,
        key('Delivery', delivery, 0),
        hash(
            @(
                data.origin,
                data.origin_slot,
                data.dest,
                data.dest_slot,
                data.finish_time,
                data.contents
            )
        )
    );
    if economic_use {
        let mut eligible = false;
        let mut items = data.contents;
        loop {
            match items.pop_front() {
                Option::Some(item) => {
                    if *item.amount > 0 && final_product(a, *item.product) {
                        eligible = true;
                    }
                },
                Option::None(_) => { break; }
            }
        };
        if eligible {
            missions::set_state(a, key('EconomicDelivery', delivery, 0), 1);
        }
    }
}

fn credit_delivery(a: Assignment, delivery: Entity) {
    let data = components::get::<Delivery>(delivery.path()).expect('delivery missing');
    assert(data.status == delivery_status::COMPLETE, 'delivery incomplete');
    assert(
        missions::state(
            a, key('Delivery', delivery, 0)
        ) == hash(
            @(
                data.origin,
                data.origin_slot,
                data.dest,
                data.dest_slot,
                data.finish_time,
                data.contents
            )
        ),
        'delivery changed'
    );
    storage_received(a, data.dest, data.dest_slot);
    if missions::state(a, key('EconomicDelivery', delivery, 0)) != 0 {
        earn(a, 7);
    }
    missions::set_state(a, key('Delivery', delivery, 0), 0);
    missions::set_state(a, key('EconomicDelivery', delivery, 0), 0);
}

#[starknet::contract]
mod StarterMissionCampaign {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use traits::Into;
    use starknet::ContractAddress;
    use influence::{components, common::{missions, mission_eligibility as eligibility}};
    use influence::common::missions::Assignment;
    use influence::components::Crew;
    use influence::types::{Context, Entity, EntityTrait};
    use super::{check_context, authorize, action, credit_delivery, parse, validate};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn evaluate(
        ref self: ContractState,
        assignment: Assignment,
        operation: u32,
        action_name: felt252,
        args: Span<felt252>,
        context: Context
    ) -> (ContractAddress, u128) {
        let a = assignment;
        check_context(a, context);
        if operation == 3 {
            assert(args.is_empty(), 'unexpected claim args');
            let delegate = components::get::<Crew>(a.subject.path())
                .expect('crew missing')
                .delegated_to;
            let rewards = array![5000_u128, 20000, 30000, 20000, 50000, 35000, 40000, 25000];
            return (delegate, *rewards.at(a.mission.into()) * 1000000);
        }
        eligibility::assert_valid(a.subject);
        if operation == 0 {
            authorize(a, context);
            assert(args.is_empty(), 'unexpected acceptance args');
            if a.mission > 0 {
                assert(
                    missions::flag(Assignment { mission: a.mission - 1, ..a }, 1),
                    'prerequisite incomplete'
                );
            }
        } else if operation == 1 {
            action(a, action_name, args, context);
        } else if operation == 2 {
            if !args.is_empty() {
                authorize(a, context);
                credit_delivery(a, parse::<Entity>(args));
            }
            validate(a);
        } else {
            panic_with_felt252('unknown mission operation');
        }
        (starknet::contract_address_const::<0>(), 0)
    }
}

#[starknet::contract]
mod ConfigureStarterMissions {
    use array::ArrayTrait;
    use traits::Into;
    use influence::{config, common::missions};
    use influence::types::{Context, ContextTrait};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, campaign: felt252, crew_cutoff: u64, context: Context) {
        assert(context.is_admin(), 'only admin');
        assert(config::get('STARTER_MISSION_CAMPAIGN') == 0, 'starter already configured');
        assert(
            campaign != 0 && missions::read(array!['DefinitionCount', campaign].span()) == 8,
            'invalid starter definition'
        );
        config::set_with_event('STARTER_MISSION_CUTOFF', crew_cutoff.into());
        config::set_with_event('STARTER_MISSION_CAMPAIGN', campaign);
    }
}
