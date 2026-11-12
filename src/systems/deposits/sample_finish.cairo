// Finishes sampling a deposit generating the initial yield (in kg)
#[starknet::contract]
mod SampleDepositFinish {
    use array::{ArrayTrait, SpanTrait};
    use option::OptionTrait;
    use starknet::ContractAddress;
    use traits::{Into, TryInto};

    use cubit::f64::procgen::rand;
    use cubit::f64::{Fixed, FixedTrait, ONE};

    use influence::common::{random, crew::CrewDetailsTrait};
    use influence::components;
    use influence::components::{Celestial,
        deposit::{MAX_YIELD, statuses as deposit_statuses, Deposit, DepositTrait}};
    use influence::config::{entities, errors};
    use influence::systems::deposits::helpers::deposit_commit_hash;
    use influence::types::{Context, Entity, EntityTrait};


    #[storage]
    struct Storage {}

    #[derive(Copy, Drop, starknet::Event)]
    struct SamplingDepositFinished {
        deposit: Entity,
        initial_yield: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct Debug_DepositBounds {
        lot_abundance: Fixed,
        initial_yield: u64,
        lower_bound: Fixed,
        upper_bound: Fixed
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        SamplingDepositFinished: SamplingDepositFinished,
        Debug_DepositBounds: Debug_DepositBounds
    }

    #[external(v0)]
    fn run(ref self: ContractState, deposit: Entity, caller_crew: Entity, context: Context) {
        // Check that crew is delegated
        let mut crew_details = CrewDetailsTrait::new(caller_crew);
        crew_details.assert_delegated_to(context.caller);

        // Check the deposit status
        let mut deposit_data = components::get::<Deposit>(deposit.path()).expect(errors::DEPOSIT_NOT_FOUND);
        assert(deposit_data.status == deposit_statuses::SAMPLING, errors::INCORRECT_STATUS);

        // Get abundance info from asteroid
        let (ast, lot) = deposit.to_position();
        let celestial_data = components::get::<Celestial>(EntityTrait::new(entities::ASTEROID, ast).path())
            .expect(errors::CELESTIAL_NOT_FOUND);

        let (lot_abundance, _, _) = influence::common::abundance::at_lot(
            ast, lot, deposit_data.resource, celestial_data
        );

        // Use lot abundance and rand reveal to calculate yield
        let mut upper_bound = lot_abundance;
        let mut lower_bound = FixedTrait::new(deposit_data.initial_yield.into() * ONE / MAX_YIELD, false);
        let range = upper_bound - lower_bound;

        if deposit_data.yield_eff.mag < ONE {
            upper_bound = lower_bound + range * deposit_data.yield_eff;
        } else {
            lower_bound = upper_bound - range / deposit_data.yield_eff;
        }

        let sample_seed = random::reveal(deposit_commit_hash(deposit, deposit_data.initial_yield));
        let mut raw_yield = FixedTrait::ZERO();

        if upper_bound > lower_bound {
            raw_yield = rand::fixed_normal_between(sample_seed, lower_bound, upper_bound);
        }

        let initial_yield = raw_yield.mag * MAX_YIELD / ONE;

        // Update and save deposit
        deposit_data.status = deposit_statuses::SAMPLED;
        deposit_data.initial_yield = initial_yield;
        deposit_data.remaining_yield = deposit_data.initial_yield;
        components::set::<Deposit>(deposit.path(), deposit_data);

        self.emit(SamplingDepositFinished {
            deposit: deposit,
            initial_yield: deposit_data.initial_yield,
            caller_crew: caller_crew,
            caller: context.caller
        });

        self.emit(Debug_DepositBounds {
            lot_abundance: lot_abundance,
            initial_yield: initial_yield,
            lower_bound: lower_bound,
            upper_bound: upper_bound
        });
    }

    use influence::common::abundance::scale;

}

// Tests --------------------------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use influence::config::MAX_ASTEROID_RADIUS;

    use cubit::f64::FixedTrait;
    use cubit::f64::test::helpers::assert_relative;

    use super::SampleDepositFinish::{scale};

    #[test]
    fn test_scale() {
        let mut result = scale(FixedTrait::new(MAX_ASTEROID_RADIUS, false));
        assert_relative(result, 4831838208, 'wrong scale max', Option::None(()));

        result = scale(FixedTrait::new(MAX_ASTEROID_RADIUS / 2, false));
        assert_relative(result, 3221225472, 'wrong scale half', Option::None(()));

        result = scale(FixedTrait::new(MAX_ASTEROID_RADIUS / 4, false));
        assert_relative(result, 2415919104, 'wrong scale quarter', Option::None(()));
    }
}
