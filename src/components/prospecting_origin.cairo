use influence::components::ComponentTrait;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct ProspectingOrigin {
    campaign_id: u64
}

impl ProspectingOriginComponent of ComponentTrait<ProspectingOrigin> {
    fn name() -> felt252 {
        'ProspectingOrigin'
    }
    fn is_set(data: ProspectingOrigin) -> bool {
        data.campaign_id != 0
    }
    fn version() -> u64 {
        0
    }
}
