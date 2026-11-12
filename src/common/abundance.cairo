use array::ArrayTrait;
use cubit::f64::{Fixed, FixedTrait, Vec3, Vec3Trait, comp, ONE, TWO};
use cubit::f64::procgen::{rand, simplex3};
use influence::common::position;
use influence::components::{Celestial, CelestialTrait};
use influence::config::{MAX_ASTEROID_RADIUS, noise::percentile};
use influence::types::ArrayHashTrait;

const RESOURCE_SIZE_VARYING: u64 = 3221225472;
const RESOURCE_SIZE_BASE: u64 = 1610612736;
const RESOURCE_PERSISTENCE: u64 = 2147483648;

fn at_lot(ast: u64, lot: u64, resource: u64, celestial: Celestial) -> (Fixed, Fixed, Fixed) {
    assert(resource >= 1 && resource <= 22, 'invalid raw resource');
    // Get the position of the lot and scale it
    let area = position::surface_area(celestial.radius);
    let pos = position::surface_position_norm(lot, area.floor()).mul(scale(celestial.radius));

    // Use asteroid, resource and packed abundances as seed
    let mut seed_path: Array<felt252> = Default::default();
    seed_path.append(ast.into());
    seed_path.append(resource.into());
    seed_path.append(celestial.abundances);
    let shifted_pos = shifted_point(pos, seed_path.hash());

    // Get simplex noise using shifted point and normalize
    let octaves = octaves(ast);
    let mut noise = simplex3::noise_octaves(
        shifted_pos, octaves, FixedTrait::new(RESOURCE_PERSISTENCE, false)
    );

    noise = (noise + FixedTrait::ONE()) / FixedTrait::new(TWO, false); // normalize to [0, 1]
    let percentile = percentile(noise, octaves);

    // Scale to [0,1] and clamp to ensure no overflows
    let abundance = celestial.abundance(resource); // Fixed
    let abundance_floor = FixedTrait::new(abundance.mag / 2, false);
    let mut lot_abundance = abundance_floor;

    if percentile.mag + abundance.mag >= ONE {
        let mut varying = FixedTrait::new((percentile.mag + abundance.mag) - ONE, false)
            / abundance;
        varying = comp::min(varying, FixedTrait::ONE()) * (FixedTrait::ONE() - abundance_floor);
        lot_abundance += varying;
    }

    (lot_abundance, noise, percentile)
}

// LUT based on: 2 + 4 * (radius / MAX_RADIUS ^ 1/3)
fn octaves(id: u64) -> u64 {
    if id == 1 {
        return 6;
    }
    if id <= 6 {
        return 5;
    }
    if id <= 74 {
        return 4;
    }
    if id <= 6345 {
        return 3;
    }
    return 2;
}

// Simplex scale based on: base + varying * (radius / MAX_RADIUS)
fn scale(radius: Fixed) -> Fixed {
    return FixedTrait::new(RESOURCE_SIZE_BASE, false)
        + FixedTrait::new(RESOURCE_SIZE_VARYING, false)
            * (radius / FixedTrait::new(MAX_ASTEROID_RADIUS, false));
}

// Shifts a point by between
fn shifted_point(pos: Vec3, seed: felt252) -> Vec3 {
    let lowShift = FixedTrait::new(21474836480, true); // -5 (f64)
    let highShift = FixedTrait::new(21474836480, false); // 5 (f64)

    return Vec3 {
        x: pos.x + rand::fixed_between(rand::derive(seed, 1), lowShift, highShift),
        y: pos.y + rand::fixed_between(rand::derive(seed, 2), lowShift, highShift),
        z: pos.z + rand::fixed_between(rand::derive(seed, 3), lowShift, highShift)
    };
}

fn global_ppm(packed: felt252, resource: u64) -> u64 {
    assert(resource >= 1 && resource <= 22, 'invalid raw resource');
    let word: u256 = packed.into();
    let mut part = if resource <= 11 {
        word.low
    } else {
        word.high
    };
    let mut index = if resource <= 11 {
        resource - 1
    } else {
        resource - 12
    };
    loop {
        if index == 0 {
            break;
        }
        part /= 1024;
        index -= 1;
    };
    let milli: u64 = (part % 1024).try_into().unwrap();
    assert(milli <= 1000, 'invalid global abundance');
    milli * 1000
}

fn lot_ppm(ast: u64, lot: u64, resource: u64, celestial: Celestial) -> u64 {
    let (abundance, _, _) = at_lot(ast, lot, resource, celestial);
    let amount: u128 = abundance.mag.into();
    (amount * 1000000 / ONE.into()).try_into().unwrap()
}

#[starknet::interface]
trait IAbundanceLookup<T> {
    fn ppm(self: @T, asteroid: u64, lot: u64, resource: u64) -> u64;
}

// Keep the noise implementation in its own registered class. Linking it into
// sampling plus inventory/crew code exceeds the contract bytecode size limit.
fn queried_ppm(asteroid: u64, lot: u64, resource: u64) -> u64 {
    IAbundanceLookupLibraryDispatcher { class_hash: influence::systems::get('Abundance') }
        .ppm(asteroid, lot, resource)
}
