// ============================================================
// HARDHAT TEST SUITE — HadETasarEngine (MR-GOV-SPEC-001)
// ============================================================

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("HadETasarEngine — MR-GOV-SPEC-001 Full Verification Suite", function () {
  let admin, guest, developer, mayor, dadgozar, voterB, attacker;
  let levelProvider, engine;

  const SCALE = 1_000_000n;
  const BPS_1X = 10_000n;
  const METADATA_HASH = ethers.keccak256(ethers.toUtf8Bytes("MR-GOV-SPEC-001-PROPOSAL"));

  const EXPECTED_TIERS = [
    1n, 1n, 3n, 8n, 18n, 36n, 76n, 166n, 366n, 796n, 1696n, 3696n, 7896n, 16896n
  ];

  beforeEach(async function () {
    [admin, guest, developer, mayor, dadgozar, voterB, attacker] = await ethers.getSigners();

    const MockProvider = await ethers.getContractFactory("MockCitizenshipLevelProvider");
    levelProvider = await MockProvider.deploy();
    await levelProvider.waitForDeployment();

    await levelProvider.setLevel(guest.address, 0);      // Level 0: Non-Citizen (Guest)
    await levelProvider.setLevel(developer.address, 4);  // Level 4: Developer (H_max = 18)
    await levelProvider.setLevel(mayor.address, 9);      // Level 9: Mayor (H_max = 796)
    await levelProvider.setLevel(dadgozar.address, 13);  // Level 13: Dadgozar (H_max = 16896)
    await levelProvider.setLevel(voterB.address, 10);    // Level 10: Governor (H_max = 1696)

    const HadETasarEngine = await ethers.getContractFactory("HadETasarEngine");
    engine = await HadETasarEngine.deploy(admin.address, await levelProvider.getAddress());
    await engine.waitForDeployment();
  });

  // ------------------------------------------------------------
  // 1. 14-Tier Governance Matrix
  // ------------------------------------------------------------
  describe("14-Tier Capacity Matrix", function () {
    it("Should return exact H_max values for all 14 tiers (0..13) and revert for tier > 13", async function () {
      for (let tier = 0; tier <= 13; tier++) {
        expect(await engine.getTierMaxCapacity(tier)).to.equal(EXPECTED_TIERS[tier]);
      }
      await expect(engine.getTierMaxCapacity(14))
        .to.be.revertedWithCustomError(engine, "InvalidTier")
        .withArgs(14);
    });

    it("Should initialize citizen balance at full scaled tier capacity", async function () {
      expect(await engine.getCurrentHadETasar(guest.address)).to.equal(1n * SCALE);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(18n * SCALE);
      expect(await engine.getCurrentHadETasar(dadgozar.address)).to.equal(16896n * SCALE);
    });
  });

  // ------------------------------------------------------------
  // 2. RBAC Rules & Level 13 Exclusive Settlement Liberation
  // ------------------------------------------------------------
  describe("RBAC Rules & Level-13 Exclusivity", function () {
    it("Should allow proposing for own level or higher, and reject lower target levels", async function () {
      // Developer (Level 4) targeting Level 4 and Level 9 -> Succeeds
      await expect(engine.connect(developer).createProposal(4, BPS_1X, 10n * SCALE, METADATA_HASH))
        .to.emit(engine, "ProposalCreated");
      await expect(engine.connect(developer).createProposal(9, BPS_1X, 10n * SCALE, METADATA_HASH))
        .to.emit(engine, "ProposalCreated");

      // Developer (Level 4) targeting Level 3 -> Reverts
      await expect(engine.connect(developer).createProposal(3, BPS_1X, 10n * SCALE, METADATA_HASH))
        .to.be.revertedWithCustomError(engine, "UnauthorizedTargetLevel")
        .withArgs(4, 3);
    });

    it("Should restrict Settlement Liberation strictly to Level 13 with radius in [66, 696]", async function () {
      // Non-Dadgozar (Mayor Level 9) -> Reverts
      await expect(
        engine.connect(mayor).createSettlementLiberationProposal(200, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.be.revertedWithCustomError(engine, "DadgozarOnly").withArgs(9);

      // Radius out of bounds -> Reverts
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(65, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.be.revertedWithCustomError(engine, "InvalidSettlementRadius").withArgs(65);

      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(697, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.be.revertedWithCustomError(engine, "InvalidSettlementRadius").withArgs(697);

      // Valid Level 13 with boundary radii 66 and 696 -> Succeeds
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(66, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.emit(engine, "ProposalCreated");
      await expect(
        engine.connect(dadgozar).createSettlementLiberationProposal(696, BPS_1X, 100n * SCALE, METADATA_HASH)
      ).to.emit(engine, "ProposalCreated");
    });
  });

  // ------------------------------------------------------------
  // 3. Cooldowns: 24h for Level 0 (Guest) & 60s for Levels 1..13
  // ------------------------------------------------------------
  describe("Cooldown Enforcement", function () {
    beforeEach(async function () {
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 1
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 2
    });

    it("Should enforce 60-second cooldown for citizens (Levels 1..13)", async function () {
      await engine.connect(developer).castVote(1, 5n * SCALE, true);

      // Voting again after 30s must revert
      await time.increase(30);
      await expect(engine.connect(developer).castVote(2, 5n * SCALE, true))
        .to.be.revertedWithCustomError(engine, "CooldownActive");

      // Voting after 60s total succeeds
      await time.increase(31);
      await expect(engine.connect(developer).castVote(2, 5n * SCALE, true))
        .to.emit(engine, "HadETasarConsumed");
    });

    it("Should enforce 24-hour cooldown (1 vote/day) for Level 0 guests even on partial spend", async function () {
      await engine.connect(guest).castVote(1, 500_000n, true); // 0.5 out of 1.0

      // After 2 hours, still blocked
      await time.increase(2 * 3600);
      await expect(engine.connect(guest).castVote(2, 500_000n, true))
        .to.be.revertedWithCustomError(engine, "CooldownActive");

      // After 24 hours total, succeeds
      await time.increase(22 * 3600 + 1);
      await expect(engine.connect(guest).castVote(2, 500_000n, true))
        .to.emit(engine, "HadETasarConsumed");
    });
  });

  // ------------------------------------------------------------
  // 4. Dual Recharge Mechanics (Gradual 24h vs Full Depletion Minute-Based)
  // ------------------------------------------------------------
  describe("Dynamic Epoch Recharge", function () {
    beforeEach(async function () {
      await engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH); // ID 1
    });

    it("Should recharge proportionally over 24 hours on gradual depletion", async function () {
      // Developer has 18 * SCALE; consume 9 * SCALE -> 9 * SCALE left
      await engine.connect(developer).castVote(1, 9n * SCALE, true);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(9n * SCALE);

      // Advance 6 hours (25% of 24h -> +4.5 * SCALE = 13.5 * SCALE)
      await time.increase(6 * 3600);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(13_500_000n);

      // Advance another 18 hours -> capped at 18 * SCALE
      await time.increase(18 * 3600);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(18n * SCALE);
    });

    it("Should recharge linearly by whole minutes when fully depleted to zero", async function () {
      // Developer consumes full 18 * SCALE -> balance = 0, depletedAt = now
      await engine.connect(developer).castVote(1, 18n * SCALE, true);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(0n);

      // Advance 45 seconds (< 1 full minute) -> still 0
      await time.increase(45);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(0n);

      // Advance to 120 minutes (2 hours = 120/1440 of 18 * SCALE = 1.5 * SCALE)
      await time.increase(120 * 60 - 45);
      expect(await engine.getCurrentHadETasar(developer.address)).to.equal(1_500_000n);
    });
  });

  // ------------------------------------------------------------
  // 5. Quorum, For/Against Majority, Voting Period & Timelock
  // ------------------------------------------------------------
  describe("Quorum, Voting Period, Timelock & Execution", function () {
    it("Should enforce voting period, timelock, quorum, and For > Against majority", async function () {
      const quorum = 500n * SCALE;
      await engine.connect(mayor).createProposal(9, BPS_1X, quorum, METADATA_HASH); // ID 1

      // Mayor votes For with 400 * SCALE (below quorum of 500)
      await engine.connect(mayor).castVote(1, 400n * SCALE, true);

      // Fast-forward past votingPeriod (3 days) + timelock (1 day)
      await time.increase(4 * 86_400 + 10);

      // Voting after votingEndsAt reverts
      await expect(engine.connect(voterB).castVote(1, 200n * SCALE, true))
        .to.be.revertedWithCustomError(engine, "VotingEnded");

      // Execution fails due to QuorumNotReached
      await expect(engine.connect(admin).executeProposal(1))
        .to.be.revertedWithCustomError(engine, "QuorumNotReached");
    });

    it("Should reject execution if Against >= For, and succeed when quorum & majority pass after timelock", async function () {
      const quorum = 500n * SCALE;
      await engine.connect(mayor).createProposal(9, BPS_1X, quorum, METADATA_HASH); // ID 1
      await engine.connect(mayor).createProposal(9, BPS_1X, quorum, METADATA_HASH); // ID 2

      // Proposal 1: 300 For vs 400 Against -> Defeated
      await engine.connect(mayor).castVote(1, 300n * SCALE, true);
      await engine.connect(voterB).castVote(1, 400n * SCALE, false);

      // Proposal 2: 400 For vs 200 Against -> Passes
      await time.increase(61);
      await engine.connect(mayor).castVote(2, 400n * SCALE, true);
      await engine.connect(voterB).castVote(2, 200n * SCALE, false);

      // Right after voting ends (3 days), timelock is still active
      await time.increase(3 * 86_400);
      await expect(engine.connect(admin).executeProposal(2))
        .to.be.revertedWithCustomError(engine, "TimelockNotExpired");

      // After timelock (1 more day)
      await time.increase(86_400 + 1);
      await expect(engine.connect(admin).executeProposal(1))
        .to.be.revertedWithCustomError(engine, "ProposalDefeated");

      await expect(engine.connect(admin).executeProposal(2))
        .to.emit(engine, "ProposalExecuted")
        .withArgs(2, admin.address);
    });

    it("Should enforce bounds on votingPeriod and timelockDelay updates", async function () {
      await expect(engine.connect(admin).setVotingPeriod(100))
        .to.be.revertedWithCustomError(engine, "InvalidDelayBounds");
      await expect(engine.connect(admin).setTimelockDelay(0))
        .to.be.revertedWithCustomError(engine, "InvalidDelayBounds");

      await expect(engine.connect(admin).setTimelockDelay(48 * 3600))
        .to.emit(engine, "TimelockDelayUpdated");
    });
  });

  // ------------------------------------------------------------
  // 6. Security: Account Freeze, Pause & Quadratic Weight
  // ------------------------------------------------------------
  describe("Security Controls & Quadratic Weighting", function () {
    it("Should block frozen citizens from proposing or voting", async function () {
      await engine.connect(admin).setCitizenFreeze(developer.address, true);

      await expect(engine.connect(developer).createProposal(4, BPS_1X, 5n * SCALE, METADATA_HASH))
        .to.be.revertedWithCustomError(engine, "AccountFrozen");

      await engine.connect(mayor).createProposal(9, BPS_1X, 5n * SCALE, METADATA_HASH);
      await expect(engine.connect(developer).castVote(1, 5n * SCALE, true))
        .to.be.revertedWithCustomError(engine, "AccountFrozen");
    });

    it("Should compute exact Quadratic Governance weight sqrt(stake)", async function () {
      expect(await engine.calculateQuadraticWeight(10_000n)).to.equal(100n);
      expect(await engine.calculateQuadraticWeight(1_000_000n)).to.equal(1_000n);
    });
  });
});