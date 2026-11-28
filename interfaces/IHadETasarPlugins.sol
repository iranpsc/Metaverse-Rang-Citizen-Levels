// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICitizenshipLevelProvider
 * @notice Layer-1 identity interface returning citizen tier (0..13).
 */
interface ICitizenshipLevelProvider {
    function getCitizenLevel(address user) external view returns (uint8);
}

/**
 * @title IProposalRuleHook
 * @notice Plugin hook for specialized timed governance rules (e.g., 13-day waiting period,
 *         1x multiplier locks, or re-voting restrictions on specific proposal types).
 */
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

/**
 * @title IQuorumCalculator
 * @notice Plugin interface for dynamic weighted quorum calculations by tier and proposal type.
 */
interface IQuorumCalculator {
    function calculateQuorum(
        uint8 proposalType,
        uint8 targetLevel,
        uint256 fallbackQuorumScaled
    ) external view returns (uint256);
}

/**
 * @title IHadETasarMarket
 * @notice Plugin interface for authorized Had-e-Tasar capacity leasing/trading contracts.
 */
interface IHadETasarMarket {
    function isActiveMarket() external view returns (bool);
}

/**
 * @title IJudicialModule
 * @notice Plugin interface for Judge-tier (Levels 11..13) appeals, penalty adjustments, and unfreezing.
 */
interface IJudicialModule {
    function isActiveJudicialModule() external view returns (bool);
}
