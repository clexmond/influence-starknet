use array::ArrayTrait;
use influence::components;
use influence::components::{ExtractorSlots, Extractor, ExtractorTrait, Unique};
use influence::components::extractor::statuses;
use influence::types::{Entity, EntityTrait};

fn count(building: Entity) -> u64 {
    match components::get::<ExtractorSlots>(building.path()) {
        Option::Some(slots) => slots.count.into(),
        // All extractors built before this component have exactly slot 1.
        Option::None(_) => 1
    }
}

fn assert_idle(lot: Entity) {
    if let Option::Some(occupied) = components::get::<Unique>(array!['LotUse', lot.into()].span()) {
        let building: Entity = occupied.unique.try_into().unwrap();
        let mut slot = 1;
        let limit = count(building);
        loop {
            if slot > limit {
                break;
            }
            if let Option::Some(extractor) =
                components::get::<Extractor>(array![building.into(), slot.into()].span()) {
                assert(extractor.status != statuses::RUNNING, 'target lot extracting');
            }
            slot += 1;
        };
    }
}

fn assert_building_ready(building: Entity) {
    let mut slot = 1;
    let limit = count(building);
    loop {
        if slot > limit {
            break;
        }
        components::get::<Extractor>(array![building.into(), slot.into()].span())
            .expect('extractor slot missing')
            .assert_ready();
        slot += 1;
    };
}
