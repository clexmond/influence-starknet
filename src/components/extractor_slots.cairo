use influence::components::ComponentTrait;

#[derive(Copy, Drop, Serde, starknet::Store)]
struct ExtractorSlots {
    count: u8
}

impl ExtractorSlotsComponent of ComponentTrait<ExtractorSlots> {
    fn name() -> felt252 {
        'ExtractorSlots'
    }
    fn is_set(data: ExtractorSlots) -> bool {
        data.count != 0
    }
    fn version() -> u64 {
        0
    }
}
