import hre, { ethers as he } from 'hardhat';
import {
STB,
STB__factory
} from '../typechain-types';

const main = async () => {
  await hre.run('compile');

  const stbFactory: STB__factory = await he.getContractFactory('STB');
  const stb: STB = await stbFactory.deploy("Stabull Finance","STABUL",18,10000000);
  console.log('token deployed to:',await  stb.getAddress());
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
