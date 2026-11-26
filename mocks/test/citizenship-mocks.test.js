// ============================================================
// UNIT & INTEGRATION TEST SUITE — MockERC20 & MockLevelRewardNFT
// ============================================================

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Citizenship Ecosystem Mocks — Security & Integration Suite", function () {
  let admin, levelContract, citizenA, citizenB, attacker;
  let mockToken, rewardNFT;

  const INITIAL_SUPPLY = ethers.parseEther("1000000");
  const BASE_URI = "ipfs://QmCitizenshipMetadata/";

  beforeEach(async function () {
    [admin, levelContract, citizenA, citizenB, attacker] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockToken = await MockERC20.deploy("Paradise Supply Chain", "PSC", INITIAL_SUPPLY, admin.address);
    await mockToken.waitForDeployment();

    const MockLevelRewardNFT = await ethers.getContractFactory("MockLevelRewardNFT");
    rewardNFT = await MockLevelRewardNFT.deploy(
      "Citizenship Level Reward",
      "CLR",
      BASE_URI,
      admin.address,
      true // soulboundEnabled = true
    );
    await rewardNFT.waitForDeployment();

    // Grant MINTER_ROLE to the simulated citizenship level contract
    const MINTER_ROLE = await rewardNFT.MINTER_ROLE();
    await rewardNFT.connect(admin).grantRole(MINTER_ROLE, levelContract.address);
  });

  // ------------------------------------------------------------
  // 1. MockERC20 Tests
  // ------------------------------------------------------------
  describe("MockERC20", function () {
    it("Should initialize with correct metadata, supply, and roles", async function () {
      expect(await mockToken.name()).to.equal("Paradise Supply Chain");
      expect(await mockToken.symbol()).to.equal("PSC");
      expect(await mockToken.balanceOf(admin.address)).to.equal(INITIAL_SUPPLY);
      expect(await mockToken.hasRole(await mockToken.MINTER_ROLE(), admin.address)).to.be.true;
    });

    it("Should allow MINTER_ROLE to mint and holders to burn", async function () {
      const amount = ethers.parseEther("500");
      await mockToken.connect(admin).mint(citizenA.address, amount);
      expect(await mockToken.balanceOf(citizenA.address)).to.equal(amount);

      await mockToken.connect(citizenA).burn(ethers.parseEther("200"));
      expect(await mockToken.balanceOf(citizenA.address)).to.equal(ethers.parseEther("300"));
    });

    it("Should revert minting from unauthorized accounts or with zero values", async function () {
      await expect(
        mockToken.connect(attacker).mint(attacker.address, ethers.parseEther("10"))
      ).to.be.reverted;

      await expect(
        mockToken.connect(admin).mint(ethers.ZeroAddress, ethers.parseEther("10"))
      ).to.be.revertedWithCustomError(mockToken, "ZeroAddress");

      await expect(
        mockToken.connect(admin).mint(citizenA.address, 0)
      ).to.be.revertedWithCustomError(mockToken, "ZeroAmount");
    });
  });

  // ------------------------------------------------------------
  // 2. MockLevelRewardNFT & ILevelRewardNFT Tests
  // ------------------------------------------------------------
  describe("MockLevelRewardNFT", function () {
    it("Should support ERC721, AccessControl, and ILevelRewardNFT interfaces (ERC-165)", async function () {
      // IERC721: 0x80ac58cd, IAccessControl: 0x7965db0b
      expect(await rewardNFT.supportsInterface("0x80ac58cd")).to.be.true;
      expect(await rewardNFT.supportsInterface("0x7965db0b")).to.be.true;

      // Compute ILevelRewardNFT interfaceId dynamically (XOR of its 3 function selectors)
      const iface = new ethers.Interface([
        "function mintReward(address to, uint256 level) external returns (uint256)",
        "function hasClaimedLevel(address user, uint256 level) external view returns (bool)",
        "function tokenLevel(uint256 tokenId) external view returns (uint256)"
      ]);
      const id1 = BigInt(iface.getFunction("mintReward").selector);
      const id2 = BigInt(iface.getFunction("hasClaimedLevel").selector);
      const id3 = BigInt(iface.getFunction("tokenLevel").selector);
      const expectedInterfaceId = "0x" + (id1 ^ id2 ^ id3).toString(16).padStart(8, "0");

      expect(await rewardNFT.supportsInterface(expectedInterfaceId)).to.be.true;
    });

    it("Should allow authorized levelContract to mint level rewards and resolve tokenURI", async function () {
      await expect(rewardNFT.connect(levelContract).mintReward(citizenA.address, 5))
        .to.emit(rewardNFT, "LevelRewardMinted")
        .withArgs(citizenA.address, 5, 1);

      expect(await rewardNFT.ownerOf(1)).to.equal(citizenA.address);
      expect(await rewardNFT.hasClaimedLevel(citizenA.address, 5)).to.be.true;
      expect(await rewardNFT.tokenLevel(1)).to.equal(5);
      expect(await rewardNFT.tokenURI(1)).to.equal(`${BASE_URI}5.json`);
    });

    it("Should reject unauthorized minters, invalid levels, and duplicate claims", async function () {
      await expect(
        rewardNFT.connect(attacker).mintReward(citizenA.address, 1)
      ).to.be.reverted;

      await expect(
        rewardNFT.connect(levelContract).mintReward(citizenA.address, 0)
      ).to.be.revertedWithCustomError(rewardNFT, "InvalidLevel");

      await expect(
        rewardNFT.connect(levelContract).mintReward(citizenA.address, 14)
      ).to.be.revertedWithCustomError(rewardNFT, "InvalidLevel");

      await rewardNFT.connect(levelContract).mintReward(citizenA.address, 3);
      await expect(
        rewardNFT.connect(levelContract).mintReward(citizenA.address, 3)
      ).to.be.revertedWithCustomError(rewardNFT, "AlreadyClaimed");
    });

    it("Should enforce Soulbound restriction when enabled and allow transfers when disabled", async function () {
      await rewardNFT.connect(levelContract).mintReward(citizenA.address, 1);

      // Transfer must revert while soulboundEnabled is true
      await expect(
        rewardNFT.connect(citizenA).transferFrom(citizenA.address, citizenB.address, 1)
      ).to.be.revertedWithCustomError(rewardNFT, "SoulboundTransferProhibited");

      // Disable soulbound by admin
      await expect(rewardNFT.connect(admin).setSoulboundEnabled(false))
        .to.emit(rewardNFT, "SoulboundStatusUpdated")
        .withArgs(false);

      // Transfer succeeds now
      await rewardNFT.connect(citizenA).transferFrom(citizenA.address, citizenB.address, 1);
      expect(await rewardNFT.ownerOf(1)).to.equal(citizenB.address);
    });

    it("Should block minting and transfers while paused and resume after unpause", async function () {
      await rewardNFT.connect(admin).pause();

      await expect(
        rewardNFT.connect(levelContract).mintReward(citizenA.address, 2)
      ).to.be.reverted;

      await rewardNFT.connect(admin).unpause();

      await rewardNFT.connect(levelContract).mintReward(citizenA.address, 2);
      expect(await rewardNFT.ownerOf(1)).to.equal(citizenA.address);
    });

    it("Should support full 13-level citizenship progression end-to-end", async function () {
      for (let level = 1; level <= 13; level++) {
        await rewardNFT.connect(levelContract).mintReward(citizenA.address, level);
        expect(await rewardNFT.hasClaimedLevel(citizenA.address, level)).to.be.true;
        expect(await rewardNFT.tokenLevel(level)).to.equal(level);
      }
      expect(await rewardNFT.balanceOf(citizenA.address)).to.equal(13);
    });
  });
});
