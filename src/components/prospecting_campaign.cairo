use starknet::ContractAddress;
use influence::components::ComponentTrait;
use influence::types::Entity;

mod statuses {
    const ACTIVE: u64 = 1;
    const CANCELLED: u64 = 2;
    const REPLACED: u64 = 3;
    const FINALIZED: u64 = 4;
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct ProspectingCampaign {
    crew: Entity,
    creator: ContractAddress,
    origin: Entity,
    resource: u64,
    context: u256,
    quality_bps: u64,
    verifier: ContractAddress,
    count: u64,
    pending: bool,
    status: u64,
    replaceable_at: u64,
    claim: Entity
}

impl ProspectingCampaignComponent of ComponentTrait<ProspectingCampaign> {
    fn name() -> felt252 {
        'ProspectingCampaign'
    }
    fn is_set(data: ProspectingCampaign) -> bool {
        data.crew.id != 0
    }
    fn version() -> u64 {
        0
    }
}
