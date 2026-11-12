#[starknet::contract]
mod ProspectingFinalize {
    use influence::common::prospecting;
    use influence::components;
    use influence::components::Claim;
    use influence::types::{Context, Entity, EntityTrait};
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[derive(Copy, Drop, starknet::Event)]
    struct ProspectingCampaignFinalized {
        campaign_id: u64,
        deposit: Entity,
        lot: Entity,
        resource: u64,
        initial_yield: u64,
        rate_bps: u64,
        reference_abundance_ppm: u64,
        rules_version: u64,
        sample_count: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }
    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ProspectingCampaignFinalized: ProspectingCampaignFinalized
    }
    #[external(v0)]
    fn run(
        ref self: ContractState,
        campaign_id: u64,
        lot: Entity,
        quantity: u64,
        rate_bps: u64,
        proof: Span<felt252>,
        caller_crew: Entity,
        context: Context
    ) -> Entity {
        let deposit = prospecting::finalize(
            campaign_id, lot, quantity, rate_bps, proof, caller_crew, context
        );
        let claim = components::get::<Claim>(deposit.path()).unwrap();
        let campaign = prospecting::campaign(campaign_id);
        self
            .emit(
                ProspectingCampaignFinalized {
                    campaign_id,
                    deposit,
                    lot,
                    resource: campaign.resource,
                    initial_yield: quantity,
                    rate_bps,
                    reference_abundance_ppm: claim.reference_abundance_ppm,
                    rules_version: claim.rules_version,
                    sample_count: campaign.count,
                    caller_crew,
                    caller: context.caller
                }
            );
        deposit
    }
}
