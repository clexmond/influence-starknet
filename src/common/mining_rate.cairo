use cubit::f64::{Fixed, FixedTrait, ONE};
use influence::components::{Claim, Celestial};
use influence::components;
use influence::common::{abundance, math::RoundedDivTrait};
use influence::types::{Entity, EntityTrait};

const BASELINE_THRESHOLD_PPM: u64 = 50000;
const BASELINE_RATE_BPS: u64 = 2500;
const LEGACY_RATE_BPS: u64 = 12000;
const RATE_SCALE: u128 = 1000000000;
const MAX_QUANTITY_PER_RUN: u64 = 10000000;

fn enabled() -> bool {
    influence::config::get('PROSPECTING_ENABLED') == 1
}

fn parameters(deposit: Entity, asteroid: u64, lot: u64, resource: u64) -> (u64, u64) {
    if let Option::Some(claim) = components::get::<Claim>(deposit.path()) {
        assert(claim.rules_version == 1, 'unsupported claim rules');
        assert(claim.rate_bps >= 9000 && claim.rate_bps <= 20000, 'invalid claim rate');
        assert(
            claim.reference_abundance_ppm > 0 && claim.reference_abundance_ppm <= 1000000,
            'invalid claim abundance'
        );
        assert(claim.campaign_id != 0, 'missing campaign');
        (claim.reference_abundance_ppm, claim.rate_bps)
    } else {
        (abundance::queried_ppm(asteroid, lot, resource), LEGACY_RATE_BPS)
    }
}

fn baseline_parameters(asteroid: u64, lot: u64, resource: u64, celestial: Celestial) -> (u64, u64) {
    assert(
        abundance::global_ppm(celestial.abundances, resource) >= BASELINE_THRESHOLD_PPM,
        'resource requires claim'
    );
    (abundance::queried_ppm(asteroid, lot, resource), BASELINE_RATE_BPS)
}

fn intrinsic_rate_nano(abundance_ppm: u64, rate_bps: u64) -> u64 {
    assert(
        abundance_ppm <= 1000000 && rate_bps > 0 && rate_bps <= 20000, 'invalid rate parameters'
    );
    if abundance_ppm == 0 {
        return 0;
    }
    let q = FixedTrait::new_unscaled(abundance_ppm, false)
        * FixedTrait::new_unscaled(875, false)
        / FixedTrait::new_unscaled(100, false);
    let fraction = q / FixedTrait::new_unscaled(10000000, false);
    let rate = q / FixedTrait::new_unscaled(31536000, false) / fraction.sqrt();
    let scaled = rate
        * FixedTrait::new_unscaled(rate_bps, false)
        / FixedTrait::new_unscaled(10000, false);
    (scaled * FixedTrait::new_unscaled(1000000000, false)).floor().try_into().unwrap()
}

fn extraction_time(
    quantity: u64, abundance_ppm: u64, rate_bps: u64, bonus: Fixed, acceleration: u64
) -> u64 {
    assert(quantity > 0 && quantity <= MAX_QUANTITY_PER_RUN, 'invalid extraction amount');
    assert(!bonus.sign && bonus.mag > 0 && acceleration > 0, 'invalid extraction bonus');
    let rate: u128 = intrinsic_rate_nano(abundance_ppm, rate_bps).into();
    let effective = rate * bonus.mag.into() / ONE.into();
    assert(effective > 0, 'no mineable output');
    let quantity: u128 = quantity.into();
    let game_seconds = (quantity * RATE_SCALE).div_ceil(effective);
    game_seconds.div_ceil(acceleration.into()).try_into().unwrap()
}
