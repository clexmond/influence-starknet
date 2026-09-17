import ibis from '@influenceth/ibis';
import { hash } from 'starknet';
import { declareClass } from './declareClass.js';

// Campaign implementations are library classes, not deployed contracts or run systems.
const updateClass = async (contractName, network, account, options = {}) => {
  const { contracts } = ibis(network);
  const classHash = hash.computeContractClassHash(contracts.sierra(contractName));
  await declareClass({ contracts, contractName, account, options, classHash });
  console.log(`${contractName}: campaign implementation hash: ${classHash}`);
};

export default updateClass;
