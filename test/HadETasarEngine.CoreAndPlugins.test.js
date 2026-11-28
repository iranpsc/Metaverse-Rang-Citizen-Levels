// ============================================================
// HARDHAT TEST SUITE — HadETasarEngine Core Kernel + 4 Plugins
// Spec: MR-GOV-SPEC-001 (Arbitrum One / Safe 2-of-3 Ready)
// ============================================================

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("HadETasarEngine — Core Kernel & Modular Plugins Suite", function () {
  let safeAdmin, guest, developer, mayor, dadgozar, voterB, attacker;
  let levelProvider, engine, ruleHook, quorumCalc, marketMod, judicialMod;

  const SCALE = 1_000_000n;
  const BPS_1X = 10_000n;
  const METADATA_HASH = ethers.keccak256(ethers.toUtf8Bytes("MR-GOV-SPEC-001-CORE-V2"));

  const EXPECTED_TIERS = [
    1n, 1n, 3n, 8n, 18n, 36n, 76n, 166n, 366n, 796n, 1696n, 3696n, 7896n, 16896n
  ];

  beforeEach(async function () {
    [safeAdmin, guest, developer, mayor, dadgozar, voterB, attacker] = await ethers.getSigners();

    const MockProvider = await ethers.getContractFactory("MockCitizenshipLevelProvider");
    levelProvider = await MockProvider.deploy();
    await levelProvider.waitForDeployment();

    await levelProvider.setLevel(guest.address, 0);      // Level 0: Non-Citizen (H_max = 1)
    await levelProvider.setLevel(developer.address, 4);  // Level 4: Developer (H_max = 18)
    await levelProvider.setLevel(mayor.address, 9);      // Level 9: Mayor (H_max = 796)
    await levelProvider.setLevel(voterB.address, 10);    // Level 10: Governor (H_max = 1696)
    await levelProvider.setLevel(dadgozar.address, 13);  // Level 13: Dadgozar (H_max = 16896)

    const Engine = await ethers.getContractFactory("HadETasarEngine");
    engine = await Engine.deploy(safeAdmin.address, await levelProvider.getAddress());
    await engine.waitForDeployment();

    const RuleHook = await ethers.getContractFactory("MockProposalRuleHook");
    ruleHook = await RuleHook.deploy();
    await ruleHook.waitForDeployment();

    const QuorumCalc = await ethers.getContractFactory("MockQuorumCalculator");
    quorumCalc = await QuorumCalc.deploy();
    await quorumCalc.waitForDeployment();

    const MarketMod = await ethers.getContractFactory("MockHadETasarMarket");
    marketMod = await MarketMod.connect(safeAdmin).deploy();
    await marketMod.waitForDeployment();

    const JudicialMod = await ethers.getContractFactory("MockJudicialModule");
    judicialMod = await JudicialMod.connect(safeAdmin).deploy();
    await judicialMod.waitForDeployment();
  });

  // ------------------------------------------------------------
  // 1. Core Kernel: 14-Tier Matrix, Cooldowns & Dual Recharge
  // ------------------------------------------------------------
  describe("1. Core Kernel (No Plugins Attached)", function () {
    it("Should assign all governance roles directly to Safe 2-of-3 admin", async function () {
      expect(await engine.hasRole(await engine.DEFAULT_ADMIN_ROLE(), safeAdmin.address)).to.equal(true);
      expect(await engine.hasRole(await engine.PAUSER_ROLE(), safeAdmin.address)).to.equal(true);
      expect(await engine.hasRole(await engine.GUARDIAN_ROLE(), safeAdmin.address)).to.equal(true);
      expect(await engine.hasRole(await engine.EXECUTOR_ROLE(), safeAdmin.address)).to.equal(true);
      expect(await engine.hasRole(await engine.DEFAULT_ADMIN_ROLE(), attacker.address)).to.equal(false);
    });

    it("Should return exact H_max for all 14 tiers and reject tier > 13", async function () {
      for (let t = 0; t <= 13; t++) {
        expect(await engine.getTierMaxCapacity(t)).to.equal(EXPECTED_TIERS[t]);
      }
      await expect(engine.getTierMaxCapacity(14))
        .to.be.revertedWithCustomError(engine, "InvalidTier")
        .withArgs(14);
    });

    it("Should enforce 60s cooldown for citizens and 24h cooldown for Level-0 guests", async function () {
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 1
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 2

      // Citizen (Level 4) 60s cooldown
      await engine.connect(developer).castVote(1, 5n * SCALE, true);
      await time.increase(30);
      await expect(engine.connect(developer).castVote(2, 5n * SCALE, true))
        .to.be.revertedWithCustomError(engine, "CooldownActive");
      await time.increase(31);
      await expect(engine.connect(developer).castVote(2, 5n * SCALE, true))
        .to.emit(engine, "HadETasarConsumed");

      // Guest (Level 0) 24h cooldown even on fractional spend
      await engine.connect(guest).castVote(1, 500_000n, true);
      await time.increase(12 * 3600);
      await expect(engine.connect(guest).castVote(2, 500_000n, true))
        .to.be.revertedWithCustomError(engine, "CooldownActive");
      await time.increase(12 * 3600 + 1);
      await expect(engine.connect(guest).castVote(2, 500_000n, true))
        .to.emit(engine, "HadETasarConsumed");
    });

    it("Should support proportional 24h recharge (gradual) and linear minute recharge (full depletion)", async function () {
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 1
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 2

      // Gradual depletion: spend 9 of 18 -> 9 left
      await engine.connect(developer).castVote(1, 9n * SCALE, true);
      await time.increase(6 * 3600); // +25% of 18 = +4.5 -> 13.5
      expect(await engine.getNativeHadETasar(developer.address)).to.equal(13_500_000n);

      // Full depletion: spend remaining 13.5 -> balance = 0, depletedAt set
      await engine.connect(developer).castVote(2, 13_500_000n, true);
      expect(await engine.getNativeHadETasar(developer.address)).to.equal(0n);

      // 45 seconds (< 1 full minute) -> still 0
      await time.increase(45);
      expect(await engine.getNativeHadETasar(developer.address)).to.equal(0n);

      // 120 full minutes (2h) -> 120/1440 * 18 = 1.5
      await time.increase(120 * 60 - 45);
      expect(await engine.getNativeHadETasar(developer.address)).to.equal(1_500_000n);
    });

    it("Should enforce RBAC target levels, Level-13 settlement bounds, Quorum, Majority, and Timelock", async function () {
      await expect(engine.connect(developer).createProposal(3, BPS_1X, 5n * SCALE, METADATA_HASH))
        .to.be.revertedWithCustomError(engine, "UnauthorizedTargetLevel")
        .withArgs(4, 3);

      await expect(engine.connect(mayor).createSettlementLiberationProposal(200, BPS_1X, 100n * SCALE, METADATA_HASH))
        .to.be.revertedWithCustomError(engine, "DadgozarOnly")
        .withArgs(9);

      await expect(engine.connect(dadgozar).createSettlementLiberationProposal(65, BPS_1X, 100n * SCALE, METADATA_HASH))
        .to.be.revertedWithCustomError(engine, "InvalidSettlementRadius")
        .withArgs(65);

      await expect(engine.connect(dadgozar).createSettlementLiberationProposal(697, BPS_1X, 100n * SCALE, METADATA_HASH))
        .to.be.revertedWithCustomError(engine, "InvalidSettlementRadius")
        .withArgs(697);

      // Valid proposal: Quorum = 500
      await engine.connect(mayor).createProposal(9, BPS_1X, 500n * SCALE, METADATA_HASH); // ID 1
      await engine.connect(mayor).castVote(1, 400n * SCALE, true);
      await engine.connect(voterB).castVote(1, 200n * SCALE, false);

      // End of voting period (3 days) -> still in timelock
      await time.increase(3 * 86_400 + 1);
      await expect(engine.connect(safeAdmin).executeProposal(1))
        .to.be.revertedWithCustomError(engine, "TimelockNotExpired");

      // After timelock (1 day) -> executes
      await time.increase(86_400 + 1);
      await expect(engine.connect(safeAdmin).executeProposal(1))
        .to.emit(engine, "ProposalExecuted")
        .withArgs(1, safeAdmin.address);
    });

    it("Should preserve calculateQuadraticWeight helper", async function () {
      expect(await engine.calculateQuadraticWeight(10_000n)).to.equal(100n);
      expect(await engine.calculateQuadraticWeight(2_500_000_000n)).to.equal(50_000n);
    });
  });

  // ------------------------------------------------------------
  // 2. Plugin 1: IProposalRuleHook (1x Lock & 13-Day Wait)
  // ------------------------------------------------------------
  describe("2. Plugin: IProposalRuleHook", function () {
    beforeEach(async function () {
      await engine.connect(safeAdmin).setProposalRuleHook(await ruleHook.getAddress());
      await ruleHook.setRules(true, true);
    });

    it("Should enforce 1x multiplier lock and 13-day waiting period after Settlement Liberation execution", async function () {
      // Non-1x multiplier rejected by hook
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(300, 15_000n, 100n * SCALE, METADATA_HASH)
      ).to.be.revertedWithCustomError(ruleHook, "MultiplierLockedTo1x").withArgs(15_000n);

      // Valid 1x settlement liberation proposal
      await engine.connect(dadgozar).createSettlementLiberationProposal(300, BPS_1X, 100n * SCALE, METADATA_HASH);
      expect(await ruleHook.createdCount()).to.equal(1n);

      // Vote & execute after votingPeriod + timelockDelay
      await engine.connect(dadgozar).castVote(1, 200n * SCALE, true);
      expect(await ruleHook.voteCount()).to.equal(1n);

      await time.increase(4 * 86_400 + 10);
      await engine.connect(safeAdmin).executeProposal(1);
      expect(await ruleHook.executedCount()).to.equal(1n);

      // Creating another settlement proposal within 13 days must revert
      await time.increase(5 * 86_400);
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(400, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.be.revertedWithCustomError(ruleHook, "SettlementWaitingPeriodActive");

      // After 13 full days -> succeeds
      await time.increase(8 * 86_400 + 10);
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(400, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.emit(engine, "ProposalCreated");
    });

    it("Should allow Safe admin to detach the rule hook via address(0)", async function () {
      await engine.connect(safeAdmin).setProposalRuleHook(ethers.ZeroAddress);
      // 1.5x multiplier now succeeds because hook is detached
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(300, 15_000n, 100n * SCALE, METADATA_HASH)
      ).to.emit(engine, "ProposalCreated");
    });
  });

  // ------------------------------------------------------------
  // 3. Plugin 2: IQuorumCalculator (Dynamic Quorum)
  // ------------------------------------------------------------
  describe("3. Plugin: IQuorumCalculator", function () {
    it("Should override fallback quorum dynamically per target tier", async function () {
      await quorumCalc.setTierQuorum(9, 1_000n * SCALE);
      await engine.connect(safeAdmin).setQuorumCalculator(await quorumCalc.getAddress());

      // Even though proposer passes 100 * SCALE fallback, calculator overrides to 1000 * SCALE
      await engine.connect(mayor).createProposal(9, BPS_1X, 100n * SCALE, METADATA_HASH);
      const prop = await engine.getProposal(1);
      expect(prop.quorumRequiredScaled).to.equal(1_000n * SCALE);

      // Voting 500 * SCALE is insufficient for dynamic quorum of 1000 * SCALE
      await engine.connect(mayor).castVote(1, 500n * SCALE, true);
      await time.increase(4 * 86_400 + 10);
      await expect(engine.connect(safeAdmin).executeProposal(1))
        .to.be.revertedWithCustomError(engine, "QuorumNotReached");
    });
  });

  // ------------------------------------------------------------
  // 4. Plugin 3: IHadETasarMarket (MARKET_ROLE Leasing)
  // ------------------------------------------------------------
  describe("4. Plugin: IHadETasarMarket (MARKET_ROLE)", function () {
    beforeEach(async function () {
      await engine.connect(safeAdmin).setMarketModule(await marketMod.getAddress());
    });

    it("Should reject inactive market module on registration", async function () {
      const BadMarket = await ethers.getContractFactory("MockHadETasarMarket");
      const badMarket = await BadMarket.deploy();
      await badMarket.setActive(false);

      await expect(engine.connect(safeAdmin).setMarketModule(await badMarket.getAddress()))
        .to.be.revertedWithCustomError(engine, "InvalidPluginModule");
    });

    it("Should lease capacity, consume leased balance before native, handle expiry and revocation", async function () {
      const engineAddr = await engine.getAddress();

      // Mayor (796) leases 200 to Developer (18) for 2 hours
      await expect(
        marketMod.connect(safeAdmin).leaseCapacity(engineAddr, mayor.address, developer.address, 200n * SCALE, 7200)
      ).to.emit(engine, "CapacityLeased");

      expect(await engine.getNativeHadETasar(mayor.address)).to.equal(596n * SCALE);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(218n * SCALE);

      // Developer votes 150 * SCALE -> consumes leased balance first, native 18 remains untouched
      await engine.connect(developer).createProposal(4, BPS_1X, 100n * SCALE, METADATA_HASH);
      await engine.connect(developer).castVote(1, 150n * SCALE, true);

      expect(await engine.getNativeHadETasar(developer.address)).to.equal(18n * SCALE);
      const [remLeased] = await engine.getLeasedHadETasar(developer.address);
      expect(remLeased).to.equal(50n * SCALE);

      // After lease expires (2h + 1s), remaining 50 leased balance drops to 0
      await time.increase(7201);
      const [expiredLeased] = await engine.getLeasedHadETasar(developer.address);
      expect(expiredLeased).to.equal(0n);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(18n * SCALE);

      // Revoking market module revokes MARKET_ROLE
      await engine.connect(safeAdmin).setMarketModule(ethers.ZeroAddress);
      expect(await engine.hasRole(await engine.MARKET_ROLE(), await marketMod.getAddress())).to.equal(false);
    });
  });

  // ------------------------------------------------------------
  // 5. Plugin 4: IJudicialModule (JUDICIAL_ROLE Appeals & Penalties)
  // ------------------------------------------------------------
  describe("5. Plugin: IJudicialModule (JUDICIAL_ROLE)", function () {
    beforeEach(async function () {
      await engine.connect(safeAdmin).setJudicialModule(await judicialMod.getAddress());
    });

    it("Should allow judicial module to unfreeze citizens and apply voting penalty BPS", async function () {
      const engineAddr = await engine.getAddress();

      // Guardian freezes developer
      await engine.connect(safeAdmin).setCitizenFreeze(developer.address, true);
      expect(await engine.isFrozen(developer.address)).to.equal(true);

      // Judicial module unfreezes developer on Case #101
      await expect(judicialMod.connect(safeAdmin).executeUnfreeze(engineAddr, developer.address, 101))
        .to.emit(engine, "CitizenUnfrozenByJudiciary")
        .withArgs(developer.address, 101, await judicialMod.getAddress());
      expect(await engine.isFrozen(developer.address)).to.equal(false);

      // Judicial module imposes 25% penalty (2500 BPS) on Case #102
      await expect(judicialMod.connect(safeAdmin).executePenalty(engineAddr, developer.address, 2500, 102))
        .to.emit(engine, "JudicialPenaltyUpdated");

      // Developer votes 10 * SCALE at 1x -> effective impact reduced by 25% to 7.5 * SCALE
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH);
      await engine.connect(developer).castVote(1, 10n * SCALE, true);

      const prop = await engine.getProposal(1);
      expect(prop.forVotes).to.equal(7_500_000n);

      // Detaching judicial module revokes JUDICIAL_ROLE
      await engine.connect(safeAdmin).setJudicialModule(ethers.ZeroAddress);
      expect(await engine.hasRole(await engine.JUDICIAL_ROLE(), await judicialMod.getAddress())).to.equal(false);
    });
  });
});
