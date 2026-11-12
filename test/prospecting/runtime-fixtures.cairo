// Compiled only in the isolated runtime fixture package.
#[starknet::contract]
mod ProspectingRuntimeSeed {
    use array::ArrayTrait;
    use cubit::{f64::FixedTrait, f128};
    use influence::{components, config, runtime_mocks as mocks};
    use influence::common::inventory;
    use influence::components::{Celestial, CelestialTrait, Control, ControlTrait, Crew, Location, LocationTrait,
        Inventory, ExtractorSlots, Unique};
    use influence::components::modifier_type::types as modifiers;
    use influence::components::product_type::types as products;
    use influence::types::{Context, ContextTrait, EntityTrait, InventoryItemTrait};
    use influence::config::entities;
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, player: ContractAddress, other: ContractAddress, context: Context) {
        assert(context.is_admin(), 'fixture admin only');
        mocks::constants();
        config::set('PROSPECTING_ENABLED', 0);
        for modifier in array![modifiers::CORE_SAMPLE_TIME, modifiers::CORE_SAMPLE_QUALITY, modifiers::EXTRACTION_TIME,
            modifiers::HOPPER_TRANSPORT_TIME, modifiers::FREE_TRANSPORT_DISTANCE,
            modifiers::INVENTORY_MASS_CAPACITY, modifiers::INVENTORY_VOLUME_CAPACITY] { mocks::modifier_type(modifier); };
        for product in array![products::CORE_DRILL, products::WATER, products::HYDROGEN] { mocks::product_type(product); };
        let asteroid = EntityTrait::new(entities::ASTEROID, 250000);
        let mut celestial = CelestialTrait::new(1, f128::FixedTrait::new_unscaled(1000000, false), FixedTrait::new(4396773074, false));
        celestial.scan_status = 4;
        celestial.abundances = 500 + 49 * 1024;
        components::set::<Celestial>(asteroid.path(), celestial);
        let crew = mocks::delegated_crew(1, player.into());
        mocks::delegated_crew(2, other.into());
        let lot = EntityTrait::from_position(asteroid.id, 1);
        let station = mocks::public_habitat(crew, 1);
        let warehouse = mocks::public_warehouse(crew, 3);
        let extractor = mocks::public_extractor(crew, 4);
        for building in array![station, warehouse, extractor] {
            components::set::<Location>(building.path(), LocationTrait::new(lot));
        };
        components::set::<Location>(crew.path(), LocationTrait::new(station));
        let mut data = components::get::<Crew>(crew.path()).unwrap();
        data.last_fed = context.now;
        components::set::<Crew>(crew.path(), data);
        components::set::<Control>(asteroid.path(), ControlTrait::new(crew));
        components::set::<Unique>(array!['LotUse', lot.into()].span(), Unique { unique: extractor.into() });
        components::set::<ExtractorSlots>(extractor.path(), ExtractorSlots { count: 2 });
        let second = components::get::<components::Extractor>(array![extractor.into(), 1].span()).unwrap();
        components::set::<components::Extractor>(array![extractor.into(), 2].span(), second);
        let path = array![warehouse.into(), 2].span();
        let mut stock = components::get::<Inventory>(path).unwrap();
        inventory::add_unchecked(ref stock, array![InventoryItemTrait::new(products::CORE_DRILL, 100)].span());
        components::set::<Inventory>(path, stock);
        let starter = 'ProspectingRuntime';
        config::set('STARTER_MISSION_CAMPAIGN', starter);
        config::set('STARTER_MISSION_CUTOFF', 0);
        // The first mission is completed and prospecting is accepted in this fixture.
        influence::common::missions::write(array!['Lifecycle', starter, crew.into(), 0].span(), 4294967299);
    }
}
