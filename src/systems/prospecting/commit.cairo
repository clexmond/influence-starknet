#[starknet::contract]
mod ProspectingSample {
    use influence::common::prospecting;
    use influence::types::{Context, Entity};
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[derive(Copy, Drop, starknet::Event)]
    struct ProspectingSampleCommitted {
        campaign_id: u64,
        index: u64,
        lot: Entity,
        commitment: u256,
        meta: u128,
        blocked_approaches: u16,
        target_block: u64,
        ready_at: u64,
        crew_ready_at: u64,
        origin: Entity,
        origin_slot: u64,
        replaceable_at: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }
    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ProspectingSampleCommitted: ProspectingSampleCommitted
    }
    #[external(v0)]
    fn run(
        ref self: ContractState,
        campaign_id: u64,
        lot: Entity,
        expected_index: u64,
        commitment: u256,
        origin: Entity,
        origin_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        let (campaign, sample, crew_ready_at) = prospecting::commit(
            campaign_id, lot, expected_index, commitment, origin, origin_slot, caller_crew, context
        );
        self
            .emit(
                ProspectingSampleCommitted {
                    campaign_id,
                    index: expected_index,
                    lot,
                    commitment,
                    meta: sample.meta,
                    blocked_approaches: sample.blocked_approaches,
                    target_block: sample.target_block,
                    ready_at: sample.ready_at,
                    crew_ready_at,
                    origin,
                    origin_slot,
                    replaceable_at: campaign.replaceable_at,
                    caller_crew,
                    caller: context.caller
                }
            );
    }
}
