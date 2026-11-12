#[starknet::contract]
mod ExtractResourceStart {
    use influence::common::{extraction, extraction::ResourceExtractionStartedV1};
    use influence::types::{Context, Entity};
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[derive(Copy, Drop, starknet::Event)]
    struct ResourceExtractionStarted {
        deposit: Entity,
        resource: u64,
        yield: u64,
        extractor: Entity,
        extractor_slot: u64,
        destination: Entity,
        destination_slot: u64,
        finish_time: u64,
        caller_crew: Entity,
        caller: ContractAddress
    }


    #[event]
    #[derive(Copy, Drop, starknet::Event)]
    enum Event {
        ResourceExtractionStarted: ResourceExtractionStarted,
        ResourceExtractionStartedV1: ResourceExtractionStartedV1
    }
    #[external(v0)]
    fn prospecting_version(self: @ContractState) -> u64 {
        1
    }
    #[external(v0)]
    fn run(
        ref self: ContractState,
        deposit: Entity,
        yield: u64,
        extractor: Entity,
        extractor_slot: u64,
        destination: Entity,
        destination_slot: u64,
        caller_crew: Entity,
        context: Context
    ) {
        let result = extraction::start(
            deposit,
            0,
            false,
            yield,
            extractor,
            extractor_slot,
            destination,
            destination_slot,
            caller_crew,
            context
        );
        if result.rate_bps == 0 {
            self
                .emit(
                    ResourceExtractionStarted {
                        deposit,
                        resource: result.resource,
                        yield,
                        extractor,
                        extractor_slot,
                        destination,
                        destination_slot,
                        finish_time: result.finish_time,
                        caller_crew,
                        caller: context.caller
                    }
                );
        } else {
            self
                .emit(
                    ResourceExtractionStartedV1 {
                        mode: 1,
                        deposit,
                        resource: result.resource,
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
}
