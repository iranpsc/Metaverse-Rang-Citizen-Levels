// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../interfaces/ILevelRewardNFT.sol";

/**
 * @title MockLevelRewardNFT
 * @notice Audit-ready ERC721 reward badge for the 13-level citizenship system.
 * @dev Supports RBAC, Pausable, ReentrancyGuard, optional Soulbound enforcement, and ERC-165.
 */
contract MockLevelRewardNFT is ERC721, AccessControl, Pausable, ReentrancyGuard, ILevelRewardNFT {
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_LEVEL = 13;

    uint256 private _nextTokenId = 1;
    string private _baseTokenURI;
    bool public soulboundEnabled;

    mapping(address => mapping(uint256 => bool)) private _claimedLevels;
    mapping(uint256 => uint256) private _tokenLevel;

    error ZeroAddress();
    error InvalidLevel(uint256 level);
    error AlreadyClaimed(address user, uint256 level);
    error SoulboundTransferProhibited();

    event BaseURIUpdated(string newBaseURI);
    event SoulboundStatusUpdated(bool enabled);
    event LevelRewardMinted(address indexed to, uint256 indexed level, uint256 indexed tokenId);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address admin_,
        bool soulboundEnabled_
    ) ERC721(name_, symbol_) {
        if (admin_ == address(0)) revert ZeroAddress();

        _baseTokenURI = baseURI_;
        soulboundEnabled = soulboundEnabled_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
    }

    /**
     * @inheritdoc ILevelRewardNFT
     */
    function mintReward(address to, uint256 level)
        external
        override
        onlyRole(MINTER_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId)
    {
        if (to == address(0)) revert ZeroAddress();
        if (level == 0 || level > MAX_LEVEL) revert InvalidLevel(level);
        if (_claimedLevels[to][level]) revert AlreadyClaimed(to, level);

        // Effects (CEI pattern)
        tokenId = _nextTokenId++;
        _claimedLevels[to][level] = true;
        _tokenLevel[tokenId] = level;

        emit LevelRewardMinted(to, level, tokenId);

        // Interaction
        _safeMint(to, tokenId);
    }

    /**
     * @inheritdoc ILevelRewardNFT
     */
    function hasClaimedLevel(address user, uint256 level) external view override returns (bool) {
        return _claimedLevels[user][level];
    }

    /**
     * @inheritdoc ILevelRewardNFT
     */
    function tokenLevel(uint256 tokenId) external view override returns (uint256) {
        _requireOwned(tokenId);
        return _tokenLevel[tokenId];
    }

    /**
     * @notice Updates the base metadata URI for level rewards.
     */
    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @notice Toggles whether level reward NFTs are soulbound (non-transferable).
     */
    function setSoulboundEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        soulboundEnabled = enabled;
        emit SoulboundStatusUpdated(enabled);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Returns level-based metadata URI (e.g., ipfs://.../<level>.json).
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 level = _tokenLevel[tokenId];
        return bytes(_baseTokenURI).length > 0
            ? string.concat(_baseTokenURI, level.toString(), ".json")
            : "";
    }

    /**
     * @dev Enforces Pausable and optional Soulbound restrictions on transfers (allows minting & burning).
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address from)
    {
        from = super._update(to, tokenId, auth);

        if (soulboundEnabled && from != address(0) && to != address(0)) {
            revert SoulboundTransferProhibited();
        }
    }

    /**
     * @dev ERC-165 interface support for ERC721, AccessControl, and ILevelRewardNFT.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(ILevelRewardNFT).interfaceId || super.supportsInterface(interfaceId);
    }
}
