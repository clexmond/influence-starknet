#[starknet::contract]
mod ReadProspectingCampaign {
    use influence::common::prospecting;
    use influence::components::ProspectingCampaign;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(self: @ContractState, campaign_id: u64, context: Context) -> ProspectingCampaign {
        prospecting::campaign(campaign_id)
    }
}
#[starknet::contract]
mod ReadProspectingSample {
    use influence::common::prospecting;
    use influence::components::ProspectingCore;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(
        self: @ContractState, campaign_id: u64, index: u64, context: Context
    ) -> ProspectingCore {
        prospecting::sample_at(campaign_id, index)
    }
}
#[starknet::contract]
mod ReadProspectingRandomness {
    use influence::common::prospecting;
    use influence::types::Context;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(self: @ContractState, campaign_id: u64, context: Context) -> u64 {
        let campaign = prospecting::campaign(campaign_id);
        prospecting::assert_active(campaign_id, campaign);
        assert(campaign.pending, 'no pending sample');
        prospecting::randomness(campaign_id, campaign.count, context.now)
    }
}
#[starknet::contract]
mod ReadProspectingOrigin {
    use influence::common::prospecting;
    use influence::types::{Context, Entity};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(self: @ContractState, origin: Entity, context: Context) -> u64 {
        prospecting::active_id(origin)
    }
}
#[starknet::contract]
mod PreviewProspectingSample {
    use influence::common::prospecting;
    use influence::types::{Context, Entity};
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(self: @ContractState, campaign_id: u64, lot: Entity, context: Context) -> (u128, u16) {
        let campaign = prospecting::campaign(campaign_id);
        prospecting::assert_active(campaign_id, campaign);
        let (_, _, celestial) = prospecting::celestial(campaign.origin);
        let count = campaign.count + if campaign.pending {
            1
        } else {
            0
        };
        (
            prospecting::metadata(campaign.origin, lot, campaign.resource),
            prospecting::approach_mask(campaign_id, lot, count, celestial.radius)
        )
    }
}
