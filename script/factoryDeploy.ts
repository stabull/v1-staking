import hre, { ethers as he } from 'hardhat';
import {
StakingFactory,
StakingFactory__factory
} from '../typechain-types';

const main = async () => {
  await hre.run('compile');

  const stakingFactoryFactory: StakingFactory__factory = await he.getContractFactory('StakingFactory');
  const stakingFactory: StakingFactory = await stakingFactoryFactory.deploy("0x0000000000000000000000000000000000000000","0x56Da9bFF1cE1F3a0F0ECeaf82A5fF7965D27D608");
  console.log('factory deployed to:',await  stakingFactory.getAddress());
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
