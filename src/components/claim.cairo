use array::SpanTrait;
use starknet::{SyscallResult, SyscallResultTrait};
use starknet::storage_access::{Store, StorageBaseAddress};
use influence::common::{packed, packed::{pack_u128, unpack_u128}};
use influence::components::ComponentTrait;

// Companion metadata: Deposit keeps its identity, balance and sampling fields.
#[derive(Copy, Drop, Serde)]
struct Claim {
    rules_version: u64,
    rate_bps: u64,
    reference_abundance_ppm: u64,
    campaign_id: u64
}

impl ClaimComponent of ComponentTrait<Claim> {
    fn name() -> felt252 {
        'Claim'
    }
    fn is_set(data: Claim) -> bool {
        data.rules_version != 0
    }
    fn version() -> u64 {
        0
    }
}

impl StoreClaim of Store<Claim> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Claim> {
        Self::read_at_offset(address_domain, base, 0)
    }
    fn write(address_domain: u32, base: StorageBaseAddress, value: Claim) -> SyscallResult<()> {
        Self::write_at_offset(address_domain, base, 0, value)
    }
    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> SyscallResult<Claim> {
        let word: u128 = Store::<felt252>::read_at_offset(address_domain, base, offset)?
            .try_into()
            .unwrap();
        Result::Ok(
            Claim {
                rules_version: unpack_u128(word, packed::EXP2_0, packed::EXP2_16)
                    .try_into()
                    .unwrap(),
                rate_bps: unpack_u128(word, packed::EXP2_16, packed::EXP2_16).try_into().unwrap(),
                reference_abundance_ppm: unpack_u128(word, packed::EXP2_32, packed::EXP2_20)
                    .try_into()
                    .unwrap(),
                campaign_id: unpack_u128(word, packed::EXP2_52, packed::EXP2_64).try_into().unwrap()
            }
        )
    }
    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Claim
    ) -> SyscallResult<()> {
        if value.rules_version == 0 {
            assert(
                value.rate_bps == 0 && value.reference_abundance_ppm == 0 && value.campaign_id == 0,
                'nonempty unset claim'
            );
        } else {
            assert(value.rules_version == 1, 'unsupported claim rules');
            assert(value.rate_bps >= 9000 && value.rate_bps <= 20000, 'invalid claim rate');
            assert(
                value.reference_abundance_ppm > 0
                    && value.reference_abundance_ppm <= 1000000
                    && value.campaign_id > 0,
                'invalid claim parameters'
            );
        }
        let mut word: u128 = 0;
        pack_u128(ref word, packed::EXP2_0, packed::EXP2_16, value.rules_version.into());
        pack_u128(ref word, packed::EXP2_16, packed::EXP2_16, value.rate_bps.into());
        pack_u128(ref word, packed::EXP2_32, packed::EXP2_20, value.reference_abundance_ppm.into());
        pack_u128(ref word, packed::EXP2_52, packed::EXP2_64, value.campaign_id.into());
        Store::<felt252>::write_at_offset(address_domain, base, offset, word.into())
    }
    fn size() -> u8 {
        1
    }
}

#[cfg(test)]
mod tests {
    use starknet::{SyscallResultTrait, storage_base_address_from_felt252};
    use starknet::storage_access::Store;
    use influence::components::ComponentTrait;
    use super::{Claim, ClaimComponent};
    #[test]
    #[available_gas(500000)]
    fn claim_storage_preserves_all_fields() {
        let base = storage_base_address_from_felt252(42);
        let claim = Claim {
            rules_version: 1,
            rate_bps: 20000,
            reference_abundance_ppm: 1000000,
            campaign_id: 18446744073709551615
        };
        Store::<Claim>::write(0, base, claim).unwrap_syscall();
        let raw = Store::<felt252>::read(0, base).unwrap_syscall();
        assert(raw == 83076749736557242056279310246871041, 'claim wire layout changed');
        let saved = Store::<Claim>::read(0, base).unwrap_syscall();
        assert(saved.rules_version == 1 && saved.rate_bps == 20000, 'rate/rules changed');
        assert(
            saved.reference_abundance_ppm == 1000000 && saved.campaign_id == claim.campaign_id,
            'claim data changed'
        );
        assert(ClaimComponent::is_set(saved), 'claim unset');
    }
    #[test]
    #[available_gas(500000)]
    fn missing_metadata_is_not_a_new_claim() {
        let base = storage_base_address_from_felt252(43);
        let empty = Store::<Claim>::read(0, base).unwrap_syscall();
        assert(!ClaimComponent::is_set(empty), 'legacy acquired metadata');
    }
    #[test]
    #[should_panic(expected: ('invalid claim rate',))]
    fn claim_rejects_invalid_rate() {
        Store::<
            Claim
        >::write(
            0,
            storage_base_address_from_felt252(44),
            Claim { rules_version: 1, rate_bps: 20001, reference_abundance_ppm: 1, campaign_id: 1 }
        )
            .unwrap_syscall();
    }
}
