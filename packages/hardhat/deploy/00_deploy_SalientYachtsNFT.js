/* eslint-disable camelcase */
// deploy/00_deploy_your_contract.js

const { ethers } = require("hardhat");

// const localChainId = "31337";
// const localChainId = "43112";

module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  console.log("chainId: ", chainId);

  await deploy("SalientYachtsReward", {
    from: deployer,
    log: true,
  });
  console.log("After await deploy SalientYachtsReward...");
  const salientYachtsReward = await ethers.getContract(
    "SalientYachtsReward",
    deployer
  );
  console.log("After const salientYachtsReward =...");

  const chainLinkPriceFeedAddr = "0x5498BB86BC934c8D34FDA08E81D444153d0D06aD"; // https://docs.chain.link/docs/avalanche-price-feeds/ (AVAX/USD)
  /*
  await deploy("SalientYachtsNFT", {
    // Learn more about args here: https://www.npmjs.com/package/hardhat-deploy#deploymentsdeploy
    from: deployer,
    args: [salientYachtsReward.address, chainLinkPriceFeedAddr],
    log: true,
  });
  console.log("After await deploy SalientYachtsNFT...");

  // Getting a previously deployed contract
  const salientYachtsNFTContract = await ethers.getContract(
    "SalientYachtsNFT",
    deployer
  );
  console.log("After const salientYachtsNFTContract =...");

  // mint reward tokens for the NFT - 2400 tokens per year -> ten years -> for 6000 NFT's
  await salientYachtsReward.mint(
    salientYachtsNFTContract.address,
    ethers.utils.parseEther(2400 * 10 * 6000 + "")
  );

  await salientYachtsNFTContract.toggleSaleActive();
  console.log("After salientYachtsNFTContract.toggleSaleActive()...");
  */

  await deploy("SalientYachtsSYONE_v01", {
    // Learn more about args here: https://www.npmjs.com/package/hardhat-deploy#deploymentsdeploy
    from: deployer,
    args: [salientYachtsReward.address, chainLinkPriceFeedAddr],
    log: true,
  });
  console.log("After await deploy SalientYachtsSYONE_v01...");

  // Getting a previously deployed contract
  const salientYachtsSYONE_v01 = await ethers.getContract(
    "SalientYachtsSYONE_v01",
    deployer
  );
  console.log("After const salientYachtsSYONE_v01 =...");

  // mint reward tokens for the NFT - 2400 tokens per year -> ten years -> for 6000 NFT's
  await salientYachtsReward.mint(
    salientYachtsSYONE_v01.address,
    ethers.utils.parseEther(2400 * 10 * 6000 + "")
  );

  await salientYachtsSYONE_v01.toggleSaleActive();
  console.log("After salientYachtsSYONE_v01.toggleSaleActive()...");

  /*  await YourContract.setPurpose("Hello");
  
    To take ownership of yourContract using the ownable library uncomment next line and add the 
    address you want to be the owner. 
    // yourContract.transferOwnership(YOUR_ADDRESS_HERE);

    //const yourContract = await ethers.getContractAt('YourContract', "0xaAC799eC2d00C013f1F11c37E654e59B0429DF6A") //<-- if you want to instantiate a version of a contract at a specific address!
  */

  /*
  //If you want to send value to an address from the deployer
  const deployerWallet = ethers.provider.getSigner()
  await deployerWallet.sendTransaction({
    to: "0x34aA3F359A9D614239015126635CE7732c18fDF3",
    value: ethers.utils.parseEther("0.001")
  })
  */

  /*
  //If you want to send some ETH to a contract on deploy (make your constructor payable!)
  const yourContract = await deploy("YourContract", [], {
  value: ethers.utils.parseEther("0.05")
  });
  */

  /*
  //If you want to link a library into your contract:
  // reference: https://github.com/austintgriffith/scaffold-eth/blob/using-libraries-example/packages/hardhat/scripts/deploy.js#L19
  const yourContract = await deploy("YourContract", [], {}, {
   LibraryName: **LibraryAddress**
  });
  */

  // Verify your contracts with Etherscan
  // You don't want to verify on localhost
  /*
  if (chainId !== localChainId) {
    await run("verify:verify", {
      address: salientYachtsNFTContract.address,
      contract: "contracts/SalientYachtsNFT.sol:SalientYachtsNFT",
      contractArguments: [],
    });
  }
  */
};
module.exports.tags = ["salientYachtsSYONE_v01"];
