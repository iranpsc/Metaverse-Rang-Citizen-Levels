// ============================================================
// DEPLOY CORE KERNEL (HadETasarEngine) + PSDToken (2B Cap, 0 Initial Supply)
// Networks: hardhat | arbitrumSepolia | arbitrumOne
// ============================================================

const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const isMainnet = network.name === "arbitrumOne";

  console.log(`\n[Deploy] Network: ${network.name} (Chain ID: ${network.config.chainId})`);
  console.log(`[Deploy] Deployer (gas only): ${deployer.address}`);

  const safeAddress = process.env.SAFE_MULTISIG_ADDRESS;
  if (!safeAddress || !ethers.isAddress(safeAddress)) {
    throw new Error("SAFE_MULTISIG_ADDRESS is missing or invalid in .env");
  }
  if (isMainnet && safeAddress.toLowerCase() === deployer.address.toLowerCase()) {
    throw new Error("Mainnet guard: SAFE_MULTISIG_ADDRESS must not be the EOA deployer");
  }

  // 1. Resolve Layer-1 Citizenship Level Provider
  let levelProviderAddress = process.env.LEVEL_PROVIDER_ADDRESS;
  if (!levelProviderAddress || !ethers.isAddress(levelProviderAddress)) {
    if (isMainnet) {
      throw new Error("Mainnet guard: LEVEL_PROVIDER_ADDRESS is mandatory on Arbitrum One");
    }
    console.log("[Deploy] No LEVEL_PROVIDER_ADDRESS set on testnet -> deploying MockCitizenshipLevelProvider...");
    const MockProvider = await ethers.getContractFactory("MockCitizenshipLevelProvider");
    const mockProvider = await MockProvider.deploy();
    await mockProvider.waitForDeployment();
    levelProviderAddress = await mockProvider.getAddress();
    console.log(`[Deploy] MockCitizenshipLevelProvider: ${levelProviderAddress}`);
  } else {
    console.log(`[Deploy] Using existing Layer-1 LevelProvider: ${levelProviderAddress}`);
  }

  // 2. Deploy PSDToken (2,000,000,000 Hard Cap, Zero Initial Circulating Supply)
  const PSDToken = await ethers.getContractFactory("PSDToken");
  const psd = await PSDToken.deploy(safeAddress, ethers.ZeroAddress, 0n);
  await psd.waitForDeployment();
  const psdAddress = await psd.getAddress();
  console.log(`[Deploy] PSDToken (2B Cap, 0 Supply): ${psdAddress}`);

  // 3. Deploy HadETasarEngine Core Kernel (Roles assigned directly to Safe 2-of-3)
  const HadETasarEngine = await ethers.getContractFactory("HadETasarEngine");
  const engine = await HadETasarEngine.deploy(safeAddress, levelProviderAddress);
  await engine.waitForDeployment();
  const engineAddress = await engine.getAddress();
  console.log(`[Deploy] HadETasarEngine Core Kernel: ${engineAddress}`);

  // 4. On-Chain Role Verification (Ensure Safe 2-of-3 owns all roles and Deployer owns none)
  const DEFAULT_ADMIN = await engine.DEFAULT_ADMIN_ROLE();
  const EXECUTOR_ROLE = await engine.EXECUTOR_ROLE();
  const GUARDIAN_ROLE = await engine.GUARDIAN_ROLE();
  const PAUSER_ROLE = await engine.PAUSER_ROLE();
  const MINTER_ROLE = await psd.MINTER_ROLE();

  const checks = [
    ["Engine DEFAULT_ADMIN -> Safe", await engine.hasRole(DEFAULT_ADMIN, safeAddress), true],
    ["Engine EXECUTOR_ROLE -> Safe", await engine.hasRole(EXECUTOR_ROLE, safeAddress), true],
    ["Engine GUARDIAN_ROLE -> Safe", await engine.hasRole(GUARDIAN_ROLE, safeAddress), true],
    ["Engine PAUSER_ROLE   -> Safe", await engine.hasRole(PAUSER_ROLE, safeAddress), true],
    ["PSD DEFAULT_ADMIN    -> Safe", await psd.hasRole(DEFAULT_ADMIN, safeAddress), true],
    ["PSD MINTER_ROLE      -> Safe", await psd.hasRole(MINTER_ROLE, safeAddress), true],
    ["PSD Initial Supply   == 0", (await psd.totalSupply()) === 0n, true],
  ];

  if (safeAddress.toLowerCase() !== deployer.address.toLowerCase()) {
    checks.push(["Engine Admin != Deployer", await engine.hasRole(DEFAULT_ADMIN, deployer.address), false]);
    checks.push(["PSD Admin != Deployer", await psd.hasRole(DEFAULT_ADMIN, deployer.address), false]);
  }

  for (const [label, actual, expected] of checks) {
    if (actual !== expected) {
      throw new Error(`Role verification failed for: ${label}`);
    }
    console.log(`  [OK] ${label}`);
  }

  // 5. Export deployment manifest JSON
  const outDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

  const manifest = {
    network: network.name,
    chainId: network.config.chainId,
    timestamp: new Date().toISOString(),
    safeMultiSig: safeAddress,
    contracts: {
      levelProvider: levelProviderAddress,
      psdToken: psdAddress,
      hadETasarEngine: engineAddress,
    },
  };

  const outFile = path.join(outDir, `${network.name}.core.json`);
  fs.writeFileSync(outFile, JSON.stringify(manifest, null, 2));
  console.log(`\n[Done] Deployment manifest saved to: ${outFile}\n`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
