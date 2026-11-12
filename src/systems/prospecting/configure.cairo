#[starknet::contract]
mod ConfigureProspecting {
    use influence::{config, contracts};
    use influence::common::prospecting::{
        IProspectingVerifierDispatcher, IProspectingVerifierDispatcherTrait, RULES
    };
    use influence::types::{Context, ContextTrait};
    use starknet::ContractAddress;
    use starknet::SyscallResultTrait;
    #[storage]
    struct Storage {}
    #[external(v0)]
    fn run(ref self: ContractState, verifier: ContractAddress, context: Context) {
        assert(context.is_admin(), 'prospecting admin only');
        assert(!influence::common::mining_rate::enabled(), 'prospecting already activated');
        assert(verifier.into() != 0, 'missing prospecting verifier');
        assert(
            IProspectingVerifierDispatcher { contract_address: verifier }.rules() == RULES,
            'wrong prospecting verifier'
        );
        // Activation must not leave an old acquisition path bypassing the new rules.
        for name in array![
            'SampleDepositStart', 'SampleDepositImprove', 'ExtractResourceStart', 'Abundance'
        ]
            .span() {
                let version = starknet::syscalls::library_call_syscall(
                    influence::systems::get(*name),
                    selector!("prospecting_version"),
                    array![].span()
                )
                    .unwrap_syscall();
                assert(version.len() == 1 && *version.at(0) == 1, 'incompatible mining system');
            };
        for name in array![
            'ProspectingStart',
            'ProspectingSample',
            'ProspectingFinalize',
            'ProspectingAbandon',
            'BaselineExtractResourceStart'
        ]
            .span() {
                assert(influence::systems::get(*name).into() != 0, 'prospecting system missing');
            };
        contracts::set_with_event('ProspectingVerifier', verifier);
        config::set_with_event('PROSPECTING_ENABLED', 1);
    }
}
