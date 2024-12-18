import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

import { getConfig } from "../../../config/config";
import { deployContract } from "../../../utils/deploy";
import { API3_ORACLE_WRAPPER_ID } from "../../../utils/oracle/deploy-ids";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { dusdDeployer } = await hre.getNamedAccounts();
  const deployer = await hre.ethers.getSigner(dusdDeployer);

  const config = await getConfig(hre);
  const baseCurrencyUnit =
    BigInt(10) ** BigInt(config.oracleAggregator.priceDecimals);

  // Deploy API3Wrapper for plain oracle feeds
  const api3WrapperDeployment = await deployContract(
    hre,
    API3_ORACLE_WRAPPER_ID,
    [baseCurrencyUnit],
    undefined,
    deployer,
    undefined,
    "API3Wrapper",
  );

  const api3Wrapper = await hre.ethers.getContractAt(
    API3_ORACLE_WRAPPER_ID,
    api3WrapperDeployment.address,
  );

  // Set proxies for plain oracle feeds
  const plainFeeds =
    config.oracleAggregator.api3OracleAssets.plainApi3OracleWrappers || {};

  for (const [assetAddress, proxyAddress] of Object.entries(plainFeeds)) {
    await api3Wrapper.setProxy(assetAddress, proxyAddress);
    console.log(
      `Set plain API3 proxy for asset ${assetAddress} to ${proxyAddress}`,
    );
  }

  // Deploy API3CompositeWrapperWithThresholding for composite feeds
  const compositeFeeds =
    config.oracleAggregator.api3OracleAssets
      .compositeApi3OracleWrappersWithThresholding || {};

  const api3CompositeWrapperDeployment = await deployContract(
    hre,
    "API3CompositeWrapperWithThresholding",
    [baseCurrencyUnit],
    undefined,
    deployer,
    undefined,
    "API3CompositeWrapperWithThresholding",
  );

  const api3CompositeWrapper = await hre.ethers.getContractAt(
    "API3CompositeWrapperWithThresholding",
    api3CompositeWrapperDeployment.address,
  );

  // Add composite feeds
  for (const [assetAddress, feedConfig] of Object.entries(compositeFeeds)) {
    await api3CompositeWrapper.addCompositeFeed(
      feedConfig.feedAsset,
      feedConfig.proxy1,
      feedConfig.proxy2,
      feedConfig.lowerThresholdInBase1,
      feedConfig.fixedPriceInBase1,
      feedConfig.lowerThresholdInBase2,
      feedConfig.fixedPriceInBase2,
    );
    console.log(
      `Set composite API3 feed for asset ${assetAddress} with:`,
      `\n  - Proxy1: ${feedConfig.proxy1}`,
      `\n  - Proxy2: ${feedConfig.proxy2}`,
      `\n  - Lower threshold in base1: ${feedConfig.lowerThresholdInBase1}`,
      `\n  - Fixed price in base1: ${feedConfig.fixedPriceInBase1}`,
      `\n  - Lower threshold in base2: ${feedConfig.lowerThresholdInBase2}`,
      `\n  - Fixed price in base2: ${feedConfig.fixedPriceInBase2}`,
    );
  }

  // Return true to indicate the success of the script
  return true;
};

func.tags = ["oracle-aggregator", "oracle-wrapper", "api3-oracle-wrapper"];
func.dependencies = [];
func.id = API3_ORACLE_WRAPPER_ID;

export default func;
