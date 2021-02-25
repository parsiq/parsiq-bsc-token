/*
 * NB: since truffle-hdwallet-provider 0.0.5 you must wrap HDWallet providers in a 
 * function when declaring them. Failure to do so will cause commands to hang. ex:
 * ```
 * mainnet: {
 *     provider: function() { 
 *       return new HDWalletProvider(mnemonic, 'https://mainnet.infura.io/<infura-key>') 
 *     },
 *     network_id: '1',
 *     gas: 4500000,
 *     gasPrice: 10000000000,
 *   },
 */

const Ganache = require('ganache-core');

const provider = Ganache.provider({
  default_balance_ether: 100000000,
  mnemonic: 'swarm because dignity grid decide rigid once size leisure unhappy powder hazard minimum push river',
  hardfork: 'istanbul',
  total_accounts: 110,
});

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    test: {
      provider,
      network_id: "*", // Match any network id
    },
    development: {
      provider,
      network_id: "*",
    }
  },
  compilers: {
    solc: {
      version: "0.7.6",
      settings: {
        optimizer: {
          enabled: true,
          runs: 1000
        }
      }
    }
  }
};
