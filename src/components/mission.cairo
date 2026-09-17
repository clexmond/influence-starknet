use array::{ArrayTrait, Span, SpanTrait};
use core::starknet::SyscallResultTrait;
use option::OptionTrait;
use result::ResultTrait;
use starknet::{ContractAddress, Felt252TryIntoContractAddress, SyscallResult};
use starknet::storage_access::{Store, StorageBaseAddress, storage_base_address_const};
use traits::{Into, TryInto};

use influence::components::{ComponentTrait, resolve};

#[derive(Copy, Drop, Serde)]
struct Mission {
    value: felt252
}

impl MissionComponent of ComponentTrait<Mission> {
    fn name() -> felt252 {
        return 'Mission';
    }

    fn is_set(data: Mission) -> bool {
        return data.value != 0;
    }

    fn version() -> u64 {
        return 0;
    }
}

// Storage Access
// -----------------------------------------------------------------------------------------------------

impl StoreMission of Store<Mission> {
    #[inline(always)]
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Mission> {
        return Self::read_at_offset(address_domain, base, 0);
    }

    #[inline(always)]
    fn write(address_domain: u32, base: StorageBaseAddress, value: Mission) -> SyscallResult<()> {
        return Self::write_at_offset(address_domain, base, 0, value);
    }

    #[inline(always)]
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Mission> {
        let res = Store::<felt252>::read_at_offset(address_domain, base, offset)?;
        return Result::Ok(Mission { value: res });
    }

    #[inline(always)]
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Mission
    ) -> SyscallResult<()> {
        return Store::<felt252>::write_at_offset(address_domain, base, offset, value.value);
    }

    #[inline(always)]
    fn size() -> u8 {
        return 1;
    }
}
