import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

import { deployContract } from "../../../utils/deploy";
import {
  NONFUNGIBLE_POSITION_MANAGER_ID,
  NONFUNGIBLE_TOKEN_POSITION_DESCRIPTOR_ID,
  UNISWAP_V3_FACTORY_ID,
} from "../../../utils/dex/deploy-ids";
import { getWETH9Address } from "../../../utils/weth9";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { dexDeployer } = await hre.getNamedAccounts();

  const weth9Address = await getWETH9Address(hre);

  const { address: factoryAddress } = await hre.deployments.get(
    UNISWAP_V3_FACTORY_ID,
  );

  const { address: positionDescriptorAddress } = await hre.deployments.get(
    NONFUNGIBLE_TOKEN_POSITION_DESCRIPTOR_ID,
  );

  // The NonfungiblePositionManager will be automatically found in contracts/dex/periphery/NonfungiblePositionManager.sol
  await deployContract(
    hre,
    NONFUNGIBLE_POSITION_MANAGER_ID,
    [factoryAddress, weth9Address, positionDescriptorAddress],
    undefined, // auto-filling gas limit
    await hre.ethers.getSigner(dexDeployer),
    undefined, // no libraries
    "NonfungiblePositionManager",
  );

  // Return true to indicate the success of the deployment
  // It is to avoid running this script again (except using --reset flag)
  return true;
};

func.id = NONFUNGIBLE_POSITION_MANAGER_ID;
func.tags = ["dex", "dex-periphery"];
export default func;
