import { ethers, run } from "hardhat";

async function main() {
  const [signer] = await ethers.getSigners();

  // Data for example, change for yourself
  const minimumQuorum: number = 51;
  const debatingPeriodDuration: number = 259200; // 3 days
  const _minimumVotes: number = 1000;

  const DAO_f = await ethers.getContractFactory("DAO");
  const Token = await ethers.getContractFactory("CryptonToken");

  const token = await Token.deploy();
  await token.deployed();

  const DAO = await DAO_f.deploy(
    token.address,
    minimumQuorum,
    debatingPeriodDuration,
    _minimumVotes
  );
  await DAO.deployed();

  await run(`verify:verify`, {
    address: token.address,
    contract: "contracts/CryptonToken.sol:CryptonToken",
  });

  await run(`verify:verify`, {
    address: DAO.address,
    contract: "contracts/DAO.sol:DAO",
    constructorArguments: [
      token.address,
      minimumQuorum,
      debatingPeriodDuration,
      _minimumVotes,
    ],
  });

  console.log(`
    Deployed in rinkeby
    =================
    "DAO" contract address: ${DAO.address}
    "Token" contract address: ${token.address}
    ${signer.address} - deployed this contracts
  `);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
