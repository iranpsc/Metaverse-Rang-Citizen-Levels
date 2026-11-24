// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ICitizenshipLevelProvider
 * @notice Minimal interface to read citizen level (0..13) from the Layer-1 Citizenship contract.
 */
interface ICitizenshipLevelProvider {
    function getCitizenLevel(address user) external view returns (uint8);
}

/**
 * @title HadETasarEngine
 * @notice Audit-ready On-Chain Governance & Dynamic Influence ("Had-e-Tasar") Engine for MetaRang Multiverse.
 * @dev Implements MR-GOV-SPEC-001: 14-tier matrix, 60s citizen cooldown, 24h Level-0 guest limit,
 *      dual recharge mechanics, For/Against voting, Quorum enforcement, separated Voting Period & Timelock,
 *      tier-based RBAC, exclusive Level-13 settlement liberation, quadratic stake weighting, and account freeze.
 */
contract HadETasarEngine is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    uint256 public constant SCALE = 1e6;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant COOLDOWN_SECONDS = 60;
    uint256 public constant GUEST_COOLDOWN_SECONDS = 86_400; // 24 hours for Level 0 (1 vote/day)
    uint256 public constant RECHARGE_CYCLE_SECONDS = 86_400; // 24 hours
    uint256 public constant RECHARGE_CYCLE_MINUTES = 1_440;  // 24 hours in minutes

    uint256 public constant MIN_VOTING_PERIOD = 1 hours;
    uint256 public constant MAX_VOTING_PERIOD = 14 days;
    uint256 public constant MIN_TIMELOCK_DELAY = 1 hours;
    uint256 public constant MAX_TIMELOCK_DELAY = 30 days;

    uint8 public constant MAX_TIER = 13;
    uint256 public constant MIN_SETTLEMENT_RADIUS = 66;
    uint256 public constant MAX_SETTLEMENT_RADIUS = 696;

    ICitizenshipLevelProvider public levelProvider;
    uint256 public votingPeriod = 3 days;
    uint256 public timelockDelay = 24 hours;
    uint256 public nextProposalId = 1;

    /// @dev 14-tier maximum Had-e-Tasar capacity matrix (unscaled base units)
    uint256[14] private _tierMaxCapacity;

    struct CitizenAccount {
        uint256 balanceScaled;      // Current H_i(t) scaled by 1e6
        uint256 lastUpdate;         // Timestamp of last balance sync
        uint256 lastConsumeTime;    // Timestamp of last consumption
        uint256 depletedAt;         // Non-zero when balance hit 0 (triggers linear minute recharge)
        bool initialized;
        bool frozen;
    }

    enum ProposalType {
        Standard,
        SettlementLiberation
    }

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        uint8 targetLevel;           // Must be >= proposer level
        uint256 settlementRadius;    // Only for Level 13 SettlementLiberation (66..696 meters)
        uint256 multiplierBps;       // Consumption/impact multiplier in BPS (10000 = 1.0x)
        uint256 quorumRequiredScaled;// Minimum total weighted votes (For + Against) scaled by 1e6
        uint256 forVotes;            // Scaled by 1e6
        uint256 againstVotes;        // Scaled by 1e6
        uint256 createdAt;
        uint256 votingEndsAt;        // createdAt + votingPeriod
        uint256 executableAt;        // votingEndsAt + timelockDelay
        bool executed;
        bytes32 metadataHash;        // IPFS / spec hash
    }

    mapping(address => CitizenAccount) private _accounts;
    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    error ZeroAddress();
    error InvalidTier(uint8 tier);
    error AccountFrozen(address user);
    error CooldownActive(uint256 availableAt);
    error InsufficientHadETasar(uint256 requested, uint256 available);
    error ZeroAmount();
    error InvalidQuorum();
    error InvalidMultiplier(uint256 multiplierBps);
    error InvalidDelayBounds(uint256 value, uint256 minAllowed, uint256 maxAllowed);
    error UnauthorizedTargetLevel(uint8 proposerLevel, uint8 targetLevel);
    error DadgozarOnly(uint8 callerLevel);
    error InvalidSettlementRadius(uint256 radius);
    error ProposalNotFound(uint256 proposalId);
    error VotingEnded(uint256 votingEndsAt);
    error AlreadyVoted(uint256 proposalId, address voter);
    error TimelockNotExpired(uint256 executableAt);
    error QuorumNotReached(uint256 totalVotes, uint256 quorumRequired);
    error ProposalDefeated(uint256 forVotes, uint256 againstVotes);
    error ProposalAlreadyExecuted(uint256 proposalId);

    event LevelProviderUpdated(address indexed oldProvider, address indexed newProvider);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event TimelockDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event CitizenFreezeUpdated(address indexed citizen, bool frozen);
    event HadETasarConsumed(
        address indexed citizen,
        uint256 indexed proposalId,
        bool support,
        uint256 amountConsumedScaled,
        uint256 effectiveImpactScaled,
        uint256 remainingScaled
    );
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        uint8 targetLevel,
        uint256 settlementRadius,
        uint256 multiplierBps,
        uint256 quorumRequiredScaled,
        uint256 votingEndsAt,
        uint256 executableAt
    );
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);

    constructor(address admin_, address levelProvider_) {
        if (admin_ == address(0) || levelProvider_ == address(0)) revert ZeroAddress();

        levelProvider = ICitizenshipLevelProvider(levelProvider_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
        _grantRole(GUARDIAN_ROLE, admin_);
        _grantRole(EXECUTOR_ROLE, admin_);

        // MR-GOV-SPEC-001 Section 3: 14-Tier Governance Hierarchy
        _tierMaxCapacity = [
            1,      // Level 0: Non-Citizen (Guest)
            1,      // Level 1: Newcomer
            3,      // Level 2: Journalist
            8,      // Level 3: Contributor
            18,     // Level 4: Developer
            36,     // Level 5: Inspector
            76,     // Level 6: Merchant
            166,    // Level 7: Lawyer
            366,    // Level 8: City Council
            796,    // Level 9: Mayor
            1696,   // Level 10: Governor
            3696,   // Level 11: Judge Level 1
            7896,   // Level 12: Judge Level 2
            16896   // Level 13: Judge Level 3 (Dadgozar)
        ];
    }

    // ------------------------------------------------------------
    // View Functions — Capacity, Proposal, Recharge & Quadratic Weight
    // ------------------------------------------------------------

    /**
     * @notice Returns the unscaled maximum Had-e-Tasar for a given tier (0..13).
     */
    function getTierMaxCapacity(uint8 tier) external view returns (uint256) {
        if (tier > MAX_TIER) revert InvalidTier(tier);
        return _tierMaxCapacity[tier];
    }

    /**
     * @notice Returns the full Proposal struct for a given proposalId.
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    /**
     * @notice Computes the current available Had-e-Tasar (scaled by 1e6) including dynamic recharge.
     */
    function getCurrentHadETasar(address citizen) public view returns (uint256) {
        uint8 tier = _getValidatedTier(citizen);
        uint256 maxCapScaled = _tierMaxCapacity[tier] * SCALE;

        CitizenAccount storage acc = _accounts[citizen];
        if (!acc.initialized) {
            return maxCapScaled;
        }

        uint256 current = acc.balanceScaled;
        if (current >= maxCapScaled) {
            return maxCapScaled;
        }

        uint256 recharged;
        if (acc.depletedAt != 0) {
            // Full depletion mode: linear minute-based recharge from depletion moment
            uint256 elapsedMinutes = (block.timestamp - acc.depletedAt) / 60;
            recharged = Math.mulDiv(maxCapScaled, elapsedMinutes, RECHARGE_CYCLE_MINUTES);
        } else {
            // Gradual depletion mode: proportional 24-hour cycle recharge
            uint256 elapsedSeconds = block.timestamp - acc.lastUpdate;
            recharged = Math.mulDiv(maxCapScaled, elapsedSeconds, RECHARGE_CYCLE_SECONDS);
        }

        uint256 updated = current + recharged;
        return updated > maxCapScaled ? maxCapScaled : updated;
    }

    /**
     * @notice Computes Quadratic Governance voting weight: sqrt(stakeAmount).
     */
    function calculateQuadraticWeight(uint256 stakeAmount) external pure returns (uint256) {
        return Math.sqrt(stakeAmount);
    }

    /**
     * @notice Checks if a citizen account is currently frozen.
     */
    function isFrozen(address citizen) external view returns (bool) {
        return _accounts[citizen].frozen;
    }

    // ------------------------------------------------------------
    // Governance Proposals (RBAC Rules — Section 4)
    // ------------------------------------------------------------

    /**
     * @notice Creates a standard governance proposal.
     * @dev Enforces RBAC Rule 1: proposer can only target their own level or higher.
     */
    function createProposal(
        uint8 targetLevel,
        uint256 multiplierBps,
        uint256 quorumRequiredScaled,
        bytes32 metadataHash
    ) external whenNotPaused returns (uint256 proposalId) {
        if (_accounts[msg.sender].frozen) revert AccountFrozen(msg.sender);
        if (targetLevel > MAX_TIER) revert InvalidTier(targetLevel);
        if (multiplierBps == 0 || multiplierBps > 50_000) revert InvalidMultiplier(multiplierBps);
        if (quorumRequiredScaled == 0) revert InvalidQuorum();

        uint8 proposerLevel = _getValidatedTier(msg.sender);
        if (targetLevel < proposerLevel) {
            revert UnauthorizedTargetLevel(proposerLevel, targetLevel);
        }

        proposalId = nextProposalId++;
        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.proposalType = ProposalType.Standard;
        p.targetLevel = targetLevel;
        p.multiplierBps = multiplierBps;
        p.quorumRequiredScaled = quorumRequiredScaled;
        p.createdAt = block.timestamp;
        p.votingEndsAt = block.timestamp + votingPeriod;
        p.executableAt = p.votingEndsAt + timelockDelay;
        p.metadataHash = metadataHash;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            ProposalType.Standard,
            targetLevel,
            0,
            multiplierBps,
            quorumRequiredScaled,
            p.votingEndsAt,
            p.executableAt
        );
    }

    /**
     * @notice Creates a Settlement Liberation proposal.
     * @dev Enforces RBAC Rule 2: exclusively Level 13 (Dadgozar) with radius in [66, 696] meters.
     */
    function createSettlementLiberationProposal(
        uint256 radiusMeters,
        uint256 multiplierBps,
        uint256 quorumRequiredScaled,
        bytes32 metadataHash
    ) external whenNotPaused returns (uint256 proposalId) {
        if (_accounts[msg.sender].frozen) revert AccountFrozen(msg.sender);
        if (multiplierBps == 0 || multiplierBps > 50_000) revert InvalidMultiplier(multiplierBps);
        if (quorumRequiredScaled == 0) revert InvalidQuorum();

        uint8 proposerLevel = _getValidatedTier(msg.sender);
        if (proposerLevel != MAX_TIER) revert DadgozarOnly(proposerLevel);

        if (radiusMeters < MIN_SETTLEMENT_RADIUS || radiusMeters > MAX_SETTLEMENT_RADIUS) {
            revert InvalidSettlementRadius(radiusMeters);
        }

        proposalId = nextProposalId++;
        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.proposalType = ProposalType.SettlementLiberation;
        p.targetLevel = MAX_TIER;
        p.settlementRadius = radiusMeters;
        p.multiplierBps = multiplierBps;
        p.quorumRequiredScaled = quorumRequiredScaled;
        p.createdAt = block.timestamp;
        p.votingEndsAt = block.timestamp + votingPeriod;
        p.executableAt = p.votingEndsAt + timelockDelay;
        p.metadataHash = metadataHash;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            ProposalType.SettlementLiberation,
            MAX_TIER,
            radiusMeters,
            multiplierBps,
            quorumRequiredScaled,
            p.votingEndsAt,
            p.executableAt
        );
    }

    // ------------------------------------------------------------
    // Had-e-Tasar Consumption & For/Against Voting
    // ------------------------------------------------------------

    /**
     * @notice Consumes Had-e-Tasar to vote For or Against a proposal.
     * @dev Enforces 24h cooldown for Level 0 (guests) and 60s cooldown for Levels 1..13.
     * @param proposalId Target proposal ID.
     * @param amountScaled Amount of Had-e-Tasar to consume (scaled by 1e6).
     * @param support True for For vote, False for Against vote.
     */
    function castVote(uint256 proposalId, uint256 amountScaled, bool support)
        external
        whenNotPaused
        nonReentrant
    {
        if (amountScaled == 0) revert ZeroAmount();

        Proposal storage prop = _proposals[proposalId];
        if (prop.id == 0) revert ProposalNotFound(proposalId);
        if (block.timestamp > prop.votingEndsAt) revert VotingEnded(prop.votingEndsAt);
        if (prop.executed) revert ProposalAlreadyExecuted(proposalId);
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted(proposalId, msg.sender);

        CitizenAccount storage acc = _accounts[msg.sender];
        if (acc.frozen) revert AccountFrozen(msg.sender);

        {
            uint256 requiredCooldown = _getValidatedTier(msg.sender) == 0
                ? GUEST_COOLDOWN_SECONDS
                : COOLDOWN_SECONDS;
            if (acc.lastConsumeTime != 0 && block.timestamp < acc.lastConsumeTime + requiredCooldown) {
                revert CooldownActive(acc.lastConsumeTime + requiredCooldown);
            }
        }

        uint256 remainingScaled;
        {
            uint256 availableScaled = getCurrentHadETasar(msg.sender);
            if (amountScaled > availableScaled) {
                revert InsufficientHadETasar(amountScaled, availableScaled);
            }
            remainingScaled = availableScaled - amountScaled;
        }

        acc.initialized = true;
        acc.balanceScaled = remainingScaled;
        acc.lastUpdate = block.timestamp;
        acc.lastConsumeTime = block.timestamp;
        acc.depletedAt = remainingScaled == 0 ? block.timestamp : 0;

        hasVoted[proposalId][msg.sender] = true;

        uint256 effectiveImpactScaled = Math.mulDiv(amountScaled, prop.multiplierBps, BPS_DENOMINATOR);
        if (support) {
            prop.forVotes += effectiveImpactScaled;
        } else {
            prop.againstVotes += effectiveImpactScaled;
        }

        emit HadETasarConsumed(
            msg.sender,
            proposalId,
            support,
            amountScaled,
            effectiveImpactScaled,
            remainingScaled
        );
    }

    /**
     * @notice Executes a governance proposal after voting ends, timelock expires, quorum is met, and majority passes.
     */
    function executeProposal(uint256 proposalId)
        external
        onlyRole(EXECUTOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        Proposal storage prop = _proposals[proposalId];
        if (prop.id == 0) revert ProposalNotFound(proposalId);
        if (prop.executed) revert ProposalAlreadyExecuted(proposalId);
        if (block.timestamp < prop.executableAt) revert TimelockNotExpired(prop.executableAt);

        uint256 totalVotes = prop.forVotes + prop.againstVotes;
        if (totalVotes < prop.quorumRequiredScaled) {
            revert QuorumNotReached(totalVotes, prop.quorumRequiredScaled);
        }
        if (prop.forVotes <= prop.againstVotes) {
            revert ProposalDefeated(prop.forVotes, prop.againstVotes);
        }

        prop.executed = true;
        emit ProposalExecuted(proposalId, msg.sender);
    }

    // ------------------------------------------------------------
    // Security & Administration
    // ------------------------------------------------------------

    function setCitizenFreeze(address citizen, bool frozen) external onlyRole(GUARDIAN_ROLE) {
        if (citizen == address(0)) revert ZeroAddress();
        _accounts[citizen].frozen = frozen;
        emit CitizenFreezeUpdated(citizen, frozen);
    }

    function setLevelProvider(address newProvider) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newProvider == address(0)) revert ZeroAddress();
        address oldProvider = address(levelProvider);
        levelProvider = ICitizenshipLevelProvider(newProvider);
        emit LevelProviderUpdated(oldProvider, newProvider);
    }

    function setVotingPeriod(uint256 newPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPeriod < MIN_VOTING_PERIOD || newPeriod > MAX_VOTING_PERIOD) {
            revert InvalidDelayBounds(newPeriod, MIN_VOTING_PERIOD, MAX_VOTING_PERIOD);
        }
        uint256 oldPeriod = votingPeriod;
        votingPeriod = newPeriod;
        emit VotingPeriodUpdated(oldPeriod, newPeriod);
    }

    function setTimelockDelay(uint256 newDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDelay < MIN_TIMELOCK_DELAY || newDelay > MAX_TIMELOCK_DELAY) {
            revert InvalidDelayBounds(newDelay, MIN_TIMELOCK_DELAY, MAX_TIMELOCK_DELAY);
        }
        uint256 oldDelay = timelockDelay;
        timelockDelay = newDelay;
        emit TimelockDelayUpdated(oldDelay, newDelay);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _getValidatedTier(address citizen) internal view returns (uint8) {
        uint8 tier = levelProvider.getCitizenLevel(citizen);
        if (tier > MAX_TIER) revert InvalidTier(tier);
        return tier;
    }
}