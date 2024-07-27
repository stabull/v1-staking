import * as dotenv from 'dotenv';
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify"; 


dotenv.config();


const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY;
const ETHEREUM_RPC_URL = process.env.ETHEREUM_RPC_URL;

const POLYGON_RPC_URL = process.env.POLYGON_RPC_URL;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.20',
      },
    ],
  },

  networks: {

    /**
     * @description This is the default network for truffle dashboard.
     * There is no need to paste PRIVATE_KEY for deployment. This enables the connection to the
     * MetaMask wallet in the browser from where the contract deployment transcation can be signed.
     * @see {@link https://trufflesuite.com/docs/truffle/getting-started/using-the-truffle-dashboard/}
     */
    truffle: {
      url: 'http://localhost:24012/rpc',
    },
    mainnet: {
      url: `${ETHEREUM_RPC_URL}`,
      chainId: 1,
      // accounts: [`0x${PRIVATE_KEY}`],
    },
    polygon: {
      url: POLYGON_RPC_URL,
      chainId: 137,
      gasPrice: 3500000000,
    },
  },

  paths: {
    artifacts: 'build/artifacts',
    cache: 'build/cache',
    sources: 'src',
  },

  etherscan: {
    apiKey: POLYGONSCAN_API_KEY,
  },

};


export default config;
