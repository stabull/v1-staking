import hre, { ethers as he } from 'hardhat';
import {
StakingPool,
StakingPool__factory
} from '../typechain-types';

const main = async () => {
  await hre.run('compile');

  const stakingPoolFactory: StakingPool__factory = await he.getContractFactory('StakingPool');
  // factory address, fee receiver address, token address(curve)
  const StakingPool: StakingPool = await stakingPoolFactory.deploy("0xa86a9A0e0B0A55F7cD030Fda574fDe43174A27ED","0x56Da9bFF1cE1F3a0F0ECeaf82A5fF7965D27D608","0xF80b3a8977d34A443a836a380B2FCe69A1A4e819");
  console.log('pool deployed to:',await StakingPool.getAddress());
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
