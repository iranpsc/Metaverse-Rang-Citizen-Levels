// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHadETasarCoreTarget
 * @notice Minimal target interface used by Market and Judicial plugin mocks to call HadETasarEngine.
 */
interface IHadETasarCoreTarget {
    function marketLeaseCapacity(
        address lessor,
        address lessee,
        uint256 amountScaled,
        uint256 durationSeconds
    ) external;

    function marketRevokeLease(address lessee) external;

    function judicialUnfreeze(address citizen, uint256 caseId) external;

    function judicialSetPenalty(address citizen, uint16 penaltyBps, uint256 caseId) external;
}

/**
 * @title MockCitizenshipLevelProvider
 * @notice Layer-1 citizenship mock returning citizen levels (0..13) until final identity contract is deployed.
 */
contract MockCitizenshipLevelProvider {
    mapping(address => uint8) private _levels;

    function setLevel(address user, uint8 level) external {
        _levels[user] = level;
    }

    function getCitizenLevel(address user) external view returns (uint8) {
        return _levels[user];
    }
}

/**
 * @title MockProposalRuleHook
 * @notice Mock implementation of IProposalRuleHook demonstrating specialized MetaRang governance rules:
 *         1) Optional 1x (10000 BPS) multiplier lock on Settlement Liberation proposals.
 *         2) Optional 13-day waiting period after executing a Settlement Liberation proposal.
 */
contract MockProposalRuleHook {
    uint256 public constant SETTLEMENT_WAIT_PERIOD = 13 days;
    uint256 public constant LOCKED_MULTIPLIER_BPS = 10_000;

    bool public enforce1xOnSettlement;
    bool public enforce13DayWaitAfterSettlement;
    uint256 public lastSettlementExecutedAt;

    uint256 public createdCount;
    uint256 public voteCount;
    uint256 public executedCount;

    error MultiplierLockedTo1x(uint256 providedBps);
    error SettlementWaitingPeriodActive(uint256 availableAt);

    function setRules(bool lock1x, bool enforce13DayWait) external {
        enforce1xOnSettlement = lock1x;
        enforce13DayWaitAfterSettlement = enforce13DayWait;
    }

    function onProposalCreated(
        uint256,
        address,
        uint8,
        uint8 proposalType,
        uint8,
        uint256,
        uint256 multiplierBps
    ) external {
        // ProposalType.SettlementLiberation == 1
        if (proposalType == 1) {
            if (enforce1xOnSettlement && multiplierBps != LOCKED_MULTIPLIER_BPS) {
                revert MultiplierLockedTo1x(multiplierBps);
            }
            if (
                enforce13DayWaitAfterSettlement &&
                lastSettlementExecutedAt != 0 &&
                block.timestamp < lastSettlementExecutedAt + SETTLEMENT_WAIT_PERIOD
            ) {
                revert SettlementWaitingPeriodActive(lastSettlementExecutedAt + SETTLEMENT_WAIT_PERIOD);
            }
        }
        createdCount += 1;
    }

    function onVoteCast(
        uint256,
        address,
        uint8,
        uint256,
        uint256,
        bool
    ) external {
        voteCount += 1;
    }

    function onProposalExecuted(
        uint256,
        uint8 proposalType,
        uint256
    ) external {
        if (proposalType == 1) {
            lastSettlementExecutedAt = block.timestamp;
        }
        executedCount += 1;
    }
}

/**
 * @title MockQuorumCalculator
 * @notice Mock implementation of IQuorumCalculator supporting per-tier dynamic quorum overrides.
 */
contract MockQuorumCalculator {
    mapping(uint8 => uint256) public tierQuorumOverrideScaled;

    function setTierQuorum(uint8 targetLevel, uint256 quorumScaled) external {
        tierQuorumOverrideScaled[targetLevel] = quorumScaled;
    }

    function calculateQuorum(
        uint8,
        uint8 targetLevel,
        uint256 fallbackQuorumScaled
    ) external view returns (uint256) {
        uint256 customQuorum = tierQuorumOverrideScaled[targetLevel];
        return customQuorum > 0 ? customQuorum : fallbackQuorumScaled;
    }
}

/**
 * @title MockHadETasarMarket
 * @notice Mock implementation of IHadETasarMarket for testing MARKET_ROLE capacity leasing/revocation.
 */
contract MockHadETasarMarket {
    address public immutable admin;
    bool private _active = true;

    error Unauthorized();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function isActiveMarket() external view returns (bool) {
        return _active;
    }

    function setActive(bool active_) external onlyAdmin {
        _active = active_;
    }

    function leaseCapacity(
        address engine,
        address lessor,
        address lessee,
        uint256 amountScaled,
        uint256 durationSeconds
    ) external onlyAdmin {
        IHadETasarCoreTarget(engine).marketLeaseCapacity(lessor, lessee, amountScaled, durationSeconds);
    }

    function revokeLease(address engine, address lessee) external onlyAdmin {
        IHadETasarCoreTarget(engine).marketRevokeLease(lessee);
    }
}

/**
 * @title MockJudicialModule
 * @notice Mock implementation of IJudicialModule for testing Judge-tier (Levels 11..13) appeals and penalties.
 */
contract MockJudicialModule {
    address public immutable admin;
    bool private _active = true;

    error Unauthorized();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function isActiveJudicialModule() external view returns (bool) {
        return _active;
    }

    function setActive(bool active_) external onlyAdmin {
        _active = active_;
    }

    function executeUnfreeze(address engine, address citizen, uint256 caseId) external onlyAdmin {
        IHadETasarCoreTarget(engine).judicialUnfreeze(citizen, caseId);
    }

    function executePenalty(
        address engine,
        address citizen,
        uint16 penaltyBps,
        uint256 caseId
    ) external onlyAdmin {
        IHadETasarCoreTarget(engine).judicialSetPenalty(citizen, penaltyBps, caseId);
    }
}
