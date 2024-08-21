import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Libraries } from "hardhat-deploy/types";

/**
 * Get the pool libraries of Lending deployment
 *
 * @param hre - Hardhat Runtime Environment
 * @returns The pool libraries
 */
export async function getPoolLibraries(
  hre: HardhatRuntimeEnvironment,
): Promise<Libraries> {
  const supplyLibraryDeployedResult = await hre.deployments.get("SupplyLogic");
  const borrowLibraryDeployedResult = await hre.deployments.get("BorrowLogic");
  const liquidationLibraryDeployedResult =
    await hre.deployments.get("LiquidationLogic");
  const eModeLibraryDeployedResult = await hre.deployments.get("EModeLogic");
  const bridgeLibraryDeployedResult = await hre.deployments.get("BridgeLogic");
  const flashLoanLogicDeployedResult =
    await hre.deployments.get("FlashLoanLogic");
  const poolLogicDeployedResult = await hre.deployments.get("PoolLogic");

  return {
    LiquidationLogic: liquidationLibraryDeployedResult.address,
    SupplyLogic: supplyLibraryDeployedResult.address,
    EModeLogic: eModeLibraryDeployedResult.address,
    FlashLoanLogic: flashLoanLogicDeployedResult.address,
    BorrowLogic: borrowLibraryDeployedResult.address,
    BridgeLogic: bridgeLibraryDeployedResult.address,
    PoolLogic: poolLogicDeployedResult.address,
  };
}

/**
 * Convert array to chunks
 *
 * @param arr - The array to convert to chunks
 * @param chunkSize - The size of each chunk
 * @returns The array of chunks
 */
export const chunk = <T>(arr: Array<T>, chunkSize: number): Array<Array<T>> => {
  return arr.reduce(
    (prevVal: any, currVal: any, currIndx: number, array: Array<T>) =>
      !(currIndx % chunkSize)
        ? prevVal.concat([array.slice(currIndx, currIndx + chunkSize)])
        : prevVal,
    [],
  );
};

/**
 * Get the timestamp of a block
 *
 * @param hre - Hardhat Runtime Environment
 * @param blockNumber - The block number
 * @returns The timestamp of the block
 */
export const getBlockTimestamp = async (
  hre: HardhatRuntimeEnvironment,
  blockNumber?: number,
): Promise<number> => {
  if (!blockNumber) {
    const block = await hre.ethers.provider.getBlock("latest");

    if (!block) {
      throw `getBlockTimestamp: missing block number ${blockNumber}`;
    }
    return block.timestamp;
  }
  let block = await hre.ethers.provider.getBlock(blockNumber);

  if (!block) {
    throw `getBlockTimestamp: missing block number ${blockNumber}`;
  }
  return block.timestamp;
};