#[starknet::contract]
mod ProspectingAbandon {
    use influence::common::prospecting;
    use influence::types::{Context, Entity};
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[derive(Copy, Drop, starknet::Event)]
    struct ProspectingCampaignAbandoned {
        campaign_id: u64,
        origin: Entity,
        replaceable_at: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }
    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ProspectingCampaignAbandoned: ProspectingCampaignAbandoned
    }
    #[external(v0)]
    fn run(ref self: ContractState, campaign_id: u64, caller_crew: Entity, context: Context) {
        let campaign = prospecting::abandon(campaign_id, caller_crew, context);
        self
            .emit(
                ProspectingCampaignAbandoned {
                    campaign_id,
                    origin: campaign.origin,
                    replaceable_at: campaign.replaceable_at,
                    caller_crew,
                    caller: context.caller
                }
            );
    }
}
