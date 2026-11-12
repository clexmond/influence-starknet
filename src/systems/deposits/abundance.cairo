#[starknet::contract]
mod Abundance {
    use influence::components;
    use influence::components::Celestial;
    use influence::config::{entities, errors};
    use influence::types::{Context, EntityTrait};
    use cubit::f64::Fixed;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn prospecting_version(self: @ContractState) -> u64 {
        1
    }
    #[external(v0)]
    fn ppm(self: @ContractState, asteroid: u64, lot: u64, resource: u64) -> u64 {
        let celestial = components::get::<
            Celestial
        >(EntityTrait::new(entities::ASTEROID, asteroid).path())
            .expect(errors::CELESTIAL_NOT_FOUND);
        influence::common::abundance::lot_ppm(asteroid, lot, resource, celestial)
    }
    #[external(v0)]
    fn run(
        self: @ContractState, ast: u64, lot: u64, resource: u64, context: Context
    ) -> (Fixed, Fixed, Fixed) {
        let celestial = components::get::<
            Celestial
        >(EntityTrait::new(entities::ASTEROID, ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);
        influence::common::abundance::at_lot(ast, lot, resource, celestial)
    }
}
