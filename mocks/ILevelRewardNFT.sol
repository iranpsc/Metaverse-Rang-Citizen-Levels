// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title ILevelRewardNFT
 * @notice Standard interface for citizenship level reward NFTs.
 */
interface ILevelRewardNFT is IERC165 {
    /**
     * @notice Mints a level reward NFT to a citizen upon reaching a specific level.
     * @param to Recipient citizen address.
     * @param level The citizenship level achieved (1 to 13).
     * @return tokenId The newly minted NFT token ID.
     */
    function mintReward(address to, uint256 level) external returns (uint256 tokenId);

    /**
     * @notice Checks whether a citizen has already claimed the reward for a given level.
     * @param user Citizen wallet address.
     * @param level Citizenship level to check.
     * @return claimed True if the reward has already been minted.
     */
    function hasClaimedLevel(address user, uint256 level) external view returns (bool claimed);

    /**
     * @notice Returns the citizenship level associated with a specific tokenId.
     * @param tokenId The NFT token ID.
     * @return level The citizenship level (1 to 13).
     */
    function tokenLevel(uint256 tokenId) external view returns (uint256 level);
}
