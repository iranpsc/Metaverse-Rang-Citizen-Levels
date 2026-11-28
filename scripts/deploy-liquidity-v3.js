// ============================================================
// UNISWAP V3 ATOMIC LIQUIDITY BOOTSTRAP (PSC / WETH -> Safe 2-of-3 LP NFT)
// Executes createAndInitializePoolIfNecessary + mint + refundETH via multicall
// ============================================================

const { ethers, network } = require("hardhat");

const ERC20_ABI = [
  "function decimals() view returns (uint8)",
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
];

const POSITION_MANAGER_ABI = [
  "function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96) payable returns (address pool)",
  "function mint((address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address recipient, uint256 deadline)) payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)",
  "function refundETH() payable",
  "function multicall(bytes[] calldata data) payable returns (bytes[] memory results)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)",
];

const FULL_RANGE_TICKS = {
  500: { min: -887270, max: 887270 },
  3000: { min: -887220, max: 887220 },
  10000: { min: -887200, max: 887200 },
};

// Exact integer square root for BigInt (Newton's method)
function bigIntSqrt(value) {
  if (value < 0n) throw new Error("Negative sqrt");
  if (value < 2n) return value;
  let x0 = value;
  let x1 = (x0 + 1n) >> 1n;
  while (x1 < x0) {
    x0 = x1;
    x1 = (x1 + value / x1) >> 1n;
  }
  return x0;
}

// Computes exact Uniswap V3 sqrtPriceX96 = floor(sqrt(amount1 / amount0) * 2^96)
function encodeSqrtPriceX96(amount1, amount0) {
  const Q192 = 1n << 192n;
  return bigIntSqrt((amount1 * Q192) / amount0);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`\n[Uniswap V3] Network: ${network.name} | Executor: ${deployer.address}`);

  const safeAddress = process.env.SAFE_MULTISIG_ADDRESS;
  const pscAddress = process.env.PSC_TOKEN_ADDRESS;
  const wethAddress = process.env.WETH_ADDRESS;
  const nfpmAddress = process.env.UNISWAP_V3_POSITION_MANAGER;
  const feeTier = Number(process.env.UNISWAP_V3_FEE_TIER || "3000");

  for (const [name, addr] of [
    ["SAFE_MULTISIG_ADDRESS", safeAddress],
    ["PSC_TOKEN_ADDRESS", pscAddress],
    ["WETH_ADDRESS", wethAddress],
    ["UNISWAP_V3_POSITION_MANAGER", nfpmAddress],
  ]) {
    if (!addr || !ethers.isAddress(addr)) {
      throw new Error(`Missing or invalid ${name} in .env`);
    }
  }

  const ticks = FULL_RANGE_TICKS[feeTier];
  if (!ticks) throw new Error(`Unsupported UNISWAP_V3_FEE_TIER: ${feeTier}`);

  const psc = new ethers.Contract(pscAddress, ERC20_ABI, deployer);
  const nfpm = new ethers.Contract(nfpmAddress, POSITION_MANAGER_ABI, deployer);

  const pscDecimals = await psc.decimals();
  const ethAmount = ethers.parseEther(process.env.INITIAL_ETH_LIQUIDITY || "3.0");
  const pscAmount = ethers.parseUnits(process.env.INITIAL_PSC_LIQUIDITY || "1000000", pscDecimals);

  const pscBalance = await psc.balanceOf(deployer.address);
  if (pscBalance < pscAmount) {
    throw new Error(`Insufficient PSC balance: have ${pscBalance}, need ${pscAmount}`);
  }

  // Sort token0 < token1 as required by Uniswap V3
  const isPscToken0 = pscAddress.toLowerCase() < wethAddress.toLowerCase();
  const token0 = isPscToken0 ? pscAddress : wethAddress;
  const token1 = isPscToken0 ? wethAddress : pscAddress;
  const amount0Desired = isPscToken0 ? pscAmount : ethAmount;
  const amount1Desired = isPscToken0 ? ethAmount : pscAmount;

  const sqrtPriceX96 = encodeSqrtPriceX96(amount1Desired, amount0Desired);
  const deadline = Math.floor(Date.now() / 1000) + 1200; // 20 minutes

  console.log(`[Uniswap V3] token0: ${token0}`);
  console.log(`[Uniswap V3] token1: ${token1}`);
  console.log(`[Uniswap V3] sqrtPriceX96: ${sqrtPriceX96.toString()}`);
  console.log(`[Uniswap V3] LP NFT Recipient (Safe 2-of-3): ${safeAddress}`);

  // Step 1: Approve PSC to NonfungiblePositionManager
  console.log("[Uniswap V3] Approving PSC...");
  const approveTx = await psc.approve(nfpmAddress, pscAmount);
  await approveTx.wait();

  // Step 2: Encode Atomic Multicall (Initialize Pool + Mint LP NFT to Safe + Refund dust ETH)
  const iface = nfpm.interface;
  const callInitialize = iface.encodeFunctionData("createAndInitializePoolIfNecessary", [
    token0,
    token1,
    feeTier,
    sqrtPriceX96,
  ]);

  const callMint = iface.encodeFunctionData("mint", [
    {
      token0,
      token1,
      fee: feeTier,
      tickLower: ticks.min,
      tickUpper: ticks.max,
      amount0Desired,
      amount1Desired,
      amount0Min: 0n, // First liquidity provider in a new pool
      amount1Min: 0n,
      recipient: safeAddress,
      deadline,
    },
  ]);

  const callRefund = iface.encodeFunctionData("refundETH", []);

  console.log("[Uniswap V3] Executing atomic multicall...");
  const tx = await nfpm.multicall([callInitialize, callMint, callRefund], { value: ethAmount });
  const receipt = await tx.wait();
  console.log(`[Uniswap V3] Confirmed in tx: ${receipt.hash}`);

  // Verify minted LP NFT ownership belongs directly to Safe 2-of-3
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog(log);
      if (parsed && parsed.name === "IncreaseLiquidity") {
        const tokenId = parsed.args.tokenId;
        const owner = await nfpm.ownerOf(tokenId);
        console.log(`[OK] LP NFT Token ID: ${tokenId.toString()} | Owner: ${owner}`);
        if (owner.toLowerCase() !== safeAddress.toLowerCase()) {
          throw new Error("LP NFT owner mismatch!");
        }
      }
    } catch (_) {
      // Ignore logs from other contracts
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
