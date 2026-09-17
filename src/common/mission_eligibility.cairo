use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};
use influence::{config, components};
use influence::common::missions::{read, write};
use influence::components::{Crew, CrewTrait};
use influence::types::{Entity, EntityTrait};

fn enabled() -> bool {
    config::get('STARTER_MISSION_CAMPAIGN') != 0
}

fn invalid(crew: Entity) -> bool {
    enabled()
        && (crew.id <= config::get('STARTER_MISSION_CUTOFF').try_into().unwrap()
            || read(array!['StarterInvalid', crew.into()].span()) != 0)
}

fn participated(crew: Entity) -> bool {
    read(array!['StarterParticipated', crew.into()].span()) != 0
}

fn participate(crew: Entity) {
    write(array!['StarterParticipated', crew.into()].span(), 1);
}

fn invalidate(crew: Entity) {
    if enabled() {
        write(array!['StarterInvalid', crew.into()].span(), 1);
    }
}

fn assert_valid(crew: Entity) {
    assert(enabled(), 'starter missions inactive');
    assert(!invalid(crew), 'crew mission invalid');
    components::get::<Crew>(crew.path()).expect('crew missing').assert_manned();
}

fn changed(old: Span<u64>, new: Span<u64>) -> bool {
    if old.len() != new.len() {
        return true;
    }
    let mut found = false;
    let mut i = 0;
    loop {
        if i == old.len() {
            break;
        }
        if !contains(new, *old.at(i)) {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

fn contains(ids: Span<u64>, id: u64) -> bool {
    let mut found = false;
    let mut i = 0;
    loop {
        if i == ids.len() {
            break;
        }
        if *ids.at(i) == id {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

fn moved(old: Span<u64>, destination: Span<u64>) -> bool {
    let mut found = false;
    let mut i = 0;
    loop {
        if i == old.len() {
            break;
        }
        if contains(destination, *old.at(i)) {
            found = true;
            break;
        }
        i += 1;
    };
    found
}

fn exchange(
    a: Entity, old_a: Span<u64>, new_a: Span<u64>, b: Entity, old_b: Span<u64>, new_b: Span<u64>
) {
    if !enabled() {
        return;
    }
    let ab = moved(old_a, new_b);
    let ba = moved(old_b, new_a);
    let mut bad_a = invalid(a) || (participated(a) && changed(old_a, new_a));
    let mut bad_b = invalid(b) || (participated(b) && changed(old_b, new_b));
    if bad_a && ab {
        bad_b = true;
    }
    if bad_b && ba {
        bad_a = true;
    }
    if bad_a && ab {
        bad_b = true;
    }
    if bad_a {
        invalidate(a);
    }
    if bad_b {
        invalidate(b);
    }
}
