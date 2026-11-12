#[starknet::contract]
mod ProspectingStart {
    use influence::common::prospecting;
    use influence::types::{Context, Entity};
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[derive(Copy, Drop, starknet::Event)]
    struct ProspectingCampaignStarted {
        campaign_id: u64,
        origin: Entity,
        resource: u64,
        context: u256,
        quality_bps: u64,
        verifier: ContractAddress,
        replaceable_at: u64,
        replaced_campaign_id: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }
    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ProspectingCampaignStarted: ProspectingCampaignStarted
    }
    #[external(v0)]
    fn run(
        ref self: ContractState,
        origin: Entity,
        resource: u64,
        caller_crew: Entity,
        context: Context
    ) -> u64 {
        let (id, campaign, previous) = prospecting::create(origin, resource, caller_crew, context);
        self
            .emit(
                ProspectingCampaignStarted {
                    campaign_id: id,
                    origin,
                    resource,
                    context: campaign.context,
                    quality_bps: campaign.quality_bps,
                    verifier: campaign.verifier,
                    replaceable_at: campaign.replaceable_at,
                    replaced_campaign_id: previous,
                    caller_crew,
                    caller: context.caller
                }
            );
        id
    }
}
