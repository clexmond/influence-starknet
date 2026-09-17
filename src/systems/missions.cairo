mod starter;

#[starknet::contract]
mod RegisterMissionCampaign {
    use array::ArrayTrait;
    use traits::Into;
    use starknet::ClassHash;
    use influence::common::missions;
    use influence::types::{Context, ContextTrait};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(
        ref self: ContractState,
        campaign: felt252,
        implementation: ClassHash,
        mission_count: u32,
        context: Context
    ) {
        assert(context.is_admin(), 'only admin');
        assert(
            campaign != 0 && implementation.into() != 0 && mission_count > 0, 'invalid definition'
        );
        let path = array!['Definition', campaign].span();
        assert(missions::read(path) == 0, 'definition immutable');
        missions::write(path, implementation.into());
        missions::write(array!['DefinitionCount', campaign].span(), mission_count.into());
    }
}

#[starknet::contract]
mod AcceptMission {
    use influence::common::missions;
    use influence::common::missions::Assignment;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, assignment: Assignment, context: Context) {
        missions::accept(assignment, context);
    }
}

#[starknet::contract]
mod MissionAction {
    use starknet::ContractAddress;
    use influence::types::Entity;

    #[derive(Copy, Drop, starknet::Event)]
    struct MissionAccepted {
        campaign: felt252,
        subject: Entity,
        mission: u32
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct MissionCompleted {
        campaign: felt252,
        subject: Entity,
        mission: u32
    }

    #[derive(Copy, Drop, starknet::Event)]
    struct MissionRewardClaimed {
        campaign: felt252,
        subject: Entity,
        mission: u32,
        recipient: ContractAddress,
        amount: u128
    }

    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        MissionAccepted: MissionAccepted,
        MissionCompleted: MissionCompleted,
        MissionRewardClaimed: MissionRewardClaimed
    }

    use influence::common::missions;
    use influence::common::missions::Assignment;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(
        ref self: ContractState,
        assignment: Assignment,
        action: felt252,
        arguments: Span<felt252>,
        context: Context
    ) {
        missions::act(assignment, action, arguments, context);
    }
}

#[starknet::contract]
mod MissionValidate {
    use influence::common::missions;
    use influence::common::missions::Assignment;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(
        ref self: ContractState, assignment: Assignment, arguments: Span<felt252>, context: Context
    ) {
        missions::validate(assignment, arguments, context);
    }
}

#[starknet::contract]
mod ClaimMissionReward {
    use influence::common::missions;
    use influence::common::missions::Assignment;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, assignment: Assignment, context: Context) {
        missions::claim(assignment, context);
    }
}

#[starknet::contract]
mod ReadMissionState {
    use array::ArrayTrait;
    use influence::common::missions;
    use influence::common::missions::Assignment;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(
        ref self: ContractState, assignment: Assignment, slot: felt252, context: Context
    ) -> (bool, bool, bool, felt252) {
        (
            missions::flag(assignment, 0),
            missions::flag(assignment, 1),
            missions::flag(assignment, 2),
            missions::state(assignment, slot)
        )
    }
}
