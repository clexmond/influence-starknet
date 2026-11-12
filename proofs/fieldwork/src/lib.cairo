mod poseidon2;
use garaga::core::circuit::{into_u256_unchecked, u256_to_u384};
use garaga::definitions::get_GRUMPKIN_modulus;
const FR: u256 = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

fn transcript_hash(values: Span<u256>) -> u256 {
    assert(values.len() > 0 && values.len() <= 48, 'invalid hash length');
    let mut a: u256 = 0;
    let mut b: u256 = 0;
    let mut c: u256 = 0;
    let len: u256 = values.len().into();
    let mut d = len * 18446744073709551616;
    let mut i: usize = 0;
    while i < values.len() {
        assert(*values.at(i) < FR, 'noncanonical hash input');
        a = (a + *values.at(i)) % FR;
        if i + 1 < values.len() {
            assert(*values.at(i + 1) < FR, 'noncanonical hash input');
            b = (b + *values.at(i + 1)) % FR;
        }
        if i + 2 < values.len() {
            assert(*values.at(i + 2) < FR, 'noncanonical hash input');
            c = (c + *values.at(i + 2)) % FR;
        }
        let (oa, ob, oc, od) = poseidon2::run_GRUMPKIN_POSEIDON2_circuit(
            u256_to_u384(a),
            u256_to_u384(b),
            u256_to_u384(c),
            u256_to_u384(d),
            get_GRUMPKIN_modulus(),
        );
        // Circuit outputs are reduced modulo the 254-bit scalar field, so truncation is exact.
        a = into_u256_unchecked(oa);
        b = into_u256_unchecked(ob);
        c = into_u256_unchecked(oc);
        d = into_u256_unchecked(od);
        i += 3;
    }
    a
}

#[starknet::interface]
trait IGroth16Verifier<T> {
    fn verify_groth16_proof_bn254(
        self: @T, full_proof_with_hints: Span<felt252>,
    ) -> Result<Span<u256>, felt252>;
}
#[starknet::interface]
trait IProspectingVerifier<T> {
    fn rules(self: @T) -> felt252;
    fn verify(self: @T, samples: u32, statement: Span<u256>, proof: Span<felt252>) -> bool;
}
#[starknet::contract]
mod ProspectingVerifier {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{IGroth16VerifierDispatcher, IGroth16VerifierDispatcherTrait, transcript_hash};
    #[storage]
    struct Storage {
        verifier: ContractAddress,
    }
    #[constructor]
    fn constructor(ref self: ContractState, verifier: ContractAddress) {
        assert(verifier.into() != 0, 'missing verifier');
        self.verifier.write(verifier);
    }
    #[abi(embed_v0)]
    impl Verifier of super::IProspectingVerifier<ContractState> {
        fn rules(self: @ContractState) -> felt252 {
            'fieldwork-r7-volume150-v1'
        }
        fn verify(
            self: @ContractState, samples: u32, statement: Span<u256>, proof: Span<felt252>,
        ) -> bool {
            assert(
                samples > 0 && samples <= 10 && statement.len() == 2 + samples * 2,
                'invalid campaign statement',
            );
            let expected = transcript_hash(statement);
            let verifier = IGroth16VerifierDispatcher {
                contract_address: self.verifier.read(),
            };
            let result = verifier.verify_groth16_proof_bn254(proof).expect('invalid groth16 proof');
            assert(result.len() == 1 && *result.at(0) == expected, 'campaign statement mismatch');
            true
        }
    }
}
