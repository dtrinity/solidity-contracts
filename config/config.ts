import { HardhatRuntimeEnvironment } from "hardhat/types";

import { getConfig as getFraxtalTestNetConfig } from "./networks/fraxtal_testnet";
import { getConfig as getLocalhostConfig } from "./networks/localhost";
import { Config } from "./types";

/**
 * Get the configuration for the network
 *
 * @param hre - Hardhat Runtime Environment
 * @returns The configuration for the network
 */
export async function getConfig(
  hre: HardhatRuntimeEnvironment,
): Promise<Config> {
  switch (hre.network.name) {
    case "fraxtal_testnet":
      return getFraxtalTestNetConfig();
    case "hardhat":
    case "localhost":
      return getLocalhostConfig(hre);
    default:
      throw new Error(`Unknown network: ${hre.network.name}`);
  }
}
