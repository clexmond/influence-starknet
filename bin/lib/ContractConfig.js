import contractConfig from '../../influence.config.js';

class ContractConfig {
  constructor(network) {
    this.network = network;
    this.config = contractConfig[network];
  }

  getDispatcher() {
    return this.config.Dispatcher;
  }

  getSystems() {
    const systems = [];

    for (const [key, value] of Object.entries(this.config)) {
      if (value.isSystem) systems.push(key);
    }

    return systems;
  }

  getContracts() {
    const contracts = [];

    for (const [key, value] of Object.entries(this.config)) {
      if (value.isContract) contracts.push(key);
    }

    return contracts;
  }

  getClasses() {
    return Object.entries(this.config).filter(([, value]) => value.isClass).map(([name]) => name);
  }

  isClass(name) {
    return this.config[name].isClass;
  }

  isDispatcher(name) {
    return this.config[name].isDispatcher;
  }

  isSystem(name) {
    return this.config[name].isSystem;
  }

  isContract(name) {
    return this.config[name].isContract;
  }
}

export default ContractConfig;