import { TokenInfo } from "../token";

// Define an error
export class NotProfitableLiquidationError extends Error {
  public collateralTokenInfo: TokenInfo;
  public borrowTokenInfo: TokenInfo;

  constructor(
    message: string,
    collateralTokenInfo: TokenInfo,
    borrowTokenInfo: TokenInfo,
  ) {
    super(message);
    this.name = "LiquidationError";
    this.collateralTokenInfo = collateralTokenInfo;
    this.borrowTokenInfo = borrowTokenInfo;
  }
}
