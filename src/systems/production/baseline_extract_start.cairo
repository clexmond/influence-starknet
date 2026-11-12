#[starknet::contract]
mod BaselineExtractResourceStart {
    use influence::common::{extraction, extraction::ResourceExtractionStartedV1};
    use influence::types::{Context, Entity, EntityTrait};
    #[storage]
    struct Storage {}
    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ResourceExtractionStartedV1: ResourceExtractionStartedV1
    }
    #[external(v0)]
    fn run(
        ref self: ContractState,
        resource: u64,
        yield: u64,
        extractor: Entity,
        extractor_slot: u64,
        destination: Entity,
        destination_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        let deposit = EntityTrait::new(0, 0);
        let result = extraction::start(
            deposit,
            resource,
            true,
            yield,
            extractor,
            extractor_slot,
            destination,
            destination_slot,
            caller_crew,
            context
        );
        self
            .emit(
                ResourceExtractionStartedV1 {
                    mode: 0,
                    deposit,
                    resource,
                    yield,
                    extractor,
                    extractor_slot,
                    destination,
                    destination_slot,
                    finish_time: result.finish_time,
                    rate_bps: result.rate_bps,
                    reference_abundance_ppm: result.reference_abundance_ppm,
                    caller_crew,
                    caller: context.caller
                }
            );
    }
}
