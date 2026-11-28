// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ============================================================
// SECTION 1: INLINE OPENZEPPELIN v5 COMPATIBLE PRIMITIVES
// (Zero External Imports — Offline Remix Compilation Ready)
// ============================================================

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract ERC165 is IERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

interface IAccessControl {
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AccessControlBadConfirmation();

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
}

abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
    }

    mapping(bytes32 role => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role].hasRole[account];
    }

    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }

    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert AccessControlBadConfirmation();
        }
        _revokeRole(role, callerConfirmation);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
        if (!hasRole(role, account)) {
            _roles[role].hasRole[account] = true;
            emit RoleGranted(role, account, _msgSender());
            return true;
        }
        return false;
    }

    function _revokeRole(bytes32 role, address account) internal virtual returns (bool) {
        if (hasRole(role, account)) {
            _roles[role].hasRole[account] = false;
            emit RoleRevoked(role, account, _msgSender());
            return true;
        }
        return false;
    }
}

abstract contract Pausable is Context {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }
}

library Math {
    error MathOverflowedMulDiv();

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            if (denominator <= prod1) {
                revert MathOverflowedMulDiv();
            }

            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            return result;
        }
    }

    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 result = 1;
        uint256 x = a;
        if (x >> 128 > 0) {
            x >>= 128;
            result <<= 64;
        }
        if (x >> 64 > 0) {
            x >>= 64;
            result <<= 32;
        }
        if (x >> 32 > 0) {
            x >>= 32;
            result <<= 16;
        }
        if (x >> 16 > 0) {
            x >>= 16;
            result <<= 8;
        }
        if (x >> 8 > 0) {
            x >>= 8;
            result <<= 4;
        }
        if (x >> 4 > 0) {
            x >>= 4;
            result <<= 2;
        }
        if (x >> 2 > 0) {
            result <<= 1;
        }

        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            uint256 roundedDownResult = a / result;
            return result < roundedDownResult ? result : roundedDownResult;
        }
    }
}

// ============================================================
// SECTION 2: LAYER-1 & MODULAR PLUGIN INTERFACES
// ============================================================

interface ICitizenshipLevelProvider {
    function getCitizenLevel(address user) external view returns (uint8);
}

interface IProposalRuleHook {
    function onProposalCreated(
        uint256 proposalId,
        address proposer,
        uint8 proposerLevel,
        uint8 proposalType,
        uint8 targetLevel,
        uint256 settlementRadius,
        uint256 multiplierBps
    ) external;

    function onVoteCast(
        uint256 proposalId,
        address voter,
        uint8 voterLevel,
        uint256 amountScaled,
        uint256 effectiveImpactScaled,
        bool support
    ) external;

    function onProposalExecuted(
        uint256 proposalId,
        uint8 proposalType,
        uint256 settlementRadius
    ) external;
}

interface IQuorumCalculator {
    function calculateQuorum(
        uint8 proposalType,
        uint8 targetLevel,
        uint256 fallbackQuorumScaled
    ) external view returns (uint256);
}

interface IHadETasarMarket {
    function isActiveMarket() external view returns (bool);
}

interface IJudicialModule {
    function isActiveJudicialModule() external view returns (bool);
}

// ============================================================
// SECTION 3: HAD-E-TASAR CORE KERNEL (MR-GOV-SPEC-001)
// ============================================================

/**
 * @title HadETasarEngine
 * @notice Standalone Plugin-Based Core Kernel for MetaRang Multiverse On-Chain Governance.
 * @dev Implements MR-GOV-SPEC-001 with 14-tier matrix, 60s citizen / 24h guest cooldowns,
 *      dual recharge mechanics, For/Against voting, Quorum + Timelock enforcement,
 *      Level-13 settlement liberation, quadratic helper, and 4 optional plugin hooks.
 */
contract HadETasarEngine is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");
    bytes32 public constant JUDICIAL_ROLE = keccak256("JUDICIAL_ROLE");

    uint256 public constant SCALE = 1e6;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_MULTIPLIER_BPS = 50_000;
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

    // Layer-1 Provider & Optional Layer-2 Plugins
    ICitizenshipLevelProvider public levelProvider;
    IProposalRuleHook public proposalRuleHook;
    IQuorumCalculator public quorumCalculator;
    IHadETasarMarket public marketModule;
    IJudicialModule public judicialModule;

    uint256 public votingPeriod = 3 days;
    uint256 public timelockDelay = 24 hours;
    uint256 public nextProposalId = 1;

    /// @dev 14-tier maximum Had-e-Tasar capacity matrix (unscaled base units)
    uint256[14] private _tierMaxCapacity;

    struct CitizenAccount {
        uint256 balanceScaled;       // Native H_i(t) scaled by 1e6
        uint256 leasedBalanceScaled; // Temporary leased/traded H_i(t) via MARKET_ROLE
        uint256 leaseExpiresAt;      // Expiration timestamp for leased balance (0 = no expiry)
        uint256 lastUpdate;          // Timestamp of last native balance sync
        uint256 lastConsumeTime;     // Timestamp of last consumption
        uint256 depletedAt;          // Non-zero when native balance hit 0 (triggers linear minute recharge)
        uint16 penaltyBps;           // Judicial penalty reduction in BPS (0..10000; 0 = none)
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
        uint8 targetLevel;            // Must be >= proposer level
        uint256 settlementRadius;     // Only for Level 13 SettlementLiberation (66..696 meters)
        uint256 multiplierBps;        // Consumption/impact multiplier in BPS (10000 = 1.0x)
        uint256 quorumRequiredScaled; // Minimum total weighted votes (For + Against) scaled by 1e6
        uint256 forVotes;             // Scaled by 1e6
        uint256 againstVotes;         // Scaled by 1e6
        uint256 createdAt;
        uint256 votingEndsAt;         // createdAt + votingPeriod
        uint256 executableAt;         // votingEndsAt + timelockDelay
        bool executed;
        bytes32 metadataHash;         // IPFS / spec hash
    }

    mapping(address => CitizenAccount) private _accounts;
    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    error ZeroAddress();
    error InvalidTier(uint8 tier);
    error InvalidPluginModule(address module);
    error AccountFrozen(address user);
    error CooldownActive(uint256 availableAt);
    error InsufficientHadETasar(uint256 requested, uint256 available);
    error ZeroAmount();
    error SelfLeaseNotAllowed();
    error InvalidQuorum();
    error InvalidMultiplier(uint256 multiplierBps);
    error InvalidPenaltyBps(uint16 penaltyBps);
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
    event ProposalRuleHookUpdated(address indexed oldHook, address indexed newHook);
    event QuorumCalculatorUpdated(address indexed oldCalculator, address indexed newCalculator);
    event MarketModuleUpdated(address indexed oldMarket, address indexed newMarket);
    event JudicialModuleUpdated(address indexed oldJudicial, address indexed newJudicial);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event TimelockDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event CitizenFreezeUpdated(address indexed citizen, bool frozen);
    event CitizenUnfrozenByJudiciary(address indexed citizen, uint256 indexed caseId, address indexed module);
    event JudicialPenaltyUpdated(address indexed citizen, uint16 penaltyBps, uint256 indexed caseId, address indexed module);
    event CapacityLeased(
        address indexed lessor,
        address indexed lessee,
        uint256 amountScaled,
        uint256 leaseExpiresAt,
        address indexed market
    );
    event LeaseRevoked(address indexed lessee, uint256 clearedAmountScaled, address indexed market);
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

    /**
     * @param admin_ Governance admin address (Gnosis Safe 2-of-3 on Arbitrum One).
     * @param levelProvider_ Layer-1 Citizenship level provider contract address.
     */
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
    // View Functions — Capacity, Proposal, Recharge & Quadratic Helper
    // ------------------------------------------------------------

    function getTierMaxCapacity(uint8 tier) external view returns (uint256) {
        if (tier > MAX_TIER) revert InvalidTier(tier);
        return _tierMaxCapacity[tier];
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    function getNativeHadETasar(address citizen) public view returns (uint256) {
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
            // Full depletion mode: linear whole-minute recharge from depletion timestamp
            uint256 elapsedMinutes = (block.timestamp - acc.depletedAt) / 60;
            // slither-disable-next-line divide-before-multiply
            recharged = Math.mulDiv(maxCapScaled, elapsedMinutes, RECHARGE_CYCLE_MINUTES);
        } else {
            // Gradual depletion mode: proportional 24-hour cycle recharge
            uint256 elapsedSeconds = block.timestamp - acc.lastUpdate;
            recharged = Math.mulDiv(maxCapScaled, elapsedSeconds, RECHARGE_CYCLE_SECONDS);
        }

        uint256 updated = current + recharged;
        return updated > maxCapScaled ? maxCapScaled : updated;
    }

    function getLeasedHadETasar(address citizen) external view returns (uint256 amountScaled, uint256 expiresAt) {
        CitizenAccount storage acc = _accounts[citizen];
        if (acc.leaseExpiresAt != 0 && block.timestamp > acc.leaseExpiresAt) {
            return (0, 0);
        }
        return (acc.leasedBalanceScaled, acc.leaseExpiresAt);
    }

    function getCurrentHadETasar(address citizen) public view returns (uint256) {
        return getNativeHadETasar(citizen) + _getActiveLeasedBalance(citizen);
    }

    function calculateQuadraticWeight(uint256 stakeAmount) external pure returns (uint256) {
        return Math.sqrt(stakeAmount);
    }

    function isFrozen(address citizen) external view returns (bool) {
        return _accounts[citizen].frozen;
    }

    function getPenaltyBps(address citizen) external view returns (uint16) {
        return _accounts[citizen].penaltyBps;
    }

    // ------------------------------------------------------------
    // Governance Proposals (RBAC Rules + Plugin Hooks)
    // ------------------------------------------------------------

    function createProposal(
        uint8 targetLevel,
        uint256 multiplierBps,
        uint256 quorumRequiredScaled,
        bytes32 metadataHash
    ) external whenNotPaused nonReentrant returns (uint256 proposalId) {
        if (_accounts[msg.sender].frozen) revert AccountFrozen(msg.sender);
        if (targetLevel > MAX_TIER) revert InvalidTier(targetLevel);
        if (multiplierBps == 0 || multiplierBps > MAX_MULTIPLIER_BPS) revert InvalidMultiplier(multiplierBps);

        uint8 proposerLevel = _getValidatedTier(msg.sender);
        if (targetLevel < proposerLevel) {
            revert UnauthorizedTargetLevel(proposerLevel, targetLevel);
        }

        uint256 finalQuorum = _resolveQuorum(ProposalType.Standard, targetLevel, quorumRequiredScaled);
        proposalId = _storeProposal(
            ProposalType.Standard,
            targetLevel,
            0,
            multiplierBps,
            finalQuorum,
            metadataHash
        );

        _emitProposalCreated(proposalId);
        _notifyProposalCreated(proposalId, proposerLevel);
    }

    function createSettlementLiberationProposal(
        uint256 radiusMeters,
        uint256 multiplierBps,
        uint256 quorumRequiredScaled,
        bytes32 metadataHash
    ) external whenNotPaused nonReentrant returns (uint256 proposalId) {
        if (_accounts[msg.sender].frozen) revert AccountFrozen(msg.sender);
        if (multiplierBps == 0 || multiplierBps > MAX_MULTIPLIER_BPS) revert InvalidMultiplier(multiplierBps);

        uint8 proposerLevel = _getValidatedTier(msg.sender);
        if (proposerLevel != MAX_TIER) revert DadgozarOnly(proposerLevel);

        if (radiusMeters < MIN_SETTLEMENT_RADIUS || radiusMeters > MAX_SETTLEMENT_RADIUS) {
            revert InvalidSettlementRadius(radiusMeters);
        }

        uint256 finalQuorum = _resolveQuorum(ProposalType.SettlementLiberation, MAX_TIER, quorumRequiredScaled);
        proposalId = _storeProposal(
            ProposalType.SettlementLiberation,
            MAX_TIER,
            radiusMeters,
            multiplierBps,
            finalQuorum,
            metadataHash
        );

        _emitProposalCreated(proposalId);
        _notifyProposalCreated(proposalId, proposerLevel);
    }

    // ------------------------------------------------------------
    // Had-e-Tasar Consumption, Voting & Execution
    // ------------------------------------------------------------

    function castVote(uint256 proposalId, uint256 amountScaled, bool support)
        external
        whenNotPaused
        nonReentrant
    {
        if (amountScaled == 0) revert ZeroAmount();

        uint8 voterLevel = _validateVoteEligibility(proposalId, msg.sender);
        uint256 remainingScaled = _consumeCapacity(msg.sender, amountScaled);
        uint256 effectiveImpactScaled = _recordVote(proposalId, msg.sender, amountScaled, support);

        emit HadETasarConsumed(
            msg.sender,
            proposalId,
            support,
            amountScaled,
            effectiveImpactScaled,
            remainingScaled
        );

        _notifyVoteCast(proposalId, msg.sender, voterLevel, amountScaled, effectiveImpactScaled, support);
    }

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

        if (address(proposalRuleHook) != address(0)) {
            proposalRuleHook.onProposalExecuted(proposalId, uint8(prop.proposalType), prop.settlementRadius);
        }
    }

    // ------------------------------------------------------------
    // Market Module Entrypoints (MARKET_ROLE)
    // ------------------------------------------------------------

    function marketLeaseCapacity(
        address lessor,
        address lessee,
        uint256 amountScaled,
        uint256 durationSeconds
    ) external onlyRole(MARKET_ROLE) whenNotPaused nonReentrant {
        if (lessor == address(0) || lessee == address(0)) revert ZeroAddress();
        if (lessor == lessee) revert SelfLeaseNotAllowed();
        if (amountScaled == 0) revert ZeroAmount();

        CitizenAccount storage lessorAcc = _accounts[lessor];
        CitizenAccount storage lesseeAcc = _accounts[lessee];
        if (lessorAcc.frozen) revert AccountFrozen(lessor);
        if (lesseeAcc.frozen) revert AccountFrozen(lessee);

        uint256 lessorNative = getNativeHadETasar(lessor);
        if (amountScaled > lessorNative) {
            revert InsufficientHadETasar(amountScaled, lessorNative);
        }

        uint256 remainingNative = lessorNative - amountScaled;
        lessorAcc.initialized = true;
        lessorAcc.balanceScaled = remainingNative;
        lessorAcc.lastUpdate = block.timestamp;
        lessorAcc.depletedAt = remainingNative == 0 ? block.timestamp : 0;

        if (lesseeAcc.leaseExpiresAt != 0 && block.timestamp > lesseeAcc.leaseExpiresAt) {
            lesseeAcc.leasedBalanceScaled = 0;
            lesseeAcc.leaseExpiresAt = 0;
        }

        lesseeAcc.leasedBalanceScaled += amountScaled;
        if (durationSeconds > 0) {
            uint256 newExpiry = block.timestamp + durationSeconds;
            if (newExpiry > lesseeAcc.leaseExpiresAt) {
                lesseeAcc.leaseExpiresAt = newExpiry;
            }
        }

        emit CapacityLeased(lessor, lessee, amountScaled, lesseeAcc.leaseExpiresAt, msg.sender);
    }

    function marketRevokeLease(address lessee) external onlyRole(MARKET_ROLE) whenNotPaused nonReentrant {
        if (lessee == address(0)) revert ZeroAddress();
        CitizenAccount storage acc = _accounts[lessee];
        uint256 cleared = acc.leasedBalanceScaled;
        acc.leasedBalanceScaled = 0;
        acc.leaseExpiresAt = 0;
        emit LeaseRevoked(lessee, cleared, msg.sender);
    }

    // ------------------------------------------------------------
    // Judicial Module Entrypoints (JUDICIAL_ROLE — Judges Levels 11..13)
    // ------------------------------------------------------------

    function judicialUnfreeze(address citizen, uint256 caseId) external onlyRole(JUDICIAL_ROLE) whenNotPaused {
        if (citizen == address(0)) revert ZeroAddress();
        _accounts[citizen].frozen = false;
        emit CitizenUnfrozenByJudiciary(citizen, caseId, msg.sender);
        emit CitizenFreezeUpdated(citizen, false);
    }

    function judicialSetPenalty(address citizen, uint16 penaltyBps, uint256 caseId)
        external
        onlyRole(JUDICIAL_ROLE)
        whenNotPaused
    {
        if (citizen == address(0)) revert ZeroAddress();
        if (penaltyBps > BPS_DENOMINATOR) revert InvalidPenaltyBps(penaltyBps);
        _accounts[citizen].penaltyBps = penaltyBps;
        emit JudicialPenaltyUpdated(citizen, penaltyBps, caseId, msg.sender);
    }

    // ------------------------------------------------------------
    // Security, Plugin Management & Administration (Safe 2-of-3)
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

    function setProposalRuleHook(address newHook) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldHook = address(proposalRuleHook);
        proposalRuleHook = IProposalRuleHook(newHook);
        emit ProposalRuleHookUpdated(oldHook, newHook);
    }

    function setQuorumCalculator(address newCalculator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldCalculator = address(quorumCalculator);
        quorumCalculator = IQuorumCalculator(newCalculator);
        emit QuorumCalculatorUpdated(oldCalculator, newCalculator);
    }

    function setMarketModule(address newMarket) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMarket != address(0)) {
            if (!IHadETasarMarket(newMarket).isActiveMarket()) {
                revert InvalidPluginModule(newMarket);
            }
        }
        address oldMarket = address(marketModule);
        if (oldMarket != address(0)) {
            _revokeRole(MARKET_ROLE, oldMarket);
        }
        marketModule = IHadETasarMarket(newMarket);
        if (newMarket != address(0)) {
            _grantRole(MARKET_ROLE, newMarket);
        }
        emit MarketModuleUpdated(oldMarket, newMarket);
    }

    function setJudicialModule(address newJudicial) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newJudicial != address(0)) {
            if (!IJudicialModule(newJudicial).isActiveJudicialModule()) {
                revert InvalidPluginModule(newJudicial);
            }
        }
        address oldJudicial = address(judicialModule);
        if (oldJudicial != address(0)) {
            _revokeRole(JUDICIAL_ROLE, oldJudicial);
        }
        judicialModule = IJudicialModule(newJudicial);
        if (newJudicial != address(0)) {
            _grantRole(JUDICIAL_ROLE, newJudicial);
        }
        emit JudicialModuleUpdated(oldJudicial, newJudicial);
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

    // ------------------------------------------------------------
    // Internal Helpers (Stack-Safe & Slither-Clean)
    // ------------------------------------------------------------

    function _getValidatedTier(address citizen) internal view returns (uint8) {
        uint8 tier = levelProvider.getCitizenLevel(citizen);
        if (tier > MAX_TIER) revert InvalidTier(tier);
        return tier;
    }

    function _getActiveLeasedBalance(address citizen) internal view returns (uint256) {
        CitizenAccount storage acc = _accounts[citizen];
        if (acc.leaseExpiresAt != 0 && block.timestamp > acc.leaseExpiresAt) {
            return 0;
        }
        return acc.leasedBalanceScaled;
    }

    function _resolveQuorum(
        ProposalType proposalType,
        uint8 targetLevel,
        uint256 fallbackQuorumScaled
    ) internal view returns (uint256 finalQuorum) {
        if (address(quorumCalculator) != address(0)) {
            finalQuorum = quorumCalculator.calculateQuorum(
                uint8(proposalType),
                targetLevel,
                fallbackQuorumScaled
            );
        } else {
            finalQuorum = fallbackQuorumScaled;
        }
        if (finalQuorum == 0) revert InvalidQuorum();
    }

    function _storeProposal(
        ProposalType proposalType,
        uint8 targetLevel,
        uint256 settlementRadius,
        uint256 multiplierBps,
        uint256 finalQuorum,
        bytes32 metadataHash
    ) internal returns (uint256 proposalId) {
        proposalId = nextProposalId++;
        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.proposalType = proposalType;
        p.targetLevel = targetLevel;
        p.settlementRadius = settlementRadius;
        p.multiplierBps = multiplierBps;
        p.quorumRequiredScaled = finalQuorum;
        p.createdAt = block.timestamp;
        p.votingEndsAt = block.timestamp + votingPeriod;
        p.executableAt = p.votingEndsAt + timelockDelay;
        p.metadataHash = metadataHash;
    }

    function _emitProposalCreated(uint256 proposalId) internal {
        Proposal storage p = _proposals[proposalId];
        emit ProposalCreated(
            p.id,
            p.proposer,
            p.proposalType,
            p.targetLevel,
            p.settlementRadius,
            p.multiplierBps,
            p.quorumRequiredScaled,
            p.votingEndsAt,
            p.executableAt
        );
    }

    function _notifyProposalCreated(uint256 proposalId, uint8 proposerLevel) internal {
        if (address(proposalRuleHook) != address(0)) {
            Proposal storage p = _proposals[proposalId];
            proposalRuleHook.onProposalCreated(
                p.id,
                p.proposer,
                proposerLevel,
                uint8(p.proposalType),
                p.targetLevel,
                p.settlementRadius,
                p.multiplierBps
            );
        }
    }

    function _validateVoteEligibility(uint256 proposalId, address voter) internal view returns (uint8 voterLevel) {
        Proposal storage prop = _proposals[proposalId];
        if (prop.id == 0) revert ProposalNotFound(proposalId);
        if (block.timestamp > prop.votingEndsAt) revert VotingEnded(prop.votingEndsAt);
        if (prop.executed) revert ProposalAlreadyExecuted(proposalId);
        if (hasVoted[proposalId][voter]) revert AlreadyVoted(proposalId, voter);

        CitizenAccount storage acc = _accounts[voter];
        if (acc.frozen) revert AccountFrozen(voter);

        voterLevel = _getValidatedTier(voter);
        uint256 requiredCooldown = voterLevel == 0 ? GUEST_COOLDOWN_SECONDS : COOLDOWN_SECONDS;
        if (acc.lastConsumeTime != 0 && block.timestamp < acc.lastConsumeTime + requiredCooldown) {
            revert CooldownActive(acc.lastConsumeTime + requiredCooldown);
        }
    }

    function _consumeCapacity(address voter, uint256 amountScaled) internal returns (uint256 remainingTotalScaled) {
        CitizenAccount storage acc = _accounts[voter];
        uint256 nativeAvailable = getNativeHadETasar(voter);
        uint256 activeLeased = _getActiveLeasedBalance(voter);
        uint256 totalAvailable = nativeAvailable + activeLeased;

        if (amountScaled > totalAvailable) {
            revert InsufficientHadETasar(amountScaled, totalAvailable);
        }

        // Clear expired lease metadata if needed
        if (acc.leaseExpiresAt != 0 && block.timestamp > acc.leaseExpiresAt) {
            acc.leasedBalanceScaled = 0;
            acc.leaseExpiresAt = 0;
        }

        uint256 nativeToDeduct;
        if (activeLeased >= amountScaled) {
            acc.leasedBalanceScaled = activeLeased - amountScaled;
            nativeToDeduct = 0;
        } else {
            acc.leasedBalanceScaled = 0;
            acc.leaseExpiresAt = 0;
            nativeToDeduct = amountScaled - activeLeased;
        }

        if (nativeToDeduct > 0) {
            uint256 remainingNative = nativeAvailable - nativeToDeduct;
            acc.initialized = true;
            acc.balanceScaled = remainingNative;
            acc.lastUpdate = block.timestamp;
            acc.depletedAt = remainingNative == 0 ? block.timestamp : 0;
        } else if (nativeAvailable > 0 && acc.depletedAt != 0) {
            acc.initialized = true;
            acc.balanceScaled = nativeAvailable;
            acc.lastUpdate = block.timestamp;
            acc.depletedAt = 0;
        }

        acc.lastConsumeTime = block.timestamp;
        remainingTotalScaled = totalAvailable - amountScaled;
    }

    function _recordVote(
        uint256 proposalId,
        address voter,
        uint256 amountScaled,
        bool support
    ) internal returns (uint256 effectiveImpactScaled) {
        Proposal storage prop = _proposals[proposalId];
        hasVoted[proposalId][voter] = true;

        uint256 baseImpact = Math.mulDiv(amountScaled, prop.multiplierBps, BPS_DENOMINATOR);
        uint16 penalty = _accounts[voter].penaltyBps;
        effectiveImpactScaled = penalty == 0
            ? baseImpact
            : Math.mulDiv(baseImpact, BPS_DENOMINATOR - penalty, BPS_DENOMINATOR);

        if (support) {
            prop.forVotes += effectiveImpactScaled;
        } else {
            prop.againstVotes += effectiveImpactScaled;
        }
    }

    function _notifyVoteCast(
        uint256 proposalId,
        address voter,
        uint8 voterLevel,
        uint256 amountScaled,
        uint256 effectiveImpactScaled,
        bool support
    ) internal {
        if (address(proposalRuleHook) != address(0)) {
            proposalRuleHook.onVoteCast(
                proposalId,
                voter,
                voterLevel,
                amountScaled,
                effectiveImpactScaled,
                support
            );
        }
    }
}
