// ============================================================
// HARDHAT TEST SUITE — PSDToken (2,000,000,000 Cap, Zero Launch Supply)
// ============================================================

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PSDToken — 2B Hard Cap & Safe Multi-Sig Governance", function () {
  let safeAdmin, treasury, userA, attacker;
  let psd;

  const MAX_SUPPLY = ethers.parseUnits("2000000000", 18); // 2,000,000,000 PSD

  beforeEach(async function () {
    [safeAdmin, treasury, userA, attacker] = await ethers.getSigners();

    const PSDToken = await ethers.getContractFactory("PSDToken");
    // Deploy with 0 initial circulating supply as required before official launch
    psd = await PSDToken.deploy(safeAdmin.address, ethers.ZeroAddress, 0n);
    await psd.waitForDeployment();
  });

  it("Should deploy with zero circulating supply and exact 2,000,000,000 MAX_SUPPLY", async function () {
    expect(await psd.name()).to.equal("MetaRang PSD");
    expect(await psd.symbol()).to.equal("PSD");
    expect(await psd.decimals()).to.equal(18);
    expect(await psd.totalSupply()).to.equal(0n);
    expect(await psd.MAX_SUPPLY()).to.equal(MAX_SUPPLY);
  });

  it("Should restrict minting to MINTER_ROLE and enforce 2B hard cap", async function () {
    await expect(psd.connect(attacker).mint(attacker.address, 1000n))
      .to.be.revertedWithCustomError(psd, "AccessControlUnauthorizedAccount");

    await psd.connect(safeAdmin).mint(treasury.address, MAX_SUPPLY);
    expect(await psd.totalSupply()).to.equal(MAX_SUPPLY);
    expect(await psd.balanceOf(treasury.address)).to.equal(MAX_SUPPLY);

    // Minting even 1 wei over 2B cap must revert
    await expect(psd.connect(safeAdmin).mint(treasury.address, 1n))
      .to.be.revertedWithCustomError(psd, "CapExceeded")
      .withArgs(MAX_SUPPLY + 1n, MAX_SUPPLY);
  });

  it("Should support transfer, burn, and emergency pause by PAUSER_ROLE", async function () {
    const amount = ethers.parseUnits("500000", 18);
    await psd.connect(safeAdmin).mint(treasury.address, amount);

    await psd.connect(treasury).transfer(userA.address, ethers.parseUnits("100000", 18));
    expect(await psd.balanceOf(userA.address)).to.equal(ethers.parseUnits("100000", 18));

    await psd.connect(userA).burn(ethers.parseUnits("25000", 18));
    expect(await psd.totalSupply()).to.equal(ethers.parseUnits("475000", 18));

    // Emergency pause blocks transfers
    await psd.connect(safeAdmin).pause();
    await expect(psd.connect(userA).transfer(treasury.address, 1n))
      .to.be.revertedWithCustomError(psd, "EnforcedPause");

    await psd.connect(safeAdmin).unpause();
    await expect(psd.connect(userA).transfer(treasury.address, 1n))
      .to.emit(psd, "Transfer");
  });
});
