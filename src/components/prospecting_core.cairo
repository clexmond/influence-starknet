use starknet::{SyscallResult, SyscallResultTrait};
use starknet::storage_access::{Store, StorageBaseAddress};
use influence::components::ComponentTrait;

const META_RADIX: u128 = 2417851639229258349412352; // 2^81
const RANDOM_RADIX: u256 = 2475880078570760549798248448; // 2^91
const U64_RADIX: u128 = 18446744073709551616;

#[derive(Copy, Drop, Serde)]
struct ProspectingCore {
    commitment: u256,
    meta: u128,
    blocked_approaches: u16,
    randomness: u64,
    target_block: u64,
    ready_at: u64
}

impl ProspectingCoreComponent of ComponentTrait<ProspectingCore> {
    fn name() -> felt252 {
        'ProspectingCore'
    }
    fn is_set(data: ProspectingCore) -> bool {
        data.meta != 0
    }
    fn version() -> u64 {
        0
    }
}

// Four slots: BN254 commitment, packed public inputs, and packed scheduling.
impl StoreProspectingCore of Store<ProspectingCore> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<ProspectingCore> {
        Self::read_at_offset(address_domain, base, 0)
    }
    fn write(
        address_domain: u32, base: StorageBaseAddress, value: ProspectingCore
    ) -> SyscallResult<()> {
        Self::write_at_offset(address_domain, base, 0, value)
    }
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<ProspectingCore> {
        let commitment = Store::<u256>::read_at_offset(address_domain, base, offset)?;
        let public: u256 = Store::<felt252>::read_at_offset(address_domain, base, offset + 2)?
            .into();
        let schedule = Store::<u128>::read_at_offset(address_domain, base, offset + 3)?;
        let meta_radix: u256 = META_RADIX.into();
        Result::Ok(
            ProspectingCore {
                commitment,
                meta: (public % meta_radix).try_into().unwrap(),
                blocked_approaches: ((public / meta_radix) % 1024).try_into().unwrap(),
                randomness: (public / RANDOM_RADIX).try_into().unwrap(),
                target_block: (schedule % U64_RADIX).try_into().unwrap(),
                ready_at: (schedule / U64_RADIX).try_into().unwrap()
            }
        )
    }
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: ProspectingCore
    ) -> SyscallResult<()> {
        assert(value.meta < META_RADIX && value.blocked_approaches < 1024, 'invalid core encoding');
        let meta: u256 = value.meta.into();
        let mask: u256 = value.blocked_approaches.into();
        let randomness: u256 = value.randomness.into();
        let packed = meta + mask * META_RADIX.into() + randomness * RANDOM_RADIX;
        let ready: u128 = value.ready_at.into();
        let schedule = value.target_block.into() + ready * U64_RADIX;
        Store::<u256>::write_at_offset(address_domain, base, offset, value.commitment)?;
        Store::<
            felt252
        >::write_at_offset(address_domain, base, offset + 2, packed.try_into().unwrap())?;
        Store::<u128>::write_at_offset(address_domain, base, offset + 3, schedule)
    }
    fn size() -> u8 {
        4
    }
}
